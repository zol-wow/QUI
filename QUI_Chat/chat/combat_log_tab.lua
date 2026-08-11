local ADDON_NAME, ns = ... -- luacheck: ignore ADDON_NAME

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: combat_log_tab.lua loaded before chat.lua. Check QUI_Chat.toc — chat.lua must precede combat_log_tab.lua.")

ns.QUI.Chat.CombatLogTab = ns.QUI.Chat.CombatLogTab or {}
local CombatLogTab = ns.QUI.Chat.CombatLogTab

local hostByWindow = {}
local activeWindow
local hiddenAnchor
local loadWaiter
local combatWaiter
local stockFont
local stockJustifyH
local fontHookInstalled
local primed

local function HiddenAnchor()
    if not hiddenAnchor and _G.CreateFrame then
        hiddenAnchor = _G.CreateFrame("Frame", "QUI_CombatLogPark", _G.UIParent)
        hiddenAnchor:Hide()
    end
    return hiddenAnchor
end

local shownPark
local function ShownPark()
    if not shownPark and _G.CreateFrame then
        shownPark = _G.CreateFrame("Frame", "QUI_CombatLogShownPark", _G.UIParent)
        shownPark:SetSize(1, 1)
        shownPark:SetPoint("TOPRIGHT", _G.UIParent, "BOTTOMLEFT", -20, -20)
        if shownPark.SetClipsChildren then
            shownPark:SetClipsChildren(true)
        end
        shownPark:Show()
    end
    return shownPark
end

function CombatLogTab.GetParkParent()
    return ShownPark() or HiddenAnchor()
end

local secureShowDriver
local SecureShowCycle

local function QueueRegenCycle()
    if not combatWaiter and _G.CreateFrame then
        combatWaiter = _G.CreateFrame("Frame")
    end
    if not combatWaiter or combatWaiter.quiCyclePending then return end
    combatWaiter.quiCyclePending = true
    combatWaiter:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        self:SetScript("OnEvent", nil)
        self.quiCyclePending = nil
        local Sup = ns.QUI.Chat.BlizzardSuppress
        if Sup and Sup.IsActive and not Sup.IsActive() then return end
        SecureShowCycle(_G.ChatFrame2)
    end)
    combatWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function SecureShowCycle(cf)
    if not cf then return end
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        if not (cf.IsShown and cf:IsShown()) and cf.Show then
            ns.SafeCallMethod("best-effort-style", cf, "Show")
        end
        QueueRegenCycle()
        return
    end
    if not secureShowDriver and _G.CreateFrame then
        local ok, drv = ns.SafeCall("best-effort-style", _G.CreateFrame, "Frame", "QUI_CombatLogSecureShow",
            nil, "SecureHandlerBaseTemplate")
        if ok and drv then secureShowDriver = drv end
    end
    if secureShowDriver and secureShowDriver.SetFrameRef and secureShowDriver.Execute then
        local okRef = ns.SafeCallMethod("best-effort-style", secureShowDriver, "SetFrameRef", "quiCombatLog", cf)
        if okRef then
            local okRun = ns.SafeCallMethod("best-effort-style", secureShowDriver, "Execute", [=[
                local f = self:GetFrameRef("quiCombatLog")
                if f then
                    if f:IsShown() then f:Hide() end
                    f:Show()
                end
            ]=])
            if okRun and cf.IsShown and cf:IsShown() then return end
        end
    end
    if not (cf.IsShown and cf:IsShown()) and cf.Show then
        ns.SafeCallMethod("best-effort-style", cf, "Show")
    end
end

function CombatLogTab.IsEnabled()
    local s = I.GetSettings and I.GetSettings()
    local cd = s and s.customDisplay
    if type(cd) ~= "table" then return true end
    return cd.combatLogTab ~= false
end

function CombatLogTab.GetHostParent()
    return activeWindow and hostByWindow[activeWindow] or nil
end

function CombatLogTab.IsActiveWindow(windowID)
    return activeWindow == (tonumber(windowID) or 1)
end

function CombatLogTab.EnsureLoaded(cb)
    if _G.CombatLogQuickButtonFrame_Custom and _G.ChatFrame2 then
        if cb then cb() end
        return true
    end
    if _G.IsLoggedIn and _G.IsLoggedIn() then
        if _G.C_AddOns and _G.C_AddOns.LoadAddOn then
            ns.SafeCall("best-effort-style", _G.C_AddOns.LoadAddOn, "Blizzard_CombatLog")
        end
        if _G.CombatLogQuickButtonFrame_Custom and _G.ChatFrame2 then
            if cb then cb() end
            return true
        end
    end
    if not loadWaiter and _G.CreateFrame then
        loadWaiter = _G.CreateFrame("Frame")
    end
    if loadWaiter then
        loadWaiter:SetScript("OnEvent", function(self)
            if _G.CombatLogQuickButtonFrame_Custom and _G.ChatFrame2 then
                self:UnregisterAllEvents()
                self:SetScript("OnEvent", nil)
                if cb then cb() end
            end
        end)
        loadWaiter:RegisterEvent("ADDON_LOADED")
        loadWaiter:RegisterEvent("UPDATE_CHAT_WINDOWS")
        loadWaiter:RegisterEvent("PLAYER_LOGIN")
    end
    return false
end

function CombatLogTab.Prime()
    if primed then return end
    if not CombatLogTab.IsEnabled() then return end
    primed = true
    CombatLogTab.EnsureLoaded(function()
        local Sup = ns.QUI.Chat.BlizzardSuppress
        if Sup and Sup.IsActive and not Sup.IsActive() then
            primed = nil
            return
        end
        if not CombatLogTab.IsEnabled() then
            primed = nil
            return
        end
        SecureShowCycle(_G.ChatFrame2)
    end)
end

local function ReassertJustify(cf)
    if cf.SetJustifyH then
        cf:SetJustifyH(stockJustifyH or "LEFT")
    end
end

function CombatLogTab.RefreshFont()
    if not activeWindow then return end
    local cf = _G.ChatFrame2
    local fo = I.chatFontObject or _G.QUI_CustomChatFontObject
    if not (cf and fo and cf.SetFontObject) then return end
    if not stockFont and cf.GetFont then
        local file, height, flags = cf:GetFont()
        if file and type(height) == "number" and height > 0 then
            stockFont = { file = file, height = height, flags = flags or "" }
        end
    end
    if not stockJustifyH and cf.GetJustifyH then
        local j = cf:GetJustifyH()
        if type(j) == "string" and j ~= "" then stockJustifyH = j end
    end
    cf:SetFontObject(fo)
    ReassertJustify(cf)
    if not fontHookInstalled and _G.hooksecurefunc then
        fontHookInstalled = true
        _G.hooksecurefunc(cf, "SetFont", function(self)
            if not activeWindow then return end
            local cur = I.chatFontObject or _G.QUI_CustomChatFontObject
            if cur and self.SetFontObject then
                self:SetFontObject(cur)
                ReassertJustify(self)
            end
        end)
    end
end

local function StripChrome(cf)
    local park = HiddenAnchor()
    if not park then return end
    local name = cf.GetName and cf:GetName()
    local bg = cf.Background or (name and _G[name .. "Background"])
    if bg and bg.SetParent then bg:SetParent(park) end
end

local function Embed(windowID, container)
    local cf = _G.ChatFrame2
    local qb = _G.CombatLogQuickButtonFrame_Custom
    if not (cf and qb) then return end
    local Display = ns.QUI.Chat.DisplayLayer
    local smf = Display and Display.GetMessageFrame and Display.GetMessageFrame(windowID)

    hostByWindow[windowID] = container
    activeWindow = windowID

    if smf and smf.Hide then smf:Hide() end
    local SB = ns.QUI.Chat.Scrollbar
    if SB and SB.SetShown then SB.SetShown(windowID, false) end

    if qb.SetParent then qb:SetParent(container) end
    if qb.ClearAllPoints then qb:ClearAllPoints() end
    if smf and qb.SetPoint then
        qb:SetPoint("TOPLEFT", smf, "TOPLEFT", 0, 0)
        qb:SetPoint("TOPRIGHT", smf, "TOPRIGHT", 0, 0)
    end
    if qb.Show then qb:Show() end

    if cf.SetParent then cf:SetParent(container) end
    if cf.ClearAllPoints then cf:ClearAllPoints() end
    if cf.SetPoint then cf:SetPoint("TOPLEFT", qb, "BOTTOMLEFT", 0, -2) end
    if smf and cf.SetPoint then
        cf:SetPoint("BOTTOMRIGHT", smf, "BOTTOMRIGHT", 0, 0)
    end
    StripChrome(cf)
    CombatLogTab.RefreshFont()
    SecureShowCycle(cf)
end

function CombatLogTab.Activate(windowID)
    windowID = tonumber(windowID) or 1
    local Display = ns.QUI.Chat.DisplayLayer
    local container = Display and Display.GetContainer and Display.GetContainer(windowID)
    if not container then return false end

    local function install()
        Embed(windowID, container)
    end

    if not CombatLogTab.EnsureLoaded(install) then
        hostByWindow[windowID] = container
        activeWindow = windowID
    end
    return true
end

function CombatLogTab.Deactivate(windowID)
    windowID = tonumber(windowID) or 1
    if activeWindow == windowID then activeWindow = nil end
    hostByWindow[windowID] = nil

    local park = HiddenAnchor()
    local cf = _G.ChatFrame2
    local qb = _G.CombatLogQuickButtonFrame_Custom
    local cfPark = CombatLogTab.GetParkParent()
    if cf and cfPark and cf.SetParent then cf:SetParent(cfPark) end
    if qb and park and qb.SetParent then qb:SetParent(park) end
    if stockFont and cf and cf.SetFont then
        cf:SetFont(stockFont.file, stockFont.height, stockFont.flags)
    end
    if cf and cf.SetJustifyH then
        cf:SetJustifyH(stockJustifyH or "LEFT")
    end

    local Display = ns.QUI.Chat.DisplayLayer
    local smf = Display and Display.GetMessageFrame and Display.GetMessageFrame(windowID)
    if smf and smf.Show then smf:Show() end
    local SB = ns.QUI.Chat.Scrollbar
    if SB and SB.SetShown then SB.SetShown(windowID, true) end
    local TabManager = ns.QUI.Chat.TabManager
    if TabManager and TabManager.ReapplyAll then TabManager.ReapplyAll() end
end
