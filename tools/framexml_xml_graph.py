#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

from tree_sitter import Language, Parser
import tree_sitter_lua

from graphify.build import _is_file_node_label, build_from_json
from graphify.cluster import cluster
from graphify.export import to_json
from graphify.extract import _file_stem, _make_id, collect_files, extract

NS_TAG = re.compile(r"^\{[^}]*\}")
NAME_ATTR = re.compile(r'\bname="(?!\$)([^"]+)"')
MIXIN_OWNER = re.compile(r"^([A-Za-z_]\w*)[:.]")
BARE_FN = re.compile(r"^([A-Za-z_]\w*)\(\)$")
MIXIN_ATTRS = ("mixin", "secureMixin")
WIDGET_PREFIX = "xmlwidget_"
NON_WIDGET_TAGS = {"Binding", "Attribute", "KeyValue"}
FLAVOR_DIRS = ("Classic", "Vanilla", "TBC", "Wrath", "Cata", "Mists", "WoWLabs", "WoWHack")


def widget_id(name):
    return WIDGET_PREFIX + _make_id(name)


def name_lines(text):
    lines = {}
    for i, line in enumerate(text.splitlines(), 1):
        for m in NAME_ATTR.finditer(line):
            lines.setdefault(m.group(1), i)
    return lines


def lua_globals(path):
    source = path.read_bytes()
    tree = Parser(Language(tree_sitter_lua.language())).parse(source)

    def walk(node, locals_):
        locals_ = set(locals_)
        for child in node.named_children:
            if child.type == "variable_declaration":
                assignment = next((n for n in child.named_children if n.type == "assignment_statement"), None)
                variables = assignment.named_children[0] if assignment else next(
                    (n for n in child.named_children if n.type == "variable_list"), None)
                if variables:
                    locals_.update(n.text.decode() for n in variables.named_children)
            elif child.type == "function_declaration":
                name = child.child_by_field_name("name")
                if child.children[0].type == "local":
                    locals_.add(name.text.decode())
                elif name.type == "identifier" and name.text.decode() not in locals_:
                    yield name.text.decode(), "function", "", child.start_point[0] + 1
            elif child.type == "assignment_statement":
                variables, values = child.named_children
                for name, value in zip(variables.named_children, values.named_children):
                    if name.type == "dot_index_expression" and name.child_by_field_name("table").text == b"_G" and value.type == "identifier":
                        yield name.child_by_field_name("field").text.decode(), "export", value.text.decode(), child.start_point[0] + 1
                    if name.type == "identifier" and name.text.decode() not in locals_:
                        if value.type == "identifier" and value.text.decode() in locals_:
                            continue
                        yield name.text.decode(), value.type, value.text.decode(), child.start_point[0] + 1
            elif child.type not in ("function_definition", "comment"):
                yield from walk(child, locals_)

    yield from walk(tree.root_node, set())


def index_lua(ast_nodes, root=None):
    mixin_files = defaultdict(set)
    bare_fns = defaultdict(set)
    files = defaultdict(set)
    functions = defaultdict(set)
    for n in ast_nodes:
        src = n.get("source_file") or ""
        if src.endswith(".lua") and _is_file_node_label(n.get("label"), src):
            files[src].add(n["id"])
    for n in ast_nodes:
        label = str(n.get("label") or "")
        src = n.get("source_file") or ""
        if not n.get("id") or not src.endswith(".lua"):
            continue
        own = MIXIN_OWNER.match(label)
        if own:
            mixin_files[own.group(1)].update(files[src])
        fn = BARE_FN.match(label)
        if fn:
            bare_fns[fn.group(1)].add(n["id"])
            functions[src, fn.group(1)].add(n["id"])
    if root is not None:
        bare_fns.clear()
        aliases = []
        for src, file_ids in files.items():
            for name, kind, value, line in lua_globals(root / src):
                if kind in ("function", "function_definition"):
                    if not functions[src, name]:
                        nid = "lua_global_" + _make_id(src, name)
                        ast_nodes.append({
                            "id": nid, "label": name + "()", "file_type": "code",
                            "source_file": src, "source_location": f"L{line}", "_origin": "ast",
                        })
                        functions[src, name].add(nid)
                    bare_fns[name].update(functions[src, name])
                elif kind == "export":
                    bare_fns[name].update(functions[src, value])
                elif kind == "table_constructor" or (kind == "function_call" and
                        re.match(r"(?:CreateFromMixins\s*\(|[A-Za-z_]\w*[:.]CreateSubPin\s*\()", value)):
                    mixin_files[name].update(file_ids)
                elif kind == "identifier":
                    aliases.append((name, value))
        for _ in range(len(aliases)):
            changed = False
            for name, target in aliases:
                for index in (mixin_files, bare_fns):
                    additions = index.get(target, set()) - index[name]
                    if additions:
                        index[name].update(additions)
                        changed = True
            if not changed:
                break
    return mixin_files, bare_fns


def index_api_docs(ast_nodes, root, names):
    functions = defaultdict(set)
    known = {n["id"] for n in ast_nodes}

    def fields(node):
        if node is None or node.type != "table_constructor":
            return {}
        return {field.child_by_field_name("name").text.decode(): field.child_by_field_name("value")
                for field in node.named_children if field.type == "field" and field.child_by_field_name("name") is not None}

    def string(node):
        content = node.child_by_field_name("content") if node is not None and node.type == "string" else None
        return content.text.decode() if content is not None else None

    sources = {n["source_file"] for n in ast_nodes if n.get("source_file", "").endswith(".lua") and
               Path(n["source_file"]).parent.name == "Blizzard_APIDocumentationGenerated" and
               _is_file_node_label(n.get("label"), n["source_file"])}
    for src in sorted(sources):
        tree = Parser(Language(tree_sitter_lua.language())).parse((root / src).read_bytes())
        if tree.root_node.has_error:
            raise ValueError(f"Malformed API documentation: {src}")
        tables = {}
        registered = set()
        for node in tree.root_node.named_children:
            if node.type == "variable_declaration":
                assignment = next((n for n in node.named_children if n.type == "assignment_statement"), None)
                if assignment:
                    variables, values = assignment.named_children
                    tables.update((name.text.decode(), value) for name, value in zip(variables.named_children, values.named_children))
            elif node.type == "function_call" and node.child_by_field_name("name").text == b"APIDocumentation:AddDocumentationTable":
                registered.update(n.text.decode() for n in node.child_by_field_name("arguments").named_children)
        for name in registered:
            system = fields(tables.get(name))
            if string(system.get("Type")) != "System":
                continue
            namespace = string(system.get("Namespace"))
            system_name = string(system.get("Name")) or ""
            if namespace is None and system_name.endswith(("API", "Manager", "Mixin")):
                namespace = system_name
            function_table = system.get("Functions")
            if function_table is None:
                continue
            for field in function_table.named_children:
                fn = fields(field.child_by_field_name("value"))
                fn_name = string(fn.get("Name"))
                if not fn_name or string(fn.get("Type")) != "Function":
                    continue
                fn_namespace = string(fn.get("Namespace"))
                if fn_namespace is None:
                    fn_namespace = namespace
                label = f"{fn_namespace}.{fn_name}" if fn_namespace else fn_name
                if label not in names:
                    continue
                nid = "api_doc_" + _make_id(src, label)
                if nid not in known:
                    ast_nodes.append({
                        "id": nid, "label": label + "()", "file_type": "code", "_origin": "api_doc",
                        "source_file": src, "source_location": f"L{fn['Name'].start_point[0] + 1}",
                    })
                    known.add(nid)
                functions[label].add(nid)
    return functions


def retail_first(path):
    parts = set(path.parts)
    return (1 if parts & set(FLAVOR_DIRS) else 0, path.as_posix())


def resolve(targets, known):
    hits = sorted(t for t in targets if t in known)
    if not hits:
        return [], "unresolved"
    return hits, "EXTRACTED" if len(hits) == 1 else "AMBIGUOUS"


def load_external_refs(root):
    manifest = root / "graphify-out" / "xml-external-references.json"
    if not manifest.exists():
        return {}
    data = json.loads(manifest.read_text(encoding="utf-8"))
    if (data.get("schema_version") != 1 or
            data.get("corpus_readme_sha256") != hashlib.sha256((root / "README.md").read_bytes()).hexdigest()):
        raise ValueError("External XML reference manifest needs revalidation for this corpus")
    cache = (root / "graphify-out" / "reference-sources").resolve()
    references = {}
    source_bytes = {}
    for node in data["references"]:
        key = (node["reference_kind"], node["symbol"])
        path = (root / node["source_file"]).resolve()
        if (key[0] not in {"handler", "mixin", "inherits"} or
                node.get("runtime_verified") is not False or not path.is_relative_to(cache)):
            raise ValueError(f"Invalid external XML reference: {key}")
        if path not in source_bytes:
            source_bytes[path] = path.read_bytes()
        raw = source_bytes[path]
        location = re.fullmatch(r"L([1-9]\d*)", node["source_location"])
        lines = raw.decode("utf-8").splitlines()
        if (hashlib.sha256(raw).hexdigest() != node["source_sha256"] or not location or
                int(location[1]) > len(lines) or node["symbol"] not in lines[int(location[1]) - 1]):
            raise ValueError(f"Stale external XML reference: {key}")
        if key in references:
            raise ValueError(f"Duplicate external XML reference: {key}")
        references[key] = node
    return references


class XmlPass:
    def __init__(self, root, lua_file_ids, mixin_files, bare_fns, external_refs=None):
        self.root = root
        self.lua_file_ids = lua_file_ids
        self.mixin_files = mixin_files
        self.bare_fns = bare_fns
        self.nodes = {}
        self.edges = []
        self.seen_edges = set()
        self.stats = defaultdict(int)
        self.pending_inherits = []
        self.external_refs = load_external_refs(root) if external_refs is None else external_refs

    def run(self, paths):
        for path in paths:
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
                tree = ET.fromstring(text)
            except (OSError, ET.ParseError):
                self.stats["unparsable_files"] += 1
                continue
            rel = path.relative_to(self.root).as_posix()
            file_node = _make_id(_file_stem(Path(rel))) + "_xml"
            self.nodes.setdefault(file_node, {
                "id": file_node,
                "label": path.name,
                "file_type": "code",
                "source_file": rel,
                "source_location": "L1",
                "_origin": "xml",
            })
            self.stats["files"] += 1
            self.walk(tree, rel, file_node, 1, name_lines(text))
        self.link_inherits()
        return {"nodes": list(self.nodes.values()), "edges": self.edges}

    def add_edge(self, src, dst, relation, confidence, rel, line, context=None, **metadata):
        if (src, dst, relation) in self.seen_edges:
            self.stats["deduped_" + relation] += 1
            return
        self.seen_edges.add((src, dst, relation))
        edge = {
            "source": src,
            "target": dst,
            "relation": relation,
            "confidence": confidence,
            "source_file": rel,
            "source_location": f"L{line}",
            "_origin": "xml",
        }
        if context:
            edge["context"] = context
        edge.update(metadata)
        self.edges.append(edge)
        self.stats[relation] += 1

    def link_external(self, kind, symbol, owner, rel, line, relation):
        node = self.external_refs.get((kind, symbol))
        if node is None:
            self.stats["unresolved_" + kind] += 1
            return
        self.nodes[node["id"]] = node
        self.stats["external_" + kind] += 1
        self.add_edge(owner, node["id"], "references_external", "INFERRED", rel, line,
                      context=symbol, reference_kind=kind, xml_relation=relation,
                      runtime_verified=False,
                      **{key: node[key] for key in ("client", "version", "source_commit", "source_url")})

    def walk(self, el, rel, owner, owner_line, lines):
        for child in el:
            tag = NS_TAG.sub("", child.tag)
            name = child.get("name")
            next_owner, next_line = owner, owner_line
            if name and not name.startswith("$") and tag not in NON_WIDGET_TAGS:
                nid = widget_id(name)
                line = lines.get(name, owner_line)
                if nid in self.nodes:
                    flavored = set(Path(rel).parts) & set(FLAVOR_DIRS)
                    self.stats["shadowed_flavor" if flavored else "shadowed_retail"] += 1
                else:
                    self.nodes[nid] = {
                        "id": nid,
                        "label": name,
                        "file_type": "code",
                        "source_file": rel,
                        "source_location": f"L{line}",
                        "_origin": "xml",
                        "xml_tag": tag,
                        "virtual": child.get("virtual") == "true",
                    }
                    self.add_edge(owner, nid, "contains", "EXTRACTED", rel, line, context=tag)
                next_owner, next_line = nid, line
            self.attrs(child, tag, rel, next_owner, next_line)
            self.walk(child, rel, next_owner, next_line, lines)

    def attrs(self, el, tag, rel, owner, line):
        for raw in el.get("inherits", "").split(","):
            template = raw.strip()
            if template:
                self.pending_inherits.append((owner, template, rel, line, tag))
        for attr in MIXIN_ATTRS:
            for raw in el.get(attr, "").split(","):
                mixin = raw.strip()
                if not mixin:
                    continue
                hits, conf = resolve(self.mixin_files.get(mixin, ()), self.lua_file_ids)
                if conf == "unresolved":
                    self.link_external("mixin", mixin, owner, rel, line, "implements")
                    continue
                for target in hits:
                    self.add_edge(owner, target, "implements", conf, rel, line, context=mixin)
        handler = el.get("function")
        if handler:
            hits, conf = resolve(self.bare_fns.get(handler, ()), self.lua_file_ids | self.bare_fn_ids)
            if conf == "unresolved":
                self.link_external("handler", handler, owner, rel, line, "calls")
            for target in hits:
                self.add_edge(owner, target, "calls", conf, rel, line, context=tag)

    @property
    def bare_fn_ids(self):
        if not hasattr(self, "_bare_fn_ids"):
            self._bare_fn_ids = {i for ids in self.bare_fns.values() for i in ids}
        return self._bare_fn_ids

    def link_inherits(self):
        for owner, template, rel, line, tag in self.pending_inherits:
            target = widget_id(template)
            if target in self.nodes:
                self.add_edge(owner, target, "inherits", "EXTRACTED", rel, line, context=tag)
            else:
                self.link_external("inherits", template, owner, rel, line, "inherits")


def main():
    repo = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(
        description="Rebuild the vendored FrameXML knowledge graph: graphify AST over "
                    "Lua/TOC plus an XML layer (named widgets, inherits, mixin->Lua, "
                    "handler->Lua). Deterministic, no LLM and no API key. Writes "
                    "tests/framexml/graphify-out/graph.json, which the graphify-mcp "
                    "container serves as project_path=/refs/framexml.")
    ap.add_argument("path", nargs="?", default=str(repo / "tests" / "framexml"))
    ap.add_argument("--no-cluster", action="store_true",
                    help="skip Louvain clustering (get_community stays unavailable)")
    ap.add_argument("--force", action="store_true",
                    help="write graph.json even if the rebuild has fewer nodes")
    ap.add_argument("--xml-only", metavar="OUT",
                    help="write just the XML extraction to OUT and exit, no graph build")
    args = ap.parse_args()

    root = Path(args.path).resolve()
    if not root.is_dir():
        sys.exit(f"not a directory: {root}")

    code = collect_files(root, root=root)
    print(f"AST: {len(code)} code files")
    ast = extract(code, cache_root=root, root=root)
    print(f"AST: {len(ast['nodes'])} nodes, {len(ast['edges'])} edges")

    file_nodes = {n["source_file"]: n["id"] for n in ast["nodes"]
                  if _is_file_node_label(n.get("label"), n.get("source_file"))}
    ast_count = len(ast["nodes"])
    mixin_files, bare_fns = index_lua(ast["nodes"], root)
    xml_files = sorted((p for p in root.rglob("*.xml") if "graphify-out" not in p.parts),
                       key=retail_first)
    handlers = set()
    for path in xml_files:
        try:
            tree = ET.parse(path)
        except (OSError, ET.ParseError):
            continue
        handlers.update(el.get("function") for el in tree.iter() if el.get("function"))
    for name, targets in index_api_docs(ast["nodes"], root, handlers).items():
        bare_fns[name].update(targets)
    for node in ast["nodes"][ast_count:]:
        ast["edges"].append({
            "source": file_nodes[node["source_file"]], "target": node["id"],
            "relation": "contains", "confidence": "EXTRACTED", "_origin": "ast",
            "source_file": node["source_file"], "source_location": node["source_location"],
        })
    known = {n["id"] for n in ast["nodes"]}
    xp = XmlPass(root, known, mixin_files, bare_fns)
    xml = xp.run(xml_files)
    print(f"XML: {len(xml['nodes'])} nodes, {len(xml['edges'])} edges "
          f"from {xp.stats['files']}/{len(xml_files)} files")
    for key in sorted(xp.stats):
        if key != "files":
            print(f"  {key}: {xp.stats[key]}")

    if args.xml_only:
        Path(args.xml_only).write_text(json.dumps(xml, indent=2), encoding="utf-8")
        print(f"wrote {args.xml_only}")
        return

    seen = set()
    nodes = []
    for n in ast["nodes"] + xml["nodes"]:
        if n["id"] not in seen:
            seen.add(n["id"])
            nodes.append(n)
    merged = {
        "nodes": nodes,
        "edges": ast["edges"] + xml["edges"],
        "hyperedges": [],
        "input_tokens": ast.get("input_tokens", 0),
        "output_tokens": ast.get("output_tokens", 0),
    }

    G = build_from_json(merged, root=root)
    if G.number_of_nodes() == 0:
        sys.exit("ERROR: graph is empty")
    communities = {} if args.no_cluster else cluster(G)
    out = root / "graphify-out" / "graph.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    if not to_json(G, communities, str(out), force=args.force):
        sys.exit("ERROR: refused to shrink graph.json (#479); re-run with --force if intended")
    print(f"Graph: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges, "
          f"{len(communities)} communities -> {out}")


if __name__ == "__main__":
    main()
