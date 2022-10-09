local activeSources = {
  sources = {}
}
LibLootStats.activeSources = activeSources

function activeSources:AddSource(source)
  table.insert(self.sources, 1, source)
  if source.items and #source.items == 0 then
    LibLootStats.logger:Warn("Added source with empty item list.")
  end
end

local transientId = 1
function activeSources:AddTransientSource(name, scenario, options)
  LibLootStats.logger:Debug("AddTransientSource(name: " , name, ", source: " , scenario.source, ", action: " , scenario.action, ")")
  local source = {
    name = name,
    scenario = scenario,
  }

  local namespace = LibLootStats.ADDON_NAME .. ".TransientSource." .. transientId
  transientId = transientId + 1
  source.remove = function() EVENT_MANAGER:UnregisterForUpdate(namespace) end

  if options then
    source.items = options.items
  end

  self:AddSource(source)
  EVENT_MANAGER:RegisterForUpdate(namespace, (options and options.delay) or 0, function()
    self:RemoveSource(source)
  end)
  return source
end

function activeSources:FindBestSource(item, count)
  if not item or not count then
    LibLootStats.logger:Warn("FindBestSource(item: ", item, ", count: ", count, "): item and count are required.")
  end

  for i = 1, #self.sources do
    local source = self.sources[i]
    local match = false
    if not source.items then
      match = true
    else
      local remaining = #source.items
      for j = 1, remaining do
        local pair = source.items[j]
        if pair.item == item and pair.count == count then
          match = true
          table.remove(source.items, j)
          if remaining == 1 then
            self:RemoveSource(source)
          end
          break
        end
      end
    end

    if match then
      return source
    end
  end
end

function activeSources:RemoveSource(source)
  LibLootStats.logger:Debug("RemoveSource(source: ", source, ")")
  for i = 1, #self.sources do
    if self.sources[i] == source then
      table.remove(self.sources, i)
      if source.items and #source.items ~= 0 then
        LibLootStats.logger:Warn("Removed source with non-empty item list.")
      end
      if source.remove then
        source.remove()
        source.remove = nil
      end
      return
    end
  end
end
