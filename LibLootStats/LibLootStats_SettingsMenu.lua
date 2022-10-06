LibLootStatsSettingsMenu = ZO_Object:Subclass()

function LibLootStatsSettingsMenu:New()
  local obj = ZO_Object.New(self)
  obj:Initialize()
  return obj
end

function LibLootStatsSettingsMenu:Initialize()
  self:CreateOptionsMenu()
end

local str = LibLootStats:GetStrings()

function LibLootStatsSettingsMenu:CreateOptionsMenu()
  local collectionVars = LibLootStats.collectionVars

  local panel = {
    type            = "panel",
    name            = LibLootStats.ADDON_TITLE,
    author          = LibLootStats.AUTHOR,
    version         = LibLootStats.VERSION,
    website         = LibLootStats.WEBSITE,
    donation        = LibLootStats.DONATION,
    feedback        = LibLootStats.FEEDBACK,
    slashCommand    = nil,
    registerForRefresh = true
  }

  local optionsData = {}

  table.insert(optionsData, {
    type = "header",
    name = str.COLLECTION_SETTINGS,
  })

  self.settingsMenuPanel = LibAddonMenu2:RegisterAddonPanel(LibLootStats.ADDON_NAME.."SettingsMenuPanel", panel)
  LibAddonMenu2:RegisterOptionControls(LibLootStats.ADDON_NAME.."SettingsMenuPanel", optionsData)
end
