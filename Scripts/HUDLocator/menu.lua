local configMod = require("HUDLocator.config")
local popup = require("HUDLocator.popup")
local utils = require("HUDLocator.utils")
local CONFIG = configMod.CONFIG

local M = {}

M.isOpen = false
M.isCompletionistViewOpen = false
local selectedIndex = 1
local currentCategory = nil

local menuItems = {
    {
        name = "Master Enabled",
        get = function() return CONFIG.Global.Enabled end,
        set = function(v) CONFIG.Global.Enabled = v end,
        type = "boolean",
        transKey = "Settings_Enable"
    },
    {
        name = "Players Text",
        get = function() return configMod.ShouldShowText(CONFIG.Players) end,
        set = function(v)
            CONFIG.Players.ShowText = v
            configMod.SyncCategoryEnabled(CONFIG.Players)
        end,
        type = "boolean",
        transKey = "Settings_ShowPlayersText"
    },
    {
        name = "Players Beam",
        get = function() return configMod.ShouldShowBeam(CONFIG.Players) end,
        set = function(v)
            CONFIG.Players.ShowBeam = v
            configMod.SyncCategoryEnabled(CONFIG.Players)
        end,
        type = "boolean",
        transKey = "Settings_ShowPlayersBeam"
    },
    {
        name = "Relics Text",
        get = function() return configMod.ShouldShowText(CONFIG.Relics) end,
        set = function(v)
            CONFIG.Relics.ShowText = v
            configMod.SyncCategoryEnabled(CONFIG.Relics)
        end,
        type = "boolean",
        transKey = "Settings_ShowRelicsText"
    },
    {
        name = "Relics Beam",
        get = function() return configMod.ShouldShowBeam(CONFIG.Relics) end,
        set = function(v)
            CONFIG.Relics.ShowBeam = v
            configMod.SyncCategoryEnabled(CONFIG.Relics)
        end,
        type = "boolean",
        transKey = "Settings_ShowRelicsBeam"
    },
    {
        name = "Chests Text",
        get = function() return configMod.ShouldShowText(CONFIG.Chests) end,
        set = function(v)
            CONFIG.Chests.ShowText = v
            configMod.SyncCategoryEnabled(CONFIG.Chests)
        end,
        type = "boolean",
        transKey = "Settings_ShowChestsText"
    },
    {
        name = "Chests Beam",
        get = function() return configMod.ShouldShowBeam(CONFIG.Chests) end,
        set = function(v)
            CONFIG.Chests.ShowBeam = v
            configMod.SyncCategoryEnabled(CONFIG.Chests)
        end,
        type = "boolean",
        transKey = "Settings_ShowChestsBeam"
    },
    {
        name = "Chest Filter",
        get = function() return CONFIG.Chests.Filter or "Both" end,
        set = function(v) CONFIG.Chests.Filter = v end,
        type = "enum",
        values = { "Both", "Chests", "Junk" },
        transKey = "Settings_ChestFilter"
    },
    {
        name = "Chest Grade Filter",
        get = function() return CONFIG.Chests.GradeFilter or "All" end,
        set = function(v) CONFIG.Chests.GradeFilter = v end,
        type = "enum",
        values = { "All", "Grade2+", "Grade3+", "Grade4+", "Grade5+", "Grade6Only", "None" },
        transKey = "Settings_ChestGradeFilter"
    },
    {
        name = "Caves Text",
        get = function() return configMod.ShouldShowText(CONFIG.Caves) end,
        set = function(v)
            CONFIG.Caves.ShowText = v
            configMod.SyncCategoryEnabled(CONFIG.Caves)
        end,
        type = "boolean",
        transKey = "Settings_ShowCavesText"
    },
    {
        name = "Caves Beam",
        get = function() return configMod.ShouldShowBeam(CONFIG.Caves) end,
        set = function(v)
            CONFIG.Caves.ShowBeam = v
            configMod.SyncCategoryEnabled(CONFIG.Caves)
        end,
        type = "boolean",
        transKey = "Settings_ShowCavesBeam"
    },
    {
        name = "Notes Text",
        get = function() return configMod.ShouldShowText(CONFIG.Notes) end,
        set = function(v)
            CONFIG.Notes.ShowText = v
            configMod.SyncCategoryEnabled(CONFIG.Notes)
        end,
        type = "boolean",
        transKey = "Settings_ShowNotesText"
    },
    {
        name = "Notes Beam",
        get = function() return configMod.ShouldShowBeam(CONFIG.Notes) end,
        set = function(v)
            CONFIG.Notes.ShowBeam = v
            configMod.SyncCategoryEnabled(CONFIG.Notes)
        end,
        type = "boolean",
        transKey = "Settings_ShowNotesBeam"
    },
    {
        name = "Loot Text",
        get = function() return configMod.ShouldShowText(CONFIG.Loot) end,
        set = function(v)
            CONFIG.Loot.ShowText = v
            configMod.SyncCategoryEnabled(CONFIG.Loot)
        end,
        type = "boolean",
        transKey = "Settings_ShowLootText"
    },
    {
        name = "Loot Beam",
        get = function() return configMod.ShouldShowBeam(CONFIG.Loot) end,
        set = function(v)
            CONFIG.Loot.ShowBeam = v
            configMod.SyncCategoryEnabled(CONFIG.Loot)
        end,
        type = "boolean",
        transKey = "Settings_ShowLootBeam"
    },
    {
        name = "Loot Filter",
        get = function() return (CONFIG.Loot and CONFIG.Loot.FilterMode) or "Filtered" end,
        set = function(v) if CONFIG.Loot then CONFIG.Loot.FilterMode = v end end,
        type = "enum",
        values = { "All", "Skill Fruits/Lotus Only", "Filtered" },
        transKey = "Settings_LootFilter"
    },
    {
        name = "Fast Travel Text",
        get = function() return configMod.ShouldShowText(CONFIG.FastTravel) end,
        set = function(v)
            if CONFIG.FastTravel then
                CONFIG.FastTravel.ShowText = v
                configMod.SyncCategoryEnabled(CONFIG.FastTravel)
            end
        end,
        type = "boolean",
        transKey = "Settings_ShowFastTravelText"
    },
    {
        name = "Fast Travel Beam",
        get = function() return configMod.ShouldShowBeam(CONFIG.FastTravel) end,
        set = function(v)
            if CONFIG.FastTravel then
                CONFIG.FastTravel.ShowBeam = v
                configMod.SyncCategoryEnabled(CONFIG.FastTravel)
            end
        end,
        type = "boolean",
        transKey = "Settings_ShowFastTravelBeam"
    },
    {
        name = "Hack Tower Text",
        get = function() return configMod.ShouldShowText(CONFIG.Hacks) end,
        set = function(v)
            if CONFIG.Hacks then
                CONFIG.Hacks.ShowText = v
                configMod.SyncCategoryEnabled(CONFIG.Hacks)
            end
        end,
        type = "boolean",
        transKey = "Settings_ShowHacksText"
    },
    {
        name = "Hack Tower Beam",
        get = function() return configMod.ShouldShowBeam(CONFIG.Hacks) end,
        set = function(v)
            if CONFIG.Hacks then
                CONFIG.Hacks.ShowBeam = v
                configMod.SyncCategoryEnabled(CONFIG.Hacks)
            end
        end,
        type = "boolean",
        transKey = "Settings_ShowHacksBeam"
    },
    {
        name = "Bounty Text",
        get = function() return configMod.ShouldShowText(CONFIG.Bounties) end,
        set = function(v)
            if CONFIG.Bounties then
                CONFIG.Bounties.ShowText = v
                configMod.SyncCategoryEnabled(CONFIG.Bounties)
            end
        end,
        type = "boolean",
        transKey = "Settings_ShowBountiesText"
    },
    {
        name = "Bounty Beam",
        get = function() return configMod.ShouldShowBeam(CONFIG.Bounties) end,
        set = function(v)
            if CONFIG.Bounties then
                CONFIG.Bounties.ShowBeam = v
                configMod.SyncCategoryEnabled(CONFIG.Bounties)
            end
        end,
        type = "boolean",
        transKey = "Settings_ShowBountiesBeam"
    },
    {
        name = "Pals Text",
        get = function() return configMod.ShouldShowText(CONFIG.Pals) end,
        set = function(v)
            if CONFIG.Pals then
                CONFIG.Pals.ShowText = v
                configMod.SyncCategoryEnabled(CONFIG.Pals)
            end
        end,
        type = "boolean",
        transKey = "Settings_ShowPalsText"
    },
    {
        name = "Pals Beam",
        get = function() return configMod.ShouldShowBeam(CONFIG.Pals) end,
        set = function(v)
            if CONFIG.Pals then
                CONFIG.Pals.ShowBeam = v
                configMod.SyncCategoryEnabled(CONFIG.Pals)
            end
        end,
        type = "boolean",
        transKey = "Settings_ShowPalsBeam"
    },
    {
        name = "Eggs Text",
        get = function() return configMod.ShouldShowText(CONFIG.Eggs) end,
        set = function(v)
            CONFIG.Eggs.ShowText = v
            configMod.SyncCategoryEnabled(CONFIG.Eggs)
        end,
        type = "boolean",
        transKey = "Settings_ShowEggsText"
    },
    {
        name = "Eggs Beam",
        get = function() return configMod.ShouldShowBeam(CONFIG.Eggs) end,
        set = function(v)
            CONFIG.Eggs.ShowBeam = v
            configMod.SyncCategoryEnabled(CONFIG.Eggs)
        end,
        type = "boolean",
        transKey = "Settings_ShowEggsBeam"
    },
    {
        name = "Pal Filter",
        get = function() return (CONFIG.Pals and CONFIG.Pals.FilterMode) or "TrackerListOnly" end,
        set = function(v) if CONFIG.Pals then CONFIG.Pals.FilterMode = v end end,
        type = "enum",
        values = { "TrackerListOnly", "All", "ShinyOnly", "BossOnly", "ShinyOrBoss" },
        transKey = "Settings_PalFilter"
    },
    {
        name = "Show Passives",
        get = function() return CONFIG.Pals and CONFIG.Pals.ShowPassives end,
        set = function(v) if CONFIG.Pals then CONFIG.Pals.ShowPassives = v end end,
        type = "boolean",
        transKey = "Settings_ShowPassives"
    },
    {
        name = "Only Matched Passives",
        get = function() return CONFIG.Pals and CONFIG.Pals.ShowOnlyMatchedPassives end,
        set = function(v) if CONFIG.Pals then CONFIG.Pals.ShowOnlyMatchedPassives = v end end,
        type = "boolean",
        transKey = "Settings_ShowOnlyMatchedPassives"
    },
    {
        name = "Passive Rarity Colors",
        get = function() return CONFIG.Pals and CONFIG.Pals.Style and CONFIG.Pals.Style.UseRarityColors ~= false end,
        set = function(v) if CONFIG.Pals and CONFIG.Pals.Style then CONFIG.Pals.Style.UseRarityColors = v end end,
        type = "boolean",
        transKey = "Settings_UseRarityColors"
    },
    {
        name = "Show Level",
        get = function() return CONFIG.Pals and CONFIG.Pals.ShowLevel end,
        set = function(v) if CONFIG.Pals then CONFIG.Pals.ShowLevel = v end end,
        type = "boolean",
        transKey = "Settings_ShowLevel"
    },
    {
        name = "Include Owned Pals",
        get = function() return CONFIG.Pals and CONFIG.Pals.IncludeOwned end,
        set = function(v) if CONFIG.Pals then CONFIG.Pals.IncludeOwned = v end end,
        type = "boolean",
        transKey = "Settings_IncludeOwned"
    },
    {
        name = "Egg Filter",
        get = function() return CONFIG.Eggs.Filter end,
        set = function(v) CONFIG.Eggs.Filter = v end,
        type = "enum",
        values = { "All", "Large+", "HugeOnly", "None" },
        transKey = "Settings_EggFilter"
    },
    {
        name = "Show Progress Tracker HUD",
        get = function() return CONFIG.Completionist and CONFIG.Completionist.ShowHUDTracker end,
        set = function(v) if CONFIG.Completionist then CONFIG.Completionist.ShowHUDTracker = v end end,
        type = "boolean",
        transKey = "Settings_ShowProgressTracker"
    },
    {
        name = "Hide Progress Tracker While In Base",
        get = function() return not CONFIG.Completionist or CONFIG.Completionist.HideInBase ~= false end,
        set = function(v) if CONFIG.Completionist then CONFIG.Completionist.HideInBase = v end end,
        type = "boolean",
        transKey = "Settings_HideProgressInBase"
    },
    {
        name = "Reposition HUD (Edit Mode)",
        get = function() return configMod.EditModeActive and "Active" or "Press Right" end,
        type = "action",
        action = function()
            M.Toggle()
            configMod.ToggleEditMode()
        end,
        transKey = "Settings_RepositionHUD",
        valKey = "Action_OpenEditMode"
    },
    {
        name = "HUD Position Preset",
        get = function() return (CONFIG.Completionist and CONFIG.Completionist.HUDAnchor) or "TopRight" end,
        set = function(v)
            if not CONFIG.Completionist then CONFIG.Completionist = {} end
            CONFIG.Completionist.HUDAnchor = v
            if v == "TopRight" then
                CONFIG.Completionist.HUDX = 95.0
                CONFIG.Completionist.HUDY = 4.0
            elseif v == "TopLeft" then
                CONFIG.Completionist.HUDX = 3.0
                CONFIG.Completionist.HUDY = 4.0
            elseif v == "BottomRight" then
                CONFIG.Completionist.HUDX = 95.0
                CONFIG.Completionist.HUDY = 85.0
            elseif v == "BottomLeft" then
                CONFIG.Completionist.HUDX = 3.0
                CONFIG.Completionist.HUDY = 85.0
            end
            pcall(configMod.SaveConfig)
        end,
        type = "enum",
        values = { "TopRight", "TopLeft", "BottomRight", "BottomLeft", "Custom" },
        transKey = "Settings_HUDAnchor"
    },
    {
        name = "HUD Tracker Scale",
        get = function() return (CONFIG.Completionist and CONFIG.Completionist.HUDScale) or 1.0 end,
        set = function(v)
            if not CONFIG.Completionist then CONFIG.Completionist = {} end
            CONFIG.Completionist.HUDScale = tonumber(string.format("%.1f", v))
            pcall(configMod.SaveConfig)
        end,
        type = "number",
        min = 0.5,
        max = 2.0,
        step = 0.1,
        format = function(v) return string.format("%.1fx", v or 1.0) end,
        transKey = "Settings_HUDScale"
    },
    {
        name = "Reset HUD Position",
        get = function() return "Press Right" end,
        type = "action",
        action = function()
            if CONFIG.Completionist then
                CONFIG.Completionist.HUDX = nil
                CONFIG.Completionist.HUDY = nil
                CONFIG.Completionist.HUDScale = 1.0
                CONFIG.Completionist.HUDAnchor = "TopRight"
            end
            pcall(configMod.SaveConfig)
            popup.Show(configMod.GetTranslation("Popup_HUDReset", "HUD Position Reset to Default"), 120)
        end,
        transKey = "Settings_ResetHUD",
        valKey = "Action_Reset"
    },
    {
        name = "Completionist List",
        get = function() return M.isCompletionistViewOpen and "Opened" or "Press Right" end,
        type = "action",
        action = function()
            M.isCompletionistViewOpen = not M.isCompletionistViewOpen
        end,
        transKey = "Settings_CompletionistList"
    },
    {
        name = "Max Distance (All)",
        get = function() return (CONFIG.Global and CONFIG.Global.MaxDistance) or CONFIG.Players.MaxDistance end,
        set = function(v)
            if CONFIG.Global then CONFIG.Global.MaxDistance = v end
            if CONFIG.Players then CONFIG.Players.MaxDistance = v end
            if CONFIG.Relics then CONFIG.Relics.MaxDistance = v end
            if CONFIG.Chests then CONFIG.Chests.MaxDistance = v end
            if CONFIG.Eggs then CONFIG.Eggs.MaxDistance = v end
            if CONFIG.Caves then CONFIG.Caves.MaxDistance = v end
            if CONFIG.Loot then CONFIG.Loot.MaxDistance = v end
            if CONFIG.Notes then CONFIG.Notes.MaxDistance = v end
            if CONFIG.FastTravel then CONFIG.FastTravel.MaxDistance = v end
            if CONFIG.Hacks then CONFIG.Hacks.MaxDistance = v end
            if CONFIG.Bounties then CONFIG.Bounties.MaxDistance = v end
            if CONFIG.Pals then CONFIG.Pals.MaxDistance = v end
        end,
        type = "number",
        min = 5000,
        max = 100000,
        step = 5000,
        format = function(v) return math.floor((v or 15000) / 100) .. "m" end,
        transKey = "Settings_MaxDistance"
    },
    {
        name = "Beam Height",
        get = function() return (CONFIG.Global and CONFIG.Global.BeamHeight) or 1500.0 end,
        set = function(v) if CONFIG.Global then CONFIG.Global.BeamHeight = v end end,
        type = "number",
        min = 500,
        max = 10000,
        step = 250,
        format = function(v) return math.floor((v or 1500) / 100) .. "m" end,
        transKey = "Settings_BeamHeight"
    },
    {
        name = "Beam Thickness",
        get = function() return (CONFIG.Global and CONFIG.Global.BeamThickness) or 8.0 end,
        set = function(v) if CONFIG.Global then CONFIG.Global.BeamThickness = v end end,
        type = "number",
        min = 1,
        max = 32,
        step = 1,
        format = function(v) return string.format("%.0f", v or 8.0) end,
        transKey = "Settings_BeamThickness"
    },
    {
        name = "Beam Follow Interval",
        get = function() return (CONFIG.Global and CONFIG.Global.BeamFollowIntervalMs) or 100 end,
        set = function(v) if CONFIG.Global then CONFIG.Global.BeamFollowIntervalMs = v end end,
        type = "number",
        min = 50,
        max = 2000,
        step = 50,
        format = function(v) return (v or 100) .. "ms" end,
        transKey = "Settings_BeamFollowInterval"
    },
    {
        name = "Scan Interval",
        get = function() return CONFIG.Global.ScanIntervalMs end,
        set = function(v) CONFIG.Global.ScanIntervalMs = v end,
        type = "number",
        min = 500,
        max = 5000,
        step = 250,
        format = function(v) return (v or 1500) .. "ms" end,
        transKey = "Settings_ScanInterval"
    },
    {
        name = "Font Scale",
        get = function() return CONFIG.Global.FontScale or 1.0 end,
        set = function(v) CONFIG.Global.FontScale = v end,
        type = "number",
        min = 0.5,
        max = 2.0,
        step = 0.1,
        format = function(v) return string.format("%.1fx", v or 1.0) end,
        transKey = "Settings_FontScale"
    },
    {
        name = "Language",
        get = function() return CONFIG.Global.Language or "system" end,
        set = function(v) CONFIG.Global.Language = v end,
        type = "enum",
        values = { "system", "en", "es", "ja", "zh-Hans", "zh-Hant", "fr", "it", "de", "ko", "pt-BR", "ru", "th", "vi", "id", "tr", "pl", "es-MX" },
        transKey = "Settings_Language"
    }
}

local itemCategory = {
    ["Master Enabled"] = "General",
    ["Scan Interval"] = "General",
    ["Max Distance (All)"] = "General",
    ["Beam Height"] = "General",
    ["Beam Thickness"] = "General",
    ["Beam Follow Interval"] = "General",
    ["Font Scale"] = "General",
    ["Language"] = "General",
    ["Players Text"] = "Players",
    ["Players Beam"] = "Players",
    ["Relics Text"] = "Relics",
    ["Relics Beam"] = "Relics",
    ["Chests Text"] = "Chests",
    ["Chests Beam"] = "Chests",
    ["Chest Filter"] = "Chests",
    ["Chest Grade Filter"] = "Chests",
    ["Caves Text"] = "Caves",
    ["Caves Beam"] = "Caves",
    ["Eggs Text"] = "Eggs",
    ["Eggs Beam"] = "Eggs",
    ["Egg Filter"] = "Eggs",
    ["Notes Text"] = "Journals",
    ["Notes Beam"] = "Journals",
    ["Loot Text"] = "Loot",
    ["Loot Beam"] = "Loot",
    ["Loot Filter"] = "Loot",
    ["Fast Travel Text"] = "FastTravel",
    ["Fast Travel Beam"] = "FastTravel",
    ["Hack Tower Text"] = "Hacks",
    ["Hack Tower Beam"] = "Hacks",
    ["Bounty Text"] = "Bounties",
    ["Bounty Beam"] = "Bounties",
    ["Pals Text"] = "Pals",
    ["Pals Beam"] = "Pals",
    ["Pal Filter"] = "Pals",
    ["Show Passives"] = "Pals",
    ["Only Matched Passives"] = "Pals",
    ["Passive Rarity Colors"] = "Pals",
    ["Show Level"] = "Pals",
    ["Include Owned Pals"] = "Pals",
    ["Show Progress Tracker HUD"] = "Progress",
    ["Hide Progress Tracker While In Base"] = "Progress",
    ["Reposition HUD (Edit Mode)"] = "Progress",
    ["HUD Position Preset"] = "Progress",
    ["HUD Tracker Scale"] = "Progress",
    ["Reset HUD Position"] = "Progress",
    ["Completionist List"] = "Progress",
}

local categoryOrder = {
    { id = "General", name = "General" },
    { id = "Players", name = "Players" },
    { id = "Relics", name = "Relics" },
    { id = "Chests", name = "Chests" },
    { id = "Caves", name = "Caves" },
    { id = "Eggs", name = "Eggs" },
    { id = "Journals", name = "Journals" },
    { id = "Loot", name = "Loot" },
    { id = "FastTravel", name = "Fast Travel" },
    { id = "Hacks", name = "Hack Towers" },
    { id = "Bounties", name = "Bounties" },
    { id = "Pals", name = "Pals" },
    { id = "Progress", name = "Progress" },
}

for _, item in ipairs(menuItems) do
    item.category = itemCategory[item.name]
end

local function CategoryName(id)
    for _, cat in ipairs(categoryOrder) do
        if cat.id == id then return cat.name end
    end
    return id
end

local function ItemVisible(item)
    if item.name == "Chest Filter" or item.name == "Chest Grade Filter" then
        if not configMod.IsCategoryTracked(CONFIG.Chests) then
            return false
        end
    elseif item.name == "Hide Progress Tracker While In Base" or item.name == "Reposition HUD (Edit Mode)" or item.name == "HUD Position Preset" or item.name == "HUD Tracker Scale" or item.name == "Reset HUD Position" then
        if not CONFIG.Completionist or not CONFIG.Completionist.Enabled or not CONFIG.Completionist.ShowHUDTracker then
            return false
        end
    end
    return true
end

local function GetVisibleItems()
    local visible = {}
    if not currentCategory then
        for _, cat in ipairs(categoryOrder) do
            table.insert(visible, {
                name = cat.name,
                type = "action",
                categoryMenu = true,
                get = function() return "" end,
                action = function()
                    currentCategory = cat.id
                    selectedIndex = 1
                end,
                valKey = "Menu_OpenCategory"
            })
        end
        return visible
    end

    table.insert(visible, {
        name = "Back",
        transKey = "Menu_Back",
        type = "action",
        get = function() return "" end,
                activate = "left",
                action = function()
                    currentCategory = nil
                    selectedIndex = 1
                end,
                valKey = "Menu_BackValue"
    })
    for _, item in ipairs(menuItems) do
        if item.category == currentCategory and ItemVisible(item) then
            table.insert(visible, item)
        end
    end
    return visible
end

function M.Toggle()
    M.isOpen = not M.isOpen
    if M.isOpen then
        currentCategory = nil
        selectedIndex = 1
        -- Load the latest configuration from disk before opening the menu
        pcall(configMod.LoadConfig)
        popup.Show(configMod.GetTranslation("Menu_Opened", "Configuration Menu Opened\nUse Up/Down/Left/Right"),
            180)
    else
        popup.Show(configMod.GetTranslation("Menu_Closed", "Configuration Menu Closed & Saved"), 120)
        pcall(configMod.SaveConfig)
    end
end

function M.Navigate(dir)
    if not M.isOpen then return end

    local visibleItems = GetVisibleItems()
    if #visibleItems == 0 then return end

    -- Ensure selectedIndex is within range of visible items
    if selectedIndex > #visibleItems then
        selectedIndex = #visibleItems
    elseif selectedIndex < 1 then
        selectedIndex = 1
    end

    if dir == "up" then
        selectedIndex = selectedIndex - 1
        if selectedIndex < 1 then selectedIndex = #visibleItems end
    elseif dir == "down" then
        selectedIndex = selectedIndex + 1
        if selectedIndex > #visibleItems then selectedIndex = 1 end
    elseif dir == "left" or dir == "right" then
        local item = visibleItems[selectedIndex]
        if item.type == "action" then
            if (item.activate or "right") == dir and item.action then
                pcall(item.action)
            end
        elseif item.type == "boolean" then
            item.set(not item.get())
        elseif item.type == "enum" then
            local current = item.get()
            local idx = 1
            for i, val in ipairs(item.values) do
                if val == current then
                    idx = i; break
                end
            end
            if dir == "right" then
                idx = idx + 1
                if idx > #item.values then idx = 1 end
            else
                idx = idx - 1
                if idx < 1 then idx = #item.values end
            end
            item.set(item.values[idx])
        elseif item.type == "number" then
            local val = item.get() or item.min
            if dir == "right" then
                val = val + item.step
                if val > item.max then val = item.max end
            else
                val = val - item.step
                if val < item.min then val = item.min end
            end
            item.set(val)
        end

        -- Automatically trigger SaveConfig on changes
        pcall(configMod.SaveConfig)
        -- Refresh world-space beams so height/thickness/toggle changes apply immediately
        pcall(function()
            local tracker = require("HUDLocator.tracker")
            tracker.SyncBeams()
        end)
    end
end

function M.Draw(hud, SizeX, SizeY)
    if not M.isOpen then return end

    -- Unwrap screenspace dimensions safely
    local sx = SizeX
    if type(sx) == "userdata" or type(sx) == "table" then
        local status, val = pcall(function() return sx:get() end)
        if status then sx = val end
    end
    local sy = SizeY
    if type(sy) == "userdata" or type(sy) == "table" then
        local status, val = pcall(function() return sy:get() end)
        if status then sy = val end
    end

    local screenW = (type(sx) == "number" and sx > 0) and sx or 1920.0
    local screenH = (type(sy) == "number" and sy > 0) and sy or 1080.0

    -- Retrieve cached font and scale multiplier
    local font, scaleMult = utils.GetFontAndScale()

    -- Measure text widths to dynamically size the menu and position the values
    local maxNameW = 0
    local maxValW = 0
    local charW = font and (7.0 + 2.0 * scaleMult) or 7.5
    
    local itemNames = {}
    local formattedValues = {}
    
    local visibleItems = GetVisibleItems()
    
    -- Ensure selectedIndex is within range of visible items
    if selectedIndex > #visibleItems then
        selectedIndex = math.max(1, #visibleItems)
    elseif selectedIndex < 1 then
        selectedIndex = 1
    end
    
    for i, item in ipairs(visibleItems) do
        local isSelected = (i == selectedIndex)
        
        -- Formatted Name
        local prefix = isSelected and "> " or "  "
        local displayName = configMod.GetTranslation(item.transKey, item.name)
        local displayStr = prefix .. displayName
        itemNames[i] = displayStr
        
        local nameW = utils.GetTextSize(hud, displayStr, 1.0)
        if not nameW or nameW == 0 then
            nameW = utils.GetStringLength(displayStr) * charW * scaleMult
        end
        if nameW > maxNameW then
            maxNameW = nameW
        end
        
        -- Formatted Value
        local rawVal = item.get()
        local valStr = ""
        if item.type == "boolean" then
            valStr = rawVal and configMod.GetTranslation("Menu_ON", "ON") or configMod.GetTranslation("Menu_OFF", "OFF")
        elseif item.type == "enum" then
            local filterKey = "Filter_" .. tostring(rawVal):gsub("%+", "Plus")
            valStr = configMod.GetTranslation(filterKey, tostring(rawVal))
        elseif item.type == "number" then
            if item.format then
                valStr = item.format(rawVal)
            else
                valStr = tostring(rawVal)
            end
        elseif item.type == "label" then
            valStr = tostring(rawVal)
        elseif item.type == "action" then
            valStr = configMod.GetTranslation(item.valKey or "Action_OpenURL", "Alt+Right to Open")
        end
        
        local valueText = isSelected and "[ " .. valStr .. " ]" or valStr
        formattedValues[i] = valueText
        
        local valW = utils.GetTextSize(hud, valueText, 1.0)
        if not valW or valW == 0 then
            valW = utils.GetStringLength(valueText) * charW * scaleMult
        end
        if valW > maxValW then
            maxValW = valW
        end
    end

    -- Header and tip translations
    local headerText = configMod.GetTranslation("Settings_Title", "HUD LOCATOR SETTINGS")
    if currentCategory then
        headerText = headerText .. "  " .. CategoryName(currentCategory)
    end
    local tipText = configMod.GetTranslation("Menu_Tips", "Up/Down: Navigate | Left/Right: Change")
    local footerText = configMod.GetTranslation("Menu_Footer", "ALT+F6 to Close & Save Settings")

    -- Pad definitions
    local padL = font and 30.0 or 20.0
    local padHighlight = font and 20.0 or 10.0
    local padText = font and 28.0 or 15.0
    local padVal = font and 35.0 or 25.0
    local gap = font and 40.0 or 30.0

    -- Dynamic width calculation
    local contentW = maxNameW + maxValW + padText + padVal + gap
    
    local headerW = utils.GetTextSize(hud, headerText, 1.2)
    if not headerW or headerW == 0 then
        headerW = utils.GetStringLength(headerText) * charW * 1.2 * scaleMult
    end
    
    local tipW = utils.GetTextSize(hud, tipText, 0.75)
    if not tipW or tipW == 0 then
        tipW = utils.GetStringLength(tipText) * charW * 0.75 * scaleMult
    end
    
    local footerW = utils.GetTextSize(hud, footerText, 0.75)
    if not footerW or footerW == 0 then
        footerW = utils.GetStringLength(footerText) * charW * 0.75 * scaleMult
    end
    
    local maxHeaderFooterW = math.max(headerW, tipW, footerW) + padL * 2
    local menuW = math.max(font and 480.0 or 400.0, contentW, maxHeaderFooterW)

    -- Define menu sizing & positioning (Left side HUD, modern layout)
    local rowH = font and (28.0 + 8.0 * scaleMult) or 34.0
    local menuX = 50.0

    -- Sizing height and offsets dynamically
    local headerOffset = 15.0
    local tipOffset = font and (38.0 + 8.0 * scaleMult) or 38.0
    local topSepOffset = font and (52.0 + 12.0 * scaleMult) or 52.0
    local startYOffset = font and (60.0 + 12.0 * scaleMult) or 65.0
    
    local itemsBottomOffset = startYOffset + #visibleItems * rowH
    local bottomSepOffset = itemsBottomOffset + 12.0
    local footerOffset = bottomSepOffset + 15.0
    local menuH = footerOffset + (font and 25.0 or 20.0)
    
    local menuY = (screenH / 2.0) - (menuH / 2.0)

    -- Draw modern semi-transparent glass panel
    local cardBg = { R = 0.05, G = 0.07, B = 0.15, A = 0.85 }
    local borderCol = { R = 0.0, G = 0.95, B = 1.0, A = 0.6 }
    local borderShadow = { R = 0.0, G = 0.0, B = 0.0, A = 0.9 }

    -- Main panel drop shadow
    hud:DrawRect(borderShadow, menuX - 2.0, menuY - 2.0, menuW + 4.0, menuH + 4.0)
    -- Main background panel
    hud:DrawRect(cardBg, menuX, menuY, menuW, menuH)
    -- Sleek top accent line (Neon Blue)
    hud:DrawRect(borderCol, menuX, menuY, menuW, 3.0)

    -- Header text
    utils.DrawText(hud, headerText, { R = 0.0, G = 0.95, B = 1.0, A = 1.0 }, menuX + padL, menuY + headerOffset, 1.2, false)

    -- Subheader keybind tips
    utils.DrawText(hud, tipText, { R = 0.6, G = 0.6, B = 0.7, A = 1.0 }, menuX + padL, menuY + tipOffset, 0.75, false)

    -- Separator line
    hud:DrawRect({ R = 0.2, G = 0.2, B = 0.3, A = 0.4 }, menuX + padL, menuY + topSepOffset, menuW - padL * 2, 1.0)

    -- Draw menu items
    for i, item in ipairs(visibleItems) do
        local isSelected = (i == selectedIndex)
        local itemY = menuY + startYOffset + (i - 1) * rowH

        -- Selection highlight background row bar
        if isSelected then
            local highlightBg = { R = 0.0, G = 0.95, B = 1.0, A = 0.15 }
            hud:DrawRect(highlightBg, menuX + padHighlight, itemY - 4.0, menuW - padHighlight * 2, rowH - 4.0)
        end

        -- Color definitions
        local nameColor = isSelected and { R = 0.0, G = 0.95, B = 1.0, A = 1.0 } or
            { R = 0.9, G = 0.9, B = 0.95, A = 1.0 }
        
        local rawVal = item.get()
        local valColor = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
        if item.type == "boolean" then
            valColor = rawVal and { R = 0.0, G = 0.96, B = 0.83, A = 1.0 } or { R = 1.0, G = 0.35, B = 0.37, A = 1.0 }
        elseif item.type == "label" or item.type == "action" then
            valColor = { R = 0.5, G = 0.9, B = 0.5, A = 1.0 }
        end

        -- Name string
        local displayStr = itemNames[i]
        utils.DrawText(hud, displayStr, nameColor, menuX + padText, itemY, 1.0, false)

        -- Value string (aligned right)
        local valueText = formattedValues[i]
        local valW = utils.GetTextSize(hud, valueText, 1.0)
        if not valW or valW == 0 then
            valW = utils.GetStringLength(valueText) * charW * scaleMult
        end
        local valueX = menuX + menuW - valW - padVal
        utils.DrawText(hud, valueText, valColor, valueX, itemY, 1.0, false)
    end

    -- Bottom separator line
    hud:DrawRect({ R = 0.2, G = 0.2, B = 0.3, A = 0.4 }, menuX + padL, menuY + bottomSepOffset, menuW - padL * 2, 1.0)

    -- Footer status / version
    utils.DrawText(hud, footerText, { R = 0.5, G = 0.5, B = 0.6, A = 1.0 }, menuX + padL, menuY + footerOffset, 0.75,
        false)
end

return M
