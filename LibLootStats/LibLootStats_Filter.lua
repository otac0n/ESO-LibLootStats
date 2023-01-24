local Filter = {}
LibLootStats.Filter = Filter

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
