--[[
    QUI Troubleshooting Page
    --------------------------------------------------------------
    Renders the second sub-page of the Help tile: a flat grid of
    diagnostic command buttons above a captured-output console.
    Data lives in ns.QUI_HelpContent.Diagnostics.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local HelpContent = ns.QUI_HelpContent
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
local Console = ns.DiagnosticsConsole

local CreateWrappedLabel = Shared.CreateWrappedLabel
local PADDING = Shared.PADDING or 15
local SECTION_LABEL_GAP = 30

local function BuildTroubleshootingContent(content)
    local y = -10
    local contentWidth = 700

    -- Set tileId + subPageIndex (V2 route) and tabName/subTabName (display).
    -- Deliberately omit tabIndex: that's the legacy V1 routing key, and the
    -- value 13 is already mapped in _navMap to the General tile. Setting
    -- it would make ResolveSearchNavigation prefer the General route over
    -- our explicit tileId, putting "General > Profiles" in the breadcrumb.
    GUI:SetSearchContext({
        tabName      = "Help",
        subTabName   = "Tools",
        tileId       = "help",
        subPageIndex = 2,
    })

    -- Header
    local title = CreateWrappedLabel(content, "Tools & Diagnostics",
        20, C.accent, contentWidth)
    title:SetPoint("TOPLEFT", PADDING, y)
    y = y - 28

    local subtitle = CreateWrappedLabel(content,
        "Direct access to QUI's slash-command diagnostics. Output mirrors to chat. Hover any button for details.",
        12, C.textMuted, contentWidth - PADDING * 2)
    subtitle:SetPoint("TOPLEFT", PADDING, y)
    y = y - (subtitle:GetStringHeight() or 14) - 6

    local disclaimer = CreateWrappedLabel(content,
        "|cffE15D5DButtons with red borders are destructive and require confirmation.|r",
        11, C.textMuted, contentWidth - PADDING * 2)
    disclaimer:SetPoint("TOPLEFT", PADDING, y)
    y = y - (disclaimer:GetStringHeight() or 14) - 18

    -- Grid section
    Shared.CreateAccentDotLabel(content, "Diagnostic Commands", y)
    y = y - SECTION_LABEL_GAP

    local entries = (HelpContent and HelpContent.Diagnostics) or {}

    local grid = CreateFrame("Frame", nil, content)
    grid:SetPoint("TOPLEFT", PADDING, y)
    grid:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)

    local function OnDiagClick(entry)
        local function runIt()
            Console.Run(entry.command, entry.run)
        end
        if entry.danger then
            GUI:ShowConfirmation({
                title         = "Run " .. entry.command .. "?",
                message       = "This will run a destructive diagnostic command.",
                warningText   = "This cannot be undone.",
                acceptText    = entry.label,
                cancelText    = "Cancel",
                onAccept      = runIt,
                isDestructive = true,
            })
        else
            runIt()
        end
    end

    local GAP_X, GAP_Y = 6, 6
    local BTN_H = 26
    local MIN_W = 110

    -- Build all buttons up front; remember each one's natural (text-derived)
    -- width so layout can re-stretch from the same baseline on resize.
    local buttons = {}
    for _, entry in ipairs(entries) do
        local btn = GUI:CreateButton(grid, entry.label, 0, BTN_H,
            function() OnDiagClick(entry) end, "ghost")

        local natW = btn:GetWidth() or MIN_W
        if natW < MIN_W then natW = MIN_W end
        btn._natW = natW
        btn:SetWidth(natW)

        if entry.danger and btn.SetBorderColor then
            btn:SetBorderColor(0.95, 0.45, 0.45, 1)
        end
        GUI:AttachTooltip(btn, entry.tooltip, entry.label)

        -- Register this button with the search index so the global
        -- "Search settings" box can land users on this sub-page when
        -- they query a button label, the slash command, or any tooltip
        -- term. The slash command is added as a keyword so queries like
        -- "cdm cache" match `/qui cdm_cache status` even though the
        -- visible label is "CDM Cache Status" with no "cache" hit on
        -- its own.
        if GUI.RegisterSearchSettingWidget then
            GUI:RegisterSearchSettingWidget({
                label       = entry.label,
                widgetType  = "button",
                description = entry.tooltip,
                keywords    = { entry.command },
            })
        end

        buttons[#buttons + 1] = btn
    end

    -- Reflow grid: split into rows by natural width, then justify each row
    -- to the live grid width by distributing the leftover space evenly
    -- across its buttons. Re-runs on grid size change so window resize
    -- reflows. Layout is single-shot per call (guard against re-entry from
    -- our own SetHeight triggering OnSizeChanged again).
    local layingOut = false
    local function LayoutGrid()
        if layingOut then return end
        local availableWidth = grid:GetWidth() or 0
        if availableWidth <= 0 then return end
        layingOut = true

        local rows = {}
        local current = nil
        for _, btn in ipairs(buttons) do
            if not current then
                current = { buttons = { btn }, totalWithGaps = btn._natW }
                rows[#rows + 1] = current
            else
                local newWidth = current.totalWithGaps + GAP_X + btn._natW
                if newWidth > availableWidth then
                    current = { buttons = { btn }, totalWithGaps = btn._natW }
                    rows[#rows + 1] = current
                else
                    current.buttons[#current.buttons + 1] = btn
                    current.totalWithGaps = newWidth
                end
            end
        end

        local rowY = 0
        for _, row in ipairs(rows) do
            local n = #row.buttons
            local extra = math.max(0, availableWidth - row.totalWithGaps)
            local extraPerBtn = math.floor(extra / n)
            local remainder = extra - extraPerBtn * n

            local x = 0
            for i, btn in ipairs(row.buttons) do
                local w = btn._natW + extraPerBtn + (i == n and remainder or 0)
                btn:SetWidth(w)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", grid, "TOPLEFT", x, rowY)
                x = x + w + GAP_X
            end
            rowY = rowY - (BTN_H + GAP_Y)
        end

        local rowsCount = #rows
        local newHeight = rowsCount * BTN_H + math.max(rowsCount - 1, 0) * GAP_Y + 4
        grid:SetHeight(newHeight)

        layingOut = false
    end

    grid:SetScript("OnSizeChanged", LayoutGrid)
    LayoutGrid()
    -- Grid's width may not be resolved yet on the first pass; run again
    -- next frame so it settles after the initial layout.
    C_Timer.After(0, LayoutGrid)

    -- Output section anchors relative to grid bottom so it reflows when
    -- the grid height changes (window resize ⇒ different row count).
    local outLabel = Shared.CreateAccentDotLabel(content, "Diagnostic Output", 0)
    outLabel:ClearAllPoints()
    outLabel:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 0, -18)
    outLabel:SetPoint("TOPRIGHT", grid, "BOTTOMRIGHT", 0, -18)

    local panel = Console.CreateOutputPanel(content)
    panel:SetPoint("TOPLEFT", outLabel, "BOTTOMLEFT", 0, -8)
    panel:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
    panel:SetHeight(320)

    -- Recompute content height after the layout settles so the scroll
    -- frame's range tracks our actual bottom.
    local function RecalcContentHeight()
        C_Timer.After(0, function()
            if not content:GetParent() then return end
            local contentTop = content:GetTop() or 0
            local panelBottom = panel:GetBottom() or 0
            if contentTop > 0 and panelBottom > 0 then
                content:SetHeight(contentTop - panelBottom + 20)
            end
        end)
    end
    grid:HookScript("OnSizeChanged", RecalcContentHeight)
    RecalcContentHeight()
end

local function CreateTroubleshootingPage(parent)
    local _, content = Shared.CreateScrollableContent(parent)
    BuildTroubleshootingContent(content)
end

ns.QUI_TroubleshootingOptions = {
    BuildTroubleshootingContent = BuildTroubleshootingContent,
    CreateTroubleshootingPage   = CreateTroubleshootingPage,
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id        = "troubleshootingPage",
        moverKey  = "help",
        category  = "help",
        nav       = { tileId = "help", subPageIndex = 2 },
        sections  = {
            Schema.Section({
                id        = "settings",
                kind      = "page",
                minHeight = 80,
                build     = BuildTroubleshootingContent,
            }),
        },
    }))
end
