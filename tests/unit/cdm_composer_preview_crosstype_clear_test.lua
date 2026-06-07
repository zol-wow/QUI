-- tests/unit/cdm_composer_preview_crosstype_clear_test.lua
-- Run: lua tests/unit/cdm_composer_preview_crosstype_clear_test.lua
--
-- Regression: switching the composer preview from a container of one frame
-- family to a container of the other family must release the leftover frames.
--
-- Repro (user report): select a custom icon container WITH entries, then
-- switch to the built-in buff-bar container with NO entries via the dropdown
-- (which routes through QUI_RefreshCDMPreview -> RefreshPreview ->
-- CDMComposerPreview.Refresh WITHOUT a Teardown). The custom container's icons
-- stayed visible because Refresh's auraBar branch only manages bars and never
-- released the icon frames from the previous container.

local loadSource = loadstring or load

local function loadDriver()
    -- Fresh namespace per load so driver `state` is fully isolated.
    local ns = {}
    local handle = assert(io.open("QUI_CDM/cdm/settings/composer_preview_driver.lua", "rb"))
    local src = handle:read("*a")
    handle:close()
    src = src:gsub("\r\n", "\n")
    local chunk = assert(loadSource(src, "@composer_preview_driver.lua"))
    chunk("QUI", ns)
    return ns
end

-- Minimal frame/factory mocks. We only need to observe show/hide/release.
local function makeIcon()
    return {
        _shown = false,
        Icon = { SetTexture = function() end },
        Show = function(self) self._shown = true end,
        Hide = function(self) self._shown = false end,
    }
end

local function makeBar()
    return {
        _shown = false,
        IconTexture = { SetTexture = function() end },
        NameText    = { SetText = function() end },
        Show      = function(self) self._shown = true end,
        Hide      = function(self) self._shown = false end,
        SetParent = function(self) self._parented = false end,
    }
end

-- Shared globals the driver reaches for. LibStub left nil so GetLCG() -> nil
-- and the glow path no-ops (no LibCustomGlow mock required).
_G.CreateFrame = function() return { SetScript = function() end } end

---------------------------------------------------------------------------
-- Scenario 1 (primary repro): icon container (3 entries) -> empty bar
---------------------------------------------------------------------------
do
    local ns = loadDriver()
    local P = ns.CDMComposerPreview

    local acquiredIcons, releaseCount = {}, 0
    ns.CDMIconFactory = {
        AcquireForPreview = function(_, entry)
            local icon = makeIcon()
            icon._spellEntry = entry
            acquiredIcons[#acquiredIcons + 1] = icon
            return icon
        end,
        ReleaseForPreview = function(icon)
            releaseCount = releaseCount + 1
            if icon then icon._shown = false; icon._released = true end
        end,
    }
    ns.CDMBars = {
        CreateForPreview = function() return makeBar() end,
        ConfigureBar     = function() end,
    }

    local DBS = {
        myicons = { containerType = "cooldown", ownedSpells = { { spellID = 1 }, { spellID = 2 }, { spellID = 3 } } },
        buffbar = { containerType = "auraBar", ownedSpells = {} },
    }
    _G.QUI_GetCDMContainerDB = function(key) return DBS[key] end

    P.Build({})

    P.Refresh("myicons")
    assert(#acquiredIcons == 3, "expected 3 preview icons acquired, got " .. #acquiredIcons)
    for i, ic in ipairs(acquiredIcons) do
        assert(ic._shown, "icon " .. i .. " should be shown after icon-container refresh")
    end
    assert(releaseCount == 0, "no icons should be released yet, got " .. releaseCount)

    -- Switch to the empty bar container. The stale icons MUST be cleared.
    P.Refresh("buffbar")
    assert(releaseCount == 3,
        "all 3 stale icons must be released when switching to the empty bar " ..
        "container, got " .. releaseCount)
    for i, ic in ipairs(acquiredIcons) do
        assert(not ic._shown,
            "icon " .. i .. " still visible after switching to the empty bar container")
    end
end

---------------------------------------------------------------------------
-- Scenario 2 (symmetric): bar container (2 entries) -> empty icon container
---------------------------------------------------------------------------
do
    local ns = loadDriver()
    local P = ns.CDMComposerPreview

    local createdBars = {}
    ns.CDMBars = {
        CreateForPreview = function()
            local bar = makeBar()
            createdBars[#createdBars + 1] = bar
            return bar
        end,
        ConfigureBar = function() end,
    }
    ns.CDMIconFactory = {
        AcquireForPreview = function() return makeIcon() end,
        ReleaseForPreview = function(icon) if icon then icon._shown = false end end,
    }

    local DBS = {
        buffbarfull = { containerType = "auraBar", ownedSpells = { { spellID = 10 }, { spellID = 11 } } },
        emptyicons  = { containerType = "cooldown", ownedSpells = {} },
    }
    _G.QUI_GetCDMContainerDB = function(key) return DBS[key] end

    P.Build({})

    P.Refresh("buffbarfull")
    assert(#createdBars == 2, "expected 2 preview bars created, got " .. #createdBars)
    for i, bar in ipairs(createdBars) do
        assert(bar._shown, "bar " .. i .. " should be shown after bar-container refresh")
    end

    -- Switch to the empty icon container. The stale bars MUST be cleared.
    P.Refresh("emptyicons")
    for i, bar in ipairs(createdBars) do
        assert(not bar._shown,
            "bar " .. i .. " still visible after switching to the empty icon container")
    end
end

print("OK: cdm_composer_preview_crosstype_clear_test")
