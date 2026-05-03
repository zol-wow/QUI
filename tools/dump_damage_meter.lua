---------------------------------------------------------------------------
-- Damage Meter discovery helper.
--
-- Usage (in-game, with the meter ENABLED via Esc -> Options -> Gameplay
-- Enhancements -> Damage Meter, and at least one extra window spawned):
--
--   /script <paste body between BEGIN/END as one /script command>
--
-- Or save the body as a macro and run it. Then copy the chat output and
-- paste it back to the agent.
--
-- After the first pass, click a meter row to open the breakdown popup,
-- then re-run with `local primary = _G.DamageMeterBreakdownFrame`
-- (or whatever the breakdown popup global turned out to be from pass 1).
---------------------------------------------------------------------------

-- BEGIN -----------------------------------------------------------------
local out = {}
local function p(line) out[#out+1] = line end
local function header(s) p("|cff34d399"..s.."|r") end
local function fname(f)
    if not f then return "<nil>" end
    if f.GetName and f:GetName() then return f:GetName() end
    return "<anonymous "..(f.GetObjectType and f:GetObjectType() or "?")..">"
end

local candidates = {
    "DamageMeterFrame", "DamageMeterContainerFrame", "DamageMeterContainer",
    "DamageMeterPrimaryWindow", "DamageMeterMainWindow", "DamageMeterWindow",
    "DamageMeterBreakdownFrame", "DamageMeterBreakdownPopup", "DamageMeterBreakdown",
    "DamageMeterDropdown", "DamageMeterSegmentDropdown", "DamageMeterSegmentSelector",
    "DamageMeterRowTemplate", "DamageMeterBarTemplate",
}
header("== Globals scan ==")
for _, name in ipairs(candidates) do
    local v = _G[name]
    if v then
        if type(v) == "table" and v.IsObjectType then
            p(("  %s = %s [%s]"):format(name, fname(v), v:GetObjectType()))
        else
            p(("  %s = %s"):format(name, type(v)))
        end
    end
end

header("== Children of DamageMeterFrame (if present) ==")
local primary = _G.DamageMeterFrame
if primary and primary.IsObjectType then
    for k, v in pairs(primary) do
        if type(v) == "table" and v.IsObjectType then
            p(("  primary.%s = %s [%s]"):format(k, fname(v), v:GetObjectType()))
        end
    end
    p(("  GetObjectType=%s GetFrameLevel=%s GetParent=%s"):format(
        primary:GetObjectType(), tostring(primary:GetFrameLevel()), fname(primary:GetParent())))
    p(("  IsProtected=%s IsForbidden=%s"):format(
        tostring(primary:IsProtected()), tostring(primary:IsForbidden())))
    for k in pairs(primary) do
        if type(k) == "string" and k:find("^_onstate%-") then
            p("  STATE-DRIVER: "..k)
        end
    end
end

header("== Methods on DamageMeterFrame (likely hook targets) ==")
if primary then
    local mt = getmetatable(primary)
    local seen = {}
    local function dumpMethods(t)
        if not t then return end
        for k, v in pairs(t) do
            if type(v) == "function" and not seen[k] then
                seen[k] = true
                if type(k) == "string" and k:find("^[A-Z]") and (
                    k:find("Show") or k:find("Hide") or k:find("Update") or
                    k:find("Refresh") or k:find("Add") or k:find("Spawn") or
                    k:find("Acquire") or k:find("Create") or k:find("New") or
                    k:find("Open")) then
                    p("  "..k)
                end
            end
        end
    end
    dumpMethods(primary)
    if mt and mt.__index then dumpMethods(mt.__index) end
end

header("== AddOns matching ^Blizzard_DamageMeter ==")
if C_AddOns and C_AddOns.GetNumAddOns then
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if name and name:find("^Blizzard_DamageMeter") then
            p(("  %s loaded=%s"):format(name, tostring(C_AddOns.IsAddOnLoaded(name))))
        end
    end
end

header("== EditModeManagerFrame methods (sanity) ==")
if EditModeManagerFrame then
    p(("  EnterEditMode=%s ExitEditMode=%s IsEditModeActive=%s"):format(
        type(EditModeManagerFrame.EnterEditMode),
        type(EditModeManagerFrame.ExitEditMode),
        type(EditModeManagerFrame.IsEditModeActive)))
end

print(table.concat(out, "\n"))
-- END -------------------------------------------------------------------
