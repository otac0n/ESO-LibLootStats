EVENT_MANAGER:RegisterForEvent(LibLootStats.ADDON_NAME, EVENT_ADD_ON_LOADED, function (eventCode, name)
  if name ~= LibLootStats.ADDON_NAME then return end
  LibLootStats:Initialize()
  EVENT_MANAGER:UnregisterForEvent(LibLootStats.ADDON_NAME, EVENT_ADD_ON_LOADED)
end)

local logger
function LibLootStats:Initialize()
  logger = LibDebugLogger(LibLootStats.ADDON_NAME)
  logger:SetMinLevelOverride(LibDebugLogger.LOG_LEVEL_VERBOSE)
  LibLootStats:InitializeSettings()
  LibLootStats:InitializeHooks()
  LibLootStats.settingsMenu = LibLootStatsSettingsMenu:New()

  LibLootStats:OnInventoryFullUpdate()
end

function LibLootStats:InitializeHooks()
  local namespace = LibLootStats.ADDON_NAME
  function Closure(fn)
    return function(...) return fn(self, ...) end
  end

  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_INVENTORY_ITEM_DESTROYED, self.OnInventoryItemDestroyed)
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_INVENTORY_ITEM_USED, self.OnInventoryItemUsed)
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_INVENTORY_FULL_UPDATE, self.OnInventoryFullUpdate)
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_INVENTORY_SINGLE_SLOT_UPDATE, self.OnInventorySingleSlotUpdate)
  ZO_PreHook("ZO_MailInboxShared_TakeAll", Closure(self.OnMailTakeAll))
  ZO_PreHook("ClaimCurrentDailyLoginReward", Closure(self.OnClaimCurrentDailyLoginReward))
  ZO_PreHook(SCENE_MANAGER, "OnSceneStateChange", self.OnSceneStateChanged)
  ZO_PreHookHandler(RETICLE.interact, "OnEffectivelyShown", self.OnReticleEffectivelyShown)
  ZO_PreHookHandler(RETICLE.interact, "OnHide", self.OnReticleHide)
  ZO_PreHook(SYSTEMS:GetObject("loot"), "UpdateLootWindow", self.OnUpdateLootWindow)
  ZO_PreHook(ZO_InteractionManager, "SelectChatterOptionByIndex", self.OnSelectChatterOptionByIndex)
  for i = 1, ZO_InteractWindowPlayerAreaOptions:GetNumChildren() do
    local option = ZO_InteractWindowPlayerAreaOptions:GetChild(i)
    ZO_PreHookHandler(option, "OnMouseUp", function (...) LibLootStats:OnChatterOptionMouseUp(option, ...) end)
  end
end

local reticleActive = false
local lastInteraction, lastInteractable, lastInteractInfo, lastFishingLure, lastSocialClass
function LibLootStats:OnReticleEffectivelyShown()
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

function LibLootStats:OnReticleHide()
  reticleActive = false
end

local currentScene, inHud
function LibLootStats:OnSceneStateChanged()
  local scene = SCENE_MANAGER:GetCurrentScene()
  if currentScene ~= scene.name then
    if currentScene == LOOT_SCENE.name then
      nextRemovalIsUse = false
      LibLootStats:CollectOutcomeGroup()
    end

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

function LibLootStats:OnChatterOptionMouseUp(option)
  lastInteraction = option:GetText()
end

function LibLootStats:OnSelectChatterOptionByIndex(index)
  lastInteraction = ZO_InteractWindowPlayerAreaOptions:GetChild(index):GetText()
end

function LibLootStats:OnMailTakeAll(mailId)
  local senderDisplayName, senderCharacterName, subject, icon, unread, fromSystem, fromCS, returned, numAttachments, attachedMoney, codAmount, expiresInDays, secsSinceReceived = GetMailItemInfo(mailId)
  if fromSystem then
    lastInteraction = GetString(SI_MAIL_READ_ATTACHMENTS_TAKE)
    lastInteractable = subject
    lastInteractInfo, lastFishingLure, lastSocialClass = nil, nil, nil
  else
    lastInteraction, lastInteractable, lastInteractInfo, lastFishingLure, lastSocialClass = nil, nil, nil, nil, nil
  end
end

function LibLootStats:OnClaimCurrentDailyLoginReward()
  local index = GetDailyLoginClaimableRewardIndex()
  if index == nil then
    return
  end
  lastInteractable = ZO_Daily_Login_Rewards_KeyboardCurrentMonth:GetText()
  lastInteraction = GetString(SI_DAILY_LOGIN_REWARDS_CLAIM_KEYBIND)
  lastInteractInfo, lastFishingLure, lastSocialClass = nil, nil, nil
end

function LibLootStats:GetContext()
  local context = {}
  if not nextRemovalIsUse then
    local interactable, interaction = lastInteractable, lastInteraction
  
    if lastInteractInfo == ADDITIONAL_INTERACT_INFO_FISHING_NODE then
      context.fishingLure = lastFishingLure
    end
  
    if lastInteractInfo == ADDITIONAL_INTERACT_INFO_PICKPOCKET_CHANCE then
      interactable = lastSocialClass
    end

    context.zoneId = GetZoneId(GetUnitZoneIndex("player"))

    return interactable, interaction, context
  else
    return nil, nil, context
  end
end

local inventorySnapshot = {}
for i = BAG_ITERATION_BEGIN, BAG_ITERATION_END do
  inventorySnapshot[i] = {}
end

function LibLootStats:OnInventoryFullUpdate(bagId, slotId, isNewItem, soundCategory, reason)
  for i = BAG_ITERATION_BEGIN, BAG_ITERATION_END do
    for slotId = 1, GetBagSize(i) do
      inventorySnapshot[i][slotId] = GetItemLink(i, slotId)
    end
  end
end

local nextRemovalIsUse
function LibLootStats:OnInventorySingleSlotUpdate(bagId, slotId, isNewItem, itemSoundCategory, updateReason, stackCountChange)
  if isNewItem then
    local source, action, context = LibLootStats:GetContext()
    local itemLink = GetItemLink(bagId, slotId)
    inventorySnapshot[bagId][slotId] = itemLink
    LibLootStats:AddOutcome(source, action, context, itemLink, stackCountChange)
  else
    if stackCountChange < 0 then
      local itemLink = inventorySnapshot[bagId][slotId]
      if nextRemovalIsUse then
        if bagId == BAG_BACKPACK and stackCountChange == -1 then
          LibLootStats:UpdatePendingOutcomeGroup(itemLink, GetString(SI_ITEM_ACTION_USE))
          LibLootStats:CollectOutcomeGroup()
        else
          logger:Warn("Not tracking", GetString(SI_ITEM_ACTION_USE), itemLink, " with the change count ", stackCountChange)
        end
        nextRemovalIsUse = false
      end
    end
    inventorySnapshot[bagId][slotId] = GetItemLink(bagId, slotId)
  end
end

function LibLootStats:OnInventoryItemUsed(eventCode, itemSoundCategory)
  nextRemovalIsUse = true
end

function LibLootStats:OnInventoryItemDestroyed(eventCode, itemSoundCategory)
end

function LibLootStats:OnUpdateLootWindow(containerName, actionName, isOwned)
  LibLootStats:ExtendOutcomeGroupLifetime()
  local source, action, context = LibLootStats:GetContext()
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
    --LibLootStats:AddOutcome(source, action, context, name, count)
  end
end

local ignoredScenes = {
  [SMITHING_SCENE.name] = true,
  [PROVISIONER_SCENE.name] = true,
  [ENCHANTING_SCENE.name] = true,
  [ALCHEMY_SCENE.name] = true,
}

LibLootStats.data = {}
local outcomeGroup, extendLifetime = nil, false
function LibLootStats:InitializeOutcomeGroup(source, action)
  EVENT_MANAGER:UnregisterForUpdate(LibLootStats.ADDON_NAME .. "CollectOutcomeGroup")

  if outcomeGroup and (outcomeGroup.source ~= source or outcomeGroup.action ~= action) then
    logger:Warn("Collecting existing outcome group (", outcomeGroup.source, ",", outcomeGroup.action, ") to create (", source, ",", action, ")")
    LibLootStats:CollectOutcomeGroup()
  end

  if not outcomeGroup then
    outcomeGroup = {
      source = source,
      action = action,
    }
  end

  if not extendLifetime then
    EVENT_MANAGER:RegisterForUpdate(LibLootStats.ADDON_NAME .. "CollectOutcomeGroup", 0, self.CollectOutcomeGroup)
  end
end

function LibLootStats:UpdatePendingOutcomeGroup(source, action)
  if outcomeGroup then
    if outcomeGroup.source == nil and outcomeGroup.action == nil then
      outcomeGroup.source = source
      outcomeGroup.action = action
    else
      logger:Warn("Not updating the source of a pending outcome group because the source was already know: (", source, ",", action, ") would overwrite (", outcomeGroup.source, ",", outcomeGroup.action, ")")
    end
  end
end

function LibLootStats:CollectOutcomeGroup()
  EVENT_MANAGER:UnregisterForUpdate(LibLootStats.ADDON_NAME .. "CollectOutcomeGroup")

  if outcomeGroup ~= nil then
    if outcomeGroup.source == nil then
      logger:Warn("Not saving outcome group with nil source.")
    elseif outcomeGroup.action == nil then
      logger:Warn("Not saving outcome group with nil action. Source was: ", outcomeGroup.source)
    else
      logger:Debug(outcomeGroup.source, "(", outcomeGroup.action, ")")
      LibLootStats:SaveOutcomeGroup(outcomeGroup)
      for i = 1, #outcomeGroup do
        local outcome = outcomeGroup[i]
        local item = outcome.item
        local count = outcome.count
        local result
        if count == 1 then
          result = item
        else
          result = string.format("%s (%d)", item, count)
        end

        logger:Debug("  ->", result)
      end
    end
  end

  outcomeGroup, extendLifetime = nil, false
end

function LibLootStats:ExtendOutcomeGroupLifetime()
  EVENT_MANAGER:UnregisterForUpdate(LibLootStats.ADDON_NAME .. "CollectOutcomeGroup")
  extendLifetime = true
end

function LibLootStats:AddOutcome(source, action, context, item, count)
  LibLootStats:InitializeOutcomeGroup(source, action)

  table.insert(outcomeGroup, {
    item = item,
    count = count,
    context = context,
  })
end

function LibLootStats:SaveOutcomeGroup(outcomeGroup)
  local source, action = outcomeGroup.source, outcomeGroup.action
  outcomeGroup.source, outcomeGroup.action = nil, nil

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
  table.insert(actionData, outcomeGroup)
end
