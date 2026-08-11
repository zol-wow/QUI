-- The bags data layer lives in core/storage (ns.Storage); bags tests reach
-- it through the shared storage loader via this entry point. The old
-- ns.Bags.* aliases are gone (storage_compat.lua retired) — tests read
-- storage as ns.Storage.* and drive the drainer by assigning
-- ns.Storage.RequestDrain directly (scan closures capture the Storage TABLE
-- and look the function up at call time). Bags-internal exports
-- (ns.Bags.Junk, .Transfers, .BagWindow, ...) are created by their own
-- module files; the empty table here just keeps early readers index-safe.
local StorageLoader = dofile("tests/helpers/load_storage_data.lua")

local M = {}
M.DATA_FILES = StorageLoader.DATA_FILES
M.InstallBaseStubs = StorageLoader.InstallBaseStubs

function M.LoadAll(ns, upto)
    ns = StorageLoader.LoadAll(ns, upto)
    ns.Bags = ns.Bags or {}
    return ns
end

return M
