-- tests/unit/groupframes_blizzard_mouse_suppression_test.lua
-- Run: lua tests/unit/groupframes_blizzard_mouse_suppression_test.lua
-- luacheck: globals CreateFrame InCombatLockdown C_Timer hooksecurefunc wipe UIParent PartyFrame CompactPartyFrame CompactRaidFrameContainer CompactUnitFrame_UpdateUnitEvents

local function newFrame(name)
    local frame = {
        name = name,
        parent = nil,
        alpha = 1,
        scale = 1,
        shown = true,
        mouseEnabled = true,
        mouseClickEnabled = true,
        mouseMotionEnabled = true,
        mouseWheelEnabled = true,
        eventsRegistered = true,
        registeredEvents = {},
        scripts = {},
        hooks = {},
    }

    function frame:SetAlpha(alpha)
        self.alpha = alpha
    end

    function frame:SetScale(scale)
        self.scale = scale
    end

    function frame:GetScale()
        return self.scale
    end

    function frame:SetParent(parent)
        self.parent = parent
    end

    function frame:GetParent()
        return self.parent
    end

    function frame:SetAllPoints()
        self.allPoints = true
    end

    function frame:Hide()
        self.shown = false
    end

    function frame:Show()
        self.shown = true
        local hook = self.hooks.Show
        if hook then hook(self) end
    end

    function frame:EnableMouse(enabled)
        self.mouseEnabled = enabled and true or false
    end

    function frame:EnableMouseWheel(enabled)
        self.mouseWheelEnabled = enabled and true or false
    end

    function frame:SetMouseClickEnabled(enabled)
        self.mouseClickEnabled = enabled and true or false
    end

    function frame:SetMouseMotionEnabled(enabled)
        self.mouseMotionEnabled = enabled and true or false
    end

    function frame:IsMouseEnabled()
        return self.mouseEnabled
    end

    function frame:IsMouseClickEnabled()
        return self.mouseClickEnabled
    end

    function frame:IsMouseMotionEnabled()
        return self.mouseMotionEnabled
    end

    function frame:IsMouseWheelEnabled()
        return self.mouseWheelEnabled
    end

    function frame:UnregisterAllEvents()
        self.eventsRegistered = false
    end

    function frame:RegisterEvent(event)
        self.registeredEvents[event] = true
    end

    function frame:UnregisterEvent(event)
        self.registeredEvents[event] = nil
    end

    function frame:SetScript(scriptName, handler)
        self.scripts[scriptName] = handler
    end

    return frame
end

local function loadModule()
    local db = {
        enabled = true,
    }
    local inCombat = false
    local createdFrames = {}

    UIParent = newFrame("UIParent")
    PartyFrame = newFrame("PartyFrame")
    PartyFrame:SetParent(UIParent)
    CompactRaidFrameContainer = newFrame("CompactRaidFrameContainer")
    CompactRaidFrameContainer:SetParent(UIParent)
    CompactPartyFrame = newFrame("CompactPartyFrame")
    CompactPartyFrame:SetParent(UIParent)
    CompactPartyFrame.title = newFrame("CompactPartyFrameTitle")
    CompactPartyFrame.title:SetParent(CompactPartyFrame)
    CompactPartyFrame.borderFrame = newFrame("CompactPartyFrameBorderFrame")
    CompactPartyFrame.borderFrame:SetParent(CompactPartyFrame)

    for i = 1, 5 do
        _G["CompactPartyFrameMember" .. i] = newFrame("CompactPartyFrameMember" .. i)
        _G["CompactPartyFrameMember" .. i]:SetParent(CompactPartyFrame)
    end
    for i = 1, 4 do
        _G["PartyMemberFrame" .. i] = newFrame("PartyMemberFrame" .. i)
        _G["PartyMemberFrame" .. i]:SetParent(PartyFrame)
    end
    for i = 1, 40 do
        _G["CompactRaidFrame" .. i] = newFrame("CompactRaidFrame" .. i)
        _G["CompactRaidFrame" .. i]:SetParent(CompactRaidFrameContainer)
    end
    for group = 1, 8 do
        _G["CompactRaidGroup" .. group] = newFrame("CompactRaidGroup" .. group)
        _G["CompactRaidGroup" .. group]:SetParent(CompactRaidFrameContainer)
        for member = 1, 5 do
            _G["CompactRaidGroup" .. group .. "Member" .. member] =
                newFrame("CompactRaidGroup" .. group .. "Member" .. member)
            _G["CompactRaidGroup" .. group .. "Member" .. member]:SetParent(_G["CompactRaidGroup" .. group])
        end
    end

    function InCombatLockdown()
        return inCombat
    end

    C_Timer = {
        After = function(_, callback)
            callback()
        end,
    }

    function CreateFrame(_, name, parent)
        local frame = newFrame(name or "eventFrame")
        frame:SetParent(parent or UIParent)
        createdFrames[#createdFrames + 1] = frame
        return frame
    end

    function hooksecurefunc(target, method, handler)
        if type(target) == "table" then
            target.hooks[method] = handler
        end
    end

    function wipe(tbl)
        for key in pairs(tbl) do
            tbl[key] = nil
        end
    end

    function CompactUnitFrame_UpdateUnitEvents(frame)
        frame.eventsRegistered = true
    end

    local ns = {
        Helpers = {
            CreateDBGetter = function()
                return function()
                    return db
                end
            end,
            CreateStateTable = function()
                return setmetatable({}, { __mode = "k" })
            end,
        },
    }

    assert(loadfile("QUI_GroupFrames/groupframes/groupframes_blizzard.lua"))("QUI", ns)
    return ns.QUI_GroupFrameBlizzard, function(value)
        inCombat = value and true or false
    end, createdFrames
end

local function assertMouseSuppressed(frame, label)
    assert(frame.alpha == 0, label .. " should be alpha-hidden")
    assert(frame.mouseEnabled == false, label .. " should disable general mouse handling")
    assert(frame.mouseClickEnabled == false, label .. " should stop mouse clicks")
    assert(frame.mouseMotionEnabled == false, label .. " should stop mouse motion tooltips")
    assert(frame.mouseWheelEnabled == false, label .. " should stop mouse wheel capture")
end

local function assertMouseRestored(frame, label)
    assert(frame.alpha == 1, label .. " should restore alpha")
    assert(frame.mouseEnabled == true, label .. " should restore general mouse handling")
    assert(frame.mouseClickEnabled == true, label .. " should restore mouse clicks")
    assert(frame.mouseMotionEnabled == true, label .. " should restore mouse motion")
    assert(frame.mouseWheelEnabled == true, label .. " should restore mouse wheel handling")
end

local function assertBanished(frame, originalParent, label)
    assertMouseSuppressed(frame, label)
    assert(frame:GetParent() ~= originalParent, label .. " should leave its original parent")
    assert(frame:GetParent() ~= UIParent, label .. " should not remain on UIParent")
    assert(frame:GetParent() and frame:GetParent().shown == false, label .. " should be under a hidden parent")
end

local groupframes, setCombat, createdFrames = loadModule()
local partyParent = PartyFrame:GetParent()
local compactPartyParent = CompactPartyFrame:GetParent()
local compactPartyMemberParent = _G.CompactPartyFrameMember1:GetParent()
local raidContainerParent = CompactRaidFrameContainer:GetParent()
local raidFrameParent = _G.CompactRaidFrame1:GetParent()
local raidGroupMemberParent = _G.CompactRaidGroup1Member1:GetParent()

groupframes:HideBlizzardFrames()

assertBanished(PartyFrame, partyParent, "PartyFrame")
assertBanished(CompactPartyFrame, compactPartyParent, "CompactPartyFrame")
assertBanished(_G.CompactPartyFrameMember1, compactPartyMemberParent, "CompactPartyFrameMember1")
assertBanished(CompactRaidFrameContainer, raidContainerParent, "CompactRaidFrameContainer")
assertBanished(_G.CompactRaidFrame1, raidFrameParent, "CompactRaidFrame1")
assertBanished(_G.CompactRaidGroup1Member1, raidGroupMemberParent, "CompactRaidGroup1Member1")

setCombat(true)
_G.CompactRaidFrame1.alpha = 1
_G.CompactRaidFrame1:SetParent(UIParent)
_G.CompactRaidFrame1:Show()
assertMouseSuppressed(_G.CompactRaidFrame1, "combat re-show CompactRaidFrame1")
assert(_G.CompactRaidFrame1:GetParent() == UIParent, "combat re-show should defer protected reparent")
setCombat(false)
for _, frame in ipairs(createdFrames) do
    if frame.registeredEvents.PLAYER_REGEN_ENABLED and frame.scripts.OnEvent then
        frame.scripts.OnEvent(frame, "PLAYER_REGEN_ENABLED")
    end
end
assertBanished(_G.CompactRaidFrame1, raidFrameParent, "post-combat CompactRaidFrame1")

groupframes:RestoreBlizzardFrames()

assertMouseRestored(PartyFrame, "PartyFrame")
assert(PartyFrame:GetParent() == partyParent, "PartyFrame should restore its original parent")
assertMouseRestored(CompactPartyFrame, "CompactPartyFrame")
assert(CompactPartyFrame:GetParent() == compactPartyParent, "CompactPartyFrame should restore its original parent")
assertMouseRestored(_G.CompactPartyFrameMember1, "CompactPartyFrameMember1")
assert(_G.CompactPartyFrameMember1:GetParent() == compactPartyMemberParent, "CompactPartyFrameMember1 should restore its original parent")
assertMouseRestored(CompactRaidFrameContainer, "CompactRaidFrameContainer")
assert(CompactRaidFrameContainer:GetParent() == raidContainerParent, "CompactRaidFrameContainer should restore its original parent")
assertMouseRestored(_G.CompactRaidFrame1, "CompactRaidFrame1")
assert(_G.CompactRaidFrame1:GetParent() == raidFrameParent, "CompactRaidFrame1 should restore its original parent")
assertMouseRestored(_G.CompactRaidGroup1Member1, "CompactRaidGroup1Member1")
assert(_G.CompactRaidGroup1Member1:GetParent() == raidGroupMemberParent, "CompactRaidGroup1Member1 should restore its original parent")

print("OK: groupframes_blizzard_mouse_suppression_test")
