#!/usr/bin/env python3
import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

from graphify.build import build_from_json
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


def index_lua(ast_nodes):
    mixin_files = defaultdict(set)
    bare_fns = defaultdict(set)
    for n in ast_nodes:
        label = str(n.get("label") or "")
        src = n.get("source_file") or ""
        if not n.get("id") or not src.endswith(".lua"):
            continue
        own = MIXIN_OWNER.match(label)
        if own:
            mixin_files[own.group(1)].add(_make_id(_file_stem(Path(src))))
        fn = BARE_FN.match(label)
        if fn:
            bare_fns[fn.group(1)].add(n["id"])
    return mixin_files, bare_fns


def retail_first(path):
    parts = set(path.parts)
    return (1 if parts & set(FLAVOR_DIRS) else 0, path.as_posix())


def resolve(targets, known):
    hits = sorted(t for t in targets if t in known)
    if not hits:
        return [], "unresolved"
    return hits, "EXTRACTED" if len(hits) == 1 else "AMBIGUOUS"


class XmlPass:
    def __init__(self, root, lua_file_ids, mixin_files, bare_fns):
        self.root = root
        self.lua_file_ids = lua_file_ids
        self.mixin_files = mixin_files
        self.bare_fns = bare_fns
        self.nodes = {}
        self.edges = []
        self.seen_edges = set()
        self.stats = defaultdict(int)
        self.pending_inherits = []

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

    def add_edge(self, src, dst, relation, confidence, rel, line, context=None):
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
        self.edges.append(edge)
        self.stats[relation] += 1

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
                    self.stats["unresolved_mixin"] += 1
                    continue
                for target in hits:
                    self.add_edge(owner, target, "implements", conf, rel, line, context=mixin)
        handler = el.get("function")
        if handler:
            hits, conf = resolve(self.bare_fns.get(handler, ()), self.lua_file_ids | self.bare_fn_ids)
            if conf == "unresolved":
                self.stats["unresolved_handler"] += 1
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
                self.stats["unresolved_inherits"] += 1


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

    mixin_files, bare_fns = index_lua(ast["nodes"])
    known = {n["id"] for n in ast["nodes"]}
    xml_files = sorted((p for p in root.rglob("*.xml") if "graphify-out" not in p.parts),
                       key=retail_first)
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
