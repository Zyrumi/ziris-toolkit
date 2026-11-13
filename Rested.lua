-- Ziri's Toolkit: rested XP per character
-- Remembers each character's rested XP when you play them, and works out
-- how much more they have rested since you logged out.
-- /zt rested lists them, most rested first.
--
-- The game's rules: a character gains rested XP worth 5% of a level every
-- 8 hours while logged out in an inn or a city, a quarter of that anywhere
-- else, up to 150% of a level (one and a half levels).

local ADDON_NAME, root = ...

local Rested = {}
root.Rested = Rested

local IsSecret = root.IsSecret

local PER_8H = 0.05
local FULL = 1.5
local OUTSIDE = 0.25
local EIGHT_HOURS = 8 * 3600

local function Store()
    local db = root.db
    if type(db.rested) ~= "table" then
        db.rested = {}
    end
    return db.rested
end

local function Num(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn, ...)
    if not ok or IsSecret(v) or type(v) ~= "number" then
        return nil
    end
    return v
end

local function AtMaxLevel(level)
    local max = Num(GetMaxLevelForPlayerExpansion) or Num(GetMaxPlayerLevel)
    return max ~= nil and level >= max
end

-- Saves the character you are playing now.
function Rested.Save()
    local key = root.CharKey()
    local level = Num(UnitLevel, "player")
    local maxXP = Num(UnitXPMax, "player")
    if not key or not level or not maxXP then
        return
    end
    local ok, resting = pcall(IsResting)
    local _, class = pcall(UnitClass, "player")
    Store()[key] = {
        level = level,
        maxXP = maxXP,
        rested = Num(GetXPExhaustion) or 0,
        resting = ok and resting == true,
        class = (type(class) == "string" and not IsSecret(class)) and class or nil,
        max = AtMaxLevel(level) or maxXP <= 0,
        t = time(),
    }
end

-- How much of a level a saved character has rested by now (0 to 1.5).
function Rested.Now(entry, now)
    if type(entry) ~= "table" or not entry.maxXP or entry.maxXP <= 0 then
        return 0
    end
    local share = (entry.rested or 0) / entry.maxXP
    local elapsed = math.max(0, (now or time()) - (entry.t or 0))
    local rate = PER_8H * (entry.resting and 1 or OUTSIDE)
    return math.min(FULL, share + rate * elapsed / EIGHT_HOURS)
end

local function Duration(seconds)
    local hours = math.ceil(seconds / 3600)
    if hours < 24 then
        return hours .. (hours == 1 and " hour" or " hours")
    end
    local days = math.floor(hours / 24)
    hours = hours % 24
    local text = days .. (days == 1 and " day" or " days")
    if hours > 0 then
        text = text .. " " .. hours .. " h"
    end
    return text
end

-- One line per character, most rested first.
function Rested.Lines(now)
    now = now or time()
    local me = root.CharKey()
    local rows = {}
    for key, e in pairs(Store()) do
        if type(e) == "table" and not e.max then
            local share = Rested.Now(e, now)
            local text = ("%s, level %d%s: %d%% of a level"):format(key, e.level or 0,
                e.class and (" " .. e.class:lower()) or "", math.floor(share * 100 + 0.5))
            if share >= FULL then
                text = text .. " (full)"
            elseif key ~= me then
                local rate = PER_8H * (e.resting and 1 or OUTSIDE)
                text = text .. (" (full in %s%s)"):format(Duration((FULL - share) / rate * EIGHT_HOURS),
                    e.resting and "" or ", logged out outside an inn or city")
            end
            if key == me then
                text = text .. " (playing now)"
            end
            rows[#rows + 1] = { share = share, text = text }
        end
    end
    table.sort(rows, function(a, b)
        if a.share ~= b.share then
            return a.share > b.share
        end
        return a.text < b.text
    end)
    local out = {}
    for i, r in ipairs(rows) do
        out[i] = r.text
    end
    return out
end

function Rested.Report()
    Rested.Save()
    local lines = Rested.Lines()
    if #lines == 0 then
        root.Print("no characters below max level seen yet. Log in on each once to add them.")
        return
    end
    root.Print("rested XP:")
    for _, line in ipairs(lines) do
        root.Print("  " .. line)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_UPDATE_RESTING")
events:RegisterEvent("UPDATE_EXHAUSTION")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:SetScript("OnEvent", function()
    if root.ModuleOn("rested") then
        pcall(Rested.Save)
    end
end)
