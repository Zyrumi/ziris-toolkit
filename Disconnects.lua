-- Ziri's Toolkit: disconnect tracker
-- In a group: chat says when someone disconnects and when they are back
-- (and how long they were gone), and lines at the top of the screen count
-- up while anyone is offline.
--   "Misty disconnected 1:23 ago"
--   "Brakk is offline" (already offline when you joined or reloaded: the
--   game doesn't say since when)

local ADDON_NAME, root = ...

local Disconnects = {}
root.Disconnects = Disconnects

local IsSecret = root.IsSecret

local MAX_LINES = 5

local gone = {} -- [name] = { since = GetTime() or nil when unknown }

local function Bool(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn, ...)
    if not ok or IsSecret(v) then
        return nil
    end
    return v and true or false
end

-- Everyone else in your group.
local function Units()
    local list = {}
    if Bool(IsInRaid) then
        for i = 1, 40 do
            local u = "raid" .. i
            if Bool(UnitExists, u) and not Bool(UnitIsUnit, u, "player") then
                list[#list + 1] = u
            end
        end
    elseif Bool(IsInGroup) then
        for i = 1, 4 do
            if Bool(UnitExists, "party" .. i) then
                list[#list + 1] = "party" .. i
            end
        end
    end
    return list
end

local function Name(unit)
    local ok, name = pcall(UnitName, unit)
    if ok and type(name) == "string" and name ~= "" and not IsSecret(name) then
        return name
    end
    return nil
end

-- The lines for the top of the screen, longest gone first.
function Disconnects.Lines(now)
    now = now or GetTime()
    local names = {}
    for name in pairs(gone) do
        names[#names + 1] = name
    end
    table.sort(names, function(a, b)
        local sa, sb = gone[a].since or -math.huge, gone[b].since or -math.huge
        if sa ~= sb then
            return sa < sb
        end
        return a < b
    end)
    local lines = {}
    for i, name in ipairs(names) do
        if i > MAX_LINES then
            lines[#lines] = ("and %d more offline"):format(#names - MAX_LINES + 1)
            break
        end
        local since = gone[name].since
        lines[#lines + 1] = since and ("%s disconnected %s ago"):format(name, root.Clock(now - since))
            or ("%s is offline"):format(name)
    end
    return lines
end

-------------------------------------------------------------------------------
-- Display
-------------------------------------------------------------------------------

local frame, texts, ticker

local function CreateDisplay()
    frame = CreateFrame("Frame", "ZirisToolkitDisconnects", UIParent)
    frame:SetSize(400, MAX_LINES * 16)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -126) -- below the instance limit line
    frame:SetFrameStrata("LOW")
    frame:EnableMouse(false)
    texts = {}
    for i = 1, MAX_LINES do
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOP", frame, "TOP", 0, -(i - 1) * 16)
        fs:SetShadowOffset(1, -1)
        texts[i] = fs
    end
    frame:Hide()
end

local function UpdateDisplay()
    local lines = root.ModuleOn("disconnects") and Disconnects.Lines() or {}
    if #lines == 0 then
        if frame then
            frame:Hide()
        end
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        return
    end
    if not frame then
        CreateDisplay()
    end
    for i = 1, MAX_LINES do
        texts[i]:SetText(lines[i] or "")
    end
    frame:Show()
    if not ticker and C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(1, UpdateDisplay)
    end
end

-------------------------------------------------------------------------------
-- Watching the group
-------------------------------------------------------------------------------

-- quiet: just take note of who is offline (after a loading screen or
-- /reload), without saying they disconnected just now.
function Disconnects.Scan(quiet)
    if not root.ModuleOn("disconnects") then
        for name in pairs(gone) do
            gone[name] = nil
        end
        UpdateDisplay()
        return
    end
    local present = {}
    for _, unit in ipairs(Units()) do
        local name = Name(unit)
        local online = Bool(UnitIsConnected, unit)
        if name and online ~= nil then
            present[name] = true
            if not online and not gone[name] then
                gone[name] = { since = not quiet and GetTime() or nil }
                if not quiet then
                    root.Print(name .. " disconnected.")
                end
            elseif online and gone[name] then
                local since = gone[name].since
                gone[name] = nil
                root.Print(since and ("%s is back (gone %s)."):format(name, root.Clock(GetTime() - since))
                    or (name .. " is back."))
            end
        elseif name then
            present[name] = gone[name] ~= nil -- can't tell right now: keep what we had
        end
    end
    -- Left the group (or you did): forget them.
    for name in pairs(gone) do
        if not present[name] then
            gone[name] = nil
        end
    end
    UpdateDisplay()
end

root.OnModuleChanged("disconnects", function()
    Disconnects.Scan(true)
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("UNIT_CONNECTION")
events:SetScript("OnEvent", function(_, event)
    if not root.db then
        return
    end
    local ok, err = pcall(Disconnects.Scan, event == "PLAYER_ENTERING_WORLD")
    if not ok then
        root.Print("disconnect tracker: " .. tostring(err))
    end
end)
