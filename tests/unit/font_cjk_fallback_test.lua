-- tests/unit/font_cjk_fallback_test.lua
-- Run: lua tests/unit/font_cjk_fallback_test.lua
--
-- Proves Helpers.GetFontFamilyObject / ApplyFontWithFallback build a per-script
-- (CJK) font family via CreateFontFamily with EXACTLY 5 members (roman, korean,
-- simplifiedchinese, traditionalchinese, russian — fewer throws on live), using
-- the canonical string alphabet names because Enum.FontAlphabet does not exist
-- on live 12.0 clients. Also covers caching, SetFontObject + justify/color
-- preservation, and graceful degradation to plain SetFont.

function LibStub() return nil end

local QUII = [[Interface\AddOns\QUI\assets\Quazii.ttf]]
local EXPECTED = {
    roman              = QUII,
    korean             = "Fonts\\2002.TTF",
    simplifiedchinese  = "Fonts\\ARKai_T.ttf",
    traditionalchinese = "Fonts\\blei00d.TTF",
    russian            = QUII,
}

-- ---------------------------------------------------------------------------
-- Stub CreateFontFamily; enforce the real 5-member contract.
-- ---------------------------------------------------------------------------
local createCalls = 0
local lastMembers
function _G.CreateFontFamily(name, members)
    createCalls = createCalls + 1
    assert(type(name) == "string" and name ~= "", "family needs a name")
    assert(#members == 5, "CreateFontFamily requires exactly 5 members, got " .. #members)
    lastMembers = members
    return { __family = name }
end

-- Live 12.0 reality: Enum.FontAlphabet is absent -> alphabet must be a string.
_G.Enum = nil

local ns = {}
assert(loadfile("core/utils.lua"))("QUI", ns)
local Helpers = ns.Helpers

-- ---------------------------------------------------------------------------
-- 1) Five members, STRING alphabets, correct per-script files/size/flags.
-- ---------------------------------------------------------------------------
local fam = Helpers.GetFontFamilyObject(QUII, 12, "OUTLINE")
assert(fam, "should build a family from string alphabets without Enum.FontAlphabet")
assert(#lastMembers == 5, "must pass exactly 5 members")

local seen = {}
for _, m in ipairs(lastMembers) do
    assert(type(m.alphabet) == "string", "alphabet must be a string when the enum is absent")
    assert(EXPECTED[m.alphabet], "unexpected alphabet: " .. tostring(m.alphabet))
    assert(m.file == EXPECTED[m.alphabet], m.alphabet .. " member file mismatch")
    assert(m.height == 12 and m.flags == "OUTLINE", "member height/flags must match request")
    seen[m.alphabet] = true
end
for name in pairs(EXPECTED) do
    assert(seen[name], "missing required alphabet member: " .. name)
end

-- ---------------------------------------------------------------------------
-- 2) Caches by (path|size|flags); a different combo builds a new family.
-- ---------------------------------------------------------------------------
local before = createCalls
assert(Helpers.GetFontFamilyObject(QUII, 12, "OUTLINE") == fam, "cache hit returns same family")
assert(createCalls == before, "cache hit must not re-call CreateFontFamily")
Helpers.GetFontFamilyObject(QUII, 14, "OUTLINE")
assert(createCalls == before + 1, "a different size must build a new family")

-- ---------------------------------------------------------------------------
-- 3) Uses the numeric enum value on builds that DO expose Enum.FontAlphabet.
-- ---------------------------------------------------------------------------
_G.Enum = { FontAlphabet = { Roman = 0, Korean = 1, SimplifiedChinese = 2,
    TraditionalChinese = 3, Russian = 4 } }
local ns3 = {}
assert(loadfile("core/utils.lua"))("QUI", ns3)
ns3.Helpers.GetFontFamilyObject(QUII, 12, "")
local numeric = false
for _, m in ipairs(lastMembers) do
    if m.alphabet == 0 or m.alphabet == 2 then numeric = true end
end
assert(numeric, "should use Enum.FontAlphabet values when the enum exists")
_G.Enum = nil

-- ---------------------------------------------------------------------------
-- 4) ApplyFontWithFallback assigns the family + restores justify/color.
-- ---------------------------------------------------------------------------
local fs = { _jh = "CENTER", _jv = "MIDDLE", _r = 0.2, _g = 0.4, _b = 0.6, _a = 0.8 }
function fs:SetFont(path, size, flags) self.setFontArgs = { path, size, flags } end
function fs:SetFontObject(obj)
    self.setObj = obj
    self._jh, self._jv = "LEFT", "TOP"
    self._r, self._g, self._b, self._a = 1, 1, 1, 1
end
function fs:GetJustifyH() return self._jh end
function fs:GetJustifyV() return self._jv end
function fs:GetTextColor() return self._r, self._g, self._b, self._a end
function fs:SetJustifyH(v) self._jh = v end
function fs:SetJustifyV(v) self._jv = v end
function fs:SetTextColor(r, g, b, a) self._r, self._g, self._b, self._a = r, g, b, a end

Helpers.ApplyFontWithFallback(fs, QUII, 12, "OUTLINE")
assert(fs.setObj and fs.setObj.__family, "ApplyFontWithFallback must SetFontObject the family")
assert(fs.setFontArgs == nil, "must not fall back to SetFont while a family is available")
assert(fs._jh == "CENTER" and fs._jv == "MIDDLE", "justify must be restored after SetFontObject")
assert(fs._r == 0.2 and fs._a == 0.8, "text color must be restored after SetFontObject")

-- ---------------------------------------------------------------------------
-- 5) Degrades to plain SetFont when CreateFontFamily is unavailable.
-- ---------------------------------------------------------------------------
local ns2 = {}
assert(loadfile("core/utils.lua"))("QUI", ns2)
_G.CreateFontFamily = nil
local fs2 = {}
function fs2:SetFont(path, size, flags) self.calls = { path, size, flags } end
function fs2:SetFontObject() error("SetFontObject must not be used without CreateFontFamily") end
ns2.Helpers.ApplyFontWithFallback(fs2, QUII, 13, "")
assert(fs2.calls and fs2.calls[1] == QUII and fs2.calls[2] == 13,
    "must fall back to SetFont(file, size, flags) when no family API exists")

print("OK: font_cjk_fallback_test")
