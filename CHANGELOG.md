# Changelog

All notable changes to QUI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## v5.2.0-beta2 - 2026-08-14

> ⚠️ **WoW 12.1 ONLY.** This build targets patch 12.1 (interface 120100) and
> will not load on the 12.0.x client.

Two features: nameplate profiles you can name and share, and an objective
tracker that matches the rest of your UI.

### Added

- **Named nameplate profiles with import/export.** Nameplate setups are now
  account-wide named profiles instead of numbered per-spec presets: create
  them, rename them, delete them, assign them per specialization, and share
  them as import/export strings. Existing spec presets are migrated into
  named profiles automatically.
- **Objective tracker progress bars and icons.** The Skinning page can now
  replace tracker progress bars with flat skinned bars in a color of your
  choice, and recolor the bullet points next to objectives in progress and
  the checkmarks next to completed ones.

## v5.2.0-beta1 - 2026-08-14

> ⚠️ **WoW 12.1 ONLY.** This build targets patch 12.1 (interface 120100) and
> will not load on the 12.0.x client.

An action-bar taint pass plus small fixes: re-showing a bar in combat no
longer throws blocked-action or cooldown errors, bag icon overlays sit on the
button again, opened mail is readable with the dark skin, and the new 12.1
consumables are in the macro dropdowns.

### Added

- **New 12.1 consumables in the macro dropdowns.** Liquid Luster, Alluring
  Nostrum, Concentrated Silvermoon Health Potion, the fleeting Silvermoon
  variants, and Vantus Rune: Tides are now available in the consumable macro
  definitions and dropdowns.

### Fixed

- **Re-showing an action bar in combat no longer throws errors.** Leaving a
  vehicle or override bar mid-combat could trigger blocked SetAttribute and
  rejected cooldown errors; QUI's buttons no longer run Blizzard's tainted
  show handler and are kept out of Blizzard's event dispatch entirely.
- **Bag item icon overlays line up again.** The overlay texture was pinned at
  a fixed size in the button center, so resized bag buttons drew it
  misplaced. It now anchors to the button itself.
- **Opened mail is readable with the dark skin.** Hiding the parchment left
  the dark-ink letter body, subject, sender, and invoice text nearly
  invisible; each text type is now recolored explicitly.
- **The Help page's community links work again.** The Discord, GitHub, and
  CurseForge links point at the current QUI homes.

## v5.1.0-beta6 - 2026-08-13

> ⚠️ **WoW 12.1 ONLY.** This build targets patch 12.1 (interface 120100) and
> will not load on the 12.0.x client.

A polish pass on icons: cooldown manager borders draw crisp at every scale,
duration and stack text is styled again, and the buff and debuff border
controls are back — now per strip.

### Added

- **Per-strip border controls for buff and debuff icons.** Each aura strip can
  now show or hide its icon borders and set its own border thickness, on top
  of the global setting.

### Fixed

- **Cooldown manager borders are crisp again.** Icon rectangles are snapped to
  physical pixels before borders are drawn, so a border no longer lands
  between pixels and comes out blurry or a pixel thicker on one side at odd
  UI scales.
- **Duration and stack text on cooldown icons follows its settings again.**
  Icons the cooldown manager rebuilds mid-combat skipped the text pass, so
  countdown and stack numbers could sit in the wrong corner with the wrong
  font. They are re-anchored and restyled now. Options dropdowns also open
  scrolled to the top instead of wherever the last menu left off.
- **Buff and debuff icon borders obey the border settings again.** The global
  border toggle and thickness had stopped being applied to aura icons.

## v5.1.0-beta5 - 2026-08-13

> ⚠️ **WoW 12.1 ONLY.** This build targets patch 12.1 (interface 120100) and
> will not load on the 12.0.x client.

One fix for players carrying settings over from older versions: custom text
colors no longer error out the resource bars.

### Fixed

- **Custom resource bar text colors from old profiles work again.** Older
  profiles saved the custom text color in a different table shape than the
  current options panel writes. Reading it the new way produced a nil color
  and threw "bad argument" on every secondary power bar update, spamming
  errors whenever the bar refreshed. Both shapes are now accepted, with a
  white fallback if the saved color is missing or malformed.

## v5.1.0-beta4 - 2026-08-13

> ⚠️ **WoW 12.1 ONLY.** This build targets patch 12.1 (interface 120100) and
> will not load on the 12.0.x client.

Two fixes that keep QUI out of Blizzard's own code: the vehicle bar can hide
itself again, and cooldown swipes stop flickering.

### Fixed

- **Leaving a vehicle no longer jams the override bar.** Blizzard's slide-out
  code read a field QUI had tainted, so the final hide was blocked — the bar
  could stick on screen with an "Interface action failed" error. QUI's action
  buttons now stay out of the event table Blizzard reads, the micro menu is
  moved back directly instead of through Blizzard's repositioning call, and a
  bar that still gets stuck hides itself as soon as it legally can.
- **Cooldown swipes stop flickering.** Two writers alternated on the swipe
  draw flag: Blizzard rewrote it on every cooldown event and QUI forced it
  back moments later. The flag belongs to Blizzard again, and recharging
  charge spells return to their native edge-only look.

## v5.1.0-beta3 - 2026-08-12

> ⚠️ **WoW 12.1 ONLY.** This build targets patch 12.1 (interface 120100) and
> will not load on the 12.0.x client.

A short follow-up to beta2: resource bars that keep working in combat, two
action bar fixes that keep QUI out of Blizzard's own code, and one new option
for aura duration text.

### Added

- **Hide Time Unit** for aura duration text, per text region. Shows `4` instead
  of `4s`; durations over 90 seconds keep their m/h/d unit.

### Fixed

- **Resource bars keep drawing in combat.** On 12.1 the client can hand back a
  protected power value, and the bar took a separate path whenever it did —
  dropping its text placement, tick marks and indicator lines for as long as the
  value stayed protected. It now renders the same way either way: the value goes
  straight to the bar and to the text, and indicator lines are positioned by the
  game instead of by arithmetic QUI is no longer allowed to do. Soul fragments
  show their real count rather than falling back to zero, and both power bars
  reuse their frame instead of stacking a second one over the first.
- **Action bar cooldowns stay off Blizzard's own fields.** The loss-of-control
  swirl was stored on a field Blizzard's code reads, so that code inherited QUI's
  taint; it lives on a private field now. A button that carries its own
  assisted-combat rotation frame builds that frame itself instead of receiving a
  second one.
- **The original QUI logo is back.**

## v5.1.0-beta2 - 2026-08-12

> ⚠️ **WoW 12.1 ONLY.** This build targets patch 12.1 (interface 120100) and
> will not load on the 12.0.x client.

The first build with real work on the 5.1 line: aura displays you place
yourself, a hidden-players filter for group frames, and a run of fixes for
settings that looked like they were doing nothing.

### Added

- **Aura displays you place yourself.** Build a display, point it at a unit,
  filter it per unit, give it load conditions and drag it where you want it.
  Displays can be renamed, and a reaction can be parked out of the way.
- **A hidden-players filter for group frames**, to keep specific players off the
  raid frames.
- **Plate Scale for nameplates** (Nameplates → Behavior). One slider grows the
  whole plate — bar, text, icons and borders together — and the clickable area
  grows with it, so plates stay clickable at their edges. It multiplies on top
  of Target Scale and the simplified-plate scale rather than replacing either.
- **Item cosmetic overlays in bags**, on live and cached bag buttons alike.

### Fixed

- **Cast on Key Press now does something.** Owned action buttons dispatched
  through a path that forced casting on key release, so the setting wrote a
  value nothing ever read. Abilities fire on the press when it is on.
- **Skins survive being loaded early.** When another addon force-loaded a
  Blizzard frame before QUI had a profile, the skin's one-shot fired against a
  profile that did not exist yet and never came back — profession windows and
  their siblings stayed unskinned for the rest of the session.
- **QUI no longer runs other addons' code while sweeping for action buttons.**
  The sweep classified frames by calling a method on every global, which threw
  inside a widget library's generated methods and surfaced as that addon's
  error with QUI's frames underneath it.
- **Duplicate abilities in the cooldown composer.** A spell the client replaces
  with an override was tracked under whichever ID happened to be stored, so it
  could be offered as available while already owned, or appear twice in a built
  list.
- **Group frame headers stop churning.** Re-configuring a header rewrote every
  secure attribute even when nothing had changed, forcing a re-layout each time.
- **Orphaned movers are released** instead of lingering in Layout Mode.
- **The nameplate settings preview opens at real size.** It used to open zoomed
  all the way in; the grip now zooms both ways from life size.

### Changed

- **The Alts window is translated.** It had been hard-coded English throughout,
  and the `Back` label it shared with a cloak slot and a UI layer is split so
  each reads correctly in every language.
- **Terminology is consistent across all ten locales** — frame and spec wording
  unified, realm and roster wording unified, five mistranslations corrected and
  the hidden-players strings translated everywhere.
- **Discord announcements come only from tagged releases.** The workflow that
  posted a second notification on every feature-branch push is gone.
- The vendored Blizzard API corpus is refreshed to 12.1.0.69273.

## v5.1.0-beta1 - 2026-08-11

> ⚠️ **WoW 12.1 ONLY.** This build targets patch 12.1 (interface 120100) and
> will not load on the 12.0.x client.

Opens the 5.1 beta line. No addon code changes: this ships the 5.0.0 tree and
moves the version on, so the next round of work has a beta channel to land in.

### Changed

- Documentation only. The README pointed at an archived repository whose
  documentation site had been switched off, and its migration guide had been
  collapsed by an old rename into instructions that told you to copy a file over
  itself. The docs site still advertised support for 12.0, which this build does
  not load on, and still described a build from June.
- The addon list now credits **Zol** alongside **Drew** as the author.

## v5.0.0 - 2026-08-11

> ⚠️ **WoW 12.1 ONLY.** This build targets patch 12.1 (interface 120100) and
> will not load on the 12.0.x client.

The 5.0.0 line, released. Nameplates become their own addon, nameplates and
group frames and unit frames move onto one shared aura engine, the suite drops
from 22 addon folders to 11, and QUI adapts to 12.1's stricter rules about what
an addon is allowed to read. Everything below landed across alpha1 to beta4; the
per-build entries under this one carry the full detail.

### Added

- **Nameplates are their own addon**, with a setup wizard and a settings preview
  that renders a real plate 1:1 and follows whatever you are editing.
- **Every plate type gets its own config** — pets and minions, friendly units,
  bosses and elites, minor and trivial units, enemy players and enemy NPCs —
  picked from a dropdown with a Copy From control.
- **Target indicators** (arrow, brackets and glow line), class power pips on the
  target plate, execute-threshold health colouring and threat colour mapping.
- **A nameplate Visibility tab** with an enemy-plate master toggle, friendly NPCs
  exposed, and Minions nesting Guardians, Pets and Totems on both sides.
  `Show In Instances` is a never / name-only / always choice.
- **Pandemic glow on aura icons**, driven by the game's own pandemic region
  rather than a timer QUI approximates, so it stays in step with the real
  duration.
- **Dispel borders and stealable buffs come from the game.** An aura element can
  be set to `Debuffs + Stealable Buffs` or `All Auras`.

### Changed

- **One aura engine drives nameplates, group frames and unit frames**, so an
  element configured on one behaves the same on the others.
- **Name-only is a real render mode** — QUI draws the name and hides the bar and
  aura containers instead of restyling Blizzard's own text.
- **The suite is 11 addon folders instead of 22.** Locales ship packed, so only
  the language in use is ever compiled, and login memory drops by roughly 2.3 MB.
- **Settings search is 2.5–3x faster.** One English index ships instead of ten
  translated copies, and typing the English term still finds the translated row
  on non-English clients.
- **The options panel opens instantly**, building on the first frame after login,
  and moving between settings tabs reuses the page it already built.
- **Every non-English locale is actually translated now.** Nine of the ten had
  been falling back to English for roughly 900 strings each.
- **Atonement tracking no longer reads the combat log.** 12.1 closed combat log
  events to addons, so the counter watches auras directly.

### Removed

- **The Brez counter's resurrection list.** Naming who battle-rezzed whom needed
  combat log events, which 12.1 does not give addons. The charge count, the
  recharge timer and the per-pull tally are unaffected.

### Upgrading

4.x to 5.0 is an install over the top: the same addon folders and the same saved
variables (`QUIDB` and `QUI_StorageDB`), so nothing moves by hand. Profiles
migrate to the current schema on first login and are backed up beforehand —
`/qui migration status` and `/qui migration restore` expose those backups.

If you hand-installed 5.0.0-alpha29 or earlier, the eleven `QUI_OptionsSearch`
folders are left behind after updating. Nothing loads them; delete them.

## v5.0.0-beta4 - 2026-08-11

> ⚠️ **WoW 12.1 ONLY.** This build targets patch 12.1 (interface 120100) and
> will not load on the 12.0.x client.

### Fixed

- **Missing raid buff icons were unreliable.** The indicator could keep showing
  a buff as missing after it had been cast, miss the change entirely when the
  game reported an aura update it could not fully read, or flag a buff as
  missing because the ally carrying it had moved out of range. Range, specialization
  and aura-change handling were all reworked so the icon follows the real state.
- **Missing raid buff names and icons could stay wrong for the session.** When
  the indicator was built before the game had finished loading spell data, the
  English placeholder name and the question-mark icon were cached permanently,
  so on a non-English client the buff kept the wrong label. Both now refresh
  until the real values are available.

## v5.0.0-beta3 - 2026-08-11

> ⚠️ **WoW 12.1 ONLY.** This build targets patch 12.1 (interface 120100) and
> will not load on the 12.0.x client.

### Fixed

- **Friendly NPC nameplates could not be turned on.** Auto-Hide shipped with
  friendly player and NPC nameplates hidden, and that setting quietly outranked
  the one on the nameplate page, so ticking Friendly NPCs there changed nothing
  and the game's own Nameplates options showed the option off. Both pages now
  read and write the same setting, so either one turns it on and it stays on.
- **Settings rows escaped the options window.** Toggling a nameplate visibility
  option left cards and checkboxes drawing loose over the game world while the
  panel below them went blank, until the page was reopened.

### Changed

- **Auto-Hide's two nameplate rows now read "Friendly Nameplates" and "Friendly
  NPCs".** They are the same two settings as the nameplate page's Visibility
  tab rather than separate ones that fought it, so ticking a box now means show,
  not hide, and both pages stay in step.

## v5.0.0-beta2 - 2026-08-10

> ⚠️ **WoW 12.1 ONLY.** This build targets patch 12.1 (interface 120100) and
> will not load on the 12.0.x client.

### Added

- **Pandemic glow on aura icons.** An icon flashes once its aura enters the
  refresh window. The glow is driven by the game's own pandemic region rather
  than a timer QUI approximates, so it stays in step with the real duration.
- **Dispel borders and stealable buffs come from the game.** Border colour and
  artwork per dispel type are handed to Blizzard's aura button instead of being
  redrawn on top of it, and an aura element can now be set to
  `Debuffs + Stealable Buffs` or `All Auras`.

### Changed

- **Moving between settings tabs is instant.** Each tab body is built once per
  variant and kept, so switching unit, plate type or context reuses the page it
  already built instead of rebuilding it.
- **Nameplate settings open on Enemy NPCs**, which is the plate type most people
  are there to edit.
- **QUI no longer adds an entry to the game's Settings > AddOns list.** It held
  one button that opened the QUI panel, which `/qui` already does.
- **A suite-wide consistency pass** landed under this release: shared helpers
  replace hand-rolled duplicates for time formatting, accent-insensitive search
  and secret-value guards, and a long tail of settings keys nothing ever read
  are gone. No behaviour changes with it; it is groundwork for 12.1's stricter
  rules about what an addon may touch.

### Fixed

- **Edit Mode could get stuck asking to reload.** When the game refused to save
  a cooldown manager layout, QUI asked for a reload, and the same refusal met it
  on the way back up. The pending save is now recorded and the loop breaks on
  the next login.
- **Atonement tracking no longer reads the combat log.** 12.1 closed combat log
  events to addons, so the counter watches auras directly and caches what it has
  already resolved per unit.

### Removed

- **The Brez counter's resurrection list.** Naming who battle-rezzed whom needed
  combat log events, which 12.1 does not give addons. The charge count, the
  recharge timer and the per-pull tally are unaffected.

## v5.0.0-beta1 - 2026-08-07

> ⚠️ **WoW 12.1 ONLY.** This build targets patch 12.1 (interface 120100) and
> will not load on the 12.0.x client.

First beta of the 5.0.0 line. Everything below has landed since v5.0.0-alpha29.

### Added

- **Nameplates are their own addon**, with a sidebar tile, a setup wizard, and a
  settings preview that renders a real plate 1:1 and follows whatever you are
  editing. A control strip toggles ten plate states plus reaction, so you can see
  each one without going and finding the unit.
- **Every plate type gets its own config** instead of one config for all plates —
  pets and minions, friendly units, bosses and elites, minor and trivial units,
  enemy players and enemy NPCs, picked from a dropdown with a Copy From control.
  A plate re-resolves its type live on classification, flag and faction changes.
- **Target indicators** — arrow, brackets and glow line — plus class power pips on
  the target plate, execute-threshold health colouring and threat colour mapping.
- **A nameplate Visibility tab**: an enemy-plate master toggle, friendly NPCs
  exposed, and Minions nesting Guardians, Pets and Totems on both sides.
  `Show In Instances` becomes a never / name-only / always choice.

### Changed

- **Nameplate auras use the same engine as group frames and unit frames.** One
  shared aura surface renders all three, so an element configured on one behaves
  the same on the others. Duration text and mine-only are per channel, and
  `Nameplate Only` is a per-element field rather than a filter flag.
- **Nameplate settings split from five tabs to eight** — General, Visibility,
  Frame, Text, Indicators, Auras, Castbar, Colors. Absorbs, heal prediction and
  Fading And Scale moved to Frame; Render Mode moved to Visibility.
- **Name-only is a real render mode** — QUI draws the name and hides the bar and
  aura containers instead of restyling Blizzard's own text.
- **Settings search is 2.5–3x faster.** One English index ships instead of ten
  translated copies, labels are localized as the index is applied, and scoring
  only visits entries that can actually match what you typed. Typing the English
  term still finds the translated row on non-English clients.
- **The suite is 11 addon folders instead of 22.** The eleven `QUI_OptionsSearch`
  folders are gone — the index moved into `QUI_Options` and the translations into
  `QUI`. Locale files ship packed, so only the language in use is ever compiled,
  and login memory drops by roughly 2.3 MB.
- **The options panel opens instantly.** It builds on the first frame after login
  rather than the first time you open it.
- **Dispel Colors** moved into Auras > Group Frames.
- **Chat button bar**: built-in and custom buttons collapse into one ordered list,
  so custom buttons can sit ahead of built-ins. Existing profiles fold at runtime
  — nothing to do.
- **Every non-English locale is actually translated now.** Nine of the ten had
  been falling back to English for roughly 900 strings each. English plural
  suffixes are gone from six strings no other language could express, the `KB`
  keybind column header is translated everywhere (ruRU had been rendering it as a
  kilobyte unit), and koKR uses one word for "cooldown" across all 25 keys that
  used it instead of two.

### Fixed

- **Friendly pet, guardian, totem and minion plates never appeared.** All four
  toggles shipped off and were re-asserted on every settings change, overriding
  the game's own Nameplates options. They ship on now, and existing profiles pick
  the change up once.
- **Macro creation errored on every attempt on 12.1.** The macro limit constants
  moved on Blizzard's side and were still being read as bare globals. The
  focus-marker index scan also started from the wrong base.
- **A fresh install could end up with a permanently empty cooldown catalog.**
  Seeding ran through a file that lives inside the load-on-demand options addon,
  so the per-character catalog stayed empty until `/qui` was opened once.
- **Totem cooldowns show their remaining duration again**, and their icons update
  when the totem is placed or drops. A totem summoned under a linked or override
  spell ID never matched an active slot, and nothing re-scanned the slots.
- **A cooldown manager icon could report a cooldown it never drew.** A recycled
  icon kept its old duration binding after the widget itself had been cleared, so
  the swipe was never re-applied.
- **The unit-frame options preview mangled CJK names.** It truncated on raw bytes
  while the live frame walks codepoints, so on koKR, zhCN and zhTW any Max Name
  Length not divisible by three cut a character in half.
- **Raid frames rendered party dispel colors.**
- **The chat button bar jumped about a second after login.**
- esES: Windrunner is Brisaveloz. zhTW: Mythic difficulty is 傳奇, not the
  client's word for Epic item quality.

### Upgrading

If you installed v5.0.0-alpha29 by hand rather than through an addon manager, the
eleven `QUI_OptionsSearch` folders are left behind after updating. Nothing loads
them, but you can delete them from `Interface/AddOns` to tidy the list.

## v5.0.0-alpha29 - 2026-07-25

> ⚠️ **WoW 12.1 PTR ONLY.** QUI targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client.

First release under the QUI name. Same codebase as QUI 5.0.0-alpha28,
continued independently — see the credits in the README.

### Changed

- The addon is now **QUI**. Every addon folder, TOC, global, and saved
  variable moved from the `QUI` namespace to `QUI`; settings now live in
  `QUIDB` rather than `QUIDB`.
- Slash commands moved to the `dui` family: `/qui` is now `/qui` (with a
  `/qui` alias), and `/quibags`, `/quialts`, `/quidp`, `/quilog`, and the rest
  are now `/quibags`, `/quialts`, `/quidp`, `/quilog`, and so on. The legacy
  `/quaziiui` alias was removed.
- Profile schema 60 renames the `quiUnitFrames`, `quiGroupFrames`, and
  `quiDatatexts` key namespaces to their `drew*` spellings, and rewrites the
  `__QUI_GLOBAL__` font sentinel. Existing profiles migrate automatically.
- Profile strings are exported with a `QUI1:` prefix. QUI's `QUI1:` strings
  are still imported natively.

### Added

- One-time, non-destructive adoption of an existing `QUIDB` on first login, so
  a QUI install's settings carry over. QUI's saved variables are never
  modified. This requires QUI to still be installed and enabled; otherwise use
  a profile export string.



## v5.0.0-alpha28 - 2026-07-25

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Fixed
- Auras placed in a cooldown container you built yourself stayed invisible when
  the container was set to show only active icons. The active check was asking
  whether the ability was on cooldown, which an aura never is, so buffs like
  Anti-Magic Shell never appeared even while running. Custom containers now
  judge auras by whether the aura is actually on you, matching how the built-in
  containers already behaved. Cooldown entries in the same container are
  unaffected.

## v5.0.0-alpha27 - 2026-07-25

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Fixed
- The duplicate-placement aura mirrors added in alpha26 kept a small internal
  bookkeeping list that grew every time a placement retired and came back —
  toggling a container off and on, swapping specs, or an entry dropping out for
  a refresh. Nothing visible went wrong and no frames were retained, but memory
  crept up over a long session. Retired records are now released exactly, so
  the list stays bounded.

## v5.0.0-alpha26 - 2026-07-25

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Added
- Placing the same ability in more than one cooldown container now shows it in
  every container you put it in. Blizzard hands out a single frame per ability,
  so one placement keeps that native icon and the others are drawn from QUI's
  own timing sources — exact duration for cooldowns, and a managed aura slot
  for aura-kind entries so stacks and remaining time stay real. Duplicated
  items, equipment, consumables, and totem instances still show exactly one
  icon: they have no exact public timing source, so they fail closed with a
  diagnostic instead of drawing a mirror that could drift.
- Group frames can show the Blizzard dispel type icon — Magic, Curse, Disease,
  Poison, or Bleed — with its own size, opacity, anchor, and offset, separate
  from the colored dispel border. A new **Show For** choice adds *All Typed
  Debuffs* next to *Dispellable by Me*, so awareness-only types such as Bleed
  and Enrage can surface without widening Cleanse-Ready Glow, which stays
  strictly on what you can actually dispel.
- Hovering an item in your bags now clears its new-item glow immediately
  instead of waiting for a click.

### Fixed
- The Cooldown Composer, Action Bars, and Resource Bars settings previews now
  measure what they actually drew and resize their pane to fit, so tall icon
  stacks and long value text are no longer clipped or stranded in empty space.
  All three headers now read *Live Preview*, matching the rest of the settings.
- The totem bar read the player class token without collapsing a restricted
  value first, so slot ordering could fall through to the wrong priorities; it
  now falls back to the standard order when the token is not readable. Active
  totem buttons also sit above the invisible placeholders they pack over, so a
  right-click to dismiss always hits the totem you aimed at.

## v5.0.0-alpha25 - 2026-07-25

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Fixed
- Dark Mode looked inert in the group frame preview whenever Use Class Color
  was also enabled: the preview painted the class color over the dark fill,
  while the live frames do it the other way round. The preview now follows the
  live rule — Dark Mode wins while it is on, with its configured color and
  alpha honored — so the two surfaces finally agree.

## v5.0.0-alpha24 - 2026-07-25

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Added
- The group frame settings preview now shows what the live frames show. It is
  built from the same frame skeleton the runtime uses, so it picks up cleanse
  glow, Party Target Frames, Spotlight role and name filters with their growth
  direction, party show-player / hide-DPS / sort / self-first, and a dedicated
  Targeted Spells chip instead of that unexplained centre cooldown.
- Aura previews are drawn with the real icon styler: icon skins, dispel
  borders, cooldown swipes, duration text, and stack counts all appear in the
  preview, so settings that only existed on the live path can finally be judged
  before you commit to them.
- **Auras > Unit Frames** gets a pinned preview of the unit frame itself,
  outside the scrolling settings body.

### Changed
- The aura element editor opens quietly: Basics, Filters, and Appearance &
  Advanced start collapsed, and expanding a section reflows the rows in place
  rather than repainting the whole tab. "What to Show" latches manual mode when
  you pick Custom…, and the spell Browse window stays open for multi-select
  while the inline list updates live behind it.
- Both unit frame previews measure what is actually visible — body, portrait,
  auras, cast bar — recentre on it and shrink the pane to fit, instead of
  reserving space for a cast bar that is not there.
- Threat and target fill opacity are no longer inert settings; both now tint a
  real fill on live frames and in the preview.

### Fixed
- Buff/debuff settings in search results sent you to **Action Bars > Per-Bar**,
  a page that contains none of them. All 46 of those entries now land on
  **Auras > Buff/Debuff Frames**, where they moved.
- The Cooldown Manager composer listed spells your class can never learn — for
  example Shaman auras offered on a Demon Hunter — and they looked active while
  never appearing on the real frame. Those rows are hidden now. Same-class
  abilities missing from your current loadout keep their Dormant treatment, and
  spell IDs you entered by hand are still yours to manage.
- The Group Frames tile and the Auras hub's Group Frames sub-page each keep
  their own Party/Raid choice; opening one no longer silently retargets the
  other.
- An automatic Missing Raid Buff container previewed as empty on classes with
  no raid buff of their own (Death Knight), leaving nothing to position. The
  preview now shows a representative icon; live frames are unchanged.
- Resource bars honour the colour mode dropdown on every path, so a static
  colour no longer stays white on Blood Death Knight Runic Power.

## v5.0.0-alpha23 - 2026-07-24

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

> 🔄 **Profile schema migrated to v59.** Removes the tracked auras that earlier
> alphas seeded into the Healer HoTs element. Your profile is backed up
> automatically before it runs.

### Removed
- The 42-spell **Healer HoTs** default seed. Alpha22 shipped that element
  pre-filled with every healer specialization's healing-over-time spells; the
  element itself stays, but its tracked auras are now yours to choose. Spells
  you added by hand are kept — only the seeded ones are swept, on every group
  frame and raid bucket, including profiles you import.
- Specialization-based aura suggestions in the aura editor and wizard.
  Suggestions now come from the Blizzard cooldown-manager catalog only.

### Added
- Aura tooltip and dispel controls in the options panel, promised in alpha22:
  hide aura tooltips in combat, anchor them to each icon (or at the cursor),
  and override the per-dispel-type ring colors for a single element. Dispel
  types you leave alone keep the engine color.
- The docked options preview panel can be detached, dragged, collapsed, and
  scaled by its grip for the rest of the session.

### Changed
- Dispel-type borders and symbols moved onto the 12.1 dispel-texture API that
  replaced the names removed after 12.1, and custom dispel artwork now reaches
  tracked-aura element buttons alongside custom dispel colors.

### Fixed
- Cooldown-manager icons no longer trigger an action-blocked error when the
  cooldown manager re-anchors during combat. Clickable icons are held in their
  own pool and only reused while they are still safe to touch, so nothing is
  dropped or leaked while you are in a fight.
- Restored the cast bar detach that a 12.1 PTR guard had been suppressing.
- A taint-scan gate check no longer accepts a look-alike namespace-prefixed
  name in place of the real one.

## v5.0.0-alpha22 - 2026-07-23

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Added
- Aura tooltips can now be positioned per element (anchor point and offset)
  and hidden in combat through profile settings. Options-panel controls for
  these arrive in a later alpha.

### Changed
- Aura containers now lay out through the 12.1 native flow layout, giving
  real multi-column growth where the old layout degraded to a single column.
- Aura tooltips now carry QUI's backdrop and border styling instead of the
  default Blizzard chrome.
- Dispel-type aura borders use the new 12.1 dispel texture API, keeping
  Blizzard's per-type artwork intact under QUI sizing.
- Aura "index" sorting uses the client's new instance-ID ordering when
  available, keeping positions stable as auras refresh.

### Fixed
- Adopted the re-shipped 12.1 PTR build 68914 API surface.
- More spots no longer error when the client withholds combat data
  ("secret" values): the party leader icon, guild names in tooltips, and
  raid buff class lookups.
- A full-repo hardening sweep closed out the remaining strict taint-scan
  findings across 32 files.

## v5.0.0-alpha21 - 2026-07-23

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Removed
- The **Encounters** browser under the Auras tab, along with instance- and
  encounter-specific aura setups. 12.1 no longer exposes the encounter
  identity they keyed on. The boss and role-on-boss visibility conditions
  remain, and per-element boss strips you created keep working; instance- or
  encounter-specific setups saved by older profiles are ignored.

### Changed
- Modules now repaint only what an event actually changed instead of doing a
  full render per event: **Bags** re-dress changed slots in place when the
  layout provably didn't move, **Resource Bars** route power ticks through a
  value-only path, **Unit Frames** coalesce rapid power updates, the
  **Damage Meter** restyles bars only when appearance actually changed and
  follows the session's own clock for Current-session rates, the **Minimap**
  clock wakes once a minute instead of once a second, and the consumable
  check reuses a cached inventory snapshot on aura ticks.
- **Bags** skip their loading-screen compile entirely when the module is
  disabled in the profile.

### Fixed
- Adopted the 12.1 PTR build 68824 API changes: action button cooldown
  updates, flyout lookups (which now hard-error on unknown IDs), and cast
  bar suppression no longer error or risk taint.
- Moving or saving frame positions while the client withholds anchor data
  ("secret" values) no longer errors, and the extra action button position
  save skips unreadable coordinates instead of writing 0,0.
- Several spots that silently treated combat-hidden values as 0 now handle
  them properly: unknown unit reactions fall through to class colors instead
  of hostile red, and tooltips with unreadable alpha are treated as visible.
- Profiles version-stamped by earlier dev builds now re-run all repair
  migrations, healing states those builds may have left behind.

## v5.0.0-alpha20 - 2026-07-22

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

> 🔄 **Profile schema migrated to v58.** Seeds the new Healer HoTs element into
> existing profiles and extends the shipped defensives element to instance- and
> encounter-specific override setups. Your profile is backed up automatically
> before it runs.

### Added
- New **Healer HoTs** tracked aura element on group frames, pre-seeded with the
  healing-over-time spells of every healer specialization so HoT tracking works
  out of the box. Existing profiles receive it via migration; deleting it is
  respected and it will not re-seed.

### Changed
- Aura tracking adopted the latest 12.1 PTR aura API (build 68824): aura groups
  keep stable identities across updates, filtering uses the native filter
  string, and weapon enchant frames are enumerated through the engine rather
  than tracked ad hoc.
- Buff presence checks now treat combat-hidden ("secret") results as unknown
  instead of missing, so indicators no longer flicker off when the client
  withholds aura data mid-combat.

### Fixed
- Broad 12.1 secret-value hardening (rounds 18–23): class colors, tooltips, the
  character pane, on-screen error messages, and aura scans no longer error when
  the client hides unit or aura data during combat.
- The shipped defensives element now also applies inside instance- and
  encounter-specific override setups, where it previously vanished.
- Repairs profiles where an earlier dev build injected a lone Healer HoTs
  element into spec, instance, or encounter overrides that were deliberately
  left empty.

## v5.0.0-alpha19 - 2026-07-18

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Changed
- Extra action button and zone ability takeover reworked for 12.1's secure
  layout: QUI now owns the shared container for the whole session, so
  disabling the takeover asks for a `/reload` to hand the frames back to
  Blizzard instead of risking a protected-layout error mid-session.
- The zone ability mover now defaults to its own screen position instead of
  riding the extra action button's anchor.

### Fixed
- In-combat frame moves are now gated behind secret-safe protection probes,
  fixing errors the 12.1 client could throw when QUI checked whether a frame
  was movable during combat; blocked moves retry automatically after combat.
- Action bar cooldown reads no longer risk a secret-value error when the
  12.1 client hides cooldown data during combat.
- Cooldown viewer icons whose text or values are hidden by the 12.1 client
  now count as present and stay visible instead of disappearing.
- The mail window position is re-asserted when Blizzard's panel manager
  re-stamps it while open.
- Frame anchoring resolves retries per consumer, so one frame's pending
  retry can no longer suppress or hijack another's; anchor work blocked by
  combat is replayed reliably once combat ends.

## v5.0.0-alpha18 - 2026-07-14

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

> 🔄 **Profile schema migrated to v56.** Repairs boss-debuff strips that
> earlier alpha dev builds could duplicate or orphan in spec-override buckets,
> so the Encounters page toggle always addresses the strip that actually
> renders. Your profile is backed up automatically before it runs.

### Added
- New **Auras** configuration hub unifying aura setup across unit frames,
  group frames, and buff/debuff frames, with a guided **Setup Wizard** as its
  first page.
- **Encounters** page: a journal-sourced encounter catalog with per-encounter
  boss aura settings and spec-specific overrides (spec × encounter cascade).
- **Dispel Colors** page with role-based dispel and bleed seeding.

### Changed
- "Action Bar Auras" is now named **Buff/Debuff Frames**; cross-links updated.
- The Setup Wizard replaces a tracked HoT wherever it appears in multi-spell
  elements, and corner placement now spaces indicators by their real pixel
  footprint — stacked HoTs on the same corner no longer overlap.
- The legacy "dispellable by me" debuff filter checkbox is ported to the 12.1
  filter token that preserves its meaning.

### Fixed
- Boss-debuff strips duplicated or orphaned by earlier alpha builds are
  repaired by the v56 migration; the strip the Encounters page controls is
  the one that renders.
- A raid-cooldown library no longer scans aura data unguarded while the 12.1
  client restricts it.

## v5.0.0-alpha17 - 2026-07-11

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

> 🔄 **Profile schema migrated to v51.** A single squashed migration repairs
> aura filter data corrupted under alpha16, folds the group-frame defensive
> indicator into the unified aura elements, and purges orphaned cooldown-viewer
> settings. Your profile is backed up automatically before it runs.

### Changed
- The Unit Frames **Icons** tab is now named **Auras**, matching the unified
  aura element system it configures.
- The group-frame defensive indicator is now a standard **defensives** aura
  element, gaining the element system's filters, sorting, layout, and placement.
- Faster login and options window: the options engine (~2.9 MB) and the
  new-profile seed data now load on demand instead of at login, the first
  `/qui` open compiles the options UI, per-locale search indexes load when
  needed, and startup runs its profile migration in a single pass.

### Fixed
- Aura filters saved under alpha16 are repaired. An alpha16 seeding bug wrote
  invalid tokens into unit-frame aura filters, which hard-errored on 12.1 when
  the filter string was compiled; the migration strips the bad tokens (a filter
  left empty reverts to off).
- A batch of 12.1 crash fixes around secret (protected) values — cooldown-viewer
  cast/channel tracking, spell-cooldown map teleports, pet proc glows, consumable
  and skyriding aura tracking, the castbar empower probe, and loot-frame
  positioning no longer error when the game returns a protected value.

### Performance
- Reduced per-frame allocations across group frames, resource bars (shared
  resource maps and zero-allocation rune tracking), and unit-frame power updates
  (frequent-power events coalesced to ~5 Hz on non-player frames).
- Trimmed ~448 KB of unused bundled cooldown data and removed dead bag storage
  code.

### Internal
- Development history re-founded on the v4.1.0 fork base as a single linear
  trunk; the packaged addon is unchanged from the prior alpha dev build.
- Blizzard API reference (FrameXML + API docs) refreshed to 12.1.0.68629.

## v5.0.0-alpha16 - 2026-07-09

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

> 🔄 **Profile schema migrated to v50.** Aura settings on all three surfaces
> (action-bar buff borders, unit-frame auras, group-frame auras) are converted
> to the new unified element format. Your profile is backed up automatically
> before the migration runs.

### Added
- feat(auras): tracked aura elements — pin specific spells as icon, square, or
  duration-bar displays — return on group frames and are new on unit frames
  (they had been non-functional since the PTR4 aura rework).
- feat(auras): sort options for unit-frame and group-frame auras, and
  right-click-to-cancel for eligible player buffs (both previously action-bar
  buff borders only).

### Changed
- feat(auras): buff borders, unit-frame auras, and group-frame auras now share
  one element-based configuration model and one editor — add aura elements per
  frame, each with its own filters (classification / whitelist / blacklist),
  sorting, layout, and placement.

### Fixed
- fix(auras): group-frame aura elements honor their individual anchor and grow
  settings again (alpha15 collapsed all of a frame's aura strips onto the
  first element's layout).

## v5.0.0-alpha15 - 2026-07-08

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Fixed
- fix(auras): all aura surfaces (unit-frame buffs/debuffs, action-bar buff
  borders, group-frame auras) migrated to the new 12.1 PTR4 aura container
  API — the latest PTR build removed the old aura APIs, which broke every
  aura display in alpha14. Right-click-to-cancel and the sort options now go
  through the game engine directly.

### Changed
- style(auras): aura icons now crop the dark bevel edge baked into icon art,
  matching the rest of the suite's icon treatment.

### Removed
- the private-aura anchor feature on unit frames and group frames. The 12.1
  aura containers render private auras natively, so the dedicated anchors
  would show them twice. Any stored private-aura settings are cleaned up
  automatically (profile schema v49).

## v5.0.0-alpha14 - 2026-07-07

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Added

A large batch of new Quality-of-Life modules. **All are opt-in and default OFF.**

- feat(qol): Group Death Alert — on-screen text plus an optional sound when a
  party/raid member dies (feign-death filtered).
- feat(qol): Healer Mana Watcher — a movable frame with a mana bar for each
  healer in your group.
- feat(qol): Focus Marker — one action to focus and raid-mark your mouseover
  target via a character macro or clickable button.
- feat(qol): Map Teleports — M+ season dungeon teleport panel on the world map
  with click-to-cast buttons and cooldown swipes.
- feat(qol): Vendor Sell Rules — rule-based auto-sell for equippable gear by
  quality/ilvl with force/never lists; runs in preview-only mode until you
  turn previews off.
- feat(qol): Gem Socket Picker — a panel of socketable gems from your bags
  under the item socketing window.
- feat(qol): Mail Contacts — an address-book side panel on the send-mail tab
  (your alts + past recipients), plus a remember-last-recipient toggle.
- feat(qol): Trade & Mail Log — account-wide trade / sent-mail / received-mail
  history, browsable via `/quilog`.
- feat(qol): EJ Loot Specs — spec-eligibility icons on Encounter Journal loot
  rows.
- feat(qol): Communities Privacy — a click-to-reveal cover over community chat
  and rosters.
- feat(qol): Cursor Trail — fading afterimage dots with combat-only and
  class-color options.
- feat(qol): Sound Mute — mute individual game sounds from a built-in catalog.
- feat(qol): Collection Fanfare — auto-clears the "new" fanfare glow on
  freshly collected mounts/pets/toys.
- feat(qol): Merchant Pets — green check on already-collected pets at
  merchants.
- feat(qol): Loot Toast Filter — hide loot-won toasts below a chosen quality,
  with keep-overrides.
- feat(qol): auto-confirm popups for socket replacement, token purchase, and
  high-cost items.
- feat(qol): Audio Device Lock — re-asserts your chosen audio output device
  whenever the OS device list changes.
- feat(qol): Event Sounds — play a chosen sound on whisper / ready check /
  LFG proposal / resurrection offer / loot roll won / loot upgrade.
- feat(qol): Extended Ignore — a user-managed ignore list beyond Blizzard's
  cap; suppresses public chat from listed names and auto-declines their
  invites and duels.
- feat(qol): Friends List class colors — class-colored names for WoW and
  BNet friends playing WoW.
- feat(qol): No-Target Warning — an in-combat "No Target" banner with
  movable placement.
- feat(tooltips): new tooltip options — scale, hide faction/PvP lines,
  connected-realm mark, guild rank, and guild-name coloring.
- feat(character): gem summary on the character pane (per-color counts and
  empty sockets).
- feat(bags): currency bar, corner widgets, and item-button refinements.
- feat(datatexts): additional datatext providers.
- feat(actionbars): position options for the open-ticket icon.

### Fixed
- fix(actionbars): Blizzard's open-ticket (help request) icon now anchors to
  the reclaimed micro bar instead of floating loose.
- fix(core): profile changes made during a Mythic+ run are parked and applied
  when the run ends, instead of being dropped.
- fix(core): cross-suite namespace export collisions are now detected, so two
  sub-addons can no longer silently overwrite each other's shared symbols.
- fix(tooltips): guard GameTooltip widget containers from tainted layout.
- fix(sounds): whispers no longer double-ping when both QUI Chat's new-message
  sound and the QoL Event Sounds whisper alert are enabled — chat owns the
  whisper sound and the QoL module defers to it.
- fix(options): settings tiles with a single sub-page no longer render a lone
  redundant tab that repeated the header title.

### Changed
- perf: idle-cost sweep across the suite — tooltip visibility watcher
  throttled, CDM buff-icon poll made allocation-free with a relaxed cadence,
  CDM mouseover poll and fade fallback stop allocating bar-frame snapshots,
  the action-button global sweep runs once per session, the damage-meter
  ticker stops walking settings every render frame, the cursor-follow watcher
  parks until you move, options sliders debounce their onChange while
  dragging, and the info bar skips mouseover-fade alpha work while settled.


## v5.0.0-alpha13 - 2026-07-05

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Fixed
- fix(cdm): the cooldown viewer HUD now re-evaluates its visibility rules the
  instant you start or stop moving, so movement-dependent conditions (skyriding,
  flying, mounted) update promptly instead of lagging until the next event.


## v5.0.0-alpha12 - 2026-07-05

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Added
- feat(groupframes): party target frames — an optional companion frame for each
  party member showing the name and health of that member's current target.
  Party only, off by default.
- feat(groupframes): the absorb, heal-absorb, and heal-prediction overlays gain
  per-bar controls — bar texture, draw order, fill direction, and an optional
  leading-edge spark with outline.
- feat(groupframes): detached mini-bar mode for those same overlays — each can
  leave the health bar and render as a standalone mini-bar with its own width,
  height, anchor, and offset. Off by default (overlay stays the default).
- feat(groupframes): debuff icon borders can be colored by dispel type
  (Magic / Curse / Poison / Disease / Bleed). Off by default.
- feat(groupframes): linear (horizontal or vertical) cooldown swipe option for
  aura icons as an alternative to the default radial swipe; the countdown
  number is kept either way.
- feat(groupframes): party frames can expose their unit frames to an external
  cooldown-tracker provider (party frames only, no raid frames).
- feat(qol): merchant grid extender — widen the vendor Items tab into a grid
  (2–4 columns × 5–8 rows) so a multi-page vendor collapses onto one page. Off
  by default; a 2×5 grid matches the vanilla layout.
- feat(qol): a toggle to force Blizzard's floating/scrolling combat text off.
  Off by default.
- feat(damagemeter): a Dark/Light theme preset dropdown for the native meter's
  appearance colors.

### Fixed
- fix(inspect): inspecting a player no longer blanks the open inspect pane's
  item levels and gear tooltips a moment later. A queued tooltip inspect
  request is now suppressed once the Inspect window opens.
- fix(bags): right-clicking a bag item to deposit into a selected bank or
  warband tab now merges into an existing partial stack of the same item
  instead of always dropping the whole stack into the first empty slot.

## v5.0.0-alpha11 - 2026-07-04

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Fixed
- fix(cdm): Cooldown Manager proc highlights no longer flicker. While a spell
  showed its proc glow, every cooldown, aura, or charge event re-triggered the
  glow's start animation, so the highlight strobed under a burst of events. The
  glow is now painted once and left alone until the proc ends or the icon is
  reused for a different spell.

## v5.0.0-alpha10 - 2026-07-04

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Fixed
- fix(cdm): a disabled Cooldown Manager tracker no longer flashes its icons in
  the middle of the screen. With a tracker disabled (e.g. Utility) and its
  spells curated into another tracker, every cooldown update briefly pinned
  the disabled tracker's icons at its hidden container's position. Disabled
  trackers now claim no icons at all, and icons they held before being
  disabled are released on the next update.

## v5.0.0-alpha9 - 2026-07-04

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Fixed
- fix(cdm): Cooldown Manager icons no longer snap to Blizzard's mid-screen
  Edit Mode position at the start of combat. The viewer is now glued onto the
  QUI container, so Blizzard's own layout lands in the right place, and icons
  that appear mid-combat stay hidden until QUI has positioned them instead of
  flashing mid-screen.
- fix(auras): aura frames are no longer created during combat, which the 12.1
  client forbids and could crash. Buff borders, group frames, and unit frames
  now update existing icons while in combat and queue brand-new icons for the
  moment combat ends.
- fix(groupframes): party and raid members who join mid-fight now show their
  auras immediately — aura frames are pre-allocated out of combat instead of
  appearing only after the fight.

### Changed
- Buff border layout and settings changes now re-lay existing icons
  immediately, even in combat, instead of waiting for combat to end. The
  weapon-enchant icons now lead the buff grid.

## v5.0.0-alpha8 - 2026-07-03

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Added
- Pandemic glow now works on re-anchored Cooldown Manager icons. It follows
  Blizzard's own per-spell pandemic window, so the flash timing matches the
  actual refresh window for each aura.

### Changed
- Tracked buff bars now mirror their fill and timer text directly from
  Blizzard's live bars. Bars animate smoothly in combat even while aura data
  is secret, instead of freezing or going blank.

### Fixed
- fix(cdm): the aura cache no longer wipes itself mid-combat under the 12.1
  secret-aura rules, which could leave cooldown and buff displays empty until
  the next out-of-combat refresh.
- fix(cdm): combat Potion / Health Potion / Healthstone entries now show their
  proper icons and names in the composer and on rendered icons instead of a
  blank or question-mark icon.
- fix(actionbars): buffs that appear after your buff count grows past its
  previous maximum now show tooltips and accept right-click-to-cancel
  immediately, instead of blocking the mouse until a /reload.

## v5.0.0-alpha7 - 2026-07-03

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Changed
- **Cooldown Manager rebuilt on the re-anchor engine.** QUI now positions and
  skins Blizzard's own cooldown icons in place instead of mirroring them into
  cloned frames. This removes the whole class of "icons hidden in combat",
  ghost-icon, and cooldown-viewer taint failures the old mirror pipeline had.
- Tracked buff bars are now rendered as QUI-owned bars; Blizzard's bar viewer
  acts purely as a data source. Bar skin, ordering, and Edit Mode suppression
  all come from QUI.
- Aura scanning migrated to the 12.1 secret-aura rules (aura getters that were
  removed in 12.1 are replaced, secret combat payloads are skipped safely)
  across the Cooldown Manager, group frames, cast bars, the consumable check,
  and the atonement counter.
- Essential/Utility cooldown icons handle clicks and tooltips through
  QUI-owned hosts, so hover and click behave consistently on re-anchored icons.

### Fixed
- fix(cdm): cold login no longer leaves the Cooldown Manager tainted (aura
  reads going secret / icons refusing to register) until a /reload.
- fix(cdm): with "Show Buff/Debuff Phase on Cooldown Icons" disabled, icons —
  including trinkets and consumables — now show their real cooldown swipe and
  desaturation instead of reading bright "ready" while the cooldown rolls.
- fix(cdm): buff icons no longer get stuck invisible or stale after combat; a
  repair net re-claims them whenever Blizzard re-shows or re-uses a frame.
- fix(cdm): Edit Mode cooldown-viewer visibility settings that conflict with
  QUI's rendering get a one-time reset (with a reload prompt) instead of
  silently fighting the addon.
- fix(unitframes): buff/debuff containers on unit frames now anchor exactly
  where the layout-mode preview shows them on non-default anchor corners.

## v5.0.0-alpha6 - 2026-06-29

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Changed
- folded the **QUI_UI** add-on back into the main QUI add-on, so the suite now
  installs one fewer sibling folder. Skinning, datatexts, info bar, alts, minimap,
  and the QoL features all load from main. Info bar, alts, datatexts, and skinning
  now default **on** — if you had never toggled Info Bar or Alts off, they will
  appear after this update; turn them off under Module Add-ons.
- combat-end recovery now re-applies backdrops only to the frames that errored
  during combat instead of rescanning every frame, and the buff-border / aura
  headers no longer rebuild on a normal combat end.

### Fixed
- fix(chat): when reloading in combat, the Blizzard chat frames are now hidden
  immediately instead of lingering beside the QUI chat until combat ends.
- fix(cdm): the cooldown re-anchor engine no longer throws a protected-call error
  when resizing cooldown containers in combat; the resize is deferred to combat end.

## v5.0.0-alpha5 - 2026-06-29

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

> 🔄 **Profile schema migrated to v48.** Player buffs and debuffs are now two
> separate aura containers. Your profile is backed up automatically before the
> migration runs; profiles older than schema v47 are backed up, reset, and
> reseeded from the starter preset instead of step-migrated.

### Added
- player buffs and debuffs now render on two independent aura containers, each
  with its own mover target, so they can be positioned and styled separately.
- rebuilt the CDM cooldown engine to reposition Blizzard's own cooldown icons in
  place (SetPoint re-anchor) instead of cloning them — no reparenting of Blizzard
  frames. Item cooldowns with no spell ID (trinkets, combat/health potions,
  healthstone) are tracked by slot/category.
- merged Blizzard's CDM Group Buffs into the missing-raid-buff tracker; CDM-
  sourced buffs surface as manual toggles in the Auras editor.
- added an ally maintenance-buff reminder (Beacon of Light / Earth Shield), an
  action-bar raid-marker bar, and a Bloodlust/Heroism cooldown timer.
- added CDM buff-icon absorb-amount text, grow-on-apply, and buff-edge options.
- added Group Frames per-group "Group N" headers, cleanse glow, and a hide-DPS
  toggle; Unit Frames inline target-of-target, class-color, and per-size raid
  positions; a composer absorb-bar texture picker.
- added horizontal scroll with overflow controls to chat window tabs.

### Changed
- the boss-frame out-of-range alpha is now driven by range-update events instead
  of a polling ticker.

### Fixed
- fix(chat): keep player class colors on guild and party/raid senders through
  combat lockdown and on cold-login-into-combat, including plain-body lines with
  a secret sender.
- fix(qol): the focus/cast-alert interrupt sound now follows the same
  interruptibility signal that gates the alert visual.


## v5.0.0-alpha4 - 2026-06-25

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Changed
- consolidated the six cosmetic addons — Skinning, Datatexts, Minimap, Info Bar,
  QoL, and Alts — into a single LoadOnDemand bundle, **QUI_UI**, using 12.1's
  per-file `[Bootstrap]` TOC directive. The visual tier loads at startup; the
  Alts roster UI loads on first open. A "UI Bundle" toggle plus per-module
  dormancy flags (minimap / info bar / alts) control it. ⚠️ Brand-new packaging
  — if a cosmetic module doesn't appear, toggle it in Module Addons and `/reload`.
- unified every aura surface — player, unit, group frames, and buff borders —
  onto a single CustomAuraContainer render path, with a secret-safe stack count
  and per-dispel borders under 12.0 secret values.
- Bags now defaults **on** for new profiles (existing profiles are untouched).


## v5.0.0-alpha3 - 2026-06-23

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

Rebased the QUI5 12.1 line onto the latest 4.x beta (v4.0.4), folding in every
fix and feature that landed on the beta line since alpha2.

### Added
- added Delves/Dressing Room/PvP Match skinning surfaces; expanded the UIKit
  factory tier.
- added professions, quest log, housing, and adventure guide buttons to the
  Info Bar micro menu.

### Fixed
- refactor(font): override the shared Blizzard font objects instead of walking
  frames per-frame, so themed fonts survive Blizzard hover/disable swaps.
- fix(chat): launder hyperlink taint so "Copy Character Name" works again.
- fix(skinning): drop the tooltip refit and adopt 12.0.7 self-sizing; repair
  dead skins, backdrop persistence, and dead-field lookups; consolidate the
  font/backdrop paths and harden persistence.
- fix(tooltip): stop a C stack overflow from reentrant `Show()` in layout refresh.
- fix(cdm): prefer the override cooldown lane when a child override is active.
- fix(anchoring): pin the CDM buff-icon container out of the restricted anchor
  family.
- fix(clickcast): edge-driven keyboard binds, clear keys on last-bind removal,
  keep the mouse-over decision secure, and re-arm on transient mouseover-off.
- perf(groupframes): cut raid-frame cost across 5 hot paths.
- fixed friendly boss frames flickering, tooltips flickering when fading out, and
  LFG category button styling / refresh handling.


## v5.0.0-alpha2 - 2026-06-21

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

### Changed
- chore(toc): pin every shipped TOC to a single `## Interface: 120100`, dropping
  the pre-12.1 forward-compat list (120000/120001/120005/120007). QUI5 now
  declares support for patch 12.1 exclusively.


## v5.0.0-alpha1 - 2026-06-18

> ⚠️ **WoW 12.1 PTR ONLY.** QUI5 targets patch 12.1 (interface 120100) and will
> not load on the 12.0.x live client. Stay on the v4.x beta line for live realms.

First QUI5 alpha. Targets patch 12.1 and pulls the latest fixes and features
forward from the 4.x beta line.

### Added
- feat(cdm): "New Window" / "Delete Window" entries in the cooldown-manager header
  right-click menu.
- feat(cdm): bar duration text now driven via `DurationTextBinding` (12.0.7 API).
- feat(alts): overflow tab strips show scroll bars; fixed equipment ilvl/status
  text overlap.

### Fixed
- fix(12.1): `GetScaledCursorPosition` was removed from the in-world environment
  in patch 12.1 (now glue-screen only) — the cursor reticle errored every frame.
  Reimplemented locally from `GetCursorPosition` and UIParent's effective scale.
- fix(12.1): the global `AnimateTexCoords` moved to `TextureUtil` in 12.1 —
  restored the button glow "ants" animation (LibCustomGlow).
- fix(12.1): 12.1's assisted-combat rotation OnUpdate now calls
  `OnActionBarSlotChanged()`, a method QUI's custom action buttons don't inherit
  — stubbed it on the hosting button to stop the per-frame error.
- fix(chat): class color preserved on secret-sender whisper/party lines.
- fix(skinning,cdm): font-revert/template-drift sweep, mail frame skinning coverage,
  and glow drawn below the cooldown swipe.
- fix(auras): removed the IMPORTANT aura filter (removed by Blizzard in 12.0.7).

### Internal
- Refreshed the vendored FrameXML + Blizzard API doc corpus to 12.1.0.68209 and
  regenerated the LSP API definitions; sanitized control bytes in generated doc
  comments so the defs always parse.
- Regenerated the enUS localization base.



## v4.0.5-beta3 - 2026-06-24

### Fixed
- fixed a taint crash caused by leftover events on legacy party frames
- fixed action bars flickering on skyriding mount/dismount

## v4.0.5-beta2 - 2026-06-24

### Fixed
- fixed raid/party names blanking out for the rest of the session until /reload
- fixed boss cast bars persisting on screen after a wipe

## v4.0.5-beta1 - 2026-06-23

### Added
- reworked click-casting for reference parity — per-frame secure proxies, click direction (up/down), and friend/enemy bind separation

### Fixed
- fixed raid/party name class colors lost in combat
- fixed unreadable dark gossip text on skinned frames
- fixed flight map canvas hidden behind skinned backdrop
- hardened skin button-font walk against bad-self GetObjectType



## v4.1.0 - 2026-07-07

### Added
- feat(qol): add cursor trail, sound mute, loot curation + tooltip/bags extras
- feat(qol): add five QoL modules - audio device lock, event sounds, extended ignore, friends class colors, no-target warning
- feat(actionbars): add position options for the open-ticket icon

### Fixed
- perf(infobar): skip the mouseover-fade alpha work while settled
- perf(options): debounce slider onChange during drags
- perf(qol): park the cursor-follow watcher and gate repositioning on movement
- perf(damagemeter): stop walking settings on every render frame of the ticker
- perf(qol): run the pairs(_G) action-button sweep once per session
- perf(cdm): stop allocating bar-frame snapshots in the mouseover poll and fade fallback
- perf(cdm): make the buff-icon poll allocation-free and relax its cadence
- perf(qol): throttle the tooltip visibility watcher's idle and shown paths
- perf(cdm): gate alpha-enforcer work behind its throttle and child-count cache
- fix(core): park profile changes during Mythic+ instead of dropping them
- fix(core): detect cross-suite namespace export collisions
- fix(options): skip tab strip for single sub-page tiles
- fix(sounds): defer QoL whisper alert to chat when chat owns it
- fix(tooltips): guard GameTooltip widget containers from tainted layout
## v4.0.5 - 2026-07-06

### Added
- feat(groupframes): linear (horizontal/vertical) cooldown swipe option
- feat(groupframes): detached mini-bar mode for health overlays
- feat(groupframes): color debuff icon borders by dispel type
- feat(groupframes): overlay bar texture, draw order, fill, spark + outline
- feat(groupframes): expose party frames to external cooldown-tracker provider API
- feat(groupframes): party target frames
- feat(groupframes): ally-buff reminders + composer absorb texture
- feat(qol): disable scrolling combat text toggle
- feat(qol): merchant grid extender
- feat(damagemeter): dark/light theme preset for native meter
- feat(chat): scroll overflow for window tabs
- feat(clickcast): reference-parity rewrite - per-frame proxies, click direction, friend/enemy
- feat(qol): raid markers, lust timer, group/unit/CDM frames, chat, damage meter

### Changed
- refactor(unitframes): event-driven boss range alpha

### Fixed
- refresh HUD visibility on movement state changes
- fix(actionbars): stop skyriding HUD-visibility show/hide flicker
- fix(bags): merge bag→bank deposits into existing tab stacks
- fix(cdm): gate override-child cooldown lane to real base cooldowns
- fix(cdm): show mirror-child proc icon art when GetOverrideSpell stays on base
- fix(chat): apply suppress synchronously on combat /reload
- fix(chat): class-color guild senders on cold-login into combat
- fix(chat): class-color prefix on plain body with secret sender
- fix(chat): restore class colors on raid/party names in combat
- fix(groupframes): strip events on pooled legacy party frames (12.x taint crash)
- fix(groupframes,castbar): stop sticky name blanks + boss castbar persisting after wipe
- fix(inspect): suppress queued tooltip NotifyInspect once InspectFrame opens
- fix(qol): read AH expansion filter via GetFilters when available
- fix(skinning): raise flight map canvas above skinned backdrop
- fix(skinning): survive bad-self GetObjectType in button-font walk
- fix(skinning): fix unreadable dark gossip text on skinned frame
## v4.0.4 - 2026-06-23

### Added
- added Delves/Dressing Room/PvP Match surfaces; expand UIKit factory tier
- added professions, quest log, housing, adventure guide to micro menu

### Fixed
- fixed friendly boss frames flickering
- fixed tooltips flickering when fading out
- improved LFG category button styling and refresh handling
- refactor(font): override shared font objects instead of per-frame walks
- fix(anchoring): pin CDM buff-icon container out of restricted anchor family
- fix(chat): launder hyperlink taint so Copy Character Name works
- refactor(skinning): consolidate font/backdrop paths, harden persistence
- fix(skinning): drop tooltip refit, adopt 12.0.7 self-sizing
- fix(skinning): repair dead skins, backdrop persistence, dead-field lookups
- fix(cdm): prefer override cooldown lane when child override is active
- fix(clickcast): edge-driven keyboard binds + clear keys on last-bind removal
- fix(clickcast): drop insecure OnShow re-arm; keep mouse-over decision secure
- fix(clickcast): re-arm keyboard binds on transient mouseover-off and re-show
- perf(groupframes): cut raid-frame cost across 5 hot paths + add A/B harness
- fix(tooltip): stop C stack overflow from reentrant Show() in layout refresh
- chore(tools): add font rendering preview check screenshots
## v4.0.3 - 2026-06-21

### Added
- added per-bar action bars content based visibility options (including specifically "show on Mythic L'ura")
- added player level text options to unitframes and groupframes
- added visible scroll bars on overflow tabs + fix equipment ilvl/status overlap
- added global default font, CJK fallback, symbol glyphs + readable skinning text

### Fixed
- perf(cdm): cut in-combat aura/resolve churn + memo queries, drop redundant + self-aura walks
- perf(ui): reduce tooltip refresh churn
- fix(cdm): stop loadout swaps from resetting entries when per-loadout is off
- fix(cdm): mirrored cooldown icon stuck in aura mode after buff ends
- fix(skinning,cdm): font-revert/template-drift sweep, mail coverage, glow-below-swipe
- fix(skinning): harden lifecycle and recolors
- fix(skinning): kill text font/color reverts across skinned frames
- fix(skinning): reassert QUI font on pool-acquired and re-shown text
- fix(skinning): re-assert QUI theming Blizzard clobbers on hover/rebind
- fix(chat): keep player class colors through combat lockdown
- fix(chat): show BN friend name in copy window instead of ???
- fix(chat): preserve class color on secret-sender whisper/party lines
- fix(chat): restore hover tooltips on chat hyperlinks
- fix(qol): stop action tracker mouse toggle taint in combat
- fix(clickcast): proxy modified target/menu clicks
- fix(auras): remove IMPORTANT aura filter (removed in 12.0.7)
- fix(resourcebars): secondary bar swap recenters anchored position
- fix(groupframes): keep unit names visible in restricted-identity combat
- fix(anchoring): don't UIParent-pin a frame that is itself secure
## v4.0.2 - 2026-06-18

### Added
- added Omnium Folio datatext + mission button drawer option
- added resourcebars segment-divider (tick) settings in UI
- added per-bar border color for primary/secondary power bars
- added chat-specific font settings
- added icon skins & glow providers (external skin-library support + proc-glow customization)

### Fixed
- perf(cdm): cut in-combat resolve churn, park idle ticker, skip full resolve on text-only mirror refreshes
- fix(anchoring): pin protected-target frames to UIParent for combat-safe resize
- fix(cdm): fix proc-override icon recharge/glow/stack flicker
- fix(cdm): keep proc-overridden cooldown from going dormant
- fix(cdm): wire glow/effects settings to the composer live preview
- fix(groupframes): abbreviate secret health in absolute/both styles
- fix(gamemenu): unskinned QUI buttons use stock Blizzard look
- fix(gamemenu): inject QUI buttons when skinning disabled
- fix(resourcebars): scope segment dividers to secondary + preview parity
- fix(skinning): stop Blizzard tab/button art + font reverting over QUI skin
- fix(skinning): stop Group Finder text reverting to Blizzard font
## v4.0.1 - 2026-06-16

### Fixed
- fixed curseforge metadata upload
## v4.0.0 - 2026-06-16

QUI 4 is the next major release for Retail/Midnight. It restructures the addon into a small core plus LoadOnDemand feature suites, rebuilds the options experience, adds several full modules, and hardens the runtime for modern combat-taint and secret-value rules. Back up your `WTF` folder before upgrading from 3.x.

### Added
- Split QUI into core plus LoadOnDemand suite add-ons for Action Bars, Cooldown Manager, Chat, Group Frames, Unit Frames, Skinning, Datatexts, Minimap, Info Bar, Alts, Bags, Damage Meter, Debug, Options, Options Search, and QoL.
- Added major new or rebuilt experiences: Bags, Alts tracking, Info Bar, native Damage Meter, QUI-owned Chat display, Group Frames aura tooling, targeted-spell indicators, missing raid-buff tracking, and Resource Bar border controls.
- Added searchable/tiled options, richer Layout Mode tooling, in-game help content, diagnostics, profile/import helpers, generated search caches, and local CI/test helpers.

### Changed
- Rebuilt the Options UI around module pages, section navigation, pins, previews, searchable routes, and deferred loading.
- Reworked Cooldown Manager internals around split resolvers/renderers, custom container parity, per-loadout/spec state, and safer aura/cooldown handling.
- Consolidated skinning, font, border, scaling, storage, settings, migration, and UI-kit infrastructure across Blizzard frames and QUI-owned UI.
- Updated profile defaults and migrations for QUI 4; very old pre-3.5.11 profiles are backed up and reseeded instead of step-migrated.

### Fixed
- Hardened combat-taint and secret-value handling across chat, unit/group frames, action bars, cooldowns, tooltips, skinning, damage meter, and layout mode.
- Fixed many startup, reload, Edit Mode, Layout Mode, packaging, release workflow, search-cache, and module lifecycle issues found during alpha/beta testing.

### Removed
- Retired the old monolithic module layout, obsolete module master flags, first-run popup flow, pre-3.5.11 incremental migrations, stale localization/dev-build artifacts, and dead-code paths guarded by the new test suite.
## v4.0.0 - 2026-06-16

QUI 4 is the next major release for Retail/Midnight. It restructures the addon into a small core plus LoadOnDemand feature suites, rebuilds the options experience, adds several full modules, and hardens the runtime for modern combat-taint and secret-value rules. Back up your `WTF` folder before upgrading from 3.x.

### Added
- Split QUI into core plus LoadOnDemand suite add-ons for Action Bars, Cooldown Manager, Chat, Group Frames, Unit Frames, Skinning, Datatexts, Minimap, Info Bar, Alts, Bags, Damage Meter, Debug, Options, Options Search, and QoL.
- Added major new or rebuilt experiences: Bags, Alts tracking, Info Bar, native Damage Meter, QUI-owned Chat display, Group Frames aura tooling, targeted-spell indicators, missing raid-buff tracking, and Resource Bar border controls.
- Added searchable/tiled options, richer Layout Mode tooling, in-game help content, diagnostics, profile/import helpers, generated search caches, and local CI/test helpers.

### Changed
- Rebuilt the Options UI around module pages, section navigation, pins, previews, searchable routes, and deferred loading.
- Reworked Cooldown Manager internals around split resolvers/renderers, custom container parity, per-loadout/spec state, and safer aura/cooldown handling.
- Consolidated skinning, font, border, scaling, storage, settings, migration, and UI-kit infrastructure across Blizzard frames and QUI-owned UI.
- Updated profile defaults and migrations for QUI 4; very old pre-3.5.11 profiles are backed up and reseeded instead of step-migrated.

### Fixed
- Hardened combat-taint and secret-value handling across chat, unit/group frames, action bars, cooldowns, tooltips, skinning, damage meter, and layout mode.
- Fixed many startup, reload, Edit Mode, Layout Mode, packaging, release workflow, search-cache, and module lifecycle issues found during alpha/beta testing.

### Removed
- Retired the old monolithic module layout, obsolete module master flags, first-run popup flow, pre-3.5.11 incremental migrations, stale localization/dev-build artifacts, and dead-code paths guarded by the new test suite.

## v3.5.11 - 2026-05-28

### Added
- added configurable boss frame group layout (QUI Edit Mode > Boss Frames > Layout)

### Fixed
- fix: disconnect pandemic glow from per spell glow overrides (thx jopierce for the PR)
- fix: custom entries UpdateIconCooldown state mgmt (thx Gholie for the PR)

## v3.5.10 - 2026-05-19

### Added
- added skinning for context menus and some popup dialogs

### Changed
- you can now (re-)apply consumables in the consumable checker before they ran out

### Fixed
- fixed CurseForge upload script to reflect latest game version compatibility
- fixed tooltip added information row rendering and tooltip chrome rendering for player characters
## v3.5.9 - 2026-05-10

### Added
- added aura classification filters to unit frames buffs/debuffs (player and target)

### Fixed
- refresh aura cooldown caches on update in M+/raids
- stabilized dungeon eye sizing during combat
- fixed Blizzard font state across global font toggles
## v3.5.8 - 2026-05-05

### Changed
- stabilized raid frame sorting and re-ordering behaviour

### Fixed
- fixed buff icon stack text to stay above borders
## v3.5.7 - 2026-05-03

### Fixed
- fix(profile-io): include layoutMode and options panel collapsible state in selective export
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
- added pull timer command(s) (/pull (if available), /quipull, /quipull)
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
