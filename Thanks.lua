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

-- Returns the caster's name if this new buff deserves a thank you.
local function ThankWorthy(aura)
    if type(aura) ~= "table" or IsSecret(aura) then
        return nil
    end
    if aura.isHelpful ~= true or aura.isFromPlayerOrPlayerPet ~= true then
        return nil
    end
    local unit = aura.sourceUnit
    if IsSecret(unit) or type(unit) ~= "string" then
        return nil
    end
    local duration = aura.duration
    if IsSecret(duration) or type(duration) ~= "number" or duration < MIN_DURATION then
        return nil -- also skips buffs without an end (0)
    end
    if Safe(UnitIsUnit, unit, "player") or Safe(UnitIsUnit, unit, "pet") then
        return nil
    end
    if not Safe(UnitIsPlayer, unit) then
        return nil -- pets and NPCs
    end
    if Safe(UnitInParty, unit) or Safe(UnitInRaid, unit) then
        return nil -- in your group: no thanks spam
    end
    return FullName(unit)
end

local function OnAura(info)
    if not listening or not root.ModuleOn("thanks") then
        return
    end
    if InCombatLockdown() or type(info) ~= "table" or info.isFullUpdate then
        return -- full updates are zoning or reloads, not new buffs
    end
    local added = info.addedAuras
    if type(added) ~= "table" then
        return
    end
    local now = GetTime()
    for _, aura in ipairs(added) do
        local ok, name = pcall(ThankWorthy, aura)
        if ok and name and (not lastThanked[name] or now - lastThanked[name] >= COOLDOWN) then
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
