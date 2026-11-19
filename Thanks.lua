-- Ziri's Toolkit: thanks
-- Does the /thank emote at a player who gives you a buff out in the world.
--
-- Forever gives addons no combat log, so this watches buffs landing on you
-- and asks the game who cast them. That is only readable out of combat,
-- which is when strangers buff you anyway.
--
-- Never thanked: yourself, pets, party and raid members, short buffs (procs
-- from someone's heal), and the same person twice within a minute.

local ADDON_NAME, root = ...

local COOLDOWN = 60       -- seconds before the same person is thanked again
local MIN_DURATION = 60   -- shorter buffs are procs, not a gift
local SETTLE = 4          -- seconds after a loading screen before we listen
local DELAY_MIN, DELAY_MAX = 1, 2.5 -- a short pause feels less robotic

local IsSecret = root.IsSecret

local lastThanked = {}    -- [name] = GetTime() of the last thanks
local seen = {}           -- the last buffs from others and what became of them, newest last
local SEEN_MAX = 8
local listening = false
local settleToken = 0

local function Safe(fn, ...)
    if not fn then
        return false
    end
    local ok, v = pcall(fn, ...)
    if not ok or IsSecret(v) then
        return nil
    end
    return v
end

-- "First Surname" on Forever (no realms), plain name elsewhere.
local function FullName(unit)
    local ok, name, second = pcall(UnitName, unit)
    if not ok or IsSecret(name) or IsSecret(second) or type(name) ~= "string" or name == "" then
        return nil
    end
    if type(second) == "string" and second ~= "" then
        return name .. " " .. second
    end
    return name
end

local function Emote(target)
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local locked = Safe(C_ChatInfo.InChatMessagingLockdown)
        if locked then
            return
        end
    end
    if C_ChatInfo and C_ChatInfo.PerformEmote then
        pcall(C_ChatInfo.PerformEmote, "THANK", target)
    elseif DoEmote then
        pcall(DoEmote, "THANK", target)
    end
end

-- Returns the caster's name if this new buff deserves a thank you, else
-- nil and why not (nil reason: not worth listing, like a debuff).
local function ThankWorthy(aura)
    if type(aura) ~= "table" or IsSecret(aura) then
        return nil, "hidden by the game"
    end
    local helpful, fromPlayer = aura.isHelpful, aura.isFromPlayerOrPlayerPet
    if IsSecret(helpful) or IsSecret(fromPlayer) then
        return nil, "hidden by the game"
    end
    if helpful ~= true then
        return nil
    end
    if fromPlayer ~= true then
        return nil, "not from a player"
    end
    local unit = aura.sourceUnit
    if IsSecret(unit) then
        return nil, "hidden by the game"
    end
    if type(unit) == "string" and (Safe(UnitIsUnit, unit, "player") or Safe(UnitIsUnit, unit, "pet")) then
        return nil -- your own
    end
    local duration = aura.duration
    if IsSecret(duration) or type(duration) ~= "number" or duration < MIN_DURATION then
        return nil, "too short to be a gift" -- also buffs without an end (0)
    end
    if type(unit) ~= "string" then
        return nil, "the game didn't say who cast it"
    end
    if not Safe(UnitIsPlayer, unit) then
        return nil, "from a pet or NPC"
    end
    if Safe(UnitInParty, unit) or Safe(UnitInRaid, unit) then
        return nil, "from your group" -- no thanks spam
    end
    local name = FullName(unit)
    if not name then
        return nil, "hidden by the game"
    end
    return name
end

local function Remember(aura, what)
    local name = type(aura) == "table" and not IsSecret(aura) and aura.name
    if IsSecret(name) or type(name) ~= "string" then
        name = "a buff"
    end
    seen[#seen + 1] = { at = GetTime(), spell = name, what = what }
    if #seen > SEEN_MAX then
        table.remove(seen, 1)
    end
end

-- /zt thanks: the last buffs from others and why each was or wasn't thanked.
function root.ThanksReport()
    if not root.ModuleOn("thanks") then
        root.Print("Thanks is switched off in the options.")
    end
    if #seen == 0 then
        root.Print("Thanks: no buffs from others seen since you logged in.")
        return
    end
    root.Print("Thanks, the last buffs on you:")
    local now, unnamed = GetTime(), false
    for _, e in ipairs(seen) do
        root.Print(("  %s ago: %s, %s"):format(root.Clock(now - e.at), e.spell, e.what))
        if e.what == "not thanked: the game didn't say who cast it" then
            unnamed = true
        end
    end
    if unnamed then
        root.Print("  The game only names who buffed you when it can see them as a unit: your target, mouseover, or a player whose nameplate is showing.")
    end
end

local function OnAura(info)
    if not listening or not root.ModuleOn("thanks") then
        return
    end
    if InCombatLockdown() or type(info) ~= "table" or IsSecret(info) then
        return
    end
    -- The game can hide aura details from addons (secret values): then
    -- there is no telling who buffed you, so nobody is thanked.
    local full = info.isFullUpdate
    if IsSecret(full) or full then
        return -- full updates are zoning or reloads, not new buffs
    end
    local added = info.addedAuras
    if IsSecret(added) or type(added) ~= "table" then
        return
    end
    local now = GetTime()
    for _, aura in ipairs(added) do
        local ok, name, why = pcall(ThankWorthy, aura)
        if not ok then
            Remember(aura, "not thanked: something went wrong")
        elseif not name then
            if why then
                Remember(aura, "not thanked: " .. why)
            end
        elseif lastThanked[name] and now - lastThanked[name] < COOLDOWN then
            Remember(aura, "from " .. name .. ", already thanked this minute")
        else
            Remember(aura, "thanked " .. name)
            lastThanked[name] = now -- several buffs at once: one thank you
            local delay = DELAY_MIN + math.random() * (DELAY_MAX - DELAY_MIN)
            C_Timer.After(delay, function()
                if root.ModuleOn("thanks") and not InCombatLockdown() then
                    Emote(name)
                end
            end)
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterUnitEvent("UNIT_AURA", "player")
events:RegisterEvent("PLAYER_ENTERING_WORLD")

events:SetScript("OnEvent", function(_, event, unit, info)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Buffs coming back after a loading screen are not new.
        listening = false
        settleToken = settleToken + 1
        local token = settleToken
        C_Timer.After(SETTLE, function()
            if token == settleToken then
                listening = true
            end
        end)
        return
    end
    local ok, err = pcall(OnAura, info)
    if not ok and not root.thanksError then
        root.thanksError = true
        root.Print("thanks: something went wrong: " .. tostring(err))
    end
end)
