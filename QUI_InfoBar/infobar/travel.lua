--- QUI Info Bar — travel widget: a secure hearthstone button in the slot
--- plus a hover flyout of owned M+ dungeon-teleport spells.
---
--- Secure rules honored here:
---  * Secure attributes are written only at attach time or in the hover
---    path's lazy flyout rebuild — both gated out of combat. The info bar
---    host attaches out of combat by contract; for other hosts a regen
---    guard defers the secure build to PLAYER_REGEN_ENABLED.
---  * The flyout is a SecureHandlerStateTemplate frame that self-hides on
---    combat entry via a state driver + `_onstate-combat` snippet (state
---    driver values arrive as the STRINGS "true"/"false").
---  * All insecure Show/Hide of the protected flyout are gated on
---    `not InCombatLockdown()`.
---  * The flyout is strata-locked (SetFixedFrameStrata) so reparenting
---    can't sink it behind other UI (strata follows parent otherwise).

local _, ns = ...
local QUICore = ns.Addon
local Datatexts = QUICore and QUICore.Datatexts
if not Datatexts then return end

local max = math.max
local ipairs = ipairs

local HEARTHSTONE_ITEM_ID = 6948

-- M+ dungeon teleports — Midnight Season 1 rotation.
-- Runtime-filtered by IsSpellKnown (no local spell DB exists to cross-check
-- the IDs against): unknown/invalid IDs simply never render a row.
local TELEPORT_SPELLS = {
    { 1254572, "Magisters' Terrace" },
    { 1254559, "Maisara Caverns" },
    { 1254563, "Nexus-Point Xenas" },
    { 1254400, "Windrunner Spire" },
    { 393273,  "Algeth'ar Academy" },
    { 1254551, "Seat of the Triumvirate" },
    { 159898,  "Skyreach" },          -- original teleport spell
    { 1254557, "Skyreach" },          -- reissued teleport spell
    { 1254555, "Pit of Saron" },
}

-- Hearthstone-effect toys for the random-hearth option. Item IDs are
-- runtime-filtered with PlayerHasToy, so stale entries are harmless.
local HEARTH_TOYS = {
    54452,   -- Ethereal Portal
    64488,   -- The Innkeeper's Daughter
    93672,   -- Dark Portal
    142542,  -- Tome of Town Portal
    162973,  -- Greatfather Winter's Hearthstone
    163045,  -- Headless Horseman's Hearthstone
    165669,  -- Lunar Elder's Hearthstone
    165670,  -- Peddlefeet's Lovely Hearthstone
    165802,  -- Noble Gardener's Hearthstone
    166746,  -- Fire Eater's Hearthstone
    166747,  -- Brewfest Reveler's Hearthstone
    168907,  -- Holographic Digitalization Hearthstone
    172179,  -- Eternal Traveler's Hearthstone
    180290,  -- Night Fae Hearthstone
    182773,  -- Necrolord Hearthstone
    183716,  -- Venthyr Sinstone
    184353,  -- Kyrian Hearthstone
    188952,  -- Dominated Hearthstone
    190196,  -- Enlightened Hearthstone
    190237,  -- Broker Translocation Matrix
    193588,  -- Timewalker's Hearthstone
    200630,  -- Ohn'ir Windsage's Hearthstone
    206195,  -- Path of the Naaru
    208704,  -- Deepdweller's Earthen Hearthstone
    209035,  -- Hearthstone of the Flame
    212337,  -- Stone of the Hearth
    228940,  -- Notorious Thread's Hearthstone
}

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local ROW_WIDTH, ROW_HEIGHT = 180, 20

-- WoW globals (upvalued from _G so the file lints identically under the
-- repo-root and worktree luacheck configs, like providers_extra.lua)
local PlayerHasToy = _G.PlayerHasToy
local C_ToyBox = _G.C_ToyBox

local function GetTravelDB()
    local db = QUICore.db and QUICore.db.profile
    return db and db.infobar
end

-- Picks the hearth action for the secure button. Returns
-- attrType, attrValue, icon, displayName; attrType ("toy"/"item") doubles
-- as the secure attribute name the value is written under.
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
            -- Snapshot semantics: the random hearth toy is rolled once per
            -- attach (widget rebuild), not per click.
            local itemID = owned[math.random(#owned)]
            local _, toyName, icon = C_ToyBox.GetToyInfo(itemID)
            return "toy", itemID,
                icon or FALLBACK_ICON, toyName or "Hearthstone"
        end
    end
    -- Plain hearthstone. If the player lacks item 6948 the secure use
    -- simply no-ops (acceptable).
    local icon = C_Item.GetItemIconByID(HEARTHSTONE_ITEM_ID)
    local name = C_Item.GetItemNameByID(HEARTHSTONE_ITEM_ID)
    return "item", "item:" .. HEARTHSTONE_ITEM_ID,
        icon or FALLBACK_ICON, name or "Hearthstone"
end

-- Grace-period hide shared by all leave handlers: hide 0.3s after the
-- pointer leaves unless it moved onto the hearth button or the flyout.
local function ScheduleFlyoutHide(frame)
    C_Timer.After(0.3, function()
        local flyout, hearth = frame._flyout, frame._hearth
        if not flyout or not flyout:IsShown() then return end
        if (hearth and hearth:IsMouseOver()) or flyout:IsMouseOver() then return end
        if InCombatLockdown() then return end  -- secure driver owns combat hide
        flyout:Hide()
    end)
end

local function BuildFlyout(frame, slotFrame)
    local flyout = CreateFrame("Frame", nil, frame, "SecureHandlerStateTemplate")
    frame._flyout = flyout

    -- Strata-inheritance landmine: lock the strata or the flyout renders
    -- at the host bar's level and gets clipped/overlapped.
    flyout:SetFrameStrata("DIALOG")
    if flyout.SetFixedFrameStrata then
        flyout:SetFixedFrameStrata(true)
    end

    -- Self-hide on combat entry, securely (insecure Hide is blocked then).
    -- Driver values arrive as strings.
    flyout:SetAttribute("_onstate-combat", [[
        if newstate == "true" then
            self:Hide()
        end
    ]])
    RegisterStateDriver(flyout, "combat", "[combat] true; false")

    local bg = flyout:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.9)

    -- One secure spell row per KNOWN teleport. Built from an IsSpellKnown
    -- snapshot at build time; LEARNED_SPELL_IN_SKILL_LINE (OnEnable) marks
    -- the flyout dirty and ShowFlyout rebuilds it on the next hover, so
    -- teleports learned mid-session appear without a settings/profile rebuild.
    local rows = 0
    for _, entry in ipairs(TELEPORT_SPELLS) do
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

    -- Above or below the slot depending on which screen edge the bar hugs.
    local db = GetTravelDB()
    if db and db.position == "BOTTOM" then
        flyout:SetPoint("BOTTOMLEFT", slotFrame, "TOPLEFT", 0, 2)
    else
        flyout:SetPoint("TOPLEFT", slotFrame, "BOTTOMLEFT", 0, -2)
    end

    flyout:SetScript("OnLeave", function() ScheduleFlyoutHide(frame) end)
    flyout:Hide()
end

-- Defined after BuildFlyout: the dirty path below re-runs it. Out of combat
-- here by the gate, so dropping and recreating the protected flyout (secure
-- attribute writes included) is allowed by construction.
local function ShowFlyout(frame)
    local flyout = frame._flyout
    if not flyout or InCombatLockdown() then return end
    if frame._flyoutDirty then
        -- A spell was learned since the last build (the event is not
        -- teleport-filtered): rebuild lazily on hover (the learn event only
        -- sets the flag). The old flyout's rows are abandoned with it —
        -- rebuilds are hover-gated and bounded by spell learns.
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
        -- Flyout first: the tooltip anchor depends on whether it shows
        -- (and the dirty path can rebuild frame._flyout — re-read after).
        ShowFlyout(frame)
        local flyout = frame._flyout
        if flyout and flyout:IsShown() then
            -- At ANCHOR_BOTTOM the tooltip covers the flyout's top rows
            -- (both hang off the slot's bottom edge). Stack it past the
            -- flyout's far edge instead — button → portal list → tooltip —
            -- mirroring the flyout's own above/below edge choice. Anchoring
            -- the insecure tooltip TO the protected flyout is taint-safe
            -- (only repositioning protected frames is not).
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

        -- The shared slot.text payload stays empty (it anchors hard-left, over
        -- the icon); this widget draws its own "Travel" label to the icon's
        -- right instead.
        if slotFrame.text then slotFrame.text:SetText("") end

        local size = max((slotFrame:GetHeight() or 0) - 6, 12)

        -- "Travel" label, honoring the per-slot No Label toggle. Built insecure
        -- in OnEnable (not the deferred secure path) so the slot width is right
        -- immediately. Inherits the slot's current font/size/outline.
        local gap = 4
        local label = frame:CreateFontString(nil, "OVERLAY")
        if slotFrame.text then
            -- Keep the multi-return intact: an `and` short-circuit would
            -- truncate GetFont to one value and pass nil height/flags to SetFont.
            local fp, fs, fl = slotFrame.text:GetFont()
            if fp then
                if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
                    ns.Helpers.ApplyFontWithFallback(label, fp, fs, fl)
                else
                    label:SetFont(fp, fs, fl)
                end
            end
        end
        -- travel draws its own label (not the shared slot.text the central
        -- Hide Text wrapper strips), so honor both toggles here: No Label and
        -- the icon-only Hide Text both blank the word and reclaim its width.
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

        -- LEARNED_SPELL_IN_SKILL_LINE is the precise "player learned a spell"
        -- signal (Blizzard's spellbook drives its new-spell glow off it);
        -- SPELLS_CHANGED also fires on zoning/spec swaps and is deliberately
        -- NOT registered. The handler only sets a flag — ShowFlyout rebuilds
        -- lazily on the next hover, which is gated not-InCombatLockdown, so
        -- the secure rebuild stays out of combat by construction.
        frame:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
        frame:SetScript("OnEvent", function(self, event)
            if event == "LEARNED_SPELL_IN_SKILL_LINE" then
                self._flyoutDirty = true
            elseif event == "PLAYER_REGEN_ENABLED" then
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                if not self._hearth then
                    BuildSecureWidgets(self, slotFrame, size)
                end
            end
        end)

        -- The info bar host attaches out of combat by contract; other hosts
        -- may not — defer the secure build to the regen window if needed.
        if InCombatLockdown() then
            frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            BuildSecureWidgets(frame, slotFrame, size)
        end

        return frame
    end,

    OnDisable = function(frame)
        if not frame then return end
        -- Also cancels a still-pending deferred secure BUILD from OnEnable
        -- (must stay before any re-registration below).
        frame:UnregisterAllEvents()
        frame:SetScript("OnEvent", nil)
        if frame._slot then
            frame._slot._quiFixedWidth = nil
            -- Tell the host the width changed now (combat-safe: the host's
            -- reflow defers itself in combat) instead of waiting a ticker.
            if frame._slot._quiOnWidthDirty then frame._slot._quiOnWidthDirty() end
        end
        if frame._flyout then
            if InCombatLockdown() then
                -- Driver unregister + insecure Hide are blocked on the
                -- protected flyout in combat; mirror OnEnable's defer-build
                -- pattern and finish at regen (no leak on in-combat detach).
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
