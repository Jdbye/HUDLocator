local configMod = require("HUDLocator.config")
local utils = require("HUDLocator.utils")
local logger = require("HUDLocator.logger")

local M = {}
M.hasLoggedPals = false

local function IsValidGuid(guid)
    if not guid then return false end
    local valid = false
    pcall(function()
        if (guid.A and guid.A ~= 0) or 
           (guid.B and guid.B ~= 0) or 
           (guid.C and guid.C ~= 0) or 
           (guid.D and guid.D ~= 0) then
            valid = true
        end
    end)
    if valid then return true end
    local text = nil
    pcall(function() text = guid:ToString() end)
    if type(text) ~= "string" or text == "" or text == "None" then return false end
    local hex = string.gsub(text, "[%{%}%-]", "")
    return hex ~= "" and not string.match(hex, "^0+$")
end

local function BoolTrue(value)
    if value == true or value == 1 then return true end
    if type(value) == "string" then
        local text = string.lower(value)
        return text == "true" or text == "1"
    end
    return false
end

local function TryBool(fn)
    local ok, value = pcall(fn)
    return ok and BoolTrue(value)
end

local palUtility = nil
local selfActorIds = {}

local function ActorId(actor)
    if not actor then return nil end
    local ok, addr = pcall(function() return actor:GetAddress() end)
    if ok and addr and addr ~= 0 then return tostring(addr) end
    return nil
end

local function PalUtility()
    if palUtility == false then return nil end
    if palUtility and palUtility:IsValid() then return palUtility end
    local found = nil
    pcall(function() found = StaticFindObject("/Script/Pal.Default__PalUtility") end)
    if not found or not found:IsValid() then
        palUtility = false
        return nil
    end
    palUtility = found
    return palUtility
end

local function RememberSelf(actor)
    if not actor then return end
    local ok, valid = pcall(function() return actor:IsValid() end)
    if not ok or valid ~= true then return end
    local id = ActorId(actor)
    if id then selfActorIds[id] = true end
end

-- The local pawn and the pal being ridden. Ownership of other pals is LiveOwned.
local function RefreshSelfActors()
    local player = utils.Player()
    local playerOk = false
    if player then pcall(function() playerOk = player:IsValid() end) end
    if not playerOk then return end
    selfActorIds = {}
    RememberSelf(player)
    pcall(function() RememberSelf(player:GetLowBodyPalCharacter()) end)
    pcall(function() RememberSelf(player:GetControlPalCharacter()) end)
    local util = PalUtility()
    if util and type(util) == "userdata" then
        local ride = nil
        pcall(function() ride = util:GetRidePal(player) end)
        RememberSelf(ride)
    end
end

local liveOwnedCache = {}
local liveOwnedTime = {}

-- Party pals report IsOtomo. Base pals report a trainer, a work assignment, or a camp id.
-- Wild pals report none of these. Only called for pals that already matched the tracker.
local function LiveOwned(actor, charParam)
    local paramOk = false
    if charParam then pcall(function() paramOk = charParam:IsValid() end) end
    if paramOk then
        if TryBool(function() return charParam:IsOtomo() end) then return true end
        if TryBool(function() return charParam:IsAssignedToAnyWork() end) then return true end
        local trainerOk = false
        pcall(function()
            local trainer = charParam.Trainer
            trainerOk = trainer and trainer:IsValid()
        end)
        if trainerOk then return true end
        local campId = nil
        pcall(function() campId = charParam:GetBaseCampId() end)
        if IsValidGuid(campId) then return true end
    end
    local util = PalUtility()
    if util and type(util) == "userdata" then
        if TryBool(function() return util:IsBaseCampPal(actor) end) then return true end
        if TryBool(function() return util:IsLocalPlayerCampPal(actor) end) then return true end
    end
    return false
end

function M.IsSelfActor(actor)
    local id = ActorId(actor)
    return id ~= nil and selfActorIds[id] == true
end

function M.IsOwnedActor(actor)
    if not actor then return false end
    local valid = false
    pcall(function() valid = actor:IsValid() end)
    if not valid then return false end
    local id = ActorId(actor)
    if id and selfActorIds[id] then return true end
    local now = (os and os.clock) and os.clock() or nil
    if id and now and liveOwnedCache[id] ~= nil and (now - (liveOwnedTime[id] or 0)) < 1.0 then
        return liveOwnedCache[id] == true
    end
    local charParam = nil
    pcall(function() charParam = actor:GetCharacterParameterComponent() end)
    if charParam then
        local paramOk = false
        pcall(function() paramOk = charParam:IsValid() end)
        if not paramOk then charParam = nil end
    end
    local owned = LiveOwned(actor, charParam)
    if id and now then
        liveOwnedCache[id] = owned
        liveOwnedTime[id] = now
    end
    return owned
end

local function IsMimogPal(actor, charIdStr, cleanCharId, palName)
    local clean = string.lower(cleanCharId or "")
    local raw = string.lower(charIdStr or "")
    local name = string.lower(palName or "")
    if clean == "mimicdog" or string.find(raw, "mimicdog", 1, true) or name == "mimog" then
        return true
    end
    local className = ""
    if actor then
        pcall(function()
            local classObj = actor:GetClass()
            if classObj and classObj.GetName then
                className = classObj:GetName()
            end
        end)
    end
    className = string.lower(className or "")
    return string.find(className, "mimicdog", 1, true) ~= nil
end

local function NormalizePassiveString(s)
    if not s then return "" end
    local clean = string.lower(tostring(s))
    clean = string.gsub(clean, "[%s_%-]+", "")
    return clean
end

local function ExtractList(val)
    local list = {}
    if not val then return list end
    if type(val) == "string" then
        if val ~= "" then table.insert(list, val) end
    elseif type(val) == "table" then
        for _, item in pairs(val) do
            if type(item) == "string" and item ~= "" then
                table.insert(list, item)
            end
        end
    end
    return list
end

local function EvaluatePalRule(rule, palName, charIdStr, cleanCharId, isShiny, isBoss, palPassiveMap)
    if not rule then return false, 0, {} end
    if type(rule) == "string" then
        rule = { palname = rule }
    end

    -- 1. Species / Pal Name filter (omitted, empty "", or "*" matches all Pals)
    if rule.palname and rule.palname ~= "" and rule.palname ~= "*" then
        local rawTarget = string.lower(rule.palname)
        local cleanTarget = rawTarget
        cleanTarget = string.gsub(cleanTarget, "^boss[_%s]+", "")
        cleanTarget = string.gsub(cleanTarget, "^alpha[_%s]+", "")
        cleanTarget = string.gsub(cleanTarget, "[_%s]+boss$", "")

        local lowerPalName = string.lower(palName or "")
        local lowerCharId = string.lower(charIdStr or "")
        local lowerCleanId = string.lower(cleanCharId or "")

        local matchedName = false
        if string.find(lowerPalName, rawTarget, 1, true) or string.find(lowerCharId, rawTarget, 1, true) or string.find(lowerCleanId, rawTarget, 1, true) then
            matchedName = true
        elseif cleanTarget ~= "" and (string.find(lowerPalName, cleanTarget, 1, true) or string.find(lowerCharId, cleanTarget, 1, true) or string.find(lowerCleanId, cleanTarget, 1, true)) then
            matchedName = true
        end

        if not matchedName and (rawTarget == "mimog" or cleanTarget == "mimog") then
            if string.find(lowerPalName, "mimicdog", 1, true) or string.find(lowerCharId, "mimicdog", 1, true) or string.find(lowerCleanId, "mimicdog", 1, true) then
                matchedName = true
            end
        end

        if not matchedName then
            return false, 0, {}
        end
    end

    -- 2. Shiny / Boss attribute checks
    if rule.shiny == true and not isShiny then
        return false, 0, {}
    end

    if rule.boss == true and not isBoss then
        return false, 0, {}
    end

    -- 3. Excluded passives check (negative filter)
    local rawExclude = nil
    if rule.passive and type(rule.passive) == "table" and rule.passive.exclude_passives then
        rawExclude = rule.passive.exclude_passives
    elseif rule.exclude_passives then
        rawExclude = rule.exclude_passives
    end

    local excludeList = ExtractList(rawExclude)
    if #excludeList > 0 and palPassiveMap then
        for _, excP in ipairs(excludeList) do
            local strExc = tostring(excP)
            local lowerExc = string.lower(strExc)
            local normExc = NormalizePassiveString(strExc)
            if palPassiveMap[strExc] or palPassiveMap[lowerExc] or palPassiveMap[normExc] then
                return false, 0, {}
            end
        end
    end

    -- 4. Required passives check
    local matchedPassivesCount = 0
    local matchedPassiveNames = {}
    if rule.passive then
        local rawRequired = (type(rule.passive) == "table") and rule.passive.passives or rule.passive
        local minThreshold = (type(rule.passive) == "table" and rule.passive.min_passive_threshold) or 1
        local requiredList = ExtractList(rawRequired)

        if #requiredList > 0 then
            if not palPassiveMap then
                return false, 0, {}
            end

            local alreadyMatched = {}
            for _, reqP in ipairs(requiredList) do
                local strReq = tostring(reqP)
                local lowerReq = string.lower(strReq)
                local normReq = NormalizePassiveString(strReq)

                local displayName = palPassiveMap[strReq] or palPassiveMap[lowerReq] or palPassiveMap[normReq]
                if displayName and not alreadyMatched[displayName] then
                    alreadyMatched[displayName] = true
                    matchedPassivesCount = matchedPassivesCount + 1
                    table.insert(matchedPassiveNames, displayName)
                end
            end

            if matchedPassivesCount < minThreshold then
                return false, 0, {}
            end
        end
    end

    return true, matchedPassivesCount, matchedPassiveNames
end

function M.Scan(playerPos, maxDistSq, palConfig)
    RefreshSelfActors()
    local newPals = {}
    local actors = {}
    local status, res = pcall(function() return FindAllOf("BP_MonsterBase_C") end)
    if status and res then
        actors = res
    else
        status, res = pcall(function() return FindAllOf("PalMonsterCharacter") end)
        if status and res then
            actors = res
        end
    end

    -- Mimog is BP_MimicDog_C. FindAllOf on the base pal class does not always return it.
    local listedNames = {}
    for _, actor in ipairs(actors) do
        local fullName = nil
        pcall(function() fullName = actor:GetFullName() end)
        if fullName then listedNames[fullName] = true end
    end
    local mimicStatus, mimicActors = pcall(function() return FindAllOf("BP_MimicDog_C") end)
    if mimicStatus and mimicActors then
        for _, actor in ipairs(mimicActors) do
            local fullName = nil
            pcall(function() fullName = actor:GetFullName() end)
            if not fullName or not listedNames[fullName] then
                if fullName then listedNames[fullName] = true end
                table.insert(actors, actor)
            end
        end
    end
    
    local filterMode = palConfig.FilterMode or "TrackerListOnly"
    local rulesList = palConfig.TrackerPals or {}
    local showPassives = palConfig.ShowPassives ~= false
    local showLevel = palConfig.ShowLevel ~= false
    local includeOwned = (palConfig.IncludeOwned == true)

    local seenActors = {}
    local seenGuids = {}

    for _, actor in ipairs(actors) do
        if utils.IsActorValidForScan(actor) then
            pcall(function()
                local isHidden = false
                pcall(function() isHidden = actor.bHidden or (actor.IsHidden and actor:IsHidden()) end)
                if isHidden then return end

                local fullName = nil
                pcall(function() fullName = actor:GetFullName() end)
                if not fullName or seenActors[fullName] then return end
                seenActors[fullName] = true

                local uePos = actor:K2_GetActorLocation()
                if uePos then
                    local within, distSq, px, py, pz = utils.IsWithinDistanceSq(uePos, playerPos, maxDistSq)
                    if within then
                        local charParam = nil
                        pcall(function() charParam = actor:GetCharacterParameterComponent() end)

                        local staticParam = nil
                        pcall(function() staticParam = actor.StaticCharacterParameterComponent end)

                        local indivParam = nil
                        if charParam and charParam:IsValid() then
                            pcall(function() indivParam = charParam:GetIndividualParameter() end)
                        end

                        local isDead = false
                        if indivParam and indivParam:IsValid() then
                            pcall(function() isDead = indivParam:IsDead() end)
                        elseif charParam and charParam:IsValid() then
                            pcall(function() isDead = charParam:IsDead() end)
                        end

                        local selfId = ActorId(actor)
                        local isOwned = selfId ~= nil and selfActorIds[selfId] == true

                        local isIgnored = isDead or (isOwned and not includeOwned)
                        if not isIgnored then
                            local isDuplicate = false
                            if indivParam and indivParam:IsValid() then
                                local guidStr = nil
                                pcall(function()
                                    local g = indivParam:GetIndividualId()
                                    if g then guidStr = g:ToString() end
                                end)
                                if not guidStr or guidStr == "" then
                                    pcall(function()
                                        local saveP = indivParam.SaveParameter
                                        if saveP and saveP.IndividualId then
                                            guidStr = saveP.IndividualId:ToString()
                                        end
                                    end)
                                end
                                if guidStr and guidStr ~= "" and guidStr ~= "00000000000000000000000000000000" then
                                    if seenGuids[guidStr] then isDuplicate = true end
                                    seenGuids[guidStr] = true
                                end
                            end

                            if not isDuplicate then
                                local charIdStr = ""
                            if indivParam and indivParam:IsValid() then
                                pcall(function()
                                    local cId = indivParam:GetCharacterID()
                                    if cId then charIdStr = cId:ToString() end
                                end)
                            end
                            if charIdStr == "" and staticParam and staticParam:IsValid() then
                                pcall(function()
                                    local cId = staticParam.CharacterID
                                    if cId then charIdStr = cId:ToString() end
                                end)
                            end

                            local cleanCharId = utils.GetCleanPalId(charIdStr)
                            if cleanCharId == "" then cleanCharId = charIdStr end

                            local isShiny = false
                            if indivParam and indivParam:IsValid() then
                                pcall(function() isShiny = BoolTrue(indivParam:IsRarePal()) end)
                            elseif staticParam and staticParam:IsValid() then
                                pcall(function() isShiny = BoolTrue(staticParam:IsRarePal()) end)
                            end

                            -- IsBoss_Database is also set on lucky pals. ExceptRare is the alpha check.
                            local isBoss = false
                            local exceptRare = nil
                            if staticParam and staticParam:IsValid() then
                                local okExcept, exceptValue = pcall(function() return staticParam:IsBossPal_Database_ExceptRare() end)
                                if okExcept then exceptRare = BoolTrue(exceptValue) end
                            end
                            if exceptRare == true then
                                isBoss = true
                            elseif exceptRare == nil and not isShiny then
                                local lowerCharId = string.lower(charIdStr)
                                if string.find(lowerCharId, "boss_", 1, true) or string.find(lowerCharId, "fboss_", 1, true) or string.find(lowerCharId, "_boss", 1, true) then
                                    isBoss = true
                                elseif staticParam and staticParam:IsValid() and staticParam.IsBoss_Database == true then
                                    isBoss = true
                                end
                            end

                            local palName = utils.GetTranslatedPalName(charIdStr)

                            local level = nil
                            if indivParam and indivParam:IsValid() then
                                pcall(function() level = indivParam:GetLevel() end)
                            elseif charParam and charParam:IsValid() then
                                pcall(function() level = charParam:GetLevel() end)
                            end

                            local rank = 0
                            if indivParam and indivParam:IsValid() then
                                pcall(function() rank = indivParam:GetRank() end)
                            end

                            local rawPassives = {}
                            if indivParam and indivParam:IsValid() then
                                pcall(function()
                                    local pList = indivParam:GetPassiveSkillList()
                                    rawPassives = utils.TArrayToTable(pList)
                                end)
                                if #rawPassives == 0 then
                                    pcall(function()
                                        local pList = indivParam.PassiveSkillList
                                        rawPassives = utils.TArrayToTable(pList)
                                    end)
                                end
                            end

                            -- ⚡ Bolt Performance Optimization:
                            -- Removed the unused `palPassivesStr` table allocation and `table.insert` operation.
                            -- Impact: Reduces Garbage Collection (GC) pressure inside the high-frequency Pal scanning loop.
                            local translatedPassives = {}
                            local structuredPassives = {}
                            local palPassiveMap = {}

                            for _, pName in ipairs(rawPassives) do
                                local strP = utils.FNameToString(pName)
                                if strP and strP ~= "" and strP ~= "None" then
                                    local transP = utils.GetTranslatedPassiveName(strP)
                                    if not transP or transP == "" then
                                        transP = strP
                                    end
                                    table.insert(translatedPassives, transP)

                                    local pRank = utils.GetPassiveRank(strP)
                                    local pColor = utils.GetPassiveRarityColor(pRank)
                                    table.insert(structuredPassives, {
                                        name = transP,
                                        rawId = strP,
                                        rank = pRank,
                                        color = pColor
                                    })

                                    local lowerRaw = string.lower(strP)
                                    local normRaw = NormalizePassiveString(strP)
                                    local lowerTrans = string.lower(transP)
                                    local normTrans = NormalizePassiveString(transP)

                                    palPassiveMap[strP] = transP
                                    palPassiveMap[transP] = transP
                                    palPassiveMap[lowerRaw] = transP
                                    palPassiveMap[normRaw] = transP
                                    palPassiveMap[lowerTrans] = transP
                                    palPassiveMap[normTrans] = transP
                                end
                            end

                            local isMimog = IsMimogPal(actor, charIdStr, cleanCharId, palName)

                            local shouldTrack = false
                            local matchedPassiveCount = 0
                            local matchedPassiveNames = {}

                            if filterMode == "All" then
                                shouldTrack = true
                            elseif filterMode == "ShinyOnly" then
                                shouldTrack = isShiny
                            elseif filterMode == "BossOnly" then
                                shouldTrack = isBoss
                            elseif filterMode == "ShinyOrBoss" then
                                shouldTrack = isShiny or isBoss
                            elseif filterMode == "TrackerListOnly" then
                                for _, rule in pairs(rulesList) do
                                    local pass, count, matchedList = EvaluatePalRule(rule, palName, charIdStr, cleanCharId, isShiny, isBoss, palPassiveMap)
                                    if pass then
                                        shouldTrack = true
                                        if count > matchedPassiveCount then
                                            matchedPassiveCount = count
                                            matchedPassiveNames = matchedList or {}
                                        end
                                        break
                                    end
                                end
                            end

                            if isMimog then
                                shouldTrack = true
                            end

                            -- Base workers are not in the party holder. Check only pals that
                            -- already matched the tracker, so this stays a handful of calls.
                            if shouldTrack and not includeOwned and not isOwned then
                                if LiveOwned(actor, charParam) then
                                    isOwned = true
                                    shouldTrack = false
                                end
                            end

                            if shouldTrack then
                                local labelParts = { palName }

                                if showLevel and level then
                                    table.insert(labelParts, "lv." .. tostring(level))
                                end

                                if rank and rank > 0 then
                                    local stars = string.rep("*", rank)
                                    table.insert(labelParts, stars)
                                end

                                if isShiny then
                                    table.insert(labelParts, "Shiny")
                                end

                                if isBoss then
                                    table.insert(labelParts, "Boss")
                                end

                                if isOwned then
                                    table.insert(labelParts, "Owned")
                                end

                                if matchedPassiveCount > 0 then
                                    table.insert(labelParts, "(" .. tostring(matchedPassiveCount) .. ")")
                                end

                                local showOnlyMatched = (palConfig.ShowOnlyMatchedPassives == true)
                                local passivesToDisplay = {}
                                local passiveNamesToDisplay = {}

                                if showPassives then
                                    if showOnlyMatched and #matchedPassiveNames > 0 then
                                        local matchedSet = {}
                                        for _, mName in ipairs(matchedPassiveNames) do
                                            matchedSet[mName] = true
                                        end
                                        for _, pItem in ipairs(structuredPassives) do
                                            if matchedSet[pItem.name] or matchedSet[pItem.rawId] then
                                                table.insert(passivesToDisplay, pItem)
                                                table.insert(passiveNamesToDisplay, pItem.name)
                                            end
                                        end
                                    else
                                        passivesToDisplay = structuredPassives
                                        passiveNamesToDisplay = translatedPassives
                                    end
                                end

                                local formattedLabel = table.concat(labelParts, " ")
                                local distStr = math.floor(math.sqrt(distSq) / 100.0) .. "m"
                                local passivesStr = #passiveNamesToDisplay > 0 and table.concat(passiveNamesToDisplay, ", ") or nil

                                table.insert(newPals, {
                                    Actor = actor,
                                    X = px, Y = py, Z = pz,
                                    Name = formattedLabel,
                                    PalName = palName,
                                    Level = level,
                                    IsShiny = isShiny,
                                    IsBoss = isBoss,
                                    IsMimog = isMimog,
                                    IsOwned = isOwned,
                                    Passives = passivesToDisplay,
                                    PassivesNames = passiveNamesToDisplay,
                                    MatchedPassives = matchedPassiveNames,
                                    MatchedPassiveCount = matchedPassiveCount,
                                    PassivesStr = passivesStr,
                                    DistStr = distStr,
                                    BracketDistStr = "[" .. distStr .. "]"
                                })
                            end
                            end
                        end
                    end
                end
            end)
        end
    end

    if not M.hasLoggedPals and #newPals > 0 then
        M.hasLoggedPals = true
        logger.log("Pal Scan (Initial detection): Found " .. tostring(#newPals) .. " tracked Pals.")
    end

    return newPals
end

return M
