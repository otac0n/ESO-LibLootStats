LibLootStats.variableVersion = 1

local defaultCollectionVars = {
}

function LibLootStats:InitializeSettings()
  LibLootStats.collectionVars = LibSavedVars
    :NewAccountWide(LibLootStats.ADDON_NAME.."_Settings", "Collection_Account", defaultCollectionVars)
    :AddCharacterSettingsToggle(LibLootStats.ADDON_NAME.."_Settings", "Collection_Character")
    :EnableDefaultsTrimming()
end
