---
layout: default
title: Alts
parent: Features
nav_order: 8
---

# Alts

QUI Alts is an optional beta module for account-wide character tracking. It builds on QUI's shared storage cache and gives you one window for roster, gear, professions, reputations, weeklies, currencies, and item search.

{: .important }
Alts is off by default. Enable it under `/qui` > **Module Addons**, then open it with `/alts` or `/quialts`.

## What It Tracks

| Tab | What you use it for |
|-----|---------------------|
| Roster | Gold, item level, played time, rested state, zone, professions, last seen, and account totals |
| Equipment | Side-by-side gear comparison by equipment slot, with item icons and item levels |
| Professions | Profession overview across your characters |
| Reputations | Per-character reputation and renown lookup |
| Weeklies | Great Vault, keystone, M+ rating, and raid lockout overview |
| Currencies | Currency lookup by character |
| Search | Find items across cached bags, banks, Warband bank, guild banks, mail, equipped gear, and auction listings |

## First Use

1. Enable **Alts** from **Module Addons**.
2. Reload if prompted.
3. Log into the characters you want tracked.
4. Open `/alts`.

The shared account cache fills as each character logs in. After a cache reset or first install, offline inventory and equipment snapshots repopulate the next time each character enters the world.

## Filters

The Currencies and Reputations tabs include **Filter** buttons. Use them to hide entries you do not care about. The same filters are also configurable from the Alts settings page.

Newly discovered currencies and reputations start visible, so fresh content is not hidden by an old filter.

## Alts Datatext

The Alts datatext can show total account gold or tracked alt count. It works on data panels and the Info Bar, and clicking it opens the Alts window.

## Good To Know

- Deleting a character from the roster removes that character from the cache.
- Equipment data fills from live character scans, so a character may show partial data until it has logged in on the current beta cache.
- The Search tab depends on cached storage data; live bank and guild-bank data becomes richer after you open those storage windows at least once.
