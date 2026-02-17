# Changelog

All notable changes to QUI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).





























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

