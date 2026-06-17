# Vendored FrameXML Source

This directory holds Blizzard's FrameXML — the XML frame templates and Lua
behavior for the live World of Warcraft client UI. Together with the
`C_*` API doc corpus at `tests/api-docs/blizzard/`, it gives QUI's
skinning gap audits, taint analyzer, and template-aware tools the
information needed to reason about Blizzard frames without a WoW install.

## Why this exists

The companion corpus at `tests/api-docs/blizzard/` documents only the
public `C_*` Lua namespace, events, enums, and structures. It does NOT
document:

- Frame templates (`ButtonFrameTemplate`, `UIPanelButtonTemplate`,
  `BackdropTemplate`, `NineSlicePanelTemplate`, etc.)
- Frame child regions (`AuctionHouseFrame.SearchBar`, `CharacterFrame.NineSlice`,
  alert-system internals, static-popup sub-elements, scroll-box layouts)
- FrameXML helper globals (`PanelTemplates_*`, `FCFDock_*`, `ScrollUtil.*`)
- XML-defined Atlas keys and texture coordinates
- Mixin definitions consumed across the UI (`BackdropTemplateMixin`,
  `ScrollBoxBaseMixin`, `AlertFrameMixin`, …)

This corpus fills that gap.

## Source

The canonical vendoring source is the `live` branch of
[`Gethe/wow-ui-source`](https://github.com/Gethe/wow-ui-source), which
tracks retail FrameXML within hours of each patch. An online mirror with
web-grep is also available at
<https://www.townlong-yak.com/framexml/live/>.

## Current snapshot

- **Patch:** 12.0.7.68235 (Midnight)
- **Source branch:** `live`
- **Vendored on:** 2026-06-17

The exact patch version is recorded in `version.txt` at the root of this
directory and should always match the snapshot.

## Refresh procedure

When WoW patches, FrameXML files change. To refresh:

```sh
# From repo root
git clone --depth 1 --branch live https://github.com/Gethe/wow-ui-source.git tests/framexml-staging
rm -rf tests/framexml/Interface tests/framexml/version.txt
mv tests/framexml-staging/Interface tests/framexml/Interface
mv tests/framexml-staging/version.txt tests/framexml/version.txt
rm -rf tests/framexml-staging
```

After refreshing:

1. Update the **Patch** and **Vendored on** fields in this README.
2. Verify the diff is sensible (`git diff --stat tests/framexml/` —
   expect ~hundreds of file changes per patch).
3. If the API docs at `tests/api-docs/blizzard/` were refreshed at the
   same time, commit both together with a single patch-version message.
4. If the taint analyzer or skinning audit tooling depends on specific
   files (e.g. `AuctionHouseFrame.xml`), spot-check those paths still
   exist after the refresh.

## Layout

```
tests/framexml/
├── README.md                              # this file
├── version.txt                            # patch version (e.g. 12.0.5.67602)
└── Interface/
    └── AddOns/
        ├── Blizzard_APIDocumentation/         # superset of tests/api-docs/blizzard
        ├── Blizzard_APIDocumentationGenerated/
        ├── Blizzard_AchievementUI/
        ├── Blizzard_ActionBar/
        ├── Blizzard_AuctionHouseUI/
        ├── Blizzard_CharacterFrame/
        ├── Blizzard_ChallengesUI/
        ├── Blizzard_Collections/
        ├── Blizzard_EncounterJournal/
        ├── Blizzard_InspectUI/
        ├── Blizzard_Professions/
        ├── Blizzard_PlayerSpells/
        └── …(plus ~250 more Blizzard_* directories)
```

The `Interface/AddOns/Blizzard_APIDocumentationGenerated/` folder here is
the *complete* upstream snapshot of the same files we vendored selectively
at `tests/api-docs/blizzard/`. The two corpora overlap intentionally:
`tests/api-docs/blizzard/` is the curated, taint-analyzer-driven subset
with a derived `api-index.lua`; `tests/framexml/Interface/AddOns/Blizzard_APIDocumentationGenerated/`
is the full upstream tree for cross-reference.

## License

FrameXML ships as part of the WoW client and has been treated as public
for the entire addon ecosystem (~20 years). Vendoring it here is standard
practice. The source repository (`Gethe/wow-ui-source`) preserves
Blizzard's content without modification, and this snapshot inherits that
posture.
