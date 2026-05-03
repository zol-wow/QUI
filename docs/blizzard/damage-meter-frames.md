# Blizzard Damage Meter — Frame Reference

> Captured 2026-05-02 from WoW Midnight 12.0.x source (`Interface/AddOns/Blizzard_DamageMeter/`)
> via in-game framestack capture and cross-referenced against the Gethe/wow-ui-source mirror.
> Update this file if Blizzard restructures the meter in a future patch.

## TOC + load order

```
## Title: Blizzard_DamageMeter
## SavedVariablesPerCharacter: DamageMeterPerCharacterSettings
## Dependencies: Blizzard_EditMode

DamageMeterConstants.lua
DamageMeterEntry.lua / DamageMeterEntry.xml
DamageMeterSettingsDropdownButton.lua / .xml
DamageMeterSourceWindow.lua / .xml
DamageMeterSessionWindow.lua / .xml
DamageMeter.lua / DamageMeter.xml
```

ADDON_LOADED arg matches `Blizzard_DamageMeter`. Hard-depends on `Blizzard_EditMode` (the meter is an Edit Mode "system" frame).

## Activation CVar

`damageMeterEnabled` — boolean cached in `CVarCallbackRegistry`. Toggling Options → Gameplay Enhancements → Damage Meter flips it. Sample:

```lua
CVarCallbackRegistry:GetCVarValueBool("damageMeterEnabled")  -- true if user enabled the meter
```

`DamageMeterMixin:ShouldBeShown()` reads this CVar and `C_DamageMeter.IsDamageMeterAvailable()` to decide visibility. Returns `true` unconditionally when `IsEditing` is set, so the meter forcibly appears during Blizzard Edit Mode.

## Frame hierarchy

### Manager (singleton)

- **Global:** `_G.DamageMeter`
- **Mixin:** `DamageMeterMixin`
- **Inherits:** `EditModeDamageMeterSystemTemplate` (Edit Mode system frame — has `OnSystemLoad`, `IsEditing`, `SetIsEditing`, etc.)
- **Parent:** `UIParent`
- **Holds:** `windowDataList` array `[{ damageMeterType, sessionType, sessionID, sessionWindow, locked, nonInteractive, minimized }]`
- **Created at addon load** via `<Frame name="DamageMeter" inherits="DamageMeterTemplate" parent="UIParent">`
- **Max session windows:** 3 (`MAX_DAMAGE_METER_SESSION_WINDOWS = 3`)
- **Primary window index:** 1 (`PRIMARY_SESSION_WINDOW_INDEX = 1`)

### Session windows

- **Globals:** `_G.DamageMeterSessionWindow1`, `…Window2`, `…Window3` (created on demand by `DamageMeterMixin:SetupSessionWindow`).
- **Template:** `DamageMeterSessionWindowTemplate`
- **Mixin:** `DamageMeterSessionWindowMixin`
- **Parent:** `_G.DamageMeter`
- **Resizable:** yes (300×120 to 600×400)
- **Primary window:** anchored TOPLEFT/BOTTOMRIGHT to `_G.DamageMeter`; positioned via Edit Mode only.
- **Secondary windows:** mouse-movable / mouse-resizable when not locked.

### Session window children (read paths)

```
DamageMeterSessionWindow<N>
├─ Header                     -- BACKGROUND layer texture, atlas "ui-damagemeters-header-bar"
├─ SessionTimer               -- OVERLAY layer fontstring (GameFontNormalMed1)
├─ MinimizeButton             -- Button (atlas "ui-questtrackerbutton-collapse-all")
├─ SettingsDropdown           -- DropdownButton (DamageMeterSettingsDropdownButtonTemplate)
├─ SessionDropdown            -- DropdownButton (WowStyle2DropdownTemplate)
│   └─ SessionName            -- OVERLAY fontstring; the "O"/"C"/prior pill text
├─ DamageMeterTypeDropdown    -- DropdownButton (WowStyle1ArrowDropdownTemplate)
│   └─ TypeName               -- OVERLAY fontstring (e.g. "Damage Done", "DPS")
└─ MinimizeContainer          -- Frame (setAllPoints, useParentLevel)
    ├─ Background             -- BACKGROUND atlas "damagemeters-background", initial alpha=0
    ├─ NotActive              -- OVERLAY fontstring (shown when no data)
    ├─ ScrollBox              -- WowScrollBoxList (the meter's row list)
    ├─ ScrollBar              -- EventFrame, MinimalScrollBar, alpha 0.3 default
    ├─ ResizeButton           -- Button, atlas "damagemeters-scalehandle"
    ├─ LocalPlayerEntry       -- Button (DamageMeterSourceEntryTemplate), shown when local player scrolls out of view
    └─ SourceWindow           -- Frame (DamageMeterSourceWindowTemplate) — the BREAKDOWN POPUP
```

### Convenience accessors on `DamageMeterSessionWindowMixin`

```lua
sessionWindow:GetMinimizeContainer()         -- the MinimizeContainer frame
sessionWindow:GetScrollBox()                 -- WowScrollBoxList for entry frames
sessionWindow:GetScrollBar()
sessionWindow:GetSourceWindow()              -- the breakdown popup frame
sessionWindow:GetHeader()                    -- the Header texture
sessionWindow:GetMinimizeButton()
sessionWindow:GetSettingsDropdown()
sessionWindow:GetSessionDropdown()
sessionWindow:GetDamageMeterTypeDropdown()
sessionWindow:GetLocalPlayerEntry()
sessionWindow:GetResizeButton()
sessionWindow:GetBackground()                -- MinimizeContainer.Background
sessionWindow:GetNotActiveFontString()
sessionWindow:GetSessionTimerFontString()
sessionWindow:EnumerateEntryFrames()         -- iterator over visible row frames
sessionWindow:ForEachEntryFrame(func)        -- callback invoked per row
sessionWindow:GetEntryFrameCount()
```

### Source window (breakdown popup)

- **Path:** `sessionWindow.MinimizeContainer.SourceWindow` (NOT a separate global)
- **Template:** `DamageMeterSourceWindowTemplate`
- **Mixin:** `DamageMeterSourceWindowMixin`
- **Frame strata:** `HIGH`
- **Created** as a child of `MinimizeContainer` per session window. Hidden by default; shown when user clicks a row → `DamageMeterSessionWindowMixin:ShowSourceWindow(source)`.
- **Children:**
  ```
  SourceWindow
  ├─ Background         -- BACKGROUND atlas "common-dropdown-bg"
  ├─ ScrollBox          -- WowScrollBoxList, rows use DamageMeterSpellEntryTemplate
  ├─ ScrollBar          -- EventFrame, MinimalScrollBar
  └─ ResizeButton       -- Button, atlas "damagemeters-scalehandle"
  ```
- **Auto-closes** on `GLOBAL_MOUSE_DOWN` outside the popup.

### Row entries

Three templates, all inheriting `DamageMeterEntryTemplate`:

| Template | Mixin | Used for |
|---|---|---|
| `DamageMeterEntryTemplate` | `DamageMeterEntryMixin` | base |
| `DamageMeterSourceEntryTemplate` | `DamageMeterSourceEntryMixin` | session window rows (one per source) |
| `DamageMeterSpellEntryTemplate` | `DamageMeterSpellEntryMixin` | breakdown popup rows (one per ability) |

#### Row child structure

```
<row Button>                         -- frame name auto-generated (e.g. "IRB0347abf0")
├─ Icon                              -- Frame, 24×24
│   └─ Icon                          -- ARTWORK Texture, parent's `.Icon` atlas/texture (class or spec icon)
└─ StatusBar                         -- StatusBar
    │   <BarTexture atlas="UI-HUD-CoolDownManager-Bar" setAllPoints="true"/>
    ├─ Background                    -- BACKGROUND Texture, atlas "ui-damagemeters-bar-shadowbg"
    ├─ BackgroundEdge                -- OVERLAY Texture, atlas "ui-damagemeters-bar-shadowedge"
    ├─ Value                         -- OVERLAY FontString (NumberFontNormal, left-justify)
    └─ Name                          -- OVERLAY FontString (NumberFontNormal, left-justify)
```

`StatusBar.Background` and `StatusBar.BackgroundEdge` are tracked together via `StatusBar.BackgroundRegions = { Background, BackgroundEdge }`.

#### Row mixin accessors

```lua
row:GetIcon()                        -- the .Icon.Icon texture
row:GetStatusBar()                   -- the StatusBar frame
row:GetStatusBarTexture()            -- StatusBar:GetStatusBarTexture()  (the BarTexture)
row:GetName()                        -- StatusBar.Name fontstring
row:GetValue()                       -- StatusBar.Value fontstring
row:GetBackground()                  -- StatusBar.Background texture
row:GetBackgroundEdge()              -- StatusBar.BackgroundEdge texture
row:GetBackgroundRegions()           -- { Background, BackgroundEdge }
row:GetBackgroundAlpha()             -- value Blizzard wants applied
row:GetBackgroundRegionAlpha()       -- alpha currently applied to background regions
```

#### Row state writes (hook-target candidates)

```lua
DamageMeterEntryMixin:Init(source)               -- new data assigned, all updaters fire
DamageMeterEntryMixin:UpdateIcon()
DamageMeterEntryMixin:UpdateName()
DamageMeterEntryMixin:UpdateValue()
DamageMeterEntryMixin:UpdateStatusBar()
DamageMeterEntryMixin:UpdateStatusBarColor()     -- sets vertex color on bar texture (CLASS COLOR PATH)
DamageMeterEntryMixin:UpdateStyle()              -- re-anchors based on Enum.DamageMeterStyle
DamageMeterEntryMixin:UpdateBackground()         -- re-asserts alpha on BackgroundRegions
DamageMeterEntryMixin:SetUseClassColor(bool)
DamageMeterEntryMixin:SetStyle(style)
DamageMeterEntryMixin:SetBackgroundAlpha(alpha)
```

## Class colors — IMPORTANT GOTCHA

Class color is applied **as a vertex color on the bar texture**, not via `SetStatusBarColor`. From `DamageMeterEntryMixin:SetStatusBarColor`:

```lua
function DamageMeterEntryMixin:SetStatusBarColor(color)
    if color ~= self.statusBarColor then
        self.statusBarColor = color;
        self:GetStatusBarTexture():SetVertexColor(color:GetRGB());
    end
end
```

**Implication for our skin:** if we replace the StatusBar's texture with `Helpers.GetGeneralTexture()`, the new texture inherits the previous vertex color until Blizzard's next `UpdateStatusBarColor` call. Two safe patterns:

1. **Don't swap the bar texture** — the stock atlas `UI-HUD-CoolDownManager-Bar` is essentially flat, so leaving it alone preserves class colors automatically. Just hide `StatusBar.Background` and `StatusBar.BackgroundEdge` to remove the chrome around it.
2. **Swap the bar texture and re-tint** — call `:SetStatusBarTexture(QUI_TEXTURE)` then immediately `:SetVertexColor(currentR, currentG, currentB, currentA)` reading from `:GetStatusBarColor()`. Re-hook `UpdateStatusBarColor` to keep the tint in sync when class color changes (e.g. user toggles class colors off via Edit Mode).

The simpler choice is **option 1** (leave the texture alone). The Blizzard atlas is a flat rectangle, not gradient; visually it matches QUI's WHITE8x8 once the chrome is stripped.

## Style enum (4 layouts)

`Enum.DamageMeterStyle`:

| Value | Setup function | Background atlas |
|---|---|---|
| `Default` | `SetupDefaultStyle` | `ui-damagemeters-bar-shadowbg` |
| `Bordered` | `SetupBorderedStyle` (alias of Default w/ different atlas) | `UI-HUD-CoolDownManager-Bar-BG` |
| `FullBackground` | `SetupFullBackgroundStyle` (alias of Default) | `ui-damagemeters-bar-shadowbg` |
| `Thin` | `SetupThinStyle` (text above bar) | `ui-damagemeters-bar-shadowbg` |

User picks via Edit Mode. Our skin must work across all four. `UpdateStyle()` re-anchors and re-applies the style; it's called by `SetStyle()`. Hooking `UpdateStyle()` post-call is the right point to re-strip our chrome and re-apply our row backdrop sizes.

`UpdateBackground()` re-asserts `:SetAlpha(alpha)` on every region in `BackgroundRegions`. To keep the stock backgrounds hidden we hook `UpdateBackground` and immediately set them back to alpha 0.

## Atlases used (chrome to strip)

| Region | Atlas |
|---|---|
| Header (per session window) | `ui-damagemeters-header-bar` |
| MinimizeContainer.Background | `damagemeters-background` (initial alpha=0 in XML, can be raised by `SetBackgroundAlpha`) |
| StatusBar.Background | `ui-damagemeters-bar-shadowbg` (Default/FullBg/Thin) or `UI-HUD-CoolDownManager-Bar-BG` (Bordered) |
| StatusBar.BackgroundEdge | `ui-damagemeters-bar-shadowedge` |
| MinimizeContainer.ResizeButton | `damagemeters-scalehandle` (+ `-hover`, `-pressed`) |
| Source window Background | `common-dropdown-bg` |
| MinimizeButton | `ui-questtrackerbutton-collapse-all` (toggles to `expand-all` when minimized) |

## Edit Mode integration

The meter inherits `EditModeDamageMeterSystemTemplate` and registers with the Edit Mode framework via `EditModeDamageMeterSystemMixin.OnSystemLoad(self)` (called from `DamageMeterMixin:OnLoad`).

Edit Mode controls these meter properties via the system framework:
- Bar height (`SetBarHeight`)
- Text scale (`SetTextScale`)
- Window alpha (`SetWindowAlpha`)
- Background alpha (`SetBackgroundAlpha`)
- Bar spacing (`SetBarSpacing`)
- Class colors on/off (`SetUseClassColor`)
- Show bar icons (`SetShowBarIcons`)
- Style (`SetStyle`)
- Number display type (`SetNumberDisplayType`)
- Position / size of the primary window only

`DamageMeterMixin:SetIsEditing(true)` forces the meter visible (`ShouldBeShown` returns `true` when editing). **This means our suppression-during-Blizzard-Edit-Mode approach must override Blizzard's force-show.** `:Hide()` on each session window after Blizzard's Edit Mode handler runs is the cleanest path. Order matters: hook `EnterEditMode` and call `:Hide()` after Blizzard finishes its work.

## API for the future "Take Over" phase (`C_DamageMeter`)

Blizzard exposes these — useful for Stage 3 when QUI builds its own meter window backed by Blizzard's data feed:

```lua
C_DamageMeter.IsDamageMeterAvailable()                      -- (isAvailable, failureReason)
C_DamageMeter.GetSessionDurationSeconds(sessionType)        -- elapsed seconds for current/overall session
C_DamageMeter.GetCombatSessionFromType(sessionType, type)   -- {combatSources, maxAmount, totalAmount, durationSeconds, ...}
C_DamageMeter.GetCombatSessionFromID(sessionID, type)
C_DamageMeter.GetAvailableCombatSessions()                  -- {{sessionID, name, durationSeconds}, ...}
C_DamageMeter.ResetAllCombatSessions()
```

Events:
- `DAMAGE_METER_COMBAT_SESSION_UPDATED` (args: `damageMeterType`, `sessionID`)
- `DAMAGE_METER_RESET`
- `DAMAGE_METER_CURRENT_SESSION_UPDATED`

Enums:
- `Enum.DamageMeterType.{DamageDone, Dps, DamageTaken, AvoidableDamageTaken, EnemyDamageTaken, HealingDone, Hps, Absorbs, Interrupts, Dispels, Deaths}`
- `Enum.DamageMeterSessionType.{Overall, Current, Expired}`
- `Enum.DamageMeterStyle.{Default, Bordered, FullBackground, Thin}`
- `Enum.DamageMeterNumbers.{Minimal, Compact, Complete}`
- `Enum.DamageMeterVisibility.{Always, InCombat, Hidden}`

## Saved variables

`DamageMeterPerCharacterSettings`:
```lua
{
    windowDataList = {
        [1] = { damageMeterType, sessionType, shown, locked, nonInteractive, minimized },
        [2] = { ... },
        [3] = { ... },
    },
}
```

## Hook targets summary

For QUI's skin module, these are the recommended `hooksecurefunc` targets:

| Target | Purpose |
|---|---|
| `_G.DamageMeter:CreateWindowData(idx)` (post-call) | Discover newly-created session windows |
| `_G.DamageMeter:SetupSessionWindow(idx, data)` | Discover when an existing window slot gets a window assigned |
| `_G.DamageMeter:OnUseClassColorChanged(useClassColor)` | Notice when user toggles class colors via Edit Mode |
| `_G.DamageMeter:OnStyleChanged(style)` | Notice when user changes layout style |
| `_G.DamageMeter:OnShowBarIconsChanged(showBarIcons)` | Notice icon-visibility changes |
| `DamageMeterSessionWindowMixin.SetupEntry` | Per-row first-time setup; ideal point to apply our row skin |
| `DamageMeterSessionWindowMixin.InitEntry` | Per-row data refresh; cheap re-skin point |
| `DamageMeterSessionWindowMixin.OnUseClassColorChanged` | Per-window class-color refresh |
| `DamageMeterSessionWindowMixin.UpdateBackground` (via `OnBackgroundAlphaChanged`) | Re-apply our stripped backgrounds |
| `DamageMeterSessionWindowMixin.ShowSourceWindow` | Detect and skin breakdown popup on first show |
| `DamageMeterEntryMixin.UpdateStyle` | Per-row style change; re-strip backgrounds + re-anchor our row backdrop |
| `DamageMeterEntryMixin.UpdateBackground` | Per-row background-alpha re-assertion; re-strip |
| `DamageMeterEntryMixin.UpdateStatusBarColor` | Class-color writes; only need if we swap the bar texture |
| `EditModeManagerFrame.EnterEditMode` (post-call) | Hide all session windows |
| `EditModeManagerFrame.ExitEditMode` (post-call) | Show all session windows that should be shown |

Mixin-level `hooksecurefunc(SomeMixin, "Method", fn)` works because session windows / row buttons are created from these mixins; our hook fires on every instance.

## Confirmed working assumptions

- `_G.DamageMeter` is the singleton manager, `parent=UIParent`, `frameLevel` 1 by default.
- Session windows are `_G.DamageMeterSessionWindow1..3` — at most 3 ever exist.
- Primary window is always `DamageMeterSessionWindow1`; it can never be hidden by user action.
- Secondary windows are mouse-movable / mouse-resizable when not locked.
- Every session window includes a SourceWindow (breakdown popup) as a child of MinimizeContainer.
- Rows are pooled WowScrollBoxList children; access via `sessionWindow:ForEachEntryFrame(fn)` or `sessionWindow:EnumerateEntryFrames()`.
- Class-color path: bar texture vertex color, NOT `SetStatusBarColor`.
- Edit Mode integration is mandatory (`Dependencies: Blizzard_EditMode`).

## Open questions / surprises

- **Tooltip type:** `DamageMeterSpellEntryMixin:Init` uses `GetAppropriateTooltip()` and calls `tooltip:SetSpellByID`. This returns the standard `GameTooltip` in normal context, so our existing tooltip skin in `skinning/system/tooltips.lua` covers it.
- **Animations:** `MinimizeContainer.ShowResizeButton` and `EmphasizeScrollBar` are AnimationGroups that play on mouse-over. We don't need to interact with these; they don't affect skin.
- **The meter forces visibility during Edit Mode** even with our skin off. Our skin's `:Hide()` after `EnterEditMode` will fight this — but since QUI takes positioning, that's the desired outcome.
- **`damageMeterEnabled` CVar** is the only signal for "is the meter on right now". `ADDON_LOADED("Blizzard_DamageMeter")` fires once when the meter addon is enabled at character creation/character switch — but the meter addon may load even when the user has the toggle off. Use `IsBlizzardMeterEnabled = function() return CVarCallbackRegistry:GetCVarValueBool("damageMeterEnabled") end` instead of frame existence.

## How to update this doc

1. After any patch where the meter visibly changes, re-run `tools/dump_damage_meter.lua` in-game.
2. Pull current source via `gh api "repos/Gethe/wow-ui-source/contents/Interface/AddOns/Blizzard_DamageMeter?ref=live"`.
3. Diff against the captured frame names and accessor methods listed above.
4. Update the "Hook targets summary" if Blizzard added or renamed mixin methods.
