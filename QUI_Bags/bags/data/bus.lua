-- Forwarding shim: bus.lua moved to core/storage/bus.lua.
-- In-game: storage_compat.lua (earlier in the toc) already aliased
-- ns.Bags.Bus, so this file is a no-op in production.
-- In stock-Lua tests that loadfile this path directly: delegates to the
-- canonical location and re-aliases ns.Bags.Bus for the caller.
local ADDON_NAME, ns = ...
if ns and ns.Bags and ns.Bags.Bus then return end   -- already aliased (in-game path)
-- stock-Lua test path: loadfile is available, forward to the canonical file
local loader = loadfile and loadfile("core/storage/bus.lua")
if loader then
    loader(ADDON_NAME, ns)
    local Bags = ns.Bags or {}; ns.Bags = Bags
    if ns.Storage and ns.Storage.Bus then
        Bags.Bus = ns.Storage.Bus
    end
end
