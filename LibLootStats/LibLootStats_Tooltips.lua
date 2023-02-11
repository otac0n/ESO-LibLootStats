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
    local value = expectation.value
    local color = "|cffffff"
    if value < LibLootStats.Analysis.ItemVendorValue(itemLink) then
      color = "|cff0000"
    else
      local price = LibPrice and LibPrice.ItemLinkToBidAskSpread and LibPrice.ItemLinkToBidAskSpread(itemLink).gold
      if price then
        local bid = price.bid and price.bid.value
        local sale = price.sale and price.sale.value
        local ask = price.ask and price.ask.value
        if ask and ask < value then
          color = "|c00ee11"
        elseif sale and sale < value then
          color = "|cffff00"
        elseif sale and sale > value then
          color = "|cff8800"
        end
      end
    end
    tooltip:AddLine("|t20:20:esoui/art/tutorial/inventory_trait_intricate_icon.dds|t Deconstruction Value: " .. color .. (round(value) or "?") .. "|r |t18:18:esoui/art/currency/currency_gold_32.dds|t", "ZoFontGameLarge")
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

local roleLabels = {
  ['Thief'] = '|cccccccThief|r',
  ['Speed'] = '|ccccc00Speed|r',
  ['Farming'] = '|c00cc00Farming|r',
}

local function AddSetScores(tooltip, itemLink)
  local s = itemLink and LibLootStats.Analysis.FindItemLinkSetRoleScores(itemLink)
  if s.scores then
    local resultsLine = ""
    local q = s.unmatched and "?" or ""
    local scores = {}
    for role, score in pairs(s.scores) do
      table.insert(scores, { role = role, score = score })
    end
    table.sort(scores, function (a, b) return a.score > b.score end)
    for _, s in ipairs(scores) do
      if resultsLine ~= "" then
        resultsLine = resultsLine .. "\n"
      end
      resultsLine = resultsLine .. (roleLabels[s.role] or s.role) .. ": " .. round(s.score) .. q
    end
    tooltip:AddLine(resultsLine, "ZoFontGameSmall")
    return true
  end
end

local function AddSources(tooltip, itemLink)
  local s = itemLink and LibLootStats.Analysis.FindItemLinkSources(itemLink)
  if s then
    local resultsLine = ""
    local total = 0
    local list = {}
    for action, items in pairs(s) do
      for item, count in pairs(items) do
        total = total + count
        table.insert(list, { action = action, item = item, count = count })
      end
    end
    table.sort(list, function (a, b) return a.count > b.count end)
    total = total / 100
    local lines = 0
    for _, pair in ipairs(list) do
      if resultsLine ~= "" then
        resultsLine = resultsLine .. "\n"
        lines = lines + 1
      end
      if lines >= 9 then
        resultsLine = resultsLine .. "…"
        break
      end
      resultsLine = resultsLine .. round(pair.count / total) .. "% " .. pair.item .. " (" .. pair.action .. ") - " .. round(pair.count)
    end
    tooltip:AddLine(resultsLine, "ZoFontGameSmall")
    return true
  end
end

local function AddBidAskSpread(tooltip, itemLink)
  local price = itemLink and LibPrice and LibPrice.ItemLinkToBidAskSpread and LibPrice.ItemLinkToBidAskSpread(itemLink).gold
  if price then
    local resultsLine = ""
    local bid = price.bid and price.bid.value
    local sale = price.sale and price.sale.value
    local ask = price.ask and price.ask.value
    if bid then
      resultsLine = resultsLine .. "Bid: " .. round(bid) .. " |t18:18:esoui/art/currency/currency_gold_32.dds|t"
    end
    if sale then
      if resultsLine ~= "" then
        resultsLine = resultsLine .. ", "
      end
      resultsLine = resultsLine .. "Sale: " .. round(sale) .. " |t18:18:esoui/art/currency/currency_gold_32.dds|t"
    end
    if ask then
      if resultsLine ~= "" then
        resultsLine = resultsLine .. ", "
      end
      resultsLine = resultsLine .. "Ask: " .. round(ask) .. " |t18:18:esoui/art/currency/currency_gold_32.dds|t"
    end
    if resultsLine ~= "" then
      tooltip:AddLine(resultsLine, "ZoFontGameLarge")
      return true
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
      spacing = AddBidAskSpread(tooltip, itemLink) or spacing
      if spacing then tooltip:AddVerticalPadding(8) end
      spacing = AddDeconPrice(tooltip, itemLink) or spacing
      if spacing then tooltip:AddVerticalPadding(8) end
      spacing = AddSources(tooltip, itemLink) or spacing
      if spacing then tooltip:AddVerticalPadding(8) end
      spacing = AddSetScores(tooltip, itemLink) or spacing
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
