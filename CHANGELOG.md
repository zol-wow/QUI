# Changelog

All notable changes to QUI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).






































































## v2.47.1 - 2026-03-07

### Fixed
- improve tooltip handling and enhance viewer alpha enforcement
## v2.47.0 - 2026-03-07

### Added
- added party and raid frames

### Fixed
- fixed stancebar icons not rendering correctly
- fixed HUD visibility with "show below 100% health" option
- fixed some special secondary resource bars (whirlwind, tip of the spear, essence)
- fixed some resource bar sizing issues
## v2.46.9 - 2026-03-07

### Added
- feat: add Whirlwind, Tip of the Spear, and Essence regen resource bars
- added second icon option for the minimap button drawer

### Fixed
- fixed nested menu entries for action bars and onwards
- fixed missing icons for the target classification
- fix: combat taint safety for keystone tracker hide and tooltip widget setup
- fix: eliminate tooltip taint by skipping all addon work in combat
- fix: detect spell list reordering via fingerprint instead of count
## v2.46.8 - 2026-03-07

### Added
- feat: configurable minimap drawer toggle button size
- feat: add classification icon for target, focus, and boss unit frames
- feat: show unit frames when player health is below 100%

### Fixed
- fix skyriding bar staying visible when flying into dungeons
- fix: exclude maxLength from castbar copy to prevent truncation
- fix: improve CDM aura detection, initial cooldown sync, and tooltip taint safety
- fix: stop clearing layoutType/layoutTextureKit on tooltip frame to prevent taint
- fix: show real item/slot cooldown instead of buff duration in trackers
- fix: gate all tooltip features behind master enabled toggle
- fix: pre-create power bar globals for Edit Mode anchoring at load time
- fix: ensure power bar globals exist for Edit Mode anchoring
## v2.46.7 - 2026-03-06

### Fixed
- revert: restore UISpecialFrames for ESC-to-close on chat and options frames
## v2.46.6 - 2026-03-06

### Fixed
- fix: tooltip combat hide flash and broaden SetSpellByID/SetItemByID suppression
- fix: replace UISpecialFrames with OnKeyDown ESC handler to avoid taint
- fix: sidebar subtab active state reads current tab at click time
- fix: separate aura/cooldown swipe color defaults, clarify options labels
- fix: datapanel init timing and gold datatext initial update
- feat: anchoring system integration, custom tracker improvements, taint safety
- fix: consumable frame SetScale combat taint, tooltip hook taint safety
- fix: remove RefreshTotemData method replacement that tainted CDM viewer
- fix: font system taint safety, CDM bar and buffbar improvements
## v2.46.5 - 2026-03-06

### Added
- added tracked buff bar factory to QUI CDM engine

### Fixed
- fix: buff bar active state, parent mismatch, and Edit Mode taint
- fix: stop overwriting point/relative on container position save
## v2.46.4 - 2026-03-05

### Fixed
- fix(custom-trackers): restore clickable tracker actions after info/usability updates
- fix: remove border debug logging, fix fade-hide flag tracking
- fix: action bar border toggle and NormalTexture re-hide on updates
## v2.46.3 - 2026-03-05

### Fixed
- fix: tooltip taint hardening and anchoring debug silencing
- fix: layoutIndex sorting, loot tooltip guard, respect layout direction flags, sort before subset
- fix: invalidate options panel on profile change
## v2.46.2 - 2026-03-05

### Added
- feat: click-to-cast for CDM icons with macro resolution and secure overlays

### Fixed
- fixed more tooltip taint paths
- fix: trust Edit Mode NumIcons API and restore bars on edit mode enter
- fix: correct secondary stat calculations and tooltips in character panel
## v2.46.1 - 2026-03-04

### Fixed
- rework tooltip skinning a bit to avoid taints
- fix: explicitly hide/show QUI textures on faded and empty action buttons
- don't show a skyriding bar when being a passenger
- fixed action bar 1 not fading when 'keep leave vehicle button visible' was active
- fixed circular anchor dependency introduced by alert skinning
## v2.46.0 - 2026-03-04

### Added
- added new collapsible side menu structure to help people find things (also use the search!)
- added some minimap button drawer enhancements

### Fixed
- fixed search interface scrollbar styling
- fix: simplify CDM cooldown mirroring and swipe classification
- fix: remove LibDBIcon10_QUI from minimap drawer blacklist
- fix: pcall SetLootRollItem to guard against third-party tooltip hook errors
- fix: combat taint safety for scaling, tooltips, and tooltip skinning
- fix: taint-safe font system, overlay-based button tints, and max-level detection
- fix: apply tooltip visibility rules to CDM item tooltips via SetItemByID
- feat: visible-only button spacing and anchor chain walk for hidden parents
## v2.45.2 - 2026-03-04

### Fixed
- resolve trinket slot to item ID for icons, tooltips, and cooldowns
- read bar grid layout from Edit Mode API, support vertical orientation
## v2.45.1 - 2026-03-04

### Fixed
- fixed cdm engine race condition that led to lua errors
- fixed issues with action bars and fixed their growth direction for multirow setups
## v2.45.0 - 2026-03-03

### Added
- added minimap button drawer
- added actionbar button spacing
- added equipment slot tracking for custom trackers
- added option to allow /reload in combat
- added custom tracker bars to anchoring system
- added help and documentation pages
## v2.44.4 - 2026-03-03

### Added
- added factory reset button to profiles page

### Fixed
- fix: respect Blizzard expansion button initialization state
- fix: stabilize expansion landing page button and add buttonSpacing default
- fix: safeguard CDM viewer totem refresh and strip embedded tooltip border
- fix: prevent override action bar taint loop during combat
## v2.44.3 - 2026-03-03

### Added
- allow for ESC to close the settings panel
- added Rotation Assist Icon to Anchoring & Layout (under CDM)

### Fixed
- fixed GCD swipes/glows for some classes
- fixed issues with tooltip parent frames
- fixed skyriding speed math
- fixed missing enchant texts for character pane
- fixed LeaveVehicleButton showing when not in a vehicle
## v2.44.2 - 2026-03-02

### Fixed
- fixed game menu highlighting and "growing"
- fixed GCD glow showing on hidden CDM frames
- fixed some minor performance issues with duplicate recompute paths
- hardened search renderer
- cleaned up duplicate code
## v2.44.1 - 2026-03-02

### Added
- added "Reset All Movers" button to profiles tab

### Changed
- no cursor-anchoring for tooltips in combat anymore to avoid taints

### Fixed
- re-apply frame anchors after profile change
- minor objective tracking skinning fixes
- prevent CDM flash on load
- fixed ESC and slash commands not working in Edit Mode
## v2.44.0 - 2026-03-02

### Added
- added option to hide CDM when in a vehicle
- added option to show hidden action bars when spellbook is open

### Fixed
- fixed a lot of issues with Edit Mode, make sure to enter Edit Mode once and hit save (massive thanks to Drew again)
- fixed stack/charge text for CDM icons in new CDM engine
- fixed keybind text being overlayed by radial swipes
## v2.43.0 - 2026-03-01

### Added
- **added a second CDM engine (you can now pick between our own and the classic blizzard hook one in the CDM options) **
- added minimap menu (click with middle mousebutton on the minimap)
- added main chat frame as an anchoring target
- added pull timer command(s) (/pull (if available), /qpull, /quipull)
- added more anchoring options for tooltips when anchoring to the mouse cursor
## v2.42.0 - 2026-02-28

### Added
- added xp tracker module
- added option to hide player frame in party or raid
- added multiple customization options for the m+ timer

### Changed
- made +/-combat text font configurable

### Fixed
- fixed queue icon being blocked by an overlay frame
- fixed tons of edit mode issues
- fixed tons of taint code paths
- fixed minimap cluster anchoring
## v2.41.1 - 2026-02-24

### Fixed
- fixed devourer DH secondary resource bar
## v2.41.0 - 2026-02-23

### Added
- added custom color feature for cdm swipes and overlays
- added VDH soul fragments as secondary resource bar
- added ability to snap/lock custom tracker bars to non-QUI player/target frames
## v2.40.6 - 2026-02-22

### Fixed
- added safety guards for GetName, NumLines and GetRegions in tooltip skinning
- guarded against applying anchors of blizzard managed frames in combat
- made edit mode keyhandler only stay active when edit mode is actually active
- guarded edit mode keyhandler
## v2.40.5 - 2026-02-22

### Changed
- udpated README with instructions for WoWUp/CurseForge installation

### Fixed
- fixed keybinds for CDM custom entries not showing
- fixed non-arrow keys not working during Edit Mode
- fixed game trying to move locked brez timer frame
- fixed stack overflow error in QoL options
## v2.40.4 - 2026-02-22

### Fixed
- fixed calling SetFrameLevel() on protected frames in combat
- prevent Edit Mode taint from anchoring to hidden system frames
## v2.40.3 - 2026-02-22

### Changed
- detatch skinning border colors from global QUI accent color and give skinning modules per-module override options
## v2.40.2 - 2026-02-22

### Added
- added curseforge upload to release workflow
## v2.40.1 - 2026-02-21

### Fixed
- fixed action tracker taint
## v2.40.0 - 2026-02-21

### Added
- added action tracker feature
- added target distance range bracket display
- added profile import validation

### Changed
- improved callback throttling

### Fixed
- enforce globally set font in all options menus
## v2.39.1 - 2026-02-21

### Changed
- updated QUI base edit mode string (now includes all action bars, blizz party and raid frames)
- updated Discord link to a non-expiring one

### Fixed
- fixed HUD min width regression
## v2.39.0 - 2026-02-21

### Added
- added anchoring integration with BigWigs bars, if addon is detected
- added discord notification for new releases
- added player castbar standalone mode (if you don't want to use QUI Unit Frames, but the player castbar)

### Fixed
- fixed / optimized OnUpdate handling across multiple modules to reduce CPU load
## v2.38.3 - 2026-02-20

### Changed
- reverted last hardening commit

### Fixed
- fixed castbar not showing in combat in some edge cases
## v2.38.2 - 2026-02-20

### Changed
- hardened in-combat re-anchoring for cmd frames
## v2.38.1 - 2026-02-20

### Fixed
- fixed anchoring susceptible to drifts when spell morphs resize frames, fix combat timer anchoring
## v2.38.0 - 2026-02-19

### Added
- added more granular visibility options when mounted/flying for CDM, Unit Frames and Custom Tracker Bars
- added more frames to the anchoring system (i.e. Skyriding, Combat Timer, M+ Timer, BRez Timer, ExtraActionButton etc pp)
## v2.37.4 - 2026-02-19

### Added
- added consumables picking ui to consumables check

### Fixed
- fixed jitter behaviour when setting player/target frame to auto-height after zoning/reloading
## v2.37.3 - 2026-02-18

### Added
- added Welcome page with FAQs and Edit Mode base layout
- added Quazii Details! string (this is old, but it was requested)
## v2.37.2 - 2026-02-18

### Fixed
- fixed castbar related lua errors introduced with the castbar ticks feature
## v2.37.1 - 2026-02-18

### Changed
- added visual distinction for headers on dropdowns

### Fixed
- fixed quick keybinding not working anymore
- fixed not being able to anchor to actionbar 1
- fixed anchoring to secondary resourcebar
## v2.37.0 - 2026-02-17

### Added
- added option for minimum HUD width in anchoring options
- added castbar channel ticks feature
- added more options to suppress Blizzard popup modals and notifications
- added option to lock brez timer and counter in place

### Fixed
- fixed some in-combat frame drifting issues when spells morphed
- fixed missing raid buff preview not working
## v2.36.1 - 2026-02-17

### Added
- added option to reverse target health bar fill direction

### Changed
- added reasonable tracked buff bars defaults

### Fixed
- partial revert of the taint hardening of last release
## v2.36.0 - 2026-02-16

### Added
- added new anchoring and layout options
- added new tracked buff bar options

### Changed
- changed CVar check after leaving combat that would disable CDM entirely when only using CDM buffs

### Fixed
- addressed some potential taint code paths
## v2.35.0 - 2026-02-15

### Added
- added target unitframe to DandersFrames anchor targets
- added option to only have action bars mouseover hide work for chars at max level


### Changed
- updated castbars text clamping logic
- made spacing of castbars anchored to cdm visually consistent between one-row and multi-row layouts

### Fixed
- fixed castbar text anchoring
- fixed and hardened re-skinning and re-layouting as well as custom CD display on custom spells and items on the CDM
- addressed various action bars related taint issues
## v2.34.1 - 2026-02-15

### Fixed
- fixed container anchoring so that we can properly anchor and move DandersFrames preview frames
- fixed resourcebar swap applying to unsupported specs
- no longer alpha-force resource bars by cdm fade controller, which caused fallback center screen positioning
## v2.34.0 - 2026-02-14

### Added
- add customizable color for non-interruptible casts on target and focus target cast bars

### Fixed
- fixed non-interruptible cast detection for cast bars
## v2.33.0 - 2026-02-13

### Added
- **added focus target spell interrupt alert feature**
- added font size option slider to tooltip skinning
- added option to customize Thrill of the Skies color in the skyriding UI

### Fixed
- attempt to fix morphing spells freaking out the cdm and keep the rest as combat safe as possible
- added check for secret values in SafeToNumber and ensure spell text width calculations handle restricted values correctly
## v2.32.0 - 2026-02-13

### Added
- add auto combat logging feature for raids

### Changed

### Fixed
- fixed edge case where the castbar would disappear mid-cast when casting instantly after dropping combat
- add more InCombatLockdown checks in cooldown and buff bar modules
- fixed issue where the objective tracker would trigger show/hide and resize events in combat
- fixed totem event related tainted swipe updates
- force castbar preview cleanup when exiting edit mode
## v2.31.0 - 2026-02-12

### Added
- added options to order currencies in datatexts

### Fixed
- fixed taint issues with cdm swipes
- properly place swapped resource bars
## v2.30.2 - 2026-02-12

### Fixed
- fixed custom glows not showing, only blizzard proc glows
## v2.30.1 - 2026-02-12

### Fixed
- fixed glows not showing up on CDM
- fixed new quests not being skinned in objective tracker
## v2.30.0 - 2026-02-12

### Changed
- this release is mainly a larger scale refactoring of the existing code base

### Fixed
- fixed Blizzard castbar randomly showing after zoning
## v2.29.4 - 2026-02-10

### Fixed
- fixed keybind scan trying to access forbidden tables
## v2.29.3 - 2026-02-09

### Added
- added separate setting to hide info messages (so you can hide errors, but still have quest prog messages)
## v2.29.2 - 2026-02-09

### Changed
- disable castbar previews on profile change, this should fix the perma castbar preview issue (happened, when profile settings got copied with previews on)
## v2.29.1 - 2026-02-09

### Fixed
- attempt to catch Blizzard's errors for them (Edit Mode lua errors)
## v2.29.0 - 2026-02-09

### Added
- **added feature to anchor DandersFrames party/raid/pinned frames to QUI elements**
- added message history feature for chat input
- added option to swap primary and secondary resource bar positions for some specs, and also to hide primary when they are swapped
- added position mover for bnet notification toasts


### Changed
- dynamically shortening castbar spelltexts if bar is too short


### Fixed
- fixed stack text being overlayed by swipe texture on unitframe buffs and debuffs
- fixed global font setting not being honored by the loot window
- fixed an issue where circular anchoring dependencies would move all involved frames off screen
## v2.28.1 - 2026-02-09

### Fixed
- fixed keyboard being unusable after leaving edit mode
## v2.28.0 - 2026-02-08

### Added
- added a defensive patch for Blizzard's EncounterWarning text throwing errors


### Changed
- reworked parts of custom trackers to fix issues with dynamic layouts and clickable icons. **this makes 'dynamic layout' and 'clickable icons' mutually exclusive options for custom trackers.**
- renamed 'Import' menu to 'Import & Export Strings'


### Fixed
- fixed resource bar visibility setting overriding CDM visibility setting in some cases
## v2.27.0 - 2026-02-07

### Added
- added maelstrom weapon as second resource for enhancement shamans

### Changed
- improved mousewheel scroll speed for easier navigation throughout the options panels (thx to Mør)

### Fixed
- fixed unitframes not showing on beta
## v2.26.2 - 2026-02-07

### Changed
- updated LibCustomGlow

### Fixed
- fix autocast shine and button glow on CDM
## v2.26.1 - 2026-02-07

### Changed
- Defer proc and glow updates by a frame to not run within Blizzard update cycle. This is an attempt to solve the issue of the whole CDM disappearing for some specs when they proc certain spells (i.e. Devourer DH). *Let me know, if this breaks things, that I have not discovered yet in my testing, then I will revert the change.*
## v2.26 - 2026-02-07

### Added
- added 'responsive' sub-tab behaviour, wrapping buttons into a second row when necessary

### Fixed
- fixed resource bar visibility check overriding CDM visibility check when mounted
- fixed an issue where a referenced variable was not initialized
- added proper secret value guards in the keybinds module
## v2.25 - 2026-02-06

### Added
- added heal prediction bars to player and target unit frames

### Changed
- keybind-text overrides are now per-character instead of per-profile
- changed hiding logic for CDM resource bars to not interfere with frames anchored to them

### Fixed
- fix 'only show in combat' option not working for custom trackers
- fix an issue with profiles that had 'nil' as their accent color
## v2.24 - 2026-02-06

### Added
- added more visibility options for CDM resource bars
- added option to show ilvl information on blizzard inspect window
- added option to hide tooltips on action bars

### Changed
- reverted a change that attempted to fix the moving CDM issue, because it caused more harm
## v2.23 - 2026-02-05

### Added
- added some visual aid for when dragging spells across hidden slots of action bars

### Fixed
- empty action bar slots should now properly refresh when dragging spells in or out
- the centered CDM should not move around anymore when changing to a profile with more or less spells on it
## v2.22 - 2026-02-05

### Added
- search results now will also capture entire sub-tabs or sections
## v2.21 - 2026-02-05

### Added
- WoWUp-compatible releases
## v2.20 - 2025-02-05

### Added
- Castbars added to QUI Edit Mode for easier positioning
- 1px and 10px nudging with cursor keys and SHIFT+cursor keys in Edit Mode
- Improved existing nudging buttons in Edit Mode

### Fixed
- Totem bar late declaration of Helpers causing errors

