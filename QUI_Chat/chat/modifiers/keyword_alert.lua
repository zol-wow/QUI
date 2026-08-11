local ADDON_NAME, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: keyword_alert.lua loaded before chat.lua. Check chat.xml — chat.lua must precede keyword_alert.lua.")

local Helpers = ns.Helpers

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local function IsSecret(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value)
end

local function IsChatMessagingLockedDown()
    return I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown()
end

local function bareName(author)
    if IsSecret(author) then return nil end -- @secret-policy: reject-secret-ids
    if type(author) ~= "string" or author == "" then return nil end
    local hyphen = author:find("-", 1, true)
    if hyphen then return author:sub(1, hyphen - 1) end
    return author
end

local function colorHex(c)
    if type(c) ~= "table" then return "ff34d399" end
    local r = math.floor(((c[1] or 0)) * 255 + 0.5)
    local g = math.floor(((c[2] or 0)) * 255 + 0.5)
    local b = math.floor(((c[3] or 0)) * 255 + 0.5)
    local a = math.floor(((c[4] or 1)) * 255 + 0.5)
    return string.format("%02x%02x%02x%02x", a, r, g, b)
end

local playerName
local playerFirstName
local playerGuildName

local function refreshIdentity()
    playerName = UnitName("player")
    playerFirstName = nil
    if type(playerName) == "string" then
        local sp = playerName:find(" ", 1, true)
        if sp then
            playerFirstName = playerName:sub(1, sp - 1)
        end
    end
    playerGuildName = GetGuildInfo and GetGuildInfo("player") or nil
end

local function buildTriggers(s)
    local list = {}
    if s.keywords then
        for i = 1, #s.keywords do
            local kw = s.keywords[i]
            if type(kw) == "string" and kw ~= "" then
                list[#list + 1] = kw
            end
        end
    end
    if s.includeOwnName and type(playerName) == "string" and playerName ~= "" then
        list[#list + 1] = playerName
    end
    if s.includeFirstName and type(playerFirstName) == "string" and playerFirstName ~= "" then
        list[#list + 1] = playerFirstName
    end
    if s.includeGuildName and type(playerGuildName) == "string" and playerGuildName ~= "" then
        list[#list + 1] = playerGuildName
    end
    return list
end

local function highlightTrigger(msg, trigger, hex)
    if IsSecret(msg) or IsSecret(trigger) then
        return msg, false
    end
    if type(msg) ~= "string" or msg == "" or type(trigger) ~= "string" or trigger == "" then
        return msg, false
    end
    local lowerMsg     = msg:lower()
    local lowerTrigger = trigger:lower()
    local pos = 1
    local out = {}
    local matched = false
    while true do
        local s, e = lowerMsg:find(lowerTrigger, pos, true)
        if not s then
            out[#out + 1] = msg:sub(pos)
            break
        end
        matched = true
        if s > pos then
            out[#out + 1] = msg:sub(pos, s - 1)
        end
        out[#out + 1] = "|c" .. hex .. msg:sub(s, e) .. "|r"
        pos = e + 1
        if pos > #msg then break end
    end
    if matched then
        return table.concat(out), true
    end
    return msg, false
end

local function highlightOutsideLinks(msg, trigger, hex)
    if type(msg) ~= "string" or not msg:find("|H", 1, true) then
        return highlightTrigger(msg, trigger, hex)
    end
    local out = {}
    local pos = 1
    local matched = false
    while true do
        local s, e = msg:find("|H.-|h.-|h", pos)
        if not s then
            local seg, hit = highlightTrigger(msg:sub(pos), trigger, hex)
            out[#out + 1] = seg
            matched = matched or hit
            break
        end
        if s > pos then
            local seg, hit = highlightTrigger(msg:sub(pos, s - 1), trigger, hex)
            out[#out + 1] = seg
            matched = matched or hit
        end
        out[#out + 1] = msg:sub(s, e)
        pos = e + 1
        if pos > #msg then break end
    end
    return table.concat(out), matched
end

local function GateAndHighlight(msg, author)
    if IsSecret(msg) or IsChatMessagingLockedDown() then return msg, false end
    if not msg or type(msg) ~= "string" or msg == "" then return msg, false end
    local settings = I.GetSettings and I.GetSettings()
    local s = settings and settings.modifiers and settings.modifiers.keywordAlert
    if not s or not s.enabled then return msg, false end
    if s.skipSelf and author and playerName then
        if not IsSecret(author) and not IsSecret(playerName) and bareName(author) == playerName then
            return msg, false
        end
    end
    local triggers = buildTriggers(s)
    if #triggers == 0 then return msg, false end
    local hex = colorHex(s.highlightColor)
    local triggered = false
    for i = 1, #triggers do
        local newMsg, hit = highlightOutsideLinks(msg, triggers[i], hex)
        if hit then
            msg = newMsg
            triggered = true
        end
    end
    return msg, triggered
end

local function PlayAlertSound(s)
    local soundFile = s and s.soundFile
    local resolved = (LSM and soundFile) and LSM:Fetch("sound", soundFile) or soundFile
    if resolved and PlaySoundFile then
        ns.SafeCall("best-effort-style", PlaySoundFile, resolved, "Master")
    end
end

ns.QUI.Chat.KeywordAlert = ns.QUI.Chat.KeywordAlert or {}
function ns.QUI.Chat.KeywordAlert.ProcessForCapture(msg, author)
    local newMsg, triggered = GateAndHighlight(msg, author)
    if triggered then
        local s = (I.GetSettings and I.GetSettings() or {}).modifiers
        s = s and s.keywordAlert
        if s then PlayAlertSound(s) end
    end
    return newMsg
end

local function ApplyEnabled()
    refreshIdentity()
end

ApplyEnabled()

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
loginFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        ApplyEnabled()
    elseif event == "PLAYER_GUILD_UPDATE" then
        refreshIdentity()
    end
end)

table.insert(ns.QUI.Chat._afterRefresh, ApplyEnabled)
