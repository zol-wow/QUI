# Changelog

All notable changes to QUI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).



## Unreleased



## v3.6.0-alpha9 - 2026-05-01

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing v34 profiles carry over unchanged. v3.5.x → alpha9: back up `WTF/` and export your profile first.

### Fixed
- **CDM stack text vanishes in combat on icons sharing a Blizzard child.** When two QUI icons mirrored the same buff-viewer child, the non-owning icon read its own stack count via `C_UnitAuras.GetPlayerAuraBySpellID` / `GetAuraDataBySpellName` rather than the hooked path. In combat that fallback went silent: `GetAuraDataBySpellName` isn't reliably callable in combat, and when neither API returned applications the icon's StackText simply blanked. Stack resolution now also consults `C_UnitAuras.GetAuraApplicationDisplayCount` (display-count fallback) and routes through `CDMSpellData:ResolveAuraState` in combat as a last resort, so non-owning icons keep their stack text accurate while the encounter is running.

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing v34 profiles carry over unchanged. v3.5.x → alpha8: back up `WTF/` and export your profile first.

### Added
- **Cooldown Manager master toggle.** A single switch under the Modules Control Center now disables the entire CDM subsystem at runtime — provider, containers, spelldata, icons, glows, and highlighter all stop processing events, polling, and forwarding cooldown data. Toggling shows a Reload UI? prompt: the current session hides the addon-owned containers and shuts the runtime down immediately, and a reload completes the engine handoff back to the default UI. Useful for quickly comparing addon-owned vs Blizzard's stock viewers, or for letting another cooldown addon take over without uninstalling QUI.
- **Action Bars master toggle in the Modules Control Center.** The Action Bars row now uses a feature-registry-backed entry with proper enable/disable handlers — flipping the toggle fires a Reload UI? prompt (action bars cannot be hooked or unhooked at runtime, so a reload is required for the handoff).

### Fixed
- **CDM `showOnlyOnCooldown` flicker on every cast.** Containers configured to show only while a spell is on cooldown were briefly hiding then re-showing the icon for ~1.5s on every player GCD. Three separate code paths (visibility filters, display-mode gates, desaturation) were independently re-deriving "is this a real cooldown vs a GCD-only cooldown?" using `_lastDuration <= 1.5s` as the heuristic — but during a player-wide GCD Blizzard temporarily writes the 1.5s GCD start/duration onto the source CD frame, and the mirror hook propagates that into `_lastDuration`. So for ~1.5s every cast every spell with a real cooldown got misclassified as GCD-only and its icon was hidden. Centralized into a single `ResolveCooldownActivityState` resolver that reads explicit `_hasRealCooldownActive` / `_hasGCDOnlyCooldown` flags set during `UpdateIconCooldown` instead of the brittle duration heuristic.
- **CDM charged-ability desaturation lag mid-recharge.** Charged spells could briefly desaturate during the recharge window when the charge-info cache lagged behind the cooldown-info cache. The new resolver consults `TickCacheGetDisplayCount` and `TickCacheGetCooldown.isActive == false` as additional "charges remain" signals so the icon stays lit through the cache stagger.
- **CDM swipe settings now apply on the next tick instead of waiting.** Toggling Show Buff Swipe / Show GCD Swipe in settings used to require a cooldown event to land before the change took effect on currently-displayed icons. The swipe refresh path now triggers the cooldown pipeline directly, so changes apply immediately on every active icon.

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations in this alpha; existing v34 profiles carry over unchanged. v3.5.x → alpha7: back up `WTF/` and export your profile first.

### Fixed
- **TOC bumped to support 12.0.7.** Interface line now lists 120000, 120001, 120005, 120007 so the addon loads on the latest WoW client without an out-of-date warning.
- **Health text no longer freezes at 100% HP on solo and group frames.** A guard that suppressed health updates while a unit was at full health left the value text stuck reading `100%` (or the configured full-HP string) until the unit took damage. The freeze path is gone — health text now refreshes on every UNIT_HEALTH event.
- **HUD show-when-damaged uses a C_CurveUtil step curve.** The damage-based HUD-visibility path was rebuilt around a `C_CurveUtil` step curve and now applies only to the player frame, sidestepping a class of secret-value alpha bugs where reading `UnitHealthPercent` in Lua returned a tainted value that couldn't be forwarded to `frame:SetAlpha`.
- **CDM: keybind and rotation overlays now clear when an icon is released.** Releasing a CDM icon back to the pool left its keybind text and rotation-glow overlays drawn on whatever spell next claimed that recycled icon. Both overlays are now wiped on release so the next user of the icon starts clean.
- **CDM: cooldown timing no longer leaks onto aura-kind icons.** A QUI aura icon whose `_blizzChild` resolved to a cooldown-viewer child carrying an `auraInstanceID` (e.g. Demon Hunter Metamorphosis — the cooldown viewer child still carries the aura ID while the buff is up) would inherit the spell's real cooldown swipe through the source-frame fan-out once the buff faded. The fan-out only gated on `_auraActive` / `hasCharges` / `_hasCooldownActive`; aura-kind classification was missing. All fan-out sites (`SetCooldownFromDurationObject` hook, `SetCooldown` hook, `ForwardToSubscribers`) now skip aura-kind targets, so aura entries get their swipe exclusively from the aura branch (DurationObject when active, `Cooldown:Clear` when inactive). Swipe styling also aligns with the per-entry kind taxonomy — aura entries on custom cooldown containers, essential, and utility containers all get correct aura-mode styling.
- **CDM: cooldown fan-out now skips icons whose blizzChild has been rebound.** Subscriber fan-out in `MirrorBlizzCooldown` forwarded cooldown timing to any icon whose entry pointed at the source blizzChild — including after Blizzard reused that cooldown-viewer child for a different spell, producing visible CD swipes on icons whose underlying spell had moved on. Each fan-out site now probes `cooldownInfo.spellID` / `overrideSpellID` / `linkedSpellIDs` plus `GetSpellID` / `GetAuraSpellID` (via `SafeValue` so secret fields don't poison the comparison) and skips the icon when readable IDs are observed and none match.
- **CDM: stack text on shared blizzChildren now reaches every subscribed icon.** A second QUI icon mirroring the same buff-viewer child as a first icon would lose its stack text — only one icon could be the "owner" of a given child's hooked StackText. The hook path now keeps a weak-keyed subscriber set per blizzChild and forwards Blizzard's text to every subscribed icon, with `display-count` stack values passing straight through to the StackText so multi-stack auras display correctly on duplicated icons.
- **CDM: custom containers now resolve buff-viewer children by entry kind.** Custom containers can mix aura and cooldown entries, but the previous fallback `_blizzChild` resolver only walked `_spellIDToChild` regardless of kind, leaving aura-kind entries without a buff-viewer child and excluding them from stack-text + aura-detection paths. Aura-kind entries now route through `CDMSpellData.FindBuffChildForSpell` first (kind-aware), then fall back to the existing viewer-spellMap lookup.
- **CDM bars: full-bar fill for no-expiration auras.** Auras that report no expiration time (true permanents) now render at 100% via a curve-driven overlay instead of dropping to empty. Stable detection uses an `IsZero` boolean, the OnLoop expired branch no longer stomps the C-side-driven fill, and a no-`DurationObject` fallback handles auras that don't expose duration objects at all.
- **CDM bars: hide rounded duration text on no-expiration auras.** Permanent auras previously read out as `0s` because the rounded duration text didn't suppress on the no-expiration path. The duration text is now hidden on the curve-driven full-bar path, with a base-alpha aware restore once the aura expires or transitions back to a timed state.
- **Blizzard buff borders: duration text state migrated off frame keys to a weak-keyed table.** `_quiDuration` / `_quiExpiration` / `_quiDuration_secs` were stored directly on Blizzard frame keys, which is unsafe under combat taint. State now lives in a weak-keyed addon-side table and is cleaned up automatically when a frame is collected. When aura timing is secret (or in combat without prior custom state), the path falls back to Blizzard's C-side countdown via `SetHideCountdownNumbers(false)` — secret-safe — and only renders our rounded text when fields are readable.
- **Group Frames: revamped options controls restored.** Several controls in the revamped Group Frames options panel had regressed and weren't visible/wired up correctly; restored.

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** Same backup advice. v3.6.0-alpha1/2/3/4/5 → alpha6: data already migrated. v3.5.x → alpha6: back up `WTF/` and export your profile first.
>
> This alpha includes a small **schema migration (v34)** that translates each unit frame's legacy `onlyMyDebuffs = true` flag into the new structured `debuffFilter.modifiers.PLAYER = true`, then removes the old key. Idempotent — visible behavior is preserved. Runs once on first load.

### Added
- **Modules Control Center.** New **Modules** sub-tab under General that surfaces every binary on/off QUI module in one place — ~76 entries across Display, QoL, Action Bars, Castbars, Group Frames, Unit Frames, Resource Bars, Instance, Cooldown Manager, 3rd Party, Tooltip, Character, and Subsystems categories. Each row is a pill toggle that flips the same DB key the module already used (no parallel store, no migration), with combat-locked greying + tooltip on protected modules and class/spec gating where it matters (Atonement Counter on Disc Priest, Totem Bar on Shaman). Section nav strip jumps between groups; the global Settings search now returns module toggles with a `[Module]` badge and an inline pill so you can flip a module without leaving the search dropdown.
- **Structured aura filters on unit frames.** Per-frame **buff filter** and **debuff filter** controls on player, target, focus, targettarget, pet, and boss1–5. Each aura settings card now has stackable modifier checkboxes (PLAYER, RAID, CANCELABLE, NOT CANCELABLE, INCLUDE NAME PLATE ONLY) plus an Exclusive Filter dropdown (External Defensive, Big Defensive, Important, Crowd Control, Raid Player Dispellable). Defaults are all-disabled — every aura renders by default; pick the ones that should pass. Filtering runs entirely C-side through Blizzard's filter string, so it stays taint-safe in combat.

### Changed
- **"Only My Debuffs" checkbox replaced by the new debuff filter.** The per-frame Only-My-Debuffs toggle is gone from the UI — its behavior is now expressed as `debuffFilter.modifiers.PLAYER = true` in the new structured filter system. The v34 migration flips that on for any profile that had the old checkbox enabled, so existing setups keep filtering exactly as they did.



## v3.6.0-alpha5 - 2026-05-01

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** Same backup advice. v3.6.0-alpha1/2/3/4 → alpha5: data already migrated. v3.5.x → alpha5: back up `WTF/` and export your profile first.
>
> This alpha includes a small **schema migration (v33)** that remaps four legacy third-party anchor aliases (`essential`, `utility`, `primary`, `secondary`) on saved BigWigs / DandersFrames / AbilityTimeline anchor configs to their canonical keys. Runs once, on first load. Existing settings keep working.

### Changed
- **Third-party "Anchor To" dropdown is now categorized + searchable.** The 3rd Party Addons Frame Positioning tab and the DandersFrames Layout Mode collapsible used a flat per-integration list with no headers and no search. Both surfaces now use the same registry-driven, categorized, searchable + collapsible Anchor To dropdown that every other mover in QUI uses, so anchoring third-party frames matches the rest of the experience.

### Fixed
- **Bundled QUI fonts (and most third-party LSM fonts) now appear in settings dropdowns.** The font dropdowns in CDM, Frames, Group Frames, Unit Frames, Action Bars, Character pane, and Click-cast were filtering by hardcoded path substrings (`"quaziiui"`, `"sharedmedia"`, `"Fonts\\"`). After the addon was renamed to QUI, asset paths became `Interface\AddOns\QUI\...` and no longer matched `"quaziiui"`, so all five bundled fonts (Quazii, Poppins ×4, Expressway) plus most third-party LSM fonts without "sharedmedia" in their path were silently dropped. Users saw only Blizzard built-in fonts. The path allowlist is gone — LSM is the gatekeeper for what gets registered, and broken file paths are still filtered by the existing prewarm-then-pcall step.
- **Custom CDM bars now collapse to the anchor edge when filters hide icons.** Custom bars with dynamic layout weren't compacting toward the configured corner when `hideNonUsable` (or any layout-time filter) hid icons — the bar would stretch wider and visible icons would float in the middle. Two root causes:
  - The frame anchoring system applied custom-bar corners via "size-stable" mode, baking corner-to-corner offsets from the frame's current width. When the bar shrank, both edges drifted symmetrically toward the old center. Buff/debuff/totem bars already opted out; custom-bar anchor keys (minted dynamically as `cdmCustom_*`) now do too.
  - The HUD min-width floor was being applied to every container, including custom bars, even though only `essential` and `utility` host the HUD frames — so custom bars got their width inflated to the floor. The floor is now gated to those two trackers only.

  Together: custom bars compute their natural icon-span width and stay glued to your chosen corner through filter flips.



## v3.6.0-alpha4 - 2026-04-30

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** Same backup advice applies. If you've been on v3.6.0-alpha1/alpha2/alpha3, your data has already been migrated. Coming straight from v3.5.x? Back up `WTF/` and export your profile first.
>
> This alpha also bundles everything from the recently-shipped v3.5.6 stable release.

### Added
- **Castbar preview in Unit Frames settings.** Animated mock castbar in the Unit Frames preview pane that follows the unit dropdown and reflects every Castbar-tab setting (geometry, colors, texture, border, icon, text anchors, channel ticks, GCD, empowered) live. Per-unit cycle scripts exercise hidden-by-default states (player cast/channel + optional empowered/GCD; target/focus interruptible vs non-interruptible alternation).

### Changed
- **DandersFrames anchoring polish.** Changing the **Anchor To** dropdown for a DandersFrames container no longer teleports it — offsets reset on target change in both the Frame Positioning tab and the Layout Mode right-click panel, matching owned-module behavior. Layout Mode's "Anchoring Details" panel now reports the true anchoring status for DandersFrames (it previously always showed "Disabled" because Danders stores its anchor in a separate DB path). The "Anchoring (drag the mover to place)" collapsible has been renamed to **Position** to match the rest of the modules, and the standalone tab's offset slider range is now `[-400, 400]` to match the Layout Mode panel.

### Fixed
- **Castbar drift after profile import + relog.** After importing a profile and logging out/in, castbars (especially `playerCastbar`) could drift to screen center. AceDB strips fields equal to defaults from saved entries, and the apply path was reading those entries raw — so `parent=nil` looked like an unset override and the castbar fell back to UIParent center. The apply path now reads through the AceDB proxy so default-stripped fields are filled back in correctly.
- **Selective profile export covers more.** Profile exports (especially Select-All) were silently dropping settings that were lazily created at runtime and missing from `defaults.lua`. Newly covered:
  - Resource-bar custom color/height, UI scale, options-panel size, and several other previously-orphaned fields — Select-All now round-trips every user-configurable field.
  - `db.layoutMode` (mover handle visibility, snap, side panel position) — now travels in the **Layout** category.
  - `db.optionsPanelCollapsibleStates` (which options-panel sections you've collapsed) — now travels in the **QoL** category.
- **`ADDON_ACTION_BLOCKED` on options open.** Clicking the QUI button on the GameMenu (or opening options via `/qui` for the first time) could trigger an `ADDON_ACTION_BLOCKED` error. Removed two redundant `SetPropagateKeyboardInput` calls outside `OnKeyDown`/`OnKeyUp` handlers — 12.0+ enforces that the API is only valid during the current key event.
- **Rogue flash border suppression hardened.**



## v3.6.0-alpha3 - 2026-04-30

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** Same backup advice applies. If you've been on v3.6.0-alpha1 or alpha2, your data has already been migrated. Coming straight from v3.5.x? Back up `WTF/` and export your profile first.

### Changed
- **Legacy spec-bar migration: promote and flag, don't wipe.** v3.6.0-alpha2 cleared entries on spec-specific custom bars so pre-V2 drag-handler garbage (slot indexes / cooldownIDs) wouldn't render as fallback `?` icons. The cost was that real spell IDs sitting on those bars got dropped too, leaving silently empty bars. v3.6.0-alpha3 promotes the entries instead, then surfaces a new amber **"Legacy data — may need review"** tooltip line in the Composer on entries that came in via the legacy slot path. Real spell IDs survive the migration; suspect entries are visually flagged so you can clean them up rather than guess what was lost.

### Fixed
- **Cross-character profile import preserves source spec.** Importing a QUI1 profile from one character to another (e.g. a Priest profile imported on a Warrior) was losing the source-spec association on spec-specific custom-tracker bars — the importing client's session would overwrite `_lastSpecID` with its own current spec before migrations ran, so the original spec hint was gone by the time the migration needed it. The fix stamps `_sourceSpecID` directly onto imported bars at import time on both full and selective imports, so the original spec stays attached through subsequent saves.
- **Trading Post alert no longer inflates into a screen-spanning yellow rectangle.** When the Trading Post (PerksProgram) frame is hidden, Blizzard's HelpTip anchored to its open button could compute unbounded text-wrap dimensions and balloon. The micro-button alert suppression now reaches non-global anchor buttons and the named alert frame, so the runaway callout is gated alongside standard micro-button glows.



## v3.6.0-alpha2 - 2026-04-30

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** Same advice as v3.6.0-alpha1 below. If you upgraded from v3.6.0-alpha1 already, your data has already been migrated. Anyone coming straight from v3.5.x should still back up `WTF/` and export their profile first.

### Changed
- **Legacy custom-bar migration is now conservative.** v3.6.0-alpha1 tried to salvage suspect spell IDs from pre-V2 custom bars at runtime, surfacing them through a "LegacyResolver" banner in Settings. That path could promote non-spell garbage (slot indexes, cooldownIDs from older drag handlers) into your per-spec storage, where it then rendered as fallback icons. The migration now clears those entries instead of promoting them — your real per-spec spell data continues to load normally.
- **Settings panel prompt replaced.** When a spec-specific custom bar has no entries, you'll see "Drag spells from your spellbook into the editor below to populate it." with **Dismiss** and **Delete bar** buttons, replacing the old recovery banner.
- **`/qui legacyrecover` remains** as an opt-in slash command for anyone who wants the old salvage walk.

### Fixed
- **QUI1 import round-trip.** Importing a QUI1 export string preserves spec-specific bar entries via the bundled-globals carrier; covered by a new round-trip test fixture so this won't silently regress.



## v3.6.0-alpha1 - 2026-04-30

> ⚠️ **Alpha release — please read before installing**
>
> This is the first alpha for QUI v3.6. Two big systems changed under the hood, and it's possible some of your settings won't survive perfectly:
>
> - **Back up your `WTF` folder before installing.** The simplest path: close WoW, copy your entire `World of Warcraft/_retail_/WTF/` folder somewhere safe. If anything goes sideways you can restore it. At minimum, hold on to `WTF/Account/<your-account>/SavedVariables/QUI_DB.lua` and the per-character `QUIDB.lua` files.
> - **Custom trackers may lose fidelity.** The Cooldown Manager's custom-tracker engine was overhauled — container shape (icon vs. bar) and entry kind (aura vs. cooldown) are now tracked separately, and legacy trackers are auto-migrated on first load. Migrations preserve as much as possible, but some custom-tracker settings can shift or reset. Before upgrading, **export your profile** via Options → Profiles → Export so you can compare or re-import if something looks off.
> - This is alpha software. Expect bugs. Please report issues on the GitHub/Discord.

### Added
- **Options panel V2.** Substantial rewrite of the settings panel: in-page section navigation with a sticky chip strip and scroll-spy on long sub-pages (e.g. Gameplay → Combat), search/pin routing into nested features, restored several settings that had gone missing during V2 migration, and tile-layout perf work.
- **Layout Mode search.** New search box in the Layout Mode frames drawer, with a clear button.
- **Help tile rework.** Sticky chip strip for navigation plus a new Tools sub-tab.
- **Group frames.**
  - New classification filters: Raid In Combat, Not Cancelable, Big Defensive, External Defensive.
  - Limit raid groups by difficulty (1–4 in Mythic, 1–6 in flex).
  - Animated aura health-bar tints; dispellable private auras now show dispel overlays.
- **Character pane.** Mirrors Blizzard's stats pane during combat so values stay visible (M+, raid combat).
- **Action bars.**
  - Totem bar settings panel with grow-direction control.
  - GSE sequence override support on QUI action bars.
- **M+ dungeon.** Mob progress display.
- **Consumables.** Per-character override toggle for macro selections.
- **Diagnostics.**
  - `/qui diagnose` — repairs corrupt Edit Mode profiles.
  - `/qui cdm_cache` — CDM spell cache status + out-of-combat reset.
  - `/qui combatprof` — `PLAYER_REGEN_ENABLED` stutter diagnosis.

### Changed
- **Cooldown Manager — custom bars & trackers.** Significant work toward feature parity between custom CDM bars and custom trackers. Container shape (icon/bar) and entry kind (aura/cooldown) are now tracked independently; legacy trackers and custom bars are migrated automatically on first load.
- **Pet frame.** Reparented out of the managed container instead of flagged in-place to prevent combat taint blocks.

### Fixed
- **Combat taint hardening (CDM, action bars, frames, tooltip).** Many edge cases addressed: cooldown swipe restart/flicker, mirror Clear/timing forwarding, hideGCD classification for charged abilities, restricted-aura unpack, flyout taint, autohide bars while flyout open, micromenu pulse suppression, proc swirl restoration, tooltip refit/dedup, boss frame buffs.
- **Cooldown Manager.**
  - Stack text preserved through transient API nils for charged abilities.
  - Target debuff stack updates restored in combat.
  - Buff-viewer spells now show stacks on custom cooldown containers.
  - Passive trinkets correctly hidden under "Hide Non-Usable".
  - Custom cooldown bars re-layout on mid-combat filter flips.
  - Frames anchored to dynamic-size containers track parent growth.
  - Charge stack lookup decoupled from Blizzard CDM category.
- **Buff borders.** Duration text honors anchor/offset on the custom timer; countdown rounds to nearest unit; guards against forbidden children.
- **Group frames.** Zero absorb overlays clear correctly; `|PLAYER` aura ownership filter applied to unit frames for player/pet/vehicle.
- **Click-cast.** Scoped per character via `db.char`.
- **Character pane.** Item context and sibling overlays preserved on slot skin; Settings button widened to fit across UI scales.
- **Minimap.** Dungeon eye no longer drifts (queue status button mutators hooked); mail icon background dropped and filled to button bounds.
- **Consumables.** Remaining-time uses ceiling rounding.
- Various tooltip, skin, mirror, click-cast, and lifecycle hardening.






## v3.5.6 - 2026-05-01

### Fixed
- fix(profile-io): cover orphaned settings dropped by selective export
- harden rogue flash border suppression
- fix(qol): suppress runaway PerksProgram trading post alert callout
- fix(profile-io, trackers): bundle spec-tracker globals on export and validate drag-resolved spell IDs
- refactor(character): forward secret stat values via SetFormattedText
- fix(cdm): honor growDirection on migrated customBar containers
- feat(character): mirror Blizzard stats pane FontStrings during combat
- fix(character): preserve ItemContextOverlay and sibling overlays on slot skin
- fix(buffborders): honor duration text anchor/offset on custom timer
- fix(cdm): restore target debuff stack updates in combat
- fix(minimap): drop background and fill mail icon to button bounds
- fix(buffborders): round countdown to nearest unit instead of floor
- fix(cdm): hide passive trinkets under hideNonUsable filter
- fix(consumablecheck): ceiling-round remaining time
- fix(consumablecheck): show hours+minutes in remaining time
## v3.5.5 - 2026-04-29

### Fixed
- fix(buffborders): guard SlotHasVisibleAura against forbidden children
- fix(minimap): hook QueueStatusButton mutators to stop dungeon eye drift
- fix(actionbars, cdm): port flyout taint + restricted-aura unpack from d7d5a36
- fix(cdm): defer buff-bar SetSize in combat to break inherited taint
- fix(frames, qol): restore proc-swirl + micromenu pulse suppression
- fix(cdm): port taint-resilient aura resolution from 16bcfcc
- feat(groupframes): expand classification filters with RaidInCombat, NotCancelable, BigDefensive, ExternalDefensive
- fix(cdm): collapse custom cooldown bars around filtered icons + mid-combat flips
- fix(frames): reparent PetFrame off managed container instead of flagging
## v3.5.4 - 2026-04-28

### Fixed
- fix(frames): use ignoreInLayout for PetFrame skip in LayoutChildren
- fix(frames): evict PetFrame from managed list to stop combat taint blocks
- fix(cdm): show stacks for buff-viewer spells on custom cooldown containers
- fix(tooltip): guard IsOwnerFadedOut against forbidden frames
- fix(actionbars): keep autohide bars visible while spell flyout is open
- fix(frames): restore boss frame buffs
- CDM tooltip/tint, Shaman OH imbue, aura-snapshot fix
- fix(cdm, anchoring): track parent growth for frames anchored to dynamic-size containers
- fix(cdm): decouple charge stack lookup from Blizzard CDM category
## v3.5.3 - 2026-04-27

### Added
- added animations to aura indicator health bar tints on group frames
- now showing dispellable private auras with dispel overlays on group frames
- added option to limit group visibility in raids (1-4 in myth, 1-6 in flex raids)

### Fixed
- fixed region-owned tooltips
- fixed CDM row opacity not being honored on update
- restored CDM buff stack updates
- raised color picker frame strata above options panel
- show actual mail tooltip information instead of a placeholder line
- fixed m+ character sheet taints, keeping (some) stats visible in protected instances
- fix(groupframes): clear zero absorb overlays
- fix(frames): avoid PetFrame edit mode taint
- fix(cooldowns): defer CDM layout in combat
- fix(cdm, tooltip): cross-class entry detection + tooltip chrome refit
- fix(tooltip, skin): dedupe stacked lines and harden refit measurement
- fix(taint, mirror, tooltip): combat-edge hardening and chrome refit
- fix(clickcast): scope per character via db.char
## v3.5.2 - 2026-04-26

### Added
- restored unit frames portrait settings
- added boss frame (out of) range alpha settings
- added group frames separate buff and debuff duration text settings

### Fixed
- fix(cdm, frames, layoutmode): taint & combat-edge regressions across mirror, stacks, action bars, layout proxy
- fix(frames/groupframes): suppress stale player summon icon without active popup
- fix(cdm/owned): thread safe-window flag through spell-data bootstrap
- fix(ui/buffborders): create secure aura headers in ADDON_LOADED safe window
- fix(frames/actionbars): cooldown swipes on owned flyout buttons + skin gate
- fix(core/assets): derive asset paths from actual addon folder name
- perf(cdm, frames): TTL query caches and per-unit event filtering
- fix(qol/tooltip): don't fade-hide tooltips owned by another tooltip frame
- perf(tooltips, frames): reduce update churn
- perf(tooltip): coalesce restyles, trim QoL hot paths, add tooltipdebug sampler
- perf(qol/tooltip): cut closure/timer churn and bound mount caches
- feat(debug/editmode_diagnose): /qui diagnose for corrupt Edit Mode profiles
- fix(character): widen Settings button so label fits across UI scales
- perf(cdm, frames): cut closure/string/timer churn in hot paths
- fix(cdm, frames): aura ownership filter for player/pet/vehicle
- fix(frames/buffbar, cdm/containers): render initial layout during ADDON_LOADED safe window on combat /reload
- feat(frames/gse_compat): GSE sequence override support on QUI action bars
- fix(frames/cdm): private-aura churn, header attribute order, spell-map leak
## v3.5.1 - 2026-04-24

### Added
- added configurable Great Vault shortcut icon to the minimap

### Fixed
- stabilized resource bar swap mechanic across reload, anchors, and toggles
- fixed CDM startup hover state and tooltip visibility
- fixed tooltip hide delay handling
- fix: harden combat death frame updates
- fix: avoid taint from Blizzard frame anchoring
- fix: improve character stats panel refresh and secret value handling
- made hidden CDM containers click through
- perf(groupframes): avoid caching negative defensive aura matches
## v3.5.0 - 2026-04-23

### Added
- feat(layoutmode): register Bonus Roll as movable Display element
- feat(frames): private auras on player/target/focus + 12.0.5 isContainer fix

### Changed
- updated Nokterian Healing Profile preset
- perf: move group frame aura handling to shared cache

### Fixed
- fixed whisper sound causing taints in raids/m+, making ppl unable to read whispers
- fix: retry buff border refresh after reload
- fix(cdm): forward secret item/slot cooldowns to C-side SetCooldown
- fix(cdm): render resource-wait and recharge swipes via durObj mirror
- fix(cdm): sharper GCD/real-cooldown classification and aura ownership
- fix(cdm): ignore target auras not cast by player
- fix(cdm): enable cooldown swipe by default
- fix(cdm): allow owned tracker rebuilds in combat
- fix(buffborders): ensure secure aura headers render after login/reload
- fix(actionbars): render pet bar when summoning pet in combat
- fix: owned CDM aura ownership, flyout rework, defaults backfill
- Fix stale owned proc glow detection
- Fix owned CDM proc glow tracking
- Fix owned CDM aura slot handling and buff icon rebuilds
## v3.4.3 - 2026-04-21

### Fixed
- fix(chat): defer to Blizzard history on Midnight
- Fix loot frame combat height taint
- fix: avoid minimap middle-click pass-through taint
- fix(actionbars): avoid combat taint when flyout owner remaps
- fix(actionbars): stop forcing Blizzard multibar cvars
- fix(actionbars): hide managed Blizzard bars via safe helper
- feat(actionbars): add secure owned spell flyout for retail
- fix(cdm): harden proc glow detection via Blizzard child state
- refactor(actionbars): unify owned standard bar setup
- refactor: centralize cooldown timing helpers
## v3.4.2 - 2026-04-20

### Added
- feat(qol): auto-close settings panel and layout mode on combat entry
- feat(qol): add 'Block All Microbutton Glows' toggle to popup blocker

### Fixed
- fix(cdm): symmetric icon↔bar viewer fallback; suppress mirror on inactive
- fix(raidbuffs): guard per-icon geometry behind InCombatLockdown
- fix(uihider): use state driver for WorldMap blackout to avoid pin taint
- fix(qol): NEW_COSMETIC_ADDED event doesn't exist; pcall each RegisterEvent
- feat(qol): UIParent fallback for HelpTip sweep + /qui helptipscan debug
- feat(qol): suppress HelpTip callouts on micro buttons via structural sweep
- fix(qol): apply blockMicroButtonGlows to MainMenuMicroButton_ShowAlert hook
- fix(cdm): guard ResolveDisplaySpellID at glow candidate boundary
- fix(cdm): guard secret spellIDs at glow candidate boundary
## v3.4.1 - 2026-04-19

### Added
- added option to show crafted item quality markers on action bars and custom trackers
- added option to only show player-cast aura indicators in group frames

### Changed
- removed group frames party tracker features ahead of 12.0.5 release, as they will break
- skyriding: hide bar while FarmHud is visible

### Fixed
- fixed group frame tracking icon and rotation assist icon layering over fullscreen UI
- fixed several procs not triggering glows in CDM viewers
- fixed cdm custom entries not obeying tooltip visibility settings and row opacity settings
- fix(cdm): evict tick aura caches on encounter/M+/PvP start
- fix(groupframes): event dispatch + raid-only spotlight
- fix(inspect): resolve empty tooltips, flashing overlays, and skinning races
- loot: skip repositioning in combat to avoid taint
- cdm: extract child metadata helpers to spelldata, dedupe in bars
- rotationassist: remove dead spellToKeybind cache
- memaudit: register ~38 probes across previously-invisible caches
- castbar: pool channel tick observation structs
- skyriding: defer frame creation until canGlide context
- perf: reduce allocations across party tracker, private auras, and castbar
## Unreleased

### Removed
- removed party tracker (CC icons, kick timer, party cooldown display)










## v3.4.0 - 2026-04-17

### Added
- anchoring: add Leave Vehicle button to layout mode and frame resolvers

### Changed
- raidbuffs: only display missing buffs in default group view

### Fixed
- fixed aura cancellation in combat
- restored resource bar swap positioning
- fixed groupframes backdrop colors changing in darkmode
- cdm: show keybinds for items added via Composer
- cdm: mirror Blizzard child texture for cycling buffs, memoize resolver lookups
- cdm: add per-tick duration cache, persist texture cache across ticks
- cdm: clean up stale hook state and debug logging after reparent refactor
- cdm: replace stack text hooks with native frame reparenting
- cdm: show "0" stacks for charged abilities when all charges depleted
- cdm: forward all hook SetText calls without filtering
- cdm: clear stack text when hook receives empty value
- cdm: prefer hook-driven stack text over API path for aura icons
- cdm: fix bar icon mirroring, aura tooltip resolution, add bar debug
- cdm: fix aura refresh detection, texture updates, and override stability
- actionbars/cdm/buffborders: UNIT_AURA count updates, parent-check hook detection
- buffborders/cdm: fix right-click cancel via secure attributes, simplify hooks
- buffborders: use INDEX sort to preserve Blizzard aura ordering
- buffborders: fix right-click cancel and stack display on secure aura children
- cdm/actionbars: fix aura icon resolution, simplify assisted combat glow
- cdm/actionbars: guard bar container sizing in combat, fix pet/stance keybinds
- cdm/buffborders: visibility-based hook tracking, banish revert, debug tooling
- cdm/buffborders: fix stack clear on hide, harden Blizzard frame suppression
- cdm/groupframes: add buff pandemic glow, new glow types, GC optimizations
- keybinds/rotation/glows: custom container support, override resolution
- perf: memory audit tooling, GC pressure reduction, party tracker raid guard
- qol/tooltip: fix taint from FlashBorder hooks, HelpTip API, and tooltip deferral
- uihider: replace CompactRaidFrameManager hooks with hidden-parent reparent
- fix taint and interaction issues, add HelpTip suppression
- Revert "cdm: add override cache and handle COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED"
- cdm: guard SyncClickButtonFrameLevel with InCombatLockdown check
- groupframes: create spotlight header at runtime, not just in edit mode
- minimap: prevent collected buttons from being dragged via StartMoving
## v3.3.3 - 2026-04-14

### Fixed
- actionbars: update icons on MODIFIER_STATE_CHANGED for macro conditionals
- castbar: simplify timer-driven time text to use DurationObject directly
- resourcebars: guard geometry calls with InCombatLockdown, suppress talent FlashBorder
## v3.3.2 - 2026-04-14

### Changed
- updated premade Nokterian Healing Profile

### Fixed
- actionbars: remove pcall from C-side assisted combat APIs, inline callbacks
- buffborders: guard FullRefresh against nil containers
- buffborders/layout: fix preview sizing, nil guards, remove bottom padding
- cdm: add passive aura source tab, block debuff texture bleed on cooldown icons
- cdm: add override cache and handle COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED
- cdm/glows: hoist GetSettings above IsPandemicMirroringEnabled
- groupframes/auras: remove pcall overhead from C-side aura APIs
- debug cleanup, rotation helper overlay fixes, and CDM improvements
## v3.3.1 - 2026-04-13

### Added
- added option for pandemic effect glow

### Fixed
- fixed Nokterian's name! <3
- groupframes: hybrid aura updates — skip full scan for stack/duration changes
- groupframes: stop re-registering UNIT_AURA on hidden Blizzard frames
- buffborders: simplify private aura slot parenting and layout math
## v3.3.0 - 2026-04-12

### Added
- added Noktarian healing preset
- added swipe hide options to group frames

### Fixed
- fixed live spec profile swaps
- fixed cdm profile/spec switching
- skip temporary whisper frame styling
- buffborders: remove EnableMouse calls on secure aura headers
- buffborders: fix tooltip fallback, use data.applications for stacks, drop SetDescendantMouse
- buffborders: properly hide/show secure headers based on enable settings
- buffborders: migrate to SecureAuraHeaderTemplate for zero-taint aura display
- groupframes/auras: remove incremental updates, always full-scan
- actionbars: respect alwaysShowInCombat during mouseover fade setup
- actionbars: reanchor micro button alerts near screen edges
- actionbars: PreClick drag suppression for useOnKeyDown, zero-alloc assisted combat
- minimap: stable anchor proxy for external HUD addon compatibility
- anchoring: resolve minimap to QUI_MinimapAnchor proxy
- anchoring: allow buff/debuff frame updates during combat
- qol: suppress all micro button alerts when microbar is hidden
- remove unnecessary InCombatLockdown guards from non-protected operations
- perf: aura event fast paths, group frame OnLoad decoration, taint hardening
## v3.2.3 - 2026-04-12

### Fixed
- avoid premature m+ log stops (should stop the "abandoned" m+ logs)
- consumablecheck: skip enhancement slot when player lacks required spells
- consumablecheck: trim legacy expansion data, always configure buttons 
- groupframes: re-check combat state per decoration batch tick
- defaults: disable auto combat logging by default
- actionbars: cast-on-key-press toggle, assisted combat rotation dedupe 
- buffborders: fix icon flow direction vars, support screen parent anchors
- buffborders: simplify aura icons to DurationObject-only cooldown path
- buffborders: remove global names from aura icon and cooldown frames
## v3.2.2 - 2026-04-11

### Added
- hud: add "Show When Mounted" condition across all visibility systems
- presets: replace Quazii profiles with Oak Tank/DPS and Healer
- actionbars: add popup direction support for spell flyouts

### Changed
- allow arrow keys in offset inputs in layout mode
- align welcome help text with QUI v3
- remove legacy Quazii import strings

### Fixed
- prevent stale CDM spec icons after character swaps
- preserve mouseover-hidden action bars during visibility refreshes
- ensure action bar flyout button directions after zoning/loading in/changed spells
- properly preserve anchor metadata and offsets when nudging in layout mode
- hud: fix visibility precedence — show conditions override hide rules
- totems: remove secure button/click-dismiss (DestroyTotem is protected)
- buffborders: scaled secondary anchor for private aura duration text
- cdm: skip ChargeCount.Hide hook for charged entries (FWD authority)
- actionbars: respect buttonlock on receive-drag, force scan after drag
- hud: route action bar fading through SetBarAlpha for MOD-blend support
- cdm: shared ResolveDisplaySpellID/ResolveDisplayName helpers
- buffborders: use SecureActionButton for weapon enchant cancellation
- actionbars: unify usability tinting, remove desaturate toggle buffborders: add borders and text styling for private aura slots minimap: add enable/disable toggle to layout mode
- actionbars: fix usability tint on empty slots and zone transitions
- gse: full icon/tooltip/watermark management for QUI buttons
- gse: add right-click sequence picker for QUI action bar buttons
- groupframes: delta-aware aura icon refresh for stack/duration updates
- party tracker: deduplicate shared helpers, player spell cache, disable filter
- cdm/actionbars: remove redundant post-combat refresh passes
- lib: fix LibOpenRaid UNIT_PET taint error with pcall wrapper
## v3.2.1 - 2026-04-10

### Added
- now hiding selective import/export selection tables in collapsible sections by default to reduce UI clutter
- layoutmode: add CDM Spells, Party Composer, Raid Composer buttons to toolbar
- layoutmode/settings: add QUI Settings button to edit mode toolbar, fix panel z-order
- aura_events: add "roster" filter for player + party/raid subscribers

### Changed
- uihider: stop auto-hiding CompactRaidFrameManager when QUI group frames are enabled

### Fixed
- restored spellbook lazy-load refresh for action bars, they should now show automatically again on spellbook open
- hardened mythic+ auto combat logging detection
- cdm/bars: skip redundant SetTimerDuration when C-side fill is active
- anchoring: fall back to configured width for castbars with no anchor parent
- cdm: fix spellbook scan skipping non-spec tabs
- actionbars/anchoring: coalesce AssistedCombat events, deregister managed-container reparents
- groupframes: scan-time defensive classification (mirror of dispel set)
- groupframes: scan-time dispel classification + set-change short-circuit + raidbuffs UNIT_FLAGS drop
- perf/taint: drop non-group units in private aura sub, early-out atonement non-Disc, skip forbidden tooltips
- actionbars: empower support, cast-on-up timing, pet bar drag, one-time hook install
- actionbars: drive charge swipes even when primary cooldown is idle
- layoutmode: solo toggle off, skip layer buttons on master rows, sync show/hide-all state
- skinning/inspect: inherit parent strata for custom background
- groupframes: avoid redundant SetBackdrop calls to stay under script budget
- groupframes: stop suppressing CompactRaidFrameManager from blizzard hider
## v3.2.0 - 2026-04-09

### Added
- added private dispel overlay support
- added GSE action bar compatibility shim

### Profile Migration Improvements
- Late migration: import action bar positions from Blizzard Edit Mode
- Migration overhaul > linear schema, chained-parent fixes, shadow defaults
- Migration: stop reading dead `ownedPosition` field as a position source
- Remove _cdmFaCleanupVersion migration and add CDM mover size fallback
- Anchoring overhaul > defaults.lua single source of truth, sentinel parent fixes, all-profile migration
- Frame scale-aware anchoring, M+ timer overlay, flyout direction, minimap zoom level
- Linear schema versioning, migration backup/restore, /qui migration command

### Fixed
- fixed whisper chat history taint
- fixed chat secret string handling
- fixed party tracker secret boolean checks
- fix castbar border sizing, keep it inside the configured castbar footprint
- stabilized totem bar anchor by sizing container to full bar extent
- guard UnitIsUnit boolean result against secret values
- Managed-container reparent, override bar restore, perf + taint fixes
- gate on party scope + avoid UnitIsUnit taint
## Unreleased

### Changed
- **Group Frames are now disabled by default.** Users who had them explicitly enabled will keep them. Users who never toggled the setting will see group frames disabled on first login — re-enable in *Group Frames → Enable* if you want them back.
- **Action Bars 7 and 8 are now disabled by default.** Same rule: explicit user toggles are preserved; users who never touched these bars will find them disabled. Re-enable in *Action Bars → Bar 7/8 → Enable* if you were using them.
- **"Keep In Place When Hidden" is now enabled by default** for every frame that supports the option. When a frame's anchor parent is hidden (e.g. pet bar when no pet, target castbar when no target, etc.), the child frame now stays anchored to its parent's last-known position instead of walking up the chain to find a visible ancestor. Users who had this explicitly disabled keep their setting.
- Migration: removed the redundant `SeedDefaultFrameAnchoring` pass. `defaults.lua` is now the single source of truth for frame anchoring defaults; AceDB serves them natively via the metatable, preventing drift and SV bloat from the parallel seed table.
- Migration: `Migrations.Run` and Tier 0 `StampOldDefaults` now iterate every stored profile instead of only the active one, so upgrading no longer leaves alt profiles frozen in their pre-migration state.
- Anchoring: `ApplyFrameAnchor`'s `hideWithParent` and `keepInPlace` branches now no longer fire when `settings.parent` is `"screen"` or `"disabled"`. For those sentinel parents there's no real frame whose visibility can be tracked and no frame to SetPoint against other than UIParent (which is always visible), so the branches fell through to `SetPoint(point, UIParent, relative, offsetX, offsetY)` — teleporting the frame to UIParent at the configured offsets. When the ghost FA entry had 0/0 offsets (from a freshly materialized default), that meant teleport to screen center. The old code had a similar bug on the `hideWithParent` side: `ResolveFrameForKey("screen")` returned nil, `directVisible` collapsed to false, and the frame got `Hide()`'d entirely. Both paths now fall through to the normal chain-walk, which correctly resolves sentinel parents to UIParent via `ResolveParentFrame`. `hideWithParent` and `keepInPlace` still work exactly as before for any frame whose parent is a real frame.
- Anchoring options: `GetFrameDB` no longer creates entries on read, and the lazy proxy skips `__newindex` writes whose value matches the default. Prevents widget OnChange handlers (dropdowns re-selecting the same value, sliders firing on focus, etc.) from materializing ghost `frameAnchoring` entries.
- Anchoring chain walker: `ResolveParentFrame` takes an optional `originKey` that prevents self-cycle resolution via hardcoded fallbacks (fixes druid tank `primaryPower → secondaryPower → fallback → primaryPower` loop). When the walker detects a cycle (revisiting a key it already tried, or the origin frame), it now consults `FRAME_ANCHOR_FALLBACKS` one more time to continue the walk via a fallback target instead of immediately giving up and returning UIParent.
- Anchoring: added `primaryPower → cdmEssential` to `FRAME_ANCHOR_FALLBACKS`. Classes without a secondary power bar (DK, druid, DH, warrior, rogue, monk) previously had legacy 3.0 profiles with `primaryPower.parent = "secondaryPower"`, which collapsed to a self-anchor loop or (after the cycle guard) dumped the frame offscreen at UIParent BOTTOM. The new fallback chain is `secondaryPower → primaryPower → cdmEssential`, so the power bar and anything chained off it land below the CDM Essential viewer — matching where the current default chain would put them.

### Fixed
- CDM container layout mode mover handles now size correctly even when the container is disabled, empty, or pre-layout. The `CDM_ELEMENTS` layout mode registration provides a `getSize` callback that falls back to `ncdm._lastEssentialWidth/Height` or `ncdm._lastUtilityWidth/Height` when the live container frame is still at its default `1x1` size.
- CDM container `frameAnchoring` entries (`cdmEssential`, `cdmUtility`, `buffIcon`, `buffBar`) are no longer nilled on upgrade. The `_cdmFaCleanupVersion` migration that removed them was designed around bugs that are now fixed at the source (lazy `GetFrameDB` proxy + hardened `__newindex` + `hideWithParent`/`keepInPlace` sentinel gate). Removing the cleanup restores the cooperation pattern: the CDM module yields positioning to the anchoring system when an FA entry exists (via `QUI_HasFrameAnchor` checks), and the settings panel's anchor/position/keepInPlace toggles actually modify something. 3.0 users keep their legitimate CDM container anchor configurations.
- 2.5.5 upgrade: `MigrateAnchoring` v2/v3 helpers now explicitly set `parent = "screen"` on legacy position backfills so `copyDefaults` can't later fill in a chain-rooted parent and misinterpret the offsets. Fixes brezCounter, lootRollAnchor, consumables, zoneAbility, and similar legacy positions landing in wrong places after upgrade.
- `MigrateAnchoring` v1/v2/v3 no longer unconditionally create an empty `profile.frameAnchoring = {}` that would shadow AceDB defaults for fresh profiles. Lazy `EnsureFa`/`ReadFa` helpers only materialize the table when there's actual legacy data to write.







## v3.1.4 - 2026-04-07

### Added
- added lots of legacy profile migration pain mitigations
- added premade profiles (Quazii, Quazii Dark Mode, Coco (Drew)) - this will be extended in the future
- added /qui cdm command to quickly open the QUI Spellmanager
- added chat frame resizing options (size sliders and resizing grip)
## v3.1.3 - 2026-04-05

### Fixed
- Anchoring: don't resolve Blizzard bar frames when action bars are disabled
## v3.1.2 - 2026-04-05

### Added
- added selective profile export

### Fixed
- fixed custom CDM entries menu sync
- restored cdm keybind override options
- fixed self-first group frame gap
- fixed resource bar reload error
- Anchoring: block bulk reapply during layout mode; reset offsets on anchor change
- Buff borders: skip anchor conversion during layout mode; sync handle size
- Fix defaults migration SV pollution, dormant spell recovery, layout mode ordering
- Fix tooltip taint from OnHide hook; CDM layout mode visibility; guard displayName types
- Fix layout mode frame positioning conflicts and dormant spell false positives
## v3.1.1 - 2026-04-05

### Changed
- improved defaults rollover handling from old profiles
## v3.1.0 - 2026-04-05

### Added
- added nudge +/- buttons to sliders
- Raid buffs: toggle aura detection, hide active provider buffs
- DandersFrames: layout mode integration with absolute positioning support
- CDM: add per-spell desaturateIgnoreAura override

### Changed
- Layout mode: right-click to select, middle-click to unanchor, sticky toolbar
- Layout mode: visual toolbar overhaul, group frame enable toggle guard
- Buff borders: simplify right-click cancel to use CancelAuraByAuraInstanceID
- DandersFrames: prompt reload on enable/disable toggle change
- Overhaul defaults for better OOTB experience; fix spec profile sync and spell detection
- stop background search indexing work after closing options panel

### Fixed
- fixed DandersFrames movement regressions
- improved sync between options panels in layout mode and options menu
- Minimap: fix dungeon eye SetPoint error on initial load
- CDM: fix item/trinket/slot ID space separation; buff borders: prefer numeric cooldown path
- stopped minimap provider refresh loops
- Click-cast: resolve base spells for override transform searchability
## v3.0.0 - 2026-04-04

### Added
- Introduced a major new layout mode system with composer UI, anchor providers, layout settings, and broader support for repositioning HUD and frame elements.
- Added Party Tracker support, an Atonement counter, consumable macros, and brought back custom tracker bars.
- Expanded raid-buff and consumable tracking with self-buff coverage, weapon enhancements, visual status states, and better group-relevant buff detection.

### Changed
- Reworked the Cooldown Manager by removing the old classic engine and expanding the owned engine/composer with better swipes, charges, desaturation, proc highlighting, and row/layout control.
- Overhauled group and unit frame customization with pinned/private auras, drag-and-drop aura indicators, new indicator types, improved click-cast handling, and separate self-first behavior for party vs raid.
- Improved action bars, buff/debuff frames, cast bars, resource bars, totem bars, and minimap behavior with more layout options, better visuals, and persistent settings like minimap zoom.
- Expanded Blizzard skinning coverage for major UI surfaces including tooltips, alerts, ready checks, Auction House, Crafting Orders, Professions, and the game menu.

### Fixed
- Hardened the addon against combat taint and secret-value issues across cooldowns, group frames, tooltips, minimap interactions, click-cast, and other secure UI paths.
- Reduced CPU overhead in several hot paths, especially for cooldown processing, action bars, aura handling, and hidden-element updates.
- Improved profile switching, migrations, defaults, import behavior, and refresh ordering to make setup changes safer and more reliable.
## v2.55.3 - 2026-03-30

### Fixed
- fix dungeon portals mapping
- fix minimap zoom not being persistent
- fix dungeon eye drift
## v2.55.2 - 2026-03-27

### Added
- added support for charged combo points (credits: jopierce)
- made m+ timer background configurable

### Fixed
- fixed HousingPhotoSharingFrame tooltip issue
## v2.55.1 - 2026-03-26

### Fixed
- fixed durations of tracked buffs not showing
- more tooltip taint hardening
## v2.55.0 - 2026-03-25

### Fixed
- backported api-change related fixes to QUI mainline
- fixed custom trackers not showing in M+ and raids
- fixed swipes and cooldowns not showing on CDM viewers
## v2.54.1 - 2026-03-24

### Fixed
- fixed datatext placeholders showing when 'no label' is selected
- fixed moneyframe tooltip taint
## v2.54.0 - 2026-03-23

### Added
- added blizzard frame mover feature
- added general status bar skinning (i.e. reputation bars)
- added totembars for all classes that can use them (i.e. brewmasters)

### Fixed
- attempt to fix golden circles appearing around hidden action bars
- attempt to fix worldquest hovering tooltip taint
## v2.53.4 - 2026-03-23

### Added
- added itemIDs in tooltips
- added PvP iLvl display when hovering iLvl on character sheet
## v2.53.3 - 2026-03-21

### Fixed
- fixed rangecheck issues on group frames
- fixed current expansion flasks and oils not showing in consumables checker
## v2.53.2 - 2026-03-19

### Changed
- cache GetPixelSize() in hot loops in buff bars, resource bars and group frames
## v2.53.1 - 2026-03-19

### Added
- added option for spec-specific custom CDM entries
- added "always show me first" option for raid frames

### Fixed
- fixed dungeon difficulty icon anchoring
- fixed raid frames randomly resizing
- fixed raid frame sorting
- fixed several tooltip taint vectors
## v2.53.0 - 2026-03-18

### Added
- added partial profile imports
- added avoidance and stagger to character stats plus some skinning improvements

### Fixed
- fix tooltip combat visibility for custom trackers and CDM viewers
- hopefully fixed tooltips breaking when BtWQuests taints values
- fixed raid tooltip taint
- fixed totem bar taint issue
## v2.52.1 - 2026-03-15

### Added
- added guild rank to tooltip

### Fixed
- fixed targetName comparison taint
## v2.52.0 - 2026-03-15

### Added
- added customizable colors to CDM buff bars
- added mount, target, m+ rating to tooltip information options

### Fixed
- fix group frames defensives would show random buffs when players are out of range
- fix contained tooltips showing their own backdrops and borders
- fix castbar border frame strata
## v2.51.1 - 2026-03-14

### Added
- added option to track Power Infusion on group frames

### Fixed
- fixed skyriding bar rendering
- fixed stance bar skinning issue
- fixed tooltip inspect functions running in unsafe environment
## v2.51.0 - 2026-03-14

### Added
- added configurable breakpoint indicators to resource bars
- added balance druid and frost dk to secondary resource bar swap group
- added options to omit % signs on health text and power text on unit frames
- added x- and y-offset for loot window relative to mouse cursor

### Fixed
- fixed paging arrow showing even when turned off
## v2.50.2 - 2026-03-14

### Added
- added anchoring support for AbilityTimeline / Better Timeline addon

### Fixed
- fixed tooltips disappearing when OPie is enabled
- fixed tooltips not showing spellIDs and iconIDs anymore
- fixed mouseover tooltips on the minimap
- fixed defensives growth direction 'center' not working as intended
## v2.50.1 - 2026-03-14

### Fixed
- fixed own frame being rendered twice with "solo mode" enabled and in a group
- fixed 'show me first' to take precedence over other sorting options
- fixed party frame anchoring when 'show me first' is enabled
## v2.50.0 - 2026-03-13

### Added
- added row growth direction options for horizontal and vertical layouts
- added spec and item level information of players in tooltips
- added CENTER growth direction for all group frame icon layouts
- added scroll wheel click-casting

### Fixed
- fixed tooltip cursor anchoring and border rendering
- fixed gap between castbar border and castbar progress bar
- fixed SetBorderColor issue on profiles page
- fix: defer SafeReload on profile scale change to next frame
- fix: profile switch refresh order and anchoring force bypass
- refactor: remove unnecessary combat-deferred initialization from modules
- fix: combat guards for minimap dragging and edit mode watcher
- fix: minimap middle-click overlay to prevent ping taint, auto-hide toggle refresh
- refactor: strip NineSlice approach for tooltips, comprehensive profile refresh, click-cast fixes
- fix: correct minimap HUD parent check, ensure backdrop visibility
- fix: zero-write tooltip skinning, fix minimap ticker cancel
- fix: strengthen external HUD detection with GetRect fallback and hooks
- refactor: overlay-based tooltip skinning
- fix: improve external HUD detection with size and parent checks
- fix: make click-cast settings live-toggleable without reload
- refactor: migrate all modules from PLAYER_LOGIN to ADDON_LOADED
## v2.49.4 - 2026-03-12

### Added
- added global ping keybinds, self-first header, show solo option
- added ping action types to click-casting system

### Fixed
- fixed crafting order icon always showing
- fix: initialize CDM at ADDON_LOADED for combat reload support
- fix: remove unused CreateBorder helper and tooltip sticking monitor
- fix: eliminate GameTooltip taint from HookScript and hooksecurefunc
## v2.49.3 - 2026-03-12

### Added
- added indicator sizing options for group frames
- added click-casting for target and target-of-target
- added crafting order indicicator to minimap

### Changed
- removed QUI tooltip engine, now back to Blizzard hooks for tooltips

### Fixed
- fix not being able to close consumable check window in combat
- fix action bar paging not working in combat
- fix: propagate secret booleans from UnitInRange, click-through tooltips
- fix: combat-safe tooltip skinning and cursor anchor taint prevention
- fix: refactor click-cast drop zone for reliable spell/macro drag handling
- fix: harden click-casting binding list against invalid data types
- fix: combat-safe cursor tooltips, macro drag-and-drop for click-casting
## v2.49.2 - 2026-03-12

### Added
- made growth direction configurable again on QUI CDM engine, and make it actually honor it

### Fixed
- fixed action bars with flyout buttons fade out when hovering their flown out buttons
- fixed target castbar not showing
- fixed tooltip sizing issues with new tooltip engine
- fix: remove unused SafeHideFrameOffscreen, use SafeHideFrame for party frames
- fix: remove SetAlpha hook to avoid infinite recursion
- fix: guard tooltip fingerprint and hash comparisons against secret values
- feat: discover and handle child tooltips from external addons
- fix: taint-safe guild datatext APIs, tooltip content-hash for late updates
## v2.49.1 - 2026-03-11

### Added
- added indicator sizing controls, improved edit mode fidelity for group frames, added a blacklist filter
- extended click-casting support to unit frames and fixed tooltip height estimation

### Changed
- replaced mixin-level tooltip overrides with a frame-level external registration approach

### Fixed
- fixed secret value handling for UnitInRange booleans and made tooltips click-through
## v2.49.0 - 2026-03-11

### Added
- added dual-engine tooltip system
- added system datatext memory stats
- added unit menu action type to click-cast bindings
- split up group frames settings into separate party and raid profiles

### Changed
- refactor: simplify AH expansion filter to single OnShow hook

### Fixed
- fixed totembar not showing in combat
- fixed unsafe Frame:Hide() on custom trackers
- fix: remove taint-causing method replacement on Blizzard cooldown viewers
- fix: defer custom tracker refresh to combat end when in lockdown
- fix: rework shopping tooltip lifecycle to prevent flash and dedup
- fix: obfuscate global mixin references in tooltip redirects
- fix: size designer inner scroll from parent frame instead of outer viewport
- fix: use actual unit class colors and improve designer scroll sizing
- fix: guard GetAlpha with SafeToNumber for combat taint safety
- fix: derive tooltip anchor from SetOwner when no SetPoint fires
- fix: cache Blizzard tooltip anchor before offscreen override
## v2.48.2 - 2026-03-10

### Changed
- did a major performance pass to reduce unneccesary CPU and memory usage
- entering the search menu should be pretty much instant now

### Fixed
- fixed unitframe class color resolution regression
- fixed blizzard party frames not hiding when wanted
## v2.48.1 - 2026-03-09

### Fixed
- clean up group frames side menu
## v2.48.0 - 2026-03-09

### Added
- added group frame composer
- added option to show GCD of instant spell as a castbar
- added option to make minimap button drawer open on mouseover
- added chat sound alerts with LibSharedMedia support
- added auction house expansion filter

### Changed
- made custom datatext panels lockable

### Fixed
- don't render swipes and glows no hidden actionbar buttons
- fix stancebar and petbar icons not rendering correctly on first load
## v2.47.3 - 2026-03-08

### Changed
- improve pixel perfect implementation to ensure proper borders

### Fixed
- fix: eliminate taint from tooltip hooks, game menu watcher, and group frame posthooks
- fix: remove Blizzard function replacements that permanently taint secure code
- fix: replace OnUpdate watcher with event hooks for CompactRaidFrameManager hide
- fix: skip UIWidget frames in font recursion, clear stale action bar icons on reload
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

