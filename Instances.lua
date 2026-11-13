-- Ziri's Toolkit: instance limit
-- The game lets an account enter at most 5 new dungeon or raid instances an
-- hour and 30 a day. The game can't be asked how many you have used, so
-- this part writes down each new instance you enter (on any of your
-- characters) and:
--   says in chat which number it was ("3 of 5 this hour, 8 of 30 today")
--   shows "Next instance allowed in 12:30" at the top of the screen while
--   you are at a limit
--   /zt instances lists the last day's instances
--
-- Going back into the same instance doesn't count again; going into a
-- fresh copy after a reset does. To tell those apart it reads the instance
-- number inside the ID of the first creature you see there.

local ADDON_NAME, root = ...

local Instances = {}
root.Instances = Instances

local IsSecret = root.IsSecret

local HOUR, DAY = 3600, 86400
Instances.PER_HOUR = 5
Instances.PER_DAY = 30

local COUNTED = { party = true, raid = true }

-- The instance you are in right now (nil outside instances).
-- { map, name, entry (the counted entry, or nil while unsure), maybe (an
--   older entry this might be a re-entry of), uid (once known) }
local here
local lastReset = 0

local function Now()
    return time()
end

local function Entries()
    local db = root.db
    if type(db.instances) ~= "table" then
        db.instances = {}
    end
    return db.instances
end

-- Forgets entries older than a day.
local function Prune(now)
    local list = Entries()
    for i = #list, 1, -1 do
        if type(list[i]) ~= "table" or type(list[i].t) ~= "number" or now - list[i].t >= DAY then
            table.remove(list, i)
        end
    end
end

-- Entry times within the last `window` seconds, oldest first.
local function TimesWithin(window, now)
    local times = {}
    for _, e in ipairs(Entries()) do
        if now - e.t < window then
            times[#times + 1] = e.t
        end
    end
    table.sort(times)
    return times
end

-- Counts for the last hour and the last day, and how many seconds until a
-- new instance is allowed (0 if it is allowed now).
function Instances.Status(now)
    now = now or Now()
    local hour = TimesWithin(HOUR, now)
    local day = TimesWithin(DAY, now)
    local wait = 0
    if #hour >= Instances.PER_HOUR then
        wait = math.max(wait, hour[#hour - Instances.PER_HOUR + 1] + HOUR - now)
    end
    if #day >= Instances.PER_DAY then
        wait = math.max(wait, day[#day - Instances.PER_DAY + 1] + DAY - now)
    end
    return #hour, #day, wait
end

local function CountLine(now)
    local hour, day, wait = Instances.Status(now)
    local text = ("%d of %d this hour, %d of %d today."):format(hour, Instances.PER_HOUR, day, Instances.PER_DAY)
    if wait > 0 then
        text = text .. " Next instance allowed in " .. root.Clock(wait) .. "."
    end
    return text
end

-------------------------------------------------------------------------------
-- On-screen line while at a limit
-------------------------------------------------------------------------------

local frame, label, ticker

local function UpdateDisplay()
    if not frame then
        return
    end
    local _, _, wait = Instances.Status()
    if wait <= 0 or not root.ModuleOn("instances") then
        frame:Hide()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        return
    end
    label:SetText("Instance limit reached. Next instance allowed in " .. root.Clock(wait))
    frame:Show()
end

local function ShowDisplay()
    if not frame then
        frame = CreateFrame("Frame", "ZirisToolkitInstances", UIParent)
        frame:SetSize(400, 16)
        frame:SetPoint("TOP", UIParent, "TOP", 0, -108) -- below the boat times
        frame:SetFrameStrata("LOW")
        frame:EnableMouse(false)
        label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("TOP")
        label:SetShadowOffset(1, -1)
        frame:Hide()
    end
    UpdateDisplay()
    if frame:IsShown() and not ticker and C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(1, UpdateDisplay)
    end
end

-------------------------------------------------------------------------------
-- Counting
-------------------------------------------------------------------------------

local function Count(map, name, uid)
    local now = Now()
    local entry = { t = now, map = map, name = name, char = root.CharKey(), uid = uid }
    local list = Entries()
    list[#list + 1] = entry
    root.Print(("%s counted: %s"):format(name, CountLine(now)))
    ShowDisplay()
    return entry
end

-- The most recent counted entry, if it was this map on this character
-- with no reset since: walking back in is then most likely the same copy.
local function LikelySame(map)
    local list = Entries()
    local last = list[#list]
    if last and last.map == map and last.char == root.CharKey() and last.t > lastReset then
        return last
    end
    return nil
end

-- An entry from the last day with this exact instance.
local function FindUid(map, uid, except)
    for _, e in ipairs(Entries()) do
        if e ~= except and e.map == map and e.uid == uid then
            return e
        end
    end
    return nil
end

local function Entered()
    local ok, name, kind, _, _, _, _, _, map = pcall(GetInstanceInfo)
    if not ok or IsSecret(kind) or IsSecret(map) or not COUNTED[kind] or type(map) ~= "number" then
        here = nil
        return
    end
    if here and here.map == map then
        return -- a loading screen inside the same instance
    end
    Prune(Now())
    here = { map = map, name = tostring(name) }
    local same = LikelySame(map)
    if same then
        here.maybe = same -- confirmed or corrected once a creature is seen
    else
        here.entry = Count(map, here.name)
    end
end

-- Called with a unit's GUID; the first creature seen tells which copy of
-- the instance this is.
local function Learn(guid)
    if not here or here.uid or type(guid) ~= "string" or IsSecret(guid) then
        return
    end
    local kind, map, uid = guid:match("^(%a+)%-%d+%-%d+%-(%d+)%-(%d+)%-")
    if (kind ~= "Creature" and kind ~= "Vehicle") or tonumber(map) ~= here.map then
        return
    end
    here.uid = uid
    if here.entry then
        local older = FindUid(here.map, uid, here.entry)
        if older then
            -- Back in an instance already counted: take the new count back.
            local list = Entries()
            for i = #list, 1, -1 do
                if list[i] == here.entry then
                    table.remove(list, i)
                end
            end
            here.entry = nil
            root.Print(("%s: same instance as before, not counted after all."):format(here.name))
            UpdateDisplay()
        else
            here.entry.uid = uid
        end
    elseif here.maybe then
        if here.maybe.uid == nil or here.maybe.uid == uid or FindUid(here.map, uid) then
            here.maybe.uid = here.maybe.uid or uid
        else
            here.entry = Count(here.map, here.name, uid) -- a fresh copy after all
        end
        here.maybe = nil
    end
end

local function LearnFromUnit(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if ok then
        Learn(guid)
    end
end

-- "Deadmines has been reset." Built from the game's own text.
local resetPattern
local function ResetPattern()
    if resetPattern == nil then
        local fmt = rawget(_G, "INSTANCE_RESET_SUCCESS")
        if type(fmt) == "string" then
            local escaped = fmt:gsub("%%s", "@@S@@"):gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
            resetPattern = "^" .. escaped:gsub("@@S@@", ".+") .. "$"
        else
            resetPattern = false
        end
    end
    return resetPattern
end

-------------------------------------------------------------------------------
-- /zt instances
-------------------------------------------------------------------------------

function Instances.Report()
    local now = Now()
    Prune(now)
    local list = Entries()
    if #list == 0 then
        root.Print("no instances entered in the last day.")
        return
    end
    root.Print(CountLine(now))
    for i = #list, 1, -1 do
        local e = list[i]
        local mins = math.floor((now - e.t) / 60)
        local ago = mins < 60 and (mins .. " min") or (("%d h %d min"):format(math.floor(mins / 60), mins % 60))
        root.Print(("  %s, %s ago%s"):format(e.name or "?", ago,
            e.char and (" (" .. e.char .. ")") or ""))
    end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
events:RegisterEvent("CHAT_MSG_SYSTEM")

events:SetScript("OnEvent", function(_, event, arg1)
    if not root.ModuleOn("instances") then
        return
    end
    local ok, err = pcall(function()
        if event == "PLAYER_ENTERING_WORLD" then
            Entered()
            ShowDisplay()
        elseif not here then
            if event == "CHAT_MSG_SYSTEM" and type(arg1) == "string" and not IsSecret(arg1) then
                local pattern = ResetPattern()
                if pattern and arg1:match(pattern) then
                    lastReset = Now()
                end
            end
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            LearnFromUnit(arg1)
        elseif event == "PLAYER_TARGET_CHANGED" then
            LearnFromUnit("target")
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            LearnFromUnit("mouseover")
        end
    end)
    if not ok and not root.instancesError then
        root.instancesError = true
        root.Print("instance limit: something went wrong: " .. tostring(err))
    end
end)

root.OnModuleChanged("instances", function(on)
    if on then
        ShowDisplay()
    else
        here = nil
        UpdateDisplay()
    end
end)
