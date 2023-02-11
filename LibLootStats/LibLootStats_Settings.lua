LibLootStats.variableVersion = 1

local defaultCollectionVars = {
}

local function MakeLookup(source, toKey, fromKey)
  local lookup = {
    itemToId = {},
    idToItem = source,
  }

  if toKey then
    if fromKey then
      lookup.idToItem = {}
      lookup.source = source
      for id, key in pairs(source) do
        local item = fromKey(key)
        lookup.itemToId[key] = id
        lookup.idToItem[id] = item
      end
  
      function lookup:GetId(item)
        if item == nil then return 0 end
        local key = toKey(item)
        local id = self.itemToId[key]
        if id == nil then
          id = #self.idToItem + 1
          self.itemToId[key] = id
          self.idToItem[id] = item
          source[id] = key
        end
        return id
      end
    else
      for id, item in pairs(source) do
        local key = toKey(item)
        lookup.itemToId[key] = id
      end
  
      function lookup:GetId(item)
        if item == nil then return 0 end
        local key = toKey(item)
        local id = self.itemToId[key]
        if id == nil then
          id = #self.idToItem + 1
          self.itemToId[key] = id
          self.idToItem[id] = item
        end
        return id
      end
    end
  else
    for id, item in pairs(source) do
      lookup.itemToId[item] = id
    end

    function lookup:GetId(item)
      if item == nil then return 0 end
      local id = self.itemToId[item]
      if id == nil then
        id = #self.idToItem + 1
        self.itemToId[item] = id
        self.idToItem[id] = item
      end
      return id
    end
  end

  function lookup:GetValue(id)
    return self.idToItem[id]
  end

  return lookup
end

function MakeQuantityStore(source, toKey, fromKey)
  local store = {
    keyToCount = source,
    statistics = {},
  }

  function store:AddStatistic(groupKey, makeValue, accumulate, makeResult)
    local statistic = {
      cache = {},
      GroupKey = groupKey,
    }

    makeResult = makeResult or function (a) return a end

    function statistic:Increment(scenarioKey, count)
      local groupKeys = groupKey(scenarioKey)
      if type(groupKeys) ~= 'table' then groupKeys = {groupKeys} end
      for _, groupKey in ipairs(groupKeys) do
        if groupKey ~= nil then
          local newValue = makeValue(scenarioKey, count, groupKey)
          local current = self.cache[groupKey]
          if current then
            self.cache[groupKey] = accumulate(current, newValue)
          else
            self.cache[groupKey] = newValue
          end
        end
      end
    end

    function statistic:GetValueByKey(groupKey)
      local current = self.cache[groupKey]
      if current then
        return makeResult(current)
      end
    end

    table.insert(self.statistics, statistic)

    for scenarioKey, count in pairs(self.keyToCount) do
      statistic:Increment(scenarioKey, count)
    end

    return statistic
  end

  function store:Count(scenario)
    local key = toKey(scenario)
    local saved = self.keyToCount[key]
    return saved or 0
  end

  function store:IncrementScenario(scenario, count)
    count = count or 1
    local key = toKey(scenario)
    local saved = self.keyToCount[key]
    self.keyToCount[key] = (saved or 0) + count
    for _, statistic in ipairs(self.statistics) do
      statistic:Increment(key, count)
    end
  end

  return store
end

local ui
function LibLootStats:InitializeSettings()
  LibLootStats.collectionVars = LibSavedVars
    :NewAccountWide(LibLootStats.ADDON_NAME.."_Settings", "Collection_Account", defaultCollectionVars)
    :AddCharacterSettingsToggle(LibLootStats.ADDON_NAME.."_Settings", "Collection_Character")
    :EnableDefaultsTrimming()
  ui = ZO_SavedVars:NewAccountWide(LibLootStats.ADDON_NAME.."_UI", 1, nil, { window = "" })
  local strings = ZO_SavedVars:NewAccountWide(LibLootStats.ADDON_NAME.."_Strings", 1, nil, { lookup = {} })
  local contexts = ZO_SavedVars:NewAccountWide(LibLootStats.ADDON_NAME.."_Contexts", 1, nil, { lookup = {} })
  local outcomes = ZO_SavedVars:NewAccountWide(LibLootStats.ADDON_NAME.."_Outcomes", 1, nil, { lookup = {} })
  local scenarios = ZO_SavedVars:NewAccountWide(LibLootStats.ADDON_NAME.."_Scenarios", 1, nil, { data = {} })
  self.data = {
    strings = MakeLookup(strings.lookup),
    contexts = MakeLookup(contexts.lookup, self.ContextToKey, self.ParseContextKey),
    outcomes = MakeLookup(outcomes.lookup, self.OutcomeToKey, self.ParseOutcomeKey),
  }
  self.data.scenarios = MakeQuantityStore(scenarios.data, self.ScenarioToKey, self.ParseScenarioKey)
  LibLootStats:ApplyUISettings()
end

local function LoadControlPosition(ctl, settings)
  local w, h, l, t = string.match(settings or "", "^(%d*%.?%d+)%*(%d*%.?%d+)%@(-?%d*%.?%d+)%,(-?%d*%.?%d+)$")
  ctl:SetWidth(tonumber(w))
  ctl:SetHeight(tonumber(h))
  ctl:SetAnchorOffsets(tonumber(l), tonumber(t))
end

local function SaveControlPosition(ctl)
  local w, h = ctl:GetWidth(), ctl:GetHeight()
  local l, t = ctl:GetLeft(), ctl:GetTop()
  return w .. "*" .. h .. "@" .. l .. "," .. t
end

function LibLootStats:ApplyUISettings()
  LoadControlPosition(LootStatsWindow, ui.window)
end

function LibLootStats:SaveUISettings()
  ui.window = SaveControlPosition(LootStatsWindow)
end
