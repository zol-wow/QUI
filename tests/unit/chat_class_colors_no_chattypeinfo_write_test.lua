-- tests/unit/chat_class_colors_no_chattypeinfo_write_test.lua
-- Run: lua tests/unit/chat_class_colors_no_chattypeinfo_write_test.lua
--
-- Regression guard for the chat taint bug:
--   "attempt to perform string conversion on a secret string value
--    (execution tainted by 'QUI')" at HistoryKeeper ChatHistory_GetToken,
--   firing on MONSTER_YELL during combat.
--
-- ROOT CAUSE: class_colors.lua used to toggle name-by-class coloring by
-- WRITING into Blizzard's global ChatTypeInfo table
-- (ChatTypeInfo[t].colorNameByClass = true). Writing a Blizzard-owned table
-- from addon code taints it; Blizzard's secure ChatFrame_MessageEventHandler
-- then reads ChatTypeInfo on every message, taints execution, and the
-- persistent accessIDs table in ChatHistory_GetAccessID stays poisoned for the
-- session -- so the first chat payload that is a secret value (monster combat
-- speech) throws in GetToken.
--
-- THE FIX: never mutate ChatTypeInfo. Class coloring is done post-render
-- instead (see chat_class_colors_sender_recolor_test.lua). This test loads the
-- modifier with class colors ENABLED and asserts it writes nothing into
-- ChatTypeInfo. It FAILS on the pre-fix source (3 writes: SAY/YELL/CHANNEL)
-- and PASSES once the ChatTypeInfo write path is removed.

-- Record every write into any ChatTypeInfo sub-table.
local writes = {}
local function guardedTypeTable(name)
    return setmetatable({}, {
        __newindex = function(t, k, v)
            writes[#writes + 1] = name .. "." .. tostring(k)
            rawset(t, k, v)
        end,
    })
end

ChatTypeInfo = {}
for _, t in ipairs({
    "SAY", "YELL", "CHANNEL", "GUILD", "OFFICER",
    "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "WHISPER",
    "MONSTER_SAY", "MONSTER_YELL",
}) do
    ChatTypeInfo[t] = guardedTypeTable(t)
end

-- SetChatColorNameByClass IS a real WoW function: Blizzard calls it from
-- ChatConfigFrame (Blizzard_ChatFrame/Mainline/ChatConfigFrame.lua:1312), and
-- the UPDATE_CHAT_COLOR_NAME_BY_CLASS event handler writes
-- ChatTypeInfo[strupper(group)].colorNameByClass
-- (Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua:160). So routing the
-- toggle through it still lands in ChatTypeInfo -- just as taint-unsafe as a
-- direct write. Model that handler's write here so this test fails on EITHER
-- reintroduced path (direct ChatTypeInfo write OR SetChatColorNameByClass).
function SetChatColorNameByClass(group, checked)
    local info = ChatTypeInfo[string.upper(group)]
    if info then info.colorNameByClass = checked end
end

function CreateFrame()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:SetScript() end
    return frame
end

local settings = {
    enabled = true,
    modifiers = {
        classColors = { enabled = true, recolorBodyText = false },
    },
}

local ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = {
        Chat = {
            _afterRefresh = {},
            Pipeline = {
                Register = function() end,
                Unregister = function() end,
            },
            _internals = {
                GetSettings = function() return settings end,
                IsChatEnabled = function(s) return s and s.enabled ~= false end,
                IsChatMessagingLockedDown = function() return false end,
            },
        },
    },
}

-- Loading the file runs ApplyEnabled() once; with class colors enabled the
-- pre-fix code writes ChatTypeInfo here.
assert(loadfile("modules/chat/modifiers/class_colors.lua"))("QUI", ns)

-- Also drive a settings refresh (enable -> apply) to be thorough.
for _, fn in ipairs(ns.QUI.Chat._afterRefresh) do fn() end

assert(
    #writes == 0,
    "class_colors.lua must NOT write into ChatTypeInfo (taints chat / poisons "
        .. "ChatHistory_GetAccessID). Offending writes: "
        .. (next(writes) and table.concat(writes, ", ") or "(none)")
)

print("OK: chat_class_colors_no_chattypeinfo_write_test")
