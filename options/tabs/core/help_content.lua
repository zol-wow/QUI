--[[
    QUI Help Content — Data Tables
    All help text lives here, separate from the UI builders.
    Exported as ns.QUI_HelpContent for use by help.lua and contextual help blocks.
]]

local ADDON_NAME, ns = ...

local QUI_HelpContent = {}

---------------------------------------------------------------------------
-- GETTING STARTED
---------------------------------------------------------------------------
QUI_HelpContent.GettingStarted = {
    {num = "1.", text = "Open |cff34D399/qui|r to access the options panel and explore available modules."},
    {num = "2.", text = "Import the QUI Edit Mode layout string from the |cff34D399Welcome|r tab into Blizzard Edit Mode to set up default frame positions."},
    {num = "3.", text = "Import a QUI profile from the |cff34D399Import & Export Strings|r tab for a recommended starting layout, then |cff34D399/rl|r to apply."},
    {num = "4.", text = "Customize individual modules — unit frames, action bars, cooldowns, and more — from their respective tabs."},
    {num = "5.", text = "Use |cff34D399/kb|r to set up keybinds by hovering over action buttons and pressing a key."},
    {num = "6.", text = "Fine-tune element positions with the |cff34D399Anchoring & Layout|r tab or Blizzard Edit Mode (|cff34D399/qui editmode|r)."},
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
    {command = "/qui editmode", description = "Open Blizzard Edit Mode for repositioning default frames"},
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
            "Use the Anchoring & Layout tab to fine-tune frame positions relative to each other.",
        },
    },
    {
        title = "Cooldown Manager (CDM)",
        description = "The Cooldown Manager displays your ability cooldowns as icon bars near your character. It integrates with Blizzard's CooldownViewer system and adds custom tracking, glow effects, and swipe overlays.",
        tips = {
            "Use |cff34D399/cdm|r to open the Blizzard Cooldown Settings panel for viewer layout.",
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
        title = "Custom Trackers",
        description = "Track specific spells, items, or buffs with custom bar-style trackers. Each tracker bar can monitor multiple spells and display cooldown/duration information with customizable appearance.",
        tips = {
            "Create tracker bars in the Custom Trackers tab — each bar can track multiple spells.",
            "Tracker bars support both cooldown tracking and buff/debuff duration monitoring.",
            "Import and export tracker bar configurations via the Import & Export Strings tab.",
            "Trackers update in real time and respect spec-specific spell availability.",
        },
    },
    {
        title = "Anchoring & Layout",
        description = "The anchoring system lets you position QUI elements relative to each other or to screen anchor points. This provides pixel-perfect control over your UI layout without needing Blizzard Edit Mode.",
        tips = {
            "Each element can be anchored to another element or to a screen corner/edge.",
            "Use the Nudge tool for fine-grained pixel adjustments to any anchored element.",
            "Anchoring respects the pixel-perfect scaling system for crisp edges at any resolution.",
            "Reset an element's position by clearing its anchor in the Anchoring & Layout tab.",
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
            "Most QoL features can be toggled individually in the General & QoL tab.",
            "Tooltip enhancements add item level, spec, and other useful data to mouseover tooltips.",
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
        answer = "Some settings require a UI reload to take effect. Type /rl or /reload to apply pending changes. Profile switches always require a reload.",
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
-- LINKS
---------------------------------------------------------------------------
QUI_HelpContent.Links = {
    {
        label = "|cff5865F2Discord|r",
        url = "https://discord.gg/FFUjA4JXnH",
        iconR = 0.345, iconG = 0.396, iconB = 0.949,
        iconTexture = "Interface\\AddOns\\QUI\\assets\\discord",
        popupTitle = "Copy Discord Invite",
    },
    {
        label = "|cffF0F6FCGitHub|r",
        url = "https://github.com/zol-wow/QUI",
        iconR = 0.941, iconG = 0.965, iconB = 0.988,
        iconTexture = "Interface\\AddOns\\QUI\\assets\\github",
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
-- CONTEXTUAL HELP (keyed by tab name for per-tab help blocks)
---------------------------------------------------------------------------
QUI_HelpContent.ContextualHelp = {
    ["Cooldown Manager"] = "Configure which abilities appear in your cooldown bars, adjust glow effects, and customize the swipe overlay. Use /cdm to open Blizzard's viewer layout settings.",
    ["Unit Frames"] = "Customize player, target, focus, party, and raid frames. Set Blizzard Edit Mode frame sizes to 100% for best results. Use Anchoring & Layout for fine positioning.",
    ["Action Bars"] = "Style your action bars with consistent appearance. Per-bar overrides let you customize individual bars. Keybind display settings are in the Cooldown Manager tab.",
    ["Anchoring & Layout"] = "Position QUI elements relative to each other or screen edges. Use the Nudge tool for pixel-perfect adjustments. Clear an anchor to reset an element's position.",
    ["Custom Trackers"] = "Create tracker bars to monitor specific spells, items, or buffs. Each bar supports multiple spells and shows cooldown or duration info. Import/export via the strings tab.",
    ["Skinning & Autohide"] = "Control which Blizzard frames are skinned and which UI elements are hidden. Most changes apply immediately without a reload.",
}

---------------------------------------------------------------------------
-- EXPORT
---------------------------------------------------------------------------
ns.QUI_HelpContent = QUI_HelpContent
