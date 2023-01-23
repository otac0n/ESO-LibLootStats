EVENT_MANAGER:RegisterForEvent(LibLootStats.ADDON_NAME, EVENT_ADD_ON_LOADED, function (eventCode, name)
  if name ~= LibLootStats.ADDON_NAME then return end
  LibLootStats:Initialize()
  EVENT_MANAGER:UnregisterForEvent(LibLootStats.ADDON_NAME, EVENT_ADD_ON_LOADED)
end)

local logger
function LibLootStats:Initialize()
  logger = LibDebugLogger(LibLootStats.ADDON_NAME)
  LibLootStats.logger = logger
  --logger:SetMinLevelOverride(LibDebugLogger.LOG_LEVEL_DEBUG)
  LibLootStats:InitializeSettings()
  LibLootStats:InitializeHooks()
  LibLootStats.settingsMenu = LibLootStatsSettingsMenu:New()

  LibLootStats:OnInventoryFullUpdate()
end

function LibLootStats:InitializeHooks()
  LibLootStats.reticleTracker:InitializeHooks()
  LibLootStats.craftingTracker:InitializeHooks()
  local namespace = LibLootStats.ADDON_NAME
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_INVENTORY_ITEM_DESTROYED, self.utils.Bind(self, self.OnInventoryItemDestroyed))
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_INVENTORY_ITEM_USED, self.utils.Bind(self, self.OnInventoryItemUsed))
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_INVENTORY_FULL_UPDATE, self.utils.Bind(self, self.OnInventoryFullUpdate))
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_INVENTORY_SINGLE_SLOT_UPDATE, self.utils.Bind(self, self.OnInventorySingleSlotUpdate))
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_QUEST_TOOL_UPDATED, self.utils.Bind(self, self.OnQuestToolUpdate))
  ZO_PreHook("ZO_MailInboxShared_TakeAll", self.utils.Bind(self, self.OnMailTakeAll))
  ZO_PreHook("ClaimCurrentDailyLoginReward", self.utils.Bind(self, self.OnClaimCurrentDailyLoginReward))
  ZO_PreHook(SCENE_MANAGER, "OnSceneStateChange", self.utils.Closure(self, self.OnSceneStateChanged))
  ZO_PreHook(SYSTEMS:GetObject("loot"), "UpdateLootWindow", self.utils.Closure(self, self.OnUpdateLootWindow))
  ZO_PreHook(ZO_InteractionManager, "SelectChatterOptionByIndex", self.utils.Closure(self, self.OnSelectChatterOptionByIndex))
  for i = 1, ZO_InteractWindowPlayerAreaOptions:GetNumChildren() do
    local option = ZO_InteractWindowPlayerAreaOptions:GetChild(i)
    ZO_PreHookHandler(option, "OnMouseUp", function(...) self:OnChatterOptionMouseUp(option, ...) end)
  end
  SLASH_COMMANDS["/loot"] = function() LootStatsWindow:SetHidden(false) end
end

local lastDialogue

local previousScene, inHud, nextRemovalIsUse
function LibLootStats:OnSceneStateChanged(scene, oldState, newState)
  local scene = SCENE_MANAGER:GetCurrentScene()
  if previousScene ~= scene.name then
    if previousScene == LOOT_SCENE.name then
      EVENT_MANAGER:RegisterForUpdate(LibLootStats.ADDON_NAME .. "CancelLoot", 0, function()
        EVENT_MANAGER:UnregisterForUpdate(LibLootStats.ADDON_NAME .. "CancelLoot")
        nextRemovalIsUse = false
        self.reticleTracker.tracksLootWindow = not nextRemovalIsUse
        LibLootStats:CollectPassiveSource()
      end)
    elseif previousScene == ZO_INTERACTION_SYSTEM_NAME then
      lastDialogue = nil
    end

    logger:Verbose("Scene changed to: %s", scene.name)
    previousScene = scene.name
  end
end

function LibLootStats:OnSelectChatterOptionByIndex(index)
  self:OnChatterOptionMouseUp(ZO_InteractWindowPlayerAreaOptions:GetChild(index))
end

function LibLootStats:OnChatterOptionMouseUp(option)
  lastDialogue = option:GetText()
end

local clearSubtypeAndLevel = { [3] = "0", [4] = "0" }

local itemTypeVector = {
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

local setCrownItem       = {              [4] = "1" }
local setCrownItem6      = { [3] = "6",   [4] = "1" }
local setCrownItem32     = { [3] = "32",  [4] = "1" }
local setCrownItem122    = { [3] = "122", [4] = "1" }
local setCrownItem123    = { [3] = "123", [4] = "1" }
local setCrownItemScroll = { [3] = "124", [4] = "1" }

local itemIdVector = {
  [61079]  = setCrownItem122,    -- Crown Repair Kit
  [61080]  = setCrownItem32,     -- Crown Soul Gem
  [64523]  = setCrownItemScroll, -- Attribute Respecification Scroll
  [64524]  = setCrownItemScroll, -- Skill Respecification Scroll
  [64537]  = setCrownItemScroll, -- Crown Experience Scroll
  [64700]  = setCrownItem6,      -- Crown Lesson: Riding Speed
  [64701]  = setCrownItem6,      -- Crown Lesson: Riding Stamina
  [64702]  = setCrownItem6,      -- Crown Lesson: Riding Capactity
  [64710]  = setCrownItem123,    -- Crown Tri-Restoration Potion
  [64711]  = setCrownItem123,    -- Crown Fortifying Meal
  [79690]  = setCrownItem6,      -- Crown Lethal Poison
  [94441]  = setCrownItemScroll, -- Grand Gold Coast Experience Scroll
  [125450] = setCrownItemScroll, -- Instant Blacksmithing Research
  [125464] = setCrownItemScroll, -- Instant Clothing Research
  [125467] = setCrownItemScroll, -- Instant Woodworking Research
  [125470] = setCrownItemScroll, -- Instant All Research
  [134583] = setCrownItem,       -- Transmutation Geode (Common)
  [134590] = setCrownItem,       -- Transmutation Geode (Epic)
  [134618] = setCrownItem,       -- Transmutation Geode (Legendary),  |H0:item:134618:124:1:0:0:0:5:10000:0:0:0:0:0:0:1:0:0:1:0:0:0|h|h instead of |H1:item:134618:124:1:0:0:0:5:10000:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h (Maybe?)
  [135110] = setCrownItemScroll, -- Crown Experience Scroll (Character Bound)
  [135121] = setCrownItem6,      -- Crown Lethal Poison (Character Bound)
  [135128] = setCrownItemScroll, -- Skill Respecification Scroll (Character Bound)
  [135130] = setCrownItemScroll, -- Attribute Respecification Scroll (Character Bound)
  [140252] = setCrownItem,       -- Battlemaster Rivyn's Reward Box,  |H0:item:140252:123:1:0:0:0:0:0:0:0:0:0:0:0:1:0:0:1:0:0:0|h|h instead of |H0:item:140252:123:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h
  [147557] = setCrownItem,       -- Bound Style Page: Fire Drake Axe, |H0:item:147557:124:1:0:0:0:0:0:0:0:0:0:0:0:1:0:0:1:0:0:0|h|h instead of |H0:item:147557:124:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h
  [190009] = setCrownItem,       -- Rewards for the Worthy,           |H0:item:190009:122:1:0:0:0:0:0:0:0:0:0:0:0:1:0:0:1:0:0:0|h|h instead of |H0:item:190009:122:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h
}

local function ParseItemLink(itemLink)
  return {string.match(itemLink, "^|H(%d):item:(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)|h(.*)|h")}
end
LibLootStats.ParseItemLink = ParseItemLink

local function MakeItemLink(parts)
  return "|H" .. parts[1] ..
         ":item:" .. parts[2] ..
         ":" .. parts[3] ..
         ":" .. parts[4] ..
         ":" .. parts[5] ..
         ":" .. parts[6] ..
         ":" .. parts[7] ..
         ":" .. parts[8] ..
         ":" .. parts[9] ..
         ":" .. parts[10] ..
         ":" .. parts[11] ..
         ":" .. parts[12] ..
         ":" .. parts[13] ..
         ":" .. parts[14] ..
         ":" .. parts[15] ..
         ":" .. parts[16] ..
         ":" .. parts[17] ..
         ":" .. parts[18] ..
         ":" .. parts[19] ..
         ":" .. parts[20] ..
         ":" .. parts[21] ..
         ":" .. parts[22] ..
         "|h" .. parts[23] .. "|h"
end
LibLootStats.MakeItemLink = MakeItemLink

local function CanonicalizeItemLink(itemLink)
  local parsed
  if not string.match(itemLink, "^|H0:.*|h|h$") then
    parsed = parsed or ParseItemLink(itemLink)
    parsed[1] = tostring(LINK_STYLE_DEFAULT)
    parsed[23] = ""
  end

  local bindType = GetItemLinkBindType(itemLink)
  if bindType == BIND_TYPE_ON_PICKUP or bindType == BIND_TYPE_ON_PICKUP_BACKPACK then
    parsed = parsed or ParseItemLink(itemLink)
    parsed[19] = "1"
    parsed[16] = tostring(BitOr(tonumber(parsed[16]), 1))
  end

  local itemType, _ = GetItemLinkItemType(itemLink)
  local update = itemTypeVector[itemType] or itemIdVector[GetItemLinkItemId(itemLink)]
  if update then
    parsed = parsed or ParseItemLink(itemLink)
    for i, v in pairs(update) do
      parsed[i] = v
    end
  end

  if parsed then
    itemLink = MakeItemLink(parsed)
  end
  return itemLink
end
LibLootStats.CanonicalizeItemLink = CanonicalizeItemLink

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
        local itemLink = CanonicalizeItemLink(GetAttachedItemLink(mailId, i))
        table.insert(items, { item = itemLink, count = count })
      end

      local source = self.activeSources:AddTransientSource("mail", scenario, { save = true, delay = 7000, items = items })
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

      local itemLink = CanonicalizeItemLink(GetItemRewardItemLink(rewardId, count))
      local scenario = {
        source = currentESOMonthName,
        action = GetString(SI_DAILY_LOGIN_REWARDS_CLAIM_KEYBIND),
        context = {}
      }
      self.activeSources:AddTransientSource("reward", scenario, { save = true, delay = 7000, items = { [1] = { item = itemLink, count = count } } })
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
LibLootStats.SkillPointLevel = SkillPointLevel

function LibLootStats:GetScenario()
  local interactable, interaction, context = nil, nil, {}
  if not nextRemovalIsUse then
    local target = self.reticleTracker.lastTarget
    if target and target.active then
      interactable, interaction = target.interactableName, lastDialogue or target.originalInteraction or target.interaction
      if target.fishingLure then
        context.lure = target.fishingLure
        context.angler = SkillPointLevel(89)
      elseif target.socialClass then
        interactable = target.socialClass
        context.cutpurse = SkillPointLevel(90)
      elseif target.lockQuality then
        context.lock = target.lockQuality
        context.hunter = SkillPointLevel(79)
      elseif lastDialogue then
      else
        context.harvest = SkillPointLevel(81)
        context.homemaker = SkillPointLevel(91)
      end
      context.zoneId = GetZoneId(GetUnitZoneIndex("player"))
    end
  end
  return { source = interactable, action = interaction, context = context }
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

function LibLootStats:OnQuestToolUpdate(eventId, journalIndex, questName, countDelta, iconFilename, questItemId, name, ...)
  local itemLink = "|H0:quest_item:" .. questItemId .. "|h|h"
  if countDelta > 0 then
    logger:Debug("Added", itemLink, "(" .. countDelta .. ")")
    self:OnItemLinkAdded(itemLink, countDelta)
  end
end

function LibLootStats:OnInventorySingleSlotUpdate(eventId, bagId, slotId, isNewItem, soundCategory, reason, stackCountChange)
  if isNewItem then
    local itemLink = GetItemLink(bagId, slotId)
    inventorySnapshot[bagId][slotId] = itemLink
    self:OnItemLinkAdded(itemLink, stackCountChange)
  else
    if stackCountChange < 0 then
      local itemLink = inventorySnapshot[bagId][slotId]
      if nextRemovalIsUse then
        if bagId == BAG_BACKPACK and stackCountChange == -1 then
          LibLootStats:UpdatePendingPassiveSource(itemLink, GetString(SI_ITEM_ACTION_USE), {})
        else
          logger:Warn("Not tracking", GetString(SI_ITEM_ACTION_USE), itemLink, "with the change count", stackCountChange)
        end
        EVENT_MANAGER:UnregisterForUpdate(LibLootStats.ADDON_NAME .. "CancelLoot")
        LibLootStats:CollectPassiveSource()
        nextRemovalIsUse = false
        self.reticleTracker.tracksLootWindow = not nextRemovalIsUse
      end
    end
    inventorySnapshot[bagId][slotId] = GetItemLink(bagId, slotId)
  end
end

function LibLootStats:OnItemLinkAdded(itemLink, countDelta)
  local scenario
  local activeSource = self.activeSources:FindBestSource(itemLink, countDelta)
  if activeSource then
    if activeSource.scenario == nil then
      logger:Info("Skipping", itemLink, "from", activeSource.name, "source.")
      return
    end
    scenario = activeSource.scenario
  else
    local filledSoulGem = false

    if itemLink == "|H0:item:33271:31:50:0:0:0:0:0:0:0:0:0:0:0:0:36:0:0:0:0:0|h|h" then
      for i = 1, GetNumBuffs("player") do
        local _, _, _, _, stackCount, _, buffType, effectType, abilityType, statusEffectType, abilityId, _, _ = GetUnitBuffInfo("player", i)
        if abilityType == ABILITY_TYPE_FILLSOULGEM then
          scenario = LibLootStats:InitializePassiveSource({
            source = GetString("SI_ITEMTYPE", ITEMTYPE_SOUL_GEM),
            action = GetString(SI_SOUL_GEM_FILLED),
            context = {}
          })
          filledSoulGem = true
          break
        end
      end
    end

    if not filledSoulGem then
      scenario = LibLootStats:InitializePassiveSource(LibLootStats:GetScenario())
    end
  end

  LibLootStats:AddOutcome(scenario, itemLink, countDelta)
end

function LibLootStats:OnInventoryItemUsed(eventCode, itemSoundCategory)
  nextRemovalIsUse = true
  self.reticleTracker.tracksLootWindow = not nextRemovalIsUse
end

function LibLootStats:OnInventoryItemDestroyed(eventCode, itemSoundCategory)
end

function LibLootStats:OnUpdateLootWindow(containerName, actionName, isOwned)
  LibLootStats:ExtendPassiveSourceLifetime()
  --local scenario = LibLootStats:InitializePassiveSource(LibLootStats:GetScenario())
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
    --LibLootStats:AddOutcome(scenario, name, count)
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
    local item = string.sub(key, a + 1, b - 1)
    local count = string.sub(key, b + 1, c - 1)
    table.insert(outcome, { item = tonumber(item) or item, count = tonumber(count) or count })
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
  local source, action, context, outcome = string.match(key, "^(%d+)%/(%d+)%@(%d+)%>(%d+)$")
  return {
    source = tonumber(source),
    action = tonumber(action),
    context = tonumber(context),
    outcome = tonumber(outcome),
  }
end
LibLootStats.ParseScenarioKey = ParseScenarioKey

local passiveScenario, extendLifetime = nil, false
function LibLootStats:InitializePassiveSource(scenario)
  local source, action, context = scenario.source, scenario.action, scenario.context
  EVENT_MANAGER:UnregisterForUpdate(LibLootStats.ADDON_NAME .. "CollectPassiveSource")

  if passiveScenario and (passiveScenario.source ~= source or passiveScenario.action ~= action or not ContextsAreEqual(passiveScenario.context, context)) then
    logger:Warn("Collecting existing outcome group (", passiveScenario.source, ",", passiveScenario.action, ",", ContextToKey(passiveScenario.context), ") to create (", source, ",", action, ",", ContextToKey(context), ")")
    LibLootStats:CollectPassiveSource()
  end

  if not passiveScenario then
    passiveScenario = scenario
  end

  if not extendLifetime then
    EVENT_MANAGER:RegisterForUpdate(LibLootStats.ADDON_NAME .. "CollectPassiveSource", 0, self.CollectPassiveSource)
  end

  return passiveScenario
end

function LibLootStats:AddOutcome(scenario, item, count)
  table.insert(scenario, {
    item = item,
    count = count,
  })
end

function LibLootStats:UpdatePendingPassiveSource(source, action, context)
  if passiveScenario then
    if passiveScenario.source == nil and passiveScenario.action == nil then
      passiveScenario.source = source
      passiveScenario.action = action
      passiveScenario.context = context
    else
      logger:Warn("Not updating the source of a pending outcome group because the source was already know: (", source, ",", action, ",", ContextToKey(context), ") would overwrite (", passiveScenario.source, ",", passiveScenario.action, ",", ContextToKey(passiveScenario.context), ")")
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

function LibLootStats:CollectPassiveSource()
  EVENT_MANAGER:UnregisterForUpdate(LibLootStats.ADDON_NAME .. "CollectPassiveSource")

  if passiveScenario ~= nil then
    if passiveScenario.source == nil then
      logger:Warn("Not saving outcome group with nil source." .. itemsDebug(passiveScenario))
    elseif passiveScenario.action == nil then
      logger:Warn("Not saving outcome group with nil action. Source was: " .. passiveScenario.source .. itemsDebug(passiveScenario))
    else
      LibLootStats:SaveOutcomeGroup(passiveScenario)
    end
  end

  passiveScenario, extendLifetime = nil, false
end

function LibLootStats:ExtendPassiveSourceLifetime()
  EVENT_MANAGER:UnregisterForUpdate(LibLootStats.ADDON_NAME .. "CollectPassiveSource")
  extendLifetime = true
end

function LibLootStats:GetOutcomeId(outcomeGroup, maintainOrder)
  local normalized = {}
  for i = 1, #outcomeGroup do
    local outcome = outcomeGroup[i]
    local item = self.data.strings:GetId(outcome.item)
    table.insert(normalized, { item = item, count = outcome.count })
  end
  if not maintainOrder then
    table.sort(normalized, function(a, b) return a.item < b.item end)
  end

  return self.data.outcomes:GetId(normalized)
end

function LibLootStats:SaveOutcomeGroup(outcomeGroup)
  logger:Info(outcomeGroup.source .. " (" .. outcomeGroup.action .. ") @" .. ContextToKey(outcomeGroup.context) .. itemsDebug(outcomeGroup))

  local source = self.data.strings:GetId(outcomeGroup.source)
  local action = self.data.strings:GetId(outcomeGroup.action)
  local context = self.data.contexts:GetId(outcomeGroup.context)

  local outcome = self:GetOutcomeId(outcomeGroup, outcomeGroup.maintainOrder)

  local scenario = ScenarioToKey({
    source = source,
    action = action,
    context = context,
    outcome = outcome,
  })
  local saved = self.data.scenarios[scenario]
  self.data.scenarios[scenario] = saved and (saved + 1) or 1
end
