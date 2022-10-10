local ReticleTracker = {
  lastTarget = nil,
  recentTargets = {
  }
}
LibLootStats.reticleTracker = ReticleTracker

local afterReticleUpdateClosure
function ReticleTracker:InitializeHooks()
  ZO_PreHookHandler(RETICLE.interact, "OnEffectivelyShown", LibLootStats.utils.Closure(self, self.ReticleShown))
  ZO_PreHookHandler(RETICLE.interact, "OnHide", LibLootStats.utils.Closure(self, self.ReticleHidden))
  SecurePostHook(RETICLE, "UpdateInteractText", LibLootStats.utils.Closure(self, self.AfterReticleUpdate))
  ZO_PreHook(SCENE_MANAGER, "OnSceneStateChange", LibLootStats.utils.Closure(self, self.OnSceneStateChanged))
end

local shouldBeActive = false
function ReticleTracker:ReticleHidden()
  shouldBeActive = false
end

function ReticleTracker:OnSceneStateChanged(scene, oldState, newState)
  if shouldBeActive and newState == SCENE_SHOWING and not (scene == HUD_SCENE or scene == HUD_UI_SCENE or scene.name == ZO_INTERACTION_SYSTEM_NAME or scene == LOOT_SCENE) then
    shouldBeActive = false
    self:AfterReticleUpdate()
  end
end

function ReticleTracker:ReticleShown()
  local newTarget = self:CreateCurrentTarget()
  if newTarget then
    shouldBeActive = true
  else
    shouldBeActive = false
    return
  end

  if self.lastTarget and self.lastTarget.active then
    if not self:TargetsMatch(self.lastTarget, newTarget) then
      LibLootStats.logger:Verbose("Closing previous reticle target: ", self.lastTarget.interactableName, "(", self.lastTarget.interaction, ") ~= ", newTarget.interactableName, "(", newTarget.interaction, ")")
      self:CloseTarget()
    end
  end

  local needsUpdate
  if not self.lastTarget or not self.lastTarget.active then
    needsUpdate = self:ReacquireOrInstallTarget(newTarget)
  else
    needsUpdate = self.lastTarget
  end

  if needsUpdate then
    self:UpdateTarget(needsUpdate, newTarget)
  end
end

function ReticleTracker:CreateCurrentTarget()
  local interaction, interactableName, interactionBlocked, isOwned, additionalInteractInfo, context, contextLink, isCriminalInteract = GetGameCameraInteractableActionInfo()
  if not interactableName then return nil end
  local interactionExists, interactionAvailableNow, questInteraction, questTargetBased, questJournalIndex, questToolIndex, questToolOnCooldown = GetGameCameraInteractableInfo()
  local questToolIcon, stack, _, questToolName, questItemId
  if questInteraction then
    questToolIcon, stack, _, questToolName, questItemId = GetQuestToolInfo(questJournalIndex, questToolIndex)
  end

  local fishingLure, socialClass
  if additionalInteractInfo == ADDITIONAL_INTERACT_INFO_FISHING_NODE then
    fishingLure = GetFishingLure()
  else
    fishingLure = nil
  end

  local socialClass
  if additionalInteractInfo == ADDITIONAL_INTERACT_INFO_PICKPOCKET_CHANCE then
    local isInBonus, isHostile, percentChance, difficulty, isEmpty, prospectiveResult, monsterSocialClassString, monsterSocialClass = GetGameCameraPickpocketingBonusInfo()
    socialClass = monsterSocialClassString
  else
    socialClass = nil
  end

  return {
    interactableName = interactableName,
    questInteraction = questInteraction,
    interaction = interaction,
    interactionBlocked = interactionBlocked,
    additionalInteractInfo = additionalInteractInfo,
    questToolName = questToolName,
    fishingLure = fishingLure,
    socialClass = socialClass,
  }
end

function ReticleTracker:TargetsMatch(a, b)
  return a.interactableName == b.interactableName and a.questInteraction == b.questInteraction and not (a.additionalInteractInfo == ADDITIONAL_INTERACT_INFO_EMPTY and b.additionalInteractInfo == ADDITIONAL_INTERACT_INFO_NONE)
end

function ReticleTracker:AfterReticleUpdate()
  if not shouldBeActive and self.lastTarget and self.lastTarget.active then
    LibLootStats.logger:Verbose("Closing previous reticle target: ", self.lastTarget.interactableName, "(", self.lastTarget.interaction, ") hidden")
    self:CloseTarget()
  end
end

function ReticleTracker:ReacquireOrInstallTarget(newTarget)
  if self.lastTarget and self:TargetsMatch(self.lastTarget, newTarget) then
    if not self.lastTarget.active then
      LibLootStats.logger:Verbose("Reacquired reticle target: ", self.lastTarget.interactableName, "(", self.lastTarget.interaction, ")")
      self.lastTarget.active = true
    end
    return self.lastTarget
  else
    LibLootStats.logger:Verbose("Installed new reticle target: ", newTarget.interactableName, "(", newTarget.interaction, ")")
    newTarget.active = true
    table.insert(self.recentTargets, newTarget)
    self.lastTarget = newTarget
    return nil
  end
end

function ReticleTracker:UpdateTarget(destination, source)
  if destination.interaction ~= source.interaction then
    LibLootStats.logger:Verbose("interaction: ", destination.interaction, " => ", source.interaction)
    destination.interaction = source.interaction
  end

  if destination.interactionBlocked ~= source.interactionBlocked then
    LibLootStats.logger:Verbose("interactionBlocked: ", destination.interactionBlocked, " => ", source.interactionBlocked)
    destination.interactionBlocked = source.interactionBlocked
  end

  if destination.additionalInteractInfo == ADDITIONAL_INTERACT_INFO_FISHING_NODE and source.additionalInteractInfo == ADDITIONAL_INTERACT_INFO_NONE then
    -- Keep the additionalInteractInfo the same.
  else
    if destination.additionalInteractInfo ~= source.additionalInteractInfo then
      LibLootStats.logger:Verbose("additionalInteractInfo: ", destination.additionalInteractInfo, " => ", source.additionalInteractInfo)
      destination.additionalInteractInfo = source.additionalInteractInfo
    end
  end

  if destination.additionalInteractInfo == ADDITIONAL_INTERACT_INFO_FISHING_NODE and source.additionalInteractInfo == ADDITIONAL_INTERACT_INFO_NONE and source.fishingLure == nil then
    -- Don't overwrite the bait with nil.
  else
    if destination.fishingLure ~= source.fishingLure then
      LibLootStats.logger:Verbose("fishingLure: ", destination.fishingLure, " => ", source.fishingLure)
      destination.fishingLure = source.fishingLure
    end
  end

  if destination.questToolName ~= source.questToolName then
    LibLootStats.logger:Verbose("questToolName: ", destination.questToolName, " => ", source.questToolName)
    destination.questToolName = source.questToolName
  end

  if destination.socialClass ~= source.socialClass then
    LibLootStats.logger:Verbose("socialClass: ", destination.socialClass, " => ", source.socialClass)
    destination.socialClass = source.socialClass
  end
end

function ReticleTracker:CloseTarget()
  if self.lastTarget then
    if self.lastTarget.active then
      self.lastTarget.active = false
    else
      LibLootStats.logger:Warn("Last reticle target was already closed.")
    end
  else
    LibLootStats.logger:Warn("No reticle target to close.")
  end
end
