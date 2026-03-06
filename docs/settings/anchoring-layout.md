---
layout: default
title: Anchoring & Layout
parent: Settings Reference
nav_order: 6
---

# Anchoring & Layout

The Anchoring & Layout tab controls frame positioning, the anchoring system that chains frames together, HUD layering, and global options panel settings. QUI uses a pixel-nudge system in Edit Mode to precisely position frames, and an anchoring system that lets frames follow each other when repositioned.

**DB path:** Various sub-paths within `db.profile`

---

## Frame Nudge

Controls the precision of arrow-key nudging in Edit Mode.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `nudgeAmount` | number | `1` | Pixel distance per nudge press in Edit Mode |

---

## Player Unit Frame Anchor

Anchor the Player unit frame to a CDM bar or power bar so it follows when repositioned.

**DB path:** `db.profile.quiUnitFrames.player`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `quiUnitFrames.player.anchorTo` | string | `"disabled"` | Anchor target: `disabled`, `essential`, `utility`, `primary`, `secondary` |
| `quiUnitFrames.player.anchorGap` | number | `10` | Vertical gap from the anchor frame in pixels |
| `quiUnitFrames.player.anchorYOffset` | number | `0` | Additional vertical offset from anchor position |

---

## Target Unit Frame Anchor

Anchor the Target unit frame to a CDM bar or power bar.

**DB path:** `db.profile.quiUnitFrames.target`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `quiUnitFrames.target.anchorTo` | string | `"disabled"` | Anchor target: `disabled`, `essential`, `utility`, `primary`, `secondary` |
| `quiUnitFrames.target.anchorGap` | number | `10` | Vertical gap from the anchor frame in pixels |
| `quiUnitFrames.target.anchorYOffset` | number | `0` | Additional vertical offset from anchor position |

---

## Utility Bar Anchor

Anchor the Utility CDM bar below the Essential CDM bar so they stack vertically.

**DB path:** `db.profile.ncdm.utility`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `ncdm.utility.anchorBelowEssential` | boolean | `false` | Anchor Utility bar below Essential bar's last row |
| `ncdm.utility.anchorGap` | number | `0` | Pixel gap between Essential and Utility when anchored |

---

## Buff Icons Anchor

Anchor the CDM Buff icon container to another CDM bar.

**DB path:** `db.profile.ncdm.buff`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `ncdm.buff.anchorTo` | string | `"disabled"` | Anchor target: `disabled`, `essential`, `utility` |
| `ncdm.buff.anchorPlacement` | string | `"center"` | Anchor placement relative to target: `center`, `left`, `right` |
| `ncdm.buff.anchorSpacing` | number | `0` | Vertical spacing from the anchor target |
| `ncdm.buff.anchorSourcePoint` | string | `"CENTER"` | Source attachment point |
| `ncdm.buff.anchorTargetPoint` | string | `"CENTER"` | Target attachment point |
| `ncdm.buff.anchorOffsetX` | number | `0` | Additional horizontal offset |
| `ncdm.buff.anchorOffsetY` | number | `0` | Additional vertical offset |

---

## Tracked Bar Anchor

Anchor the CDM Tracked Bar container to another CDM bar.

**DB path:** `db.profile.ncdm.trackedBar`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `ncdm.trackedBar.anchorTo` | string | `"disabled"` | Anchor target: `disabled`, `essential`, `utility` |
| `ncdm.trackedBar.anchorPlacement` | string | `"center"` | Anchor placement: `center`, `left`, `right` |
| `ncdm.trackedBar.anchorSpacing` | number | `0` | Vertical spacing from the anchor target |
| `ncdm.trackedBar.anchorSourcePoint` | string | `"CENTER"` | Source attachment point |
| `ncdm.trackedBar.anchorTargetPoint` | string | `"CENTER"` | Target attachment point |

---

## Power Bar Anchor

Controls how the Primary Power Bar attaches to CDM bars and other frames.

**DB path:** `db.profile.powerBar`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `powerBar.autoAttach` | boolean | `false` | Auto-attach power bar to a CDM viewer |
| `powerBar.standaloneMode` | boolean | `false` | Standalone positioning (free placement, ignores attachment) |
| `powerBar.attachTo` | string | `"EssentialCooldownViewer"` | Frame to attach to when auto-attach is enabled |
| `powerBar.lockedToEssential` | boolean | `false` | Auto-resize width to match Essential CDM bar |
| `powerBar.lockedToUtility` | boolean | `false` | Auto-resize width to match Utility CDM bar |
| `powerBar.snapGap` | number | `5` | Gap in pixels when snapped to a CDM bar |

---

## Secondary Power Bar Position

Controls how the Secondary Power Bar relates to the Primary bar.

**DB path:** `db.profile.secondaryPowerBar`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `secondaryPowerBar.lockedToPrimary` | boolean | `true` | Lock position and width to the Primary power bar |
| `secondaryPowerBar.lockedToEssential` | boolean | `false` | Auto-resize width to match Essential CDM bar |
| `secondaryPowerBar.lockedToUtility` | boolean | `false` | Auto-resize width to match Utility CDM bar |
| `secondaryPowerBar.snapGap` | number | `5` | Gap in pixels when snapped |

---

## Config Panel

Appearance settings for the QUI options panel itself.

**DB path:** `db.profile`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `configPanelScale` | number | `1.0` | Options panel UI scale multiplier |
| `configPanelWidth` | number | `750` | Options panel width in pixels |
| `configPanelAlpha` | number | `0.97` | Options panel background opacity (0-1) |

---

## Addon Accent Color

The accent color used throughout the QUI options panel theme, skinned frames, and UI highlights.

**DB path:** `db.profile`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `addonAccentColor` | color | `{0.204, 0.827, 0.6, 1}` | Addon accent color (#34D399 mint green) |

---

## HUD Layer Order

The HUD layering system controls the stacking order (frame level) of all QUI elements. Higher values render on top of lower values.

**DB path:** `db.profile.hudLayout.layerOrder`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `layerOrder.essentialBar` | number | `7` | Essential CDM bar frame level |
| `layerOrder.utilityBar` | number | `6` | Utility CDM bar frame level |
| `layerOrder.buffIcons` | number | `5` | CDM Buff icons frame level |
| `layerOrder.trackedBar` | number | `5` | CDM Tracked bar frame level |
| `layerOrder.powerBar` | number | `7` | Primary power bar frame level |
| `layerOrder.secondaryPowerBar` | number | `6` | Secondary power bar frame level |
| `layerOrder.playerFrame` | number | `4` | Player unit frame level |
| `layerOrder.playerIndicators` | number | `6` | Player frame indicators (above frame for visibility) |
| `layerOrder.targetFrame` | number | `4` | Target unit frame level |
| `layerOrder.totFrame` | number | `3` | Target-of-target frame level |
| `layerOrder.petFrame` | number | `3` | Pet frame level |
| `layerOrder.focusFrame` | number | `4` | Focus frame level |
| `layerOrder.bossFrames` | number | `4` | Boss frames level |
| `layerOrder.playerCastbar` | number | `5` | Player cast bar level |
| `layerOrder.targetCastbar` | number | `5` | Target cast bar level |
| `layerOrder.customBars` | number | `5` | Custom tracker bars level |
| `layerOrder.totemBar` | number | `5` | Totem bar level |
| `layerOrder.groupFrames` | number | `4` | Group frames (party/raid) level |
| `layerOrder.groupPetFrames` | number | `3` | Group pet frames level |
