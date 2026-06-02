-- tests/unit/main_dead_uimult_removed_test.lua
-- Run: lua tests/unit/main_dead_uimult_removed_test.lua
--
-- core/main.lua called self:UIMult() at two scale-application sites, each guarded
-- by `if self.UIMult then`. QUICore.UIMult was never defined anywhere (the real
-- scale work is done by RefreshAllFonts + UIKit.RefreshScaleBoundWidgets, called
-- right alongside), so both branches were permanently-dead no-ops. They were
-- removed. This guards that the dead reference stays gone.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local main = readAll("core/main.lua")
assert(not main:find("UIMult", 1, true),
    "dead UIMult no-op branches must be removed from core/main.lua")

print("main_dead_uimult_removed_test: OK")
