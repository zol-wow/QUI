---------------------------------------------------------------------------
-- QUI Modules Panel — content for the Modules sub-tab under General.
--
-- Renders a grouped, scrollable list of registered module entries with
-- pill toggles, collapsible chevron group headers, and a live
-- enabled-count label.
--
-- Layout: dual-column card rows via CreateSettingsCardGroup.
-- Pill style: 26x14 track with sliding 10x10 knob (accent ON, toggleOff OFF).
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
local UIKit = ns.UIKit

local CreateWrappedLabel = Shared.CreateWrappedLabel
local PADDING = Shared.PADDING or 15

-- Layout constants
local CONTENT_WIDTH   = 680
local GROUP_HDR_H     = 22  -- matches Shared.CreateAccentDotLabel container height
local BOTTOM_PADDING  = 20

-- Y-cursor starting position: just below the counts label (top offset -8,
-- ~16px tall) with a small breathing gap. No search box to account for.
local CONTENT_TOP_Y   = -32

---------------------------------------------------------------------------
-- Helper: live accent color (mirrors layoutmode_ui approach)
---------------------------------------------------------------------------
local function GetAccent()
    if C and C.accent then
        return C.accent[1], C.accent[2], C.accent[3]
    end
    return 0.204, 0.827, 0.6  -- #34D399 fallback
end

---------------------------------------------------------------------------
-- Step 1: CollectVisibleModules
---------------------------------------------------------------------------
local function CollectVisibleModules()
    local groups     = {}   -- groupName -> { {id, entry, label} }
    local groupOrder = {}   -- ordered list of group names (alphabetical)
    local total, enabled = 0, 0

    if not Registry or not Registry._featuresById then
        return groupOrder, groups, total, enabled
    end

    for featureId, spec in pairs(Registry._featuresById) do
        local entry = spec and spec.moduleEntry
        if type(entry) == "table" then
            local hide = entry.hidden
            if type(hide) ~= "function" or not hide() then
                local groupName = type(entry.group) == "string" and entry.group ~= ""
                    and entry.group or "Other"
                local bucket = groups[groupName]
                if not bucket then
                    bucket = {}
                    groups[groupName] = bucket
                    groupOrder[#groupOrder + 1] = groupName
                end
                bucket[#bucket + 1] = {
                    id    = featureId,
                    entry = entry,
                    label = entry.label or spec.name or featureId,
                }
                total = total + 1
                if type(entry.isEnabled) == "function" and entry.isEnabled() then
                    enabled = enabled + 1
                end
            end
        end
    end

    table.sort(groupOrder)
    for _, name in ipairs(groupOrder) do
        table.sort(groups[name], function(a, b)
            local ao = a.entry.order or 1000
            local bo = b.entry.order or 1000
            if ao ~= bo then return ao < bo end
            return a.label < b.label
        end)
    end

    return groupOrder, groups, total, enabled
end

---------------------------------------------------------------------------
-- Step 2: CreateModuleTogglePill
--
-- Standard pill style: 26x14 track with 10x10 sliding knob.
-- Accent color when ON, C.toggleOff when OFF. Hover boost +0.06 alpha.
-- Subscribes to ns.QUI_Modules:Subscribe so external state changes refresh
-- the visual. Does NOT call NotifyChanged — the module's setEnabled does.
---------------------------------------------------------------------------
local function CreateModuleTogglePill(parent, featureId, entry)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(26, 14)

    local track = btn:CreateTexture(nil, "ARTWORK")
    track:SetAllPoints(btn)
    track:SetColorTexture(C.toggleOff[1], C.toggleOff[2], C.toggleOff[3], C.toggleOff[4])

    local trackMask = btn:CreateMaskTexture()
    trackMask:SetTexture(ns.Helpers.AssetPath .. "pill_mask",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    trackMask:SetAllPoints(track)
    track:AddMaskTexture(trackMask)

    local knob = btn:CreateTexture(nil, "OVERLAY")
    knob:SetSize(10, 10)
    knob:SetColorTexture(C.toggleThumb[1], C.toggleThumb[2], C.toggleThumb[3], C.toggleThumb[4])
    knob:ClearAllPoints()
    knob:SetPoint("LEFT", btn, "LEFT", 2, 0)

    local knobMask = btn:CreateMaskTexture()
    knobMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    knobMask:SetAllPoints(knob)
    knob:AddMaskTexture(knobMask)

    local isHovered = false

    local function ApplyVisual()
        local on = type(entry.isEnabled) == "function" and entry.isEnabled() or false
        local locked = entry.combatLocked and InCombatLockdown()
        local hoverBoost = isHovered and 0.06 or 0

        if locked then
            track:SetColorTexture(0.2, 0.2, 0.2, 0.6)
            knob:ClearAllPoints()
            if on then
                knob:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
            else
                knob:SetPoint("LEFT", btn, "LEFT", 2, 0)
            end
            knobMask:SetAllPoints(knob)
            knob:SetVertexColor(0.5, 0.5, 0.5, 1)
            btn._isLocked = true
        else
            knob:SetVertexColor(1, 1, 1, 1)
            if on then
                track:SetColorTexture(C.accent[1], C.accent[2], C.accent[3],
                    math.min(1, (C.accent[4] or 1) + hoverBoost))
                knob:ClearAllPoints()
                knob:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
            else
                track:SetColorTexture(C.toggleOff[1], C.toggleOff[2], C.toggleOff[3],
                    math.min(1, (C.toggleOff[4] or 1) + hoverBoost))
                knob:ClearAllPoints()
                knob:SetPoint("LEFT", btn, "LEFT", 2, 0)
            end
            knobMask:SetAllPoints(knob)
            btn._isLocked = false
        end
    end
    ApplyVisual()

    btn:SetScript("OnClick", function(self)
        if self._isLocked then return end
        if type(entry.setEnabled) == "function" then
            local current = type(entry.isEnabled) == "function" and entry.isEnabled() or false
            entry.setEnabled(not current)
            -- setEnabled is responsible for calling NotifyChanged.
        end
    end)

    btn:SetScript("OnEnter", function(self)
        if self._isLocked then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Cannot change during combat — leave combat to toggle.", 1, 1, 1, 1, true)
            GameTooltip:Show()
            return
        end
        isHovered = true
        ApplyVisual()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
        isHovered = false
        ApplyVisual()
    end)

    local token = ns.QUI_Modules and ns.QUI_Modules:Subscribe(featureId, ApplyVisual)
    btn:SetScript("OnHide", function()
        if token then
            ns.QUI_Modules:Unsubscribe(token)
            token = nil
        end
    end)

    btn._refresh = ApplyVisual
    return btn
end

---------------------------------------------------------------------------
-- BuildModuleCell
--
-- Builds one cell (half of a dual-column card row).  Contains a bold label
-- on the left and the pill toggle anchored to the right.  Caption is NOT
-- shown inline (32px rows are too short for stacked text) but appears as a
-- hover tooltip when present.
---------------------------------------------------------------------------
local function BuildModuleCell(parent, item)
    local cell = CreateFrame("Frame", nil, parent)
    -- AddRow only sets LEFT/RIGHT anchors, so the cell needs an explicit
    -- height — otherwise children collapse onto a 0-px-tall region and
    -- aren't visible. Match the card row height.
    cell:SetHeight(32)

    local entry = item.entry
    local label = item.label

    -- Bold label (left-aligned, right edge leaves room for the 26px pill + 4px gap)
    local nameLabel = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetTextColor(0.953, 0.957, 0.965, 1)
    nameLabel:SetText(label)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetWordWrap(false)
    nameLabel:SetPoint("LEFT", cell, "LEFT", 0, 0)
    nameLabel:SetPoint("RIGHT", cell, "RIGHT", -30, 0)  -- 26px pill + 4px gap

    -- Pill toggle: right edge of cell, vertically centered.
    -- A single RIGHT,y=0 anchor centers vertically by default when the cell
    -- is anchored top-to-bottom by AddRow (no explicit height on the pill's
    -- parent axis means WoW places it at y=0 relative to the frame origin,
    -- which is the vertical center when paired with a RIGHT anchor).
    local pill = CreateModuleTogglePill(cell, item.id, entry)
    pill:SetPoint("RIGHT", cell, "RIGHT", 0, 0)

    -- Hover tooltip exposing the caption (when present)
    if entry.caption and entry.caption ~= "" then
        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(label, 1, 1, 1, 1, true)
            GameTooltip:AddLine(entry.caption, 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    cell._pill       = pill
    cell._nameLabel  = nameLabel
    return cell
end

---------------------------------------------------------------------------
-- RelayoutVisibleRows: shared re-anchor pass used by the group-collapse
-- handler.  Repositions all group headers and their card groups
-- contiguously, then resizes the content frame.
--
-- Both TOPLEFT and TOPRIGHT are set on each header so the accent-dot-label
-- container has a real width and its underline renders full-width.
---------------------------------------------------------------------------
local function RelayoutVisibleRows(content)
    local groupOrder = content._groupOrder or {}

    local y = CONTENT_TOP_Y
    for _, gn in ipairs(groupOrder) do
        local hdr  = content._groupHeaders and content._groupHeaders[gn]
        local card = content._groupCards   and content._groupCards[gn]
        if hdr and hdr:IsShown() then
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, y)
            hdr:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
            y = y - GROUP_HDR_H - 4
        end
        if card and card.frame:IsShown() then
            card.frame:ClearAllPoints()
            card.frame:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, y)
            card.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
            y = y - card.frame:GetHeight() - 8
        end
    end
    content:SetHeight(math.abs(y) + BOTTOM_PADDING)
end

---------------------------------------------------------------------------
-- Step 3 + 4: BuildModulesContent
---------------------------------------------------------------------------
local function BuildModulesContent(content)
    -- Clean up previous wildcard counts subscription if rebuilding.
    if content._countsToken and ns.QUI_Modules then
        ns.QUI_Modules:Unsubscribe(content._countsToken)
        content._countsToken = nil
    end

    -- Reset per-build state tables.
    content._panelRows    = {}
    content._groupHeaders = {}
    content._groupCards   = {}
    content._groupOrder   = {}

    -- Section list lives on the contentBody (us). Wipe it on rebuild so
    -- the section-nav strip doesn't accumulate stale entries from previous
    -- builds. CreateAccentDotLabel re-registers each group fresh below.
    if content._sections then
        -- Don't replace the table — the framework holds a reference. Empty in place.
        for k in pairs(content._sections) do content._sections[k] = nil end
    end

    local groupOrder, groups, total, enabled = CollectVisibleModules()
    -- Stash group order so RelayoutVisibleRows can iterate in the correct order.
    content._groupOrder = groupOrder

    -- ----------------------------------------------------------------
    -- Empty state: zero modules registered
    -- ----------------------------------------------------------------
    if total == 0 then
        local label = CreateWrappedLabel(content,
            "No modules registered yet.\nThis panel will populate as modules are onboarded.",
            12, C.textMuted, 500)
        label:SetPoint("TOP", content, "TOP", 0, -60)
        label:SetJustifyH("CENTER")
        -- Without an explicit height the placeholder is clipped: content
        -- is the scroll-child and its height drives the visible region.
        content:SetHeight(160)
        return
    end

    -- ----------------------------------------------------------------
    -- Step 4: Counts label (top-right)
    -- ----------------------------------------------------------------
    local function CountsText(e, t)
        return string.format("[%d of %d enabled]", e, t)
    end

    local countsLabel = CreateWrappedLabel(content, CountsText(enabled, total),
        11, C.textMuted, 200)
    countsLabel:SetPoint("TOPRIGHT", content, "TOPRIGHT", -12, -8)
    countsLabel:SetJustifyH("RIGHT")

    -- Live-refresh the counts label whenever any module state changes.
    if ns.QUI_Modules then
        content._countsToken = ns.QUI_Modules:Subscribe("*", function()
            local _, _, t2, e2 = CollectVisibleModules()
            countsLabel:SetText(CountsText(e2, t2))
        end)
        -- Unsubscribe when the content frame hides (panel closed / rebuilt).
        content:HookScript("OnHide", function()
            if content._countsToken and ns.QUI_Modules then
                ns.QUI_Modules:Unsubscribe(content._countsToken)
                content._countsToken = nil
            end
        end)
    end

    -- ----------------------------------------------------------------
    -- Rows: group headers + dual-column card groups
    -- ----------------------------------------------------------------
    local yCursor = CONTENT_TOP_Y

    for _, groupName in ipairs(groupOrder) do
        -- ----------------------------------------------------------------
        -- Group header — accent-dot label.  CreateAccentDotLabel walks the
        -- parent chain looking for RegisterSection, so when the sub-page is
        -- mounted with sectionNav = true the group becomes a chip in the
        -- sticky section-nav strip automatically.
        -- ----------------------------------------------------------------
        local header = Shared.CreateAccentDotLabel(content, groupName, yCursor)

        -- Anchor TOPRIGHT as well so the accent-dot underline renders
        -- full-width (TOPLEFT alone leaves the container 0px wide).
        header:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yCursor)

        content._groupHeaders[groupName] = header
        yCursor = yCursor - GROUP_HDR_H - 4

        -- ----------------------------------------------------------------
        -- Card group for this group's modules (dual-column, paired rows)
        -- ----------------------------------------------------------------
        local card = Shared.CreateSettingsCardGroup(content, yCursor)

        local modules = groups[groupName]
        local i = 1
        while i <= #modules do
            local leftItem  = modules[i]
            local rightItem = modules[i + 1]

            -- Attach group name for context
            leftItem.group = groupName
            local leftCell = BuildModuleCell(card.frame, leftItem)

            local rightCell
            if rightItem then
                rightItem.group = groupName
                rightCell = BuildModuleCell(card.frame, rightItem)
            end

            local row = card.AddRow(leftCell, rightCell)

            -- panelRows record for the left cell
            content._panelRows[#content._panelRows + 1] = {
                row      = row,
                cell     = leftCell,
                cellSide = "left",
                group    = groupName,
                entry    = leftItem.entry,
                pill     = leftCell._pill,
            }

            -- panelRows record for the right cell (when present)
            if rightItem and rightCell then
                content._panelRows[#content._panelRows + 1] = {
                    row      = row,
                    cell     = rightCell,
                    cellSide = "right",
                    group    = groupName,
                    entry    = rightItem.entry,
                    pill     = rightCell._pill,
                }
            end

            i = i + 2
        end

        card.Finalize()

        content._groupCards[groupName] = card

        yCursor = yCursor - card.frame:GetHeight() - 8
    end

    -- Set total content height for the scroll frame child.
    content:SetHeight(math.abs(yCursor) + BOTTOM_PADDING)

    -- ----------------------------------------------------------------
    -- Task 7: Combat watcher — grey out combatLocked pills on combat
    -- boundary transitions.  Created only once per content frame (stored
    -- on content._combatWatcher) so repeated BuildModulesContent calls
    -- don't accumulate duplicate listeners.
    -- ----------------------------------------------------------------
    if not content._combatWatcher then
        local combatWatcher = CreateFrame("Frame", nil, content)
        combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
        combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        combatWatcher:SetScript("OnEvent", function()
            for _, rec in ipairs(content._panelRows or {}) do
                if rec.entry.combatLocked and rec.pill and rec.pill._refresh then
                    rec.pill._refresh()
                end
            end
        end)
        content._combatWatcher = combatWatcher

        -- Defensive cleanup: unregister when the panel hides or is rebuilt.
        content:HookScript("OnHide", function()
            if content._combatWatcher then
                content._combatWatcher:UnregisterAllEvents()
                content._combatWatcher:SetScript("OnEvent", nil)
            end
        end)
    end
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
ns.QUI_ModulesPage = {
    BuildModulesContent      = BuildModulesContent,
    CreateModuleTogglePill   = CreateModuleTogglePill,
    CollectVisibleModules    = CollectVisibleModules,
    RelayoutVisibleRows      = RelayoutVisibleRows,
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "modulesPage",
        category = "global",
        nav = { tileId = "global", subPageId = "modules" },
        sections = {
            Schema.Section({
                id = "modulesList",
                kind = "page",
                minHeight = 400,
                build = BuildModulesContent,
            }),
        },
    }))
end
