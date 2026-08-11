-- tests/unit/cdm_reanchor_editlock_test.lua
-- Run: lua tests/unit/cdm_reanchor_editlock_test.lua
-- Contract for CDMReanchorEditLock: locks Blizzard CooldownViewer systems out
-- of Blizzard Edit Mode without touching their EditMode selection state during
-- cold login. Once Blizzard_EditMode is loaded, native selections are hidden.

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_editlock.lua", "cdm_reanchor_editlock.lua")("QUI", ns)
local EL = assert(ns.CDMReanchorEditLock, "CDMReanchorEditLock exported")

-- Mock hooksecurefunc: record post-hooks; fire() runs original then post-hooks.
local hooks = {}
local function mockHooksec(obj, method, fn)
    hooks[obj] = hooks[obj] or {}
    hooks[obj][method] = hooks[obj][method] or {}
    table.insert(hooks[obj][method], fn)
end
local function fire(obj, method, ...)
    if obj[method] then obj[method](obj, ...) end
    local list = hooks[obj] and hooks[obj][method]
    if list then for _, fn in ipairs(list) do fn(obj, ...) end end
end

local function MakeSelection()
    local s = { alpha = 1, alphaCalls = 0, scripts = {} }
    function s:SetAlpha(a) self.alpha = a; self.alphaCalls = self.alphaCalls + 1 end
    function s:SetScript(scriptName, fn)
        if fn == nil then
            self.scripts[scriptName] = false
        else
            self.scripts[scriptName] = fn
        end
    end
    function s:Show() self.shown = true end   -- ShowHighlighted/ShowSelected analog
    return s
end

local function MakeViewer()
    local v = { movable = true, Selection = MakeSelection(), system = 20 }
    function v:SetMovable(m) self.movable = m end
    function v:SelectSystem() end
    function v:HighlightSystem() end
    function v:ClearHighlight() end
    return v
end

local function MakeDialog()
    local d = { hidden = false, attached = nil }
    function d:AttachToSystemFrame(sf) self.attached = sf end
    function d:Hide() self.hidden = true end
    return d
end

-- ===== No cold-login viewer mutation while EditMode dialog is unavailable
do
    local viewer = MakeViewer()
    local requested = 0
    local continued = {}
    local lock = EL.New({
        hooksecurefunc = mockHooksec,
        keys = { "essential" },
        getDialog = function() return nil end,
        continueOnAddOnLoaded = function(addonName, fn)
            continued[#continued + 1] = { addonName = addonName, fn = fn }
        end,
    })
    lock:Install(function()
        requested = requested + 1
        return viewer
    end)

    assert(requested == 0, "viewer lookup is deferred until Blizzard_EditMode/dialog exists")
    assert(viewer.movable == true, "viewer movable state is not touched during cold login")
    assert(viewer.Selection.alphaCalls == 0, "Selection alpha is not touched during cold login")
    assert(#continued == 1 and continued[1].addonName == "Blizzard_EditMode",
        "missing dialog queues one Blizzard_EditMode retry")
end

-- ===== No native viewer mutation while CooldownViewer data is unavailable
do
    local viewer = MakeViewer()
    local dialog = MakeDialog()
    local requested = 0
    local continued = 0
    local lock = EL.New({
        hooksecurefunc = mockHooksec,
        keys = { "trackedBar" },
        getDialog = function() return dialog end,
        isCooldownViewerReady = function() return false end,
        continueOnCooldownViewerDataLoaded = function(fn)
            continued = continued + 1
        end,
    })
    lock:Install(function()
        requested = requested + 1
        return viewer
    end)

    assert(requested == 0, "viewer lookup is deferred until CooldownViewer data is ready")
    assert(viewer.Selection.alphaCalls == 0, "Selection is not hidden before CooldownViewer data is ready")
    assert(continued == 1, "missing CooldownViewer data queues one data-loaded retry")
end

-- ===== Core: lock a viewer + hook a present dialog
do
    local viewer = MakeViewer()
    local dialog = MakeDialog()
    local notifies = 0
    local lock = EL.New({
        hooksecurefunc = mockHooksec,
        keys = { "essential" },
        getDialog = function() return dialog end,
        isCooldownViewerReady = function() return true end,
        notify = function() notifies = notifies + 1 end,
    })
    lock:Install(function() return viewer end)

    assert(lock:IsManaged(viewer), "viewer marked managed")
    assert(viewer.movable == false, "viewer forced non-movable at install")
    assert(viewer.Selection.alpha == 0, "Selection alpha is hidden after Blizzard_EditMode is available")
    assert(viewer.Selection.alphaCalls > 0, "Selection alpha is written only after the dialog exists")
    assert(viewer.Selection.scripts.OnDragStart == false and viewer.Selection.scripts.OnDragStop == false,
        "Selection drag scripts are disabled")

    -- Blizzard may try to show the selection again; the SetAlpha hook re-hides it.
    fire(viewer.Selection, "SetAlpha", 1)
    assert(viewer.Selection.alpha == 0, "Selection SetAlpha(1) is re-hidden")

    -- Selecting the system re-asserts non-movable AND closes the dialog.
    viewer.movable = true
    fire(viewer, "SelectSystem")
    assert(viewer.movable == false, "SelectSystem re-asserts non-movable")
    assert(dialog.hidden == true, "SelectSystem closes the settings dialog")

    -- Dialog attaching to a MANAGED viewer -> Hide + notify once.
    dialog.hidden = false
    fire(dialog, "AttachToSystemFrame", viewer)
    assert(dialog.hidden == true, "dialog attached to managed viewer is hidden")
    assert(notifies == 1, "notify fired once")

    -- Attaching again -> hidden again, but notify is one-shot.
    dialog.hidden = false
    fire(dialog, "AttachToSystemFrame", viewer)
    assert(dialog.hidden == true, "dialog re-hidden on second attach")
    assert(notifies == 1, "notify is one-shot")

    -- Dialog attaching to an UNMANAGED frame -> left alone.
    dialog.hidden = false
    fire(dialog, "AttachToSystemFrame", { foreign = true })
    assert(dialog.hidden == false, "unmanaged system frame: dialog NOT hidden")

    -- Idempotent: re-locking the same viewer is a no-op.
    assert(lock:LockViewer(viewer) == false, "LockViewer idempotent")
end

-- ===== Lazy dialog: retry after Blizzard_EditMode loads
do
    local viewer = MakeViewer()
    local dialog = MakeDialog()
    local available = false
    local retry
    local lock = EL.New({
        hooksecurefunc = mockHooksec,
        keys = { "essential" },
        getDialog = function() return available and dialog or nil end,
        isCooldownViewerReady = function() return true end,
        continueOnAddOnLoaded = function(_, fn) retry = fn end,
    })
    lock:Install(function() return viewer end)
    -- Dialog not present yet -> no viewer hook/mutation.
    viewer.movable = true
    fire(viewer, "SelectSystem")
    assert(viewer.movable == true, "missing dialog means no viewer mutation yet")
    assert(dialog.hidden == false, "missing dialog means no dialog close")
    assert(type(retry) == "function", "missing dialog queues a retry")

    -- Edit Mode loads the dialog; queued retry installs the lock.
    available = true
    retry()
    assert(viewer.Selection.alpha == 0, "retry hides Selection after Blizzard_EditMode loads")
    fire(viewer, "SelectSystem")
    assert(dialog.hidden == true, "lazily resolved dialog is closed on later select")
end

-- ===== Nil-safety
do
    local lock = EL.New({ hooksecurefunc = mockHooksec, keys = {} })
    lock:Install(nil)                 -- no getViewer, no dialog
    assert(lock:IsManaged(nil) == false, "nil is never managed")
    assert(lock:LockViewer(nil) == false, "LockViewer(nil) is a safe no-op")
end

-- ===== Default managed key set includes trackedBar for Edit Mode suppression
do
    local viewers = {
        essential = MakeViewer(),
        utility = MakeViewer(),
        buff = MakeViewer(),
        trackedBar = MakeViewer(),
    }
    local dialog = MakeDialog()
    local requested = {}
    local lock = EL.New({
        hooksecurefunc = mockHooksec,
        getDialog = function() return dialog end,
        isCooldownViewerReady = function() return true end,
    })
    lock:Install(function(key)
        requested[#requested + 1] = key
        return viewers[key]
    end)

    assert(lock:IsManaged(viewers.essential), "default keys include essential")
    assert(lock:IsManaged(viewers.utility), "default keys include utility")
    assert(lock:IsManaged(viewers.buff), "default keys include buff")
    assert(lock:IsManaged(viewers.trackedBar),
        "default keys include trackedBar because Blizzard Edit Mode must not expose the native tracked-bar system")
    assert(#requested == 4, "default install requests the four Edit Mode suppressed CDM surfaces")
end

-- ===== trackedBar: native Blizzard bar is suppressed when edit-lock installs
do
    local viewer = MakeViewer()
    local dialog = MakeDialog()
    local suppressedViewer, suppressedKey
    local lock = EL.New({
        hooksecurefunc = mockHooksec,
        keys = { "trackedBar" },
        getDialog = function() return dialog end,
        isCooldownViewerReady = function() return true end,
        suppressNativeTrackedBar = function(v, key)
            suppressedViewer = v
            suppressedKey = key
        end,
    })

    lock:Install(function() return viewer end)
    assert(suppressedViewer == viewer and suppressedKey == "trackedBar",
        "trackedBar edit-lock suppresses the native Blizzard buff bar")
end

print("OK: cdm_reanchor_editlock_test")
