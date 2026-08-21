local loadstring = loadstring or load

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source:gsub("\r\n", "\n")
end

local source = readAll("modules/qol/qol.lua")
local start = assert(source:find("local function OnQuestDetail()", 1, true))
local finish = assert(source:find("\nend", start, true))
local block = source:sub(start, finish + 4)
_G.QUI_TEST_QUEST_SETTINGS = nil
_G.QUI_TEST_QUEST_ACCEPTED = 0
local OnQuestDetail = assert(loadstring(([=[
local GetSettings = function() return QUI_TEST_QUEST_SETTINGS end
local ShouldPauseQuest = function() return false end
local AcceptQuest = function() QUI_TEST_QUEST_ACCEPTED = QUI_TEST_QUEST_ACCEPTED + 1 end
%s
return OnQuestDetail
]=]):format(block), "qol_auto_accept_quest"))()

for _, value in ipairs({ false, "off", 0 }) do
    QUI_TEST_QUEST_SETTINGS = { autoAcceptQuest = value }
    OnQuestDetail()
end
QUI_TEST_QUEST_SETTINGS = nil
OnQuestDetail()
assert(_G.QUI_TEST_QUEST_ACCEPTED == 0, "disabled and legacy off values must not accept quests")

QUI_TEST_QUEST_SETTINGS = { autoAcceptQuest = true }
OnQuestDetail()
assert(_G.QUI_TEST_QUEST_ACCEPTED == 1, "true must accept quests")

_G.QUI_TEST_QUEST_SETTINGS = nil
_G.QUI_TEST_QUEST_ACCEPTED = nil

print("qol_auto_accept_quest_test.lua: ok")
