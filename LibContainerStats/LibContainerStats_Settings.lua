LibContainerStats.variableVersion = 1

local defaultCollectionVars = {
}

function LibContainerStats:InitializeSettings()
  LibContainerStats.collectionVars = LibSavedVars
    :NewAccountWide(LibContainerStats.ADDON_NAME.."_Settings", "Collection_Account", defaultCollectionVars)
    :AddCharacterSettingsToggle(LibContainerStats.ADDON_NAME.."_Settings", "Collection_Character")
    :EnableDefaultsTrimming()
end
