local ReticleTracker = {
  lastTarget = nil,
  tracksLootWindow = true,
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
  if shouldBeActive and newState == SCENE_SHOWING and not (scene == HUD_SCENE or scene == HUD_UI_SCENE or scene == LOCK_PICK_SCENE or scene == LOCK_PICK_GAMEPAD_SCENE or scene.name == ZO_INTERACTION_SYSTEM_NAME or (tracksLootWindow and scene == LOOT_SCENE)) then
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
      LibLootStats.logger:Debug("Closing previous reticle target: ", self.lastTarget.interactableName, "(", self.lastTarget.interaction, ") ~= ", newTarget.interactableName, "(", newTarget.interaction, ")")
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

  local fishingLure
  if additionalInteractInfo == ADDITIONAL_INTERACT_INFO_FISHING_NODE then
    fishingLure = GetFishingLure()
  end

  local antiquity
  if additionalInteractInfo == ADDITIONAL_INTERACT_INFO_NONE and interaction == GetString("SI_GAMECAMERAACTIONTYPE", 27) then
    antiquity = GetTrackedAntiquityId()
  end

  local socialClass, blockedReason
  if additionalInteractInfo == ADDITIONAL_INTERACT_INFO_PICKPOCKET_CHANCE then
    local isInBonus, isHostile, percentChance, difficulty, isEmpty, prospectiveResult, monsterSocialClassString, monsterSocialClass = GetGameCameraPickpocketingBonusInfo()
    socialClass = monsterSocialClassString
    if interactionBlocked then
      if isEmpty and prospectiveResult ~= PROSPECTIVE_PICKPOCKET_RESULT_CAN_ATTEMPT then
        blockedReason = GetString(SI_JUSTICE_PICKPOCKET_TARGET_EMPTY)
      else
        blockedReason = GetString("SI_PROSPECTIVEPICKPOCKETRESULT", prospectiveResult)
      end
    end
  end

  if interactionBlocked and blockedReason == nil then
    if additionalInteractInfo == ADDITIONAL_INTERACT_INFO_EMPTY then
      blockedReason = GetString(SI_GAME_CAMERA_ACTION_EMPTY)
    elseif IsPlayerMoving() then
      blockedReason = GetString(SI_KEYBINDINGS_CATEGORY_MOVEMENT)
    end
  end

  local lockQuality
  if additionalInteractInfo == ADDITIONAL_INTERACT_INFO_LOCKED then
    lockQuality = GetString("SI_LOCKQUALITY", context)
  end

  return {
    interactableName = interactableName,
    questInteraction = questInteraction,
    interaction = interaction,
    interactionBlocked = interactionBlocked,
    blockedReason = blockedReason,
    additionalInteractInfo = additionalInteractInfo,
    questToolName = questToolName,
    fishingLure = fishingLure,
    antiquity = antiquity,
    socialClass = socialClass,
    lockQuality = lockQuality
  }
end

function ReticleTracker:TargetsMatch(a, b)
  return a.interactableName == b.interactableName and a.questInteraction == b.questInteraction and not (a.additionalInteractInfo == ADDITIONAL_INTERACT_INFO_EMPTY and b.additionalInteractInfo == ADDITIONAL_INTERACT_INFO_NONE)
end

function ReticleTracker:AfterReticleUpdate()
  if not shouldBeActive and self.lastTarget and self.lastTarget.active then
    LibLootStats.logger:Debug("Closing previous reticle target: ", self.lastTarget.interactableName, "(", self.lastTarget.interaction, ") hidden")
    self:CloseTarget()
  end
end

function ReticleTracker:ReacquireOrInstallTarget(newTarget)
  if self.lastTarget and self:TargetsMatch(self.lastTarget, newTarget) then
    if not self.lastTarget.active then
      LibLootStats.logger:Debug("Reacquired reticle target: ", self.lastTarget.interactableName, "(", self.lastTarget.interaction, ")")
      self.lastTarget.active = true
    end
    return self.lastTarget
  else
    LibLootStats.logger:Debug("Installed new reticle target: ", newTarget.interactableName, "(", newTarget.interaction, ")")
    newTarget.active = true
    table.insert(self.recentTargets, newTarget)
    self.lastTarget = newTarget
    return nil
  end
end

function ReticleTracker:UpdateTarget(destination, source)
  if destination.interaction ~= source.interaction then
    if destination.additionalInteractInfo == ADDITIONAL_INTERACT_INFO_LOCKED and source.additionalInteractInfo == ADDITIONAL_INTERACT_INFO_NONE then
      -- Save the original the interaction.
      LibLootStats.logger:Debug("originalInteraction: ", destination.interaction)
      destination.originalInteraction = destination.interaction
    end
    LibLootStats.logger:Debug("interaction: ", destination.interaction, " => ", source.interaction)
    destination.interaction = source.interaction
  end

  if destination.interactionBlocked ~= source.interactionBlocked then
    LibLootStats.logger:Debug("interactionBlocked: ", destination.interactionBlocked, " => ", source.interactionBlocked)
    destination.interactionBlocked = source.interactionBlocked
  end

  if destination.blockedReason ~= source.blockedReason then
    LibLootStats.logger:Debug("blockedReason: ", destination.blockedReason, " => ", source.blockedReason)
    destination.blockedReason = source.blockedReason
  end

  if destination.antiquity ~= source.antiquity then
    destination.antiquity = source.antiquity
  end

  if (destination.additionalInteractInfo == ADDITIONAL_INTERACT_INFO_FISHING_NODE and source.additionalInteractInfo == ADDITIONAL_INTERACT_INFO_NONE) then
    -- Keep the additionalInteractInfo the same.
  else
    if destination.additionalInteractInfo ~= source.additionalInteractInfo then
      LibLootStats.logger:Debug("additionalInteractInfo: ", destination.additionalInteractInfo, " => ", source.additionalInteractInfo)
      destination.additionalInteractInfo = source.additionalInteractInfo
    end
  end

  if destination.fishingLure ~= nil and source.fishingLure == nil then
    -- Don't overwrite the bait with nil.
  else
    if destination.fishingLure ~= source.fishingLure then
      LibLootStats.logger:Debug("fishingLure: ", destination.fishingLure, " => ", source.fishingLure)
      destination.fishingLure = source.fishingLure
    end
  end

  if destination.lockQuality ~= nil and source.lockQuality == nil then
    -- Don't overwrite the lock quality with nil.
  else
    if destination.lockQuality ~= source.lockQuality then
      LibLootStats.logger:Debug("lockQuality: ", destination.lockQuality, " => ", source.lockQuality)
      destination.lockQuality = source.lockQuality
    end
  end

  if destination.questToolName ~= source.questToolName then
    LibLootStats.logger:Debug("questToolName: ", destination.questToolName, " => ", source.questToolName)
    destination.questToolName = source.questToolName
  end

  if destination.socialClass ~= source.socialClass then
    LibLootStats.logger:Debug("socialClass: ", destination.socialClass, " => ", source.socialClass)
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
