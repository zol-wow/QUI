local ADDON_NAME, ns = ...

local UISmoke = ns.UISmoke or {}
local suites = UISmoke._suites or {}
local lastResult = UISmoke._lastResult

UISmoke._suites = suites

local PREFIX = "|cff60A5FAQUI UI smoke:|r "

local function Now()
    if type(GetTime) == "function" then
        return GetTime()
    end
    return os.clock and os.clock() or 0
end

local function Trim(value)
    value = value and tostring(value) or ""
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Lower(value)
    return string.lower(Trim(value))
end

local function PrintLine(printer, line)
    printer = printer or print
    printer(PREFIX .. tostring(line))
end

local function LocalSafeCall(object, method, ...)
    if not object or type(object[method]) ~= "function" then
        return false
    end
    return pcall(object[method], object, ...)
end

local function SafeFrameValue(frame, method)
    local ok, value = LocalSafeCall(frame, method)
    if ok then
        return value
    end
    return nil
end

local function FrameName(frame)
    if not frame then
        return "nil"
    end
    local name = SafeFrameValue(frame, "GetName")
    return name or tostring(frame)
end

local function IsShown(frame)
    local shown = SafeFrameValue(frame, "IsShown")
    return shown and true or false
end

local function IsVisible(frame)
    local visible = SafeFrameValue(frame, "IsVisible")
    return visible and true or false
end

local function TextureAlpha(texture)
    if not texture then
        return nil
    end
    local alpha = SafeFrameValue(texture, "GetAlpha")
    if type(alpha) == "number" then
        return alpha
    end
    return nil
end

local function DescribeFrame(frame)
    if not frame then
        return { frame = "nil" }
    end

    local details = {
        frame = FrameName(frame),
        shown = IsShown(frame),
        visible = IsVisible(frame),
    }

    local alpha = SafeFrameValue(frame, "GetAlpha")
    if type(alpha) == "number" then
        details.alpha = string.format("%.2f", alpha)
    end

    local strata = SafeFrameValue(frame, "GetFrameStrata")
    if strata then
        details.strata = strata
    end

    local level = SafeFrameValue(frame, "GetFrameLevel")
    if type(level) == "number" then
        details.level = level
    end

    local points = SafeFrameValue(frame, "GetNumPoints")
    if type(points) == "number" then
        details.points = points
    end

    return details
end

local function FormatFields(fields)
    if type(fields) ~= "table" then
        return tostring(fields)
    end

    local keys = {}
    for key in pairs(fields) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)

    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = tostring(key) .. "=" .. tostring(fields[key])
    end
    return table.concat(parts, " ")
end

local function AddFailure(result, step, message, details)
    local failure = {
        step = step and step.name or nil,
        message = tostring(message or "assertion failed"),
        details = details,
    }
    result.failures[#result.failures + 1] = failure

    if step then
        if step.status ~= "FAIL" then
            step.status = "FAIL"
            result.failed = result.failed + 1
        end
    else
        result.failed = result.failed + 1
    end
end

local function NewResult(suiteName)
    return {
        suite = suiteName,
        status = "RUNNING",
        startedAt = Now(),
        endedAt = nil,
        duration = 0,
        steps = {},
        passed = 0,
        failed = 0,
        skipped = 0,
        failures = {},
        details = {},
    }
end

function UISmoke.ParseCommand(input)
    input = Trim(input)
    if input == "" or input == "help" or input == "status" then
        return { action = "help" }
    end

    local cmd, rest = input:match("^(%S+)%s*(.-)$")
    cmd = Lower(cmd)
    rest = Trim(rest)

    if cmd == "list" then
        return { action = "list" }
    end

    if cmd == "last" then
        return { action = "last" }
    end

    if cmd == "run" then
        if rest == "" then
            return { action = "help", error = "missing suite for run" }
        end
        return { action = "run", suite = Lower(rest) }
    end

    return { action = "help", error = "unknown command '" .. tostring(cmd) .. "'" }
end

function UISmoke.RegisterSuite(name, fn, opts)
    name = Lower(name)
    if name == "" or name == "all" then
        return false, "invalid suite name"
    end
    if type(fn) ~= "function" then
        return false, "suite must be a function"
    end

    opts = opts or {}
    suites[name] = {
        name = name,
        fn = fn,
        description = opts.description,
    }
    return true
end

function UISmoke.ListSuites()
    local names = {}
    for name in pairs(suites) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

function UISmoke.StoreResult(result)
    lastResult = result
    UISmoke._lastResult = result
    return result
end

function UISmoke.GetLastResult()
    return lastResult
end

function UISmoke.FormatResult(result)
    if not result then
        return { "no result yet" }
    end

    local duration = tonumber(result.duration) or 0
    local firstFailure = result.failures and result.failures[1]
    local suffix = ""
    if firstFailure then
        suffix = string.format(" first: %s%s",
            firstFailure.step and (firstFailure.step .. " - ") or "",
            firstFailure.message or "failed")
    end

    local lines = {
        string.format("%s %s: %d pass, %d fail, %d skip, %.2fs%s",
            result.status or "UNKNOWN",
            result.suite or "?",
            result.passed or 0,
            result.failed or 0,
            result.skipped or 0,
            duration,
            suffix),
    }

    if firstFailure and firstFailure.details then
        lines[#lines + 1] = "  detail: " .. FormatFields(firstFailure.details)
    end

    if result.details then
        for _, detail in ipairs(result.details) do
            lines[#lines + 1] = "  " .. tostring(detail.label or "detail") .. ": " .. FormatFields(detail.fields)
        end
    end

    return lines
end

local function PrintResult(result, printer)
    local lines = UISmoke.FormatResult(result)
    for _, line in ipairs(lines) do
        PrintLine(printer, line)
    end
end

local function FinishResult(result, opts)
    if result.status == "RUNNING" then
        result.status = result.failed > 0 and "FAIL" or "PASS"
    end
    result.endedAt = Now()
    result.duration = math.max(0, result.endedAt - result.startedAt)
    UISmoke.StoreResult(result)

    if not (opts and opts.quiet) then
        PrintResult(result, opts and opts.print)
    end
    if opts and type(opts.onDone) == "function" then
        opts.onDone(result)
    end
    return result
end

local function NewContext(result, opts)
    local ctx = {
        result = result,
        opts = opts or {},
        _pending = 0,
        _finishWhenIdle = false,
        _finished = false,
        _currentStep = nil,
    }

    function ctx:Detail(label, fields)
        self.result.details[#self.result.details + 1] = {
            label = label,
            fields = fields,
        }
    end

    function ctx:Assert(condition, message, details)
        if condition then
            return true
        end
        AddFailure(self.result, self._currentStep, message, details)
        return false
    end

    function ctx:Skip(message, details)
        local step = self._currentStep
        if step and step.status == "PASS" then
            step.status = "SKIP"
            self.result.skipped = self.result.skipped + 1
            step.message = message
            step.details = details
        else
            self.result.skipped = self.result.skipped + 1
            self.result.steps[#self.result.steps + 1] = {
                name = tostring(message or "skipped"),
                status = "SKIP",
                details = details,
            }
        end
        return false
    end

    function ctx:Step(name, fn)
        local step = {
            name = tostring(name or "step"),
            status = "PASS",
        }
        self.result.steps[#self.result.steps + 1] = step

        local previous = self._currentStep
        self._currentStep = step
        local ok, err = pcall(fn)
        self._currentStep = previous

        if not ok then
            AddFailure(self.result, step, "lua error: " .. tostring(err))
        end

        if step.status == "PASS" then
            self.result.passed = self.result.passed + 1
        end

        return step.status == "PASS"
    end

    function ctx:WaitFor(name, predicate, timeout, interval, callback)
        local step = {
            name = tostring(name or "wait"),
            status = "RUNNING",
        }
        self.result.steps[#self.result.steps + 1] = step
        self._pending = self._pending + 1

        timeout = tonumber(timeout) or 2
        interval = tonumber(interval) or 0.1
        local startedAt = Now()

        local function complete(ok, message, details)
            if step.status ~= "RUNNING" then
                return
            end

            if ok then
                step.status = "PASS"
                self.result.passed = self.result.passed + 1
            else
                AddFailure(self.result, step, message or ("timeout waiting for " .. step.name), details)
            end

            self._pending = math.max(0, self._pending - 1)
            if type(callback) == "function" then
                callback(ok)
            end
            if self._finishWhenIdle and self._pending == 0 then
                self:Finish()
            end
        end

        local function poll()
            local ok, hitOrErr = pcall(predicate)
            if ok and hitOrErr then
                complete(true)
                return
            end
            if not ok then
                complete(false, "wait predicate error: " .. tostring(hitOrErr))
                return
            end
            if Now() - startedAt >= timeout then
                complete(false, "timeout waiting for " .. step.name)
                return
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(interval, poll)
            else
                complete(false, "C_Timer.After unavailable")
            end
        end

        poll()
        return true
    end

    function ctx:Finish()
        if self._finished then
            return self.result
        end
        if self._pending > 0 then
            self._finishWhenIdle = true
            return nil
        end
        self._finished = true
        return FinishResult(self.result, self.opts)
    end

    return ctx
end

function UISmoke.RunSuite(name, opts)
    name = Lower(name)
    if name == "all" then
        return UISmoke.RunAll(opts)
    end

    local suite = suites[name]
    if not suite then
        local result = NewResult(name ~= "" and name or "?")
        AddFailure(result, nil, "unknown suite '" .. tostring(name) .. "'")
        return FinishResult(result, opts)
    end

    local result = NewResult(name)
    local ctx = NewContext(result, opts)

    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        AddFailure(result, nil, "cannot run UI smoke suites in combat")
        return ctx:Finish()
    end

    local ok, asyncOrErr = pcall(suite.fn, ctx)
    if not ok then
        AddFailure(result, nil, "suite error: " .. tostring(asyncOrErr))
        return ctx:Finish()
    end

    if asyncOrErr == true or ctx._pending > 0 then
        return nil
    end
    return ctx:Finish()
end

function UISmoke.RunAll(opts)
    local names = UISmoke.ListSuites()
    local aggregate = NewResult("all")
    local index = 1
    local finalResult

    local function finish()
        aggregate.status = aggregate.failed > 0 and "FAIL" or "PASS"
        finalResult = FinishResult(aggregate, opts)
        return finalResult
    end

    local function absorb(result)
        aggregate.steps[#aggregate.steps + 1] = {
            name = result.suite,
            status = result.status == "PASS" and "PASS" or "FAIL",
        }
        if result.status == "PASS" then
            aggregate.passed = aggregate.passed + 1
        else
            aggregate.failed = aggregate.failed + 1
            if result.failures and result.failures[1] then
                aggregate.failures[#aggregate.failures + 1] = result.failures[1]
            end
        end
        aggregate.skipped = aggregate.skipped + (result.skipped or 0)
    end

    local function runNext()
        if index > #names then
            return finish()
        end

        local suiteName = names[index]
        index = index + 1
        local completedInCallback = false
        local result = UISmoke.RunSuite(suiteName, {
            quiet = true,
            onDone = function(doneResult)
                completedInCallback = true
                absorb(doneResult)
                runNext()
            end,
        })
        if result and not completedInCallback then
            absorb(result)
            return runNext()
        end
        return finalResult
    end

    return runNext()
end

local function PrintHelp(printer, errorMessage)
    if errorMessage then
        PrintLine(printer, errorMessage)
    end
    PrintLine(printer, "usage: /qui uitest list | run <suite|all> | last")
    local last = UISmoke.GetLastResult()
    if last then
        PrintLine(printer, "last: " .. (UISmoke.FormatResult(last)[1] or "unknown"))
    else
        PrintLine(printer, "last: none")
    end
end

function UISmoke.HandleSlash(input, opts)
    opts = opts or {}
    local parsed = UISmoke.ParseCommand(input)
    local printer = opts.print

    if parsed.action == "list" then
        local names = UISmoke.ListSuites()
        PrintLine(printer, "suites: " .. (#names > 0 and table.concat(names, ", ") or "none"))
        return true
    end

    if parsed.action == "last" then
        local result = UISmoke.GetLastResult()
        if result then
            PrintResult(result, printer)
        else
            PrintLine(printer, "no result yet")
        end
        return true
    end

    if parsed.action == "run" then
        PrintLine(printer, "running " .. tostring(parsed.suite) .. "...")
        UISmoke.RunSuite(parsed.suite, {
            print = printer,
            onDone = opts.onDone,
        })
        return true
    end

    PrintHelp(printer, parsed.error)
    return true
end

local function SkinField(frame, key)
    local skin = ns.SkinBase
    if skin and type(skin.GetFrameData) == "function" then
        local ok, value = ns.SafeCall("report", skin.GetFrameData, frame, key)
        if ok then
            return value
        end
    end
    return nil
end

local function SkinBackdrop(frame)
    local skin = ns.SkinBase
    if skin and type(skin.GetBackdrop) == "function" then
        local ok, value = ns.SafeCall("report", skin.GetBackdrop, frame)
        if ok then
            return value
        end
    end
    return nil
end

local function IsSkinned(frame)
    local skin = ns.SkinBase
    if skin and type(skin.IsSkinned) == "function" then
        local ok, value = ns.SafeCall("report", skin.IsSkinned, frame)
        if ok then
            return value and true or false
        end
    end
    return false
end

local function CollectScrollBoxFrames(scrollBox)
    local frames = {}
    if not scrollBox then
        return frames
    end

    if type(scrollBox.ForEachFrame) == "function" then
        ns.SafeCallMethod("report", scrollBox, "ForEachFrame", function(frame)
            frames[#frames + 1] = frame
        end)
    end

    if #frames == 0 and type(scrollBox.GetFrames) == "function" then
        local ok, list = ns.SafeCallMethod("report", scrollBox, "GetFrames")
        if ok and type(list) == "table" then
            for _, frame in ipairs(list) do
                frames[#frames + 1] = frame
            end
        end
    end

    return frames
end

local function AssertHiddenTexture(ctx, label, texture)
    if not texture then
        return
    end
    local alpha = TextureAlpha(texture)
    ctx:Assert(alpha == nil or alpha <= 0.05, label .. " texture alpha is not suppressed", {
        texture = FrameName(texture),
        alpha = alpha and string.format("%.2f", alpha) or "nil",
    })
end

local function LabelFontString(frame)
    if not frame then return nil end
    if frame.GetFontString then
        local ok, fs = ns.SafeCallMethod("report", frame, "GetFontString")
        if ok and fs then return fs end
    end
    return frame.Text or frame.Label
end

local function TextColor(fontString)
    if not fontString or not fontString.GetTextColor then return nil end
    local ok, r, g, b, a = ns.SafeCallMethod("report", fontString, "GetTextColor")
    if not ok or type(r) ~= "number" then return nil end
    return r, g, b, a
end

local function IsWhiteish(r, g, b, a)
    return r and r >= 0.95 and g >= 0.95 and b >= 0.95 and (a or 1) >= 0.99
end

local function CheckQuantityInput(ctx, label, quantityInput)
    ctx:Step(label .. " quantity input", function()
        if not ctx:Assert(quantityInput ~= nil, label .. " QuantityInput is missing") then
            return
        end

        local inputBox = quantityInput.InputBox
        ctx:Assert(inputBox ~= nil, label .. " QuantityInput.InputBox is missing", DescribeFrame(quantityInput))
        if inputBox then
            ctx:Assert(SkinField(inputBox, "skinKind") == "editbox" or SkinBackdrop(inputBox) ~= nil,
                label .. " QuantityInput.InputBox is not skinned",
                DescribeFrame(inputBox))
        end

        local maxButton = quantityInput.MaxButton
        if maxButton then
            ctx:Assert(SkinField(maxButton, "skinKind") == "button" or SkinBackdrop(maxButton) ~= nil,
                label .. " QuantityInput.MaxButton is not skinned",
                DescribeFrame(maxButton))
        else
            ctx:Skip(label .. " QuantityInput.MaxButton not present", DescribeFrame(quantityInput))
        end
    end)
end

local function InspectCategoryRows(ctx, categoriesList)
    local scrollBox = categoriesList and categoriesList.ScrollBox
    local rows = CollectScrollBoxFrames(scrollBox)
    if #rows == 0 then
        ctx:Step("category rows visible", function()
            ctx:Skip("no category rows visible", DescribeFrame(scrollBox))
        end)
        return
    end

    ctx:Detail("category rows", { count = #rows })
    local limit = math.min(#rows, 5)
    for i = 1, limit do
        local row = rows[i]
        ctx:Step("category row " .. i, function()
            ctx:Assert(SkinField(row, "skinKind") == "category" or SkinBackdrop(row) ~= nil,
                "category row is not skinned",
                DescribeFrame(row))
            AssertHiddenTexture(ctx, "category row normal", row.NormalTexture)
            AssertHiddenTexture(ctx, "category row selected", row.SelectedTexture)
            AssertHiddenTexture(ctx, "category row highlight", row.HighlightTexture)
            if row.GetHighlightTexture then
                local ok, highlight = ns.SafeCallMethod("report", row, "GetHighlightTexture")
                if ok then
                    AssertHiddenTexture(ctx, "category row highlight", highlight)
                end
            end
            -- R2: the selected row must read as selected (bright text), and an
            -- idle row must not be painted with the selected colour.
            local label = LabelFontString(row)
            local r, g, b, a = TextColor(label)
            if r then
                local okSel, selected = ns.SafeCall("report", function()
                    return row.SelectedTexture and row.SelectedTexture:IsShown()
                end)
                if okSel and selected then
                    ctx:Assert(r >= 0.9 and g >= 0.9 and b >= 0.9 and a >= 0.99,
                        "selected category row text is not bright",
                        { r = r, g = g, b = b, a = a })
                else
                    ctx:Assert(a > 0.2, "category row text is (nearly) invisible", { r = r, g = g, b = b, a = a })
                end
            end
        end)
    end
end

local function InspectAuctionHouse(ctx)
    local frame = _G.AuctionHouseFrame

    ctx:Step("auction house frame exists", function()
        ctx:Assert(frame ~= nil, "AuctionHouseFrame is missing")
    end)
    if not frame then
        return
    end

    ctx:Step("auction house frame shown", function()
        ctx:Assert(IsShown(frame), "AuctionHouseFrame is not shown", DescribeFrame(frame))
    end)

    ctx:Step("auction house skin state", function()
        ctx:Assert(IsSkinned(frame), "AuctionHouseFrame is not marked skinned", DescribeFrame(frame))
        ctx:Assert(SkinBackdrop(frame) ~= nil, "AuctionHouseFrame has no QUI backdrop", DescribeFrame(frame))
    end)

    ctx:Step("auction house core children", function()
        ctx:Assert(frame.CategoriesList ~= nil, "CategoriesList is missing", DescribeFrame(frame))
        ctx:Assert(frame.SearchBar ~= nil, "SearchBar is missing", DescribeFrame(frame))
        ctx:Assert(frame.BrowseResultsFrame ~= nil, "BrowseResultsFrame is missing", DescribeFrame(frame))
        ctx:Assert(frame.ItemSellFrame ~= nil, "ItemSellFrame is missing", DescribeFrame(frame))
        ctx:Assert(frame.CommoditiesSellFrame ~= nil, "CommoditiesSellFrame is missing", DescribeFrame(frame))
    end)

    if frame.SetDisplayMode and _G.AuctionHouseFrameDisplayMode and _G.AuctionHouseFrameDisplayMode.Buy then
        ctx:Step("select buy surface", function()
            local ok, err = pcall(frame.SetDisplayMode, frame, _G.AuctionHouseFrameDisplayMode.Buy)
            ctx:Assert(ok, "SetDisplayMode(Buy) failed", { error = err })
        end)
    end

    ctx:Step("buy surface visible", function()
        ctx:Assert(IsShown(frame.CategoriesList), "CategoriesList is not shown", DescribeFrame(frame.CategoriesList))
        ctx:Assert(IsShown(frame.SearchBar), "SearchBar is not shown", DescribeFrame(frame.SearchBar))
    end)

    if frame.CategoriesList then
        InspectCategoryRows(ctx, frame.CategoriesList)
    end

    CheckQuantityInput(ctx, "item sell", frame.ItemSellFrame and frame.ItemSellFrame.QuantityInput)
    CheckQuantityInput(ctx, "commodities sell", frame.CommoditiesSellFrame and frame.CommoditiesSellFrame.QuantityInput)
end

UISmoke.RegisterSuite("auctionhouse", function(ctx)
    local frame = _G.AuctionHouseFrame
    if not frame then
        ctx:Step("auction house frame loaded", function()
            ctx:Assert(false, "open the Auction House before running this suite")
        end)
        return
    end

    ctx:WaitFor("auction house frame shown", function()
        return _G.AuctionHouseFrame and IsShown(_G.AuctionHouseFrame)
    end, 1.5, 0.1, function(ok)
        if ok then
            InspectAuctionHouse(ctx)
        end
        ctx:Finish()
    end)
    return true
end, {
    description = "Auction House frame skinning smoke checks",
})

-- R3: SkinButton-skinned buttons must keep a white label through
-- Disable() -> Enable() with the global-font gate OFF as well as ON. Probes
-- the first available skinned candidate from currently loaded frames.
local BUTTON_STATE_CANDIDATES = {
    function() local f = _G.AuctionHouseFrame; return f and f.SearchBar and f.SearchBar.SearchButton, "AuctionHouseFrame.SearchBar.SearchButton" end,
    function() local f = _G.AuctionHouseFrame; return f and f.ItemSellFrame and f.ItemSellFrame.PostButton, "AuctionHouseFrame.ItemSellFrame.PostButton" end,
    function() local f = _G.AuctionHouseFrame; return f and f.CommoditiesSellFrame and f.CommoditiesSellFrame.PostButton, "AuctionHouseFrame.CommoditiesSellFrame.PostButton" end,
    function() local p = _G.PaperDollFrame; p = p and p.EquipmentManagerPane; return p and p.EquipSet, "PaperDollFrame.EquipmentManagerPane.EquipSet" end,
    function() return _G.MerchantFrame and _G.MerchantFrame.BuybackButton, "MerchantFrame.BuybackButton" end,
    function() return _G.MailFrame and _G.SendMailMailButton, "SendMailMailButton" end,
}

local function FindSkinnedButton()
    for _, probe in ipairs(BUTTON_STATE_CANDIDATES) do
        local ok, button, name = ns.SafeCall("report", probe)
        if ok and button and SkinField(button, "skinKind") == "button" and SkinField(button, "skinFont") then
            return button, name
        end
    end
    return nil
end

local function GetGeneralSettings()
    local core = ns.Helpers and ns.Helpers.GetCore and ns.Helpers.GetCore()
    return core and core.db and core.db.profile and core.db.profile.general
end

local function CheckButtonStateRoundTrip(ctx, button, name, gateValue)
    local skin = ns.SkinBase
    local label = LabelFontString(button)
    if not label then
        ctx:Skip(name .. " has no label font string", DescribeFrame(button))
        return
    end
    local wasEnabled = button:IsEnabled()
    local tag = name .. " (applyGlobalFontToBlizzard=" .. tostring(gateValue) .. ")"

    ns.SafeCall("report", skin.RefreshButtonVisualState, button)
    if wasEnabled then
        ctx:Assert(IsWhiteish(TextColor(label)), tag .. " enabled label is not white", { color = { TextColor(label) } })
    end

    ns.SafeCallMethod("report", button, "Disable")
    local dr, dg, db, da = TextColor(label)
    ctx:Assert(dr and not IsWhiteish(dr, dg, db, da), tag .. " disabled label still reads as enabled", { r = dr, g = dg, b = db, a = da })

    ns.SafeCallMethod("report", button, "Enable")
    ctx:Assert(IsWhiteish(TextColor(label)), tag .. " label did not return to white after Enable()", { color = { TextColor(label) } })

    if not wasEnabled then
        ns.SafeCallMethod("report", button, "Disable")
    end
end

UISmoke.RegisterSuite("buttons", function(ctx)
    local button, name = FindSkinnedButton()
    ctx:Step("skinned button available", function()
        if not button then
            ctx:Skip("no SkinButton-skinned candidate is loaded (open the Auction House, Merchant, or Mail window)")
        end
    end)
    if not button then return end

    local general = GetGeneralSettings()
    local originalGate = general and general.applyGlobalFontToBlizzard
    local gates = general and { false, true } or { originalGate }
    for _, gateValue in ipairs(gates) do
        ctx:Step("button state round-trip gate=" .. tostring(gateValue), function()
            if general then general.applyGlobalFontToBlizzard = gateValue end
            CheckButtonStateRoundTrip(ctx, button, name, gateValue)
        end)
    end
    if general then
        general.applyGlobalFontToBlizzard = originalGate
        ns.SafeCall("report", ns.SkinBase.RefreshButtonVisualState, button)
    end
end, {
    description = "Skinned button enabled/disabled label contrast (both font-gate values)",
})

ns.UISmoke = UISmoke
