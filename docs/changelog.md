---
layout: default
title: Changelog
nav_order: 5
---

# Changelog

All notable changes to QUI are documented here. For the complete changelog, see the [CHANGELOG.md](https://github.com/zol-wow/QUI/blob/main/CHANGELOG.md) on GitHub.

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
