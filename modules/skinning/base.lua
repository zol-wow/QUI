-- The skinning engine now lives in core/uikit.lua (loaded first) and is exposed
-- as both ns.UIKit and ns.SkinBase. This stub keeps the load manifest unchanged.
local _, ns = ...
ns.SkinBase = ns.SkinBase or ns.UIKit
