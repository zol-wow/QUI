---------------------------------------------------------------------------
-- QUI Database Defaults
-- Default values for AceDB profile, global, and char storage.
-- Extracted from core/main.lua for maintainability.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local defaults = {
    profile = {
        -- General Settings
        general = {
            uiScale = 0.64,  -- Default UI scale for 1440p+ monitors
            font = "Quazii",  -- Default font face
            fontOutline = "OUTLINE",  -- Default font outline: "", "OUTLINE", "THICKOUTLINE"
            texture = "Quazii v5",  -- Default bar texture
            darkMode = false,
            darkModeHealthColor = { 0, 0, 0, 1 },
            darkModeBgColor = { 0.592, 0.592, 0.592, 1 },
            darkModeOpacity = 0.7,
            darkModeHealthOpacity = 0.7,
            darkModeBgOpacity = 0.7,
            masterColorNameText = false,
            masterColorToTText = false,
            masterColorPowerText = false,
            masterColorHealthText = false,
            masterColorCastbarText = false,
            defaultUseClassColor = true,
            defaultHealthColor = { 0.2, 0.2, 0.2, 1 },
            hostilityColorHostile = { 0.8, 0.2, 0.2, 1 },
            hostilityColorNeutral = { 1, 1, 0.2, 1 },
            hostilityColorFriendly = { 0.2, 0.8, 0.2, 1 },
            defaultBgColor = { 0, 0, 0, 1 },
            defaultOpacity = 1.0,
            defaultHealthOpacity = 1.0,
            defaultBgOpacity = 1.0,
            applyGlobalFontToBlizzard = true,  -- Apply font to Blizzard UI elements
            overrideSCTFont = false,  -- Override scrolling combat text font with QUI font
            autoInsertKey = true,  -- Auto-insert keystone in M+ UI
            skinKeystoneFrame = true,  -- Skin keystone insertion window
            skinGameMenu = false,  -- Skin ESC menu (opt-in)
            allowReloadInCombat = false,  -- Allow /reload during combat (bypass SafeReload)
            addQUIButton = false,  -- Add QUI button to ESC menu (opt-in)
            addEditModeButton = true,  -- Add QUI Edit Mode button to ESC menu
            gameMenuFontSize = 12,  -- Game menu button font size
            gameMenuDim = true,  -- Dim background when game menu is open
            skinPowerBarAlt = true,  -- Skin encounter/quest power bar (PlayerPowerBarAlt)
            skinStatusTrackingBars = true,  -- Skin bottom HUD XP / reputation / status tracking bars
            statusTrackingBarsBarColorMode = "accent",  -- blizzard | custom | class | accent
            statusTrackingBarsBarColor = { 0.2, 0.5, 1.0, 1.0 },  -- fill when mode is custom (alpha optional)
            statusTrackingBarsBarHeight = 0,  -- 0 = keep Blizzard default height for slot
            statusTrackingBarsBarWidthPercent = 100,  -- 25-100 (% of Blizzard bar width)
            statusTrackingBarsShowBorder = true,
            statusTrackingBarsBorderThickness = 0,  -- 0 = pixel-perfect edge; else 1-8 px
            statusTrackingBarsShowBarText = true,
            statusTrackingBarsBarTextAlways = false,  -- ignore XP bar text CVar; keep label visible
            statusTrackingBarsBarTextAnchor = "CENTER",  -- LEFT | CENTER | RIGHT
            statusTrackingBarsBarTextColor = { 0.95, 0.95, 0.95, 1 },
            statusTrackingBarsBarTextFont = "__QUI_GLOBAL__",  -- LSM name or __QUI_GLOBAL__
            statusTrackingBarsBarTextFontSize = 11,
            statusTrackingBarsBarTextOutline = "_inherit",  -- _inherit | _none | OUTLINE | THICKOUTLINE
            statusTrackingBarsBarTextOffsetX = 0,
            statusTrackingBarsBarTextOffsetY = 0,
            skinOverrideActionBar = false,  -- Skin override/vehicle action bar (opt-in)
            skinObjectiveTracker = false,  -- Skin objective tracker (opt-in)
            objectiveTrackerClickThrough = false,  -- Make objective tracker click-through
            objectiveTrackerHeight = 600,  -- Objective tracker max height
            objectiveTrackerModuleFontSize = 12,  -- Module headers (QUESTS, ACHIEVEMENTS, etc.)
            objectiveTrackerTitleFontSize = 10,  -- Quest/achievement titles
            objectiveTrackerTextFontSize = 10,  -- Objective text lines
            hideObjectiveTrackerBorder = false,  -- Hide the class-colored border
            objectiveTrackerModuleColor = { 1.0, 0.82, 0.0, 1.0 },  -- Module header color (Blizzard gold)
            objectiveTrackerTitleColor = { 1.0, 1.0, 1.0, 1.0 },  -- Quest title color (white)
            objectiveTrackerTextColor = { 0.8, 0.8, 0.8, 1.0 },  -- Objective text color (light gray)
            skinInstanceFrames = false,  -- Skin PVE/Dungeon/PVP frames (opt-in)
            skinAuctionHouse = false,  -- Skin Auction House frame (opt-in)
            skinCraftingOrders = false,  -- Skin Crafting Orders frame (opt-in)
            skinProfessions = false,  -- Skin Professions frame (opt-in)
            skinBgColor = { 0.008, 0.008, 0.008, 1 },  -- Skinning background color (with alpha)
            skinAlerts = true,  -- Skin alert/toast frames
            skinCharacterFrame = true,  -- Skin Character Frame (Character, Reputation, Currency tabs)
            skinInspectFrame = true,  -- Skin Inspect Frame to match Character Frame
            skinUseClassColor = true,  -- Use class color for skin accents
            -- QoL Automation
            sellJunk = true,
            autoRepair = "personal",      -- "off", "personal", "guild"
            autoRoleAccept = true,
            autoAcceptInvites = "all",    -- "off", "all", "friends", "guild", "both"
            autoAcceptQuest = false,
            autoTurnInQuest = false,
            questHoldShift = true,
            fastAutoLoot = true,
            autoSelectGossip = false,  -- Auto-select single gossip options
            autoCombatLog = false,  -- Auto start/stop combat logging in M+ (opt-in)
            autoCombatLogRaid = false,  -- Auto start/stop combat logging in raids (opt-in)
            autoDeleteConfirm = true,  -- Auto-fill DELETE confirmation text
            auctionHouseExpansionFilter = true,  -- Auto-enable current expansion filter in AH
            craftingOrderExpansionFilter = true,  -- Auto-enable current expansion filter in Crafting Orders
            -- Popup & Toast Blocker (granular, all OFF by default)
            popupBlocker = {
                enabled = false,
                blockTalentMicroButtonAlerts = false, -- Unspent talent/spellbook reminder callouts
                blockEventToasts = false, -- Event toast manager (often campaign/housing news)
                blockMountAlerts = false, -- New mount toasts
                blockPetAlerts = false, -- New pet toasts
                blockToyAlerts = false, -- New toy toasts
                blockCosmeticAlerts = false, -- New cosmetic toasts
                blockWarbandSceneAlerts = false, -- Warband scene toasts (can include housing)
                blockEntitlementAlerts = false, -- Entitlement/RAF delivery toasts
                blockStaticTalentPopups = false, -- StaticPopup dialogs with talent/trait-related IDs
                blockStaticHousingPopups = false, -- StaticPopup dialogs with housing-related IDs
            },
            -- Pet Warning (pet-spec classes: Hunter, Warlock, DK, Mage)
            petCombatWarning = true,    -- Show combat warning in instances when pet missing/passive
            petWarningOffsetX = 0,      -- Warning frame X offset from center
            petWarningOffsetY = -200,   -- Warning frame Y offset from center
            -- Focus Cast Alert (warn when hostile focus is casting and interrupt is ready)
            focusCastAlert = {
                enabled = false,
                text = "Focus is casting. Kick!",
                anchorTo = "screen", -- "screen", "essential", "focus"
                offsetX = 0,
                offsetY = -120,
                font = "", -- empty = global QUI font
                fontSize = 26,
                fontOutline = "OUTLINE", -- "", "OUTLINE", "THICKOUTLINE"
                textColor = {1, 0.2, 0.2, 1},
                useClassColor = false,
            },
            -- Consumable Check (disabled by default)
            consumableCheckEnabled = false,       -- Master toggle
            consumableOnReadyCheck = true,        -- Show on ready check
            consumableOnDungeon = false,          -- Show on dungeon entrance
            consumableOnRaid = false,             -- Show on raid entrance
            consumableOnResurrect = false,        -- Show on instanced resurrect
            consumableFood = true,                -- Track food buff
            consumableFlask = true,               -- Track flask buff
            consumableOilMH = true,               -- Track main hand weapon enchant
            consumableOilOH = true,               -- Track off hand weapon enchant
            consumableRune = true,                -- Track augment rune
            consumableHealthstone = true,         -- Track healthstones (warlock in group)
            consumablePreferredFood = nil,        -- Preferred food item ID
            consumablePreferredFlask = nil,       -- Preferred flask item ID
            consumablePreferredRune = nil,        -- Preferred rune item ID
            consumablePreferredOilMH = nil,       -- Preferred main hand oil item ID
            consumablePreferredOilOH = nil,       -- Preferred off hand oil item ID
            consumableExpirationWarning = false,  -- Warn when buffs expiring
            consumableExpirationThreshold = 300,  -- Seconds before expiration warning
            consumableAnchorMode = true,          -- Anchor to ready check frame
            consumableIconOffset = 5,             -- Icon offset from anchor
            consumableIconSize = 40,              -- Icon size in pixels
            consumableScale = 1,                  -- Frame scale multiplier
            -- Consumable Macro Automation
            consumableMacros = {
                enabled = false,              -- Opt-in, OFF by default
                selectedFlask = "none",       -- Flask type key or "none"
                selectedPotion = "none",      -- Potion type key or "none"
                selectedHealth = "none",      -- Health potion type key or "none"
                selectedHealthstone = "none", -- Healthstone type key or "none"
                selectedAugment = "none",     -- Augment rune type key or "none"
                selectedVantus = "none",      -- Vantus rune type key or "none"
                selectedWeapon = "none",      -- Weapon consumable type key or "none"
                chatNotifications = true,     -- Notify in chat when active item changes
            },
            -- Quick Salvage settings
            quickSalvage = {
                enabled = false,  -- Opt-in, OFF by default
                modifier = "ALT",  -- "ALT", "ALTCTRL", "ALTSHIFT"
            },
            -- M+ Dungeon Teleport
            mplusTeleportEnabled = true,  -- Click-to-teleport on M+ tab icons
            keyTrackerEnabled = true,     -- Show party keys on M+ tab
            keyTrackerFontSize = 9,       -- Font size for key tracker (7-12)
            keyTrackerFont = nil,         -- Font name from LSM (nil = global QUI font "Quazii")
            keyTrackerTextColor = {1, 1, 1, 1},  -- RGBA text color for dungeon/player text
            keyTrackerPoint = "TOPRIGHT",         -- Anchor point on KeyTracker frame
            keyTrackerRelPoint = "BOTTOMRIGHT",   -- Relative point on PVEFrame
            keyTrackerOffsetX = 0,                -- X offset from anchor
            keyTrackerOffsetY = 0,                -- Y offset from anchor
            keyTrackerWidth = 170,                -- Frame width in pixels
        },

        -- Alert & Toast Skinning Settings (enabled via general.skinAlerts)
        alerts = {
            enabled = true,
            alertPosition = { point = "TOP", relPoint = "TOP", x = 1.667, y = -293.333 },
            toastPosition = { point = "CENTER", relPoint = "CENTER", x = -5.833, y = 268.333 },
            bnetToastPosition = nil, -- nil = default Blizzard positioning
        },

        -- Missing Raid Buffs Display Settings
        raidBuffs = {
            enabled = true,
            showOnlyInGroup = true,
            providerMode = false,
            hideLabelBar = false,  -- Hide the "Missing Buffs" label bar
            iconSize = 32,
            iconSpacing = 4,
            labelFontSize = 12,
            labelTextColor = nil,  -- nil = white, otherwise {r, g, b, a}
            position = nil,
            growDirection = "RIGHT",  -- LEFT, RIGHT, UP, DOWN, CENTER_H, CENTER_V
            iconBorder = {
                show = true,
                width = 1,
                useClassColor = false,
                color = { 0.376, 0.647, 0.980, 1 },  -- Default sky blue accent
            },
            buffCount = {
                show = true,
                position = "BOTTOM",  -- TOP, BOTTOM, LEFT, RIGHT
                fontSize = 10,
                font = "Quazii",  -- Font name from LibSharedMedia
                color = { 1, 1, 1, 1 },  -- White default
                offsetX = 0,
                offsetY = 0,
            },
        },

        -- Custom M+ Timer Settings
        mplusTimer = {
            enabled = false,
            layoutMode = "sleek",
            showTimer = true,
            showBorder = true,
            frameBackgroundOpacity = 1,
            showDeaths = true,
            showAffixes = true,
            showObjectives = true,
            position = { x = -11.667, y = -204.998 },
            forcesBarEnabled = true,
            forcesDisplayMode = "bar",
            forcesPosition = "after_timer",
            forcesTextFormat = "both",
            forcesLabel = "Forces",
            forcesFont = "Poppins",
            forcesFontSize = 11,
            maxDungeonNameLength = 18,
        },

        -- Character Pane Settings
        character = {
            enabled = true,
            showItemName = true,            -- Show equipment name (line 1)
            showItemLevel = true,           -- Show item level & track (line 2)
            showEnchants = true,            -- Show enchant status (line 3)
            showGems = true,                -- Show gem indicators
            showDurability = false,         -- Show durability bars
            inspectEnabled = true,
            showModelBackground = true,     -- Show background behind model
            -- Inspect-specific overlay settings (separate from character)
            showInspectItemName = true,
            showInspectItemLevel = true,
            showInspectEnchants = true,
            showInspectGems = true,

            -- In-pane customization
            panelScale = 1.0,               -- Panel scale (0.75 - 1.5 multiplier, base 1.30)
            overlayScale = 0.75,            -- Overlay scale for slot info
            backgroundColor = {0, 0, 0, 0.762},  -- Black with transparency
            statsTextSize = 13,             -- Stats text size in pixels (6 - 40)
            statsTextColor = {1, 1, 1, 1},  -- Stats text color (white)
            ilvlTextSize = 8,               -- Item level text size in pixels (8 - 16)
            headerTextSize = 16,            -- Header text size in pixels (10 - 18)
            secondaryStatFormat = "both",   -- Secondary stat format: "percent", "rating", "both"
            compactStats = true,            -- Compact stats mode (reduced spacing)
            headerClassColor = true,        -- Use class color for headers (default on)
            headerColor = {0.376, 0.647, 0.980},  -- Header color (default accent/sky blue, used when headerClassColor is off)
            enchantTextSize = 10,           -- Enchant text size in pixels (8 - 14) [DEPRECATED - use slotTextSize]
            enchantClassColor = true,       -- Use class color for enchants (default on)
            enchantTextColor = {0.376, 0.647, 0.980},  -- Enchant text color (used when enchantClassColor is off)
            enchantFont = nil,              -- Enchant font (nil = use global font)
            noEnchantTextColor = {1, 0.341, 0.314, 1},  -- "No Enchant" text color (red tint)
            slotTextSize = 12,              -- Unified text size for all 3 slot lines (6 - 40)
            slotPadding = 0,                -- Padding between slot elements
            upgradeTrackColor = {1, 0.816, 0.145, 1},  -- Upgrade track text color (gold)
        },

        -- Loot Window Settings
        loot = {
            enabled = true,           -- Enable custom loot window
            lootUnderMouse = false,   -- Position loot window at cursor
            lootUnderMouseOffsetX = 0, -- Cursor anchor X offset (pixels)
            lootUnderMouseOffsetY = 0, -- Cursor anchor Y offset (pixels)
            showTransmogMarker = true, -- Show marker on uncollected appearances
            position = { point = "TOP", relPoint = "TOP", x = 289.166, y = -165.667 },
        },

        -- Loot Roll Frame Settings
        lootRoll = {
            enabled = true,           -- Enable custom roll frames
            growDirection = "DOWN",   -- Roll frame stacking direction (UP/DOWN)
            spacing = 4,              -- Spacing between roll frames
            position = { point = "TOP", relPoint = "TOP", x = -11.667, y = -166 },
        },

        -- Loot History (Results) Settings
        lootResults = {
            enabled = true,           -- Skin GroupLootHistoryFrame
        },

        -- Keybind Overrides (stored per character/spec in db.char.keybindOverrides[specID])
        keybindOverridesEnabledCDM = true,
        keybindOverridesEnabledTrackers = true,

        -- FPS Settings Backup (stores user's CVars before applying Quazii's settings)
        fpsBackup = nil,

        -- QUI New Cooldown Display Manager (NCDM)
        -- Per-row configuration for Essential and Utility viewers
        ncdm = {
            _snapshotVersion = 0,   -- Incremented each time ownedSpells are snapshotted
            _specProfiles = nil,    -- Future: per-spec owned spell profiles
            essential = {
                enabled = true,
                pos = nil,  -- { ox = number, oy = number } saved container position (nil = first-time, seed from Blizzard)
                desaturateOnCooldown = true,
                rangeIndicator = true,
                rangeColor = {0.8, 0.1, 0.1, 1},
                usabilityIndicator = true,
                clickableIcons = false,
                layoutDirection = "HORIZONTAL",
                row1 = {
                    iconCount = 8,      -- How many icons in row 1 (0 = disabled)
                    iconSize = 39,      -- Icon size in pixels (width)
                    borderSize = 1,     -- Border thickness around icon (0 to 5)
                    borderColorTable = {0, 0, 0, 1}, -- Border color (RGBA)
                    aspectRatioCrop = 1.0,  -- 1.0 = square, higher = flatter
                    zoom = 0,           -- Icon texture zoom (0 to 0.2)
                    padding = 2,        -- Spacing between icons (-20 to 20)
                    xOffset = 0,        -- Horizontal offset for this row
                    yOffset = 0,        -- Vertical offset for this row (-50 to 50)
                    hideDurationText = false, -- Hide duration countdown text on CDM icons
                    durationSize = 16,  -- Duration text font size (8 to 24)
                    durationOffsetX = 0, -- Duration text X offset
                    durationOffsetY = 0, -- Duration text Y offset
                    stackSize = 12,     -- Stack count text font size (8 to 24)
                    stackOffsetX = 0,   -- Stack text X offset
                    stackOffsetY = 2,   -- Stack text Y offset
                    durationTextColor = {1, 1, 1, 1}, -- Duration text color (white default)
                    durationAnchor = "CENTER",        -- Duration text anchor point
                    stackTextColor = {1, 1, 1, 1},    -- Stack text color (white default)
                    stackAnchor = "BOTTOMRIGHT",      -- Stack text anchor point
                },
                row2 = {
                    iconCount = 8,
                    iconSize = 39,
                    borderSize = 1,
                    borderColorTable = {0, 0, 0, 1},
                    aspectRatioCrop = 1.0,
                    zoom = 0,
                    padding = 2,
                    xOffset = 0,
                    yOffset = 3,
                    durationSize = 16,
                    durationOffsetX = 0,
                    durationOffsetY = 0,
                    stackSize = 12,
                    stackOffsetX = 0,
                    stackOffsetY = 2,
                    durationTextColor = {1, 1, 1, 1},
                    durationAnchor = "CENTER",
                    stackTextColor = {1, 1, 1, 1},
                    stackAnchor = "BOTTOMRIGHT",
                },
                row3 = {
                    iconCount = 8,      -- 0 = row disabled by default
                    iconSize = 39,
                    borderSize = 1,
                    borderColorTable = {0, 0, 0, 1},
                    aspectRatioCrop = 1.0,
                    zoom = 0,
                    padding = 2,
                    xOffset = 0,
                    yOffset = 0,
                    durationSize = 16,
                    durationOffsetX = 0,
                    durationOffsetY = 0,
                    stackSize = 12,
                    stackOffsetX = 0,
                    stackOffsetY = 2,
                    durationTextColor = {1, 1, 1, 1},
                    durationAnchor = "CENTER",
                    stackTextColor = {1, 1, 1, 1},
                    stackAnchor = "BOTTOMRIGHT",
                },
                rangeColor = {0.8, 0.1, 0.1}, -- Range indicator tint color
                -- Owned spell list (Phase A CDM Overhaul)
                ownedSpells = nil,           -- nil = not yet snapshotted; {} = snapshotted empty
                removedSpells = {},          -- { [spellID] = true }
                dormantSpells = {},          -- { spellID, ... }
                spellOverrides = {},         -- { [spellID] = { glowColor, hidden, ... } }
                iconDisplayMode = "always",  -- "always" | "active" | "combat"
                containerType = "cooldown",  -- "cooldown" | "aura" | "auraBar"
                greyOutInactive = false,     -- Grey out icons when linked debuff not active on target
                greyOutInactiveBuffs = false, -- Grey out icons when linked buff not active on player
            },
            utility = {
                enabled = true,
                pos = nil,  -- { ox = number, oy = number } saved container position (nil = first-time, seed from Blizzard)
                desaturateOnCooldown = true,
                rangeIndicator = true,
                rangeColor = {0.8, 0.1, 0.1, 1},
                usabilityIndicator = true,
                clickableIcons = false,
                layoutDirection = "HORIZONTAL",
                row1 = {
                    iconCount = 6,
                    iconSize = 30,
                    borderSize = 1,
                    borderColorTable = {0, 0, 0, 1},
                    aspectRatioCrop = 1.0,
                    zoom = 0,
                    padding = 2,
                    xOffset = 0,
                    yOffset = 0,
                    durationSize = 14,
                    durationOffsetX = 0,
                    durationOffsetY = 0,
                    stackSize = 14,
                    stackOffsetX = 0,
                    stackOffsetY = 0,
                    durationTextColor = {1, 1, 1, 1},
                    durationAnchor = "CENTER",
                    stackTextColor = {1, 1, 1, 1},
                    stackAnchor = "BOTTOMRIGHT",
                },
                row2 = {
                    iconCount = 0,
                    iconSize = 30,
                    borderSize = 1,
                    borderColorTable = {0, 0, 0, 1},
                    aspectRatioCrop = 1.0,
                    zoom = 0,
                    padding = 2,
                    xOffset = 0,
                    yOffset = 8,
                    durationSize = 14,
                    durationOffsetX = 0,
                    durationOffsetY = 0,
                    stackSize = 14,
                    stackOffsetX = 0,
                    stackOffsetY = 0,
                    durationTextColor = {1, 1, 1, 1},
                    durationAnchor = "CENTER",
                    stackTextColor = {1, 1, 1, 1},
                    stackAnchor = "BOTTOMRIGHT",
                },
                row3 = {
                    iconCount = 0,
                    iconSize = 30,
                    borderSize = 1,
                    borderColorTable = {0, 0, 0, 1},
                    aspectRatioCrop = 1.0,
                    zoom = 0,
                    padding = 2,
                    xOffset = 0,
                    yOffset = 4,
                    durationSize = 14,
                    durationOffsetX = 0,
                    durationOffsetY = 0,
                    stackSize = 14,
                    stackOffsetX = 0,
                    stackOffsetY = 0,
                    durationTextColor = {1, 1, 1, 1},
                    durationAnchor = "CENTER",
                    stackTextColor = {1, 1, 1, 1},
                    stackAnchor = "BOTTOMRIGHT",
                },
                anchorBelowEssential = false,
                anchorGap = 0,
                rangeColor = {0.8, 0.1, 0.1},
                -- Owned spell list (Phase A CDM Overhaul)
                ownedSpells = nil,           -- nil = not yet snapshotted; {} = snapshotted empty
                removedSpells = {},          -- { [spellID] = true }
                dormantSpells = {},          -- { spellID, ... }
                spellOverrides = {},         -- { [spellID] = { glowColor, hidden, ... } }
                iconDisplayMode = "always",  -- "always" | "active" | "combat"
                containerType = "cooldown",  -- "cooldown" | "aura" | "auraBar"
                greyOutInactive = false,     -- Grey out icons when linked debuff not active on target
                greyOutInactiveBuffs = false, -- Grey out icons when linked buff not active on player
            },
            buff = {
                enabled = true,
                pos = nil,  -- { ox = number, oy = number } saved container position (nil = first-time, seed from Blizzard)
                iconSize = 32,      -- Icon size in pixels
                borderSize = 1,     -- Border thickness (0 to 8)
                shape = "square",   -- DEPRECATED: use aspectRatioCrop instead
                aspectRatioCrop = 1.0,  -- Aspect ratio (0.5-2.0): <1=taller, 1=square, >1=wider
                growthDirection = "CENTERED_HORIZONTAL",  -- CENTERED_HORIZONTAL, LEFT, or RIGHT
                zoom = 0,           -- Icon texture zoom (0 to 0.2)
                padding = 4,        -- Spacing between icons (-20 to 20)
                hideDurationText = false, -- Hide duration countdown text on CDM icons
                durationSize = 14,  -- Duration text font size (8 to 24)
                durationOffsetX = 0,
                durationOffsetY = 8,
                durationAnchor = "TOP",
                stackSize = 14,     -- Stack count text font size (8 to 24)
                stackOffsetX = 0,
                stackOffsetY = -8,
                stackAnchor = "BOTTOM",
                anchorTo = "disabled",
                anchorPlacement = "center",
                anchorSpacing = 0,
                anchorSourcePoint = "CENTER",
                anchorTargetPoint = "CENTER",
                anchorOffsetX = 0,
                anchorOffsetY = 0,
                -- Owned spell list (Phase A CDM Overhaul)
                ownedSpells = nil,           -- nil = not yet snapshotted; {} = snapshotted empty
                removedSpells = {},          -- { [spellID] = true }
                dormantSpells = {},          -- { spellID, ... }
                spellOverrides = {},         -- { [spellID] = { glowColor, hidden, ... } }
                iconDisplayMode = "active",  -- default: show only when aura present
                containerType = "aura",      -- "cooldown" | "aura" | "auraBar"
            },
            trackedBar = {
                enabled = true,
                hideIcon = false,
                barHeight = 25,
                barWidth = 215,
                texture = "Quazii v5",
                useClassColor = true,
                barColor = {0.376, 0.647, 0.980, 1},  -- sky blue accent fallback
                colorOverrides = {},                  -- Per-spell color overrides {spellID → {r, g, b, a}}
                barOpacity = 1.0,
                borderSize = 2,
                bgColor = {0, 0, 0, 1},
                bgOpacity = 0.5,
                textSize = 14,
                spacing = 2,
                growUp = true,  -- true = grow upward, false = grow downward
                -- Inactive tracked-buff display behavior
                inactiveMode = "hide",  -- always, fade, hide
                inactiveAlpha = 0.3,
                desaturateInactive = false,
                reserveSlotWhenInactive = false,
                autoWidth = false,
                autoWidthOffset = 0,
                anchorTo = "disabled",
                anchorPlacement = "center",
                anchorSpacing = 0,
                anchorSourcePoint = "CENTER",
                anchorTargetPoint = "CENTER",
                anchorOffsetX = 0,
                anchorOffsetY = 0,
                orientation = "horizontal",
                fillDirection = "up",
                iconPosition = "top",
                showTextOnVertical = false,
                pos = nil,  -- owned container position (seeded from Blizzard viewer on first init)
                -- Owned spell list (Phase A CDM Overhaul)
                ownedSpells = nil,           -- nil = not yet snapshotted; {} = snapshotted empty
                removedSpells = {},          -- { [spellID] = true }
                dormantSpells = {},          -- { spellID, ... }
                spellOverrides = {},         -- { [spellID] = { glowColor, hidden, ... } }
                iconDisplayMode = "active",  -- default: show only when aura present
                containerType = "auraBar",   -- "cooldown" | "aura" | "auraBar"
            },
            -- Unified containers table (Phase G CDM Overhaul)
            -- Mirrors the top-level essential/utility/buff/trackedBar structures
            -- with added builtIn, name, and containerType fields.
            -- Custom containers are added dynamically with builtIn = false.
            containers = {
                essential = {
                    name = "Essential",
                    builtIn = true,
                    containerType = "cooldown",
                    enabled = true,
                    pos = nil,
                    desaturateOnCooldown = true,
                    rangeIndicator = true,
                    rangeColor = {0.8, 0.1, 0.1, 1},
                    usabilityIndicator = true,
                    clickableIcons = false,
                    layoutDirection = "HORIZONTAL",
                    row1 = {
                        iconCount = 8, iconSize = 39, borderSize = 1,
                        borderColorTable = {0, 0, 0, 1}, aspectRatioCrop = 1.0,
                        zoom = 0, padding = 2, xOffset = 0, yOffset = 0,
                        hideDurationText = false, durationSize = 16,
                        durationOffsetX = 0, durationOffsetY = 0,
                        stackSize = 12, stackOffsetX = 0, stackOffsetY = 2,
                        durationTextColor = {1, 1, 1, 1}, durationAnchor = "CENTER",
                        stackTextColor = {1, 1, 1, 1}, stackAnchor = "BOTTOMRIGHT",
                    },
                    row2 = {
                        iconCount = 8, iconSize = 39, borderSize = 1,
                        borderColorTable = {0, 0, 0, 1}, aspectRatioCrop = 1.0,
                        zoom = 0, padding = 2, xOffset = 0, yOffset = 3,
                        durationSize = 16, durationOffsetX = 0, durationOffsetY = 0,
                        stackSize = 12, stackOffsetX = 0, stackOffsetY = 2,
                        durationTextColor = {1, 1, 1, 1}, durationAnchor = "CENTER",
                        stackTextColor = {1, 1, 1, 1}, stackAnchor = "BOTTOMRIGHT",
                    },
                    row3 = {
                        iconCount = 8, iconSize = 39, borderSize = 1,
                        borderColorTable = {0, 0, 0, 1}, aspectRatioCrop = 1.0,
                        zoom = 0, padding = 2, xOffset = 0, yOffset = 0,
                        durationSize = 16, durationOffsetX = 0, durationOffsetY = 0,
                        stackSize = 12, stackOffsetX = 0, stackOffsetY = 2,
                        durationTextColor = {1, 1, 1, 1}, durationAnchor = "CENTER",
                        stackTextColor = {1, 1, 1, 1}, stackAnchor = "BOTTOMRIGHT",
                    },
                    rangeColor = {0.8, 0.1, 0.1},
                    ownedSpells = nil,
                    removedSpells = {},
                    dormantSpells = {},
                    spellOverrides = {},
                    iconDisplayMode = "always",
                },
                utility = {
                    name = "Utility",
                    builtIn = true,
                    containerType = "cooldown",
                    enabled = true,
                    pos = nil,
                    desaturateOnCooldown = true,
                    rangeIndicator = true,
                    rangeColor = {0.8, 0.1, 0.1, 1},
                    usabilityIndicator = true,
                    clickableIcons = false,
                    layoutDirection = "HORIZONTAL",
                    row1 = {
                        iconCount = 6, iconSize = 30, borderSize = 1,
                        borderColorTable = {0, 0, 0, 1}, aspectRatioCrop = 1.0,
                        zoom = 0, padding = 2, xOffset = 0, yOffset = 0,
                        durationSize = 14, durationOffsetX = 0, durationOffsetY = 0,
                        stackSize = 14, stackOffsetX = 0, stackOffsetY = 0,
                        durationTextColor = {1, 1, 1, 1}, durationAnchor = "CENTER",
                        stackTextColor = {1, 1, 1, 1}, stackAnchor = "BOTTOMRIGHT",
                    },
                    row2 = {
                        iconCount = 0, iconSize = 30, borderSize = 1,
                        borderColorTable = {0, 0, 0, 1}, aspectRatioCrop = 1.0,
                        zoom = 0, padding = 2, xOffset = 0, yOffset = 8,
                        durationSize = 14, durationOffsetX = 0, durationOffsetY = 0,
                        stackSize = 14, stackOffsetX = 0, stackOffsetY = 0,
                        durationTextColor = {1, 1, 1, 1}, durationAnchor = "CENTER",
                        stackTextColor = {1, 1, 1, 1}, stackAnchor = "BOTTOMRIGHT",
                    },
                    row3 = {
                        iconCount = 0, iconSize = 30, borderSize = 1,
                        borderColorTable = {0, 0, 0, 1}, aspectRatioCrop = 1.0,
                        zoom = 0, padding = 2, xOffset = 0, yOffset = 4,
                        durationSize = 14, durationOffsetX = 0, durationOffsetY = 0,
                        stackSize = 14, stackOffsetX = 0, stackOffsetY = 0,
                        durationTextColor = {1, 1, 1, 1}, durationAnchor = "CENTER",
                        stackTextColor = {1, 1, 1, 1}, stackAnchor = "BOTTOMRIGHT",
                    },
                    anchorBelowEssential = false,
                    anchorGap = 0,
                    rangeColor = {0.8, 0.1, 0.1},
                    ownedSpells = nil,
                    removedSpells = {},
                    dormantSpells = {},
                    spellOverrides = {},
                    iconDisplayMode = "always",
                },
                buff = {
                    name = "Buff Icons",
                    builtIn = true,
                    containerType = "aura",
                    enabled = true,
                    pos = nil,
                    iconSize = 32, borderSize = 1,
                    shape = "square",
                    aspectRatioCrop = 1.0,
                    growthDirection = "CENTERED_HORIZONTAL",
                    zoom = 0, padding = 4,
                    hideDurationText = false, durationSize = 14,
                    durationOffsetX = 0, durationOffsetY = 8,
                    durationAnchor = "TOP",
                    stackSize = 14, stackOffsetX = 0, stackOffsetY = -8,
                    stackAnchor = "BOTTOM",
                    anchorTo = "disabled",
                    anchorPlacement = "center",
                    anchorSpacing = 0,
                    anchorSourcePoint = "CENTER",
                    anchorTargetPoint = "CENTER",
                    anchorOffsetX = 0,
                    anchorOffsetY = 0,
                    ownedSpells = nil,
                    removedSpells = {},
                    dormantSpells = {},
                    spellOverrides = {},
                    iconDisplayMode = "active",
                },
                trackedBar = {
                    name = "Buff Bars",
                    builtIn = true,
                    containerType = "auraBar",
                    enabled = true,
                    hideIcon = false,
                    barHeight = 25, barWidth = 215,
                    texture = "Quazii v5",
                    useClassColor = true,
                    barColor = {0.376, 0.647, 0.980, 1},
                    colorOverrides = {},
                    barOpacity = 1.0,
                    borderSize = 2,
                    bgColor = {0, 0, 0, 1},
                    bgOpacity = 0.5,
                    textSize = 14,
                    spacing = 2,
                    growUp = true,
                    inactiveMode = "hide",
                    inactiveAlpha = 0.3,
                    desaturateInactive = false,
                    reserveSlotWhenInactive = false,
                    autoWidth = false,
                    autoWidthOffset = 0,
                    anchorTo = "disabled",
                    anchorPlacement = "center",
                    anchorSpacing = 0,
                    anchorSourcePoint = "CENTER",
                    anchorTargetPoint = "CENTER",
                    anchorOffsetX = 0,
                    anchorOffsetY = 0,
                    orientation = "horizontal",
                    fillDirection = "up",
                    iconPosition = "top",
                    showTextOnVertical = false,
                    pos = nil,
                    ownedSpells = nil,
                    removedSpells = {},
                    dormantSpells = {},
                    spellOverrides = {},
                    iconDisplayMode = "active",
                },
            },
        },

        -- CDM Visibility (essentials, utility, buffs, power bars)
        cdmVisibility = {
            showAlways = true,
            showWhenTargetExists = true,
            showInCombat = false,
            showInGroup = false,
            showInInstance = false,
            showOnMouseover = false,
            fadeDuration = 0.2,
            fadeOutAlpha = 0,
            hideWhenMounted = false,
            hideWhenInVehicle = false,
            hideWhenFlying = false,
            hideWhenSkyriding = false,
            dontHideInDungeonsRaids = false,
        },

        -- Unitframes Visibility (player, target, focus, pet, tot, boss)
        unitframesVisibility = {
            showAlways = true,
            showWhenTargetExists = false,
            showInCombat = false,
            showInGroup = false,
            showInInstance = false,
            showOnMouseover = false,
            showWhenHealthBelow100 = false,
            fadeDuration = 0.2,
            fadeOutAlpha = 0,
            alwaysShowCastbars = false,  -- When true, castbars ignore UF visibility
            hideWhenMounted = false,
            hideWhenFlying = false,
            hideWhenSkyriding = false,
            dontHideInDungeonsRaids = false,
        },

        -- Custom Trackers Visibility (all custom item/spell bars)
        customTrackersVisibility = {
            showAlways = true,
            showWhenTargetExists = false,
            showInCombat = false,
            showInGroup = false,
            showInInstance = false,
            showOnMouseover = false,
            fadeDuration = 0.2,
            fadeOutAlpha = 0,
            hideWhenMounted = false,
            hideWhenFlying = false,
            hideWhenSkyriding = false,
            dontHideInDungeonsRaids = false,
        },

        -- Action Bars Visibility
        actionBarsVisibility = {
            showAlways = true,
            showWhenTargetExists = false,
            showInCombat = false,
            showInGroup = false,
            showInInstance = false,
            showOnMouseover = false,
            fadeDuration = 0.2,
            fadeOutAlpha = 0,
            hideWhenMounted = false,
            hideWhenInVehicle = false,
            hideWhenFlying = false,
            hideWhenSkyriding = false,
            dontHideInDungeonsRaids = false,
        },

        -- Chat Frames Visibility
        chatVisibility = {
            showAlways = true,
            showWhenTargetExists = false,
            showInCombat = false,
            showInGroup = false,
            showInInstance = false,
            showOnMouseover = false,
            fadeDuration = 0.2,
            fadeOutAlpha = 0,
            hideWhenMounted = false,
            hideWhenInVehicle = false,
            hideWhenFlying = false,
            hideWhenSkyriding = false,
            dontHideInDungeonsRaids = false,
        },

        viewers = {
            EssentialCooldownViewer = {
                enabled          = true,
                iconSize         = 50,
                aspectRatioCrop  = 1.0,
                spacing          = -11,
                zoom             = 0,
                borderSize       = 1,
                borderColor      = { 0, 0, 0, 1 },
                chargeTextAnchor = "BOTTOMRIGHT",
                countTextSize    = 14,
                countTextOffsetX = 0,
                countTextOffsetY = 0,
                durationTextSize = 14,
                rowLimit         = 8,
                -- Row pattern: icons per row (0 = row disabled)
                row1Icons        = 6,
                row2Icons        = 6,
                row3Icons        = 6,
                useRowPattern    = false,  -- false = use rowLimit, true = use row pattern
                rowAlignment     = "CENTER", -- LEFT, CENTER, RIGHT
                -- Keybind display
                showKeybinds      = false,
                keybindTextSize   = 12,
                keybindTextColor  = { 1, 0.82, 0, 1 },  -- Gold/Yellow
                keybindAnchor     = "TOPLEFT",
                keybindOffsetX    = 2,
                keybindOffsetY    = 2,
                -- Rotation Helper overlay (uses C_AssistedCombat)
                showRotationHelper = false,
                rotationHelperColor = { 0, 1, 0.84, 1 },  -- #00FFD6 cyan/mint border
                rotationHelperThickness = 2,  -- Border thickness in pixels
            },
            UtilityCooldownViewer = {
                enabled          = true,
                iconSize         = 42,
                aspectRatioCrop  = 1.0,
                spacing          = -11,
                zoom             = 0.08,
                borderSize       = 1,
                borderColor      = { 0, 0, 0, 1 },
                chargeTextAnchor = "BOTTOMRIGHT",
                countTextSize    = 14,
                countTextOffsetX = 0,
                countTextOffsetY = 0,
                durationTextSize = 14,
                rowLimit         = 0,
                -- Row pattern: icons per row (0 = row disabled)
                row1Icons        = 8,
                row2Icons        = 8,
                useRowPattern    = false,  -- false = use rowLimit, true = use row pattern
                rowAlignment     = "CENTER", -- LEFT, CENTER, RIGHT
                -- Auto-anchor to Essential
                anchorToEssential = false,  -- When true, Utility anchors below Essential's last row
                anchorGap         = 10,     -- Gap between Essential and Utility when anchored
                -- Keybind display
                showKeybinds      = false,
                keybindTextSize   = 12,
                keybindTextColor  = { 1, 0.82, 0, 1 },  -- Gold/Yellow
                keybindAnchor     = "TOPLEFT",
                keybindOffsetX    = 2,
                keybindOffsetY    = 2,
                -- Rotation Helper overlay (uses C_AssistedCombat)
                showRotationHelper = false,
                rotationHelperColor = { 0, 1, 0.84, 1 },  -- #00FFD6 cyan/mint border
                rotationHelperThickness = 2,  -- Border thickness in pixels
            },
            -- BuffIconCooldownViewer removed - now handled by qui_buffbar.lua
            -- Settings are at db.profile.ncdm.buff instead
        },

        -- Rotation Assist Icon (standalone icon showing next recommended ability)
        rotationAssistIcon = {
            enabled = false,
            isLocked = true,
            iconSize = 56,
            visibility = "always",  -- "always", "combat", "hostile"
            frameStrata = "MEDIUM",
            -- Border
            showBorder = true,
            borderThickness = 2,
            borderColor = { 0, 0, 0, 1 },
            -- Cooldown
            cooldownSwipeEnabled = true,
            -- Keybind
            showKeybind = true,
            keybindFont = nil,  -- nil = use general.font
            keybindSize = 13,
            keybindColor = { 1, 1, 1, 1 },
            keybindOutline = true,
            keybindAnchor = "BOTTOMRIGHT",
            keybindOffsetX = -2,
            keybindOffsetY = 2,
            -- Position (anchored to CENTER of screen)
            positionX = 0,
            positionY = -180,
        },

        powerBar = {
            enabled           = true,
            autoAttach        = false,
            standaloneMode    = false,
            attachTo          = "EssentialCooldownViewer",
            height            = 8,
            borderSize        = 1,
            offsetY           = -204,      -- Snapped to top of Essential CDM (default position)
            offsetX           = 0,
            width             = 326,       -- Matches Essential CDM width
            useRawPixels      = true,
            texture           = "Quazii v5",
            colorMode         = "power",  -- "power" = power type color, "class" = class color
            usePowerColor     = true,     -- Use power type color (customizable in Power Colors section)
            useClassColor     = false,    -- Use class color
            customColor       = { 0.2, 0.6, 1, 1 },  -- Custom power bar color
            showPercent       = true,
            hidePercentSymbol = false,
            showText          = true,
            textSize          = 16,
            textAlign         = "CENTER",
            textX             = 1,
            textY             = 3,
            textUseClassColor = false,    -- Use class color for text
            textCustomColor   = { 1, 1, 1, 1 },  -- Custom text color (white default)
            bgColor           = { 0.078, 0.078, 0.078, 1 },
            showTicks         = false,    -- Show tick marks for segmented resources (Holy Power, Chi, etc.)
            tickThickness     = 2,        -- Thickness of tick marks in pixels
            tickColor         = { 0, 0, 0, 1 },  -- Color of tick marks (default black)
            indicators        = {
                enabled   = false,        -- Show custom breakpoint indicator lines
                thickness = 2,            -- Indicator line thickness in pixels
                color     = { 1, 1, 1, 0.9 }, -- Indicator line color
                perSpec   = {},           -- [specID] = { value1, value2, value3 }
            },
            lockedToEssential = false,  -- Auto-resize width when Essential CDM changes
            lockedToUtility   = false,  -- Auto-resize width when Utility CDM changes
            snapGap           = 5,      -- Gap when snapped to CDM
            orientation       = "HORIZONTAL",  -- Bar orientation
            visibility        = "always",  -- "always", "combat", "hostile"
        },
        secondaryPowerBar = {
            enabled       = true,
            autoAttach    = false,
            standaloneMode = false,
            attachTo      = "EssentialCooldownViewer",
            height        = 8,
            borderSize    = 1,
            offsetY       = 0,        -- User adjustment when locked to primary (0 = no offset)
            offsetX       = 0,
            width         = 326,      -- Matches Primary bar width
            useRawPixels  = true,
            texture       = "Quazii v5",
            colorMode     = "power",  -- "power" = power type color, "class" = class color
            usePowerColor = true,     -- Use power type color (customizable in Power Colors section)
            useClassColor = false,    -- Use class color
            customColor   = { 1, 0.8, 0.2, 1 },  -- Custom power bar color
            showPercent   = false,
            hidePercentSymbol = false,
            showText      = false,
            textSize      = 14,
            textAlign     = "CENTER",
            textX         = 0,
            textY         = 2,
            textUseClassColor = false,    -- Use class color for text
            textCustomColor   = { 1, 1, 1, 1 },  -- Custom text color (white default)
            bgColor       = { 0.078, 0.078, 0.078, 0.83 },
            showTicks     = true,     -- Show tick marks for segmented resources (Holy Power, Chi, etc.)
            tickThickness = 2,        -- Thickness of tick marks in pixels
            tickColor     = { 0, 0, 0, 1 },  -- Color of tick marks (default black)
            indicators    = {
                enabled   = false,        -- Show custom breakpoint indicator lines
                thickness = 2,            -- Indicator line thickness in pixels
                color     = { 1, 1, 1, 0.9 }, -- Indicator line color
                perSpec   = {},           -- [specID] = { value1, value2, value3 }
            },
            lockedToEssential = false,  -- Auto-resize width when Essential CDM changes
            lockedToUtility   = false,  -- Auto-resize width when Utility CDM changes
            lockedToPrimary   = true,   -- Position above + match Primary bar width
            swapToPrimaryPosition = false,  -- Show secondary bar at primary bar's position (supported specs only)
            hidePrimaryOnSwap = false,      -- Auto-hide primary bar when secondary is swapped to its position
            swapSpecs = {                   -- Per-spec swap enable (all candidates default on)
                [102]  = true,  -- Druid: Balance
                [251]  = true,  -- Death Knight: Frost
                [66]   = true,  -- Paladin: Protection
                [70]   = true,  -- Paladin: Retribution
                [263]  = true,  -- Shaman: Enhancement
                [265]  = true,  -- Warlock: Affliction
                [266]  = true,  -- Warlock: Demonology
                [267]  = true,  -- Warlock: Destruction
                [1467] = true,  -- Evoker: Devastation
                [1473] = true,  -- Evoker: Augmentation
            },
            hideSpecs = {                   -- Per-spec auto-hide enable (all candidates default on)
                [102]  = true,  -- Druid: Balance
                [251]  = true,  -- Death Knight: Frost
                [66]   = true,  -- Paladin: Protection
                [70]   = true,  -- Paladin: Retribution
                [263]  = true,  -- Shaman: Enhancement
                [265]  = true,  -- Warlock: Affliction
                [266]  = true,  -- Warlock: Demonology
                [267]  = true,  -- Warlock: Destruction
                [1467] = true,  -- Evoker: Devastation
                [1473] = true,  -- Evoker: Augmentation
            },
            snapGap       = 5,        -- Gap when snapped
            orientation   = "AUTO",   -- Bar orientation
            visibility    = "always",  -- "always", "combat", "hostile"
            showFragmentedPowerBarText = false,  -- Show text on fragmented power bars
            textPerSpec = false,           -- When true, text settings are saved per specialization
            textSpecOverrides = {},        -- [specID] = { showText, showPercent, ... }
        },
        -- Power Colors (global, used by both Primary and Secondary power bars)
        powerColors = {
            -- Core Resources
            rage = { 1.00, 0.00, 0.00, 1 },
            energy = { 1.00, 1.00, 0.00, 1 },
            mana = { 0.00, 0.00, 1.00, 1 },
            focus = { 1.00, 0.50, 0.25, 1 },
            runicPower = { 0.00, 0.82, 1.00, 1 },
            fury = { 0.79, 0.26, 0.99, 1 },
            insanity = { 0.40, 0.00, 0.80, 1 },
            maelstrom = { 0.00, 0.50, 1.00, 1 },
            maelstromWeapon = { 0.00, 0.69, 1.00, 1 },
            lunarPower = { 0.30, 0.52, 0.90, 1 },

            -- Builder Resources
            holyPower = { 0.95, 0.90, 0.60, 1 },
            chi = { 0.00, 1.00, 0.59, 1 },
            comboPoints = { 1.00, 0.96, 0.41, 1 },
            soulShards = { 0.58, 0.51, 0.79, 1 },
            arcaneCharges = { 0.10, 0.10, 0.98, 1 },
            essence = { 0.20, 0.58, 0.50, 1 },

            -- Specialized Resources
            stagger = { 0.00, 1.00, 0.59, 1 },
            staggerLight = { 0.52, 1.00, 0.52, 1 },     -- Green (0-30% of max health)
            staggerModerate = { 1.00, 0.98, 0.72, 1 },  -- Yellow (30-60% of max health)
            staggerHeavy = { 1.00, 0.42, 0.42, 1 },     -- Red (60%+ of max health)
            useStaggerLevelColors = true,               -- Enable dynamic stagger colors
            soulFragments = { 0.64, 0.19, 0.79, 1 },
            whirlwind = { 0.90, 0.20, 0.20, 1 },           -- Red (Warrior theme)
            tipOfTheSpear = { 0.00, 0.80, 0.30, 1 },       -- Green (Hunter/Survival theme)
            runes = { 0.77, 0.12, 0.23, 1 },
            bloodRunes = { 0.77, 0.12, 0.23, 1 },
            frostRunes = { 0.00, 0.82, 1.00, 1 },
            unholyRunes = { 0.00, 0.80, 0.00, 1 },
        },
        -- Reticle (GCD tracker around cursor)
        reticle = {
            enabled = false,
            -- Reticle
            reticleStyle = "dot",         -- "dot", "cross", "chevron", "diamond"
            reticleSize = 10,             -- Size in pixels (4-20)
            -- Ring
            ringStyle = "standard",       -- "thin", "standard", "thick", "solid"
            ringSize = 40,                -- Ring diameter (20-80)
            -- Colors
            useClassColor = false,        -- Use class color vs custom
            customColor = {1, 1, 1, 1},   -- White default (#ffffff)
            -- Visibility
            inCombatAlpha = 1.0,
            outCombatAlpha = 1.0,
            hideOutOfCombat = false,
            -- Positioning
            offsetX = 0,
            offsetY = 0,
            -- GCD
            gcdEnabled = true,
            gcdFadeRing = 0.35,           -- Fade ring during GCD (0-1)
            gcdReverse = false,           -- Reverse swipe direction
            -- Behavior
            hideOnRightClick = false,
        },
        -- Screen Center Crosshair
        crosshair = {
            enabled = false,         -- Disabled by default
            onlyInCombat = false,    -- Show all the time when enabled
            size = 9,                -- Line length (half-length from center)
            thickness = 3,           -- Line thickness in pixels
            borderSize = 3,          -- Border thickness around lines
            offsetX = 0,             -- X offset from screen center
            offsetY = 0,             -- Y offset from screen center
            r = 0.796,               -- Crosshair color red
            g = 1,                   -- Crosshair color green
            b = 0.780,               -- Crosshair color blue
            a = 1,                   -- Crosshair alpha
            borderR = 0,             -- Border color red
            borderG = 0,             -- Border color green
            borderB = 0,             -- Border color blue
            borderA = 1,             -- Border alpha
            strata = "LOW",          -- Frame strata
            lineColor = { 0.796, 1, 0.780, 1 },
            borderColorTable = { 0, 0, 0, 1 },
            -- Range-based color changes
            changeColorOnRange = false,           -- Master toggle for range checking
            enableMeleeRangeCheck = true,         -- Check melee range (5 yards)
            enableMidRangeCheck = false,          -- Check mid-range (25 yards) for Evokers/Devourers
            outOfRangeColor = { 1, 0.2, 0.2, 1 },  -- Red color when out of range
            midRangeColor = { 1, 0.6, 0.2, 1 },   -- Orange color for 25-yard range (when both checks enabled)
            rangeColorInCombatOnly = false,       -- Only change color in combat
            hideUntilOutOfRange = false,          -- Only show crosshair when in combat AND out of range
        },

        -- Target Distance Bracket Display
        rangeCheck = {
            enabled = false,
            combatOnly = false,
            showOnlyWithTarget = true,
            updateRate = 0.1, -- seconds
            shortenText = false,
            dynamicColor = false,
            font = "Quazii",
            fontSize = 22,
            useClassColor = false,
            textColor = { 0.2, 0.95, 0.55, 1 },
            strata = "MEDIUM",
            offsetX = 0,
            offsetY = -190,
        },

        -- Skyriding Vigor Bar
        skyriding = {
            enabled = true,
            width = 250,
            vigorHeight = 20,
            secondWindHeight = 20,
            offsetX = 0,
            offsetY = 135,
            locked = false,
            useClassColorVigor = false,
            barColor = { 0.2, 0.8, 1.0, 1 },              -- 33CCFF
            backgroundColor = { 0.102, 0.102, 0.102, 0.353 }, -- 1A1A1A with lower alpha
            segmentColor = { 0, 0, 0, 1 },                -- 000000
            rechargeColor = { 0.4, 0.9, 1.0, 1 },         -- 66E6FF
            borderSize = 1,
            borderColor = { 0, 0, 0, 1 },
            barTexture = "Quazii v4",
            showSegments = true,
            segmentThickness = 1,
            showSpeed = true,
            speedFormat = "PERCENT",
            speedFontSize = 11,
            showVigorText = true,
            vigorTextFormat = "FRACTION",
            vigorFontSize = 11,
            secondWindMode = "MINIBAR",
            secondWindScale = 2.1,
            useClassColorSecondWind = false,
            secondWindColor = { 1.0, 0.8, 0.2, 1 },       -- FFCC33
            secondWindBackgroundColor = { 0.102, 0.102, 0.102, 0.301 }, -- 1A1A1A with lower alpha
            useThrillOfTheSkiesColor = true,               -- Change bar color when Thrill of the Skies buff is active
            thrillOfTheSkiesColor = { 1.0, 0.5, 0.0, 1 }, -- FF8000 (orange)
            visibility = "FLYING_ONLY",
            fadeDelay = 1,
            fadeDuration = 0.3,
        },

        -- Chat Frame Customization
        chat = {
            enabled = true,
            -- Glass visual effect
            glass = {
                enabled = true,
                bgAlpha = 0.25,          -- Background transparency (0-1.0)
                bgColor = {0, 0, 0},     -- Background color (RGB)
            },
            -- Message fade after inactivity (uses native API)
            fade = {
                enabled = false,         -- Off by default
                delay = 15,              -- Seconds before fade starts
                duration = 0.6,          -- Fade animation duration
            },
            -- Font settings
            font = {
                forceOutline = false,    -- Force font outline
            },
            -- URL detection and copying
            urls = {
                enabled = true,
                color = {0.078, 0.608, 0.992, 1},  -- Clickable URL color (blue)
            },
            -- UI cleanup
            hideButtons = true,          -- Hide social/channel/scroll buttons
            -- Input box styling
            editBox = {
                enabled = true,          -- Apply glass styling to input box
                bgAlpha = 0.25,          -- Background transparency (0-1.0)
                bgColor = {0, 0, 0},     -- Background color (RGB)
                height = 20,             -- Input box height
                positionTop = false,     -- Position input box above chat tabs
            },
            -- Timestamps
            timestamps = {
                enabled = false,         -- Off by default
                format = "24h",          -- "24h" or "12h"
                color = {0.6, 0.6, 0.6}, -- Gray color
            },
            -- Copy button mode: "always", "hover", "hidden", "disabled"
            copyButtonMode = "always",
            -- Default chat tab on login/reload (1 = General, 2-10 = other tabs)
            defaultTab = 1,
            defaultTabPerSpec = false,    -- Use spec-specific default tabs
            defaultTabBySpec = {},        -- [specID] = tabIndex
            -- Intro message on login
            showIntroMessage = true,
            -- Message history cache for arrow key navigation
            messageHistory = {
                enabled = true,
                maxHistory = 50,  -- Maximum number of messages to store
            },
            -- Sound on new message (SharedMedia compatible)
            newMessageSound = {
                enabled = false,
                entries = {                -- Array of {channel, sound} - each channel can have its own sound
                    { channel = "guild_officer", sound = "None" },
                },
            },
        },

        -- Tooltip Management
        tooltip = {
            engine = "default",                -- tooltip engine
            enabled = true,                    -- Master toggle for tooltip module
            anchorToCursor = true,             -- Follow cursor vs fixed anchor
            anchorPosition = nil,              -- Saved fixed anchor position {point, relPoint, x, y}
            cursorAnchor = "TOPLEFT",          -- Tooltip point anchored to cursor
            cursorOffsetX = 16,                -- Cursor anchor X offset (pixels)
            cursorOffsetY = -16,               -- Cursor anchor Y offset (pixels)
            hideInCombat = true,               -- Suppress tooltips during combat
            classColorName = false,            -- Color player names by class
            fontSize = 12,                     -- Tooltip text font size
            skinTooltips = true,               -- Apply QUI theme to tooltips
            bgColor = {0.05, 0.05, 0.05, 1},  -- Custom background color
            bgOpacity = 0.95,                  -- Background opacity (0-1)
            showBorder = true,                 -- Toggle border visibility
            borderThickness = 1,               -- Border thickness (1-10)
            borderColor = {0.376, 0.647, 0.980, 1}, -- Border color (default = sky blue accent)
            borderUseClassColor = false,       -- Use player class color for border
            borderUseAccentColor = false,      -- Use addon accent color for border
            showSpellIDs = false,              -- Show spell ID and icon ID on buff/debuff tooltips
            showPlayerItemLevel = false,       -- Show inspected player item level on player tooltips
            colorPlayerItemLevel = true,       -- Color tooltip player item level by configured ilvl brackets
            itemLevelBrackets = {
                white = 245,                   -- White bracket starts here (below = grey)
                green = 255,                   -- Green bracket starts here
                blue = 265,                    -- Blue bracket starts here
                purple = 275,                  -- Purple bracket starts here
                orange = 285,                  -- Orange bracket starts here
            },
            hideDelay = 0,                     -- Seconds before tooltip hides after mouse leaves (0 = instant, >0 = fade out)
            -- Per-Context Visibility (SHOW/HIDE/SHIFT/CTRL/ALT)
            visibility = {
                npcs = "SHOW",                 -- NPCs/players in world
                abilities = "SHOW",            -- Action bar buttons
                items = "SHOW",                -- Bag/bank items
                frames = "SHOW",               -- Unit frame mouseover
                cdm = "SHOW",                  -- CDM views (Essential, Utility, Buff)
                customTrackers = "SHOW",       -- Custom Items/Spells bars
            },
            combatKey = "SHIFT",               -- NONE/SHIFT/CTRL/ALT
            hideHealthBar = true,              -- Hide the health bar on unit tooltips
            hideServerName = false,            -- Hide server/realm name line from player tooltips
            hidePlayerTitle = false,           -- Hide player title from tooltip name line
            showTooltipTarget = true,          -- Show target of unit on tooltip
            showPlayerMount = true,            -- Show active mount on player tooltip
            showPlayerMythicRating = true,     -- Show M+ rating on player tooltip
        },

        -- QUI Action Bars - Button Skinning and Fade System
        actionBars = {
            enabled = true,
            engine = "owned",       -- "blizzard" or "owned"
            -- Global settings (apply to all bars)
            global = {
                skinEnabled = true,         -- Apply button skinning
                iconSize = 36,              -- Base icon size (36x36)
                iconZoom = 0.05,            -- Icon texture crop (0.05-0.15)
                showBackdrop = true,        -- Show backdrop behind icons
                backdropAlpha = 0.8,        -- Backdrop opacity (0-1)
                showGloss = true,           -- Show gloss/shine overlay
                glossAlpha = 0.6,           -- Gloss opacity (0-1)
                showFlash = "qui",          -- Pushed texture style: "off", "blizzard", "qui"
                showBorders = true,         -- Show button borders
                showKeybinds = true,        -- Show hotkey text
                showMacroNames = false,     -- Show macro name text
                showCounts = true,          -- Show stack/charge count
                hideEmptyKeybinds = false,  -- Hide placeholder keybinds
                keybindFontSize = 12,       -- Keybind text size
                keybindColor = {1, 1, 1, 1},-- Keybind text color
                keybindAnchor = "TOPLEFT",  -- Keybind text anchor point
                keybindOffsetX = 4,         -- Keybind text X offset
                keybindOffsetY = -4,        -- Keybind text Y offset
                macroNameFontSize = 10,     -- Macro name text size
                macroNameColor = {1, 1, 1, 1}, -- Macro name text color
                macroNameAnchor = "BOTTOM", -- Macro name text anchor point
                macroNameOffsetX = 0,       -- Macro name text X offset
                macroNameOffsetY = 4,       -- Macro name text Y offset
                countFontSize = 12,         -- Count text size
                countColor = {1, 1, 1, 1},  -- Count text color
                countAnchor = "BOTTOMRIGHT", -- Stack count text anchor point
                countOffsetX = -4,          -- Stack count text X offset
                countOffsetY = 4,           -- Stack count text Y offset
                -- Bar Layout settings
                barScale = 1.0,             -- Global scale multiplier (0.5 - 2.0)
                buttonSpacing = nil,        -- Button spacing override (nil = use Blizzard Edit Mode padding)
                hideEmptySlots = false,     -- Hide buttons with no ability assigned
                lockButtons = false,        -- Prevent dragging abilities off buttons
                -- Range indicator settings
                rangeIndicator = false,     -- Tint out-of-range buttons
                rangeColor = {0.8, 0.1, 0.1, 1}, -- Red tint color
                -- Usability indicator settings
                usabilityIndicator = false,     -- Dim unusable buttons
                usabilityDesaturate = false,    -- Use desaturation (grey) for unusable
                usabilityColor = {0.4, 0.4, 0.4, 1},  -- Fallback color if not desaturating
                manaColor = {0.5, 0.5, 1.0, 1}, -- Out of mana color (blue tint)
                fastUsabilityUpdates = false, -- 5x faster range/usability checks (50ms vs 250ms)
                showTooltips = true,        -- Show tooltips when hovering action buttons
            },
            -- Mouseover fade settings
            fade = {
                enabled = true,             -- Master toggle for mouseover fade
                fadeInDuration = 0.2,       -- Fade in speed (seconds)
                fadeOutDuration = 0.3,      -- Fade out speed (seconds)
                fadeOutAlpha = 0.0,         -- Alpha when faded out (0-1)
                fadeOutDelay = 0.5,         -- Delay before fading out (seconds)
                alwaysShowInCombat = false, -- Force full opacity during combat
                showWhenSpellBookOpen = false, -- Force bars visible while Spellbook is open
                keepLeaveVehicleVisible = false, -- Keep leave-vehicle button visible when mouseover hide is active
                disableBelowMaxLevel = false, -- Keep bars visible until character reaches max level
                linkBars1to8 = false,       -- Link all action bars 1-8 for mouseover
            },
            -- Per-bar settings (nil = use global, value = override)
            -- alwaysShow = true means bar stays visible even when mouseover hide is enabled
            bars = {
                bar1 = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    hidePageArrow = true,
                    ownedPosition = nil,  -- { point, relPoint, x, y } for owned engine
                    -- Owned engine layout (independent of Blizzard Edit Mode)
                    ownedLayout = {
                        orientation = "horizontal", -- "horizontal" or "vertical"
                        columns = 12,               -- buttons per row (horizontal) or per column (vertical)
                        iconCount = 12,             -- visible button count (1-12)
                        buttonSize = 30,            -- button size in pixels
                        buttonSpacing = 0,          -- spacing between buttons in pixels
                        growUp = false,             -- rows grow bottom-to-top
                        growLeft = false,           -- columns grow right-to-left
                    },
                    -- Style overrides (nil = use global)
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = nil,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = nil, keybindOffsetY = nil,
                    showMacroNames = nil, macroNameFontSize = nil, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = nil, macroNameOffsetY = nil,
                    showCounts = nil, countFontSize = nil, countColor = nil,
                    countAnchor = nil, countOffsetX = nil, countOffsetY = nil,
                },
                bar2 = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    ownedPosition = nil,
                    ownedLayout = {
                        orientation = "horizontal", columns = 12, iconCount = 12,
                        buttonSize = 30, buttonSpacing = 0, growUp = false, growLeft = false,
                    },
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = nil,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = nil, keybindOffsetY = nil,
                    showMacroNames = nil, macroNameFontSize = nil, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = nil, macroNameOffsetY = nil,
                    showCounts = nil, countFontSize = nil, countColor = nil,
                    countAnchor = nil, countOffsetX = nil, countOffsetY = nil,
                },
                bar3 = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    ownedPosition = nil,
                    ownedLayout = {
                        orientation = "horizontal", columns = 12, iconCount = 12,
                        buttonSize = 30, buttonSpacing = 0, growUp = false, growLeft = false,
                    },
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = nil,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = nil, keybindOffsetY = nil,
                    showMacroNames = nil, macroNameFontSize = nil, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = nil, macroNameOffsetY = nil,
                    showCounts = nil, countFontSize = nil, countColor = nil,
                    countAnchor = nil, countOffsetX = nil, countOffsetY = nil,
                },
                bar4 = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    ownedPosition = nil,
                    ownedLayout = {
                        orientation = "horizontal", columns = 6, iconCount = 12,
                        buttonSize = 30, buttonSpacing = 0, growUp = false, growLeft = false,
                    },
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = nil,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = nil, keybindOffsetY = nil,
                    showMacroNames = nil, macroNameFontSize = nil, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = nil, macroNameOffsetY = nil,
                    showCounts = nil, countFontSize = nil, countColor = nil,
                    countAnchor = nil, countOffsetX = nil, countOffsetY = nil,
                },
                bar5 = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    ownedPosition = nil,
                    ownedLayout = {
                        orientation = "horizontal", columns = 6, iconCount = 12,
                        buttonSize = 30, buttonSpacing = 0, growUp = false, growLeft = false,
                    },
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = nil,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = nil, keybindOffsetY = nil,
                    showMacroNames = nil, macroNameFontSize = nil, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = nil, macroNameOffsetY = nil,
                    showCounts = nil, countFontSize = nil, countColor = nil,
                    countAnchor = nil, countOffsetX = nil, countOffsetY = nil,
                },
                bar6 = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    ownedPosition = nil,
                    ownedLayout = {
                        orientation = "horizontal", columns = 12, iconCount = 12,
                        buttonSize = 30, buttonSpacing = 0, growUp = false, growLeft = false,
                    },
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = nil,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = nil, keybindOffsetY = nil,
                    showMacroNames = nil, macroNameFontSize = nil, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = nil, macroNameOffsetY = nil,
                    showCounts = nil, countFontSize = nil, countColor = nil,
                    countAnchor = nil, countOffsetX = nil, countOffsetY = nil,
                },
                bar7 = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    ownedPosition = nil,
                    ownedLayout = {
                        orientation = "horizontal", columns = 12, iconCount = 12,
                        buttonSize = 30, buttonSpacing = 0, growUp = false, growLeft = false,
                    },
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = nil,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = nil, keybindOffsetY = nil,
                    showMacroNames = nil, macroNameFontSize = nil, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = nil, macroNameOffsetY = nil,
                    showCounts = nil, countFontSize = nil, countColor = nil,
                    countAnchor = nil, countOffsetX = nil, countOffsetY = nil,
                },
                bar8 = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    ownedPosition = nil,
                    ownedLayout = {
                        orientation = "horizontal", columns = 12, iconCount = 12,
                        buttonSize = 30, buttonSpacing = 0, growUp = false, growLeft = false,
                    },
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = nil,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = nil, keybindOffsetY = nil,
                    showMacroNames = nil, macroNameFontSize = nil, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = nil, macroNameOffsetY = nil,
                    showCounts = nil, countFontSize = nil, countColor = nil,
                    countAnchor = nil, countOffsetX = nil, countOffsetY = nil,
                },
                -- Pet/Stance bars: owned containers with layout + style (same as bars 2-8)
                pet = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    ownedPosition = nil,
                    ownedLayout = {
                        orientation = "horizontal", columns = 10, iconCount = 10,
                        buttonSize = nil, buttonSpacing = nil, growUp = false, growLeft = false,
                    },
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = nil,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = nil, keybindOffsetY = nil,
                    showMacroNames = nil, macroNameFontSize = nil, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = nil, macroNameOffsetY = nil,
                    showCounts = nil, countFontSize = nil, countColor = nil,
                    countAnchor = nil, countOffsetX = nil, countOffsetY = nil,
                },
                stance = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    ownedPosition = nil,
                    ownedLayout = {
                        orientation = "horizontal", columns = 10, iconCount = 10,
                        buttonSize = nil, buttonSpacing = nil, growUp = false, growLeft = false,
                    },
                    overrideEnabled = false,
                    iconZoom = 0.05, showBackdrop = nil, backdropAlpha = 0,
                    showGloss = nil, glossAlpha = 0,
                    showKeybinds = nil, hideEmptyKeybinds = nil, keybindFontSize = nil,
                    keybindColor = nil, keybindAnchor = nil, keybindOffsetX = nil, keybindOffsetY = nil,
                    showMacroNames = nil, macroNameFontSize = nil, macroNameColor = nil,
                    macroNameAnchor = nil, macroNameOffsetX = nil, macroNameOffsetY = nil,
                    showCounts = nil, countFontSize = nil, countColor = nil,
                    countAnchor = nil, countOffsetX = nil, countOffsetY = nil,
                },
                microbar = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    ownedPosition = nil,
                    clickthrough = false,
                    ownedLayout = {
                        orientation = "horizontal", columns = 12, iconCount = 12,
                        buttonSize = 32, buttonHeight = 40, buttonSpacing = -8,
                        growUp = false, growLeft = false,
                    },
                },
                bags = {
                    enabled = true, fadeEnabled = nil, fadeOutAlpha = nil, alwaysShow = false,
                    ownedPosition = nil,
                    ownedLayout = {
                        orientation = "horizontal", columns = 6, iconCount = 6,
                        buttonSize = 32, buttonSpacing = 2, growUp = false, growLeft = false,
                    },
                },
                -- Extra Action Button (boss encounters, quests)
                extraActionButton = {
                    enabled = true,
                    fadeEnabled = nil,
                    fadeOutAlpha = nil,
                    alwaysShow = true,
                    scale = 1.0,
                    offsetX = 0,
                    offsetY = 0,
                    position = { point = "CENTER", relPoint = "CENTER", x = -120.833, y = -25.833 },
                    hideArtwork = false,
                },
                -- Zone Ability Button (garrison, covenant, zone powers)
                zoneAbility = {
                    enabled = true,
                    fadeEnabled = nil,
                    fadeOutAlpha = nil,
                    alwaysShow = true,
                    scale = 1.0,
                    offsetX = 0,
                    offsetY = 0,
                    position = { point = "CENTER", relPoint = "CENTER", x = 150, y = -27.5 },
                    hideArtwork = false,
                },
            },
        },

        -- QUI Unit Frames (New Implementation)
        quiUnitFrames = {
            enabled = true,
            -- General settings (applies to all frames)
            general = {
                darkMode = false,                         -- Instant dark mode toggle (disabled by default)
                darkModeHealthColor = { 0.15, 0.15, 0.15, 1 },  -- #262626
                darkModeBgColor = { 0.25, 0.25, 0.25, 1 },      -- #404040
                darkModeOpacity = 1.0,                          -- Frame opacity when dark mode enabled (0.1 to 1.0)
                darkModeHealthOpacity = 1.0,                    -- Health bar opacity when dark mode enabled
                darkModeBgOpacity = 1.0,                        -- Background opacity when dark mode enabled
                -- Default unitframe colors (when dark mode is OFF)
                defaultUseClassColor = true,                    -- Use class color for health bar (default ON)
                defaultHealthColor = { 0.2, 0.2, 0.2, 1 },      -- Default health bar color (when class color OFF)
                defaultBgColor = { 0, 0, 0, 1 },                -- Default background color (pure black)
                defaultOpacity = 1.0,                           -- Default bar opacity
                defaultHealthOpacity = 1.0,                     -- Health bar opacity when dark mode disabled
                defaultBgOpacity = 1.0,                         -- Background opacity when dark mode disabled
                classColorText = false,                   -- LEGACY: Use class color for all unit frame text (kept for migration)
                -- Master text color overrides (new system - takes precedence over per-unit settings)
                masterColorNameText = false,              -- Apply class/reaction color to ALL name text
                masterColorHealthText = false,            -- Apply class/reaction color to ALL health text
                masterColorPowerText = false,             -- Apply class/reaction color to ALL power text
                masterColorCastbarText = false,           -- Apply class/reaction color to ALL castbar text (spell + timer)
                masterColorToTText = false,               -- Apply class/reaction color to ALL inline ToT text
                font = "Quazii",
                fontSize = 12,
                fontOutline = "OUTLINE",                  -- NONE, OUTLINE, THICKOUTLINE
                showTooltips = true,                      -- Show tooltips on unit frame mouseover
                smootherAnimation = false,                -- Uncap 60 FPS throttle for smoother castbar animation
                -- Hostility colors (for NPC unit frames)
                hostilityColorHostile = { 0.8, 0.2, 0.2, 1 },   -- Red (enemies)
                hostilityColorNeutral = { 1, 1, 0.2, 1 },       -- Yellow (neutral NPCs)
                hostilityColorFriendly = { 0.2, 0.8, 0.2, 1 },  -- Green (friendly NPCs)
            },
            -- Player frame settings
            player = {
                enabled = true,
                borderSize = 1,                     -- Frame border thickness (0-5)
                width = 240,
                height = 40,
                offsetX = -290,
                offsetY = -219,
                -- Anchor to frame (disabled, essential, utility, primary, secondary)
                anchorTo = "disabled",
                anchorGap = 10,
                anchorYOffset = 0,
                texture = "Quazii v5",
                useClassColor = true,
                customHealthColor = { 0.2, 0.6, 0.2, 1 },
                -- Portrait
                showPortrait = false,
                portraitSide = "LEFT",
                portraitSize = 40,
                portraitBorderSize = 1,
                portraitBorderUseClassColor = false,
                portraitBorderColor = { 0, 0, 0, 1 },
                portraitGap = 0,
                -- Name text
                showName = true,
                nameTextUseClassColor = false,
                nameTextColor = { 1, 1, 1, 1 },
                nameFontSize = 16,
                nameAnchor = "LEFT",
                nameOffsetX = 12,
                nameOffsetY = 0,
                maxNameLength = 0,              -- 0 = no limit, otherwise truncate to N characters
                -- Health text
                showHealth = true,
                showHealthPercent = true,
                showHealthAbsolute = true,
                healthDisplayStyle = "both",    -- "percent", "absolute", "both", "both_reverse"
                hideHealthPercentSymbol = false,
                healthDivider = " | ",          -- " | ", " - ", " / "
                healthFontSize = 16,
                healthAnchor = "RIGHT",
                healthOffsetX = -12,
                healthOffsetY = 0,
                healthTextUseClassColor = false, -- Independent from name class color
                healthTextColor = { 1, 1, 1, 1 }, -- Custom health text color
                -- Power text
                showPowerText = false,
                powerTextFormat = "percent",    -- "percent", "current", "both"
                hidePowerPercentSymbol = false,
                powerTextUsePowerColor = true,  -- Use power type color (mana blue, rage red, etc.)
                powerTextUseClassColor = false,
                powerTextColor = { 1, 1, 1, 1 },
                powerTextFontSize = 12,
                powerTextAnchor = "BOTTOMRIGHT",
                powerTextOffsetX = -9,
                powerTextOffsetY = 4,
                -- Power bar
                showPowerBar = false,
                powerBarHeight = 4,
                powerBarBorder = true,
                powerBarUsePowerColor = true,
                powerBarColor = { 0, 0.5, 1, 1 },  -- Custom power bar color
                -- Absorbs
                absorbs = {
                    enabled = false,
                    color = { 1, 1, 1, 1 },
                    opacity = 0.3,
                    texture = "QUI Stripes",
                },
                -- Heal prediction (incoming heals)
                healPrediction = {
                    enabled = false,
                    color = { 0.2, 1, 0.2 },
                    opacity = 0.5,
                },
                -- Castbar
                castbar = {
                    enabled = true,
                    showIcon = true,
                    width = 333,
                    height = 25,
                    offsetX = 0,
                    offsetY = -35,
                    widthAdjustment = 0,
                    fontSize = 14,
                    color = {0.404, 1, 0.984, 1},  -- Cyan color from your profile
                    anchor = "none",
                    texture = "Quazii v5",
                    bgColor = {0.149, 0.149, 0.149, 1},
                    borderSize = 1,
                    useClassColor = false,
                    highlightInterruptible = false,
                    interruptibleColor = {0.2, 0.8, 0.2, 1},
                    maxLength = 0,
                },
                -- Auras (buffs/debuffs)
                auras = {
                    showBuffs = false,
                    showDebuffs = false,
                    -- Debuff settings
                    iconSize = 22,
                    debuffAnchor = "TOPLEFT",
                    debuffGrow = "RIGHT",
                    debuffMaxIcons = 4,
                    debuffMaxPerRow = 0,  -- 0 = unlimited (no row wrapping)
                    debuffOffsetX = 0,
                    debuffOffsetY = 0,
                    -- Buff settings
                    buffIconSize = 22,
                    buffAnchor = "BOTTOMLEFT",
                    buffGrow = "RIGHT",
                    buffMaxIcons = 4,
                    buffMaxPerRow = 0,  -- 0 = unlimited (no row wrapping)
                    buffOffsetX = 0,
                    buffOffsetY = 0,
                    -- Duration text
                    iconSpacing = 2,
                    buffSpacing = 2,
                    debuffSpacing = 2,
                    durationColor = {1, 1, 1, 1},
                    showDuration = false,
                    durationSize = 12,
                    durationAnchor = "CENTER",
                    durationOffsetX = 0,
                    durationOffsetY = 0,
                    -- Stack text
                    stackColor = {1, 1, 1, 1},
                    showStack = true,
                    stackSize = 10,
                    stackAnchor = "BOTTOMRIGHT",
                    stackOffsetX = -1,
                    stackOffsetY = 1,
                    -- Buff duration/stack
                    buffDuration = { show = true, fontSize = 12, anchor = "CENTER", offsetX = 0, offsetY = 0, color = {1, 1, 1, 1} },
                    buffStack = { show = true, fontSize = 10, anchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 1, color = {1, 1, 1, 1} },
                    buffShowStack = true,
                    buffStackSize = 10,
                    buffStackAnchor = "BOTTOMRIGHT",
                    buffStackOffsetX = -1,
                    buffStackOffsetY = 1,
                    buffStackColor = {1, 1, 1, 1},
                    -- Debuff duration/stack
                    debuffDuration = { show = false, fontSize = 10, anchor = "CENTER", offsetX = 0, offsetY = 0, color = {1, 1, 1, 1} },
                    debuffStack = { show = true, fontSize = 10, anchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 1, color = {1, 1, 1, 1} },
                    debuffShowStack = true,
                    debuffStackSize = 10,
                    debuffStackAnchor = "BOTTOMRIGHT",
                    debuffStackOffsetX = -1,
                    debuffStackOffsetY = 1,
                    debuffStackColor = {1, 1, 1, 1},
                },
                -- Status indicators (player only)
                indicators = {
                    rested = {
                        enabled = false,      -- Disabled by default
                        size = 16,
                        anchor = "TOPLEFT",
                        offsetX = -2,
                        offsetY = 2,
                    },
                    combat = {
                        enabled = false,      -- Disabled by default
                        size = 16,
                        anchor = "TOPRIGHT",
                        offsetX = -2,
                        offsetY = 2,
                    },
                    stance = {
                        enabled = false,      -- Disabled by default (opt-in)
                        fontSize = 12,
                        anchor = "BOTTOM",
                        offsetX = 0,
                        offsetY = -2,
                        useClassColor = true,
                        customColor = { 1, 1, 1, 1 },
                        showIcon = false,
                        iconSize = 14,
                        iconOffsetX = -2,
                    },
                },
                -- Target marker (raid icons like skull, cross, etc.)
                targetMarker = {
                    enabled = false,    -- Disabled by default for player (rarely marked)
                    size = 20,
                    anchor = "TOP",
                    xOffset = 0,
                    yOffset = 8,
                },
                -- Leader/Assistant icon (crown for leader, flag for assistant)
                leaderIcon = {
                    enabled = false,
                    size = 16,
                    anchor = "TOPLEFT",
                    xOffset = -8,
                    yOffset = 8,
                },
            },
            -- Target frame settings
            target = {
                enabled = true,
                borderSize = 1,                     -- Frame border thickness (0-5)
                width = 240,
                height = 40,
                offsetX = 290,
                offsetY = -219,
                -- Anchor to frame (disabled, essential, utility, primary, secondary)
                anchorTo = "disabled",
                anchorGap = 10,
                anchorYOffset = 0,
                texture = "Quazii v5 Inverse",
                invertHealthDirection = false,   -- false = default right-to-left depletion, true = left-to-right
                useClassColor = true,
                useHostilityColor = true,  -- Use red/yellow/green based on unit hostility
                customHealthColor = { 0.2, 0.6, 0.2, 1 },
                -- Portrait
                showPortrait = false,
                portraitSide = "RIGHT",
                portraitSize = 40,
                portraitBorderSize = 1,
                portraitBorderUseClassColor = false,
                portraitBorderColor = { 0, 0, 0, 1 },
                portraitGap = 0,
                -- Name text
                showName = true,
                nameTextUseClassColor = false,
                nameTextColor = { 1, 1, 1, 1 },
                nameFontSize = 16,
                nameAnchor = "RIGHT",
                nameOffsetX = -9,
                nameOffsetY = 0,
                maxNameLength = 10,              -- 0 = no limit, otherwise truncate to N characters
                -- Inline Target of Target (shows ">> ToT Name" after target name)
                showInlineToT = false,
                totSeparator = " >> ",
                totUseClassColor = true,
                totDividerUseClassColor = false,    -- Color divider by class/reaction
                totDividerColor = {1, 1, 1, 1},     -- Custom divider color (white default)
                totNameCharLimit = 0,               -- 0 = no limit, otherwise limit ToT name length
                -- Health text
                showHealth = true,
                showHealthPercent = true,
                showHealthAbsolute = true,
                healthDisplayStyle = "both",    -- "percent", "absolute", "both", "both_reverse"
                hideHealthPercentSymbol = false,
                healthDivider = " | ",          -- " | ", " - ", " / "
                healthFontSize = 16,
                healthAnchor = "LEFT",
                healthOffsetX = 9,
                healthOffsetY = 0,
                healthTextUseClassColor = false, -- Independent from name class color
                healthTextColor = { 1, 1, 1, 1 }, -- Custom health text color
                -- Power text
                showPowerText = false,
                powerTextFormat = "percent",    -- "percent", "current", "both"
                hidePowerPercentSymbol = false,
                powerTextUsePowerColor = false,  -- Use power type color (mana blue, rage red, etc.)
                powerTextUseClassColor = false,
                powerTextColor = { 1, 1, 1, 1 },
                powerTextFontSize = 14,
                powerTextAnchor = "BOTTOMRIGHT",
                powerTextOffsetX = -2,
                powerTextOffsetY = 2,
                -- Power bar
                showPowerBar = false,
                powerBarHeight = 4,
                powerBarBorder = true,
                powerBarUsePowerColor = true,
                powerBarColor = { 0, 0.5, 1, 1 },  -- Custom power bar color
                -- Absorbs
                absorbs = {
                    enabled = true,
                    color = { 1, 1, 1, 1 },
                    opacity = 0.3,
                    texture = "QUI Stripes",
                },
                -- Heal prediction (incoming heals)
                healPrediction = {
                    enabled = false,
                    color = { 0.2, 1, 0.2 },
                    opacity = 0.5,
                },
                -- Castbar
                castbar = {
                    enabled = true,
                    showIcon = true,
                    width = 245,
                    height = 25,
                    offsetX = 0,
                    offsetY = 0,
                    widthAdjustment = 0,
                    fontSize = 14,
                    color = {0.2, 0.6, 1, 1},
                    notInterruptibleColor = {0.7, 0.2, 0.2, 1},
                    anchor = "unitframe",
                    texture = "Quazii v5",
                    bgColor = {0.149, 0.149, 0.149, 1},
                    borderSize = 1,
                    highlightInterruptible = true,
                    interruptibleColor = {0.2, 0.8, 0.2, 1},
                    maxLength = 12,
                },
                -- Auras (buffs/debuffs)
                auras = {
                    showBuffs = false,
                    showDebuffs = false,
                    -- Debuff settings
                    iconSize = 26,
                    debuffAnchor = "TOPLEFT",
                    debuffGrow = "RIGHT",
                    debuffMaxIcons = 4,
                    debuffOffsetX = 0,
                    debuffOffsetY = 0,
                    -- Buff settings
                    buffIconSize = 18,
                    buffAnchor = "BOTTOMLEFT",
                    buffGrow = "RIGHT",
                    buffMaxIcons = 4,
                    buffOffsetX = 0,
                    buffOffsetY = 0,
                    -- Duration text
                    iconSpacing = 2,
                    buffSpacing = 2,
                    debuffSpacing = 2,
                    durationColor = {1, 1, 1, 1},
                    showDuration = false,
                    durationSize = 12,
                    durationAnchor = "CENTER",
                    durationOffsetX = 0,
                    durationOffsetY = 0,
                    -- Stack text
                    stackColor = {1, 1, 1, 1},
                    showStack = true,
                    stackSize = 10,
                    stackAnchor = "BOTTOMRIGHT",
                    stackOffsetX = -1,
                    stackOffsetY = 1,
                    -- Buff duration/stack
                    buffDuration = { show = true, fontSize = 12, anchor = "CENTER", offsetX = 0, offsetY = 0, color = {1, 1, 1, 1} },
                    buffStack = { show = true, fontSize = 10, anchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 1, color = {1, 1, 1, 1} },
                    buffShowStack = true,
                    buffStackSize = 10,
                    buffStackAnchor = "BOTTOMRIGHT",
                    buffStackOffsetX = -1,
                    buffStackOffsetY = 1,
                    buffStackColor = {1, 1, 1, 1},
                    -- Debuff duration/stack
                    debuffDuration = { show = false, fontSize = 10, anchor = "CENTER", offsetX = 0, offsetY = 0, color = {1, 1, 1, 1} },
                    debuffStack = { show = true, fontSize = 10, anchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 1, color = {1, 1, 1, 1} },
                    debuffShowStack = true,
                    debuffStackSize = 10,
                    debuffStackAnchor = "BOTTOMRIGHT",
                    debuffStackOffsetX = -1,
                    debuffStackOffsetY = 1,
                    debuffStackColor = {1, 1, 1, 1},
                },
                -- Target marker (raid icons like skull, cross, etc.)
                targetMarker = {
                    enabled = false,
                    size = 20,
                    anchor = "TOP",
                    xOffset = 0,
                    yOffset = 8,
                },
                -- Leader/Assistant icon (crown for leader, flag for assistant)
                leaderIcon = {
                    enabled = false,
                    size = 16,
                    anchor = "TOPLEFT",
                    xOffset = -8,
                    yOffset = 8,
                },
                -- Classification icon (elite/rare/boss indicator)
                classificationIcon = {
                    enabled = false,
                    size = 16,
                    anchor = "LEFT",
                    xOffset = -8,
                    yOffset = 0,
                },
            },
            -- Target of Target
            targettarget = {
                enabled = false,
                borderSize = 1,                     -- Frame border thickness (0-5)
                width = 160,
                height = 30,
                offsetX = 496,
                offsetY = -214,
                texture = "Quazii",
                useClassColor = true,
                useHostilityColor = true,  -- Use red/yellow/green based on unit hostility
                customHealthColor = { 0.2, 0.6, 0.2, 1 },
                -- Name text
                showName = true,
                nameTextUseClassColor = false,
                nameTextColor = { 1, 1, 1, 1 },
                nameFontSize = 14,
                nameAnchor = "LEFT",
                nameOffsetX = 4,
                nameOffsetY = 0,
                maxNameLength = 0,
                -- Health text
                showHealth = true,
                showHealthPercent = true,
                showHealthAbsolute = false,
                healthDisplayStyle = "percent",
                hideHealthPercentSymbol = false,
                healthDivider = " | ",
                healthFontSize = 14,
                healthAnchor = "RIGHT",
                healthOffsetX = -4,
                healthOffsetY = 0,
                healthTextUseClassColor = false,
                healthTextColor = { 1, 1, 1, 1 },
                -- Power text
                showPowerText = false,
                powerTextFormat = "percent",
                hidePowerPercentSymbol = false,
                powerTextUsePowerColor = true,
                powerTextUseClassColor = false,
                powerTextColor = { 1, 1, 1, 1 },
                powerTextFontSize = 10,
                powerTextAnchor = "BOTTOMRIGHT",
                powerTextOffsetX = -4,
                powerTextOffsetY = 2,
                -- Power bar
                showPowerBar = false,
                powerBarHeight = 3,
                powerBarBorder = true,
                powerBarUsePowerColor = true,
                powerBarColor = { 0, 0.5, 1, 1 },  -- Custom power bar color
                -- Absorbs
                absorbs = {
                    enabled = true,
                    color = { 1, 1, 1, 1 },
                    opacity = 0.7,
                    texture = "QUI Stripes",
                },
                -- Castbar
                castbar = {
                    enabled = false,
                    showIcon = true,
                    width = 50,
                    height = 12,
                    offsetX = 0,
                    offsetY = -20,
                    widthAdjustment = 0,
                    fontSize = 10,
                    color = {1, 0.7, 0, 1},
                    anchor = "unitframe",
                },
                -- Auras (buffs/debuffs)
                auras = {
                    showBuffs = false,
                    showDebuffs = false,
                    -- Debuff settings
                    iconSize = 22,
                    debuffAnchor = "TOPLEFT",
                    debuffGrow = "RIGHT",
                    debuffMaxIcons = 4,
                    debuffOffsetX = 0,
                    debuffOffsetY = 0,
                    -- Buff settings
                    buffIconSize = 22,
                    buffAnchor = "BOTTOMLEFT",
                    buffGrow = "RIGHT",
                    buffMaxIcons = 4,
                    buffOffsetX = 0,
                    buffOffsetY = 0,
                },
                -- Target marker (raid icons like skull, cross, etc.)
                targetMarker = {
                    enabled = false,    -- Disabled by default for ToT (small frame)
                    size = 16,
                    anchor = "TOP",
                    xOffset = 0,
                    yOffset = 6,
                },
            },
            -- Pet frame
            pet = {
                enabled = true,
                borderSize = 1,                     -- Frame border thickness (0-5)
                width = 140,
                height = 25,
                offsetX = -340,
                offsetY = -254,
                texture = "Quazii",
                useClassColor = true,
                useHostilityColor = true,
                customHealthColor = { 0.2, 0.6, 0.2, 1 },
                -- Name text
                showName = true,
                nameTextUseClassColor = false,
                nameTextColor = { 1, 1, 1, 1 },
                nameFontSize = 10,
                nameAnchor = "LEFT",
                nameOffsetX = 4,
                nameOffsetY = 0,
                maxNameLength = 0,
                -- Health text
                showHealth = true,
                showHealthPercent = true,
                showHealthAbsolute = false,
                healthDisplayStyle = "percent",
                hideHealthPercentSymbol = false,
                healthDivider = " | ",
                healthFontSize = 10,
                healthAnchor = "RIGHT",
                healthOffsetX = -4,
                healthOffsetY = 0,
                healthTextUseClassColor = false,
                healthTextColor = { 1, 1, 1, 1 },
                -- Power text
                showPowerText = false,
                powerTextFormat = "percent",
                hidePowerPercentSymbol = false,
                powerTextUsePowerColor = true,
                powerTextUseClassColor = false,
                powerTextColor = { 1, 1, 1, 1 },
                powerTextFontSize = 10,
                powerTextAnchor = "BOTTOMRIGHT",
                powerTextOffsetX = -4,
                powerTextOffsetY = 2,
                -- Power bar
                showPowerBar = true,
                powerBarHeight = 3,
                powerBarBorder = true,
                powerBarUsePowerColor = true,
                powerBarColor = { 0, 0.5, 1, 1 },  -- Custom power bar color
                -- Absorbs
                absorbs = {
                    enabled = true,
                    color = { 1, 1, 1 },
                    opacity = 0.7,
                    texture = "QUI Stripes",
                },
                -- Castbar
                castbar = {
                    enabled = false,
                    showIcon = true,
                    width = 140,
                    height = 12,
                    offsetX = 0,
                    offsetY = -20,
                    widthAdjustment = 0,
                    fontSize = 10,
                    color = {1, 0.7, 0, 1},
                    anchor = "unitframe",
                },
                -- Auras (buffs/debuffs)
                auras = {
                    showBuffs = false,
                    showDebuffs = false,
                    -- Debuff settings
                    iconSize = 22,
                    debuffAnchor = "TOPLEFT",
                    debuffGrow = "RIGHT",
                    debuffMaxIcons = 4,
                    debuffOffsetX = 0,
                    debuffOffsetY = 0,
                    -- Buff settings
                    buffIconSize = 22,
                    buffAnchor = "BOTTOMLEFT",
                    buffGrow = "RIGHT",
                    buffMaxIcons = 4,
                    buffOffsetX = 0,
                    buffOffsetY = 0,
                },
                -- Target marker (raid icons like skull, cross, etc.)
                targetMarker = {
                    enabled = false,    -- Disabled by default for pet (rarely marked)
                    size = 16,
                    anchor = "TOP",
                    xOffset = 0,
                    yOffset = 6,
                },
                -- Castbar (opt-in for vehicle/RP casts)
                castbar = {
                    enabled = false,  -- Disabled by default (opt-in feature)
                    showIcon = true,
                    width = 140,
                    height = 15,
                    offsetX = 0,
                    offsetY = -20,
                    widthAdjustment = 0,
                    fontSize = 10,
                    color = {0.404, 1, 0.984, 1},
                },
            },
            -- Focus frame
            focus = {
                enabled = false,
                borderSize = 1,                     -- Frame border thickness (0-5)
                width = 160,
                height = 30,
                offsetX = -496,
                offsetY = -214,
                texture = "Quazii v5",
                useClassColor = true,
                useHostilityColor = true,  -- Use red/yellow/green based on unit hostility
                customHealthColor = { 0.2, 0.6, 0.2, 1 },
                -- Portrait
                showPortrait = false,
                portraitSide = "RIGHT",
                portraitSize = 30,
                portraitBorderSize = 1,
                portraitBorderUseClassColor = false,
                portraitBorderColor = { 0, 0, 0, 1 },
                portraitGap = 0,
                -- Name text
                showName = true,
                nameTextUseClassColor = false,
                nameTextColor = { 1, 1, 1, 1 },
                nameFontSize = 14,
                nameAnchor = "LEFT",
                nameOffsetX = 4,
                nameOffsetY = 0,
                maxNameLength = 0,
                -- Health text
                showHealth = true,
                showHealthPercent = true,
                showHealthAbsolute = true,
                healthDisplayStyle = "percent",
                hideHealthPercentSymbol = false,
                healthDivider = " | ",
                healthFontSize = 14,
                healthAnchor = "RIGHT",
                healthOffsetX = -4,
                healthOffsetY = 0,
                healthTextUseClassColor = false,
                healthTextColor = { 1, 1, 1, 1 },
                -- Power text
                showPowerText = false,
                powerTextFormat = "percent",
                hidePowerPercentSymbol = false,
                powerTextUsePowerColor = true,
                powerTextUseClassColor = false,
                powerTextColor = { 1, 1, 1, 1 },
                powerTextFontSize = 10,
                powerTextAnchor = "BOTTOMRIGHT",
                powerTextOffsetX = -4,
                powerTextOffsetY = 2,
                -- Power bar
                showPowerBar = true,
                powerBarHeight = 3,
                powerBarBorder = true,
                powerBarUsePowerColor = true,
                powerBarColor = { 0, 0.5, 1, 1 },  -- Custom power bar color
                -- Absorbs
                absorbs = {
                    enabled = true,
                    color = { 1, 1, 1, 1 },
                    opacity = 0.7,
                    texture = "QUI Stripes",
                },
                -- Castbar
                castbar = {
                    enabled = true,
                    showIcon = false,
                    width = 160,
                    height = 20,
                    offsetX = 0,
                    offsetY = 0,
                    widthAdjustment = 0,
                    fontSize = 14,
                    color = {0.2, 0.6, 1, 1},
                    notInterruptibleColor = {0.7, 0.2, 0.2, 1},
                    anchor = "unitframe",
                },
                -- Auras (buffs/debuffs)
                auras = {
                    showBuffs = false,
                    showDebuffs = false,
                    -- Debuff settings
                    iconSize = 20,
                    debuffAnchor = "TOPLEFT",
                    debuffGrow = "RIGHT",
                    debuffMaxIcons = 16,
                    debuffOffsetX = 0,
                    debuffOffsetY = 2,
                    -- Buff settings
                    buffIconSize = 20,
                    buffAnchor = "BOTTOMLEFT",
                    buffGrow = "RIGHT",
                    buffMaxIcons = 16,
                    buffOffsetX = 0,
                    buffOffsetY = -2,
                },
                -- Target marker (raid icons like skull, cross, etc.)
                targetMarker = {
                    enabled = false,
                    size = 18,
                    anchor = "TOP",
                    xOffset = 0,
                    yOffset = 6,
                },
                -- Leader/Assistant icon (crown for leader, flag for assistant)
                leaderIcon = {
                    enabled = false,
                    size = 16,
                    anchor = "TOPLEFT",
                    xOffset = -8,
                    yOffset = 8,
                },
                -- Classification icon (elite/rare/boss indicator)
                classificationIcon = {
                    enabled = false,
                    size = 16,
                    anchor = "LEFT",
                    xOffset = -8,
                    yOffset = 0,
                },
            },
            -- Boss frames
            boss = {
                enabled = true,
                borderSize = 1,                     -- Frame border thickness (0-5)
                width = 162,
                height = 36,
                offsetX = 974,
                offsetY = 106,
                spacing = 35,           -- Vertical spacing between boss frames
                texture = "Quazii v5",
                useClassColor = true,
                useHostilityColor = true,
                customHealthColor = { 0.6, 0.2, 0.2, 1 },
                -- Name text
                showName = true,
                nameTextUseClassColor = false,
                nameTextColor = { 1, 1, 1, 1 },
                nameFontSize = 11,
                nameAnchor = "LEFT",
                nameOffsetX = 4,
                nameOffsetY = 0,
                maxNameLength = 0,
                -- Health text
                showHealth = true,
                healthDisplayStyle = "both",
                hideHealthPercentSymbol = false,
                healthDivider = " | ",
                healthFontSize = 11,
                healthAnchor = "RIGHT",
                healthOffsetX = -4,
                healthOffsetY = 0,
                healthTextUseClassColor = false,
                healthTextColor = { 1, 1, 1, 1 },
                -- Power text
                showPowerText = false,
                powerTextFormat = "percent",
                hidePowerPercentSymbol = false,
                powerTextUsePowerColor = true,
                powerTextUseClassColor = false,
                powerTextColor = { 1, 1, 1, 1 },
                powerTextFontSize = 10,
                powerTextAnchor = "BOTTOMRIGHT",
                powerTextOffsetX = -4,
                powerTextOffsetY = 2,
                -- Power bar
                showPowerBar = true,
                powerBarHeight = 3,
                powerBarBorder = true,
                powerBarUsePowerColor = true,
                powerBarColor = { 0, 0.5, 1, 1 },  -- Custom power bar color
                -- Absorbs
                absorbs = {
                    enabled = true,
                    color = { 1, 1, 1 },
                    opacity = 0.7,
                    texture = "QUI Stripes",
                },
                -- Castbar
                castbar = {
                    enabled = true,
                    showIcon = true,
                    width = 162,
                    height = 16,
                    offsetX = 0,
                    offsetY = 0,
                    widthAdjustment = 0,
                    fontSize = 11,
                    color = {1, 0.7, 0, 1},
                    anchor = "unitframe",
                },
                -- Auras (buffs/debuffs)
                auras = {
                    showBuffs = false,
                    showDebuffs = false,
                    -- Debuff settings
                    iconSize = 22,
                    debuffAnchor = "TOPLEFT",
                    debuffGrow = "RIGHT",
                    debuffMaxIcons = 4,
                    debuffOffsetX = 0,
                    debuffOffsetY = 0,
                    -- Buff settings
                    buffIconSize = 22,
                    buffAnchor = "BOTTOMLEFT",
                    buffGrow = "RIGHT",
                    buffMaxIcons = 4,
                    buffOffsetX = 0,
                    buffOffsetY = 0,
                },
                -- Target marker (raid icons like skull, cross, etc.)
                targetMarker = {
                    enabled = false,
                    size = 20,
                    anchor = "TOP",
                    xOffset = 0,
                    yOffset = 8,
                },
                -- Classification icon (elite/rare/boss indicator)
                classificationIcon = {
                    enabled = false,
                    size = 16,
                    anchor = "LEFT",
                    xOffset = -8,
                    yOffset = 0,
                },
                -- Target highlight (border when boss is your current target)
                targetHighlight = {
                    enabled = true,
                    color = { 1, 1, 1, 0.6 },
                },
            },
        },

        -- QUI Group Frames (party/raid)
        quiGroupFrames = {
            enabled = false,          -- Disabled by default (opt-in feature)

            -- Position
            position = { offsetX = -400, offsetY = 0 },      -- party position
            raidPosition = { offsetX = -400, offsetY = 0 },   -- raid position (always separate)

            -- Self-first toggles split by mode. Party keeps the separate self header;
            -- raid uses its own ordering path and should never render a duplicate lead block.
            partySelfFirst = false,
            raidSelfFirst = false,

            -------------------------------------------------------------------
            -- Party visual settings
            -------------------------------------------------------------------
            party = {
                general = {
                    useClassColor = true,
                    texture = "Quazii v5",
                    borderSize = 1,
                    font = "Quazii",
                    fontSize = 12,
                    fontOutline = "OUTLINE",
                    showTooltips = true,
                    darkMode = false,
                    darkModeHealthColor = { 0.15, 0.15, 0.15, 1 },
                    darkModeBgColor = { 0.25, 0.25, 0.25, 1 },
                    darkModeHealthOpacity = 1.0,
                    darkModeBgOpacity = 1.0,
                    defaultBgColor = { 0, 0, 0, 1 },
                    defaultHealthOpacity = 1.0,
                    defaultBgOpacity = 1.0,
                },
                layout = {
                    growDirection = "DOWN",
                    spacing = 2,
                    showPlayer = true,
                    showSolo = false,
                    sortMethod = "INDEX",
                    sortByRole = true,
                    groupBy = "GROUP",
                },
                health = {
                    showHealthText = true,
                    healthDisplayStyle = "percent",
                    healthFontSize = 12,
                    healthAnchor = "RIGHT",
                    healthJustify = "RIGHT",
                    healthOffsetX = -4,
                    healthOffsetY = 0,
                    healthTextColor = { 1, 1, 1, 1 },
                    healthFillDirection = "HORIZONTAL",
                    hideHealthPercentSymbol = false,
                },
                power = {
                    showPowerBar = true,
                    powerBarHeight = 4,
                    powerBarUsePowerColor = true,
                    powerBarColor = { 0.2, 0.4, 0.8, 1 },
                    powerBarOnlyHealers = false,
                    powerBarOnlyTanks = false,
                },
                name = {
                    showName = true,
                    nameFontSize = 12,
                    nameAnchor = "LEFT",
                    nameJustify = "LEFT",
                    nameOffsetX = 4,
                    nameOffsetY = 0,
                    maxNameLength = 10,
                    nameTextUseClassColor = false,
                    nameTextColor = { 1, 1, 1, 1 },
                },
                absorbs = { enabled = true, color = { 1, 1, 1, 1 }, opacity = 0.3 },
                healAbsorbs = { enabled = true, color = { 0.5, 0.1, 0.1 }, opacity = 0.6 },
                healPrediction = { enabled = true, color = { 0.2, 1, 0.2 }, opacity = 0.5 },
                indicators = {
                    showRoleIcon = true, roleIconSize = 12, roleIconAnchor = "TOPLEFT", roleIconOffsetX = 2, roleIconOffsetY = -2,
                    showRoleTank = true, showRoleHealer = true, showRoleDPS = true,
                    showReadyCheck = true, readyCheckSize = 16, readyCheckAnchor = "CENTER", readyCheckOffsetX = 0, readyCheckOffsetY = 0,
                    showResurrection = true, resurrectionSize = 16, resurrectionAnchor = "CENTER", resurrectionOffsetX = 0, resurrectionOffsetY = 0,
                    showSummonPending = true, summonSize = 20, summonAnchor = "CENTER", summonOffsetX = 16, summonOffsetY = 0,
                    showLeaderIcon = true, leaderSize = 12, leaderAnchor = "TOP", leaderOffsetX = 0, leaderOffsetY = 6,
                    showTargetMarker = true, targetMarkerSize = 14, targetMarkerAnchor = "TOPRIGHT", targetMarkerOffsetX = -2, targetMarkerOffsetY = -2,
                    showThreatBorder = true, threatBorderSize = 3, threatColor = { 1, 0, 0, 0.8 }, threatFillOpacity = 0.15,
                    showPhaseIcon = true, phaseSize = 16, phaseAnchor = "BOTTOMLEFT", phaseOffsetX = 2, phaseOffsetY = 2,
                },
                healer = {
                    dispelOverlay = {
                        enabled = true, opacity = 0.8, fillOpacity = 0.18, borderSize = 3,
                        colors = {
                            Magic   = { 0.2, 0.6, 1.0, 1 },
                            Curse   = { 0.6, 0.0, 1.0, 1 },
                            Disease = { 0.6, 0.4, 0.0, 1 },
                            Poison  = { 0.0, 0.6, 0.0, 1 },
                        },
                    },
                    targetHighlight = { enabled = true, color = { 1, 1, 1, 0.6 }, fillOpacity = 0.12 },
                    defensiveIndicator = { enabled = false, iconSize = 16, maxIcons = 3, spacing = 2, growDirection = "RIGHT", position = "CENTER", offsetX = 0, offsetY = 0, reverseSwipe = true },
                },
                classPower = { enabled = false, height = 4, spacing = 1 },
                range = { enabled = true, outOfRangeAlpha = 0.4 },
                auras = {
                    showDebuffs = true, maxDebuffs = 3, debuffIconSize = 16,
                    debuffAnchor = "BOTTOMRIGHT", debuffGrowDirection = "LEFT",
                    debuffSpacing = 2, debuffOffsetX = -2, debuffOffsetY = -18,
                    debuffReverseSwipe = false,
                    showBuffs = false, maxBuffs = 0, buffIconSize = 14,
                    buffAnchor = "TOPLEFT", buffGrowDirection = "RIGHT",
                    buffSpacing = 2, buffOffsetX = 2, buffOffsetY = 16,
                    buffReverseSwipe = false,
                    showDurationColor = true,
                    showExpiringPulse = true,
                    showDurationText = true,
                    durationFontSize = 9,
                    filterMode = "off",
                    buffFilterOnlyMine = false,
                    buffHidePermanent = false,
                    buffDeduplicateDefensives = true,
                    buffClassifications = { raid = false, cancelable = false, important = false },
                    debuffClassifications = { raid = true, crowdControl = true, important = true },
                    buffWhitelist = {},
                    buffBlacklist = {},
                    debuffWhitelist = {},
                    debuffBlacklist = {},
                },
                privateAuras = {
                    enabled = true,
                    maxPerFrame = 2,
                    iconSize = 20,
                    growDirection = "RIGHT",
                    spacing = 2,
                    anchor = "RIGHT",
                    anchorOffsetX = -2,
                    anchorOffsetY = 0,
                    showCountdown = true,
                    showCountdownNumbers = true,
                    reverseSwipe = false,
                    borderScale = 1,
                    textScale = 2,
                    textOffsetX = 0,
                    textOffsetY = 0,
                },
                auraIndicators = {
                    enabled = false,
                    iconSize = 14,
                    anchor = "TOPLEFT",
                    anchorOffsetX = 0,
                    anchorOffsetY = 0,
                    growDirection = "RIGHT",
                    spacing = 2,
                    maxIndicators = 5,
                    reverseSwipe = false,
                    trackedSpells = {},
                    entries = {},
                },
                pinnedAuras = {
                    enabled = false,
                    slotSize = 8,
                    edgeInset = 2,
                    showSwipe = true,
                    reverseSwipe = false,
                    specSlots = {},
                },
                castbar = { enabled = false, height = 8, showIcon = false, showText = false },
                portrait = { showPortrait = false, portraitSide = "LEFT", portraitSize = 30 },
                pets = {
                    enabled = false,
                    width = 100, height = 20,
                    showPowerBar = false,
                    showAuras = false,
                    anchorTo = "BOTTOM",
                    anchorGap = 2,
                },
                dimensions = {
                    partyWidth = 200, partyHeight = 40,
                },
            },

            -------------------------------------------------------------------
            -- Raid visual settings
            -------------------------------------------------------------------
            raid = {
                general = {
                    useClassColor = true,
                    texture = "Quazii v5",
                    borderSize = 1,
                    font = "Quazii",
                    fontSize = 12,
                    fontOutline = "OUTLINE",
                    showTooltips = true,
                    darkMode = false,
                    darkModeHealthColor = { 0.15, 0.15, 0.15, 1 },
                    darkModeBgColor = { 0.25, 0.25, 0.25, 1 },
                    darkModeHealthOpacity = 1.0,
                    darkModeBgOpacity = 1.0,
                    defaultBgColor = { 0, 0, 0, 1 },
                    defaultHealthOpacity = 1.0,
                    defaultBgOpacity = 1.0,
                },

                layout = {
                    growDirection = "DOWN",
                    groupGrowDirection = "RIGHT",
                    spacing = 2,
                    groupSpacing = 10,
                    sortMethod = "INDEX",
                    sortByRole = true,
                    groupBy = "GROUP",
                    unitsPerFlat = 5,
                },
                health = {
                    showHealthText = true,
                    healthDisplayStyle = "percent",
                    healthFontSize = 12,
                    healthAnchor = "RIGHT",
                    healthJustify = "RIGHT",
                    healthOffsetX = -4,
                    healthOffsetY = 0,
                    healthTextColor = { 1, 1, 1, 1 },
                    healthFillDirection = "HORIZONTAL",
                    hideHealthPercentSymbol = false,
                },
                power = {
                    showPowerBar = true,
                    powerBarHeight = 4,
                    powerBarUsePowerColor = true,
                    powerBarColor = { 0.2, 0.4, 0.8, 1 },
                    powerBarOnlyHealers = false,
                    powerBarOnlyTanks = false,
                },
                name = {
                    showName = true,
                    nameFontSize = 12,
                    nameAnchor = "LEFT",
                    nameJustify = "LEFT",
                    nameOffsetX = 4,
                    nameOffsetY = 0,
                    maxNameLength = 10,
                    nameTextUseClassColor = false,
                    nameTextColor = { 1, 1, 1, 1 },
                },
                absorbs = { enabled = true, color = { 1, 1, 1, 1 }, opacity = 0.3 },
                healAbsorbs = { enabled = true, color = { 0.5, 0.1, 0.1 }, opacity = 0.6 },
                healPrediction = { enabled = true, color = { 0.2, 1, 0.2 }, opacity = 0.5 },
                indicators = {
                    showRoleIcon = true, roleIconSize = 12, roleIconAnchor = "TOPLEFT", roleIconOffsetX = 2, roleIconOffsetY = -2,
                    showRoleTank = true, showRoleHealer = true, showRoleDPS = true,
                    showReadyCheck = true, readyCheckSize = 16, readyCheckAnchor = "CENTER", readyCheckOffsetX = 0, readyCheckOffsetY = 0,
                    showResurrection = true, resurrectionSize = 16, resurrectionAnchor = "CENTER", resurrectionOffsetX = 0, resurrectionOffsetY = 0,
                    showSummonPending = true, summonSize = 20, summonAnchor = "CENTER", summonOffsetX = 16, summonOffsetY = 0,
                    showLeaderIcon = true, leaderSize = 12, leaderAnchor = "TOP", leaderOffsetX = 0, leaderOffsetY = 6,
                    showTargetMarker = true, targetMarkerSize = 14, targetMarkerAnchor = "TOPRIGHT", targetMarkerOffsetX = -2, targetMarkerOffsetY = -2,
                    showThreatBorder = true, threatBorderSize = 3, threatColor = { 1, 0, 0, 0.8 }, threatFillOpacity = 0.15,
                    showPhaseIcon = true, phaseSize = 16, phaseAnchor = "BOTTOMLEFT", phaseOffsetX = 2, phaseOffsetY = 2,
                },
                healer = {
                    dispelOverlay = {
                        enabled = true, opacity = 0.8, fillOpacity = 0.18, borderSize = 3,
                        colors = {
                            Magic   = { 0.2, 0.6, 1.0, 1 },
                            Curse   = { 0.6, 0.0, 1.0, 1 },
                            Disease = { 0.6, 0.4, 0.0, 1 },
                            Poison  = { 0.0, 0.6, 0.0, 1 },
                        },
                    },
                    targetHighlight = { enabled = true, color = { 1, 1, 1, 0.6 }, fillOpacity = 0.12 },
                    defensiveIndicator = { enabled = false, iconSize = 16, maxIcons = 3, spacing = 2, growDirection = "RIGHT", position = "CENTER", offsetX = 0, offsetY = 0, reverseSwipe = true },
                },
                classPower = { enabled = false, height = 4, spacing = 1 },
                range = { enabled = true, outOfRangeAlpha = 0.4 },
                auras = {
                    showDebuffs = true, maxDebuffs = 3, debuffIconSize = 16,
                    debuffAnchor = "BOTTOMRIGHT", debuffGrowDirection = "LEFT",
                    debuffSpacing = 2, debuffOffsetX = -2, debuffOffsetY = -18,
                    debuffReverseSwipe = false,
                    showBuffs = false, maxBuffs = 0, buffIconSize = 14,
                    buffAnchor = "TOPLEFT", buffGrowDirection = "RIGHT",
                    buffSpacing = 2, buffOffsetX = 2, buffOffsetY = 16,
                    buffReverseSwipe = false,
                    showDurationColor = true,
                    showExpiringPulse = true,
                    showDurationText = true,
                    durationFontSize = 9,
                    filterMode = "off",
                    buffFilterOnlyMine = false,
                    buffHidePermanent = false,
                    buffDeduplicateDefensives = true,
                    buffClassifications = { raid = false, cancelable = false, important = false },
                    debuffClassifications = { raid = true, crowdControl = true, important = true },
                    buffWhitelist = {},
                    buffBlacklist = {},
                    debuffWhitelist = {},
                    debuffBlacklist = {},
                },
                privateAuras = {
                    enabled = true,
                    maxPerFrame = 2,
                    iconSize = 20,
                    growDirection = "RIGHT",
                    spacing = 2,
                    anchor = "RIGHT",
                    anchorOffsetX = -2,
                    anchorOffsetY = 0,
                    showCountdown = true,
                    showCountdownNumbers = true,
                    reverseSwipe = false,
                    borderScale = 1,
                    textScale = 2,
                    textOffsetX = 0,
                    textOffsetY = 0,
                },
                auraIndicators = {
                    enabled = false,
                    iconSize = 14,
                    anchor = "TOPLEFT",
                    anchorOffsetX = 0,
                    anchorOffsetY = 0,
                    growDirection = "RIGHT",
                    spacing = 2,
                    maxIndicators = 5,
                    reverseSwipe = false,
                    trackedSpells = {},
                    entries = {},
                },
                pinnedAuras = {
                    enabled = false,
                    slotSize = 8,
                    edgeInset = 2,
                    showSwipe = true,
                    reverseSwipe = false,
                    specSlots = {},
                },
                castbar = { enabled = false, height = 8, showIcon = false, showText = false },
                portrait = { showPortrait = false, portraitSide = "LEFT", portraitSize = 30 },
                pets = {
                    enabled = false,
                    width = 100, height = 20,
                    showPowerBar = false,
                    showAuras = false,
                    anchorTo = "BOTTOM",
                    anchorGap = 2,
                },
                dimensions = {
                    smallRaidWidth = 180, smallRaidHeight = 36,
                    mediumRaidWidth = 160, mediumRaidHeight = 30,
                    largeRaidWidth = 140, largeRaidHeight = 24,
                },
                spotlight = {
                    enabled = false,
                    byRole = {},
                    byName = {},
                    position = { offsetX = -400, offsetY = 200 },
                    growDirection = "DOWN",
                    spacing = 2,
                    useMainFrameStyle = true,
                },
            },

            -- Click-casting (shared)
            clickCast = {
                enabled = false,
                bindings = {},
                perSpec = true,
                perLoadout = false,
                loadoutBindings = {},
                smartRes = true,
                showTooltip = true,
                unitFrames = {
                    player = false,
                    target = false,
                    targettarget = false,
                    focus = false,
                    pet = false,
                    boss = false,
                },
            },

            -- Test/preview mode (shared)
            testMode = {
                partyCount = 5,
                raidCount = 25,
            },
        },

        -- Config Panel Scale, Width, and Alpha (for the settings UI, not the in-game HUD)
        configPanelScale = 1.0,
        configPanelWidth = 750,
        configPanelAlpha = 0.97,

        -- Addon Accent Color (drives options panel theme + default fallback for skinned elements)
        addonAccentColor = {0.376, 0.647, 0.980, 1},  -- #60A5FA Sky Blue
        themePreset = "Sky Blue",  -- Theme preset name (see GUI.ThemePresets)

        -- Combat Text Indicator
        combatText = {
            enabled = true,
            displayTime = 0.8,    -- Time text is visible before fade starts (seconds)
            fadeTime = 0.3,       -- Fade animation duration (seconds)
            fontSize = 14,        -- Text size
            xOffset = 0,          -- Horizontal offset from screen center
            yOffset = 0,          -- Vertical offset from screen center (positive = above)
            enterCombatColor = {1, 0.98, 0.2, 1},      -- +Combat text color (#FFFA33 yellow)
            leaveCombatColor = {1, 0.98, 0.2, 1},      -- -Combat text color (#FFFA33 yellow)
        },

        -- Battle Res Counter (displays brez charges and timer)
        brzCounter = {
            enabled = true,
            width = 50,
            height = 50,
            fontSize = 14,
            timerFontSize = 12,
            xOffset = 500,
            yOffset = -50,
            showBackdrop = true,
            backdropColor = { 0, 0, 0, 0.6 },
            textColor = { 1, 1, 1, 1 },
            timerColor = { 1, 1, 1, 1 },
            noChargesColor = { 1, 0.3, 0.3, 1 },
            hasChargesColor = { 0.3, 1, 0.3, 1 },
            useClassColorText = false,
            borderSize = 1,
            hideBorder = false,
            borderColor = { 0, 0, 0, 1 },
            useClassColorBorder = false,
            useAccentColorBorder = false,
            borderTexture = "None",
            useCustomFont = false,
            font = nil,
        },

        -- Atonement Counter (displays active player-cast Atonements)
        atonementCounter = {
            enabled = true,
            locked = true,
            showOnlyInInstance = false,
            hideIcon = false,
            width = 50,
            height = 50,
            fontSize = 24,
            xOffset = 500,
            yOffset = 10,
            showBackdrop = true,
            backdropColor = { 0, 0, 0, 0.6 },
            activeCountColor = { 1.0, 0.82, 0.2, 1 },
            zeroCountColor = { 1, 1, 1, 0.55 },
            useClassColorText = false,
            borderSize = 1,
            hideBorder = false,
            borderColor = { 0, 0, 0, 1 },
            useClassColorBorder = false,
            useAccentColorBorder = false,
            borderTexture = "None",
            useCustomFont = false,
            font = nil,
        },

        -- Combat Timer (displays elapsed combat time)
        combatTimer = {
            enabled = false,       -- Opt-in feature (disabled by default)
            xOffset = 0,           -- Horizontal offset from screen center
            yOffset = -150,        -- Vertical offset (below center by default)
            width = 80,            -- Frame width
            height = 30,           -- Frame height
            fontSize = 16,         -- Font size for timer text
            useCustomFont = false, -- If false, use global addon font
            font = "Quazii",       -- Font name (from LibSharedMedia)
            useClassColorText = false,  -- If true, use player class color for text
            textColor = {1, 1, 1, 1},  -- White text
            -- Backdrop settings
            showBackdrop = true,
            backdropColor = {0, 0, 0, 0.6},  -- Semi-transparent black
            -- Border settings
            borderSize = 1,
            borderTexture = "None", -- Border texture from LibSharedMedia (or "None" for solid)
            useClassColorBorder = false,  -- If true, use player class color
            useAccentColorBorder = false,  -- If true, use addon accent color
            borderColor = {0, 0, 0, 1},  -- Black border
            hideBorder = false,  -- If true, hide border completely (overrides other border settings)
            onlyShowInEncounters = false,  -- If true, only show during boss encounters (not general combat)
        },

        -- XP Tracker
        xpTracker = {
            enabled = false,
            width = 300,
            height = 90,
            barHeight = 20,
            headerFontSize = 12,
            headerLineHeight = 18,
            fontSize = 11,
            lineHeight = 14,
            offsetX = 0,
            offsetY = 150,
            locked = true,
            hideTextUntilHover = false,
            detailsGrowDirection = "auto",
            barTexture = "Solid",
            showBarText = true,
            showRested = true,
            barColor = {0.2, 0.5, 1.0, 1},
            restedColor = {1.0, 0.7, 0.1, 0.5},
            backdropColor = {0.05, 0.05, 0.07, 0.85},
            borderColor = {0, 0, 0, 1},
        },

        -- Prey Tracker
        preyTracker = {
            enabled = true,
            -- Bar dimensions
            width = 250,
            height = 20,
            borderSize = 1,
            -- Bar appearance
            texture = "Quazii v5",
            barUseClassColor = false,
            barUseAccentColor = true,
            barColor = { 0.2, 0.8, 0.2, 1 },
            barBgOverride = false,
            barBackgroundColor = { 0.1, 0.1, 0.1, 0.8 },
            -- Border
            borderOverride = false,
            borderUseClassColor = false,
            borderColor = { 0, 0, 0, 1 },
            -- Text
            showText = true,
            textSize = 11,
            textFormat = "stage_pct",
            -- Tick marks
            showTickMarks = true,
            tickStyle = "thirds",
            -- Spark
            showSpark = true,
            -- Sounds
            soundEnabled = true,
            soundStage2 = true,
            soundStage3 = true,
            soundStage4 = true,
            completionSound = true,
            -- Ambush alerts
            ambushAlertEnabled = true,
            ambushSoundEnabled = true,
            ambushGlowEnabled = true,
            ambushDuration = 6,
            -- Default indicator
            replaceDefaultIndicator = true,
            -- Visibility
            autoHide = true,
            hideInInstances = true,
            hideOutsidePreyZone = false,
            -- Hunt Scanner
            huntScannerEnabled = true,
            -- Currency Tracker
            currencyEnabled = true,
            currencyShowSession = true,
            currencyShowWeekly = true,
        },

        -- Cooldown Manager Effects
        cooldownSwipe = {
            showBuffSwipe = false,      -- Buff/aura duration swipe (Essential/Utility)
            showBuffIconSwipe = false,  -- BuffIcon viewer swipe (opt-in)
            showGCDSwipe = false,       -- GCD swipe (~1.5s)
            showCooldownSwipe = false,  -- Actual spell cooldown swipe

            showRechargeEdge = false,   -- Show edge texture on cooldown swipe (recharge edge)

            showActionSwipe = true,     -- Action bar cooldown swipe
            showNcdmSwipe = true,       -- NCDM cooldown swipe
            showCustomTrackerSwipe = true, -- Custom tracker cooldown swipe
            migratedToV2 = true,        -- Migration marker from old hideEssential/hideUtility
        },
        cooldownEffects = {
            hideEssential = true,
            hideUtility = true,
        },
        -- Custom Glow Settings (for Essential/Utility cooldown viewers)
        customGlow = {
            -- Essential Cooldowns
            essentialEnabled = true,
            essentialGlowType = "Pixel Glow",  -- "Pixel Glow", "Autocast Shine", "Button Glow"
            essentialColor = {0.95, 0.95, 0.32, 1},  -- Default yellow/gold
            essentialLines = 14,       -- Number of lines for Pixel Glow / spots for Autocast Shine
            essentialFrequency = 0.25, -- Animation speed
            essentialLength = nil,     -- nil = auto-calculate based on icon size
            essentialThickness = 2,    -- Line thickness for Pixel Glow
            essentialScale = 1,        -- Scale for Autocast Shine
            essentialXOffset = 0,
            essentialYOffset = 0,

            -- Utility Cooldowns
            utilityEnabled = true,
            utilityGlowType = "Pixel Glow",
            utilityColor = {0.95, 0.95, 0.32, 1},
            utilityLines = 14,
            utilityFrequency = 0.25,
            utilityLength = nil,
            utilityThickness = 2,
            utilityScale = 1,
            utilityXOffset = 0,
            utilityYOffset = 0,
        },
        
        -- Cooldown Highlighter (flash on spell cast)
        cooldownHighlighter = {
            enabled = false,
            glowType = "Pixel Glow",  -- "Pixel Glow", "Autocast Shine", "Button Glow"
            color = {1, 1, 1, 0.8},   -- White highlight
            duration = 0.4,            -- Seconds to show highlight
            lines = 8,
            thickness = 1,
            scale = 1,
            frequency = 0.25,
        },

        -- Buff/Debuff Visuals
        buffBorders = {
            enableBuffs = true,
            enableDebuffs = true,
            hideBuffFrame = false,
            hideDebuffFrame = false,
            fadeBuffFrame = false,
            fadeDebuffFrame = false,
            fadeOutAlpha = 0,
            borderSize = 2,
            fontSize = 12,
            fontOutline = true,
            -- Layout overrides (0 = use Blizzard default)
            buffIconsPerRow = 0,
            buffIconSpacing = 0,
            buffIconSize = 0,
            buffGrowLeft = false,
            buffGrowUp = false,
            buffInvertSwipeDarkening = false,
            buffRowSpacing = 0,
            debuffIconsPerRow = 0,
            debuffIconSpacing = 0,
            debuffIconSize = 0,
            debuffGrowLeft = false,
            debuffGrowUp = false,
            debuffInvertSwipeDarkening = false,
            debuffRowSpacing = 0,
            -- Text positioning (per-frame)
            buffStackTextAnchor = "BOTTOMRIGHT",
            buffStackTextOffsetX = -1,
            buffStackTextOffsetY = 1,
            buffDurationTextAnchor = "CENTER",
            buffDurationTextOffsetX = 0,
            buffDurationTextOffsetY = 0,
            debuffStackTextAnchor = "BOTTOMRIGHT",
            debuffStackTextOffsetX = -1,
            debuffStackTextOffsetY = 1,
            debuffDurationTextAnchor = "CENTER",
            debuffDurationTextOffsetX = 0,
            debuffDurationTextOffsetY = 0,
        },
        
        -- QUI Autohides
        uiHider = {
            hideObjectiveTrackerAlways = false,  -- Hide Objective Tracker always
            hideObjectiveTrackerInstanceTypes = {
                mythicPlus = false,
                mythicDungeon = false,
                normalDungeon = false,
                heroicDungeon = false,
                followerDungeon = false,
                raid = false,
                pvp = false,
                arena = false,
            },
            hideMinimapBorder = true,
            hideTimeManager = true,
            hideGameTime = true,
            hideMinimapTracking = true,
            hideRaidFrameManager = true,
            hideMinimapZoneText = true,
            hideBuffCollapseButton = true,
            hideFriendlyPlayerNameplates = true,
            hideFriendlyNPCNameplates = true,
            hideTalkingHead = true,
            muteTalkingHead = false,
            hideErrorMessages = false,
            hideInfoMessages = false,
            hideMinimapZoomButtons = true,
            hideWorldMapBlackout = true,
            hideTalkingHeadFrame = true,
            hideXPAtMaxLevel = false,
            hideExperienceBar = false,
            hideReputationBar = false,
            hideDataBarsInVehicle = false,  -- Hide data bars while in a vehicle
            hideDataBarsInPetBattle = false, -- Hide data bars during pet battles
            hideMainActionBarArt = false,
        },
        
        -- Minimap Settings
        minimap = {
            enabled = true,  -- Enabled by default for clean minimap experience
            
            -- Shape and Size
            shape = "SQUARE",  -- SQUARE or ROUND
            size = 160,
            scale = 1.0,  -- Scale multiplier for minimap frame
            borderSize = 2,
            borderColor = {0, 0, 0, 1},  -- Black border
            useClassColorBorder = false,
            useAccentColorBorder = false,
            buttonRadius = 2,  -- LibDBIcon button radius for square minimap
            
            -- Position
            lock = false,  -- Unlocked by default so users can position it
            position = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 790, y = 285 },
            
            -- Features
            autoZoom = false,  -- Auto zoom out after 10 seconds
            hideAddonButtons = true,  -- Show addon buttons on hover only
            buttonDrawer = {
                enabled = false,        -- Off by default (opt-in feature)
                anchor = "RIGHT",       -- Which side of minimap: LEFT, RIGHT, TOPLEFT, TOPRIGHT, BOTTOMLEFT, BOTTOMRIGHT, TOP, BOTTOM
                offsetX = 0,            -- Horizontal offset from anchor position
                offsetY = 0,            -- Vertical offset from anchor position
                toggleOffsetX = 0,      -- Horizontal offset for the toggle button
                toggleOffsetY = 0,      -- Vertical offset for the toggle button
                openOnMouseover = true, -- Open drawer when hovering the toggle button
                autoHideToggle = false, -- Auto-hide the toggle button (show on minimap hover)
                hiddenButtons = {},     -- Table of button names hidden from the drawer (e.g., { ["LibDBIcon10_Details"] = true })
                autoHideDelay = 1.5,    -- Seconds after mouse leave before hiding (0 = no auto-hide)
                buttonSize = 28,        -- Size of collected buttons in pixels
                buttonSpacing = 2,      -- Gap between buttons in pixels
                padding = 6,            -- Inner frame padding around the icon grid
                columns = 1,            -- Number of columns in grid layout (1 = vertical strip)
                growthDirection = "RIGHT", -- Primary growth direction: RIGHT, LEFT, UP, DOWN
                centerGrowth = false,      -- Expand around center axis instead of from one edge
                bgColor = {0.03, 0.03, 0.03, 1}, -- Drawer background color (alpha controlled by bgOpacity)
                bgOpacity = 98,            -- Drawer background opacity (0-100)
                borderSize = 1,            -- Drawer border thickness multiplier (0 hides border)
                borderColor = {0.2, 0.8, 0.6, 1}, -- Drawer border color
            },
            middleClickMenuEnabled = true,  -- Middle click minimap opens quick menu
            hideMicroMenu = false,  -- Hide Blizzard micro menu (Character/Spellbook/etc.)
            hideBagBar = false,  -- Hide Blizzard bag bar
            
            -- Button Visibility
            showZoomButtons = false,
            showMail = false,
            showCraftingOrder = true,
            showAddonCompartment = false,
            showDifficulty = false,
            showMissions = false,
            showCalendar = true,
            showTracking = false,

            -- Dungeon Eye (LFG Queue Status Button) - repositions to minimap when in queue
            dungeonEye = {
                enabled = true,
                corner = "BOTTOMLEFT",
                scale = 0.6,
                offsetX = 0,
                offsetY = 0,
            },

            -- Clock (anchored top-left) - disabled by default, user can enable
            showClock = false,
            clockConfig = {
                offsetX = 0,
                offsetY = 0,
                align = "LEFT",
                font = "Quazii",
                fontSize = 12,
                monochrome = false,
                outline = "OUTLINE",
                color = {1, 1, 1, 1},
                useClassColor = false,
                timeFormat = "local",  -- "local" or "server"
            },
            
            -- Coordinates (anchored top-right)
            showCoords = false,
            coordPrecision = "%d,%d",  -- %d,%d = normal, %.1f,%.1f = high, %.2f,%.2f = very high
            coordUpdateInterval = 1,  -- Update every 1 second
            coordsConfig = {
                offsetX = 0,
                offsetY = 0,
                align = "RIGHT",
                font = "Quazii",
                fontSize = 12,
                monochrome = false,
                outline = "OUTLINE",
                color = {1, 1, 1, 1},
                useClassColor = false,
            },
            
            -- Zone Text (anchored top-center)
            showZoneText = true,
            zoneTextConfig = {
                offsetX = 0,
                offsetY = 0,
                align = "CENTER",
                font = "Quazii",
                fontSize = 12,
                allCaps = false,
                monochrome = false,
                outline = "OUTLINE",
                useClassColor = false,
                colorNormal = {1, 0.82, 0, 1},      -- Gold
                colorSanctuary = {0.41, 0.8, 0.94, 1},  -- Light blue
                colorArena = {1.0, 0.1, 0.1, 1},    -- Red
                colorFriendly = {0.1, 1.0, 0.1, 1}, -- Green
                colorHostile = {1.0, 0.1, 0.1, 1},  -- Red
                colorContested = {1.0, 0.7, 0.0, 1}, -- Orange
            },
        },
        
        -- Minimap Button (LibDBIcon) - separate from minimap module
        minimapButton = {
            hide = false,
            minimapPos = 180,  -- 9 o'clock position (left side)
        },
        
        -- Datatext Panel (fixed below minimap - slot-based architecture)
        datatext = {
            enabled = true,
            slots = {"fps", "durability", "time"},  -- 3 configurable datatext slots

            -- Per-slot configuration (shortLabel, noLabel, xOffset, yOffset)
            slot1 = { shortLabel = false, noLabel = false, xOffset = -1, yOffset = 0 },
            slot2 = { shortLabel = false, noLabel = false, xOffset = 6, yOffset = 0 },
            slot3 = { shortLabel = true, noLabel = false, xOffset = 3, yOffset = 0 },

            forceSingleLine = true,  -- If true, ignores wrapping and forces single line
            
            -- Panel Settings (width auto-matches minimap)
            height = 22,
            offsetY = 0,  -- Y offset from minimap bottom
            bgOpacity = 60,  -- 0-100
            borderSize = 2,  -- Border thickness (0-8, 0=hidden)
            borderColor = {0, 0, 0, 1},  -- Black border (#90)

            -- Font Settings
            font = "Quazii",
            fontSize = 13,
            fontOutline = "OUTLINE",  -- "OUTLINE" = Thin

            -- Color Settings
            useClassColor = false,
            valueColor = {0.1, 1.0, 0.1, 1},  -- #1AFF1A green
            
            -- Separator
            separator = "  ",
            
            -- Legacy Composite Mode Toggles
            showFPS = true,
            showLatency = false,
            showDurability = true,
            showGold = false,
            showTime = true,
            showCoords = false,
            showFriends = false,
            showGuild = false,
            showLootSpec = false,
            
            -- Time Settings (for Time datatext or legacy mode)
            timeFormat = "local",  -- "local" or "server"
            use24Hour = true,
            useLocalTime = true,  -- For datatext registry
            lockoutCacheMinutes = 5,  -- minutes between lockout data refresh (min 1)

            -- Social datatext settings
            showTotal = true,  -- Show total count (friends/guild)
            showGuildName = false,  -- Show guild name in text

            -- Player Spec datatext settings
            specDisplayMode = "full",  -- "icon" = icon only, "loadout" = icon + loadout, "full" = icon + spec/loadout

            -- System datatext settings (combined FPS + Latency)
            system = {
                latencyType = "home",      -- "home" or "world" latency on main display
                showLatency = true,        -- Show Home/World latency in tooltip
                showProtocols = true,      -- Show IPv4/IPv6 protocols in tooltip
                showBandwidth = true,      -- Show bandwidth/download % when downloading
                showAddonMemory = true,    -- Show addon memory usage in tooltip
                addonCount = 10,           -- Number of addons to show (sorted by memory)
                showFpsStats = true,       -- Show FPS avg/low/high when Shift held
            },

            -- Volume datatext settings
            volume = {
                volumeStep = 5,            -- Volume change per scroll (1-20)
                controlType = "master",    -- Which volume to control: "master", "music", "sfx", "ambience", "dialog"
                showIcon = false,          -- Show speaker icon instead of "Vol:" label
            },

            -- Currencies datatext settings
            currencyOrder = {},  -- Ordered currency IDs selected by user (up to 6)
            currencyEnabled = {}, -- Per-currency toggle map (id -> true/false)
        },
        
        -- Additional Datapanels (user-created, independent of minimap)
        quiDatatexts = {
            panels = {},  -- Array of panel configurations
        },

        -- Custom Tracker Bars (consumables, trinkets, custom spells)
        customTrackers = {
            bars = {
                {
                    id = "default_tracker_1",
                    name = "Trinket & Pot",
                    enabled = false,
                    locked = false,
                    -- Position (offset from screen center, use snap buttons to align to player)
                    offsetX = -406,
                    offsetY = -152,
                    -- Layout
                    growDirection = "RIGHT",
                    iconSize = 28,
                    spacing = 4,
                    borderSize = 2,
                    aspectRatioCrop = 1.0,
                    zoom = 0,
                    -- Duration text
                    durationSize = 13,
                    durationColor = {1, 1, 1, 1},
                    durationAnchor = "CENTER",
                    durationOffsetX = 0,
                    durationOffsetY = 0,
                    hideDurationText = false,
                    -- Stack text
                    stackSize = 9,
                    stackColor = {1, 1, 1, 1},
                    stackAnchor = "BOTTOMRIGHT",
                    stackOffsetX = 3,
                    stackOffsetY = -1,
                    hideStackText = false,
                    showItemCharges = true,  -- Show item charges (e.g., Healthstone 3 charges) instead of item count
                    -- Background
                    bgOpacity = 0,
                    bgColor = {0, 0, 0, 1},
                    hideGCD = true,
                    hideNonUsable = false,
                    showOnlyOnCooldown = false,
                    showOnlyWhenActive = false,
                    showOnlyWhenOffCooldown = false,
                    showOnlyInCombat = false,
                    -- Click behavior
                    clickableIcons = false,  -- Allow clicking icons to use items/cast spells
                    -- Active state (buff/cast/channel display)
                    showActiveState = true,
                    activeGlowEnabled = true,
                    activeGlowType = "Pixel Glow",
                    activeGlowColor = {1, 0.85, 0.3, 1},
                    -- Pre-populated with Algari Healing Potion
                    entries = {
                        { type = "item", id = 224022 },
                    },
                },
            },
            -- Global keybind settings for custom trackers
            keybinds = {
                showKeybinds = false,
                keybindTextSize = 12,
                keybindTextColor = { 1, 0.82, 0, 1 },  -- Gold
                keybindOffsetX = 2,
                keybindOffsetY = -2,
            },
            -- CDM buff tracking (trinket proc detection)
            cdmBuffTracking = {
                trinketData = {},
                learnedBuffs = {},
            },
        },

        -- Totem bar: Blizzard TotemFrame (any class the game uses it for)
        totemBar = {
            enabled = false,
            locked = false,
            offsetX = 0,
            offsetY = -200,
            growDirection = "RIGHT",
            iconSize = 36,
            spacing = 4,
            borderSize = 2,
            zoom = 0,
            durationSize = 13,
            durationColor = {1, 1, 1, 1},
            durationAnchor = "CENTER",
            durationOffsetX = 0,
            durationOffsetY = 0,
            hideDurationText = false,
            showSwipe = true,
            swipeColor = {0, 0, 0, 0.6},
        },

        -- DandersFrames Integration: Anchor DF containers to QUI elements
        dandersFrames = {
            party = {
                enabled = false,
                anchorTo = "disabled",
                sourcePoint = "TOP",
                targetPoint = "BOTTOM",
                offsetX = 0,
                offsetY = -5,
            },
            raid = {
                enabled = false,
                anchorTo = "disabled",
                sourcePoint = "TOP",
                targetPoint = "BOTTOM",
                offsetX = 0,
                offsetY = -5,
            },
            pinned1 = {
                enabled = false,
                anchorTo = "disabled",
                sourcePoint = "TOP",
                targetPoint = "BOTTOM",
                offsetX = 0,
                offsetY = -5,
            },
            pinned2 = {
                enabled = false,
                anchorTo = "disabled",
                sourcePoint = "TOP",
                targetPoint = "BOTTOM",
                offsetX = 0,
                offsetY = -5,
            },
        },

        -- AbilityTimeline Integration: Anchor timeline and big icon frames to QUI elements
        abilityTimeline = {
            timeline = {
                enabled = false,
                anchorTo = "disabled",
                sourcePoint = "TOP",
                targetPoint = "BOTTOM",
                offsetX = 0,
                offsetY = -5,
            },
            bigIcon = {
                enabled = false,
                anchorTo = "disabled",
                sourcePoint = "TOP",
                targetPoint = "BOTTOM",
                offsetX = 0,
                offsetY = -5,
            },
        },

        -- BigWigs Integration: Anchor BigWigs normal/emphasized bars to QUI elements
        bigWigs = {
            backupPositions = {},
            normal = {
                enabled = false,
                anchorTo = "disabled",
                sourcePoint = "TOP",
                targetPoint = "BOTTOM",
                offsetX = 0,
                offsetY = -5,
            },
            emphasized = {
                enabled = false,
                anchorTo = "disabled",
                sourcePoint = "TOP",
                targetPoint = "BOTTOM",
                offsetX = 0,
                offsetY = -5,
            },
        },

        -- HUD Layering: Control frame level ordering for HUD elements
        -- Higher values appear above lower values (range 0-10)
        hudLayering = {
            -- CDM viewers (default 5 - middle)
            essential = 5,
            utility = 5,
            buffIcon = 5,
            buffBar = 5,
            -- Power bars (higher defaults so text visible above CDM)
            primaryPowerBar = 7,
            secondaryPowerBar = 6,
            -- Unit frames (lower defaults, background elements)
            playerFrame = 4,
            playerIndicators = 6,  -- Above player frame for visibility
            targetFrame = 4,
            totFrame = 3,
            petFrame = 3,
            focusFrame = 4,
            bossFrames = 4,
            -- Castbars (middle)
            playerCastbar = 5,
            targetCastbar = 5,
            -- Custom trackers
            customBars = 5,
            -- Totem bar
            totemBar = 5,
            -- Group frames (party/raid)
            groupFrames = 4,
            groupPetFrames = 3,
        },
        frameAnchoring = {},
        -- Blizzard UI panels: modifier-drag reposition (see modules/qol/blizzard_mover.lua)
        blizzardMover = {
            enabled = false,
            requireModifier = true,
            modifier = "SHIFT",
            scaleEnabled = false,
            scaleModifier = "CTRL",
            positionPersistence = "reset", -- "close" | "lockout" | "reset"
            frames = {}, -- [entryId] = { enabled, point, x, y, scale }
        },
    },
    -- Account-wide storage (shared across all characters)
    global = {
        -- Gold tracking per character (realm-name = copper)
        goldData = {},
        -- Spell Scanner: cross-character spell/item duration mappings
        spellScanner = {
            spells = {},   -- [castSpellID] = { buffSpellID, duration, icon, name, scannedAt }
            items = {},    -- [itemID] = { useSpellID, buffSpellID, duration, icon, name, scannedAt }
            autoScan = false,  -- Auto-scan setting (off by default)
        },
    },
    char = {
        keybindOverrides = {},  -- [specID] = { [spellID] = keybindText, [-itemID] = keybindText }
    },
}

ns.defaults = defaults
