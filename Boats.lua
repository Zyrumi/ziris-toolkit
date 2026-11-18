-- Ziri's Toolkit: boat times
-- A few lines at the top of the screen, only when they matter:
--   standing at a dock: when each boat or zeppelin from here leaves (and
--   when it arrives, if it is still on its way)
--   on board: when you arrive
-- Everything else stays off the screen.
--
-- The times come from the DockWatch addon, which learns them and shares
-- them between players. It offers them to other addons through its public
-- DockWatchAPI. DockWatch's own map and window can be switched off in its
-- options (/dw options); this part keeps working.

local ADDON_NAME, root = ...

local Boats = {}
root.Boats = Boats

local TICK = 1
local MAX_LINES = 4
-- DockWatch only counts you as "at a dock" within 150 yards of where the
-- boat stops; a whole harbor (Stormwind's, say) is bigger than that.
local NEAR = 300 -- yards
local WEEK = 7 * 24 * 60 * 60

local frame, lines
local ticker

local function API()
    local api = rawget(_G, "DockWatchAPI")
    if type(api) ~= "table" or type(api.IsReady) ~= "function" then
        return nil
    end
    local ok, ready = pcall(api.IsReady)
    if not ok or not ready then
        return nil
    end
    return api
end

-- Calls a DockWatch function; nil on any error or "not ready" answer.
local function Ask(api, name, ...)
    local fn = api[name]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, ...)
    if not ok then
        return nil
    end
    return result
end

local Clock = root.Clock

local function When(seconds, approximate)
    return (approximate and "~" or "") .. Clock(seconds)
end

local VEHICLES = { boat = "Boat", zeppelin = "Zeppelin", tram = "Tram" }

local function Vehicle(route)
    local v = route and route.vehicle
    return VEHICLES[v] or (type(v) == "string" and (v:sub(1, 1):upper() .. v:sub(2))) or "Boat"
end

-- All docks DockWatch knows, by endpoint ID.
local function DocksById(api)
    local byId = {}
    local docks = Ask(api, "GetDocks")
    if type(docks) == "table" then
        for _, d in ipairs(docks) do
            if d.id then
                byId[d.id] = d
            end
        end
    end
    return byId
end

local function DockName(docks, endpointId)
    local d = endpointId and docks[endpointId]
    return d and d.name or "?"
end

-------------------------------------------------------------------------------
-- What to show
-------------------------------------------------------------------------------

-- When the servers last restarted for the weekly reset, on DockWatch's clock.
-- A restart moves every boat's schedule, so a time DockWatch last saw before
-- it is a guess that can be off by a whole trip. (DockWatch only notices a
-- restart from the shutdown warning in chat or from riding a route.)
local function LastRestart(api)
    local dt = rawget(_G, "C_DateAndTime")
    local fn = type(dt) == "table" and dt.GetSecondsUntilWeeklyReset
    local now = Ask(api, "Now")
    if type(fn) ~= "function" or type(now) ~= "number" then
        return nil
    end
    local ok, left = pcall(fn)
    if not ok or root.IsSecret(left) or type(left) ~= "number" then
        return nil
    end
    return now + left - WEEK
end

-- True for a time DockWatch has not confirmed since the last restart.
local function Outdated(info, restart)
    if type(info) ~= "table" or not info.approximate or not restart then
        return false
    end
    return type(info.confirmedAt) ~= "number" or info.confirmedAt < restart
end

-- The docks you are at: DockWatch's own answer, plus any dock within NEAR
-- yards or named like the part of the zone you are in. Nearest first.
local function NearbyDocks(docks, context)
    local found, list = {}, {}
    local function add(id, distance)
        if not found[id] then
            found[id] = { id = id, distance = distance or 0 }
            list[#list + 1] = found[id]
        elseif distance and distance < found[id].distance then
            found[id].distance = distance
        end
    end
    if type(context.atEndpoints) == "table" then
        for _, id in ipairs(context.atEndpoints) do
            add(id, 0)
        end
    end
    local ok, p1, p2, _, instance = pcall(UnitPosition, "player")
    if not ok or root.IsSecret(p1) or root.IsSecret(p2) or root.IsSecret(instance) then
        p1 = nil
    end
    local subzone = GetSubZoneText and GetSubZoneText()
    if root.IsSecret(subzone) or subzone == "" then
        subzone = nil
    end
    for id, d in pairs(docks) do
        local pos = d.position
        if type(p1) == "number" and type(p2) == "number" and type(pos) == "table"
            and pos.instanceId == instance and pos.x and pos.y then
            local distance = math.sqrt((pos.x - p1) ^ 2 + (pos.y - p2) ^ 2)
            if distance <= NEAR then
                add(id, distance)
            end
        end
        if subzone and d.name == subzone then
            add(id, NEAR)
        end
    end
    table.sort(list, function(a, b)
        if a.distance ~= b.distance then
            return a.distance < b.distance
        end
        return a.id < b.id
    end)
    return list
end

-- Returns the lines to show right now (may be empty).
function Boats.Lines()
    local api = API()
    if not api then
        return {}
    end
    local out = {}

    -- On board: the arrival countdown. Once it reaches 0:00 the boat is in,
    -- and the dock's own times show (DockWatch keeps you "aboard" for up to
    -- 20 seconds after that, until you stand still or walk off).
    local ride = Ask(api, "GetCurrentRide")
    if type(ride) == "table" and not (ride.arrivesIn and ride.arrivesIn <= 0) then
        local to = DockName(DocksById(api), ride.to)
        if ride.arrivesIn then
            out[1] = ("Arriving at %s in %s"):format(to, Clock(ride.arrivesIn))
        else
            out[1] = ("On the way to %s"):format(to)
        end
        return out
    end

    local context = Ask(api, "GetPlayerContext")
    if type(context) ~= "table" then
        return out
    end
    local docks = DocksById(api)
    local restart = LastRestart(api)
    for _, near in ipairs(NearbyDocks(docks, context)) do
        local endpointId = near.id
        local dock = docks[endpointId]
        local route = dock and dock.routeId and Ask(api, "GetRoute", dock.routeId)
        local direction
        if type(route) == "table" and type(route.directions) == "table" then
            for _, dir in ipairs(route.directions) do
                if dir.from == endpointId then
                    direction = dir
                end
            end
        end
        if direction and #out < MAX_LINES then
            local name = ("%s to %s"):format(Vehicle(route), DockName(docks, direction.to))
            local dep = Ask(api, "GetNextDeparture", direction.id)
            local arr = Ask(api, "GetNextArrival", endpointId)
            local leaves = type(dep) == "table" and dep.departsIn
            local arrives = type(arr) == "table" and arr.underway and arr.arrivesIn
            local outdated = (leaves and Outdated(dep, restart)) or (arrives and Outdated(arr, restart))
            if outdated then
                out[#out + 1] = ("%s: not seen since the server restart, time unknown"):format(name)
            elseif arrives and leaves then
                out[#out + 1] = ("%s: arrives in %s, leaves in %s"):format(name,
                    When(arrives, arr.approximate), When(leaves, dep.approximate))
            elseif leaves then
                out[#out + 1] = ("%s leaves in %s"):format(name, When(leaves, dep.approximate))
            elseif arrives then
                out[#out + 1] = ("%s arrives in %s"):format(name, When(arrives, arr.approximate))
            else
                out[#out + 1] = ("%s: time not known yet"):format(name)
            end
        end
    end
    return out
end

-------------------------------------------------------------------------------
-- Display
-------------------------------------------------------------------------------

local function CreateDisplay()
    frame = CreateFrame("Frame", "ZirisToolkitBoats", UIParent)
    frame:SetSize(400, MAX_LINES * 16)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -40)
    frame:SetFrameStrata("LOW")
    frame:EnableMouse(false) -- never in the way of clicks
    lines = {}
    for i = 1, MAX_LINES do
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOP", frame, "TOP", 0, -(i - 1) * 16)
        fs:SetShadowOffset(1, -1)
        lines[i] = fs
    end
    frame:Hide()
end

local function Update()
    if not frame then
        return
    end
    local ok, text = pcall(Boats.Lines)
    if not ok or type(text) ~= "table" or #text == 0 then
        frame:Hide()
        return
    end
    for i = 1, MAX_LINES do
        lines[i]:SetText(text[i] or "")
    end
    frame:Show()
end

local function Start()
    -- DockWatch loads before us when it is installed; without it there is
    -- nothing to show, so nothing runs.
    if type(rawget(_G, "DockWatchAPI")) ~= "table" then
        return
    end
    if not frame then
        CreateDisplay()
    end
    if not ticker and C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(TICK, Update)
    end
    Update()
end

local function Stop()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if frame then
        frame:Hide()
    end
end

function Boats.Refresh()
    if root.ModuleOn("boats") then
        Start()
    else
        Stop()
    end
end

-- True if DockWatch is installed and loaded.
function Boats.HasDockWatch()
    return type(rawget(_G, "DockWatchAPI")) == "table"
end

root.OnModuleChanged("boats", function()
    Boats.Refresh()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    local ok, err = pcall(Boats.Refresh)
    if not ok then
        root.Print("boat times: " .. tostring(err))
    end
end)
