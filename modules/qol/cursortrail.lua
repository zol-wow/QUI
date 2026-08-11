local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local TRAIL_MAX = 24
local FRAME_LEVEL = 9490
local DOT_TEXTURE = Helpers.AssetPath .. "cursor\\qui_reticle_dot.tga"

local DENSITY_SPACING = { low = 24, medium = 14, high = 8 }

local trailFrame
local dots
local nextDot = 1
local lastX, lastY = 0, 0
local running = false
local inCombat = false

local function GetTrailColor(cfg)
    if cfg.useClassColor ~= false then
        local _, class = UnitClass("player")
        -- @secret-policy: collapse-only — custom color / white fallback below
        if Helpers.IsSecretValue(class) then class = nil end
        local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if color then return color.r, color.g, color.b end
    end
    local c = cfg.customColor
    if type(c) == "table" then return c[1] or 1, c[2] or 1, c[3] or 1 end
    return 1, 1, 1
end

local function EnsureFrame()
    if trailFrame then return end
    trailFrame = CreateFrame("Frame", nil, UIParent)
    trailFrame:SetFrameStrata("TOOLTIP")
    trailFrame:SetFrameLevel(FRAME_LEVEL)
    trailFrame:SetAllPoints(UIParent)
    trailFrame:EnableMouse(false)
    dots = {}
    for i = 1, TRAIL_MAX do
        local tex = trailFrame:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(DOT_TEXTURE)
        tex:SetAlpha(0)
        tex:Hide()
        dots[i] = { tex = tex, alpha = 0 }
    end
end

local function TrailOnUpdate(_, elapsed)
    local settings = GetSettings()
    local cfg = settings and settings.cursorTrail
    if not cfg then return end

    local duration = tonumber(cfg.duration) or 0.4
    if duration <= 0.05 then duration = 0.05 end
    local decay = elapsed / duration

    for i = 1, TRAIL_MAX do
        local dot = dots[i]
        if dot.alpha > 0 then
            dot.alpha = dot.alpha - decay
            if dot.alpha <= 0 then
                dot.alpha = 0
                dot.tex:Hide()
            else
                dot.tex:SetAlpha(dot.alpha)
            end
        end
    end

    local px, py = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if scale <= 0 then return end
    local x, y = px / scale, py / scale
    local spacing = DENSITY_SPACING[cfg.density] or DENSITY_SPACING.medium
    local dx, dy = x - lastX, y - lastY
    if (dx * dx + dy * dy) < (spacing * spacing) then return end
    lastX, lastY = x, y

    local dot = dots[nextDot]
    nextDot = (nextDot % TRAIL_MAX) + 1
    local size = tonumber(cfg.size) or 16
    local r, g, b = GetTrailColor(cfg)
    dot.tex:SetSize(size, size)
    dot.tex:SetVertexColor(r, g, b)
    dot.tex:ClearAllPoints()
    dot.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    dot.alpha = 1
    dot.tex:SetAlpha(1)
    dot.tex:Show()
end

local function Stop()
    if not running then return end
    running = false
    if trailFrame then
        trailFrame:SetScript("OnUpdate", nil)
        for i = 1, TRAIL_MAX do
            dots[i].alpha = 0
            dots[i].tex:Hide()
        end
    end
end

local function Start()
    if running then return end
    EnsureFrame()
    running = true
    trailFrame:SetScript("OnUpdate", TrailOnUpdate)
end

local function Refresh()
    local settings = GetSettings()
    local cfg = settings and settings.cursorTrail
    if not cfg or not cfg.enabled then
        Stop()
        return
    end
    if cfg.combatOnly ~= false and not inCombat then
        Stop()
        return
    end
    Start()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event)
    inCombat = (event == "PLAYER_REGEN_DISABLED")
    Refresh()
end)

ns.RefreshCursorTrail = Refresh

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        inCombat = InCombatLockdown() and true or false
        Refresh()
    end)
end
