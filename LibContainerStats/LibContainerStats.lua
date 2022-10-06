EVENT_MANAGER:RegisterForEvent(LibContainerStats.ADDON_NAME, EVENT_ADD_ON_LOADED, function (eventCode, name)
  if name ~= LibContainerStats.ADDON_NAME then return end
  LibContainerStats:Initialize()
  EVENT_MANAGER:UnregisterForEvent(LibContainerStats.ADDON_NAME, EVENT_ADD_ON_LOADED)
end)

local logger
function LibContainerStats:Initialize()
  logger = LibDebugLogger(LibContainerStats.ADDON_NAME)
  logger:SetMinLevelOverride(LibDebugLogger.LOG_LEVEL_VERBOSE)
  LibContainerStats:InitializeSettings()
  LibContainerStats:InitializeHooks()
  LibContainerStats.settingsMenu = LibContainerStatsSettingsMenu:New()
end

function LibContainerStats:InitializeHooks()
  local namespace = LibContainerStats.ADDON_NAME
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_INVENTORY_ITEM_DESTROYED, self.OnInventoryItemDestroyed)
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_INVENTORY_ITEM_USED, self.OnInventoryItemUsed)
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_INVENTORY_FULL_UPDATE, self.OnInventoryFullUpdate)
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_INVENTORY_SINGLE_SLOT_UPDATE, self.OnInventorySingleSlotUpdate)
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_MAIL_OPEN_MAILBOX , self.OnMailOpenMailbox)
  ZO_PreHook(SCENE_MANAGER, "OnSceneStateChange", self.OnSceneStateChanged)
  ZO_PreHookHandler(RETICLE.interact, "OnEffectivelyShown", self.OnReticleEffectivelyShown)
  ZO_PreHookHandler(RETICLE.interact, "OnHide", self.OnReticleHide)
  ZO_PreHook(SYSTEMS:GetObject("loot"), "UpdateLootWindow", self.OnUpdateLootWindow)
  ZO_PreHook(ZO_InteractionManager, "SelectChatterOptionByIndex", self.OnSelectChatterOptionByIndex)
  for i = 1, ZO_InteractWindowPlayerAreaOptions:GetNumChildren() do
    local option = ZO_InteractWindowPlayerAreaOptions:GetChild(i)
    ZO_PreHookHandler(option, "OnMouseUp", function (...) LibContainerStats:OnChatterOptionMouseUp(option, ...) end)
  end
end

local reticleActive = false
local lastInteraction, lastInteractable, lastInteractInfo, lastFishingLure, lastSocialClass
function LibContainerStats:OnReticleEffectivelyShown()
  reticleActive = true
  local interaction, interactableName, interactionBlocked, isOwned, additionalInteractInfo, context, contextLink, isCriminalInteract = GetGameCameraInteractableActionInfo()

  if lastInteractInfo == ADDITIONAL_INTERACT_INFO_FISHING_NODE and lastInteractable == interactableName then
    -- Keep the lastInteractInfo set to ADDITIONAL_INTERACT_INFO_FISHING_NODE and leave the lure set
    lastInteraction = interaction
  elseif not interactionBlocked then
    lastInteraction, lastInteractable, lastInteractInfo = interaction, interactableName, additionalInteractInfo

    if additionalInteractInfo == ADDITIONAL_INTERACT_INFO_FISHING_NODE then
      lastFishingLure = GetFishingLure()
    else
      lastFishingLure = nil
    end

    if additionalInteractInfo == ADDITIONAL_INTERACT_INFO_PICKPOCKET_CHANCE then
      local isInBonus, isHostile, percentChance, difficulty, isEmpty, prospectiveResult, monsterSocialClassString, monsterSocialClass = GetGameCameraPickpocketingBonusInfo()
      lastSocialClass = monsterSocialClassString
    else
      lastSocialClass = nil
    end

  elseif lastInteraction ~= interaction or lastInteractable ~= interactableName then
    lastInteraction, lastInteractable, lastInteractInfo, lastFishingLure, lastSocialClass = nil, nil, nil, nil, nil
  end
end

function LibContainerStats:OnReticleHide()
  reticleActive = false
end

local currentScene, inHud
function LibContainerStats:OnSceneStateChanged()
  local scene = SCENE_MANAGER:GetCurrentScene()
  if currentScene ~= scene.name then
    currentScene = scene.name
    logger:Verbose("Scene changed to: %s", currentScene)

    inHud = currentScene == SCENE_MANAGER.hudSceneName or currentScene == SCENE_MANAGER.hudUISceneName
    if not inHud then
      lastFishingLure = nil
      if currentScene == ZO_INTERACTION_SYSTEM_NAME then
      else
        lastInteraction, lastInteractable, lastInteractInfo, lastFishingLure, lastSocialClass = nil, nil, nil, nil, nil
      end
    end
  end
end

function LibContainerStats:OnChatterOptionMouseUp(option)
  lastInteraction = option:GetText()
end

function LibContainerStats:OnSelectChatterOptionByIndex(index)
  lastInteraction = ZO_InteractWindowPlayerAreaOptions:GetChild(index):GetText()
end

function LibContainerStats:GetContext()
  local context = {}
  local interactable = lastInteractable

  if lastInteractInfo == ADDITIONAL_INTERACT_INFO_FISHING_NODE then
    context.fishingLure = lastFishingLure
  end

  if lastInteractInfo == ADDITIONAL_INTERACT_INFO_PICKPOCKET_CHANCE then
    interactable = lastSocialClass
  end

  context.zoneId = GetZoneId(GetUnitZoneIndex("player"))

  return interactable, lastInteraction, context
end

function LibContainerStats:OnMailOpenMailbox(eventCode)
end

local inventorySnapshot = {}
for i = BAG_ITERATION_BEGIN, BAG_ITERATION_END do
  inventorySnapshot[i] = {}
end

function LibContainerStats:OnInventoryFullUpdate(bagId, slotId, isNewItem, soundCategory, reason)
  for i = BAG_ITERATION_BEGIN, BAG_ITERATION_END do
    for slotId = 1, GetBagSize(i) do
      inventorySnapshot[i][slotId] = GetItemLink(i, slotId)
    end
  end
end

local nextRemovalIsUse
function LibContainerStats:OnInventorySingleSlotUpdate(bagId, slotId, isNewItem, itemSoundCategory, updateReason, stackCountChange)
  if isNewItem then
    local source, action, context = LibContainerStats:GetContext()
    local itemLink = GetItemLink(bagId, slotId)
    inventorySnapshot[bagId][slotId] = itemLink
    LibContainerStats:AddOutcome(source, action, context, itemLink, stackCountChange)
  else
    if stackCountChange < 0 then
      local itemLink = inventorySnapshot[bagId][slotId]
      if bagId == BAG_BACKPACK and stackCountChange == -1 and nextRemovalIsUse then
        logger:Debug("Used item was %s", itemLink)
        nextRemovalIsUse = false
      end
    end
    inventorySnapshot[bagId][slotId] = GetItemLink(bagId, slotId)
  end
end

function LibContainerStats:OnInventoryItemUsed(eventCode, itemSoundCategory)
  nextRemovalIsUse = true
end

function LibContainerStats:OnInventoryItemDestroyed(eventCode, itemSoundCategory)
end

function LibContainerStats:OnUpdateLootWindow(containerName, actionName, isOwned)
  local source, action, context
  if inHud then
    source, action, context = LibContainerStats:GetContext()
  else
    source = containerName
  end

  local numLootItems = GetNumLootItems()
  for i = 1, numLootItems do
    local lootId, name, icon, count, displayQuality, value, isQuest, isStolen, lootType = GetLootItemInfo(i)
    local itemInfo = {
      lootId = lootId,
      name = name,
      icon = icon,
      count = count,
      displayQuality = displayQuality,
      value = value,
      isQuest = isQuest,
      isStolen = isStolen,
      lootType = lootType,
    }
    LibContainerStats:AddOutcome(source, action, context, name, count)
  end
end

local ignoredScenes = {
  [SMITHING_SCENE.name] = true,
  [PROVISIONER_SCENE.name] = true,
  [ENCHANTING_SCENE.name] = true,
  [ALCHEMY_SCENE.name] = true,
}

LibContainerStats.data = {}
function LibContainerStats:AddOutcome(source, action, context, item, count)
  local result
  if count == 1 then
    result = item
  else
    result = string.format("%s (%d)", item, count)
  end

  if source == nil or action == nil or nextRemovalIsUse then
    if nextRemovalIsUse then
      logger:Debug(string.format("Used item -> %s", result))
    elseif not ignoredScenes[currentScene] then
      logger:Debug(string.format("No source -> %s", result))
    end
    return
  end

  logger:Debug(string.format("%s (%s) -> %s", source, action, result))
  sourceData = self.data[source]
  if sourceData == nil then
    sourceData = {}
    self.data[source] = sourceData
  end
  actionData = sourceData[action]
  if actionData == nil then
    actionData = {}
    sourceData[action] = actionData
  end
  itemData = actionData[item]
  if itemData == nil then
    itemData = {}
    actionData[item] = itemData
  end
  table.insert(itemData, { count = count, context = context })
end
