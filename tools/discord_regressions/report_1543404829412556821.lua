-- Run from the addon root with Lua 5.1.
local sent, popup = {}, nil
local secret = {}
local grouped, raided = true, true
local instanceGroup, instanceRaid = false, false
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
IsInGroup = function(category) return category == LE_PARTY_CATEGORY_INSTANCE and instanceGroup or (category ~= LE_PARTY_CATEGORY_INSTANCE and grouped) end
IsInRaid = function(category) return category == LE_PARTY_CATEGORY_INSTANCE and instanceRaid or (category ~= LE_PARTY_CATEGORY_INSTANCE and raided) end
CreateFrame = function()
    return setmetatable({}, { __index = function() return function() end end })
end
CreateAbbreviateConfig = function(t) return t end
AbbreviateNumbers = function(n) return tostring(n) end
BreakUpLargeNumbers = function(n) return tostring(n) end
SlashCmdList = {}
local pending, queueSending = {}, false
C_ChatInfo = { SendChatMessage = function(...)
    assert(queueSending, 'reports must use the shared throttling queue')
    sent[#sent + 1] = {...}
end }
ChatThrottleLib = { SendChatMessage = function(_, priority, prefix, text, channel, language, target, queueName)
    assert(priority == 'NORMAL' and prefix == 'QUI_DAMAGE_METER' and queueName == prefix)
    pending[#pending + 1] = {text, channel, language, target}
end }
local function flush()
    queueSending = true
    for _, line in ipairs(pending) do C_ChatInfo.SendChatMessage(unpack(line, 1, 4)) end
    pending, queueSending = {}, false
end
StaticPopup_Show = function(which, _, _, data)
    assert(which == 'GENERIC_INPUT_BOX')
    popup = data
end
Enum = { DamageMeterType = { DamageDone = 0, Dps = 1 },
    DamageMeterSessionType = { Overall = 0, Current = 1 } }
local appearance = { numberFormat = 'complete', showSecondaryValue = true }
QUI = { db = { profile = { damageMeter = { native = {
    windows = { {} }, appearance = { global = appearance, perWindow = {} },
} } } } }
local ns = { L = setmetatable({}, { __index = function(_, key) return key end }),
    Helpers = { IsSecretValue = function(v) return rawequal(v, secret) end } }
assert(loadfile('QUI_DamageMeter/damage_meter/damage_meter.lua'))('QUI', ns)
local Window = ns.QUI_DamageMeter.Window
local window = setmetatable({windowID = 1, damageMeterType = 1, sessionType = 1,
    sessionID = 7, sessionLabel = 'Boss', _renderSources = {
        {name = 'Alpha', rank = 1, totalAmount = 1000, amountPerSecond = 100},
        {name = 'Bravo', rank = 2, totalAmount = 500, amountPerSecond = 50},
    }}, {__index = Window})
local function node(label, callback)
    local n = { label = label, callback = callback, children = {} }
    function n:CreateButton(text, fn)
        local child = node(text, fn); self.children[text] = child; return child
    end
    n.CreateRadio = n.CreateButton
    n.CreateCheckbox = n.CreateButton
    function n:CreateTitle() end
    function n:CreateDivider() end
    function n:SetEnabled(value) self.enabled = value end
    return n
end
local menu
MenuUtil = { CreateContextMenu = function(_, fn) menu = node(); fn(nil, menu) end }
window._PopulateSessionMenu = function() end
window:_OpenConfigMenu()
local share = assert(menu.children['Share Results'], 'meter menu must offer sharing')
share.children.Party.callback()
assert(#sent == 0 and #pending == 3, 'snapshot must enter the queue before sending')
flush()
assert(#sent == 3 and sent[1][1] == 'QUI - DPS - Boss')
assert(sent[2][1] == '1. Alpha - 100 (1000)' and sent[3][1] == '2. Bravo - 50 (500)')
for _, line in ipairs(sent) do assert(line[2] == 'PARTY') end
sent = {}; share.children.Raid.callback(); flush()
assert(#sent == 3 and sent[1][2] == 'RAID')
sent = {}; share.children.Whisper.callback()
assert(#sent == 0 and popup, 'whisper must request recipient first')
window._renderSources[1].amountPerSecond = 999
popup.callback('  Receiver-Realm  '); flush()
assert(#sent == 3 and sent[2][1] == '1. Alpha - 100 (1000)', 'whisper must send snapshot')
assert(sent[1][2] == 'WHISPER' and sent[1][4] == 'Receiver-Realm')
sent = {}; popup.callback('   '); flush(); assert(#sent == 0)
grouped, raided = false, false
share.children.Party.callback(); share.children.Raid.callback(); flush(); assert(#sent == 0)
window:_OpenConfigMenu()
assert(menu.children['Share Results'].children.Party.enabled == false)
assert(menu.children['Share Results'].children.Raid.enabled == false)
grouped = true
window._renderSources[2].totalAmount = secret
share.children.Party.callback(); flush(); assert(#sent == 0, 'restricted data must not partially send')
window._renderSources = {}; share.children.Party.callback(); flush(); assert(#sent == 0)
window._renderSources = {{name='Solo',rank=1,totalAmount=500,amountPerSecond=50}}
window.damageMeterType = 0; window.sessionID = nil; window.sessionType = 0
appearance.showSecondaryValue = false
share.children.Party.callback(); flush()
assert(sent[1][1] == 'QUI - Damage Done - Overall' and sent[2][1] == '1. Solo - 500')
-- Native chat routing prefers home groups and uses INSTANCE_CHAT only when needed.
sent = {}; grouped, raided, instanceGroup, instanceRaid = false, false, true, false
window:_OpenConfigMenu(); share = menu.children['Share Results']
assert(share.children.Party.enabled and not share.children.Raid.enabled)
share.children.Party.callback(); flush()
assert(#sent == 2 and sent[1][2] == 'INSTANCE_CHAT', 'queued dungeon party must use instance chat')
sent = {}; instanceRaid = true
window:_OpenConfigMenu(); share = menu.children['Share Results']
assert(share.children.Raid.enabled)
share.children.Raid.callback(); flush()
assert(#sent == 2 and sent[1][2] == 'INSTANCE_CHAT', 'LFR raid must use instance chat')
sent = {}; grouped, raided = true, true
share.children.Party.callback(); share.children.Raid.callback(); flush()
assert(sent[1][2] == 'PARTY' and sent[3][2] == 'RAID', 'home group takes precedence')
-- Large and repeated snapshots stay queued in order, without a direct-send fallback.
sent = {}; window._renderSources = {}
for i = 1, 40 do window._renderSources[i] = {name = 'Player' .. i, rank = i, totalAmount = i, amountPerSecond = i} end
share.children.Party.callback(); share.children.Party.callback()
assert(#sent == 0 and #pending == 82, 'all report lines must share the queue')
flush()
assert(#sent == 82 and sent[2][1]:find('Player1', 1, true) and sent[41][1]:find('Player40', 1, true))
assert(sent[1][1] == sent[42][1], 'repeated reports keep each header before its rows')
sent = {}; local throttle = ChatThrottleLib; ChatThrottleLib = nil
share.children.Party.callback(); flush(); assert(#sent == 0, 'no unthrottled fallback')
ChatThrottleLib = throttle
print('OK: damage meter sharing')
