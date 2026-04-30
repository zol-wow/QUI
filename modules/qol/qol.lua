local addonName, ns = ...
local Helpers = ns.Helpers
addonName = addonName or "QUI"

---------------------------------------------------------------------------
-- QOL AUTOMATION FEATURES
---------------------------------------------------------------------------

local GetSettings = Helpers.CreateDBGetter("general")

local qolFrame = CreateFrame("Frame")

local popupBlockerDefaults = {
    enabled = false,
    blockTalentMicroButtonAlerts = false,
    blockMicroButtonGlows = false,
    blockHelpTips = false,
    blockEventToasts = false,
    blockMountAlerts = false,
    blockPetAlerts = false,
    blockToyAlerts = false,
    blockCosmeticAlerts = false,
    blockWarbandSceneAlerts = false,
    blockEntitlementAlerts = false,
    blockStaticTalentPopups = false,
    blockStaticHousingPopups = false,
}

local staticPopupBlockRules = {
    blockStaticTalentPopups = { "TALENT", "TRAIT", "PLAYER_SPELLS", "PLAYERSP" },
    blockStaticHousingPopups = { "HOUSING", "HOMESTEAD", "WARBAND_HOME", "WARBANDHOME" },
}

local alertSystemToggleMap = {
    NewMountAlertSystem = "blockMountAlerts",
    NewPetAlertSystem = "blockPetAlerts",
    NewToyAlertSystem = "blockToyAlerts",
    NewCosmeticAlertFrameSystem = "blockCosmeticAlerts",
    NewWarbandSceneAlertSystem = "blockWarbandSceneAlerts",
    EntitlementDeliveredAlertSystem = "blockEntitlementAlerts",
    RafRewardDeliveredAlertSystem = "blockEntitlementAlerts",
}

local talentMicroButtonCandidates = {
    "PlayerSpellsMicroButton",
    "TalentMicroButton",
    "SpellbookMicroButton",
}

local talentMicroButtonAlertCandidates = {
    "PlayerSpellsMicroButtonAlert",
    "TalentMicroButtonAlert",
    "SpellbookMicroButtonAlert",
}

local hookedAlertSystems = {}
local eventToastHooked = false
local mainMenuAlertHooked = false
local microButtonPulseHooked = false
local _quiPopupBlockerHooked = {}  -- Track hooked alert frames (avoids writing to Blizzard frames)

local function GetMaxStaticPopupDialogs()
    return math.min(STATICPOPUP_NUMDIALOGS or 4, 8)
end

local function GetPopupBlockerSettings()
    local settings = GetSettings()
    if not settings then return nil end

    if type(settings.popupBlocker) ~= "table" then
        settings.popupBlocker = {}
    end

    local blocker = settings.popupBlocker
    for key, defaultValue in pairs(popupBlockerDefaults) do
        if blocker[key] == nil then
            blocker[key] = defaultValue
        end
    end

    return blocker
end

local function IsPopupBlockEnabled(toggleKey)
    local blocker = GetPopupBlockerSettings()
    if not blocker or not blocker.enabled then
        return false
    end
    return blocker[toggleKey] == true
end

local function HideAlertFrame(frame)
    if not frame then return end
    if frame.Hide then
        frame:Hide()
    end
end

local function ShouldBlockStaticPopup(which)
    if type(which) ~= "string" then return false end

    local blocker = GetPopupBlockerSettings()
    if not blocker or not blocker.enabled then
        return false
    end

    local upperWhich = string.upper(which)
    for toggleKey, keywords in pairs(staticPopupBlockRules) do
        if blocker[toggleKey] then
            for _, keyword in ipairs(keywords) do
                if string.find(upperWhich, keyword, 1, true) then
                    return true
                end
            end
        end
    end

    return false
end

local function HideStaticPopupByWhich(which)
    if type(which) ~= "string" then return end

    for i = 1, GetMaxStaticPopupDialogs() do
        local frame = _G["StaticPopup" .. i]
        if frame and frame.which == which and frame:IsShown() then
            frame:Hide()
        end
    end
end

local function HookAlertSystem(globalSystemName, toggleKey)
    local system = _G[globalSystemName]
    if not system or hookedAlertSystems[system] then
        return
    end

    if type(system.setUpFunction) ~= "function" then
        return
    end

    -- TAINT SAFETY: Defer to break taint chain from secure alert system context.
    hooksecurefunc(system, "setUpFunction", function(frame)
        C_Timer.After(0, function()
            if IsPopupBlockEnabled(toggleKey) then
                HideAlertFrame(frame)
            end
        end)
    end)
    hookedAlertSystems[system] = true
end

local function HookPopupAlertSystems()
    for globalSystemName, toggleKey in pairs(alertSystemToggleMap) do
        HookAlertSystem(globalSystemName, toggleKey)
    end
end

local function HideEventToasts()
    if not IsPopupBlockEnabled("blockEventToasts") then return end
    if not EventToastManagerFrame then return end
    EventToastManagerFrame:Hide()
end

local function HookEventToastManager()
    if eventToastHooked or not EventToastManagerFrame then
        return
    end

    -- TAINT SAFETY: Defer to break taint chain — EventToastManagerFrame methods
    -- can fire inside secure execution contexts.
    local function PostShowHide(self)
        C_Timer.After(0, function()
            if IsPopupBlockEnabled("blockEventToasts") then
                self:Hide()
            end
        end)
    end

    hooksecurefunc(EventToastManagerFrame, "Show", PostShowHide)
    if type(EventToastManagerFrame.ShowToast) == "function" then
        hooksecurefunc(EventToastManagerFrame, "ShowToast", PostShowHide)
    end
    if type(EventToastManagerFrame.DisplayToast) == "function" then
        hooksecurefunc(EventToastManagerFrame, "DisplayToast", PostShowHide)
    end
    if type(EventToastManagerFrame.QueueToast) == "function" then
        hooksecurefunc(EventToastManagerFrame, "QueueToast", PostShowHide)
    end

    eventToastHooked = true
end

local function IsTalentMicroButton(button)
    if not button then return false end
    if (PlayerSpellsMicroButton and button == PlayerSpellsMicroButton)
        or (TalentMicroButton and button == TalentMicroButton)
        or (SpellbookMicroButton and button == SpellbookMicroButton) then
        return true
    end

    local name = button.GetName and button:GetName()
    if type(name) ~= "string" then
        return false
    end

    local upperName = string.upper(name)
    return string.find(upperName, "TALENT", 1, true)
        or string.find(upperName, "SPELLBOOK", 1, true)
        or string.find(upperName, "PLAYERSP", 1, true)
end

local function HideTalentMicroButtonAlert(button)
    if not button then return end

    local alert = button.alert
    if not alert and button.GetName then
        alert = _G[button:GetName() .. "Alert"]
    end
    if alert then
        alert:Hide()
    end

    -- Blizzard's MicroButtonPulse flashes BOTH FlashBorder and FlashContent
    -- (MainMenuBarMicroButtons.lua). Hiding only FlashBorder leaves the
    -- inner pulse rendering — that's the gap that lets the "big glow"
    -- bleed through when the microbar is visible.
    if button.FlashBorder then
        -- Alpha 0 persists across re-shows; Blizzard pulse animations can
        -- re-show the texture, but with alpha 0 it renders invisibly.
        button.FlashBorder:SetAlpha(0)
        button.FlashBorder:Hide()
    end
    if button.FlashContent then
        button.FlashContent:SetAlpha(0)
        button.FlashContent:Hide()
    end
    if button.NewFeatureTexture then
        button.NewFeatureTexture:Hide()
    end
    if button.NewFeatureShine then
        button.NewFeatureShine:Hide()
    end
    if button.Flash then
        button.Flash:Hide()
    end
end

-- Returns true when the microbar is disabled or faded to alpha 0,
-- meaning alerts anchored to micro buttons would be invisible/off-screen.
local function IsMicrobarEffectivelyHidden()
    local db = QUI and QUI.db and QUI.db.profile
    local bars = db and db.actionBars and db.actionBars.bars
    local microDB = bars and bars.microbar
    if not microDB or microDB.enabled == false then return true end
    -- Check if currently faded to zero (mouseover fade, HUD visibility, etc.)
    local abOwned = ns.ActionBarsOwned
    local fs = abOwned and abOwned.fadeState and abOwned.fadeState["microbar"]
    if fs and fs.currentAlpha <= 0 then return true end
    -- Check if the container itself is hidden (e.g. HUD visibility system)
    local cont = abOwned and abOwned.containers and abOwned.containers["microbar"]
    if cont and not cont:IsShown() then return true end
    return false
end

-- All micro buttons that can show alerts (superset of talent candidates)
local allMicroButtonNames = {
    "CharacterMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton",
    "AchievementMicroButton", "QuestLogMicroButton", "HousingMicroButton",
    "GuildMicroButton", "LFDMicroButton", "CollectionsMicroButton",
    "EJMicroButton", "StoreMicroButton", "MainMenuMicroButton",
}

-- Additional alert anchor buttons not exposed as globals. Blizzard's HelpTip
-- system anchors callouts to these; when the parent frame is hidden (e.g.
-- PerksProgramFrame is closed) the callout's text-wrap math can produce a
-- runaway size, rendering the GlowFrame as a screen-spanning rectangle.
-- Resolved lazily because the parent frame may not exist at addon load.
local extraAlertAnchorResolvers = {
    function() return PerksProgramFrame and PerksProgramFrame.OpenButton end,
}

-- Named alert frames not following the <MicroButton>Alert convention.
-- Hooked via OnShow so they get the same suppression gating as the
-- standard micro button alerts.
local extraAlertFrameNames = {
    "PerksProgramFrameOpenButtonAlertFrame",
}

-- Detects a HelpTip-shaped frame by structural signature. HelpTip frames are
-- pooled by Blizzard's HelpTip module; they have Text, CloseButton, and either
-- Arrow or BouncyArrow regions. We identify them structurally so we can hide
-- them without touching the HelpTip module itself.
local function IsHelpTipShapedFrame(frame)
    if type(frame) ~= "table" then return false end
    if not (frame.Text and frame.CloseButton) then return false end
    return frame.Arrow ~= nil or frame.BouncyArrow ~= nil
end

-- TAINT SAFETY: Do NOT call ANY HelpTip module methods (Show/Hide/Acknowledge/
-- SetHelpTipsEnabled). They mutate HelpTip's internal Lua tables and taint
-- propagates through Blizzard secure reads. Only touch the discovered frame
-- via C-side methods (SetAlpha, EnableMouse, ClearAllPoints) — those don't
-- write to HelpTip's Lua state. We use SetAlpha(0) rather than Hide() so the
-- frame's OnHide handler never fires → HelpTip's framePool:Release is never
-- triggered from our context.
local function AlphaZeroHelpTip(child)
    if child.SetAlpha then child:SetAlpha(0) end
    if child.EnableMouse then child:EnableMouse(false) end
end

local function HideHelpTipsOnButton(button)
    if not button or type(button.GetChildren) ~= "function" then return end
    local children = { button:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if IsHelpTipShapedFrame(child) and child.IsShown and child:IsShown() then
            AlphaZeroHelpTip(child)
        end
    end
end

-- Builds a lookup set {[frameRef]=true} of the live micro button frames
-- plus any extra alert-anchor buttons (e.g. PerksProgramFrame.OpenButton).
local function BuildMicroButtonSet()
    local set = {}
    for i = 1, #allMicroButtonNames do
        local btn = _G[allMicroButtonNames[i]]
        if btn then set[btn] = true end
    end
    for i = 1, #extraAlertAnchorResolvers do
        local ok, btn = pcall(extraAlertAnchorResolvers[i])
        if ok and btn then set[btn] = true end
    end
    return set
end

-- Fallback sweep: HelpTip frames are often parented to UIParent with SetPoint
-- anchored to the micro button (not direct children of the button). Scan
-- UIParent children once per tick and hide any HelpTip-shaped frame that's
-- anchored to a known micro button.
local function SweepHelpTipsFromUIParent()
    if not UIParent or type(UIParent.GetChildren) ~= "function" then return end
    local micros = BuildMicroButtonSet()
    local kids = { UIParent:GetChildren() }
    for i = 1, #kids do
        local child = kids[i]
        if IsHelpTipShapedFrame(child) and child.IsShown and child:IsShown()
            and type(child.GetNumPoints) == "function" then
                local hit = false
                for p = 1, child:GetNumPoints() do
                    local _, relTo = child:GetPoint(p)
                    if relTo and micros[relTo] then hit = true; break end
                end
                if hit then AlphaZeroHelpTip(child) end
        end
    end
end

local function HideAllMicroButtonAlerts()
    for _, buttonName in ipairs(allMicroButtonNames) do
        local button = _G[buttonName]
        if button then
            HideTalentMicroButtonAlert(button)
            HideHelpTipsOnButton(button)
        end
        -- Also hide the named alert frame if it exists
        local alertFrame = _G[buttonName .. "Alert"]
        if alertFrame and alertFrame:IsShown() then
            alertFrame:Hide()
        end
    end
    -- Named alert frames not following the <MicroButton>Alert convention.
    for _, alertName in ipairs(extraAlertFrameNames) do
        local alertFrame = _G[alertName]
        if alertFrame and alertFrame:IsShown() then
            alertFrame:Hide()
        end
    end
end

local function HideTalentReminderAlerts()
    -- Broad sweep: microbar hidden (alerts would be off-screen) OR user opted
    -- into blocking ALL micro button glows → suppress every micro button.
    if IsMicrobarEffectivelyHidden() or IsPopupBlockEnabled("blockMicroButtonGlows") then
        HideAllMicroButtonAlerts()
    end

    -- Talent-specific sweep (named alert frames beyond the generic button set).
    if IsPopupBlockEnabled("blockTalentMicroButtonAlerts") then
        for _, buttonName in ipairs(talentMicroButtonCandidates) do
            local button = _G[buttonName]
            if button then
                HideTalentMicroButtonAlert(button)
            end
        end

        for _, alertName in ipairs(talentMicroButtonAlertCandidates) do
            local alertFrame = _G[alertName]
            if alertFrame then
                alertFrame:Hide()
            end
        end
    end
end

local function HookTalentReminderAlerts()
    if not mainMenuAlertHooked and type(MainMenuMicroButton_ShowAlert) == "function" then
        -- TAINT SAFETY: Defer to break taint chain from secure context.
        hooksecurefunc("MainMenuMicroButton_ShowAlert", function(button)
            C_Timer.After(0, function()
                -- If microbar is hidden/invisible, suppress ALL micro button alerts
                if IsMicrobarEffectivelyHidden() or IsPopupBlockEnabled("blockMicroButtonGlows") then
                    HideTalentMicroButtonAlert(button)
                    return
                end
                if IsPopupBlockEnabled("blockTalentMicroButtonAlerts") and IsTalentMicroButton(button) then
                    HideTalentMicroButtonAlert(button)
                end
            end)
        end)
        mainMenuAlertHooked = true
    end

    -- Some frames are only created lazily, so keep checking and attach one-shot OnShow hooks.
    -- Use local table to track hooked frames (NOT writing to Blizzard frames to avoid taint)
    for _, alertName in ipairs(talentMicroButtonAlertCandidates) do
        local alertFrame = _G[alertName]
        if alertFrame and not _quiPopupBlockerHooked[alertFrame] then
            -- TAINT SAFETY: Defer to break taint chain from secure context.
            alertFrame:HookScript("OnShow", function(self)
                C_Timer.After(0, function()
                    if not self or not self.Hide then return end
                    if IsMicrobarEffectivelyHidden()
                        or IsPopupBlockEnabled("blockMicroButtonGlows")
                        or IsPopupBlockEnabled("blockTalentMicroButtonAlerts") then
                            self:Hide()
                    end
                end)
            end)
            _quiPopupBlockerHooked[alertFrame] = true
        end
    end

    -- Hook OnShow on non-talent micro button alert frames too (e.g. CollectionsMicroButtonAlert,
    -- AchievementMicroButtonAlert). These are plain callout frames — not secure-layout
    -- children like FlashBorder — so HookScript is taint-safe here.
    for _, buttonName in ipairs(allMicroButtonNames) do
        local alertFrame = _G[buttonName .. "Alert"]
        if alertFrame and not _quiPopupBlockerHooked[alertFrame] then
            alertFrame:HookScript("OnShow", function(self)
                C_Timer.After(0, function()
                    if not self or not self.Hide then return end
                    if IsMicrobarEffectivelyHidden() or IsPopupBlockEnabled("blockMicroButtonGlows") then
                        self:Hide()
                    end
                end)
            end)
            _quiPopupBlockerHooked[alertFrame] = true
        end
    end

    -- Hook OnShow on named alert frames that don't follow the <MicroButton>Alert
    -- convention (e.g. PerksProgramFrameOpenButtonAlertFrame). These can inflate
    -- to screen-spanning size when their anchor button is hidden, so suppress
    -- under the same gating as the standard micro button alerts.
    for _, alertName in ipairs(extraAlertFrameNames) do
        local alertFrame = _G[alertName]
        if alertFrame and not _quiPopupBlockerHooked[alertFrame] then
            alertFrame:HookScript("OnShow", function(self)
                C_Timer.After(0, function()
                    if not self or not self.Hide then return end
                    if IsMicrobarEffectivelyHidden() or IsPopupBlockEnabled("blockMicroButtonGlows") then
                        self:Hide()
                    end
                end)
            end)
            _quiPopupBlockerHooked[alertFrame] = true
        end
    end

    -- TAINT SAFETY: Do NOT HookScript("OnShow") on FlashBorder — micro button
    -- children can fire OnShow from secure context (MicroButtonAndBagsBar layout),
    -- and HookScript injects addon code into that context. Taint propagates through
    -- ShowUIPanel → GameMenuFrame → callback() → ADDON_ACTION_FORBIDDEN.
    --
    -- Instead, hook the named globals MicroButtonPulse / MicroButtonPulseStop.
    -- hooksecurefunc on named globals is taint-safe (the original runs first,
    -- untainted), and Hide/SetAlpha on a texture from our deferred callback
    -- doesn't taint secure state. This re-suppresses FlashBorder whenever
    -- Blizzard re-triggers the pulse (talent change, spec swap, etc.).
    if not microButtonPulseHooked then
        if type(MicroButtonPulse) == "function" then
            hooksecurefunc("MicroButtonPulse", function(button)
                C_Timer.After(0, function()
                    if not button then return end
                    if IsMicrobarEffectivelyHidden()
                        or IsPopupBlockEnabled("blockMicroButtonGlows")
                        or (IsPopupBlockEnabled("blockTalentMicroButtonAlerts") and IsTalentMicroButton(button)) then
                            HideTalentMicroButtonAlert(button)
                    end
                end)
            end)
        end
        if type(MicroButtonPulseStop) == "function" then
            hooksecurefunc("MicroButtonPulseStop", function(button)
                C_Timer.After(0, function()
                    if not button then return end
                    if button.FlashBorder then
                        button.FlashBorder:SetAlpha(0)
                        button.FlashBorder:Hide()
                    end
                    if button.FlashContent then
                        button.FlashContent:SetAlpha(0)
                        button.FlashContent:Hide()
                    end
                end)
            end)
        end
        microButtonPulseHooked = true
    end

    -- EJMicroButtonMixin:UpdateNewAdventureNotice() shows FlashBorder
    -- directly, bypassing MicroButtonPulse — so the pulse hook above never
    -- catches it. Hook it on the instance so the same gating still applies.
    if EJMicroButton and EJMicroButton.UpdateNewAdventureNotice
        and not _quiPopupBlockerHooked[EJMicroButton] then
        hooksecurefunc(EJMicroButton, "UpdateNewAdventureNotice", function(self)
            C_Timer.After(0, function()
                if not self then return end
                if IsMicrobarEffectivelyHidden() or IsPopupBlockEnabled("blockMicroButtonGlows") then
                    HideTalentMicroButtonAlert(self)
                end
            end)
        end)
        _quiPopupBlockerHooked[EJMicroButton] = true
    end
end

-- TAINT SAFETY: HelpTip is a Lua mixin (not a C-side API). Calling ANY of its
-- methods from addon code — SetHelpTipsEnabled, ForceHideAll, Show — writes to
-- internal Lua tables with addon taint.  When Blizzard secure code later reads
-- those tables (e.g. during ShowUIPanel → GameMenuFrame), taint propagates and
-- causes ADDON_ACTION_FORBIDDEN on game menu buttons.  Even deferring via
-- C_Timer.After does not help: the table entries remain permanently tainted.
-- The feature is disabled until Blizzard exposes a C-side API for help tip control.
local function RefreshHelpTipSuppression()
    -- intentionally empty — see taint safety note above
end

-- Event-driven sweep for micro button HelpTips. Pure C-side (Frame:GetChildren
-- + SetAlpha/EnableMouse) — does NOT touch the HelpTip Lua module, so no
-- taint risk. Triggered by the events that actually cause HelpTips to appear
-- on micro buttons, so no polling cost.
local function SweepMicroButtonHelpTips()
    if not (IsMicrobarEffectivelyHidden() or IsPopupBlockEnabled("blockMicroButtonGlows")) then
        return
    end
    -- 1) Direct children of each micro button (covers HelpTips parented to button)
    for _, buttonName in ipairs(allMicroButtonNames) do
        local btn = _G[buttonName]
        if btn then HideHelpTipsOnButton(btn) end
    end
    -- 2) UIParent children anchored to a micro button (covers HelpTips
    --    parented to UIParent with SetPoint(..., microButton, ...))
    SweepHelpTipsFromUIParent()
end

-- Events that reliably trigger a micro button HelpTip appearance. Each fires
-- once per state change (not per frame), so the cost is trivial. A short
-- C_Timer.After defer lets Blizzard actually create/show the HelpTip before
-- we sweep.
local helpTipSweepEvents = {
    "PLAYER_ENTERING_WORLD",        -- Login / zone change (catches pre-existing tips)
    "NEW_MOUNT_ADDED",              -- Collections: new mount
    "NEW_PET_ADDED",                -- Collections: new pet
    "NEW_TOY_ADDED",                -- Collections: new toy
    "ACHIEVEMENT_EARNED",           -- Achievements button
    "TRAIT_CONFIG_UPDATED",         -- PlayerSpells/Talents button
    "PLAYER_TALENT_UPDATE",         -- Legacy talent event
    "QUEST_LOG_UPDATE",             -- Quest log callouts
}
local helpTipSweepFrame = CreateFrame("Frame")
helpTipSweepFrame:SetScript("OnEvent", function()
    C_Timer.After(0.1, SweepMicroButtonHelpTips)
end)

local function RefreshHelpTipSweeper()
    local shouldRun = IsPopupBlockEnabled("blockMicroButtonGlows")
        or IsMicrobarEffectivelyHidden()
    if shouldRun then
        -- pcall each RegisterEvent so an event renamed/removed in a future
        -- WoW patch doesn't break the whole handler chain.
        for _, ev in ipairs(helpTipSweepEvents) do
            pcall(helpTipSweepFrame.RegisterEvent, helpTipSweepFrame, ev)
        end
        -- Immediate sweep for any HelpTips currently showing
        SweepMicroButtonHelpTips()
    else
        helpTipSweepFrame:UnregisterAllEvents()
    end
end

local function RefreshPopupBlocker()
    HookPopupAlertSystems()
    HookEventToastManager()
    HookTalentReminderAlerts()

    HideEventToasts()
    HideTalentReminderAlerts()
    RefreshHelpTipSuppression()
    RefreshHelpTipSweeper()
end

_G.QUI_RefreshPopupBlocker = RefreshPopupBlocker

if ns.Registry then
    ns.Registry:Register("popupBlocker", {
        refresh = _G.QUI_RefreshPopupBlocker,
        priority = 30,
        group = "qol",
        importCategories = { "qol" },
    })
end

---------------------------------------------------------------------------
-- MERCHANT: SELL JUNK + AUTO REPAIR
---------------------------------------------------------------------------

local function OnMerchantShow()
    local settings = GetSettings()
    if not settings then return end

    -- Sell gray items
    if settings.sellJunk then
        for bag = 0, 4 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.quality == Enum.ItemQuality.Poor then
                    C_Container.UseContainerItem(bag, slot)
                end
            end
        end
    end

    -- Auto repair (dropdown: "off", "personal", "guild")
    local repairMode = settings.autoRepair
    if repairMode and repairMode ~= "off" and CanMerchantRepair() then
        local repairCost = GetRepairAllCost()
        if repairCost and repairCost > 0 then
            if repairMode == "guild" then
                RepairAllItems(CanGuildBankRepair())
            else
                RepairAllItems(false)
            end
        end
    end
end

---------------------------------------------------------------------------
-- ROLE CHECK: AUTO ACCEPT
---------------------------------------------------------------------------

local function OnRoleCheckShow()
    local settings = GetSettings()
    if settings and settings.autoRoleAccept then
        CompleteLFGRoleCheck(true)
    end
end

---------------------------------------------------------------------------
-- PARTY INVITES: AUTO ACCEPT
---------------------------------------------------------------------------

local function IsFriendOrBNet(name)
    if not name then return false end
    -- Check regular friends
    if C_FriendList.IsFriend(name) then return true end
    -- Check BattleNet friends (by iterating through them)
    local numBNetTotal = BNGetNumFriends()
    for i = 1, numBNetTotal do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.gameAccountInfo then
            local charName = accountInfo.gameAccountInfo.characterName
            local realmName = accountInfo.gameAccountInfo.realmName
            if charName then
                local fullName = realmName and (charName .. "-" .. realmName) or charName
                if fullName == name or charName == name:match("^([^-]+)") then
                    return true
                end
            end
        end
    end
    return false
end

local function IsGuildMemberByName(name)
    if not name or not IsInGuild() then return false end
    local numMembers = GetNumGuildMembers()
    local searchName = name:match("^([^-]+)") or name
    for i = 1, numMembers do
        local memberName = GetGuildRosterInfo(i)
        if memberName then
            local memberShort = memberName:match("^([^-]+)") or memberName
            if memberShort == searchName then
                return true
            end
        end
    end
    return false
end

local function OnPartyInvite(inviterName)
    local settings = GetSettings()
    if not settings then return end

    -- Dropdown: "off", "all", "friends", "guild", "both"
    local mode = settings.autoAcceptInvites
    if not mode or mode == "off" then return end

    local shouldAccept = false

    if mode == "all" then
        shouldAccept = true
    elseif mode == "friends" then
        shouldAccept = IsFriendOrBNet(inviterName)
    elseif mode == "guild" then
        shouldAccept = IsGuildMemberByName(inviterName)
    elseif mode == "both" then
        shouldAccept = IsFriendOrBNet(inviterName) or IsGuildMemberByName(inviterName)
    end

    if shouldAccept then
        AcceptGroup()
        StaticPopup_Hide("PARTY_INVITE")
    end
end

---------------------------------------------------------------------------
-- QUESTS: AUTO ACCEPT & AUTO TURN-IN
---------------------------------------------------------------------------

local function ShouldPauseQuest(settings)
    return settings.questHoldShift and IsShiftKeyDown()
end

local function OnQuestDetail()
    local settings = GetSettings()
    if not settings or not settings.autoAcceptQuest then return end
    if ShouldPauseQuest(settings) then return end

    AcceptQuest()
end

local function OnQuestComplete()
    local settings = GetSettings()
    if not settings or not settings.autoTurnInQuest then return end
    if ShouldPauseQuest(settings) then return end

    -- If multiple reward choices exist, let player decide
    local numChoices = GetNumQuestChoices()
    if numChoices > 1 then return end

    GetQuestReward(numChoices > 0 and 1 or nil)
end

---------------------------------------------------------------------------
-- GOSSIP: AUTO-SELECT SINGLE OPTION
---------------------------------------------------------------------------

local gossipClicked = {}

local function OnGossipShow()
    local settings = GetSettings()
    if not settings or not settings.autoSelectGossip then return end

    -- Shift bypass: let user manually interact (reuse quest shift setting)
    if settings.questHoldShift and IsShiftKeyDown() then return end

    -- Get available quests (pickups) and active quests (turnins)
    local availableQuests = C_GossipInfo.GetAvailableQuests()
    local numActiveQuests = C_GossipInfo.GetNumActiveQuests()

    -- If quest options exist, don't auto-select gossip
    if (availableQuests and #availableQuests > 0) or (numActiveQuests and numActiveQuests > 0) then
        return
    end

    -- Get pure gossip options
    local options = C_GossipInfo.GetOptions()
    if not options or #options == 0 then return end

    -- Count valid options to ensure we truly have only one choice
    local validOptions = {}
    for _, option in pairs(options) do
        if option.gossipOptionID then
            table.insert(validOptions, option)
        end
    end

    -- ONLY auto-select when there is exactly 1 option
    if #validOptions == 1 then
        local option = validOptions[1]
        local optionID = option.gossipOptionID

        if optionID and not gossipClicked[optionID] then
            gossipClicked[optionID] = true
            C_GossipInfo.SelectOption(optionID)
        end
    end
    -- If there are multiple options, do NOTHING - let the player choose
    -- This prevents auto-skipping dialogue/cutscene choices
end

local function OnGossipClosed()
    gossipClicked = {}
end

---------------------------------------------------------------------------
-- FAST AUTO LOOT
---------------------------------------------------------------------------

local lootRetryPending = false

local function TryLootAll()
    local numItems = GetNumLootItems()
    for slotIndex = 1, numItems do
        if LootSlotHasItem(slotIndex) then
            LootSlot(slotIndex)
        end
    end
end

local function CheckRemainingLoot()
    lootRetryPending = false
    local settings = GetSettings()
    if not settings or not settings.fastAutoLoot then return end

    -- Check if any items still remain (handles stuck loot bug)
    local numItems = GetNumLootItems()
    for slotIndex = 1, numItems do
        if LootSlotHasItem(slotIndex) then
            TryLootAll()
            return
        end
    end
end

local function OnLootReady()
    local settings = GetSettings()
    if not settings or not settings.fastAutoLoot then return end

    -- Auto-enable WoW's auto-loot if our setting is on (lazy init on first loot)
    if not GetCVarBool("autoLootDefault") then
        SetCVar("autoLootDefault", "1")
    end

    TryLootAll()

    -- Schedule check for stuck items
    if not lootRetryPending then
        lootRetryPending = true
        C_Timer.After(0.1, CheckRemainingLoot)
    end
end

---------------------------------------------------------------------------
-- M+ COMBAT LOGGING
---------------------------------------------------------------------------

local wasLoggingBeforeChallenge = false
local mplusAutoLoggingActive = false
local wasInMythicPlus = false
local pendingMythicPlusUpdate = nil
local pendingMythicPlusStop = nil
local raidAutoLoggingActive = false
local wasInRaidInstance = false
local MYTHIC_PLUS_STOP_GRACE_SECONDS = 8

local function CancelPendingMythicPlusUpdate()
    if pendingMythicPlusUpdate and pendingMythicPlusUpdate.Cancel then
        pendingMythicPlusUpdate:Cancel()
    end
    pendingMythicPlusUpdate = nil
end

local function CancelPendingMythicPlusStop()
    if pendingMythicPlusStop and pendingMythicPlusStop.Cancel then
        pendingMythicPlusStop:Cancel()
    end
    pendingMythicPlusStop = nil
end

local function HasMythicPlusActiveSignal()
    if C_MythicPlus and type(C_MythicPlus.IsMythicPlusActive) == "function" then
        local ok, active = pcall(C_MythicPlus.IsMythicPlusActive)
        if ok and active == true then
            return true
        end
    end

    if C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
        local ok, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
        if ok and mapID ~= nil then
            return true
        end
    end

    if C_ChallengeMode and type(C_ChallengeMode.IsChallengeModeActive) == "function" then
        local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
        if ok and active == true then
            return true
        end
    end

    return false
end

local function IsInMythicPlusInstance()
    local _, instanceType, difficultyID = GetInstanceInfo()
    return instanceType == "party" and difficultyID == 8
end

local function StopMythicPlusLogging()
    if mplusAutoLoggingActive and LoggingCombat() then
        LoggingCombat(false)
        print("|cFF30D1FFQUI:|r Combat logging stopped")
    end

    mplusAutoLoggingActive = false
    wasLoggingBeforeChallenge = false
end

local function UpdateMythicPlusAutoLogging(allowImmediateStop)
    local settings = GetSettings()
    local hasActiveSignal = HasMythicPlusActiveSignal()
    local inMythicPlusInstance = IsInMythicPlusInstance()
    local inMythicPlus = hasActiveSignal or (inMythicPlusInstance and (wasInMythicPlus or mplusAutoLoggingActive or LoggingCombat()))

    if not settings or not settings.autoCombatLog then
        CancelPendingMythicPlusStop()
        StopMythicPlusLogging()
        wasInMythicPlus = inMythicPlus
        return
    end

    if inMythicPlus then
        CancelPendingMythicPlusStop()

        if not wasInMythicPlus then
            -- Remember if user already had logging enabled so we never stop their manual logging.
            wasLoggingBeforeChallenge = LoggingCombat()
            mplusAutoLoggingActive = false
        end

        if not LoggingCombat() then
            LoggingCombat(true)
            mplusAutoLoggingActive = true

            if wasInMythicPlus then
                print("|cFF30D1FFQUI:|r Combat logging resumed (active M+ detected)")
            else
                print("|cFF30D1FFQUI:|r Combat logging started for M+")
            end
        end
    elseif wasInMythicPlus then
        if allowImmediateStop then
            StopMythicPlusLogging()
        else
            CancelPendingMythicPlusStop()
            -- Give Blizzard's challenge-state APIs a moment to settle before stopping the log.
            pendingMythicPlusStop = C_Timer.NewTimer(MYTHIC_PLUS_STOP_GRACE_SECONDS, function()
                pendingMythicPlusStop = nil
                UpdateMythicPlusAutoLogging(true)
            end)
            return
        end
    end

    wasInMythicPlus = inMythicPlus
end

local function ScheduleMythicPlusUpdate(delaySeconds)
    CancelPendingMythicPlusUpdate()
    pendingMythicPlusUpdate = C_Timer.NewTimer(delaySeconds or 0, function()
        pendingMythicPlusUpdate = nil
        UpdateMythicPlusAutoLogging()
    end)
end

local function IsInRaidInstance()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "raid"
end

local function UpdateRaidAutoLogging()
    local settings = GetSettings()
    local inRaidInstance = IsInRaidInstance()

    if not settings or not settings.autoCombatLogRaid then
        -- If disabled while active, only stop if QUI started it.
        if raidAutoLoggingActive and LoggingCombat() then
            LoggingCombat(false)
            print("|cFF30D1FFQUI:|r Combat logging stopped")
        end
        raidAutoLoggingActive = false
        wasInRaidInstance = inRaidInstance
        return
    end

    if inRaidInstance and not wasInRaidInstance then
        raidAutoLoggingActive = false

        if not LoggingCombat() then
            LoggingCombat(true)
            raidAutoLoggingActive = true
            print("|cFF30D1FFQUI:|r Combat logging started for raid")
        end
    elseif not inRaidInstance and wasInRaidInstance then
        -- Only stop if QUI started it on raid entry.
        if raidAutoLoggingActive and LoggingCombat() then
            LoggingCombat(false)
            print("|cFF30D1FFQUI:|r Combat logging stopped")
        end
        raidAutoLoggingActive = false
    end

    wasInRaidInstance = inRaidInstance
end

local function RefreshAutoCombatLogging()
    CancelPendingMythicPlusUpdate()
    CancelPendingMythicPlusStop()
    UpdateMythicPlusAutoLogging()
    UpdateRaidAutoLogging()
end

_G.QUI_RefreshAutoCombatLogging = RefreshAutoCombatLogging

---------------------------------------------------------------------------
-- DELETE CONFIRMATION: AUTO-FILL
---------------------------------------------------------------------------

local deletePopups = {
    ["DELETE_ITEM"] = true,
    ["DELETE_GOOD_ITEM"] = true,
    ["DELETE_GOOD_QUEST_ITEM"] = true,
    ["DELETE_QUEST_ITEM"] = true,
}

-- TAINT SAFETY: Defer to break taint chain from secure context.
hooksecurefunc("StaticPopup_Show", function(which)
    C_Timer.After(0, function()
        if ShouldBlockStaticPopup(which) then
            HideStaticPopupByWhich(which)
            return
        end

        if not deletePopups[which] then return end

        local settings = GetSettings()
        if not settings or not settings.autoDeleteConfirm then return end

        -- Find the popup frame that's showing this dialog
        for i = 1, GetMaxStaticPopupDialogs() do
            local frame = _G["StaticPopup" .. i]
            if frame and frame.which == which and frame:IsShown() then
                local editBox = frame.editBox or _G["StaticPopup" .. i .. "EditBox"]
                if editBox then
                    editBox:SetText(DELETE_ITEM_CONFIRM_STRING or "DELETE")
                    -- Trigger OnTextChanged to enable the confirm button
                    local handler = editBox:GetScript("OnTextChanged")
                    if handler then
                        handler(editBox)
                    end
                -- Note: Cannot auto-click - DeleteCursorItem() is protected
            end
            break
        end
    end
    end)
end)

---------------------------------------------------------------------------
-- AUCTION HOUSE EXPANSION FILTER
---------------------------------------------------------------------------

local ahHooked = false

local function SetupAuctionHouseFilter()
    if ahHooked then return end
    if not AuctionHouseFrame then return end

    ahHooked = true

    local searchBar = AuctionHouseFrame.SearchBar
    local searchBox = searchBar.SearchBox

    local function applyFilter()
        local settings = GetSettings()
        if not settings or not settings.auctionHouseExpansionFilter then return end
        searchBar.FilterButton.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
        searchBar:UpdateClearFiltersButton()
        searchBox:SetFocus()
    end

    searchBar:HookScript("OnShow", function() C_Timer.After(0, applyFilter) end)
    C_Timer.After(0, applyFilter)
end

---------------------------------------------------------------------------
-- CRAFTING ORDERS EXPANSION FILTER
---------------------------------------------------------------------------

local coHooked = false

local function SetupCraftingOrderFilter()
    if coHooked then return end
    local frame = ProfessionsCustomerOrdersFrame
    if not frame then return end

    local browseOrders = frame.BrowseOrders
    if not browseOrders or not browseOrders.SearchBar then return end

    coHooked = true

    local filterDropdown = browseOrders.SearchBar.FilterDropdown
    if not filterDropdown then return end

    local function applyFilter()
        local settings = GetSettings()
        if not settings or not settings.craftingOrderExpansionFilter then return end
        if not filterDropdown.filters then return end
        filterDropdown.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
    end

    browseOrders:HookScript("OnShow", function() C_Timer.After(0, applyFilter) end)
    C_Timer.After(0, applyFilter)
end

---------------------------------------------------------------------------
-- EVENT REGISTRATION
---------------------------------------------------------------------------

qolFrame:RegisterEvent("MERCHANT_SHOW")
qolFrame:RegisterEvent("LFG_ROLE_CHECK_SHOW")
qolFrame:RegisterEvent("PARTY_INVITE_REQUEST")
qolFrame:RegisterEvent("QUEST_DETAIL")
qolFrame:RegisterEvent("QUEST_COMPLETE")
qolFrame:RegisterEvent("GOSSIP_SHOW")
qolFrame:RegisterEvent("GOSSIP_CLOSED")
qolFrame:RegisterEvent("LOOT_READY")
qolFrame:RegisterEvent("CHALLENGE_MODE_START")
qolFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
qolFrame:RegisterEvent("CHALLENGE_MODE_RESET")
qolFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
qolFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
qolFrame:RegisterEvent("ADDON_LOADED")
qolFrame:RegisterEvent("AUCTION_HOUSE_SHOW")

qolFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "MERCHANT_SHOW" then
        OnMerchantShow()
    elseif event == "LFG_ROLE_CHECK_SHOW" then
        OnRoleCheckShow()
    elseif event == "PARTY_INVITE_REQUEST" then
        OnPartyInvite(...)
    elseif event == "QUEST_DETAIL" then
        OnQuestDetail()
    elseif event == "QUEST_COMPLETE" then
        OnQuestComplete()
    elseif event == "GOSSIP_SHOW" then
        OnGossipShow()
    elseif event == "GOSSIP_CLOSED" then
        OnGossipClosed()
    elseif event == "LOOT_READY" then
        OnLootReady()
    elseif event == "CHALLENGE_MODE_START" then
        UpdateMythicPlusAutoLogging()
    elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET" then
        -- Active-state APIs can lag the completion/reset event slightly.
        ScheduleMythicPlusUpdate(5)
    elseif event == "PLAYER_ENTERING_WORLD" then
        ScheduleMythicPlusUpdate(2)
        C_Timer.After(2, UpdateRaidAutoLogging)
        C_Timer.After(2, RefreshPopupBlocker)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        UpdateMythicPlusAutoLogging()
        UpdateRaidAutoLogging()
    elseif event == "AUCTION_HOUSE_SHOW" then
        SetupAuctionHouseFilter()
        qolFrame:UnregisterEvent("AUCTION_HOUSE_SHOW")
    elseif event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            C_Timer.After(0, RefreshPopupBlocker)
            return
        end
        if loadedAddon == "Blizzard_ProfessionsCustomerOrders" then
            C_Timer.After(0.1, SetupCraftingOrderFilter)
        end
        if type(loadedAddon) == "string" and string.find(loadedAddon, "Blizzard_", 1, true) == 1 then
            C_Timer.After(0, RefreshPopupBlocker)
        end
    end
end)
