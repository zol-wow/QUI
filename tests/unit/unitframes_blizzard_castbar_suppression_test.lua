-- tests/unit/unitframes_blizzard_castbar_suppression_test.lua
-- Run: lua tests/unit/unitframes_blizzard_castbar_suppression_test.lua
-- luacheck: globals CreateFrame InCombatLockdown C_Timer UIParent PlayerCastingBarFrame PetCastingBarFrame PetFrame TargetFrame FocusFrame PlayerFrame TargetFrameToT hooksecurefunc

local function newCastbar()
    local icon = {
        alpha = 1,
        shown = true,
    }

    function icon:SetAlpha(alpha)
        self.alpha = alpha
    end

    function icon:Hide()
        self.shown = false
    end

    local castbar = {
        alpha = 1,
        scale = 1,
        shown = true,
        unit = "player",
        point = nil,
        eventsRegistered = true,
        Icon = icon,
    }

    function castbar:SetAlpha(alpha)
        self.alpha = alpha
    end

    function castbar:SetScale(scale)
        self.scale = scale
    end

    function castbar:SetPoint(...)
        self.point = {...}
    end

    function castbar:UnregisterAllEvents()
        self.eventsRegistered = false
    end

    function castbar:SetUnit(unit)
        self.unit = unit
    end

    function castbar:Hide()
        self.shown = false
    end

    function castbar:IsShown()
        return self.shown
    end

    return castbar
end

local function loadModule()
    local db = {
        enabled = true,
        player = {
            enabled = true,
            castbar = {
                enabled = true,
            },
        },
    }

    local createdFrames = {}

    UIParent = {}
    PetCastingBarFrame = nil
    PetFrame = nil
    TargetFrame = nil
    FocusFrame = nil
    PlayerFrame = nil
    TargetFrameToT = nil

    function InCombatLockdown()
        return false
    end

    C_Timer = {
        After = function(_, callback)
            callback()
        end,
    }

    function CreateFrame()
        local frame = {
            scripts = {},
        }

        function frame:SetScript(scriptName, handler)
            self.scripts[scriptName] = handler
        end

        function frame:RegisterEvent(event)
            self.event = event
        end

        function frame:SetAllPoints()
            self.allPoints = true
        end

        function frame:Hide()
            self.hidden = true
        end

        createdFrames[#createdFrames + 1] = frame
        return frame
    end

    function hooksecurefunc() end

    local ns = {
        QUI_UnitFrames = {},
        Helpers = {
            CreateDBGetter = function()
                return function()
                    return db
                end
            end,
            CreateStateTable = function()
                return {}
            end,
            DeferredHideOnShow = function() end,
            IsEditModeActive = function()
                return false
            end,
        },
    }

    assert(loadfile("QUI_UnitFrames/unitframes/unitframe_blizzard.lua"))("QUI", ns)
    return ns.QUI_UnitFrames, createdFrames
end

local function assertSuppressed(castbar, messagePrefix)
    assert(castbar.alpha == 0, messagePrefix .. " should set the default castbar alpha to zero")
    assert(castbar.scale == 0.0001, messagePrefix .. " should shrink the default castbar")
    assert(castbar.shown == false, messagePrefix .. " should hide the default castbar")
    assert(castbar.unit == nil, messagePrefix .. " should detach the default castbar unit")
    assert(castbar.eventsRegistered == false, messagePrefix .. " should unregister the default castbar events")
    assert(castbar.Icon.alpha == 0, messagePrefix .. " should set the default castbar icon alpha to zero")
    assert(castbar.Icon.shown == false, messagePrefix .. " should hide the default castbar icon")
end

do
    local unitframes = loadModule()
    PlayerCastingBarFrame = newCastbar()

    unitframes:HideBlizzardCastbars()

    assertSuppressed(PlayerCastingBarFrame, "initial suppression")
end

do
    local unitframes, createdFrames = loadModule()
    PlayerCastingBarFrame = nil

    unitframes:HideBlizzardCastbars()
    assert(#createdFrames == 1, "watcher should be installed even before the Blizzard castbar exists")
    assert(createdFrames[1].scripts.OnUpdate, "watcher should install an OnUpdate handler")

    PlayerCastingBarFrame = newCastbar()
    createdFrames[1].scripts.OnUpdate(createdFrames[1], 0.1)

    assertSuppressed(PlayerCastingBarFrame, "watcher suppression")
end

print("OK: unitframes_blizzard_castbar_suppression_test")
