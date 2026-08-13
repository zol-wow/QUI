local _, ns = ...

local CDMReanchorRealEnv = {}
ns.CDMReanchorRealEnv = CDMReanchorRealEnv

local _securecall = securecallfunction or function(fn, ...) return fn(...) end
local _issecretvalue = issecretvalue or function() return false end

local function IsBuffIconKey(key)
    return key == "buff" or key == "buffIcon"
end

local _countFontCache = {}

local function _EnsureCountFont(font, sz, outline, color)
    if not CreateFont then return nil end
    sz = (type(sz) == "number" and sz > 0) and sz or 14
    outline = outline or ""
    local ck = ""
    if type(color) == "table" then
        ck = "_" .. math.floor((color[1] or 1) * 255 + 0.5)
            .. "," .. math.floor((color[2] or 1) * 255 + 0.5)
            .. "," .. math.floor((color[3] or 1) * 255 + 0.5)
            .. "," .. math.floor((color[4] or 1) * 255 + 0.5)
    end
    local fk = tostring(font or ""):gsub("[^%w]", "")
    local key = fk .. "_" .. sz .. (outline ~= "" and "_" .. outline or "") .. ck
    local name = _countFontCache[key]
    if not name then
        name = "QUI_CDM_CountFont_" .. key
        CreateFont(name)
        _countFontCache[key] = name
    end
    local fo = _G[name]
    if fo then
        if fo.SetFont and font then
            fo:SetFont(font, sz, outline)
        end
        if fo.SetTextColor then
            local r, g, b, a = 1, 1, 1, 1
            if type(color) == "table" then
                r = color[1] or 1; g = color[2] or 1
                b = color[3] or 1; a = color[4] or 1
            end
            fo:SetTextColor(r, g, b, a)
        end
    end
    return name
end

-- Resolved countdown fontstring per Cooldown widget. applyChrome runs per
-- claimed icon per collect pass, so the resolve (and its GetRegions table)
-- must not re-run on the hot path; misses are retried until the fontstring
-- exists (it is created lazily on the first SetCooldown).
local _cdCountdownFS = setmetatable({}, { __mode = "k" })

local function _CollectRegions(cd)
    return { cd:GetRegions() }
end

local function _ResolveCountdownFontString(cd)
    local fs = _cdCountdownFS[cd]
    if fs then return fs end
    if cd.GetCountdownFontString then
        local ok, got = ns.SafeCallMethod("best-effort-style", cd, "GetCountdownFontString")
        if ok and got and not _issecretvalue(got) then fs = got end
    end
    if not fs and cd.GetRegions then
        local ok, regions = ns.SafeCall("best-effort-style", _CollectRegions, cd)
        if ok and type(regions) == "table" then
            for i = 1, #regions do
                local region = regions[i]
                if region and not _issecretvalue(region)
                    and region.GetObjectType and region:GetObjectType() == "FontString" then
                    fs = region
                    break
                end
            end
        end
    end
    if fs then _cdCountdownFS[cd] = fs end
    return fs
end

local function _AnchorCountdownText(cd, frame, rowConfig)
    if not (cd and frame) then return end
    local fs = _ResolveCountdownFontString(cd)
    if fs and fs.ClearAllPoints and fs.SetPoint then
        fs:ClearAllPoints()
        fs:SetPoint(rowConfig.durationAnchor or "CENTER", frame,
            rowConfig.durationAnchor or "CENTER",
            rowConfig.durationOffsetX or 0, rowConfig.durationOffsetY or 0)
    end
end

local function _ResolveStackText(frame)
    local apps = frame.Applications
    if apps then
        if apps.GetObjectType and apps:GetObjectType() == "FontString" then
            return apps, nil
        end
        local fs = apps.Applications
        if fs and fs.GetObjectType and fs:GetObjectType() == "FontString" then
            return fs, apps
        end
    end
    local charge = frame.ChargeCount
    if charge then
        local fs = charge.Current
        if fs and fs.GetObjectType and fs:GetObjectType() == "FontString" then
            return fs, charge
        end
    end
    return nil, nil
end

local function _StyleStackText(frame, rowConfig, baseFont, outline)
    local fs, holder = _ResolveStackText(frame)
    if not fs then return end
    if rowConfig.hideStackText then
        if holder and holder.SetAlpha then holder:SetAlpha(0) end
        if fs.SetAlpha then fs:SetAlpha(0) end
        return
    end
    if holder and holder.SetAlpha then holder:SetAlpha(1) end
    if fs.SetAlpha then fs:SetAlpha(1) end
    local font = baseFont
    local LSM = ns.LSM
    if LSM and rowConfig.stackFont and rowConfig.stackFont ~= "" then
        font = LSM:Fetch("font", rowConfig.stackFont) or font
    end
    local stackSize = rowConfig.stackSize
    if font and type(stackSize) == "number" and stackSize > 0 then
        local name = _EnsureCountFont(font, stackSize, outline or "",
            rowConfig.stackTextColor or {1, 1, 1, 1})
        if name and fs.SetFontObject then fs:SetFontObject(name) end
    end
    if fs.ClearAllPoints and fs.SetPoint then
        local anchor = rowConfig.stackAnchor or "BOTTOMRIGHT"
        fs:ClearAllPoints()
        fs:SetPoint(anchor, frame, anchor, rowConfig.stackOffsetX or 0, rowConfig.stackOffsetY or 0)
    end
end

local function _DecorateWork(decorator, live, shell, rowConfig)
    if shell and shell.Border and shell.Border.Hide then shell.Border:Hide() end
    return decorator:Decorate(live, rowConfig)
end

local _barHooked = setmetatable({}, { __mode = "k" })

local _barWidgets = setmetatable({}, { __mode = "k" })

local function _ResolveBarIconTexture(live, entry)
    if live and live.Icon and live.Icon.Icon and live.Icon.Icon.GetTexture then
        local ok, t = pcall(live.Icon.Icon.GetTexture, live.Icon.Icon)
        if ok and t and not _issecretvalue(t) then return t end
    end
    local sid = entry and (entry.spellID or entry.overrideSpellID or entry.id)
    if type(sid) == "number" and C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, sid)
        if ok and t and not _issecretvalue(t) then return t end
    end
    return nil
end

local function _EnsureBarWidgets(live)
    if not live then return nil end
    local w = _barWidgets[live]
    if w then return w end
    w = {}
    local bar = live.Bar
    if bar and bar.CreateTexture then
        w.bg = bar:CreateTexture(nil, "BACKGROUND")
    end
    if bar and bar.CreateFontString then
        w.name = bar:CreateFontString(nil, "OVERLAY")
    end
    if live.CreateTexture then
        w.icon = live:CreateTexture(nil, "ARTWORK")
        w.border = live:CreateTexture(nil, "BACKGROUND")
    end
    _barWidgets[live] = w
    return w
end

local function _BarReskinWork(live, settings)
    local bar = live.Bar
    if not bar then return end
    settings = settings or {}
    local showIcon = not settings.hideIcon
    local iconSize = settings.barHeight or 25
    if live.Icon and live.Icon.Hide then live.Icon:Hide() end
    if live.DebuffBorder and live.DebuffBorder.Hide then live.DebuffBorder:Hide() end
    if bar.BarBG and bar.BarBG.Hide then
        bar.BarBG:Hide()
        if bar.BarBG.SetAlpha then bar.BarBG:SetAlpha(0) end
    end
    if bar.Pip and bar.Pip.Hide then
        bar.Pip:Hide()
        if bar.Pip.SetAlpha then bar.Pip:SetAlpha(0) end
    end

    if bar.ClearAllPoints and bar.SetPoint then
        local leftInset = showIcon and (iconSize + 2) or 1
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", live, "TOPLEFT", leftInset, -1)
        bar:SetPoint("BOTTOMRIGHT", live, "BOTTOMRIGHT", -1, 1)
    end

    local LSM = ns.LSM
    if bar.SetStatusBarTexture and LSM and LSM.Fetch then
        local tex = LSM:Fetch("statusbar", settings.texture or "Quazii v5")
            or LSM:Fetch("statusbar", "Quazii v5")
        if tex then bar:SetStatusBarTexture(tex) end
    end
    if bar.SetStatusBarColor then
        local opacity = settings.barOpacity or 1.0
        local r, g, b
        if settings.useClassColor and UnitClass and RAID_CLASS_COLORS then
            local _, class = UnitClass("player")
            -- @secret-policy: collapse-only — UnitClass can return SECRET on 12.1 PTR7
            if _issecretvalue(class) then class = nil end
            local cc = class and RAID_CLASS_COLORS[class]
            if cc then r, g, b = cc.r, cc.g, cc.b end
        end
        if not r then
            local c = settings.barColor or { 0.376, 0.647, 0.980, 1 }
            r, g, b = c[1] or 0.376, c[2] or 0.647, c[3] or 0.980
        end
        bar:SetStatusBarColor(r, g, b, opacity)
    end

    local w = _EnsureBarWidgets(live)
    if w then
        if w.bg then
            local bg = settings.bgColor or { 0, 0, 0, 1 }
            w.bg:SetColorTexture(bg[1] or 0, bg[2] or 0, bg[3] or 0, 1)
            w.bg:ClearAllPoints()
            w.bg:SetAllPoints(bar)
            w.bg:Show()
        end
        if w.icon then
            if showIcon then
                local tex = _ResolveBarIconTexture(live, w.entry)
                if tex then w.icon:SetTexture(tex) end
                w.icon:ClearAllPoints()
                w.icon:SetPoint("LEFT", live, "LEFT", 1, 0)
                local sz = iconSize - 2
                if w.icon.SetSize then w.icon:SetSize(sz, sz) end
                if w.icon.SetTexCoord then w.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
                w.icon:Show()
            elseif w.icon.Hide then
                w.icon:Hide()
            end
        end
        if w.name then
            local Helpers = ns.Helpers
            if Helpers and Helpers.GetGeneralFont and w.name.SetFont then
                local font = Helpers.GetGeneralFont()
                local outline = Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline() or ""
                if font then w.name:SetFont(font, settings.nameSize or 12, outline) end
            end
            local entry = w.entry
            local sid = entry and (entry.spellID or entry.overrideSpellID or entry.id)
            local nm
            if type(sid) == "number" and C_Spell and C_Spell.GetSpellName then
                local ok, n = ns.SafeCall("best-effort-style", C_Spell.GetSpellName, sid)
                if ok and type(n) == "string" then nm = n end
            end
            if nm then
                w.name:SetText(nm)
            elseif bar.Name and bar.Name.GetText then
                w.name:SetText(bar.Name:GetText())
            end
            w.name:ClearAllPoints()
            w.name:SetPoint("LEFT", bar, "LEFT", 4, 0)
            if w.name.SetJustifyH then w.name:SetJustifyH("LEFT") end
            w.name:Show()
            if bar.Name and bar.Name.SetAlpha then bar.Name:SetAlpha(0) end
        end
        if w.border then
            local Helpers = ns.Helpers
            local Core = ns.Addon or _G.QUI
            local borderSize = settings.borderSize or 0
            if borderSize > 0 then
                local bs = (Core and Core.Pixels) and Core:Pixels(borderSize, live) or borderSize
                local r, g, b, a = 0, 0, 0, 1
                if Helpers and Helpers.GetSkinBorderColor then
                    r, g, b, a = Helpers.GetSkinBorderColor(settings, "")
                end
                w.border:SetColorTexture(r, g, b, a)
                w.border:ClearAllPoints()
                w.border:SetPoint("TOPLEFT", live, "TOPLEFT", -bs, bs)
                w.border:SetPoint("BOTTOMRIGHT", live, "BOTTOMRIGHT", bs, -bs)
                w.border:Show()
            elseif w.border.Hide then
                w.border:Hide()
            end
        end
    end
end

local function _BarDecorateWork(live, shell, settings)
    if live and live.SetAlpha then live:SetAlpha(1) end
    local w = _EnsureBarWidgets(live)
    if w then w.entry = (shell and shell._spellEntry) or nil end
    _BarReskinWork(live, settings)
end

CDMReanchorRealEnv._DecorateWork    = _DecorateWork
CDMReanchorRealEnv._BarDecorateWork = _BarDecorateWork
CDMReanchorRealEnv._BarReskinWork   = _BarReskinWork

local function _InstallBarReskinHooks(live, getSettingsFn, key)
    if _barHooked[live] or not hooksecurefunc then return end
    _barHooked[live] = true
    local function reapply()
        _BarReskinWork(live, getSettingsFn and getSettingsFn(key) or nil)
    end
    if live.SetBarContent then hooksecurefunc(live, "SetBarContent", function() _securecall(reapply) end) end
    if live.SetBarWidth then hooksecurefunc(live, "SetBarWidth", function() _securecall(reapply) end) end
    local function hideOnShow(region)
        if region and region.Show then
            hooksecurefunc(region, "Show", function(self)
                _securecall(function()
                    if self.Hide then self:Hide() end
                    if self.SetAlpha then self:SetAlpha(0) end
                end)
            end)
        end
    end
    if live.Bar then
        hideOnShow(live.Bar.Pip)
        hideOnShow(live.Bar.BarBG)
    end
    hideOnShow(live.DebuffBorder)
end

function CDMReanchorRealEnv.BuildEnv(ctx)
    ctx = ctx or {}
    local Containers = ctx.CDMContainers or ns.CDMContainers
    local SpellData  = ctx.CDMSpellData or ns.CDMSpellData
    local Layout     = ctx.CDMLayout or ns.CDMLayout
    local Icons      = ctx.CDMIcons or ns.CDMIcons
    local Factory    = ctx.CDMIconFactory or ns.CDMIconFactory
    local Sources    = ctx.CDMSources or ns.CDMSources
    local Core       = ctx.core or _G.QUI
    local DecorateMod = ctx.CDMReanchorDecorate or ns.CDMReanchorDecorate

    local Helpers = ns.Helpers
    local _chrome = setmetatable({}, { __mode = "k" })
    local function applyChrome(frame, rowConfig, _firstChrome)
        if frame and frame.SetAlpha then frame:SetAlpha(1) end
        if Icons and Icons.NeutralizeBlizzardItemChrome then
            Icons.NeutralizeBlizzardItemChrome(frame, rowConfig)
        end
        if type(rowConfig) ~= "table" then return end
        local cd = frame.Cooldown
        if cd then
            if cd.SetSwipeTexture then cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8") end
            if cd.SetDrawBling then cd:SetDrawBling(false) end
        end
        local generalFont, generalOutline
        if Helpers and Helpers.GetGeneralFont then
            generalFont = Helpers.GetGeneralFont()
            generalOutline = Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline() or ""
        end
        if generalFont then
            local durationFont = generalFont
            local LSM = ns.LSM
            if LSM and rowConfig.durationFont and rowConfig.durationFont ~= "" then
                durationFont = LSM:Fetch("font", rowConfig.durationFont) or durationFont
            end
            local dtc = rowConfig.durationTextColor or {1, 1, 1, 1}
            local countFontName = _EnsureCountFont(durationFont, rowConfig.durationSize or 14, generalOutline, dtc)
            if cd and cd.SetCountdownFont and countFontName then
                cd:SetCountdownFont(countFontName)
            end
        end
        if cd and cd.SetHideCountdownNumbers then
            cd:SetHideCountdownNumbers(rowConfig.hideDurationText and true or false)
        end
        if not rowConfig.hideDurationText then
            _AnchorCountdownText(cd, frame, rowConfig)
        end
        _StyleStackText(frame, rowConfig, generalFont, generalOutline)
        local lvlOk, baseLvl = ns.SafeCallMethod("best-effort-style", frame, "GetFrameLevel")
        if lvlOk and type(baseLvl) == "number" then
            local textLvl = baseLvl + 23
            local apps = frame.Applications
            ns.SafeCallMethodIfPresent("best-effort-style", apps, "SetFrameLevel", textLvl)
            local charge = frame.ChargeCount
            ns.SafeCallMethodIfPresent("best-effort-style", charge, "SetFrameLevel", textLvl)
        end
        if frame.CreateTexture then
            local chrome = _chrome[frame]
            if not chrome then
                chrome = { border = frame:CreateTexture(nil, "BACKGROUND") }
                _chrome[frame] = chrome
            end
            local tex = chrome.border
            local borderSize = rowConfig.borderSize or 0
            if borderSize > 0 and tex then
                local bs = (Core and Core.Pixels) and Core:Pixels(borderSize, frame) or borderSize
                local r, g, b, a = 0, 0, 0, 1
                if Helpers and Helpers.GetSkinBorderColor then
                    r, g, b, a = Helpers.GetSkinBorderColor(rowConfig, "")
                end
                tex:SetColorTexture(r, g, b, a)
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", frame, "TOPLEFT", -bs, bs)
                tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", bs, -bs)
                tex:Show()
            elseif tex then
                tex:Hide()
            end
        end
    end

    local decorator
    if DecorateMod and DecorateMod.New then
        decorator = DecorateMod.New({
            hideRegion = function(frame, name)
                local region = frame[name]
                if not region then return end
                if region.SetAlpha then region:SetAlpha(0) end
                if region.Hide then region:Hide() end
            end,
            applyChrome = applyChrome,
        })
    end
    local decorate = function(live, shell, rowConfig, key)
        if key == "trackedBar" then
            _securecall(_BarDecorateWork, live, shell, ctx.getSettings and ctx.getSettings(key) or nil)
            _InstallBarReskinHooks(live, ctx.getSettings, key)
            return true
        end
        if decorator then
            return _securecall(_DecorateWork, decorator, live, shell, rowConfig)
        end
    end

    local shellPools = setmetatable({}, { __mode = "k" })
    local function getShellPool(container)
        local p = shellPools[container]
        if not p then p = { list = {}, used = 0, generation = 0 }; shellPools[container] = p end
        return p
    end

    local function isInCombatLockdown()
        if ctx.isInCombat then return ctx.isInCombat() end
        return (InCombatLockdown and InCombatLockdown()) or false
    end

    local function isInitSafeWindow()
        if ctx.isInitSafeWindow then return ctx.isInitSafeWindow() end
        return ns._inInitSafeWindow == true
    end

    local function canMutateProtectedShells(frame)
        if (not isInCombatLockdown()) or isInitSafeWindow() then return true end
        if not (frame and Helpers) then return false end
        return not (Helpers.FrameIsProtected(frame)
            or Helpers.FrameIsAnchoringRestricted(frame))
    end

    local function hideShell(shell)
        if not shell then return end
        local overlay = shell._quiCdmHoverOverlay
        if overlay and overlay.Hide and ((not overlay.IsShown) or overlay:IsShown()) then
            overlay:Hide()
        end
        if shell.Hide and ((not shell.IsShown) or shell:IsShown()) then
            shell:Hide()
        end
        shell._spellEntry = nil
        shell._quiTooltipContext = nil
        shell.__quiTooltipContext = nil
        shell.__customTrackerIcon = nil
    end

    local function beginShellPass(container)
        local p = getShellPool(container)
        p.generation = (p.generation or 0) + 1
        p.used = 0
        return p.generation
    end

    local function endShellPass(container)
        local p = shellPools[container]
        if not p then return true end
        if not canMutateProtectedShells() then
            p.cleanupPending = true
            return false
        end
        local generation = p.generation or 0
        for i = 1, #p.list do
            local shell = p.list[i]
            if shell and shell._quiCdmShellGeneration ~= generation then
                hideShell(shell)
            end
        end
        p.cleanupPending = nil
        return true
    end

    local function resetShells(container)
        local p = shellPools[container]
        if not p then return end
        if not canMutateProtectedShells() then
            p.cleanupPending = true
            return false
        end
        for i = 1, #p.list do
            local s = p.list[i]
            hideShell(s)
        end
        p.used = 0
        return true
    end
    local function getContainerFor(key)
        if Containers and Containers.GetContainer then return Containers.GetContainer(key) end
        return nil
    end

    local function getShellTooltipContext(_containerKey)
        return "cdm"
    end

    local function runShellTooltipScript(shell, scriptName)
        if not (shell and shell.GetScript) then return end
        local script = shell:GetScript(scriptName)
        if script then script(shell) end
    end

    local function ensureHoverOverlay(shell)
        if not (shell and shell.CreateTexture and CreateFrame) then return nil end
        local overlay = shell._quiCdmHoverOverlay
        if not overlay then
            overlay = CreateFrame("Frame", nil, shell)
            overlay._quiCdmHoverOverlay = true
            overlay:SetAllPoints(shell)
            overlay:EnableMouse(true)
            if overlay.SetMouseClickEnabled then
                overlay:SetMouseClickEnabled(false)
            end
            if overlay.SetMouseMotionEnabled then
                overlay:SetMouseMotionEnabled(true)
            end
            overlay:SetScript("OnEnter", function(self)
                runShellTooltipScript(self:GetParent(), "OnEnter")
            end)
            overlay:SetScript("OnLeave", function(self)
                runShellTooltipScript(self:GetParent(), "OnLeave")
            end)
            shell._quiCdmHoverOverlay = overlay
        end
        overlay:SetAllPoints(shell)
        overlay:Show()
        return overlay
    end

    local function raiseHoverOverlay(shell)
        local overlay = shell and shell._quiCdmHoverOverlay
        if not overlay then return end
        if overlay.SetFrameStrata and shell.GetFrameStrata then
            overlay:SetFrameStrata(shell:GetFrameStrata())
        end
        if overlay.SetFrameLevel and shell.GetFrameLevel then
            overlay:SetFrameLevel(shell:GetFrameLevel() + 4)
        end
    end

    local function ensureShellTooltip(shell)
        if not shell then return end
        if not shell._quiCdmTooltipWired then
            shell._quiCdmTooltipWired = true
            shell:EnableMouse(true)
            if shell.SetMouseClickEnabled then
                shell:SetMouseClickEnabled(false)
            end
            if shell.SetMouseMotionEnabled then
                shell:SetMouseMotionEnabled(true)
            end
            shell:SetScript("OnEnter", function(self)
                local Factory = ns.CDMIconFactory
                if Factory and Factory.ShowEntryTooltip then
                    Factory.ShowEntryTooltip(self, self._spellEntry, self._quiTooltipContext or "cdm")
                end
            end)
            shell:SetScript("OnLeave", function()
                local Factory = ns.CDMIconFactory
                if Factory and Factory.HideEntryTooltip then
                    Factory.HideEntryTooltip()
                elseif GameTooltip and GameTooltip.Hide then
                    GameTooltip.Hide(GameTooltip)
                end
            end)
        end
        ensureHoverOverlay(shell)
    end

    local _liveTooltip = setmetatable({}, { __mode = "k" })
    local function ensureLiveTooltip(live, entry)
        if not (live and CreateFrame) then return nil end
        local overlay = _liveTooltip[live]
        if not overlay then
            overlay = CreateFrame("Frame", nil, live)
            overlay:SetAllPoints(live)
            overlay:EnableMouse(true)
            if overlay.SetMouseClickEnabled then
                overlay:SetMouseClickEnabled(false)
            end
            if overlay.SetMouseMotionEnabled then
                overlay:SetMouseMotionEnabled(true)
            end
            if overlay.SetFrameLevel then
                local baseLevel = (live.GetFrameLevel and live:GetFrameLevel()) or 0
                overlay:SetFrameLevel(baseLevel + 4)
            end
            overlay:SetScript("OnEnter", function(self)
                local Factory = ns.CDMIconFactory
                if Factory and Factory.ShowEntryTooltip then
                    Factory.ShowEntryTooltip(self, self._entry, "cdm")
                end
            end)
            overlay:SetScript("OnLeave", function()
                local Factory = ns.CDMIconFactory
                if Factory and Factory.HideEntryTooltip then
                    Factory.HideEntryTooltip()
                elseif GameTooltip and GameTooltip.Hide then
                    GameTooltip.Hide(GameTooltip)
                end
            end)
            _liveTooltip[live] = overlay
        end
        overlay._entry = entry
        overlay:SetAllPoints(live)
        overlay:EnableMouse(true)
        overlay:Show()
        return overlay
    end

    local function hideLiveTooltip(live)
        if not live then return end
        local overlay = _liveTooltip[live]
        if not overlay then return end
        overlay:Hide()
        overlay:EnableMouse(false)
    end

    local function mintClickSlot(_entry, containerKey)
        local container = getContainerFor(containerKey)
        if not container then return nil end
        local p = getShellPool(container)
        local nextIndex = (p.used or 0) + 1
        local slot = p.list[nextIndex]
        if not slot then
            if not canMutateProtectedShells(container) then
                p.cleanupPending = true
                return nil
            end
            slot = CreateFrame("Frame", nil, container)
            slot._quiCdmClickSlot = true
            p.list[nextIndex] = slot
        elseif slot.IsShown and not slot:IsShown() and not canMutateProtectedShells(slot) then
            p.cleanupPending = true
            return nil
        end
        p.used = nextIndex
        slot._quiCdmShellGeneration = p.generation or 0
        local tooltipContext = getShellTooltipContext(containerKey)
        slot._spellEntry = _entry
        slot._quiTooltipContext = tooltipContext
        slot.__quiTooltipContext = tooltipContext
        slot.__customTrackerIcon = nil
        if canMutateProtectedShells(slot) then
            ensureShellTooltip(slot)
        end
        if slot.Show and ((not slot.IsShown) or not slot:IsShown()) then
            slot:Show()
        end
        return slot
    end
    local function positionClickSlot(container, live, entry, containerKey, x, y, w, h)
        if not (container and live and w and h) then return nil end
        local slot = mintClickSlot(entry, containerKey)
        if not slot then return nil end
        if not canMutateProtectedShells(slot) then
            return nil
        end
        slot:ClearAllPoints()
        slot:SetPoint("CENTER", container, "CENTER", x, y)
        if slot.SetSize then slot:SetSize(w, h) end
        if slot.SetFrameStrata then
            local strata = (live.GetFrameStrata and live:GetFrameStrata())
                or (container.GetFrameStrata and container:GetFrameStrata())
            if strata then slot:SetFrameStrata(strata) end
        end
        if slot.SetFrameLevel then
            local liveLevel = live.GetFrameLevel and live:GetFrameLevel()
            local containerLevel = container.GetFrameLevel and container:GetFrameLevel()
            slot:SetFrameLevel(((liveLevel or containerLevel or 0) + 8))
        end
        raiseHoverOverlay(slot)
        return slot
    end
    local function updateClickOverlay(shell, entry, viewerType)
        if Icons and Icons.UpdateSecureClickOverlay then
            Icons.UpdateSecureClickOverlay(shell, entry, viewerType)
        end
    end

    local function entryAuraIsPresent(entry)
        if type(entry) ~= "table" then return false end
        local query = Sources and Sources.QueryPlayerAuraBySpellID
        if not query then return false end
        local function present(id)
            if type(id) ~= "number" or _issecretvalue(id) then return false end
            local ok, aura = pcall(query, id)
            return (ok and not _issecretvalue(aura) and aura ~= nil) or false
        end
        if present(entry.overrideSpellID) or present(entry.spellID) or present(entry.id) then
            return true
        end
        local linked = entry.linkedSpellIDs
        if type(linked) == "table" then
            for i = 1, #linked do
                if present(linked[i]) then return true end
            end
        end
        return false
    end

    local function rowConfigForEntry(entry, containerKey)
        local settings = ctx.getSettings and ctx.getSettings(containerKey) or {}
        if Layout and Layout.BuildRows then
            local rows = Layout.BuildRows(settings)
            local wanted = entry and entry._assignedRow
            for i = 1, #rows do
                if rows[i].rowNum == wanted then return rows[i] end
            end
            if rows[1] then return rows[1] end
        end
        return {
            size = settings.iconSize or 42,
            borderSize = settings.borderSize or 2,
            borderColorSource = settings.borderColorSource,
            borderColor = settings.borderColor or settings.borderColorTable,
            durationSize = settings.durationSize or 14,
            durationOffsetX = settings.durationOffsetX or 0,
            durationOffsetY = settings.durationOffsetY or 8,
            durationTextColor = settings.durationTextColor,
            durationAnchor = settings.durationAnchor or "TOP",
            hideDurationText = settings.hideDurationText,
            stackSize = settings.stackSize or 14,
            stackOffsetX = settings.stackOffsetX or 0,
            stackOffsetY = settings.stackOffsetY or -8,
            stackTextColor = settings.stackTextColor,
            stackAnchor = settings.stackAnchor or "BOTTOM",
            hideStackText = settings.hideStackText,
        }
    end

    local function auraProfileFromRow(rowConfig)
        rowConfig = rowConfig or {}
        local br, bg, bb, ba = 0, 0, 0, 1
        if Helpers and Helpers.GetSkinBorderColor then
            br, bg, bb, ba = Helpers.GetSkinBorderColor(rowConfig, "")
        elseif type(rowConfig.borderColor) == "table" then
            br, bg, bb, ba = rowConfig.borderColor[1] or 0,
                rowConfig.borderColor[2] or 0, rowConfig.borderColor[3] or 0,
                rowConfig.borderColor[4] or 1
        end
        return {
            iconSize = rowConfig.size or 42,
            borderColor = { br, bg, bb, ba },
            duration = {
                fontSize = rowConfig.durationSize or 14,
                anchor = rowConfig.durationAnchor or "CENTER",
                offsetX = rowConfig.durationOffsetX or 0,
                offsetY = rowConfig.durationOffsetY or 0,
                color = rowConfig.durationTextColor,
                show = rowConfig.hideDurationText ~= true,
            },
            stack = {
                fontSize = rowConfig.stackSize or 14,
                anchor = rowConfig.stackAnchor or "BOTTOMRIGHT",
                offsetX = rowConfig.stackOffsetX or 0,
                offsetY = rowConfig.stackOffsetY or 0,
                color = rowConfig.stackTextColor,
                show = rowConfig.hideStackText ~= true,
            },
        }
    end

    local auraMirrors
    if ns.CDMManagedAuraMirrors and ns.CDMManagedAuraMirrors.New then
        auraMirrors = ns.CDMManagedAuraMirrors.New({
            createFrame = CreateFrame,
            isSecret = _issecretvalue,
            canCreate = function()
                return (not isInCombatLockdown()) or isInitSafeWindow()
            end,
            canMutate = canMutateProtectedShells,
            aurasAreSecret = function()
                return C_Secrets and C_Secrets.ShouldAurasBeSecret
                    and C_Secrets.ShouldAurasBeSecret() or false
            end,
            styleFrame = function(frame, profile)
                local skin = ns.AuraSkin or (ns.Addon and ns.Addon.AuraSkin)
                if skin and skin.WireButton then skin.WireButton(frame, profile) end
            end,
            restyleFrame = function(frame, rowConfig)
                local skin = ns.AuraSkin or (ns.Addon and ns.Addon.AuraSkin)
                if skin and skin.WireButton then
                    skin.WireButton(frame, auraProfileFromRow(rowConfig))
                end
            end,
            positionBase = function(icon, host, rowConfig)
                if icon.GetScale and icon:GetScale() ~= 1 then icon:SetScale(1) end
                icon:ClearAllPoints()
                icon:SetPoint("CENTER", host, "CENTER", 0, 0)
                icon:Show()
                if Icons and Icons.OnContainerIconPlaced then
                    Icons.OnContainerIconPlaced(icon, rowConfig)
                end
            end,
        })
    end

    local function beginAuraMirrorPass(container)
        return auraMirrors and auraMirrors:BeginPass(container) or false
    end

    local function acquireAuraMirror(entry, containerKey, placementKey)
        if not auraMirrors then return nil end
        local swipe = ns._OwnedSwipe and ns._OwnedSwipe.GetSettings
            and ns._OwnedSwipe.GetSettings() or nil
        if swipe and swipe.showCooldownIconAuraPhase == false then return nil end
        local container = getContainerFor(containerKey)
        if not container then return nil end
        local profile = auraProfileFromRow(rowConfigForEntry(entry, containerKey))
        return auraMirrors:Acquire(container, placementKey, entry, profile)
    end

    local function positionAuraMirror(record, baseIcon, container, x, y, w, h, rowConfig)
        return auraMirrors and auraMirrors:Position(
            record, baseIcon, container, x, y, w, h, rowConfig) or false
    end

    local function endAuraMirrorPass(container)
        return auraMirrors and auraMirrors:EndPass(container) or true
    end

    return {
        CDMReanchor        = ns.CDMReanchor,
        CDMReanchorWiring  = ns.CDMReanchorWiring,
        CDMReanchorRuntime = ns.CDMReanchorRuntime,
        CDMPlacementPlanner = ns.CDMPlacementPlanner,
        uiParent = ctx.uiParent or _G.UIParent,
        index = ctx.CDMIndex or ns.CDMIndex,
        getContainer = function(key)
            if Containers and Containers.GetContainer then return Containers.GetContainer(key) end
            return nil
        end,
        getCurated = function(key)
            if SpellData and SpellData.BuildSpellListFromOwned then
                return SpellData:BuildSpellListFromOwned(key)
            end
            return {}
        end,
        getSettings = ctx.getSettings,
        resolveAdditional = ctx.resolveAdditional or function() return {} end,
        onMetrics = ctx.onMetrics,
        canMutate = canMutateProtectedShells,
        buildLayout = Layout and Layout.BuildIconLayout or nil,
        buildBuffLayout = Layout and function(s, icons, opts, key)
            if key == "trackedBar" and Layout.BuildBuffBarLayout then
                return Layout.BuildBuffBarLayout(s, icons, opts)
            end
            return (Layout.BuildBuffGridLayout and Layout.BuildBuffGridLayout(s, icons, opts)) or nil
        end or nil,
        frameIsActive = function(frame, containerKey, entry)
            if not frame then return true end
            if IsBuffIconKey(containerKey) then
                if frame.IsActive then
                    local ok, active = pcall(frame.IsActive, frame)
                    if ok and not _issecretvalue(active) then
                        return active and true or false
                    end
                end
                if frame.IsShown then
                    local ok, shown = pcall(frame.IsShown, frame)
                    if not ok then return true end
                    if _issecretvalue(shown) then return true end -- @secret-policy: keep-visible-when-unknown
                    return shown and true or false
                end
                return true
            end
            if not frame.IsActive then return true end
            local ok, active = pcall(frame.IsActive, frame)
            if not ok then return true end
            if _issecretvalue(active) then return true end -- @secret-policy: keep-visible-when-unknown
            return active and true or false
        end,
        entryAuraIsPresent = entryAuraIsPresent,
        inCombat = function() return isInCombatLockdown() end,
        isEditMode = function()
            if Helpers and Helpers.IsLayoutModeActive and Helpers.IsLayoutModeActive() then
                return true
            end
            local cdmEdit = _G.QUI_IsCDMEditModeActive
            if cdmEdit and cdmEdit() then return true end
            return false
        end,
        pixelRound = function(v, c)
            if Core and Core.PixelRound then return Core:PixelRound(v, c) end
            return v
        end,
        acquireIcon = function(c, e, containerKey)
            if not (Factory and Factory.AcquireIcon) then return nil end
            local clickable = false
            if containerKey and ctx.getSettings then
                local s = ctx.getSettings(containerKey)
                clickable = (s and s.clickableIcons) and true or false
            end
            local icon = Factory:AcquireIcon(c, e, clickable)
            if icon and containerKey and Factory.EnsurePool then
                local pool = Factory:EnsurePool(containerKey)
                pool[#pool + 1] = icon
            end
            return icon
        end,
        releaseIcon = function(icon, containerKey)
            if not (Factory and Factory.ReleaseIcon) then return end
            local ok = Factory:ReleaseIcon(icon)
            if ok == false then return false end
            if containerKey and Factory.GetIconPool then
                local pool = Factory:GetIconPool(containerKey)
                for i = #pool, 1, -1 do
                    if pool[i] == icon then
                        table.remove(pool, i)
                        break
                    end
                end
            end
            return ok
        end,
        onIconPlaced = function(icon, rowConfig)
            if Icons and Icons.OnContainerIconPlaced then Icons.OnContainerIconPlaced(icon, rowConfig) end
        end,
        decorate = decorate,
        applyChrome = applyChrome,
        positionClickSlot = positionClickSlot,
        beginAuraMirrorPass = beginAuraMirrorPass,
        acquireAuraMirror = acquireAuraMirror,
        positionAuraMirror = positionAuraMirror,
        endAuraMirrorPass = endAuraMirrorPass,
        ensureLiveTooltip = ensureLiveTooltip,
        hideLiveTooltip = hideLiveTooltip,
        updateClickOverlay = updateClickOverlay,
        beginShellPass = beginShellPass,
        endShellPass = endShellPass,
        resetShells = resetShells,
    }
end
