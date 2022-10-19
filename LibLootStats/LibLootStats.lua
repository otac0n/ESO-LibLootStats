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
  ZO_PreHook(SYSTEMS:GetObject("loot"), "UpdateLootWindow", self.utils.Closure(self, self.OnUpdateLootWindow))
  ZO_PreHook(ZO_InteractionManager, "SelectChatterOptionByIndex", self.utils.Closure(self, self.OnSelectChatterOptionByIndex))
  for i = 1, ZO_InteractWindowPlayerAreaOptions:GetNumChildren() do
    local option = ZO_InteractWindowPlayerAreaOptions:GetChild(i)
    ZO_PreHookHandler(option, "OnMouseUp", function(...) self:OnChatterOptionMouseUp(option, ...) end)
  end
end

local lastDialogue

local currentScene, inHud, nextRemovalIsUse
function LibLootStats:OnSceneStateChanged(scene, oldState, newState)
  local scene = SCENE_MANAGER:GetCurrentScene()
  if currentScene ~= scene.name then
    if currentScene == LOOT_SCENE.name then
      EVENT_MANAGER:RegisterForUpdate(LibLootStats.ADDON_NAME .. "CancelLoot", 0, function()
        EVENT_MANAGER:UnregisterForUpdate(LibLootStats.ADDON_NAME .. "CancelLoot")
        nextRemovalIsUse = false
        self.reticleTracker.tracksLootWindow = not nextRemovalIsUse
        LibLootStats:CollectOutcomeGroup()
      end)
    elseif currentScene == ZO_INTERACTION_SYSTEM_NAME then
      lastDialogue = nil
    end

    currentScene = scene.name
    logger:Verbose("Scene changed to: %s", currentScene)
  end
end

function LibLootStats:OnSelectChatterOptionByIndex(index)
  self:OnChatterOptionMouseUp(ZO_InteractWindowPlayerAreaOptions:GetChild(index))
end

function LibLootStats:OnChatterOptionMouseUp(option)
  lastDialogue = option:GetText()
end

local clearSubtypeAndLevel = { [4] = "0", [5] = "0" }
local updateVector = {
  [ITEMTYPE_ARMOR_BOOSTER] = clearSubtypeAndLevel,
  [ITEMTYPE_ARMOR_TRAIT] = clearSubtypeAndLevel,
  [ITEMTYPE_BLACKSMITHING_BOOSTER] = clearSubtypeAndLevel,
  [ITEMTYPE_BLACKSMITHING_MATERIAL] = clearSubtypeAndLevel,
  [ITEMTYPE_BLACKSMITHING_RAW_MATERIAL] = clearSubtypeAndLevel,
  [ITEMTYPE_CLOTHIER_BOOSTER] = clearSubtypeAndLevel,
  [ITEMTYPE_CLOTHIER_MATERIAL] = clearSubtypeAndLevel,
  [ITEMTYPE_CLOTHIER_RAW_MATERIAL] = clearSubtypeAndLevel,
  [ITEMTYPE_BLACKSMITHING_RAW_MATERIAL] = clearSubtypeAndLevel,
  [ITEMTYPE_BLACKSMITHING_RAW_MATERIAL] = clearSubtypeAndLevel,
  [ITEMTYPE_ENCHANTING_RUNE_ASPECT] = clearSubtypeAndLevel,
  [ITEMTYPE_ENCHANTING_RUNE_ESSENCE] = clearSubtypeAndLevel,
  [ITEMTYPE_ENCHANTING_RUNE_POTENCY] = clearSubtypeAndLevel,
  [ITEMTYPE_FURNISHING_MATERIAL] = clearSubtypeAndLevel,
  [ITEMTYPE_INGREDIENT] = clearSubtypeAndLevel,
  [ITEMTYPE_JEWELRYCRAFTING_BOOSTER] = clearSubtypeAndLevel,
  [ITEMTYPE_JEWELRYCRAFTING_RAW_BOOSTER] = clearSubtypeAndLevel,
  [ITEMTYPE_JEWELRYCRAFTING_MATERIAL] = clearSubtypeAndLevel,
  [ITEMTYPE_JEWELRYCRAFTING_RAW_MATERIAL] = clearSubtypeAndLevel,
  [ITEMTYPE_JEWELRY_RAW_TRAIT] = clearSubtypeAndLevel,
  [ITEMTYPE_JEWELRY_TRAIT] = clearSubtypeAndLevel,
  [ITEMTYPE_RAW_MATERIAL] = clearSubtypeAndLevel,
  [ITEMTYPE_STYLE_MATERIAL] = clearSubtypeAndLevel,
  [ITEMTYPE_WEAPON_BOOSTER] = clearSubtypeAndLevel,
  [ITEMTYPE_WEAPON_TRAIT] = clearSubtypeAndLevel,
  [ITEMTYPE_WOODWORKING_BOOSTER] = clearSubtypeAndLevel,
  [ITEMTYPE_WOODWORKING_MATERIAL] = clearSubtypeAndLevel,
  [ITEMTYPE_WOODWORKING_RAW_MATERIAL] = clearSubtypeAndLevel,
}

function LibLootStats:CanonicalizeItemLink(itemLink)
  local itemType, specializedItemType = GetItemLinkItemType(itemLink)
  local update = updateVector[itemType]
  if update then
    itemLink = self:UpdateItemLink(itemLink, update)
  end
  return itemLink
end

function LibLootStats:UpdateItemLink(itemLink, updates)
  local updated = ""
  local i = 1
  for v in string.gmatch(itemLink, "[^:]+") do
    updated = updated .. (updated ~= "" and ":" or "") .. (updates[i] or v)
    i = i + 1
  end
  return updated
end

function LibLootStats:OnMailTakeAll(mailId)
  local senderDisplayName, senderCharacterName, subject, icon, unread, fromSystem, fromCS, returned, numAttachments, attachedMoney, codAmount, expiresInDays, secsSinceReceived = GetMailItemInfo(mailId)

  local shouldTrack = fromSystem and not fromCS and not returned
  if shouldTrack and numAttachments > 0 then
    local exists = false
    for _, source in ipairs(self.activeSources.sources) do
      if source.mailId == mailId then
        exists = true
        break
      end
    end

    if not exists then
      local scenario = {
        source = subject,
        action = GetString(SI_MAIL_READ_ATTACHMENTS_TAKE),
        context = {}
      }

      local items = {}
      for i = 1, numAttachments do
        local icon, count, creator = GetAttachedItemInfo(mailId, i)
        local itemLink = self:CanonicalizeItemLink(GetAttachedItemLink(mailId, i))
        table.insert(items, { item = itemLink, count = count })
      end

      local source = self.activeSources:AddTransientSource("mail", scenario, { delay = 7000, items = items })
      source.mailId = mailId
    end
  end
end

function LibLootStats:OnClaimCurrentDailyLoginReward()
  local index = GetDailyLoginClaimableRewardIndex()
  if index ~= nil then
    local rewardId, count, isMilestone = GetDailyLoginRewardInfoForCurrentMonth(index)
    local entryType = GetRewardType(rewardId)
    if entryType == REWARD_ENTRY_TYPE_ITEM then
      local currentMonth = GetCurrentDailyLoginMonth()
      local currentESOMonthName = GetString("SI_GREGORIANCALENDARMONTHS_LORENAME", currentMonth)

      local itemLink = self:CanonicalizeItemLink(GetItemRewardItemLink(rewardId, count))
      local scenario = {
        source = currentESOMonthName,
        action = GetString(SI_DAILY_LOGIN_REWARDS_CLAIM_KEYBIND),
        context = {}
      }
      self.activeSources:AddTransientSource("reward", scenario, { delay = 7000, items = { [1] = { item = itemLink, count = count } } })
    end
  end
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
  local interactable, interaction, context = nil, nil, {}
  if not nextRemovalIsUse then
    local target = self.reticleTracker.lastTarget
    if target and target.active then
      interactable, interaction = target.interactableName, lastDialogue or target.interaction
      if target.additionalInteractInfo == ADDITIONAL_INTERACT_INFO_FISHING_NODE then
        context.lure = target.fishingLure
        context.angler = SkillPointLevel(89)
      elseif target.additionalInteractInfo == ADDITIONAL_INTERACT_INFO_PICKPOCKET_CHANCE then
        interactable = target.socialClass
        context.cutpurse = SkillPointLevel(90)
      elseif target.additionalInteractInfo == ADDITIONAL_INTERACT_INFO_LOCKED then
        context.lock = target.lockQuality
        context.hunter = SkillPointLevel(79)
      else
        context.harvest = SkillPointLevel(81)
        context.homemaker = SkillPointLevel(91)
      end
      context.zoneId = GetZoneId(GetUnitZoneIndex("player"))
    end
  end
  return interactable, interaction, context
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

function LibLootStats:OnInventorySingleSlotUpdate(eventId, bagId, slotId, isNewItem, soundCategory, reason, stackCountChange)
  if isNewItem then
    local source, action, context
    local itemLink = GetItemLink(bagId, slotId)
    inventorySnapshot[bagId][slotId] = itemLink

    local activeSource = self.activeSources:FindBestSource(itemLink, stackCountChange)
    if activeSource then
      if activeSource.scenario == nil then
        logger:Debug("Skipping", itemLink, "from", activeSource.name, "source.")
        return
      end
      source, action, context = activeSource.scenario.source, activeSource.scenario.action, activeSource.scenario.context
    else
      source, action, context = LibLootStats:GetContext()
    end

    LibLootStats:AddOutcome(source, action, context, itemLink, stackCountChange)
  else
    if stackCountChange < 0 then
      local itemLink = inventorySnapshot[bagId][slotId]
      if nextRemovalIsUse then
        if bagId == BAG_BACKPACK and stackCountChange == -1 then
          LibLootStats:UpdatePendingOutcomeGroup(itemLink, GetString(SI_ITEM_ACTION_USE), {})
        else
          logger:Warn("Not tracking", GetString(SI_ITEM_ACTION_USE), itemLink, "with the change count", stackCountChange)
        end
        EVENT_MANAGER:UnregisterForUpdate(LibLootStats.ADDON_NAME .. "CancelLoot")
        LibLootStats:CollectOutcomeGroup()
        nextRemovalIsUse = false
        self.reticleTracker.tracksLootWindow = not nextRemovalIsUse
      end
    end
    inventorySnapshot[bagId][slotId] = GetItemLink(bagId, slotId)
  end
end

function LibLootStats:OnInventoryItemUsed(eventCode, itemSoundCategory)
  nextRemovalIsUse = true
  self.reticleTracker.tracksLootWindow = not nextRemovalIsUse
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

function itemsDebug(outcomeGroup)
  local logOutput = ""
  for i = 1, #outcomeGroup do
    local outcome = outcomeGroup[i]
    logOutput = logOutput .. "\n  -> " .. outcome.item
    if outcome.count ~= 1 then
      logOutput = logOutput .. " (" .. tostring(outcome.count) .. ")"
    end
  end
  return logOutput
end
LibLootStats.itemsDebug = itemsDebug

function LibLootStats:CollectOutcomeGroup()
  EVENT_MANAGER:UnregisterForUpdate(LibLootStats.ADDON_NAME .. "CollectOutcomeGroup")

  if outcomeGroup ~= nil then
    if outcomeGroup.source == nil then
      logger:Warn("Not saving outcome group with nil source." .. itemsDebug(outcomeGroup))
    elseif outcomeGroup.action == nil then
      logger:Warn("Not saving outcome group with nil action. Source was: " .. outcomeGroup.source .. itemsDebug(outcomeGroup))
    else
      logger:Debug(outcomeGroup.source .. " (" .. outcomeGroup.action .. ")" .. itemsDebug(outcomeGroup))

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
