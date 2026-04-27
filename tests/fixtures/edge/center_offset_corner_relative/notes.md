# center_offset_corner_relative

Pins the v24/v25 frameAnchoring corruption shape. After RepairDisabledAnchorsWithStaleCornerPoints, the anchor must be normalized to CENTER/CENTER preserving the offsets — NOT left as TOPRIGHT/TOPRIGHT with CENTER-style offsets, which teleports frames off-screen.

Reference: core/migrations.lua lines 50-68.
