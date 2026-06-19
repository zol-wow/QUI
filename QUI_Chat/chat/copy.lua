---------------------------------------------------------------------------
-- QUI Chat Module — Copy
-- URL copy popup, full-history copy frame (custom display only), custom
-- display copy button (always/hover/hidden modes), URL click handler
-- routing through the EventRegistry SetItemRef callback.
--
-- Blizzard-frame copy-button machinery removed in Phase 11 Task 3.
-- The copy frame is populated exclusively from the custom display's
-- MessageStore; Blizzard ChatFrame live-line and persisted-history
-- paths have been excised.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local UIKit = ns.UIKit

-- Defensive: assert _internals exists before reading state through it.
-- Set up by chat.lua, which loads first per chat.xml.
local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: copy.lua loaded before chat.lua. Check chat.xml — chat.lua must precede copy.lua.")

ns.QUI.Chat.Copy = ns.QUI.Chat.Copy or {}
local Copy = ns.QUI.Chat.Copy

-- Localized table functions for performance
local tinsert = table.insert
local tconcat = table.concat

-- Skip the on-open Select-All when the rendered text is large — the
-- selection walk is another full-text pass on top of SetText. Users can
-- still hit the Select All button on demand.
local AUTO_HIGHLIGHT_MAX_CHARS = 8000
local COPY_BUTTON_SIZE = 24
local COPY_BUTTON_FRAME_LEVEL = 100
local COPY_GLYPH_STROKE = 2

---------------------------------------------------------------------------
-- Module-local state
---------------------------------------------------------------------------
local urlPopup = nil            -- Copy popup frame (created on demand)
local chatCopyFrame = nil       -- Chat history copy frame (created on demand)
-- Per-window copy buttons live on their window's container (container._quiCopyButton)
-- so they follow DisplayLayer's window pool without orphaning on delete/recreate.

-- Shared color palette (defined in chat.lua, hoisted to _internals).
-- bg/text values are chat-module-specific and intentionally diverge from the
-- options framework palette; accent is resolved live via I.GetAccent so a
-- theme preset switch propagates to popup chrome on next Show.
local QUI_COLORS = I.QUI_COLORS
if type(QUI_COLORS) ~= "table" then
    QUI_COLORS = {
        bg      = {0.067, 0.094, 0.153, 0.97},
        accent  = {0.204, 0.827, 0.600, 1},
        text    = {0.953, 0.957, 0.965, 1},
        textDim = {0.72,  0.72,  0.76,  1},
    }
end

local function ResolveAccent()
    return (I.GetAccent and I.GetAccent()) or QUI_COLORS.accent
end

-- Copy surfaces render with the SAME font object the message frame publishes
-- (I.chatFontObject, resolved once in display_layer.ApplyTheme) so copied
-- history looks exactly like the chat window — the chain the input editbox
-- uses (editbox_basics.ApplyEditBoxFont). Re-resolved on every open via
-- RefreshPopupAccent: the popups are created once and reused, and the chat
-- font can change between opens.
local function ResolveChatFontObject()
    return I.chatFontObject or _G.QUI_CustomChatFontObject or _G.ChatFontNormal
end

-- Apply the QUI chat font to a copy-surface EditBox. These editboxes are created
-- template-less (no inherited font), which is why every naive approach failed:
--   * SetFontObject(I.chatFontObject) — the per-script SimpleFont FAMILY the
--     message frame uses — does NOT render when set as the box's FIRST-EVER font:
--     with no base font to derive from it leaves the box on the engine default
--     (the long-standing "copy window has no QUI font / boxed symbols" bug). The
--     chat-input editbox carries the same family fine only because its template
--     seeds a base font first.
--   * Re-running SetFont(physical) on every open renders, but layering the family
--     on top each time DROPS the font on reopen — repeating SetFont destabilizes
--     the per-script family re-resolution across opens.
-- Fix: seed a physical base font ONCE (flag-gated) so the family has something to
-- attach to, then SetFontObject the family on EVERY refresh. SetFont never repeats
-- (reopen-stable, and it sidesteps the editbox SetFontObject self-cycle), and the
-- family gives QUI font + baked symbols (roman member) for Latin plus the Blizzard
-- fallback members for CJK names from other players. If the family still can't
-- attach the seeded physical base stands — QUI font + symbols, no CJK, no worse
-- than before. Falls back to the published font object when no path is published
-- yet (pre-build / stock chat font).
local function ApplyCopyFont(editBox)
    if not editBox then return end
    if not editBox._quiFontSeeded and editBox.SetFont then
        local path, size, flags = I.chatFontPath, I.chatFontSize, I.chatFontFlags
        if type(path) == "string" and path ~= "" and type(size) == "number" and size > 0 then
            if pcall(editBox.SetFont, editBox, path, size, flags or "") then
                editBox._quiFontSeeded = true
            end
        end
    end
    local fo = ResolveChatFontObject()
    if fo and editBox.SetFontObject then editBox:SetFontObject(fo) end
end

-- Font for the history frame's ScrollingEditBox control. Its inner editbox is
-- font-bearing, so the per-script family attaches — BUT the scrollable editbox
-- re-applies its `fontName` field on relayout, so a bare SetFontObject reverts to
-- the template default (GameFontHighlight). Set BOTH the fontName field and the
-- control's font object (mirrors how Blizzard frames drive this template) so the
-- QUI family sticks: QUI font + baked symbols for Latin, Blizzard fallback members
-- for CJK names from other players.
local function ApplyScrollingEditBoxFont(seb)
    if not seb then return end
    local fo = ResolveChatFontObject()
    if not fo then return end
    local editBox = seb.GetEditBox and seb:GetEditBox()
    if editBox then editBox.fontName = fo end
    if seb.SetFontObject then seb:SetFontObject(fo) end
end

-- QUI-skin a MinimalScrollBar (the ScrollingEditBox gutter bar): hide the stock
-- atlas thumb/steppers and lay a flat accent thumb, matching the rest of the
-- chat chrome. The thumb's atlas regions (Middle/Begin/End) are re-set on hover
-- via OnButtonStateChanged, but SetAtlas does NOT reset alpha — so alpha 0 once
-- keeps them hidden across states; the flat fill tracks the thumb by anchor.
local function StyleMinimalScrollBar(bar, accent)
    if not bar then return end
    -- Hide the arrow steppers (minimal look).
    local back = bar.GetBackStepper and bar:GetBackStepper()
    local fwd = bar.GetForwardStepper and bar:GetForwardStepper()
    if back then back:SetAlpha(0) end
    if fwd then fwd:SetAlpha(0) end
    -- Hide the stock rounded atlas caps (Begin/Middle/End) on both the track and
    -- the thumb — those are the "weird border" — and replace with flat fills.
    -- SetAtlas (re-run on thumb hover) does NOT reset alpha, so alpha 0 sticks.
    local function hideAtlasRegions(region)
        for _, key in ipairs({ "Begin", "Middle", "End" }) do
            local r = region and region[key]
            if r and r.SetAlpha then r:SetAlpha(0) end
        end
    end
    -- Faint always-visible track channel.
    local track = (bar.GetTrack and bar:GetTrack()) or bar.Track
    if track then
        hideAtlasRegions(track)
        if not track._quiBg then
            local trackBg = track:CreateTexture(nil, "BACKGROUND")
            trackBg:SetAllPoints(track)
            track._quiBg = trackBg
        end
        track._quiBg:SetColorTexture(1, 1, 1, 0.08)
    end
    -- Flat accent thumb.
    local thumb = bar.GetThumb and bar:GetThumb()
    if thumb then
        hideAtlasRegions(thumb)
        if not thumb._quiFill then
            local fill = thumb:CreateTexture(nil, "ARTWORK")
            fill:SetAllPoints(thumb)
            thumb._quiFill = fill
        end
        thumb._quiFill:SetColorTexture(accent[1], accent[2], accent[3], 0.9)
    end
end

local function ResolveTheme()
    if I.GetThemeColors then
        local theme = I.GetThemeColors()
        if theme then return theme end
    end
    local accent = ResolveAccent()
    return {
        bg = QUI_COLORS.bg,
        bgDark = {0.03, 0.04, 0.06, 1},
        text = QUI_COLORS.text,
        textDim = QUI_COLORS.textDim,
        textMuted = QUI_COLORS.textDim,
        border = {1, 1, 1, 0.08},
        accent = accent,
        accentHover = accent,
    }
end

local function ColorTexture(texture, color)
    if texture and texture.SetColorTexture and color then
        texture:SetColorTexture(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
end

local function CreateThemedButton(parent, text, width, height, onClick, variant)
    -- Route through the central core factory (UIKit.CreateButton lives in core and is
    -- always available at login, unlike GUI:CreateButton which is in the LOD Options
    -- addon). Pass the chat module's palette so the button keeps chat chrome — chat
    -- intentionally diverges from the options palette (see QUI_COLORS above).
    local theme = ResolveTheme()
    return UIKit.CreateButton(parent, {
        text = text,
        width = width,
        height = height,
        onClick = onClick,
        variant = variant,
        colors = { text = theme.text, textDim = theme.textDim, accent = theme.accent },
    })
end

local function StyleThemedButton(button, variant)
    if not button then return end
    local theme = ResolveTheme()
    local isPrimary = variant == "primary"

    if button.SetBorderColor then
        if isPrimary then
            button:SetBorderColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.55)
        else
            button:SetBorderColor(1, 1, 1, 0.2)
        end
    elseif UIKit and UIKit.UpdateBorderLines then
        if isPrimary then
            UIKit.UpdateBorderLines(button, 1, theme.accent[1], theme.accent[2], theme.accent[3], 0.55)
        else
            UIKit.UpdateBorderLines(button, 1, 1, 1, 1, 0.2)
        end
    end

    if button.text then
        local c = isPrimary and theme.accent or theme.textDim
        button.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
end

local function CreateCloseButton(parent, onClick)
    local button = CreateThemedButton(parent, "x", 22, 22, onClick, "ghost")
    return button
end

local function GetScrollBar(scrollFrame)
    if not scrollFrame then return nil end
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then return scrollBar end
    local name = scrollFrame.GetName and scrollFrame:GetName()
    if name then
        return _G[name .. "ScrollBar"]
    end
    return nil
end

local function HideButtonArtwork(button)
    if not button then return end
    button:SetAlpha(0)
    button:SetSize(1, 1)
    if button.GetRegions then
        for _, region in ipairs({button:GetRegions()}) do
            if region and region.SetAlpha then
                region:SetAlpha(0)
            end
        end
    end
end

local function HideFrameTextures(frame)
    if not frame or not frame.GetRegions then return end
    for _, region in ipairs({frame:GetRegions()}) do
        if region and region.GetObjectType and region:GetObjectType() == "Texture" and region.SetAlpha then
            region:SetAlpha(0)
        end
    end
end

local function StyleScrollFrame(scrollFrame)
    local scrollBar = GetScrollBar(scrollFrame)
    if not scrollBar then return end

    local theme = ResolveTheme()
    HideFrameTextures(scrollBar)
    if scrollBar.Track then
        scrollBar.Track:SetAlpha(0)
    end
    if scrollBar.Background then
        scrollBar.Background:SetAlpha(0)
    end
    if scrollBar.BG then
        scrollBar.BG:SetAlpha(0)
    end
    if scrollBar.SetWidth then
        scrollBar:SetWidth(8)
    end

    local thumb = scrollBar.ThumbTexture or (scrollBar.GetThumbTexture and scrollBar:GetThumbTexture())
    if thumb then
        thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
        thumb:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 0.7)
        if thumb.SetAlpha then thumb:SetAlpha(1) end
        if thumb.SetSize then
            thumb:SetSize(8, 40)
        end
    end

    HideButtonArtwork(scrollBar.ScrollUpButton)
    HideButtonArtwork(scrollBar.ScrollDownButton)

    local name = scrollFrame.GetName and scrollFrame:GetName()
    if name then
        HideButtonArtwork(_G[name .. "ScrollBarScrollUpButton"])
        HideButtonArtwork(_G[name .. "ScrollBarScrollDownButton"])
    end
end

local function StyleResizeButton(button)
    if not button then return end
    local theme = ResolveTheme()
    local textures = {
        button.GetNormalTexture and button:GetNormalTexture(),
        button.GetHighlightTexture and button:GetHighlightTexture(),
        button.GetPushedTexture and button:GetPushedTexture(),
    }
    for i, texture in ipairs(textures) do
        if texture then
            if texture.SetDesaturated then texture:SetDesaturated(true) end
            local alpha = (i == 2) and 0.9 or 0.55
            texture:SetVertexColor(theme.accent[1], theme.accent[2], theme.accent[3], alpha)
        end
    end
end

-- Re-apply the current theme accent to a popup's surface and title text so
-- a user who switched themes after the popup was first created sees the new
-- color the next time they open it (popups are created once, reused).
local function RefreshPopupAccent(popup)
    if not popup then return end
    local theme = ResolveTheme()
    local accent = theme.accent
    I.ApplySurfaceStyle(popup, theme.bg, accent, 2)
    if popup.title then
        popup.title:SetTextColor(accent[1], accent[2], accent[3], 1)
    end
    if popup.hint then
        popup.hint:SetTextColor(theme.textDim[1], theme.textDim[2], theme.textDim[3], theme.textDim[4] or 1)
    end
    if popup.editBg then
        I.ApplySurfaceStyle(popup.editBg, theme.bgDark, theme.border, 1)
    end
    if popup.editBox then
        popup.editBox:SetTextColor(theme.text[1], theme.text[2], theme.text[3], theme.text[4] or 1)
        if popup.scrollingEditBox then
            ApplyScrollingEditBoxFont(popup.scrollingEditBox)
            if popup.scrollBar then StyleMinimalScrollBar(popup.scrollBar, accent) end
        else
            ApplyCopyFont(popup.editBox)
        end
    end
    if popup.scrollFrame then
        StyleScrollFrame(popup.scrollFrame)
    end
    StyleThemedButton(popup.selectAllButton, "primary")
    StyleThemedButton(popup.closeButton, "ghost")
    StyleThemedButton(popup.cornerCloseButton, "ghost")
    StyleResizeButton(popup.resizeButton)
end

---------------------------------------------------------------------------
-- URL copy popup
---------------------------------------------------------------------------
local function CreateCopyPopup()
    if urlPopup then return urlPopup end

    urlPopup = CreateFrame("Frame", "QUI_ChatCopyPopup", UIParent)
    urlPopup:SetSize(420, 90)
    urlPopup:SetPoint("CENTER")
    urlPopup:SetFrameStrata("DIALOG")
    local theme = ResolveTheme()
    local accent = theme.accent
    I.ApplySurfaceStyle(urlPopup, theme.bg, accent, 2)
    urlPopup:EnableMouse(true)
    urlPopup:SetMovable(true)
    urlPopup:RegisterForDrag("LeftButton")
    urlPopup:SetScript("OnDragStart", urlPopup.StartMoving)
    urlPopup:SetScript("OnDragStop", urlPopup.StopMovingOrSizing)
    urlPopup:Hide()

    -- Title text with accent color. Stored on the popup so RefreshPopupAccent
    -- can repaint it when the user has switched theme presets between opens.
    local title = urlPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText(ns.L["Press Ctrl+C to copy"])
    title:SetTextColor(accent[1], accent[2], accent[3], 1)
    urlPopup.title = title

    local editBg = CreateFrame("Frame", nil, urlPopup)
    editBg:SetPoint("LEFT", 18, 0)
    editBg:SetPoint("RIGHT", -34, 0)
    editBg:SetHeight(26)
    editBg:SetPoint("CENTER", 0, -9)
    I.ApplySurfaceStyle(editBg, theme.bgDark, theme.border, 1)
    urlPopup.editBg = editBg

    -- EditBox for URL
    local editBox = CreateFrame("EditBox", nil, editBg)
    editBox:SetPoint("LEFT", 8, 0)
    editBox:SetPoint("RIGHT", -8, 0)
    editBox:SetHeight(22)
    editBox:SetAutoFocus(true)
    editBox:SetTextColor(theme.text[1], theme.text[2], theme.text[3], theme.text[4] or 1)
    ApplyCopyFont(editBox)
    editBox:SetScript("OnEscapePressed", function() urlPopup:Hide() end)
    editBox:SetScript("OnEnterPressed", function() urlPopup:Hide() end)
    urlPopup.editBox = editBox

    -- Close button
    local closeBtn = CreateCloseButton(urlPopup, function() urlPopup:Hide() end)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    urlPopup.cornerCloseButton = closeBtn
    StyleThemedButton(closeBtn, "ghost")

    -- Add to special frames so ESC closes it
    if not tContains(UISpecialFrames, "QUI_ChatCopyPopup") then
        tinsert(UISpecialFrames, "QUI_ChatCopyPopup")
    end

    return urlPopup
end

---------------------------------------------------------------------------
-- Show copy popup with URL
---------------------------------------------------------------------------
local function ShowCopyPopup(url)
    local popup = CreateCopyPopup()
    RefreshPopupAccent(popup)
    popup.editBox:SetText(url)
    popup.editBox:HighlightText()
    popup:Show()
    popup.editBox:SetFocus()
end

---------------------------------------------------------------------------
-- URL click handler — routes addon:quaziiuichat:url:* hyperlinks to the popup
---------------------------------------------------------------------------
local function ExtractURLFromLink(link)
    if type(link) ~= "string" then return nil end

    local url = link:match("^addon:quaziiuichat:url:(.*)")
    if url then return url end

    local legacy = link:match("^addon:quaziiuichat:(.*)")
    if legacy
        and not legacy:find("^waypoint:")
        and not legacy:find("^player:") then
        return legacy
    end
    return nil
end

local function SetupURLClickHandler()
    -- Register for hyperlink clicks
    EventRegistry:RegisterCallback("SetItemRef", function(_, link, text, button)
        local settings = I.GetSettings and I.GetSettings()
        if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end

        local url = ExtractURLFromLink(link)
        if url then
            ShowCopyPopup(url)
            return true
        end
    end)
end

---------------------------------------------------------------------------
-- Full-history copy frame
---------------------------------------------------------------------------
-- Entry's effective base color as a "|cff..." escape. The live resolver
-- override is applied first — the SAME one RenderEntry uses — so a channel
-- color edited after capture (or resolved only at render time) wraps the
-- copied line exactly as the window paints it; the baked capture color is
-- the fallback. White returns nil — it matches the editbox base color, so
-- the wrap would only bloat the copied text. Callers gate on entry.s, so
-- the resolver is never consulted for secret entries (RenderEntry parity).
local function LineColorCode(entry)
    local r, g, b = entry.r, entry.g, entry.b
    local resolver = ns.QUI.Chat._lineColorResolver
    if resolver and entry.e then
        local orR, orG, orB = resolver(entry.e, entry.ch and { [9] = entry.ch } or nil)
        if orR then r, g, b = orR, orG, orB end
    end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    if r >= 1 and g >= 1 and b >= 1 then return nil end
    local function byte(v)
        if v < 0 then v = 0 elseif v > 1 then v = 1 end
        return math.floor(v * 255 + 0.5)
    end
    return ("|cff%02x%02x%02x"):format(byte(r), byte(g), byte(b))
end

-- Strip textures, icons, and hyperlink wrappers but KEEP color escapes so the
-- copy window shows lines the way the chat window renders them. lineColor (the
-- entry's baked base-color escape) wraps the line and replaces |r terminators:
-- |r resets to the editbox's single base text color, not the line's own color,
-- so "|cff..Name|r: hi" would paint the tail the wrong color without it.
local function CleanMessage(message, lineColor)
    if Helpers.IsSecretValue(message) or type(message) ~= "string" then return "" end

    local cleaned = message
    -- BN friend toasts/links carry the friend's name as a |K kstring INSIDE the
    -- |HBNplayer link (both the link data and the [display]). The chat SMF
    -- renders kstrings; a plain EditBox cannot, so the generic |K strip below
    -- would blank the friend's name to "???". The bnID is embedded in the link
    -- DATA (field 2), so resolve the BNet display name from it and substitute it
    -- BEFORE the kstring strip. Resolving HERE (copy-window open) rather than at
    -- capture is deliberate: the friend's BN account info is reliably cached by
    -- now, whereas at the FRIEND_ONLINE toast it often has not populated yet
    -- (the account just came online). Use the battleTag truncated at '#'
    -- ("Devilspit#1846" -> "Devilspit"): in these toasts accountInfo.accountName
    -- comes back AS THE SAME |K kstring (verified in-game), so it can't be used
    -- -- it would re-blank to "???". battleTag is the plain, reliably-populated
    -- field (non-Nilable per BNetAccountInfo docs) and is the friends-list
    -- display name once the discriminator is dropped. Nil-safe -- leaves the
    -- match untouched (the |K strip handles the fallback) when unresolved.
    if _G.C_BattleNet and _G.C_BattleNet.GetAccountInfoByID then
        cleaned = cleaned:gsub("|HBNplayer:.-:(%d+):.-|h(%b[])|h", function(bnID)
            local id = tonumber(bnID)
            if not id then return nil end
            local ok, info = pcall(_G.C_BattleNet.GetAccountInfoByID, id)
            if not ok or type(info) ~= "table" then return nil end
            local bt = info.battleTag
            if type(bt) ~= "string" or bt == "" or bt:sub(1, 2) == "|K" then return nil end
            local hash = bt:find("#", 1, true)
            local name = hash and bt:sub(1, hash - 1) or bt
            if name ~= "" then
                return ("[%s]"):format(name)
            end
            return nil
        end)
    end
    -- Battle.net kstrings (|K...|k) and name-wrap escapes (|W...|w) FIRST:
    -- an EditBox cannot render foreign kstrings — one leaked |K anywhere in
    -- the concatenated text blanks the ENTIRE copy editbox (the SMF renders
    -- them fine, so the window looks normal while copy shows nothing). BN
    -- links also embed kstrings in their link DATA, which would break the
    -- |H strip below; substituting first keeps that pattern matching.
    cleaned = cleaned:gsub("%f[|]|K.-%f[|]|k", "???")
    cleaned = cleaned:gsub("%f[|]|W(.-)%f[|]|w", "%1")
    -- Convert raid icons to text BEFORE the generic texture strip eats them
    cleaned = cleaned:gsub("|TInterface\\TargetingFrame\\UI%-RaidTargetingIcon_(%d):[^|]*|t", "{rt%1}")
    -- Remove texture escapes |T...|t
    cleaned = cleaned:gsub("|T[^|]*|t", "")
    -- Remove atlas textures |A...|a
    cleaned = cleaned:gsub("|A[^|]*|a", "")
    -- Strip hyperlink wrappers but keep the visible text VERBATIM, brackets
    -- included — |H...|h[text]|h -> [text] — so the copied line reads like the
    -- window renders it. The capture must admit | (class-colored player names
    -- are |H...|h[|cff..Name|r]|h). A leaked raw |H..|h wrapper renders
    -- unreliably in the copy editbox (link parsing degrades on refocus/
    -- scroll), so both bracketed and bare link shapes must strip.
    cleaned = cleaned:gsub("|H[^|]*|h(%[.-%])|h", "%1")
    cleaned = cleaned:gsub("|H[^|]*|h(.-)|h", "%1")
    cleaned = cleaned:gsub("|n", "\n")
    if lineColor and cleaned ~= "" then
        -- Plain wrap ONLY — never touch the line's own |r terminators and
        -- never inject extra color codes after them. Both re-assert variants
        -- (replacing |r, and keeping |r while re-pushing the line color)
        -- corrupt the editbox's color rendering at scale: colors die partway
        -- down the text or bleed across lines. Verified in-game via
        -- /quicopydiag on a full spam-channel scrollback: this exact form
        -- renders 100% correctly. Accepted tradeoff: text after an inner |r
        -- (links, class-colored names) falls back to the editbox base color
        -- for the rest of that line instead of the line color.
        cleaned = lineColor .. cleaned .. "|r"
    end

    return cleaned
end

-- Lines for the CUSTOM display's copy popup. With a windowID, sourced from
-- exactly that window's visible set (the store filtered by its active tab) so
-- the copied text matches what's on screen; without one — or before the
-- display exists — the whole store (back-compat with no-arg callers). Texture/
-- link markup is stripped; color escapes are kept (and each line is wrapped in
-- its baked base color) so the window renders like the chat display; secrets
-- are replaced with a placeholder (never touched).
local function GetCustomDisplayLines(windowID)
    local lines = {}
    local function collect(entry)
        if entry.s then
            lines[#lines + 1] = "??? (protected message)"
        else
            local cleaned = CleanMessage(entry.m, LineColorCode(entry))
            if cleaned ~= "" then
                lines[#lines + 1] = cleaned
            end
        end
    end
    local Display = ns.QUI.Chat.DisplayLayer
    if windowID and Display and Display.ForEachVisible then
        Display.ForEachVisible(windowID, collect)
    else
        local Store = ns.QUI.Chat.MessageStore
        if Store then Store.ForEach(collect) end
    end
    return lines
end
Copy.GetCustomDisplayLines = GetCustomDisplayLines

local function AddGlyphLine(parent, layer)
    local line = parent:CreateTexture(nil, layer or "ARTWORK")
    line:SetTexture("Interface\\Buttons\\WHITE8x8")
    return line
end

local function CreateCopyGlyph(button)
    if button._quiGlyphParts then return end

    local parts = {}
    local back = CreateFrame("Frame", nil, button)
    back:SetSize(10, 12)
    back:SetPoint("CENTER", -3, 3)
    parts.backTop = AddGlyphLine(back)
    parts.backBottom = AddGlyphLine(back)
    parts.backLeft = AddGlyphLine(back)
    parts.backRight = AddGlyphLine(back)
    parts.backTop:SetPoint("TOPLEFT")
    parts.backTop:SetPoint("TOPRIGHT")
    parts.backTop:SetHeight(COPY_GLYPH_STROKE)
    parts.backBottom:SetPoint("BOTTOMLEFT")
    parts.backBottom:SetPoint("BOTTOMRIGHT")
    parts.backBottom:SetHeight(COPY_GLYPH_STROKE)
    parts.backLeft:SetPoint("TOPLEFT")
    parts.backLeft:SetPoint("BOTTOMLEFT")
    parts.backLeft:SetWidth(COPY_GLYPH_STROKE)
    parts.backRight:SetPoint("TOPRIGHT")
    parts.backRight:SetPoint("BOTTOMRIGHT")
    parts.backRight:SetWidth(COPY_GLYPH_STROKE)

    local front = CreateFrame("Frame", nil, button)
    front:SetSize(12, 14)
    front:SetPoint("CENTER", 2, -2)
    parts.frontTop = AddGlyphLine(front)
    parts.frontBottom = AddGlyphLine(front)
    parts.frontLeft = AddGlyphLine(front)
    parts.frontRight = AddGlyphLine(front)
    parts.frontTop:SetPoint("TOPLEFT")
    parts.frontTop:SetPoint("TOPRIGHT", -4, 0)
    parts.frontTop:SetHeight(COPY_GLYPH_STROKE)
    parts.frontBottom:SetPoint("BOTTOMLEFT")
    parts.frontBottom:SetPoint("BOTTOMRIGHT")
    parts.frontBottom:SetHeight(COPY_GLYPH_STROKE)
    parts.frontLeft:SetPoint("TOPLEFT")
    parts.frontLeft:SetPoint("BOTTOMLEFT")
    parts.frontLeft:SetWidth(COPY_GLYPH_STROKE)
    parts.frontRight:SetPoint("TOPRIGHT", 0, -4)
    parts.frontRight:SetPoint("BOTTOMRIGHT")
    parts.frontRight:SetWidth(COPY_GLYPH_STROKE)
    parts.foldA = AddGlyphLine(front)
    parts.foldB = AddGlyphLine(front)
    parts.foldA:SetPoint("TOPRIGHT", 0, -4)
    parts.foldA:SetSize(4, COPY_GLYPH_STROKE)
    parts.foldB:SetPoint("TOPRIGHT", -4, 0)
    parts.foldB:SetSize(COPY_GLYPH_STROKE, 4)

    button._quiGlyphParts = parts
end

local function RefreshCopyGlyph(button, hovered)
    if not button then return end
    local theme = ResolveTheme()
    CreateCopyGlyph(button)
    if button._hoverBg then
        if hovered then
            button._hoverBg:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 0.18)
            button._hoverBg:Show()
        else
            button._hoverBg:Hide()
        end
    end
    for key, part in pairs(button._quiGlyphParts) do
        if key:find("^back") then
            ColorTexture(part, {theme.text[1], theme.text[2], theme.text[3], hovered and 0.72 or 0.55})
        else
            ColorTexture(part, {theme.accent[1], theme.accent[2], theme.accent[3], hovered and 1 or 0.95})
        end
    end
end

-- Create the chat copy frame (on demand)
local function CreateChatCopyFrame()
    if chatCopyFrame then return chatCopyFrame end

    chatCopyFrame = CreateFrame("Frame", "QUI_ChatCopyFrame", UIParent)
    chatCopyFrame:SetSize(500, 400)
    chatCopyFrame:SetPoint("CENTER")
    chatCopyFrame:SetFrameStrata("DIALOG")
    local theme = ResolveTheme()
    local accent = theme.accent
    I.ApplySurfaceStyle(chatCopyFrame, theme.bg, accent, 2)
    chatCopyFrame:EnableMouse(true)
    chatCopyFrame:SetMovable(true)
    chatCopyFrame:SetResizable(true)
    chatCopyFrame:SetResizeBounds(300, 200, 800, 600)
    chatCopyFrame:RegisterForDrag("LeftButton")
    chatCopyFrame:SetScript("OnDragStart", chatCopyFrame.StartMoving)
    chatCopyFrame:SetScript("OnDragStop", chatCopyFrame.StopMovingOrSizing)
    chatCopyFrame:Hide()

    -- Title (stored for RefreshPopupAccent on subsequent opens after a theme switch).
    local title = chatCopyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText(ns.L["Chat History - Select and Ctrl+C to copy"])
    title:SetTextColor(accent[1], accent[2], accent[3], 1)
    chatCopyFrame.title = title

    local hint = chatCopyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
    hint:SetText(ns.L["Select all (Ctrl+A) then copy (Ctrl+C)"])
    hint:SetTextColor(theme.textDim[1], theme.textDim[2], theme.textDim[3], theme.textDim[4] or 1)
    chatCopyFrame.hint = hint

    local editBg = CreateFrame("Frame", nil, chatCopyFrame)
    editBg:SetPoint("TOPLEFT", 12, -55)
    editBg:SetPoint("BOTTOMRIGHT", -12, 45)
    I.ApplySurfaceStyle(editBg, theme.bgDark, theme.border, 1)
    chatCopyFrame.editBg = editBg

    -- Selectable text surface: Blizzard's ScrollingEditBoxTemplate, NOT a bare
    -- EditBox in a ScrollFrame. Two reasons it must be this template:
    --   1. Its inner EditBox is font-bearing (the template seeds a base font in
    --      OnLoad), so SetFontObject(I.chatFontObject) — the per-script SimpleFont
    --      family — actually ATTACHES, giving the QUI font + baked symbols for
    --      Latin and the Blizzard fallback members for CJK names from others. A
    --      template-less EditBox silently drops the family (the long-standing
    --      "copy window has no QUI font" bug).
    --   2. Its ScrollBox VIRTUALIZES the text, so a large chat history renders
    --      without the plain-EditBox failure mode where too much text stops the
    --      font from rendering partway down.
    local seb = CreateFrame("Frame", "QUI_ChatCopyScrollingEditBox", editBg, "ScrollingEditBoxTemplate")
    seb:SetPoint("TOPLEFT", 8, -8)
    seb:SetPoint("BOTTOMRIGHT", -8, 8)
    local editBox = seb:GetEditBox()
    editBox:SetAutoFocus(false)
    editBox:SetTextColor(theme.text[1], theme.text[2], theme.text[3], theme.text[4] or 1)
    chatCopyFrame.scrollingEditBox = seb
    chatCopyFrame.editBox = editBox
    ApplyScrollingEditBoxFont(seb)

    -- The template ships a ScrollBox but no scrollbar; create + bind a
    -- MinimalScrollBar on the right edge (mouse wheel works regardless).
    if _G.ScrollUtil and _G.ScrollUtil.RegisterScrollBoxWithScrollBar then
        local scrollBar = CreateFrame("EventFrame", nil, seb, "MinimalScrollBar")
        scrollBar:SetPoint("TOPRIGHT", seb, "TOPRIGHT", -1, -2)
        scrollBar:SetPoint("BOTTOMRIGHT", seb, "BOTTOMRIGHT", -1, 2)
        local scrollBox = seb:GetScrollBox()
        _G.ScrollUtil.RegisterScrollBoxWithScrollBar(scrollBox, scrollBar)
        -- Managed visibility: hide the WHOLE bar (and its track channel) when there
        -- is nothing to scroll, and reclaim the gutter for the text; show + inset
        -- when there is. Without this the empty track lingers and reads as a broken
        -- scrollbar on short histories.
        if _G.ScrollUtil.AddManagedScrollBarVisibilityBehavior and _G.CreateAnchor then
            local withBar = {
                _G.CreateAnchor("TOPLEFT", seb, "TOPLEFT", 0, 0),
                _G.CreateAnchor("BOTTOMRIGHT", seb, "BOTTOMRIGHT", -16, 0),
            }
            local withoutBar = {
                _G.CreateAnchor("TOPLEFT", seb, "TOPLEFT", 0, 0),
                _G.CreateAnchor("BOTTOMRIGHT", seb, "BOTTOMRIGHT", 0, 0),
            }
            _G.ScrollUtil.AddManagedScrollBarVisibilityBehavior(scrollBox, scrollBar, withBar, withoutBar)
        end
        chatCopyFrame.scrollBar = scrollBar
        StyleMinimalScrollBar(scrollBar, accent)
    end

    -- Close button
    local closeBtn = CreateCloseButton(chatCopyFrame, function() chatCopyFrame:Hide() end)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    chatCopyFrame.cornerCloseButton = closeBtn
    StyleThemedButton(closeBtn, "ghost")

    -- Select All button
    local selectAllBtn = CreateThemedButton(chatCopyFrame, "Select All", 100, 24, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end, "primary")
    selectAllBtn:SetPoint("BOTTOMLEFT", 12, 10)
    chatCopyFrame.selectAllButton = selectAllBtn
    StyleThemedButton(selectAllBtn, "primary")

    local closeBottomBtn = CreateThemedButton(chatCopyFrame, "Close", 80, 24, function()
        chatCopyFrame:Hide()
    end, "ghost")
    closeBottomBtn:SetPoint("BOTTOMRIGHT", -32, 10)
    chatCopyFrame.closeButton = closeBottomBtn
    StyleThemedButton(closeBottomBtn, "ghost")

    -- Resize grip
    local resizeBtn = CreateFrame("Button", nil, chatCopyFrame)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    chatCopyFrame.resizeButton = resizeBtn
    StyleResizeButton(resizeBtn)
    resizeBtn:SetScript("OnMouseDown", function() chatCopyFrame:StartSizing("BOTTOMRIGHT") end)
    resizeBtn:SetScript("OnMouseUp", function()
        chatCopyFrame:StopMovingOrSizing()
        -- ScrollingEditBox reflows on its own OnSizeChanged; forcing UpdateScrollBox
        -- here snapped the scroll back to the top, so leave it to the widget.
    end)

    -- Add to special frames so ESC closes it
    if not tContains(UISpecialFrames, "QUI_ChatCopyFrame") then
        tinsert(UISpecialFrames, "QUI_ChatCopyFrame")
    end

    return chatCopyFrame
end

-- Open the chat-copy frame populated from ONE window's visible set (the
-- window the copy button was clicked on). windowID nil → whole store.
function Copy.ShowCustomCopyFrame(windowID)
    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end
    local frame = CreateChatCopyFrame()
    RefreshPopupAccent(frame)
    local lines = GetCustomDisplayLines(windowID)
    local text = #lines > 0 and tconcat(lines, "\n") or "(No copyable messages in custom display)"
    -- SetText on the CONTROL routes through the mixin (editBox:ApplyText +
    -- scrollbox update); the scrollbox virtualizes large histories so the font
    -- renders all the way down.
    frame.scrollingEditBox:SetText(text)
    frame:Show()
    frame.editBox:SetFocus()
    if #text <= AUTO_HIGHLIGHT_MAX_CHARS then
        frame.editBox:HighlightText()
    end
    -- Land on the NEWEST lines (bottom). Deferred a frame: the scrollbox extent
    -- settles only after the text lays out.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            local seb = frame.scrollingEditBox
            local sb = seb and seb.GetScrollBox and seb:GetScrollBox()
            if frame:IsShown() and sb and sb.ScrollToEnd then
                sb:ScrollToEnd()
            end
        end)
    end
end

-- Apply the current copyButtonMode to ONE window's button + its container.
-- Called on creation and on every subsequent EnsureCustomCopyButton call so
-- live mode-switches take effect without a /reload.
--
-- "always"  — button always visible; container hover scripts cleared; mouse released.
-- "hover"   — button hidden until container OnEnter; true OnLeave (cursor no longer
--             over the container or any child) hides it again. EnableMouse(true) makes
--             the container swallow panel-background clicks — acceptable (children keep
--             priority; SMF/drag-strip interactions are unaffected).
-- "hidden"/"disabled" — button hidden; hover scripts cleared; mouse released.
local function ApplyCustomCopyButtonMode(button, container)
    if not (button and container) then return end
    local settings = I.GetSettings and I.GetSettings()
    local mode = settings and settings.copyButtonMode or "always"
    if mode == "hidden" or mode == "disabled" then
        button:Hide()
        container:SetScript("OnEnter", nil)
        container:SetScript("OnLeave", nil)
        container:SetScript("OnUpdate", nil)
        container:EnableMouse(false)
    elseif mode == "hover" then
        button:Hide()
        container:EnableMouse(true)
        container._quiCopyHovered = false
        -- Drive show AND hide from a single IsMouseOver() poll, NOT OnEnter/
        -- OnLeave. The container has mouse-enabled children (scrollbar track,
        -- jump-to-bottom + copy buttons, drag strip, resize grip). Entering OR
        -- leaving THROUGH a child fires the child's enter/leave, not the
        -- container's, so an OnEnter/OnLeave pair both misses the show (cursor
        -- arrives onto the scrollbar first, container OnEnter never fires) and
        -- misses the hide (cursor departs off the scrollbar). IsMouseOver() is
        -- true for the whole container rect, children included, so the poll is
        -- correct for both directions. It only fires while the container is
        -- shown, and toggles the button on transitions only.
        container:SetScript("OnEnter", nil)
        container:SetScript("OnLeave", nil)
        container:SetScript("OnUpdate", function(self)
            local over = (self.IsMouseOver and self:IsMouseOver()) or false
            if over ~= self._quiCopyHovered then
                self._quiCopyHovered = over
                button:SetShown(over)
            end
        end)
    else -- "always"
        button:Show()
        container:SetScript("OnEnter", nil)
        container:SetScript("OnLeave", nil)
        container:SetScript("OnUpdate", nil)
        container:EnableMouse(false)
    end
end

-- Create one window's copy button, stored on its container so it follows the
-- container through DisplayLayer's window pool (no orphan accumulation on
-- delete/recreate). The OnClick reads the button's CURRENT windowID (refreshed
-- on every EnsureCustomCopyButton) so the copy stays scoped to the right
-- window even after id compaction shuffles ids.
local function CreateCopyButton(windowID, container)
    -- Window 1 keeps the legacy global name (parity with the old singleton);
    -- windows 2+ stay anonymous, like the scrollbar/jump-bottom chrome.
    local name = (windowID == 1) and "QUI_CustomChatCopyButton" or nil
    local button = CreateFrame("Button", name, container)
    button:SetSize(COPY_BUTTON_SIZE, COPY_BUTTON_SIZE)
    button:SetPoint("TOPRIGHT", container, "TOPRIGHT", -2, 2)
    if button.SetFrameLevel then
        button:SetFrameLevel(COPY_BUTTON_FRAME_LEVEL)
    end
    button:EnableMouse(true)
    button._hoverBg = button:CreateTexture(nil, "BACKGROUND")
    button._hoverBg:SetAllPoints(button)
    button._hoverBg:Hide()
    RefreshCopyGlyph(button, false)
    button:SetScript("OnEnter", function(self)
        RefreshCopyGlyph(self, true)
    end)
    button:SetScript("OnLeave", function(self)
        RefreshCopyGlyph(self, false)
    end)
    button:SetScript("OnClick", function(self)
        Copy.ShowCustomCopyFrame(self._quiWindowID)
    end)
    container._quiCopyButton = button
    return button
end

-- Ensure every live window has its own copy button, each scoped to that
-- window's active tab. Idempotent: existing buttons are reused (and their
-- windowID + mode refreshed) so live settings changes and id compaction both
-- take effect without a /reload.
function Copy.EnsureCustomCopyButton()
    local Display = ns.QUI.Chat.DisplayLayer
    if not (Display and Display.GetContainer) then return end
    local count = (Display.GetWindowCount and Display.GetWindowCount()) or 1
    local settings = I.GetSettings and I.GetSettings()
    local mode = settings and settings.copyButtonMode or "always"
    for windowID = 1, count do
        local container = Display.GetContainer(windowID)
        if container then
            local button = container._quiCopyButton
            -- Lazy creation: skip first creation for hidden/disabled to avoid
            -- an invisible orphan button when the feature is off.
            if not button and mode ~= "hidden" and mode ~= "disabled" then
                button = CreateCopyButton(windowID, container)
            end
            if button then
                button._quiWindowID = windowID
                ApplyCustomCopyButtonMode(button, container)
            end
        end
    end
end

-- DisplayLayer.DeleteWindow compacts window ids; refresh every surviving
-- button's windowID + mode. The deleted window's container is hidden/pooled by
-- DisplayLayer, so its button hides with it and is reclaimed (via the stored
-- container._quiCopyButton) when that pooled shell is reused.
function Copy.OnWindowDeleted()
    Copy.EnsureCustomCopyButton()
end

---------------------------------------------------------------------------
-- Public surface
---------------------------------------------------------------------------
Copy.ShowURLPopup  = ShowCopyPopup
Copy.SetupURLClick = SetupURLClickHandler
