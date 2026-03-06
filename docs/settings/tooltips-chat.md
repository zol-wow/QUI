---
layout: default
title: Tooltips & Chat
parent: Settings Reference
nav_order: 13
---

# Tooltips & Chat

Tooltip and Chat settings are accessible from the **General & QoL** tab in-game but are documented separately here for convenience. This page also covers Skyriding, XP Tracker, Combat Text, BRez Counter, Combat Timer, M+ Timer, Raid Buffs, and Buff/Debuff Borders settings.

---

## Tooltip Settings

**Database path:** `db.profile.tooltip`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `tooltip.enabled` | boolean | `true` | Enable tooltip module |
| `tooltip.anchorToCursor` | boolean | `true` | Follow cursor |
| `tooltip.cursorAnchor` | string | `"TOPLEFT"` | Cursor anchor point |
| `tooltip.cursorOffsetX` | number | `16` | Cursor X offset |
| `tooltip.cursorOffsetY` | number | `-16` | Cursor Y offset |
| `tooltip.hideInCombat` | boolean | `true` | Hide in combat |
| `tooltip.classColorName` | boolean | `false` | Class color names |
| `tooltip.fontSize` | number | `12` | Font size |
| `tooltip.skinTooltips` | boolean | `true` | Apply QUI theme |
| `tooltip.bgColor` | color | `{0.05, 0.05, 0.05, 1}` | Background color |
| `tooltip.bgOpacity` | number | `0.95` | Background opacity |
| `tooltip.showBorder` | boolean | `true` | Show border |
| `tooltip.borderThickness` | number | `1` | Border thickness (1-10) |
| `tooltip.borderColor` | color | `{0.2, 1, 0.6, 1}` | Border color (mint) |
| `tooltip.borderUseClassColor` | boolean | `false` | Class color border |
| `tooltip.borderUseAccentColor` | boolean | `false` | Accent color border |
| `tooltip.showSpellIDs` | boolean | `false` | Show spell/icon IDs |
| `tooltip.hideHealthBar` | boolean | `true` | Hide health bar |
| `tooltip.combatKey` | string | `"SHIFT"` | Combat modifier key |

### Per-Context Visibility

**Database path:** `db.profile.tooltip.visibility`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `visibility.npcs` | string | `"SHOW"` | NPC/player tooltips |
| `visibility.abilities` | string | `"SHOW"` | Action bar tooltips |
| `visibility.items` | string | `"SHOW"` | Bag/bank item tooltips |
| `visibility.frames` | string | `"SHOW"` | Unit frame tooltips |
| `visibility.cdm` | string | `"SHOW"` | CDM tooltips |
| `visibility.customTrackers` | string | `"SHOW"` | Custom tracker tooltips |

Options for each visibility key: `SHOW`, `HIDE`, `SHIFT`, `CTRL`, `ALT`

---

## Chat Settings

**Database path:** `db.profile.chat`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `chat.enabled` | boolean | `true` | Enable chat module |

### Glass Effect

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `glass.enabled` | boolean | `true` | Enable glass effect |
| `glass.bgAlpha` | number | `0.25` | Background transparency |
| `glass.bgColor` | color | `{0, 0, 0}` | Background color |

### Message Fade

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `fade.enabled` | boolean | `false` | Enable message fade |
| `fade.delay` | number | `15` | Seconds before fade |
| `fade.duration` | number | `0.6` | Fade animation duration |

### Font

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `font.forceOutline` | boolean | `false` | Force font outline |

### URLs

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `urls.enabled` | boolean | `true` | Enable URL detection |
| `urls.color` | color | `{0.078, 0.608, 0.992, 1}` | URL color (blue) |

### UI Cleanup

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `chat.hideButtons` | boolean | `true` | Hide social/channel/scroll buttons |

### Edit Box

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `editBox.enabled` | boolean | `true` | Style input box |
| `editBox.bgAlpha` | number | `0.25` | Input box transparency |
| `editBox.bgColor` | color | `{0, 0, 0}` | Input box color |
| `editBox.height` | number | `20` | Input box height |
| `editBox.positionTop` | boolean | `false` | Position above chat |

### Timestamps

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `timestamps.enabled` | boolean | `false` | Enable timestamps |
| `timestamps.format` | string | `"24h"` | Format: `24h` or `12h` |
| `timestamps.color` | color | `{0.6, 0.6, 0.6}` | Timestamp color |

### Copy Button

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `chat.copyButtonMode` | string | `"always"` | Mode: `always`, `hover`, `hidden`, `disabled` |

### Intro Message

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `chat.showIntroMessage` | boolean | `true` | Show login message |

### Message History

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `messageHistory.enabled` | boolean | `true` | Enable message history |
| `messageHistory.maxHistory` | number | `50` | Max stored messages |

---

## Skyriding

**Database path:** `db.profile.skyriding`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `skyriding.enabled` | boolean | `true` | Enable vigor bar |
| `skyriding.width` | number | `250` | Bar width |
| `skyriding.vigorHeight` | number | `20` | Vigor bar height |
| `skyriding.secondWindHeight` | number | `20` | Second wind height |
| `skyriding.useClassColorVigor` | boolean | `false` | Class color bar |
| `skyriding.barColor` | color | `{0.2, 0.8, 1, 1}` | Bar color |
| `skyriding.showSegments` | boolean | `true` | Show segments |
| `skyriding.showSpeed` | boolean | `true` | Show speed |
| `skyriding.speedFormat` | string | `"PERCENT"` | Speed format |
| `skyriding.showVigorText` | boolean | `true` | Show vigor text |
| `skyriding.vigorTextFormat` | string | `"FRACTION"` | Vigor format |
| `skyriding.secondWindMode` | string | `"MINIBAR"` | Second wind mode |
| `skyriding.useThrillOfTheSkiesColor` | boolean | `true` | Thrill color |
| `skyriding.thrillOfTheSkiesColor` | color | `{1, 0.5, 0, 1}` | Thrill color (orange) |
| `skyriding.visibility` | string | `"FLYING_ONLY"` | Visibility mode |
| `skyriding.fadeDelay` | number | `1` | Fade delay |
| `skyriding.fadeDuration` | number | `0.3` | Fade duration |

---

## XP Tracker

**Database path:** `db.profile.xpTracker`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `xpTracker.enabled` | boolean | `false` | Enable XP tracker |
| `xpTracker.width` | number | `300` | Frame width |
| `xpTracker.height` | number | `90` | Frame height |
| `xpTracker.barHeight` | number | `20` | Bar height |
| `xpTracker.headerFontSize` | number | `12` | Header font size |
| `xpTracker.fontSize` | number | `11` | Details font size |
| `xpTracker.locked` | boolean | `true` | Lock position |
| `xpTracker.hideTextUntilHover` | boolean | `false` | Hide text until hover |
| `xpTracker.detailsGrowDirection` | string | `"auto"` | Grow direction |
| `xpTracker.barTexture` | string | `"Solid"` | Bar texture |
| `xpTracker.showBarText` | boolean | `true` | Show bar text |
| `xpTracker.showRested` | boolean | `true` | Show rested XP |
| `xpTracker.barColor` | color | `{0.2, 0.5, 1, 1}` | Bar color |
| `xpTracker.restedColor` | color | `{1, 0.7, 0.1, 0.5}` | Rested XP color |

---

## Combat Text

**Database path:** `db.profile.combatText`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `combatText.enabled` | boolean | `true` | Enable combat text |
| `combatText.displayTime` | number | `0.8` | Display duration |
| `combatText.fadeTime` | number | `0.3` | Fade duration |
| `combatText.fontSize` | number | `14` | Font size |
| `combatText.enterCombatColor` | color | `{1, 0.98, 0.2, 1}` | +Combat color |
| `combatText.leaveCombatColor` | color | `{1, 0.98, 0.2, 1}` | -Combat color |

---

## BRez Counter

**Database path:** `db.profile.brzCounter`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `brzCounter.enabled` | boolean | `true` | Enable BRez counter |
| `brzCounter.width` | number | `50` | Frame width |
| `brzCounter.height` | number | `50` | Frame height |
| `brzCounter.fontSize` | number | `14` | Font size |
| `brzCounter.showBackdrop` | boolean | `true` | Show backdrop |
| `brzCounter.noChargesColor` | color | `{1, 0.3, 0.3, 1}` | No charges color |
| `brzCounter.hasChargesColor` | color | `{0.3, 1, 0.3, 1}` | Has charges color |

---

## Combat Timer

**Database path:** `db.profile.combatTimer`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `combatTimer.enabled` | boolean | `false` | Enable combat timer |
| `combatTimer.fontSize` | number | `16` | Font size |
| `combatTimer.showBackdrop` | boolean | `true` | Show backdrop |
| `combatTimer.onlyShowInEncounters` | boolean | `false` | Boss encounters only |

---

## M+ Timer

**Database path:** `db.profile.mplusTimer`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `mplusTimer.enabled` | boolean | `false` | Enable custom M+ timer |
| `mplusTimer.layoutMode` | string | `"sleek"` | Layout mode |
| `mplusTimer.showTimer` | boolean | `true` | Show timer |
| `mplusTimer.showBorder` | boolean | `true` | Show border |
| `mplusTimer.showDeaths` | boolean | `true` | Show deaths |
| `mplusTimer.showAffixes` | boolean | `true` | Show affixes |
| `mplusTimer.showObjectives` | boolean | `true` | Show objectives |
| `mplusTimer.forcesBarEnabled` | boolean | `true` | Show forces bar |
| `mplusTimer.forcesDisplayMode` | string | `"bar"` | Forces display mode |
| `mplusTimer.maxDungeonNameLength` | number | `18` | Max dungeon name length |

---

## Raid Buffs

**Database path:** `db.profile.raidBuffs`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `raidBuffs.enabled` | boolean | `true` | Enable missing buffs |
| `raidBuffs.showOnlyInGroup` | boolean | `true` | Only show in group |
| `raidBuffs.providerMode` | boolean | `false` | Provider mode |
| `raidBuffs.iconSize` | number | `32` | Icon size |
| `raidBuffs.growDirection` | string | `"RIGHT"` | Grow direction |

---

## Buff/Debuff Borders

**Database path:** `db.profile.buffBorders`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `buffBorders.enableBuffs` | boolean | `true` | Style buff borders |
| `buffBorders.enableDebuffs` | boolean | `true` | Style debuff borders |
| `buffBorders.borderSize` | number | `2` | Border thickness |
