local scenarios = {}
local outcomes = {}
local Caches = {
  scenarios = scenarios,
  outcomes = outcomes,
}
LibLootStats.Caches = Caches

local Filter = {}
LibLootStats.Filter = Filter

--- Enumerate all outcomes according to the specified filter functions.
-- @param ... Any number of filter functions.
function LibLootStats:EnumerateScenarios(...)
  local filter = LibLootStats.Filter.And(...)
  for key, count in pairs(LibLootStats.data.scenarios) do
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
LibLootStats.SimilarItemLinkPattern = SimilarItemLinkPattern

function LibLootStats:FindDeconstructionExpectation(itemLink)
  local pattern = SimilarItemLinkPattern(itemLink)
  local samples = 0
  local results = {}
  self:EnumerateScenarios(
    Filter.SourceItems(Filter.All(function (item, count) return string.match(item, pattern) and true or false end)),
    function (scenario, count)
      for _, pair in ipairs(scenario.sourceItems) do
        samples = samples + (pair.count * count)
      end
      for _, pair in ipairs(scenario.outcome) do
        results[pair.item] = (results[pair.item] or 0) + (pair.count * count)
      end
    end
  )
  local expectation = {
    samples = samples
  }
  for item, count in pairs(results) do
    table.insert(expectation, { item = item, count = count / samples })
  end
  return expectation
end

local function GetOutcomeId(outcomeLink)
  if outcomeLink then
    local outcome = string.match(outcomeLink, "^|LLS:out:(%d+)|$")
    if outcome then
      return tonumber(outcome)
    end
  end
end

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

--- Creates a filter that invokes a debug function then returns true.
-- @param debugger The debug function to invoke.
function Filter.Debug(debugger)
  return function(input, count)
    debugger(input, count)
    return true
  end
end

--- Creates a filter that is a conjunction of the specified filters.
-- @param ... Any number of filters.
function Filter.And(...)
  local filters = {...}
  return function(input, count)
    for _, filter in ipairs(filters) do
      if not filter(input, count) then
        return false
      end
    end
    return true
  end
end

--- Creates a filter that is a disjunction of the specified filters.
-- @param ... Any number of filters.
function Filter.Or(...)
  local filters = {...}
  return function(input, count)
    for _, filter in ipairs(filters) do
      if filter(input, count) then
        return true
      end
    end
    return false
  end
end

--- Creates a filter applicable to strings.
-- @param pattern The string match pattern.
function Filter.StringMatch(pattern)
  return function(source)
    return (source and string.match(source, pattern) and true) or false
  end
end

--- Creates a filter applicable to strings.
-- @param pattern The LibTextFilter pattern.
function Filter.LibTextFilter(pattern)
  return function(source)
    return (source and LibTextFilter:Filter(source, pattern) and true) or false
  end
end

--- Applies the provided filter to the action.
-- @param filter The filter to apply to the action.
function Filter.Action(filter)
  return function(scenario)
    return filter(scenario.action)
  end
end

function Filter.ToLower(filter)
  return function(source)
    return filter(source and source:lower())
  end
end

--- Applies the provided filter to the source.
-- @param filter The filter to apply to the source.
function Filter.Source(filter)
  return function(scenario)
    if scenario.sourceItems then return false end
    if string.match(scenario.source, "^|H") then
      return filter(GetItemLinkName(scenario.source))
    else
      return filter(scenario.source)
    end
  end
end

function Filter.SourceItems(filter)
  return function (scenario)
    return scenario.sourceItems and filter(scenario.sourceItems) or false
  end
end

function Filter.OutcomeItems(filter)
  return function (scenario)
    return filter(scenario.outcome)
  end
end

function Filter.AnySourceItem(filter)
  local inner = Filter.Any(filter)
  return function (scenario)
    return inner(scenario.sourceItems)
  end
end

function Filter.AnyOutcomeItem(filter)
  local inner = Filter.Any(filter)
  return function (scenario)
    return inner(scenario.outcome)
  end
end

function Filter.Any(itemFilter)
  return function (items)
    if items then
      for _, row in ipairs(items) do
        if itemFilter(row.item, row.count) then
          return true
        end
      end
    end
    return false
  end
end

function Filter.All(itemFilter)
  return function (items)
    if items then
      for _, row in ipairs(items) do
        if not itemFilter(row.item, row.count) then
          return false
        end
      end
    end
    return true
  end
end

function Filter.ItemName(filter)
  return function(row, count)
    return filter(GetItemLinkName(row.item))
  end
end

function Filter.AnyTextField(filter)
  return Filter.Or(
    Filter.Source(filter),
    Filter.AnySourceItem(Filter.ItemName(filter)),
    Filter.Action(filter),
    Filter.AnyOutcomeItem(Filter.ItemName(filter))
  )
end
