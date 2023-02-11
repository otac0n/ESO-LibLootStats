local function round(value)
  if value then
    local scale = 1
    local abs = math.abs(value)
    if abs < 1 then
      scale = math.pow(10, math.ceil(math.log10(abs)) - 2)
    elseif abs < 40 then
      scale = 0.1
    end
    return math.floor(value / scale + 0.5) * scale
  end
end

local function AddDeconPrice(tooltip, itemLink)
  local expectation = itemLink and LibLootStats:FindDeconstructionExpectation(itemLink, LibLootStats.Analysis.ItemSaleValue)
  if expectation then
    tooltip:AddVerticalPadding(8)
    tooltip:AddLine("|t20:20:esoui/art/tutorial/inventory_trait_intricate_icon.dds|t Deconstruction Value: " .. (round(expectation.value) or "?") .. " |t18:18:esoui/art/currency/currency_gold_32.dds|t", "ZoFontGameLarge")
    local resultsLine = ""
    for _, pair in ipairs(expectation) do
      if resultsLine ~= "" then
        resultsLine = resultsLine .. ", "
      end
      resultsLine = resultsLine .. pair.item .. "×" .. round(pair.expected)
    end
    if resultsLine ~= "" then
      tooltip:AddLine(resultsLine, "ZoFontGameSmall")
    end
    resultsLine = ""
    if expectation.samples then
      resultsLine = resultsLine .. "Samples: " .. expectation.samples
    end
    if expectation.baseSamples then
      if resultsLine ~= "" then
        resultsLine = resultsLine .. "\n"
      end
      resultsLine = resultsLine .. "Base Samples: " .. expectation.baseSamples
    end
    if expectation.styleSamples then
      if resultsLine ~= "" then
        resultsLine = resultsLine .. "\n"
      end
      resultsLine = resultsLine .. "Style Samples: " .. expectation.styleSamples
    end
    if expectation.qualitySamples then
      if resultsLine ~= "" then
        resultsLine = resultsLine .. "\n"
      end
      resultsLine = resultsLine .. "Quality Samples: " .. expectation.qualitySamples
    end
    if resultsLine ~= "" then
      tooltip:AddLine(resultsLine, "ZoFontGameSmall")
    end
  end
end

EVENT_MANAGER:RegisterForEvent(LibLootStats.ADDON_NAME .. "Tooltips", EVENT_ADD_ON_LOADED, function (eventCode, name)
  EVENT_MANAGER:UnregisterForEvent(LibLootStats.ADDON_NAME .. "Tooltips", EVENT_ADD_ON_LOADED)

  local function HookToolTip(tooltip, name, getItemLink)
    local original = tooltip[name]
    tooltip[name] = function(tooltip, ...)
      original(tooltip, ...)
      local itemLink = getItemLink(...)
      local spacing = false
      spacing = AddDeconPrice(tooltip, itemLink) or spacing
    end
  end

  local identity = function (itemLink) return itemLink end

  HookToolTip(PopupTooltip, "SetLink", identity)

  HookToolTip(ZO_SmithingTopLevelCreationPanelResultTooltip, "SetPendingSmithingItem", GetSmithingPatternResultLink)

  HookToolTip(ItemTooltip, "SetBagItem", GetItemLink)
  HookToolTip(ItemTooltip, "SetWornItem", function (equipSlot) return GetItemLink(BAG_WORN, equipSlot) end)
  HookToolTip(ItemTooltip, "SetLootItem", GetLootItemLink)
  HookToolTip(ItemTooltip, "SetLink", identity)
  HookToolTip(ItemTooltip, "SetAttachedMailItem", GetAttachedItemLink)
  HookToolTip(ItemTooltip, "SetBuybackItem", GetBuybackItemLink)
  HookToolTip(ItemTooltip, "SetTradeItem", GetTradeItemLink)
  HookToolTip(ItemTooltip, "SetStoreItem", GetStoreItemLink)
  HookToolTip(ItemTooltip, "SetQuestReward", GetQuestRewardItemLink)
  HookToolTip(ItemTooltip, "SetTradingHouseListing", GetTradingHouseListingItemLink)

  if AwesomeGuildStore then
    AwesomeGuildStore:RegisterCallback(AwesomeGuildStore.callback.AFTER_INITIAL_SETUP, function ()
      HookToolTip(ItemTooltip, "SetTradingHouseItem", GetTradingHouseSearchResultItemLink)
    end)
  else
    HookToolTip(ItemTooltip, "SetTradingHouseItem", GetTradingHouseSearchResultItemLink)
  end
end)
