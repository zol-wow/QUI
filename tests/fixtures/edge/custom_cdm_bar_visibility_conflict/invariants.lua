return {
  {
    name = "customBar visibility flags are mutually exclusive",
    assert = function(sv)
      local c = sv.QUI_DB.profiles.Default.ncdm.containers.customBar_conflict
      return c.showOnlyOnCooldown == true
        and c.showOnlyWhenActive == false
        and c.showOnlyWhenOffCooldown == false
        and c.visibilityMode == "onCooldown"
    end,
  },
  {
    name = "dynamic layout wins over clickable secure icons",
    assert = function(sv)
      local c = sv.QUI_DB.profiles.Default.ncdm.containers.customBar_conflict
      return c.dynamicLayout == true and c.clickableIcons == false
    end,
  },
  {
    name = "legacy custom tracker contexts are stamped",
    assert = function(sv)
      local c = sv.QUI_DB.profiles.Default.ncdm.containers.customBar_conflict
      return c.tooltipContext == "customTrackers"
        and c.keybindContext == "customTrackers"
    end,
  },
}
