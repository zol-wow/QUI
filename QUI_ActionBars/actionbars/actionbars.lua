local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

---@diagnostic disable: lowercase-global -- SetChunkEnv installs a setfenv

ADDON_NAME, ns = ...
Helpers = ns.Helpers
GetCore = Helpers.GetCore
LSM = ns.LSM

type = type
pairs = pairs
ipairs = ipairs
pcall = pcall
C_Timer = C_Timer
InCombatLockdown = InCombatLockdown

inInitSafeWindow = false

IS_MIDNIGHT = select(4, GetBuildInfo()) >= 120000

TEXTURE_PATH = (ns.Helpers and ns.Helpers.AssetPath or [[Interface\AddOns\QUI\assets\]]) .. [[iconskin\]]
TEXTURES = {
    normal = TEXTURE_PATH .. "Normal",
    gloss = TEXTURE_PATH .. "Gloss",
    highlight = TEXTURE_PATH .. "Highlight",
    pushed = TEXTURE_PATH .. "Pushed",
    checked = TEXTURE_PATH .. "Checked",
    flash = TEXTURE_PATH .. "Flash",
}

BAR_FRAMES = {
    bar1 = "MainActionBar",
    bar2 = "MultiBarBottomLeft",
    bar3 = "MultiBarBottomRight",
    bar4 = "MultiBarRight",
    bar5 = "MultiBarLeft",
    bar6 = "MultiBar5",
    bar7 = "MultiBar6",
    bar8 = "MultiBar7",
    pet = "PetActionBar",
    stance = "StanceBar",
    microbar = "MicroMenuContainer",
    bags = "BagsBar",
    extraActionButton = "ExtraActionBarFrame",
    zoneAbility = "ZoneAbilityFrame",
}

BUTTON_PATTERNS = {
    bar1 = "ActionButton%d",
    bar2 = "MultiBarBottomLeftButton%d",
    bar3 = "MultiBarBottomRightButton%d",
    bar4 = "MultiBarRightButton%d",
    bar5 = "MultiBarLeftButton%d",
    bar6 = "MultiBar5Button%d",
    bar7 = "MultiBar6Button%d",
    bar8 = "MultiBar7Button%d",
    pet = "PetActionButton%d",
    stance = "StanceButton%d",
}

BUTTON_COUNTS = {
    bar1 = 12, bar2 = 12, bar3 = 12, bar4 = 12, bar5 = 12,
    bar6 = 12, bar7 = 12, bar8 = 12, pet = 10, stance = 10,
}

BAR_ACTION_OFFSETS = {
    bar2 = 60,
    bar3 = 48,
    bar4 = 24,
    bar5 = 36,
    bar6 = 144,
    bar7 = 156,
    bar8 = 168,
}

BINDING_COMMANDS = {
    bar1 = "ACTIONBUTTON",
    bar2 = "MULTIACTIONBAR1BUTTON",
    bar3 = "MULTIACTIONBAR2BUTTON",
    bar4 = "MULTIACTIONBAR3BUTTON",
    bar5 = "MULTIACTIONBAR4BUTTON",
    bar6 = "MULTIACTIONBAR5BUTTON",
    bar7 = "MULTIACTIONBAR6BUTTON",
    bar8 = "MULTIACTIONBAR7BUTTON",
    pet = "BONUSACTIONBUTTON",
    stance = "SHAPESHIFTBUTTON",
}

MICRO_BUTTON_NAMES = {
    "CharacterMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton",
    "AchievementMicroButton", "QuestLogMicroButton", "HousingMicroButton",
    "GuildMicroButton", "LFDMicroButton", "CollectionsMicroButton",
    "EJMicroButton", "StoreMicroButton", "MainMenuMicroButton",
}

STANDARD_BAR_KEYS = {"bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8"}
STANDARD_BAR_KEY_SET = {
    bar1 = true, bar2 = true, bar3 = true, bar4 = true,
    bar5 = true, bar6 = true, bar7 = true, bar8 = true,
}

LINKED_OWNED_BAR_KEYS = {"bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8", "pet", "stance"}

ALL_MANAGED_BAR_KEYS = {"bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8", "pet", "stance", "microbar", "bags"}

SKINNABLE_BAR_KEYS = {
    bar1 = true, bar2 = true, bar3 = true, bar4 = true,
    bar5 = true, bar6 = true, bar7 = true, bar8 = true,
    pet = true, stance = true,
}

ActionBarsOwned = {
    initialized = false,
    containers = {},
    nativeButtons = {},
    cachedLayouts = {},
    editModeActive = false,
    editOverlays = {},
    fadeState = {},
    pendingExtraButtonRefresh = false,
    pendingExtraButtonInit = false,
    skinnedButtons = {},
}
ns.ActionBarsOwned = ActionBarsOwned

env.__declared.UpdateAssistedCombatRotationFrame = true
env.__declared.UpdateAllAssistedHighlights = true
env.__declared.ResetButtonChargeCapabilityCache = true
env.__declared.ResetAllChargeCapabilityCaches = true
env.__declared.IsButtonInsideVisibleLayout = true
env.__declared.MarkSpellIdMapDirty = true
env.__declared.ScheduleUsabilityUpdate = true

ActionBarsOwned.mirrorButtons = ActionBarsOwned.nativeButtons

ActionBarsOwned._activeButtons = ActionBarsOwned._activeButtons
    or setmetatable({}, { __mode = "k" })
ActionBarsOwned._activeStandardButtons = ActionBarsOwned._activeStandardButtons
    or setmetatable({}, { __mode = "k" })

local function SetupDebugInstrumentation()
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = {
        name = "AB_activeButtons",
        fn = function()
            local count = 0
            for _ in pairs(ActionBarsOwned._activeButtons) do count = count + 1 end
            return count, 0
        end,
    }
    mp[#mp + 1] = {
        name = "AB_activeStandardButtons",
        fn = function()
            local count = 0
            for _ in pairs(ActionBarsOwned._activeStandardButtons) do count = count + 1 end
            return count, 0
        end,
    }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

env.__declared.UpdateButtonProfessionQuality = true
env.__declared.SafeHasAction = true
env.__declared.HasButtonContent = true

function ActionBarsOwned.SafeUpdate(self)
    local action = self.action
    if not action then return end
    local hasAction = SafeHasAction(action)
    local hasContent = hasAction or (self.GetAttribute and self:GetAttribute("gse-button"))

    if hasContent then
        if not InCombatLockdown() and hasAction then
            local flyoutID
            local actionType, actionID, subType = GetActionInfo(action)
            if actionType == "flyout" then
                flyoutID = actionID or subType
            end
            local prevFlyoutID = self:GetAttribute("qui-flyout-id")
            self:SetAttribute("qui-flyout-id", flyoutID)
            if prevFlyoutID and prevFlyoutID ~= flyoutID then
                local popup = _G.QUI_SpellFlyout
                if popup and popup:IsShown()
                    and popup:GetParent() == self
                    and ActionBarsOwned.HideOwnedFlyout then
                    ActionBarsOwned.HideOwnedFlyout()
                end
            end
        end

        local barKey = self._quiBarKey
        local visibleInLayout = not IsButtonInsideVisibleLayout or IsButtonInsideVisibleLayout(self, barKey)
        if visibleInLayout then
            ActionBarsOwned._activeButtons[self] = true
        else
            ActionBarsOwned._activeButtons[self] = nil
        end
        if visibleInLayout and STANDARD_BAR_KEY_SET[barKey] then
            ActionBarsOwned._activeStandardButtons[self] = true
        else
            ActionBarsOwned._activeStandardButtons[self] = nil
        end
        local gseSeq = self:GetAttribute("gse-button")
        local texture
        if gseSeq then
            if _G.QUI_GetGSEButtonIcon then
                texture = _G.QUI_GetGSEButtonIcon(self)
            end
            if not texture and GetMacroIndexByName then
                local idx = GetMacroIndexByName(gseSeq)
                if idx and idx > 0 then
                    local _, macTex = GetMacroInfo(idx)
                    local logoIcon = _G.GSE and _G.GSE.Static
                        and _G.GSE.Static.Icons and _G.GSE.Static.Icons.GSE_Logo_Dark
                    if macTex and macTex ~= logoIcon then
                        texture = macTex
                    end
                end
            end
        else
            texture = GetActionTexture(action)
        end
        if texture then
            self.icon:SetTexture(texture)
            self.icon:Show()
            if self.SlotBackground then self.SlotBackground:Hide() end
        else
            self.icon:Hide()
            if self.SlotBackground then self.SlotBackground:Show() end
        end

        UpdateButtonProfessionQuality(self)

        self:SetAlpha(1.0)

        if hasAction and (IsCurrentAction(action) or IsAutoRepeatAction(action)) then
            self:SetChecked(true)
        else
            self:SetChecked(false)
        end

        self.icon:SetVertexColor(1, 1, 1)

        if hasAction and IsEquippedAction(action) then
            self.Border:SetVertexColor(0, 1, 0, 0.35)
            self.Border:Show()
        else
            self.Border:Hide()
        end

        if hasAction then
            self.Name:SetText(GetActionText(action) or "")
        else
            self.Name:SetText("")
        end

        self:UpdateCount()
        ActionBarsOwned.UpdateCooldown(self)

        ActionBarsOwned.UpdateOverlayGlow(self)

        ns.SafeCallMethodIfPresent("best-effort-style", self, "UpdateFlyout")

        if hasAction
            and C_ActionBar and C_ActionBar.IsAssistedCombatAction
            and C_ActionBar.IsAssistedCombatAction(action) then
            ActionBarsOwned._assistedCombatEverActive = true
        end
        UpdateAssistedCombatRotationFrame(self)

        if hasAction and self.LevelLinkLockIcon and C_LevelLink and C_LevelLink.IsActionLocked then
            if C_LevelLink.IsActionLocked(action) then
                self.icon:SetDesaturated(true)
                self.LevelLinkLockIcon:SetShown(true)
            else
                self.icon:SetDesaturated(false)
                self.LevelLinkLockIcon:SetShown(false)
            end
        end

        local shouldFlash = hasAction and (
            (IsAttackAction(action) and IsCurrentAction(action))
            or IsAutoRepeatAction(action)
        )
        if shouldFlash then
            if self.flashing ~= 1 then
                ns.SafeCallMethodIfPresent("best-effort-style", self, "StartFlash")
            end
        else
            if self.flashing == 1 then
                ns.SafeCallMethodIfPresent("best-effort-style", self, "StopFlash")
            end
        end
    else
        if not InCombatLockdown() then
            local prevFlyoutID = self:GetAttribute("qui-flyout-id")
            self:SetAttribute("qui-flyout-id", nil)
            if prevFlyoutID then
                local popup = _G.QUI_SpellFlyout
                if popup and popup:IsShown()
                    and popup:GetParent() == self
                    and ActionBarsOwned.HideOwnedFlyout then
                    ActionBarsOwned.HideOwnedFlyout()
                end
            end
        end
        ActionBarsOwned._activeButtons[self] = nil
        ActionBarsOwned._activeStandardButtons[self] = nil
        self.icon:Hide()
        if self.SlotBackground then self.SlotBackground:Show() end
        self:SetChecked(false)
        self.cooldown:Hide()
        self.Count:SetText("")
        self.Name:SetText("")
        self.Border:Hide()
        UpdateButtonProfessionQuality(self)
        if self.LevelLinkLockIcon then
            self.LevelLinkLockIcon:SetShown(false)
        end
        if self.flashing == 1 then
            ns.SafeCallMethodIfPresent("best-effort-style", self, "StopFlash")
        end
        ns.SafeCallMethodIfPresent("best-effort-style", self, "UpdateFlyout")
        UpdateAssistedCombatRotationFrame(self)
        ActionBarsOwned.UpdateOverlayGlow(self)
    end
end

hiddenBarParent = CreateFrame("Frame")
hiddenBarParent:Hide()

---@type fun(...)
noop = function() end

function PurgeShownExternalTaint(frame)
    if not frame or not frame.system then return end

    frame.isShownExternal = nil
    local c = 42
    repeat
        if frame[c] == nil then
            frame[c] = nil
        end
        c = c + 1
    until issecurevariable(frame, "isShownExternal")
end

function HideManagedBlizzardBarFrame(frame, clearEvents)
    if not frame then return end

    if clearEvents then
        frame:UnregisterAllEvents()
    end

    PurgeShownExternalTaint(frame)

    frame:SetParent(hiddenBarParent)
    if frame.HideBase then
        frame:HideBase()
    else
        frame:Hide()
    end
end

function SuppressBlizzardButton(btn)
    btn:Hide()
    btn:UnregisterAllEvents()
    btn:SetAttribute("statehidden", true)
end

env.__declared.LayoutNativeButtons = true

function ReclaimBarButtons(barKey)
    local btns = ActionBarsOwned.nativeButtons[barKey]
    local cont = ActionBarsOwned.containers[barKey]
    if not btns or not cont then return end
    for _, btn in ipairs(btns) do
        if btn:GetParent() ~= cont then
            btn:SetParent(cont)
        end
    end
    LayoutNativeButtons(barKey)
end

layoutHandler = CreateFrame("Frame", "QUI_ActionBarLayoutHandler", UIParent, "SecureHandlerAttributeTemplate")

layoutHandler:SetAttribute("_onattributechanged", [=[
    if name ~= "do-layout" then return end
    local barKey = self:GetAttribute("layout-target")
    if not barKey then return end

    local prefix = "bl-" .. barKey
    local count  = self:GetAttribute(prefix .. "-count") or 0
    local anchor = self:GetAttribute(prefix .. "-anchor") or "TOPLEFT"
    local scale  = tonumber(self:GetAttribute(prefix .. "-scale")) or 1
    local cw     = tonumber(self:GetAttribute(prefix .. "-cw"))
    local ch     = tonumber(self:GetAttribute(prefix .. "-ch"))
    local barRef = self:GetFrameRef("bar-" .. barKey)
    if not barRef then return end

    if cw and ch then
        barRef:SetScale(1)
        barRef:SetWidth(cw)
        barRef:SetHeight(ch)
    end

    for i = 1, count do
        local btnRef = self:GetFrameRef("btn-" .. barKey .. "-" .. i)
        if btnRef then
            local data = self:GetAttribute(prefix .. "-" .. i)
            if data then
                local x, y, show = strsplit("|", data)
                btnRef:SetScale(scale)
                btnRef:ClearAllPoints()
                btnRef:SetPoint(anchor, barRef, anchor, tonumber(x) or 0, tonumber(y) or 0)
                if show == "1" then
                    btnRef:Show()
                else
                    btnRef:Hide()
                end
            end
        end
    end
]=])

function SecureLayoutBar(barKey, buttons, numVisible, anchor, btnScale, positions, groupWidth, groupHeight)
    local prefix = "bl-" .. barKey
    layoutHandler:SetAttribute(prefix .. "-count", #buttons)
    layoutHandler:SetAttribute(prefix .. "-anchor", anchor)
    layoutHandler:SetAttribute(prefix .. "-scale", btnScale)
    layoutHandler:SetAttribute(prefix .. "-cw", groupWidth)
    layoutHandler:SetAttribute(prefix .. "-ch", groupHeight)

    for i = 1, #buttons do
        if i <= numVisible then
            local pos = positions[i]
            layoutHandler:SetAttribute(prefix .. "-" .. i, pos.x .. "|" .. pos.y .. "|1")
        else
            layoutHandler:SetAttribute(prefix .. "-" .. i, "0|0|0")
        end
    end

    layoutHandler:SetAttribute("layout-target", barKey)
    layoutHandler:SetAttribute("do-layout", GetTime())
end

env.__declared.SkinButton = true
env.__declared.UpdateButtonText = true
env.__declared.UpdateEmptySlotVisibility = true
env.__declared.UpdateKeybindText = true
env.__declared.FadeHideTextures = true
env.__declared.FadeShowTextures = true
env.__declared.ApplyAllBarSpacing = true
env.__declared.ApplyFlyoutDirection = true
env.__declared.ApplyAllFlyoutDirections = true

frameState, GetFrameState = Helpers.CreateStateTable()
