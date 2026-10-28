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
            local display = BountyName(charIdStr)
            if not display or display == "" then return end
            if IsDead(charParam, indivParam) then return end

            local name = display
            if not name or name == "" then
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
