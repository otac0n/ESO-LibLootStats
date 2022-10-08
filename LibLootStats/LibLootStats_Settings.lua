LibLootStats.variableVersion = 1

local defaultCollectionVars = {
}

local function MakeLookup(source, toKey)
  local lookup = {
    forward = {},
    reverse = source,
  }

  if toKey then
    for k, v in ipairs(source) do
      local key = toKey(v)
      lookup.forward[key] = k
      lookup.reverse[k] = v
    end

    function lookup:GetId(item)
      if item == nil then return 0 end
      local key = toKey(item)
      local id = self.forward[key]
      if id == nil then
        id = #self.reverse + 1
        self.forward[key] = id
        self.reverse[id] = item
      end
      return id
    end
  else
    for k, v in ipairs(source) do
      lookup.forward[v] = k
      lookup.reverse[k] = v
    end

    function lookup:GetId(item)
      if item == nil then return 0 end
      local id = self.forward[item]
      if id == nil then
        id = #self.reverse + 1
        self.forward[item] = id
        self.reverse[id] = item
      end
      return id
    end
  end

  function lookup:GetValue(id)
    return self.reverse[id]
  end

  return lookup
end

function LibLootStats:InitializeSettings()
  LibLootStats.collectionVars = LibSavedVars
    :NewAccountWide(LibLootStats.ADDON_NAME.."_Settings", "Collection_Account", defaultCollectionVars)
    :AddCharacterSettingsToggle(LibLootStats.ADDON_NAME.."_Settings", "Collection_Character")
    :EnableDefaultsTrimming()
  local strings = ZO_SavedVars:NewAccountWide(LibLootStats.ADDON_NAME.."_Strings", 1, nil, { lookup = {} })
  local contexts = ZO_SavedVars:NewAccountWide(LibLootStats.ADDON_NAME.."_Contexts", 1, nil, { lookup = {} })
  local outcomes = ZO_SavedVars:NewAccountWide(LibLootStats.ADDON_NAME.."_Outcomes", 1, nil, { lookup = {} })
  local scenarios = ZO_SavedVars:NewAccountWide(LibLootStats.ADDON_NAME.."_Scenarios", 1, nil, { lookup = {} })
  self.data = {
    strings = MakeLookup(strings.lookup),
    contexts = MakeLookup(contexts.lookup, self.ContextToKey),
    outcomes = MakeLookup(outcomes.lookup, self.OutcomeToKey),
    scenarios = MakeLookup(scenarios.lookup, self.ScenarioToKey),
  }
end
