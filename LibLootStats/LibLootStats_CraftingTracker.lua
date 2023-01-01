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
  local bag = self.pending[bagId]
  if not bag then
    bag = {}
    self.pending[bagId] = bag
  end
  bag[slotIndex] = (bag[slotIndex] or 0) + quantity
end

function CraftingTracker:SendDeconstructMessage()
  local sourceGroup = {}
  for bagId, bag in pairs(self.pending) do
    for slotIndex, count in pairs(bag) do
      table.insert(sourceGroup, { item = GetItemLink(bagId, slotIndex), count = count })
    end
  end

  local scenario = {
    source = "|LLS:out:" .. tostring(LibLootStats:GetOutcomeId(sourceGroup)) .. "|",
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
