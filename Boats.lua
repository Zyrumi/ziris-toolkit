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

-- Returns the lines to show right now (may be empty).
function Boats.Lines()
    local api = API()
    if not api then
        return {}
    end
    local out = {}

    local ride = Ask(api, "GetCurrentRide")
    if type(ride) == "table" then
        local to = DockName(DocksById(api), ride.to)
        if ride.arrivesIn then
            out[1] = ("Arriving at %s in %s"):format(to, Clock(ride.arrivesIn))
        else
            out[1] = ("On the way to %s"):format(to)
        end
        return out
    end

    local context = Ask(api, "GetPlayerContext")
    if type(context) ~= "table" or type(context.atEndpoints) ~= "table" then
        return out
    end
    if #context.atEndpoints == 0 then
        return out
    end
    local docks = DocksById(api)
    for _, endpointId in ipairs(context.atEndpoints) do
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
            if arrives and leaves then
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
