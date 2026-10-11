local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local RecipeLearning = {}
Storage.RecipeLearning = RecipeLearning
RecipeLearning.SNAPSHOT_VERSION = 1
local dirty = false
local statusChanged = false
local recipeProfessions = {}
for name, subclass in pairs(Enum.ItemRecipeSubclass or {}) do
    if name ~= "FirstAid" and Enum.Profession and Enum.Profession[name] ~= nil then
        recipeProfessions[subclass] = Enum.Profession[name]
    end
end

function RecipeLearning.IsRecipe(itemID)
    if not itemID or not C_Item or not C_Item.GetItemInfoInstant then return false end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    return classID == ((Enum.ItemClass and Enum.ItemClass.Recipe) or 9)
end

local function IsRed(color)
    return color and color.r and color.r > 0.8 and color.g < 0.25 and color.b < 0.25
end

local function HasRequiredProfession(itemID)
    local _, _, _, _, _, _, subclass = C_Item.GetItemInfoInstant(itemID)
    local profession = recipeProfessions[subclass]
    if profession == nil or not C_TradeSkillUI or not C_TradeSkillUI.GetProfessionSkillLineID
        or not _G.GetProfessions or not _G.GetProfessionInfo then return nil end
    local required = C_TradeSkillUI.GetProfessionSkillLineID(profession)
    local indices = { _G.GetProfessions() }
    for _, index in pairs(indices) do
        local _, _, _, _, _, _, skillLineID = _G.GetProfessionInfo(index)
        if skillLineID == required then return true end
    end
    return false
end

function RecipeLearning.GetStatus(itemID, data, evaluated)
    if not RecipeLearning.IsRecipe(itemID) or not data or not data.lines or #data.lines == 0 then return nil end
    local types = Enum.TooltipDataLineType or {}
    local requirements = Enum.TooltipDataUsageRequirementType or {}
    local status, hasLearn, preview, seenName = nil, false, false, false
    for _, row in ipairs(data.lines) do
        if types.ItemSpellTriggerLearn and row.type == types.ItemSpellTriggerLearn then
            hasLearn = true
        elseif types.LearnableSpell and row.type == types.LearnableSpell then
            hasLearn = true
        elseif types.NestedBlock and row.type == types.NestedBlock then
            preview = true
        elseif types.ItemName and row.type == types.ItemName then
            if seenName then preview = true end
            seenName = true
        end
        if (_G.ITEM_SPELL_KNOWN and row.leftText == _G.ITEM_SPELL_KNOWN)
            or (requirements.NotAlreadyKnown and row.requirementType == requirements.NotAlreadyKnown
                and row.usable ~= true) then
            status = "known"
        elseif not preview and status ~= "known"
            and (row.usable == false or IsRed(row.leftColor) or IsRed(row.rightColor)) then
            status = "cannotLearn"
        end
    end
    if status ~= "known" and HasRequiredProfession(itemID) == false then status = "cannotLearn" end
    if not status and hasLearn and evaluated then status = "canLearn" end
    if status and evaluated and Storage.Store.IsReady() then
        local rec = Storage.Store.GetCurrentCharacter()
        if rec then
            rec.recipeLearning = rec.recipeLearning or {}
            local old = rec.recipeLearning[itemID]
            if not old or old.status ~= status or old.version ~= RecipeLearning.SNAPSHOT_VERSION then
                statusChanged = true
            end
            rec.recipeLearning[itemID] = {
                status = status, checkedAt = time(), version = RecipeLearning.SNAPSHOT_VERSION,
            }
        end
    end
    return status
end

function RecipeLearning.MarkAllDirty()
    dirty = true
end

local function ScanContainers(containers)
    for bagID, container in pairs(containers or {}) do
        for slot, entry in pairs(container.slots or {}) do
            if entry and RecipeLearning.IsRecipe(entry.itemID) then
                local info = C_Container.GetContainerItemInfo(bagID, slot)
                if info and info.itemID == entry.itemID then
                    RecipeLearning.GetStatus(entry.itemID, C_TooltipInfo.GetBagItem(bagID, slot), true)
                end
            end
        end
    end
end

function RecipeLearning.Drain()
    if not dirty then return false end
    local rec = Storage.Store.GetCurrentCharacter()
    if not rec or not C_TooltipInfo or not C_TooltipInfo.GetBagItem
        or not C_Container or not C_Container.GetContainerItemInfo then return false end
    dirty = false
    ScanContainers(rec.bags)
    if C_Bank and C_Bank.CanViewBank and Enum.BankType then
        if C_Bank.CanViewBank(Enum.BankType.Character) then ScanContainers(rec.bankTabs) end
        if C_Bank.CanViewBank(Enum.BankType.Account) then
            local warband = Storage.Store.GetWarband()
            if warband then ScanContainers(warband.tabs) end
        end
    end
    if statusChanged then
        statusChanged = false
        Storage.Bus.Publish("RecipeLearningChanged", Storage.Store.GetCurrentCharacterKey())
    end
    return true
end

local function OnStorageChanged(event, owner, changed)
    local slots = event == "WarbandChanged" and owner or changed
    if type(slots) ~= "table" or #slots == 0 then return end
    if (event == "BagsChanged" or event == "BankChanged")
        and owner ~= Storage.Store.GetCurrentCharacterKey() then return end
    RecipeLearning.MarkAllDirty()
    if Storage.RequestDrain then Storage.RequestDrain() end
end

for _, event in ipairs({ "BagsChanged", "BankChanged", "WarbandChanged" }) do
    Storage.Bus.Subscribe(event, OnStorageChanged)
end
