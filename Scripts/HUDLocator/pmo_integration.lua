-- Mod Options Framework Integration for HUDLocator
local configMod = require("HUDLocator.config")

local M = {}
M.pmoClient = nil
M.currentGeneration = -1

local function FormatPalTrackerList(trackerPals)
    if type(trackerPals) ~= "table" then return "" end
    local list = {}
    for _, item in ipairs(trackerPals) do
        if type(item) == "string" and item ~= "" then
            table.insert(list, item)
        elseif type(item) == "table" then
            local pName = item.palname
            if not pName or pName == "" then pName = "*" end

            local parts = {}
            if item.passive and type(item.passive) == "table" and type(item.passive.passives) == "table" and #item.passive.passives > 0 then
                local pListStr = table.concat(item.passive.passives, "/")
                local thresh = item.passive.min_passive_threshold
                if thresh and thresh > 1 then
                    pListStr = pListStr .. "[" .. tostring(thresh) .. "]"
                end
                table.insert(parts, pListStr)
            end

            if item.shiny == true then
                table.insert(parts, "Shiny")
            end
            if item.boss == true then
                table.insert(parts, "Boss")
            end

            if #parts > 0 then
                table.insert(list, pName .. ":" .. table.concat(parts, ":"))
            else
                table.insert(list, pName)
            end
        end
    end
    return table.concat(list, ", ")
end

local function ParsePalTrackerList(str, existingTrackerPals)
    local newTokensList = {}
    if type(str) == "string" then
        for item in string.gmatch(str, "([^,]+)") do
            local trimmed = item:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then
                table.insert(newTokensList, trimmed)
            end
        end
    end

    local existingMap = {}
    if type(existingTrackerPals) == "table" then
        for _, rule in ipairs(existingTrackerPals) do
            if type(rule) == "table" then
                local key = (rule.palname and rule.palname ~= "") and rule.palname:lower() or "*"
                existingMap[key] = rule
            elseif type(rule) == "string" and rule ~= "" then
                existingMap[rule:lower()] = { palname = rule }
            end
        end
    end

    local result = {}
    for _, token in ipairs(newTokensList) do
        if string.find(token, ":") then
            local colonParts = {}
            for segment in string.gmatch(token, "([^:]+)") do
                local sTrimmed = segment:match("^%s*(.-)%s*$")
                if sTrimmed and sTrimmed ~= "" then
                    table.insert(colonParts, sTrimmed)
                end
            end

            local pName = "*"
            local startIdx = 1
            if not token:match("^%s*:") and #colonParts > 0 then
                pName = colonParts[1]
                startIdx = 2
            end

            local rule = { palname = pName }

            for i = startIdx, #colonParts do
                local sub = colonParts[i]
                local subLower = sub:lower()
                if subLower == "shiny" then
                    rule.shiny = true
                elseif subLower == "boss" or subLower == "alpha" then
                    rule.boss = true
                else
                    local threshold = sub:match("%[(%d+)%]")
                    local cleanSub = sub:gsub("%[%d+%]", "")
                    local passives = {}
                    for p in string.gmatch(cleanSub, "([^/%+|]+)") do
                        local pTrimmed = p:match("^%s*(.-)%s*$")
                        if pTrimmed and pTrimmed ~= "" then
                            table.insert(passives, pTrimmed)
                        end
                    end
                    if #passives > 0 then
                        rule.passive = {
                            passives = passives,
                            min_passive_threshold = tonumber(threshold) or 1
                        }
                    end
                end
            end
            table.insert(result, rule)
        else
            local lower = token:lower()
            if existingMap[lower] then
                local ruleCopy = existingMap[lower]
                if type(ruleCopy) == "table" then
                    table.insert(result, ruleCopy)
                else
                    table.insert(result, { palname = token })
                end
            else
                table.insert(result, { palname = token })
            end
        end
    end
    return result
end

local function FormatLootFilters(filters)
    if type(filters) ~= "table" then return "" end
    local list = {}
    for _, item in ipairs(filters) do
        if type(item) == "string" and item ~= "" then
            table.insert(list, item)
        end
    end
    return table.concat(list, ", ")
end

local function ParseLootFilters(str)
    local result = {}
    if type(str) ~= "string" then return result end
    for item in string.gmatch(str, "([^,]+)") do
        local trimmed = item:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            table.insert(result, trimmed)
        end
    end
    return result
end

local function ApplySettings(settings, gen)
    if not settings then return end
    if gen and type(gen) == "number" and gen >= 0 then
        M.currentGeneration = gen
    end

    local CONFIG = configMod.CONFIG

    if settings["Global_Enabled"] ~= nil then CONFIG.Global.Enabled = settings["Global_Enabled"] end
    if settings["Global_ScanIntervalMs"] ~= nil then CONFIG.Global.ScanIntervalMs = settings["Global_ScanIntervalMs"] end
    if settings["Global_MaxDistance"] ~= nil then
        local d = settings["Global_MaxDistance"]
        if CONFIG.Global then CONFIG.Global.MaxDistance = d end
        if CONFIG.Players then CONFIG.Players.MaxDistance = d end
        if CONFIG.Relics then CONFIG.Relics.MaxDistance = d end
        if CONFIG.Chests then CONFIG.Chests.MaxDistance = d end
        if CONFIG.Eggs then CONFIG.Eggs.MaxDistance = d end
        if CONFIG.Caves then CONFIG.Caves.MaxDistance = d end
        if CONFIG.Loot then CONFIG.Loot.MaxDistance = d end
        if CONFIG.Notes then CONFIG.Notes.MaxDistance = d end
        if CONFIG.FastTravel then CONFIG.FastTravel.MaxDistance = d end
        if CONFIG.Hacks then CONFIG.Hacks.MaxDistance = d end
        if CONFIG.Bounties then CONFIG.Bounties.MaxDistance = d end
        if CONFIG.Pals then CONFIG.Pals.MaxDistance = d end
    end
    if settings["Global_FontScale"] ~= nil then CONFIG.Global.FontScale = settings["Global_FontScale"] end
    if settings["Global_BeamHeight"] ~= nil then CONFIG.Global.BeamHeight = settings["Global_BeamHeight"] end
    if settings["Global_BeamThickness"] ~= nil then CONFIG.Global.BeamThickness = settings["Global_BeamThickness"] end
    if settings["Global_BeamFollowIntervalMs"] ~= nil then CONFIG.Global.BeamFollowIntervalMs = settings["Global_BeamFollowIntervalMs"] end
    if settings["Global_Language"] ~= nil then CONFIG.Global.Language = settings["Global_Language"] end

    local function ApplyCategoryDisplay(cat, textKey, beamKey, legacyEnabledKey)
        if not cat then return end
        if settings[textKey] ~= nil then cat.ShowText = settings[textKey] end
        if settings[beamKey] ~= nil then cat.ShowBeam = settings[beamKey] end
        -- Backward compat: old single Enabled toggle sets both text and beam
        if settings[textKey] == nil and settings[beamKey] == nil and settings[legacyEnabledKey] ~= nil then
            cat.ShowText = settings[legacyEnabledKey]
            cat.ShowBeam = settings[legacyEnabledKey]
        end
        configMod.SyncCategoryEnabled(cat)
    end

    ApplyCategoryDisplay(CONFIG.Players, "Players_ShowText", "Players_ShowBeam", "Players_Enabled")
    ApplyCategoryDisplay(CONFIG.Relics, "Relics_ShowText", "Relics_ShowBeam", "Relics_Enabled")
    ApplyCategoryDisplay(CONFIG.Chests, "Chests_ShowText", "Chests_ShowBeam", "Chests_Enabled")
    if settings["Chests_Filter"] ~= nil and CONFIG.Chests then
        local legacyFilter = {
            Both = "Chests & Junk",
            Chests = "Only Chests",
            Junk = "Any Junk"
        }
        CONFIG.Chests.Filter = legacyFilter[settings["Chests_Filter"]] or settings["Chests_Filter"]
    end
    if settings["Chests_GradeFilter"] ~= nil and CONFIG.Chests then CONFIG.Chests.GradeFilter = settings["Chests_GradeFilter"] end
    ApplyCategoryDisplay(CONFIG.Caves, "Caves_ShowText", "Caves_ShowBeam", "Caves_Enabled")
    ApplyCategoryDisplay(CONFIG.Eggs, "Eggs_ShowText", "Eggs_ShowBeam", "Eggs_Enabled")
    if settings["Eggs_Filter"] ~= nil and CONFIG.Eggs then CONFIG.Eggs.Filter = settings["Eggs_Filter"] end
            ApplyCategoryDisplay(CONFIG.Notes, "Notes_ShowText", "Notes_ShowBeam", "Notes_Enabled")
    ApplyCategoryDisplay(CONFIG.FastTravel, "FastTravel_ShowText", "FastTravel_ShowBeam", "FastTravel_Enabled")
    ApplyCategoryDisplay(CONFIG.Hacks, "Hacks_ShowText", "Hacks_ShowBeam", "Hacks_Enabled")
    ApplyCategoryDisplay(CONFIG.Bounties, "Bounties_ShowText", "Bounties_ShowBeam", "Bounties_Enabled")
    
    local shownLootList = CONFIG.Loot and CONFIG.Loot.TrackerLoot
    if CONFIG.Loot and type(CONFIG.Loot.Filters) == "table" and #CONFIG.Loot.Filters > 0 then
        shownLootList = CONFIG.Loot.Filters
    end
    local currentLootStr = FormatLootFilters(shownLootList)
    ApplyCategoryDisplay(CONFIG.Loot, "Loot_ShowText", "Loot_ShowBeam", "Loot_Enabled")
    if settings["Loot_Filters"] ~= nil and settings["Loot_Filters"] ~= currentLootStr and CONFIG.Loot then
        local parsedFilters = ParseLootFilters(settings["Loot_Filters"])
        CONFIG.Loot.Filters = parsedFilters
        CONFIG.Loot.TrackerLoot = parsedFilters
    end
    if settings["Loot_FilterMode"] ~= nil and CONFIG.Loot then
        CONFIG.Loot.FilterMode = settings["Loot_FilterMode"]
    end

    local currentTrackerStr = FormatPalTrackerList(CONFIG.Pals and CONFIG.Pals.TrackerPals)
    ApplyCategoryDisplay(CONFIG.Pals, "Pals_ShowText", "Pals_ShowBeam", "Pals_Enabled")
    if settings["Pals_FilterMode"] ~= nil and CONFIG.Pals then CONFIG.Pals.FilterMode = settings["Pals_FilterMode"] end
    if settings["Pals_ShowPassives"] ~= nil and CONFIG.Pals then CONFIG.Pals.ShowPassives = settings["Pals_ShowPassives"] end
    if settings["Pals_ShowOnlyMatchedPassives"] ~= nil and CONFIG.Pals then CONFIG.Pals.ShowOnlyMatchedPassives = settings["Pals_ShowOnlyMatchedPassives"] end
    if settings["Pals_UseRarityColors"] ~= nil and CONFIG.Pals and CONFIG.Pals.Style then CONFIG.Pals.Style.UseRarityColors = settings["Pals_UseRarityColors"] end
    if settings["Pals_ShowLevel"] ~= nil and CONFIG.Pals then CONFIG.Pals.ShowLevel = settings["Pals_ShowLevel"] end
    if settings["Pals_IncludeOwned"] ~= nil and CONFIG.Pals then CONFIG.Pals.IncludeOwned = settings["Pals_IncludeOwned"] end
    if settings["Pals_TrackerList"] ~= nil and settings["Pals_TrackerList"] ~= currentTrackerStr and CONFIG.Pals then
        CONFIG.Pals.TrackerPals = ParsePalTrackerList(settings["Pals_TrackerList"], CONFIG.Pals.TrackerPals)
    end

    if settings["Completionist_ShowHUDTracker"] ~= nil and CONFIG.Completionist then CONFIG.Completionist.ShowHUDTracker = settings["Completionist_ShowHUDTracker"] end
    if settings["Completionist_HideInBase"] ~= nil and CONFIG.Completionist then CONFIG.Completionist.HideInBase = settings["Completionist_HideInBase"] end
    if settings["Completionist_ShowInMenu"] ~= nil and CONFIG.Completionist then CONFIG.Completionist.ShowInMenu = settings["Completionist_ShowInMenu"] end

    pcall(configMod.SaveConfig)
    pcall(function()
        local tracker = require("HUDLocator.tracker")
        tracker.SyncBeams()
    end)
end

function M.Sync()
    if not M.pmoClient then return end
    pcall(function()
        local curGen = M.pmoClient.generation()
        if curGen > M.currentGeneration then
            local gen, updated, settings = M.pmoClient.sync(M.currentGeneration, function(newValues, g)
                ApplySettings(newValues, g)
            end)
            if updated and gen then
                M.currentGeneration = gen
            end
        end
    end)
end

function M.Init()
    local ok, pmo = pcall(require, "PalModOptionsClient")
    if not ok or not pmo then
        return
    end

    M.pmoClient = pmo
    local CONFIG = configMod.CONFIG

    local initial_values = {
            Global_Enabled = CONFIG.Global and CONFIG.Global.Enabled or true,
            Global_ScanIntervalMs = CONFIG.Global and CONFIG.Global.ScanIntervalMs or 1500,
            Global_MaxDistance = (CONFIG.Global and CONFIG.Global.MaxDistance) or (CONFIG.Players and CONFIG.Players.MaxDistance) or 15000.0,
            Global_FontScale = CONFIG.Global and CONFIG.Global.FontScale or 1.0,
            Global_BeamHeight = CONFIG.Global and CONFIG.Global.BeamHeight or 1500.0,
            Global_BeamThickness = CONFIG.Global and CONFIG.Global.BeamThickness or 8.0,
            Global_BeamFollowIntervalMs = CONFIG.Global and CONFIG.Global.BeamFollowIntervalMs or 100,
            Global_Language = CONFIG.Global and CONFIG.Global.Language or "system",
            Players_ShowText = configMod.ShouldShowText(CONFIG.Players),
            Players_ShowBeam = configMod.ShouldShowBeam(CONFIG.Players),
            Relics_ShowText = configMod.ShouldShowText(CONFIG.Relics),
            Relics_ShowBeam = configMod.ShouldShowBeam(CONFIG.Relics),
            Chests_ShowText = configMod.ShouldShowText(CONFIG.Chests),
            Chests_ShowBeam = configMod.ShouldShowBeam(CONFIG.Chests),
            Chests_Filter = CONFIG.Chests and CONFIG.Chests.Filter or "Chests & Junk",
            Chests_GradeFilter = CONFIG.Chests and CONFIG.Chests.GradeFilter or "All",
            Caves_ShowText = configMod.ShouldShowText(CONFIG.Caves),
            Caves_ShowBeam = configMod.ShouldShowBeam(CONFIG.Caves),
            Eggs_ShowText = configMod.ShouldShowText(CONFIG.Eggs),
            Eggs_ShowBeam = configMod.ShouldShowBeam(CONFIG.Eggs),
            Eggs_Filter = CONFIG.Eggs and CONFIG.Eggs.Filter or "All",
            Notes_ShowText = configMod.ShouldShowText(CONFIG.Notes),
            Notes_ShowBeam = configMod.ShouldShowBeam(CONFIG.Notes),
            FastTravel_ShowText = configMod.ShouldShowText(CONFIG.FastTravel),
            FastTravel_ShowBeam = configMod.ShouldShowBeam(CONFIG.FastTravel),
            Hacks_ShowText = configMod.ShouldShowText(CONFIG.Hacks),
            Hacks_ShowBeam = configMod.ShouldShowBeam(CONFIG.Hacks),
            Bounties_ShowText = configMod.ShouldShowText(CONFIG.Bounties),
            Bounties_ShowBeam = configMod.ShouldShowBeam(CONFIG.Bounties),
            Loot_ShowText = configMod.ShouldShowText(CONFIG.Loot),
            Loot_ShowBeam = configMod.ShouldShowBeam(CONFIG.Loot),
            Loot_Filters = FormatLootFilters((CONFIG.Loot and CONFIG.Loot.TrackerLoot) or (CONFIG.Loot and CONFIG.Loot.Filters)),
            Loot_FilterMode = CONFIG.Loot and CONFIG.Loot.FilterMode or "Filtered",
            Pals_ShowText = configMod.ShouldShowText(CONFIG.Pals),
            Pals_ShowBeam = configMod.ShouldShowBeam(CONFIG.Pals),
            Pals_FilterMode = CONFIG.Pals and CONFIG.Pals.FilterMode or "TrackerListOnly",
            Pals_ShowPassives = CONFIG.Pals and CONFIG.Pals.ShowPassives or true,
            Pals_ShowOnlyMatchedPassives = CONFIG.Pals and CONFIG.Pals.ShowOnlyMatchedPassives or false,
            Pals_UseRarityColors = (CONFIG.Pals and CONFIG.Pals.Style and CONFIG.Pals.Style.UseRarityColors ~= false) or true,
            Pals_ShowLevel = CONFIG.Pals and CONFIG.Pals.ShowLevel or true,
            Pals_IncludeOwned = CONFIG.Pals and CONFIG.Pals.IncludeOwned or false,
            Pals_TrackerList = FormatPalTrackerList(CONFIG.Pals and CONFIG.Pals.TrackerPals),
            Completionist_ShowHUDTracker = CONFIG.Completionist and CONFIG.Completionist.ShowHUDTracker or true,
            Completionist_HideInBase = not CONFIG.Completionist or CONFIG.Completionist.HideInBase ~= false,
            Completionist_ShowInMenu = CONFIG.Completionist and CONFIG.Completionist.ShowInMenu or true,
        }

    local function Page(id, title, description, options)
        for _, option in ipairs(options) do
            if option.hint and not option.description then
                option.description = option.hint
            end
            if option.minimum == nil and option.min ~= nil then option.minimum = option.min end
            if option.maximum == nil and option.max ~= nil then option.maximum = option.max end
        end
        return {
            api = 1,
            id = id,
            mod_folder = "HUDLocator",
            title = title,
            description = description,
            version = 2,
            apply_mode = "event",
            initial_values = initial_values,
            options = options,
        }
    end

    local pages = {
        Page("HUDLocator.General", "HUD Locator: General", "Master switch, scan range, text size, and beam size.", {
            {
                key = "Global_Enabled",
                type = "boolean",
                label = "Master Enable",
                hint = "Enable or disable HUD Locator completely.",
                default = true
            },
            {
                key = "Global_ScanIntervalMs",
                type = "integer",
                label = "Scan Interval (ms)",
                hint = "Milliseconds between background locator scan loops.",
                default = 1500,
                min = 500,
                max = 5000,
                step = 250
            },
            {
                key = "Global_MaxDistance",
                type = "number",
                label = "Scan Distance (UE Units)",
                hint = "Maximum scan distance in unreal units (e.g. 15000 = 150m).",
                default = 15000.0,
                min = 1000.0,
                max = 100000.0,
                step = 1000.0
            },
            {
                key = "Global_FontScale",
                type = "number",
                label = "Global Font Scale",
                hint = "Scale multiplier for HUD text overlays.",
                default = 1.0,
                min = 0.5,
                max = 3.0,
                step = 0.1
            },
            {
                key = "Global_BeamHeight",
                type = "number",
                label = "Beam Pillar Height",
                hint = "Height of the world-space Niagara beam in unreal units (100 = 1m). Default 1500 = 15m.",
                default = 1500.0,
                min = 500.0,
                max = 10000.0,
                step = 250.0
            },
            {
                key = "Global_BeamFollowIntervalMs",
                type = "integer",
                label = "Beam Follow Interval (ms)",
                hint = "How often moving beacons are checked. The pillar is recreated only after the target moves about 3 meters.",
                default = 100,
                min = 50,
                max = 2000,
                step = 50
            },
            {
                key = "Global_BeamThickness",
                type = "number",
                label = "Beam Pillar Thickness",
                hint = "Width scale of the world-space Niagara beam (8 = default width).",
                default = 8.0,
                min = 1.0,
                max = 32.0,
                step = 1.0
            },
            {
                key = "Global_Language",
                type = "enum",
                label = "UI Language",
                hint = "Interface display language ('system' autodetects game language).",
                default = "system",
                choices = { "system", "en", "es", "ja", "zh-Hans", "zh-Hant", "fr", "it", "de", "ko", "pt-BR", "ru", "th", "vi", "id", "tr", "pl", "es-MX" }
            },
        }),
        Page("HUDLocator.Players", "HUD Locator: Players", "Text and beam markers for other players.", {
            {
                key = "Players_ShowText",
                type = "boolean",
                label = "Players: Text",
                hint = "Show text labels for other players.",
                default = true
            },
            {
                key = "Players_ShowBeam",
                type = "boolean",
                label = "Players: Beam",
                hint = "Show 3D light beam pillars for other players.",
                default = true
            },
        }),
        Page("HUDLocator.Relics", "HUD Locator: Relics", "Text and beam markers for Lifmunk Effigies.", {
            {
                key = "Relics_ShowText",
                type = "boolean",
                label = "Relics: Text",
                hint = "Show text labels for Lifmunk Effigies.",
                default = true
            },
            {
                key = "Relics_ShowBeam",
                type = "boolean",
                label = "Relics: Beam",
                hint = "Show 3D light beam pillars for Lifmunk Effigies.",
                default = true
            },
        }),
        Page("HUDLocator.Chests", "HUD Locator: Treasure", "Text, beams, and filters for treasure chests and junk piles.", {
            {
                key = "Chests_ShowText",
                type = "boolean",
                label = "Treasure: Text",
                hint = "Show text labels for treasure chests and junk piles.",
                default = true
            },
            {
                key = "Chests_ShowBeam",
                type = "boolean",
                label = "Treasure: Beam",
                hint = "Show 3D light beam pillars for treasure chests and junk piles.",
                default = true
            },
            {
                key = "Chests_Filter",
                type = "enum",
                label = "Treasure Filter",
                hint = "Choose chests, land junk, fishing junk, or a combination.",
                default = "Chests & Junk",
                choices = { "Chests & Junk", "Chests & Land Junk", "Chests & Fishing Junk", "Only Chests", "Any Junk", "Land Junk", "Fishing Junk" }
            },
            {
                key = "Chests_GradeFilter",
                type = "enum",
                label = "Treasure Grade Filter",
                hint = "Filter minimum rarity grade for displayed chests.",
                default = "All",
                choices = { "All", "Grade2+", "Grade3+", "Grade4+", "Grade5+", "Grade6Only", "None" }
            },
        }),
        Page("HUDLocator.Caves", "HUD Locator: Caves", "Text and beam markers for dungeon entrances.", {
            {
                key = "Caves_ShowText",
                type = "boolean",
                label = "Caves: Text",
                hint = "Show text labels for dungeon entrances.",
                default = true
            },
            {
                key = "Caves_ShowBeam",
                type = "boolean",
                label = "Caves: Beam",
                hint = "Show 3D light beam pillars for dungeon entrances.",
                default = true
            },
        }),
        Page("HUDLocator.Eggs", "HUD Locator: Eggs", "Text, beams, and size filter for wild eggs.", {
            {
                key = "Eggs_ShowText",
                type = "boolean",
                label = "Eggs: Text",
                hint = "Show text labels for wild eggs.",
                default = true
            },
            {
                key = "Eggs_ShowBeam",
                type = "boolean",
                label = "Eggs: Beam",
                hint = "Show 3D light beam pillars for wild eggs.",
                default = true
            },
            {
                key = "Eggs_Filter",
                type = "enum",
                label = "Egg Filter",
                hint = "Filter wild egg size categories.",
                default = "All",
                choices = { "All", "Large+", "HugeOnly", "None" }
            },
        }),
        Page("HUDLocator.Journals", "HUD Locator: Journals", "Text and beam markers for collectible journals.", {
            {
                key = "Notes_ShowText",
                type = "boolean",
                label = "Journals: Text",
                hint = "Show text labels for collectible journals.",
                default = true
            },
            {
                key = "Notes_ShowBeam",
                type = "boolean",
                label = "Journals: Beam",
                hint = "Show 3D light beam pillars for collectible journals.",
                default = true
            },
        }),
        Page("HUDLocator.Loot", "HUD Locator: Loot", "Text, beams, and filters for ground loot.", {
            {
                key = "Loot_ShowText",
                type = "boolean",
                label = "Loot: Text",
                hint = "Show text labels for ground loot.",
                default = false
            },
            {
                key = "Loot_ShowBeam",
                type = "boolean",
                label = "Loot: Beam",
                hint = "Show 3D light beam pillars for ground loot.",
                default = false
            },
            {
                key = "Loot_FilterMode",
                type = "enum",
                label = "Loot Filter",
                hint = "All ground items, skill fruits and lotus only, or the custom item list.",
                default = "Filtered",
                choices = { "All", "Skill Fruits/Lotus Only", "Filtered" }
            },
            {
                key = "Loot_Filters",
                type = "text",
                label = "Tracked Items List",
                hint = "Used when Loot Filter is Filtered. Comma-separated names (Skill Fruit, Lotus, Sphere, or any item).",
                default = "SkillFruit, Skill Fruit, Lotus, Sphere",
                max_length = 256
            },
        }),
        Page("HUDLocator.FastTravel", "HUD Locator: Fast Travel", "Text and beam markers for unactivated fast travel points.", {
            {
                key = "FastTravel_ShowText",
                type = "boolean",
                label = "Fast Travel: Text",
                hint = "Show text labels for unactivated fast travel points.",
                default = true
            },
            {
                key = "FastTravel_ShowBeam",
                type = "boolean",
                label = "Fast Travel: Beam",
                hint = "Show 3D light beam pillars for unactivated fast travel points.",
                default = true
            },
        }),
        Page("HUDLocator.Hacks", "HUD Locator: Hack Towers", "Text and beam markers for uncollected hack-tower prizes.", {
            {
                key = "Hacks_ShowText",
                type = "boolean",
                label = "Hack Towers: Text",
                hint = "Show text labels for hack towers whose prize has not been collected.",
                default = true
            },
            {
                key = "Hacks_ShowBeam",
                type = "boolean",
                label = "Hack Towers: Beam",
                hint = "Show 3D light beam pillars for hack towers whose prize has not been collected.",
                default = true
            },
        }),
        Page("HUDLocator.Bounties", "HUD Locator: Bounties", "Text and beam markers for bounty targets.", {
            {
                key = "Bounties_ShowText",
                type = "boolean",
                label = "Bounties: Text",
                hint = "Show text labels for bounty targets.",
                default = true
            },
            {
                key = "Bounties_ShowBeam",
                type = "boolean",
                label = "Bounties: Beam",
                hint = "Show 3D light beam pillars for bounty targets.",
                default = true
            },
        }),
        Page("HUDLocator.Pals", "HUD Locator: Pals", "Text, beams, and filters for wild Pals.", {
            {
                key = "Pals_ShowText",
                type = "boolean",
                label = "Pals: Text",
                hint = "Show text labels for wild Pals.",
                default = true
            },
            {
                key = "Pals_ShowBeam",
                type = "boolean",
                label = "Pals: Beam",
                hint = "Show 3D light beam pillars for wild Pals.",
                default = true
            },
            {
                key = "Pals_FilterMode",
                type = "enum",
                label = "Pal Filter Mode",
                hint = "Criteria used to filter tracked wild Pals.",
                default = "TrackerListOnly",
                choices = { "TrackerListOnly", "All", "ShinyOnly", "BossOnly", "ShinyOrBoss" }
            },
            {
                key = "Pals_ShowPassives",
                type = "boolean",
                label = "Show Pal Passives",
                hint = "Display passive skills on Pal markers.",
                default = true
            },
            {
                key = "Pals_ShowOnlyMatchedPassives",
                type = "boolean",
                label = "Show Only Matched Passives",
                hint = "Display only the passives that matched tracking rules instead of all 4 slots.",
                default = false
            },
            {
                key = "Pals_UseRarityColors",
                type = "boolean",
                label = "Passive Rarity Colors",
                hint = "Color passives according to tier (Gold for Legend/Tier 3, Blue for Tier 2, White for Tier 1, Red for negative).",
                default = true
            },
            {
                key = "Pals_ShowLevel",
                type = "boolean",
                label = "Show Pal Level",
                hint = "Display level numbers on Pal markers.",
                default = true
            },
            {
                key = "Pals_IncludeOwned",
                type = "boolean",
                label = "Include Owned Pals",
                hint = "Display markers for player-owned and base camp worker Pals.",
                default = false
            },
            {
                key = "Pals_TrackerList",
                type = "text",
                label = "Tracked Pals List",
                hint = "Comma-separated Pals or rules (e.g. 'Lamball, *:Runner, *:Swift/Legend[2], Cattiva:Shiny'). Use '*' for any Pal.",
                default = "*:Runner/Swift/Legend/Artisan, Lamball:Runner, Jetragon:Boss:Legend/Swift[2]",
                max_length = 256
            },
        }),
        Page("HUDLocator.Progress", "HUD Locator: Progress", "Completion tracker card and menu summary.", {
            {
                key = "Completionist_ShowHUDTracker",
                type = "boolean",
                label = "Show Progress Tracker HUD",
                hint = "Display zone completion stats on HUD.",
                default = true
            },
            {
                key = "Completionist_HideInBase",
                type = "boolean",
                label = "Hide Progress Tracker While In Base",
                hint = "Hide the progress tracker while the base HUD is active.",
                default = true
            },
            {
                key = "Completionist_ShowInMenu",
                type = "boolean",
                label = "Show Progress In Menu",
                hint = "Enable completionist summary in quick menu.",
                default = true
            },
        }),
    }

    for _, schema in ipairs(pages) do
        pmo.register_when_ready(schema, function(settings, registration_error)
            if settings ~= nil then
                M.currentGeneration = pmo.generation()
            end
        end)
    end
end

return M
