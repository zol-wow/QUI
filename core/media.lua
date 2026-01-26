-- QUI Media Registration
-- This file handles the registration of fonts and textures with LibSharedMedia

local LSM = LibStub("LibSharedMedia-3.0")

-- Media types from LibSharedMedia
local MediaType = LSM.MediaType
local FONT = MediaType.FONT
local STATUSBAR = MediaType.STATUSBAR
local BACKGROUND = MediaType.BACKGROUND
local BORDER = MediaType.BORDER

-- Register media synchronously (LSM:Register is lightweight - just table entries)
-- Register the Quazii font (used as the main UI font)
local quaziiFontPath = "Interface\\AddOns\\QUI\\assets\\Quazii.ttf"
LSM:Register(FONT, "Quazii", quaziiFontPath)

-- Register Poppins fonts
LSM:Register(FONT, "Poppins Black", "Interface\\AddOns\\QUI\\assets\\Poppins-Black.ttf")
LSM:Register(FONT, "Poppins Bold", "Interface\\AddOns\\QUI\\assets\\Poppins-Bold.ttf")
LSM:Register(FONT, "Poppins Medium", "Interface\\AddOns\\QUI\\assets\\Poppins-Medium.ttf")
LSM:Register(FONT, "Poppins SemiBold", "Interface\\AddOns\\QUI\\assets\\Poppins-SemiBold.ttf")

-- Register Expressway font
LSM:Register(FONT, "Expressway", "Interface\\AddOns\\QUI\\assets\\Expressway.TTF")

-- Register the Quazii Logo texture
local logoTexturePath = "Interface\\AddOns\\QUI\\assets\\QUI.tga"
LSM:Register(BACKGROUND, "QUI_logo", logoTexturePath)

-- Register the Quazii texture
local quaziiTexturePath = "Interface\\AddOns\\QUI\\assets\\Quazii.tga"
LSM:Register(BACKGROUND, "Quazii", quaziiTexturePath)
LSM:Register(STATUSBAR, "Quazii", quaziiTexturePath)
LSM:Register(BORDER, "Quazii", quaziiTexturePath)

-- Register the Quazii Reverse texture
local quaziiReverseTexturePath = "Interface\\AddOns\\QUI\\assets\\Quazii_reverse.tga"
LSM:Register(BACKGROUND, "Quazii Reverse", quaziiReverseTexturePath)
LSM:Register(STATUSBAR, "Quazii Reverse", quaziiReverseTexturePath)
LSM:Register(BORDER, "Quazii Reverse", quaziiReverseTexturePath)

-- Register Square texture
local squareTexturePath = "Interface\\AddOns\\QUI\\assets\\Square.tga"
LSM:Register(BACKGROUND, "Square", squareTexturePath)
LSM:Register(STATUSBAR, "Square", squareTexturePath)
LSM:Register(BORDER, "Square", squareTexturePath)

-- Register Quazii v2 texture
local quaziiV2TexturePath = "Interface\\AddOns\\QUI\\assets\\Quazii_v2.tga"
LSM:Register(BACKGROUND, "Quazii v2", quaziiV2TexturePath)
LSM:Register(STATUSBAR, "Quazii v2", quaziiV2TexturePath)
LSM:Register(BORDER, "Quazii v2", quaziiV2TexturePath)

-- Register Quazii v2 Reverse texture
local quaziiV2ReverseTexturePath = "Interface\\AddOns\\QUI\\assets\\Quazii_v2reverse.tga"
LSM:Register(BACKGROUND, "Quazii v2 Reverse", quaziiV2ReverseTexturePath)
LSM:Register(STATUSBAR, "Quazii v2 Reverse", quaziiV2ReverseTexturePath)
LSM:Register(BORDER, "Quazii v2 Reverse", quaziiV2ReverseTexturePath)

-- Register Quazii v3 texture
local quaziiV3TexturePath = "Interface\\AddOns\\QUI\\assets\\Quazii_v3.tga"
LSM:Register(BACKGROUND, "Quazii v3", quaziiV3TexturePath)
LSM:Register(STATUSBAR, "Quazii v3", quaziiV3TexturePath)
LSM:Register(BORDER, "Quazii v3", quaziiV3TexturePath)

-- Register Quazii v3 Inverse texture
local quaziiV3InverseTexturePath = "Interface\\AddOns\\QUI\\assets\\Quazii_v3inverse.tga"
LSM:Register(BACKGROUND, "Quazii v3 Inverse", quaziiV3InverseTexturePath)
LSM:Register(STATUSBAR, "Quazii v3 Inverse", quaziiV3InverseTexturePath)
LSM:Register(BORDER, "Quazii v3 Inverse", quaziiV3InverseTexturePath)

-- Register Quazii v4 texture
local quaziiV4TexturePath = "Interface\\AddOns\\QUI\\assets\\Quazii_v4.tga"
LSM:Register(BACKGROUND, "Quazii v4", quaziiV4TexturePath)
LSM:Register(STATUSBAR, "Quazii v4", quaziiV4TexturePath)
LSM:Register(BORDER, "Quazii v4", quaziiV4TexturePath)

-- Register Quazii v4 Inverse texture
local quaziiV4InverseTexturePath = "Interface\\AddOns\\QUI\\assets\\Quazii_v4inverse.tga"
LSM:Register(BACKGROUND, "Quazii v4 Inverse", quaziiV4InverseTexturePath)
LSM:Register(STATUSBAR, "Quazii v4 Inverse", quaziiV4InverseTexturePath)
LSM:Register(BORDER, "Quazii v4 Inverse", quaziiV4InverseTexturePath)

-- Register Quazii v5 texture
local quaziiV5TexturePath = "Interface\\AddOns\\QUI\\assets\\Quazii_v5.tga"
LSM:Register(BACKGROUND, "Quazii v5", quaziiV5TexturePath)
LSM:Register(STATUSBAR, "Quazii v5", quaziiV5TexturePath)
LSM:Register(BORDER, "Quazii v5", quaziiV5TexturePath)

-- Register Quazii v5 Inverse texture
local quaziiV5InverseTexturePath = "Interface\\AddOns\\QUI\\assets\\Quazii_v5_inverse.tga"
LSM:Register(BACKGROUND, "Quazii v5 Inverse", quaziiV5InverseTexturePath)
LSM:Register(STATUSBAR, "Quazii v5 Inverse", quaziiV5InverseTexturePath)
LSM:Register(BORDER, "Quazii v5 Inverse", quaziiV5InverseTexturePath)

-- Register Quazii v6 texture
local quaziiV6TexturePath = "Interface\\AddOns\\QUI\\assets\\Quazii_v6.tga"
LSM:Register(BACKGROUND, "Quazii v6", quaziiV6TexturePath)
LSM:Register(STATUSBAR, "Quazii v6", quaziiV6TexturePath)
LSM:Register(BORDER, "Quazii v6", quaziiV6TexturePath)

-- Register Quazii v6 Inverse texture
local quaziiV6InverseTexturePath = "Interface\\AddOns\\QUI\\assets\\Quazii_v6inverse.tga"
LSM:Register(BACKGROUND, "Quazii v6 Inverse", quaziiV6InverseTexturePath)
LSM:Register(STATUSBAR, "Quazii v6 Inverse", quaziiV6InverseTexturePath)
LSM:Register(BORDER, "Quazii v6 Inverse", quaziiV6InverseTexturePath)

-- Register QUI Stripes texture (for absorb shield overlays)
local absorbStripeTexturePath = "Interface\\AddOns\\QUI\\assets\\absorb_stripe"
LSM:Register(STATUSBAR, "QUI Stripes", absorbStripeTexturePath)

-- Function to check if our media is registered
function QUI:CheckMediaRegistration()
    local quaziiFontRegistered = LSM:IsValid(FONT, "Quazii")
    local logoTextureRegistered = LSM:IsValid(BACKGROUND, "QUI_logo")
    local quaziiTextureRegistered = LSM:IsValid(BACKGROUND, "Quazii")
    local quaziiReverseTextureRegistered = LSM:IsValid(BACKGROUND, "Quazii Reverse")
    
    -- Silent check - only print if there's a failure
    if not (quaziiFontRegistered and logoTextureRegistered and quaziiTextureRegistered and quaziiReverseTextureRegistered) then
        QUI:Print("Media registration failed:")
        if not quaziiFontRegistered then QUI:Print("- Quazii font not registered") end
        if not logoTextureRegistered then QUI:Print("- QUI_logo texture not registered") end
        if not quaziiTextureRegistered then QUI:Print("- Quazii texture not registered") end
        if not quaziiReverseTextureRegistered then QUI:Print("- Quazii Reverse texture not registered") end
    end
end

-- Register any additional fonts or textures here
-- Example:
-- LSM:Register(FONT, "MyCustomFont", "Interface\\AddOns\\QUI\\assets\\mycustomfont.ttf")
-- LSM:Register(STATUSBAR, "MyCustomTexture", "Interface\\AddOns\\QUI\\assets\\mycustomtexture.tga") 
