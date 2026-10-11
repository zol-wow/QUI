import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.framexml_xml_graph import XmlPass, index_lua, widget_id
from tools import framexml_xml_graph


class LuaReferenceTests(unittest.TestCase):
    root = Path()
    nodes = []

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.nodes = []

    def lua(self, source, text, file_id):
        path = self.root / source
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        self.nodes.append({
            "id": file_id,
            "label": path.name,
            "source_file": source,
            "source_location": "L1",
        })

    def function(self, source, label, node_id):
        self.nodes.append({
            "id": node_id,
            "label": label,
            "source_file": source,
            "source_location": "L2",
        })

    def xml(self, text, scan_sources=True):
        mixins, handlers = index_lua(self.nodes, self.root) if scan_sources else index_lua(self.nodes)
        path = self.root / "Widgets.xml"
        path.write_text(text, encoding="utf-8")
        extraction = XmlPass(self.root, {node["id"] for node in self.nodes}, mixins, handlers)
        graph = extraction.run([path])
        return extraction, graph

    def test_mixin_uses_actual_file_node_id(self):
        self.lua("Shared/Widget.lua", "function WidgetMixin:OnLoad() end", "opaque-file-id")
        self.function("Shared/Widget.lua", "WidgetMixin:OnLoad()", "widget-onload")
        extraction, graph = self.xml('<Ui><Frame name="Widget" mixin="WidgetMixin"/></Ui>', False)
        edges = [edge for edge in graph["edges"] if edge["relation"] == "implements"]
        self.assertEqual([(edge["source"], edge["target"]) for edge in edges],
                         [(widget_id("Widget"), "opaque-file-id")])
        self.assertEqual(extraction.stats["unresolved_mixin"], 0)

    def test_assignment_only_and_inherited_mixins_resolve(self):
        self.lua("Shared/Mixins.lua", """
BaseMixin = {}
DerivedMixin = CreateFromMixins(BaseMixin)
AliasMixin = DerivedMixin
""", "mixin-source")
        extraction, graph = self.xml('<Ui><Frame name="Widget" mixin="BaseMixin, DerivedMixin, AliasMixin"/></Ui>')
        mixins, _ = index_lua(self.nodes, self.root)
        for name in ("BaseMixin", "DerivedMixin", "AliasMixin"):
            self.assertEqual(mixins[name], {"mixin-source"})
        self.assertEqual(extraction.stats["unresolved_mixin"], 0)
        self.assertEqual([edge["target"] for edge in graph["edges"] if edge["relation"] == "implements"],
                         ["mixin-source"])

    def test_handler_alias_chain_resolves_target_function(self):
        self.lua("Handlers.lua", """
function TargetHandler(self) end
FirstAlias = TargetHandler
SecondAlias = FirstAlias
""", "handler-file")
        self.function("Handlers.lua", "TargetHandler()", "target-function")
        extraction, graph = self.xml('<Ui><Frame name="Widget"><Scripts><OnLoad function="SecondAlias"/></Scripts></Frame></Ui>')
        calls = [edge for edge in graph["edges"] if edge["relation"] == "calls"]
        self.assertEqual([edge["target"] for edge in calls], ["target-function"])
        self.assertEqual(extraction.stats["unresolved_handler"], 0)

    def test_colliding_global_function_gets_distinct_target(self):
        self.lua("Input.lua", """
function InputScrollFrame:OnTabPressed() end
function InputScrollFrame_OnTabPressed(self) end
""", "input-file")
        self.function("Input.lua", "InputScrollFrame:OnTabPressed()", "colliding-method-id")
        extraction, graph = self.xml('<Ui><Frame name="Widget"><Scripts><OnTabPressed function="InputScrollFrame_OnTabPressed"/></Scripts></Frame></Ui>')
        calls = [edge for edge in graph["edges"] if edge["relation"] == "calls"]
        self.assertEqual(len(calls), 1)
        self.assertNotEqual(calls[0]["target"], "colliding-method-id")
        target = next(node for node in self.nodes if node["id"] == calls[0]["target"])
        self.assertEqual(target["label"], "InputScrollFrame_OnTabPressed()")
        self.assertEqual(target["source_file"], "Input.lua")
        self.assertEqual(extraction.stats["unresolved_handler"], 0)
        count = len(self.nodes)
        _, handlers = index_lua(self.nodes, self.root)
        self.assertEqual(len(self.nodes), count)
        self.assertEqual(handlers["InputScrollFrame_OnTabPressed"], {target["id"]})

    def test_comments_and_locals_do_not_create_globals(self):
        self.lua("Locals.lua", """
-- CommentMixin = {}
--[[ BlockMixin = {} ]]
local LocalMixin = {}
local ShadowedMixin
ShadowedMixin = {}
local function LocalHandler() end
local LocalAlias = LocalHandler
Container.MemberMixin = {}
""", "locals-file")
        mixins, handlers = index_lua(self.nodes, self.root)
        for name in ("CommentMixin", "BlockMixin", "LocalMixin", "ShadowedMixin", "MemberMixin"):
            self.assertFalse(mixins.get(name), name)
        for name in ("LocalHandler", "LocalAlias"):
            self.assertFalse(handlers.get(name), name)

    def test_missing_references_remain_unresolved(self):
        self.lua("Empty.lua", "", "empty-file")
        extraction, graph = self.xml('<Ui><Frame name="Widget" mixin="MissingMixin" inherits="MissingTemplate"><Scripts><OnLoad function="MissingHandler"/></Scripts></Frame></Ui>')
        for kind in ("mixin", "inherits", "handler"):
            self.assertEqual(extraction.stats["unresolved_" + kind], 1)
        self.assertFalse([edge for edge in graph["edges"] if edge["relation"] != "contains"])

    def test_root_mode_excludes_ast_indexed_local_handler(self):
        self.lua("LocalHandler.lua", "local function LocalHandler() end", "local-handler-file")
        self.function("LocalHandler.lua", "LocalHandler()", "local-handler-function")
        extraction, graph = self.xml('<Ui><Frame name="Widget"><Scripts><OnLoad function="LocalHandler"/></Scripts></Frame></Ui>')
        self.assertEqual(extraction.stats["unresolved_handler"], 1)
        self.assertFalse([edge for edge in graph["edges"] if edge["relation"] == "calls"])

    def test_explicit_global_export_resolves_local_handler(self):
        self.lua("ExportedHandler.lua", """
local function LocalHandler() end
_G.ExportedHandler = LocalHandler
""", "exported-handler-file")
        self.function("ExportedHandler.lua", "LocalHandler()", "local-handler-function")
        extraction, graph = self.xml('<Ui><Frame name="Widget"><Scripts><OnLoad function="ExportedHandler"/><OnShow function="LocalHandler"/></Scripts></Frame></Ui>')
        calls = [edge for edge in graph["edges"] if edge["relation"] == "calls"]
        self.assertEqual([edge["target"] for edge in calls], ["local-handler-function"])
        self.assertEqual(calls[0]["context"], "OnLoad")
        self.assertEqual(extraction.stats["unresolved_handler"], 1)

    def test_aliases_to_conditionally_shadowed_handler_do_not_resolve_global(self):
        self.lua("ScopedAliases.lua", """
function SharedHandler() end
if enabled then
    local SharedHandler = function() end
    VariableAlias = SharedHandler
end
if enabled then
    local function SharedHandler() end
    FunctionAlias = SharedHandler
end
""", "scoped-alias-file")
        self.function("ScopedAliases.lua", "SharedHandler()", "global-shared-handler")
        extraction, graph = self.xml('<Ui><Frame name="Widget"><Scripts><OnLoad function="VariableAlias"/><OnShow function="FunctionAlias"/></Scripts></Frame></Ui>')
        self.assertEqual(extraction.stats["unresolved_handler"], 2)
        self.assertFalse([edge for edge in graph["edges"] if edge["relation"] == "calls"])

    def test_alias_cycles_and_missing_alias_targets_remain_unresolved(self):
        self.lua("Aliases.lua", """
FirstAlias = SecondAlias
SecondAlias = FirstAlias
MissingAlias = AbsentHandler
""", "aliases-file")
        extraction, graph = self.xml('<Ui><Frame name="Widget"><Scripts><OnLoad function="FirstAlias"/><OnShow function="MissingAlias"/></Scripts></Frame></Ui>')
        self.assertEqual(extraction.stats["unresolved_handler"], 2)
        self.assertFalse([edge for edge in graph["edges"] if edge["relation"] == "calls"])

    def test_flavor_definitions_preserve_ambiguity(self):
        for directory, file_id in (("Shared", "shared-file"), ("Classic", "classic-file")):
            source = directory + "/Widget.lua"
            self.lua(source, "function WidgetMixin:OnLoad() end", file_id)
            self.function(source, "WidgetMixin:OnLoad()", directory + "-method")
        _, graph = self.xml('<Ui><Frame name="Widget" mixin="WidgetMixin"/></Ui>', False)
        edges = [edge for edge in graph["edges"] if edge["relation"] == "implements"]
        self.assertEqual({edge["target"] for edge in edges}, {"shared-file", "classic-file"})
        self.assertEqual({edge["confidence"] for edge in edges}, {"AMBIGUOUS"})

    def test_requested_native_global_uses_registered_api_documentation(self):
        source = "Interface/AddOns/Blizzard_APIDocumentationGenerated/GameCursorDocumentation.lua"
        text = """
local System = {
    Name = "GameCursor",
    Type = "System",
    Functions = {
        { Name = "DropCursorMoney", Type = "Function" },
        { Name = "UnrequestedFunction", Type = "Function" },
    },
};
APIDocumentation:AddDocumentationTable(System);
"""
        self.lua(source, text, "cursor-documentation-file")
        self.lua("Interface/AddOns/Blizzard_APIDocumentationGenerated/Blizzard_APIDocumentationGenerated.toc",
                 "## Interface: 120105\nGameCursorDocumentation.lua\n", "documentation-toc")
        initial_count = len(self.nodes)
        indexed = framexml_xml_graph.index_api_docs(self.nodes, self.root, {"DropCursorMoney"})
        self.assertEqual(set(indexed), {"DropCursorMoney"})
        self.assertEqual(len(indexed["DropCursorMoney"]), 1)
        self.assertEqual(len(self.nodes), initial_count + 1)
        target = next(node for node in self.nodes if node["id"] in indexed["DropCursorMoney"])
        self.assertEqual(target["source_file"], source)
        self.assertEqual(target["source_location"], "L6")
        self.assertEqual(target["_origin"], "api_doc")
        second_index = framexml_xml_graph.index_api_docs(self.nodes, self.root, {"DropCursorMoney"})
        self.assertEqual(second_index, indexed)
        self.assertEqual(len(self.nodes), initial_count + 1)

    def test_namespaced_native_api_never_resolves_bare_handler(self):
        source = "Interface/AddOns/Blizzard_APIDocumentationGenerated/SecureTransferDocumentation.lua"
        self.lua(source, """
local System = {
    Name = "SecureTransfer",
    Namespace = "C_SecureTransfer",
    Type = "System",
    Functions = { { Name = "AcceptTrade", Type = "Function" } },
};
APIDocumentation:AddDocumentationTable(System);
""", "secure-transfer-docs")
        indexed = framexml_xml_graph.index_api_docs(
            self.nodes, self.root, {"AcceptTrade", "C_SecureTransfer.AcceptTrade"})
        self.assertFalse(indexed.get("AcceptTrade"))
        self.assertEqual(len(indexed.get("C_SecureTransfer.AcceptTrade", ())), 1)

    def test_function_namespace_overrides_system_namespace(self):
        source = "Interface/AddOns/Blizzard_APIDocumentationGenerated/OverrideDocumentation.lua"
        self.lua(source, """
local System = {
    Name = "GameTrade",
    Namespace = "C_Default",
    Type = "System",
    Functions = { { Name = "ScopedHandler", Namespace = "C_Override", Type = "Function" } },
};
APIDocumentation:AddDocumentationTable(System);
""", "namespace-override-docs")
        indexed = framexml_xml_graph.index_api_docs(
            self.nodes, self.root, {"ScopedHandler", "C_Default.ScopedHandler", "C_Override.ScopedHandler"})
        self.assertFalse(indexed.get("ScopedHandler"))
        self.assertFalse(indexed.get("C_Default.ScopedHandler"))
        self.assertEqual(len(indexed.get("C_Override.ScopedHandler", ())), 1)

    def test_namespace_like_system_names_do_not_create_bare_globals(self):
        requested = {"ScopedHandler"}
        for name in ("CombatAPI", "CombatManager", "CombatMixin"):
            source = "Interface/AddOns/Blizzard_APIDocumentationGenerated/" + name + "Documentation.lua"
            self.lua(source, """
local System = {
    Name = "%s",
    Type = "System",
    Functions = { { Name = "ScopedHandler", Type = "Function" } },
};
APIDocumentation:AddDocumentationTable(System);
""" % name, name + "-docs")
            requested.add(name + ".ScopedHandler")
        indexed = framexml_xml_graph.index_api_docs(self.nodes, self.root, requested)
        self.assertFalse(indexed.get("ScopedHandler"))
        for name in ("CombatAPI", "CombatManager", "CombatMixin"):
            self.assertEqual(len(indexed.get(name + ".ScopedHandler", ())), 1)

    def test_unregistered_tables_widget_methods_and_events_are_not_api_globals(self):
        source = "Interface/AddOns/Blizzard_APIDocumentationGenerated/FilteredDocumentation.lua"
        self.lua(source, """
local Ghost = {
    Name = "GameGhost",
    Type = "System",
    Functions = { { Name = "UnregisteredHandler", Type = "Function" } },
};
local Widget = {
    Name = "SimpleFrame",
    Type = "ScriptObject",
    Functions = { { Name = "WidgetMethod", Type = "Function" } },
};
APIDocumentation:AddDocumentationTable(Widget);
local System = {
    Name = "GameEvents",
    Type = "System",
    Events = { { Name = "EventHandler", Type = "Event" } },
    Tables = { { Name = "StructHandler", Type = "Structure" } },
};
APIDocumentation:AddDocumentationTable(System);
""", "filtered-docs")
        initial_count = len(self.nodes)
        indexed = framexml_xml_graph.index_api_docs(
            self.nodes, self.root, {"UnregisteredHandler", "WidgetMethod", "EventHandler", "StructHandler"})
        self.assertFalse(any(indexed.values()))
        self.assertEqual(len(self.nodes), initial_count)

    def test_malformed_api_documentation_fails_explicitly(self):
        source = "Interface/AddOns/Blizzard_APIDocumentationGenerated/MalformedDocumentation.lua"
        self.lua(source, 'local System = { Name = "GameCursor", Functions = {', "malformed-docs")
        with self.assertRaisesRegex(ValueError, "Malformed API documentation: " + source):
            framexml_xml_graph.index_api_docs(self.nodes, self.root, {"DropCursorMoney"})

    def external_reference(self, kind, symbol):
        (self.root / "README.md").write_text("Pinned Mainline corpus\n", encoding="utf-8")
        commit = "b" * 40
        suffix = ".xml" if kind == "inherits" else ".lua"
        source = "graphify-out/reference-sources/classic/" + commit + "/Interface/" + symbol + suffix
        path = self.root / source
        path.parent.mkdir(parents=True, exist_ok=True)
        text = '<Ui><Frame name="%s" virtual="true"/></Ui>\n' % symbol if kind == "inherits" else symbol + " = {}\n"
        path.write_text(text, encoding="utf-8")
        return {
            "id": "external_" + kind + "_" + symbol,
            "label": symbol + "()" if kind == "handler" else symbol,
            "file_type": "code",
            "source_file": source,
            "source_location": "L1",
            "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "reference_kind": kind,
            "symbol": symbol,
            "client": "Classic",
            "version": "1.15.8",
            "source_commit": commit,
            "source_url": "https://github.com/Gethe/wow-ui-source/blob/" + commit + "/Interface/" + symbol + suffix,
            "runtime_verified": False,
            "_origin": "external_reference",
        }

    def external_manifest(self, references, **overrides):
        manifest = {
            "schema_version": 1,
            "corpus_readme_sha256": hashlib.sha256((self.root / "README.md").read_bytes()).hexdigest(),
            "references": references,
        }
        manifest.update(overrides)
        path = self.root / "graphify-out/xml-external-references.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(manifest), encoding="utf-8")

    def test_missing_external_manifest_returns_empty_mapping(self):
        self.assertEqual(framexml_xml_graph.load_external_refs(self.root), {})

    def test_external_manifest_loads_verified_reference(self):
        node = self.external_reference("handler", "ClassicHandler")
        self.external_manifest([node])
        self.assertEqual(framexml_xml_graph.load_external_refs(self.root), {("handler", "ClassicHandler"): node})

    def test_external_manifest_rejects_stale_or_invalid_evidence(self):
        node = self.external_reference("handler", "ClassicHandler")
        (self.root / "outside.lua").write_bytes((self.root / str(node["source_file"])).read_bytes())
        cases = (
            ({}, {"schema_version": 2}),
            ({}, {"corpus_readme_sha256": "0" * 64}),
            ({"reference_kind": "invalid"}, {}),
            ({"runtime_verified": True}, {}),
            ({"source_file": "outside.lua"}, {}),
            ({"source_sha256": "0" * 64}, {}),
            ({"source_location": "L0"}, {}),
            ({"source_location": "L999"}, {}),
            ({"source_location": "invalid"}, {}),
            ({"symbol": "UnverifiedName"}, {}),
        )
        for changes, overrides in cases:
            with self.subTest(changes=changes, overrides=overrides):
                self.external_manifest([dict(node, **changes)], **overrides)
                with self.assertRaises(ValueError):
                    framexml_xml_graph.load_external_refs(self.root)
        self.external_manifest([node, node])
        with self.assertRaises(ValueError):
            framexml_xml_graph.load_external_refs(self.root)

    def test_changed_corpus_readme_invalidates_external_manifest(self):
        node = self.external_reference("handler", "ClassicHandler")
        self.external_manifest([node])
        (self.root / "README.md").write_text("Changed corpus\n", encoding="utf-8")
        with self.assertRaises(ValueError):
            framexml_xml_graph.load_external_refs(self.root)

    def test_external_fallback_edges_keep_provenance_and_deduplicate(self):
        references = [self.external_reference(kind, symbol) for kind, symbol in (
            ("handler", "ClassicHandler"), ("mixin", "ClassicMixin"), ("inherits", "ClassicTemplate"))]
        self.external_manifest(references)
        extraction, graph = self.xml('<Ui><Frame name="Widget" mixin="ClassicMixin, ClassicMixin" inherits="ClassicTemplate"><Scripts><OnLoad function="ClassicHandler"/><OnShow function="ClassicHandler"/><OnHide function="UnknownNativeHandler"/></Scripts></Frame></Ui>')
        edges = [edge for edge in graph["edges"] if edge["relation"] == "references_external"]
        self.assertEqual(len(edges), 3)
        relations = {"handler": "calls", "mixin": "implements", "inherits": "inherits"}
        for node in references:
            edge = next(edge for edge in edges if edge["target"] == node["id"])
            self.assertEqual(edge["confidence"], "INFERRED")
            self.assertEqual(edge["reference_kind"], node["reference_kind"])
            self.assertEqual(edge["xml_relation"], relations[str(node["reference_kind"])])
            for key in ("client", "version", "source_commit", "source_url", "runtime_verified"):
                self.assertEqual(edge[key], node[key])
            self.assertIn(node["id"], {entry["id"] for entry in graph["nodes"]})
        for kind, occurrences in (("handler", 2), ("mixin", 2), ("inherits", 1)):
            self.assertEqual(extraction.stats["external_" + kind], occurrences)
        self.assertEqual(extraction.stats["deduped_references_external"], 2)
        self.assertEqual(extraction.stats["unresolved_handler"], 1)
        self.assertEqual(extraction.stats["unresolved_mixin"], 0)
        self.assertEqual(extraction.stats["unresolved_inherits"], 0)

    def test_local_definitions_win_over_explicit_external_mapping_in_any_file_order(self):
        self.lua("Local.lua", "LocalMixin = {}\nfunction LocalHandler() end", "local-file")
        self.function("Local.lua", "LocalHandler()", "local-handler")
        mixins, handlers = index_lua(self.nodes, self.root)
        references = {(kind, symbol): self.external_reference(kind, symbol) for kind, symbol in (
            ("handler", "LocalHandler"), ("mixin", "LocalMixin"), ("inherits", "LocalTemplate"))}
        instance = self.root / "Instance.xml"
        template = self.root / "Template.xml"
        instance.write_text('<Ui><Frame name="Widget" mixin="LocalMixin" inherits="LocalTemplate"><Scripts><OnLoad function="LocalHandler"/></Scripts></Frame></Ui>', encoding="utf-8")
        template.write_text('<Ui><Frame name="LocalTemplate" virtual="true"/></Ui>', encoding="utf-8")
        for paths in ([instance, template], [template, instance]):
            with self.subTest(order=[path.name for path in paths]):
                extraction = XmlPass(self.root, {node["id"] for node in self.nodes}, mixins, handlers,
                                     external_refs=references)
                graph = extraction.run(paths)
                self.assertFalse([edge for edge in graph["edges"] if edge["relation"] == "references_external"])
                targets = {edge["relation"]: edge["target"] for edge in graph["edges"] if edge["relation"] != "contains"}
                self.assertEqual(targets, {"calls": "local-handler", "implements": "local-file", "inherits": widget_id("LocalTemplate")})


if __name__ == "__main__":
    unittest.main()
