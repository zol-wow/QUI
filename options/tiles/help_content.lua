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
