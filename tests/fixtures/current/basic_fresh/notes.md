# basic_fresh

A profile with no user customizations — AceDB serves everything from
defaults. This fixture proves:

- Migrations run cleanly on an empty profile
- Export emits a valid `QUI1:` string for an empty profile
- Import on a fresh DB reproduces the same state
- Strip-on-save leaves only what migrations explicitly stamped

If `expected.sv.lua` ever diverges from `seed.sv.lua` for this fixture,
something has shifted in defaults / migrations / strip behavior.
