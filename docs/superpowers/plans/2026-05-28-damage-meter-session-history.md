# Damage Meter Session History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add runtime-only previous-session selection to QUI's native damage meter through the existing right-click context menu.

**Architecture:** Keep the existing single-file damage meter architecture and extend its data selector from `sessionType` only to `sessionType + optional sessionID`. Use Blizzard's `C_DamageMeter` session list and ID-based fetch APIs; do not persist selected previous session IDs. Thread the selector through main views, breakdowns, target reconstruction, and reset handling.

**Tech Stack:** Lua addon code, Blizzard `C_DamageMeter` API, Blizzard menu descriptions via `MenuUtil.CreateContextMenu`, local unit tests run with `lua`, validation with `luacheck`.

---

## File Map

- Modify: `modules/damage_meter/damage_meter.lua`
  - Add selector-key helper.
  - Re-key view cache by selector string.
  - Add ID-based main-view, breakdown, and target-fetch paths.
  - Add runtime `Window.sessionID`.
  - Replace the current Session menu items with `Current`, `Overall`, and `Previous` submenu.
  - Clear runtime previous-session selections on reset.
- Create: `tests/unit/damage_meter_session_history_test.lua`
  - Static and pure-helper coverage for selector keys, runtime-only state, menu surface, and ID-based API calls.
- Modify: `docs/features/damage-meter.md`
  - Document the right-click `Previous` submenu.

---

### Task 1: Add Failing Session-History Test

**Files:**
- Create: `tests/unit/damage_meter_session_history_test.lua`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/damage_meter_session_history_test.lua`:

```lua
-- tests/unit/damage_meter_session_history_test.lua
-- Run: lua tests/unit/damage_meter_session_history_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data:gsub("\r\n", "\n")
end

local src = readAll("modules/damage_meter/damage_meter.lua")

local start_pos = src:find("local function SessionKey")
assert(start_pos, "could not locate SessionKey helper")
local end_pos = src:find("QUI_DamageMeter%.SessionKey", start_pos)
assert(end_pos, "could not locate QUI_DamageMeter.SessionKey assignment")
local chunk = src:sub(start_pos, end_pos - 1):match("^(.-)\n%s*$")
local SessionKey = assert(loadstring(chunk .. "\nreturn SessionKey"))()

assert(SessionKey(1, nil) == "type:1", "Current selector key must be type-backed")
assert(SessionKey(0, nil) == "type:0", "Overall selector key must be type-backed")
assert(SessionKey(1, 1) == "id:1", "sessionID must take precedence over sessionType")
assert(SessionKey(0, 42) == "id:42", "historical selector key must use the sessionID")
assert(SessionKey(1, 1) ~= SessionKey(1, nil), "id:1 and type:1 must not collide")

assert(src:find("GetCombatSessionFromID", 1, true),
    "main views must support C_DamageMeter.GetCombatSessionFromID")
assert(src:find("GetCombatSessionSourceFromID", 1, true),
    "breakdowns must support C_DamageMeter.GetCombatSessionSourceFromID")
assert(src:find("GetAvailableCombatSessions", 1, true),
    "menu must use C_DamageMeter.GetAvailableCombatSessions")
assert(src:find('root:CreateButton("Previous"', 1, true),
    "Session menu must expose a Previous submenu")
assert(src:find("previousMenu:CreateRadio", 1, true),
    "Previous submenu must create selectable session rows")
assert(src:find("availableSession.name", 1, true),
    "Previous submenu rows must use Blizzard's session name field")
assert(src:find("self.sessionID = nil", 1, true),
    "Window runtime state must initialize sessionID to nil")

local defaults = readAll("core/defaults.lua")
local nativeStart = defaults:find("native = {", 1, true)
assert(nativeStart, "could not locate damageMeter.native defaults")
local nativeEnd = defaults:find("\n%s*alerts%s*=", nativeStart) or #defaults
local nativeBlock = defaults:sub(nativeStart, nativeEnd)
assert(not nativeBlock:find("sessionID", 1, true),
    "sessionID must remain runtime-only and absent from damage meter defaults")

print("OK: damage_meter_session_history_test")
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
lua tests/unit/damage_meter_session_history_test.lua
```

Expected: FAIL with `could not locate SessionKey helper`.

- [ ] **Step 3: Commit the failing test**

```bash
git add tests/unit/damage_meter_session_history_test.lua
git commit -m "test damage meter session history"
```

---

### Task 2: Add Selector-Key Cache And ID-Based Main Views

**Files:**
- Modify: `modules/damage_meter/damage_meter.lua`
- Test: `tests/unit/damage_meter_session_history_test.lua`

- [ ] **Step 1: Add the selector-key helper**

In `modules/damage_meter/damage_meter.lua`, after `Data._generation = 0`, add:

```lua
local function SessionKey(sessionType, sessionID)
    if sessionID ~= nil then
        return "id:" .. tostring(sessionID)
    end
    return "type:" .. tostring(sessionType)
end
QUI_DamageMeter.SessionKey = SessionKey
```

- [ ] **Step 2: Replace cache helpers with selector-key helpers**

Replace the current `CacheView(sessionType, damageMeterType, view)` helper with:

```lua
local function CacheView(sessionType, sessionID, damageMeterType, view)
    local key = SessionKey(sessionType, sessionID)
    local bySelector = Data._cache[key]
    if not bySelector then
        bySelector = {}
        Data._cache[key] = bySelector
    end
    bySelector[damageMeterType] = view
end

local function GetCachedView(sessionType, sessionID, damageMeterType)
    local bySelector = Data._cache[SessionKey(sessionType, sessionID)]
    return bySelector and bySelector[damageMeterType] or nil
end

local function HasCachedViewKey(selectorKey, damageMeterType)
    local bySelector = Data._cache[selectorKey]
    return bySelector and bySelector[damageMeterType] ~= nil
end
```

- [ ] **Step 3: Add selector-key dirty marking**

Replace `MarkDirty(sessionType, damageMeterType)` with this pair:

```lua
local function MarkDirtyKey(selectorKey, damageMeterType)
    local bySelector = Data._dirty[selectorKey]
    if not bySelector then
        bySelector = {}
        Data._dirty[selectorKey] = bySelector
    end
    bySelector[damageMeterType] = true
end

local function MarkDirty(sessionType, damageMeterType)
    MarkDirtyKey(SessionKey(sessionType, nil), damageMeterType)
end
```

Keep `MarkAllDirty()` unchanged except that later refresh code will clear the cache before notifying windows.

- [ ] **Step 4: Change `FetchView` to accept `sessionID`**

Replace the `FetchView` function signature and API-fetch block with:

```lua
local function FetchView(sessionType, damageMeterType, sessionID)
    if not C_DamageMeter then
        return NewView({}, 0, 0, 0)
    end

    local ok, session
    if sessionID ~= nil then
        if not C_DamageMeter.GetCombatSessionFromID then
            return NewView({}, 0, 0, 0)
        end
        ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, damageMeterType)
    else
        if not C_DamageMeter.GetCombatSessionFromType then
            return NewView({}, 0, 0, 0)
        end
        ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, damageMeterType)
    end
    if not ok or type(session) ~= "table" then
        return NewView({}, 0, 0, 0)
    end
```

Keep the existing line that normalizes `session.combatSources` after this block:

```lua
    local sources = NormalizeSources(session.combatSources or {})
```

- [ ] **Step 5: Update duration/rate logic in `FetchView`**

In `FetchView`, replace the duration block with:

```lua
    local duration
    if sessionID ~= nil then
        duration = session.durationSeconds
    elseif sessionType == (Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Expired or 2) then
        duration = session.durationSeconds
    else
        duration = GetCombatElapsed()
    end
```

Replace the `rateDuration` block with:

```lua
    local rateDuration
    if sessionID ~= nil then
        rateDuration = session.durationSeconds
    else
        local apiDuration = C_DamageMeter.GetSessionDurationSeconds
            and C_DamageMeter.GetSessionDurationSeconds(sessionType)
        rateDuration = ResolveRateDuration(
            sessionType, apiDuration, GetCombatElapsed(), session.durationSeconds,
            IsSecret, (S and S.Current) or 1, (S and S.Expired) or 2)
    end
```

Keep the existing loop that calls `DerivePerSecond`.

- [ ] **Step 6: Update `Data:Refresh` and `Data:GetView`**

In `Data:Refresh`, change the `_allDirty` branch to clear the selector cache instead of iterating the old session-type table:

```lua
    if self._allDirty then
        self._allDirty = false
        self._cache = {}
        self._dirty = {}
        if self._onChange then self:_onChange() end
        if Perf.enabled then Perf:Record("data", PerfNow() - _t0) end
        return
    end
```

Replace the dirty loop with:

```lua
    for selectorKey, byType in pairs(self._dirty) do
        local sessionType, sessionID
        local idText = selectorKey:match("^id:(.+)$")
        if idText then
            sessionID = tonumber(idText)
        else
            sessionType = tonumber(selectorKey:match("^type:(.+)$"))
        end
        for damageMeterType in pairs(byType) do
            CacheView(sessionType, sessionID, damageMeterType,
                FetchView(sessionType, damageMeterType, sessionID))
            anyChanged = true
        end
    end
```

Replace `Data:GetView` with:

```lua
function Data:GetView(sessionType, damageMeterType, sessionID)
    local view = GetCachedView(sessionType, sessionID, damageMeterType)
    if view then return view end
    view = FetchView(sessionType, damageMeterType, sessionID)
    CacheView(sessionType, sessionID, damageMeterType, view)
    return view
end
```

- [ ] **Step 7: Update event dirty handling**

In the `DAMAGE_METER_COMBAT_SESSION_UPDATED` handler, replace the existing comment/body with:

```lua
        for sessionType = 0, 2 do
            MarkDirty(sessionType, arg1)
        end
        local sessionID = _arg2
        if sessionID ~= nil then
            local key = SessionKey(nil, sessionID)
            if HasCachedViewKey(key, arg1) then
                MarkDirtyKey(key, arg1)
            end
        end
```

- [ ] **Step 8: Run tests**

Run:

```bash
lua tests/unit/damage_meter_session_history_test.lua
lua tests/unit/damage_meter_rate_duration_test.lua
```

Expected: `damage_meter_session_history_test` still fails on menu/runtime state if those are not implemented yet; `damage_meter_rate_duration_test` passes.

- [ ] **Step 9: Commit selector data work**

```bash
git add modules/damage_meter/damage_meter.lua
git commit -m "Add damage meter session selectors"
```

---

### Task 3: Thread Session IDs Through Breakdowns And Target Views

**Files:**
- Modify: `modules/damage_meter/damage_meter.lua`
- Test: `tests/unit/damage_meter_target_breakdown_test.lua`

- [ ] **Step 1: Update source-spell fetching**

Replace `FetchSourceSpells` with:

```lua
local function FetchSourceSpells(sessionType, meterType, sourceGUID, sourceCreatureID, sessionID)
    if not C_DamageMeter then return {} end
    local ok, src
    if sessionID ~= nil then
        if not C_DamageMeter.GetCombatSessionSourceFromID then return {} end
        ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID,
            sessionID, meterType, sourceGUID, sourceCreatureID)
    else
        if not C_DamageMeter.GetCombatSessionSourceFromType then return {} end
        ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
            sessionType, meterType, sourceGUID, sourceCreatureID)
    end
    if not ok or type(src) ~= "table" then return {} end
    return src.combatSpells or {}
end
```

- [ ] **Step 2: Update target helpers**

Change signatures and calls:

```lua
function Data:GetEnemyAttackers(sessionType, sessionID, sourceGUID, sourceCreatureID)
    local eType = EnemyDamageTakenType()
    if not eType then return {} end
    local IsSecret = Helpers and Helpers.IsSecretValue
    return AggregateSpellsByUnit(
        FetchSourceSpells(sessionType, eType, sourceGUID, sourceCreatureID, sessionID), IsSecret)
end

function Data:GetPlayerTargetsMap(sessionType, sessionID)
    local eType = EnemyDamageTakenType()
    if not eType then return {} end
    local enemyView = self:GetView(sessionType, eType, sessionID)
    local genKey = SessionKey(sessionType, sessionID) .. ":" .. tostring(enemyView.generation or 0)
    if self._targetsCacheKey == genKey and self._targetsCache then
        return self._targetsCache
    end
    local IsSecret = Helpers and Helpers.IsSecretValue
    local perEnemy = {}
    for _, enemy in ipairs(enemyView.sources or {}) do
        perEnemy[#perEnemy + 1] = {
            enemyName = enemy.name,
            players   = AggregateSpellsByUnit(
                FetchSourceSpells(sessionType, eType, enemy.sourceGUID, enemy.sourceCreatureID, sessionID),
                IsSecret),
        }
    end
    local map = PivotPlayerTargets(perEnemy)
    self._targetsCacheKey = genKey
    self._targetsCache    = map
    return map
end

function Data:GetPlayerTargets(sessionType, sessionID, playerName)
    if playerName == nil then return {} end
    local IsSecret = Helpers and Helpers.IsSecretValue
    if IsSecret and IsSecret(playerName) then return {} end
    return self:GetPlayerTargetsMap(sessionType, sessionID)[playerName] or {}
end
```

- [ ] **Step 3: Update combined healing helpers**

Change the `Data:GetCombinedHealingView` declaration from:

```lua
function Data:GetCombinedHealingView(sessionType)
```

to:

```lua
function Data:GetCombinedHealingView(sessionType, sessionID)
```

Inside that function, replace:

```lua
    local hView = self:GetView(sessionType, hType)
    local aView = self:GetView(sessionType, aType)
```

with:

```lua
    local hView = self:GetView(sessionType, hType, sessionID)
    local aView = self:GetView(sessionType, aType, sessionID)
```

Change the `Data:GetCombinedHealingBreakdown` declaration from:

```lua
function Data:GetCombinedHealingBreakdown(sessionType, sourceGUID, sourceCreatureID)
```

to:

```lua
function Data:GetCombinedHealingBreakdown(sessionType, sessionID, sourceGUID, sourceCreatureID)
```

Inside that function, replace:

```lua
    local hView = self:GetBreakdownView(sessionType, hType, sourceGUID, sourceCreatureID)
    local aView = self:GetBreakdownView(sessionType, aType, sourceGUID, sourceCreatureID)
```

with:

```lua
    local hView = self:GetBreakdownView(sessionType, hType, sourceGUID, sourceCreatureID, sessionID)
    local aView = self:GetBreakdownView(sessionType, aType, sourceGUID, sourceCreatureID, sessionID)
```

Keep the rest of each function's merge logic unchanged.

- [ ] **Step 4: Update `Data:GetBreakdownView`**

Replace the opening API block with:

```lua
function Data:GetBreakdownView(sessionType, damageMeterType, sourceGUID, sourceCreatureID, sessionID)
    if not C_DamageMeter then
        return { spells = {}, maxAmount = 0, totalAmount = 0 }
    end
    local ok, src
    if sessionID ~= nil then
        if not C_DamageMeter.GetCombatSessionSourceFromID then
            return { spells = {}, maxAmount = 0, totalAmount = 0 }
        end
        ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID,
            sessionID, damageMeterType, sourceGUID, sourceCreatureID)
    else
        if not C_DamageMeter.GetCombatSessionSourceFromType then
            return { spells = {}, maxAmount = 0, totalAmount = 0 }
        end
        ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
            sessionType, damageMeterType, sourceGUID, sourceCreatureID)
    end
    if not ok or type(src) ~= "table" then
        return { spells = {}, maxAmount = 0, totalAmount = 0 }
    end
```

Keep the existing return table after this block.

- [ ] **Step 5: Update window and breakdown call sites**

In `Window:Refresh`, use:

```lua
        view = Data:GetCombinedHealingView(self.sessionType, self.sessionID)
```

and:

```lua
        view = Data:GetView(self.sessionType, self.damageMeterType, self.sessionID)
```

In `Breakdown:_ResolveTargets`, use:

```lua
    local st = self.parentWindow.sessionType
    local sid = self.parentWindow.sessionID
    if meterType == T.EnemyDamageTaken then
        return Data:GetEnemyAttackers(st, sid, self.source.sourceGUID, self.source.sourceCreatureID), "Attacked By"
    elseif meterType == T.DamageDone or meterType == T.Dps then
        return Data:GetPlayerTargets(st, sid, self.source.name), "Targets"
    end
```

In `Breakdown:Refresh`, use:

```lua
    local sessionType = self.parentWindow.sessionType
    local sessionID = self.parentWindow.sessionID
```

and pass `sessionID` to the combined and ordinary breakdown helpers:

```lua
        view = Data:GetCombinedHealingBreakdown(sessionType, sessionID,
            self.source.sourceGUID, self.source.sourceCreatureID)
```

```lua
        view = Data:GetBreakdownView(sessionType, damageMeterType,
            self.source.sourceGUID, self.source.sourceCreatureID, sessionID)
```

- [ ] **Step 6: Run tests**

Run:

```bash
lua tests/unit/damage_meter_target_breakdown_test.lua
lua tests/unit/damage_meter_session_history_test.lua
```

Expected: target breakdown test passes; session-history test still fails until menu/runtime state is implemented.

- [ ] **Step 7: Commit breakdown selector work**

```bash
git add modules/damage_meter/damage_meter.lua
git commit -m "Route damage meter breakdowns by session"
```

---

### Task 4: Add Runtime Session Selection Menu

**Files:**
- Modify: `modules/damage_meter/damage_meter.lua`
- Test: `tests/unit/damage_meter_session_history_test.lua`

- [ ] **Step 1: Initialize runtime `sessionID`**

In `Window.New`, add `sessionID = nil` to the instance table:

```lua
        sessionType     = windowState.sessionType,
        sessionID       = nil,
        rows            = {},      -- pool, filled in T10
```

- [ ] **Step 2: Add a small runtime-selector helper inside `_OpenConfigMenu`**

Inside `Window:_OpenConfigMenu`, after `local owner = self.header or self.frame`, add:

```lua
    local function SelectSession(sessionType, sessionID)
        self.sessionType = sessionType or self.sessionType
        self.sessionID = sessionID
        if sessionID == nil and sessionType ~= nil then
            windowState.sessionType = sessionType
        end
        self._lastGeneration = -1
        if self._breakdown and self._breakdown.Close then
            self._breakdown:Close()
        end
        QUI_DamageMeter.WindowManager:RefreshAll()
    end
```

- [ ] **Step 3: Replace the `Session` menu block**

Replace the block from `root:CreateTitle("Session")` through the current `for _, entry in ipairs(sessions)` loop with:

```lua
        root:CreateTitle("Session")
        local S = Enum and Enum.DamageMeterSessionType
        local currentSession = (S and S.Current) or 1
        local overallSession = (S and S.Overall) or 0

        root:CreateRadio("Current",
            function() return self.sessionID == nil and self.sessionType == currentSession end,
            function() SelectSession(currentSession, nil) end)

        root:CreateRadio("Overall",
            function() return self.sessionID == nil and self.sessionType == overallSession end,
            function() SelectSession(overallSession, nil) end)

        local previousMenu = root:CreateButton("Previous")
        local sessions
        if C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions then
            local ok, availableSessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
            if ok and type(availableSessions) == "table" then
                sessions = availableSessions
            end
        end

        if not sessions or #sessions == 0 then
            local none = previousMenu:CreateButton("No previous sessions", function() end)
            none:SetEnabled(false)
        else
            for _, availableSession in ipairs(sessions) do
                local sessionID = availableSession.sessionID
                previousMenu:CreateRadio(availableSession.name,
                    function() return self.sessionID == sessionID end,
                    function() SelectSession(nil, sessionID) end)
            end
        end
```

Do not compare, concatenate, or format `availableSession.name`; pass it directly to the menu row so the user sees Blizzard's session name.

- [ ] **Step 4: Run the session-history test**

Run:

```bash
lua tests/unit/damage_meter_session_history_test.lua
```

Expected: PASS.

- [ ] **Step 5: Commit menu work**

```bash
git add modules/damage_meter/damage_meter.lua
git commit -m "Add damage meter previous session menu"
```

---

### Task 5: Clear Runtime Previous Sessions On Reset

**Files:**
- Modify: `modules/damage_meter/damage_meter.lua`
- Test: `tests/unit/damage_meter_reset_data_test.lua`

- [ ] **Step 1: Track reset-driven runtime clearing in Data**

Near the other Data state fields, add:

```lua
Data._clearRuntimeSessions = false
```

In the `DAMAGE_METER_RESET` event branch, change it to:

```lua
    elseif event == "DAMAGE_METER_RESET" then
        Data._clearRuntimeSessions = true
        MarkAllDirty()
```

- [ ] **Step 2: Add WindowManager runtime clear method**

After `function WindowManager:DespawnAll()` add:

```lua
function WindowManager:ClearRuntimeSessionIDs()
    self:Enumerate(function(_windowID, w)
        if w then
            w.sessionID = nil
            w._lastGeneration = -1
            if w._breakdown and w._breakdown.Close then
                w._breakdown:Close()
            end
        end
    end)
end
```

- [ ] **Step 3: Use the clear method from `_onChange`**

Replace `Data._onChange` with:

```lua
Data._onChange = function(self)
    local clearRuntimeSessions = self._clearRuntimeSessions
    self._clearRuntimeSessions = false
    if clearRuntimeSessions and WindowManager.ClearRuntimeSessionIDs then
        WindowManager:ClearRuntimeSessionIDs()
    end
    WindowManager:Enumerate(function(_id, w)
        if w.Refresh then w:Refresh() end
    end)
end
```

- [ ] **Step 4: Clear runtime previous sessions from the Reset Data menu action**

Inside the existing `Reset Data` button callback, before `RefreshAll()`, add:

```lua
                if QUI_DamageMeter.WindowManager.ClearRuntimeSessionIDs then
                    QUI_DamageMeter.WindowManager:ClearRuntimeSessionIDs()
                end
```

The callback should become:

```lua
        root:CreateButton("Reset Data", function()
            if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
                C_DamageMeter.ResetAllCombatSessions()
                if QUI_DamageMeter.WindowManager.ClearRuntimeSessionIDs then
                    QUI_DamageMeter.WindowManager:ClearRuntimeSessionIDs()
                end
                QUI_DamageMeter.WindowManager:RefreshAll()
            end
        end)
```

- [ ] **Step 5: Extend reset static test**

In `tests/unit/damage_meter_reset_data_test.lua`, add these assertions before the final print:

```lua
assert(src:find("function WindowManager:ClearRuntimeSessionIDs", 1, true),
    "WindowManager must expose ClearRuntimeSessionIDs")
assert(menu:find("ClearRuntimeSessionIDs", 1, true),
    "Reset Data must clear runtime previous-session selections")
```

- [ ] **Step 6: Run reset and session tests**

Run:

```bash
lua tests/unit/damage_meter_reset_data_test.lua
lua tests/unit/damage_meter_session_history_test.lua
```

Expected: both PASS.

- [ ] **Step 7: Commit reset behavior**

```bash
git add modules/damage_meter/damage_meter.lua tests/unit/damage_meter_reset_data_test.lua
git commit -m "Clear damage meter previous sessions on reset"
```

---

### Task 6: Document The Session Menu

**Files:**
- Modify: `docs/features/damage-meter.md`

- [ ] **Step 1: Update the in-window controls section**

In `docs/features/damage-meter.md`, under `## In-window controls`, add or adjust the session bullet so it says:

```markdown
- **Session** — choose `Current`, `Overall`, or `Previous`. `Previous` opens a submenu of Blizzard-tracked combat sessions by name; selecting one changes only the live window state and is cleared by reload or reset.
```

- [ ] **Step 2: Scan the docs change**

Run:

```bash
rg -n "Previous|session|Session" docs/features/damage-meter.md
```

Expected: output includes the new `Previous` wording and no third-party addon names.

- [ ] **Step 3: Commit docs**

```bash
git add docs/features/damage-meter.md
git commit -m "Document damage meter previous sessions"
```

---

### Task 7: Validation

**Files:**
- Validate: `modules/damage_meter/damage_meter.lua`
- Validate: `tests/unit/damage_meter_*.lua`

- [ ] **Step 1: Run focused unit tests**

Run:

```bash
lua tests/unit/damage_meter_session_history_test.lua
lua tests/unit/damage_meter_reset_data_test.lua
lua tests/unit/damage_meter_rate_duration_test.lua
lua tests/unit/damage_meter_target_breakdown_test.lua
lua tests/unit/damage_meter_scaffold_test.lua
```

Expected: each focused test prints its `OK:` line.

- [ ] **Step 2: Run the full damage meter unit subset**

Run:

```bash
for f in tests/unit/damage_meter_*.lua; do lua "$f" || exit 1; done
```

Expected: every damage meter test prints an `OK:` line and the command exits 0.

- [ ] **Step 3: Run Lua syntax and luacheck**

Run:

```bash
luac -p modules/damage_meter/damage_meter.lua \
    modules/damage_meter/settings/damage_meter_content.lua \
    core/defaults.lua
luacheck modules/damage_meter/damage_meter.lua \
    tests/unit/damage_meter_session_history_test.lua \
    tests/unit/damage_meter_reset_data_test.lua
```

Expected: `luac` exits 0. `luacheck` exits 0 or reports only pre-existing warnings outside the touched lines; if it reports touched-line warnings, fix them before continuing.

- [ ] **Step 4: Inspect final diff**

Run:

```bash
git diff --stat HEAD
git diff -- modules/damage_meter/damage_meter.lua tests/unit/damage_meter_session_history_test.lua tests/unit/damage_meter_reset_data_test.lua docs/features/damage-meter.md
```

Expected: diff contains only the session-history implementation, tests, and docs.

- [ ] **Step 5: Commit final fixes if validation required edits**

If Step 3 or Step 4 required edits, commit them:

```bash
git add modules/damage_meter/damage_meter.lua tests/unit/damage_meter_session_history_test.lua tests/unit/damage_meter_reset_data_test.lua docs/features/damage-meter.md
git commit -m "Validate damage meter session history"
```

If no edits were needed, do not create an empty commit.
