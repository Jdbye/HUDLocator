-- World-space Niagara beam pillars.
-- The long visible range comes from mEi_EffigyBeaconRange_P.pak, which replaces
-- NS_MapObject_TreasureLight for the whole game. Spawn matches ScanEffigiesBLP.

local configMod = require("HUDLocator.config")
local utils = require("HUDLocator.utils")
local scanPals = require("HUDLocator.scanners.scan_pals")

local function OwnedPalBeamBlocked(actor)
    local pals = configMod.CONFIG and configMod.CONFIG.Pals
    if pals and pals.IncludeOwned == true then return false end
    if not actor then return false end
    local owned = false
    pcall(function() owned = scanPals.IsOwnedActor(actor) end)
    return owned == true
end

local M = {}

local BEAM_EFFECT_PATH = "/Game/Pal/Effect/Treasure/NS_MapObject_TreasureLight.NS_MapObject_TreasureLight"
local COLOR_PARAM = "User.Color"
local SCALE_PARAM = "User.Scale"
local MAX_SPAWNS_PER_SYNC = 24

local niagaraLib = nil
local beamAsset = nil
local spawnedBeams = {}
local generation = 0
local logged = {}

local function LogOnce(key, msg)
    if logged[key] then return end
    logged[key] = true
    print("[HUDLocator] " .. msg .. "\n")
end

local function IsValidObj(obj)
    if type(obj) ~= "userdata" then return false end
    if type(IsValid) == "function" then
        local ok, valid = pcall(IsValid, obj)
        if ok and valid == true then return true end
    end
    local ok, valid = pcall(obj.IsValid, obj)
    return ok and valid == true
end

local function Unwrap(obj)
    if obj and type(obj) == "userdata" and obj.get then
        local ok, inner = pcall(obj.get, obj)
        if ok and inner then return inner end
    end
    return obj
end

-- Niagara only appears if it is spawned on the game thread. ExecuteWithDelay is not
-- that thread. Keep one callback queued. Do not start another from inside it.
local Reconcile
local RunRefresh
local gameThreadQueued = false
local gameThreadQueuedAt = nil
local pendingReconcile = nil
local wantRefresh = false

local function NowSeconds()
    if os and os.clock then return os.clock() end
    return nil
end

local function DrainGameThread()
    for _ = 1, 3 do
        if not pendingReconcile and not wantRefresh then break end
        local rec = pendingReconcile
        pendingReconcile = nil
        local doRefresh = wantRefresh
        wantRefresh = false
        if rec and rec.gen == generation then
            local recOk, recErr = pcall(Reconcile, rec.copy, rec.height, rec.xy)
            if not recOk then
                LogOnce("reconcile_err", "Beam sync error: " .. tostring(recErr))
            end
        end
        if doRefresh then
            local refOk, refErr = pcall(RunRefresh)
            if not refOk then
                LogOnce("refresh_err", "Beam follow error: " .. tostring(refErr))
            end
        end
    end
end

local function ScheduleGameThread()
    local now = NowSeconds()
    if gameThreadQueued then
        -- A cutscene can drop the game-thread callback. Do not leave the queue latched.
        if now and gameThreadQueuedAt and (now - gameThreadQueuedAt) < 1.5 then
            return true
        end
        gameThreadQueued = false
    end
    if type(ExecuteInGameThread) ~= "function" then
        return false
    end
    gameThreadQueued = true
    gameThreadQueuedAt = now
    local ok, err = pcall(function()
        ExecuteInGameThread(function()
            local drainOk, drainErr = pcall(DrainGameThread)
            gameThreadQueued = false
            if not drainOk then
                LogOnce("game_thread", "Beam game-thread error: " .. tostring(drainErr))
            end
        end)
    end)
    if not ok then
        gameThreadQueued = false
        LogOnce("game_thread", "Beam game-thread error: " .. tostring(err))
        return false
    end
    return true
end

-- Same actor gate the pal label uses. Hidden and destroying actors produce no text,
-- so they must not keep a pillar either. This has to run on the game thread.
local function RendererSkipsActor(actor)
    if not IsValidObj(actor) then return false end
    local okD, resD = pcall(function() return actor:IsActorBeingDestroyed() end)
    if okD and resD then return true end
    local okH, resH = pcall(function()
        return actor.bHidden or (actor.IsHidden and actor:IsHidden())
    end)
    return okH and resH and true or false
end

local function GetNiagaraLib()
    if IsValidObj(niagaraLib) then return niagaraLib end
    local ok, obj = pcall(StaticFindObject, "/Script/Niagara.Default__NiagaraFunctionLibrary")
    obj = Unwrap(obj)
    if ok and IsValidObj(obj) then
        niagaraLib = obj
        return obj
    end
    LogOnce("no_lib", "Beam spawn failed: NiagaraFunctionLibrary was not found.")
    return nil
end

local function GetBeamAsset()
    if beamAsset then return beamAsset end
    local ok, asset = pcall(LoadAsset, BEAM_EFFECT_PATH)
    asset = Unwrap(asset)
    if ok and asset then
        beamAsset = asset
        return asset
    end
    LogOnce("no_asset", "Beam spawn failed: could not load " .. BEAM_EFFECT_PATH)
    return nil
end

local function GetWorld(actor)
    if IsValidObj(actor) then
        local ok, world = pcall(actor.GetWorld, actor)
        world = Unwrap(world)
        if ok and IsValidObj(world) then return world end
    end

    return utils.World(actor)
end

local function GetRoot(actor)
    if not IsValidObj(actor) then return nil end
    local ok, root = pcall(function() return actor.RootComponent end)
    if ok and IsValidObj(root) then return root end
    return nil
end

local function GetEngineLocation(actor, fallback)
    if IsValidObj(actor) then
        local ok, loc = pcall(actor.K2_GetActorLocation, actor)
        if ok and loc then return loc end
    end
    if fallback then
        return { X = fallback.X or 0.0, Y = fallback.Y or 0.0, Z = fallback.Z or 0.0 }
    end
    return nil
end

-- BeamHeight is UE units (cm). User.Scale 100 is a normal pillar.
local function HeightToNiagaraScale(heightUE)
    return math.max(1.0, (heightUE or 1500.0) / 15.0)
end

local function ThicknessToXYScale(thickness)
    return math.max(0.15, (thickness or 8.0) / 8.0)
end

-- Keys from the latest scan list. Refresh must not rebuild a pillar that list no longer has.
local allowedKeys = nil

local pendingDestroy = {}

local function CleanupComponent(comp)
    if not IsValidObj(comp) then return true end
    pcall(function() comp:SetHiddenInGame(true, true) end)
    pcall(function() comp:SetVisibility(false, true) end)
    pcall(function() comp:SetNiagaraVariableFloat(SCALE_PARAM, 0) end)
    pcall(function() comp:Deactivate() end)
    pcall(function() comp:SetAutoDestroy(true) end)
    return not IsValidObj(comp)
end

local function QueueDestroy(comp)
    if not comp then return end
    if CleanupComponent(comp) then return end
    pendingDestroy[#pendingDestroy + 1] = comp
end

local function FlushPendingDestroy()
    if #pendingDestroy == 0 then return end
    local still = {}
    for i = 1, #pendingDestroy do
        local comp = pendingDestroy[i]
        if not CleanupComponent(comp) then
            still[#still + 1] = comp
        end
    end
    pendingDestroy = still
end

local function ApplyColor(comp, color)
    if not IsValidObj(comp) or not color then return end
    pcall(function()
        comp:SetNiagaraVariableLinearColor(COLOR_PARAM, {
            R = color.R or 1.0,
            G = color.G or 1.0,
            B = color.B or 1.0,
            A = color.A or 1.0
        })
    end)
end

local function ApplyHeight(comp, heightScale)
    if not IsValidObj(comp) then return end
    pcall(function()
        comp:SetNiagaraVariableFloat(SCALE_PARAM, heightScale)
    end)
end

local function ApplyThickness(comp, xyScale)
    if not IsValidObj(comp) or not xyScale or math.abs(xyScale - 1.0) < 0.001 then return end
    pcall(function()
        comp:SetRelativeScale3D({ X = xyScale, Y = xyScale, Z = 1.0 })
    end)
end

local function MakeKey(category, item)
    local actor = item.Actor
    if IsValidObj(actor) then
        local ok, name = pcall(actor.GetFullName, actor)
        if ok and name and name ~= "" then
            return category .. ":" .. name
        end
    end
    if item.Name and category == "Players" then
        return category .. ":name:" .. tostring(item.Name)
    end
    local x = item.X or (item.Pos and item.Pos.X) or 0
    local y = item.Y or (item.Pos and item.Pos.Y) or 0
    local z = item.Z or (item.Pos and item.Pos.Z) or 0
    return string.format("%s:%.0f:%.0f:%.0f", category, x, y, z)
end

local MOVE_REFRESH_UU = 100.0
local MOVE_REFRESH_SQ = MOVE_REFRESH_UU * MOVE_REFRESH_UU

local function Coord(v)
    if type(v) == "number" then return v end
    local n = tonumber(v)
    if n then return n end
    return 0.0
end
local MAX_REFRESH_PER_TICK = 6

local function SpawnBeam(key, actor, fallbackLoc, color, heightScale, xyScale, mobile)
    if spawnedBeams[key] and IsValidObj(spawnedBeams[key].comp) then
        return true
    end

    local system, lib = GetBeamAsset(), GetNiagaraLib()
    if not system or not lib then return false end

    local location = GetEngineLocation(actor, fallbackLoc)
    if not location then return false end

    -- Static pillars attach to the actor, matching ScanEffigiesBLP.
    -- Moving actors do not: the Niagara pillar stays where it was spawned,
    -- so those are placed in the world and recreated after a real move.
    local root = (not mobile) and GetRoot(actor) or nil
    local comp = nil
    local attached = false

    if root then
        local ok, spawnedOrErr = pcall(function()
            return lib:SpawnSystemAttached(system, root, FName(""), { X = 0, Y = 0, Z = 0 }, { Pitch = 0, Yaw = 0, Roll = 0 }, 0, false, true, 0, true)
        end)
        if ok and IsValidObj(spawnedOrErr) then
            comp = spawnedOrErr
            attached = true
        elseif not ok then
            LogOnce("attach_err", "SpawnSystemAttached failed: " .. tostring(spawnedOrErr))
        end
    end

    if not comp then
        local world = GetWorld(actor)
        if not world then
            LogOnce("no_world", "Beam spawn failed: world is not available.")
            return false
        end
        local ok, spawnedOrErr = pcall(function()
            return lib:SpawnSystemAtLocation(world, system, location, { Pitch = 0, Yaw = 0, Roll = 0 }, { X = 1, Y = 1, Z = 1 }, false, true, 0, true)
        end)
        if ok and IsValidObj(spawnedOrErr) then
            comp = spawnedOrErr
            attached = false
        else
            LogOnce("spawn_err", "SpawnSystemAtLocation failed: " .. tostring(spawnedOrErr))
            return false
        end
    end

    ApplyColor(comp, color)
    ApplyHeight(comp, heightScale)
    ApplyThickness(comp, xyScale)
    spawnedBeams[key] = {
        comp = comp,
        attached = attached,
        mobile = mobile == true,
        actor = actor,
        category = nil,
        loc = { X = Coord(location.X), Y = Coord(location.Y), Z = Coord(location.Z) },
        colorR = color and color.R,
        colorG = color and color.G,
        colorB = color and color.B,
        heightScale = heightScale,
        xyScale = xyScale
    }
    LogOnce("spawned", "World-space beam pillar spawned.")
    return true
end

local function PalBeamBlocked(entry)
    if not entry or entry.category ~= "Pals" then return false end
    if RendererSkipsActor(entry.actor) then return true end
    return OwnedPalBeamBlocked(entry.actor)
end

Reconcile = function(desired, heightScale, xyScale)
    FlushPendingDestroy()
    local seen = {}
    local keep = {}
    for i = 1, #desired do
        local entry = desired[i]
        local key = entry.key
        if key and not PalBeamBlocked(entry) then
            seen[key] = true
            keep[#keep + 1] = entry
        end
    end
    allowedKeys = seen

    local toRemove = {}
    for key, _ in pairs(spawnedBeams) do
        if not seen[key] then toRemove[#toRemove + 1] = key end
    end
    for i = 1, #toRemove do
        local existing = spawnedBeams[toRemove[i]]
        if existing then QueueDestroy(existing.comp) end
        spawnedBeams[toRemove[i]] = nil
    end

    local spawnBudget = MAX_SPAWNS_PER_SYNC
    for i = 1, #keep do
        local entry = keep[i]
        local key = entry.key
        local color = entry.color or { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
        local existing = spawnedBeams[key]
        if existing and IsValidObj(existing.comp) then
            ApplyColor(existing.comp, color)
            ApplyHeight(existing.comp, heightScale)
            if existing.xyScale ~= xyScale then
                ApplyThickness(existing.comp, xyScale)
                existing.xyScale = xyScale
            end
            existing.heightScale = heightScale
            existing.colorR = color.R
            existing.colorG = color.G
            existing.colorB = color.B
            existing.category = entry.category
        else
            if existing then
                QueueDestroy(existing.comp)
                spawnedBeams[key] = nil
            end
            if spawnBudget > 0 and SpawnBeam(key, entry.actor, entry.loc, color, heightScale, xyScale, entry.mobile) then
                spawnedBeams[key].category = entry.category
                spawnBudget = spawnBudget - 1
            end
        end
    end
end

function M.DespawnAll()
    generation = generation + 1
    local snapshot = spawnedBeams
    spawnedBeams = {}
    pendingReconcile = nil
    wantRefresh = false
    local function DestroySnapshot()
        for _, entry in pairs(snapshot) do
            QueueDestroy(entry.comp)
        end
        FlushPendingDestroy()
    end
    if type(ExecuteInGameThread) == "function" then
        ExecuteInGameThread(DestroySnapshot)
    else
        DestroySnapshot()
    end
end

function M.Sync(desired)
    local CONFIG = configMod.CONFIG
    if not CONFIG or not CONFIG.Global or not CONFIG.Global.Enabled then
        allowedKeys = {}
        M.DespawnAll()
        return
    end

    local nextAllowed = {}
    for i = 1, #desired do
        local key = desired[i].key
        if key then nextAllowed[key] = true end
    end
    allowedKeys = nextAllowed

    generation = generation + 1
    local gen = generation
    local heightScale = HeightToNiagaraScale(CONFIG.Global and CONFIG.Global.BeamHeight)
    local xyScale = ThicknessToXYScale(CONFIG.Global and CONFIG.Global.BeamThickness)

    local copy = {}
    for i = 1, #desired do
        local entry = desired[i]
        local loc = entry.loc
        copy[i] = {
            key = entry.key,
            actor = entry.actor,
            color = entry.color,
            mobile = entry.mobile == true,
            category = entry.category,
            loc = loc and { X = loc.X, Y = loc.Y, Z = loc.Z } or nil
        }
    end

    pendingReconcile = { copy = copy, height = heightScale, xy = xyScale, gen = gen }
    if not ScheduleGameThread() then
        if gen == generation then
            local ok, err = pcall(Reconcile, copy, heightScale, xyScale)
            if not ok then
                LogOnce("reconcile_err", "Beam sync error: " .. tostring(err))
            end
        end
    end
end

function M.MakeKey(category, item)
    return MakeKey(category, item)
end

function M.Follow()
end

-- Recreate pillars whose actor has moved far enough that the old pillar is stale.
RunRefresh = function()
    FlushPendingDestroy()
    local budget = MAX_REFRESH_PER_TICK
    for key, entry in pairs(spawnedBeams) do
        local okEntry, errEntry = pcall(function()
            local actorGone = entry.mobile and not IsValidObj(entry.actor)
            local dropped = allowedKeys and not allowedKeys[key]
            local blocked = entry.category == "Pals" and (RendererSkipsActor(entry.actor) or OwnedPalBeamBlocked(entry.actor))
            if not IsValidObj(entry.comp) or dropped or blocked or actorGone then
                QueueDestroy(entry.comp)
                spawnedBeams[key] = nil
                return
            end
            if budget <= 0 then return end
            if not (entry.mobile and entry.loc) then return end
            local ok, loc = pcall(entry.actor.K2_GetActorLocation, entry.actor)
            if not ok or not loc then return end
            local dx = Coord(loc.X) - Coord(entry.loc.X)
            local dy = Coord(loc.Y) - Coord(entry.loc.Y)
            local dz = Coord(loc.Z) - Coord(entry.loc.Z)
            if dx * dx + dy * dy + dz * dz < MOVE_REFRESH_SQ then return end
            local color = {
                R = entry.colorR or 1.0,
                G = entry.colorG or 1.0,
                B = entry.colorB or 1.0,
                A = 1.0
            }
            local oldComp = entry.comp
            local category = entry.category
            -- Keep the old pillar visible until the replacement exists.
            spawnedBeams[key] = nil
            if SpawnBeam(key, entry.actor, loc, color, entry.heightScale, entry.xyScale, true) then
                spawnedBeams[key].category = category
                QueueDestroy(oldComp)
                budget = budget - 1
            else
                spawnedBeams[key] = entry
            end
        end)
        if not okEntry then
            LogOnce("refresh_entry", "Beam follow skipped one pillar: " .. tostring(errEntry))
        end
    end
end

function M.RefreshMobile()
    local CONFIG = configMod.CONFIG
    if not CONFIG or not CONFIG.Global or not CONFIG.Global.Enabled then return end
    wantRefresh = true
    if not ScheduleGameThread() then
        wantRefresh = false
        local ok, err = pcall(RunRefresh)
        if not ok then
            LogOnce("refresh_err", "Beam follow error: " .. tostring(err))
        end
    end
end

return M
