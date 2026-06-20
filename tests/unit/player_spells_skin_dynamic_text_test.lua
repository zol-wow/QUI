-- tests/unit/player_spells_skin_dynamic_text_test.lua
-- Run: lua tests/unit/player_spells_skin_dynamic_text_test.lua
--
-- Spellbook content is paged and pooled. Text styling must be applied after
-- Blizzard displays/acquires the visible spell rows, not only once on addon load.

-- luacheck: globals _G C_Timer hooksecurefunc PagedContentFrameBaseMixin

C_Timer = { After = function(_, fn) fn() end }
function hooksecurefunc() end

PagedContentFrameBaseMixin = { Event = { OnUpdate = "OnUpdate" } }

local callbacks = {}
local registered = {}
local calls = {}
local frameData = setmetatable({}, { __mode = "k" })
local settings = { skinSpellBook = true }

local function NewPagedSpellsFrame(row)
    local pagedSpellsFrame = {}
    function pagedSpellsFrame:RegisterCallback(event, callback, owner)
        self.callbackEvent = event
        self.callback = callback
        self.callbackOwner = owner
    end
    function pagedSpellsFrame:EnumerateFrames()
        local index = 0
        local frames = { row }
        return function()
            index = index + 1
            if frames[index] then
                return index, frames[index]
            end
        end
    end
    return pagedSpellsFrame
end

local function NewPlayerSpellsFrame(name, row)
    local pagedSpellsFrame = NewPagedSpellsFrame(row)
    return {
        name = name,
        TabSystem = { tabs = {} },
        SpellBookFrame = {
            PagedSpellsFrame = pagedSpellsFrame,
        },
    }, pagedSpellsFrame
end

local lateSpellRow = { name = "lateSpellRow" }
local playerSpellsFrame, pagedSpellsFrame = NewPlayerSpellsFrame("PlayerSpellsFrame", lateSpellRow)
_G.PlayerSpellsFrame = playerSpellsFrame

local function CreateStateTable()
    local tbl = setmetatable({}, { __mode = "k" })
    return tbl, function(key)
        local state = tbl[key]
        if not state then
            state = {}
            tbl[key] = state
        end
        return state
    end
end

local ns = {
    Helpers = {
        CreateStateTable = CreateStateTable,
        GetCore = function()
            return {
                db = {
                    profile = {
                        general = settings,
                    },
                },
            }
        end,
    },
    Registry = {
        Register = function(_, key, feature)
            registered[key] = feature
        end,
    },
}

ns.SkinBase = {
    RefreshFrameBackdropColors = function() end,
    IsSkinned = function(frame) return calls.marked == frame end,
    SkinButtonFrameTemplate = function(frame)
        calls.buttonFrame = frame
    end,
    SkinTabGroup = function() end,
    RefreshTabSelected = function() end,
    SkinFrameText = function(frame, opts)
        calls[frame] = opts or {}
    end,
    LockFrameTextObjects = function(frame)
        calls.locked = calls.locked or {}
        calls.locked[frame] = true
    end,
    MarkSkinned = function(frame)
        calls.marked = frame
    end,
    SetFrameData = function(frame, key, value)
        frameData[frame] = frameData[frame] or {}
        frameData[frame][key] = value
    end,
    GetFrameData = function(frame, key)
        local data = frameData[frame]
        return data and data[key]
    end,
    OnAddOnLoaded = function(addon, callback)
        callbacks[addon] = callback
    end,
}

assert(loadfile("QUI_Skinning/skinning/frames/journals.lua"))("QUI", ns)
assert(type(callbacks.Blizzard_PlayerSpells) == "function", "PlayerSpells load hook must be registered")

callbacks.Blizzard_PlayerSpells()

assert(calls.buttonFrame == playerSpellsFrame, "PlayerSpellsFrame must still get QUI frame chrome")
assert(calls.marked == playerSpellsFrame, "PlayerSpellsFrame must be marked skinned")
assert(pagedSpellsFrame.callbackEvent == PagedContentFrameBaseMixin.Event.OnUpdate,
    "spellbook skin must hook paged spell updates")

pagedSpellsFrame.callback(pagedSpellsFrame, pagedSpellsFrame.callbackOwner)

assert(calls[lateSpellRow] and calls[lateSpellRow].recurse == true and calls[lateSpellRow].chrome == true,
    "late spellbook rows must receive recursive QUI chrome text styling")
assert(calls.locked and calls.locked[lateSpellRow],
    "late spellbook rows must have their font objects locked against hover/rebind revert")

settings.skinSpellBook = false
calls = {}
frameData = setmetatable({}, { __mode = "k" })
local refreshLateSpellRow = { name = "refreshLateSpellRow" }
local refreshPlayerSpellsFrame, refreshPagedSpellsFrame =
    NewPlayerSpellsFrame("RefreshPlayerSpellsFrame", refreshLateSpellRow)
_G.PlayerSpellsFrame = refreshPlayerSpellsFrame

callbacks.Blizzard_PlayerSpells()

assert(calls.buttonFrame == nil, "disabled spellbook skin must not skin on Blizzard load")
assert(refreshPagedSpellsFrame.callbackEvent == nil, "disabled spellbook skin must not hook paged updates")

settings.skinSpellBook = true
assert(registered.skinSpellBook and type(registered.skinSpellBook.refresh) == "function",
    "spellbook skin must register an options refresh")
registered.skinSpellBook.refresh()

assert(calls.buttonFrame == refreshPlayerSpellsFrame,
    "enabling spellbook skin after Blizzard load must skin PlayerSpellsFrame")
assert(refreshPagedSpellsFrame.callbackEvent == PagedContentFrameBaseMixin.Event.OnUpdate,
    "enabling spellbook skin after Blizzard load must hook paged updates")

refreshPagedSpellsFrame.callback(refreshPagedSpellsFrame, refreshPagedSpellsFrame.callbackOwner)

assert(calls[refreshLateSpellRow]
    and calls[refreshLateSpellRow].recurse == true
    and calls[refreshLateSpellRow].chrome == true,
    "refreshed spellbook rows must receive recursive QUI chrome text styling")
assert(calls.locked and calls.locked[refreshLateSpellRow],
    "refreshed spellbook rows must have their font objects locked against hover/rebind revert")

print("OK: player_spells_skin_dynamic_text_test")
