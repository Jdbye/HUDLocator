local configMod = require("HUDLocator.config")
local scanners = require("HUDLocator.scanners")
local utils = require("HUDLocator.utils")
local completion = require("HUDLocator.completion")
local beams = require("HUDLocator.beams")
local scanPals = require("HUDLocator.scanners.scan_pals")

local M = {}

M.activePlayers = {}
M.activeRelics = {}
M.activeChests = {}
M.activeEggs = {}
M.activeCaves = {}
M.activeLoot = {}
M.activeNotes = {}
M.activeFastTravel = {}
M.activeHacks = {}
M.activeBounties = {}
M.activePals = {}
M.cachedLocalPlayer = nil

local hasRunResolve = false
local function ResolvePaths(hud)
    if hasRunResolve then return end
    hasRunResolve = true
    
    configMod.DebugPrint("Resolving item icon paths using BP_PalUIFunctionLibrary...")
    local lib = StaticFindObject("/Game/Pal/Blueprint/UI/BP_PalUIFunctionLibrary.Default__BP_PalUIFunctionLibrary_C")
    if not lib or not lib:IsValid() then
        local classObj = FindFirstOf("BP_PalUIFunctionLibrary_C")
        if classObj and classObj:IsValid() then
            local statusCDO, res = pcall(function() return classObj:GetDefaultObject() end)
            if statusCDO and res and res:IsValid() then
                lib = res
            end
        end
    end
    if not lib or not lib:IsValid() then
        configMod.DebugPrint("Failed to find valid BP_PalUIFunctionLibrary CDO")
        return
    end
    
    local items = { "Relic", "PalEgg", "TreasureBox", "PalSphere", "CopperKey", "Lifmunk" }
    local localAppData = os.getenv("LOCALAPPDATA") or "C:"
    local filepath = string.gsub(localAppData .. "/Pal/Saved/Mods/HUDLocator/resolved_paths.txt", "\\", "/")
    
    local file = io.open(filepath, "w")
    if file then
        file:write("Resolved Item Paths:\n\n")
        for _, item in ipairs(items) do
            local success, softPtr = pcall(function()
                return lib:GetBlueprintItemIcon(FName(item), hud)
            end)
            if success and softPtr then
                local path = tostring(softPtr.AssetPathName)
                file:write(item .. " -> " .. path .. "\n")
                configMod.DebugPrint(item .. " resolved to: " .. path)
            else
                file:write(item .. " -> failed: " .. tostring(softPtr) .. "\n")
                configMod.DebugPrint(item .. " failed to resolve: " .. tostring(softPtr))
            end
        end
        file:close()
        configMod.DebugPrint("Successfully wrote resolved paths to " .. filepath)
    else
        configMod.DebugPrint("Failed to open resolved_paths.txt for writing")
    end
end

local function GetMaxDistSq(categoryConfig)
    local globalDist = (configMod.CONFIG.Global and configMod.CONFIG.Global.MaxDistance) or 15000.0
    local dist = (categoryConfig and categoryConfig.MaxDistance) or globalDist
    return dist * dist
end

-- Scan players, relics, chests, eggs, caves
function M.scan()
    pcall(function()
        local pmoIntegration = require("HUDLocator.pmo_integration")
        pmoIntegration.Sync()
    end)

    if not configMod.CONFIG.Global.Enabled then
        M.activePlayers = {}
        M.activeRelics = {}
        M.activeChests = {}
        M.activeEggs = {}
        M.activeCaves = {}
        M.activeLoot = {}
        M.activeNotes = {}
        M.activeFastTravel = {}
        M.activeHacks = {}
        M.activeBounties = {}
        M.activePals = {}
        pcall(beams.DespawnAll)
        return
    end

    -- Safety check: Only scan when world is fully ready (not during loading screens or level transitions)
    if not utils.IsWorldReady() then
        M.activePlayers = {}
        M.activeRelics = {}
        M.activeChests = {}
        M.activeEggs = {}
        M.activeCaves = {}
        M.activeLoot = {}
        M.activeNotes = {}
        M.activeFastTravel = {}
        M.activeHacks = {}
        M.activeBounties = {}
        M.activePals = {}
        M.cachedLocalPlayer = nil
        scanners.tempCaves = {}
        pcall(beams.DespawnAll)
        return
    end

    -- Run font scanner in the background
    if not utils.CachedFont or not utils.CachedFont:IsValid() then
        utils.FindAndCacheFont()
    end

    -- Run path resolver only in debug mode
    if configMod.CONFIG and configMod.CONFIG.Global and configMod.CONFIG.Global.Debug then
        local hudCheck = FindFirstOf("BP_PalHUD_InGame_C")
        if hudCheck and hudCheck:IsValid() then
            pcall(ResolvePaths, hudCheck)
        end
    end

    local localPlayer = utils.Player()
    if not localPlayer or not localPlayer:IsValid() then
        M.activePlayers = {}
        M.activeRelics = {}
        M.activeChests = {}
        M.activeEggs = {}
        M.activeCaves = {}
        M.activeLoot = {}
        M.activeNotes = {}
        M.activeFastTravel = {}
        M.activeHacks = {}
        M.activeBounties = {}
        M.activePals = {}
        M.cachedLocalPlayer = nil
        scanners.tempCaves = {}
        pcall(beams.DespawnAll)
        return 
    end

    M.cachedLocalPlayer = localPlayer

    local uePlayerPos = localPlayer:K2_GetActorLocation()
    if not uePlayerPos then return end

    -- Optimize: Convert UE FVector to native Lua table to avoid thousands of C++ property reflection lookups during distance checks
    local playerPos = { X = uePlayerPos.X, Y = uePlayerPos.Y, Z = uePlayerPos.Z }

    -- 1. Scan Players
    if configMod.IsCategoryTracked(configMod.CONFIG.Players) then
        pcall(function()
            local localPlayerState = localPlayer.PlayerState
            M.activePlayers = scanners.ScanPlayers(localPlayerState, localPlayer, playerPos)
        end)
    else
        M.activePlayers = {}
    end

    -- 2. Scan Relics
    if configMod.IsCategoryTracked(configMod.CONFIG.Relics) then
        pcall(function()
            M.activeRelics = scanners.ScanRelics(playerPos, GetMaxDistSq(configMod.CONFIG.Relics))
        end)
    else
        M.activeRelics = {}
    end

    -- 3. Scan Chests
    if configMod.IsCategoryTracked(configMod.CONFIG.Chests) then
        pcall(function()
            M.activeChests = scanners.ScanChests(playerPos, GetMaxDistSq(configMod.CONFIG.Chests))
        end)
    else
        M.activeChests = {}
    end

    -- 4. Scan Eggs
    if configMod.CONFIG.Eggs.Filter ~= "None" and configMod.IsCategoryTracked(configMod.CONFIG.Eggs) then
        pcall(function()
            M.activeEggs = scanners.ScanEggs(playerPos, GetMaxDistSq(configMod.CONFIG.Eggs), configMod.CONFIG.Eggs.Filter, configMod.CONFIG.Global.Debug)
        end)
    else
        M.activeEggs = {}
    end

    -- 5. Scan Caves
    if configMod.IsCategoryTracked(configMod.CONFIG.Caves) then
        pcall(function()
            M.activeCaves = scanners.ScanCaves(playerPos, GetMaxDistSq(configMod.CONFIG.Caves))
        end)
    else
        M.activeCaves = {}
        scanners.tempCaves = {}
    end

    -- 6. Scan Loot
    if configMod.IsCategoryTracked(configMod.CONFIG.Loot) then
        pcall(function()
            M.activeLoot = scanners.ScanLoot(playerPos, GetMaxDistSq(configMod.CONFIG.Loot), configMod.CONFIG.Loot)
        end)
    else
        M.activeLoot = {}
    end

    -- 7. Scan Notes
    if configMod.IsCategoryTracked(configMod.CONFIG.Notes) then
        pcall(function()
            M.activeNotes = scanners.ScanNotes(playerPos, GetMaxDistSq(configMod.CONFIG.Notes))
        end)
    else
        M.activeNotes = {}
    end

    -- 8. Scan unactivated fast travel points
    if configMod.IsCategoryTracked(configMod.CONFIG.FastTravel) then
        pcall(function()
            M.activeFastTravel = scanners.ScanFastTravel(playerPos, GetMaxDistSq(configMod.CONFIG.FastTravel))
        end)
    else
        M.activeFastTravel = {}
    end

    -- 9. Scan uncollected hack-tower prizes
    if configMod.IsCategoryTracked(configMod.CONFIG.Hacks) then
        pcall(function()
            M.activeHacks = scanners.ScanHacks(playerPos, GetMaxDistSq(configMod.CONFIG.Hacks))
        end)
    else
        M.activeHacks = {}
    end

    -- 10. Scan bounty NPCs
    if configMod.IsCategoryTracked(configMod.CONFIG.Bounties) then
        pcall(function()
            M.activeBounties = scanners.ScanBounties(playerPos, GetMaxDistSq(configMod.CONFIG.Bounties))
        end)
    else
        M.activeBounties = {}
    end

    -- 11. Scan Pals
    if configMod.IsCategoryTracked(configMod.CONFIG.Pals) then
        pcall(function()
            M.activePals = scanners.ScanPals(playerPos, GetMaxDistSq(configMod.CONFIG.Pals), configMod.CONFIG.Pals)
        end)
    else
        M.activePals = {}
    end

    -- 12. Scan Completionist Save Data
    if configMod.CONFIG.Completionist and configMod.CONFIG.Completionist.Enabled then
        local completionOk, completionErr = pcall(completion.ScanCompletionData)
        if not completionOk then
            print("[HUDLocator] Completion scan error: " .. tostring(completionErr) .. "\n")
        end
    end

    -- 13. Sync world-space Niagara beam pillars with current tracked items
    local beamOk, beamErr = pcall(M.SyncBeams)
    if not beamOk then
        print("[HUDLocator] Beam sync error: " .. tostring(beamErr) .. "\n")
    end
end

local function GetCategoryBeamColor(catConfig, colorOverride)
    if colorOverride then return colorOverride end
    if catConfig and catConfig.Style and catConfig.Style.NameColor then
        return catConfig.Style.NameColor
    end
    return { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
end

-- A pal at the palbox is often not marked owned on the first scan.
-- Wait until the same actor is still unowned on the next scan before giving it a pillar.
local palBeamConfirm = {}

local function ActorStableId(actor)
    if not actor then return nil end
    local ok, addr = pcall(function() return actor:GetAddress() end)
    if ok and addr and addr ~= 0 then return tostring(addr) end
    return nil
end

local function ConfirmedPalBeams(pals)
    local ready = {}
    local keep = {}
    if pals then
        for i = 1, #pals do
            local pal = pals[i]
            local id = ActorStableId(pal.Actor) or beams.MakeKey("Pals", pal)
            keep[id] = true
            local seen = (palBeamConfirm[id] or 0) + 1
            palBeamConfirm[id] = seen
            if seen >= 2 then
                ready[#ready + 1] = pal
            end
        end
    end
    for id, _ in pairs(palBeamConfirm) do
        if not keep[id] then palBeamConfirm[id] = nil end
    end
    return ready
end

local function AppendBeamEntries(desired, category, items, catConfig, getItem, getColor)
    if not configMod.ShouldShowBeam(catConfig) or not items then return end
    local defaultColor = GetCategoryBeamColor(catConfig)
    for i = 1, #items do
        local item = items[i]
        local beamItem = getItem and getItem(item) or item
        if beamItem then
            local color = defaultColor
            if getColor then
                color = getColor(item) or defaultColor
            end
            local loc = beamItem.Pos or beamItem
            table.insert(desired, {
                key = beams.MakeKey(category, beamItem),
                actor = beamItem.Actor,
                loc = { X = loc.X, Y = loc.Y, Z = loc.Z },
                color = color,
                category = category,
                mobile = category == "Pals" or category == "Players" or category == "Bounties"
            })
        end
    end
end

function M.SyncBeams()
    local CONFIG = configMod.CONFIG
    local desired = {}

    local localPawn = M.cachedLocalPlayer
    local graceM = (CONFIG.Players and CONFIG.Players.GraceRadiusM) or 30
    local graceSq = (graceM * 100.0) * (graceM * 100.0)
    local localPos = nil
    if localPawn and localPawn:IsValid() then
        local okPos, pos = pcall(function() return localPawn:K2_GetActorLocation() end)
        if okPos then localPos = pos end
    end
    AppendBeamEntries(desired, "Players", M.activePlayers, CONFIG.Players, function(p)
        if scanPals.IsSelfActor(p.Actor) then return nil end
        if localPawn and localPawn:IsValid() and p.Actor and p.Actor:IsValid() then
            local same = p.Actor == localPawn
            if not same then
                local okA, addrA = pcall(function() return p.Actor:GetAddress() end)
                local okB, addrB = pcall(function() return localPawn:GetAddress() end)
                same = okA and okB and addrA and addrA == addrB
            end
            if same then return nil end
        end
        if localPos and p.Pos then
            local dx = (p.Pos.X or 0.0) - (localPos.X or 0.0)
            local dy = (p.Pos.Y or 0.0) - (localPos.Y or 0.0)
            local dz = (p.Pos.Z or 0.0) - (localPos.Z or 0.0)
            if dx * dx + dy * dy + dz * dz <= graceSq then return nil end
        end
        return { Actor = p.Actor, Name = p.Name, Pos = p.Pos, X = p.Pos and p.Pos.X, Y = p.Pos and p.Pos.Y, Z = p.Pos and p.Pos.Z }
    end)

    AppendBeamEntries(desired, "Relics", M.activeRelics, CONFIG.Relics)
    AppendBeamEntries(desired, "Chests", M.activeChests, CONFIG.Chests)
    if CONFIG.Eggs and CONFIG.Eggs.Filter ~= "None" then
        AppendBeamEntries(desired, "Eggs", M.activeEggs, CONFIG.Eggs)
    end
    AppendBeamEntries(desired, "Caves", M.activeCaves, CONFIG.Caves)
    AppendBeamEntries(desired, "Loot", M.activeLoot, CONFIG.Loot)
    AppendBeamEntries(desired, "Notes", M.activeNotes, CONFIG.Notes)
    AppendBeamEntries(desired, "FastTravel", M.activeFastTravel, CONFIG.FastTravel)
    AppendBeamEntries(desired, "Hacks", M.activeHacks, CONFIG.Hacks)
    AppendBeamEntries(desired, "Bounties", M.activeBounties, CONFIG.Bounties)
    local palBeams = {}
    local confirmed = ConfirmedPalBeams(M.activePals)
    for i = 1, #confirmed do
        if not scanPals.IsSelfActor(confirmed[i].Actor) then
            palBeams[#palBeams + 1] = confirmed[i]
        end
    end
    AppendBeamEntries(desired, "Pals", palBeams, CONFIG.Pals, nil, function(pal)
        if pal.IsMimog and CONFIG.Pals.Style and CONFIG.Pals.Style.MimogColor then
            return CONFIG.Pals.Style.MimogColor
        elseif pal.IsShiny and CONFIG.Pals.Style and CONFIG.Pals.Style.ShinyColor then
            return CONFIG.Pals.Style.ShinyColor
        elseif pal.IsBoss and CONFIG.Pals.Style and CONFIG.Pals.Style.BossColor then
            return CONFIG.Pals.Style.BossColor
        end
        return nil
    end)

    beams.Sync(desired)
end

return M
