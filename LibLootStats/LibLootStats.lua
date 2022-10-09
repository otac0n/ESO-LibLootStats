EVENT_MANAGER:RegisterForEvent(LibLootStats.ADDON_NAME, EVENT_ADD_ON_LOADED, function (eventCode, name)
  if name ~= LibLootStats.ADDON_NAME then return end
  LibLootStats:Initialize()
  EVENT_MANAGER:UnregisterForEvent(LibLootStats.ADDON_NAME, EVENT_ADD_ON_LOADED)
end)

local logger
function LibLootStats:Initialize()
  logger = LibDebugLogger(LibLootStats.ADDON_NAME)
  LibLootStats.logger = logger
  logger:SetMinLevelOverride(LibDebugLogger.LOG_LEVEL_VERBOSE)
  LibLootStats:InitializeSettings()
  LibLootStats:InitializeHooks()
  LibLootStats.settingsMenu = LibLootStatsSettingsMenu:New()

  LibLootStats:OnInventoryFullUpdate()
end

function LibLootStats:InitializeHooks()
  LibLootStats.reticleTracker:InitializeHooks()
  local namespace = LibLootStats.ADDON_NAME
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_INVENTORY_ITEM_DESTROYED, self.utils.Bind(self, self.OnInventoryItemDestroyed))
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_INVENTORY_ITEM_USED, self.utils.Bind(self, self.OnInventoryItemUsed))
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_INVENTORY_FULL_UPDATE, self.utils.Bind(self, self.OnInventoryFullUpdate))
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_INVENTORY_SINGLE_SLOT_UPDATE, self.utils.Bind(self, self.OnInventorySingleSlotUpdate))
  ZO_PreHook("ZO_MailInboxShared_TakeAll", self.utils.Bind(self, self.OnMailTakeAll))
  ZO_PreHook("ClaimCurrentDailyLoginReward", self.utils.Bind(self, self.OnClaimCurrentDailyLoginReward))
  ZO_PreHook(SCENE_MANAGER, "OnSceneStateChange", self.utils.Closure(self, self.OnSceneStateChanged))
  ZO_PreHookHandler(RETICLE.interact, "OnEffectivelyShown", self.utils.Closure(self, self.OnReticleEffectivelyShown))
  ZO_PreHookHandler(RETICLE.interact, "OnHide", self.utils.Closure(self, self.OnReticleHide))
  ZO_PreHook(SYSTEMS:GetObject("loot"), "UpdateLootWindow", self.utils.Closure(self, self.OnUpdateLootWindow))
  ZO_PreHook(ZO_InteractionManager, "SelectChatterOptionByIndex", self.utils.Closure(self, self.OnSelectChatterOptionByIndex))
  for i = 1, ZO_InteractWindowPlayerAreaOptions:GetNumChildren() do
    local option = ZO_InteractWindowPlayerAreaOptions:GetChild(i)
    ZO_PreHookHandler(option, "OnMouseUp", function(...) self:OnChatterOptionMouseUp(option, ...) end)
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
function LibLootStats:OnSceneStateChanged(scene, oldState, newState)
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

local function SkillPointLevel(skillPointId)
  for i = 1, 4 do
    if GetSlotBoundId(i, HOTBAR_CATEGORY_CHAMPION) == skillPointId then
      local spent = GetNumPointsSpentOnChampionSkill(skillPointId)
      if DoesChampionSkillHaveJumpPoints(skillPointId) then
        local points, level = {GetChampionSkillJumpPoints(skillPointId)}, 0
        for i, threshold in ipairs(points) do
          if threshold == spent then return level
          elseif threshold > spent then return level - 1
          end
          level = i
        end
        return nil
      else
        return spent
      end
    end
  end
end

function LibLootStats:GetContext()
  local context = {}
  if not nextRemovalIsUse then
    local interactable, interaction = lastInteractable, lastInteraction
  
    if lastInteractInfo == ADDITIONAL_INTERACT_INFO_FISHING_NODE then
      context.lure = lastFishingLure
      context.angler = SkillPointLevel(89)
    elseif lastInteractInfo == ADDITIONAL_INTERACT_INFO_PICKPOCKET_CHANCE then
      interactable = lastSocialClass
      context.cutpurse = SkillPointLevel(90)
    else
      context.harvest = SkillPointLevel(81)
      context.homemaker = SkillPointLevel(91)
      context.hunter = SkillPointLevel(79)
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

function LibLootStats:OnInventoryFullUpdate(eventId, bagId, slotId, isNewItem, soundCategory, reason)
  for i = BAG_ITERATION_BEGIN, BAG_ITERATION_END do
    for slotId = 1, GetBagSize(i) do
      inventorySnapshot[i][slotId] = GetItemLink(i, slotId)
    end
  end
end

local nextRemovalIsUse
function LibLootStats:OnInventorySingleSlotUpdate(eventId, bagId, slotId, isNewItem, soundCategory, reason, stackCountChange)
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
          logger:Warn("Not tracking", GetString(SI_ITEM_ACTION_USE), itemLink, "with the change count", stackCountChange)
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

local function ContextsAreEqual(a, b)
  local keys = {}
  for k, v in pairs(a) do
    if v ~= b[k] then return false end
    keys[k] = true
  end
  for k, v in pairs(b) do
    if not keys[k] or v == nil then return false end
  end
  return true
end
LibLootStats.ContextsAreEqual = ContextsAreEqual

local function ContextToKey(context)
  if context == nil then return nil end
  local key = ""
  local sorted = {}
  for k, v in pairs(context) do
    table.insert(sorted, { k = k, v = v })
  end
  table.sort(sorted, function(a, b) return a.k < b.k end)

  for _, kvp in ipairs(sorted) do
    local k, v = kvp.k, kvp.v
    if key == "" then
      key = k .. ":" .. tostring(v)
    else
      key = key .. "," .. k .. ":" .. tostring(v)
    end
  end
  return key
end
LibLootStats.ContextToKey = ContextToKey

local function ParseContextKey(key)
  local context = {}
  local e, l = 0, string.len(key)
  while e < l do
    local a, b, c = e, string.find(key, ":", e), string.find(key, ",", e + 1) or l + 1
    context[string.sub(key, a + 1, b - 1)] = tonumber(string.sub(key, b + 1, c - 1))
    e = c
  end
  return context
end
LibLootStats.ParseContextKey = ParseContextKey

local function OutcomeToKey(outcome)
  local key = ""
  for _, p in ipairs(outcome) do
    if key == "" then
      key = tostring(p.item) .. "*" .. tostring(p.count)
    else
      key = key .. "+" .. tostring(p.item) .. "*" .. tostring(p.count)
    end
  end
  return key
end
LibLootStats.OutcomeToKey = OutcomeToKey

local function ParseOutcomeKey(key)
  local outcome = {}
  local e, l = 0, string.len(key)
  while e < l do
    local a, b, c = e, string.find(key, "*", e), string.find(key, "+", e + 1) or l + 1
    table.insert(outcome, { item = tonumber(string.sub(key, a + 1, b - 1)), count = tonumber(string.sub(key, b + 1, c - 1)) })
    e = c
  end
  return outcome
end
LibLootStats.ParseOutcomeKey = ParseOutcomeKey

local function ScenarioToKey(scenario)
  return tostring(scenario.source) .. "/" .. tostring(scenario.action) .. "@" .. tostring(scenario.context) .. ">" .. tostring(scenario.outcome)
end
LibLootStats.ScenarioToKey = ScenarioToKey

local function ParseScenarioKey(key)
  local a, b, c = string.find(key, "/"), string.find(key, "@"), string.find(key, ">")
  return {
    source = tonumber(string.sub(key, 1, a - 1)),
    action = tonumber(string.sub(key, a + 1, b - 1)),
    context = tonumber(string.sub(key, b + 1, c - 1)),
    outcome = tonumber(string.sub(key, c + 1)),
  }
end
LibLootStats.ParseScenarioKey = ParseScenarioKey

local outcomeGroup, extendLifetime = nil, false
function LibLootStats:InitializeOutcomeGroup(source, action, context)
  EVENT_MANAGER:UnregisterForUpdate(LibLootStats.ADDON_NAME .. "CollectOutcomeGroup")

  if outcomeGroup and (outcomeGroup.source ~= source or outcomeGroup.action ~= action or not ContextsAreEqual(outcomeGroup.context, context)) then
    logger:Warn("Collecting existing outcome group (", outcomeGroup.source, ",", outcomeGroup.action, ",", ContextToKey(outcomeGroup.context), ") to create (", source, ",", action, ",", ContextToKey(context), ")")
    LibLootStats:CollectOutcomeGroup()
  end

  if not outcomeGroup then
    outcomeGroup = {
      source = source,
      action = action,
      context = context,
    }
  end

  if not extendLifetime then
    EVENT_MANAGER:RegisterForUpdate(LibLootStats.ADDON_NAME .. "CollectOutcomeGroup", 0, self.CollectOutcomeGroup)
  end
end

function LibLootStats:UpdatePendingOutcomeGroup(source, action, context)
  if outcomeGroup then
    if outcomeGroup.source == nil and outcomeGroup.action == nil then
      outcomeGroup.source = source
      outcomeGroup.action = action
      outcomeGroup.context = context
    else
      logger:Warn("Not updating the source of a pending outcome group because the source was already know: (", source, ",", action, ",", ContextToKey(context), ") would overwrite (", outcomeGroup.source, ",", outcomeGroup.action, ",", ContextToKey(outcomeGroup.context), ")")
    end
  end
end

function LibLootStats:CollectOutcomeGroup()
  EVENT_MANAGER:UnregisterForUpdate(LibLootStats.ADDON_NAME .. "CollectOutcomeGroup")

  if outcomeGroup ~= nil then
    if outcomeGroup.source == nil then
      logger:Warn("Not saving outcome group with nil source.")
    elseif outcomeGroup.action == nil then
      logger:Warn("Not saving outcome group with nil action. Source was:", outcomeGroup.source)
    else
      logger:Debug(outcomeGroup.source, "(", outcomeGroup.action, ")")
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
      LibLootStats:SaveOutcomeGroup(outcomeGroup)
    end
  end

  outcomeGroup, extendLifetime = nil, false
end

function LibLootStats:ExtendOutcomeGroupLifetime()
  EVENT_MANAGER:UnregisterForUpdate(LibLootStats.ADDON_NAME .. "CollectOutcomeGroup")
  extendLifetime = true
end

function LibLootStats:AddOutcome(source, action, context, item, count)
  LibLootStats:InitializeOutcomeGroup(source, action, context)

  table.insert(outcomeGroup, {
    item = item,
    count = count,
  })
end

function LibLootStats:SaveOutcomeGroup(outcomeGroup)
  local source = self.data.strings:GetId(outcomeGroup.source)
  local action = self.data.strings:GetId(outcomeGroup.action)
  local context = self.data.contexts:GetId(outcomeGroup.context)

  local normalized = {}
  for i = 1, #outcomeGroup do
    local outcome = outcomeGroup[i]
    local item = self.data.strings:GetId(outcome.item)
    table.insert(normalized, { item = item, count = outcome.count })
  end
  table.sort(normalized, function(a, b) return a.item < b.item end)

  local outcome = self.data.outcomes:GetId(normalized)

  local scenario = ScenarioToKey({
    source = source,
    action = action,
    context = context,
    outcome = outcome,
  })
  local saved = self.data.scenarios[scenario]
  self.data.scenarios[scenario] = saved and (saved + 1) or 1
end
