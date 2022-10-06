local localizedStrings = {
  ["en"] = {
    COLLECTION_SETTINGS = "Collection Settings",
  },
}

function LibLootStats:GetStrings()
  local lang = GetCVar("language.2")
  return localizedStrings[lang]
end
