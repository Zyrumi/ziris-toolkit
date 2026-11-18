-- Ziri's Toolkit: healer mana after combat
-- When a fight ends and you are tanking in a group, a warning in the middle
-- of the screen if a healer is under 20% mana, so you wait before the next
-- pull: "Healer low on mana: Holly 14%".
-- Healers are the people with the healer group role; nobody is guessed.

local ADDON_NAME, root = ...

local HealerMana = {}
root.HealerMana = HealerMana

local IsSecret = root.IsSecret

local LOW = 0.20
local MANA = 0 -- Enum.PowerType.Mana
local SETTLE = 0.5 -- seconds after combat before reading: values can still be hidden right at the end

local function Get(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn, ...)
    if not ok or IsSecret(v) then
        return nil
    end
    return v
end

local function Units()
    local list = {}
    if Get(IsInRaid) then
        for i = 1, 40 do
            list[#list + 1] = "raid" .. i
        end
    elseif Get(IsInGroup) then
        for i = 1, 4 do
            list[#list + 1] = "party" .. i
        end
    end
    return list
end

-- Healers under 20% mana: list of { name, percent }, lowest first.
function HealerMana.LowHealers()
    local low = {}
    for _, unit in ipairs(Units()) do
        if Get(UnitExists, unit) and not Get(UnitIsUnit, unit, "player")
            and Get(UnitGroupRolesAssigned, unit) == "HEALER"
            and Get(UnitIsConnected, unit) and not Get(UnitIsDeadOrGhost, unit) then
            local cur, max = Get(UnitPower, unit, MANA), Get(UnitPowerMax, unit, MANA)
            local name = Get(UnitName, unit)
            if type(cur) == "number" and type(max) == "number" and max > 0 and cur / max < LOW
                and type(name) == "string" then
                low[#low + 1] = { name = name, percent = math.floor(cur / max * 100) }
            end
        end
    end
    table.sort(low, function(a, b) return a.percent < b.percent end)
    return low
end

function HealerMana.Text(low)
    local parts = {}
    for _, h in ipairs(low) do
        parts[#parts + 1] = ("%s %d%%"):format(h.name, h.percent)
    end
    return (#low == 1 and "Healer low on mana: " or "Healers low on mana: ") .. table.concat(parts, ", ")
end

local function Show(text)
    if RaidNotice_AddMessage and RaidWarningFrame then
        local color = ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.28, b = 0 }
        RaidNotice_AddMessage(RaidWarningFrame, text, color)
    elseif UIErrorsFrame then
        UIErrorsFrame:AddMessage(text, 1, 0.28, 0)
    end
end

function HealerMana.Check()
    if not root.ModuleOn("healerMana") or InCombatLockdown() then
        return
    end
    if not (root.Threat and root.Threat.IsTank()) then
        return
    end
    local low = HealerMana.LowHealers()
    if #low > 0 then
        Show(HealerMana.Text(low))
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
    if not root.db then
        return
    end
    C_Timer.After(SETTLE, function()
        local ok, err = pcall(HealerMana.Check)
        if not ok then
            root.Print("healer mana: " .. tostring(err))
        end
    end)
end)
