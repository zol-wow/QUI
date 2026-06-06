local _, ns = ...
-- ns proxies into the main QUI namespace (bootstrap.lua metatable bridge).
--
-- Drain the main addon's queued debug instrumentation. This file MUST stay
-- the last entry in debug.xml: setup closures bind
-- ns.MemAuditProfilerMeasure/Mark (defined by memaudit.lua) and push probes
-- into the ns._memprobes array that memaudit keeps alive after its own
-- load-time drain. Ordering is enforced by tests/unit/debug_addon_split_test.lua.
ns.DebugActivate()
