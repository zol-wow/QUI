-- tests/unit/options_profiles_dual_column_test.lua
-- Structure regression: the Profiles tab renders three accent-dot sections
-- (Current Profile / Manage Profiles / Spec Auto-Switch) with dual-column
-- paired rows, replacing the legacy six single-column sections.
-- Run: lua tests/unit/options_profiles_dual_column_test.lua

-- Headless WoW-ish stubs --------------------------------------------------
local function NewFontString()
    local fs = {}
    function fs:SetPoint() end
    function fs:SetText(text) self._text = text end
    function fs:SetTextColor() end
    function fs:SetJustifyH() end
    function fs:SetFont() end
    function fs:GetFont() return "font", 11, "" end
    function fs:SetWordWrap() end
    function fs:SetNonSpaceWrap() end
    function fs:SetWidth() end
    return fs
end

local function NewFrame()
    local f = {}
    function f:SetHeight(h) self._height = h end
    function f:GetHeight() return self._height or 0 end
    function f:SetWidth() end
    function f:SetSize() end
    function f:SetPoint() end
    function f:ClearAllPoints() end
    function f:SetScript(name, fn) self["_" .. name] = fn end
    function f:SetParent() end
    function f:Hide() end
    function f:Show() end
    function f:EnableMouse() end
    function f:CreateFontString() return NewFontString() end
    function f:CreateTexture() return NewFontString() end
    return f
end

_G.CreateFrame = function() return NewFrame() end
_G.C_Timer = { After = function() end }
_G.GetNumSpecializations = function() return 3 end
_G.GetSpecializationInfo = function(i) return i, "Spec" .. i end
_G.GetSpecialization = function() return 1 end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local gui = {
    Colors = {
        text = { 1, 1, 1, 1 },
        textMuted = { 0.6, 0.6, 0.6, 1 },
        accent = { 0.2, 0.8, 0.6, 1 },
    },
    ERROR_TEXT = { 0.9, 0.3, 0.3, 1 },
}
function gui:CreateLabel() return NewFontString() end
function gui:CreateButton(_parent, text)
    local b = NewFrame()
    b.text = NewFontString()
    b._buttonText = text
    return b
end
function gui:CreateFormDropdown()
    local d = NewFrame()
    function d:SetValue() end
    d.SetOptions = function() end -- dot-called by RefreshProfileDropdowns
    return d
end
function gui:CreateFormEditBox()
    local e = NewFrame()
    e.editBox = NewFrame()
    e.editBox.GetText = function() return "" end
    e.editBox.SetText = function() end
    return e
end
function gui:CreateFormCheckbox() return NewFrame() end
function gui:ShowConfirmation() end

_G.QUI = { GUI = gui, _presetProfiles = {}, imports = {} }

-- Recorders: every accent-dot header and card group the builder creates.
local headers = {}
local cards = {}
local Shared = {
    PADDING = 10,
    CreateScrollableContent = function() end,
    CreateAccentDotLabel = function(_, text)
        headers[#headers + 1] = text
        return NewFrame()
    end,
    CreateSettingsCardGroup = function()
        local card = { frame = NewFrame(), rows = {} }
        function card.AddRow(left, right)
            card.rows[#card.rows + 1] = { left = left, right = right }
            return NewFrame()
        end
        function card.Finalize() card.frame:SetHeight(#card.rows * 32) end
        function card.GetRowCount() return #card.rows end
        cards[#cards + 1] = card
        return card
    end,
    BuildSettingRow = function(_, labelText, widget)
        return { _settingRowLabel = labelText, _widgetLabel = labelText, _widget = widget }
    end,
}

local db = {}
function db:GetProfiles() return { "Default", "Raid" } end
function db:GetCurrentProfile() return "Default" end
function db:SetProfile() end
function db:CopyProfile() end
function db:DeleteProfile() end
function db:ResetProfile() end
function db:ResetDB() end
function db:IsDualSpecEnabled() return false end
function db:SetDualSpecEnabled() end
function db:GetDualSpecProfile() return "" end
function db:SetDualSpecProfile() end

local ns = {
    QUI_Options = Shared,
    Helpers = { GetCore = function() return { db = db } end },
}

assert(loadfile("core/settings/content/profiles_content.lua"))("QUI", ns)
local Profiles = ns.QUI_ProfilesOptions
assert(Profiles and type(Profiles.BuildSpecProfilesContent) == "function",
    "profiles_content must expose BuildSpecProfilesContent")

local content = NewFrame()
Profiles.BuildSpecProfilesContent(content)

-- Three consolidated sections, in order. -----------------------------------
assert(#headers == 3, "expected 3 section headers, got " .. #headers
    .. " (" .. table.concat(headers, ", ") .. ")")
assert(headers[1] == "Current Profile",
    "header 1 must be Current Profile, got " .. tostring(headers[1]))
assert(headers[2] == "Manage Profiles",
    "header 2 must be Manage Profiles, got " .. tostring(headers[2]))
assert(headers[3] == "Spec Auto-Switch",
    "header 3 must be Spec Auto-Switch, got " .. tostring(headers[3]))

assert(#cards == 3, "expected 3 card groups, got " .. #cards)
local currentCard, manageCard, specCard = cards[1], cards[2], cards[3]

-- Current Profile: two paired rows (active|reset-profile, movers|factory).
assert(#currentCard.rows == 2,
    "Current Profile card must have 2 rows, got " .. #currentCard.rows)
assert(currentCard.rows[1].right, "Current Profile row 1 must be paired")
assert(currentCard.rows[2].right, "Current Profile row 2 must be paired")

-- Manage Profiles: switch|copy then delete|create.
assert(#manageCard.rows == 2,
    "Manage Profiles card must have 2 rows, got " .. #manageCard.rows)
assert(manageCard.rows[1].left._settingRowLabel == "Switch Profile",
    "row 1 left must be Switch Profile, got " .. tostring(manageCard.rows[1].left._settingRowLabel))
assert(manageCard.rows[1].right._settingRowLabel == "Copy From",
    "row 1 right must be Copy From, got " .. tostring(manageCard.rows[1].right._settingRowLabel))
assert(manageCard.rows[2].left._settingRowLabel == "Delete Profile",
    "row 2 left must be Delete Profile, got " .. tostring(manageCard.rows[2].left._settingRowLabel))
assert(manageCard.rows[2].right,
    "Manage Profiles row 2 must pair the create cell on the right")
assert(manageCard.rows[2].right._widgetLabel == "New Profile",
    "create cell must carry _widgetLabel for the search cache")

-- Spec Auto-Switch: full-width enable row, then 3 specs paired two-up.
assert(#specCard.rows == 3,
    "Spec card must have 3 rows (enable + 2 spec rows), got " .. #specCard.rows)
assert(specCard.rows[1].right == nil, "enable row must stay full-width")
assert(specCard.rows[1].left._settingRowLabel == "Enable Spec Profiles",
    "spec row 1 must be the enable checkbox")
assert(specCard.rows[2].right, "first spec row must be paired")
assert(specCard.rows[3].left and specCard.rows[3].right == nil,
    "odd spec count must leave the last row solo")

print("OK options_profiles_dual_column_test")
