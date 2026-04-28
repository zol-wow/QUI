--[[
    QUI Help Content — Data Tables
    All help text lives here, separate from the UI builders.
    Exported as ns.QUI_HelpContent for use by help.lua and contextual help blocks.
]]

local ADDON_NAME, ns = ...

local QUI_HelpContent = {}
local AssetPath = ns.Helpers.AssetPath

---------------------------------------------------------------------------
-- GETTING STARTED
---------------------------------------------------------------------------
QUI_HelpContent.GettingStarted = {
    {num = "1.", text = "Open |cff60A5FA/qui|r to access the options panel and explore available modules."},
    {num = "2.", text = "Import the QUI Edit Mode layout string from the |cff60A5FAWelcome|r tab into Blizzard Edit Mode to set up default frame positions."},
    {num = "3.", text = "Import a QUI profile from the |cff60A5FAImport & Export Strings|r tab for a recommended starting layout, then |cff60A5FA/rl|r to apply."},
    {num = "4.", text = "Customize individual modules — unit frames, action bars, cooldowns, and more — from their respective tabs."},
    {num = "5.", text = "Use |cff60A5FA/kb|r to set up keybinds by hovering over action buttons and pressing a key."},
    {num = "6.", text = "Fine-tune element positions with |cff60A5FA/qui layout|r (Layout Mode) or the |cff60A5FAFrame Positioning|r tab."},
}

---------------------------------------------------------------------------
-- SLASH COMMANDS
---------------------------------------------------------------------------
QUI_HelpContent.SlashCommands = {
    {command = "/qui",          description = "Open the QUI options panel"},
    {command = "/kb",           description = "Open the keybind overlay — hover a button and press a key to bind it"},
    {command = "/cdm",          description = "Open Cooldown Manager settings (Blizzard's CooldownViewer panel)"},
    {command = "/rl",           description = "Reload the UI — applies changes and resets frame state"},
    {command = "/qui debug",    description = "Toggle debug mode — enables verbose logging for one session"},
    {command = "/qui layout",   description = "Open Layout Mode — drag to reposition all QUI frames"},
    {command = "/qui editmode", description = "Alias for /qui layout (backward compatibility)"},
    {command = "/pull <sec>",   description = "Start a pull timer countdown (requires BigWigs or DBM)"},
}

---------------------------------------------------------------------------
-- FEATURE GUIDES
---------------------------------------------------------------------------
QUI_HelpContent.FeatureGuides = {
    {
        title = "Unit Frames",
        description = "QUI replaces the default player, target, focus, party, and raid frames with custom-styled versions. Each unit type can be configured independently with health/power bars, name text, portraits, and aura displays.",
        tips = {
            "Set all Blizzard Edit Mode frame sizes to 100% for best results with QUI skinning.",
            "Aura filtering, icon size, and layout are configured per unit in the Unit Frames tab.",
            "Party and raid frames support class colors, role icons, and incoming heal predictions.",
            "Use the Frame Positioning tab to fine-tune frame positions relative to each other.",
        },
    },
    {
        title = "Cooldown Manager (CDM)",
        description = "The Cooldown Manager displays your ability cooldowns as icon bars near your character. It integrates with Blizzard's CooldownViewer system and adds custom tracking, glow effects, and swipe overlays.",
        tips = {
            "Use |cff60A5FA/cdm|r to open the Blizzard Cooldown Settings panel for viewer layout.",
            "Custom CDM entries let you track specific spells or items not in the default list.",
            "Glow effects highlight abilities when they proc — configure styles in the CDM tab.",
            "The CDM swipe overlay shows remaining cooldown time visually on each icon.",
        },
    },
    {
        title = "Action Bars",
        description = "QUI styles and customizes your action bars with consistent appearance, keybind text, and optional per-bar overrides for size, spacing, and visibility.",
        tips = {
            "Per-bar overrides let you style individual bars differently from the global settings.",
            "Keybind text font, size, and color are configurable for better readability.",
            "Action bar macro text can be shown or hidden independently of keybind text.",
            "Bar visibility settings respect combat state — some bars can auto-show in combat.",
        },
    },
    {
        title = "Custom CDM Bars",
        description = "Track specific spells, items, or buffs with custom CDM bars. Each bar can monitor multiple spells and display cooldown/duration information with customizable appearance.",
        tips = {
            "Create custom CDM bars in the Custom CDM Bars tab — each bar can track multiple spells.",
            "Custom CDM bars support both cooldown tracking and buff/debuff duration monitoring.",
            "Import and export bar configurations via the Import & Export Strings tab.",
            "Bars update in real time and respect spec-specific spell availability.",
        },
    },
    {
        title = "Frame Positioning",
        description = "The anchoring system lets you position QUI elements relative to each other or to screen anchor points. This provides pixel-perfect control over your UI layout without needing Blizzard Edit Mode.",
        tips = {
            "Each element can be anchored to another element or to a screen corner/edge.",
            "Use the Nudge tool for fine-grained pixel adjustments to any anchored element.",
            "Anchoring respects the pixel-perfect scaling system for crisp edges at any resolution.",
            "Reset an element's position by clearing its anchor in the Frame Positioning tab.",
        },
    },
    {
        title = "Skinning & Autohide",
        description = "QUI skins many Blizzard frames to match the addon's visual style. The autohide system lets you hide specific UI elements (like gryphons, XP bar, or micro menu) to clean up your screen.",
        tips = {
            "Skinning is cosmetic-only — it doesn't change frame behavior or functionality.",
            "Autohide settings take effect immediately — no reload needed for most elements.",
            "The HUD Visibility section controls which elements show in and out of combat.",
            "Frame Levels (strata) can be adjusted if elements overlap unexpectedly.",
        },
    },
    {
        title = "Minimap & Datatexts",
        description = "QUI styles the minimap with custom borders and shape options, and provides data text panels that display useful information like FPS, latency, gold, and more.",
        tips = {
            "Data panels can be positioned independently using the anchoring system.",
            "Each data text module can be enabled or disabled individually.",
            "Minimap button collection helps declutter the minimap edge.",
            "Right-click data text modules for additional options where available.",
        },
    },
    {
        title = "Quality of Life",
        description = "QUI includes many small quality-of-life improvements: auto-repair, auto-sell junk, improved tooltips, chat enhancements, a crosshair overlay, skyriding helpers, and more.",
        tips = {
            "Most QoL features can be toggled individually in the Quality of Life tile.",
            "Tooltip enhancements include class-colored names, spell IDs, and an optional player item level line on player tooltips.",
            "The combat timer shows elapsed encounter time during boss fights.",
            "Chat improvements include link copying, URL detection, and timestamp formatting.",
        },
    },
}

---------------------------------------------------------------------------
-- TROUBLESHOOTING
---------------------------------------------------------------------------
QUI_HelpContent.Troubleshooting = {
    {
        question = "My frames disappeared or look broken after an update",
        answer = "Try importing the QUI Edit Mode layout string from the Welcome tab, then /rl. If frames are still missing, check for Lua errors with /console scriptErrors 1 and report them on GitHub or Discord.",
    },
    {
        question = "I'm getting 'secret value' or 'forbidden table' errors",
        answer = "These are related to WoW 12.0's combat security system. Most are harmless and self-correct after combat ends. If they persist out of combat, update to the latest QUI version or report the specific error on GitHub.",
    },
    {
        question = "Settings didn't apply after changing them",
        answer = "Some settings require a UI reload to take effect. Most profile switches should apply live; use /rl only when a specific setting asks for it or combat blocked protected updates.",
    },
    {
        question = "My keybinds aren't showing on action bars",
        answer = "Open /kb to enter keybind mode, then hover each button and press the desired key. Check the Cooldown Manager tab for keybind display settings (font, size, visibility).",
    },
    {
        question = "The Cooldown Manager icons aren't appearing",
        answer = "Open /cdm to configure which cooldowns are tracked. Make sure the Cooldown Manager is enabled in the CDM tab. After combat, icons should auto-recover if they were disrupted by combat restrictions.",
    },
    {
        question = "QUI conflicts with another addon",
        answer = "QUI is designed to work alongside other addons, but conflicts can occur with addons that modify the same frames. Try disabling the conflicting addon to isolate the issue, then report it on GitHub with both addon names.",
    },
    {
        question = "How do I reset everything to defaults?",
        answer = "Go to the Profiles tab and click 'Reset Profile' to restore default settings for the current profile. For a complete reset, delete the QUI saved variables (WTF folder) and /rl.",
    },
}

---------------------------------------------------------------------------
-- DIAGNOSTICS (Troubleshooting sub-tab buttons)
---------------------------------------------------------------------------
-- Each entry:
--   label    = button text
--   command  = slash form shown in tooltip + capture header
--   tooltip  = body text shown on hover
--   run      = closure invoked under DiagnosticsConsole.Run
--   danger   = optional; true => red border + confirmation modal
QUI_HelpContent.Diagnostics = {
    -- General
    { label = "Reload UI",            command = "/rl",
      tooltip = "Reload the UI safely. If you're in combat, the reload defers until combat ends.",
      run = function() QUI:SafeReload() end },
    { label = "Toggle Debug",         command = "/qui debug",
      tooltip = "Toggle QUI debug mode for one session. Persists across one /reload, then resets to off.",
      run = function() QUI:SlashCommandOpen("debug") end },
    { label = "Layout Mode",          command = "/qui layout",
      tooltip = "Toggle QUI's Layout Mode for repositioning every QUI frame. Click again to exit.",
      run = function() QUI:SlashCommandOpen("layout") end },
    { label = "Performance Monitor",  command = "/qui perf",
      tooltip = "Toggle the QUI performance monitor overlay. Useful when investigating frame-rate hitches.",
      run = function() QUI:SlashCommandOpen("perf") end },
    { label = "Open Keybind Mode",    command = "/kb",
      tooltip = "Open the keybind overlay. Hover an action button and press a key to bind it.",
      run = function() if SlashCmdList and SlashCmdList["QUIKB"] then SlashCmdList["QUIKB"]() end end },
    -- CDM
    { label = "Open CDM Settings",    command = "/cdm",
      tooltip = "Toggle Blizzard's CooldownViewer Settings panel.",
      run = function() if SlashCmdList and SlashCmdList["QUI_CDM"] then SlashCmdList["QUI_CDM"]() end end },
    { label = "Open CDM Composer",    command = "/qui cdm",
      tooltip = "Open the QUI CDM Spell Composer for editing custom CDM tracking entries.",
      run = function() QUI:SlashCommandOpen("cdm") end },
    { label = "CDM Cache Status",     command = "/qui cdm_cache status",
      tooltip = "Print sizes and dirty flags for every CDM internal cache. Use first when CDM seems stuck.",
      run = function() QUI:SlashCommandOpen("cdm_cache status") end },
    { label = "CDM Cache Reset",      command = "/qui cdm_cache reset",
      tooltip = "Wipe and rebuild every CDM cache. Out-of-combat only. Run when /qui cdm_cache status reports stale state.",
      danger = true,
      run = function() QUI:SlashCommandOpen("cdm_cache reset") end },
    -- Migrations & profiles
    { label = "Migration Status",     command = "/qui migration status",
      tooltip = "Print the active profile's schema version and any available rollback slots.",
      run = function() QUI:SlashCommandOpen("migration status") end },
    { label = "Migration Restore Newest", command = "/qui migration restore 1",
      tooltip = "Roll the active profile back to the most recent migration backup. Reloads the UI on success.",
      danger = true,
      run = function() QUI:SlashCommandOpen("migration restore 1") end },
    { label = "Migration Log",        command = "/qui miglog",
      tooltip = "Dump the buffered migration debug log. Enable buffering with /run QUI_MIGRATION_DEBUG = true then /reload before the run you want to capture.",
      run = function() QUI:SlashCommandOpen("miglog") end },
    { label = "Migration Log Clear",  command = "/qui miglog clear",
      tooltip = "Empty the migration debug log buffer.",
      danger = true,
      run = function() QUI:SlashCommandOpen("miglog clear") end },
    { label = "Anchor Dump",          command = "/qui anchordump",
      tooltip = "Print frame-anchoring state (saved data + live frame positions) for the active profile.",
      run = function() QUI:SlashCommandOpen("anchordump") end },
    -- Tooltip debugging
    { label = "Tooltip Debug On",     command = "/qui tooltipdebug on",
      tooltip = "Begin sampling tooltip processing churn every 1 second. Use Tooltip Debug Report to read samples. To log slow callers, type /qui tooltipdebug slow N in chat (N = millisecond threshold).",
      run = function() QUI:SlashCommandOpen("tooltipdebug on") end },
    { label = "Tooltip Debug Report", command = "/qui tooltipdebug report",
      tooltip = "Print the most recent tooltip-debug sample without resetting it.",
      run = function() QUI:SlashCommandOpen("tooltipdebug report") end },
    { label = "Tooltip Bypass: QoL",  command = "/qui tooltipdebug bypass qol",
      tooltip = "Isolate tooltip processors: bypass QoL hooks only. Use when diagnosing which addon owns a tooltip stall.",
      run = function() QUI:SlashCommandOpen("tooltipdebug bypass qol") end },
    { label = "Tooltip Bypass: Skin", command = "/qui tooltipdebug bypass skin",
      tooltip = "Isolate tooltip processors: bypass Skin hooks only.",
      run = function() QUI:SlashCommandOpen("tooltipdebug bypass skin") end },
    { label = "Tooltip Bypass: All",  command = "/qui tooltipdebug bypass all",
      tooltip = "Isolate tooltip processors: bypass both QoL and Skin hooks (vanilla tooltip path).",
      run = function() QUI:SlashCommandOpen("tooltipdebug bypass all") end },
    { label = "Tooltip Bypass: Off",  command = "/qui tooltipdebug bypass off",
      tooltip = "Restore default tooltip processing (clear any active bypass).",
      run = function() QUI:SlashCommandOpen("tooltipdebug bypass off") end },
    { label = "White-Backdrop Scan",  command = "/qui tooltipdbg",
      tooltip = "Scan every visible frame and report any with explicit white backdrops or visible NineSlices. Useful when a stray white panel appears mid-screen.",
      run = function() QUI:SlashCommandOpen("tooltipdbg") end },
    -- Edit Mode diagnostic
    { label = "Diagnose Edit Mode",   command = "/qui diagnose",
      tooltip = "Report Edit Mode state and the most recent ADDON_ACTION_BLOCKED events. Run after a frame-positioning action that didn't take effect.",
      run = function() QUI:SlashCommandOpen("diagnose") end },
    { label = "Diagnose Clear",       command = "/qui diagnose clear",
      tooltip = "Empty the Edit Mode diagnostic ring buffer.",
      run = function() QUI:SlashCommandOpen("diagnose clear") end },
    -- Memory & GSE
    { label = "Memory Audit Help",    command = "/qui memaudit",
      tooltip = "Print memory audit usage. Power forms (alloc N, dump foo bar) stay in chat — type them directly.",
      run = function() QUI:SlashCommandOpen("memaudit") end },
    { label = "GSE Dump",             command = "/qui gse",
      tooltip = "Dump current GSE compatibility-shim override state.",
      run = function() QUI:SlashCommandOpen("gse") end },
    { label = "GSE Toggle Debug",     command = "/qui gse debug",
      tooltip = "Toggle GSE click-event logging on or off.",
      run = function() QUI:SlashCommandOpen("gse debug") end },
    { label = "GSE Tail (last 20)",   command = "/qui gse tail 20",
      tooltip = "Print the last 20 entries from the GSE log.",
      run = function() QUI:SlashCommandOpen("gse tail 20") end },
    -- Recovery
    { label = "Legacy Tracker Recovery", command = "/qui legacyrecover",
      tooltip = "Show usage for the legacy tracker resolver. To recover a specific tracker, type /qui legacyrecover <handle> in chat.",
      run = function() QUI:SlashCommandOpen("legacyrecover") end },
}

---------------------------------------------------------------------------
-- LINKS
---------------------------------------------------------------------------
QUI_HelpContent.Links = {
    {
        label = "|cff5865F2Discord|r",
        url = "https://discord.gg/FFUjA4JXnH",
        iconR = 0.345, iconG = 0.396, iconB = 0.949,
        iconTexture = AssetPath .. "discord",
        popupTitle = "Copy Discord Invite",
    },
    {
        label = "|cffF0F6FCGitHub|r",
        url = "https://github.com/zol-wow/QUI",
        iconR = 0.941, iconG = 0.965, iconB = 0.988,
        iconTexture = AssetPath .. "github",
        popupTitle = "Copy GitHub URL",
    },
    {
        label = "|cffF16436CurseForge|r",
        url = "https://www.curseforge.com/wow/addons/qui",
        iconR = 0.945, iconG = 0.392, iconB = 0.212,
        popupTitle = "Copy CurseForge URL",
    },
}

---------------------------------------------------------------------------
-- EXPORT
---------------------------------------------------------------------------
ns.QUI_HelpContent = QUI_HelpContent
