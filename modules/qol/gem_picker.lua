local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local ICON = 30
local PAD = 6
local PER_ROW_MIN = 6

local panel, titleText
local buttons = {}

local function Enabled()
    local s = GetSettings()
    return s and s.gemSocketPicker == true
end

local function EnsurePanel()
    if panel then return end
    local socketFrame = _G.ItemSocketingFrame
    panel = CreateFrame("Frame", nil, socketFrame)
    panel:SetPoint("TOPLEFT", socketFrame, "BOTTOMLEFT", 0, -2)
    panel:SetSize(math.max(socketFrame:GetWidth(), 200), 60)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
    titleText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    titleText:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -PAD)
    panel:Hide()
end

local function GetButton(i)
    local btn = buttons[i]
    if btn then return btn end
    btn = CreateFrame("Button", nil, panel)
    btn:SetSize(ICON, ICON)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn:RegisterForClicks("AnyUp")
    btn:SetScript("OnClick", function(self)
        if not self.bag or not self.slot then return end
        ClearCursor()
        C_Container.PickupContainerItem(self.bag, self.slot)
        self.icon:SetDesaturated(true)
        self.icon:SetAlpha(0.5)
    end)
    btn:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buttons[i] = btn
    return btn
end

local function CollectBagGems()
    local gems = {}
    for bag = 0, 5 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and not info.isLocked then
                local okI, _, _, _, _, icon, classID = pcall(C_Item.GetItemInfoInstant, info.hyperlink)
                if okI and classID == 3 then
                    gems[#gems + 1] = {
                        bag = bag, slot = slot,
                        link = info.hyperlink,
                        icon = icon or info.iconFileID,
                        count = info.stackCount or 1,
                    }
                end
            end
        end
    end
    return gems
end

local function Refresh()
    local socketFrame = _G.ItemSocketingFrame
    if not socketFrame then return end
    if not Enabled() or not socketFrame:IsShown() then
        if panel then panel:Hide() end
        return
    end
    EnsurePanel()

    local gems = CollectBagGems()
    if #gems == 0 then
        titleText:SetText(ns.L["No gems in bags"])
        for i = 1, #buttons do buttons[i]:Hide() end
        panel:SetHeight(24)
        panel:Show()
        return
    end
    titleText:SetText(ns.L["Bag gems — click to pick up"])

    local perRow = math.max(PER_ROW_MIN, math.floor((panel:GetWidth() - PAD * 2) / (ICON + 2)))
    for i, gem in ipairs(gems) do
        local btn = GetButton(i)
        local row = math.floor((i - 1) / perRow)
        local col = (i - 1) % perRow
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT",
            PAD + col * (ICON + 2), -(PAD + 14) - row * (ICON + 2))
        btn.bag, btn.slot, btn.link = gem.bag, gem.slot, gem.link
        btn.icon:SetTexture(gem.icon)
        btn.icon:SetDesaturated(false)
        btn.icon:SetAlpha(1)
        btn:Show()
    end
    for i = #gems + 1, #buttons do buttons[i]:Hide() end

    local rows = math.ceil(#gems / perRow)
    panel:SetHeight(PAD + 14 + rows * (ICON + 2) + PAD)
    panel:Show()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("SOCKET_INFO_UPDATE")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("CURSOR_CHANGED")
frame:SetScript("OnEvent", function(_, event)
    local socketFrame = _G.ItemSocketingFrame
    if event == "SOCKET_INFO_UPDATE" then
        C_Timer.After(0, Refresh)
        if socketFrame and not socketFrame._quiGemPickerHooked then
            socketFrame._quiGemPickerHooked = true
            socketFrame:HookScript("OnHide", function()
                if panel then panel:Hide() end
            end)
        end
    elseif socketFrame and socketFrame:IsShown() then
        Refresh()
    end
end)

ns.RefreshGemPicker = Refresh
