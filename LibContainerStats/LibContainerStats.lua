EVENT_MANAGER:RegisterForEvent(LibContainerStats.ADDON_NAME, EVENT_ADD_ON_LOADED, function (eventCode, name)
  if name ~= LibContainerStats.ADDON_NAME then return end
  LibContainerStats:Initialize()
  EVENT_MANAGER:UnregisterForEvent(LibContainerStats.ADDON_NAME, EVENT_ADD_ON_LOADED)
end)

function LibContainerStats:Initialize()
  LibContainerStats:InitializeSettings()
  LibContainerStats:InitializeHooks()
  LibContainerStats.settingsMenu = LibContainerStatsSettingsMenu:New()
end

function LibContainerStats:InitializeHooks()
end
