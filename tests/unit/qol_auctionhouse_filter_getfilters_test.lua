-- tests/unit/qol_auctionhouse_filter_getfilters_test.lua
-- Run: lua tests/unit/qol_auctionhouse_filter_getfilters_test.lua
--
-- AuctionHouseFilterButtonMixin does not store a professions-style
-- FilterButton.filters table; it exposes GetFilters(), backed by
-- g_auctionHouseFilters.filters. QUI must use that method when forcing the
-- CurrentExpansionOnly filter.

local function noop() end

local timers = {}
local createdFrames = {}

local function newFrame()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(scriptName, callback) self.scripts[scriptName] = callback end
    return frame
end

function CreateFrame()
    local frame = newFrame()
    createdFrames[#createdFrames + 1] = frame
    return frame
end

function hooksecurefunc() end

Enum = {
    AuctionHouseFilter = {
        CurrentExpansionOnly = "CurrentExpansionOnly",
    },
}

C_AddOns = {
    IsAddOnLoaded = function()
        return false
    end,
}

C_Timer = {
    After = function(_, callback)
        timers[#timers + 1] = callback
    end,
}

local settings = {
    auctionHouseExpansionFilter = true,
}

local updateCount = 0
local focusCount = 0
local filters = {}

local searchBar = {
    FilterButton = {
        GetFilters = function()
            return filters
        end,
    },
    SearchBox = {
        SetFocus = function()
            focusCount = focusCount + 1
        end,
    },
    HookScript = function(self, scriptName, callback)
        self.scripts = self.scripts or {}
        self.scripts[scriptName] = callback
    end,
    UpdateClearFiltersButton = function()
        updateCount = updateCount + 1
    end,
}

AuctionHouseFrame = {
    SearchBar = searchBar,
}

local ns = {
    L = setmetatable({}, { __index = function(_, key) return key end }),
    Helpers = {
        CreateDBGetter = function()
            return function()
                return settings
            end
        end,
    },
}

assert(loadfile("modules/qol/qol.lua"))("QUI", ns)

local qolFrame = assert(createdFrames[1], "qol.lua should create its event frame first")
local onEvent = assert(qolFrame.scripts.OnEvent, "qol.lua should register an OnEvent handler")

onEvent(qolFrame, "AUCTION_HOUSE_SHOW")

for i = 1, #timers do
    local ok, err = pcall(timers[i])
    assert(ok, "auction house filter callback should not error: " .. tostring(err))
end

assert(filters.CurrentExpansionOnly == true,
    "Auction House expansion filter should be written through FilterButton:GetFilters()")
assert(updateCount == 1, "Auction House clear-filter state should be refreshed after applying the filter")
assert(focusCount == 1, "Auction House search box should keep focus after applying the filter")

print("OK: qol_auctionhouse_filter_getfilters_test")
