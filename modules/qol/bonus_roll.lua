local _, ns = ...
local Helpers = ns.Helpers
local GetGeneral = Helpers.CreateDBGetter("general")
local Number = Helpers.SafeNumberOrNil
local BonusRoll = {}
ns.BonusRoll = BonusRoll

local pending, activeRun, encounterCache
local serial = 0
local session = tostring(time()) .. "-" .. tostring(GetTimePreciseSec())
local raidDifficulties = { 17, 14, 15, 16, 220 }

local function Settings()
    local general = GetGeneral()
    return general and general.bonusRoll
end

local function Catalogue()
    local core = Helpers.GetCore()
    return core and core.db and core.db.global and core.db.global.bonusRoll
end

local function Print(message)
    local core = Helpers.GetCore()
    if core and core.Print then core:Print(message) end
end

local function IsPreview(frame)
    return frame.isInEditMode or (_G.QUI_IsLayoutModeActive and _G.QUI_IsLayoutModeActive())
end

local function ReadOffer(frame)
    if not frame or IsPreview(frame) then return nil end
    -- @secret-policy: reject-to-nil
    if Helpers.IsSecretValue(frame.state) then return nil end
    if frame.state ~= "prompt" then return nil end
    local spellID, endTime = Number(frame.spellID), Number(frame.endTime)
    if not spellID or spellID <= 0 or not endTime or endTime <= time() then return nil end
    return {
        spellID = spellID,
        endTime = endTime,
        difficultyID = Number(frame.difficultyID),
        encounterID = Number(frame.encounterID),
        instanceID = Number(frame.instanceID),
    }
end

local function SameOffer(offer)
    if not pending or not offer or pending.spellID ~= offer.spellID or pending.endTime ~= offer.endTime then
        return false
    end
    for _, key in ipairs({ "difficultyID", "encounterID", "instanceID" }) do
        if offer[key] and offer[key] ~= 0 and pending[key] and pending[key] ~= 0 and offer[key] ~= pending[key] then
            return false
        end
    end
    return true
end

local function Learn(offer)
    local catalogue = Catalogue()
    if not catalogue then return end
    if offer.difficultyID and offer.difficultyID > 0 then
        local difficultyID = offer.difficultyID == 233 and 16 or offer.difficultyID
        catalogue.seenDifficulties[difficultyID] = true
    end
    if offer.encounterID and offer.encounterID > 0 then
        local name = EJ_GetEncounterInfo and EJ_GetEncounterInfo(offer.encounterID)
        -- @secret-policy: reject-to-nil
        if Helpers.IsSecretValue(name) then name = nil end
        local encounter = catalogue.seenEncounters[offer.encounterID]
        if type(encounter) ~= "table" then encounter = { difficulties = {} } end
        encounter.name = name or string.format(ns.L["Encounter %d"], offer.encounterID)
        encounter.instanceID = offer.instanceID
        if offer.difficultyID and offer.difficultyID > 0 then
            encounter.difficulties[offer.difficultyID == 233 and 16 or offer.difficultyID] = true
        end
        catalogue.seenEncounters[offer.encounterID] = encounter
    end
end

local function ShouldHide(offer)
    local cfg = Settings()
    if not cfg or not cfg.enabled then return false end
    local difficultyID = offer.difficultyID
    if not difficultyID or difficultyID == 0 then return false end
    if difficultyID == 233 then difficultyID = 16 end
    if difficultyID == 8 then
        local mythic = cfg.mythicPlus or {}
        if mythic.mode == "hide" then return true end
        if mythic.mode == "minimum" and offer.level and offer.level < (tonumber(mythic.minLevel) or 10) then return true end
    end
    local difficulty = cfg.difficulty and cfg.difficulty[difficultyID]
    return difficulty and (difficulty.hide or (offer.encounterID and difficulty.encounters
        and difficulty.encounters[offer.encounterID] == true)) or false
end

local function UpdateRun(completed)
    local cm = C_ChallengeMode
    if not cm then activeRun = nil; return end
    local _, _, difficultyID, _, _, _, _, gameMapID = GetInstanceInfo()
    difficultyID, gameMapID = Number(difficultyID), Number(gameMapID)
    if difficultyID ~= 8 or not gameMapID or gameMapID <= 0 then activeRun = nil; return end
    if completed then
        if not activeRun or activeRun.gameMapID ~= gameMapID or not cm.GetChallengeCompletionInfo then return end
        local info = cm.GetChallengeCompletionInfo()
        if type(info) ~= "table" then return end
        local mapID, level = Number(info.mapChallengeModeID), Number(info.level)
        if mapID == activeRun.mapID and level and level > 0 then activeRun.level = level end
        return
    end
    local mapID = cm.GetActiveChallengeMapID and Number(cm.GetActiveChallengeMapID())
    local level = cm.GetActiveKeystoneInfo and Number(cm.GetActiveKeystoneInfo())
    if not mapID or mapID <= 0 or not level or level <= 0 then activeRun = nil; return end
    local journalID = C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap
        and Number(C_EncounterJournal.GetInstanceForGameMap(gameMapID))
    activeRun = { mapID = mapID, gameMapID = gameMapID, instanceID = journalID, level = level }
end

local function Announce(offer)
    local cfg = Settings()
    if not cfg or not cfg.announce or offer.announced then return end
    offer.announced = true
    local catalogue = Catalogue()
    local encounter = catalogue and catalogue.seenEncounters[offer.encounterID]
    local name = type(encounter) == "table" and encounter.name or encounter
    local difficulty = offer.difficultyID and GetDifficultyInfo(offer.difficultyID)
    -- @secret-policy: reject-to-nil
    if Helpers.IsSecretValue(difficulty) then difficulty = nil end
    local label = name or ns.L["Bonus Roll"]
    if difficulty then label = label .. " — " .. difficulty end
    local link = "|cff00ccff|Haddon:qui:bonusroll:" .. offer.token .. "|h[" .. ns.L["Show bonus roll"] .. "]|h|r"
    Print(string.format(ns.L["Bonus roll hidden: %s. %s"], label, link))
end

local function OnShow(frame)
    local offer = ReadOffer(frame)
    if not offer then return end
    if SameOffer(offer) then
        for _, key in ipairs({ "difficultyID", "encounterID", "instanceID" }) do
            if offer[key] and offer[key] ~= 0 then pending[key] = offer[key] end
        end
    else
        serial = serial + 1
        offer.token = session .. "-" .. serial
        if offer.difficultyID == 8 and activeRun and offer.instanceID and offer.instanceID == activeRun.instanceID then
            offer.level = activeRun.level
        end
        pending = offer
        pending.filtered = ShouldHide(offer)
    end
    Learn(pending)
    if pending.filtered and not pending.bypass then
        GroupLootContainer_RemoveFrame(GroupLootContainer, frame)
        pending.hidden = true
        Announce(pending)
    else
        pending.hidden = false
    end
end

function BonusRoll.GetPendingRoll()
    if pending and pending.hidden and SameOffer(ReadOffer(_G.BonusRollFrame)) then return pending end
end

function BonusRoll.ShowPendingRoll(token)
    local frame = _G.BonusRollFrame
    if not pending or (token and token ~= pending.token) or not SameOffer(ReadOffer(frame)) then
        Print(ns.L["That bonus roll is no longer available."])
        return false
    end
    if frame:IsShown() then
        Print(ns.L["The bonus roll is already showing."])
        return true
    end
    local rollButton = frame.PromptFrame.RollButton
    local enabled = rollButton:IsEnabled()
    -- @secret-policy: reject-to-nil
    if Helpers.IsSecretValue(enabled) then return false end
    pending.bypass = true
    pending.hidden = false
    GroupLootContainer_AddFrame(GroupLootContainer, frame)
    if not enabled then rollButton:Disable() end
    return true
end

function BonusRoll.ClearFilters()
    local cfg = Settings()
    if not cfg then return end
    for _, difficulty in pairs(cfg.difficulty or {}) do
        difficulty.hide = false
        for id in pairs(difficulty.encounters or {}) do difficulty.encounters[id] = false end
    end
    cfg.mythicPlus = cfg.mythicPlus or {}
    cfg.mythicPlus.mode = "show"
    cfg.mythicPlus.minLevel = 10
end

function BonusRoll.GetSeenDifficulties()
    local result = {}
    local catalogue = Catalogue()
    for id in pairs(catalogue and catalogue.seenDifficulties or {}) do
        if type(id) == "number" and id > 0 then result[#result + 1] = id end
    end
    table.sort(result)
    return result
end

local function BuildEncounterGroups()
    local groups, found = {}, {}
    if not (EJ_GetNumTiers and EJ_GetInstanceByIndex and EJ_GetEncounterInfoByIndex and EJ_SelectTier and EJ_SelectInstance) then
        return groups, found
    end
    local tier = EJ_GetNumTiers()
    if not tier or tier < 1 then return groups, found end
    local savedTier = EJ_GetCurrentTier and EJ_GetCurrentTier()
    local savedInstance = _G.EncounterJournal and Number(_G.EncounterJournal.instanceID)
    local savedDifficulty = EJ_GetDifficulty and EJ_GetDifficulty()
    local savedEncounter = _G.EncounterJournal and Number(_G.EncounterJournal.encounterID)
    local ok = ns.SafeCall("report", function()
        EJ_SelectTier(tier)
        local tierName = EJ_GetTierInfo and EJ_GetTierInfo(tier)
        local index = 1
        while true do
            local id, name, _, _, _, _, _, areaMapID = EJ_GetInstanceByIndex(index, true)
            if not id then break end
            local world = areaMapID == 0 or (tierName ~= nil and name == tierName)
            local selected = ns.SafeCall("report", EJ_SelectInstance, id)
            local group = { id = id, name = name, world = world, encounters = {} }
            if selected and not world and EJ_IsValidInstanceDifficulty then
                local valid = {}
                for _, difficultyID in ipairs(raidDifficulties) do
                    if EJ_IsValidInstanceDifficulty(difficultyID) then valid[difficultyID] = true end
                end
                if next(valid) then group.difficulties = valid end
            end
            local bossIndex = 1
            while true do
                local bossName, _, bossID = EJ_GetEncounterInfoByIndex(bossIndex, id)
                if not bossID then break end
                if bossName then
                    group.encounters[#group.encounters + 1] = { id = bossID, name = bossName }
                    found[bossID] = true
                end
                bossIndex = bossIndex + 1
            end
            if #group.encounters > 0 then groups[#groups + 1] = group end
            index = index + 1
        end
    end)
    if savedTier and savedTier > 0 then ns.SafeCall("report", EJ_SelectTier, savedTier) end
    if savedInstance and savedInstance > 0 then ns.SafeCall("report", EJ_SelectInstance, savedInstance) end
    if savedDifficulty and EJ_SetDifficulty then ns.SafeCall("report", EJ_SetDifficulty, savedDifficulty) end
    if savedEncounter and EJ_SelectEncounter then ns.SafeCall("report", EJ_SelectEncounter, savedEncounter) end
    if not ok then return {}, {} end
    return groups, found
end

function BonusRoll.GetEncounterGroups(difficultyID)
    if not encounterCache then
        local groups, found = BuildEncounterGroups()
        if #groups > 0 then encounterCache = { groups = groups, found = found } end
    end
    local result = {}
    local world = difficultyID == 172
    if difficultyID == 233 then difficultyID = 16 end
    if encounterCache then
        for _, group in ipairs(encounterCache.groups) do
            if (difficultyID == nil or group.world == world)
                and (difficultyID == nil or not group.difficulties or group.difficulties[difficultyID]) then
                result[#result + 1] = group
            end
        end
    end
    local catalogue = Catalogue()
    local extra = { id = "other", name = ns.L["Other Encounters"], encounters = {} }
    for id, encounter in pairs(catalogue and catalogue.seenEncounters or {}) do
        if not encounterCache or not encounterCache.found[id] then
            local seen = type(encounter) == "table" and encounter.difficulties
            if not difficultyID or (seen and seen[difficultyID]) then
                extra.encounters[#extra.encounters + 1] = {
                    id = id, name = type(encounter) == "table" and encounter.name or encounter,
                }
            end
        end
    end
    table.sort(extra.encounters, function(a, b) return a.id < b.id end)
    if #extra.encounters > 0 then result[#result + 1] = extra end
    return result
end

local hooked, linkHooked
local function Initialize()
    if not linkHooked and EventRegistry then
        linkHooked = true
        EventRegistry:RegisterCallback("SetItemRef", function(_, link)
            -- @secret-policy: reject-to-nil
            if Helpers.IsSecretValue(link) or type(link) ~= "string" then return end
            local token = link:match("^addon:qui:bonusroll:(.+)$")
            if token then BonusRoll.ShowPendingRoll(token) end
        end, BonusRoll)
    end
    local frame = _G.BonusRollFrame
    if hooked or not frame then return end
    hooked = true
    frame:HookScript("OnShow", OnShow)
    local function ClearPending() pending = nil end
    frame.PromptFrame.RollButton:HookScript("OnClick", ClearPending)
    frame.PromptFrame.PassButton:HookScript("OnClick", ClearPending)
    hooksecurefunc("BonusRollFrame_CloseBonusRoll", ClearPending)
    hooksecurefunc("BonusRollFrame_StartBonusRoll", function()
        if frame:IsShown() then OnShow(frame) end
    end)
    if frame:IsShown() then OnShow(frame) end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "CHALLENGE_MODE_START",
    "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET", "BONUS_ROLL_STARTED", "BONUS_ROLL_FAILED", "BONUS_ROLL_RESULT" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then
        Initialize()
    elseif event == "CHALLENGE_MODE_RESET" then
        activeRun = nil
    elseif event == "PLAYER_ENTERING_WORLD" or event == "CHALLENGE_MODE_START" then
        UpdateRun(false)
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        UpdateRun(true)
    else
        pending = nil
    end
end)
Initialize()
