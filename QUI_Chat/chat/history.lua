local ADDON_NAME, ns = ...

local I = assert(ns.QUI and ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: history.lua loaded before chat.lua. Check chat.xml — chat.lua must precede history.lua.")

ns.QUI.Chat.History = ns.QUI.Chat.History or {}
local History = ns.QUI.Chat.History

local LOGIN_REPLAY_LIMIT = 500

local ApplyEnabled

History._repumping = false

local storeSubscribed = false

local WHISPER_KEYS = I.WHISPER_TYPE_KEYS

local function isExcludedChannel(chatTypeKey, channelName, excludedSet)
    if not excludedSet then return false end
    if type(channelName) == "string" and channelName ~= ""
       and excludedSet[channelName] == true then
        return true
    end
    if type(chatTypeKey) ~= "string" then return false end
    local slotStr = chatTypeKey:match("^CHANNEL(%d+)$")
    if not slotStr then return false end
    local slot = tonumber(slotStr)
    if not slot or not GetChannelName then return false end
    local resolvedName = select(2, GetChannelName(slot))
    if not resolvedName or resolvedName == "" then return false end
    return excludedSet[resolvedName] == true
end

local function captureFromStore(entry)
    if History._repumping then return end
    if entry.hist then return end
    if entry.s then return end
    if type(entry.m) ~= "string" or entry.m == "" then return end
    local e = entry.e
    if e == "ADDMESSAGE" or e == "BACKFILL" or e == "HISTORY" then return end
    if e == "TIME_PLAYED_MSG" then return end
    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end
    local s = settings and settings.history
    if not s or not s.enabled then return end
    local chatTypeKey = entry.k
    if not s.storeWhispers and chatTypeKey and WHISPER_KEYS[chatTypeKey] then return end
    if isExcludedChannel(chatTypeKey, entry.ch, s.excludedChannels) then return end
    local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
    if not Storage then return end
    Storage.AppendLive({
        t = entry.t or ((GetServerTime and GetServerTime()) or time()),
        f = 1,
        m = entry.m,
        r = entry.r, g = entry.g, b = entry.b,
        c = chatTypeKey,
        ch = entry.ch,
        ev = entry.e,
        w = entry.w,
    }, s.maxEntries)
end

History._CaptureFromStore = captureFromStore

local function pruneAndPersist()
    local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
    if not Storage then return end

    local settings = I.GetSettings and I.GetSettings()
    local s = settings and settings.history
    if not s or not s.enabled then
        Storage.PersistNow()
        return
    end

    if Storage.Prune then
        Storage.Prune(s)
    end
    Storage.PersistNow()
end

local function repump()
    History._repumping = true

    local ok, err = pcall(function()
        local settings = I.GetSettings and I.GetSettings()
        if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end
        local s = settings and settings.history
        if not s or not s.enabled then return end

        local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
        if not Storage then return end

        if Storage.Prune then
            Storage.Prune(s)
        end

        local replayLimit = tonumber(s.replayLines) or LOGIN_REPLAY_LIMIT
        local entries = Storage.GetRecentEntries and Storage.GetRecentEntries(replayLimit) or {}
        if #entries == 0 then return end

        local sepBefore = "---- Previous session ----"
        local sepAfter  = "---- Resumed ----"
        local sepR, sepG, sepB = 0.5, 0.5, 0.5

        local StoreMod = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.MessageStore
        if StoreMod and StoreMod.Append then
            local now = (GetServerTime and GetServerTime()) or time()
            local function pumpSeparator(m)
                StoreMod.Append({ m = m, r = sepR, g = sepG, b = sepB,
                    e = "HISTORY", k = "SYSTEM", hist = true, t = now })
            end
            local function pumpEntry(rec)
                StoreMod.Append({
                    m = rec.m or "", r = rec.r or 1, g = rec.g or 1, b = rec.b or 1,
                    k = rec.c, ch = rec.ch, e = rec.ev, w = rec.w,
                    hist = true, t = rec.t or now,
                })
            end
            if s.showSeparators then pumpSeparator(sepBefore) end
            for i = 1, #entries do
                if entries[i].ev ~= "TIME_PLAYED_MSG" then
                    pumpEntry(entries[i])
                end
            end
            if s.showSeparators then pumpSeparator(sepAfter) end
        end
    end)

    History._repumping = false

    if not ok and geterrorhandler then
        geterrorhandler()(err)
    end
end

History._Repump = repump

function History.Clear()
    local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
    if Storage and Storage.Clear then Storage.Clear() end
end

function History.ClearAllCharacters()
    local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
    if not Storage or not Storage.ClearAllCharacters then return 0, 0, nil end
    return Storage.ClearAllCharacters()
end

function ApplyEnabled()
end

local addonFrame = CreateFrame("Frame")
addonFrame:RegisterEvent("ADDON_LOADED")
addonFrame:RegisterEvent("PLAYER_LOGIN")
addonFrame:RegisterEvent("PLAYER_LOGOUT")
addonFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
        if Storage and Storage.Init then Storage.Init() end
        if not storeSubscribed then
            local MsgStore = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.MessageStore
            if MsgStore and MsgStore.OnAppend then
                storeSubscribed = true
                MsgStore.OnAppend(captureFromStore)
            end
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
        if Storage and Storage.MigrateFromAceDB then
            Storage.MigrateFromAceDB()
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, repump)
        else
            repump()
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_LOGOUT" then
        pruneAndPersist()
    end
end)

local function getFrameID(frame)
    if not frame then return nil end
    local nWindows = _G.NUM_CHAT_WINDOWS or 50
    for i = 1, nWindows do
        if _G["ChatFrame" .. i] == frame then return i end
    end
    return nil
end

local function pruneClosedFrame(frameID)
    if not frameID then return end
    local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
    if Storage and Storage.RemoveFrame then
        Storage.RemoveFrame(frameID)
    end
end

if hooksecurefunc and _G.FCF_Close then
    hooksecurefunc("FCF_Close", function(frame)
        pruneClosedFrame(getFrameID(frame))
    end)
end

table.insert(ns.QUI.Chat._afterRefresh, ApplyEnabled)
