local CraftingTracker = {
  pending = nil,
  sent = nil
}
LibLootStats.craftingTracker = CraftingTracker

function CraftingTracker:InitializeHooks()
  local namespace = LibLootStats.ADDON_NAME .. "CraftingTracker"
  ZO_PreHook("PrepareDeconstructMessage", LibLootStats.utils.Bind(self, self.PrepareDeconstructMessage))
  ZO_PreHook("AddItemToDeconstructMessage", LibLootStats.utils.Bind(self, self.AddItemToDeconstructMessage))
  ZO_PreHook("SendDeconstructMessage", LibLootStats.utils.Bind(self, self.SendDeconstructMessage))
  EVENT_MANAGER:RegisterForEvent(namespace, EVENT_CRAFT_COMPLETED, LibLootStats.utils.Bind(self, self.OnCraftCompleted))
end

function CraftingTracker:PrepareDeconstructMessage()
  self.sent = nil
  self.pending = {}
end

function CraftingTracker:AddItemToDeconstructMessage(bagId, slotIndex, quantity)
  table.insert(self.pending, { bagId = bagId, slotIndex = slotIndex, count = quantity })
end

function CraftingTracker:SendDeconstructMessage()
  local sourceGroup = {}
  local indexLookup = {}
  for _, item in ipairs(self.pending) do
    local key = tostring(item.bagId) .. ',' .. tostring(item.slotIndex)
    local index = indexLookup[key]
    if index then
      sourceGroup[index].count = (sourceGroup[index].count or 0) + item.count
    else
      table.insert(sourceGroup, { item = GetItemLink(item.bagId, item.slotIndex), count = item.count })
      indexLookup[key] = #sourceGroup
    end
  end

  local maintainOrder = true
  local scenario = {
    source = "|LLS:out:" .. tostring(LibLootStats:GetOutcomeId(sourceGroup, maintainOrder)) .. "|",
    action = GetString(SI_INTERACT_OPTION_UNIVERSAL_DECONSTRUCTION),
    context = self:GetContext(),
  }
  self.sent = {
    scenario = scenario,
    sourceGroup = sourceGroup,
    activeSource = LibLootStats.activeSources:AddNamedSource("Deconstruct", scenario),
  }

  self.pending = nil
end

function CraftingTracker:OnCraftCompleted()
  local sent = self.sent
  if sent and sent.activeSource then
    LibLootStats.activeSources:RemoveSource(sent.activeSource)
  end

  self.sent = nil
end

local extract = {
  cloth = NON_COMBAT_BONUS_CLOTHIER_EXTRACT_LEVEL,
  smith = NON_COMBAT_BONUS_BLACKSMITHING_EXTRACT_LEVEL,
  wood = NON_COMBAT_BONUS_WOODWORKING_EXTRACT_LEVEL,
  enchant = NON_COMBAT_BONUS_ENCHANTING_DECONSTRUCTION_UPGRADE,
  jewel = NON_COMBAT_BONUS_JEWELRYCRAFTING_EXTRACT_LEVEL,
}
function CraftingTracker:GetContext()
  local context = {
    meticulous = LibLootStats.SkillPointLevel(83),
  }
  for k,v in pairs(extract) do
    local bonus = GetNonCombatBonus(v)
    if bonus > 0 then
      context[k] = bonus
    end
  end
  return context
end
