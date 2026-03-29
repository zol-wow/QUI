--- QUI Deferred Backdrop System
--- Combat/Secret Value protection for SetBackdrop calls (WoW 12.0+)

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

-- QUICore is created by main.lua which loads before this file
local QUICore = ns.Addon

---=================================================================================
--- SAFE BACKDROP UTILITY (Combat/Secret Value Protection)
---=================================================================================

-- Weak-keyed table to store pending backdrop data per frame (avoids writing properties
-- directly onto Blizzard secure frames, which can cause taint).
local _pendingBackdropData = Helpers.CreateStateTable()

-- Reusable named function: check if a frame has valid (non-secret) dimensions.
-- Avoids creating a throwaway closure on every pcall.
local function _CheckFrameHasValidSize(frame)
    local w = frame:GetWidth()
    local h = frame:GetHeight()
    if w and h then
        local test = w + h  -- Will error if secret
        return test > 0
    end
    return false
end

-- Max retries per frame before giving up (50 * 0.1s = 5 seconds)
local BACKDROP_MAX_RETRIES = 50

-- Global SafeSetBackdrop function that defers SetBackdrop calls when frame dimensions
-- are secret values (Midnight 12.0 protection) or when in combat lockdown.
-- This prevents the "attempt to perform arithmetic on a secret value" error that occurs
-- when Blizzard's Backdrop.lua tries to use GetWidth()/GetHeight() during protected contexts.
--
-- @param frame The frame to set backdrop on (must have BackdropTemplate mixed in)
-- @param backdropInfo The backdrop info table, or nil to remove backdrop
-- @param borderColor Optional {r,g,b,a} table for border color after backdrop is set
-- @param bgColor Optional {r,g,b,a} table for background color after backdrop is set
-- @return boolean True if backdrop was set immediately, false if deferred
function QUICore.SafeSetBackdrop(frame, backdropInfo, borderColor, bgColor)
    if not frame or not frame.SetBackdrop then return false end

    -- Check if frame has valid (non-secret) dimensions
    -- SetBackdrop internally calls GetWidth/GetHeight which can error on secret values
    local hasValidSize = false
    local ok, result = pcall(_CheckFrameHasValidSize, frame)
    if ok and result then
        hasValidSize = true
    end

    -- If dimensions are secret/invalid, defer the backdrop setup
    if not hasValidSize then
        _pendingBackdropData[frame] = { info = backdropInfo, borderColor = borderColor, bgColor = bgColor }
        QUICore.__pendingBackdrops = QUICore.__pendingBackdrops or {}
        QUICore.__pendingBackdrops[frame] = true

        -- Set up deferred processing via OnUpdate (for when dimensions become valid)
        if not QUICore.__backdropUpdateFrame then
            local updateFrame = CreateFrame("Frame")
            local elapsed = 0
            updateFrame:SetScript("OnUpdate", function(self, delta)
                elapsed = elapsed + delta
                if elapsed < 0.1 then return end  -- Check every 0.1s
                elapsed = 0

                -- Performance: reuse module-level scratch table instead of allocating per tick.
                -- Track total vs processed count to avoid a second pairs() scan to check emptiness.
                local processed = QUICore.__backdropProcessed
                if not processed then
                    processed = {}
                    QUICore.__backdropProcessed = processed
                end
                wipe(processed)
                local totalCount = 0
                for pendingFrame in pairs(QUICore.__pendingBackdrops or {}) do
                    totalCount = totalCount + 1
                    local pendingData = _pendingBackdropData[pendingFrame]
                    if pendingFrame and pendingData then
                        -- Per-frame retry tracking: abandon individual frames after
                        -- max retries instead of blocking the entire batch.
                        pendingData.retries = (pendingData.retries or 0) + 1
                        if pendingData.retries > BACKDROP_MAX_RETRIES then
                            _pendingBackdropData[pendingFrame] = nil
                            processed[#processed + 1] = pendingFrame
                        else
                            -- Re-check if dimensions are now valid (reuse named function)
                            local checkOk, checkResult = pcall(_CheckFrameHasValidSize, pendingFrame)

                            if checkOk and checkResult and not InCombatLockdown() then
                                local setOk = pcall(pendingFrame.SetBackdrop, pendingFrame, pendingData.info)
                                if setOk then
                                    if pendingData.info and pendingData.borderColor then
                                        local c = pendingData.borderColor
                                        pendingFrame:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
                                    end
                                    if pendingData.info and pendingData.bgColor then
                                        local c = pendingData.bgColor
                                        pendingFrame:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
                                    end
                                    _pendingBackdropData[pendingFrame] = nil
                                    processed[#processed + 1] = pendingFrame
                                end
                            end
                        end
                    else
                        processed[#processed + 1] = pendingFrame
                    end
                end

                for _, pf in ipairs(processed) do
                    QUICore.__pendingBackdrops[pf] = nil
                end

                -- Stop OnUpdate if no more pending (SetScript nil to avoid per-frame CPU cost)
                if #processed >= totalCount then
                    self:SetScript("OnUpdate", nil)
                    self:Hide()
                end
            end)
            QUICore.__backdropUpdateHandler = updateFrame:GetScript("OnUpdate")
            QUICore.__backdropUpdateFrame = updateFrame
        end
        -- Per-frame retry count is tracked in pendingData.retries (no global reset needed)
        if QUICore.__backdropUpdateHandler then
            QUICore.__backdropUpdateFrame:SetScript("OnUpdate", QUICore.__backdropUpdateHandler)
        end
        QUICore.__backdropUpdateFrame:Show()
        return false
    end

    -- If in combat, defer backdrop setup to avoid secret value errors
    if InCombatLockdown() then
        local alreadyPending = QUICore.__pendingBackdrops and QUICore.__pendingBackdrops[frame]
        if not alreadyPending then
            _pendingBackdropData[frame] = { info = backdropInfo, borderColor = borderColor, bgColor = bgColor }

            if not QUICore.__backdropEventFrame then
                local eventFrame = CreateFrame("Frame")
                eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                eventFrame:SetScript("OnEvent", function(self)
                    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                    QUICore.__backdropEventListening = false
                    local stillPending = false
                    for pendingFrame in pairs(QUICore.__pendingBackdrops or {}) do
                        local pendingData = _pendingBackdropData[pendingFrame]
                        if pendingFrame and pendingData then
                            if not InCombatLockdown() then
                                local setOk = pcall(pendingFrame.SetBackdrop, pendingFrame, pendingData.info)
                                if setOk then
                                    if pendingData.info and pendingData.borderColor then
                                        local c = pendingData.borderColor
                                        pendingFrame:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
                                    end
                                    if pendingData.info and pendingData.bgColor then
                                        local c = pendingData.bgColor
                                        pendingFrame:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
                                    end
                                    _pendingBackdropData[pendingFrame] = nil
                                    QUICore.__pendingBackdrops[pendingFrame] = nil
                                else
                                    stillPending = true
                                end
                            else
                                stillPending = true
                            end
                        else
                            _pendingBackdropData[pendingFrame] = nil
                            QUICore.__pendingBackdrops[pendingFrame] = nil
                        end
                    end
                    if stillPending then
                        -- Re-register so we retry on next combat exit
                        self:RegisterEvent("PLAYER_REGEN_ENABLED")
                    else
                        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                        QUICore.__pendingBackdrops = {}
                    end
                end)
                QUICore.__backdropEventFrame = eventFrame
            end

            QUICore.__pendingBackdrops = QUICore.__pendingBackdrops or {}
            QUICore.__pendingBackdrops[frame] = true
            -- Guard: only register if not already listening (avoids redundant event handler fires)
            if not QUICore.__backdropEventListening then
                QUICore.__backdropEventListening = true
                QUICore.__backdropEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            end
        end
        return false
    end

    -- Safe to set backdrop now
    local setOk = pcall(frame.SetBackdrop, frame, backdropInfo)
    if setOk and backdropInfo then
        if borderColor then
            frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        end
        if bgColor then
            frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
        end
    end
    return setOk
end
