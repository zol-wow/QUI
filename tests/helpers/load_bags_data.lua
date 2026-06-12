-- Compatibility shim: the bags data layer moved to core/storage (ns.Storage).
-- Existing bags tests load through here and read ns.Bags.*; alias after load.
local StorageLoader = dofile("tests/helpers/load_storage_data.lua")
local M = {}
M.DATA_FILES = StorageLoader.DATA_FILES
M.InstallBaseStubs = StorageLoader.InstallBaseStubs

function M.LoadAll(ns, upto)
    ns = StorageLoader.LoadAll(ns, upto)
    local S = ns.Storage or {}
    ns.Bags = ns.Bags or {}
    for _, name in ipairs({
        "Bus", "Store", "Summaries", "ItemInfo", "ScanCommon",
        "ScanBags", "ScanBank", "ScanGuild", "ScanMail",
        "ScanEquipped", "ScanCurrencies", "ScanAuctions",
    }) do
        if S[name] ~= nil then ns.Bags[name] = S[name] end
    end
    -- RequestDrain is owned by the core collection driver
    -- (core/storage/collector.lua), which is NOT loaded in these headless
    -- tests — so Storage.RequestDrain has no real owner here. Tests drive the
    -- drainer by assigning ns.Bags.RequestDrain. scan_common closures capture
    -- the Storage TABLE and look up .RequestDrain at call time, so install a
    -- live proxy that forwards to the test-assigned ns.Bags.RequestDrain.
    S.RequestDrain = function(...) return ns.Bags.RequestDrain and ns.Bags.RequestDrain(...) end
    return ns
end

return M
