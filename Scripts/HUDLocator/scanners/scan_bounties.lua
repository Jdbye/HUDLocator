local configMod = require("HUDLocator.config")
local utils = require("HUDLocator.utils")
local logger = require("HUDLocator.logger")
local completion = require("HUDLocator.completion")

local M = {}
M.hasLogged = false

-- Bounty targets are human NPCs (BOSS_Male_Soldier and similar), not pals.
-- APalMonsterCharacter extends APalNPC, so FindAllOf("PalNPC") also returns pals.
local function BountyName(charIdStr)
    return completion.BountyDisplay(charIdStr)
end

local NPC_CLASSES = {
    "BP_NPC_Base_C",
    "BP_NPC_NewBase_C",
    "BP_NPC_StandardHumanDataSet_C",
    "BP_NPC_FatHumanDataSet_C",
    "BP_NPC_Female_Soldier_C",
    "BP_NPC_DarkTrader_C",
}

local monsterClass = nil
local function IsPalMonster(actor)
    if not monsterClass then
        pcall(function()
            monsterClass = StaticFindObject("/Script/Pal.PalMonsterCharacter")
        end)
    end
    if monsterClass then
        local isMonster = false
        local ok = pcall(function() isMonster = actor:IsA(monsterClass) end)
        if ok and isMonster == true then return true end
    end
    local className = ""
    pcall(function()
        local cls = actor:GetClass()
        if cls and cls.GetName then className = string.lower(cls:GetName()) end
    end)
    if className == "" then return false end
    if string.find(className, "mimicdog", 1, true) then return true end
    if string.find(className, "monster", 1, true) then return true end
    if string.find(className, "_boss_c", 1, true) then return true end
    return false
end

local function CharacterId(actor)
    local charIdStr = ""
    local charParam = nil
    local indivParam = nil
    pcall(function() charParam = actor:GetCharacterParameterComponent() end)
    if charParam and charParam:IsValid() then
        pcall(function() indivParam = charParam:GetIndividualParameter() end)
    end
    if indivParam and indivParam:IsValid() then
        pcall(function()
            local cId = indivParam:GetCharacterID()
            if cId then charIdStr = cId:ToString() end
        end)
    end
    if charIdStr == "" then
        pcall(function()
            local staticParam = actor.StaticCharacterParameterComponent
            if staticParam and staticParam:IsValid() then
                local cId = staticParam.CharacterID
                if cId then charIdStr = cId:ToString() end
            end
        end)
    end
    return charIdStr, charParam, indivParam
end

local function TextOf(value)
    if type(value) == "string" then return value end
    if value == nil then return "" end
    local text = ""
    pcall(function()
        if value.ToString then text = value:ToString() end
    end)
    if type(text) ~= "string" then return "" end
    return text
end

local function FNameString(value)
    local text = ""
    pcall(function()
        if value and value.ToString then text = value:ToString() end
    end)
    if type(text) ~= "string" then return "" end
    return text
end

-- The boss health bar shows SaveParameter.NickName. Calling GetSaveParameter()
-- returns that whole struct and crashes, so this reads the property directly,
-- the same way the pal scanner reads IndividualId. UniqueNPCID is the fallback
-- the bar uses when the nickname is empty.
local nameByKey = {}
local database = nil

local function CharacterDatabase()
    if database and database.IsValid and database:IsValid() then return database end
    database = nil
    local world = utils.World()
    if not world then return nil end
    local utility = nil
    pcall(function() utility = StaticFindObject("/Script/Pal.Default__PalUtility") end)
    if not utility then return nil end
    local db = nil
    local ok = pcall(function()
        db = utility:GetDatabaseCharacterParameter(world)
    end)
    if ok and db and db.IsValid and db:IsValid() then
        database = db
    end
    return database
end

local humanNames = nil

local function ForEachEntry(arrayLike, fn)
    if not arrayLike then return end
    if type(arrayLike) == "table" then
        for _, elem in ipairs(arrayLike) do fn(elem) end
        return
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
    local seen = 0
    if type(count) == "number" and count > 0 then
        if count > 8000 then count = 8000 end
        for i = 1, count do
            local elem = nil
            pcall(function() elem = arrayLike[i] end)
            if elem == nil then pcall(function() elem = arrayLike:Get(i) end) end
            if elem == nil then pcall(function() elem = arrayLike:Get(i - 1) end) end
            if elem ~= nil then
                seen = seen + 1
                fn(elem)
            end
        end
        if seen > 0 then return end
    end
    pcall(function()
        if not arrayLike.ForEach then return end
        arrayLike:ForEach(function(a, b)
            local elem = b
            if type(a) ~= "number" or elem == nil then elem = a end
            if elem ~= nil then fn(elem) end
        end)
    end)
end

local function ColumnStrings(lib, tableObj, prop)
    local list = {}
    local column = nil
    local ok = pcall(function()
        column = lib:GetDataTableColumnAsString(tableObj, FName(prop))
    end)
    if not ok or not column then return list end
    ForEachEntry(column, function(elem)
        local text = TextOf(elem)
        if text ~= "" then list[#list + 1] = text end
    end)
    return list
end

local function RowNames(lib, tableObj)
    local list = {}
    local names = nil
    local ok = pcall(function() names = lib:GetDataTableRowNames(tableObj) end)
    if not ok or not names then return list end
    ForEachEntry(names, function(elem)
        local text = FNameString(elem)
        if text == "" then text = TextOf(elem) end
        if text ~= "" then list[#list + 1] = text end
    end)
    return list
end

local function LocalText(category, key)
    if not key or key == "" or key == "None" then return "" end
    local util = nil
    pcall(function() util = StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility") end)
    local world = utils.World()
    if not util or not world then return "" end
    local text = nil
    local ok = pcall(function()
        text = util:GetLocalizedText(world, category, FName(key))
    end)
    if not ok then return "" end
    local str = TextOf(text)
    if str == "" or str == key or str == "None" then return "" end
    return str
end

local function ResolveTextId(textId)
    for _, category in ipairs({ 5, 6, 4, 7 }) do
        local text = LocalText(category, textId)
        if text ~= "" then return text end
    end
    return ""
end

-- The boss bar name is OverrideNameTextID on the human parameter row.
-- The character nickname and unique NPC id are empty for these bounties.
local function LoadHumanNames()
    if humanNames == false then return nil end
    if humanNames ~= nil then return humanNames end
    local db = CharacterDatabase()
    if not db then return nil end
    local lib = nil
    pcall(function() lib = StaticFindObject("/Script/Engine.Default__DataTableFunctionLibrary") end)
    if not lib then return nil end
    local tables = {}
    pcall(function()
        if db.HumanParameterDataTable and db.HumanParameterDataTable:IsValid() then
            tables[#tables + 1] = db.HumanParameterDataTable
        end
        if db.MonsterParameterDataTable and db.MonsterParameterDataTable:IsValid() then
            tables[#tables + 1] = db.MonsterParameterDataTable
        end
    end)
    local map = {}
    for _, tableObj in ipairs(tables) do
        local rows = RowNames(lib, tableObj)
        local overrides = ColumnStrings(lib, tableObj, "OverrideNameTextID")
        local count = math.max(#rows, #overrides)
        for i = 1, count do
            local row = rows[i]
            local overrideId = overrides[i]
            if row and row ~= "" and overrideId and overrideId ~= "" and overrideId ~= "None" then
                local key = string.lower(row)
                if not map[key] then
                    map[key] = ResolveTextId(overrideId)
                    map[key .. ".id"] = overrideId
                end
            end
        end
    end
    if next(map) == nil then
        humanNames = false
        return nil
    end
    humanNames = map
    return map
end

local function FieldString(saveP, field)
    local value = nil
    local ok, err = pcall(function() value = saveP[field] end)
    if not ok then return "", tostring(err) end
    return TextOf(value), nil
end

local function UsableName(name, charIdStr, uniqueStr)
    if name == "" or name == "None" then return "" end
    local lower = string.lower(name)
    local raw = string.lower(charIdStr or "")
    local unique = string.lower(uniqueStr or "")
    if lower == raw or lower == unique or string.sub(lower, 1, 5) == "boss_" then
        return ""
    end
    return name
end

local function NoteName(charIdStr, uniqueStr, nick, filtered, chosen, detail)
    if M.loggedNick then return end
    M.loggedNick = true
    print("[HUDLocator] Bounty name: " .. tostring(charIdStr)
        .. " unique " .. tostring(uniqueStr)
        .. " nick " .. tostring(nick)
        .. " filtered " .. tostring(filtered)
        .. " -> " .. (chosen ~= "" and chosen or "(none)")
        .. (detail and (" (" .. detail .. ")") or "")
        .. "\n")
end

local function PersonName(indivParam, charIdStr)
    if not indivParam or not indivParam:IsValid() then
        NoteName(charIdStr, "", "", "", "", "no parameter")
        return ""
    end
    local cacheKey = string.lower(charIdStr or "")
    local instance = ""
    pcall(function()
        local g = indivParam:GetIndividualId()
        if g then instance = g:ToString() end
    end)
    if instance ~= "" then cacheKey = instance end
    if cacheKey ~= "" and nameByKey[cacheKey] then return nameByKey[cacheKey] end

    local saveP = nil
    local readOk, readErr = pcall(function() saveP = indivParam.SaveParameter end)
    if not readOk or not saveP then
        NoteName(charIdStr, "", "", "", "", readOk and "no save parameter" or tostring(readErr))
        return ""
    end
    local nick, nickErr = FieldString(saveP, "NickName")
    local filtered, filteredErr = FieldString(saveP, "FilteredNickName")
    local uniqueValue = nil
    pcall(function() uniqueValue = saveP.UniqueNPCID end)
    saveP = nil
    local uniqueStr = FNameString(uniqueValue)
    uniqueValue = nil
    if uniqueStr == "None" then uniqueStr = "" end

    local name = UsableName(filtered, charIdStr, uniqueStr)
    if name == "" then name = UsableName(nick, charIdStr, uniqueStr) end
    local overrideId = ""
    local localized = ""
    local dbNote = CharacterDatabase() and "db" or "no db"
    if name == "" then
        local db = CharacterDatabase()
        if db then
            local output = {}
            local ok, err = pcall(function()
                db:GetLocalizedCharacterName(FName(charIdStr), output)
            end)
            if ok then
                localized = TextOf(output.OutText)
                if localized == "" then localized = TextOf(output.outText) end
                name = UsableName(localized, charIdStr, uniqueStr)
            else
                localized = "err " .. tostring(err)
            end
        end
    end
    if name == "" then
        local map = LoadHumanNames()
        local rowKey = string.lower(charIdStr or "")
        if map and map[rowKey .. ".id"] then
            overrideId = map[rowKey .. ".id"]
            name = UsableName(map[rowKey] or "", charIdStr, uniqueStr)
        elseif map == nil then
            overrideId = humanNames == false and "table empty" or "table unread"
        end
    end
    local detail = "db " .. dbNote .. " localized " .. (localized ~= "" and localized or "(none)")
    if overrideId ~= "" then detail = detail .. " override " .. overrideId end
    if nickErr then detail = detail .. " nick " .. nickErr end
    if filteredErr then detail = detail .. " filtered " .. filteredErr end
    NoteName(charIdStr, uniqueStr, nick, filtered, name, detail)
    if name == "" or cacheKey == "" then return name end
    nameByKey[cacheKey] = name
    return name
end

local function IsDead(charParam, indivParam)
    local dead = false
    if indivParam and indivParam:IsValid() then
        pcall(function() dead = indivParam:IsDead() end)
    elseif charParam and charParam:IsValid() then
        pcall(function() dead = charParam:IsDead() end)
    end
    return dead == true or dead == 1
end

function M.Scan(playerPos, maxDistSq)
    local found = {}
    local seen = {}
    local function Consider(actor)
        local key = nil
        pcall(function() key = actor:GetFullName() end)
        if not key or seen[key] or string.find(key, "Default__", 1, true) then return end
        seen[key] = true
        if not utils.IsActorValidForScan(actor) then return end

        pcall(function()
            local hidden = false
            pcall(function() hidden = actor.bHidden or (actor.IsHidden and actor:IsHidden()) end)
            if hidden then return end

            local pos = actor:K2_GetActorLocation()
            if not pos then return end
            local within, distSq, px, py, pz = utils.IsWithinDistanceSq(pos, playerPos, maxDistSq)
            if not within then return end

            if IsPalMonster(actor) then return end
            local charIdStr, charParam, indivParam = CharacterId(actor)
            if not BountyName(charIdStr) then return end
            if IsDead(charParam, indivParam) then return end

            local name = PersonName(indivParam, charIdStr)
            if name == "" then
                name = configMod.GetTranslation("Bounty", "Bounty")
            end
            local level = nil
            if indivParam and indivParam:IsValid() then
                pcall(function() level = indivParam:GetLevel() end)
            elseif charParam and charParam:IsValid() then
                pcall(function() level = charParam:GetLevel() end)
            end
            if level and level > 0 then
                name = name .. " lv." .. tostring(level)
            end

            local distStr = math.floor(math.sqrt(distSq) / 100.0) .. "m"
            table.insert(found, {
                Actor = actor,
                X = px, Y = py, Z = pz,
                Name = name,
                DistStr = distStr,
                BracketDistStr = "[" .. distStr .. "]",
            })
        end)
    end

    for _, className in ipairs(NPC_CLASSES) do
        local status, actors = pcall(function() return FindAllOf(className) end)
        if status and actors then
            for _, actor in ipairs(actors) do
                Consider(actor)
            end
        end
    end

    if not M.hasLogged and #found > 0 then
        M.hasLogged = true
        logger.log("Bounty scan: found " .. tostring(#found) .. " nearby targets.")
    end
    return found
end

return M
