# Changelog

All notable changes to QUI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).









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

