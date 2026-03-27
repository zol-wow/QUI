---
layout: default
title: Changelog
nav_order: 5
---

# Changelog

All notable changes to QUI are documented here. For the complete changelog, see the [CHANGELOG.md](https://github.com/zol-wow/QUI/blob/main/CHANGELOG.md) on GitHub.

---

## v2.55.2 - 2026-03-27

### Added
- Added support for charged combo points
- Made M+ timer background configurable

### Fixed
- Fixed HousingPhotoSharingFrame tooltip issue

---

## v2.55.1 - 2026-03-26

### Fixed
- Fixed durations of tracked buffs not showing
- More tooltip taint hardening

---

## v2.55.0 - 2026-03-25

### Fixed
- Backported API-change related fixes to QUI mainline
- Fixed custom trackers not showing in M+ and raids
- Fixed swipes and cooldowns not showing on CDM viewers

---

## v2.54.1 - 2026-03-24

### Fixed
- Fixed datatext placeholders showing when "no label" is selected
- Fixed moneyframe tooltip taint

---

## v2.54.0 - 2026-03-23

### Added
- Added Blizzard Frame Mover feature
- Added general status bar skinning (reputation bars, etc.)
- Added totem bars for all applicable classes (Brewmasters, etc.)

### Fixed
- Attempt to fix golden circles appearing around hidden action bars
- Attempt to fix world quest hovering tooltip taint

---

## v2.53.4 - 2026-03-23

### Added
- Added item IDs in tooltips
- Added PvP iLvl display when hovering iLvl on character sheet

---

## v2.53.3 - 2026-03-21

### Fixed
- Fixed range check issues on group frames
- Fixed current expansion flasks and oils not showing in consumable checker

---

## v2.53.2 - 2026-03-19

### Changed
- Performance: cached GetPixelSize() in hot loops for buff bars, resource bars, and group frames

---

## v2.53.1 - 2026-03-19

### Added
- Added option for spec-specific custom CDM entries
- Added "always show me first" option for raid frames

### Fixed
- Fixed dungeon difficulty icon anchoring
- Fixed raid frames randomly resizing
- Fixed raid frame sorting
- Fixed several tooltip taint vectors

---

## v2.53.0 - 2026-03-18

### Added
- Added partial profile imports
- Added avoidance and stagger to character stats

### Fixed
- Fixed tooltip combat visibility for custom trackers and CDM viewers
- Fixed raid tooltip taint
- Fixed totem bar taint issue

---

## v2.52.1 - 2026-03-15

### Added
- Added guild rank to tooltip display

### Fixed
- Fixed targetName comparison taint

---

## v2.52.0 - 2026-03-15

### Added
- Added customizable colors for CDM buff bars
- Added mount, target, and M+ rating to tooltip information

### Fixed
- Fixed group frame defensives showing random buffs when players are out of range
- Fixed castbar border frame strata

---

## v2.51.1 - 2026-03-14

### Added
- Added option to track Power Infusion on group frames

### Fixed
- Fixed skyriding bar rendering
- Fixed stance bar skinning issue
- Fixed tooltip inspect functions running in unsafe environment

---

## v2.51.0 - 2026-03-14

### Added
- Added configurable breakpoint indicators to resource bars
- Added Balance Druid and Frost DK to secondary resource bar swap group
- Added options to omit percent signs on health text and power text
- Added x- and y-offset for loot window relative to mouse cursor

### Fixed
- Fixed paging arrow showing even when turned off

---

## v2.50.2 - 2026-03-14

### Added
- Added anchoring support for AbilityTimeline / Better Timeline addon

### Fixed
- Fixed tooltips disappearing when OPie is enabled
- Fixed tooltips not showing spell IDs and icon IDs anymore
- Fixed mouseover tooltips on the minimap
- Fixed defensives growth direction 'center' not working as intended

---

## v2.50.1 - 2026-03-14

### Fixed
- Fixed own frame being rendered twice with "solo mode" enabled and in a group
- Fixed 'show me first' to take precedence over other sorting options
- Fixed party frame anchoring when 'show me first' is enabled

---

## v2.50.0 - 2026-03-13

### Added
- Added row growth direction options for horizontal and vertical layouts
- Added spec and item level information of players in tooltips
- Added CENTER growth direction for all group frame icon layouts
- Added scroll wheel click-casting

### Fixed
- Fixed tooltip cursor anchoring and border rendering
- Fixed gap between castbar border and castbar progress bar
- Fixed various profile switch and anchoring issues

---

## v2.49.4 - 2026-03-12

### Added
- Added global ping keybinds, self-first header, show solo option
- Added ping action types to click-casting system

### Fixed
- Fixed crafting order icon always showing
- Fixed CDM initialization for combat reload support
- Eliminated GameTooltip taint from hooks

---

## v2.49.0 - 2026-03-11

### Added
- Added system datatext memory stats
- Added unit menu action type to click-cast bindings
- Split up group frames settings into separate party and raid profiles

### Changed
- Removed QUI tooltip engine, now back to Blizzard hooks for tooltips

### Fixed
- Fixed totembar not showing in combat
- Various taint safety improvements

---

## v2.48.0 - 2026-03-09

### Added
- Added group frame composer
- Added option to show GCD of instant spell as a castbar
- Added option to make minimap button drawer open on mouseover
- Added chat sound alerts with LibSharedMedia support
- Added auction house expansion filter

### Changed
- Made custom datatext panels lockable

---

## v2.47.0 - 2026-03-07

### Added
- Added party and raid frames (Group Frames)

---

## v2.46.0 - 2026-03-04

### Added
- Added new collapsible side menu structure
- Added minimap button drawer enhancements

---

## v2.45.0 - 2026-03-03

### Added
- Added minimap button drawer
- Added action bar button spacing
- Added equipment slot tracking for custom trackers
- Added option to allow /reload in combat
- Added custom tracker bars to anchoring system
- Added help and documentation pages

---

## v2.44.3 - 2026-03-03

### Added
- Allow for ESC to close the settings panel
- Added Rotation Assist Icon to Anchoring & Layout (under CDM)

### Fixed
- Fixed GCD swipes/glows for some classes
- Fixed issues with tooltip parent frames
- Fixed skyriding speed math
- Fixed missing enchant texts for character pane
- Fixed LeaveVehicleButton showing when not in a vehicle

---

For older versions, see the [full changelog on GitHub](https://github.com/zol-wow/QUI/blob/main/CHANGELOG.md).
