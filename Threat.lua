-- Ziri's Toolkit: threat
-- Two small displays for tanks:
--   Target: a box above your target's frame with your threat. While you
--   hold the mob it shows your threat as a percentage of the next person's
--   (101% = barely ahead, 150% = safe); otherwise your share of the
--   tank's threat. Same numbers as the game's own threat percentage.
--   Nameplates: text left of each enemy plate in the fight:
--     "+38%"     yours, 38% ahead of the next person
--     "Slipping" yours, but someone is about to take it
--     "! Misty"  not yours: who it is on
--   Bosses: the game hides threat numbers for bosses from addons, so only
--   "Yours" / "Slipping" / "! name" is shown there.
-- When you are not the tank, nameplates only mark mobs that are on you.

local ADDON_NAME, root = ...

local Threat = {}
root.Threat = Threat

local IsSecret = root.IsSecret
local TICK = 0.25

local COLORS = {
    mine = { 0.45, 0.95, 0.35 },
    slipping = { 1.0, 0.75, 0.2 },
    other = { 1.0, 0.3, 0.3 },
    onyou = { 1.0, 0.3, 0.3 },
}

local plates = {}   -- [nameplate unit] = true while shown
local texts = {}    -- [plate frame] = our frame on it
local box, boxText
local ticker

-------------------------------------------------------------------------------
-- Reading the game
-------------------------------------------------------------------------------

local function Num(v)
    if type(v) == "number" and not IsSecret(v) then
        return v
    end
    return nil
end

-- 0..3 (3 = you hold it securely, 2 = you hold it but are about to lose
-- it, 1 = not yours but above the holder, 0 = not yours), or nil when the
-- unit is not on the mob's threat list or the game hides it.
local function State(unit, mob)
    if type(UnitThreatSituation) ~= "function" then
        return nil
    end
    local ok, s = pcall(UnitThreatSituation, unit, mob)
    return ok and Num(s) or nil
end

local function LeadPercent(mob)
    if type(UnitThreatPercentageOfLead) ~= "function" then
        return nil
    end
    local ok, v = pcall(UnitThreatPercentageOfLead, "player", mob)
    v = ok and Num(v) or nil
    if v and v > 0 then
        return v
    end
    return nil
end

local function Bool(fn, ...)
    if type(fn) ~= "function" then
        return false
    end
    local ok, v = pcall(fn, ...)
    return ok and not IsSecret(v) and v == true
end

-- Everyone whose threat counts: you, your pet, your party and their pets
-- (in a raid: the raid members, without pets, to keep it light).
function Threat.GroupUnits()
    local list = { "player", "pet" }
    if Bool(IsInRaid) then
        for i = 1, 40 do
            list[#list + 1] = "raid" .. i
        end
    else
        for i = 1, 4 do
            list[#list + 1] = "party" .. i
            list[#list + 1] = "partypet" .. i
        end
    end
    return list
end

local function ShortName(unit)
    local ok, name = pcall(UnitName, unit)
    if ok and type(name) == "string" and not IsSecret(name) then
        return name
    end
    return "someone"
end

local TANK_FORMS = { [5] = true, [8] = true, [18] = true } -- bear, dire bear, defensive stance
local RIGHTEOUS_FURY = 25780

-- True when you are playing as a tank: the game says so, your group role
-- is tank, or you are in a tanking form or have Righteous Fury up.
function Threat.IsTank()
    if PlayerUtil and Bool(PlayerUtil.IsPlayerEffectivelyTank) then
        return true
    end
    if type(UnitGroupRolesAssigned) == "function" then
        local ok, role = pcall(UnitGroupRolesAssigned, "player")
        if ok and not IsSecret(role) and role == "TANK" then
            return true
        end
    end
    if type(GetShapeshiftFormID) == "function" then
        local ok, form = pcall(GetShapeshiftFormID)
        form = ok and Num(form) or nil
        if form and TANK_FORMS[form] then
            return true
        end
    end
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if get then
        local ok, aura = pcall(get, RIGHTEOUS_FURY)
        if ok and aura ~= nil and not IsSecret(aura) then
            return true
        end
    end
    return false
end

-- What to write next to one enemy's nameplate: text, kind (or nil).
function Threat.PlateText(mob, tank)
    if not Bool(UnitCanAttack, "player", mob) or Bool(UnitIsDead, mob) then
        return nil
    end
    local mine = State("player", mob)
    if mine and mine >= 2 then
        if not tank then
            return "On you", "onyou"
        end
        if mine == 2 then
            return "Slipping", "slipping"
        end
        local lead = LeadPercent(mob)
        if lead then
            return ("+%d%%"):format(math.floor(lead - 100 + 0.5)), "mine"
        end
        return "Yours", "mine"
    end
    if not tank then
        return nil
    end
    for _, unit in ipairs(Threat.GroupUnits()) do
        if unit ~= "player" and Bool(UnitExists, unit) and not Bool(UnitIsUnit, unit, "player") then
            local s = State(unit, mob)
            if s and s >= 2 then
                return "! " .. ShortName(unit), "other"
            end
        end
    end
    if mine ~= nil then
        -- you are on its list, but it is on someone outside your group
        return "! Not on you", "other"
    end
    return nil
end

-- Text and kind for the box above the target frame (or nil).
function Threat.TargetText(tank)
    if not Bool(UnitExists, "target") or not Bool(UnitCanAttack, "player", "target")
        or Bool(UnitIsDead, "target") then
        return nil
    end
    local state = State("player", "target")
    if state == nil then
        return nil
    end
    local isTanking, display
    if type(UnitDetailedThreatSituation) == "function" then
        local ok, t, _, _, rawPct = pcall(UnitDetailedThreatSituation, "player", "target")
        if ok and not IsSecret(t) then
            isTanking = t == true
            display = Num(rawPct)
        end
    end
    if isTanking == nil then
        isTanking = state >= 2
    end
    if isTanking then
        display = LeadPercent("target")
    end
    if not display or display == 0 then
        -- numbers hidden (boss) or nobody else on the list: words only
        if isTanking then
            return state == 2 and "Slipping" or "Yours", state == 2 and "slipping" or "mine"
        end
        return nil
    end
    local text = ("%d%%"):format(math.floor(display + 0.5))
    if isTanking then
        return text, state == 2 and "slipping" or "mine"
    end
    if tank then
        return "! " .. text, "other"
    end
    -- not the tank: your share of the tank's threat
    if display >= 90 then
        return text, "slipping"
    end
    return text, "plain"
end

-------------------------------------------------------------------------------
-- Display
-------------------------------------------------------------------------------

local function Color(fs, kind)
    local c = COLORS[kind]
    if c then
        fs:SetTextColor(c[1], c[2], c[3])
    else
        fs:SetTextColor(1, 1, 1)
    end
end

local function PlateFrame(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
        return nil
    end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if ok and type(plate) == "table" then
        return plate
    end
    return nil
end

local function TextFor(plate)
    local t = texts[plate]
    if t then
        return t
    end
    t = CreateFrame("Frame", nil, plate)
    t:SetSize(1, 1)
    -- Beside the health bar when the plate has the usual layout.
    local hb
    local uf = rawget(plate, "UnitFrame")
    if type(uf) == "table" then
        hb = rawget(uf, "healthBar")
        local box = rawget(uf, "HealthBarsContainer")
        if type(hb) ~= "table" and type(box) == "table" then
            hb = rawget(box, "healthBar")
        end
    end
    t:SetPoint("RIGHT", type(hb) == "table" and hb or plate, "LEFT", -4, 0)
    t.fs = t:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t.fs:SetPoint("RIGHT", t, "RIGHT")
    if t.fs.SetFont and STANDARD_TEXT_FONT then
        t.fs:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    end
    t:EnableMouse(false)
    texts[plate] = t
    return t
end

local function CreateBox()
    local parent = TargetFrame or UIParent
    box = CreateFrame("Frame", "ZirisToolkitTargetThreat", parent, "BackdropTemplate")
    box:SetSize(58, 20)
    if TargetFrame then
        box:SetPoint("BOTTOM", TargetFrame, "TOP", -28, -33)
    else
        box:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
    box:SetFrameStrata("MEDIUM")
    box:EnableMouse(false)
    if box.SetBackdrop then
        box:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        box:SetBackdropColor(0, 0, 0, 0.75)
    end
    boxText = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    boxText:SetPoint("CENTER")
    if boxText.SetFont and STANDARD_TEXT_FONT then
        boxText:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    end
    box:Hide()
end

local function HideAll()
    for _, t in pairs(texts) do
        t:Hide()
    end
    if box then
        box:Hide()
    end
end

function Threat.Update()
    if not root.ModuleOn("threat") then
        HideAll()
        return
    end
    local tank = Threat.IsTank()

    -- nameplates
    local used = {}
    for unit in pairs(plates) do
        local plate = PlateFrame(unit)
        if plate then
            local text, kind = Threat.PlateText(unit, tank)
            if text then
                local t = TextFor(plate)
                t.fs:SetText(text)
                Color(t.fs, kind)
                t:Show()
                used[plate] = true
            end
        end
    end
    for plate, t in pairs(texts) do
        if not used[plate] then
            t:Hide()
        end
    end

    -- target
    local text, kind = Threat.TargetText(tank)
    if text then
        if not box then
            CreateBox()
        end
        boxText:SetText(text)
        Color(boxText, kind)
        local c = COLORS[kind]
        if box.SetBackdropBorderColor then
            if c then
                box:SetBackdropBorderColor(c[1], c[2], c[3], 1)
            else
                box:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
            end
        end
        box:Show()
    elseif box then
        box:Hide()
    end
end

local function SafeUpdate()
    local ok, err = pcall(Threat.Update)
    if not ok then
        HideAll()
        if not Threat.warned then
            Threat.warned = true
            root.Print("threat: " .. tostring(err))
        end
    end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

-- Runs only while you are in combat; out of combat everything is hidden.
local function Start()
    if not ticker and C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(TICK, SafeUpdate)
    end
    SafeUpdate()
end

local function Stop()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    HideAll()
end

local function InCombat()
    return Bool(UnitAffectingCombat, "player") or Bool(InCombatLockdown)
end

root.OnModuleChanged("threat", function(on)
    if on and InCombat() then
        Start()
    else
        Stop()
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" and type(unit) == "string" then
        plates[unit] = true
    elseif event == "NAME_PLATE_UNIT_REMOVED" and type(unit) == "string" then
        plates[unit] = nil
        local plate = PlateFrame(unit)
        if plate and texts[plate] then
            texts[plate]:Hide()
        end
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        Stop()
        return
    end
    if not root.ModuleOn("threat") then
        return
    end
    if event == "PLAYER_REGEN_DISABLED" or (event == "PLAYER_LOGIN" and InCombat()) then
        Start()
    elseif ticker then
        SafeUpdate()
    end
end)
