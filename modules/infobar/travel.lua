local _, ns = ...
local QUICore = ns.Addon
local Datatexts = QUICore and QUICore.Datatexts
if not Datatexts then return end

local max = math.max
local ipairs = ipairs

local HEARTHSTONE_ITEM_ID = 6948

local HEARTH_TOYS = {
    54452,
    64488,
    93672,
    142542,
    162973,
    163045,
    165669,
    165670,
    165802,
    166746,
    166747,
    168907,
    172179,
    180290,
    182773,
    183716,
    184353,
    188952,
    190196,
    190237,
    193588,
    200630,
    206195,
    208704,
    209035,
    212337,
    228940,
}

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local ROW_WIDTH, ROW_HEIGHT = 180, 20

local PlayerHasToy = _G.PlayerHasToy
local C_ToyBox = _G.C_ToyBox

local function GetTravelDB()
    local db = QUICore.db and QUICore.db.profile
    return db and db.infobar
end

local function GetTeleportEntries()
    local challengeMode = _G.C_ChallengeMode
    local dungeonData = ns.DungeonData
    if not challengeMode or not dungeonData then return {} end

    local maps = challengeMode.GetMapTable and challengeMode.GetMapTable()
    if type(maps) ~= "table" then return {} end

    local entries, seen = {}, {}
    for _, mapID in ipairs(maps) do
        local spellID = dungeonData.GetTeleportSpellID(mapID)
        if spellID and not seen[spellID] then
            local name = challengeMode.GetMapUIInfo and challengeMode.GetMapUIInfo(mapID)
            entries[#entries + 1] = { spellID, name }
            seen[spellID] = true
        end
    end
    return entries
end

ns.TravelData = { GetTeleportEntries = GetTeleportEntries }

local function ResolveHearthAction()
    local db = GetTravelDB()
    local useRandom = db and db.travel and db.travel.useRandomHearth
    if useRandom then
        local owned = {}
        for _, itemID in ipairs(HEARTH_TOYS) do
            if PlayerHasToy(itemID) then
                owned[#owned + 1] = itemID
            end
        end
        if #owned > 0 then
            local itemID = owned[math.random(#owned)]
            local _, toyName, icon = C_ToyBox.GetToyInfo(itemID)
            return "toy", itemID,
                icon or FALLBACK_ICON, toyName or "Hearthstone"
        end
    end
    local icon = C_Item.GetItemIconByID(HEARTHSTONE_ITEM_ID)
    local name = C_Item.GetItemNameByID(HEARTHSTONE_ITEM_ID)
    return "item", "item:" .. HEARTHSTONE_ITEM_ID,
        icon or FALLBACK_ICON, name or "Hearthstone"
end

local function ScheduleFlyoutHide(frame)
    C_Timer.After(0.3, function()
        local flyout, hearth = frame._flyout, frame._hearth
        if not flyout or not flyout:IsShown() then return end
        if (hearth and hearth:IsMouseOver()) or flyout:IsMouseOver() then return end
        if InCombatLockdown() then return end
        flyout:Hide()
    end)
end

local function BuildFlyout(frame, slotFrame)
    local flyout = CreateFrame("Frame", nil, frame, "SecureHandlerStateTemplate")
    frame._flyout = flyout

    flyout:SetFrameStrata("DIALOG")
    if flyout.SetFixedFrameStrata then
        flyout:SetFixedFrameStrata(true)
    end

    flyout:SetAttribute("_onstate-combat", [[
        if newstate == "true" then
            self:Hide()
        end
    ]])
    RegisterStateDriver(flyout, "combat", "[combat] true; false")

    local bg = flyout:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.9)

    local rows = 0
    for _, entry in ipairs(GetTeleportEntries()) do
        local spellID, label = entry[1], entry[2]
        if IsSpellKnown(spellID) then
            rows = rows + 1
            local row = CreateFrame("Button", nil, flyout, "SecureActionButtonTemplate")
            row:SetSize(ROW_WIDTH, ROW_HEIGHT)
            row:SetPoint("TOPLEFT", flyout, "TOPLEFT", 2, -(2 + (rows - 1) * ROW_HEIGHT))
            row:RegisterForClicks("AnyUp", "AnyDown")
            row:SetAttribute("type", "spell")
            row:SetAttribute("spell", spellID)

            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.1)

            local name = C_Spell.GetSpellName(spellID)
            local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("LEFT", row, "LEFT", 6, 0)
            text:SetJustifyH("LEFT")
            text:SetWordWrap(false)
            text:SetText(label or name or (ns.L["Spell "] .. spellID))

            row:SetScript("OnLeave", function() ScheduleFlyoutHide(frame) end)
        end
    end
    frame._flyoutRows = rows

    flyout:SetSize(ROW_WIDTH + 4, max(rows * ROW_HEIGHT + 4, 1))

    local db = GetTravelDB()
    if db and db.position == "BOTTOM" then
        flyout:SetPoint("BOTTOMLEFT", slotFrame, "TOPLEFT", 0, 2)
    else
        flyout:SetPoint("TOPLEFT", slotFrame, "BOTTOMLEFT", 0, -2)
    end

    flyout:SetScript("OnLeave", function() ScheduleFlyoutHide(frame) end)
    flyout:Hide()
end

local function ShowFlyout(frame)
    local flyout = frame._flyout
    if not flyout or InCombatLockdown() then return end
    if frame._flyoutDirty then
        frame._flyoutDirty = false
        UnregisterStateDriver(flyout, "combat")
        flyout:Hide()
        flyout:SetParent(nil)
        BuildFlyout(frame, frame._slot)
        flyout = frame._flyout
    end
    if frame._flyoutRows == 0 then return end
    flyout:Show()
end

local function BuildSecureWidgets(frame, slotFrame, size)
    local attrType, attrValue, icon, displayName = ResolveHearthAction()

    local hearth = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
    frame._hearth = hearth
    hearth:SetSize(size, size)
    hearth:SetPoint("LEFT", frame, "LEFT", 2, 0)
    hearth:RegisterForClicks("AnyUp", "AnyDown")
    hearth:SetAttribute("type", attrType)
    hearth:SetAttribute(attrType, attrValue)
    hearth:SetNormalTexture(icon)
    hearth:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    BuildFlyout(frame, slotFrame)

    hearth:SetScript("OnEnter", function(self)
        ShowFlyout(frame)
        local flyout = frame._flyout
        if flyout and flyout:IsShown() then
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            local db = GetTravelDB()
            if db and db.position == "BOTTOM" then
                GameTooltip:SetPoint("BOTTOMLEFT", flyout, "TOPLEFT", 0, 2)
            else
                GameTooltip:SetPoint("TOPLEFT", flyout, "BOTTOMLEFT", 0, -2)
            end
        else
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        end
        GameTooltip:ClearLines()
        GameTooltip:AddLine(displayName, 1, 1, 1)
        GameTooltip:AddLine(ns.L["Left click to hearth"], 0.6, 0.6, 0.6)
        GameTooltip:AddLine(ns.L["Hover for dungeon teleports"], 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    hearth:SetScript("OnLeave", function()
        GameTooltip:Hide()
        ScheduleFlyoutHide(frame)
    end)
end

Datatexts:Register("travel", {
    displayName = ns.L["Travel"],
    category = ns.L["Interface"],
    description = "Hearthstone button with dungeon teleport flyout",

    OnEnable = function(slotFrame, settings)
        local frame = CreateFrame("Frame", nil, slotFrame)
        frame:SetAllPoints()
        frame._slot = slotFrame
        frame._flyoutRows = 0

        if slotFrame.text then slotFrame.text:SetText("") end

        local size = max((slotFrame:GetHeight() or 0) - 6, 12)

        local gap = 4
        local label = frame:CreateFontString(nil, "OVERLAY")
        if slotFrame.text then
            local fp, fs, fl = slotFrame.text:GetFont()
            if fp then
                if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
                    ns.Helpers.ApplyFontWithFallback(label, fp, fs, fl)
                else
                    label:SetFont(fp, fs, fl)
                end
            end
        end
        local labelHidden = slotFrame.noLabel or slotFrame.hideText
        label:SetTextColor(1, 1, 1, 1)
        label:SetText(labelHidden and "" or ns.L["Travel"])
        label:SetPoint("LEFT", frame, "LEFT", 2 + size + gap, 0)
        frame._label = label

        if labelHidden then
            slotFrame._quiFixedWidth = size + 4
        else
            slotFrame._quiFixedWidth = 2 + size + gap + (label:GetStringWidth() or 0) + 4
        end
        if slotFrame._quiOnWidthDirty then slotFrame._quiOnWidthDirty() end

        frame:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
        frame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
        frame:SetScript("OnEvent", function(self, event)
            if event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "CHALLENGE_MODE_MAPS_UPDATE" then
                self._flyoutDirty = true
            elseif event == "PLAYER_REGEN_ENABLED" then
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                if not self._hearth then
                    BuildSecureWidgets(self, slotFrame, size)
                end
            end
        end)

        if InCombatLockdown() then
            frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            BuildSecureWidgets(frame, slotFrame, size)
        end

        return frame
    end,

    OnDisable = function(frame)
        if not frame then return end
        frame:UnregisterAllEvents()
        frame:SetScript("OnEvent", nil)
        if frame._slot then
            frame._slot._quiFixedWidth = nil
            if frame._slot._quiOnWidthDirty then frame._slot._quiOnWidthDirty() end
        end
        if frame._flyout then
            if InCombatLockdown() then
                frame:RegisterEvent("PLAYER_REGEN_ENABLED")
                frame:SetScript("OnEvent", function(self)
                    self:UnregisterAllEvents()
                    self:SetScript("OnEvent", nil)
                    if self._flyout then
                        UnregisterStateDriver(self._flyout, "combat")
                        self._flyout:Hide()
                    end
                end)
            else
                UnregisterStateDriver(frame._flyout, "combat")
                frame._flyout:Hide()
            end
        end
    end,
})
