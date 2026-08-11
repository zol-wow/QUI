local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local QUICore = ns.Addon

local _pendingBackdropData = Helpers.CreateStateTable()

local function _CheckFrameHasValidSize(frame)
    local w = frame:GetWidth()
    local h = frame:GetHeight()
    if w and h then
        local test = w + h
        return test > 0
    end
    return false
end

local BACKDROP_MAX_RETRIES = 50

function QUICore.SafeSetBackdrop(frame, backdropInfo, borderColor, bgColor)
    if not frame or not frame.SetBackdrop then return false end

    local hasValidSize = false
    local ok, result = ns.SafeCall("defer-ooc", _CheckFrameHasValidSize, frame)
    if ok and result then
        hasValidSize = true
    end

    if not hasValidSize then
        _pendingBackdropData[frame] = { info = backdropInfo, borderColor = borderColor, bgColor = bgColor }
        QUICore.__pendingBackdrops = QUICore.__pendingBackdrops or {}
        QUICore.__pendingBackdrops[frame] = true

        if not QUICore.__backdropUpdateFrame then
            local updateFrame = CreateFrame("Frame")
            local elapsed = 0
            updateFrame:SetScript("OnUpdate", function(self, delta)
                elapsed = elapsed + delta
                if elapsed < 0.1 then return end
                elapsed = 0
                if InCombatLockdown() then return end

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
                        pendingData.retries = (pendingData.retries or 0) + 1
                        if pendingData.retries > BACKDROP_MAX_RETRIES then
                            _pendingBackdropData[pendingFrame] = nil
                            processed[#processed + 1] = pendingFrame
                        else
                            local checkOk, checkResult = ns.SafeCall("defer-ooc", _CheckFrameHasValidSize, pendingFrame)

                            if checkOk and checkResult and not InCombatLockdown() then
                                local setOk = ns.SafeCallMethod("defer-ooc", pendingFrame, "SetBackdrop", pendingData.info)
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

                if #processed >= totalCount then
                    self:SetScript("OnUpdate", nil)
                    self:Hide()
                end
            end)
            QUICore.__backdropUpdateHandler = updateFrame:GetScript("OnUpdate")
            QUICore.__backdropUpdateFrame = updateFrame
        end
        if QUICore.__backdropUpdateHandler then
            QUICore.__backdropUpdateFrame:SetScript("OnUpdate", QUICore.__backdropUpdateHandler)
        end
        QUICore.__backdropUpdateFrame:Show()
        return false
    end

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
                                local setOk = ns.SafeCallMethod("defer-ooc", pendingFrame, "SetBackdrop", pendingData.info)
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
            if not QUICore.__backdropEventListening then
                QUICore.__backdropEventListening = true
                QUICore.__backdropEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            end
        end
        return false
    end

    local setOk = ns.SafeCallMethod("defer-ooc", frame, "SetBackdrop", backdropInfo)
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
