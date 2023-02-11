local scenarios = {}
local outcomes = {}
local Caches = {
  scenarios = scenarios,
  outcomes = outcomes,
  setIdBonusImpacts = {},
}
local Analysis = {
  Caches = Caches,
}
LibLootStats.Analysis = Analysis

local itemTypeVector = {
  [ITEMTYPE_ARMOR_BOOSTER] = 'improvement',
  [ITEMTYPE_ARMOR_TRAIT] = 'trait',
  [ITEMTYPE_BLACKSMITHING_BOOSTER] = 'improvement',
  [ITEMTYPE_BLACKSMITHING_MATERIAL] = 'material',
  [ITEMTYPE_BLACKSMITHING_RAW_MATERIAL] = 'raw',
  [ITEMTYPE_CLOTHIER_BOOSTER] = 'improvement',
  [ITEMTYPE_CLOTHIER_MATERIAL] = 'material',
  [ITEMTYPE_CLOTHIER_RAW_MATERIAL] = 'raw',
  [ITEMTYPE_ENCHANTING_RUNE_ASPECT] = 'aspect',
  [ITEMTYPE_ENCHANTING_RUNE_ESSENCE] = 'essence',
  [ITEMTYPE_ENCHANTING_RUNE_POTENCY] = 'potency',
  [ITEMTYPE_FURNISHING_MATERIAL] = 'material',
  [ITEMTYPE_JEWELRYCRAFTING_BOOSTER] = 'improvement',
  [ITEMTYPE_JEWELRYCRAFTING_RAW_BOOSTER] = 'raw_improvement',
  [ITEMTYPE_JEWELRYCRAFTING_MATERIAL] = 'material',
  [ITEMTYPE_JEWELRYCRAFTING_RAW_MATERIAL] = 'raw',
  [ITEMTYPE_JEWELRY_RAW_TRAIT] = 'raw_trait',
  [ITEMTYPE_JEWELRY_TRAIT] = 'trait',
  [ITEMTYPE_RAW_MATERIAL] = 'raw_style',
  [ITEMTYPE_STYLE_MATERIAL] = 'style',
  [ITEMTYPE_WEAPON_BOOSTER] = 'improvement',
  [ITEMTYPE_WEAPON_TRAIT] = 'trait',
  [ITEMTYPE_WOODWORKING_BOOSTER] = 'improvement',
  [ITEMTYPE_WOODWORKING_MATERIAL] = 'material',
  [ITEMTYPE_WOODWORKING_RAW_MATERIAL] = 'raw',
}
Analysis.itemTypeVector = itemTypeVector

--- Enumerate all outcomes according to the specified filter functions.
-- @param ... Any number of filter functions.
function LibLootStats:EnumerateScenarios(...)
  local filter = self.Filter.And(...)
  for key, count in pairs(LibLootStats.data.scenarios.keyToCount) do
    local scenario = Caches.LookupScenario(key)
    filter(scenario, count)
  end
end

function LibLootStats:Find(name, caseSensitive)
  local filter
  if not caseSensitive then
    filter = Filter.ToLower(Filter.LibTextFilter(name:lower()))
  else
    filter = Filter.LibTextFilter(name)
  end
  return self:FindScenarios(Filter.AnyTextField(filter))
end

function LibLootStats:FindScenarios(...)
  local results = {}
  self:EnumerateScenarios(..., function (scenario, count)
    results[scenario.key] = scenario
  end)
  return results
end

local function SimilarItemLinkPattern(itemLink)
  local parsed = LibLootStats.ParseItemLink(itemLink)
  parsed[1] = "%d"
  parsed[16] = "%d+"
  parsed[19] = "%d"
  parsed[20] = "%d"
  if not GetItemLinkShowItemStyleInTooltip(itemLink) then
    parsed[17] = "%d+"
  end
  parsed[23] = ".*"
  return "^" .. LibLootStats.MakeItemLink(parsed) .. "$"
end
Analysis.SimilarItemLinkPattern = SimilarItemLinkPattern

local patterns = {
  ["^Adds (%d+%%?) (.*)$"] = 2,
}
function Analysis.CountItemLinkSetBonusAttributeImpacts(itemLink)
  local hasSet, setName, numBonuses, numNormalEquipped, maxEquipped, setId, numPerfectedEquipped = GetItemLinkSetInfo(itemLink, false)
  if hasSet then
    local impact = Caches.setIdBonusImpacts[setId]
    if not impact then
      local impact = {}
      local unknown
      for i = 1, numBonuses do
        local numRequired, description, isPerfectedBonus = GetItemLinkSetBonusInfo(itemLink, false, i)
        description = string.match(description, '^%(' .. numRequired .. ' items%) (.*)$') or description
        for pattern, index in pairs(patterns) do
          local match = {string.match(description, pattern)}
          local key
          if match[index] then
            key = match[index]
          else
            key = description
          end
          impact[key] = (impact[key] or 0) + 1
        end
      end
      Caches.setIdBonusImpacts[setId] = impact
    end
    return impact
  end
end

local function MakeSourceStatistic(outcomeItemKey, makeValue, accumulate, makeResult)
  local function groupKey(scenarioKey)
    local scenario = Caches.LookupScenario(scenarioKey)
    local keys = {}
    for _, pair in ipairs(scenario.outcome) do
      local itemKey = outcomeItemKey(pair.item)
      if itemKey ~= nil then
        keys[itemKey] = true
      end
    end
    local groupKeys = {}
    for k, _ in pairs(keys) do
      table.insert(groupKeys, k)
    end
    return groupKeys
  end

  local function makeValueInner(scenarioKey, count, groupKey)
    scenario = Caches.LookupScenario(scenarioKey)
    return makeValue(scenario, count, groupKey)
  end

  return LibLootStats.data.scenarios:AddStatistic(groupKey, makeValueInner, accumulate, makeResult)
end
Analysis.MakeSourceStatistic = MakeSourceStatistic

function Analysis.FindItemLinkSources(itemLink)
  if not Caches.itemSources then
    Caches.itemSources = MakeSourceStatistic(
      function (itemLink) return itemLink end,
      function (scenario, count, itemLink)
        local outcomeCount = 0
        for _, pair in ipairs(scenario.outcome) do
          if pair.item == itemLink then
            outcomeCount = outcomeCount + pair.count
          end
        end
        local sourceItems = scenario.sourceItems or { { item = scenario.source, count = 1 } }
        local sourceCount = 0
        for _, sourceItem in ipairs(sourceItems) do
          sourceCount = sourceCount + sourceItem.count
        end

        local result = {}
        if sourceCount > 0 then
          for _, sourceItem in ipairs(sourceItems) do
            result[sourceItem.item] = (result[sourceItem.item] or 0) + (sourceItem.count / sourceCount) * count
          end
        end
        return {
          [scenario.action] = result
        }
      end,
      function (a, b)
        for action, bItems in pairs(b) do
          local aItems = a[action]
          if aItems then
            for item, count in pairs(bItems) do
              aItems[item] = (aItems[item] or 0) + count
            end
          else
            a[action] = bItems
          end
        end
        return a
      end)
  end
  return Caches.itemSources:GetValueByKey(itemLink)
end

local function IsItemLinkDeconstructable(itemLink)
  local itemType = itemTypeVector[GetItemLinkItemType(itemLink)]
  if itemType then
    return string.match(itemType, "^raw")
  end

  local craftingType = GetItemLinkCraftingSkillType(itemLink)
  if craftingType ~= CRAFTING_TYPE_INVALID and craftingType ~= CRAFTING_TYPE_ALCHEMY and craftingType ~= CRAFTING_TYPE_PROVISIONING then
    if not ZO_IsElementInNumericallyIndexedTable({GetItemLinkFilterTypeInfo(itemLink)}, ITEMFILTERTYPE_COMPANION) then
      if GetItemLinkValue(itemLink) ~= 500 then -- Exemplary
        return true
      end
    end
  end
  return false
end
Analysis.IsItemLinkDeconstructable = IsItemLinkDeconstructable

local function WilsonScore(positive, samples, z)
  z = z or 1.96 -- 95% confidence
  local p = positive / samples
  local zSq = z * z
  local partA = 2 * positive + zSq
  local partB = zSq - 1/samples + 4*positive*(1 - p)
  local partC = 4 * p - 2
  local denom = 2 * (samples + zSq)
  local lower = math.max(0, (partA - (z * math.sqrt(partB + partC) + 1)) / denom)
  local upper = math.min(1, (partA + (z * math.sqrt(partB - partC) + 1)) / denom)
  return p, lower, upper
end
Analysis.WilsonScore = WilsonScore

--- Welford's Algorithm, weighted
local function CombineVariance(countA, averageA, M2a, countB, averageB, M2b)
  local count = countA + countB
  local delta = averageB - averageA
  local partA = delta * (countB / count)
  local M2 = M2a + M2b + delta * countA * partA
  local average = averageA + partA
  return count, average, M2
end
Analysis.CombineVariance = CombineVariance

local bonuses = {
  [CRAFTING_TYPE_CLOTHIER] = 'cloth',
  [CRAFTING_TYPE_BLACKSMITHING] = 'smith',
  [CRAFTING_TYPE_WOODWORKING] = 'wood',
  [CRAFTING_TYPE_JEWELRYCRAFTING] = 'jewel',
  [CRAFTING_TYPE_ENCHANTING] = 'enchant',
}
Analysis.craftingTypeBonusContextKeys = bonuses
local function MakeDeconstructionStatistic(sourceItemKey, outcomeItemKey)
  outcomeItemKey = outcomeItemKey or function (key) return key end

  local function groupItemKey(itemLink, context)
    local skillType = GetItemLinkCraftingSkillType(itemLink)
    if skillType == CRAFTING_TYPE_INVALID then
      local itemType = itemTypeVector[GetItemLinkItemType(itemLink)]
      if not (itemType == 'raw_style' or itemType == 'raw_trait') then
        return
      end
    elseif context[bonuses[skillType]] ~= 3 then
      return
    end

    return sourceItemKey(itemLink)
  end

  local function groupKey(scenarioKey)
    local scenario = Caches.LookupScenario(scenarioKey)
    if scenario.sourceItems and scenario.action == GetString(SI_INTERACT_OPTION_UNIVERSAL_DECONSTRUCTION) and scenario.context and scenario.context.meticulous == 1 then
      local anyHasCount, pattern = false, nil
      for _, pair in ipairs(scenario.sourceItems) do
        local newPattern = groupItemKey(pair.item, scenario.context)
        if not newPattern then
          return nil
        end
        anyHasCount = anyHasCount or pair.count > 0
        if pattern == nil then
          pattern = newPattern
        elseif pattern ~= newPattern then
          return nil
        end
      end
      return (anyHasCount and pattern) or nil
    end
  end

  local function makeValue(scenarioKey, count)
    scenario = Caches.LookupScenario(scenarioKey)
    local samples = 0
    for _, pair in ipairs(scenario.sourceItems) do
      samples = samples + pair.count
    end
    -- TODO: Compute M2,b of the byItem aggregate
    local byItem = {}
    for _, pair in ipairs(scenario.outcome) do
      local itemKey = outcomeItemKey(pair.item)
      if itemKey then
        local agg = byItem[itemKey]
        if not agg then
          agg = { mean = 0, M2 = 0 }
          byItem[itemKey] = agg
        end
        agg.mean = agg.mean + pair.count
      end
    end
    for _, agg in pairs(byItem) do
      agg.mean = agg.mean / samples
    end
    return {
      byItem = byItem,
      samples = samples * count,
    }
  end

  local function accumulate(a, b)
    for item, aggA in pairs(a.byItem) do
      if not b.byItem[item] then
        b.byItem[item] = { mean = 0, M2 = 0 }
      end
    end
    local byItem = {}
    for item, aggB in pairs(b.byItem) do
      local aggA = a.byItem[item]
      if not aggA then
        aggA = { mean = 0, M2 = 0 }
      end
      byItem[item] = aggA
      _, aggA.mean, aggA.M2 = CombineVariance(a.samples, aggA.mean, aggA.M2, b.samples, aggB.mean, aggB.M2)
    end
    return {
      byItem = byItem,
      samples = a.samples + b.samples,
    }
  end

  local function makeResult(a)
    local expectation = {
      samples = a.samples,
    }
    if a.samples > 1 then
      for item, agg in pairs(a.byItem) do
        local sampleVariance = agg.M2 / (a.samples - 1)
        local standardError = (1.96 * sampleVariance) / math.sqrt(a.samples) -- 95% confidence, Student's T
        local expected = math.max(0, agg.mean * (1 - standardError))
        local lower = agg.mean - sampleVariance
        local upper = agg.mean + sampleVariance
        table.insert(expectation, { item = item, expected = expected, lower = lower, upper = upper })
      end
    end
    return expectation
  end

  return LibLootStats.data.scenarios:AddStatistic(groupKey, makeValue, accumulate, makeResult)
end
Analysis.MakeDeconstructionStatistic = MakeDeconstructionStatistic

function Analysis.ItemSaleValue(item)
  local value, laundry = GetItemLinkValue(item), 0
  if IsItemLinkStolen(item) then
    laundry = value
    value = value * 1.1
  end
  if not IsItemLinkBound(item) then
    local price = LibPrice and LibPrice.ItemLinkToBidAskSpread and LibPrice.ItemLinkToBidAskSpread(item).gold
    if price then
      local bid = price.bid and (price.bid.value * 0.8 - laundry)
      local sale = price.sale and (price.sale.value * 0.8 - laundry)
      return math.max(value, bid or 0, sale or 0)
    end
  end
  return value
end

local function AttachExpectationValues(expectation, getValue)
  local totalValue = 0
  for _, row in ipairs(expectation) do
    local value = getValue(row.item)
    if value then
      local expectedValue = value * row.expected
      row.value = expectedValue
      totalValue = totalValue + expectedValue
    end
  end
  expectation.value = totalValue
end
Analysis.AttachExpectationValues = AttachExpectationValues

function LibLootStats:FindDeconstructionExpectation(itemLink, getValue)
  if not IsItemLinkDeconstructable(itemLink) then
    return
  end

  if not Caches.similarItemOutcome then
    Caches.similarItemOutcome = MakeDeconstructionStatistic(SimilarItemLinkPattern)
  end

  local expectation = Caches.similarItemOutcome:GetValueByKey(SimilarItemLinkPattern(itemLink)) or { samples = 0 }
  if expectation.samples <= 6 and GetItemLinkCraftingSkillType(itemLink) ~= CRAFTING_TYPE_ENCHANTING then
    local upside = self.ItemDeconstructionUpside(itemLink) or {}
    upside.samples = expectation.samples
    expectation = upside
  end

  if getValue then
    AttachExpectationValues(expectation, getValue)
  end
  return expectation
end

local function UpsideKey(itemLink)
  local armorType = GetItemLinkArmorType(itemLink)
  local weaponOrEquipType
  if armorType == ARMORTYPE_NONE then
    weaponOrEquipType = GetItemLinkWeaponType(itemLink)
    if weaponOrEquipType == WEAPONTYPE_RUNE then
      return
    end
  else
    weaponOrEquipType = GetItemLinkEquipType(itemLink)
  end

  local functionalQuality = GetItemLinkFunctionalQuality(itemLink)
  local hasSet = GetItemLinkSetInfo(itemLink)
  local isCrafted = IsItemLinkCrafted(itemLink)
  return tostring(armorType)
    .. ':' .. tostring(weaponOrEquipType)
    .. ':' .. tostring(functionalQuality)
    .. ':' .. tostring(hasSet)
    .. ':' .. tostring(isCrafted)
end

local function MaterialKey(itemLink)
  local armorType = GetItemLinkArmorType(itemLink)
  local weaponOrEquipType
  if armorType == ARMORTYPE_NONE then
    weaponOrEquipType = GetItemLinkWeaponType(itemLink)
    if weaponOrEquipType == WEAPONTYPE_RUNE then
      return
    end
  else
    weaponOrEquipType = GetItemLinkEquipType(itemLink)
  end

  local functionalQuality = GetItemLinkFunctionalQuality(itemLink)
  local level = GetItemLinkRequiredLevel(itemLink)
  local cpLevel = GetItemLinkRequiredChampionPoints(itemLink)
  local isCrafted = IsItemLinkCrafted(itemLink)
  return tostring(armorType)
    .. ':' .. tostring(weaponOrEquipType)
    .. ':' .. tostring(level)
    .. ':' .. tostring(cpLevel)
    .. ':' .. tostring(functionalQuality)
    .. ':' .. tostring(isCrafted)
end

local function StyleKey(itemLink)
  local craftingType = GetItemLinkCraftingSkillType(itemLink)
  if not DoesSmithingTypeIgnoreStyleItems(craftingType) then
    local functionalQuality = GetItemLinkFunctionalQuality(itemLink)
    local isCrafted = IsItemLinkCrafted(itemLink)
    local itemStyle = GetItemLinkItemStyle(itemLink)
    return tostring(functionalQuality)
      .. ':' .. tostring(isCrafted)
      .. ':' .. tostring(itemStyle)
  end
end

local function UpsideOutcomeKey(itemLink)
  local itemType = itemTypeVector[GetItemLinkItemType(itemLink)]
  if itemType ~= 'style' and itemType ~= 'raw' or itemType ~= 'material' then
    return itemType
  end
end

local function MaterialOutcomeKey(itemLink)
  local itemType = itemTypeVector[GetItemLinkItemType(itemLink)]
  if itemType == 'raw' or itemType == 'material' then
    return itemLink
  end
end

local function StyleOutcomeKey(itemLink)
  local itemType = itemTypeVector[GetItemLinkItemType(itemLink)]
  if itemType == 'style' then
    return itemType
  end
end

function LibLootStats.ItemDeconstructionUpside(itemLink, getValue)
  if not IsItemLinkDeconstructable(itemLink) or itemTypeVector[GetItemLinkItemType(itemLink)] then
    return
  end

  if not Caches.baseProbabilityStats then
    Caches.baseProbabilityStats = MakeDeconstructionStatistic(UpsideKey, UpsideOutcomeKey)
  end
  if not Caches.matProbabilityStats then
    Caches.matProbabilityStats = MakeDeconstructionStatistic(MaterialKey, MaterialOutcomeKey)
  end
  if not Caches.styleProbabilityStats then
    Caches.styleProbabilityStats = MakeDeconstructionStatistic(StyleKey, StyleOutcomeKey)
  end

  local outcome = {}

  local material = Caches.matProbabilityStats:GetValueByKey(MaterialKey(itemLink))
  if material then
    outcome.baseSamples = material.samples
    for _, row in ipairs(material) do
      table.insert(outcome, row)
    end
  end

  local craftingType = GetItemLinkCraftingSkillType(itemLink)
  if not DoesSmithingTypeIgnoreStyleItems(craftingType) then
    local item = GetItemStyleMaterialLink(GetItemLinkItemStyle(itemLink), LINK_STYLE_DEFAULT)
    if item ~= "" then
      local byStyle
      local styleExpectations = Caches.styleProbabilityStats:GetValueByKey(StyleKey(itemLink))
      if styleExpectations and styleExpectations[1] then
        outcome.styleSamples = styleExpectations.samples
        byStyle = styleExpectations[1].expected
      end

      byStyle = byStyle or 0.25
      table.insert(outcome, { item = item, expected = byStyle })
    end
  end

  local expectations = Caches.baseProbabilityStats:GetValueByKey(UpsideKey(itemLink))
  local expectedTypes = {}
  if expectations then
    outcome.qualitySamples = expectations.samples
    for _, row in ipairs(expectations) do
      expectedTypes[row.item] = row.expected
    end
  end

  local functionalQuality = GetItemLinkFunctionalQuality(itemLink)

  if functionalQuality > ITEM_FUNCTIONAL_QUALITY_NORMAL then
    local itemType, scale = 'improvement', 1
    if craftingType == CRAFTING_TYPE_JEWELRYCRAFTING then
      itemType, scale = 'raw_improvement', 0.1
    end

    local byImprovement = expectedTypes[itemType] or 0.9
    table.insert(outcome, { item = GetSmithingImprovementItemLink(craftingType, functionalQuality - 1, LINK_STYLE_DEFAULT), expected = byImprovement * scale })
  end

  local traitType = GetItemLinkTraitType(itemLink)
  if traitType ~= ITEM_TRAIT_TYPE_NONE and
    traitType ~= ITEM_TRAIT_TYPE_ARMOR_INTRICATE and
    traitType ~= ITEM_TRAIT_TYPE_JEWELRY_INTRICATE and
    traitType ~= ITEM_TRAIT_TYPE_WEAPON_INTRICATE  and
    traitType ~= ITEM_TRAIT_TYPE_ARMOR_ORNATE and
    traitType ~= ITEM_TRAIT_TYPE_JEWELRY_ORNATE and
    traitType ~= ITEM_TRAIT_TYPE_WEAPON_ORNATE then

    local itemType, scale = 'trait', 1
    if craftingType == CRAFTING_TYPE_JEWELRYCRAFTING then
      itemType, scale = 'raw_trait', 0.1
    end

    local byTrait = expectedTypes[itemType] or 0.9
    table.insert(outcome, { item = GetSmithingTraitItemLink(traitType + 1, LINK_STYLE_DEFAULT), expected = byTrait * scale })
  end

  if getValue then
    AttachExpectationValues(outcome, getValue)
  end
  return outcome
end

local function GetOutcomeId(outcomeLink)
  if outcomeLink then
    local outcome = string.match(outcomeLink, "^|LLS:out:(%d+)|$")
    if outcome then
      return tonumber(outcome)
    end
  end
end
Analysis.GetOutcomeId = GetOutcomeId

function Caches.LookupOutcome(id)
  local outcome = outcomes[id]
  if not outcome then
    local shallow = LibLootStats.data.outcomes:GetValue(id)
    outcome = {
      id = id,
    }
    for i, pair in ipairs(shallow) do
      outcome[i] = {
        itemId = pair.item,
        item = LibLootStats.data.strings:GetValue(pair.item),
        count = pair.count,
      }
    end
    outcomes[id] = outcome
  end
  return outcome
end

function Caches.LookupScenario(key)
  local scenario = scenarios[key]
  if not scenario then
    scenario = LibLootStats.ParseScenarioKey(key)

    scenario.key = key

    scenario.sourceId = scenario.source
    scenario.source = LibLootStats.data.strings:GetValue(scenario.sourceId)
    local sourceOutcomeId = GetOutcomeId(scenario.source)
    if sourceOutcomeId then
        scenario.sourceOutcomeId = sourceOutcomeId
        scenario.sourceItems = Caches.LookupOutcome(sourceOutcomeId)
    end

    scenario.actionId = scenario.action
    scenario.action = LibLootStats.data.strings:GetValue(scenario.actionId)

    scenario.contextId = scenario.context
    scenario.context = LibLootStats.data.contexts:GetValue(scenario.contextId)

    scenario.outcomeId = scenario.outcome
    scenario.outcome = Caches.LookupOutcome(scenario.outcomeId)

    scenarios[key] = scenario
  end
  return scenario
end
