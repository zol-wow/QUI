local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local MAX_ROWS = 14
local MAX_CONTACTS = 60

local panel, rows
local hooksInstalled = false
local lastRecipient

local function PanelEnabled()
    local s = GetSettings()
    return s and s.mailContactsPanel == true
end

local function RememberEnabled()
    local s = GetSettings()
    return s and s.mailRememberRecipient == true
end

local function GetStore()
    local db = ns.Addon and ns.Addon.db
    local g = db and db.global
    if not g then return nil end
    if type(g.mailContacts) ~= "table" then g.mailContacts = {} end
    return g.mailContacts
end

-- <<< QUI_TEST_EXTRACT recipient_format
local function NormalizeRealm(realm)
    if type(realm) ~= "string" then return "" end
    return (realm:gsub("[%s%-']", "")):lower()
end

local function FormatRecipient(name, realm, playerRealm)
    if type(name) ~= "string" or name == "" then return nil end
    if type(realm) ~= "string" or realm == "" then return name end
    if NormalizeRealm(realm) == NormalizeRealm(playerRealm) then
        return name
    end
    return name .. "-" .. realm
end
-- <<< QUI_TEST_EXTRACT recipient_format

local function SplitKey(key)
    local name, realm = key:match("^([^%-]+)%-?(.*)$")
    return name or key, realm or ""
end

local function TouchContact(key, class)
    local store = GetStore()
    if not store or type(key) ~= "string" or key == "" then return end
    local name, realm = SplitKey(key)
    local rec = store[key]
    if not rec then
        rec = { name = name, realm = realm }
        store[key] = rec
    end
    if class then rec.class = class end
    rec.lastUsed = time()

    local keys = {}
    for k in pairs(store) do keys[#keys + 1] = k end
    if #keys > MAX_CONTACTS then
        table.sort(keys, function(a, b)
            return (store[a].lastUsed or 0) < (store[b].lastUsed or 0)
        end)
        for i = 1, #keys - MAX_CONTACTS do
            store[keys[i]] = nil
        end
    end
end

local function SeedFromAlts()
    local store = GetStore()
    local Storage = ns.Storage
    if not store or not (Storage and Storage.Store and Storage.Store.ListCharacters) then return end
    local current = Storage.Store.GetCurrentCharacterKey and Storage.Store.GetCurrentCharacterKey()
    for _, key in ipairs(Storage.Store.ListCharacters()) do
        if key ~= current and not store[key] then
            local rec = Storage.Store.GetCharacter(key)
            local name, realm = SplitKey(key)
            store[key] = {
                name = name,
                realm = realm,
                class = rec and rec.details and rec.details.class or nil,
                lastUsed = 0,
            }
        end
    end
end

local function BuildSortedContacts()
    local store = GetStore()
    if not store then return {} end
    local current
    local Storage = ns.Storage
    if Storage and Storage.Store and Storage.Store.GetCurrentCharacterKey then
        current = Storage.Store.GetCurrentCharacterKey()
    end
    local list = {}
    for key, rec in pairs(store) do
        if key ~= current then
            list[#list + 1] = { key = key, rec = rec }
        end
    end
    table.sort(list, function(a, b)
        local la, lb = a.rec.lastUsed or 0, b.rec.lastUsed or 0
        if la ~= lb then return la > lb end
        return a.key < b.key
    end)
    return list
end

local function FillRecipient(rec)
    local editBox = _G.SendMailNameEditBox
    if not editBox then return end
    local playerRealm = GetRealmName() or ""
    local recipient = FormatRecipient(rec.name, rec.realm, playerRealm)
    if not recipient then return end
    editBox:SetText(recipient)
    editBox:ClearFocus()
end

local function EnsurePanel()
    if panel then return end
    local mailFrame = _G.MailFrame
    panel = CreateFrame("Frame", nil, mailFrame)
    panel:SetPoint("TOPLEFT", mailFrame, "TOPRIGHT", 4, -8)
    panel:SetSize(150, 30)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -5)
    title:SetText(ns.L["Contacts"])
    rows = {}
    for i = 1, MAX_ROWS do
        local btn = CreateFrame("Button", nil, panel)
        btn:SetSize(138, 16)
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -20 - (i - 1) * 17)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.text:SetPoint("LEFT")
        btn.text:SetJustifyH("LEFT")
        btn.text:SetWidth(138)
        btn.text:SetWordWrap(false)
        btn:SetScript("OnClick", function(self)
            if self.rec then FillRecipient(self.rec) end
        end)
        btn:SetScript("OnEnter", function(self)
            self.text:SetTextColor(1, 0.82, 0)
        end)
        btn:SetScript("OnLeave", function(self)
            local c = self.classColor
            if c then self.text:SetTextColor(c.r, c.g, c.b) else self.text:SetTextColor(1, 1, 1) end
        end)
        btn:Hide()
        rows[i] = btn
    end
    panel:Hide()
end

local function UpdatePanel()
    local mailFrame, sendFrame = _G.MailFrame, _G.SendMailFrame
    if not PanelEnabled() or not mailFrame or not mailFrame:IsShown()
        or not sendFrame or not sendFrame:IsShown() then
        if panel then panel:Hide() end
        return
    end
    EnsurePanel()
    SeedFromAlts()
    local list = BuildSortedContacts()
    local shown = math.min(#list, MAX_ROWS)
    for i = 1, MAX_ROWS do
        local btn = rows[i]
        local entry = list[i]
        if i <= shown and entry then
            btn.rec = entry.rec
            local color = entry.rec.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.rec.class]
            btn.classColor = color
            if color then
                btn.text:SetTextColor(color.r, color.g, color.b)
            else
                btn.text:SetTextColor(1, 1, 1)
            end
            btn.text:SetText(entry.rec.name or entry.key)
            btn:Show()
        else
            btn.rec = nil
            btn:Hide()
        end
    end
    panel:SetHeight(24 + shown * 17 + 6)
    panel:Show()
end

local function OnSendMail()
    local editBox = _G.SendMailNameEditBox
    local text = editBox and editBox:GetText()
    if type(text) ~= "string" or text == "" then return end
    lastRecipient = text
    if PanelEnabled() then
        local key = text
        if not key:find("-", 1, true) then
            local realm = (GetRealmName() or ""):gsub("[%s']", "")
            if realm ~= "" then key = key .. "-" .. realm end
        end
        TouchContact(key, nil)
    end
end

local function OnSendReset()
    if not RememberEnabled() or not lastRecipient then return end
    local mailFrame = _G.MailFrame
    if not (mailFrame and mailFrame:IsShown()) then return end
    local editBox = _G.SendMailNameEditBox
    if editBox then
        editBox:SetText(lastRecipient)
        editBox:HighlightText(0, 0)
        editBox:ClearFocus()
    end
end

local function InstallHooks()
    if hooksInstalled then return end
    if type(_G.SendMailFrame_SendMail) ~= "function" then return end
    hooksInstalled = true
    hooksecurefunc("SendMailFrame_SendMail", OnSendMail)
    hooksecurefunc("SendMailFrame_Reset", function()
        OnSendReset()
        UpdatePanel()
    end)
    hooksecurefunc("MailFrameTab_OnClick", UpdatePanel)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_CLOSED")
frame:SetScript("OnEvent", function(_, event)
    if event == "MAIL_SHOW" then
        InstallHooks()
        C_Timer.After(0, UpdatePanel)
    else
        lastRecipient = nil
        if panel then panel:Hide() end
    end
end)

ns.RefreshMailContacts = UpdatePanel
