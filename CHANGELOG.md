# Changelog

All notable changes to QUI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).



## v4.0.0-beta39 - 2026-06-12

> 🧪 **QUI 4 beta — meet QUI Alts: account-wide character tracking.** ⚠️ This beta introduces the **QUI Alts module — brand new, expect bugs, and off by default** (enable it under Module Addons). A new Alts window tracks every character you log: gold, item level, played time, professions, reputations, weeklies, lockouts, currencies, and a cross-character item search that covers bags, banks, the warband bank, and guild banks. Under the hood, the character data layer moved from the Bags module into core and now collects in the background on every login regardless of which modules you enable — **this is a one-time cache reset**: offline characters' inventory snapshots repopulate as you next log each one in. The M+ timer also picks up forces-row alignment and height options. No profile schema migration — your beta38 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Added
- **QUI Alts module (off by default).** A new account-wide character window — toggle it under Module Addons, then open it with `/alts` (or `/quialts`). Six tabs: **Roster** (sortable columns for gold, item level, played, rested, zone, professions, last seen, with account totals and right-click to drop a character from the cache), **Currencies** (every currency seen on any character, one selected character at a time), **Professions**, **Reputations** (renown- and paragon-aware, per-character selector), **Weeklies** (Great Vault, keystone, M+ rating, plus raid lockouts), and **Search** (find any item across all characters' bags and banks, including warband and guild banks).
- **Alts datatext.** A new datatext for the Info Bar and data panels summarising the account cache, with a configurable bar text (total account gold or alt count); clicking it toggles the Alts window.
- **M+ timer: forces row alignment and height.** The forces text gains a Left/Center/Right alignment dropdown, and bar mode gains a height setting (0 keeps the layout's default).

### Changed
- **Character data now collects in core, always on.** The storage layer behind Bags was promoted out of the module: scanning (character basics, gold, professions, reputations, weeklies, lockouts, inventory) runs at login whether or not Bags or Alts are enabled, so the cache is warm by the time you opt in. Per-scanner toggles for reputations, weeklies, and lockouts live in the Alts settings. One-time effect for existing installs: offline characters' inventory snapshots reset and repopulate as each character next logs in.
- **Played time fills in by itself.** The roster's Played column no longer waits for you to type `/played` — one silent request fires at login with the chat reply suppressed, so nothing extra prints to your chat.
- **Gold datatext reads the account cache.** Gold tracking now uses the same core roster as the Alts window (the old gold store remains as a read-only fallback); deleting a character from the roster also clears its legacy gold entry, and middle-click now opens the Alts window.

## v4.0.0-beta38 - 2026-06-12

> 🧪 **QUI 4 beta — Layout Mode anchoring polish and a damage meter display option.** A small beta: in Layout Mode, frames anchored to other frames now follow live while you drag, mover handles land where the anchored frame actually sits, and the minimap no longer fights the mover while docked elsewhere. The damage meter gains a toggle to hide the parenthetical secondary value on rows. No schema migration — your beta37 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Added
- **Damage meter: "Show secondary value" toggle.** A new appearance option (global, with a per-window override) controls the parenthetical metric on row values — per-second windows show "DPS (total)" and total windows show "total (per second)". Turn it off for a primary-value-only display. Default stays on, matching current behavior.

### Fixed
- **Anchored frames follow drags live in Layout Mode.** Dragging or nudging a frame now cascades immediately to everything anchored to it — children, grandchildren, and frames anchored through a proxy — instead of leaving them behind until the next refresh. The anchor sliders in settings cascade the same way.
- **Mover handles line up with anchored frames.** A frame's Layout Mode handle is now placed from its resolved anchor — the parent's handle, the parent frame itself, or the screen edge — so handles no longer drift for frames glued to their own handle, and a re-applied anchor snaps the frame back into its handle cleanly.
- **Minimap stops fighting Layout Mode while docked elsewhere.** When the minimap is parented away from the screen (for example into an external HUD), its anchor mirror now stands down, and entering Layout Mode no longer trips the HUD's reparent latch.

## v4.0.0-beta37 - 2026-06-11

> 🧪 **QUI 4 beta — Bags keep growing: auction house selling, a guild bank "All" tab, and a taint-safe takeover.** This beta keeps polishing the new Bags module: right-click items to post them at the auction house, browse the whole guild vault on one "All" tab, and manage your currencies from a single shared list used by the bag window, Info Bar, data panels, and minimap. Under the hood, the bag takeover was rewritten so secure flows that open bags — the mailbox, profession windows, loot toasts — keep running Blizzard's own code and can't be blocked by taint. The M+ timer learns objective text alignment, and the embedded Combat Log tab gets several in-combat fixes. No schema migration — your beta36 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Added
- **Sell from your bags at the auction house.** With the auction house open, right-clicking an item in the QUI bag window stages it in the sell panel. Items that can't be auctioned dim while the sell panel is open, with a tooltip hint to match.
- **Guild bank "All" tab.** The QUI guild bank window gains a synthetic All tab showing every tab's contents at once, and hovering a tab button highlights that tab's slots in the grid.
- **One Currencies list everywhere.** The data panels, the minimap currency panel, the Info Bar, and the bag window's currency bar now share a single Currencies section in settings — reorder and toggle your tracked currencies in one place and every surface follows.
- **M+ timer objective text alignment.** A new Left/Center/Right dropdown in the timer's General settings controls how the objective lines are aligned.

### Fixed
- **Opening the mailbox no longer trips taint with Bags enabled.** The bag takeover was rewritten to hook Blizzard's bag functions instead of replacing them, so secure code paths that open your bags — the mailbox, profession enchant flows, loot toasts — stay on Blizzard's own code. ESC still closes windows in the usual order.
- **The Combat Log tab works mid-combat.** Enabling the embedded Combat Log or clicking its tab during combat now shows the log immediately instead of leaving it blank until combat ends; only the protected filter pass waits for combat to drop, and the session's first mid-combat use now finds filters already applied.
- **Channel chat no longer leaks into the embedded Combat Log.** Trade and community channel messages are wired up outside the groups the Combat Log strip handled, so they kept interleaving with combat events; they're now stripped explicitly and handed back when the tab is disabled.
- **Leg enchants count in the character pane's enchant sidebar.** Legs are permanently enchantable, but the sidebar didn't treat them that way — a missing leg enchant now shows up like any other missing enchant.
- **Click-cast hover tooltip lists keyboard binds.** The click-cast tooltip on unit frames now includes your global keyboard binds, not just per-frame scroll-wheel binds.
- **Gold datatext tooltip uses digit separators.** The current-gold line in the gold datatext tooltip now formats large amounts with separators.

## v4.0.0-beta36 - 2026-06-11

> 🧪 **QUI 4 beta — Bags and Info Bar follow-up polish.** A quick follow-up to beta35's two new modules: the Info Bar gains a right-click menu for adding and arranging widgets, the guild bank now opens reliably with QUI Bags, bank footer buttons wrap on narrow windows, and the micro menu and bag bar get the same Enabled checkbox as the other action bars. No schema migration — your beta35 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Added
- **Right-click the Info Bar to manage widgets.** Right-clicking empty space on the Info Bar opens a context menu for the section under the cursor (left, center, or right): add any available widget there, remove ones you don't want, tweak per-widget settings, or jump straight to the Info Bar settings page.
- **Enabled checkbox for the micro menu and bag bar.** The micro menu and bag bar settings pages now have the same **Bar → Enabled** checkbox as bars 2-8, and toggling it takes effect immediately — no /reload needed.

### Fixed
- **The guild bank opens with QUI Bags.** Visiting the guild vault could leave QUI's guild bank window closed because the events it listened for don't fire there on retail. It now keys off the retail interaction events, with the old ones kept as a fallback.
- **Bank footer buttons wrap on narrow windows.** Shrinking the bank window squeezed the footer buttons into each other; they now wrap onto extra rows, the footer grows to fit, and the buttons pick up proper borders. The warband-tab highlight also shows only on the "All" grid and clears when you switch tabs.
- **The hearthstone tooltip no longer covers the teleport list.** On the Info Bar travel widget, hovering the hearthstone now stacks its tooltip past the teleport flyout instead of overlapping its top rows.
- **Options search routes Bags results correctly.** Bags search results shared a navigation slot with the Info Bar tile, which could send a click to the wrong page; each tile now has its own slot, with a regression test guarding future collisions.

## v4.0.0-beta35 - 2026-06-11

> 🧪 **QUI 4 beta — Bags and the Info Bar arrive.** Two brand-new modules land in this beta: **QUI Bags**, a complete replacement for your bags, bank, Warband bank, and guild bank, and the **Info Bar**, a full-width datatext bar with a micro menu. ⚠️ **Both modules are very new and may have bugs — they are OFF by default.** Enable them under **Module Addons** in the QUI options if you'd like to help test, and please report anything you hit on GitHub. This beta also adds four new datatexts plus data-broker plugin support, folds overflowing chat tabs into a "»" menu, and keeps non-combat chatter out of the embedded Combat Log. No schema migration — your beta34 profiles carry over unchanged. As always, **back up your `WTF` folder before installing**.

### Added
- **New module: QUI Bags** ⚠️ *brand new, off by default — expect bugs.* A full takeover of your bags, bank, Warband bank, and guild bank in QUI-styled combined windows: flat or category-grouped layouts, per-corner item badges (item level, crafting quality, junk, equipment set, quantity, binding, expansion), junk dimming with a Sell Junk button at merchants, one-click sorting (quality, type, name, item level, or expansion), Warband reagent deposit, new-item glow, and tooltip item counts across your characters. A "search everywhere" window finds items across every character's bags, banks, mail, equipped gear, and auction listings. Auto-open at merchants, mail, the auction house, and more is configurable, and there's an optional currency bar. Enable it under **Module Addons → Bags** and please report what breaks.
- **New module: Info Bar** ⚠️ *brand new, off by default — expect bugs.* A full-width bar across the top or bottom of the screen with left/center/right widget zones. Fill it with any QUI datatext, a micro menu, a travel/hearthstone button, or a quick spec-swap widget — and third-party data-broker (LDB) plugins are supported too. Height, font, background, border, mouseover fade, and combat hiding are all configurable. Enable it under **Module Addons → Info Bar**.
- **Four new datatexts: Reputation, Great Vault, Mail, and Professions.** Usable on the data panels and the new Info Bar.
- **Chat tabs overflow into a "»" menu.** When a chat window has more tabs than fit on the tab bar, the tail tabs fold into a "»" button — click it to jump to any hidden tab.

### Fixed
- **The embedded Combat Log shows only combat-log entries.** The Combat Log tab could interleave plain chat lines — tradeskill "creates" messages, pet info, and similar — with real combat events. That chatter now stays in your chat tabs, where its message groups belong.
- **Re-enabling the Combat Log tab refreshes the chat Filters page.** Toggling the Combat Log tab off and back on now updates the Filters page's "Editing tab" list immediately instead of leaving it stale.
- **Chat window sizing waits out combat restrictions.** If combat restricts the chat window (for example, a secure button is anchored to it), size and position updates are now applied when combat ends instead of being blocked with an error.

### Changed
- **Datatexts now live in their own module addon.** The data panels and datatexts moved into a `QUI_Datatexts` sub-addon as part of the suite split. It loads automatically — no action needed, your settings carry over.

## v4.0.0-beta34 - 2026-06-10

> 🧪 **QUI 4 beta — action bar, chat, and tracker fixes.** A small follow-up beta: the pet and stance bars now properly join the "Link Bars 1-8" mouseover group, the guild message of the day no longer reappears randomly mid-session, the combat-log filter fix from beta33 now holds across every login path, the Prey Tracker can be toggled without a /reload, and encounter power-bar widgets follow the skinned power bar instead of floating at their stock position. No schema migration — your beta33 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Pet and stance bars follow the linked mouseover group.** With "Link Bars 1-8" on, mousing over a linked bar showed bars 1-8 but left the pet and stance bars faded out. They're now full members of the linked group — they appear with the group, stay shown with it during combat when configured to, and the pet bar keeps working after mid-combat pet changes. Linked fading also respects a bar's individual fade setting.
- **The guild message of the day no longer reappears mid-session.** The login recovery added in beta32 could re-print the guild MOTD beside system messages at random points during play. The recovery now runs only around login; real MOTD changes still show normally.
- **Combat-log filters survive every login.** Beta33's fix for combat-log filters resetting to "show everything" could still miss on some logins; the embedded Combat Log now re-applies your saved filters reliably every time it's shown.
- **The Prey Tracker toggles without a /reload.** Enabling the Prey Tracker mid-session now takes effect immediately, and disabling it hands the stock Blizzard tracker back live.
- **Encounter power-bar widgets follow the skinned power bar.** Fights that add extra power-bar widgets left them at their stock screen position, detached from QUI's alternate power bar. They now sit just below it — unless you've taken control of them with the "Power Bar Widgets" mover, which still wins.

### Changed
- **Combat Log tab settings are clearer.** The Combat Log tab's settings page now explains that message groups and channels don't apply to it instead of showing empty editors, and deleting the tab turns the embedded Combat Log feature off.

## v4.0.0-beta33 - 2026-06-10

> 🧪 **QUI 4 beta — QUI Chat follow-up fixes.** A quick follow-up to beta32 focused on the new Combat Log tab and custom chat tabs: combat-log filters no longer reset to "show everything", the embedded Combat Log is left-aligned like the stock one, /played no longer prints repeatedly at login, and unchecking channels on a custom tab actually keeps them out. No schema migration — your beta32 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Combat-log filters no longer reset to "show everything".** With the Combat Log embedded as a QUI Chat tab, your combat-log filters could silently break — the log began showing every event from everyone and stayed that way until a /reload. The embed now keeps Blizzard's filter refresh on a safe path, so your filters keep working.
- **The embedded Combat Log is left-aligned again.** Combat Log lines were centered after adopting QUI's chat font; they now stay left-aligned like the stock combat log, including after live font changes, and alignment is handed back correctly when the tab is disabled.
- **/played no longer prints repeatedly at login.** Addons can quietly ask the game for your played time; QUI Chat printed every one of those background requests as /played output. It now prints only when the result was meant to be shown, and old /played lines are no longer replayed from saved chat history.
- **Unchecked channels stay out of custom chat tabs.** Unchecking every channel on a custom tab could bring Trade and Services right back on the next login. A deselected channel now stays deselected. If a tab you emptied before this fix still shows them, toggle any of its channel checkboxes once to re-save it.

## v4.0.0-beta32 - 2026-06-10

> 🧪 **QUI 4 beta — QUI Chat polish.** This one is almost entirely about the QUI Chat module: the Combat Log joins your chat window as a real tab, whisper tabs can be reordered alongside your saved tabs, the copy-chat window finally copies exactly what you see (colors included), chat windows stop jumping between two remembered positions, replying with the reply keybind works again, and channel colors are right at login instead of white. There's also a new option to show cross-realm players' full "Name-Realm" in chat, and the minimap lays out correctly after a /reload during combat. **This beta migrates your profile schema (v43 → v45)** — an automatic backup is taken, but as always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Added
- **The Combat Log is a tab in QUI Chat.** Blizzard's Combat Log now embeds as a pinned tab in your first chat window, using QUI's font and styling, with its own scrollbar. It's on by default, can be turned off in the chat settings, and can be drag-reordered within the tab bar like any other tab.
- **Option to show cross-realm players' realm names.** A new "Show Realm Names" chat setting displays senders as "Name-Realm" instead of just "Name". It's off by default; if your profile previously showed realms via the channel-shortening setting, the migration keeps your current look.

### Fixed
- **Chat windows no longer snap between two saved positions.** QUI Chat kept a window's position in two places that could drift apart, so a window would sometimes jump to an older spot after a move or reload. Position now lives in a single store (migrated automatically), and resizing a window from a corner grip no longer shifts it sideways when you close Layout Mode — for the damage meter too.
- **Copy Chat copies what you actually see.** The copy window could come up completely blank when a Battle.net name was anywhere in the scrollback, dropped all colors, and mangled some item and player links. It now preserves each line's color, keeps link text readable, and opens scrolled to the newest lines.
- **Channel colors are correct at login.** Lines that arrived before your chat colors finished downloading — most visibly the guild message of the day — were baked white and stayed white. QUI Chat now waits for the right color and retroactively recolors the affected lines once colors sync.
- **The reply keybind works in QUI Chat.** Pressing your reply key (R by default) to answer the last whisper did nothing under the chat takeover. Incoming whispers and Battle.net whispers now register as your reply target again.
- **Battle.net names in chat link correctly.** Clicking a Battle.net player's name could fail because the protected name token was being upper-cased. Those name links work again.
- **Chat respects your font with Asian-language clients.** With CJK locales, the chat edit box and the embedded Combat Log stayed on Blizzard's stock font; they now adopt the same font as the rest of QUI Chat, including after live theme changes.
- **Chat history honors its limits.** Restored history now respects your configured line cap instead of a fixed default, and excluded channels are matched reliably so their lines stay out of the saved history.
- **The minimap survives a /reload during combat.** Reloading the UI mid-combat could leave the minimap blocked from laying out ("action blocked"); it now initializes inside the safe window and comes up positioned and skinned.

### Changed
- **Whisper tabs reorder like normal tabs.** Conversation (whisper) tabs and your saved tabs now share one ordering on the tab bar, so you can drag any tab anywhere. Saved-tab order persists; conversation-tab positions last for the session.

## v4.0.0-beta31 - 2026-06-09

> 🧪 **QUI 4 beta — small fixes.** Another quick follow-up to beta30: buff border timers on long buffs like flasks no longer freeze or blank out, right-clicking a buff border to cancel it works again, QUI Chat is steadier (whisper tabs, the guild message of the day, and a couple of crashes), fresh installs get a starter look and a welcome window, and loot roll toasts and the Mythic+ abandon prompt land where they should. No schema migration — your beta30 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Added
- **Fresh installs start with a ready-made look.** A brand-new install now applies a starter profile automatically and shows a short welcome window with a Reload button, so QUI looks complete the first time you log in. Upgrades are untouched — this only happens on a clean first install.
- **Private auras have a Text Scale setting.** Group-frame private auras now have a Text Scale slider (0.5–1.5) so you can size their countdown and stack text without changing the icon size.

### Fixed
- **Buff border timers no longer freeze or blank out.** The countdown on action-bar buff borders — most visibly on long buffs such as flasks — could freeze at a stale number or disappear during combat. The remaining time is now drawn by the game's own countdown, so it stays accurate through combat.
- **Right-clicking a buff border to cancel it works again.** Cancelling a buff by right-clicking its border had silently stopped working after a settings change or leaving combat. It cancels reliably again.
- **No more stale borders on empty buff slots.** A buff border could briefly linger on a slot that no longer had a buff. Empty slots are now cleared.
- **QUI Chat whisper tabs no longer hide whispers from your regular tabs.** Opening a whisper conversation in its own tab removed those whispers from your normal tabs. Whisper tabs are now additive — the conversation tab is extra, and your regular tabs keep showing the whispers.
- **QUI Chat no longer crashes when you turn it off.** Disabling the QUI Chat module could crash the game while restoring Blizzard's chat font. The font is now restored safely.
- **Clicking a name in QUI Chat no longer crashes.** Left-clicking a player, Battle.net, or channel name could crash the game. Those clicks are safe again.
- **The guild message of the day shows reliably at login in QUI Chat.** It could be missing right after logging in; QUI Chat now picks it up once chat settings finish downloading.
- **Loot roll-won toasts respect your Alert Anchor.** A toast for loot you won could snap to the bottom-center of the screen instead of following QUI's Alert Anchor. It now stays where you placed it.
- **The Mythic+ abandon-vote prompt opens in the right place.** Blizzard's "leave instance?" vote popup appeared in the bottom-right corner; it now opens top-center through QUI's frame mover, where you can reposition it.
- **Boss frames no longer risk a combat error during encounters.** Refreshing boss frames when an encounter begins could trip a protected-value error; the refresh now avoids it.
- **World quest reward tooltips no longer cause errors.** Hovering a world quest's reward card could taint Blizzard's tooltip sizing and produce errors. QUI now leaves that embedded reward tooltip untouched.

### Changed
- **The QUI Chat settings page offers a reload when you toggle it.** Turning the chat module on or off from its settings page now prompts for a UI reload, matching the Module Addons screen.
- **QUI's sub-addons group together in the AddOns list.** The separate QUI feature folders now share a "QUI" group so they sit together on the in-game AddOns list.

## v4.0.0-beta30 - 2026-06-09

> 🧪 **QUI 4 beta — small fixes.** Another quick follow-up to beta29: several Quality of Life features that quietly stopped starting at login are back (combat timer, crosshair, reticle, consumable check and more), the minimap is skinned and positioned correctly straight from the loading screen, QUI Chat shows Battle.net friend online/offline notices again, and a couple of in-combat "action blocked" errors around the Cooldown Manager and the guild message of the day are fixed. No schema migration — your beta29 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Quality of Life features that stopped starting at login work again.** With the Quality of Life module enabled, several features set themselves up at login but never actually started — so you would see no combat timer in encounters, no crosshair or reticle, and no consumable check, action tracker, battle-res counter, or extra combat text. They now initialize reliably once you log in.
- **The minimap is skinned and positioned from the loading screen.** The minimap could briefly appear unskinned or mis-placed after logging in, and stay that way until you opened Layout Mode. It now skins, reparents, and anchors during the loading screen and re-settles against your final UI scale, so it looks right the moment you arrive.
- **Battle.net friend online and offline notices show again in QUI Chat.** With the QUI Chat module enabled, Battle.net friends coming online or going offline produced no message. Those notices are back.
- **The Cooldown Manager no longer throws an "action blocked" error in combat.** Refreshing the buff-icon layout during combat could trigger a blocked-action error. The refresh now waits a frame so it runs safely.
- **The guild message of the day no longer throws an "action blocked" error.** Reading the guild message of the day during combat could trigger a blocked-action error and drop the message. It is now read through a path that is safe in combat, so your guild's message of the day shows reliably at login.
- **Blizzard chat keeps its left alignment when QUI Chat is off.** Applying QUI's font to Blizzard's chat frames re-centered their text; chat now preserves its original alignment.
- **More close buttons sit correctly and pick up QUI's skin.** The Inspect window's close button and its View and Talents buttons are now skinned, and the close buttons on the loot-history and item-link tooltip windows are tucked into the corner so QUI's button no longer overhangs the frame edge.

## v4.0.0-beta29 - 2026-06-08

> 🧪 **QUI 4 beta — small fixes.** A quick follow-up to beta28: cooldowns that a talent turns passive now reliably go dormant (beta28's version missed the most common case), QUI Chat no longer spams Lua errors on text emotes and guild loot messages, and the close button on item-link tooltips picks up QUI's skin. No schema migration — your beta28 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Cooldowns that a talent turns passive now reliably go dormant.** beta28 added this, but it missed the most common case — a talent that swaps an active ability for a passive one (a different spell) left the old icon sitting on the bar doing nothing. The Cooldown Manager now keys this on your currently-active cooldowns, so a converted-away ability goes dormant on its own and comes back automatically once it's an active ability again. Legitimate active replacements are kept.
- **QUI Chat no longer throws Lua errors on text emotes and guild loot messages.** With the QUI Chat module enabled, lines such as text emotes (for example `/wave`) and guild member loot notifications produced a burst of `formatKey ... doesn't exist` errors. Those messages now format cleanly with no errors.
- **The close button on item-link tooltips is skinned.** Clicking an item link opens a tooltip whose close button was still Blizzard's red X, showing through the otherwise-skinned frame. It now matches QUI's skin.

## v4.0.0-beta28 - 2026-06-08

> 🧪 **QUI 4 beta — suite-split follow-up fixes.** A fast follow-up to beta27 that restores tooltip skinning and a few other features the suite split quietly broke, cleans up how the Cooldown Manager handles spells that hero talents turn passive, makes the Hero Talents window movable, and locks the resize handles on anchored chat and damage-meter windows. No schema migration — your beta27 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Tooltips are skinned again, and tooltips can follow the cursor again.** The beta27 suite split left several features that set themselves up at login from ever actually starting — so Blizzard's tooltips lost QUI's skin everywhere, and the "anchor tooltips to the cursor" option stopped working. Those features now initialize reliably after you log in, restoring tooltip skinning, cursor anchoring, loot-window skinning, the pet-happiness warning, the Mythic+ progress tooltip, and range checking.
- **The Cooldown Manager handles cooldowns that a hero talent turns passive.** When a hero talent converts one of your tracked cooldowns into a passive, the icon used to sit on the bar doing nothing. It now goes dormant — hidden but kept — on its own, and comes back automatically once it's an active ability again, the same way spells you can't currently use already behave.
- **Removing a tracked spell no longer carries over to your other hero talent build.** Both hero talent builds inside one loadout share the game's loadout id, so removing a spell from a tracked container in one build also removed it from the other. Removals are now scoped to the hero build you made them in.

### Added
- **The Hero Talents window can be moved.** QUI's Blizzard frame mover can now reposition the Hero Talents dialog, without the stream of "anchor family connection" errors moving it used to produce.

### Changed
- **Anchored chat and damage-meter windows lock their resize handles in Layout Mode.** A window pinned to another frame already refused to be dragged unless you held Shift; its resize grips now behave the same way. Grabbing a corner without Shift flashes the border instead of resizing, and holding Shift detaches the anchor and resizes it — exactly like Shift-dragging the window to move it.

## v4.0.0-beta27 - 2026-06-08

> 🧪 **QUI 4 beta — suite split + opt-in QUI chat.** The biggest structural change since QUI 4: QUI now installs as a core addon plus a set of per-feature sub-addons you can enable or disable individually — and one of them is a brand-new, opt-in QUI-owned chat display. Plus a Cooldown Manager loadout-tracking fix at login, a first-open Options speed fix, and Korean/Chinese font support. This build upgrades your profile to schema v43 and **takes an automatic backup of your profile first** — your beta26 settings carry over untouched, and if you were on Blizzard chat you stay there unless you opt in. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.
>
> ⚠️ **Install note:** QUI is now several addon folders. Updating through CurseForge or the release zip installs all of them automatically — but if you copy files in by hand, install **every** `QUI*` folder from the zip, not just `QUI`, or modules will be missing.

### Added
- **QUI is now a modular suite.** QUI has been split from one monolithic addon into a core addon plus individual sub-addons — Unit Frames, Action Bars, Cooldown Manager, Chat, Group Frames, Resource Bars, Skinning, Minimap, Quality of Life, Damage Meter, and the Options panel. You can turn whole modules on or off from QUI's Module Addons page (or your AddOns list), and several load on demand instead of at every login. Your settings and layouts carry over unchanged.
- **QUI-owned chat display (opt-in).** A new QUI Chat module replaces Blizzard's chat with QUI's own: multi-window chat, dedicated whisper conversation tabs, a copy button, a custom scrollbar, and full parity with Blizzard's message formatting — channel labels, system lines, guild Message of the Day, and class colors. It ships **off by default** — enable the **QUI Chat** module from the Module Addons page (or your AddOns list) to switch it on, and turn it off any time to go back to Blizzard chat. Existing beta26 setups stay on Blizzard chat unless you opt in.

### Changed
- **Modules are now enabled or disabled per addon.** The old per-profile module master switches have been retired in favor of the single enable/disable row each module has on the Module Addons page (and in your AddOns list). If you'd previously turned a module off, that choice is carried over automatically — and it is now account-wide rather than per-profile.
- **The Options window opens instantly the first time.** The settings search index — a large generated file — now loads on demand the moment you first use the search box, instead of being compiled up front, so the first time you open Options in a session no longer briefly hitches.

### Fixed
- **Cooldown Manager containers track the right loadout right after login.** The game doesn't report your selected talent loadout until just after you finish loading in, so containers keyed to a specific loadout could come up tracking the wrong one until a `/reload`. QUI now waits for the game's talent/loadout callbacks and re-keys to the correct loadout on its own, including through rapid loadout swaps.
- **Korean and Chinese characters render with the QUI font.** QUI's font carries no CJK glyphs, and applying it collapsed the game's per-language font fallback, blanking Korean/Chinese names and text wherever QUI set the font. QUI now builds a proper font family that keeps the game's CJK fonts as fallbacks, so those names display correctly.

## v4.0.0-beta26 - 2026-06-06

> 🧪 **QUI 4 beta — bugfix build.** Follow-up to beta25 with a ground-up rework of how Cooldown Manager containers treat spells the game reports as unknown, a keyboard click-cast hover fix, a new durability mover, and refreshed skyriding defaults. No schema migrations: your beta25 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Cooldown Manager containers never automatically remove tracked spells anymore.** The beta25 fix narrowed the login window in which a tracked talent spell (interrupts like Quell, and other class-tree picks) could be judged "unknown" and silently moved out of a container — but the window could still be hit during talent/loadout swaps, when the game transiently unlearns and relearns talent spells. The model is now changed outright: your tracked lists are treated as pure user intent and are never modified by spell-known checks at all. A spell you can't currently use is simply not drawn on the bar (and comes back on its own as soon as the game reports it learned again), the composer lists it in a grayed **Dormant** section where it can still be removed by hand, and adding a spell the game momentarily reports as unknown now lands directly in your list instead of on a hidden shelf. Any spells the old behavior had already shelved are automatically restored into their containers at their saved position on first load — including spells stranded by this bug in earlier builds.
- **Keyboard click-cast keys no longer take over while you hover a nameplate or a world unit.** beta25 routed keyboard click-cast through a secure caster that activates while your cursor is over a unit — but the game's hover condition can't tell your unit frames apart from enemy nameplates or characters standing in the world, so keyboard click-cast keys could swallow their normal action-bar action anywhere your cursor crossed a unit. The caster now checks whether the cursor is genuinely over one of your registered unit frames, and bindings engage and release the instant your cursor enters or leaves a frame instead of on a fraction-of-a-second polling delay.
- **Spec-tracked Cooldown Manager profiles keep up with rapid loadout swaps.** Switching talent loadouts in quick succession could leave a pending spec-profile switch unresolved, so containers could keep showing the previous spec's tracking until the next clean switch. The switch now resolves directly from the game's talent-system callbacks, so it lands even during loadout churn.

### Added
- **The equipment durability indicator now has a Layout Mode mover.** The armored-figure durability display can be repositioned like any other QUI element — with a show/hide preview while you place it — instead of being stuck at the game's default spot.

### Changed
- **Refreshed skyriding bar defaults.** Fresh installs — and any skyriding settings you haven't customized — now default to Second Wind drawn as a minibar under the vigor bar (instead of pips), taller bars, showing the bar only while flying with a quicker fade, and a higher on-screen position. The layout-mode preview now matches the real sizing for each display mode. Anything you've customized is untouched.
- **The Profiles page and pinned settings now use the dual-column layout.** Switch/Copy/Delete/Create are merged into a single Manage Profiles card with paired rows, the Create button sits inline next to the new-profile name box, and pinned settings render two per row with compact value chips and Jump/Unpin buttons. The Click-Cast settings page also moves onto the shared card layout.
- **Debug instrumentation is now fully dormant in normal sessions.** QUI's internal counters, memory probes, and profiler hooks only switch on when the separate QUI_Debug developer addon is loaded, so regular sessions no longer pay any overhead for them.

## v4.0.0-beta25 - 2026-06-05

> 🧪 **QUI 4 beta — bugfix build.** Follow-up to beta24 with a cold-login keyboard click-cast rework, a Cooldown Manager data-loss fix, and two skinning border fixes. No schema migrations: your beta24 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Custom Cooldown Manager containers could randomly lose tracked spells at login.** Talent-granted spells (interrupts like Quell, and other class-tree picks) could be judged "unknown" during the brief window before the game finishes loading talent data, get shelved out of the container, and then have their recovery record destroyed — making the loss permanent and forcing a manual re-add. Three fixes: the dormancy check now waits until talent data is actually loaded before shelving anything; shelved spells are never automatically purged anymore (a shelved spell now always returns on its own once it's known again); and spec/loadout profile loads — and profile imports — no longer touch custom containers' shelved-spell state.
- **Keyboard click-cast no longer comes up dead after a cold login.** On a fresh game start (not a `/reload`) the game could silently drop the keyboard bindings click-cast set up while you hover a unit frame — mouse click-casting worked, but keyboard keys did nothing until a `/reload`. The binding model is reworked: keyboard click-cast keys are now published once at setup and routed through a single secure caster that is only active while your cursor is over a unit frame, so the keys reliably cast on hover and fall straight back to their normal action-bar behavior when you aren't hovering anyone. Scroll-wheel click-casts are unaffected and keep their existing behavior.
- **The ready-check popup's border no longer disappears after login.** The popup's 1px border was laid out before the final UI scale was applied; once the real scale landed the edges could land between pixels and drop out. The border now recomputes whenever the UI scale settles or changes.
- **Skinned 1px borders no longer vanish at certain screen positions.** A 1-pixel solid border line could fail to draw at all depending on where the frame sits on screen — most visibly the Character window's close button losing its border box on the Reputation and Currency tabs while looking fine on the Character tab. The skinning engine now exempts these hairline borders from the game's pixel-grid snapping, the same treatment the other border styles already had.

## v4.0.0-beta24 - 2026-06-05

> 🧪 **QUI 4 beta — feature preview build.** Follow-up to beta23 laying the groundwork for a QUI-owned chat display. Everything new in this build ships **off by default** — your chat works exactly as in beta23 unless you opt in. No schema migrations: your beta23 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Added
- **Custom chat display (early preview, opt-in).** First phase of the chat takeover: QUI can now capture chat messages directly from the game's events and render them in its own message view, instead of restyling Blizzard's window. The capture path respects Blizzard's chat filters, and you can flip between the custom view and stock Blizzard chat losslessly at any time. There is no options toggle yet — the feature sits behind the `chat.displayMode` profile setting and defaults to the Blizzard display, so nothing changes until a later build exposes it. Shipping it dark lets the plumbing soak in real sessions first.

## v4.0.0-beta23 - 2026-06-05

> 🧪 **QUI 4 beta — bugfix build.** Follow-up to beta22 with a keyboard click-cast keybind fix and main-chat polish. No schema migrations: your beta22 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Keyboard click-cast keys that are also action-bar keybinds no longer get shadowed after a cold login.** If the same key was bound to both a keyboard click-cast and an action-bar slot, the action bar could win that key on a slow or cold login and the hovercast would silently stop working on it until a `/reload`. The two systems now coordinate: click-cast owns the key end to end — it casts on the frame you're hovering and falls straight back to the action-bar action when you aren't hovering anyone — so there's no longer a tug-of-war over the binding.
- **The main chat frame keeps its custom size across `/reload`.** Blizzard regenerates its preset chat layout from code on load, which could snap a resized chat window back to the default dimensions. QUI now re-applies your stored chat width and height once the login layout settles.

### Changed
- **Blizzard's Edit Mode selection box and resize grip no longer clutter the chat frame.** Since QUI skins and owns the chat window, that blue selection outline and the corner resize handle are now hidden while Edit Mode is open.

## v4.0.0-beta22 - 2026-06-05

> 🧪 **QUI 4 beta — bugfix build.** Follow-up to beta21 with another keyboard click-cast fix. No schema migrations: your beta21 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Keyboard click-casting no longer cuts out when you move between unit frames after a busy login.** All of your party/raid frames share a single keyboard-binding manager. During a slow or cold login the frames shuffle around a lot, and a "mouse left" event for a frame you'd *already* moved off of could arrive late and clear the binding the frame you're actually hovering just set — dropping that key back to its normal action (for example an action-bar keybind sharing the same key) until a `/reload`. Mouse click-casting was unaffected. QUI now tracks which frame is genuinely under your cursor and only clears bindings for that frame, so keyboard click-casting stays live through login.

## v4.0.0-beta20 - 2026-06-05

> 🧪 **QUI 4 beta — hotfix build.** Follow-up to beta19 for protected chat-event handling. No schema migrations: your beta19 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Protected channel notices no longer trip over the main chat frame on login.** beta19 loaded the main chat sizing helper on the runtime path and automatically detached/synced the main chat frame during startup. On restricted chat events, Blizzard can deliver secret channel-notice fields; if the frame's event path had already been tainted by that startup sync, Blizzard's own channel-notice comparisons could error. QUI now keeps that helper load-on-demand for options/layout controls and no longer runs the automatic startup detach/sync, while leaving manual chat width, height, and position controls available.

## v4.0.0-beta19 - 2026-06-05

> 🧪 **QUI 4 beta — bugfix build.** Follow-up to beta18 with fixes for the character pane and chat positioning. No schema migrations: your beta18 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **The character pane's Versatility row stays live in restricted combat.** Versatility could freeze or show an empty bar while the other secondary stats kept updating in dungeons, raids, or PvP, because its full displayed value needed a Lua-side calculation that is unsafe when the stat values are restricted. QUI now uses a combat-safe live value path for that row and keeps the tooltip plain when the richer breakdown cannot be read safely.
- **Main chat window positioning no longer re-enters Edit Mode.** The earlier chat protection fixes detached the main chat window, but stored-position restores and frame-position refreshes could still call the game's Edit Mode geometry overrides and re-taint chat handling, causing protected chat lines to error again. QUI now positions detached system frames through the original frame geometry setters and loads the chat sizing helper on the runtime path, so login positioning and layout refreshes stay out of Edit Mode.

## v4.0.0-beta18 - 2026-06-04

> 🧪 **QUI 4 beta — bugfix build.** Follow-up to beta17 with three fixes for click-cast and skinning. No schema migrations: your beta17 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Keyboard click-casting survives spec/talent data that lands during combat.** If your specialization or talent data finished loading while you were already in combat — and you reached for a keyboard click-cast binding mid-fight — QUI couldn't rebuild the binding then (the game blocks that in combat) and could quietly give up, leaving keyboard click-casting inactive (mouse bindings still worked) until a `/reload`. QUI now remembers the pending setup and completes it the instant combat ends, so your keyboard bindings come back on their own.
- **Reward pop-up alerts stay pinned to your Alert Anchor.** While certain Blizzard panels are open, the game briefly relocates the frame that pop-up alerts (collection rewards, achievements, and the like) anchor to. QUI's alerts could follow that temporary frame instead of your configured Alert Anchor and appear in the wrong spot. QUI now keeps those alerts attached to your Alert Anchor mover regardless.
- **Encounter Journal monthly activities text now uses your QUI font.** The monthly activities panel rebuilds its activity rows, filters, and reward threshold text after QUI's journal skin runs, so those pieces could fall back to the game's default font. QUI now re-applies its text styling whenever that panel refreshes, so the whole panel reads in the QUI font.

## v4.0.0-beta17 - 2026-06-04

> 🧪 **QUI 4 beta — bugfix build.** Follow-up to beta16 with two fixes for click-cast and the Ready Check skin. No schema migrations: your beta16 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Keyboard click-casting holds up through a slow login even with all-spec bindings.** Building on beta16, QUI could still treat a brief, not-yet-resolved specialization the game reports during a slow login as if it were your real spec. If you also kept a global (all-spec) click-cast binding set, that set could resolve first and make setup look finished — leaving your per-spec keyboard bindings inactive (mouse bindings still worked) until a `/reload`. QUI now recognizes that not-yet-ready state and keeps recovering until your real specialization lands, so per-spec keyboard click-casting comes alive on its own.
- **The skinned Ready Check popup no longer draws over its own text.** On some setups the Ready Check window sits at the very bottom of the interface's layering, where QUI's themed background and border could cover the "Ready Check" title, the prompt, or the Yes/No button labels. QUI now draws that background and border as dedicated layered pieces that always stay behind the text, so the popup is fully readable.

## v4.0.0-beta16 - 2026-06-04

> 🧪 **QUI 4 beta — a follow-up fix.** A small follow-up to beta15 that makes keyboard click-cast recover on its own no matter how late your spec/talent data lands. No schema migrations: your beta15 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Keyboard click-casting reliably wires itself up after a slow login.** beta15 kept retrying click-cast setup on a fixed timer; on an unusually slow login your specialization and talent data could still arrive after that retry window closed, leaving keyboard bindings inactive (mouse bindings still worked) until a `/reload`. QUI now re-checks the moment the game reports your spec/talent data is ready, and again the moment you hover a unit frame to use a binding — so keyboard click-casting comes alive on its own, and at worst heals on your very next hover.

## v4.0.0-beta15 - 2026-06-04

> 🧪 **QUI 4 beta — a follow-up fix.** A small follow-up to beta14 that makes the keyboard click-cast cold-login fix hold up even on slow logins. No schema migrations: your beta14 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Keyboard click-casting now comes alive even after a slow first login.** beta14 made QUI keep retrying click-cast setup until your specialization and talent data arrived, but on a slow login (busy realm, first load of the session) that data could still show up after QUI had stopped retrying — leaving keyboard click-cast bindings inactive (mouse bindings still worked) until a `/reload`. QUI now watches for that data longer, and also re-checks the moment the game reports your spec/talent data is ready, so keyboard click-casting wires itself up on its own no matter how late that data lands.

## v4.0.0-beta14 - 2026-06-04

> 🧪 **QUI 4 beta — performance + a fix.** Follow-up to beta13 that smooths out Mythic+ and raid pulls and fixes keyboard click-casting right after login. No schema migrations: your beta13 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Performance
- **No more stutter at the end of Mythic+ and raid pulls.** Whenever an encounter, Mythic+ run, or rated PvP match began, QUI's cooldown manager was queuing a full rebuild of its internal cooldown catalog and running it the moment combat ended — adding a brief hitch right as each pull wrapped up. QUI now does only the cheap, targeted refresh those moments actually need (re-syncing tracked auras), and does it on the spot rather than at the end of combat, so pull transitions stay smooth.
- **A little more login work moved off the startup path.** Following beta13's change to build the options UI on demand, the minimap's settings page is now also assembled only when you open the settings, taking a bit more work off login.

### Fixed
- **Keyboard click-casting on group frames now works reliably right after login.** On a cold login your specialization and talent data can arrive a moment after the game finishes loading, and QUI could finish wiring up click-cast bindings before it was ready — leaving your keyboard click-cast bindings inactive (mouse bindings still worked) until a `/reload`. QUI now keeps retrying until that data lands, so keyboard click-casting is live from the first login.

## v4.0.0-beta13 - 2026-06-04

> 🧪 **QUI 4 beta — performance + a fix.** Follow-up to beta12 that speeds up login and tidies up tooltip fonts. Your beta12 profiles carry over unchanged; on first login QUI also slims down its own saved data behind the scenes. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Performance
- **Faster login.** QUI no longer builds its options panel on every login — the configuration UI is now assembled on demand the first time you open the settings, taking that work off the startup path. Remaining startup tasks now also wait until the game has rendered its first frame before running, so they stop competing with the initial login.
- **Smaller saved data.** QUI's per-profile saved-variables footprint has been trimmed so there's less to read and copy at login. The safeguard that preserves your customizations when a built-in default changes still works exactly as before — it's just stored far more compactly now, as a single account-level snapshot instead of a copy per profile. QUI also keeps only the most recent pre-migration backup rather than several.

### Fixed
- **Tooltips now use your configured QUI font throughout.** Tooltip lines could keep the game's default font face even though QUI was applying the configured size, leaving a mismatch on later lines. QUI now sets the font face and outline alongside the size, so tooltip text renders in the QUI font as intended.

## v4.0.0-beta12 - 2026-06-03

> 🧪 **QUI 4 beta — bugfix build.** Follow-up to beta11 fixing a Mythic+ keystone skinning glitch. No schema migrations: your beta11 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Mythic+ keystone affix icons are no longer covered by a colored square.** When you slotted a keystone, QUI's themed border on each affix icon was being drawn as a solid filled square on top of the icon, hiding the affix art behind a skin-colored block. QUI now draws a proper hollow border around each affix icon, so the affix art stays visible and the border follows your skin color as intended.

## v4.0.0-beta11 - 2026-06-03

> 🧪 **QUI 4 beta — bugfix build.** Follow-up to beta10 making the chat protected-message fix airtight on login. No schema migrations: your beta10 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Chat protected-message fix now lands before the chat window is styled.** beta10 stopped QUI from managing the main chat window through Edit Mode, but on login QUI could still apply its own styling to the window first, leaving a brief gap where a protected message (such as some channel or system lines) could still throw an error. QUI now detaches the chat window from Edit Mode before any of its styling or layout runs, closing that gap.

## v4.0.0-beta10 - 2026-06-03

> 🧪 **QUI 4 beta — bugfix build.** Follow-up to beta9 fixing a chat error on certain protected messages and a ready-check skinning glitch. No schema migrations: your beta9 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Chat no longer errors on certain protected messages.** QUI sized and positioned the main chat window through the game's Edit Mode, which could interfere with chat's own message handling and throw an error when a protected message (such as some channel or system lines) arrived. QUI now manages the main chat window's size and position directly, outside Edit Mode, so those messages display cleanly.
- **Ready-check buttons keep their styling.** The **Ready** / **Not Ready** labels on the ready-check popup could come up unstyled or fail to render, because the game reapplies the button's font when the popup is shown or its buttons enable and disable. QUI now re-asserts the label styling on those events and keeps the button background beneath the text, so the labels always stay readable.

## v4.0.0-beta9 - 2026-06-03

> 🧪 **QUI 4 beta — bugfix build.** Follow-up to beta8 fixing a cold-boot Cooldown Manager buff issue and a preview glitch in the options. No schema migrations: your beta8 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Tracked self-buffs now show after a fresh login without a `/reload`.** A buff whose icon the game only creates once its data has finished loading (for example a self-buff like an Augmentation Evoker's Ebon Might) could be skipped on a cold boot and stay missing from the Cooldown Manager buff container until you reloaded. The container now rebuilds once the Cooldown Manager data has settled, so the icon is ready and appears the moment the buff goes active.
- **Cooldown Manager preview no longer leaves stale icons or bars behind.** In the Cooldown Manager options, switching the live preview between an icon-shaped container and a bar-shaped one (for example from a custom icon group to the Buff Bars) left the previous container's preview frames on screen. The preview now clears those leftover frames whenever the container shape changes.

### Internal
- **Release packaging stamps the version from the release tag.** The packaged `.toc` files now always take their version straight from the release tag, so the in-game version can never drift from the published build. Also retired the temporary cold-boot buff/mirror diagnostics added in beta6 and beta8 now that the underlying issue is fixed. No effect on normal use.

## v4.0.0-beta8 - 2026-06-03

> 🧪 **QUI 4 beta — feature + bugfix build.** Follow-up to beta7 adding per-container border-color controls to the Cooldown Manager buff containers and fixing doubled private-aura text. No schema migrations: your beta7 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Added
- **Border color controls for the Cooldown Manager buff containers.** The **Buff Icons** and **Buff Bars** containers now have their own **Border Color Source** (Inherit / Theme / Class / Custom) and **Border Color** pickers, just like the Essential/Utility cooldown rows. They default to **Inherit**, so they keep following your global skin border exactly as before until you choose otherwise.

### Fixed
- **Private aura stacks and timer no longer render twice.** When a private aura's text scale was set to anything other than 1, its stack count and duration timer were drawn on top of themselves. They now render once, and the private-aura icon no longer sinks behind the health bar on group and player/target/focus frames.

### Removed
- **Private Aura text scale and offset sliders.** These options drove the duplicate-text rendering fixed above and have been retired; private-aura stack/timer text now follows the icon automatically. Existing profiles load fine — the old values are simply ignored.

### Internal
- **Cold-boot buff-container diagnostics.** Added a temporary `QUI_CDM_FORCE_BUFF_REBUILD` helper that forces a clean buff-container rebuild (bypassing the relayout skip caches) to investigate a cold-boot relayout issue. No effect on normal use.

## v4.0.0-beta7 - 2026-06-03

> 🧪 **QUI 4 beta — feature + bugfix build.** Follow-up to beta6 wiring the consumable reminder popup to your configured macros and fixing spell-flyout layering and direction. No schema migrations: your beta6 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Added
- **Consumable Check now follows your configured consumable macros.** When you've set a flask, weapon oil/stone, or augment rune in the consumables options, the reminder popup suggests that same item by default instead of its built-in order. Right-clicking an icon to pick a specific item still overrides the macro for that character. Hunters can now have a weapon **oil** suggested on their bow (the popup previously only offered ranged ammo there).

### Fixed
- **Spell flyouts stay on top and open the right way.** Action-button flyout popups (the fan of buttons that opens from a flyout slot) no longer render behind party/raid frames, and their tint no longer dims the button icons. With direction set to **Auto**, the flyout now opens toward the center of the screen and the little direction arrow always matches the way the popup actually opens — previously the arrow and the popup could disagree.

## v4.0.0-beta6 - 2026-06-02

> 🧪 **QUI 4 beta — diagnostic build.** A small instrumented follow-up to beta5 that exposes the Cooldown Manager mirror API for cold-boot troubleshooting. No functional or visual changes and no schema migrations: your beta5 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Internal
- **Cold-boot Cooldown Manager diagnostics.** Exposed the Cooldown Manager mirror as a global handle so its tracked-bar state can be inspected with a base `/dump` on a fresh login, without the separate diagnostic companion. This is a temporary investigation aid with no effect on normal use.

## v4.0.0-beta5 - 2026-06-02

> 🧪 **QUI 4 beta — bugfix build.** Follow-up to beta4 squashing two WoW 12.0 taint/error bugs and finishing the keyboard click-casting work. No schema migrations: your beta4 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Chat no longer errors on raid warnings and monster emotes.** Channel coloring used to write Blizzard's chat color table directly, which tainted chat dispatch and threw a "secret string value" error when a raid warning or monster yell/whisper arrived. Channel colors are now applied purely at render time without touching any Blizzard global, so the error is gone and your custom channel colors still apply.
- **Opening the World Map by keybind no longer blocks emotes.** Restoring saved positions for protected frames (World Map, Mail) tainted them, which blocked the map's read animation and produced an "action blocked" error. Protected frames are now repositioned through a secure path that no longer taints them.
- **Keyboard click-cast rebinds apply immediately.** Changing a keyboard click-cast key out of combat now takes effect right away instead of waiting for you to re-hover the frame or `/reload`.
- **Click-casting no longer skips party/raid frames while the roster settles.** A momentarily-empty frame slot could cause later frames to be skipped during setup; all frames are now bound reliably.

### Internal
- **Editor-only WoW API language-server definitions.** Added generated Lua language-server type definitions for the WoW client API, widget types, and supporting tooling. These are development aids only — not loaded in-game and not shipped in the release zip.

## v4.0.0-beta4 - 2026-06-02

> 🧪 **QUI 4 beta — bugfix build.** Follow-up to beta3 with group-frame and click-casting fixes. No schema migrations: your beta3 profiles carry over unchanged. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.

### Fixed
- **Click-casting now survives instance zone-ins.** Entering a group instance (e.g. a follower dungeon, where party members are NPCs) grows the party roster and makes the secure frames create their unit buttons after the initial setup pass, so the new party frames had no click-cast bindings until you `/reload`. Click-casting is now re-applied on every roster change (deferred out of combat), so the new frames are bound immediately.
- **Heal-absorb bar respects its own toggle.** The heal-absorb bar is now driven by the Heal Absorbs toggle instead of the Absorb Shield toggle, so it no longer freezes when Show Absorb Shield is turned off.
- **Ready-check icons appear on the initial check.** Frames now show the waiting icon the moment a ready check starts, instead of staying blank until someone responds.
- **Overlays reappear after a settings change.** Absorb, heal-absorb, and heal-prediction overlays are repopulated after any group-frame settings refresh, instead of staying hidden until their next value change.
- **Copy All Settings includes heal-absorb settings.** Heal-absorb options are now copied with the rest of the group-frame visuals instead of being silently skipped.

## v4.0.0-beta3 - 2026-06-01

> 🧪 **QUI 4 beta — internal refactor sync.** This beta brings the QUI 4 line in step with the latest development work: the Cooldown Manager and action bar internals have been split into smaller modules, chrome skinning is centralized behind a shared policy, and release packaging is hardened. These are largely under-the-hood changes — your beta2 profiles carry over unchanged, with no schema migrations. As always, **back up your `WTF` folder before installing** and report anything you hit on GitHub.
>
> **Packaging change:** the release zip now ships **two** folders — `QUI/` and `QUI_Options/` — which must live next to each other in `Interface/AddOns/`. The optional `QUI_Debug` diagnostic companion is no longer bundled in the release.

### Changed
- **Options search surfaces group-frame subtabs.** The in-options search index was refreshed so group-frame settings are found from the search box.

### Internal
- **Cooldown Manager runtime modularized.** The monolithic CDM runtime was split into shared, catalog, resolver, and scheduler modules with dedicated aura, icon, and buff-layout helpers, and the XML load order updated to match. No behavior change intended.
- **Action bars split into env-backed submodules.** Action bar logic was moved into dedicated files with shared cross-file wiring.
- **Centralized chrome skinning and stat tooltip policy.** Chrome palette/backdrop and close-button styling now route through a shared `SkinBase` policy (including the character and inspect panes), and character stat tooltip secret handling is consolidated behind one shared path.
- **Hardened release packaging.** The release zip is now assembled from an explicit runtime file list with required/forbidden-path validation, and the debug companion is dropped from the package.
- Updated structural test guards to match the new module and packaging boundaries.

## v4.0.0-beta2 - 2026-06-01

> 🧪 **QUI 4 beta — bugfix build.** Follow-up to beta1. Still expect rough edges — please report anything you hit on GitHub. **Back up your `WTF` folder before installing.** No schema migrations: your beta1 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Cooldown Manager icons and tracked buffs now bind reliably on a fresh login.** On a cold start the cooldown viewer can report data before it is fully populated; the mirror used to wipe its catalog on that partial read and fail to repopulate, leaving some cooldown icons and tracked buffs blank until a `/reload` or spec swap. The scan is now two-phase — it only commits once a complete read succeeds — and keeps retrying past the initial settle window instead of giving up.

### Internal
- Removed a batch of confirmed-dead code (legacy options widget builders, unreachable scale branches, retired profile keys, an unused import) with guard tests locking in each removal.

## v4.0.0-beta1 - 2026-06-01

> 🧪 **QUI 4 — first beta.** This is the opening beta of the QUI 4 line. It is more settled than the alpha builds, but still expect rough edges — please report anything you hit on GitHub. **Back up your `WTF` folder before installing.** No new schema migrations: your alpha80 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **Aura presets and a reorganized aura indicator editor.** The group-frame aura indicator options are now laid out in two columns with grouped tabs, and you can apply ready-made aura presets instead of configuring every indicator by hand.
- **Border coloring for chat tabs and the damage meter.** The per-module border color controls now extend to chat tab chrome and the damage meter window.

### Changed
- **Aura bars track live duration changes.** Aura bar timers now follow updates to an aura's duration (refreshes and extensions) instead of staying pinned to the original time.
- **Consumable reminders always show on instance triggers.** Entering a triggering instance now reliably surfaces your consumable reminders.
- **`/quiclearspell` is now `/quiclearscan`.** The scanner command accepts a spell **or** item ID, and `/quiclearscan all` wipes everything the scanner has learned.

### Fixed
- **More reliable consumable and trinket buff detection.** The spell scanner now only adopts a buff whose spell ID matches the ability or trinket you actually used. This removes false matches where an unrelated buff landing in the same moment — for example an external buff arriving just as you use a potion — was picked up instead.
- **Click-cast overlay focus and cleanup.** Fixes to how the click-cast overlay takes focus and tears itself down.
- **Custom bars refresh correctly after a layout change.** Custom bar runtime state is now rebuilt after Layout Mode changes.
- **Locked power bars respect Cooldown Manager Edit Mode again.** A stale always-off check was replaced so the locked power bar correctly holds its position while the Cooldown Manager Edit Mode is active.

### Internal
- Consolidated the duplicated deep-copy helpers into one shared, cycle-safe implementation; cached per-tick settings lookups in the skyriding and castbar update loops; and moved chat tab chrome and click-cast buttons onto shared pixel-safe helpers.

## v3.6.0-alpha80 - 2026-06-01

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha79 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Closed another way tracked buffs and cooldowns could come up blank on a cold login.** Building on the earlier cold-login fix, QUI could still capture an empty snapshot of your tracked spells if it ran before the game's Cooldown Manager settings finished loading. Every snapshot path — including the first-login and spec-change paths — now waits for the same readiness signal and retries briefly instead of committing an empty list, so your tracked rows populate without needing a `/reload`.

## v3.6.0-alpha79 - 2026-06-01

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** This build migrates your saved border colors to a new per-module format (schema v40). The upgrade runs automatically on first login and your borders will look exactly as they did before; a one-time backup of the previous values is kept.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **Per-module border color control across many more elements.** You can now choose how each element's border is colored — inherit the global skin color, use the theme accent, use your class color, or pick a custom color — individually for the Minimap, Datatext panels, Minimap button drawer, Chat, Tooltips, CDM icon containers, unit frame castbar (frame and icon), portrait ring, Crosshair, Combat Timer, XP Tracker, Action Tracker (and its icons), Skyriding vigor bar, Prey/Atonement/Brez counters, Rotation Assist icon, M+ Timer, Ready Check, and skin alerts. A new **Border Coloring** page under the skinning options lists every element in one place.

### Changed
- **Existing border settings are carried over automatically.** Older per-module border colors — including the previous "use class color" toggles — are converted to the new color-source format on first login so every element keeps its current appearance.

## v3.6.0-alpha78 - 2026-05-31

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha77 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Tracked buffs and cooldowns no longer come up blank on a cold login.** Right after logging in, QUI waited a fixed two seconds and then built its cooldown display once — even if the game's Cooldown Manager hadn't finished loading yet. When that happened the tracked-buff section could be built from empty data and stay blank until you `/reload`. QUI now waits until the Cooldown Manager actually reports ready (retrying briefly if needed) before building, and any updates that arrive during that window are applied afterward instead of being dropped.

## v3.6.0-alpha77 - 2026-05-31

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha76 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Cooldown icons and bars now pick up linked-buff info that loads after login.** Right after a cold login the game can finish loading a spell's linked aura details a moment later; affected cooldown icons and tracked bars now refresh themselves when that happens instead of showing stale tracking until your next `/reload`.
- **Pixel borders redraw reliably after a UI scale change.** If one bordered frame's edges had gone stale, the scale-change refresh could stop early and leave other frames' borders un-redrawn; the refresh now skips and rebuilds the bad frame so every border updates.

## v3.6.0-alpha76 - 2026-05-31

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha75 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Tracked cooldown auras no longer get cleared right after login.** During a fresh login the game can finish loading its cooldown list before its buff/aura list. QUI now waits for the aura list specifically before pruning, so your tracked auras are no longer briefly mistaken for ones that don't belong to you and shelved.

## v3.6.0-alpha75 - 2026-05-31

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha74 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Cooldown bars no longer flicker to stale defaults right after login.** The built-in cooldown sets are now captured during the cold-load grace window so your saved layout is reconciled against the correct catalog, and the grace window always clears — even when you log in while in combat.
- **Changing the accent color keeps you on the current options subpage.** Adjusting the accent while the options window is open no longer bounces you back to the first subpage of the active section.
- **Spellbook and Adventure Guide text stays skinned as you navigate.** Newly rendered text on later spellbook pages and in Encounter Journal sections now picks up the QUI font and themed color instead of only the text that was visible when the frame first opened.

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha73 profiles carry over unchanged. (If you skipped alpha73 and are upgrading straight from alpha72, the border-color *source* migration is a little smarter about preserving your previous class-colored borders.)
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Chat no longer plays the new-message sound for your own messages.** Lines you send are now matched by sender and skipped, so configured chat sounds only fire for messages from other players.
- **Your explicitly chosen black chat background is respected.** Picking pure black in the chat background color picker now sticks instead of being treated as "unset" and overridden by the skin theme; default chat surfaces still track the skin.
- **Chat lines that arrive while chat is locked down stay correct.** Messages rendered during the game's protected chat path are now tracked so they aren't re-processed once the lockdown clears, avoiding a late re-color of those lines.
- **Damage meter Mythic+ handling respects the disabled state.** The automatic session reset/swap on key start, completion, and abandonment no longer runs when the damage meter is turned off, and key resets (abandoned/restarted runs) are now handled alongside completions.

## v3.6.0-alpha73 - 2026-05-31

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** **Schema migration to v39** — the separate border-color checkboxes are replaced by a single border-color *source* (Theme / Class / Custom) for both the global skin border and tooltip borders. Existing alpha72 profiles upgrade automatically: a genuinely custom border color is kept on **Custom**, while borders that were only tracking your accent or theme preset are restored to **Theme**. The old toggle keys are removed.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **Border color source picker.** The skin and tooltip border-color options now use a single **Source** dropdown — **Theme**, **Class**, or **Custom** — in place of the old "use class color" / "use accent color" checkboxes. The color picker is enabled only when the source is **Custom**.
- **Damage meter Mythic+ handling.** The damage meter can now reset its stored sessions automatically when a Mythic+ key starts (on by default), with an optional swap between your Current and Overall data at key start and completion.
- **More message types in the System chat tab.** SYSTEM tabs now also collect whispers, achievements, system/error/target-marker messages, toasts, and pings; existing tabs pick these up once, automatically. Battle.net broadcast toasts and pings are now shown with QUI's chat decoration too.

### Changed
- **Consistent class colors across the UI.** Class coloring in the damage meter, minimap, cooldown manager, character & inspect panes, tooltips, unit frames, and theme presets now flows through one shared helper that respects any custom class-color overrides you've set.
- **Cleaner damage meter previous-session menu.** Past sessions are listed as plain menu buttons with tidied-up labels — no leftover alert prefix, a sensible fallback name when a fight is unnamed, and the fight duration shown as `[m:ss]`.
- **Resource bar and cooldown-manager bar borders follow your skin border color** instead of always being black, and unit-frame borders now carry their border transparency.

### Fixed
- **Skin, accent, and border color changes apply instantly to far more of the UI.** Many modules previously only picked up a global color change after a `/reload`; the cooldown manager bars, damage meter, Mythic+ keystones, group frames, minimap, combat timer, consumable check, pet warning, resource bars, unit frames, and chat (buttons and the glass background/border/tabs) now all update live.
- **Chat buttons no longer get stuck brightened.** Hovering a chat button and moving away now restores its proper color instead of leaving — and compounding — the highlight.
- **Character pane keeps its themed colors.** Backdrop colors and the selected-tab tint on the character and inspect frames now survive a UI scale change instead of reverting to defaults.
- **Your custom chat background color is preserved** after the skinning rework, while default chat surfaces continue to track the skin.
- **Group/raid frames** now use a more robust hide method (a hidden parent with mouse state restored) in place of the previous scale trick.
- **Cooldown manager** waits until its data is fully available before showing, so it no longer seeds defaults from a half-loaded cooldown list.
- **Selective profile export now includes recently-added settings** — option tooltips, the action tracker, damage-meter skinning, and the new damage-meter category — so a "select all" export no longer silently drops them.
- **Chat reliability in combat.** QUI no longer participates in the game's protected chat-message path and skips its chat text/sound tweaks while chat is locked down, avoiding rare combat-time errors.



## v3.6.0-alpha72 - 2026-05-30

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha71 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Layout Mode now shows only position settings for several movers.** Right-clicking the M+ timer, missing raid buffs, pet warning, ready check, M+ progress, minimap, datatext panel, and other movers in Layout Mode opened their full settings panel instead of just the Position controls. These now show only the position settings plus a link to open their full settings, matching every other mover in Layout Mode.



## v3.6.0-alpha71 - 2026-05-30

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha70 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Hidden frames no longer reappear at login.** Rebuilding a skinned backdrop during the login scale-refresh pass was forcing some intentionally-hidden frames (the loot window and the alert/toast/Battle.net movers) back into view; building a backdrop no longer changes a frame's visibility.
- **No more "Invalid fontHeight" error when skinning certain labels.** A label whose font hadn't finished loading could report a bad size that crashed the skinner; QUI now falls back to the default size in that case.
- **Right-click menus no longer error in some cases.** QUI now skins only the frame and backdrop of modern Blizzard menus and leaves their text untouched, since their font is locked by the game; classic dropdown menus still use the QUI font as before.



## v3.6.0-alpha70 - 2026-05-30

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha69 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Chat no longer errors when a creature speaks near you during combat.** Player names in say, yell, and channel chat are still shown in class colors, but the coloring is now applied to each line as it is printed rather than by changing Blizzard's chat color settings — which on current game versions could break chat with a Lua error the first time a hostile creature spoke in combat.

### Changed
- **More skinned UI text now uses the QUI font** for a more consistent look across skinned Blizzard frames; text colors are unchanged.



## v3.6.0-alpha69 - 2026-05-29

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha68 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **New "Hide Guild Name" toggle in QoL > Tooltip.** Off by default; when enabled, the guild-name line is stripped from player tooltips, matching the existing Hide Server Name option.

### Fixed
- **Skinned frames no longer flash white when the UI scale changes.** Loot, alerts, the Mythic+ timer, the keystone frame, status-tracking bars, the override action bar, and more now keep their themed colors through a scale refresh, and selected options sub-tabs stay tinted instead of briefly turning white.
- **Bonus-roll windows now match the QUI theme.** The roll prompt (dice/pass buttons, item icon, cost, and timer) and the won-loot/won-money toasts are skinned every time they appear instead of occasionally showing up unstyled.
- **Target/focus castbars no longer break the action bars in combat.** Switching targets with a keybind mid-fight could block protected actions and leave parts of the UI stuck; the castbar update is now deferred safely until it can run without interfering.



## v3.6.0-alpha68 - 2026-05-29

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha67 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Cooldowns stay accurate after starting a Mythic+ key, raid encounter, or rated PvP match.** The cooldown manager now re-syncs automatically when the pull begins, instead of needing a `/reload` to keep tracking.
- **Starting a Mythic+ key while already in combat no longer leaves cooldowns missing or stuck.** Recovery is deferred until you drop combat rather than being skipped, so the display catches up on its own.
- **Cooldowns hidden during a loading screen now reappear once the game settles,** instead of staying shelved until your next talent change or a `/reload`.



## v3.6.0-alpha67 - 2026-05-29

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha66 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Changed
- **Auction house & crafting-orders text now uses the QUI font.** Tabs, buttons, and search boxes in these windows match the font used across the rest of the skinned UI.

### Fixed
- **Opening or switching settings tabs no longer freezes the game.** The options window now reuses already-built pages and skips redundant rebuild work, so moving between settings stays smooth even on large pages.
- **Skin-color changes now apply everywhere instantly.** Adjusting your skin color recolors the character pane (including its close button and sidebar tabs), tooltips, and status-tracking bars live, without a `/reload`.
- **Cooldown-manager preview no longer goes blank** after closing and reopening the options window, or tabbing away and back.
- **Auction house & crafting-orders filter buttons display correctly.** The clear/reset (X) button now shows and layers above the filter dropdown as expected.
- **Category lists keep their QUI styling** in the auction house and crafting-orders windows after you select a category or scroll, instead of flashing back to default textures.



## v3.6.0-alpha66 - 2026-05-29

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha65 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Changed
- **Skinning internals consolidated.** The auction house, crafting orders, professions, and instance-frame skins now share a common set of widget stylers instead of each maintaining its own copy, removing roughly 470 lines of duplicated code. Frame-specific behavior is preserved; this is groundwork that keeps future skin fixes consistent across these windows.

### Fixed
- **Instance-frame queue tabs now show which tab is active,** matching the active-tab highlight already used by the other skinned windows.



## v3.6.0-alpha65 - 2026-05-28

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha64 profiles carry over unchanged. The new boss-frame layout keys are seeded from your current boss spacing, so frames stay where they are until you change the grow direction.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **Damage meter: previous-session history.** The damage meter now keeps recorded sessions instead of only the current fight. A session selector lets you switch between the live session and previous ones, with per-session breakdowns routed to the session you pick. Resetting the meter clears the stored sessions and invalidates the cached view.
- **Unit frames: configurable boss frame group layout.** Boss frames can now grow in any of four directions (Up, Down, Left, Right) with independent X and Y spacing, instead of a fixed vertical stack. New Grow Direction dropdown and X/Y Spacing sliders live in the boss-frame appearance settings; the layout-mode mover treats the boss group as one unit.

### Changed
- **Castbar settings apply live, including in combat.** Castbar element changes refresh immediately rather than waiting for a reload, and castbar icon sizing now routes through the shared pixel-aware icon helpers so the icon and its border stay crisp after UI-scale changes.
- **Options surfaces load faster.** Settings tabs are cached and warmed up, and the full-surface render path was tightened to cut redundant work when opening and switching options pages.

### Fixed
- **CDM: pandemic glow is no longer suppressed by the per-spell glow toggle.** A spell's per-spell overlay/proc glow override and its pandemic (aura-expiry) glow are distinct signals; turning off the overlay glow no longer hides the pandemic glow.
- **Item aura removal now refreshes correctly.** Removing an item-based aura updates the affected frames immediately instead of leaving stale state behind.
- **Skinning regressions cleaned up.** World map fill layering and the shopping/compare tooltip header skinning were corrected, and the Blizzard unit-frame castbar suppression path was hardened.



## v3.6.0-alpha64 - 2026-05-28

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** This alpha supersedes `v3.6.0-alpha63`, which shipped the same runtime changes with fallback release notes. No schema migrations; existing alpha62/alpha63 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **Action bars: cooldown duration text controls.** Each action bar now has settings for native cooldown countdown visibility, font size, anchor, offsets, and color, with defaults, copy-bar support, preview coverage, and regression tests.
- **Pixel-scaling regression coverage.** New unit tests lock down scale-refresh behavior, pixel-border call sites, manual backdrop borders, and border refreshes after UI-scale changes.

### Changed
- **Pixel borders now re-snap after scale and display changes.** The shared UI kit queues scale refreshes across multiple ticks, refreshes both registered widgets and pixel borders, and listens for display-size changes so one-pixel borders stay crisp after resolution or UI-scale updates.
- **Skinning uses centralized pixel-aware helpers.** Backdrops, border frames, inset points, tab backdrops, tooltip chrome, character/inspect panes, loot/alert frames, objective tracker, power bars, keystone widgets, and other skinned frames now route through shared pixel-sized border and point helpers instead of raw one-unit offsets.
- **Options and layout surfaces use pixel-sized chrome.** CDM composer popups/context menus, options strip buttons, layout-mode panels, group-frame editors, chat frame settings, dungeon keystone settings, utility keybinds, and related option UI surfaces now use effective pixel sizes for their borders.
- **CDM dormant spell handling is more conservative.** Dormant checks now preserve slot/row/kind metadata, avoid destructive cleanup during zone transitions, restore same-character aura entries more reliably, and keep cross-character or unlearned entries visible for explicit removal instead of silently losing configured rows.
- **Action/resource preview drivers paint more realistic rows.** Action-bar and resource-bar preview paths now reflect the new text controls and avoid empty preview space in embedded composer layouts.

### Fixed
- **CDM custom bars no longer inherit dead stack offsets or stale dormant state.** Dormant spell adds live in `dormantSpells`, custom-bar active entries stay under `entries`, and per-spell hide-duration/hide-stack overrides are reflected by the preview and render paths.
- **Tooltip and skinning borders keep their intended thickness.** Tooltip refits, added-line layouts, manual texture backdrops, and character/inspect pane hardening now keep pixel-perfect borders when the effective UI scale changes.
- **Release notes are back on the changelog-backed path.** The alpha64 tag includes this matching changelog section, so the GitHub release body and release notification use the proper notes instead of the fallback `Release <tag>` text.



## v3.6.0-alpha62 - 2026-05-28

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha61 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **Damage meter: optional row backgrounds.** A new Appearance setting lets you keep or hide the dark trough behind each damage-meter row, with the option included in search.

### Changed
- **CDM: stronger cooldown and aura stack handling.** Cooldown icons now preserve stack text more reliably across mirrored aura states, item auras, trinket/slot entries, charge text, and secret combat values.
- **Options and validation upkeep.** The options search cache was refreshed, and the Lua lint configuration now understands more current client globals so local checks are easier to run cleanly.

### Fixed
- **CDM: aura counts no longer leak, flicker, or show misleading zeroes.** Aura stack text now respects empty display counts, carries mirrored aura stacks only while the aura is active, keeps secret values on safe render paths, and avoids treating equipment slot numbers as spell counts.
- **CDM: cooldown desaturation is more accurate.** Item cooldowns now use the resolved item cooldown duration for greying out instead of falling back to a spell cooldown lane that may not represent the item.
- **Chat history: secret chat metadata no longer drops normal messages.** Guild, raid, and community channel lines can still be captured when the chat type ID is protected; the event payload is used for a safe fallback.
- **Layout, minimap, and utility modules received stability cleanup.** Several frame-positioning, minimap/data text, combat timer, consumable check, action tracker, and unit frame paths were tightened to reduce stale state and improve consistency after reloads or setting changes.



## v3.6.0-alpha61 - 2026-05-25

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha60 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **Mythic+ Mob Progress: nameplate font controls.** The mob-progress nameplate now has a "Text Format" preset dropdown (`+2.5%` / `2.5%` / `2.5` / `Forces: 2.5%`) plus its own Font and Font Size controls, which override the global QUI font when set (leave Font empty to follow the global font).
- **Damage meter: "Reset Data" button.** The window config menu gains a Reset Data action that clears all combat sessions and refreshes the open windows.

### Changed
- **Damage meter: dropped the bar-fill animation.** The optional row bar-fill animation has been removed; it could only ever run on non-secret values, so it never animated in combat anyway, and the instant snap path is now the only path.

### Fixed
- **Damage meter: per-second rate no longer goes to garbage after combat.** The rate now picks the correct duration divisor per session — the live Current session prefers QUI's own combat timer (matching the `[m:ss]` header), Expired sessions use their recorded duration, and Overall uses the API span — instead of leaving the API's per-second value in place where it declassified to a meaningless number once combat ended.
- **CDM: a previous character's spells no longer linger after login.** With a single profile shared across characters the live cooldown container is shared too; on a peaceful login (no combat) the reconcile that re-stamps it for the current character could be skipped, leaving another character's — even another class's — spells rendering until first combat. Login now re-runs spec tracking to self-heal and forces a reconcile when the live container is still owned by a different character.
- **CDM: foreign-class auras cleaned from shared aura containers.** A shared profile could carry a previous character's class auras into the aura containers; these are now stripped on load.
- **Settings: stale options-stub no longer breaks newer setting widgets.** Several settings providers (ready check, M+ timer, M+ mob progress, damage meter) captured an early minimal options stub that the full options module later replaces, so newer label widgets were missing; they now resolve the live options table.

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha59 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **Damage meter: per-target damage breakdown.** The breakdown view now splits a combatant's damage by the target it was dealt to, in addition to the existing per-spell split. Sorting runs through a combat-safe path so the rows stay correctly ordered on protected combat values.
- **Damage meter: window border applies live.** Each window builds a 1px border ring through the shared UI helper, and the Appearance → Colors → Border picker repaints it immediately — the border color now applies without a `/reload`, with a QUI-accent fallback when no explicit color is set.

### Changed
- **Damage meter: long cross-realm names are shortened by default.** A new `shortenNames` option (on by default) trims the `-Realm` suffix from combatant names so cross-realm rows no longer blow out the row width.
- **Layout: corner-drag resize updates the Frame Size sliders live.** Dragging a chat or damage-meter window by a corner grip now re-reads the live dimensions into the Layout Mode Frame Size sliders instead of leaving them on the stale pre-drag value.

### Fixed
- **Chat: the ChatFrame1 size now survives `/reload`.** QUI owns the chat frame size in its own profile and re-applies it on login (deferred so it wins over Edit Mode's layout restore), instead of writing Blizzard's Edit Mode layout — which preset layouts regenerate on load and silently drop, reverting the size every `/reload`.
- **CDM: charge spells no longer flicker to a GCD swipe while recharging.** An active multi-charge recharge now outranks the incidental global-cooldown swipe in both the live and mirror render paths (matching Blizzard's CooldownViewer), so a recharging charge spell keeps its recharge swipe instead of resetting it on every global cooldown.
- **CDM: charge spells no longer desaturate while a charge is still banked.** Charge spells whose recharge reports as continuously active (Putrefy is the reference case) now stay saturated via the secret-safe `wasSetFromCharges` signal, instead of greying out mid-recharge with a charge still available.
- **QoL: Mythic+ auto combat logging no longer stays on after a run.** The in-M+ signal is now gated on actually being inside an instance; the underlying "is M+ active" check can linger true out in the open world after a run, which previously kept auto-logging enabled indefinitely.

### Performance
- **CDM: lower combat memory churn.** Removed the per-refresh trusted-GCD snapshot walk and read the on-GCD flag directly off the cooldown info (it is never a protected value, so the snapshot machinery was unnecessary) — this was the dominant source of combat-time allocation churn in the cooldown path. In-game A/B measured roughly 6–10× fewer cooldown-source calls and ~2.5× lower runtime-event volume per 5-second window.



## v3.6.0-alpha59 - 2026-05-24

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha58 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **Options search now finds module on/off toggles and the damage-meter settings.** The search index was regenerated to seed every module-toggle label plus the full damage-meter settings tab, so typing a module name or a damage-meter option in the options search box jumps straight to it. The damage-meter settings tab now resolves the `QUI_Options` namespace at call time, so it still builds when it loads ahead of `shared.lua` on the search-cache load path.

### Fixed
- **Damage meter: bars no longer collapse to zero-width in combat.** Bar fill and the per-second rate now derive through Blizzard's secret-safe APIs — raw value/max is handed straight to the StatusBar and the rate is computed by Blizzard — instead of ratios computed in Lua, which fault on protected combat values and left "colorless" empty bars.
- **Chat: protected slash commands no longer taint after using the edit box.** Insecure slash commands are kept out of edit-box history (gated on `IsSecureCmd`) and history mutations are guarded against combat lockdown, so protected commands such as `/tm` and `/cast` keep working instead of faulting `ADDON_ACTION_FORBIDDEN`.
- **Action bars: picking up an action from a locked bar no longer taints casting.** The "modified-click picks up instead of casts" logic moved out of an insecure `PreClick` (which tainted the click dispatch and could break `AllowedWhenUntainted` calls like a `/tm` macro's `SetRaidTarget`) into the secure click snippet, with the on-key-down cast state cleared in the pre-body and restored in the post-body.
- **CDM: talent-overridden cooldowns no longer get erased by an incidental global cooldown.** When a talent-replaced slot has no cooldown of its own, casting any other spell put a GCD swipe on the base every global cooldown and wiped the real swipe (Augmentation Breath of Eons is the reference case). A real (non-GCD) cooldown on the base or override now always outranks the GCD — mirroring Blizzard's CooldownViewer `max(realCD, GCD)` behavior — and the GCD-only swipe is used only as a fallback.



## v3.6.0-alpha58 - 2026-05-24

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha57 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **CDM: toggling "Clickable Icons" now takes effect without `/reload`.** When `BuildIcons` reused the existing icon pool (signature match), `AcquireIcon` — which installs the secure click-to-cast attributes — was skipped, so flipping `clickableIcons` on essential or utility containers had no visible effect until the next full rebuild. The reuse path now runs a full secure-attribute pass over every cooldown icon in the pool; the non-reuse path still does a pending-only pass so combat-deferred `PLAYER_REGEN_ENABLED` rebuilds remain cheap.



## v3.6.0-alpha57 - 2026-05-24

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha56 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **CDM: talent-overridden cooldowns no longer freeze on "inactive" after the buff expires.** `C_Spell.GetSpellCooldown` only reports `isActive=true` on the spellID a cooldown was directly initiated on; for talent-replaced slots (Guardian Druid Berserk → Incarnation: Guardian of Ursoc is the reference case) that's the override, not the registered base. Probing only `m.spellID` made the icon fall through to `mode="inactive"` once the aura phase ended, leaving the rest of the 3-minute cooldown invisible. `DeriveMirrorPayloadMode` now falls back to `m.overrideSpellID` and returns the detected spellID so `BuildMirrorRenderPayload` binds the matching `DurationObject` — the base's `DurObj` reflects an inactive cooldown lane and renders no swipe.
- **Damage meter (native): number format no longer flips mid-combat.** `FormatNumber` previously branched on secret state and routed tainted values through `C_StringUtil.TruncateWhenZero`, which emits raw integers — so the same row would render `1.5K` out of combat and `1500` in combat, silently dropping the user's chosen format. Switched to `AbbreviateNumbers` / `BreakUpLargeNumbers` (both `AllowedWhenTainted`), so the same call site works in and out of combat. `BuildValueText` now suppresses `0` at the string layer (`AbbreviateNumbers` returns `"0"`, never `""`) and passes the user's `numberFormat` through to the secondary cell as well — fixing mismatched pairs like `2,400,000 (450)` in complete mode.



## v3.6.0-alpha56 - 2026-05-24

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** **Schema migration to v38** — the legacy `maxVisibleRows` key on saved damage-meter windows is dropped on first load (rows are now scrollable; the window's height alone decides what's visible without scrolling). No user-facing settings move.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **Damage meter (native): scrollable rows.** Each meter window now embeds a ScrollFrame with mouse-wheel scrolling and a thin accent-colored thumb at the right edge that auto-hides when content fits. The previous hard `maxVisibleRows` cap is gone — window height alone decides what renders without scrolling, and everything below the fold is reachable via the wheel. Two-row scroll step per tick.
- **Damage meter (native): sticky self-row.** The pinned-self feature now anchors a real-rank row to the bottom of the window (with a 1px separator above it) whenever the local player scrolls out of the visible viewport, instead of overwriting the bottom visible row. Sticky shares all visuals + click-to-breakdown + hover tooltip with pooled rows via a new `_AttachRowVisuals` helper, and its colors / fonts live-update through `_ApplyColors` and `_ApplyFonts`.

### Changed
- **Damage meter (native): disabling the toggle is instant.** Flipping the Damage Meter feature toggle OFF now despawns every live window immediately (via `WindowManager:DespawnAll`) instead of leaving them on screen until the next `/reload`. The reload prompt still shows, because Blizzard's stock meter can only re-appear at addon-load time — the `damageMeterEnabled` CVar is restored on disable so the stock meter loads next reload.

### Fixed
- **Damage meter (native): clicking a row mid-combat no longer opens an empty popup.** Blizzard secret-tags per-source `combatSpells` while in combat lockdown, so `C_DamageMeter.GetCombatSessionSourceFromType` returns no iterable spell rows and the breakdown popup would render as an empty header. The row click is now blocked during combat, and a hint line ("Spell breakdown is hidden during combat") appears in the hover tooltip. The Data layer's `PLAYER_REGEN_ENABLED` handler re-dirties views 0.5s after combat ends, so the next click populates normally.



## v3.6.0-alpha55 - 2026-05-23

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** **Schema migration to v37** — defunct damage-meter-skinner keys (`db.profile.damageMeter.appearance.global.*` from before the native rewrite) are nilled on first load. User-facing damage-meter appearance values are preserved.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **Damage meter (native): per-window Hide toggle.** Each row in the Windows section now has a Hide checkbox alongside Delete. Hides the window frame; state (type, session, position, overrides) is preserved across reload so you can stash a window without losing its config.
- **Damage meter (native): spec-faithful per-window override UX.** New "Editing Window" selector at the top of the page: "Global" (default — widgets edit shared appearance) or "Window N" (each Appearance widget shows a partner Override? checkbox; widget is greyed when checkbox is OFF, editable when ON; toggling ON copies the current global value into the override, toggling OFF deletes the override key). Switching the editing target rebuilds the page so widget values reflect the new target. Covers every Appearance field (Bars, Fonts as slot-level overrides, Colors, Number Format, Icon Style, Bar Texture). Replaces the prior "Per-Window Overrides" collapsible.
- **Damage meter (native): performance instrumentation.** `/quidmperf on` enables timing of `Data:Refresh`, `Window:Refresh`, and `Breakdown:Refresh`. `/quidmperf` prints avg / p95 / max per kind. `/quidmperf reset` clears buffers. Disabled by default; cost when off is one branch per Refresh call.
- **Damage meter (native): icon-strip animations.** Slide (icons shift one slot per cast) and Fly (new icon flies in from off-screen and fades in) modes for the spell history icon strip. Animation duration is configurable (0.05–0.3s).
- **Damage meter (native): spell history bar-window mode.** A meter-window-shaped display of recent casts as bars (icon + spell name + "Ns ago"). Bar color tints by outcome (failed = red, interrupted = yellow). hideTopBar omits the most-recent entry for streamers. Color modes mirror the main meter window (class / accent / custom); texture mode "match" inherits Window 1's resolved texture. Layout Mode-positionable. Instance-type filtering matches the icon strip.
- **Damage meter (native): session timer anchor-to-window.** New dropdown under Session Timer: "Free (Layout Mode)" or "Anchored to Window N". When anchored, the timer follows the chosen meter window's TOPRIGHT corner each Refresh tick.
- **Damage meter (native): Reset All Sessions keybind.** Now bindable via Esc → Keybindings → QUI Damage Meter → "Reset All Sessions". Also exposed as `/quidmreset` for macro users.
- **Damage meter (native): standalone session timer.** Opt-in big combat-elapsed display configurable in size (12–64px) and color (defaults to QUI accent). Independent 0.25s ticker so the frozen post-combat value shows immediately. Layout Mode-positionable. For streamers / users who want a big timer without meter chrome.
- **Damage meter (native): bar-fill animations.** Optional per-window-overridable smooth lerp on bar widths between ticks. Configurable duration (0.1–0.5s). Off by default for performance.
- **Damage meter (native): spell history icon strip.** Opt-in row of recent player spell icons, configurable size (16–64), count (1–10), opacity, and grow direction (Left/Right/Up/Down). Failed casts render dim. Layout Mode-positionable. Hide toggles for dungeons / raids / out-of-instance. Events register lazily so the feature is genuinely zero-cost when disabled. (Bar-window mode + slide/fly icon animations defer to a future milestone.)
- **Damage meter (native): per-source spell breakdown popup.** Click any row in a meter window to open a small popup listing every spell that source used in the current view, ranked by amount. The popup follows the row by default (configurable to center-of-screen under Behavior > Breakdown Popup Position), mirrors to the other side when it would clip off-screen, refreshes live on the same ticker as the parent window, and dismisses on any outside click. Re-uses the parent window's accent / texture / font / number-format choices.
- **Damage meter (native): multi-window (up to 5).** New "Windows" section in the Damage Meter (Native) settings page lists every spawned window with type/session info, plus a "+ Add Window" button and a [Delete] action per row. Each window saves its own position via Layout Mode and gets its own anchor-registry entry, so other QUI elements can anchor to a specific damage meter window. Per-window appearance overrides are read from `db.profile.damageMeter.native.appearance.perWindow[id]` — editable via the in-window gear / SavedVariables today; full per-window override UI lands in a later milestone.
- **Damage meter (native): meter-type and session switching from the in-window gear.** Click the gear button to open a context menu and switch the window between Damage Done, Healing Done, Damage Taken, Interrupts, Dispels, and Deaths; switch between Current and Overall session. Choices persist across `/reload`.
- **Damage meter (native): hover tooltip.** Hover any row for a tooltip showing class-colored name, class, total (Complete format), per-second, and percent of the top source. Toggleable under Behavior.
- **Damage meter (native): pinned-self row.** When the local player isn't in the visible top-N, optionally show their actual rank/amount at the bottom of the window.
- **Damage meter (native): three new appearance sections.** Bars (bar height, spacing, LSM texture, fill alpha, class color / accent / custom bar color), Fonts (per-element font, size, outline for row name / row value / header), Colors (window bg, header text, row name, row value, border). All settings live-apply via `WindowManager:RefreshAll()` — no `/reload` required.
- **Damage meter (native): number formats.** Minimal (1K / 2M), Compact (1.5K / 2.4M; default), Complete (1,500 / 2,400,000) — selectable under Behavior.
- **Damage meter (native): Refresh Rate (Idle) slider** plus icon style (Spec / Class / None) and pinned-self / hover-tooltip toggles in the Behavior collapsible.

### Fixed
- **CDM composer: Buff Bars preview was invisible after adding spells.** `RefreshBars` in the new preview driver styled bars via `CDMBars.ConfigureBar`, which reads `bar._active`; with the trackedBar default `inactiveMode="hide"` the bar was set to alpha 0 on every refresh. The driver now forces `_active = true` and paints the entry's icon (via `GetEntryTexture`) and spell name (via the newly-exposed `_G.QUI_GetCDMEntryName`) — `ConfigureBar` is settings-only and never bound the icon/name in the preview path. Regression locked in by `cdm_composer_preview_driver_test` T10.
- **Damage meter (native): meter-type integer mapping bug.** Phase 2 hardcoded `{[0]="Damage Done", [1]="Healing Done", [2]="Damage Taken", ...}` but Blizzard's `Enum.DamageMeterType` integers don't match that order (verified: `HealingDone=2`, `Dps=1`, `Deaths=9`). Picking "Healing Done" in the gear menu was actually fetching Dps data; "Interrupts" was fetching AvoidableDamageTaken; etc. Now the label table is keyed by enum name and resolved to integers at module load via `Enum.DamageMeterType[name]`, so we're robust to Blizzard reordering the enum.
- **Damage meter (native): `MarkCurrentDirty` missed types beyond 7.** The Phase 1 implementation hardcoded a `for t = 0, 7 do` loop that marked types 0–7 dirty on `DAMAGE_METER_CURRENT_SESSION_UPDATED`. Since the real enum spans 0–10, Dispels / Deaths / Absorbs windows weren't getting their dirty flag set and were stale until the next per-type event fired. Now iterates `pairs(Enum.DamageMeterType)` to pick up whatever Blizzard exposes.

### Changed
- **Damage meter (native): gear-menu type list expanded** from 6 to all 11 types Blizzard's `C_DamageMeter` surfaces — adds **DPS**, **HPS**, **Avoidable Damage Taken**, **Enemy Damage Taken**, and **Absorbs**. DPS / HPS views re-sort sources by per-second (not total), which gives a meaningfully different ranking from Damage Done / Healing Done in uneven combats. Every view shows both metrics: primary value large, secondary in parens (e.g. Damage Done row reads `2.4M (180K)`; DPS row reads `180K (2.4M)`).
- **Damage meter (native): hover tooltip anchor** flipped from "above row" to "below row" to match spec language ("Anchored TOP to row's BOTTOM").
- **Damage meter (native): color schema migrates to array form `{r,g,b,a}`** to round-trip cleanly through QUI's `GUI:CreateFormColorPicker`. Two Phase-1 consumers (`Window:New` backdrop and `_SetRowSource` bar color) updated to read array indices. No `core/migrations.lua` bump required — Phase 1 only wrote literal defaults and no live user had customized native colors yet.
- **Damage meter: replaced Blizzard-meter skin with a native QUI implementation built on `C_DamageMeter`.** A single damage meter window now ships out of the box, suppressing Blizzard's stock meter via the `damageMeterEnabled` CVar. The window is positionable via Layout Mode and shows live damage-done with class-colored bars. Existing appearance-related saved settings (`db.profile.damageMeter.appearance.global.*`) are preserved; defunct skinner-era keys are nilled by schema migration v37. See `docs/features/damage-meter.md`.



## v3.6.0-alpha54 - 2026-05-21

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha53 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **CDM: mid-cast swipe blip on long casts** (e.g. Mind Blast). The runtime now holds gcd-only mode through casts whose cast time exceeds the GCD; previously `UNIT_SPELLCAST_SUCCEEDED` fired after the GCD ended, leaving an ~80ms gap where the swipe vanished mid-cast.
- **CDM: 1/1-charge spells now show their cooldown swipe.** Charge-duration probe is now gated on an active recharge with `maxCharges>1`, not just charge capability — 1/1-max spells carry a charge capability but their real cooldown lives on the spell cooldown.
- **CDM: custom-bar icons get click-to-cast secure attributes.** `UpdateIconSecureAttributes` now reads settings under `ncdm.containers[viewerType]`, and the post-rebuild pass no longer gates custom bars out.
- **Totems bar: hidden bar no longer eats world clicks.** Left-click on ground / right-click camera control return when the bar is alpha-hidden. `EnableMouse` now tracks alpha via centralized `ShowContainer` / `HideContainer` helpers with `pcall`-guarded toggles for combat.
- **CDM cold-login: catalog no longer freezes with stale viewer data.** At PEW the cooldown viewer could be empty/stale, leaving cross-category mirror binds (e.g. Death's Advance) permanently unbound until `/reload` or spec swap. Adds an availability gate, a 2s `PLAYER_LOGIN` grace window, a coordinated cold-load reconcile, and a debounced post-`OVERRIDE_UPDATED` reconcile.
- **CDM composer: "not in /cdm" warning reflects what's actually enabled.** Derives the red-tint signal from Blizzard's `CooldownViewerSettings` data provider rather than the API category set. Adds a red "!" badge, tighter red tint, mirrored signal in the Add list, and `OnDataChanged` cache invalidation.
- **CDM composer: bag items no longer duplicate.** `GetUsableItems` de-dupes by `itemID`, keeping the highest profession quality rank so multiple stacks of the same consumable produce one Items-tab entry.

### Changed
- **CDM per-spell duration text override** renamed `showDurationText` → `hideDurationText` so a composer override can force-hide independent of row default (and force-show to override a row-level hide). Bar renderer honors the override on item/aura paths; containers plumb `hideDurationText` / `hideStackText` / font from row config.

### Internal
- CDM composer entry-cell tooltips now show spell/item ID.
- Test stub: `GetSpellOverride` added to the `CDMSpellData` mock for `cdm_bars_label_test`.



## v3.6.0-alpha53 - 2026-05-21

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha52 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **Frame skinning phase 3 — 11 new Blizzard frames covered.**
  - Inventory: **Bank**, **Merchant**, **Mail**, **GuildBank**.
  - Social: **Friends**, **Guild**, **Communities**, plus the **Journal** (Encounter / Mounts / Pets / Toys).
  - World content: **Achievement**, **WorldMap**, **WeeklyRewards**.
  - Tabs on the four phase-3 frames pick up the new SkinBase tab pattern (selected-state highlight, hover restore, theme-color refresh).
- **Bonus Roll mover gets a proper Position panel.** Layout-mode right-click on the bonus-roll anchor now shows the standard Position section (anchor target, from/to point, X/Y offsets) instead of an empty panel.

### Fixed
- **Profession specialization tabs now render their selected state.** `StyleSpecPoolTab` was passing nil as the owner to `HookTabHover` / `RestoreTabVisual` (it referenced `specPage` as an undefined upvalue), so spec tabs always looked inactive even when selected.
- **Inspect frame skinning no longer no-ops on a casing typo** (`controlFrame` vs `ControlFrame`). Silent since the file was first written.
- **Keystone affix iteration walked the wrong table** and produced no styling. Also silent since the file was first written.
- **Professions close button** hides the Blizzard X chrome and uses the QUI accent + label.
- **10 alert subsystem hooks wired up** (achievement / loot / level-up alerts that had registration sites but no actual `hooksecurefunc` on the relevant `Setup*` callbacks).
- **WorldMap backdrop now covers the map canvas** and fills from the border on the LOW frame strata (so it sits behind the map without occluding pins).
- **FriendsFrame tabs and four other phase-3 frames** had Blizzard tab textures bleeding through; the SkinBase tab helpers now strip those textures and override the tab text color.
- **TopTileStreaks** regression from the `HidePortraitFrameChrome` extraction is restored.
- **CDM charge-cycle frame**: corrected the charge-cycle resolver state when an item's max-charges drops mid-cycle.
- **Chat clear-all is now deferred** until the next frame, so it doesn't race with in-flight message inserts.

### Internal
- **Vendored FrameXML snapshot** under `tests/framexml/` to back the skinning gap audit and template lookups. Ships in tests-only paths — not included in the release zip.
- **New SkinBase composers**: `SkinBase.SkinCloseButton`, `SkinBase.SkinButtonFrameTemplate`, and SkinBase tab helpers. `HidePortraitFrameChrome` was extracted into `SkinBase` and extended to cover `BasicFrameTemplate`.
- **12 ScrollBox callsites migrated** to `ScrollUtil.AddAcquiredFrameCallback`, replacing ad-hoc `hooksecurefunc(scrollBox, "ForEachFrame", …)` patterns.
- **Settings theming pass** across the QUI_Options surfaces to align with the new skinning helpers.



## v3.6.0-alpha52 - 2026-05-21

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha51 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Cooldown range-color alpha now applies.** A duplicate `rangeColor` key in the cooldown container default factory was silently dropping the alpha channel.
- **Glow text overlay stays anchored above the cooldown swipe.** The highlighter path had a thinner duplicate of EnsureGlowAboveCooldown that skipped the text-overlay re-anchor step; both paths now share one implementation.
- **Tracked cooldown bars prefer the QUI-owned viewer** over the Blizzard `BuffBarCooldownViewer` fallback when both are available.
- **Corrupted-profile `inactiveMode` falls back to `hide`** instead of `always`, matching the missing-setting branch.
- **Plugged several global leaks** in the CDM render path (`ids` in `cdm_domain.GetOrderedSpellMap`, bare `_` in the runtime resolver) that were writing to `_G` every tick.

### Performance
- **CDM glow scans no longer allocate per icon per frame.** `EvaluateGlowForIcon`, `ScanAllGlows`, and `ScanGlowsForSpell` now gather candidate spells into a reused scratch table instead of constructing fresh closures via `ForEachSpellCandidate` / `ForEachIconSpellID` on every pass.

### Internal
- Added a reentry guard (`_rebuildGlowSpellMapInFlight`) around `RebuildGlowSpellMap` so the wipe → repopulate invariant survives any future recursion through `AddIconToGlowMaps`.
- Drove `modules/cdm/` luacheck warnings from ~520 down to ~140 with no behavior changes: expanded `.luacheckrc` for WoW client globals exposed by the consolidation, removed dead `ok = true` scaffold left over from prior `pcall` removal, dropped 34 `ADDON_NAME` residues, deleted unused locals/tables/helpers, and collapsed redundant empty-if chains.
- Removed the dead `SetHostPandemicState` no-op stub and its four caller sites; pandemic glow flows through `cdm_frame_writes.GetPandemicCurve`.
- Trimmed `ResolveMirrorStackText` from a 6-tuple to a 5-tuple (the unused `mirrorIsCharge` return is gone) and dropped the `previousInitSafeWindow` shadow inside the PEW handler.



## v3.6.0-alpha51 - 2026-05-20

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha50 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Cooldown icons that combine a cooldown with an aura overlay now refresh in the correct phase.** The cooldown DurationObject is captured at hook time so the swipe and aura overlay stay in sync.

### Changed
- **CDM cooldown/charge classification was rewritten around a single 4-mode contract.** Icon rendering, mirror payload building, and finalization now share one mode resolution path instead of scattered cascade branches — fewer surprises when cooldowns, charges, and auras overlap on the same spell.

### Internal
- Consolidated the CDM module surface: legacy icon factory, runtime, scheduler, and policy files were folded into `cdm_icon_renderer`, `cdm_runtime`, `cdm_domain`, and `cdm_frame_writes`.
- Removed orphaned charge-resolver helpers after the cascade collapse; moved tests under `tests/unit/` and lifted fixtures into `tests/fixtures/{current,edge,legacy}/`.
- Added regression coverage for blizz-mirror cooldown capture, debug cdtest details, runtime events, runtime query cache, aura priority integration, and the memaudit addon profiler.



## v3.6.0-alpha50 - 2026-05-18

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha49 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Action bar cooldown and charge refreshes now reuse short-lived runtime state instead of requerying every button on each event.** Active cooldown DurationObjects and inactive buttons are cached with tight combat-safe TTLs, while secret boolean fields are decoded through the C-side curve path before driving visibility decisions.
- **CDM spell, item, aura, usability, and mirror refreshes now target only the affected icons when possible.** Event handlers defer combat refresh work through scoped queues, avoid broad full walks for item/equipment/usability changes, and keep layout draining tied to actual icon updates.
- **Target aura mirror cooldowns now reject non-owned target aura data before binding aura DurationObjects.** This prevents mirrored target aura entries from borrowing another unit's aura timing while preserving owned target aura refreshes.

### Changed
- **CDM runtime query caches now retain stable override lookups and transient cooldown/charge reads during combat batches.** Duration binding keys are cached separately from secret-sensitive source comparisons, reducing churn without comparing secret values.

### Internal
- Added regression coverage for action bar cooldown/charge caching, CDM runtime query caches, scoped cooldown refresh targeting, GCD deduping, mirror refresh targeting, and stack resolution.



## v3.6.0-alpha49 - 2026-05-18

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha48 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **CDM aura and charge cooldown resolution now keeps timer lanes stable across aura, recharge, and GCD states.** Aura-backed cooldowns prefer secret-safe DurationObjects, recharge swipes stay in their charge/resource lane, and stale aura or pandemic state is cleared before falling back to normal cooldowns.
- **CDM item sources now preserve scanned item aura entries and quality variants.** Usable item candidates are ordered consistently, scanned item registrations survive refreshes, and dormant unlearned entries stay available for composer rows.
- **Chat channel shortening and temporary chat-tab filtering now avoid combat-sensitive mutations.** Rendered channel text can still be shortened while protected chat frames and temporary tabs avoid taint-prone state changes.
- **Aura-related frame paths now avoid unsafe secret-value decisions.** Buff borders, unit frames, and group-frame aura indicators use guarded state handling for combat-safe updates.

### Changed
- **CDM debug and renderer paths now expose more precise GCD and cooldown state diagnostics.** Debug traces include richer cooldown resolution details, and bar labels/statusbar timers follow the same resolved runtime state as icons.

### Internal
- Added regression coverage for aura cooldown application, item-quality source ordering, scanned item aura registration, spellscanner item registration, channel shortening, temporary chat-tab filtering, GCD styling, statusbar timers, and cooldown resolver state transitions.



## v3.6.0-alpha48 - 2026-05-17

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha47 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **CDM charged aura cooldowns now keep aura overlays and active recharge swipes in the correct lane.** Utility cooldown entries with captured auras prefer the aura DurationObject when aura display is enabled, fall back to charge timers when disabled, and clear stale pandemic/aura state when resolving back to recharge.
- **CDM multi-charge availability now decodes secret current-charge counts through a C-side curve path.** Recharge swipes can remain visible without treating spells with charges remaining as unavailable, while zero-charge states still desaturate correctly.
- **Chat rendered text transforms now avoid taint-sensitive in-place mutation.** Keyword alerts and redundant-text cleanup run through safe rendered-line transforms without touching protected chat internals during combat.

### Changed
- **CDM cooldown runtime internals were split into resolver, policy, runtime-query, and runtime-store modules.** Custom bars, stack text, range, visibility, and mirror identity now route through shared runtime state instead of scattered icon-factory logic.

### Internal
- Added regression coverage for CDM resolver/runtime policies, charged aura recharge handling, stale aura/pandemic clearing, secret charge-count decoding, debug event-trace fallback paths, and chat rendered-transform taint safety.



## v3.6.0-alpha47 - 2026-05-15

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha46 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **CDM mirror cooldowns now prefer live charge DurationObjects for active multi-charge spell recharges.** Active recharge swipes stay in the charge/resource lane even when the mirrored cooldown payload is stale, GCD-only, or cooldown-backed.
- **Cooldown-backed multi-charge CDM mirrors now resolve as charge timers without requiring visible charge-count proof.** The mirror keeps the secret-safe charge DurationObject and avoids falling back to ordinary cooldown timing.

### Internal
- Added regression coverage for live charge DurationObjects overriding mirror GCD payloads and cooldown-backed multi-charge mirror resolution.



## v3.6.0-alpha46 - 2026-05-15

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha45 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **CDM mirror cooldowns now treat charge lanes as authoritative only when Blizzard exposes visible charge count state.** This prevents one-charge or uncounted charge-flagged cooldowns from being downgraded into resource timers while preserving real recharge timers.
- **Mirror-backed CDM icons now clear stale stack text on bind and keep active charge mirrors in charge mode.** Empty mirror stack state no longer leaves old count text behind, and active recharge swipes no longer fall back through inactive spell cooldown state.

### Internal
- Added regression coverage for uncounted charge-flagged mirror cooldowns, stale mirror stack clearing, unbound mirror stack authority, and active charge mirror mode.



## v3.6.0-alpha45 - 2026-05-15

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha44 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Extra Action Button and Zone Ability hide-artwork toggles now keep saved anchoring aligned.** When artwork is hidden, QUI sizes the holder from the visible button footprint before reapplying the frame anchor, preventing edge and corner anchors from appearing offset.

### Internal
- Added regression coverage for hide-artwork holder sizing on special buttons.



## v3.6.0-alpha44 - 2026-05-15

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha43 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Extra Action Button and Zone Ability anchoring now recovers after Blizzard moves the shared Extra Abilities container.** QUI watches the shared container as well as the individual special-button frames, then reapplies both saved holder anchors instead of leaving Blizzard's position in control.

### Internal
- Added regression coverage to require shared Extra Abilities container hooks for both special buttons.



## v3.6.0-alpha43 - 2026-05-15

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha42 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **Extra Action Button and Zone Ability can now be configured from Action Bars > Per Bar.** Both special buttons have dedicated Enabled, Hide Artwork, Scale, positioning, and full-settings controls without copying incompatible regular bar settings into their saved data.

### Fixed
- **Options keyboard handling avoids restricted propagation writes in combat.** Pressing ESC still closes the options panel, but the handler skips `SetPropagateKeyboardInput` while locked down.
- **Game menu skinning keeps its visuals on addon-owned overlays during combat.** Button labels, hover state, borders, and background fills now render through high-layer overlay textures/text instead of mutating Blizzard button font strings, textures, or hook scripts during lockdown.
- **Cursor reticle layering stays above other tooltip-level overlays.** The reticle now uses a stable high frame level and keeps the GCD swipe above the ring frame.

### Internal
- Added regression coverage for special-button per-bar settings, combat-safe options keyboard handling, combat game-menu skinning, and reticle layering.



## v3.6.0-alpha42 - 2026-05-15

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha41 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **CDM cooldown swipes now render for one-charge spells that Blizzard flags through the charge path.** Mind Blast, Prayer of Mending, and linked spell aliases now fall back to the real spell cooldown DurationObject instead of treating a `0/1` charge payload as a recharge timer.

### Internal
- Added regression coverage for one-charge Blizzard mirror cooldowns, linked Prayer of Mending cooldown aliases, and the custom cooldown resolver path used when buff/debuff phase display is disabled.



## v3.6.0-alpha41 - 2026-05-15

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha40 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **CDM no longer shows false stack text from spell cast counts.** Mirror-backed cooldown icons now only use Blizzard mirror stack/charge text or the real multi-charge display path, preventing non-charge abilities from showing cast-count values as stacks.

### Internal
- Added regression coverage for mirror-backed cooldown icons whose spell cast count is non-zero but whose charge API reports no charges.



## v3.6.0-alpha40 - 2026-05-15

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha39 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **CDM entries can now be cleared in one action.** The entry context menu includes a Remove All Entries command that clears active, dormant, removed, and spec-tracked entries for the current container.

### Fixed
- **Extra Action Button and Zone Ability positions stay in sync with Layout Mode anchors.** Dragging or nudging these holders now updates both the action-bar position settings and the shared frame-anchoring data, then reapplies the saved anchor after size refreshes.
- **Action bar anchoring no longer falls back to raw Blizzard frames before QUI owns safe containers.** Layout Mode now waits for QUI-owned action bar containers instead of moving Blizzard-managed bars directly.
- **Bonus Roll anchoring waits until Blizzard finishes showing or moving the prompt.** Saved anchors are reapplied on the next frame instead of inside the Show/SetPoint hook.
- **CDM reset seeds respect cooldown row capacity.** Reset entries are assigned across active rows by configured capacity, and overflow entries are shown separately instead of collapsing everything into the first active row.

### Internal
- Added regression coverage for extra/zone button anchor sync, action bar resolver taint safety, deferred bonus roll anchoring, and CDM reset/clear-all behavior.



## v3.6.0-alpha39 - 2026-05-15

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha38 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Minimap waypoint pins stay on the minimap after `/reload`.** The addon button drawer now rejects numeric minimap pin/node frames before applying broad minimap button-name matching, while still collecting normal addon launcher buttons.

### Internal
- Added regression coverage for minimap drawer frame classification so pin-style minimap frames are not collected into the drawer.



## v3.6.0-alpha38 - 2026-05-15

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha37 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Changed
- **Character pane settings moved from Gameplay to Appearance.** The Character page now sits next to Skinning in Appearance, and related navigation/search routes were updated for the shifted Appearance and Gameplay sub-page indices.

### Fixed
- **Disabling the Character module restores Blizzard-native character and inspect surfaces.** Character frame skinning now leaves the native stats pane readable when QUI's replacement pane is off, and inspect skinning/overlay paths honor the master Character module toggle instead of leaving QUI-owned inspect overlays active.

### Internal
- Regenerated the options search cache for the updated Character page routes.
- Added regression tests for Appearance > Character navigation and native character/inspect fallback behavior when the Character module is disabled.



## v3.6.0-alpha37 - 2026-05-15

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha36 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Chat frame size sliders no longer recurse into a C stack overflow.** ChatFrame1 size writes now short-circuit when the requested width and height already match the live frame, so slider refreshes and initialization do not re-enter Blizzard sizing, Edit Mode persistence, or the slider sync hook.
- **ChatFrame1 sizing now persists through Blizzard Edit Mode layout data.** Width and height changes from full settings, Layout Mode drawer controls, and Layout Mode corner grips route through the shared ChatFrame1 sizing helper, preserving legacy chat dimensions while also saving the live Edit Mode layout.

### Added
- **Chat Frame Width and Height controls are available in Layout Mode.** The Chat Frame drawer now resolves to the main chat feature and renders the same Frame Size controls as the full chat settings page, matching the damage meter Layout Mode sizing pattern.

### Internal
- Added regression coverage for ChatFrame1 Edit Mode size persistence, no-op resize writes, and Layout Mode drawer sizing metadata.



## v3.6.0-alpha36 - 2026-05-15

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha35 profiles carry over unchanged. Per-loadout CDM entries are additive and disabled by default.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **Per-loadout CDM entries.** CDM can now maintain separate spell lists for each saved talent loadout within a spec. The new "Per-Loadout Entries" toggle preserves shared data when disabled, seeds the active saved loadout on first enable, and swaps entries on loadout changes without using ephemeral active-config IDs.

### Fixed
- **CDM reset/import seeding now distinguishes "ready but empty" from "not ready yet."** Blizzard-tracked category data is read through the settings data provider when available, unlearned tracked spells can appear in the add list, and empty tracked categories no longer fall back to stale snapshot data.
- **Character and inspect pane skinning is more resilient.** Bottom tabs are styled consistently, selected-state visuals refresh after tab changes, inspect tabs initialize even when the frame already exists, and character-pane geometry is applied immediately while only decoration/stat refresh work is deferred after combat.
- **Character and inspect item overlays use structured tooltip data with secret-value guards.** Item level, upgrade, socket, and enchant reads avoid unsafe string/number handling and are more tolerant of missing or delayed item data.
- **Profession tab and filter styling preserves functional child controls.** Filter dropdown clear buttons are no longer stripped, tab hover/selected visuals are restored cleanly, and color refresh updates the stored skin data.
- **Tooltip extra info lines no longer depend on right-side double-line measurement.** QUI-added target, mount, rating, spell ID, icon ID, item ID, and player item-level rows now render as colored single lines, avoiding layout refit issues and secret-value right-edge reads.
- **Damage meter windows reapply saved sizes after reload or external size resets.** Saved dimensions are restored after session-window setup and after safe size changes outside layout mode.
- **Boss-frame range alpha is less jumpy.** Range changes now require confirmation before alpha flips, nil/unchecked range results leave the current alpha alone, and cached range state clears on world/combat/spec transitions.

### Internal
- Profile fixtures cover the new CDM loadout storage shape and legacy upgrade path.
- New regression tests cover per-loadout CDM persistence, unlearned CDM add-list entries, frame tab skinning, character/inspect pane hardening, tooltip refit/layout safety, damage meter reload sizing, and boss range alpha stability.
- Added a SavedVariables inspection helper for diagnosing profile snapshots.



## v3.6.0-alpha35 - 2026-05-14

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha34 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **Hover tooltips on game hyperlinks in chat.** Hovering an item, spell, achievement, quest, currency, recipe, talent, mount, toy, transmog, etc. link now anchors `GameTooltip` at the cursor with the link's details and clears it on leave. QUI's own addon-link types are excluded (they still respond to click). Failure to render a tooltip silently hides instead of stranding the previous one.

### Fixed
- **Banish/restore for Blizzard's `BuffFrame` and `DebuffFrame` uses parent reparenting instead of `Show` / `SetAlpha` hooksecurefuncs.** The old approach permanently tainted the frames' dispatch tables; the new path reparents to a hidden frame, snapshots the original parent / alpha / mouse / `ignoreFramePositionManager` into a `Helpers.CreateStateTable()` side-table, and restores from that snapshot on disable. Combat-gated so neither operation runs during lockdown outside the init safe window.
- **URL detection in chat is stricter and recognizes Discord invites.** URLs are now only highlighted at word boundaries (whitespace / opening paren or bracket / quote / `<`) and trailing punctuation (`.,;:!?)]}>` ) is stripped from the link before it's wrapped, so "see https://example.com." becomes a clickable `https://example.com` followed by the period instead of `https://example.com.`. `discord.gg/invite`, `discord.com/invite/code`, and `discordapp.com/invite/code` are also detected without an explicit `https://` prefix.
- **Top-positioned chat editbox stays invisible until you press Enter.** The editbox itself is now alpha-driven (not just the backdrop), and focus state is tracked through `editBoxState[editBox].hasFocus` rather than `editBox:HasFocus()` (which is unreliable across editbox swaps). The backdrop and editbox visibility stay in lockstep on focus gain / loss.
- **Temporary chat tab chrome geometry no longer depends on `tab:GetWidth()`.** Reading the tab's width could surface a secret value and produce a chrome-width math result that QUI couldn't safely forward to `SetWidth`. The backdrop now anchors `BOTTOMRIGHT` to the tab with a negative `sizePadding` offset, so the visible chrome trims away Blizzard's whisper-icon reserve without computing a width from a possibly-secret tab size.

### Internal
- New regression tests: `buffborders_blizzard_banish_taint_test`, `chat_editbox_top_focus_test`, `chat_hyperlink_tooltip_test`, `chat_tab_secret_geometry_test`, `chat_url_detection_test`.



## v3.6.0-alpha34 - 2026-05-14

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha33 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **GCD swipes on cooldown-kind icons no longer get recolored as aura swipes** when a live aura on the player happens to match the spell. The effect-classification path now treats the resolver's `_resolvedCooldownMode` as authoritative for cooldown-kind icons (gcd-only / cooldown / charge / item-cooldown / inactive); the live aura probe and `icon._auraActive` fallback only fire for buff/aura entries or when the resolver has not yet produced a mode. Stops a CooldownFrame currently bound to a GCD DurationObject from being repainted with aura colors and edge styling mid-swipe.

### Internal
- New regression test asserts that a `_resolvedCooldownMode = "gcd-only"` cooldown-kind icon keeps the GCD swipe styling (no edge, cooldown swipe color + alpha) even when `IsAuraCurrentlyActive` would have returned true for its spellID.



## v3.6.0-alpha33 - 2026-05-13

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No schema migrations; existing alpha32 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Cooldown icons no longer flash Blizzard's ready-glow.** The native CooldownFrame "bling" is now disabled at icon creation and on every native-widget reshow; QUI's own glow / highlight systems remain the single source of cooldown-ready feedback. The native flash was especially visible after short GCD bindings and HUD visibility transitions.
- **Skyriding speed text shows current movement speed when not actively gliding.** Previously it displayed the glide-physics number even on foot. While gliding, the glide speed is still used. If the engine returns a secret or nil value, the text hides itself instead of printing garbage.
- **Vigor-charge protection no longer blanks an active glide.** The "treat `canGlide` as false when Vigor's `maxCharges` is secret" safety check now only fires when the player isn't already gliding. Fixes passenger / ride-along edge cases where the in-flight HUD could vanish mid-glide.
- **Player and target absorb-bar sizing no longer treats active shields as part of max health during the clamp.** The absorb calculator captures its attached/overflow split with `MaximumHealthMode.Default` first; the switch to `WithAbsorbs` happens after, scoped to the group's visibility curve. Visible absorb portion now reflects real missing HP, while the bars still appear when there are absorbs at full HP.

### Added
- **Breakpoint indicators on Primary and Secondary Power bars.** New "Breakpoint Indicators" collapsible under each power bar's settings panel: enable toggle, line thickness slider, color picker, and three per-spec value entries. Stored values are normalized, deduped, and sorted on save; non-numeric or non-positive entries are dropped.

### Internal
- Skyriding speed helpers (`ResolveDisplaySpeed`, `FormatSpeedText`) lifted onto `QUI.Skyriding` for headless testing. `BASE_MOVEMENT_SPEED` falls back to a literal `7` when the global is absent.
- Power-bar indicator settings use a transient string-keyed proxy for the form edit boxes so the persisted shape stays a sorted number array, with the current spec resolved at save time.
- New regression tests: `cdm_icon_factory_bling_test`, `resourcebars_breakpoint_settings_test`, `skyriding_speed_test`, `unitframes_absorb_clamp_order_test`.



## v3.6.0-alpha32 - 2026-05-13

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; the legacy `cdmLearnedCastToAura` global is cleared on first load (see below).
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Send Mail and Open Mail movers no longer trip `ADDON_ACTION_BLOCKED` while interacting with mail.** Both panels are now treated as `secureFrame`: a watcher frame drives anchor reassertion instead of `HookScript("OnShow")` / `hooksecurefunc` on the root, so the mover's hooks can't taint the protected call chain that the mail UI runs after `ShowUIPanel`.
- **Cooldown bars keep their countdown text running when they reappear mid-cast.** The status-bar timer is re-armed via `SetTimerDuration` on show, and the duration text is written from `DurationObject:GetRemainingDuration` rather than read off the bar's `value` (which is secret in combat). A deferred-one-frame re-arm covers the case where the bar's `OnShow` fires before its size is final.
- **Aura-tracked cooldown icons and bars no longer drop stack text and harmful/helpful state in combat.** The Blizzard mirror was nil'ing `auraInstanceID` / `auraUnit` / `auraData` at the payload boundary; they now flow end-to-end into the icon/bar result tables. Secret values are still C-side-only — Lua reads (`spellId`, `isHarmful`, `icon`) go through `IsSecretValue` + `SafeValue` guards rather than ok-flag sentinels.
- **Resolver refuses to bind an entry to a mirror cooldown whose spell identity doesn't match.** `MirrorStateMatchesEntryIdentity` now compares the entry's `overrideSpellID` / `spellID` / `id` against the mirror state's `spellID` / `overrideSpellID` / `overrideTooltipSpellID` / `linkedSpellIDs` before accepting the bind. Prevents cross-binds when two configured entries collide on the same Blizzard cooldown frame.
- **Buff icon container wakes itself on layout refresh.** `RequestBuffIconLayoutRefresh` now calls the container's `Show()` (subject to the anchor's hidden flag) so a freshly-added icon doesn't sit invisible until something else forces a repaint.

### Changed
- **Removed the `cdmLearnedCastToAura` SavedVariable.** Cast→aura correlation is now runtime-only — `UNIT_SPELLCAST_SUCCEEDED` + `UNIT_AURA` correlation within the 100ms window still resolves `auraInstanceID` for cast-keyed trackers, but it no longer persists. The legacy global (and any stale entries from previous sessions) is wiped on `Initialize` and on every `RebuildSpellToCooldownID`. Catalog-derived aura links from `C_CooldownViewer` are unaffected.

### Internal
- **AuraStamp event tracing logs full target/state context.** Stamp attempts, accepts, and rejects (`owner` / `no-unit`) now print target cooldown ID, viewer category, child-frame source, aura instance, spell IDs, and aura name. `/cdmevents` icon summary lines include the matched mirror state (cooldownID, spell identity, linkedSpellIDs) so cross-bind investigations don't need a debugger.
- **StatusBar timer renderer hardened.** Uses interpolation=0 (immediate) and direction=1 (remaining); the renderer pcalls `SetTimerDuration` and drops the prior `SetMinMaxValues` call (the timer drives the range internally).
- **Aura-scoped per-icon resolve API.** `CDMIcons.ApplyAuraScopedResolvedCooldown` runs `ApplyResolvedCooldown` + container visibility + (for buff-viewer entries) a buff layout refresh, scoped to a single icon — used by aura/auraBar event handlers in place of the broader sweep.
- New regression tests: `blizzard_mover_mail_taint`, `cdm_bars_show_rearm`, `cdm_debug_event_trace_mirror`, `cdm_renderers_statusbar_timer`, `cdm_spelldata_ignores_learned_cast_to_aura`.



## v3.6.0-alpha31 - 2026-05-13

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing alpha30 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Damage-meter source breakdown popup no longer trips taint in combat or on combat-restricted source IDs.** Clicking a source row that resolves to a secret `sourceGUID` / `sourceCreatureID` — or trying to open the popup while in combat lockdown — used to drop into `C_DamageMeter.GetCombatSessionSourceFromType` / `…FromID` with tainted arguments and throw. QUI now bails out of the popup-open path under those conditions and closes any already-open popup if combat starts with it visible.
- **Session list no longer faults on the `totalAmount` compare in `BuildDataProvider`.** The stock data-provider build read `combatSource.totalAmount` in Lua to short-circuit a redundant popup refresh; that field is secret in restricted contexts. The replacement build skips the compare and just marks the popup stale when there's a focused source.
- **Totem-summoning buffs that don't enumerate by slot pick up their duration via a frame-side fallback.** When the conventional totem-slot walk misses a cooldown (some buff-only summons), the mirror now reads `preferredTotemUpdateSlot` / `totemData.slot` off the matched child and forwards `GetTotemDuration(slot)` so the swipe still tracks the buff.
- **CDM mirror text refreshes are now targeted per-icon instead of a global sweep.** Stack / aura state changes refresh only the affected icon's cooldown text rather than running `UpdateAllCooldowns` on every pulse.
- **Mirror no longer registers its own UNIT_AURA handler** — it consumes the pipeline from `cdm_spelldata`, so aura events scan once per pulse instead of twice.

### Added
- **Per-event icon profiler in `/qui cdm_cache`.** When tracking is enabled, the slash command prints the top icon events by cost (ms/sec, calls/sec) for the recent window, so combat hot spots show up in-game without an external profiler.

### Internal
- Damage-meter source-window focus state moved off Blizzard frames onto a `Helpers.CreateStateTable()` side-table. Taint-safer; cleanup is automatic via weak keys.
- `QUI_Debug` performance monitor renamed its primary target field and pinned its metric thresholds against a regression test.



## v3.6.0-alpha30 - 2026-05-12

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing alpha29 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Added
- **New option: "Show Buff/Debuff Phase on Cooldown Icons"** (Effects → Swipe, default **on**). When enabled, cooldown icons show their linked buff/debuff phase before switching to recharge or cooldown — restoring the pre-alpha29 behavior. Disable it to keep alpha29's strict cooldown-only swipe on cooldown viewers.

### Changed
- **Damage-meter skinning dropped its secret-safe entry-display overrides** (the replacement `UpdateName`/`UpdateValue`/`UpdateIcon`/`UpdateStatusBar` shims plus pcall wrappers around `GetThumb`/`GetScrollBar`/`GetLocalPlayerEntry`). They weren't catching real faults in practice; the per-instance UpdateBackground / UpdateStyle skin hooks are unchanged. Smaller surface, less per-frame work.



## v3.6.0-alpha29 - 2026-05-12

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing alpha28 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Totem-summoning self-buffs now render the totem's duration on the swipe**, not whatever aura happens to win the buff lookup. The aura-viewer mirror prefers the active totem duration when there is one for that cooldown ID — so Mana Totem, Healing Stream, etc. count down to the actual totem expiry.
- **Cooldown viewers no longer show aura/totem timers on the cooldown swipe.** The cooldown swipe now strictly reflects recharge / cooldown state; aura uptime stays in the aura viewer where it belongs.
- **Composer's "Not usable on your current class" entries clear themselves after a spec or hero-talent swap.** Dormancy reconciliation now runs on `PLAYER_SPECIALIZATION_CHANGED` and `SPELLS_CHANGED` (debounced 0.35s) and on every preview refresh — no need to close and reopen the composer to make stale Reaper's Mark / Festering Wound entries fall off.
- **Totem slot scan uses the dynamic slot-count API** (`GetNumTotemSlots`) instead of a fixed `MAX_TOTEMS + 1` probe. Picks up classes whose slot count differs from the constant without an extra probe, and reports the actually-scanned count in taint logs.

### Performance
- **Removed defensive aura-cache rescans at combat / encounter / M+ / PvP boundaries.** `auraInstanceID` is treated as stable per the current Blizzard documentation, so the cache no longer rebuilds on `PLAYER_REGEN_ENABLED`, encounter starts, or zone-in / login bootstrap. Event-driven eviction (removed-aura validation against `GetAuraDataByAuraInstanceID`) plus `isFullUpdate` rescans cover the same ground without the burst at every boundary.

### Internal
- **Damage meter skinning drops unnecessary `SecureCallMethod` wrappers** on plain frame methods (`SetText`, `SetSize`, `Hide`, `Show`, `SetMovable`, `SetResizable`, `SetWidth`, `SetHeight`). These targets aren't secure-handler frames, so the wrapper was free overhead.
- New regression tests cover the aura/totem/cooldown-viewer lane selection and the composer's spec-change reconciliation.



## v3.6.0-alpha28 - 2026-05-12

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing alpha27 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Alts that share an AceDB profile no longer overwrite each other's CDM spec data.** Two characters on the same QUI profile now each have their own per-spec owned/dormant/removed spell lists. Logging in or switching specs on a shared profile no longer imports another character's spell set, and the next save no longer clobbers the one you weren't logged into.
- **Combat /reload on a shared profile keeps the cooldown manager visible.** The legacy profile-side spec cache is still trusted during combat lockdown (when the character key can't be resolved yet), so the layout refreshes immediately and then migrates to the per-character store once player identity is known.



## v3.6.0-alpha27 - 2026-05-12

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing alpha26 profiles carry over unchanged.
>
> **Reminder: QUI ships as three folders — `QUI/`, `QUI_Options/`, and `QUI_Debug/`.** All three must live next to each other in `Interface/AddOns/`. The release zip already contains all three.

### Fixed
- **Icons no longer get stuck greyed out during proc windows.** When a proc (e.g. Festering Scythe substituting for Festering Strike) held Blizzard's mirror cooldown active after the underlying spell was actually usable, the icon stayed desaturated for the full proc window (12+ seconds) and `procOnUsable` glows were suppressed. The resolver now treats the live cooldown API as authoritative — if the underlying spell reports usable, the icon lifts immediately.
- **Icons no longer stay greyed out for seconds after a real cooldown ends.** Previously, if a GCD chain started the instant the real CD finished, the icon stayed desaturated through the entire GCD-after-CD-end window (often 3+ seconds visible). GCD-only swipes now correctly clear any leftover cooldown desaturation.
- **Stopped a per-tick flicker** on usability tints (range / not-enough-resources greying) when a stale numeric duration cached on the icon was being misread as "still on real cooldown."

### Performance
- **Removed a UNIT_AURA-driven full-refresh storm during combat.** A defensive fallback was scanning every icon on most player aura events (rune CDs, hidden state auras, talent procs — most of which CDM doesn't track), producing an `UpdateAllCooldowns` sweep on nearly every combat aura pulse. Player/pet aura updates now only touch the icons whose instance IDs actually changed.

### Added
- **`/cdmevents` write-probe instrumentation.** When event tracing is enabled for a spell, QUI now also hooks the icon's texture and cooldown writes (`SetVertexColor`, `SetDesaturated`, `SetAlpha`, `SetSwipeColor`, `SetDrawSwipe`, `SetDrawEdge`) and prints each write with its previous value. Diagnostic only — no cost when tracing is off.



## v3.6.0-alpha26 - 2026-05-12

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing alpha25 profiles carry over unchanged.
>
> **Heads up: this release adds a third folder, `QUI_Debug/`.** It's load-on-demand — it only loads when you run `/qui debug`, so retail users pay zero startup cost. The release zip already contains all three folders (`QUI/`, `QUI_Options/`, `QUI_Debug/`). Drop them into `Interface/AddOns/` side by side.

### Fixed
- **Cooldown swipes now follow a strict priority — aura, then charges/recharge, then cooldown, then GCD.** Previously the wrong timer could win in mixed states: a real cooldown could hide an active aura, or a GCD pulse could overwrite a real cooldown swipe. The priority is now locked end-to-end across the mirror and resolver.
- **Buff viewers render swipes correctly for guardian-summoning self-buffs** like Raise Abomination and Army of the Dead. The buff timer is now surfaced as the swipe duration instead of dead-ending blank.
- **Cooldown swipes no longer disappear when you drop or change targets mid-fight.** Target-debuff spells (Soul Reaper, Reaper's Mark, Festering Wound, etc.) stay lit while still on cooldown, instead of the swipe being wiped on target change.
- **GCD pulses no longer get mis-classified as real cooldowns** on spells that happen to have a base cooldown entry in the catalog.
- **Stack counts on Blizzard mirror icons stop getting clobbered** when both the mirror and the resolver report a count.
- **Combat /reload no longer leaves the cooldown manager invisible** until combat ends. Spec ID now falls back to the cached value during the addon-load window so the layout can refresh immediately.
- **Death Charge (and other override-spell IDs) resolve correctly** to the base ability in your spellbook, so the icon picker recognizes them as known.
- **No more visible full CDM reset on every combat exit.** The aura pipeline no longer force-pushes a refresh from combat / encounter / M+ / PvP end.

### Performance
- **Major reduction in raid-combat allocations.** Pooled scratch tables replace per-tick closures and temporary tables in the resolver, mirror, and icon factory hot paths — multi-MB/s of garbage in raid combat eliminated.
- **Events now refresh only the icons they can affect.** Aura events touch aura icons, item events touch item icons, etc., instead of sweeping every icon every time. Cuts cross-scope flicker on unrelated cooldown-only spells.
- **Blizzard API queries are cached within a tick** so each one is hit at most once per pass.
- **Per-spell range and usability refresh** replaces the global range OnUpdate poll.

### Added
- **QUI_Debug companion addon (load-on-demand).** Diagnostics, memaudit, performance profiling, and the aura/CDM probes moved into a sibling addon that only loads when `/qui debug` is enabled. Zero startup cost for retail users.
- **Right-clicking a mover in Layout Mode now opens its settings panel on first use.** Options addon loads automatically when needed.

### Internal
- Full Lua test suite now runs on every push and PR (new `lua-tests.yml` workflow).
- 30+ new regression tests covering the fixes above (aura priority contract, target-change cooldown preservation, GC churn refactors, scoped event resolves, mirror identity, GCD dedupe).



## v3.6.0-alpha25 - 2026-05-10

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing alpha24 profiles carry over unchanged.
>
> **Reminder: QUI ships as two folders — `QUI/` and `QUI_Options/`.** Both must live next to each other in `Interface/AddOns/`. The release zip already contains both.

### Fixed
- **Cooldown manager no longer errors on combat-secret aura stacks.** Aura entries with stack counts that Blizzard marks secret in combat (boss debuff stacks, encounter-only buffs) used to throw a "secret value compared" error inside the runtime state cache. The cache now treats secret values as "unknown" and refreshes safely, so those icons stay live through the encounter.



## v3.6.0-alpha24 - 2026-05-10

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing alpha23 profiles carry over unchanged. v3.5.x → alpha24: back up `WTF/` and export your profile first.
>
> **Reminder: QUI ships as two folders — `QUI/` and `QUI_Options/`.** Both must live next to each other in `Interface/AddOns/`. The release zip already contains both.

### Changed
- **Cooldown icons no longer fight Blizzard's hidden cooldown viewer.** QUI now observes Blizzard's viewer state without taking over its frames — the QUI icons render natively in every case, with fewer visibility glitches and fewer taint paths.
- **Spells that live in multiple viewer categories now track independently.** A spell that has both a cast (essential) and a tracked buff/bar entry used to share one state and last-write-wins between them; each entry now keeps its own duration and updates separately.

### Fixed
- **GCD swipe is no longer hidden by a stale cooldown.** When a spell is ready (or off cooldown) but still inside its global cooldown window, the GCD swipe shows instead of the previous cooldown lingering on the icon.
- **Stuck "active" cooldown swipes that lingered after a spell came off cooldown** clear as soon as live state catches up, instead of waiting for the next event.
- **Charged spells that are fully recharged show the GCD swipe during use** instead of going blank between casts.
- **Real cooldowns longer than the GCD remain visible** during the GCD window — they keep showing their own cooldown swipe even while the GCD is active.
- **Target debuffs that Blizzard files under multiple cooldown IDs** (cast in essentials + buff in trackedBar) stay bound to the right entry through every refresh, instead of swapping or going blank.

### Internal
- `/qui cdm_cache` now reports Blizzard mirror state counts, runtime store entries, and stale-mirror skip counters — useful when triaging cooldown-display reports.



## v3.6.0-alpha23 - 2026-05-09

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing alpha22 profiles carry over unchanged. v3.5.x → alpha23: back up `WTF/` and export your profile first.
>
> **Reminder: QUI ships as two folders — `QUI/` and `QUI_Options/`.** Both must live next to each other in `Interface/AddOns/`. The release zip already contains both.

### Added
- **Per-frame aura filter and sort settings on Buff Borders.** Each frame (player buff, target buff, target debuff, focus debuff, etc.) now exposes its own filter checkboxes — Buffs: PLAYER, RAID, CANCELABLE, NOT_CANCELABLE, BIG_DEFENSIVE; Debuffs: PLAYER, RAID, INCLUDE_NAME_PLATE_ONLY, RAID_PLAYER_DISPELLABLE, IMPORTANT, CROWD_CONTROL — and a sort dropdown (Default, Expiration, Expiration only, Name, Name only, Big Defensive, API order) plus a Reverse toggle. Defaults are unchanged (all flags off, sort = API order) so existing profiles look identical.
- **Optional `ignoreGCD` parameter on `Helpers.ApplyCooldownFromSpell`.** Internal API addition — used by the rotation-assist and reticle modules to render the GCD swipe correctly.

### Changed
- **Faster CDM container layout refresh.** The sync and async paths in RefreshAll now share a single `RunPostLayoutRefresh` helper instead of duplicating the same post-layout work twice.
- **Rotation Assist:** the "Cooldown Swipe" toggle is now labeled **"GCD Swipe"** — the swipe it drives is always the global cooldown, and the previous label implied the spell's own cooldown.

### Fixed
- **Permanent / durationless auras (stances, forms, pet-presence indicators, perma buffs) no longer flicker.** They reliably stay shown without a countdown swipe. Previously they oscillated active/inactive and never visually settled.
- **Late-bound CDM icons now appear on first cast.** Some Blizzard cooldown entries (Death Knight DT buff, etc.) are created lazily when the relevant aura first applies — those icons used to stay permanently empty until `/reload`. They now bind on the spot when Blizzard publishes the entry.
- **Talent-renumbered spell IDs bind correctly.** Saved entries pinned to a pre-override spell ID now still find their cooldown when Blizzard's runtime override changes the ID (e.g. apex talents).
- **Pandemic refresh glow is continuous through combat.** A defensive nil-return in the in-combat aura duration query was flipping `_auraActive` off whenever a duration query had a transient miss between UNIT_AURA ticks; the glow now stays on through those misses.
- **Group-frame backdrop updates no longer emit taint warnings.** Health-update repaints route the backdrop fill color through `Texture:SetVertexColor` instead of `BackdropTemplateMixin:SetBackdropColor` — silences ~80+ taint events per session on the raid frames.
- **Tooltips no longer clip their content in combat.** The chrome-refit's Y-axis measurement now anchors off the last text line directly, instead of comparing every line's bottom coordinate (which errored on combat-restricted secret coords and silently no-op'd, leaving tooltips clipped).
- **Absorb / heal-prediction bar visibility** is now driven by a step curve evaluated C-side, removing a defensive `pcall` against secret values on every health update.
- **GCD swipe renders correctly on the rotation-assist and reticle icons.** The shared cooldown helper used to short-circuit on the GCD spell itself; now those callers explicitly request "include GCD" and get the full sweep.



## v3.6.0-alpha22 - 2026-05-08

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** New schema migration (v36) splits the per-container pandemic-glow toggle in two; existing profiles auto-migrate with both halves enabled. v3.5.x → alpha22: back up `WTF/` and export your profile first.
>
> **Heads-up: this alpha ships as two folders — `QUI/` and `QUI_Options/`.** Both must live next to each other in `Interface/AddOns/`. The release zip already contains both.

### Added
- **"Open QUI" entry in the Blizzard Settings panel** — loads the full options on first click.
- **Per-aura-type pandemic glow.** Each container now has separate "Debuffs/DoTs" and "Buffs/HoTs" toggles. Existing profiles keep current behavior with both enabled.
- **Channel Colors.** New chat options section lets you recolor any channel by name; custom colors follow the channel across rejoins.
- **Per-channel exclusion checkboxes** replace the old free-form editbox in the persistent history settings.

### Changed
- **Settings UI loads on demand.** The options panel was extracted into a sister addon, `QUI_Options`, that doesn't load until you open it — faster login and lower idle memory if you never open settings.
- **Character / Inspect gear panels build widgets lazily** on first open.
- **Action bars: lower idle CPU.** Cooldown scans throttle to ~5Hz out of combat; in-combat updates unchanged.
- **Group frames:** snappier aura rendering, up to **5 defensive icons per frame** (was 1), and zero per-frame aura cost when you're solo.
- **Chat history loads faster on `/reload`.** Storage split into a hot recent slice plus older chunks; only what's needed is decoded.
- **Skyriding:** Thrill of the Skies buff probe replaced with a direct spell-ID lookup instead of scanning 40 buff slots every tick.

### Fixed
- **Cooldowns and aura icons are way more reliable.** Stuck "always on" states gone, durationless auras (stances, forms, permanent buffs) display, and target debuffs that Blizzard mis-files (Virulent Plague, Dread Plague) route to the correct unit.
- **Anti-Magic Zone, totems, and split buff/debuff entries** light up correctly whether the aura sits on you or your target.
- **Reaping and similar Blizzard cooldowns** without their own swipe duration now show the swipe.
- **`/reload` during combat** no longer leaves Blizz-backed cooldowns blank until combat ends.
- **Target switching** clears previous-target debuffs instantly — no more swap lag in PvP / dungeons.
- **Always-mode icons** stay at full opacity instead of dimming when their aura is absent.
- **Permanent buffs no longer flash a stuck pandemic glow.**
- **Pandemic-glow dropdown changes apply immediately** instead of waiting for the next cooldown tick.
- **Damage meter skin survives** lowering the window's background opacity.
- **BonusRollFrame stays where you put it** — Blizzard's per-roll re-position no longer wins.
- **Chat editbox no longer left unskinned** after `/reload` in combat / M+ / encounters / PvP.



## v3.6.0-alpha21 - 2026-05-05

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing v34 profiles carry over unchanged. v3.5.x → alpha21: back up `WTF/` and export your profile first.

### Added
- **Appearance > Damage Meter sub-page** with user-pickable LSM textures (bar, background, border) and fonts (row name, row value, header — each with size + outline) on top of QUI's existing meter skin. Promotes the damage meter settings out of the Skinning page collapsible into a dedicated sub-page; the Skinning page no longer references the damage meter. Defaults use sentinel values (nil/0/_inherit) so existing rendering for row text is preserved on upgrade. Header text now uses the QUI general font on default install (deliberate — matches the rest of QUI's text). Live preview is wired through `RefreshAll`, which re-runs the skin pipeline and restyles the four header-area fontstrings (session timer, session/type dropdowns, minimize-container hint).

### Changed
- **CDM owned engine: full data-decoupling from Blizzard's Cooldown Manager.** Runtime path is now data-independent of Blizzard's CDM viewers. The composer is the authoritative spell catalog; `cdm_resolvers` owns runtime event publication on an internal bus; consumers (`cdm_icons`, `cdm_bars`, `cdm_icon_factory`, `glows`) subscribe instead of reading viewer children. Blizzard's Cooldown Manager is no longer hidden by QUI — to hide it, disable the Cooldown Manager in Blizzard's Edit Mode. Pandemic glow now uses a curve-driven gold flash texture (the C-side path required to keep secret-userdata alpha out of LCG primitives).
- **CDM owned engine: less idle CPU on range/glow polls and the OOC safety tick.**
  - Range gate (`UpdateIconVisualState`) and glow check (`IsSpellCastable`) now read the resolved override spell ID off `icon._runtimeSpellID` instead of resolving it via `TickCacheGetOverrideSpell` on every poll. The cooldown event path already writes `_runtimeSpellID` on every refresh, so this just stops re-resolving the same value.
  - `SafetyTickOnUpdate` now early-returns when out of combat. Nothing the safety tick is meant to catch (cooldown events, aura updates, override flips) can change OOC without an event firing, so the tick was running its full body at idle and producing tick-cache allocation churn for unchanged state.
- **Action Bars settings preview no longer refreshes while the panel is hidden.** `RefreshPreview` was hooked to `ACTIONBAR_SLOT_CHANGED`, which fires ~10/s even at idle, so the hidden panel was running its full preview update continuously. The `OnEvent` body now gates on `self:IsVisible()`; the existing 0.25s `OnUpdate` already keeps an open panel current.
- **New load-profiler memprobes for Action Bars cooldown work.** `ns._memprobes.AB_cooldownEvents` / `AB_cooldownBatches` / `AB_cooldownButtons` let the profiler attribute action-bar cooldown CPU — events received, throttled batches actually run, and per-button `ApplyCooldown` invocations.



## v3.6.0-alpha20 - 2026-05-05

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing v34 profiles carry over unchanged. v3.5.x → alpha20: back up `WTF/` and export your profile first.

### Fixed
- **GCD swipe now shows on every same-spell cast.** (Resolves the known issue called out in alpha19.) Same-spell back-to-back casts shared the dedupe key `gcd-only:<sid>`, so `ApplyResolvedCooldown` short-circuited and left the cooldown frame bound to the previous pulse's already-expired timer — visually, the swipe stopped firing on subsequent casts of the same ability. The dedupe state is now invalidated at known per-pulse signals (`UNIT_SPELLCAST_SUCCEEDED`, plus the full-walk branch of `SPELL_UPDATE_COOLDOWN` that covers the GCD spell, GCD-flag flips, and arg-less fires) so the next pass takes the bind path. Real-cooldown and aura dedupe paths are unaffected (real CDs already had distinct keys per pulse; auras dedupe on DurationObject userdata identity).



## v3.6.0-alpha19 - 2026-05-05

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing v34 profiles carry over unchanged. v3.5.x → alpha19: back up `WTF/` and export your profile first.

### Known issues
- **GCD swipe rendering on CDM icons can behave inconsistently right now.** The shared GCD swipe (the brief 1.5s sweep that overlays icons during the global cooldown) is showing up on the wrong icons or not at all in some configurations. This is a pre-existing issue and is being tracked for a follow-up alpha — the event-scoping work in this build is unrelated. If you want to mute the symptom in the meantime, disable Show GCD Swipe under each affected CDM container's settings.

### Added
- **Channel-shorten Number preset now actually drops to the channel number.** Previously the Number preset was identical to Letter and numbered chat channels (`CHAT_MSG_CHANNEL`) were out of scope. Both presets now handle numbered channels:
  - **Letter** abbreviates the channel name: `[1. General]` → `[Gen]`, `[2. Trade - Stormwind]` → `[T]`, `[4. Trade (Services)]` → `[S]`. Falls back to the first three alphanumeric characters for unknown / custom channels.
  - **Number** drops the name and keeps just the number: `[1. General]` → `[1]`.

  Built-in abbreviations cover Blizzard's standard channels (Trade, LFG, Guild Recruitment, etc.) before falling through to the 3-character rule.

### Changed
- **Login is dramatically faster on populated chat histories.** Eager prune on each `FCF_Close` fire previously decompressed and re-encoded the full chat history blob; Blizzard fires `FCF_Close` ~15 times during chat layout restoration at login, costing ~9s of CPU on a populated history. The hook now queues frame IDs + close timestamps and folds the prune into the existing 5-minute / `PLAYER_LOGOUT` flush. **Measured on a chatty character: `ADDON_LOADED` → `PLAYER_LOGIN` gap dropped from 9.2s to 1.9s; QUI CPU during login dropped from 7.4s to 0.07s. FCF_Close hook total: 9001ms / 15 fires → 0.1ms / 15 fires.** The cross-contamination guarantee is preserved — entries belonging to a closed frame are still dropped before the next SV write, so a recycled slot on next login won't replay stale content.
- **CDM event handlers scoped to reduce raid-combat GC churn.**
  - `UNIT_SPELLCAST_*` events now register via `RegisterUnitEvent("...", "player")` instead of unit-agnostic, cutting other-unit cast traffic in raid.
  - `SPELL_UPDATE_COOLDOWN` with a non-nil, non-GCD spell ID now scopes to matching icons through a new per-spellID dispatch path; the full pool walk only runs when the event fires with no spell ID, with the GCD spell ID, or when the icon's GCD flag flipped.
  - `SPELL_ACTIVATION_OVERLAY_GLOW_*` and `UNIT_SPELLCAST_SUCCEEDED` also use scoped resolves.
  - Highlighter consolidated to dispatch from the central CDM event frame instead of registering its own `UNIT_SPELLCAST_SUCCEEDED`.
- **`TickCacheGetOverrideSpell` / `TickCacheGetDisplayCount` no longer short-circuit on secret returns** — the cache now stores and serves them so secret-bearing spell IDs stop hitting the C API on every call.

### Fixed
- **Chat tab clicks no longer get eaten in top-mode chat layouts.** When the edit box is positioned at the top of the chat frame, it shares the strip with the chat tabs. Blizzard sometimes leaves the edit box shown (chatStyle `im`, `lockShow`, sticky channels) which left an invisible-but-mouse-enabled frame eating tab clicks. The unfocused top-mode edit box now disables mouse so clicks fall through to the tabs; mouse is restored on focus, on bottom-mode config, and on edit-box style teardown.



## v3.6.0-alpha18 - 2026-05-04

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing v34 profiles carry over unchanged. v3.5.x → alpha18: back up `WTF/` and export your profile first.
>
> This alpha picks up several fixes from the v3.5.7 / v3.5.8 stable line that hadn't yet landed on the v3.6.0 alpha track.

### Added
- **Buff Overlay Color controls on aura-type CDM containers.** The Buff Overlay Color mode + custom swatch were previously only surfaced on cooldown containers, even though the keys are consumed for buff icons. Both controls are now exposed alongside the Buff/Debuff Swipe toggle in the aura container's Effects card.

### Fixed
- **Buff/Debuff Swipe toggle (added in alpha17) was wired to the wrong DB key.** The aura-container Effects panel wrote `showBuffSwipe`, but `swipe.lua` reads `showBuffIconSwipe` for buff-viewer icons — so toggling the new control had no effect. Rebound to the correct key.
- **Buff icon stack text now stays above icon borders** instead of being clipped/occluded by them. (Backport from v3.5.8.)
- **Raid frame sorting stabilized.** Resolves jitter in raid frame ordering during composition changes. (Backport from v3.5.8.)
- **Selective profile export now includes `layoutMode` and `optionsPanelCollapsibleStates`.** Two lazy-created profile keys (mover handles / snap / side panel state, and which options-panel sections you have collapsed) were missing from the export categories, so a Select-All export silently dropped them. Both now travel with the export under their correct categories. (Backport from v3.5.8.)



## v3.6.0-alpha17 - 2026-05-04

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing v34 profiles carry over unchanged. v3.5.x → alpha17: back up `WTF/` and export your profile first.
>
> This alpha decomposes the 8157-line `modules/cooldowns/owned/cdm_icons.lua` into three focused files (resolvers + factory + view). Behavior is intended to be unchanged — the headless profile harness is green and luac is clean — but if you see a CDM regression compared to alpha16, please report the spell + container so we can check the right layer.

### Added
- **"Cooldown Swipe" toggle on aura-type CDM containers.** The aura-container Effects panel previously short-circuited to the pandemic-glow checkbox only, leaving no UI surface for disabling the swipe animation on aura entries. There's now a Cooldown Swipe card with the `showBuffSwipe` checkbox above the existing Effects card. (Setting is profile-global.)

### Changed
- **CDM owned-engine internals split into three files:**
  - `cdm_resolvers.lua` (new, ~970 LOC) — pure resolution layer with no frame writes. Owns the per-tick cache subsystem, identity/texture/macro/classification resolvers, and the DurationObject resolver group.
  - `cdm_icon_factory.lua` (new, ~1400 LOC) — pool lifecycle + the per-tick `UpdateIconCooldown` driver. Allowed to write frames.
  - `cdm_icons.lua` (slimmed by ~27%) — view layer: `ConfigureIcon`, aura binding, expiry timers, Blizz texture mirror.

  Load order: `cdm_spelldata.lua` → `cdm_resolvers.lua` → `cdm_icon_factory.lua` → `cdm_icons.lua`.

### Fixed
- **CDM aura icons no longer hold a stale duration on refresh.** The dedupe key for aura-mode `ApplyResolvedCooldown` matched on `auraInstanceID`, which is preserved across refreshes, so the resolver's freshly-fetched DurationObject was never bound and the swipe stayed on the original (now-stale) duration. The dedupe now also compares `durObj` userdata identity for aura mode (Blizzard returns a new userdata wrapper on refresh), matching the pattern already used in `cdm_bars.lua`.
- **Layout Mode no longer clamps the chat frame to the screen.** ChatFrame1's mover was inheriting the framework default that prevents dragging past the edge — overridden in the chat element's `onOpen` so the chat can be positioned partially off-screen if desired.



## v3.6.0-alpha16 - 2026-05-04

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing v34 profiles carry over unchanged. v3.5.x → alpha16: back up `WTF/` and export your profile first.
>
> **Heads-up: this alpha adds a new `SavedVariablesPerCharacter` file (`QUI_ChatHistory`).** Existing chat history stored in the previous account-wide AceDB slot is migrated automatically on first login per character — no action required, but the legacy slot is left in place as a safety net.

### Added
- **Persistent chat history is now stored per-character in a separate SavedVariables file** (`QUI_ChatHistory`), as a single AceSerializer+LibDeflate-encoded blob that's decoded on demand. Idle Lua heap drops from O(all-characters × all-entries) to one compressed string per character — large historical snapshots that previously contributed ~150 MB of resident memory should no longer balloon the addon's footprint.
- **"Max stored messages" slider** in the Persistent History section caps the FIFO retention at 500–50000 entries (default 5000). The pre-existing edit-box recall slider was relabeled to **"Max command history"** to disambiguate.
- **"Clear all characters" button** next to the per-character Clear in Persistent History. Walks every character's storage slot (both the new SV and any unmigrated legacy slots) and reports the totals it cleared. Routed through `GUI:ShowConfirmation` with destructive styling.
- **Copy popup source dropdown** in the History section. Surfaces the existing `chat.copyHistorySource` setting as a UI control with two values: *Live* (current chat scrollback, default) or *Persisted* (full saved history). Gated by the Persistent History toggle.
- **Static combat-taint analyzer** under `tools/` plus a CI workflow (`.github/workflows/taint-check.yml`) that runs it on every PR. `modules/cooldowns/` and `modules/chat/` are configured as *strict* — any new analyzer warning fails CI. Driven by a vendored Blizzard API-docs index in `tests/api-docs/`.

### Changed
- **History buffer now flushes on a 5-minute timer and at `PLAYER_LOGOUT`** rather than every event, applying the time-prune + entry cap together. Live captures still go to a session buffer immediately so reload-replay is unaffected.

### Fixed
- **Five taint-prone patterns flagged by the new analyzer** were corrected across cooldowns and chat code. (Internal hardening; no specific user-visible symptoms reported, but reduces the surface area for future combat-taint regressions.)



## v3.6.0-alpha15 - 2026-05-04

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing v34 profiles carry over unchanged. v3.5.x → alpha15: back up `WTF/` and export your profile first.

### Fixed
- **CDM aura icons no longer flicker mid-encounter when the in-combat aura query races with the next tick.** When the resolver returned "inactive" for an aura-mode icon during combat but the cached aura DurObj still matched the last known binding, the icon would briefly clear and re-bind on the next tick. The pipeline now holds the last good aura DurObj across that single-tick race and lets the resolver re-converge naturally. Also re-evaluates the resolver inline on the aura-bind path so the new DurObj is applied immediately instead of one event later.



## v3.6.0-alpha14 - 2026-05-04

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing v34 profiles carry over unchanged. v3.5.x → alpha14: back up `WTF/` and export your profile first.
>
> This alpha rewrites large parts of the CDM owned-engine internals around a resolver-based pipeline (DurationObject + stack text + aura mode all flow through three central resolvers). Behavior is intended to be unchanged, but if you see CDM icons render incorrectly compared to alpha13, please report the spell + container so we can check the resolver path.

### Added
- **Custom chat button-bar buttons can now fire protected slash commands.** Custom-command buttons switched from `RunMacroText` through an OnClick handler to a `SecureActionButtonTemplate` with the `macrotext` attribute, so `/cast`, `/use`, `/click`, and other protected commands actually fire instead of silently failing under taint. The built-in *Reload* button also routes through `QUI:SafeReload` now so combat-deferred reloads behave consistently. Bars with custom buttons refuse to mutate during combat (would be blocked anyway).
- **Item-trigger cooldowns resolve through a dedicated identity path.** Custom CDM bar entries that point at an item (trinkets, on-use consumables) now resolve their cooldown identity through `C_Item.GetItemSpell` with `C_Item.GetFirstTriggeredSpellForItem` as a fallback (passing item quality when available), and look up active auras either by spell ID or by item name.

### Changed
- **CDM owned engine internals reorganized around three resolvers.** `IsAuraCurrentlyActive(entry)` for the shared aura-detection check (combat-safe), `ResolveIconDurationObject(icon)` for *which* DurationObject to apply (linear priority `aura > charge > cooldown > gcd > inactive`), and `ResolveIconStackText(icon)` for charge / aura-application / linked-aura rollup text. The previous patchwork of mirror / sync / hook functions has been folded into this pipeline so visual aura mode and the chosen DurationObject source can no longer diverge.
- **Cooldown-expiry refresh now runs on a per-icon timer.** Each icon schedules its own one-shot refresh at expiration (with a small fudge factor) instead of the engine running a global per-tick ticker. Less idle CPU; no lingering refreshes on icons whose cooldown has already finished.
- **Combat-end (`PLAYER_REGEN_ENABLED`) no longer triggers a full CDM rescan.** The previous `ForceScan` + per-container snapshot + dormant-spell check + reconcile + refresh-all pass was redundant once the resolver picks up state on the next event. The spec-tracking finalize step is preserved.
- **Chat filters bail before addon-side string work if any vararg is secret.** Same defensive ordering across the pipeline, the master message filter, `channel_shorten`, `redundant_text`, and `sounds`: check `IsSecret(msg)`, then `HasSecretValue(...)` on the rest of the chat varargs *before* doing any modifier string operations. Prevents secret tokens in sender / channel / GUID args from tainting Blizzard's downstream HistoryKeeper / chat-formatter path even when the filter ultimately returns nil.

### Fixed
- **Charge counters on cooldown icons backed by a buff-viewer child no longer blank briefly during fast refreshes.** A per-icon last-good-value cache and new linked-aura / buff-viewer-backed lookup helpers keep the count steady through native + addon repaint races.



## v3.6.0-alpha13 - 2026-05-03

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing v34 profiles carry over unchanged. v3.5.x → alpha13: back up `WTF/` and export your profile first.

### Added
- **`/qspell` slash command** for dumping everything QUI can read about a spell (identity, override/base, knowledge state, cooldown/charges, active player aura, description). Accepts a spell ID, hyperlink, or partial name. Useful for debugging custom CDM bar entries.
- **Settings search now deep-links into sub-pages.** Group Frames and Action Bars search results carry their tile, sub-page, provider, and surface-tab context, so clicking a result jumps to the right tab + section instead of just the parent page. The cache also tracks `surfaceTabKey` / `surfaceUnitKey` so per-unit settings (party vs raid) deep-link correctly.

### Changed
- **CDM owned engine: secret-safety pass through the cooldown classifier.** The tick caches (`TickCacheGetCharges` / `Cooldown` / `Duration` / `ChargeDuration` / `OverrideSpell` / `DisplayCount`) all bail when the spell ID itself is a secret value and `pcall` every `C_Spell.*` lookup so a tainted argument can't propagate. `chargeInfo.isActive` is now treated as nil unless it's a non-secret boolean.
- **`IsCooldownInfoRealCooldown` reads `isEnabled`** and treats `duration > GCD` with `isActive==true` as a real cooldown immediately, fixing non-charged custom-bar entries that misclassified resource-recovery payloads as real cooldowns and vice versa.
- **GCD classification now uses a per-tick trusted snapshot.** `C_Spell.GetSpellCooldownInfo.isOnGCD` is secret in combat, so QUI captures the non-secret GCD state once at the top of each tick (`CaptureTrustedGCDState`) and looks up that snapshot from the classifier instead of reading `isOnGCD` per-call. Affects any code that distinguished "GCD-only" vs "real cooldown" rendering during combat.
- **Stack-text resolution rewritten** with new helpers for linked-aura ID lookup, buff-viewer-backed cooldown containers, and a per-icon last-good-value cache. Charge counters on cooldown icons backed by a buff-viewer child should hold steady through fast refreshes instead of blanking briefly.
- **Search cache regen runs through a new auditor.** `tools/audit_search_cache.lua` flags zero-setting features (allowlisted ones aside) and cross-checks the regenerated cache. CI's dev-build, search-cache-regen, and release workflows now all run both the generator and the auditor.

### Fixed
- **Mirror cooldown apply path** only sets `_mirrorDriven=true` when `SetCooldownFromDurationObject` actually returned successfully — the previous code was optimistic, which could leave icons stuck believing the C-side was driving the swipe when the call had failed under `pcall`.
- **`GetTrackerSettings` forward declaration** so `HookBlizzStackText` can call into it without a load-order race.



## v3.6.0-alpha12 - 2026-05-03

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing v34 profiles carry over unchanged. v3.5.x → alpha12: back up `WTF/` and export your profile first.

### Added
- **Custom CDM bar drag-reorder.** Custom CDM containers now support drag-to-reorder of entries within a row, including for spec-specific bars. Drag is constrained to the same source spec — attempting to drag across specs surfaces a brief on-screen warning. Each cell's tooltip reflects whether drag is available.
- **Custom CDM bar visibility resolver.** Non-charged custom-bar entries that lack a Blizzard mirror child now resolve real cooldown vs GCD via runtime spell-cooldown timing plus an optional cast-alias fallback (when a spell's runtime ID differs from its cast ID). Adds `_hasGCDOnlyCooldown` and refines `HasRealCooldownState` so "show only on cooldown" filters work correctly on custom entries.
- **Skinning for temporary chat windows.** Whispers and other temporary chat frames opened mid-session now pick up QUI's chat theme (backdrop, tabs, scrollbar, edit box) the same as the persistent chat frames.

### Changed
- **Chat timestamp setting routes through `Settings.GetValue`/`Settings.SetValue`** with a CVar fallback, and the user's Blizzard timestamp choice is persisted in the profile so QUI's override can restore it cleanly when toggled off. Timestamp behavior also gates on `C_ChatInfo.InChatMessagingLockdown` to avoid touching restricted state during combat.
- **CDM cooldown info is read through secret-aware accessors.** New `GetCooldownInfoField` / `IsCooldownInfoActive` / `IsCooldownInfoRealCooldown` helpers detect secret values in `C_Spell.GetSpellCooldownInfo` payloads and return tri-state (`true` / `false` / `nil` for unknown), eliminating places where addon code could be tainted by reading secret cooldown timing.
- **Damage meter entry rendering rewritten.** The skin now picks the correct primary value (DPS vs total) per entry based on `numberDisplayType` and `showsValuePerSecondAsPrimary`, and respects `suppressValuePerSecond` to avoid drawing redundant parenthetical numbers.
- **Options framework hover tooltips attach to the container, not the inner widget.** Checkboxes, color swatches, sliders, and dropdowns all expose their tooltip across the full row, so the description shows up consistently regardless of which sub-element you hover.

### Fixed
- **Custom CDM "Remove" on spec-specific bars.** Right-click → Remove from a spec-specific custom CDM bar was operating on the rendered index rather than the actual per-spec list index, which could remove the wrong entry (or fail silently for entries surfaced from a non-active spec). The remove path now passes the source spec key and the entry's per-spec index.



## v3.6.0-alpha11 - 2026-05-03

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing v34 profiles carry over unchanged. v3.5.x → alpha11: back up `WTF/` and export your profile first.

### Added
- **QUI chat module.** A full chat overhaul with a master toggle:
  - **Glass backdrop, themed tabs and edit box** with full-width input and per-tab unread pulse anchored to the tab chrome.
  - **Themed scrollbars** on every chat frame (and the matching scroll-to-bottom chevron) styled as one accent-colored chrome strip.
  - **Copy button** redesigned as a small accent glyph in the top-right corner of each chat frame, with a smooth fade tied to chat hover. Two visibility modes: *Fade When Idle* and *Hide When Idle*. New **Copy Source** option chooses between the live scrollback and persisted history when copying.
  - **Persistent chat history** that replays on login/reload (per-frame), pruned automatically when a chat window is closed.
  - **Per-tab filters.** Inclusion-only message-group and channel filters per tab, with a small accent pill on customized tabs.
  - **Per-frame Button Bar.** Add user-defined slash-command buttons to any chat frame. Configurable position (outside/inside left/right, inside the tab row), per-frame X/Y offsets, button spacing, and *Hide in combat*.
  - **Edit Box command history** with arrow-key recall.
  - **Timestamps**, **URL detection**, **clickable coordinates and player names**, **channel-name shortening**, **class colors**, **redundant-text cleanup** (loot/XP/honor/rep), **keyword alerts**, and **new-message sound**.
  - **Scrollback Lines** dropdown (client default, 500–5000) to extend the live scrollback cap.
  - **Hide chat buttons** for the social/channel chrome (the scrollbar stays visible).
- **Damage Meter QUI skin.** The Blizzard built-in damage meter (added in 12.0+) now picks up QUI's theme — backdrop, dropdowns, entry rows, and matching themed scrollbars on session windows and source popups. Eleven Blizzard meter settings are surfaced in QUI options, and the addon takes over Edit-Mode-style placement so meters move via QUI's Layout Mode.
- **Theme & Colors sub-page** on the Appearance tile. Picks up everything color-related in one place: theme preset / custom accent, global skin colors and borders, chat backgrounds, and tooltip skin (skin/opacity/border thickness/class or accent border).
- **Layout Mode polish for chat and damage meter.** Four-corner resize grips on chat frames (with accent-themed grip color) and on damage meter session windows. New **Frame Size** sliders for ChatFrame1 width/height and the damage meter, plus a screen-clamp guard so chat can't be dragged off-screen.

### Changed
- **Chat tile split into five sub-pages** in settings: General, Filters, Button Bar, Alerts, History. Tooltips moves to a sixth sub-page on the same tile. Search and deep-links now route to the matching sub-page automatically.
- **Native Blizzard chat timestamp is suppressed while QUI's timestamp is on**, so toggling the Blizzard `showTimestamps` CVar no longer doubles up the time prefix. Disabling QUI's timestamps restores whatever Blizzard format you had.

### Fixed
- **Chat input now resizes with the chat frame.** The edit box backdrop tracks chat-frame width on resize instead of staying at the original width.
- **Chat send path repaired for 12.0.** Slash commands fired from QUI button-bar buttons now dispatch through the supported macro-text path; sent-message capture for the command history sees the actual typed text instead of the cleared input.
- **Damage meter: stack of 12.0 taint-safety fixes.** Local-player and pooled entry rows are patched before any secret-string source name lands, so the meter's `UpdateName`/`UpdateValue`/`UpdateIcon` no longer faults during encounters; session-duration text uses secret-safe formatters; Edit Mode movers are suppressed in favor of QUI's Layout Mode.
- **Settings search index** now treats the precomputed search cache as authoritative, so chat sub-page entries don't double up between cache and runtime registration. Tab Filters' transient option proxies are skipped from search/sync/pin.
- **Group / Unit frames sliders** no longer rebuild on every pixel of drag — `onChange` fires on mouse release.



## v3.6.0-alpha10 - 2026-05-02

> ⚠️ **Still alpha — back up your `WTF` folder before installing.** No new schema migrations; existing v34 profiles carry over unchanged. v3.5.x → alpha10: back up `WTF/` and export your profile first.

### Changed
- **Library bumps.** Vendored libraries refreshed to current upstream releases. No QUI behavior change is expected from these on its own.
  - `LibSharedMedia-3.0` → 12000001 (Midnight)
  - `LibRangeCheck-3.0` → MINOR 34
  - `LibDualSpec-1.0` → v1.29.0
  - `LibOpenRaid` → CONST_LIB_VERSION 177



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
