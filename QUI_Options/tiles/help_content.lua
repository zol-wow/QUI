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
    {num = "1.", text = ns.L["Open |cff60A5FA/qui|r to access the options panel and explore available modules."]},
    {num = "2.", text = ns.L["Import the QUI Edit Mode layout string from the |cff60A5FAWelcome|r tab into Blizzard Edit Mode to set up default frame positions."]},
    {num = "3.", text = ns.L["Import a QUI profile from the |cff60A5FAImport & Export Strings|r tab for a recommended starting layout, then |cff60A5FA/rl|r to apply."]},
    {num = "4.", text = ns.L["Customize individual modules — unit frames, action bars, cooldowns, and more — from their respective tabs."]},
    {num = "5.", text = ns.L["Use |cff60A5FA/kb|r to set up keybinds by hovering over action buttons and pressing a key."]},
    {num = "6.", text = ns.L["Fine-tune element positions with |cff60A5FA/qui layout|r (Layout Mode) or the |cff60A5FAFrame Positioning|r tab."]},
}

---------------------------------------------------------------------------
-- SLASH COMMANDS
---------------------------------------------------------------------------
QUI_HelpContent.SlashCommands = {
    {command = "/qui",          description = ns.L["Open the QUI options panel"]},
    {command = "/kb",           description = ns.L["Open the keybind overlay — hover a button and press a key to bind it"]},
    {command = "/cdm",          description = ns.L["Open Cooldown Manager settings (Blizzard's CooldownViewer panel)"]},
    {command = "/rl",           description = ns.L["Reload the UI — applies changes and resets frame state"]},
    {command = "/qui debug",    description = ns.L["Toggle debug mode — enables verbose logging for one session"]},
    {command = "/qui layout",   description = ns.L["Open Layout Mode — drag to reposition all QUI frames"]},
    {command = "/qui editmode", description = ns.L["Alias for /qui layout (backward compatibility)"]},
    {command = "/pull <sec>",   description = ns.L["Start a pull timer countdown (requires BigWigs or DBM)"]},
}

---------------------------------------------------------------------------
-- FEATURE GUIDES
---------------------------------------------------------------------------
QUI_HelpContent.FeatureGuides = {
    {
        title = ns.L["Unit Frames"],
        description = ns.L["QUI replaces the default player, target, focus, party, and raid frames with custom-styled versions. Each unit type can be configured independently with health/power bars, name text, portraits, and aura displays."],
        tips = {
            ns.L["Set all Blizzard Edit Mode frame sizes to 100% for best results with QUI skinning."],
            ns.L["Aura filtering, icon size, and layout are configured per unit in the Unit Frames tab."],
            ns.L["Party and raid frames support class colors, role icons, and incoming heal predictions."],
            ns.L["Use the Frame Positioning tab to fine-tune frame positions relative to each other."],
        },
    },
    {
        title = ns.L["Group Frames"],
        description = ns.L["QUI Group Frames provide separate party and raid layouts with class colors, role icons, heal prediction, range fading, aura elements, click-casting, castbars, pet frames, and targeted spell warnings."],
        tips = {
            ns.L["Use Group Frames > Auras > Targeted Spells to show enemy nameplate casts on the group members being targeted."],
            ns.L["Use Add Missing Raid Buff in the Auras element list to show icons only when a player is missing Arcane Intellect, Fortitude, Battle Shout, Mark of the Wild, Skyfury, or Blessing of the Bronze."],
            ns.L["Leave Auto-Detect My Buff enabled to track the raid buff your current class can provide; turn it off to choose individual buffs manually."],
            ns.L["Party and raid frames have separate settings, so verify both contexts when tuning alerts."],
        },
    },
    {
        title = ns.L["Cooldown Manager (CDM)"],
        description = ns.L["The Cooldown Manager displays your ability cooldowns as icon bars near your character. It integrates with Blizzard's CooldownViewer system and adds custom tracking, glow effects, and swipe overlays."],
        tips = {
            ns.L["Use |cff60A5FA/cdm|r to open the Blizzard Cooldown Settings panel for viewer layout."],
            ns.L["Custom CDM entries let you track specific spells or items not in the default list."],
            ns.L["Glow effects highlight abilities when they proc — configure styles in the CDM tab."],
            ns.L["The CDM swipe overlay shows remaining cooldown time visually on each icon."],
        },
    },
    {
        title = ns.L["Action Bars"],
        description = ns.L["QUI styles and customizes your action bars with consistent appearance, keybind text, and optional per-bar overrides for size, spacing, and visibility."],
        tips = {
            ns.L["Per-bar overrides let you style individual bars differently from the global settings."],
            ns.L["Keybind text font, size, and color are configurable for better readability."],
            ns.L["Action bar macro text can be shown or hidden independently of keybind text."],
            ns.L["Bar visibility settings respect combat state — some bars can auto-show in combat."],
        },
    },
    {
        title = ns.L["Custom CDM Bars"],
        description = ns.L["Track specific spells, items, or buffs with custom CDM bars. Each bar can monitor multiple spells and display cooldown/duration information with customizable appearance."],
        tips = {
            ns.L["Create custom CDM bars in the Custom CDM Bars tab — each bar can track multiple spells."],
            ns.L["Custom CDM bars support both cooldown tracking and buff/debuff duration monitoring."],
            ns.L["Import and export bar configurations via the Import & Export Strings tab."],
            ns.L["Bars update in real time and respect spec-specific spell availability."],
        },
    },
    {
        title = ns.L["Frame Positioning"],
        description = ns.L["The anchoring system lets you position QUI elements relative to each other or to screen anchor points. This provides pixel-perfect control over your UI layout without needing Blizzard Edit Mode."],
        tips = {
            ns.L["Each element can be anchored to another element or to a screen corner/edge."],
            ns.L["Use the Nudge tool for fine-grained pixel adjustments to any anchored element."],
            ns.L["Anchoring respects the pixel-perfect scaling system for crisp edges at any resolution."],
            ns.L["Reset an element's position by clearing its anchor in the Frame Positioning tab."],
        },
    },
    {
        title = ns.L["Skinning & Autohide"],
        description = ns.L["QUI skins many Blizzard frames to match the addon's visual style. The autohide system lets you hide specific UI elements (like gryphons, XP bar, or micro menu) to clean up your screen."],
        tips = {
            ns.L["Skinning is cosmetic-only — it doesn't change frame behavior or functionality."],
            ns.L["Autohide settings take effect immediately — no reload needed for most elements."],
            ns.L["The HUD Visibility section controls which elements show in and out of combat."],
            ns.L["Frame Levels (strata) can be adjusted if elements overlap unexpectedly."],
        },
    },
    {
        title = ns.L["Minimap & Datatexts"],
        description = ns.L["QUI styles the minimap with custom borders and shape options, and provides data text panels that display useful information like FPS, latency, gold, and more."],
        tips = {
            ns.L["Data panels can be positioned independently using the anchoring system."],
            ns.L["Each data text module can be enabled or disabled individually."],
            ns.L["Minimap button collection helps declutter the minimap edge."],
            ns.L["Right-click data text modules for additional options where available."],
        },
    },
    {
        title = ns.L["Quality of Life"],
        description = ns.L["QUI includes many small quality-of-life improvements: auto-repair, auto-sell junk, improved tooltips, chat enhancements, a crosshair overlay, skyriding helpers, and more."],
        tips = {
            ns.L["Most QoL features can be toggled individually in the Quality of Life tile."],
            ns.L["Tooltip enhancements include class-colored names, spell IDs, and an optional player item level line on player tooltips."],
            ns.L["The combat timer shows elapsed encounter time during boss fights."],
            ns.L["Chat improvements include link copying, URL detection, and timestamp formatting."],
        },
    },
}

---------------------------------------------------------------------------
-- TROUBLESHOOTING
---------------------------------------------------------------------------
QUI_HelpContent.Troubleshooting = {
    {
        question = ns.L["My frames disappeared or look broken after an update"],
        answer = ns.L["Try importing the QUI Edit Mode layout string from the Welcome tab, then /rl. If frames are still missing, check for Lua errors with /console scriptErrors 1 and report them on GitHub or Discord."],
    },
    {
        question = ns.L["I'm getting 'secret value' or 'forbidden table' errors"],
        answer = ns.L["These are related to WoW 12.0's combat security system. Most are harmless and self-correct after combat ends. If they persist out of combat, update to the latest QUI version or report the specific error on GitHub."],
    },
    {
        question = ns.L["Settings didn't apply after changing them"],
        answer = ns.L["Some settings require a UI reload to take effect. Most profile switches should apply live; use /rl only when a specific setting asks for it or combat blocked protected updates."],
    },
    {
        question = ns.L["My keybinds aren't showing on action bars"],
        answer = ns.L["Open /kb to enter keybind mode, then hover each button and press the desired key. Check the Cooldown Manager tab for keybind display settings (font, size, visibility)."],
    },
    {
        question = ns.L["The Cooldown Manager icons aren't appearing"],
        answer = ns.L["Open /cdm to configure which cooldowns are tracked. Make sure the Cooldown Manager is enabled in the CDM tab. After combat, icons should auto-recover if they were disrupted by combat restrictions."],
    },
    {
        question = ns.L["QUI conflicts with another addon"],
        answer = ns.L["QUI is designed to work alongside other addons, but conflicts can occur with addons that modify the same frames. Try disabling the conflicting addon to isolate the issue, then report it on GitHub with both addon names."],
    },
    {
        question = ns.L["How do I reset everything to defaults?"],
        answer = ns.L["Go to the Profiles tab and click 'Reset Profile' to restore default settings for the current profile. For a complete reset, delete the QUI saved variables (WTF folder) and /rl."],
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
    { label = ns.L["Reload UI"],            command = "/rl",
      tooltip = ns.L["Reload the UI safely. If you're in combat, the reload defers until combat ends."],
      run = function() QUI:SafeReload() end },
    { label = ns.L["Toggle Debug"],         command = "/qui debug",
      tooltip = ns.L["Toggle QUI debug mode for one session. Persists across one /reload, then resets to off."],
      run = function() QUI:SlashCommandOpen("debug") end },
    { label = ns.L["Layout Mode"],          command = "/qui layout",
      tooltip = ns.L["Toggle QUI's Layout Mode for repositioning every QUI frame. Click again to exit."],
      run = function() QUI:SlashCommandOpen("layout") end },
    { label = ns.L["Performance Monitor"],  command = "/qui perf",
      tooltip = ns.L["Toggle the QUI performance monitor overlay. Useful when investigating frame-rate hitches."],
      run = function() QUI:SlashCommandOpen("perf") end },
    { label = ns.L["Open Keybind Mode"],    command = "/kb",
      tooltip = ns.L["Open the keybind overlay. Hover an action button and press a key to bind it."],
      run = function() if SlashCmdList and SlashCmdList["QUIKB"] then SlashCmdList["QUIKB"]() end end },
    -- CDM
    { label = ns.L["Open CDM Settings"],    command = "/cdm",
      tooltip = ns.L["Toggle Blizzard's CooldownViewer Settings panel."],
      run = function() if SlashCmdList and SlashCmdList["QUI_CDM"] then SlashCmdList["QUI_CDM"]() end end },
    { label = ns.L["Open CDM Composer"],    command = "/qui cdm",
      tooltip = ns.L["Open the QUI CDM Spell Composer for editing custom CDM tracking entries."],
      run = function() QUI:SlashCommandOpen("cdm") end },
    { label = ns.L["CDM Cache Status"],     command = "/qui cdm_cache status",
      tooltip = ns.L["Print sizes and dirty flags for every CDM internal cache. Use first when CDM seems stuck."],
      run = function() QUI:SlashCommandOpen("cdm_cache status") end },
    { label = ns.L["CDM Cache Reset"],      command = "/qui cdm_cache reset",
      tooltip = ns.L["Wipe and rebuild every CDM cache. Out-of-combat only. Run when /qui cdm_cache status reports stale state."],
      danger = true,
      run = function() QUI:SlashCommandOpen("cdm_cache reset") end },
    -- Migrations & profiles
    { label = ns.L["Migration Status"],     command = "/qui migration status",
      tooltip = ns.L["Print the active profile's schema version and any available rollback slots."],
      run = function() QUI:SlashCommandOpen("migration status") end },
    { label = ns.L["Migration Restore Newest"], command = "/qui migration restore 1",
      tooltip = ns.L["Roll the active profile back to the most recent migration backup. Reloads the UI on success."],
      danger = true,
      run = function() QUI:SlashCommandOpen("migration restore 1") end },
    { label = ns.L["Migration Log"],        command = "/qui miglog",
      tooltip = ns.L["Dump the buffered migration debug log. Enable buffering with /run QUI_MIGRATION_DEBUG = true then /reload before the run you want to capture."],
      run = function() QUI:SlashCommandOpen("miglog") end },
    { label = ns.L["Migration Log Clear"],  command = "/qui miglog clear",
      tooltip = ns.L["Empty the migration debug log buffer."],
      danger = true,
      run = function() QUI:SlashCommandOpen("miglog clear") end },
    { label = ns.L["Anchor Dump"],          command = "/qui anchordump",
      tooltip = ns.L["Print frame-anchoring state (saved data + live frame positions) for the active profile."],
      run = function() QUI:SlashCommandOpen("anchordump") end },
    -- Tooltip debugging
    { label = ns.L["Tooltip Debug On"],     command = "/qui tooltipdebug on",
      tooltip = ns.L["Begin sampling tooltip processing churn every 1 second. Use Tooltip Debug Report to read samples. To log slow callers, type /qui tooltipdebug slow N in chat (N = millisecond threshold)."],
      run = function() QUI:SlashCommandOpen("tooltipdebug on") end },
    { label = ns.L["Tooltip Debug Report"], command = "/qui tooltipdebug report",
      tooltip = ns.L["Print the most recent tooltip-debug sample without resetting it."],
      run = function() QUI:SlashCommandOpen("tooltipdebug report") end },
    { label = ns.L["Tooltip Bypass: QoL"],  command = "/qui tooltipdebug bypass qol",
      tooltip = ns.L["Isolate tooltip processors: bypass QoL hooks only. Use when diagnosing which addon owns a tooltip stall."],
      run = function() QUI:SlashCommandOpen("tooltipdebug bypass qol") end },
    { label = ns.L["Tooltip Bypass: Skin"], command = "/qui tooltipdebug bypass skin",
      tooltip = ns.L["Isolate tooltip processors: bypass Skin hooks only."],
      run = function() QUI:SlashCommandOpen("tooltipdebug bypass skin") end },
    { label = ns.L["Tooltip Bypass: All"],  command = "/qui tooltipdebug bypass all",
      tooltip = ns.L["Isolate tooltip processors: bypass both QoL and Skin hooks (vanilla tooltip path)."],
      run = function() QUI:SlashCommandOpen("tooltipdebug bypass all") end },
    { label = ns.L["Tooltip Bypass: Off"],  command = "/qui tooltipdebug bypass off",
      tooltip = ns.L["Restore default tooltip processing (clear any active bypass)."],
      run = function() QUI:SlashCommandOpen("tooltipdebug bypass off") end },
    { label = ns.L["White-Backdrop Scan"],  command = "/qui tooltipdbg",
      tooltip = ns.L["Scan every visible frame and report any with explicit white backdrops or visible NineSlices. Useful when a stray white panel appears mid-screen."],
      run = function() QUI:SlashCommandOpen("tooltipdbg") end },
    -- Edit Mode diagnostic
    { label = ns.L["Diagnose Edit Mode"],   command = "/qui diagnose",
      tooltip = ns.L["Report Edit Mode state and the most recent ADDON_ACTION_BLOCKED events. Run after a frame-positioning action that didn't take effect."],
      run = function() QUI:SlashCommandOpen("diagnose") end },
    { label = ns.L["Diagnose Clear"],       command = "/qui diagnose clear",
      tooltip = ns.L["Empty the Edit Mode diagnostic ring buffer."],
      run = function() QUI:SlashCommandOpen("diagnose clear") end },
    -- Combat-end profiler
    { label = ns.L["Combat Profiler On"],   command = "/qui combatprof on",
      tooltip = ns.L["Start profiling the PLAYER_REGEN_ENABLED handler chain. Wraps named CDM functions plus every frame in QUI_PerfRegistry (CDM, group frames, action bars, raid buffs, aura dispatch, plus skinning combat-defer frames) and prints a summary 2.5s after each combat ends. Use to diagnose combat-end stutter."],
      run = function() QUI:SlashCommandOpen("combatprof on") end },
    { label = ns.L["Combat Profiler Off"],  command = "/qui combatprof off",
      tooltip = ns.L["Stop the combat-end profiler and unwrap functions."],
      run = function() QUI:SlashCommandOpen("combatprof off") end },
    { label = ns.L["Combat Profiler Report"], command = "/qui combatprof report",
      tooltip = ns.L["Reprint the most recent combat-end report."],
      run = function() QUI:SlashCommandOpen("combatprof report") end },
    { label = ns.L["Combat Profiler Reset"], command = "/qui combatprof reset",
      tooltip = ns.L["Clear the combat-end profiler's accumulated stats."],
      run = function() QUI:SlashCommandOpen("combatprof reset") end },
    -- Memory & GSE
    { label = ns.L["Memory Audit Help"],    command = "/qui memaudit",
      tooltip = ns.L["Print memory audit usage. Power forms (alloc N, dump foo bar) stay in chat — type them directly."],
      run = function() QUI:SlashCommandOpen("memaudit") end },
    { label = ns.L["GSE Dump"],             command = "/qui gse",
      tooltip = ns.L["Dump current GSE compatibility-shim override state."],
      run = function() QUI:SlashCommandOpen("gse") end },
    { label = ns.L["GSE Toggle Debug"],     command = "/qui gse debug",
      tooltip = ns.L["Toggle GSE click-event logging on or off."],
      run = function() QUI:SlashCommandOpen("gse debug") end },
    { label = ns.L["GSE Tail (last 20)"],   command = "/qui gse tail 20",
      tooltip = ns.L["Print the last 20 entries from the GSE log."],
      run = function() QUI:SlashCommandOpen("gse tail 20") end },
}

---------------------------------------------------------------------------
-- LINKS
---------------------------------------------------------------------------
QUI_HelpContent.Links = {
    {
        label = ns.L["|cff5865F2Discord|r"],
        url = "https://discord.gg/FFUjA4JXnH",
        iconR = 0.345, iconG = 0.396, iconB = 0.949,
        iconTexture = AssetPath .. "discord",
        popupTitle = ns.L["Copy Discord Invite"],
    },
    {
        label = ns.L["|cffF0F6FCGitHub|r"],
        url = "https://github.com/zol-wow/QUI",
        iconR = 0.941, iconG = 0.965, iconB = 0.988,
        iconTexture = AssetPath .. "github",
        popupTitle = ns.L["Copy GitHub URL"],
    },
    {
        label = ns.L["|cffF16436CurseForge|r"],
        url = "https://www.curseforge.com/wow/addons/qui",
        iconR = 0.945, iconG = 0.392, iconB = 0.212,
        popupTitle = ns.L["Copy CurseForge URL"],
    },
}

---------------------------------------------------------------------------
-- EXPORT
---------------------------------------------------------------------------
ns.QUI_HelpContent = QUI_HelpContent
