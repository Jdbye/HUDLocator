-- In-game region boundary editor.
-- Set Enabled to false for a public build. Alt+F6 then always opens settings.
local M = {}
M.Enabled = true
M.Active = false

local configMod = require("HUDLocator.config")
local utils = require("HUDLocator.utils")
local popup = require("HUDLocator.popup")
local json = require("HUDLocator.json")

local REGIONS = {
    { id = "grasslands", name = "Grasslands & Central Isles" },
    { id = "volcano", name = "Mount Obsidian" },
    { id = "desert", name = "Desiccated Desert" },
    { id = "snow", name = "Astral Mountains" },
    { id = "sakurajima", name = "Sakurajima" },
    { id = "feybreak", name = "Feybreak" },
    { id = "sunreach", name = "Sunreach" },
    { id = "xenolord", name = "Deserted Islet" },
    { id = "sanctuaries", name = "Wildlife Sanctuaries" },
    { id = "worldtree", name = "World Tree" },
    { id = "outer", name = "Outer Isles" },
    { id = "oilrigs", name = "Oil Rigs" },
}

local COLORS = {
    grasslands = { R = 0.30, G = 0.85, B = 0.35, A = 1 },
    volcano = { R = 0.95, G = 0.35, B = 0.15, A = 1 },
    desert = { R = 0.95, G = 0.80, B = 0.25, A = 1 },
    snow = { R = 0.55, G = 0.85, B = 1.00, A = 1 },
    sakurajima = { R = 1.00, G = 0.45, B = 0.70, A = 1 },
    feybreak = { R = 0.60, G = 0.40, B = 1.00, A = 1 },
    sunreach = { R = 0.30, G = 0.70, B = 1.00, A = 1 },
    xenolord = { R = 0.90, G = 0.20, B = 0.25, A = 1 },
    sanctuaries = { R = 0.20, G = 0.90, B = 0.70, A = 1 },
    worldtree = { R = 0.65, G = 0.45, B = 0.20, A = 1 },
    outer = { R = 0.95, G = 0.55, B = 0.15, A = 1 },
    oilrigs = { R = 0.55, G = 0.62, B = 0.68, A = 1 },
}
local DRAFT_COLOR = { R = 1, G = 1, B = 1, A = 1 }
local BANNER_COLOR = { R = 1, G = 0.95, B = 0.7, A = 1 }

local boundaries = {}
local shipped = {}
local draft = {}
local regionIndex = 5
local mapBase = nil
local loaded = false
local shippedLoaded = false
local lastClickAt = 0
local projectWarned = false
local RefreshMarkers
local AppendDraftVisual
local DropDraftTail
local PointInPoly
local PolyArea

local function ToolBoundsPath()
    return configMod.GetConfigDir() .. "/region_bounds.json"
end

-- The copy next to this script is the one region checks use. The mapping tool
-- never writes it. Edits go to the save-data copy only.
local function ScriptBoundsPath()
    local info = debug.getinfo(1, "S")
    if info and info.source and info.source:sub(1, 1) == "@" then
        local src = info.source:sub(2)
        local dir = src:match("^(.*)[/\\]boundary_tool%.lua$")
        if dir then
            local sep = string.find(src, "\\", 1, true) and "\\" or "/"
            return dir .. sep .. "region_bounds.json"
        end
    end
    return "Mods/HUDLocator/Scripts/HUDLocator/region_bounds.json"
end

local function ReadText(path)
    local raw = nil
    pcall(function()
        local handle = io.open(path, "r")
        if not handle then return end
        raw = handle:read("*a")
        handle:close()
    end)
    if type(raw) ~= "string" or raw == "" then return nil end
    return raw
end

local function ParseBounds(raw)
    local list = {}
    if type(raw) ~= "string" or raw == "" then return list end
    local data = json.parse(raw)
    local rows = data and data.boundaries
    if type(rows) ~= "table" then return list end
    for _, row in ipairs(rows) do
        if type(row) == "table" and type(row.name) == "string" and type(row.points) == "table" and #row.points >= 3 then
            local points = {}
            for _, pt in ipairs(row.points) do
                if type(pt) == "table" and type(pt.x) == "number" and type(pt.y) == "number" then
                    points[#points + 1] = { x = pt.x, y = pt.y }
                end
            end
            if #points >= 3 then
                list[#list + 1] = { name = row.name, points = points }
            end
        end
    end
    return list
end

-- Mapping tool: save-data file if the player has one, otherwise the shipped file.
function M.Load()
    boundaries = {}
    draft = {}
    local raw = ReadText(ToolBoundsPath())
    if not raw then raw = ReadText(ScriptBoundsPath()) end
    boundaries = ParseBounds(raw)
    loaded = true
end

local function LoadShipped()
    if shippedLoaded then return end
    shipped = ParseBounds(ReadText(ScriptBoundsPath()))
    shippedLoaded = true
end

local function EnsureLoaded()
    if not loaded then M.Load() end
end

function M.Save()
    local list = {}
    for _, row in ipairs(boundaries) do
        local points = {}
        for _, pt in ipairs(row.points) do
            points[#points + 1] = { x = pt.x, y = pt.y }
        end
        list[#list + 1] = { name = row.name, points = points }
    end
    pcall(function()
        local handle = io.open(ToolBoundsPath(), "w")
        if not handle then return end
        handle:write(json.stringify({ boundaries = list }))
        handle:close()
    end)
    loaded = true
end

function M.HasRegion(id)
    LoadShipped()
    for _, row in ipairs(shipped) do
        if row.name == id and #row.points >= 3 then return true end
    end
    return false
end

function M.RegionAt(x, y)
    LoadShipped()
    if not x or not y or #shipped == 0 then return nil end
    -- Oil Rigs win over every other boundary, including Outer Isles.
    -- Outer Isles then win over the biome polygons they overlap.
    local best, bestArea = nil, nil
    local inOil, inOuter = false, false
    for _, row in ipairs(shipped) do
        if #row.points >= 3 and PointInPoly(row.points, x, y) then
            if row.name == "oilrigs" then
                inOil = true
            elseif row.name == "outer" then
                inOuter = true
            else
                local area = PolyArea(row.points)
                if not bestArea or area < bestArea then
                    best = row.name
                    bestArea = area
                end
            end
        end
    end
    if inOil then return "oilrigs" end
    if inOuter then return "outer" end
    return best
end

local function SegmentDistance(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    if len2 <= 0 then
        local ex, ey = px - ax, py - ay
        return math.sqrt(ex * ex + ey * ey)
    end
    local t = ((px - ax) * dx + (py - ay) * dy) / len2
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local qx, qy = ax + t * dx, ay + t * dy
    local ex, ey = px - qx, py - qy
    return math.sqrt(ex * ex + ey * ey)
end

function M.NearestRegion(x, y)
    LoadShipped()
    if not x or not y or #shipped == 0 then return nil end
    local best, bestDist = nil, nil
    for _, row in ipairs(shipped) do
        if #row.points >= 3 then
            local dist = nil
            local count = #row.points
            for i = 1, count do
                local a = row.points[i]
                local b = row.points[i % count + 1]
                local d = SegmentDistance(x, y, a.x, a.y, b.x, b.y)
                if not dist or d < dist then dist = d end
            end
            if dist and (not bestDist or dist < bestDist) then
                best = row.name
                bestDist = dist
            end
        end
    end
    return best
end

local function RegionId()
    local row = REGIONS[regionIndex] or REGIONS[1]
    return row.id
end

local function RegionLabel(id)
    for _, row in ipairs(REGIONS) do
        if row.id == id then return row.name end
    end
    return id or ""
end

local function OutlinesFor(id)
    local count = 0
    for _, row in ipairs(boundaries) do
        if row.name == id then count = count + 1 end
    end
    return count
end

local function OutlineTitle(id, index)
    local name = RegionLabel(id)
    local total = OutlinesFor(id)
    if total > 1 and index then return string.format("%s #%d", name, index) end
    return name
end

local function ColorFor(id)
    return COLORS[id] or DRAFT_COLOR
end

local function XY(value)
    if value == nil then return nil end
    local x, y = nil, nil
    pcall(function()
        x = value.X
        y = value.Y
    end)
    if type(x) == "number" and type(y) == "number" then return x, y end
    return nil
end

local function FirstXY(results)
    if not results[1] then return nil end
    for i = 2, #results do
        local x, y = XY(results[i])
        if x then return x, y end
    end
    if type(results[2]) == "number" and type(results[3]) == "number" then
        return results[2], results[3]
    end
    if type(results[3]) == "number" and type(results[4]) == "number" then
        return results[3], results[4]
    end
    return nil
end

local function Shown(widget)
    if not widget or not widget.IsValid or not widget:IsValid() then return false end
    local code = ""
    pcall(function() code = tostring(widget:GetVisibility()) end)
    if code == "1" or code == "2" then return false end
    if string.find(code, "Collapsed", 1, true) or string.find(code, "Hidden", 1, true) then
        return false
    end
    local full = ""
    pcall(function() full = widget:GetFullName() or "" end)
    if string.find(full, "Default__", 1, true) then return false end
    return true
end

-- Palworld keeps the map widget alive after it closes, so GetVisibility stays
-- "visible". IsVisible() is false until the map is actually on screen.
local function MapOnScreen(widget)
    if not widget or not widget.IsValid or not widget:IsValid() then return false end
    local full = ""
    pcall(function() full = widget:GetFullName() or "" end)
    if string.find(full, "Default__", 1, true) then return false end
    local open = false
    pcall(function()
        if widget:IsVisible() == true then open = true end
    end)
    if not open then
        pcall(function()
            if widget:IsInViewport() == true then open = true end
        end)
    end
    return open
end

PointInPoly = function(points, x, y)
    local inside = false
    local j = #points
    for i = 1, #points do
        local xi, yi = points[i].x, points[i].y
        local xj, yj = points[j].x, points[j].y
        if (yi > y) ~= (yj > y) then
            local xint = (xj - xi) * (y - yi) / (yj - yi) + xi
            if x < xint then inside = not inside end
        end
        j = i
    end
    return inside
end

PolyArea = function(points)
    local area = 0
    for i = 1, #points do
        local j = i % #points + 1
        area = area + points[i].x * points[j].y - points[j].x * points[i].y
    end
    return math.abs(area) * 0.5
end

local function FindMap()
    local widgets = nil
    pcall(function() widgets = FindAllOf("WBP_Map_Base_C") end)
    if not widgets then return nil end
    for _, widget in ipairs(widgets) do
        if MapOnScreen(widget) then return widget end
    end
    return nil
end

local function MapBody()
    if mapBase and not MapOnScreen(mapBase) then
        mapBase = nil
    end
    if not mapBase or not mapBase.IsValid or not mapBase:IsValid() then
        mapBase = FindMap()
    end
    if not mapBase then return nil end
    local body = nil
    local out = {}
    pcall(function()
        local returned = mapBase:GetCurrentMapBody(out)
        body = returned or out.MapBody or out[1]
    end)
    if body and body.IsValid and body:IsValid() then return body end
    pcall(function() body = mapBase.WBP_Map_Body_MW5 end)
    if body and body.IsValid and body:IsValid() then return body end
    return nil
end

local function MapBounds(body)
    local minX, minY = XY(body.MinLandScapePosition)
    local maxX, maxY = XY(body.MaxLandScapePosition)
    if not minX or not maxX or maxX <= minX or maxY <= minY then
        minX, minY = XY(body.landScapeRealPositionMin)
        maxX, maxY = XY(body.landScapeRealPositionMax)
    end
    if not minX or not maxX or maxX <= minX or maxY <= minY then return nil end
    return minX, minY, maxX, maxY
end

local slateCached = nil
local function SlateLib()
    if slateCached and slateCached.IsValid and slateCached:IsValid() then return slateCached end
    local lib = nil
    pcall(function() lib = StaticFindObject("/Script/UMG.Default__SlateBlueprintLibrary") end)
    if lib and lib.IsValid and lib:IsValid() then
        slateCached = lib
        return lib
    end
    return nil
end

local function MapImage(body)
    local image = nil
    pcall(function() image = body.Image_MapBody end)
    if image and image.IsValid and image:IsValid() then return image end
    return body
end

-- Map texture axes match the game widget: horizontal is world Y, vertical is opposite world X.
local function WorldToLocal(x, y, minX, minY, maxX, maxY, sizeX, sizeY)
    local spanX = maxX - minX
    local spanY = maxY - minY
    if spanX == 0 or spanY == 0 or sizeX == 0 or sizeY == 0 then return nil end
    local u = (x - minX) / spanX
    local v = (y - minY) / spanY
    return v * sizeX, (1.0 - u) * sizeY
end

local function LocalToWorld(lx, ly, minX, minY, maxX, maxY, sizeX, sizeY)
    if sizeX == 0 or sizeY == 0 then return nil end
    local mapX = lx / sizeX
    local mapY = ly / sizeY
    local spanX = maxX - minX
    local spanY = maxY - minY
    local worldY = minY + mapX * spanY
    local worldX = maxX - mapY * spanX
    return worldX, worldY
end

local function ScreenFromWorld(body, x, y)
    local minX, minY, maxX, maxY = MapBounds(body)
    if not minX then return nil end
    local image = MapImage(body)
    local slate = SlateLib()
    local world = utils.World(image)
    if not slate or not world or not image then return nil end
    local geo = nil
    pcall(function() geo = image:GetCachedGeometry() end)
    if not geo then return nil end
    local sizeX, sizeY = FirstXY({ pcall(function() return slate:GetLocalSize(geo) end) })
    if not sizeX then return nil end
    local lx, ly = WorldToLocal(x, y, minX, minY, maxX, maxY, sizeX, sizeY)
    if not lx then return nil end
    local results = { pcall(function() return slate:LocalToViewport(world, geo, { X = lx, Y = ly }) end) }
    if not results[1] then return nil end
    local vx, vy = nil, nil
    local found = 0
    for i = 2, #results do
        local px, py = XY(results[i])
        if px then
            found = found + 1
            vx, vy = px, py
        end
    end
    if found == 0 then return nil end
    return vx, vy
end

local function UsableCursor(x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    if x ~= x or y ~= y then return false end
    if math.abs(x) > 5000000 or math.abs(y) > 5000000 then return false end
    if x == 0 and y == 0 then return false end
    return true
end

local function InMapBounds(body, x, y)
    local minX, minY, maxX, maxY = MapBounds(body)
    if not minX then return true end
    local pad = 200000
    return x >= minX - pad and x <= maxX + pad and y >= minY - pad and y <= maxY + pad
end

-- The map label is sometimes metres. Keep whichever scale lands on the world map.
local function ScaleCursor(body, x, y)
    if InMapBounds(body, x, y) then return x, y end
    if InMapBounds(body, x * 100, y * 100) then return x * 100, y * 100 end
    return nil
end

local function TextString(value)
    if type(value) == "string" then return value end
    local text = nil
    pcall(function()
        local lib = StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
        if lib then text = lib:Conv_TextToString(value) end
    end)
    if type(text) == "string" and text ~= "" then return text end
    pcall(function()
        if value and value.ToString then text = value:ToString() end
    end)
    if type(text) == "string" then return text end
    return nil
end

-- Same numbers the map draws in the corner. GetCursorWorldLocation only
-- fills its output parameter, so a bare call never returns the position.
local function CursorFromGame(body)
    local out = {}
    local results = { pcall(function() return body:GetCursorWorldLocation(out) end) }
    local x, y = XY(out)
    if UsableCursor(x, y) then return x, y end
    x, y = FirstXY(results)
    if UsableCursor(x, y) then return x, y end
    for i = 2, #results do
        x, y = XY(results[i])
        if UsableCursor(x, y) then return x, y end
    end
    local block = nil
    pcall(function() block = mapBase and mapBase.Text_CursorLocation end)
    if not block then return nil end
    local raw = nil
    pcall(function() raw = block:GetText() end)
    local label = TextString(raw)
    if type(label) ~= "string" then return nil end
    local nums = {}
    for token in string.gmatch(label, "[-+]?%d+%.?%d*") do
        nums[#nums + 1] = tonumber(token)
    end
    if #nums < 2 then return nil end
    return ScaleCursor(body, nums[1], nums[2])
end

local function CursorWorld(body)
    local x, y = CursorFromGame(body)
    if UsableCursor(x, y) then return x, y end
    local slate = SlateLib()
    local world = utils.World()
    local pc = utils.PlayerController()
    if not slate or not world or not pc then return nil end
    local mx, my = FirstXY({ pcall(function() return pc:GetMousePosition() end) })
    if not mx then return nil end
    local image = MapImage(body)
    local geo = nil
    pcall(function() geo = image:GetCachedGeometry() end)
    if not geo then return nil end
    local lx, ly = FirstXY({ pcall(function()
        return slate:ScreenToWidgetLocal(world, geo, { X = mx, Y = my }, false)
    end) })
    if not lx then return nil end
    local minX, minY, maxX, maxY = MapBounds(body)
    if not minX then return nil end
    local sizeX, sizeY = FirstXY({ pcall(function() return slate:GetLocalSize(geo) end) })
    if not sizeX then return nil end
    return LocalToWorld(lx, ly, minX, minY, maxX, maxY, sizeX, sizeY)
end

local function Notify(text)
    popup.Show(text, 120)
end

local function FinishDraft()
    if #draft < 3 then return false end
    local id = RegionId()
    boundaries[#boundaries + 1] = { name = id, points = draft }
    draft = {}
    Notify(string.format("%s outline %d saved", RegionLabel(id), OutlinesFor(id)))
    return true
end

local function DeleteAt(x, y)
    local best, bestArea = nil, nil
    for i, row in ipairs(boundaries) do
        if PointInPoly(row.points, x, y) then
            local area = PolyArea(row.points)
            if not bestArea or area < bestArea then
                best = i
                bestArea = area
            end
        end
    end
    if not best then return false end
    local removed = boundaries[best]
    local ordinal = 0
    for i = 1, best do
        if boundaries[i].name == removed.name then ordinal = ordinal + 1 end
    end
    local total = OutlinesFor(removed.name)
    table.remove(boundaries, best)
    local title = RegionLabel(removed.name)
    if total > 1 then title = string.format("%s #%d", title, ordinal) end
    Notify(title .. " removed")
    RefreshMarkers()
    return true
end

local ReleaseOverlay

function M.TryToggle()
    if not M.Enabled then return false end
    if M.Active then
        FinishDraft()
        M.Save()
        M.Active = false
        ReleaseOverlay()
        mapBase = nil
        Notify("Region boundaries saved")
        return true
    end
    local base = FindMap()
    if not base then return false end
    mapBase = base
    M.Load()
    M.Active = true
    Notify("Boundary tool on\nInsert: point   Del: undo   End: close\nHome: clear   Alt+F6: save")
    RefreshMarkers()
    return true
end

function M.AddPoint()
    if not M.Enabled or not M.Active then return end
    local now = os.clock()
    if now - lastClickAt < 0.25 then return end
    local body = MapBody()
    if not body then return end
    local x, y = CursorWorld(body)
    if not x or math.abs(x) > 5000000 or math.abs(y) > 5000000 then
        Notify("Move the cursor onto the map, then press Insert")
        return
    end
    local last = draft[#draft]
    if last then
        local dx, dy = x - last.x, y - last.y
        if dx * dx + dy * dy < 500 * 500 then return end
    end
    lastClickAt = now
    draft[#draft + 1] = { x = x, y = y }
    Notify(string.format("%s point %d added", RegionLabel(RegionId()), #draft))
    AppendDraftVisual()
end

function M.DeleteLastPoint()
    if not M.Enabled or not M.Active then return end
    if #draft == 0 then
        Notify("No point to remove")
        return
    end
    DropDraftTail(#draft > 1)
    table.remove(draft)
    Notify(string.format("%s point removed (%d left)", RegionLabel(RegionId()), #draft))
end

function M.DeleteHovered()
    if not M.Enabled or not M.Active then return end
    local now = os.clock()
    if now - lastClickAt < 0.25 then return end
    lastClickAt = now
    local body = MapBody()
    if not body then return end
    local x, y = CursorWorld(body)
    if not x then
        Notify("Move the cursor onto the map first")
        return
    end
    DeleteAt(x, y)
end

function M.CycleRegion(step)
    if not M.Enabled or not M.Active then return end
    regionIndex = regionIndex + step
    if regionIndex < 1 then regionIndex = #REGIONS end
    if regionIndex > #REGIONS then regionIndex = 1 end
    RefreshMarkers()
end

function M.Finish()
    if not M.Enabled or not M.Active then return end
    if not FinishDraft() then
        Notify("Add at least 3 points before closing the outline")
    end
    RefreshMarkers()
end

local confirmBoundary = nil
local confirmUntil = 0

function M.ClearDraft()
    if not M.Enabled or not M.Active then return end
    if #draft > 0 then
        draft = {}
        confirmBoundary = nil
        confirmUntil = 0
        Notify("Unfinished points cleared")
        RefreshMarkers()
        return
    end
    local body = MapBody()
    local x, y = nil, nil
    if body then x, y = CursorWorld(body) end
    if not x then
        confirmBoundary = nil
        confirmUntil = 0
        Notify("Move the cursor onto a boundary, then press Home")
        return
    end
    local best, bestArea = nil, nil
    for _, row in ipairs(boundaries) do
        if #row.points >= 3 and PointInPoly(row.points, x, y) then
            local area = PolyArea(row.points)
            if not bestArea or area < bestArea then
                best = row
                bestArea = area
            end
        end
    end
    if not best then
        confirmBoundary = nil
        confirmUntil = 0
        Notify("No boundary under the cursor")
        return
    end
    local now = os.clock()
    if confirmBoundary == best and now <= confirmUntil then
        confirmBoundary = nil
        confirmUntil = 0
        DeleteAt(x, y)
        return
    end
    confirmBoundary = best
    confirmUntil = now + 2.0
    Notify("Tap Home again to delete boundary")
end

local overlay = { texts = {}, lines = {}, captions = {}, root = nil, canvas = nil, usedText = 0, usedLine = 0 }
local whiteTex = nil

local function WidgetAlive(widget)
    return widget and widget.IsValid and widget:IsValid()
end

local function DropWidget(widget)
    if not WidgetAlive(widget) then return end
    pcall(function() widget:RemoveFromParent() end)
end

local marks = {}
local mapWasOpen = false
local showTries = 0
local lastSpan = nil
local lastView = nil
local spanMoving = false
local spanHold = 0

local function ClearPlaced()
    for i = 1, #marks do
        local mark = marks[i]
        if mark then
            DropWidget(mark.image)
            DropWidget(mark.text)
        end
        marks[i] = nil
    end
end

ReleaseOverlay = function()
    ClearPlaced()
    DropWidget(overlay.root)
    overlay = { texts = {}, lines = {}, captions = {}, root = nil, canvas = nil, usedText = 0, usedLine = 0 }
end

local classCache = {}

local function Construct(classPath, outer)
    local class = classCache[classPath]
    if not class or not class.IsValid or not class:IsValid() then
        class = nil
        pcall(function() class = StaticFindObject(classPath) end)
        classCache[classPath] = class
    end
    if not class or not class.IsValid or not class:IsValid() then return nil end
    local widget = nil
    pcall(function() widget = StaticConstructObject(class, outer) end)
    if not WidgetAlive(widget) then return nil end
    return widget
end

local function WhiteTexture()
    if WidgetAlive(whiteTex) then return whiteTex end
    pcall(function()
        whiteTex = StaticFindObject("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture")
    end)
    return whiteTex
end

local function HideWidget(widget)
    if not WidgetAlive(widget) then return end
    pcall(function() widget:SetVisibility(1) end)
end

local function ShowWidget(widget)
    if not WidgetAlive(widget) then return end
    pcall(function() widget:SetVisibility(4) end)
end

local function SlotOf(parent, widget)
    if not WidgetAlive(parent) or not WidgetAlive(widget) then return nil end
    local slot = nil
    pcall(function() slot = parent:AddChildToCanvas(widget) end)
    if not slot then
        pcall(function() slot = parent:AddChild(widget) end)
    end
    return slot
end

local function PinSlot(slot, z)
    if not slot then return end
    pcall(function() slot:SetMinimum({ X = 0.0, Y = 0.0 }) end)
    pcall(function() slot:SetMaximum({ X = 0.0, Y = 0.0 }) end)
    pcall(function() slot:SetAlignment({ X = 0.5, Y = 0.5 }) end)
    pcall(function() slot:SetZOrder(z or 20) end)
end

local function MoveSlot(slot, x, y, w, h)
    if not slot then return end
    pcall(function() slot:SetPosition({ X = x, Y = y }) end)
    if w then
        pcall(function() slot:SetAutoSize(false) end)
        pcall(function() slot:SetSize({ X = w, Y = h }) end)
    else
        pcall(function() slot:SetAutoSize(true) end)
    end
end

local function EnsureBanner(parent)
    if WidgetAlive(overlay.banner) then return overlay.banner end
    local text = Construct("/Script/UMG.TextBlock", parent)
    if not text then return nil end
    local slot = SlotOf(parent, text)
    PinSlot(slot, 30)
    MoveSlot(slot, 24, 28, 1600, 36)
    pcall(function() text.Font.Size = 28 end)
    pcall(function()
        text:SetColorAndOpacity({ SpecifiedColor = BANNER_COLOR, ColorUseRule = 0 })
    end)
    overlay.banner = text
    return text
end

local function NextText(parent)
    overlay.usedText = overlay.usedText + 1
    local text = overlay.texts[overlay.usedText]
    if not WidgetAlive(text) then
        text = Construct("/Script/UMG.TextBlock", parent)
        if not text then return nil end
        local slot = SlotOf(parent, text)
        PinSlot(slot, overlay.z or 20)
        pcall(function() text.Font.Size = 16 end)
        overlay.texts[overlay.usedText] = text
    end
    ShowWidget(text)
    return text
end

local function NextLine(parent)
    overlay.usedLine = overlay.usedLine + 1
    local image = overlay.lines[overlay.usedLine]
    if not WidgetAlive(image) then
        image = Construct("/Script/UMG.Image", parent)
        if not image then return nil end
        local slot = SlotOf(parent, image)
        PinSlot(slot, overlay.z or 20)
        local tex = WhiteTexture()
        if tex then pcall(function() image:SetBrushFromTexture(tex, false) end) end
        pcall(function() image:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
        overlay.lines[overlay.usedLine] = image
    end
    ShowWidget(image)
    return image
end

local function HideUnused()
    for i = overlay.usedText + 1, #overlay.texts do HideWidget(overlay.texts[i]) end
    for i = overlay.usedLine + 1, #overlay.lines do HideWidget(overlay.lines[i]) end
end

local function ImageFrame(body)
    local image = MapImage(body)
    local px, py, sx, sy = 0, 0, nil, nil
    pcall(function()
        local slot = image.Slot
        px, py = XY(slot:GetPosition())
        sx, sy = XY(slot:GetSize())
    end)
    if not px then px, py = 0, 0 end
    if not sx or sx < 10 or sy < 10 then
        local slate = SlateLib()
        local geo = nil
        pcall(function() geo = image:GetCachedGeometry() end)
        if slate and geo then
            sx, sy = FirstXY({ pcall(function() return slate:GetLocalSize(geo) end) })
        end
    end
    if not sx or sx < 10 or sy < 10 then return nil end
    return px, py, sx, sy
end

local frame = nil

-- Markers live on our own viewport widget. Updating widgets inside the world
-- map forces the whole map to rebuild, which is why each point cost frames
-- and still never appeared above the map image.
local function EnsureScreenLayer()
    if WidgetAlive(overlay.root) and WidgetAlive(overlay.canvas) then return overlay.canvas end
    local pc = utils.PlayerController()
    if not WidgetAlive(pc) then return nil end
    local library, widgetClass, world = nil, nil, nil
    pcall(function() library = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end)
    pcall(function() widgetClass = StaticFindObject("/Script/UMG.UserWidget") end)
    pcall(function() world = pc:GetWorld() end)
    if not WidgetAlive(library) or not WidgetAlive(widgetClass) or not WidgetAlive(world) then return nil end
    local widget = nil
    pcall(function() widget = library:Create(world, widgetClass, pc) end)
    if not WidgetAlive(widget) then return nil end
    local tree = nil
    pcall(function() tree = widget.WidgetTree end)
    local canvas = Construct("/Script/UMG.CanvasPanel", widget)
    if not WidgetAlive(tree) or not canvas then return nil end
    pcall(function() tree.RootWidget = canvas end)
    pcall(function() widget.bIsFocusable = false end)
    pcall(function() widget:SetVisibility(4) end)
    pcall(function() widget:AddToViewport(90000) end)
    overlay.root = widget
    overlay.canvas = canvas
    return canvas
end

local function BeginFrame(body)
    local image = MapImage(body)
    local slate = SlateLib()
    local world = utils.World(image)
    local geo = nil
    pcall(function() geo = image and image:GetCachedGeometry() end)
    local sizeX, sizeY = nil, nil
    if slate and geo then
        sizeX, sizeY = FirstXY({ pcall(function() return slate:GetLocalSize(geo) end) })
    end
    local minX, minY, maxX, maxY = MapBounds(body)
    frame = {
        slate = slate, world = world, geo = geo,
        sizeX = sizeX, sizeY = sizeY,
        minX = minX, minY = minY, maxX = maxX, maxY = maxY,
    }
end

local function ScreenPoint(x, y)
    if not frame or not frame.geo or not frame.slate or not frame.world then return nil end
    if not frame.sizeX or not frame.minX then return nil end
    local lx, ly = WorldToLocal(x, y, frame.minX, frame.minY, frame.maxX, frame.maxY, frame.sizeX, frame.sizeY)
    if not lx then return nil end
    local results = { pcall(function()
        return frame.slate:LocalToViewport(frame.world, frame.geo, { X = lx, Y = ly })
    end) }
    if not results[1] then return nil end
    local vx, vy, found = nil, nil, 0
    for i = 2, #results do
        local px, py = XY(results[i])
        if px then
            found = found + 1
            vx, vy = px, py
        end
    end
    if found == 0 then return nil end
    return vx, vy
end

local function PaintLine(ax, ay, bx, by, color)
    local x1, y1 = ScreenPoint(ax, ay)
    local x2, y2 = ScreenPoint(bx, by)
    if not x1 or not x2 then return false end
    local image = NextLine(overlay.canvas)
    if not image then return false end
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return true end
    local angle = math.deg(math.atan2(dy, dx))
    local mx, my = (x1 + x2) * 0.5, (y1 + y2) * 0.5
    if image._mx ~= mx or image._my ~= my or image._len ~= len or image._ang ~= angle then
        image._mx, image._my, image._len, image._ang = mx, my, len, angle
        local slot = nil
        pcall(function() slot = image.Slot end)
        MoveSlot(slot, mx, my, len, 3)
        pcall(function() image:SetRenderTransformAngle(angle) end)
    end
    if image._color ~= color then
        image._color = color
        pcall(function() image:SetColorAndOpacity(color) end)
    end
    return true
end

local function PaintLabel(pt, id, shown)
    local x, y = ScreenPoint(pt.x, pt.y)
    if not x then return false end
    local text = NextText(overlay.canvas)
    if not text then return false end
    if text._px ~= x or text._py ~= y then
        text._px, text._py = x, y
        local slot = nil
        pcall(function() slot = text.Slot end)
        MoveSlot(slot, x + 8, y - 14, nil, nil)
    end
    local index = overlay.usedText
    local caption = string.format("%s  %.0f, %.0f", shown, pt.x, pt.y)
    if overlay.captions[index] ~= caption then
        overlay.captions[index] = caption
        pcall(function() text:SetText(FText(caption)) end)
        pcall(function()
            text:SetColorAndOpacity({ SpecifiedColor = ColorFor(id), ColorUseRule = 0 })
        end)
    end
    return true
end

local function DrawSegment(hud, body, ax, ay, bx, by, color)
    local x1, y1 = ScreenFromWorld(body, ax, ay)
    local x2, y2 = ScreenFromWorld(body, bx, by)
    if not x1 or not x2 then return end
    pcall(function() hud:DrawLine(x1, y1, x2, y2, color, 2.0) end)
end

local refreshGen = 0

local function IconCanvas(body)
    local canvas = nil
    pcall(function() canvas = body.Canvas_ForIcon_NoMask end)
    if WidgetAlive(canvas) then return canvas end
    pcall(function() canvas = body.Canvas_ForIcon_Priority end)
    if WidgetAlive(canvas) then return canvas end
    local image = MapImage(body)
    local parent = nil
    if WidgetAlive(image) then
        pcall(function() parent = image:GetParent() end)
    end
    if WidgetAlive(parent) then return parent end
    return nil
end

local function AsNumber(value)
    if type(value) == "number" then return value end
    if type(value) == "userdata" then
        local n = nil
        pcall(function() n = value:get() end)
        if type(n) == "number" then return n end
    end
    return nil
end

-- ScalingSize is the map canvas in its current zoom. CachedMapScale often stays
-- at 1, so the live zoom is the step counter: ZoomFactor ^ (step - default).
local function MapZoom(body)
    local step, origin, factor = nil, nil, nil
    pcall(function()
        step = body.CurrentZoomStep
        origin = body.DefaultMapZoomStep
        factor = body.ZoomFactor
    end)
    step = AsNumber(step)
    origin = AsNumber(origin) or 0
    factor = AsNumber(factor)
    if step and factor and factor > 1.01 then
        return factor ^ (step - origin)
    end
    local scale = nil
    pcall(function() scale = body.CachedMapScale end)
    scale = AsNumber(scale)
    if scale and scale > 0.05 then return scale end
    local results = { pcall(function() return body:GetMapScale({}) end) }
    if results[1] then
        for i = 2, #results do
            local n = AsNumber(results[i])
            if n and n > 0.05 then return n end
        end
    end
    return 1
end

local function WidgetScaleX(widget)
    if not WidgetAlive(widget) then return nil end
    local x = nil
    pcall(function() x = widget.RenderTransform.Scale.X end)
    x = AsNumber(x)
    if x and x > 0.05 then return x end
    return nil
end

-- Past the min and max zoom step the game still changes the map's drawn scale.
local function ViewScale(body, canvas)
    local image = MapImage(body)
    local parent = nil
    if WidgetAlive(image) then
        pcall(function() parent = image:GetParent() end)
    end
    local scale = WidgetScaleX(image) or WidgetScaleX(parent) or WidgetScaleX(canvas)
    if scale then return scale end
    local cached = nil
    pcall(function() cached = body.CachedMapScale end)
    cached = AsNumber(cached)
    if cached and cached > 0.05 then return cached end
    return nil
end

local function RawCanvasSize(body)
    local out = {}
    local results = { pcall(function() return body:GetMapCanvasScalingSize(out) end) }
    local sizeX, sizeY = XY(out)
    if not sizeX then sizeX, sizeY = FirstXY(results) end
    if not sizeX or sizeX < 10 or not sizeY or sizeY < 10 then
        local image = MapImage(body)
        local slate = SlateLib()
        if slate and WidgetAlive(image) then
            local geo = nil
            pcall(function() geo = image:GetCachedGeometry() end)
            if geo then
                sizeX, sizeY = FirstXY({ pcall(function() return slate:GetLocalSize(geo) end) })
            end
        end
    end
    if not sizeX or sizeX < 10 or not sizeY or sizeY < 10 then return nil end
    return sizeX, sizeY
end

local function MapImageSize(body)
    local sizeX, sizeY = RawCanvasSize(body)
    if not sizeX then return nil end
    local zoom = MapZoom(body)
    if zoom > 0.05 then
        sizeX, sizeY = sizeX / zoom, sizeY / zoom
    end
    return sizeX, sizeY
end

-- The icon canvas multiplies a new widget by the zoom it was created at, then
-- keeps that widget in step with later zooms. Divide the creation zoom back out
-- so a marker made while zoomed in is the same size as one made at 1.0x.
local function CreationScale(body)
    local zoom = MapZoom(body)
    if not zoom or zoom < 0.05 then return 1 end
    return 1 / zoom
end

local function ApplyFont(text, size)
    if not WidgetAlive(text) then return end
    pcall(function()
        local font = text.Font
        font.Size = size
        text:SetFont(font)
    end)
end

-- Slot positions match the map image's layout size. The icon layer already
-- moves with the map, so the current pan offset is not added on top.
local function PointLocal(canvas, body, worldX, worldY)
    local minX, minY, maxX, maxY = MapBounds(body)
    local sizeX, sizeY = MapImageSize(body)
    if not minX or not sizeX then return nil end
    return WorldToLocal(worldX, worldY, minX, minY, maxX, maxY, sizeX, sizeY)
end

local function LayoutPoint(mark, canvas, body)
    local x, y = PointLocal(canvas, body, mark.x, mark.y)
    if not x then return false end
    local scale = CreationScale(body)
    if WidgetAlive(mark.image) then
        MoveSlot(mark.image.Slot, x, y, 12, 12)
        pcall(function() mark.image:SetRenderScale({ X = scale, Y = scale }) end)
    end
    if WidgetAlive(mark.text) then
        MoveSlot(mark.text.Slot, x + 10, y - 8, nil, nil)
        ApplyFont(mark.text, 12)
        pcall(function() mark.text:SetRenderScale({ X = scale, Y = scale }) end)
    end
    return true
end

local function LayoutLine(mark, canvas, body)
    local x1, y1 = PointLocal(canvas, body, mark.x1, mark.y1)
    local x2, y2 = PointLocal(canvas, body, mark.x2, mark.y2)
    if not x1 or not x2 or not WidgetAlive(mark.image) then return false end
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 2 then return false end
    MoveSlot(mark.image.Slot, (x1 + x2) * 0.5, (y1 + y2) * 0.5, len, 2)
    pcall(function() mark.image:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
    pcall(function() mark.image:SetRenderTransformAngle(math.deg(math.atan(dy, dx))) end)
    pcall(function() mark.image:SetRenderScale({ X = 1, Y = CreationScale(body) }) end)
    return true
end

-- Same line placement a full boundary refresh uses. Point positions stay as they are.
local function RedrawLines(canvas, body)
    for _, mark in ipairs(marks) do
        if mark and mark.kind == "line" then
            LayoutLine(mark, canvas, body)
        end
    end
end

local function MakeDot(canvas, x, y, color, caption)
    local image = Construct("/Script/UMG.Image", canvas)
    if not image then return nil end
    PinSlot(SlotOf(canvas, image), 400)
    pcall(function() image:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
    local tex = WhiteTexture()
    if tex then pcall(function() image:SetBrushFromTexture(tex, false) end) end
    pcall(function() image:SetColorAndOpacity(color) end)
    pcall(function() image:SetVisibility(4) end)
    local text = Construct("/Script/UMG.TextBlock", canvas)
    if text then
        PinSlot(SlotOf(canvas, text), 410)
        pcall(function() text:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
        ApplyFont(text, 12)
        pcall(function() text:SetText(FText(caption)) end)
        pcall(function()
            text:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
        end)
        pcall(function() text:SetVisibility(4) end)
    end
    local mark = { kind = "point", image = image, text = text, x = x, y = y, draft = false }
    marks[#marks + 1] = mark
    return mark
end

local function MakeLine(canvas, x1, y1, x2, y2, color)
    local image = Construct("/Script/UMG.Image", canvas)
    if not image then return nil end
    PinSlot(SlotOf(canvas, image), 390)
    local tex = WhiteTexture()
    if tex then pcall(function() image:SetBrushFromTexture(tex, false) end) end
    pcall(function() image:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
    pcall(function() image:SetColorAndOpacity(color) end)
    pcall(function() image:SetVisibility(4) end)
    local mark = { kind = "line", image = image, x1 = x1, y1 = y1, x2 = x2, y2 = y2, draft = false }
    marks[#marks + 1] = mark
    return mark
end

local function AddOutline(canvas, body, points, color, caption, closed)
    local placedAny = false
    local dots = {}
    for _, pt in ipairs(points) do
        local shown = string.format("%s  %.0f, %.0f", caption, pt.x, pt.y)
        local mark = MakeDot(canvas, pt.x, pt.y, color, shown)
        dots[#dots + 1] = mark
        if mark and LayoutPoint(mark, canvas, body) then placedAny = true end
    end
    local count = #points
    local last = (closed and count >= 3) and count or (count - 1)
    for i = 1, last do
        local a = points[i]
        local b = points[i % count + 1]
        local mark = MakeLine(canvas, a.x, a.y, b.x, b.y, color)
        if mark then
            mark.a = dots[i]
            mark.b = dots[i % count + 1]
            if LayoutLine(mark, canvas, body) then placedAny = true end
        end
    end
    return placedAny
end

AppendDraftVisual = function()
    local function run()
        local body = MapBody()
        local canvas = body and IconCanvas(body) or nil
        if not WidgetAlive(canvas) or #draft == 0 then return end
        local pt = draft[#draft]
        local prev = draft[#draft - 1]
        local label = RegionLabel(RegionId())
        local shown = string.format("%s  %.0f, %.0f", label, pt.x, pt.y)
        local mark = MakeDot(canvas, pt.x, pt.y, DRAFT_COLOR, shown)
        if mark then
            mark.draft = true
            LayoutPoint(mark, canvas, body)
        end
        if prev then
            local prevMark = nil
            for i = #marks, 1, -1 do
                local older = marks[i]
                if older and older ~= mark and older.draft and older.kind == "point" then
                    prevMark = older
                    break
                end
            end
            local line = MakeLine(canvas, prev.x, prev.y, pt.x, pt.y, DRAFT_COLOR)
            if line then
                line.draft = true
                line.a = prevMark
                line.b = mark
                LayoutLine(line, canvas, body)
            end
        end
    end
    if ExecuteInGameThread then
        ExecuteInGameThread(run)
    else
        run()
    end
end

DropDraftTail = function(removeLine)
    local function run()
        if removeLine then
            for i = #marks, 1, -1 do
                local mark = marks[i]
                if mark and mark.draft and mark.kind == "line" then
                    DropWidget(mark.image)
                    table.remove(marks, i)
                    break
                end
            end
        end
        for i = #marks, 1, -1 do
            local mark = marks[i]
            if mark and mark.draft and mark.kind == "point" then
                DropWidget(mark.image)
                DropWidget(mark.text)
                table.remove(marks, i)
                break
            end
        end
    end
    if ExecuteInGameThread then
        ExecuteInGameThread(run)
    else
        run()
    end
end

local function RefreshNow()
    ClearPlaced()
    if not M.Enabled or not M.Active then return end
    local body = MapBody()
    local canvas = body and IconCanvas(body) or nil
    if not WidgetAlive(canvas) then return end
    local placedAny = false
    for index, row in ipairs(boundaries) do
        local ordinal = 0
        for i = 1, index do
            if boundaries[i].name == row.name then ordinal = ordinal + 1 end
        end
        if AddOutline(canvas, body, row.points, ColorFor(row.name), OutlineTitle(row.name, ordinal), true) then
            placedAny = true
        end
    end
    if #draft > 0 and AddOutline(canvas, body, draft, DRAFT_COLOR, RegionLabel(RegionId()), false) then
        placedAny = true
    end
    if not placedAny and (#boundaries > 0 or #draft > 0) and not projectWarned then
        projectWarned = true
        Notify("Boundary points could not be placed on the map")
    end
end

RefreshMarkers = function()
    refreshGen = refreshGen + 1
    local gen = refreshGen
    local function run()
        if gen ~= refreshGen then return end
        local ok, err = pcall(RefreshNow)
        if not ok then
            Notify("Boundary points could not be placed on the map")
            print("[HUDLocator] Boundary markers: " .. tostring(err) .. "\n")
        end
    end
    if ExecuteInGameThread then
        ExecuteInGameThread(run)
    else
        run()
    end
end

function M.Draw(hud)
    if not M.Enabled or not M.Active or not hud then return end
    local label = RegionLabel(RegionId())
    local banner = string.format(
        "Boundary tool  |  %s (%d saved)  |  Insert: add point (%d)  |  Del: undo point  |  End: close outline  |  Home: clear / delete  |  PgUp/PgDn: region  |  Alt+F6: save",
        label, OutlinesFor(RegionId()), #draft)
    utils.DrawText(hud, banner, BANNER_COLOR, 24, 16, 1.35, false)
    local body = MapBody()
    if not body then
        mapWasOpen = false
        showTries = 0
        return
    end
    EnsureLoaded()
    local savedAlive = false
    for _, mark in ipairs(marks) do
        if mark and not mark.draft and WidgetAlive(mark.image) then
            savedAlive = true
            break
        end
    end
    if (not mapWasOpen or (#boundaries > 0 and not savedAlive)) and showTries < 8 then
        mapWasOpen = true
        showTries = showTries + 1
        if showTries == 1 or showTries == 4 or showTries == 8 then
            RefreshMarkers()
        end
        return
    end
    local canvas = IconCanvas(body)
    if not WidgetAlive(canvas) then return end
    local span = RawCanvasSize(body)
    if not span then return end
    local view = ViewScale(body, canvas)
    local spanChanged = not lastSpan or math.abs(span - lastSpan) / lastSpan > 0.02
    local viewChanged = view and (not lastView or math.abs(view - lastView) > 0.02)
    if spanChanged or viewChanged then
        lastSpan = span
        if view then lastView = view end
        spanHold = 0
        spanMoving = true
        return
    end
    if spanMoving then
        spanHold = spanHold + 1
        if spanHold >= 8 then
            RedrawLines(canvas, body)
            spanMoving = false
        end
    end
end

local function ScrollListOr(dir, toolFn)
    if M.Enabled and M.Active then
        toolFn()
        return
    end
    local menu = package.loaded["HUDLocator.menu"]
    if menu and menu.isCompletionistViewOpen then
        menu.ScrollCompletionList(dir)
    end
end

if M.Enabled then
    RegisterKeyBind(Key.INS, {}, function() M.AddPoint() end)
    RegisterKeyBind(Key.DEL, {}, function() M.DeleteLastPoint() end)
    RegisterKeyBind(Key.END, {}, function() ScrollListOr("end", M.Finish) end)
    RegisterKeyBind(Key.HOME, {}, function() ScrollListOr("home", M.ClearDraft) end)
    RegisterKeyBind(Key.PAGE_UP, {}, function() ScrollListOr("pageup", function() M.CycleRegion(-1) end) end)
    RegisterKeyBind(Key.PAGE_DOWN, {}, function() ScrollListOr("pagedown", function() M.CycleRegion(1) end) end)
else
    RegisterKeyBind(Key.END, {}, function() ScrollListOr("end", function() end) end)
    RegisterKeyBind(Key.HOME, {}, function() ScrollListOr("home", function() end) end)
    RegisterKeyBind(Key.PAGE_UP, {}, function() ScrollListOr("pageup", function() end) end)
    RegisterKeyBind(Key.PAGE_DOWN, {}, function() ScrollListOr("pagedown", function() end) end)
end

return M
