-- Palworld HUDLocator Mod - Completionist Tracker Engine
-- Module for managing per-region and save-wide completion stats:
-- Effigies, Alphas, Fast Travels, Watch Towers, and Bounties.

local configMod = require("HUDLocator.config")
local logger = require("HUDLocator.logger")
local utils = require("HUDLocator.utils")
local boundary = require("HUDLocator.boundary_tool")
local pois = { Points = {} }

local M = {}

local lastLogged = {
    region = "",
    ft = -1,
    alphas = -1,
    towers = -1,
    bounties = -1,
    effigies = -1,
    journals = -1
}

local REGION_META = {
    { id = "grasslands", name = "Grasslands & Central Isles" },
    { id = "volcano", name = "Mount Obsidian" },
    { id = "desert", name = "Desiccated Desert" },
    { id = "snow", name = "Astral Mountains" },
    { id = "sakurajima", name = "Sakurajima" },
    { id = "feybreak", name = "Feybreak" },
    { id = "sunreach", name = "Sunreach" },
    { id = "xenolord", name = "Deserted Islet" },
    { id = "sanctuaries", name = "Wildlife Sanctuaries" },
    { id = "worldtree", name = "World Tree Base" },
    { id = "worldtreemap", name = "World Tree" },
    { id = "oilrigs", name = "Oil Rigs" },
    { id = "outer", name = "Outer Isles" }
}

local regionById = {}
M.Regions = {}
for _, meta in ipairs(REGION_META) do
    local reg = {
        id = meta.id,
        name = meta.name,
        icon = "[*]",
        totals = { effigies = 0, journals = 0, alphas = 0, fastTravels = 0, towers = 0, bounties = 0, hacks = 0 }
    }
    regionById[meta.id] = reg
    table.insert(M.Regions, reg)
end

-- Current active player state & stats cache
M.currentRegionId = "grasslands"
M.currentRegionName = "Grasslands & Central Isles"
M.cachedRegionStats = {}
local function SumTotals(field)
    local total = 0
    for _, reg in ipairs(M.Regions) do
        total = total + (reg.totals[field] or 0)
    end
    return total
end

M.globalSaveProgress = {
    unlockedFastTravels = 0,
    totalFastTravels = SumTotals("fastTravels"),
    defeatedAlphas = 0,
    totalAlphas = SumTotals("alphas"),
    defeatedTowers = 0,
    totalTowers = SumTotals("towers"),
    clearedBounties = 0,
    totalBounties = SumTotals("bounties"),
    collectedEffigies = 0,
    totalEffigies = SumTotals("effigies"),
    collectedJournals = 0,
    totalJournals = SumTotals("journals"),
    collectedHacks = 0,
    totalHacks = SumTotals("hacks"),
    overallPercent = 0
}

-- Only RemoteUnrealParam has get(). Indexing get on a script struct throws,
-- because UE4SS looks up a property named Get and aborts the read.
local function Unwrap(value)
    if type(value) ~= "userdata" then return value end
    local label = nil
    local okLabel, labeled = pcall(function() return tostring(value) end)
    if okLabel then label = labeled end
    if type(label) ~= "string" or not string.find(label, "RemoteUnrealParam", 1, true) then
        return value
    end
    local inner = nil
    local ok = pcall(function() inner = value:get() end)
    if ok and inner ~= nil then return inner end
    return value
end

local function NormKey(value)
    local text = ""
    if type(value) == "string" then
        text = value
    elseif value ~= nil then
        pcall(function()
            if value.ToString then text = value:ToString() end
        end)
        if type(text) ~= "string" then text = "" end
        if text == "" or string.find(text, "RemoteUnrealParam", 1, true) then
            text = utils.FNameToString(value)
        end
    end
    if type(text) ~= "string" then text = "" end
    if string.find(text, "RemoteUnrealParam", 1, true) then text = "" end
    text = string.gsub(text, "^EPalBossType::", "")
    text = string.gsub(text, "[%s%-%{%}]", "")
    return string.lower(text)
end

local function FlagIsTrue(value)
    value = Unwrap(value)
    if value == true or value == 1 then return true end
    if type(value) == "number" then return value > 0 end
    if type(value) == "string" then
        local lower = string.lower(value)
        return lower == "true" or lower == "1"
    end
    return false
end

-- A missing bool usually means UE4SS could not read the bit, not that the flag is off.
-- Only an explicit false or 0 rejects the entry. Tower defeats do not use this.
local function IsFlagSet(value)
    value = Unwrap(value)
    if value == nil then return true end
    if value == false or value == 0 then return false end
    if type(value) == "number" then return value > 0 end
    if type(value) == "string" then
        local lower = string.lower(value)
        return lower ~= "false" and lower ~= "0"
    end
    return true
end

-- Story towers. The save key is often the row name or a difficulty suffix, not the bare enum.
local BOSS_TYPES = {
    { id = "GrassBoss", value = 1 },
    { id = "ElectricBoss", value = 2 },
    { id = "ForestBoss", value = 3 },
    { id = "SnowBoss", value = 4 },
    { id = "DesertBoss", value = 5 },
    { id = "SakurajimaBoss", value = 6 },
    { id = "VikingBoss", value = 7 },
    { id = "SorajimaBoss", value = 8 },
    { id = "KingWhaleBoss", value = 9 },
    { id = "WorldTreeMiddleBoss1", value = 10 },
    { id = "WorldTreeMiddleBoss2", value = 11 },
    { id = "WorldTreeMiddleBoss3", value = 12 },
    { id = "WorldTreeBoss", value = 13 },
}

local function TowerStoredMatches(stored, key)
    if stored == key or stored == "boss_battle_name_" .. key then return true end
    local prefixed = "boss_battle_name_" .. key .. "_"
    if string.sub(stored, 1, #prefixed) == prefixed then return true end
    return false
end

local function AbsorbTowerKeys(from, into)
    for stored, on in pairs(from) do
        if on then
            into[stored] = true
            for _, boss in ipairs(BOSS_TYPES) do
                local key = NormKey(boss.id)
                if TowerStoredMatches(stored, key) then into[key] = true end
            end
        end
    end
end

local function ForEachEntry(arrayLike, fn)
    arrayLike = Unwrap(arrayLike)
    if not arrayLike then return 0 end
    local seen = 0
    local function take(elem)
        elem = Unwrap(elem)
        if elem == nil then return end
        seen = seen + 1
        fn(elem)
    end

    if type(arrayLike) == "table" then
        for _, elem in ipairs(arrayLike) do take(elem) end
        return seen
    end

    local count = 0
    pcall(function()
        if arrayLike.GetArrayNum then count = arrayLike:GetArrayNum() end
    end)
    if type(count) ~= "number" or count < 1 then
        pcall(function()
            if arrayLike.Num then
                local num = arrayLike.Num
                if type(num) == "function" then count = arrayLike:Num() else count = num end
            end
        end)
    end
    if type(count) == "number" and count > 0 then
        if count > 4000 then count = 4000 end
        for i = 1, count do
            local elem = nil
            pcall(function() elem = arrayLike[i] end)
            if elem == nil then pcall(function() elem = arrayLike:Get(i) end) end
            if elem == nil then pcall(function() elem = arrayLike:Get(i - 1) end) end
            take(elem)
        end
        if seen > 0 then return seen end
    end

    local hasForEach = false
    if type(arrayLike) == "userdata" then
        pcall(function() hasForEach = arrayLike.ForEach ~= nil end)
    end
    if hasForEach then
        pcall(function()
            arrayLike:ForEach(function(a, b)
                local elem = b
                if type(a) ~= "number" or elem == nil then elem = a end
                take(elem)
            end)
        end)
    end
    return seen
end

local function CollectBoolFlags(flagObj, strict)
    local set = {}
    if type(flagObj) ~= "userdata" then return set, 0 end
    local items = nil
    local gotItems = pcall(function() items = flagObj.Items end)
    if not gotItems or items == nil then return set, 0 end
    items = Unwrap(items)
    local seen = ForEachEntry(items, function(entry)
        local key, value = nil, nil
        pcall(function()
            key = entry.Key
            value = entry.Value
        end)
        if key == nil then
            pcall(function() key = entry:GetPropertyValue("Key") end)
        end
        if value == nil then
            pcall(function() value = entry:GetPropertyValue("Value") end)
        end
        if key and (strict and FlagIsTrue(value) or (not strict and IsFlagSet(value))) then
            local norm = NormKey(key)
            if norm ~= "" then set[norm] = true end
        end
    end)
    return set, seen
end

local function SafeCollect(flagObj, strict)
    local ok, set, seen = pcall(CollectBoolFlags, flagObj, strict)
    if not ok then
        if not M._loggedFlagRead then
            M._loggedFlagRead = true
            print("[HUDLocator] Completion flag read failed: " .. tostring(set) .. "\n")
        end
        return {}, 0
    end
    if type(set) ~= "table" then return {}, 0 end
    return set, seen or 0
end

local function CollectMapFlags(mapObj)
    local set = {}
    if type(mapObj) ~= "userdata" then return set end
    local canWalk = false
    pcall(function() canWalk = mapObj.ForEach ~= nil end)
    if not canWalk then return set end
    pcall(function()
        mapObj:ForEach(function(key, value)
            if IsFlagSet(value) then
                local norm = NormKey(key)
                if norm ~= "" then set[norm] = true end
            end
        end)
    end)
    return set
end

local function MergeSets(into, extra)
    for key, value in pairs(extra) do
        if value then into[key] = true end
    end
end

local function SetCount(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end

-- UPalPlayerRecordData stores one bool map per statue effect. ByType exists only
-- on the serialized save struct, so the live record never exposes it.
local RELIC_FLAG_FIELDS = {
    "RelicObtainForInstanceFlag_CapturePower",
    "RelicObtainForInstanceFlag_HungerReduction",
    "RelicObtainForInstanceFlag_SwimSpeed",
    "RelicObtainForInstanceFlag_FoodDecayReduction",
    "RelicObtainForInstanceFlag_JumpPower",
    "RelicObtainForInstanceFlag_GliderSpeed",
    "RelicObtainForInstanceFlag_ClimbSpeed",
    "RelicObtainForInstanceFlag_StatusAilmentResist",
    "RelicObtainForInstanceFlag_StaminaReduction",
    "RelicObtainForInstanceFlag_SphereHoming",
    "RelicObtainForInstanceFlag_ExpBonus",
    "RelicObtainForInstanceFlag_RainbowPassiveRate",
    "RelicObtainForInstanceFlag_MoveSpeed",
}

local function CollectRelicFlags(recordData)
    local set = {}
    local lifmunk = 0
    local other = 0
    local parts = {}
    for _, name in ipairs(RELIC_FLAG_FIELDS) do
        local flagObj = nil
        pcall(function() flagObj = recordData[name] end)
        local flags = SafeCollect(flagObj)
        local count = SetCount(flags)
        MergeSets(set, flags)
        if name == "RelicObtainForInstanceFlag_CapturePower" then
            lifmunk = count
        else
            other = other + count
            if count > 0 then
                parts[#parts + 1] = string.match(name, "([^_]+)$") .. " " .. count
            end
        end
    end
    MergeSets(set, SafeCollect(recordData.RelicObtainForInstanceFlag))
    if not M._loggedRelicFlags then
        M._loggedRelicFlags = true
        local detail = ""
        if #parts > 0 then detail = " (" .. table.concat(parts, ", ") .. ")" end
        print(string.format(
            "[HUDLocator] Effigy save flags: lifmunk %d, other types %d%s.\n",
            lifmunk, other, detail))
    end
    return set, SetCount(set)
end

local function FlagHas(set, id)
    local key = NormKey(id)
    if key == "" then return false end
    return set[key] == true
end

-- Technology data asks the game whether this tower boss has been defeated.
local function MergeTechnologyTowers(playerState, into)
    local tech = nil
    pcall(function() tech = playerState.TechnologyData end)
    if type(tech) ~= "userdata" then return end
    local canCall = false
    pcall(function() canCall = tech.IsTowerBossRequirementSatisfied ~= nil end)
    if not canCall then return end
    for _, boss in ipairs(BOSS_TYPES) do
        local ok, result = pcall(function()
            return tech:IsTowerBossRequirementSatisfied("EPalBossType::" .. boss.id)
        end)
        if not ok then
            ok, result = pcall(function()
                return tech:IsTowerBossRequirementSatisfied(boss.value)
            end)
        end
        if ok and (result == true or result == 1) then
            into[NormKey(boss.id)] = true
        end
    end
end

local function QuestMentionsBoss(quest, key)
    if string.sub(quest, -#key) == key then return true end
    local token = "_" .. key
    local at = 1
    while true do
        local i = string.find(quest, token, at, true)
        if not i then return false end
        local after = string.sub(quest, i + #token, i + #token)
        if after == "" or not string.match(after, "%w") then return true end
        at = i + 1
    end
end

local function MergeQuestTowers(playerState, into)
    local manager = nil
    pcall(function() manager = playerState.QuestManager end)
    if type(manager) ~= "userdata" then return end
    local names = nil
    local ok = pcall(function()
        if manager.GetAllCompletedQuestId then
            names = manager:GetAllCompletedQuestId()
        else
            names = manager.CompletedQuestNames
        end
    end)
    if not ok or names == nil then return end
    ForEachEntry(names, function(entry)
        local quest = NormKey(entry)
        if quest == "" then return end
        for _, boss in ipairs(BOSS_TYPES) do
            local key = NormKey(boss.id)
            if QuestMentionsBoss(quest, key) then into[key] = true end
        end
    end)
end

-- Map squares from DT_WorldMapUIData. These match the rows PalMiniMap
-- decoded (main island, then the World Tree island). A live read replaces
-- them, and the open world-map widget replaces them again if a patch moves
-- the world.
local mapAreas = {
    { main = true, minX = -1099400, minY = -724400, maxX = 349400, maxY = 724400 },
    { main = false, minX = 347351.5, minY = -818197, maxX = 689148.5, maxY = -476400 },
}
local mapBoundsFromGame = false
local mapCalibrateTries = 0
local mapCalibrateAt = -1000

local function MainArea()
    for _, area in ipairs(mapAreas) do
        if area.main then return area end
    end
    return mapAreas[1]
end

local function ParseVec(text)
    if type(text) ~= "string" then return nil end
    local x = tonumber(string.match(text, "[Xx]%s*=%s*([%-%.%d]+)"))
    local y = tonumber(string.match(text, "[Yy]%s*=%s*([%-%.%d]+)"))
    if not x or not y then return nil end
    return x, y
end

local function ColumnStrings(lib, tableObj, prop)
    local list = {}
    local column = nil
    local ok = pcall(function()
        column = lib:GetDataTableColumnAsString(tableObj, FName(prop))
    end)
    if not ok or not column then return list end
    ForEachEntry(column, function(elem)
        local text = ""
        if type(elem) == "string" then
            text = elem
        elseif elem ~= nil then
            pcall(function()
                if elem.ToString then
                    local s = elem:ToString()
                    if type(s) == "string" then text = s end
                end
            end)
        end
        if text ~= "" then list[#list + 1] = text end
    end)
    return list
end

local function FindMapTable()
    local tableObj = nil
    pcall(function()
        local player = utils.Player()
        local state = player and player.PlayerState
        if not state or not state:IsValid() then return end
        local data = state.WorldMapData
        if (not data or not data:IsValid()) and state.GetWorldMapData then
            data = state:GetWorldMapData()
        end
        if data and data:IsValid() then tableObj = data.WorldMapDataTable end
    end)
    if tableObj and tableObj.IsValid and tableObj:IsValid() then return tableObj end
    local paths = {
        "/Game/Pal/DataTable/WorldMapUIData/DT_WorldMapUIData.DT_WorldMapUIData",
        "/Game/Pal/DataTable/WorldMapUIData/DT_WorldMapUIData",
    }
    for _, path in ipairs(paths) do
        local obj = nil
        pcall(function() obj = StaticFindObject(path) end)
        if obj and obj.IsValid and obj:IsValid() then return obj end
    end
    return nil
end

local function ApplyParsedAreas(mins, maxs)
    if #mins < 1 or #mins ~= #maxs then return false end
    local areas = {}
    local biggest, bigSpan = 1, -1
    for i = 1, #mins do
        local minX, minY = ParseVec(mins[i])
        local maxX, maxY = ParseVec(maxs[i])
        if not minX or not maxX or maxX <= minX or maxY <= minY then return false end
        local span = (maxX - minX) * (maxY - minY)
        areas[i] = { main = false, minX = minX, minY = minY, maxX = maxX, maxY = maxY }
        if span > bigSpan then
            bigSpan = span
            biggest = i
        end
    end
    areas[biggest].main = true
    mapAreas = areas
    return true
end

local function ReadMapTable()
    local tableObj = FindMapTable()
    if not tableObj then return false end
    local lib = nil
    pcall(function() lib = StaticFindObject("/Script/Engine.Default__DataTableFunctionLibrary") end)
    if not lib or not lib.IsValid or not lib:IsValid() then return false end
    local mins = ColumnStrings(lib, tableObj, "landScapeRealPositionMin")
    local maxs = ColumnStrings(lib, tableObj, "landScapeRealPositionMax")
    if not ApplyParsedAreas(mins, maxs) then return false end
    if not mapBoundsFromGame then
        mapBoundsFromGame = true
        local main = MainArea()
        print(string.format(
            "[HUDLocator] Map bounds from DT_WorldMapUIData: (%.0f, %.0f)..(%.0f, %.0f), %d areas\n",
            main.minX, main.minY, main.maxX, main.maxY, #mapAreas))
    end
    return true
end

local function VecXY(value)
    if value == nil then return nil end
    local x, y = nil, nil
    pcall(function() x = value.X end)
    pcall(function() y = value.Y end)
    if type(x) == "number" and type(y) == "number" then return x, y end
    return nil
end

local function ApplyWidgetBounds(minX, minY, maxX, maxY)
    if not minX or not maxX or maxX - minX < 10000 or maxY - minY < 10000 then return false end
    local cx, cy = (minX + maxX) * 0.5, (minY + maxY) * 0.5
    local best, bestD = nil, nil
    for _, area in ipairs(mapAreas) do
        local ax = (area.minX + area.maxX) * 0.5
        local ay = (area.minY + area.maxY) * 0.5
        local d = (ax - cx) * (ax - cx) + (ay - cy) * (ay - cy)
        if not bestD or d < bestD then
            best, bestD = area, d
        end
    end
    if not best then return false end
    local changed = math.abs(best.minX - minX) > 1 or math.abs(best.minY - minY) > 1
        or math.abs(best.maxX - maxX) > 1 or math.abs(best.maxY - maxY) > 1
    best.minX, best.minY, best.maxX, best.maxY = minX, minY, maxX, maxY
    if changed then
        print(string.format(
            "[HUDLocator] Map bounds calibrated from the map widget: (%.0f, %.0f)..(%.0f, %.0f)\n",
            minX, minY, maxX, maxY))
    end
    return true
end

-- The map widget exists only after the world map has been opened. Same
-- backoff PalMiniMap uses: FindAllOf walks every UObject.
local function CalibrateFromMapWidget()
    if mapCalibrateTries >= 12 then return end
    local now = os.clock()
    if now < mapCalibrateAt then return end
    mapCalibrateAt = now + 20
    mapCalibrateTries = mapCalibrateTries + 1
    local widgets = nil
    pcall(function() widgets = FindAllOf("WBP_Map_Body_C") end)
    if not widgets then return end
    for _, widget in ipairs(widgets) do
        local got = false
        pcall(function()
            if not widget:IsValid() then return end
            local full = widget:GetFullName()
            if not full or string.find(full, "Default__", 1, true) then return end
            local minX, minY = VecXY(widget.MinLandScapePosition)
            local maxX, maxY = VecXY(widget.MaxLandScapePosition)
            if not minX then minX, minY = VecXY(widget.landScapeRealPositionMin) end
            if not maxX then maxX, maxY = VecXY(widget.landScapeRealPositionMax) end
            if ApplyWidgetBounds(minX, minY, maxX, maxY) then got = true end
        end)
        if got then
            mapCalibrateTries = 12
            return
        end
    end
end

local function RefreshMapBounds()
    if not mapBoundsFromGame then ReadMapTable() end
    CalibrateFromMapWidget()
end

local function InsideArea(area, x, y)
    return x >= area.minX and x <= area.maxX and y >= area.minY and y <= area.maxY
end

-- The drawn "worldtree" polygon is the foot of the tree on the main map.
-- The separate World Tree map is the other square from DT_WorldMapUIData.
local function InSeparateWorldTree(x, y)
    local main = MainArea()
    if not main then return false end
    for _, area in ipairs(mapAreas) do
        if not area.main and InsideArea(area, x, y) and not InsideArea(main, x, y) then
            return true
        end
    end
    return false
end

-- DT_WorldMapAreaData row name, or the English area label, onto a tracker region.
local function AreaToRegion(name)
    local s = NormKey(name)
    if s == "" or s == "none" then return nil end
    if string.find(s, "worldtree", 1, true) then return "worldtree" end
    if string.find(s, "xenolord", 1, true) then return "xenolord" end
    if string.find(s, "sanctuary", 1, true) then return "sanctuaries" end
    if string.find(s, "sakura", 1, true) or string.find(s, "yakushima", 1, true) then return "sakurajima" end
    if string.find(s, "feybreak", 1, true) or string.find(s, "yamijima", 1, true) then return "feybreak" end
    if string.find(s, "sunreach", 1, true) or string.find(s, "skyisland", 1, true) then return "sunreach" end
    if string.find(s, "desert", 1, true) or string.find(s, "dessert", 1, true) then return "desert" end
    if string.find(s, "volcano", 1, true) or string.find(s, "obsidian", 1, true) then return "volcano" end
    if string.find(s, "snow", 1, true) or string.find(s, "astral", 1, true) or string.find(s, "glacial", 1, true) then return "snow" end
    if string.find(s, "grass", 1, true) or string.find(s, "forest", 1, true) or string.find(s, "plain", 1, true) then return "grasslands" end
    return nil
end

local function ToLocal(dx, dy, dz, pitch, yaw, roll)
    local p = math.rad(pitch or 0)
    local y = math.rad(yaw or 0)
    local r = math.rad(roll or 0)
    local cp, sp = math.cos(p), math.sin(p)
    local cy, sy = math.cos(y), math.sin(y)
    local cr, sr = math.cos(r), math.sin(r)
    local xx, xy, xz = cp * cy, cp * sy, sp
    local yx = sr * sp * cy - cr * sy
    local yy = sr * sp * sy + cr * cy
    local yz = -sr * cp
    local zx = -(cr * sp * cy + sr * sy)
    local zy = cy * sr - cr * sp * sy
    local zz = cr * cp
    return dx * xx + dy * xy + dz * xz,
           dx * yx + dy * yy + dz * yz,
           dx * zx + dy * zy + dz * zz
end

local regionVolumes = nil
local volumeRefreshAt = -1000
local volumesLogged = false

local function VolumeContains(v, x, y, z)
    local pad = 200
    if v.kind == "sphere" then
        if not z and (math.abs(v.z) - v.radius) > 40000 then return false end
        local dx, dy = x - v.x, y - v.y
        local d2 = dx * dx + dy * dy
        if z then
            local dz = z - v.z
            d2 = d2 + dz * dz
        end
        local limit = v.radius + pad
        return d2 <= limit * limit
    end
    -- A point with no height should not join a sky-only slab.
    if not z and (v.z - v.ez) > 40000 then return false end
    local lx, ly, lz = ToLocal(x - v.x, y - v.y, (z or v.z) - v.z, v.pitch, v.yaw, v.roll)
    if math.abs(lx) > v.ex + pad or math.abs(ly) > v.ey + pad then return false end
    if z and math.abs(lz) > v.ez + pad then return false end
    return true
end

local function VolumeRegionId(x, y, z)
    if not regionVolumes or #regionVolumes == 0 then return nil end
    local best, bestArea = nil, nil
    for i = 1, #regionVolumes do
        local v = regionVolumes[i]
        if v.region and VolumeContains(v, x, y, z) then
            if not bestArea or v.area < bestArea then
                best = v.region
                bestArea = v.area
            end
        end
    end
    return best
end

local function ReadAreaName(actor)
    local text = ""
    pcall(function()
        local area = actor.AreaName
        local key = area and area.Key or area
        if type(key) == "string" then
            text = key
        elseif key ~= nil then
            pcall(function()
                if key.ToString then
                    local s = key:ToString()
                    if type(s) == "string" then text = s end
                end
            end)
            if text == "" then text = utils.FNameToString(key) end
        end
    end)
    if type(text) ~= "string" then return "" end
    return text
end

local function ExtentOf(comp)
    local ex, ey, ez = nil, nil, nil
    pcall(function()
        local e = nil
        if comp.GetScaledBoxExtent then e = comp:GetScaledBoxExtent() end
        if not e then e = comp.BoxExtent end
        if e then
            ex, ey, ez = e.X, e.Y, e.Z
        end
    end)
    if type(ex) ~= "number" or type(ey) ~= "number" or type(ez) ~= "number" then return nil end
    return math.abs(ex), math.abs(ey), math.abs(ez)
end

local function RadiusOf(comp)
    local radius = nil
    pcall(function()
        if comp.GetScaledSphereRadius then radius = comp:GetScaledSphereRadius() end
        if type(radius) ~= "number" then radius = comp.SphereRadius end
    end)
    if type(radius) ~= "number" then return nil end
    return math.abs(radius)
end

local function CollectVolumes(className, kind, into, unknown)
    local actors = nil
    pcall(function() actors = FindAllOf(className) end)
    if not actors then return end
    for _, actor in ipairs(actors) do
        pcall(function()
            if not actor:IsValid() then return end
            local full = actor:GetFullName()
            if not full or string.find(full, "Default__", 1, true) then return end
            local comp = kind == "box" and actor.Box or actor.Sphere
            if not comp or not comp:IsValid() then return end
            local loc = comp:K2_GetComponentLocation()
            local rot = comp:K2_GetComponentRotation()
            if not loc or not rot then return end
            local name = ReadAreaName(actor)
            local region = AreaToRegion(name) or M.ResolveRegion(loc.X, loc.Y, loc.Z).id
            if name ~= "" and not AreaToRegion(name) and unknown and #unknown < 12 then
                unknown[#unknown + 1] = name
            end
            if kind == "box" then
                local ex, ey, ez = ExtentOf(comp)
                if not ex or ex < 100 or ey < 100 then return end
                into[#into + 1] = {
                    kind = "box", region = region, x = loc.X, y = loc.Y, z = loc.Z or 0,
                    pitch = rot.Pitch or 0, yaw = rot.Yaw or 0, roll = rot.Roll or 0,
                    ex = ex, ey = ey, ez = ez, area = ex * ey
                }
            else
                local radius = RadiusOf(comp)
                if not radius or radius < 100 then return end
                into[#into + 1] = {
                    kind = "sphere", region = region, x = loc.X, y = loc.Y, z = loc.Z or 0,
                    radius = radius, area = radius * radius
                }
            end
        end)
    end
end

local function RefreshRegionVolumes()
    if (os.clock() - volumeRefreshAt) < 20 then return end
    local into = {}
    local unknown = {}
    CollectVolumes("BP_PalRegionTriggerBox_C", "box", into, unknown)
    CollectVolumes("BP_PalRegionTriggerSphere_C", "sphere", into, unknown)
    volumeRefreshAt = os.clock()
    if #into == 0 then return end
    regionVolumes = into
    if not volumesLogged then
        volumesLogged = true
        print(string.format("[HUDLocator] Region borders: %d game volumes.\n", #into))
        if #unknown > 0 then
            print("[HUDLocator] Unmapped area names: " .. table.concat(unknown, ", ") .. "\n")
            end
        end
    end
    
function M.ResolveRegion(x, y, z)
    if not x or not y then return M.Regions[1] end
    local drawn = boundary.RegionAt(x, y)
    if drawn and regionById[drawn] then return regionById[drawn] end
    if InSeparateWorldTree(x, y) then return regionById.worldtreemap or M.Regions[1] end
    local nearest = boundary.NearestRegion(x, y)
    if nearest and regionById[nearest] then return regionById[nearest] end
    return M.Regions[1]
end

local poisClassified = false
local function ClassifyPois()
    if poisClassified then return end
    local misses = {}
    for _, pt in ipairs(pois.Points) do
        local id = nil
        if pt.x and pt.y then
            id = boundary.RegionAt(pt.x, pt.y)
            if not id and InSeparateWorldTree(pt.x, pt.y) then id = "worldtreemap" end
            if not id then
                id = boundary.NearestRegion(pt.x, pt.y)
                local label = (pt.ids and pt.ids[1]) or "?"
                misses[#misses + 1] = string.format(
                    "%s %s at (%.0f, %.0f) -> %s", pt.k or "?", label, pt.x, pt.y, id or "?")
            end
        end
        if id and regionById[id] then
            pt.region = id
        else
            pt.region = pt.r
        end
    end
    poisClassified = true
    if #misses == 0 then return end
    print(string.format(
        "[HUDLocator] %d POIs are outside every drawn boundary and the World Tree map. Using the nearest boundary.\n",
        #misses))
    for i = 1, #misses do
        print("[HUDLocator] " .. misses[i] .. "\n")
    end
end

-- Same borders as the player marker. Points with no world position keep the file tag.
local function PointRegionId(pt)
    if pt.region then return pt.region end
    if pt.x and pt.y then
        return M.ResolveRegion(pt.x, pt.y).id
    end
    return pt.r
end

local function ClearTotals()
    for _, reg in ipairs(M.Regions) do
        reg.totals.effigies = 0
        reg.totals.journals = 0
        reg.totals.alphas = 0
        reg.totals.fastTravels = 0
        reg.totals.towers = 0
        reg.totals.bounties = 0
        reg.totals.hacks = 0
    end
end

local function AddTotal(reg, kind)
    if kind == "ft" then reg.totals.fastTravels = reg.totals.fastTravels + 1
    elseif kind == "tower" then reg.totals.towers = reg.totals.towers + 1
    elseif kind == "bounty" then reg.totals.bounties = reg.totals.bounties + 1
    elseif kind == "alpha" then reg.totals.alphas = reg.totals.alphas + 1
    elseif kind == "effigy" then reg.totals.effigies = reg.totals.effigies + 1
    elseif kind == "journal" then reg.totals.journals = reg.totals.journals + 1
    elseif kind == "hack" then reg.totals.hacks = reg.totals.hacks + 1
    end
end

local function RebuildTotals()
    ClearTotals()
    ClassifyPois()
    for _, pt in ipairs(pois.Points) do
        local id = pt.region or pt.r
        local reg = regionById[id]
        if reg then AddTotal(reg, pt.k) end
    end
    M.globalSaveProgress.totalFastTravels = SumTotals("fastTravels")
    M.globalSaveProgress.totalAlphas = SumTotals("alphas")
    M.globalSaveProgress.totalTowers = SumTotals("towers")
    M.globalSaveProgress.totalBounties = SumTotals("bounties")
    M.globalSaveProgress.totalEffigies = SumTotals("effigies")
    M.globalSaveProgress.totalJournals = SumTotals("journals")
    M.globalSaveProgress.totalHacks = SumTotals("hacks")
end

local function EmptyBuckets()
    local buckets = {}
    for _, reg in ipairs(M.Regions) do
        buckets[reg.id] = { ft = 0, tower = 0, alpha = 0, bounty = 0, effigy = 0, journal = 0, hack = 0 }
    end
    return buckets
end

local function Publish(unlockedByRegion)
    unlockedByRegion = unlockedByRegion or EmptyBuckets()
    local newRegionStats = {}
    for _, reg in ipairs(M.Regions) do
        local bucket = unlockedByRegion[reg.id] or { ft = 0, tower = 0, alpha = 0, bounty = 0, effigy = 0, journal = 0, hack = 0 }
        local rFT = math.min(reg.totals.fastTravels, bucket.ft)
        local rAlpha = math.min(reg.totals.alphas, bucket.alpha)
        local rTower = math.min(reg.totals.towers, bucket.tower)
        local rBounty = math.min(reg.totals.bounties, bucket.bounty)
        local rEffigy = math.min(reg.totals.effigies, bucket.effigy)
        local rJournal = math.min(reg.totals.journals or 0, bucket.journal or 0)
        local rHack = math.min(reg.totals.hacks or 0, bucket.hack or 0)

        local regUnlocked = rFT + rAlpha + rTower + rBounty + rEffigy + rJournal + rHack
        local regTotal = reg.totals.fastTravels + reg.totals.alphas + reg.totals.towers + reg.totals.bounties + reg.totals.effigies + (reg.totals.journals or 0) + (reg.totals.hacks or 0)
        local regPct = (regTotal > 0) and math.floor((regUnlocked / regTotal) * 100) or 0

        newRegionStats[reg.id] = {
            name = reg.name,
            icon = reg.icon,
            isCurrent = (reg.id == M.currentRegionId),
            percent = regPct,
            fastTravels = { unlocked = rFT, total = reg.totals.fastTravels },
            alphas = { defeated = rAlpha, total = reg.totals.alphas },
            towers = { defeated = rTower, total = reg.totals.towers },
            bounties = { cleared = rBounty, total = reg.totals.bounties },
            effigies = { collected = rEffigy, total = reg.totals.effigies },
            journals = { collected = rJournal, total = reg.totals.journals or 0 },
            hacks = { collected = rHack, total = reg.totals.hacks or 0 }
        }
    end
    M.cachedRegionStats = newRegionStats
end

Publish(nil)

local function GuidText(value)
    if value == nil then return "" end
    local text = ""
    pcall(function()
        local a, b, c, d = value.A, value.B, value.C, value.D
        if type(a) == "number" and type(b) == "number" and type(c) == "number" and type(d) == "number" then
            text = string.format("%08x%08x%08x%08x",
                math.floor(a) % 4294967296, math.floor(b) % 4294967296,
                math.floor(c) % 4294967296, math.floor(d) % 4294967296)
        end
    end)
    if text ~= "" then return text end
    return NormKey(value)
end

-- Alphas and bounties come from the boss spawner table. Everything else is
-- created from the actors that are already loaded.
local PLACE_TRIES = 8
local placeTries = 0
local placeLogged = false
local waitingOnOrigin = true
local bossesLoaded = false
local effigyByKey = nil
local noteByKey = nil
local alphaById = nil
local towerById = nil
local hackByKey = nil
local ftByKey = nil

local TOWER_CLASS_KEY = {
    bp_palbosstower_kingwhale_c = "kingwhaleboss",
    bp_palbosstower_lastboss_c = "worldtreelastboss",
}

local function UaidOf(text)
    local s = string.lower(text or "")
    local at = string.find(s, "uaid_", 1, true)
    if not at then return nil end
    return string.sub(s, at)
end

local function BuildPlacementIndexes()
    if effigyByKey then return end
    effigyByKey, noteByKey, alphaById, towerById = {}, {}, {}, {}
    hackByKey, ftByKey = {}, {}
    for _, pt in ipairs(pois.Points) do
        if pt.k == "effigy" then
            for _, id in ipairs(pt.ids or {}) do
                local uaid = UaidOf(id)
                if uaid and not effigyByKey[uaid] then effigyByKey[uaid] = pt end
                local key = NormKey(id)
                if #key >= 8 and not effigyByKey[key] then effigyByKey[key] = pt end
            end
        elseif pt.k == "journal" then
            for _, id in ipairs(pt.ids or {}) do
                local uaid = UaidOf(id)
                if uaid and not noteByKey[uaid] then noteByKey[uaid] = pt end
                local key = NormKey(id)
                if #key >= 8 and not noteByKey[key] then noteByKey[key] = pt end
            end
        elseif pt.k == "alpha" and pt.ids and pt.ids[1] then
            alphaById[string.lower(pt.ids[1])] = pt
        elseif pt.k == "tower" then
            for _, id in ipairs(pt.ids or {}) do
                local key = NormKey(id)
                if key ~= "" and not towerById[key] then towerById[key] = pt end
            end
        end
    end
end

local function UsableLocation(loc)
    if not loc or type(loc.X) ~= "number" or type(loc.Y) ~= "number" then return false end
    -- An unset transform is exactly 0, 0. A point near the origin can still be
    -- a real spot: the world origin sits inside the Astral Mountains.
    if loc.X == 0 and loc.Y == 0 then return false end
    return true
end

local function AssignPosition(pt, loc)
    if not pt or pt.x or not UsableLocation(loc) then return false end
    pt.x, pt.y = loc.X, loc.Y
    return true
end

local function IndexPoint(index, pt)
    for _, id in ipairs(pt.ids or {}) do
        local key = NormKey(id)
        if key ~= "" and not index[key] then index[key] = pt end
        local uaid = UaidOf(id)
        if uaid and not index[uaid] then index[uaid] = pt end
    end
end

local function TakePoint(index, ids)
    for _, id in ipairs(ids) do
        local key = NormKey(id)
        if key ~= "" and index[key] then return index[key] end
        local uaid = UaidOf(id)
        if uaid and index[uaid] then return index[uaid] end
    end
    return nil
end

local function AddPoint(kind, index, ids, loc)
    if not index or not UsableLocation(loc) then return nil, false end
    local pt = TakePoint(index, ids)
    if not pt then
        pt = { k = kind, r = "grasslands", ids = ids }
        pois.Points[#pois.Points + 1] = pt
        IndexPoint(index, pt)
    end
    return pt, AssignPosition(pt, loc)
end

local function IdsForTower(key)
    key = NormKey(key)
    for _, boss in ipairs(BOSS_TYPES) do
        if NormKey(boss.id) == key then
            return { boss.id, "EPalBossType::" .. boss.id }
        end
    end
    if key == "worldtreelastboss" then
        return {
            "WorldTreeLastBoss", "WorldTreeBoss",
            "EPalBossType::WorldTreeLastBoss", "EPalBossType::WorldTreeBoss",
        }
    end
    if key == "kingwhaleboss" or key == "kingwhale" then
        return {
            "KingWhaleBoss", "KingWhale",
            "EPalBossType::KingWhaleBoss", "EPalBossType::KingWhale",
        }
    end
    if key == "" then return nil end
    return { key }
end

local function NoteExplicit(value)
    if value == true or value == 1 then return true end
    if value == false or value == 0 then return false end
    return nil
end

local function ClassNameOf(actor)
    local name = ""
    pcall(function()
        local cls = actor:GetClass()
        if cls and cls.GetName then name = cls:GetName() or "" end
    end)
    return name
end

local function EachOf(className, fn)
    local actors = nil
    pcall(function() actors = FindAllOf(className) end)
    if not actors then return end
    for _, actor in ipairs(actors) do
        pcall(function()
            local full = actor:GetFullName()
            if not full or string.find(full, "Default__", 1, true) then return end
            local loc = actor:K2_GetActorLocation()
            fn(actor, full, loc)
        end)
    end
end

local diagActors = {}
local diagSeen = {}

local function NoteDiag(group, actor, full, loc, matched)
    local x = (loc and type(loc.X) == "number") and loc.X or 0
    local y = (loc and type(loc.Y) == "number") and loc.Y or 0
    local name = full or ""
    if #name > 220 then name = string.sub(name, 1, 220) end
    local key = string.format("%s|%s|%d|%d", group, name,
        math.floor(x / 1000 + 0.5), math.floor(y / 1000 + 0.5))
    if diagSeen[key] then return end
    diagSeen[key] = true
    diagActors[#diagActors + 1] = {
        group = group,
        className = ClassNameOf(actor),
        full = name,
        x = x,
        y = y,
        usable = UsableLocation(loc) and "yes" or "no",
        matched = matched or "",
    }
end

local function PointLabel(pt)
    local ids = pt.ids or {}
    if pt.k == "bounty" or pt.k == "alpha" then return ids[#ids] or "?" end
    if pt.k == "effigy" then return ids[2] or ids[1] or "?" end
    return ids[1] or "?"
end

local function DescribeRegion(x, y)
    local id = boundary.RegionAt(x, y)
    if id then return id, "inside" end
    if InSeparateWorldTree(x, y) then return "worldtreemap", "worldtree-map" end
    return boundary.NearestRegion(x, y) or "", "nearest"
end

local function ReadVector(obj)
    local loc = nil
    pcall(function() loc = obj:K2_GetActorLocation() end)
    if UsableLocation(loc) then return loc end
    pcall(function() loc = obj:GetLocation() end)
    if UsableLocation(loc) then return loc end
    pcall(function()
        local v = obj.Location
        if v and type(v.X) == "number" then loc = v end
    end)
    if UsableLocation(loc) then return loc end
    return nil
end

local function ActorCharacterId(actor)
    local charIdStr = ""
    pcall(function()
        local charParam = actor:GetCharacterParameterComponent()
        if not charParam or not charParam:IsValid() then return end
        local indiv = charParam:GetIndividualParameter()
        if not indiv or not indiv:IsValid() then return end
        local cId = indiv:GetCharacterID()
        if cId then charIdStr = cId:ToString() end
    end)
    return charIdStr
end

local function RawName(value)
    if type(value) == "string" then return value end
    if value == nil then return "" end
    local text = ""
    pcall(function()
        if value.ToString then text = value:ToString() end
    end)
    if type(text) ~= "string" or text == "" or string.find(text, "RemoteUnrealParam", 1, true) then
        local named = utils.FNameToString(value)
        if type(named) == "string" then text = named end
    end
    if type(text) ~= "string" then return "" end
    if string.find(text, "RemoteUnrealParam", 1, true) then return "" end
    return text
end

local function ReadField(obj, name)
    if obj == nil then return nil end
    local value = nil
    local ok = pcall(function() value = obj[name] end)
    if ok and value ~= nil then return value end
    pcall(function()
        if obj.GetPropertyValue then value = obj:GetPropertyValue(name) end
    end)
    return value
end

local function BlankName(value)
    local text = string.lower(value or "")
    return text == "" or text == "none"
end

-- A row with a character id is an alpha, including sealed realms.
-- A row with no character id and a BOSS_ spawner id is a bounty.
-- Oil rigs use REGION_Oilrig and are not tracked.
local function BossRowKind(entry)
    if not BlankName(entry.character) then return "alpha" end
    local spawner = string.lower(entry.spawner or "")
    if string.sub(spawner, 1, 13) == "region_oilrig" then return "oilrig" end
    if string.sub(spawner, 1, 5) == "boss_" then return "bounty" end
    return "other"
end

local cachedBossRows = nil
local cachedBossNote = nil

local function ReadBossTable()
    if cachedBossRows then return cachedBossRows, cachedBossNote end
    local tableRows = {}
    local tableNote = "not read"
    local util, lib, tableObj, access = nil, nil, nil, nil
    pcall(function() util = StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility") end)
    pcall(function() lib = StaticFindObject("/Script/Engine.Default__DataTableFunctionLibrary") end)
    if not util or not util.IsValid or not util:IsValid() then
        tableNote = "no PalMasterDataTablesUtility"
    elseif not lib or not lib.IsValid or not lib:IsValid() then
        tableNote = "no DataTableFunctionLibrary"
    else
        local world = utils.World()
        local ok, err = pcall(function()
            tableObj = util:GetBossSpawnerUIDataTable(world)
            access = util:GetBossSpawnerUIDataTableAccess(world)
        end)
        if (not ok or not tableObj or not tableObj.IsValid or not tableObj:IsValid()) then
            pcall(function()
                local tables = FindAllOf("PalMasterDataTables")
                if tables then
                    for _, obj in ipairs(tables) do
                        local candidate = nil
                        pcall(function() candidate = obj.BossSpawnerUIDataTable end)
                        if candidate and candidate.IsValid and candidate:IsValid() then
                            tableObj = candidate
                            pcall(function() access = obj.Access_BossSpawnerUIDataTable end)
                            break
                        end
                    end
                end
            end)
        end
        if not ok and (not tableObj or not tableObj.IsValid or not tableObj:IsValid()) then
            tableNote = "GetBossSpawnerUIDataTable failed: " .. tostring(err)
        elseif not tableObj or not tableObj.IsValid or not tableObj:IsValid() then
            tableNote = "boss table empty"
        else
            local full = ""
            pcall(function() full = tableObj:GetFullName() or "" end)
            local rowNames = {}
            if access and access.IsValid and access:IsValid() then
                local names = nil
                local namesOk, namesErr = pcall(function() names = access:GetRowNames() end)
                if namesOk and names then
                    ForEachEntry(names, function(elem)
                        local text = RawName(elem)
                        if text ~= "" then rowNames[#rowNames + 1] = text end
                    end)
                elseif not namesOk then
                    full = full .. " row names failed: " .. tostring(namesErr)
                end
            end
            local spawners = ColumnStrings(lib, tableObj, "SpawnerID")
            local characters = ColumnStrings(lib, tableObj, "CharacterID")
            local locations = ColumnStrings(lib, tableObj, "Location")
            local levels = ColumnStrings(lib, tableObj, "Level")
            local count = math.max(#rowNames, #spawners, #characters, #locations, #levels)
            for i = 1, count do
                local x, y, z = nil, nil, nil
                local locText = locations[i] or ""
                if locText ~= "" then
                    x, y = ParseVec(locText)
                    z = tonumber(string.match(locText, "[Zz]%s*=%s*([%-%.%d]+)"))
                end
                tableRows[#tableRows + 1] = {
                    key = rowNames[i] or "",
                    spawner = spawners[i] or "",
                    character = characters[i] or "",
                    x = x, y = y, z = z,
                    level = levels[i] or "",
                    locText = locText,
                }
            end
            local sample = locations[1] or ""
            if #sample > 80 then sample = string.sub(sample, 1, 80) end
            tableNote = string.format(
                "%s names %d spawner %d character %d location %d level %d sample [%s]",
                full ~= "" and full or "table",
                #rowNames, #spawners, #characters, #locations, #levels, sample)
            if #tableRows > 0 then
                cachedBossRows = tableRows
                cachedBossNote = tableNote
            end
        end
    end
    return tableRows, tableNote
end

local function PlacedIdSets()
    local alpha, bounty = {}, {}
    for _, pt in ipairs(pois.Points) do
        local into = nil
        if pt.k == "alpha" then into = alpha
        elseif pt.k == "bounty" then into = bounty end
        if into then
            for _, id in ipairs(pt.ids or {}) do
                local key = string.lower(tostring(id))
                if key ~= "" then into[key] = true end
            end
        end
    end
    return alpha, bounty
end

-- The world map builds alpha and bounty icons from this table.
local function AppendBossSpawnerLog(lines)
    local alphaIds, bountyIds = PlacedIdSets()
    local worldData = nil
    local worldNote = "missing"
    pcall(function()
        local player = utils.Player()
        local state = player and player.PlayerState
        if not state or not state:IsValid() then
            worldNote = "no player state"
            return
        end
        local data = state.WorldMapData
        if (not data or not data:IsValid()) and state.GetWorldMapData then
            data = state:GetWorldMapData()
        end
        if data and data:IsValid() then
            worldData = data
            worldNote = "player state"
        else
            worldNote = "WorldMapData empty"
        end
    end)

    local rows = {}
    local walkNote = "not walked"
    if worldData then
        local mapObj = nil
        pcall(function() mapObj = worldData.AllBossSpawnerUIDataMap end)
        if mapObj == nil then
            walkNote = "AllBossSpawnerUIDataMap missing"
        else
            local canWalk = false
            pcall(function() canWalk = mapObj.ForEach ~= nil end)
            if not canWalk then
                walkNote = "map has no ForEach"
            else
                local walked = 0
                local ok, err = pcall(function()
                    mapObj:ForEach(function(a, b)
                        walked = walked + 1
                        local key, row = a, b
                        if b == nil then key, row = nil, a end
                        local entry = {
                            key = RawName(key),
                            spawner = "",
                            character = "",
                            x = nil, y = nil, z = nil,
                            level = "",
                            arg = string.format("%s,%s", type(a), type(b)),
                        }
                        local readOk, readErr = pcall(function()
                            entry.spawner = RawName(ReadField(row, "SpawnerID"))
                            entry.character = RawName(ReadField(row, "CharacterID"))
                            local loc = ReadField(row, "Location")
                            entry.x, entry.y = VecXY(loc)
                            if loc then
                                local z = nil
                                pcall(function() z = loc.Z end)
                                if type(z) == "number" then entry.z = z end
                            end
                            local level = ReadField(row, "Level")
                            if level ~= nil then entry.level = tostring(level) end
                        end)
                        if not readOk then entry.level = "read failed: " .. tostring(readErr) end
                        rows[#rows + 1] = entry
                    end)
                end)
                local mapNum = nil
                pcall(function()
                    local num = mapObj.Num
                    if type(num) == "function" then mapNum = mapObj:Num()
                    elseif type(num) == "number" then mapNum = num end
                end)
                if ok then
                    walkNote = string.format("ForEach %d, Num %s", walked, tostring(mapNum))
                else
                    walkNote = "ForEach failed: " .. tostring(err)
                end
            end
        end
    end

    local tableRows, tableNote = {}, "not read"
    if #rows == 0 then
        tableRows, tableNote = ReadBossTable()
    end

    local listed = #rows > 0 and rows or tableRows
    local source = #rows > 0 and "world map data" or (#tableRows > 0 and "boss data table" or "none")
    local kindCounts = { alpha = 0, bounty = 0, oilrig = 0, other = 0 }
    local mapExtra = {}
    local covered = { alpha = {}, bounty = {} }

    lines[#lines + 1] = ""
    lines[#lines + 1] = "boss spawner table"
    lines[#lines + 1] = "world map data\t" .. worldNote
    lines[#lines + 1] = "map walk\t" .. walkNote
    lines[#lines + 1] = "data table\t" .. tableNote
    lines[#lines + 1] = "rows used\t" .. source .. "\t" .. #listed
    lines[#lines + 1] = "key\tspawner id\tcharacter id\tworld x\tworld y\tworld z\tlevel\tusable\tkind\tplaced"
    for _, entry in ipairs(listed) do
        local spawnerKey = string.lower(entry.spawner or "")
        local characterKey = string.lower(entry.character or "")
        local kind = BossRowKind(entry)
        kindCounts[kind] = (kindCounts[kind] or 0) + 1
        local placed = "skipped"
        if kind == "oilrig" and alphaIds[spawnerKey] then
            placed = "alpha"
            covered.alpha[spawnerKey] = true
        elseif kind == "alpha" and (alphaIds[spawnerKey] or alphaIds[characterKey]) then
            placed = "alpha"
            covered.alpha[spawnerKey] = true
            if characterKey ~= "" then covered.alpha[characterKey] = true end
        elseif kind == "bounty" and (bountyIds[spawnerKey] or bountyIds[characterKey]) then
            placed = "bounty"
            covered.bounty[spawnerKey] = true
        elseif kind == "alpha" or kind == "bounty" or kind == "oilrig" then
            placed = "no"
            mapExtra[#mapExtra + 1] = entry
        end
        local usable = (type(entry.x) == "number" and type(entry.y) == "number" and not (entry.x == 0 and entry.y == 0)) and "yes" or "no"
        lines[#lines + 1] = string.format("%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s",
            entry.key or "",
            entry.spawner or "",
            entry.character or "",
            type(entry.x) == "number" and string.format("%.0f", entry.x) or (entry.locText or ""),
            type(entry.y) == "number" and string.format("%.0f", entry.y) or "",
            type(entry.z) == "number" and string.format("%.0f", entry.z) or "",
            entry.level or "",
            usable,
            kind,
            placed)
    end

    local fileMiss = {}
    for _, pt in ipairs(pois.Points) do
        if pt.k == "alpha" or pt.k == "bounty" then
            local key = string.lower((pt.ids and pt.ids[1]) or "")
            if key == "" or not covered[pt.k][key] then fileMiss[#fileMiss + 1] = pt end
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("row kinds\talpha %d\tbounty %d\toil rig %d\tother %d",
        kindCounts.alpha, kindCounts.bounty, kindCounts.oilrig, kindCounts.other)
    lines[#lines + 1] = "placed points missing from the boss table (" .. #fileMiss .. ")"
    lines[#lines + 1] = "kind\tlabel\tids"
    for _, pt in ipairs(fileMiss) do
        lines[#lines + 1] = string.format("%s\t%s\t%s", pt.k, PointLabel(pt), table.concat(pt.ids or {}, " | "))
    end
    lines[#lines + 1] = "boss rows that were not placed (" .. #mapExtra .. ")"
    lines[#lines + 1] = "key\tspawner id\tcharacter id"
    local extraLimit = math.min(#mapExtra, 80)
    for i = 1, extraLimit do
        local entry = mapExtra[i]
        lines[#lines + 1] = string.format("%s\t%s\t%s", entry.key or "", entry.spawner or "", entry.character or "")
    end
    if #mapExtra > extraLimit then
        lines[#lines + 1] = string.format("... %d more", #mapExtra - extraLimit)
    end

    print(string.format(
        "[HUDLocator] Boss spawner table: %d rows from %s. Alpha rows %d, bounty rows %d, oil rigs %d, unplaced %d.\n",
        #listed, source, kindCounts.alpha, kindCounts.bounty, kindCounts.oilrig, #mapExtra))
end

local function WritePoiLog()
    local lines = {}
    lines[#lines + 1] = "unmatched points (no live world position)"
    lines[#lines + 1] = "kind\tlabel\tfile region\tids"
    for _, pt in ipairs(pois.Points) do
        if (pt.k == "effigy" or pt.k == "alpha" or pt.k == "tower") and not (pt.x and pt.y) then
            lines[#lines + 1] = string.format("%s\t%s\t%s\t%s",
                pt.k, PointLabel(pt), pt.r or "", table.concat(pt.ids or {}, " | "))
        end
    end

    local ftPoints = {}
    for _, pt in ipairs(pois.Points) do
        if pt.k == "ft" then ftPoints[#ftPoints + 1] = pt end
    end
    table.sort(ftPoints, function(a, b)
        local ra = a.region or a.r or ""
        local rb = b.region or b.r or ""
        if ra ~= rb then return ra < rb end
        local ia = (a.ids and a.ids[1]) or ""
        local ib = (b.ids and b.ids[1]) or ""
        return ia < ib
    end)
    local nearOther = {}
    for i = 1, #ftPoints do
        local a = ftPoints[i]
        if a.x and a.y then
            for j = i + 1, #ftPoints do
                local b = ftPoints[j]
                if b.x and b.y then
                    local dx, dy = a.x - b.x, a.y - b.y
                    if dx * dx + dy * dy <= 5000 * 5000 then
                        local aName = (a.ids and a.ids[1]) or "?"
                        local bName = (b.ids and b.ids[1]) or "?"
                        nearOther[a] = nearOther[a] and (nearOther[a] .. ", " .. bName) or bName
                        nearOther[b] = nearOther[b] and (nearOther[b] .. ", " .. aName) or aName
                    end
                end
            end
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "fast travel points (" .. #ftPoints .. ")"
    lines[#lines + 1] = "region\tworld x\tworld y\tunlocked\twithin 50m\tids"
    for _, pt in ipairs(ftPoints) do
        local unlocked = "unknown"
        if pt.unlocked == true then unlocked = "yes"
        elseif pt.unlocked == false then unlocked = "no" end
        local region, how = "", ""
        if pt.x and pt.y then region, how = DescribeRegion(pt.x, pt.y) end
        lines[#lines + 1] = string.format("%s\t%s\t%s\t%s\t%s\t%s",
            region ~= "" and (region .. " (" .. how .. ")") or (pt.region or pt.r or ""),
            pt.x and string.format("%.0f", pt.x) or "",
            pt.y and string.format("%.0f", pt.y) or "",
            unlocked,
            nearOther[pt] or "",
            table.concat(pt.ids or {}, " | "))
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "live fast travel actors"
    lines[#lines + 1] = "class\tworld x\tworld y\tusable\tscan class\tpoint id\tguid\tdisposition\tname"
    for _, row in ipairs(diagActors) do
        if row.group == "ft" then
            lines[#lines + 1] = string.format("%s\t%.0f\t%.0f\t%s\t%s\t%s",
                row.className, row.x, row.y, row.usable, row.matched, row.full)
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "placed towers"
    lines[#lines + 1] = "id\tworld x\tworld y\tfile region\tboundary\thow"
    for _, pt in ipairs(pois.Points) do
        if pt.k == "tower" and pt.x and pt.y then
            local region, how = DescribeRegion(pt.x, pt.y)
            lines[#lines + 1] = string.format("%s\t%.0f\t%.0f\t%s\t%s\t%s",
                (pt.ids and pt.ids[1]) or "?", pt.x, pt.y, pt.r or "", region, how)
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "live tower actors"
    lines[#lines + 1] = "class\tworld x\tworld y\tusable\tmatched id\tname"
    local relicMisses = 0
    for _, row in ipairs(diagActors) do
        if row.group == "tower" then
            lines[#lines + 1] = string.format("%s\t%.0f\t%.0f\t%s\t%s\t%s",
                row.className, row.x, row.y, row.usable, row.matched, row.full)
        elseif row.group == "relic" then
            relicMisses = relicMisses + 1
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "relic actors that did not match an effigy (" .. relicMisses .. ")"
    lines[#lines + 1] = "class\tworld x\tworld y\tusable\tnote\tname"
    for _, row in ipairs(diagActors) do
        if row.group == "relic" then
            lines[#lines + 1] = string.format("%s\t%.0f\t%.0f\t%s\t%s\t%s",
                row.className, row.x, row.y, row.usable, row.matched, row.full)
        end
    end

    local classCounts = {}
    local bossRows = {}
    local spawnerCount = 0
    for _, row in ipairs(diagActors) do
        if row.group == "spawner" then
            spawnerCount = spawnerCount + 1
            local className = row.className ~= "" and row.className or "?"
            classCounts[className] = (classCounts[className] or 0) + 1
            local blob = string.lower(row.className .. " " .. row.full)
            if string.find(blob, "boss", 1, true) then
                bossRows[#bossRows + 1] = row
            end
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "spawner actors seen: " .. spawnerCount
    lines[#lines + 1] = "class\tcount"
    local classRows = {}
    for className, count in pairs(classCounts) do
        classRows[#classRows + 1] = { className = className, count = count }
    end
    table.sort(classRows, function(a, b) return a.count > b.count end)
    local classLimit = math.min(#classRows, 30)
    for i = 1, classLimit do
        lines[#lines + 1] = string.format("%s\t%d", classRows[i].className, classRows[i].count)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "spawner actors whose name contains boss (" .. #bossRows .. ")"
    lines[#lines + 1] = "class\tworld x\tworld y\tusable\tmatched id\tname"
    local bossLimit = math.min(#bossRows, 100)
    for i = 1, bossLimit do
        local row = bossRows[i]
        lines[#lines + 1] = string.format("%s\t%.0f\t%.0f\t%s\t%s\t%s",
            row.className, row.x, row.y, row.usable, row.matched, row.full)
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "bounties"
    lines[#lines + 1] = "name\tcharacter id\tfile region\tstored x\tstored y\tboundary\thow\tlive x\tlive y\tdistance m\tmatch"
    local liveById = {}
    local npcClasses = {
        "BP_NPC_Base_C",
        "BP_NPC_NewBase_C",
        "BP_NPC_StandardHumanDataSet_C",
        "BP_NPC_FatHumanDataSet_C",
        "BP_NPC_Female_Soldier_C",
        "BP_NPC_DarkTrader_C",
    }
    for _, className in ipairs(npcClasses) do
        local actors = nil
        pcall(function() actors = FindAllOf(className) end)
        if actors then
            for _, actor in ipairs(actors) do
                pcall(function()
                    local full = actor:GetFullName()
                    if not full or string.find(full, "Default__", 1, true) then return end
                    local charId = ActorCharacterId(actor)
                    if charId == "" then return end
                    local loc = actor:K2_GetActorLocation()
                    if not UsableLocation(loc) then return end
                    local keys = { string.lower(charId), NormKey(charId) }
                    for _, key in ipairs(keys) do
                        if key ~= "" then
                            local list = liveById[key]
                            if not list then
                                list = {}
                                liveById[key] = list
                            end
                            list[#list + 1] = { x = loc.X, y = loc.Y }
                        end
                    end
                end)
            end
        end
    end
    for _, pt in ipairs(pois.Points) do
        if pt.k == "bounty" and pt.x and pt.y then
            local region, how = DescribeRegion(pt.x, pt.y)
            local best = nil
            local bestDist = nil
            for _, id in ipairs(pt.ids or {}) do
                local lists = { liveById[string.lower(id)], liveById[NormKey(id)] }
                for _, list in ipairs(lists) do
                    if list then
                        for _, loc in ipairs(list) do
                            local dx, dy = loc.x - pt.x, loc.y - pt.y
                            local dist = dx * dx + dy * dy
                            if not bestDist or dist < bestDist then
                                bestDist = dist
                                best = loc
                            end
                        end
                    end
                end
            end
            local liveX, liveY, meters, match = "", "", "", "unloaded"
            if best and bestDist then
                liveX = string.format("%.0f", best.x)
                liveY = string.format("%.0f", best.y)
                meters = string.format("%.1f", math.sqrt(bestDist) / 100)
                match = bestDist <= 2000 * 2000 and "yes" or "no"
            end
            lines[#lines + 1] = string.format("%s\t%s\t%s\t%.0f\t%.0f\t%s\t%s\t%s\t%s\t%s\t%s",
                PointLabel(pt), (pt.ids and pt.ids[1]) or "", pt.r or "",
                pt.x, pt.y, region, how, liveX, liveY, meters, match)
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "map markers and other classes (not used for placement)"
    lines[#lines + 1] = "probe\tclass\tcount"
    local probeClasses = {
        "PalBossTower",
        "PalNPCSpawnerBase",
        "PalLocationPoint_BossTower",
        "PalLocationPoint_Character",
        "PalLocationPoint_NPC",
        "PalLocationPoint_DroppedCharacter",
        "PalLocationPointFastTravel",
        "PalLocationPoint",
    }
    for _, className in ipairs(probeClasses) do
        local actors = nil
        local ok = pcall(function() actors = FindAllOf(className) end)
        if not ok or not actors then
            lines[#lines + 1] = string.format("probe\t%s\t0", className)
        else
            local real = 0
            local samples = {}
            for _, actor in ipairs(actors) do
                local full = ""
                pcall(function() full = actor:GetFullName() or "" end)
                if full ~= "" and not string.find(full, "Default__", 1, true) then
                    real = real + 1
                    local cls = ClassNameOf(actor)
                    local blob = string.lower(full .. " " .. cls)
                    local want = string.find(blob, "boss", 1, true)
                        or string.find(blob, "tower", 1, true)
                        or string.find(blob, "npc", 1, true)
                        or string.find(blob, "relic", 1, true)
                        or string.find(blob, "whale", 1, true)
                    if want or #samples < 8 then
                        if #samples < 40 then
                            local loc = ReadVector(actor)
                            samples[#samples + 1] = string.format("marker\t%s\t%s\t%.0f\t%.0f\t%s",
                                className, cls,
                                loc and loc.X or 0, loc and loc.Y or 0,
                                string.sub(full, 1, 200))
                        end
                    end
                end
            end
            lines[#lines + 1] = string.format("probe\t%s\t%d", className, real)
            for _, sample in ipairs(samples) do
                lines[#lines + 1] = sample
            end
        end
    end

    AppendBossSpawnerLog(lines)

    local path = configMod.GetConfigDir() .. "/poi_positions.log"
    local handle = nil
    pcall(function() handle = io.open(path, "w") end)
    if not handle then
        print("[HUDLocator] Could not write " .. path .. "\n")
        return
    end
    handle:write(table.concat(lines, "\n"))
    handle:write("\n")
    handle:close()
    print("[HUDLocator] Position details written to " .. path .. "\n")
end

local function LocalizedText(category, key)
    if not key or key == "" then return "" end
    local util = nil
    pcall(function() util = StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility") end)
    if not util or not util.IsValid or not util:IsValid() then return "" end
    local world = utils.World()
    if not world then return "" end
    local text = nil
    local ok = pcall(function()
        text = util:GetLocalizedText(world, category, FName(key))
    end)
    if not ok or text == nil then return "" end
    local str = ""
    pcall(function() str = text:ToString() end)
    if type(str) ~= "string" or str == "" or str == key then return "" end
    return str
end

local function BountyTitle(spawner)
    local clean = utils.GetCleanPalId(spawner)
    local keys = { spawner, clean }
    if clean ~= "" then
        keys[#keys + 1] = "NAME_" .. clean
        keys[#keys + 1] = "NPC_" .. clean
    end
    for _, key in ipairs(keys) do
        local unique = LocalizedText(6, key)
        if unique ~= "" then return unique end
    end
    for _, key in ipairs({ spawner, clean }) do
        local human = LocalizedText(5, key)
        if human ~= "" then return human end
    end
    if clean ~= "" then return clean end
    return spawner
end

local bossSeen = {}

local function LoadBossSpawners()
    if bossesLoaded then return 0 end
    local rows = ReadBossTable()
    if not rows or #rows == 0 then return 0 end
    local alphas, bounties, oil, skipped = 0, 0, 0, 0
    local nameSamples = {}
    for _, entry in ipairs(rows) do
        local rowKind = BossRowKind(entry)
        local kind = rowKind == "oilrig" and "alpha" or rowKind
        local usable = type(entry.x) == "number" and type(entry.y) == "number" and not (entry.x == 0 and entry.y == 0)
        if kind ~= "alpha" and kind ~= "bounty" or not usable then
            skipped = skipped + 1
        else
            local placeKey = string.format("%s|%d|%d",
                string.lower(entry.spawner or ""),
                math.floor(entry.x + 0.5),
                math.floor(entry.y + 0.5))
            if not bossSeen[placeKey] then
                bossSeen[placeKey] = true
                local ids
                if kind == "alpha" then
                    ids = { entry.spawner }
                    if not BlankName(entry.character) then ids[#ids + 1] = entry.character end
                    alphas = alphas + 1
                    if rowKind == "oilrig" then oil = oil + 1 end
                else
                    local title = BountyTitle(entry.spawner)
                    ids = { entry.spawner }
                    if title ~= "" and string.lower(title) ~= string.lower(entry.spawner) then
                        ids[#ids + 1] = title
                    end
                    if #nameSamples < 6 then nameSamples[#nameSamples + 1] = ids[#ids] end
                    bounties = bounties + 1
                end
                local pt = { k = kind, r = "grasslands", ids = ids, x = entry.x, y = entry.y }
                pois.Points[#pois.Points + 1] = pt
                if kind == "alpha" and alphaById then IndexPoint(alphaById, pt) end
            end
        end
    end
    bossesLoaded = true
    poisClassified = false
    print(string.format(
        "[HUDLocator] Boss spawners: %d alphas, %d bounties. %d oil rigs included as alphas.\n",
        alphas, bounties, oil))
    if skipped > 0 then
        print(string.format("[HUDLocator] Boss spawners skipped %d other rows.\n", skipped))
    end
    if #nameSamples > 0 then
        print("[HUDLocator] Bounty names: " .. table.concat(nameSamples, ", ") .. "\n")
    end
    return alphas + bounties
end

local function PlacementPending()
    if not bossesLoaded then return true end
    if waitingOnOrigin then return true end
    for _, pt in ipairs(pois.Points) do
        if (pt.k == "alpha" or pt.k == "effigy" or pt.k == "tower" or pt.k == "journal" or pt.k == "hack") and not (pt.x and pt.y) then
            return true
        end
    end
    return false
end

local function PlaceLoadedPois()
    if placeTries >= PLACE_TRIES then return end
    if not PlacementPending() then
        placeTries = PLACE_TRIES
        return
    end
    placeTries = placeTries + 1
    BuildPlacementIndexes()
    local changed = LoadBossSpawners()
    local relicActors, originRelic = 0, 0
    local noteActors, originNote = 0, 0
    local hackActors, originHack = 0, 0

    EachOf("PalLevelObjectRelic", function(actor, full, loc)
        relicActors = relicActors + 1
        if not UsableLocation(loc) then
            originRelic = originRelic + 1
            return
        end
        local uaid = UaidOf(full)
        local pt = uaid and effigyByKey[uaid] or nil
        local guid = ""
        pcall(function() guid = GuidText(actor:GetLevelObjectInstanceId()) end)
        if not pt and guid ~= "" then pt = effigyByKey[guid] end
        if not pt and UsableLocation(loc) and uaid then
            local raw = full or ""
            local at = string.find(string.lower(raw), "uaid_", 1, true)
            local idText = at and string.sub(raw, at) or uaid
            local ids = {}
            if guid ~= "" and guid ~= "00000000000000000000000000000000" then
                ids[#ids + 1] = guid
            end
            ids[#ids + 1] = idText
            pt = { k = "effigy", r = "grasslands", ids = ids }
            pois.Points[#pois.Points + 1] = pt
            effigyByKey[uaid] = pt
            if guid ~= "" then effigyByKey[guid] = pt end
        elseif pt and guid ~= "" and guid ~= "00000000000000000000000000000000" then
            local known = false
            for _, id in ipairs(pt.ids or {}) do
                if NormKey(id) == guid then known = true end
            end
            if not known then
                pt.ids = pt.ids or {}
                table.insert(pt.ids, 1, guid)
            end
        end
        if pt then
            pcall(function()
                local value = actor.bPickedInClient
                if value == true or value == 1 then pt.picked = true
                elseif value == false or value == 0 then pt.picked = false end
            end)
        end
        local lifmunk = string.find(string.lower(full or ""), "bp_relicobject_c", 1, true)
            or string.find(string.lower(full or ""), "bp_levelobject_relic_c", 1, true)
        if lifmunk and (not pt or not UsableLocation(loc)) then
            NoteDiag("relic", actor, full, loc, "unmatched " .. (uaid or guid or ""))
        end
        if AssignPosition(pt, loc) then changed = changed + 1 end
    end)

    EachOf("PalLevelObjectNote", function(actor, full, loc)
        noteActors = noteActors + 1
        if not UsableLocation(loc) then
            originNote = originNote + 1
            return
        end
        local uaid = UaidOf(full)
        local pt = uaid and noteByKey[uaid] or nil
        local guid = ""
        pcall(function() guid = GuidText(actor:GetLevelObjectInstanceId()) end)
        if not pt and guid ~= "" then pt = noteByKey[guid] end
        local row = ""
        pcall(function()
            local key = actor.NoteRowName and actor.NoteRowName.Key
            if type(key) == "string" then
                row = NormKey(key)
            elseif key ~= nil then
                row = NormKey(key)
            end
        end)
        if not pt and row ~= "" then pt = noteByKey[row] end
        if not pt and UsableLocation(loc) then
            local raw = full or ""
            local at = string.find(string.lower(raw), "uaid_", 1, true)
            local idText = at and string.sub(raw, at) or uaid
            local ids = {}
            if guid ~= "" and guid ~= "00000000000000000000000000000000" then
                ids[#ids + 1] = guid
            end
            if row ~= "" then ids[#ids + 1] = row end
            if idText then ids[#ids + 1] = idText end
            pt = { k = "journal", r = "grasslands", ids = ids }
            pois.Points[#pois.Points + 1] = pt
            if uaid then noteByKey[uaid] = pt end
            if guid ~= "" then noteByKey[guid] = pt end
            if row ~= "" then noteByKey[row] = pt end
        elseif pt and guid ~= "" and guid ~= "00000000000000000000000000000000" then
            local known = false
            for _, id in ipairs(pt.ids or {}) do
                if NormKey(id) == guid then known = true end
            end
            if not known then
                pt.ids = pt.ids or {}
                table.insert(pt.ids, 1, guid)
                noteByKey[guid] = pt
            end
        end
        if pt then
            pcall(function()
                local value = actor.bPickedInClient
                if value == true or value == 1 then pt.picked = true
                elseif value == false or value == 0 then pt.picked = false end
            end)
        end
        if AssignPosition(pt, loc) then changed = changed + 1 end
    end)

    local function NameText(value)
        if type(value) == "string" then return value end
        local text = ""
        pcall(function()
            if value and value.ToString then text = value:ToString() or "" end
        end)
        if text == "" or text == "None" then return "" end
        return text
    end

    for _, className in ipairs({
        "PalLevelObjectUnlockableFastTravelPoint",
        "BP_LevelObject_TowerFastTravelPoint_C",
        "BP_LevelObject_UnlockMapPoint_C",
    }) do
        EachOf(className, function(actor, full, loc)
            local pointId = ""
            pcall(function() pointId = NameText(actor.FastTravelPointID) end)
            local guid = ""
            pcall(function() guid = GuidText(actor:GetLevelObjectInstanceId()) end)
            if guid == "00000000000000000000000000000000" then guid = "" end
            local ids = {}
            if pointId ~= "" then ids[#ids + 1] = pointId end
            if guid ~= "" then ids[#ids + 1] = guid end
            if #ids == 0 then return end
            local existed = TakePoint(ftByKey, ids) ~= nil
            local pt, placed = AddPoint("ft", ftByKey, ids, loc)
            if placed then changed = changed + 1 end
            NoteDiag("ft", actor, full, loc, table.concat({
                className,
                pointId ~= "" and pointId or "-",
                guid ~= "" and guid or "-",
                existed and "existing" or (pt and "new" or "skipped"),
            }, "\t"))
            if not pt then return end
            local unlocked = nil
            pcall(function()
                if actor.IsUnlocked then unlocked = NoteExplicit(actor:IsUnlocked()) end
            end)
            if unlocked == nil then
                pcall(function() unlocked = NoteExplicit(actor.bUnlocked) end)
            end
            if unlocked ~= nil then pt.unlocked = unlocked end
        end)
    end

    EachOf("BP_LevelObject_ItemPickupTower_C", function(actor, full, loc)
        hackActors = hackActors + 1
        if not UsableLocation(loc) then
            originHack = originHack + 1
            return
        end
        local guid = ""
        pcall(function() guid = GuidText(actor:GetLevelObjectInstanceId()) end)
        if guid == "" or guid == "00000000000000000000000000000000" then return end
        local pt, placed = AddPoint("hack", hackByKey, { guid }, loc)
        if placed then changed = changed + 1 end
        if not pt then return end
        pcall(function()
            local picked = NoteExplicit(actor.bPickedInClient)
            if picked ~= nil then pt.picked = picked end
        end)
    end)

    EachOf("BP_PalSpawner_Standard_C", function(actor, full, loc)
        local blob = string.lower((full or "") .. " " .. ClassNameOf(actor))
        local id = string.match(blob, "bp_palspawner_sheets_(.-)_c")
        local pt = id and alphaById[id] or nil
        if not pt then
            local bestLen = 0
            for key, candidate in pairs(alphaById) do
                if #key > bestLen and string.find(blob, key, 1, true) then
                    pt = candidate
                    bestLen = #key
                end
            end
        end
        NoteDiag("spawner", actor, full, loc, (pt and pt.ids and pt.ids[1]) or "")
        if AssignPosition(pt, loc) then changed = changed + 1 end
    end)

    local towerClasses = {
        "BP_PalBossTower_C",
        "BP_PalBossTower_MiddleBoss_C",
        "BP_PalBossTower_LastBoss_C",
        "BP_PalBossTower_KingWhale_C",
    }
    local towerAnchors = {
        { id = "forestboss", x = -266563, y = 174506 },
        { id = "grassboss", x = -321596, y = 209085 },
        { id = "electricboss", x = -361695, y = -112009 },
        { id = "desertboss", x = 29975, y = 413325 },
        { id = "snowboss", x = 81363, y = 90183 },
        { id = "sakurajimaboss", x = -29428, y = -115900 },
        { id = "sorajimaboss", x = -778216, y = -36026 },
        { id = "vikingboss", x = -889805, y = -435828 },
        { id = "kingwhaleboss", x = -108094, y = 77936 },
    }
    for _, className in ipairs(towerClasses) do
        EachOf(className, function(actor, full, loc)
            if UsableLocation(loc) then
                for _, pt in pairs(towerById) do
                    if pt.x and pt.y then
                        local dx, dy = loc.X - pt.x, loc.Y - pt.y
                        if dx * dx + dy * dy < 500 * 500 then return end
                    end
                end
            end
            local lowFull = string.lower(full or "")
            local classKey = TOWER_CLASS_KEY[string.lower(ClassNameOf(actor))]
            if not classKey and string.find(lowFull, "kingwhale", 1, true) then classKey = "kingwhaleboss" end
            if not classKey and string.find(lowFull, "lastboss", 1, true) then classKey = "worldtreelastboss" end
            if not classKey and string.find(lowFull, "middleboss", 1, true) then classKey = "middleboss" end
            local key = (classKey and classKey ~= "middleboss") and classKey or ""
            if key == "" and UsableLocation(loc) then
                local bossKey = ""
                pcall(function()
                    local value = actor.BossType
                    if type(value) == "string" then bossKey = NormKey(value) end
                    if bossKey == "" and type(value) == "number" then
                        for _, boss in ipairs(BOSS_TYPES) do
                            if boss.value == value then bossKey = NormKey(boss.id) end
                        end
                    end
                end)
                if bossKey == "" then
                    pcall(function()
                        local row = actor:GetBossBattleRowName()
                        if row and row.ToString then bossKey = NormKey(row:ToString()) end
                    end)
                end
                if bossKey ~= "" then
                    for _, boss in ipairs(BOSS_TYPES) do
                        local id = NormKey(boss.id)
                        if bossKey == id or TowerStoredMatches(bossKey, id) then key = id end
                    end
                    if key == "" and (bossKey == "kingwhale" or bossKey == "kingwhaleboss") then key = "kingwhaleboss" end
                    if key == "" and (bossKey == "worldtreeboss" or bossKey == "worldtreelastboss") then
                        key = "worldtreelastboss"
                    end
                    if key == "" then key = bossKey end
                end
            end
            if key == "" and classKey ~= "middleboss" and UsableLocation(loc) then
                local bestDist = 8000 * 8000
                for _, anchor in ipairs(towerAnchors) do
                    local dx, dy = loc.X - anchor.x, loc.Y - anchor.y
                    local dist = dx * dx + dy * dy
                    if dist < bestDist then
                        bestDist = dist
                        key = anchor.id
                    end
                end
            end
            if key == "" and classKey == "middleboss" then
                for _, id in ipairs({ "WorldTreeMiddleBoss1", "WorldTreeMiddleBoss2", "WorldTreeMiddleBoss3" }) do
                    if not towerById[NormKey(id)] then
                        key = NormKey(id)
                        break
                    end
                end
            end
            local ids = IdsForTower(key)
            local pt = nil
            if ids then
                local placed = false
                pt, placed = AddPoint("tower", towerById, ids, loc)
                if placed then changed = changed + 1 end
            end
            NoteDiag("tower", actor, full, loc, (pt and pt.ids and pt.ids[1]) or "unmatched")
        end)
    end

    if changed > 0 then poisClassified = false end
    waitingOnOrigin = relicActors == 0 or originRelic > 0
        or noteActors == 0 or originNote > 0
        or hackActors == 0 or originHack > 0
    if not placeLogged and (not PlacementPending() or placeTries >= PLACE_TRIES) then
        placeLogged = true
        local function counted(kind)
            local have, total = 0, 0
            for _, pt in ipairs(pois.Points) do
                if pt.k == kind then
                    total = total + 1
                    if pt.x and pt.y then have = have + 1 end
                end
            end
            return have, total
        end
        local eHave, eTotal = counted("effigy")
        local aHave, aTotal = counted("alpha")
        local bHave, bTotal = counted("bounty")
        local tHave, tTotal = counted("tower")
        local jHave, jTotal = counted("journal")
        local fHave, fTotal = counted("ft")
        local hHave, hTotal = counted("hack")
        print(string.format(
            "[HUDLocator] Positions from the world: effigies %d/%d, journals %d/%d, fast travel %d/%d, hacks %d/%d, alphas %d/%d, bounties %d/%d, towers %d/%d.\n",
            eHave, eTotal, jHave, jTotal, fHave, fTotal, hHave, hTotal, aHave, aTotal, bHave, bTotal, tHave, tTotal))
        local logOk, logErr = pcall(WritePoiLog)
        if not logOk then
            print("[HUDLocator] Position log failed: " .. tostring(logErr) .. "\n")
        end
    end
end

-- The world map icon uses this transform. Inside a tower the pawn is moved to
-- the arena, which sits near the World Tree, while the map stays at the entrance.
local function MapDisplayLocation(playerState)
    if type(playerState) ~= "userdata" then return nil end
    local info = nil
    local ok = pcall(function() info = playerState:GetPlayerInfoForMap() end)
    if not ok or info == nil then return nil end
    local transform = nil
    pcall(function() transform = info.Transform end)
    if transform == nil then return nil end
    local loc = nil
    pcall(function() loc = transform.Translation end)
    local x, y = VecXY(loc)
    if not x then
        pcall(function() loc = transform:GetLocation() end)
        x, y = VecXY(loc)
    end
    if not x then return nil end
    if math.abs(x) < 1000 and math.abs(y) < 1000 then return nil end
    return x, y
end

-- Main periodic scan method to extract completion data from UPalPlayerRecordData
function M.ScanCompletionData()
    if not configMod.CONFIG.Global.Enabled then return end
    if configMod.CONFIG.Completionist and not configMod.CONFIG.Completionist.Enabled then return end

    -- Loading Screen & World Transition Protection: Never run scans during transitions or loading screens
    if not utils.IsWorldReady() then return end

    local localPlayer = utils.Player()
    if not localPlayer or not localPlayer:IsValid() then return end

    -- Update active region from player location. Volumes are read here, not on the HUD thread.
    RefreshMapBounds()
    PlaceLoadedPois()
    ClassifyPois()
    RebuildTotals()
    -- Access UPalPlayerRecordData safely
    local playerState = localPlayer.PlayerState
    if not playerState or not playerState:IsValid() then return end

    pcall(function()
        local loc = localPlayer:K2_GetActorLocation()
        local x, y = VecXY(loc)
        local mx, my = MapDisplayLocation(playerState)
        if x and mx then
            local dx, dy = mx - x, my - y
            if dx * dx + dy * dy > 50000 * 50000 then
                if not M._loggedMapPos then
                    M._loggedMapPos = true
                    print(string.format(
                        "[HUDLocator] World map position (%.0f, %.0f) is away from the pawn (%.0f, %.0f). Using the map position for the region.\n",
                        mx, my, x, y))
                end
                x, y = mx, my
            end
        elseif mx then
            x, y = mx, my
        end
        if x and y then
            local activeReg = M.ResolveRegion(x, y, loc and loc.Z)
            M.currentRegionId = activeReg.id
            M.currentRegionName = activeReg.name
        end
    end)

    local recordData = nil
    pcall(function()
        if playerState.GetRecordData then
            recordData = playerState:GetRecordData()
        else
            recordData = playerState.RecordData
        end
    end)

    if not recordData or not recordData:IsValid() then return end

    -- Per-point unlock maps. Exp-table indexes and thread-safe ints stay at 0, so they
    -- cannot be used as the collected count.
    local ftFlags = SafeCollect(recordData.FastTravelPointUnlockFlag)
    local towerFlags, towerSeen = SafeCollect(recordData.TowerBossDefeatFlag, true)
    local towerCounts, towerCountSeen = SafeCollect(recordData.TowerBossDefeatCount, true)
    AbsorbTowerKeys(towerCounts, towerFlags)
    local alphaFlags, alphaSeen = SafeCollect(recordData.NormalBossDefeatFlag)
    local bountyFlags = SafeCollect(recordData.SpecificBossDefeatFlag)
    local effigyFlags, effigySeen = CollectRelicFlags(recordData)
    local hackFlags = SafeCollect(recordData.ItemPickupObtainForInstanceFlag)
    local journalFlags = SafeCollect(recordData.NoteObtainForInstanceFlag)

    local alphaApi, effigyApi = 0, 0
    pcall(function()
        if recordData.GetNormalBossDefeatCount then
            alphaApi = recordData:GetNormalBossDefeatCount() or 0
        end
    end)
    pcall(function()
        if recordData.GetRelicPossessNumByType then
            effigyApi = recordData:GetRelicPossessNumByType(0) or 0
        end
    end)

    pcall(function()
        local managers = FindAllOf("PalNPCManager")
        if managers then
            for _, manager in ipairs(managers) do
                MergeSets(alphaFlags, CollectMapFlags(manager.RespawnDisableFlag))
            end
        end
    end)

    local unlockedByRegion = {}
    for _, reg in ipairs(M.Regions) do
        unlockedByRegion[reg.id] = { ft = 0, tower = 0, alpha = 0, bounty = 0, effigy = 0, journal = 0, hack = 0 }
    end

    local function PointCleared(pt)
        local keys = pt.ids
        local function inSet(set)
            for _, id in ipairs(keys) do
                if FlagHas(set, id) then return true end
            end
            return false
        end
        if pt.k == "ft" then return pt.unlocked == true or inSet(ftFlags) end
        if pt.k == "tower" then
            for _, id in ipairs(keys) do
                local key = NormKey(id)
                if key ~= "" and towerFlags[key] then return true end
                for stored, on in pairs(towerFlags) do
                    if on and key ~= "" and TowerStoredMatches(stored, key) then return true end
                end
            end
            return false
        end
        if pt.k == "alpha" then return inSet(alphaFlags) end
        if pt.k == "bounty" then return inSet(bountyFlags) or inSet(alphaFlags) end
        if pt.k == "effigy" then return pt.picked == true or inSet(effigyFlags) end
        if pt.k == "journal" then return pt.picked == true or inSet(journalFlags) end
        if pt.k == "hack" then return inSet(hackFlags) end
        return false
    end

    for _, pt in ipairs(pois.Points) do
        local bucket = unlockedByRegion[pt.region or PointRegionId(pt)]
        if bucket and PointCleared(pt) then
            if pt.k == "ft" then bucket.ft = bucket.ft + 1
            elseif pt.k == "tower" then bucket.tower = bucket.tower + 1
            elseif pt.k == "alpha" then bucket.alpha = bucket.alpha + 1
            elseif pt.k == "bounty" then bucket.bounty = bucket.bounty + 1
            elseif pt.k == "effigy" then bucket.effigy = bucket.effigy + 1
            elseif pt.k == "journal" then bucket.journal = (bucket.journal or 0) + 1
            elseif pt.k == "hack" then bucket.hack = (bucket.hack or 0) + 1
            end
        end
    end

    local ftCount, alphaCount, towerCount, bountyCount, effigyCount, journalCount, hackCount = 0, 0, 0, 0, 0, 0, 0
    for _, bucket in pairs(unlockedByRegion) do
        ftCount = ftCount + bucket.ft
        alphaCount = alphaCount + bucket.alpha
        towerCount = towerCount + bucket.tower
        bountyCount = bountyCount + bucket.bounty
        effigyCount = effigyCount + bucket.effigy
        journalCount = journalCount + (bucket.journal or 0)
        hackCount = hackCount + (bucket.hack or 0)
    end

    M.globalSaveProgress.unlockedFastTravels = ftCount
    M.globalSaveProgress.defeatedAlphas = alphaCount
    M.globalSaveProgress.defeatedTowers = towerCount
    M.globalSaveProgress.clearedBounties = bountyCount
    M.globalSaveProgress.collectedEffigies = effigyCount
    M.globalSaveProgress.collectedJournals = journalCount
    M.globalSaveProgress.collectedHacks = hackCount

    local totalItems = M.globalSaveProgress.totalFastTravels + M.globalSaveProgress.totalAlphas + 
                       M.globalSaveProgress.totalTowers + M.globalSaveProgress.totalBounties + 
                       M.globalSaveProgress.totalEffigies + M.globalSaveProgress.totalJournals + M.globalSaveProgress.totalHacks
    local unlockedItems = ftCount + alphaCount + towerCount + bountyCount + effigyCount + journalCount + hackCount
    M.globalSaveProgress.overallPercent = (totalItems > 0) and math.floor((unlockedItems / totalItems) * 100) or 0

    if towerCount == 0 and not M._loggedTowerKeys then
        local sample = {}
        for key in pairs(towerFlags) do
            if #sample < 8 then table.insert(sample, key) end
        end
        if #sample > 0 then
            M._loggedTowerKeys = true
            print("[HUDLocator] Tower records did not match the map list. Sample: " .. table.concat(sample, ", ") .. "\n")
        end
    end

    -- Log diagnostic completion state whenever region or counts change
    if ftCount ~= lastLogged.ft or alphaCount ~= lastLogged.alphas or towerCount ~= lastLogged.towers or 
       bountyCount ~= lastLogged.bounties or effigyCount ~= lastLogged.effigies or journalCount ~= lastLogged.journals or M.currentRegionId ~= lastLogged.region then
        
        lastLogged.ft = ftCount
        lastLogged.alphas = alphaCount
        lastLogged.towers = towerCount
        lastLogged.bounties = bountyCount
        lastLogged.effigies = effigyCount
        lastLogged.journals = journalCount
        lastLogged.region = M.currentRegionId

        local here = unlockedByRegion[M.currentRegionId] or { ft = 0, tower = 0, alpha = 0, bounty = 0, effigy = 0, journal = 0 }
        local hereReg = regionById[M.currentRegionId]
        local hereTotals = hereReg and hereReg.totals or {}
        logger.log(string.format("[Completionist Scan] Region: %s (%s) | FTs: %d/%d | Alphas: %d/%d (save %d, flags %d/%d) | Towers: %d/%d (flags %d/%d) | Bounties: %d/%d | Effigies: %d/%d (save %d, flags %d/%d) | Journals: %d/%d (flags %d)",
            tostring(M.currentRegionName), tostring(M.currentRegionId),
            here.ft, hereTotals.fastTravels or 0,
            here.alpha, hereTotals.alphas or 0, alphaApi, SetCount(alphaFlags), alphaSeen or 0,
            here.tower, hereTotals.towers or 0, SetCount(towerFlags), (towerSeen or 0) + (towerCountSeen or 0),
            here.bounty, hereTotals.bounties or 0,
            here.effigy, hereTotals.effigies or 0, effigyApi, SetCount(effigyFlags), effigySeen or 0,
            here.journal or 0, hereTotals.journals or 0, SetCount(journalFlags)))
        if alphaApi > 0 and alphaCount == 0 then
            local sample = {}
            local n = 0
            for key in pairs(alphaFlags) do
                n = n + 1
                if n <= 8 then table.insert(sample, key) end
            end
            logger.log("[Completionist] Alpha flags did not match the map list. Sample: " .. table.concat(sample, ", "))
        end
        if effigyApi > 0 and effigyCount == 0 then
            local sample = {}
            local n = 0
            for key in pairs(effigyFlags) do
                n = n + 1
                if n <= 8 then table.insert(sample, key) end
            end
            logger.log("[Completionist] Effigy flags did not match the map list. Sample: " .. table.concat(sample, ", "))
        end
    end

    Publish(unlockedByRegion)
end

function M.BountyDisplay(charId)
    local key = string.lower(tostring(charId or ""))
    local clean = string.lower(utils.GetCleanPalId(tostring(charId or "")))
    if key == "" and clean == "" then return nil end
    for _, pt in ipairs(pois.Points) do
        if pt.k == "bounty" then
            for _, id in ipairs(pt.ids or {}) do
                local norm = string.lower(id)
                if norm == key or (clean ~= "" and norm == clean) then
                    return pt.ids[#pt.ids]
                end
            end
        end
    end
    return nil
end

return M
