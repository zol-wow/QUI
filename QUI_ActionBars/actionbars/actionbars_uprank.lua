-- luacheck: globals PlaceAction
local _, ns = ...
if not (ns.Client and ns.Client.isForever) then return end

local Helpers = ns.Helpers
local GetDB = Helpers.CreateDBGetter("actionBars")
local SafeValue = Helpers.SafeValue
local SpellRanks = {}
ns.ActionBarsSpellRanks = SpellRanks
local activeDB, callbackDB, previous
local pending = {}
local updating = false
local bank = Enum.SpellBookSpellBank.Player

local function Snapshot()
    local current = { highest = {}, known = {} }
    local count = SafeValue(C_SpellBook.GetNumSpellBookSkillLines())
    if type(count) ~= "number" then return current end
    for tab = 1, count do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(tab)
        local offset = line and SafeValue(line.itemIndexOffset)
        local size = line and SafeValue(line.numSpellBookItems)
        if type(offset) == "number" and type(size) == "number" then
            for slot = offset + 1, offset + size do
                local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                if info and SafeValue(info.itemType) == Enum.SpellBookItemType.Spell
                    and SafeValue(info.isPassive) == false and SafeValue(info.isOffSpec) == false then
                    local id, name = SafeValue(info.spellID), SafeValue(info.name)
                    local low = SafeValue(C_SpellBook.IsSpellBookItemLowRank(slot, bank))
                    if type(id) == "number" and type(name) == "string" and name ~= ""
                        and type(low) == "boolean" then
                        current.known[id] = { name = name, low = low }
                        if not low then
                            local top = current.highest[name]
                            current.highest[name] = top == nil and id or (top == id and id or false)
                        end
                    end
                end
            end
        end
    end
    return current
end

function SpellRanks.Refresh()
    local core = Helpers.GetCore and Helpers.GetCore()
    if core and core.db and callbackDB ~= core.db then
        callbackDB = core.db
        local function Reset()
            activeDB, previous, pending = nil, nil, {}
            SpellRanks.Refresh()
        end
        for _, event in ipairs({ "OnProfileChanged", "OnProfileCopied", "OnProfileReset" }) do
            callbackDB.RegisterCallback(SpellRanks, event, Reset)
        end
    end
    local db = GetDB()
    if not (IsLoggedIn() and db and db.enabled ~= false and db.global and db.global.autoUpgradeSpellRanks == true
        and C_SpellBook and C_SpellBook.IsSpellBookItemLowRank) then
        activeDB, previous, pending = nil, nil, {}
        return false
    end
    if activeDB ~= db then
        activeDB, pending = db, {}
        previous = Snapshot()
        return false
    end
    return true
end

local function CursorSpell()
    local kind, _, _, id = GetCursorInfo()
    return SafeValue(kind), SafeValue(id)
end

local function Apply(current)
    for slot, change in pairs(pending) do
        if InCombatLockdown() or SafeValue(GetCursorInfo(), true) ~= nil then return end
        pending[slot] = nil
        local kind, id = GetActionInfo(slot)
        local old, target = current.known[change.old], current.known[change.target]
        if SafeValue(kind) == "spell" and SafeValue(id) == change.old and old and old.low
            and target and not target.low and old.name == target.name
            and current.highest[target.name] == change.target then
            local picked = pcall(C_Spell.PickupSpell, change.target)
            local cursorKind, cursorID = CursorSpell()
            if picked and cursorKind == "spell" and cursorID == change.target then
                ns.SafeCall("defer-ooc", PlaceAction, slot)
                cursorKind, cursorID = CursorSpell()
                local placedKind, placedID = GetActionInfo(slot)
                if cursorKind == "spell" and (cursorID == change.target
                    or (cursorID == change.old and SafeValue(placedKind) == "spell"
                        and SafeValue(placedID) == change.target)) then
                    ClearCursor()
                end
            end
        end
    end
end

local function Update(_, event)
    if updating or not SpellRanks.Refresh() then return end
    if (event == "CURSOR_CHANGED" or event == "PLAYER_REGEN_ENABLED") and not next(pending) then return end
    local current = Snapshot()
    local upgrades = {}
    for name, target in pairs(current.highest) do
        local old = previous.highest[name]
        if target and old and old ~= target and not previous.known[target]
            and current.known[old] and current.known[old].low then
            upgrades[old] = target
        end
    end
    previous = current
    if next(upgrades) then
        for slot = 1, 180 do
            local kind, id = GetActionInfo(slot)
            kind, id = SafeValue(kind), SafeValue(id)
            local queued = pending[slot]
            if queued and kind == "spell" and id == queued.old and upgrades[queued.target] then
                queued.target = upgrades[queued.target]
            elseif kind == "spell" and id and upgrades[id] then
                pending[slot] = { old = id, target = upgrades[id] }
            end
        end
    end
    updating = true
    Apply(current)
    updating = false
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED",
    "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_REGEN_ENABLED", "CURSOR_CHANGED" }) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", Update)
SpellRanks.Refresh()
