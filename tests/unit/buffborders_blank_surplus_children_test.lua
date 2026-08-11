-- tests/unit/buffborders_blank_surplus_children_test.lua
-- Run: lua tests/unit/buffborders_blank_surplus_children_test.lua
--
-- Regression guard for stale icons/borders on empty buff/debuff/enchant slots.
--
-- Model history:
--   * SecureAuraHeader hid dead children in secure code; QUI blanked its parented
--     regions a frame later.
--   * The B2 insecure AuraButtonMixin pool made QUI Clear()+Hide() each pooled
--     button with no aura this pass.
--   * The E4 unification moved the player onto the SHARED secure
--     CustomAuraContainer. For LIVE buffs/debuffs, blanking surplus buttons is now
--     ENGINE-OWNED: CustomAuraContainerPrivateMixin:RefreshAuraFrames calls
--     auraFrame:ClearAuraInstance() on every pooled AuraSkin button past the live
--     count (see Blizzard_CustomAuraContainer.lua). QUI no longer pools or clears
--     the live aura buttons, so there is intentionally NO QUI Lua loop for them.
--
-- Temp weapon enchants (the old exception -- synthetic non-aura entries the
-- container couldn't show) are ALSO engine-owned now: PTR4 AddItemEnchantment
-- (AuraSkin.ConfigureEnchantments, folded into the SAME strip-1 container)
-- means the engine's ClearAuraInstance blanking covers them too. QUI no
-- longer pools ANY buff/debuff/enchant button -- guard that no bespoke pool
-- of any kind crept back in.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("QUI_ActionBars/actionbars/buffborders.lua")

-- No bespoke insecure aura-button pool for live buffs/debuffs (engine owns it now).
assert(not source:find("function AuraFrame:Update", 1, true),
    "buffborders.lua must NOT keep a bespoke AuraFrame:Update pool (the secure container blanks surplus buttons C-side)")
assert(not source:find("function AuraButton:Clear", 1, true),
    "buffborders.lua must NOT keep a bespoke AuraButton:Clear (engine ClearAuraInstance owns blanking)")

-- The separate insecure temp-enchant strip (and its own Clear+Hide pool loop)
-- is fully gone: enchants render inside the buff container via the engine now.
assert(not source:find("function UpdateTempEnchants", 1, true),
    "buffborders.lua must NOT keep a bespoke UpdateTempEnchants pool (enchants are engine-owned inside the buff container)")
assert(not source:find("function EnsureTempEnchantButton", 1, true),
    "buffborders.lua must NOT keep a bespoke EnsureTempEnchantButton (no QUI-pooled enchant buttons remain)")
assert(source:find("AuraSkin.ConfigureEnchantments", 1, true),
    "buffborders.lua must fold temp enchants into the buff container via AuraSkin.ConfigureEnchantments")

print("OK: buffborders_blank_surplus_children_test")
