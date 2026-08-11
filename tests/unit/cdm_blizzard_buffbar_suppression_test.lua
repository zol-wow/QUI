-- tests/unit/cdm_blizzard_buffbar_suppression_test.lua
-- Run: lua tests/unit/cdm_blizzard_buffbar_suppression_test.lua
--
-- Reference-style suppression for Blizzard's BuffBarCooldownViewer: keep the
-- viewer alive as the aura data source, alpha-hide it, and park its visual shell
-- offscreen out of combat while QUI mirrors its children.

local ns = {}
local chunk = assert(loadfile("QUI_CDM/cdm/cdm_blizzard_buffbar_suppression.lua"))
local unpackValue = table.unpack or unpack

local function MakeFrame()
    local f = {
        alpha = 1,
        points = {
            { "CENTER", "Parent", "CENTER", 12, -8 },
        },
        pointWrites = 0,
        clearCalls = 0,
        mouseWrites = {},
    }
    function f:GetNumPoints() return #self.points end
    function f:GetPoint(i) return unpackValue(self.points[i]) end
    function f:SetAlpha(a) self.alpha = a end
    function f:ClearAllPoints() self.clearCalls = self.clearCalls + 1; self.points = {} end
    function f:SetPoint(...) self.pointWrites = self.pointWrites + 1; self.points[#self.points + 1] = { ... } end
    function f:EnableMouse(value) self.mouseWrites.EnableMouse = value end
    function f:EnableMouseMotion(value) self.mouseWrites.EnableMouseMotion = value end
    return f
end

local inCombat = false
_G.InCombatLockdown = function() return inCombat end
_G.UIParent = { name = "UIParent" }

chunk("QUI", ns)
local Suppressor = assert(ns.CDMBlizzardBuffBarSuppressor, "suppression module exported")

do
    local frame = MakeFrame()
    _G.BuffBarCooldownViewer = frame
    _G.C_CooldownViewer = { IsCooldownViewerAvailable = function() return true end }

    assert(Suppressor:Suppress() == true, "suppression succeeds when the native frame exists")
    assert(frame.alpha == 0, "suppression hides via SetAlpha(0)")
    assert(frame.clearCalls == 1, "suppression clears native viewer points out of combat")
    assert(frame.pointWrites == 1, "suppression moves BuffBarCooldownViewer offscreen out of combat")
    assert(frame.points[1][1] == "TOPLEFT" and frame.points[1][2] == _G.UIParent
        and frame.points[1][3] == "BOTTOMLEFT" and frame.points[1][5] <= -10000,
        "suppression parks BuffBarCooldownViewer below UIParent")
    assert(frame.mouseWrites.EnableMouse == false, "suppression disables mouse")
    assert(frame.mouseWrites.EnableMouseMotion == false, "suppression disables mouse motion")

    Suppressor:Restore()
    assert(frame.alpha == 1, "restore makes the native bar visible again")
    assert(frame.points[1][1] == "CENTER" and frame.points[1][4] == 12 and frame.points[1][5] == -8,
        "restore returns the original anchor")
end

do
    local frame = MakeFrame()
    _G.BuffBarCooldownViewer = frame
    _G.C_CooldownViewer = { IsCooldownViewerAvailable = function() return true end }
    inCombat = true

    assert(Suppressor:Suppress() == true, "combat suppression still succeeds")
    assert(frame.alpha == 0, "combat suppression may still alpha-hide")
    assert(frame.clearCalls == 0, "combat suppression must not clear protected points")
    assert(frame.pointWrites == 0, "combat suppression must not move the native viewer")

    inCombat = false
    Suppressor:FlushPendingRestore()
    assert(frame.clearCalls == 1 and frame.pointWrites == 1,
        "combat suppression parks the native viewer when combat ends")
end

do
    local frame = MakeFrame()
    _G.BuffBarCooldownViewer = frame
    _G.C_CooldownViewer = { IsCooldownViewerAvailable = function() return true end }
    inCombat = false

    assert(Suppressor:Apply({ enabled = false }) == false,
        "disabled tracked-bar settings restore instead of suppress")
    assert(frame.alpha == 1, "disabled tracked-bar settings leave Blizzard visible")
end

do
    local frame = MakeFrame()
    _G.BuffBarCooldownViewer = frame
    _G.C_CooldownViewer = { IsCooldownViewerAvailable = function() return false end }

    assert(Suppressor:Suppress() == false,
        "suppression waits until CooldownViewer data is available")
    assert(frame.alpha == 1, "not-ready suppression must not touch native alpha")
    assert(frame.clearCalls == 0 and frame.pointWrites == 0,
        "not-ready suppression must not move the native viewer")
end

print("OK: cdm_blizzard_buffbar_suppression_test")
