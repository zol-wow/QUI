-- TRUE fresh install: SavedVariables exist but hold NO profile yet.
-- AceDB materializes profiles.Default on first access, which fires
-- OnNewProfile -> ns.ApplyNewProfileSeed (the shipped Starter Profile seed), exactly
-- as core/main.lua QUICore:OnInitialize does in-game. Distinct from
-- basic_fresh, whose seed pre-creates an empty profiles.Default and so
-- never fires OnNewProfile.
--
-- Guards the regression fixed when the seed callback was wired to the dead
-- QUI_DB instead of the live profile DB: fresh installs got legacy defaults
-- instead of the Starter Profile seed. If the seed stops applying, themePreset reverts
-- to the legacy default ("Horde") and the invariants below fail.
QUI_DB = {}
QUIDB = {}
