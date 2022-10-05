LibContainerStatsSettingsMenu = ZO_Object:Subclass()

function LibContainerStatsSettingsMenu:New()
  local obj = ZO_Object.New(self)
  obj:Initialize()
  return obj
end

function LibContainerStatsSettingsMenu:Initialize()
  self:CreateOptionsMenu()
end

local str = LibContainerStats:GetStrings()

function LibContainerStatsSettingsMenu:CreateOptionsMenu()
  local collectionVars = LibContainerStats.collectionVars

  local panel = {
    type            = "panel",
    name            = LibContainerStats.ADDON_TITLE,
    author          = LibContainerStats.AUTHOR,
    version         = LibContainerStats.VERSION,
    website         = LibContainerStats.WEBSITE,
    donation        = LibContainerStats.DONATION,
    feedback        = LibContainerStats.FEEDBACK,
    slashCommand    = nil,
    registerForRefresh = true
  }

  local optionsData = {}

  table.insert(optionsData, {
    type = "header",
    name = str.COLLECTION_SETTINGS,
  })

  self.settingsMenuPanel = LibAddonMenu2:RegisterAddonPanel(LibContainerStats.ADDON_NAME.."SettingsMenuPanel", panel)
  LibAddonMenu2:RegisterOptionControls(LibContainerStats.ADDON_NAME.."SettingsMenuPanel", optionsData)
end
