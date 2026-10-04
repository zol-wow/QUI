local _, ns = ...
local P = {}
ns.SpellReminderPresentation = P

local function Font(text, config, size)
    ns.Helpers.ApplyFontWithFallback(text, config.font ~= "" and config.font or ns.Helpers.GetGeneralFont(),
        size or config.fontSize, config.fontOutline)
    text:SetTextColor(unpack(config.textColor))
end

function P.Name(config)
    local info = C_Spell.GetSpellInfo(config.spellID)
    return info and info.name or tostring(config.spellID)
end

local function Border(parent, color, thickness)
    local edges = {}
    for i = 1, 4 do
        local edge = parent:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(unpack(color))
        if i < 3 then
            local point = i == 1 and "TOP" or "BOTTOM"
            edge:SetPoint(point .. "LEFT"); edge:SetPoint(point .. "RIGHT"); edge:SetHeight(thickness)
        else
            local point = i == 3 and "LEFT" or "RIGHT"
            edge:SetPoint("TOP" .. point); edge:SetPoint("BOTTOM" .. point); edge:SetWidth(thickness)
        end
        edges[i] = edge
    end
    return edges
end

function P.CreateIcon(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame.texture = frame:CreateTexture(nil, "ARTWORK")
    frame.texture:SetAllPoints()
    frame.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints()
    frame.cooldown:SetDrawEdge(false)
    frame.label = frame:CreateFontString(nil, "OVERLAY")
    frame.border = Border(frame, { 0, 0, 0, 1 }, 1)
    return frame
end

function P.ConfigureIcon(frame, config)
    frame:SetSize(config.size, config.size)
    frame.texture:SetTexture(C_Spell.GetSpellTexture(config.spellID))
    frame.label:ClearAllPoints()
    frame.label:SetWidth(config.nameLayout == "overlay" and config.size + 20 or 180)
    if config.nameLayout == "left" then
        frame.label:SetPoint("RIGHT", frame, "LEFT", -6, 0)
        frame.label:SetJustifyH("RIGHT")
    elseif config.nameLayout == "right" then
        frame.label:SetPoint("LEFT", frame, "RIGHT", 6, 0)
        frame.label:SetJustifyH("LEFT")
    else
        frame.label:SetPoint("CENTER")
        frame.label:SetJustifyH("CENTER")
    end
    Font(frame.label, config)
    for _, edge in ipairs(frame.border) do edge:SetShown(config.showBorder) end
    P.StopEffects(frame)
end

function P.StopEffects(frame)
    if frame.effect then frame.effect:Stop() end
    frame.effect, frame.effectKey = nil, nil
    if frame.glowing then
        local lib = LibStub("LibCustomGlow-1.0", true)
        if lib then
            lib.ProcGlow_Stop(frame); lib.PixelGlow_Stop(frame)
            lib.AutoCastGlow_Stop(frame); lib.ButtonGlow_Stop(frame)
        end
        frame.glowing = nil
    end
    frame:SetAlpha(1)
end

local function Effects(frame, config, ready)
    local glow = (ready or not config.glowReadyOnly) and config.glow or "none"
    local animation = (ready or not config.animationReadyOnly) and config.animation or "none"
    local key = glow .. ":" .. animation
    if frame.effectKey == key then return end
    P.StopEffects(frame)
    frame.effectKey = key
    local lib = LibStub("LibCustomGlow-1.0", true)
    if lib and glow ~= "none" then
        if glow == "proc" then lib.ProcGlow_Start(frame, { color = config.glowColor })
        elseif glow == "pixel" then lib.PixelGlow_Start(frame, config.glowColor)
        elseif glow == "autocast" then lib.AutoCastGlow_Start(frame, config.glowColor)
        else lib.ButtonGlow_Start(frame, config.glowColor) end
        frame.glowing = true
    end
    if animation == "none" then return end
    -- Native animation groups avoid a per-icon OnUpdate loop.
    frame.animations = frame.animations or {}
    if frame.animations[animation] then
        frame.effect = frame.animations[animation]
        frame.effect:Play()
        return
    end
    local group = frame:CreateAnimationGroup()
    group:SetLooping(animation == "spin" and "REPEAT" or "BOUNCE")
    local anim
    if animation == "bounce" then
        anim = group:CreateAnimation("Translation"); anim:SetOffset(0, 8)
    elseif animation == "spin" then
        anim = group:CreateAnimation("Rotation"); anim:SetDegrees(360)
    elseif animation == "pulse" then
        anim = group:CreateAnimation("Scale"); anim:SetScale(1.15, 1.15)
    else
        anim = group:CreateAnimation("Alpha"); anim:SetFromAlpha(1); anim:SetToAlpha(0.25)
    end
    anim:SetDuration(animation == "spin" and 1.5 or 0.4)
    frame.effect = group
    frame.animations[animation] = group
    group:Play()
end

function P.Draw(frame, config, output, duration, recipient)
    local nativeEarly = not output.show and not output.ready and config.showBeforeReady and duration
        and duration.EvaluateRemainingDuration and C_CurveUtil
    if not output.show and not nativeEarly then
        if frame.effectKey then P.StopEffects(frame) end
        frame:Hide()
        return
    end
    Effects(frame, config, output.ready or output.encounter)
    frame.texture:SetDesaturated(config.desaturate and not output.ready)
    local text = recipient or config.label
    frame.label:SetText(config.nameLayout ~= "none" and text or "")
    if output.ready then
        frame.cooldown:Clear()
    elseif duration then
        frame.cooldown:SetCooldownFromDurationObject(duration)
    end
    frame:Show()
    if nativeEarly then
        if frame.earlyThreshold ~= config.beforeReadyTime then
            local curve = C_CurveUtil.CreateCurve()
            curve:SetType(Enum.LuaCurveType.Step)
            curve:AddPoint(0, 0)
            curve:AddPoint(0.001, 1)
            curve:AddPoint(config.beforeReadyTime + 0.001, 0)
            frame.earlyCurve, frame.earlyThreshold = curve, config.beforeReadyTime
        end
        -- @secret-safe: curve output goes directly to an alpha sink, never Lua control flow.
        frame:SetAlpha(duration:EvaluateRemainingDuration(frame.earlyCurve))
    else
        frame:SetAlpha(1)
    end
end

-- AuraContainer owns the slot's visibility. Its entire artwork subtree must
-- remain scriptless, including animations: never attach LibCustomGlow here.
function P.Highlight(slot, host, pi, art)
    if not art then
        art = CreateFrame("Frame", nil, slot, "DisableUntrustedLayoutScriptsTemplate")
        art:SetAllPoints(host)
        art.edges = Border(art, { 1, 1, 1, 1 }, 2)
        art.fill = art:CreateTexture(nil, "OVERLAY")
        art.fill:SetAllPoints()
        art.proc = art:CreateTexture(nil, "OVERLAY")
        art.proc:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook")
        art.proc:SetDesaturated(true)
        art.procLoop = art.proc:CreateAnimationGroup()
        art.procLoop:SetLooping("REPEAT")
        art.flip = art.procLoop:CreateAnimation("FlipBook")
        art.flip:SetFlipBookRows(6); art.flip:SetFlipBookColumns(5); art.flip:SetFlipBookFrames(30)
        art.dashes = {}
        for side = 1, 4 do
            for index = 0, 6 do
                local texture = art:CreateTexture(nil, "OVERLAY")
                local group = texture:CreateAnimationGroup()
                group:SetLooping("REPEAT")
                local move = group:CreateAnimation("Translation")
                art.dashes[#art.dashes + 1] = { texture = texture, group = group, move = move, side = side, index = index }
            end
        end
        art.bar = CreateFrame("StatusBar", nil, slot, "DisableUntrustedLayoutScriptsTemplate")
        art.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    end
    local style, color = pi.glowStyle, pi.color
    -- The flipbook includes transparent margins. Match LibCustomGlow's 20%
    -- expansion on each edge so the visible loop surrounds the whole host.
    local paddingX, paddingY = host:GetWidth() * 0.2, host:GetHeight() * 0.2
    art.proc:ClearAllPoints()
    art.proc:SetPoint("TOPLEFT", host, "TOPLEFT", -paddingX, paddingY)
    art.proc:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", paddingX, -paddingY)
    art.fill:SetColorTexture(color[1], color[2], color[3], color[4] * 0.3)
    art.fill:SetShown(style == "fill")
    art.procLoop:Stop()
    art.proc:SetVertexColor(unpack(color)); art.proc:SetShown(style == "proc")
    art.flip:SetDuration(1 / pi.speed)
    if style == "proc" then art.procLoop:Play() end
    for i, edge in ipairs(art.edges) do
        edge:SetColorTexture(unpack(color)); edge:SetShown(style == "border")
        if i < 3 then edge:SetHeight(pi.thickness or 2) else edge:SetWidth(pi.thickness or 2) end
    end
    for _, dash in ipairs(art.dashes) do
        dash.group:Stop()
        dash.texture:SetShown(style == "pixel")
        if style == "pixel" then
            local horizontal = dash.side < 3
            local gap = (horizontal and host:GetWidth() or host:GetHeight()) / 8
            dash.texture:SetColorTexture(unpack(color))
            dash.texture:SetSize(horizontal and gap * 0.55 or pi.thickness, horizontal and pi.thickness or gap * 0.55)
            local point = ({ "TOPLEFT", "BOTTOMLEFT", "TOPLEFT", "TOPRIGHT" })[dash.side]
            dash.texture:ClearAllPoints()
            dash.texture:SetPoint(point, art, point, horizontal and gap * dash.index or 0, horizontal and 0 or -gap * dash.index)
            dash.move:SetOffset(horizontal and gap or 0, horizontal and 0 or -gap)
            dash.move:SetDuration(1 / pi.speed); dash.group:Play()
        end
    end
    art.bar:Hide()
    if slot.ClearDurationBar then slot:ClearDurationBar() end
    if style == "countdown" and slot.SetDurationBar then
        art.bar:ClearAllPoints()
        art.bar:SetPoint(pi.countdownAnchor, host, pi.countdownAnchor)
        art.bar:SetWidth(host:GetWidth()); art.bar:SetHeight(pi.countdownHeight)
        art.bar:SetStatusBarColor(unpack(color))
        slot:SetDurationBar(art.bar, { direction = Enum.StatusBarTimerDirection.RemainingTime })
        art.bar:Show()
    end
    return art
end

function P.Duration(slot, host, config, pi, text)
    slot:ClearDurationText()
    text = text or slot:CreateFontString(nil, "OVERLAY")
    text:ClearAllPoints()
    text:SetPoint(pi.durationAnchor, host, pi.durationAnchor, pi.durationX, pi.durationY)
    Font(text, config, pi.durationSize)
    slot:SetDurationText(text)
    return text
end

function P.AuraIcon(slot, host, config, name, pi, index, view)
    view = view or {}
    local size = config.size
    slot:SetSize(size, size)
    slot:ClearAllPoints()
    -- Fixed recipient positions do not depend on secret aura presence.
    local column, row = (index - 1) % 5, math.floor((index - 1) / 5)
    local spacing = config.nameLayout == "left" or config.nameLayout == "right"
    slot:SetPoint("TOPLEFT", host, "TOPLEFT", (column + 1) * (size + (spacing and 190 or 12)), -row * (size + 22))
    local texture = view.texture or slot:CreateTexture(nil, "ARTWORK")
    view.texture = texture
    texture:SetAllPoints(); texture:SetTexture(C_Spell.GetSpellTexture(config.spellID))
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    view.border = view.border or Border(slot, { 0, 0, 0, 1 }, 1)
    for _, edge in ipairs(view.border) do edge:SetShown(config.showBorder) end
    local text = view.text or slot:CreateFontString(nil, "OVERLAY")
    view.text = text
    text:ClearAllPoints()
    Font(text, config)
    if config.nameLayout == "left" then text:SetPoint("RIGHT", slot, "LEFT", -6, 0)
    elseif config.nameLayout == "right" then text:SetPoint("LEFT", slot, "RIGHT", 6, 0)
    else text:SetPoint("CENTER") end
    text:SetText(config.nameLayout ~= "none" and name or "")
    if pi.alertGlow then
        local opts = { glowStyle = "proc", color = config.glowColor, speed = 1 }
        view.glow = P.Highlight(slot, slot, opts, view.glow)
        view.glow:Show()
    elseif view.glow then view.glow:Hide() end
    return view
end

return P
