local UEHelpers = require("UEHelpers")
local configMod = require("HUDLocator.config")
local logger = require("HUDLocator.logger")

local M = {}

M.MapObjectNameCache = {}
M.ItemNameCache = {}
M.DungeonNameCache = {}
M.NoteNameCache = {}
M.PalNameCache = {}
M.PassiveNameCache = {}
M.LoggedTranslations = {}
M.MasterDataUtility = nil
M.CachedFont = nil
M.FontScaleMultiplier = 0.7
local lastFontScanTime = 0
local fontScanInterval = 10.0
local cachedController = nil

local function Live(obj)
    if type(obj) ~= "userdata" then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and (valid == true or valid == 1)
end

-- UEHelpers.GetPlayerController runs FindAllOf on every call. The HUD draw
-- already has the controller, so later scans reuse that instead of searching.
function M.NotePlayerController(controller)
    if Live(controller) then cachedController = controller end
end

function M.PlayerController(hud)
    if hud then
        local owner = nil
        pcall(function() owner = hud.PlayerOwner end)
        if Live(owner) then
            cachedController = owner
            return owner
        end
    end
    if Live(cachedController) then return cachedController end
    cachedController = nil
    local pc = nil
    pcall(function() pc = UEHelpers.GetPlayerController() end)
    if Live(pc) then cachedController = pc end
    return cachedController
end

function M.Player(hud)
    local pc = M.PlayerController(hud)
    if not Live(pc) then return nil end
    local pawn = nil
    pcall(function() pawn = pc.Pawn end)
    if Live(pawn) then return pawn end
    return nil
end

function M.World(hint)
    if Live(hint) then
        local world = nil
        pcall(function() world = hint:GetWorld() end)
        if Live(world) then return world end
    end
    local pc = M.PlayerController()
    if not Live(pc) then return nil end
    local world = nil
    pcall(function() world = pc:GetWorld() end)
    if Live(world) then return world end
    return nil
end

function M.GetFontAndScale()
    local font = M.CachedFont
    if font then
        local isValid = false
        pcall(function() isValid = font:IsValid() end)
        if not isValid then
            M.CachedFont = nil
            font = nil
        end
    end
    local systemMult = font and M.FontScaleMultiplier or 1.0
    local userScale = 1.0
    if configMod.CONFIG and configMod.CONFIG.Global and configMod.CONFIG.Global.FontScale then
        userScale = configMod.CONFIG.Global.FontScale
    end
    return font, systemMult * userScale
end

-- Validates whether the game world is fully loaded and safe for scanning.
-- Returns false during loading screens, level transitions, fast travel, or player respawning.
function M.IsWorldReady()
    -- 1. Check in-game HUD actor
    local hudCheck = nil
    pcall(function() hudCheck = FindFirstOf("BP_PalHUD_InGame_C") end)
    if not hudCheck or not hudCheck:IsValid() then
        return false
    end

    -- 2. Check GameInstance loading state. A leftover fade parameter object stays
    -- valid after a watchtower cutscene, so only a visible loading widget counts.
    local isStarting = false
    local hasLoadingTask = false
    pcall(function()
        local gi = FindFirstOf("BP_PalGameInstance_C")
        if gi and gi:IsValid() then
            if gi.IsStartingGame then isStarting = true end
            local task = gi.CurrentLoadingTask
            if task and task:IsValid() then hasLoadingTask = true end
        end
    end)
    if isStarting then
        return false
    end

    -- 3. Check Loading Screen Widgets
    local isLoadingWidgetActive = false
    local function WidgetBlocksReady(widget)
        if not widget or not widget:IsValid() then return false end
        local full = ""
        pcall(function() full = widget:GetFullName() end)
        if full and string.find(full, "Default__", 1, true) then return false end
        local inView = false
        pcall(function() inView = widget:IsInViewport() end)
        if inView ~= true and inView ~= 1 then return false end
        local vis = nil
        local ok = pcall(function() vis = widget:GetVisibility() end)
        local n = ok and tonumber(vis) or nil
        if n == 1 or n == 2 then return false end
        return true
    end
    pcall(function()
        local loadScreen = FindFirstOf("WBP_LoadingScreen_Transition_C")
        if not loadScreen or not loadScreen:IsValid() then
            loadScreen = FindFirstOf("WBP_LoadingScreen_C")
        end
        if WidgetBlocksReady(loadScreen) then
            isLoadingWidgetActive = true
        end
        if not isLoadingWidgetActive and hasLoadingTask then
            local fade = FindFirstOf("WBP_InLevelLoadingFade_C")
            if WidgetBlocksReady(fade) then
                isLoadingWidgetActive = true
            end
        end
    end)
    if isLoadingWidgetActive then
        return false
    end

    -- 4. Check Local Player & Player Controller
    local localPlayer = M.Player()
    if not localPlayer or not localPlayer:IsValid() then
        return false
    end

    local pc = nil
    pcall(function() pc = localPlayer:GetController() end)
    if not pc or not pc:IsValid() then
        pcall(function() pc = localPlayer.Controller end)
    end
    if not pc or not pc:IsValid() then
        return false
    end

    -- 5. Check Player Level & OwningWorld
    local hasValidWorld = false
    pcall(function()
        local level = localPlayer:GetLevel()
        if level and level:IsValid() then
            local world = level.OwningWorld
            if world and world:IsValid() then
                hasValidWorld = true
            end
        end
    end)
    if not hasValidWorld then
        return false
    end

    return true
end

-- Proactively validates that an actor is fully initialized, not being destroyed,
-- and attached to a valid Level and OwningWorld before running reflection queries.
function M.IsActorValidForScan(actor)
    if not actor then return false end
    local valid = false
    pcall(function()
        if not actor:IsValid() then return end
        if actor.IsActorBeingDestroyed and actor:IsActorBeingDestroyed() then return end
        local level = actor:GetLevel()
        if not level or not level:IsValid() then return end
        local world = level.OwningWorld
        if not world or not world:IsValid() then return end
        valid = true
    end)
    return valid
end

function M.OpenURL(url)
    pcall(function()
        local status, SystemLibrary = pcall(function() return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end)
        if status and SystemLibrary then
            SystemLibrary:LaunchURL(url)
            print("[HUDLocator] Launching URL: " .. tostring(url) .. "\n")
        else
            print("[HUDLocator] ERROR: KismetSystemLibrary not found, cannot launch URL." .. "\n")
        end
    end)
end

function M.UrlEncode(str)
    if not str then return "" end
    str = string.gsub(str, "([^%w %-%_%.%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    str = string.gsub(str, " ", "+")
    return str
end

function M.DrawText(hud, text, color, x, y, baseScale, scalePosition)
    local font, scaleMult = M.GetFontAndScale()
    local finalScale = (baseScale or 1.0) * scaleMult
    hud:DrawText(text, color, x, y, font, finalScale, scalePosition or false)
end

local TextSizeCache = {}

-- Safely measure text width using Unreal Engine's GetTextSize.
-- Falls back to 0 on failure. Logs outcomes once via M.LogOnce to avoid frame-rate lag.
function M.GetTextSize(hud, text, baseScale)
    if not text or text == "" then return 0 end
    local font, scaleMult = M.GetFontAndScale()
    local finalScale = (baseScale or 1.0) * scaleMult
    
    local cacheKey = text .. "_" .. string.format("%.3f", finalScale)
    if TextSizeCache[cacheKey] then
        return TextSizeCache[cacheKey]
    end
    
    local width = 0
    if font then
        local success, err = pcall(function()
            local canvas = hud.Canvas
            if canvas and canvas:IsValid() then
                -- UCanvas:K2_TextSize(class UFont* RenderFont, FString RenderText, FVector2D Scale)
                local size = canvas:K2_TextSize(font, text, { X = finalScale, Y = finalScale })
                if size then
                    width = size.X or size.x or 0
                end
            end
        end)
        
        if success and width and width > 0 then
            TextSizeCache[cacheKey] = width
            M.LogOnce("text_size_success", string.format("GetTextSize successfully measuring font sizes via UCanvas. Example: text='%s', scale=%.2f -> width=%.2f (using custom font: %s)", tostring(text), finalScale, width, tostring(font ~= nil)))
        else
            local errMsg = err or (not hud.Canvas and "hud.Canvas is nil" or "K2_TextSize returned nil size")
            M.LogOnce("text_size_fail_" .. tostring(text), string.format("GetTextSize failed or returned 0 for text '%s' (scale=%.2f, custom font: %s). Error: %s. Using fallback character spacing.", tostring(text), finalScale, tostring(font ~= nil), tostring(errMsg)))
        end
    end
    
    return width
end

function M.DebugPrint(msg)
    configMod.DebugPrint(msg)
end

function M.LogOnce(key, msg)
    if not M.LoggedTranslations[key] then
        M.LoggedTranslations[key] = true
        M.DebugPrint(msg)
    end
end

function M.GetTranslatedMapObjectName(masterDataId)
    local idStr = nil
    if type(masterDataId) == "string" then
        idStr = masterDataId
    elseif type(masterDataId) == "userdata" then
        pcall(function() idStr = masterDataId:ToString() end)
    end
    if not idStr then idStr = tostring(masterDataId) end

    if configMod.CONFIG.Global.Language ~= "system" and configMod.CONFIG.Global.Language ~= "" then
        if string.find(idStr, "FishingJunk", 1, true) then return configMod.GetTranslation("FishingJunk", "Fishing Junk") end
        if string.find(idStr, "RequiredLongHold", 1, true) or string.find(idStr, "Search", 1, true) then return configMod.GetTranslation("LandJunk", "Land Junk") end
        if string.find(idStr, "TreasureBox") then return configMod.GetTranslation("Chest", "Chest") end
        if string.find(idStr, "Relic") then return configMod.GetTranslation("Relic", "Relic") end
        if string.find(idStr, "PalEgg") then return configMod.GetTranslation("Egg", "Egg") end
        return idStr
    end

    if M.MapObjectNameCache[idStr] then
        return M.MapObjectNameCache[idStr]
    end
    
    if not M.MasterDataUtility then
        local status, util = pcall(function() return StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility") end)
        if status and util then M.MasterDataUtility = util end
    end
    
    local world = M.World()
    if world then
        if M.MasterDataUtility then
            local mapObjectKey = "MAPOBJECT_NAME_" .. idStr
            local status, outText = pcall(function()
                return M.MasterDataUtility:GetLocalizedText(world, 13, FName(mapObjectKey))
            end)
            M.LogOnce(mapObjectKey, string.format("MapObjectName lookup key=%s, status=%s, outText=%s", mapObjectKey, tostring(status), tostring(outText)))
            if status and outText then
                local strStatus, str = pcall(function() return outText:ToString() end)
                M.LogOnce(mapObjectKey .. "_str", string.format("MapObjectName stringify key=%s, strStatus=%s, str=%s", mapObjectKey, tostring(strStatus), tostring(str)))
                if strStatus and str and str ~= "" then
                    if str == mapObjectKey then
                        -- Translation failed (e.g. custom constructed ID string like TreasureBox_GradeX), cache a fallback
                        if string.find(idStr, "TreasureBox") then
                            str = configMod.GetTranslation("Chest", "Chest")
                        elseif string.find(idStr, "Relic") then
                            str = configMod.GetTranslation("Relic", "Relic")
                        elseif string.find(idStr, "PalEgg") then
                            str = configMod.GetTranslation("Egg", "Egg")
                        else
                            str = idStr
                        end
                    end
                    M.MapObjectNameCache[idStr] = str
                    return str
                end
            end
        end
    end
    
    -- Cache failure fallback to avoid calling GetLocalizedText on every scan loop tick
    local fallback = idStr
    if string.find(idStr, "TreasureBox") then
        fallback = configMod.GetTranslation("Chest", "Chest")
    elseif string.find(idStr, "Relic") then
        fallback = configMod.GetTranslation("Relic", "Relic")
    elseif string.find(idStr, "PalEgg") then
        fallback = configMod.GetTranslation("Egg", "Egg")
    end
    M.MapObjectNameCache[idStr] = fallback
    return fallback
end

function M.GetTranslatedDungeonName(overrideId)
    if not overrideId or overrideId:ToString() == "None" then
        return nil
    end
    local idStr = overrideId:ToString()
    local dungeonKey = idStr
    if not string.match(idStr, "^NAME_") then
        dungeonKey = "NAME_" .. idStr
    end
    
    if configMod.CONFIG.Global.Language ~= "system" and configMod.CONFIG.Global.Language ~= "" then
        return configMod.GetTranslation("Cave", "Cave")
    end

    if M.DungeonNameCache[idStr] then
        return M.DungeonNameCache[idStr]
    end
    
    if not M.MasterDataUtility then
        local status, util = pcall(function() return StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility") end)
        if status and util then M.MasterDataUtility = util end
    end
    
    local world = M.World()
    if world then
        if M.MasterDataUtility then
            local status, outText = pcall(function()
                return M.MasterDataUtility:GetLocalizedText(world, 21, FName(dungeonKey))
            end)
            M.LogOnce(dungeonKey, string.format("DungeonName lookup key=%s, status=%s, outText=%s", dungeonKey, tostring(status), tostring(outText)))
            if status and outText then
                local strStatus, str = pcall(function() return outText:ToString() end)
                M.LogOnce(dungeonKey .. "_str", string.format("DungeonName stringify key=%s, strStatus=%s, str=%s", dungeonKey, tostring(strStatus), tostring(str)))
                if strStatus and str and str ~= "" then
                    if str == dungeonKey then
                        str = configMod.GetTranslation("Cave", "Cave")
                    end
                    M.DungeonNameCache[idStr] = str
                    return str
                end
            end
        end
    end
    
    -- Cache translation failure fallback
    M.DungeonNameCache[idStr] = configMod.GetTranslation("Cave", "Cave")
    return M.DungeonNameCache[idStr]
end

function M.GetTranslatedItemName(itemId)
    local idStr = nil
    if type(itemId) == "string" then
        idStr = itemId
    elseif type(itemId) == "userdata" then
        pcall(function() idStr = itemId:ToString() end)
    end
    if not idStr then idStr = tostring(itemId) end

    if configMod.CONFIG.Global.Language ~= "system" and configMod.CONFIG.Global.Language ~= "" then
        if string.find(idStr, "Relic") then return configMod.GetTranslation("Relic", "Relic") end
        return idStr
    end

    if M.ItemNameCache[idStr] then
        return M.ItemNameCache[idStr]
    end
    
    if not M.MasterDataUtility then
        local status, util = pcall(function() return StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility") end)
        if status and util then M.MasterDataUtility = util end
    end
    
    local world = M.World()
    if world then
        if M.MasterDataUtility then
            local itemKey = "ITEM_NAME_" .. idStr
            local status, outText = pcall(function()
                return M.MasterDataUtility:GetLocalizedText(world, 11, FName(itemKey))
            end)
            M.LogOnce(itemKey, string.format("ItemName lookup key=%s, status=%s, outText=%s", itemKey, tostring(status), tostring(outText)))
            if status and outText then
                local strStatus, str = pcall(function() return outText:ToString() end)
                M.LogOnce(itemKey .. "_str", string.format("ItemName stringify key=%s, strStatus=%s, str=%s", itemKey, tostring(strStatus), tostring(str)))
                if strStatus and str and str ~= "" then
                    if str == itemKey then
                        str = idStr
                    end
                    M.ItemNameCache[idStr] = str
                    return str
                end
            end
        end
    end
    
    -- Cache failure fallback
    M.ItemNameCache[idStr] = idStr
    return idStr
end

function M.GetTranslatedRelicName(relicType)
    local itemId = "Relic"
    local num = nil
    if type(relicType) == "number" then
        num = relicType
    elseif type(relicType) == "userdata" then
        local statusVal, val = pcall(function() return relicType.value end)
        if statusVal and type(val) == "number" then
            num = val
        else
            local statusVal2, val2 = pcall(function() return relicType:value() end)
            if statusVal2 and type(val2) == "number" then
                num = val2
            else
                num = tonumber(tostring(relicType))
            end
        end
    end
    
    if num == 0 then
        itemId = "Relic"
    elseif num and num >= 1 and num <= 12 then
        itemId = string.format("Relic_%02d", num)
    end

    return M.GetTranslatedItemName(itemId)
end

function M.IsRelicPicked(relic)
    local status, picked = pcall(function()
        if relic:IsValid() then
            return relic.bPickedInClient
        end
        return true
    end)
    if status then
        return picked
    else
        return true
    end
end

function M.IsChestOpened(chest)
    local status, opened = pcall(function()
        if chest:IsValid() then
            local model = chest.MapObjectModel
            if model and model:IsValid() then
                local concrete = model.ConcreteModel
                if concrete and concrete:IsValid() then
                    return concrete.bOpened
                end
            end
        end
        return true
    end)
    if status then
        return opened
    else
        return true
    end
end

function M.IsEggPicked(egg)
    local status, picked = pcall(function()
        if not egg:IsValid() then return true end
        if egg.bHidden then return true end
        
        if type(egg.bPickedInClient) == "boolean" and egg.bPickedInClient then return true end
        
        local model = egg.MapObjectModel
        if model and model:IsValid() then
            local concrete = model.ConcreteModel
            if concrete and concrete:IsValid() then
                if type(concrete.bPicked) == "boolean" and concrete.bPicked then return true end
                if type(concrete.bIsPicked) == "boolean" and concrete.bIsPicked then return true end
            end
        end
        
        return false
    end)
    
    if status then return picked else return false end
end

function M.IsNotePicked(note)
    local status, picked = pcall(function()
        if note:IsValid() then
            return note.bPickedInClient
        end
        return true
    end)
    if status then
        return picked
    else
        return true
    end
end

local NOTE_DESCRIPTION = 22

local function NoteTitleLine(str, key)
    if type(str) ~= "string" then return "" end
    str = str:gsub("\r\n", "\n"):gsub("\r", "\n")
    local line = str:match("^%s*(%S[^\n]*)")
    if not line then return "" end
    line = line:gsub("%s+$", ""):gsub("<[^>]+>", "")
    if line == "" or line == key or line == "None" or #line > 120 then return "" end
    return line
end

local function NoteTitleText(key, category)
    if not key or key == "" or key == "None" then return "" end
    if not M.MasterDataUtility then
        local status, util = pcall(function() return StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility") end)
        if status and util then M.MasterDataUtility = util end
    end
    local world = M.World()
    if not world or not M.MasterDataUtility then return nil end
    local status, outText = pcall(function()
        return M.MasterDataUtility:GetLocalizedText(world, category or NOTE_DESCRIPTION, FName(key))
    end)
    if not status or not outText then return "" end
    local strStatus, str = pcall(function() return outText:ToString() end)
    if not strStatus then return "" end
    return NoteTitleLine(str, key)
end

local function NoteTitleFromData(idStr)
    local world = M.World()
    if not world or not M.MasterDataUtility then return "" end
    local desc = nil
    local ok = pcall(function()
        local asset = M.MasterDataUtility:GetNoteDataAsset(world)
        if not asset or not asset:IsValid() then return end
        local data = asset:Find(FName(idStr))
        if not data or not data:IsValid() then return end
        if data.TextId_Description and data.TextId_Description.ToString then
            desc = data.TextId_Description:ToString()
        end
    end)
    if not ok or not desc or desc == "" or desc == "None" then return "" end
    local titleKey = desc:gsub("DESCRIPTION", "TITLE"):gsub("Description", "Title"):gsub("DESC", "TITLE")
    if titleKey ~= desc then
        local titled = NoteTitleText(titleKey)
        if titled and titled ~= "" then return titled end
    end
    local short = NoteTitleText(desc)
    if short and short ~= "" then return short end
    return ""
end

function M.GetTranslatedNoteName(noteKey)
    local idStr = nil
    if type(noteKey) == "string" then
        idStr = noteKey
    elseif type(noteKey) == "userdata" then
        pcall(function() idStr = noteKey:ToString() end)
    end
    if not idStr or idStr == "" or idStr == "None" then return nil end

    if M.NoteNameCache[idStr] then
        return M.NoteNameCache[idStr]
    end

    local title = NoteTitleText(idStr, NOTE_DESCRIPTION)
    if title == nil then return configMod.GetTranslation("Note", "Journal") end
    if title == "" then title = NoteTitleText(idStr, 1) or "" end
    if title == "" then title = NoteTitleFromData(idStr) end
    if title == "" then title = configMod.GetTranslation("Note", "Journal") end

    M.NoteNameCache[idStr] = title
    return title
end

function M.GetDungeonDetails(cave)
    local level = nil
    local state = "Closed"
    
    pcall(function()
        if cave:IsValid() then
            local stageModel = cave.StageModel
            if stageModel and stageModel:IsValid() then
                local instanceModel = stageModel.InstanceModel
                if instanceModel and instanceModel:IsValid() then
                    level = instanceModel.Level
                    
                    local bossState = instanceModel.BossState
                    if bossState == 1 then
                        state = "Cleared"
                    else
                        state = "Open"
                    end
                end
            end
        end
    end)
    
    return level, state
end

function M.GetDistanceSq(posA, posB)
    local dx = posA.X - posB.X
    local dy = posA.Y - posB.Y
    local dz = posA.Z - posB.Z
    return dx*dx + dy*dy + dz*dz
end

function M.FindAndCacheFont()
    if M.CachedFont and M.CachedFont:IsValid() then
        return M.CachedFont
    end

    local currentTime = os.clock()
    if currentTime - lastFontScanTime < fontScanInterval then
        return nil
    end
    lastFontScanTime = currentTime

    logger.log("Starting background font scan...")
    local status, fonts = pcall(function() return FindAllOf("Font") end)
    if status and fonts then
        logger.log(string.format("Font scan completed. Found %d loaded Font objects.", #fonts))
        for _, f in ipairs(fonts) do
            if f:IsValid() then
                local name = f:GetFullName()
                logger.log("Loaded Font: " .. name)
                
                -- Check if it's a game-specific font asset under /Game/ (case-insensitive)
                if string.find(name:lower(), "/game/") then
                    logger.log("Matched and cached game UI font: " .. name)
                    M.CachedFont = f
                    
                    -- Test character length calculation for Thai
                    local testStr = "ถ้ำ"
                    local bytes = #testStr
                    local chars = M.GetStringLength(testStr)
                    logger.log(string.format("UTF-8 Length Test: string='%s', bytes=%d, chars=%d", testStr, bytes, chars))
                    
                    return f
                end
            end
        end
    else
        logger.log("Failed to scan Font objects: " .. tostring(fonts))
    end
    return nil
end

function M.GetStringLength(str)
    if not str then return 0 end
    local status, len = pcall(function() return utf8.len(str) end)
    if status and len then
        return len
    end
    return #str
end

local function GetModDir()
    local info = debug.getinfo(1, "S")
    if info and info.source and info.source:sub(1, 1) == "@" then
        local src = info.source:sub(2)
        local modDir = src:match("(.*)[/\\ ]Scripts[/\\]HUDLocator[/\\]utils%.lua")
        if modDir then
            return modDir
        end
    end
    return "Mods/HUDLocator"
end

local hasDumpedTextures = false
function M.DumpAllLoadedTextures()
    if hasDumpedTextures then return end
    hasDumpedTextures = true
    
    if not (configMod.CONFIG and configMod.CONFIG.Global and configMod.CONFIG.Global.Debug) then
        return
    end
    local status, textures = pcall(function() return FindAllOf("Texture2D") end)
    if status and textures then
        logger.log(string.format("Texture scan completed. Found %d loaded Texture2D objects.", #textures))
        local modDir = GetModDir()
        local filepath = modDir .. "/loaded_textures.txt"
        logger.log("Writing textures to " .. filepath)
        
        local file = io.open(filepath, "w")
        if file then
            file:write("Loaded Texture2D objects:\n\n")
            for _, t in ipairs(textures) do
                if t:IsValid() then
                    local name = t:GetFullName()
                    file:write(name .. "\n")
                end
            end
            file:close()
            logger.log("Successfully wrote all loaded textures to file!")
        else
            logger.log("Failed to open loaded_textures.txt for writing")
        end
    else
        logger.log("Failed to scan Texture2D: " .. tostring(textures))
    end
end

function M.TArrayToTable(arrayVal)
    local t = {}
    if not arrayVal then return t end
    if type(arrayVal) == "table" then return arrayVal end
    if type(arrayVal) == "userdata" then
        if arrayVal.ForEach then
            pcall(function()
                arrayVal:ForEach(function(arg1, arg2)
                    local val = nil
                    if type(arg1) ~= "number" then
                        val = arg1
                    else
                        val = arg2
                    end
                    if val then
                        table.insert(t, val)
                    end
                end)
            end)
        else
            for i = 0, 100 do
                local elem = nil
                local success = pcall(function() elem = arrayVal[i] end)
                if not success or not elem then break end
                table.insert(t, elem)
            end
        end
    end
    return t
end

function M.FNameToString(fn)
    if not fn then return "" end
    if type(fn) == "string" then return fn end
    if type(fn) == "userdata" then
        if fn.get then
            local success, inner = pcall(function() return fn:get() end)
            if success and inner then
                fn = inner
            end
        end
        if type(fn) == "string" then return fn end
        if type(fn) == "userdata" and fn.ToString then
            local success, str = pcall(function() return fn:ToString() end)
            if success and str and type(str) == "string" and not string.find(str, "RemoteUnrealParam") then
                return str
            end
        end
    end
    local s = tostring(fn)
    if string.find(s, "RemoteUnrealParam") then
        return ""
    end
    return s
end

function M.GetCleanPalId(idStr)
    if not idStr or idStr == "" then return "" end
    local clean = idStr
    -- Strip Blueprint prefixes and suffixes if present
    clean = string.gsub(clean, "^BP_", "")
    clean = string.gsub(clean, "_C$", "")
    
    -- Strip Boss / Predator / Raid / Gym prefixes (case-insensitive)
    clean = string.gsub(clean, "^[Bb][Oo][Ss][Ss]_", "")
    clean = string.gsub(clean, "^[Ff][Bb][Oo][Ss][Ss]_", "")
    clean = string.gsub(clean, "^[Pp][Rr][Ee][Dd][Aa][Tt][Oo][Rr]_", "")
    clean = string.gsub(clean, "^[Rr][Aa][Ii][Dd]_", "")
    clean = string.gsub(clean, "^[Gg][Yy][Mm]_", "")
    
    -- Strip Boss suffixes
    clean = string.gsub(clean, "_[Bb][Oo][Ss][Ss]$", "")
    
    return clean
end

function M.GetTranslatedPalName(masterDataId)
    local idStr = nil
    if type(masterDataId) == "string" then
        idStr = masterDataId
    elseif type(masterDataId) == "userdata" then
        pcall(function() idStr = masterDataId:ToString() end)
    end
    if not idStr then idStr = tostring(masterDataId) end

    local cleanId = M.GetCleanPalId(idStr)
    if cleanId == "" then cleanId = idStr end

    if M.PalNameCache[cleanId] then
        return M.PalNameCache[cleanId]
    end

    if not M.MasterDataUtility then
        local status, util = pcall(function() return StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility") end)
        if status and util then M.MasterDataUtility = util end
    end

    local world = M.World()
    if world and M.MasterDataUtility then
        local palKey = "PAL_NAME_" .. cleanId
        local status, outText = pcall(function()
            return M.MasterDataUtility:GetLocalizedText(world, 4, FName(palKey))
        end)
        if status and outText then
            local strStatus, str = pcall(function() return outText:ToString() end)
            if strStatus and str and str ~= "" and str ~= palKey then
                M.PalNameCache[cleanId] = str
                return str
            end
        end
    end

    M.PalNameCache[cleanId] = cleanId
    return cleanId
end

function M.GetTranslatedPassiveName(passiveId)
    local idStr = M.FNameToString(passiveId)
    if not idStr or idStr == "" or idStr == "None" then return "" end

    if M.PassiveNameCache[idStr] then
        return M.PassiveNameCache[idStr]
    end

    if not M.MasterDataUtility then
        local status, util = pcall(function() return StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility") end)
        if status and util then M.MasterDataUtility = util end
    end

    local world = M.World()
    if world and M.MasterDataUtility then
        local status, outText = pcall(function()
            return M.MasterDataUtility:GetLocalizedText(world, 16, FName(idStr))
        end)
        if not status or not outText or outText:ToString() == idStr then
            status, outText = pcall(function()
                return M.MasterDataUtility:GetLocalizedText(world, 16, FName("PASSIVE_" .. idStr))
            end)
        end
        if status and outText then
            local strStatus, str = pcall(function() return outText:ToString() end)
            if strStatus and str and str ~= "" and str ~= idStr and str ~= ("PASSIVE_" .. idStr) then
                M.PassiveNameCache[idStr] = str
                return str
            end
        end
    end

    M.PassiveNameCache[idStr] = idStr
    return idStr
end

M.RarityColors = {
    Rank4 = { R = 1.0, G = 0.84, B = 0.0, A = 1.0 },   -- Gold / Legend / Rainbow
    Rank3 = { R = 0.96, G = 0.68, B = 0.15, A = 1.0 }, -- Warm Amber / Tier 3
    Rank2 = { R = 0.32, G = 0.78, B = 1.0, A = 1.0 },  -- Cyan / Tier 2
    Rank1 = { R = 0.88, G = 0.88, B = 0.88, A = 1.0 }, -- Silver / White / Tier 1
    RankNeg = { R = 1.0, G = 0.32, B = 0.32, A = 1.0 },-- Coral Red / Negative
    Rank0 = { R = 0.75, G = 0.75, B = 0.75, A = 1.0 }  -- Neutral
}

M.PassiveRankCache = {}
M.PassiveSkillManager = nil

M.StaticPassiveRanks = {
    -- Tier 4 / Legend / Rare / Element Emperor
    ["legend"] = 4, ["rare"] = 4, ["lucky"] = 4, ["divinedragon"] = 4, ["flameemperor"] = 4,
    ["lordoftheunderworld"] = 4, ["sirenofthevoid"] = 4, ["spiritemperor"] = 4, ["iceemperor"] = 4,
    ["celestialemperor"] = 4, ["eternalflame"] = 4, ["earthemperor"] = 4, ["legendary"] = 4,
    ["elementmaster"] = 4, ["invader"] = 4,
    -- Tier 3 (Gold)
    ["swift"] = 3, ["artisan"] = 3, ["musclehead"] = 3, ["ferocious"] = 3, ["burlybody"] = 3,
    ["vanguard"] = 3, ["strongholdstrategist"] = 3, ["motivationalleader"] = 3, ["mineforeman"] = 3,
    ["loggingforeman"] = 3, ["dragonslayer"] = 3, ["craftspeedup2"] = 3, ["movespeedup2"] = 3,
    ["movespeedup3"] = 3, ["attackup2"] = 3, ["defenseup2"] = 3, ["craftspeedup3"] = 3,
    ["craftspeedup3downattack"] = 3, ["runspeedup2"] = 3, ["runspeedup3"] = 3,
    -- Tier 2 (Blue)
    ["runner"] = 2, ["workslave"] = 2, ["zenmind"] = 2, ["dietmaster"] = 2, ["workaholic"] = 2,
    ["serious"] = 2, ["conceited"] = 2, ["masochist"] = 2, ["sadist"] = 2, ["hooligan"] = 2,
    ["craftspeedup1"] = 2, ["movespeedup1"] = 2, ["attackup1"] = 2, ["defenseup1"] = 2,
    ["runspeedup1"] = 2, ["staminaup1"] = 2, ["staminaup2"] = 2,
    -- Tier 1 (White)
    ["nimble"] = 1, ["brave"] = 1, ["hardskin"] = 1, ["positivethinker"] = 1, ["glutton"] = 1,
    ["daintyeater"] = 1, ["hydromaniac"] = 1, ["abnormal"] = 1, ["cheery"] = 1,
    -- Negative (Red)
    ["coward"] = -1, ["slacker"] = -1, ["clumsy"] = -1, ["fragile"] = -1, ["bottomlessstomach"] = -2,
    ["pacifist"] = -1, ["destructive"] = -2, ["downtrodden"] = -1, ["brittle"] = -1, ["unstable"] = -1
}

function M.GetPassiveRank(passiveId)
    local idStr = M.FNameToString(passiveId)
    if not idStr or idStr == "" or idStr == "None" then return 1 end

    if M.PassiveRankCache[idStr] ~= nil then
        return M.PassiveRankCache[idStr]
    end

    -- 1. Try static dictionary first (zero reflection overhead, 100% safe)
    local cleanKey = string.lower(string.gsub(idStr, "[%s_%-]+", ""))
    if M.StaticPassiveRanks[cleanKey] ~= nil then
        local r = M.StaticPassiveRanks[cleanKey]
        M.PassiveRankCache[idStr] = r
        return r
    end

    local trans = M.PassiveNameCache[idStr]
    if trans then
        local cleanTrans = string.lower(string.gsub(trans, "[%s_%-]+", ""))
        if M.StaticPassiveRanks[cleanTrans] ~= nil then
            local r = M.StaticPassiveRanks[cleanTrans]
            M.PassiveRankCache[idStr] = r
            return r
        end
    end

    -- 2. Try native UPalPassiveSkillManager / DT_PassiveSkillData reflection as fallback
    pcall(function()
        if not M.PassiveSkillManager or not M.PassiveSkillManager:IsValid() then
            local status, mgr = pcall(function() return StaticFindObject("/Script/Pal.Default__PalPassiveSkillManager") end)
            if status and mgr and mgr:IsValid() then
                M.PassiveSkillManager = mgr
            else
                local statusClass, mClass = pcall(function() return FindFirstOf("PalPassiveSkillManager") end)
                if statusClass and mClass and mClass:IsValid() then
                    M.PassiveSkillManager = mClass
                end
            end
        end

        if M.PassiveSkillManager and M.PassiveSkillManager:IsValid() then
            local dt = M.PassiveSkillManager.PassiveSkillDataTable
            if dt and dt:IsValid() and dt.FindRow then
                local fn = FName(idStr)
                local row = nil
                pcall(function() row = dt:FindRow(fn) end)
                if not row or not row:IsValid() then
                    local fn2 = FName("PASSIVE_" .. idStr)
                    pcall(function() row = dt:FindRow(fn2) end)
                end
                if row and row:IsValid() and row.Rank ~= nil then
                    M.PassiveRankCache[idStr] = row.Rank
                    return row.Rank
                end
            end
        end
    end)

    if M.PassiveRankCache[idStr] ~= nil then
        return M.PassiveRankCache[idStr]
    end

    M.PassiveRankCache[idStr] = 1
    return 1
end

function M.GetPassiveRarityColor(rank)
    if type(rank) ~= "number" then rank = 1 end
    if rank >= 4 then
        return M.RarityColors.Rank4
    elseif rank == 3 then
        return M.RarityColors.Rank3
    elseif rank == 2 then
        return M.RarityColors.Rank2
    elseif rank == 1 then
        return M.RarityColors.Rank1
    elseif rank < 0 then
        return M.RarityColors.RankNeg
    else
        return M.RarityColors.Rank0
    end
end

-- Fast sequential axis spatial distance evaluation
function M.IsWithinDistanceSq(uePos, playerPos, maxDistSq)
    if not uePos or not playerPos then return false, math.huge end
    local px = uePos.X
    local dx = px - playerPos.X
    local dxSq = dx * dx
    if dxSq > maxDistSq then return false, math.huge end

    local py = uePos.Y
    local dy = py - playerPos.Y
    local dySq = dy * dy
    if (dxSq + dySq) > maxDistSq then return false, math.huge end

    local pz = uePos.Z
    local dz = pz - playerPos.Z
    local distSq = dxSq + dySq + dz * dz
    if distSq > maxDistSq then return false, math.huge end

    return true, distSq, px, py, pz
end

return M

