-- Ziri's Toolkit: cleanse buttons
-- One button for you and each party member. Clicking a button casts your
-- cleanse spell on that person, no targeting needed. If your class has two
-- (Druid: curse + poison, Shaman: poison + disease), left click casts one
-- and right click the other.
--
-- During combat the game hides what debuffs people have from addons, so the
-- buttons can't always light up. Clicking still works: the game casts the
-- spell, and if there is nothing to remove it just says so.

local ADDON_NAME, root = ...

local Cleanse = {}
root.Cleanse = Cleanse

local UNITS = { "player", "party1", "party2", "party3", "party4" }
local TYPE_ORDER = { "Magic", "Curse", "Poison", "Disease" }
local MOUSE = { "Left click", "Right click", "Middle click" }

-- The game's own debuff colors. A word is always shown too, never color alone.
local TYPE_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
}

-- Cleanse spells by class. ids are the classic spell IDs; the English name is
-- a fallback in case Forever numbers a spell differently. Spells with the
-- same name (Cure Poison, Cure Disease) cast the same way for every class.
-- When two spells remove the same types, the higher "better" wins.
local SPELLS = {
    { ids = { 4987 },      name = "Cleanse",             types = { Magic = true, Poison = true, Disease = true } },
    { ids = { 1152 },      name = "Purify",              types = { Poison = true, Disease = true } },
    { ids = { 475 },       name = "Remove Lesser Curse", types = { Curse = true } },
    { ids = { 2782 },      name = "Remove Curse",        types = { Curse = true } },
    { ids = { 2893 },      name = "Abolish Poison",      types = { Poison = true }, better = 1 },
    { ids = { 8946, 526 }, name = "Cure Poison",         types = { Poison = true } },
    { ids = { 2870, 528 }, name = "Cure Disease",        types = { Disease = true } },
    { ids = { 552 },       name = "Abolish Disease",     types = { Disease = true }, better = 1 },
    { ids = { 527 },       name = "Dispel Magic",        types = { Magic = true } },
}

local IsSecret = root.IsSecret

local strip           -- the movable holder
local buttons = {}    -- [index] = secure unit button
local chosen = {}     -- spells on mouse buttons: { name = cast name, types = {...} }
local covered = {}    -- [type] = true for every type the player can remove
local needsSetup = false -- spells or visibility changed during combat

-------------------------------------------------------------------------------
-- Which spells the player knows
-------------------------------------------------------------------------------

local function SpellName(id)
    local get = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
    if not get then
        return nil
    end
    local ok, name = pcall(get, id)
    if ok and type(name) == "string" and name ~= "" and not IsSecret(name) then
        return name
    end
    return nil
end

local function IsPlayerSpellSafe(id)
    if not IsPlayerSpell then
        return false
    end
    local ok, known = pcall(IsPlayerSpell, id)
    return ok and known == true
end

-- Returns the name to cast for each spell the player knows: the name as it
-- is written in their spell book (casting by name uses the highest rank).
local function KnownSpells()
    local book = {}
    root.ForEachBookSpell(function(info)
        local n = info.name
        if (type(n) ~= "string" or IsSecret(n)) then
            n = SpellName(info.spellID)
        end
        if type(n) == "string" then
            book[n:lower()] = n
        end
    end)
    local known = {}
    for _, s in ipairs(SPELLS) do
        local castName
        for _, id in ipairs(s.ids) do
            local n = SpellName(id)
            if n and book[n:lower()] then
                castName = book[n:lower()]
            elseif n and IsPlayerSpellSafe(id) then
                castName = n
            end
            if castName then
                break
            end
        end
        castName = castName or book[s.name:lower()]
        if castName then
            known[#known + 1] = { name = castName, types = s.types, better = s.better or 0 }
        end
    end
    return known
end

local function CountTypes(types)
    local n = 0
    for _ in pairs(types) do
        n = n + 1
    end
    return n
end

-- Picks at most three spells: for each type (Magic, Curse, Poison, Disease)
-- the spell that removes the most types, the better one on a tie.
local function ChooseSpells()
    local known = KnownSpells()
    local list, used = {}, {}
    covered = {}
    for _, t in ipairs(TYPE_ORDER) do
        local best
        for _, s in ipairs(known) do
            if s.types[t] then
                if not best
                    or CountTypes(s.types) > CountTypes(best.types)
                    or (CountTypes(s.types) == CountTypes(best.types) and s.better > best.better) then
                    best = s
                end
            end
        end
        if best then
            covered[t] = true
            if not used[best.name] and #list < 3 then
                used[best.name] = true
                list[#list + 1] = best
            end
        end
    end
    return list
end

-------------------------------------------------------------------------------
-- Reading debuffs
-------------------------------------------------------------------------------

-- Returns "yes", "no" or "unknown", plus the debuff type when it is known.
local function DebuffState(unit)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        return "unknown"
    end
    local ok, exists = pcall(UnitExists, unit)
    if not ok or IsSecret(exists) or not exists then
        return "no"
    end

    -- First: every harmful aura, with its type. Works when auras are readable.
    local okScan, state, kind = pcall(function()
        for i = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL")
            if IsSecret(aura) then
                return "unknown"
            end
            if aura == nil then
                return "no"
            end
            local t = aura.dispelName
            if IsSecret(t) then
                return "unknown"
            end
            if t and covered[t] then
                return "yes", t
            end
        end
        return "no"
    end)
    if okScan and state ~= "unknown" then
        return state, kind
    end

    -- Second: let the game filter for "debuffs I can remove". Even when the
    -- details are hidden, that something was found may still be readable.
    local okProbe, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, 1, "HARMFUL|RAID_PLAYER_DISPELLABLE")
    if okProbe and not IsSecret(aura) then
        if aura == nil then
            return "no"
        end
        local t = aura.dispelName
        if IsSecret(t) or not TYPE_COLORS[t] then
            t = nil
        end
        return "yes", t
    end
    return "unknown"
end

-------------------------------------------------------------------------------
-- Buttons
-------------------------------------------------------------------------------

local WIDTH, HEIGHT, GAP = 132, 24, 2

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Cleanse", 1, 1, 1)
    if #chosen == 0 then
        GameTooltip:AddLine("You don't know a cleanse spell yet.", nil, nil, nil, true)
    end
    for i, s in ipairs(chosen) do
        local types = {}
        for _, t in ipairs(TYPE_ORDER) do
            if s.types[t] then
                types[#types + 1] = t:lower()
            end
        end
        GameTooltip:AddDoubleLine(MOUSE[i] .. ": " .. s.name, table.concat(types, ", "), 1, 1, 1, 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

local function UpdateButton(b)
    local unit = b.unit
    local okName, name = pcall(UnitName, unit)
    -- A hidden (secret) name can't be tested, but SetText still shows it.
    if okName and (IsSecret(name) or name) then
        b.nameText:SetText(name)
    else
        b.nameText:SetText("")
    end

    local state, kind = DebuffState(unit)
    if state == "yes" then
        local c = TYPE_COLORS[kind] or { 1, 0.85, 0.3 }
        b.border:SetColorTexture(c[1], c[2], c[3], 1)
        b.border:Show()
        b.statusText:SetText(kind or "Debuff")
        b.statusText:SetTextColor(1, 1, 1)
    else
        b.border:Hide()
        b.statusText:SetText("")
    end
end

local function UpdateAll()
    for _, b in ipairs(buttons) do
        if b:IsVisible() then
            pcall(UpdateButton, b)
        end
    end
end
Cleanse.UpdateAll = UpdateAll

local function CreateButton(index, unit)
    local b = CreateFrame("Button", "ZirisToolkitCleanse" .. index, strip, "SecureUnitButtonTemplate")
    b:SetSize(WIDTH, HEIGHT)
    b:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, -16 - (index - 1) * (HEIGHT + GAP))
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("unit", unit)
    b.unit = unit

    -- Colored frame shown when the person has something you can remove.
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.border:Hide()
    local bg = b:CreateTexture(nil, "BORDER")
    bg:SetPoint("TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", -2, 2)
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.85)

    b.nameText = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.nameText:SetPoint("LEFT", 6, 0)
    b.nameText:SetPoint("RIGHT", -52, 0)
    b.nameText:SetJustifyH("LEFT")
    b.nameText:SetWordWrap(false)
    b.statusText = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.statusText:SetPoint("RIGHT", -6, 0)
    b.statusText:SetJustifyH("RIGHT")

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 2, -2)
    hl:SetPoint("BOTTOMRIGHT", -2, 2)
    hl:SetColorTexture(1, 1, 1, 0.12)

    b:SetScript("OnEnter", ShowTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnShow", function(self) pcall(UpdateButton, self) end)

    -- Each button listens only to its own person's auras.
    local watcher = CreateFrame("Frame")
    watcher:RegisterUnitEvent("UNIT_AURA", unit)
    if unit ~= "player" then
        watcher:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    end
    watcher:SetScript("OnEvent", function()
        if b:IsVisible() then
            pcall(UpdateButton, b)
        end
    end)
    return b
end

local function SavePosition()
    local point, _, relativePoint, x, y = strip:GetPoint(1)
    if point then
        root.db.cleanse.point = { point, relativePoint, math.floor(x + 0.5), math.floor(y + 0.5) }
    end
end

local function CreateStrip()
    strip = CreateFrame("Frame", "ZirisToolkitCleanseFrame", UIParent)
    strip:SetSize(WIDTH, 16 + #UNITS * (HEIGHT + GAP))
    strip:SetClampedToScreen(true)
    strip:SetMovable(true)
    local p = root.db.cleanse.point
    if type(p) == "table" and p[1] then
        strip:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        strip:SetPoint("LEFT", UIParent, "LEFT", 260, 40)
    end

    -- Title bar: shows what this is, and is where you drag it from.
    local handle = CreateFrame("Frame", nil, strip)
    handle:SetPoint("TOPLEFT")
    handle:SetSize(WIDTH, 14)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    local title = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", 2, 0)
    title:SetText("Cleanse")
    strip.title = title
    handle:SetScript("OnDragStart", function()
        if not root.db.cleanse.locked and not InCombatLockdown() then
            strip:StartMoving()
        end
    end)
    handle:SetScript("OnDragStop", function()
        strip:StopMovingOrSizing()
        SavePosition()
    end)
    handle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Cleanse buttons", 1, 1, 1)
        if root.db.cleanse.locked then
            GameTooltip:AddLine("Locked. Unlock it in the Ziri's Toolkit settings (/zt) to move it.", nil, nil, nil, true)
        else
            GameTooltip:AddLine("Drag here to move. Lock it in the Ziri's Toolkit settings (/zt).", nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function() GameTooltip:Hide() end)

    for i, unit in ipairs(UNITS) do
        buttons[i] = CreateButton(i, unit)
    end
end

-------------------------------------------------------------------------------
-- Setup (only possible out of combat: these buttons cast spells)
-------------------------------------------------------------------------------

local function InGroup()
    return IsInGroup and IsInGroup() or false
end

local function Setup()
    if InCombatLockdown() then
        needsSetup = true
        return
    end
    needsSetup = false
    if not strip then
        CreateStrip()
    end

    chosen = ChooseSpells()
    for _, b in ipairs(buttons) do
        for i = 1, 3 do
            local s = chosen[i]
            b:SetAttribute("type" .. i, s and "spell" or nil)
            b:SetAttribute("spell" .. i, s and s.name or nil)
        end
        -- Without a second spell, right click does nothing (no unit menu).
        if not chosen[2] then
            b:SetAttribute("type2", nil)
        end
    end

    local show = root.ModuleOn("cleanse") and #chosen > 0
        and (InGroup() or root.db.cleanse.showSolo)
    if show then
        for _, b in ipairs(buttons) do
            if b.unit == "player" or InGroup() then
                RegisterUnitWatch(b)
            else
                UnregisterUnitWatch(b)
                b:Hide()
            end
        end
        strip:Show()
    else
        for _, b in ipairs(buttons) do
            UnregisterUnitWatch(b)
            b:Hide()
        end
        strip:Hide()
    end
    strip.title:SetText(root.db.cleanse.locked and "Cleanse" or "Cleanse (drag to move)")
    UpdateAll()
end

function Cleanse.Refresh()
    local ok, err = pcall(Setup)
    if not ok then
        root.Print("cleanse buttons: " .. tostring(err))
    end
end

root.OnModuleChanged("cleanse", function()
    Cleanse.Refresh()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")

local setupQueued = false

events:SetScript("OnEvent", function(_, event)
    if not root.db then
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        UpdateAll()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" and not needsSetup then
        UpdateAll() -- debuffs can be read again
        return
    end
    -- Spell book and group changes come in bursts; set up once.
    if not setupQueued then
        setupQueued = true
        C_Timer.After(0.2, function()
            setupQueued = false
            Cleanse.Refresh()
        end)
    end
end)
