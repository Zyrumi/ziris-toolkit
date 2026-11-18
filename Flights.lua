-- Ziri's Toolkit: flight path timer
-- A bar at the top of the screen while you are on a flight path: where you
-- are going, how long is left and how far along you are.
--
-- The game doesn't tell addons how long a flight takes, so the toolkit
-- learns each route the first time you fly it all the way (that flight
-- shows the time so far instead). Routes are shared by all your characters.
-- Flights you leave early (the "land now" button) are not saved.

local ADDON_NAME, root = ...

local Flights = {}
root.Flights = Flights

local IsSecret = root.IsSecret

local START_WAIT = 10   -- seconds to wait for the flight to start after picking it
local RESUME_LIMIT = 30 * 60 -- a saved flight older than this is not resumed

local frame, bar, text
local pending -- { key, to, picked } after picking a flight, before take-off

local function Store()
    local db = root.db
    if type(db.flights) ~= "table" then
        db.flights = {}
    end
    return db.flights
end

-- The flight under way, saved so a /reload mid-flight keeps it:
-- { key, to, startWall (time()), early }
local function Current()
    return root.db and root.db.flight
end

local function Str(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn, ...)
    if ok and type(v) == "string" and v ~= "" and not IsSecret(v) then
        return v
    end
    return nil
end

local function Num(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn, ...)
    if ok and type(v) == "number" and not IsSecret(v) then
        return v
    end
    return nil
end

local function OnTaxi()
    if type(UnitOnTaxi) ~= "function" then
        return false
    end
    local ok, v = pcall(UnitOnTaxi, "player")
    return ok and not IsSecret(v) and v == true
end

-- "Stormwind, Elwynn" -> "Stormwind"
local function Short(name)
    return (name:match("^([^,]+)") or name)
end

-- The node you are standing at on the open flight map: name, slot.
local function HereName()
    for i = 1, Num(NumTaxiNodes) or 0 do
        if Str(TaxiNodeGetType, i) == "CURRENT" then
            return Str(TaxiNodeName, i), i
        end
    end
    return nil
end

-- Called when you pick a destination on the flight map.
function Flights.Picked(slot)
    if not root.ModuleOn("flights") then
        return
    end
    local to = Str(TaxiNodeName, slot)
    local from = HereName()
    if not to then
        return
    end
    local ok, est, kind = pcall(Flights.TimeTo, slot)
    pending = { key = (from or "?") .. " > " .. to, to = to, picked = GetTime(), known = from ~= nil,
        est = ok and est or nil, kind = ok and kind or nil }
end

-- Seconds for a learned route, or nil.
function Flights.Known(key)
    local v = Store()[key]
    if type(v) == "number" and v > 0 then
        return v
    end
    return nil
end

-- Text and fill (0..1) for the bar, from the time flown so far.
function Flights.Status(flight, elapsed)
    local name = Short(flight.to)
    if flight.known == false then
        return ("%s: %s so far"):format(name, root.Clock(elapsed)), nil
    end
    local total, about = Flights.Known(flight.key), false
    if not total and type(flight.est) == "number" and flight.est > 0 then
        total, about = flight.est, flight.kind == "estimate"
    end
    if not total then
        return ("%s: first flight on this route, timing it (%s)"):format(name, root.Clock(elapsed)), nil
    end
    local left = total - elapsed
    if left <= 0 then
        return ("%s: landing any moment"):format(name), 1
    end
    return ("%s: %s%s left"):format(name, about and "about " or "", root.Clock(left)), math.min(1, elapsed / total)
end

-------------------------------------------------------------------------------
-- Display
-------------------------------------------------------------------------------

local function CreateDisplay()
    frame = CreateFrame("Frame", "ZirisToolkitFlight", UIParent, "BackdropTemplate")
    frame:SetSize(300, 22)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -72)
    frame:SetFrameStrata("LOW")
    frame:EnableMouse(false) -- never in the way of clicks
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.6)
        frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)
    end
    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOPLEFT", 3, -3)
    bar:SetPoint("BOTTOMRIGHT", -3, 3)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.25, 0.55, 0.9, 0.85)
    bar:SetMinMaxValues(0, 1)
    text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    text:SetShadowOffset(1, -1)
    frame:Hide()
end

local function Show(flight, elapsed)
    if not frame then
        CreateDisplay()
    end
    local label, fill = Flights.Status(flight, elapsed)
    text:SetText(label)
    bar:SetValue(fill or 0)
    frame:Show()
end

local function Hide()
    if frame then
        frame:Hide()
    end
end

-------------------------------------------------------------------------------
-- Following the flight
-------------------------------------------------------------------------------

local function Landed(flight)
    root.db.flight = nil
    Hide()
    if flight.early or not flight.known then
        return
    end
    local seconds = math.floor(time() - flight.startWall + 0.5)
    if seconds > 5 then
        Store()[flight.key] = seconds
    end
end

-- Runs about ten times a second while a flight is picked or under way.
function Flights.Tick()
    local flight = Current()
    if pending then
        if OnTaxi() then
            root.db.flight = { key = pending.key, to = pending.to, known = pending.known,
                est = pending.est, kind = pending.kind, startWall = time(), startClock = GetTime() }
            pending = nil
            flight = root.db.flight
        elseif GetTime() - pending.picked > START_WAIT then
            pending = nil -- the flight never started (no money, closed, ...)
        end
    end
    if not flight then
        Hide()
        return
    end
    if not OnTaxi() then
        Landed(flight)
        return
    end
    local elapsed = flight.startClock and (GetTime() - flight.startClock) or (time() - flight.startWall)
    Show(flight, elapsed)
end

function Flights.LandEarly()
    local flight = Current()
    if flight then
        flight.early = true
    end
end

local driver = CreateFrame("Frame")
local since = 0
driver:SetScript("OnUpdate", function(_, dt)
    since = since + (dt or 0)
    if since < 0.1 then
        return
    end
    since = 0
    if not pending and not Current() then
        Hide()
        return
    end
    local ok, err = pcall(Flights.Tick)
    if not ok then
        pending = nil
        if root.db then
            root.db.flight = nil
        end
        Hide()
        root.Print("flight timer: " .. tostring(err))
    end
end)

-- After a /reload or relog in the air: carry on with the saved flight.
local function Resume()
    local flight = Current()
    if not flight then
        return
    end
    if not root.ModuleOn("flights") or not OnTaxi() or time() - (flight.startWall or 0) > RESUME_LIMIT then
        root.db.flight = nil
        return
    end
    flight.startClock = GetTime() - (time() - flight.startWall)
end

root.OnModuleChanged("flights", function(on)
    if not on then
        pending = nil
        if root.db then
            root.db.flight = nil
        end
        Hide()
    end
end)

if type(TakeTaxiNode) == "function" and hooksecurefunc then
    hooksecurefunc("TakeTaxiNode", function(slot)
        pcall(Flights.Picked, slot)
    end)
end
if type(TaxiRequestEarlyLanding) == "function" and hooksecurefunc then
    hooksecurefunc("TaxiRequestEarlyLanding", function()
        pcall(Flights.LandEarly)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    pcall(Resume)
end)

-------------------------------------------------------------------------------
-- Flight time on the flight map's tooltip
-------------------------------------------------------------------------------

-- Times from other addons (FlightData.lua) for routes you haven't flown:
-- InFlight's measured times and FlightCountdown's hop lengths. Both are
-- keyed by the game's flight point IDs, not names.

-- slot -> flight point ID at the open flight master.
local function NodeIDs()
    local ids = {}
    local mapID = Num(GetTaxiMapID)
    if not mapID or not (C_TaxiMap and type(C_TaxiMap.GetAllTaxiNodes) == "function") then
        return ids
    end
    local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
    if ok and type(nodes) == "table" then
        for _, n in ipairs(nodes) do
            if type(n) == "table" and type(n.slotIndex) == "number" and type(n.nodeID) == "number"
                and not IsSecret(n.slotIndex) and not IsSecret(n.nodeID) then
                ids[n.slotIndex] = n.nodeID
            end
        end
    end
    return ids
end

-- Frequent Flier (Adventure Legacy perk): flights are 20% faster. The other
-- addons' data is without it; your own learned times already include it.
local FREQUENT_FLIER_TREE, FREQUENT_FLIER_NODE, FREQUENT_FLIER = 1188, 110300, 1.2
local function SpeedUp()
    if not (C_Traits and C_Traits.GetConfigIDByTreeID and C_Traits.GetNodeInfo) then
        return 1
    end
    local ok, config = pcall(C_Traits.GetConfigIDByTreeID, FREQUENT_FLIER_TREE)
    if not ok or type(config) ~= "number" or IsSecret(config) then
        return 1
    end
    local ok2, info = pcall(C_Traits.GetNodeInfo, config, FREQUENT_FLIER_NODE)
    if ok2 and type(info) == "table" and type(info.activeRank) == "number"
        and not IsSecret(info.activeRank) and info.activeRank > 0 then
        return FREQUENT_FLIER
    end
    return 1
end

-- InFlight's measured time from one flight point to another, or nil.
local function DataTime(fromID, toID)
    local data = root.FlightData
    local faction = Str(UnitFactionGroup, "player")
    local t = data and faction and fromID and toID and data.times[faction]
    t = t and t[fromID] and t[fromID][toID]
    return type(t) == "number" and t or nil
end

-- A direct hop's length turned into seconds, or nil.
local function YardsTime(fromID, toID)
    local data = root.FlightData
    local y = data and fromID and toID and data.yards[fromID * 10000 + toID]
    return type(y) == "number" and y / data.speed or nil
end

-- Seconds for the flight from where you stand to `slot`, and where the time
-- comes from: "learned" (you flew it), "data" (InFlight's measured time for
-- the whole route) or "estimate" (the stops added up). nil if unknown.
function Flights.TimeTo(slot)
    local here, hereSlot = HereName()
    local to = Str(TaxiNodeName, slot)
    if not here or not to then
        return nil
    end
    local known = Flights.Known(here .. " > " .. to)
    if known then
        return known, "learned"
    end
    local ids, speedUp = NodeIDs(), SpeedUp()
    local data = DataTime(ids[hereSlot], ids[slot])
    if data then
        return data / speedUp, "data"
    end
    -- Add up the stops, each from your own time, InFlight's or its length.
    local hops = Num(GetNumRoutes, slot) or 1
    local total = 0
    for i = 1, hops do
        local a = Num(TaxiGetNodeSlot, slot, i, true) or (hops == 1 and hereSlot)
        local b = Num(TaxiGetNodeSlot, slot, i, false) or (hops == 1 and slot)
        local an, bn = a and Str(TaxiNodeName, a), b and Str(TaxiNodeName, b)
        local t = an and bn and Flights.Known(an .. " > " .. bn)
        if not t then
            local other = DataTime(ids[a], ids[b]) or YardsTime(ids[a], ids[b])
            t = other and other / speedUp
        end
        if not t then
            return nil
        end
        total = total + t
    end
    return total, "estimate"
end

function Flights.TooltipLine(slot)
    local seconds, kind = Flights.TimeTo(slot)
    if not seconds then
        return "Flight time: not timed yet", 0.6, 0.6, 0.6
    end
    return ("Flight time: %s%s"):format(kind == "estimate" and "about " or "", root.Clock(seconds)), 1, 1, 1
end

local function AddToTooltip(owner, slot)
    if not root.ModuleOn("flights") or not slot or GameTooltip:GetOwner() ~= owner then
        return
    end
    local text, r, g, b = Flights.TooltipLine(slot)
    GameTooltip:AddLine(text, r, g, b)
    GameTooltip:Show()
end

-- The new flight map (most flight masters).
local function HookFlightMap()
    local mixin = FlightMap_FlightPointPinMixin
    if type(mixin) ~= "table" or Flights.flightMapHooked then
        return
    end
    Flights.flightMapHooked = true
    local function OnEnter(pin)
        local data = rawget(pin, "taxiNodeData")
        if type(data) == "table" and Enum and Enum.FlightPathState
            and data.state == Enum.FlightPathState.Reachable then
            pcall(AddToTooltip, pin, data.slotIndex)
        end
    end
    hooksecurefunc(mixin, "OnMouseEnter", OnEnter)
    -- Pins made before the hook carry the old function.
    local map = FlightMapFrame
    if map and map.EnumeratePinsByTemplate then
        pcall(function()
            for pin in map:EnumeratePinsByTemplate("FlightMap_FlightPointPinTemplate") do
                hooksecurefunc(pin, "OnMouseEnter", OnEnter)
            end
        end)
    end
end

-- The older taxi map (a few flight masters).
if type(TaxiNodeOnButtonEnter) == "function" and hooksecurefunc then
    hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
        local slot = button and button.GetID and button:GetID()
        if slot and Str(TaxiNodeGetType, slot) == "REACHABLE" then
            pcall(AddToTooltip, button, slot)
        end
    end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    if name == "Blizzard_FlightMap" then
        pcall(HookFlightMap)
    end
end)
pcall(HookFlightMap) -- in case it was loaded before the toolkit

-- /zt flights: the routes learned so far.
function Flights.Report()
    local keys = {}
    for key, v in pairs(Store()) do
        if type(v) == "number" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    if #keys == 0 then
        root.Print("no flight routes learned yet. Fly one all the way to add it.")
        return
    end
    root.Print("flight times learned:")
    for _, key in ipairs(keys) do
        root.Print("  " .. key .. ": " .. root.Clock(Store()[key]))
    end
end
