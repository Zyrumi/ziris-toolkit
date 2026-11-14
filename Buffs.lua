-- Ziri's Toolkit: buff reminders
-- Out of combat, a row of icons for your own buffs, auras and tracking that
-- are missing (after dying, or when they ran out) or about to run out.
-- Click an icon to cast it on yourself. Nothing shows when all is well.
--
-- Which ones are watched is set per character on the "Buff reminders"
-- settings page; everything your class can cast starts switched on except a
-- few that only some players want (Righteous Fury, Thorns, Shadow
-- Protection).
--
-- Rules:
--   - Hidden in combat (the game hides aura details then anyway), while dead,
--     on a flight path, in a vehicle, and for druids/shamans while shifted.
--   - "Runs out soon" = the last tenth of the buff, at least 30 seconds and
--     at most 5 minutes before it ends.
--   - Groups like paladin auras or mage armors are happy with any one of
--     them; a click casts the one you had last.
--   - Tracking (Find Minerals, Find Herbs, ...) is a minimap switch on this
--     client: a click switches back on what you had, through the minimap.
--   - If the game won't say what buffs you have, nothing is shown (no
--     guessing).

local ADDON_NAME, root = ...

local Buffs = {}
root.Buffs = Buffs

local IsSecret = root.IsSecret

-- spells: what to cast, first one is the default. also: buffs from others
-- that count too (group versions, greater blessings). off: starts switched
-- off. Spell IDs are the classic rank 1 IDs; the English name is a fallback.
local GROUPS = {
    { key = "paladinAura", label = "Paladin aura", class = "PALADIN", spells = {
        { 465, "Devotion Aura" }, { 7294, "Retribution Aura" }, { 19746, "Concentration Aura" },
        { 20218, "Sanctity Aura" }, { 19876, "Shadow Resistance Aura" }, { 19888, "Frost Resistance Aura" },
        { 19891, "Fire Resistance Aura" }, { 32223, "Crusader Aura" } } },
    { key = "blessing", label = "Blessing on yourself", class = "PALADIN", spells = {
        { 19740, "Blessing of Might" }, { 19742, "Blessing of Wisdom" }, { 20217, "Blessing of Kings" },
        { 1038, "Blessing of Salvation" }, { 19977, "Blessing of Light" }, { 20911, "Blessing of Sanctuary" } },
        also = { { 25782, "Greater Blessing of Might" }, { 25894, "Greater Blessing of Wisdom" },
            { 25898, "Greater Blessing of Kings" }, { 25895, "Greater Blessing of Salvation" },
            { 25890, "Greater Blessing of Light" }, { 25899, "Greater Blessing of Sanctuary" } } },
    { key = "righteousFury", label = "Righteous Fury", class = "PALADIN", off = true, spells = {
        { 25780, "Righteous Fury" } } },

    { key = "fortitude", label = "Power Word: Fortitude", class = "PRIEST", spells = {
        { 1243, "Power Word: Fortitude" } }, also = { { 21562, "Prayer of Fortitude" } } },
    { key = "innerFire", label = "Inner Fire", class = "PRIEST", spells = { { 588, "Inner Fire" } } },
    { key = "divineSpirit", label = "Divine Spirit", class = "PRIEST", spells = {
        { 14752, "Divine Spirit" } }, also = { { 27681, "Prayer of Spirit" } } },
    { key = "shadowProtection", label = "Shadow Protection", class = "PRIEST", off = true, spells = {
        { 976, "Shadow Protection" } }, also = { { 27683, "Prayer of Shadow Protection" } } },

    { key = "intellect", label = "Arcane Intellect", class = "MAGE", spells = {
        { 1459, "Arcane Intellect" } }, also = { { 23028, "Arcane Brilliance" } } },
    { key = "mageArmor", label = "Mage armor", class = "MAGE", spells = {
        { 168, "Frost Armor" }, { 7302, "Ice Armor" }, { 6117, "Mage Armor" }, { 30482, "Molten Armor" } } },

    { key = "wild", label = "Mark of the Wild", class = "DRUID", spells = {
        { 1126, "Mark of the Wild" } }, also = { { 21849, "Gift of the Wild" } } },
    { key = "omen", label = "Omen of Clarity", class = "DRUID", spells = { { 16864, "Omen of Clarity" } } },
    { key = "thorns", label = "Thorns", class = "DRUID", off = true, spells = { { 467, "Thorns" } } },

    { key = "shamanShield", label = "Lightning or Water Shield", class = "SHAMAN", spells = {
        { 324, "Lightning Shield" }, { 24398, "Water Shield" } } },

    { key = "warlockArmor", label = "Demon armor", class = "WARLOCK", spells = {
        { 706, "Demon Armor" }, { 687, "Demon Skin" }, { 28176, "Fel Armor" } } },

    { key = "aspect", label = "Hunter aspect", class = "HUNTER", spells = {
        { 13165, "Aspect of the Hawk" }, { 13163, "Aspect of the Monkey" }, { 5118, "Aspect of the Cheetah" },
        { 13159, "Aspect of the Pack" }, { 20043, "Aspect of the Wild" }, { 13161, "Aspect of the Beast" },
        { 34074, "Aspect of the Viper" } } },
    { key = "trueshot", label = "Trueshot Aura", class = "HUNTER", spells = { { 19506, "Trueshot Aura" } } },

    { key = "tracking", label = "Tracking", tracking = true, spells = {
        { 2580, "Find Minerals" }, { 2383, "Find Herbs" }, { 2481, "Find Treasure" }, { 43308, "Find Fish" },
        { 1494, "Track Beasts" }, { 19883, "Track Humanoids" }, { 5225, "Track Humanoids" },
        { 19884, "Track Undead" }, { 19885, "Track Hidden" }, { 19880, "Track Elementals" },
        { 19878, "Track Demons" }, { 19882, "Track Giants" }, { 19879, "Track Dragonkin" },
        { 5502, "Sense Undead" }, { 5500, "Sense Demons" } } },
}
Buffs.GROUPS = GROUPS

local SIZE = 36
local GAP = 8
local TICK = 1
local QUIET_AFTER_LOAD = 3 -- seconds: buffs aren't all there right after a loading screen

local container
local buttons = {}
local page
local needsLayout = false
local quietUntil = 0
local ticking = false

-------------------------------------------------------------------------------
-- Saved settings (per character)
-------------------------------------------------------------------------------

local function DB()
    local db = root.db
    if not db then
        return nil
    end
    if type(db.buffs) ~= "table" then
        db.buffs = {}
    end
    if type(db.buffs.chars) ~= "table" then
        db.buffs.chars = {}
    end
    return db.buffs
end

local function CharData()
    local db, key = DB(), root.CharKey()
    if not db or not key then
        return nil
    end
    local c = db.chars[key]
    if type(c) ~= "table" then
        c = {}
        db.chars[key] = c
    end
    c.on = type(c.on) == "table" and c.on or {}
    c.last = type(c.last) == "table" and c.last or {}
    return c
end

local function GroupOn(g, c)
    c = c or CharData()
    local v = c and c.on[g.key]
    if v == nil then
        return not g.off
    end
    return v == true
end

local function PlayerClass()
    local ok, _, class = pcall(UnitClass, "player")
    if ok and type(class) == "string" and not IsSecret(class) then
        return class
    end
    return nil
end

-- The groups for this character's class, in order.
local function MyGroups()
    local class, list = PlayerClass(), {}
    for _, g in ipairs(GROUPS) do
        if not g.class or g.class == class then
            list[#list + 1] = g
        end
    end
    return list
end
Buffs.MyGroups = MyGroups

-------------------------------------------------------------------------------
-- What you have
-------------------------------------------------------------------------------

-- The spell book, read again only when it changes.
local bookCache
local function Book()
    if not bookCache then
        local book = root.BookNames()
        if next(book) then -- empty right at login: don't keep that
            bookCache = book
        end
        return book
    end
    return bookCache
end

-- Your buffs: [lower case name] = { expires, duration } (0 = never ends).
-- nil when the game won't say.
local function PlayerBuffs()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        return nil
    end
    local ok, result = pcall(function()
        local out = {}
        for i = 1, 40 do
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if IsSecret(a) then
                return nil
            end
            if a == nil then
                return out
            end
            local n, exp, dur = a.name, a.expirationTime, a.duration
            if IsSecret(n) or IsSecret(exp) or IsSecret(dur) then
                return nil
            end
            if type(n) == "string" then
                exp, dur = tonumber(exp) or 0, tonumber(dur) or 0
                local key, old = n:lower(), out[n:lower()]
                -- Two of the same (say, from two people): keep the longer one.
                if not old or old.expires ~= 0 and (exp == 0 or exp > old.expires) then
                    out[key] = { expires = exp, duration = dur }
                end
            end
        end
        return out
    end)
    if ok then
        return result
    end
    return nil
end

-- The minimap's tracking list: [lower case name] = { index, active }.
-- nil when this client has no tracking list or won't say.
local function MinimapTracking()
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo) then
        return nil
    end
    local ok, result = pcall(function()
        local n = C_Minimap.GetNumTrackingTypes()
        if IsSecret(n) or type(n) ~= "number" then
            return nil
        end
        local out = {}
        for i = 1, n do
            local r = { C_Minimap.GetTrackingInfo(i) }
            local name, active
            if type(r[1]) == "table" and not IsSecret(r[1]) then
                name, active = r[1].name, r[1].active
            else
                name, active = r[1], r[3] -- older clients: name, texture, active, ...
            end
            if type(name) == "string" and not IsSecret(name) and not IsSecret(active) then
                out[name:lower()] = { index = i, active = active == true }
            end
        end
        return out
    end)
    if ok then
        return result
    end
    return nil
end

-- "Runs out soon": the last tenth, at least 30 s, at most 5 min.
local function WarnAt(duration)
    return math.max(30, math.min(300, duration * 0.1))
end
Buffs.WarnAt = WarnAt

-- Works out one group. Returns a table:
--   state: "ok", "missing", "soon", "unknown" or "unlearned"
--   left: seconds left (for "soon" and timed "ok")
--   cast: spell name to cast; track: minimap indexes to switch on
--   name: what is (or was) on you, for the tooltip
local function GroupState(g, book, buffs, track, c)
    local known, knownList = {}, {}
    for _, s in ipairs(g.spells) do
        local n = root.KnownSpell(s[1], s[2], book)
        if n and not known[n:lower()] then
            known[n:lower()] = n
            knownList[#knownList + 1] = n
        end
    end
    if #knownList == 0 then
        return { state = "unlearned" }
    end

    -- Every name that counts, as the game spells it here.
    local names = {}
    for _, list in ipairs({ g.spells, g.also or {} }) do
        for _, s in ipairs(list) do
            names[#names + 1] = root.SpellName(s[1]) or s[2]
        end
    end

    if g.tracking then
        local listed, active = {}, {}
        for _, n in ipairs(names) do
            local t = track and track[n:lower()]
            if t and known[n:lower()] then
                listed[n:lower()] = t.index
                if t.active then
                    active[#active + 1] = known[n:lower()]
                end
            elseif buffs and buffs[n:lower()] and known[n:lower()] then
                active[#active + 1] = known[n:lower()]
            end
        end
        if #active > 0 then
            if c then
                c.last[g.key] = active -- what to switch back on later
            end
            return { state = "ok", name = active[1] }
        end
        if not next(listed) and not buffs then
            return { state = "unknown" }
        end
        -- Switch back on what you had last, else the first one you know.
        local want = {}
        local last = c and type(c.last[g.key]) == "table" and c.last[g.key] or {}
        for _, n in ipairs(last) do
            if type(n) == "string" and known[n:lower()] then
                want[#want + 1] = known[n:lower()]
            end
        end
        if #want == 0 then
            want[1] = knownList[1]
        end
        local indexes = {}
        for _, n in ipairs(want) do
            if listed[n:lower()] then
                indexes[#indexes + 1] = listed[n:lower()]
            end
        end
        return { state = "missing", cast = want[1], track = #indexes > 0 and indexes or nil, name = want[1] }
    end

    if not buffs then
        return { state = "unknown" }
    end
    local now = GetTime()
    local best, bestName, forever
    for _, n in ipairs(names) do
        local b = buffs[n:lower()]
        if b then
            if b.expires == 0 or b.duration == 0 then
                forever, bestName = true, n
            elseif not forever and (not best or b.expires - now > best.left) then
                best, bestName = { left = b.expires - now, duration = b.duration }, n
            end
        end
    end
    if bestName and c and known[bestName:lower()] then
        c.last[g.key] = known[bestName:lower()]
    end

    local cast = c and type(c.last[g.key]) == "string" and known[c.last[g.key]:lower()] or knownList[1]
    if forever then
        return { state = "ok", name = bestName, cast = cast }
    end
    if best then
        if best.duration >= 60 and best.left <= WarnAt(best.duration) then
            return { state = "soon", left = best.left, name = bestName, cast = cast }
        end
        return { state = "ok", left = best.left, name = bestName, cast = cast }
    end
    return { state = "missing", cast = cast, name = cast }
end
Buffs.GroupState = GroupState

-- True when reminders make no sense right now.
local function Busy()
    local function Is(fn, ...)
        if type(fn) ~= "function" then
            return false
        end
        local ok, v = pcall(fn, ...)
        return ok and not IsSecret(v) and v and true or false
    end
    if InCombatLockdown() or Is(UnitIsDeadOrGhost, "player") or Is(UnitOnTaxi, "player")
        or Is(UnitInVehicle, "player") or Is(UnitHasVehicleUI, "player") then
        return true
    end
    local class = PlayerClass()
    if (class == "DRUID" or class == "SHAMAN") and type(GetShapeshiftForm) == "function" then
        local ok, form = pcall(GetShapeshiftForm)
        if ok and not IsSecret(form) and type(form) == "number" and form > 0 then
            return true
        end
    end
    return GetTime() < quietUntil
end

-- What needs a reminder right now: list of { group, state table }.
function Buffs.Needed()
    local c = CharData()
    if not c then
        return {}
    end
    local book, buffs, track = Book(), PlayerBuffs(), MinimapTracking()
    local out = {}
    for _, g in ipairs(MyGroups()) do
        local st = GroupState(g, book, buffs, track, c)
        if GroupOn(g, c) and (st.state == "missing" or st.state == "soon") then
            out[#out + 1] = { group = g, st = st }
        end
    end
    return out
end

-------------------------------------------------------------------------------
-- The icons
-------------------------------------------------------------------------------

local function SavePoint()
    local db = DB()
    if not db or not container then
        return
    end
    local point, _, relPoint, x, y = container:GetPoint()
    if point then
        db.point = { point, relPoint, x, y }
    end
end

local function PlacePoint()
    local db = DB()
    local p = db and type(db.point) == "table" and db.point
    container:ClearAllPoints()
    if p and p[1] then
        container:SetPoint(p[1], UIParent, p[2] or p[1], tonumber(p[3]) or 0, tonumber(p[4]) or 0)
    else
        container:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end
end

local function ShowTooltip(self)
    local item = self.item
    if not item then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(item.st.name or item.group.label, 1, 1, 1)
    if item.st.state == "soon" then
        GameTooltip:AddLine("Runs out in " .. root.Clock(item.st.left) .. ".", nil, nil, nil, true)
    else
        GameTooltip:AddLine("Not on you.", nil, nil, nil, true)
    end
    GameTooltip:AddLine("Click to cast it. Shift-drag to move these icons.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

local function CreateButton(i)
    local b = CreateFrame("Button", "ZirisToolkitBuff" .. i, container, "SecureActionButtonTemplate")
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    -- Shift is for moving: a shift-click casts nothing.
    b:SetAttribute("shift-type1", "none")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.2)
    -- Always a word or a time under the icon, never color alone.
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)

    b:SetScript("OnEnter", ShowTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function()
        if IsShiftKeyDown() and not InCombatLockdown() then
            container:StartMoving()
        end
    end)
    b:SetScript("OnDragStop", function()
        container:StopMovingOrSizing()
        SavePoint()
    end)
    -- Tracking is switched on through the minimap, not cast.
    b:HookScript("PostClick", function(self)
        local item = self.item
        if item and item.st.track and not IsShiftKeyDown() and not InCombatLockdown() then
            for _, index in ipairs(item.st.track) do
                pcall(C_Minimap.SetTracking, index, true)
            end
            C_Timer.After(0.3, function() Buffs.Update() end)
        end
    end)
    buttons[i] = b
    return b
end

local function CreateContainer()
    container = CreateFrame("Frame", "ZirisToolkitBuffs", UIParent, "SecureHandlerStateTemplate")
    container:SetSize(SIZE, SIZE)
    container:SetMovable(true)
    container:SetClampedToScreen(true)
    PlacePoint()
    -- The game hides it in combat by itself (these buttons cast spells,
    -- which addons may not show or hide during a fight).
    RegisterStateDriver(container, "visibility", "[combat] hide; show")
end

local function HideFrom(first)
    for i = first, #buttons do
        local b = buttons[i]
        if b.item or b.sig then
            b.item = nil
            b.sig = nil
            b:SetAttribute("type1", nil)
            b:SetAttribute("spell1", nil)
            b:Hide()
        end
    end
end

-- Lays out the icons. Out of combat only: they cast spells.
local function Layout()
    if InCombatLockdown() then
        needsLayout = true
        return
    end
    needsLayout = false
    if not container then
        if not root.ModuleOn("buffs") then
            return
        end
        CreateContainer()
    end
    local list = (root.ModuleOn("buffs") and not Busy()) and Buffs.Needed() or {}
    local width = math.max(SIZE, #list * SIZE + math.max(0, #list - 1) * GAP)
    if container.width ~= width then
        container.width = width
        container:SetWidth(width)
    end
    for i, item in ipairs(list) do
        local b = buttons[i] or CreateButton(i)
        b.item = item
        local st = item.st
        -- This runs every second: only set the button up again when what
        -- it casts changed. The countdown under it is all that ticks.
        local sig = item.group.key .. "|" .. tostring(st.cast) .. "|" .. (st.track and "track" or "cast")
        if b.sig ~= sig then
            b.sig = sig
            b:SetAttribute("unit", "player")
            if st.track then
                b:SetAttribute("type1", nil) -- PostClick switches it on
                b:SetAttribute("spell1", nil)
            else
                b:SetAttribute("type1", "spell")
                b:SetAttribute("spell1", st.cast)
            end
            b.icon:SetTexture(root.SpellIcon(st.cast))
            b:ClearAllPoints()
            b:SetPoint("LEFT", container, "LEFT", (i - 1) * (SIZE + GAP), 0)
            b:Show()
        end
        b.label:SetText(st.state == "soon" and root.Clock(st.left) or "missing")
    end
    HideFrom(#list + 1)
end

function Buffs.Update()
    local ok, err = pcall(Layout)
    if not ok then
        root.Print("buff reminders: " .. tostring(err))
    end
end

-- Once a second while switched on: counts down, and catches buffs running
-- out (the game doesn't always say).
local function Tick()
    if not root.ModuleOn("buffs") then
        ticking = false
        return
    end
    if not InCombatLockdown() then
        Buffs.Update()
    end
    C_Timer.After(TICK, Tick)
end

local function StartTicking()
    if not ticking and root.ModuleOn("buffs") then
        ticking = true
        C_Timer.After(TICK, Tick)
    end
end

root.OnModuleChanged("buffs", function(on)
    Buffs.Update()
    if on then
        StartTicking()
    end
end)

-------------------------------------------------------------------------------
-- Settings page: which ones, per character
-------------------------------------------------------------------------------

local function BuildPage()
    local UI = root.UI
    local panel = CreateFrame("Frame", "ZirisToolkitBuffsOptions", UIParent)
    panel:Hide()
    local content = UI.ScrollArea(panel)
    local x, y = 16, -16
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", x, y)
    title:SetText("Buff reminders")
    y = y - 26
    UI.Note(content, "For this character. An icon shows when one of these is missing or about to run out, out of combat only. Click it to cast.", x, y)
    y = y - 34
    for _, g in ipairs(MyGroups()) do
        local names = {}
        for i, s in ipairs(g.spells) do
            if i <= 4 then
                names[#names + 1] = root.SpellName(s[1]) or s[2]
            end
        end
        local tip = table.concat(names, ", ") .. (#g.spells > 4 and ", ..." or "")
        UI.Check(content, g.label, tip, x, y,
            function() return GroupOn(g) end,
            function(v)
                local c = CharData()
                if c then
                    c.on[g.key] = v
                end
                Buffs.Update()
            end,
            function()
                return GroupState(g, Book(), nil, nil, nil).state ~= "unlearned"
            end)
        y = y - 28
    end
    UI.Note(content, "Greyed out: not learned yet on this character.", x, y - 6)
    content:SetHeight(-y + 40)
    panel:SetScript("OnShow", UI.RefreshAll)
    page = root.RegisterSubPage(panel, "Buff reminders")
end

-------------------------------------------------------------------------------
-- /zt buffs
-------------------------------------------------------------------------------

function Buffs.Report()
    local c = CharData()
    local book, buffs, track = Book(), PlayerBuffs(), MinimapTracking()
    root.Print("buff reminders for this character:")
    if not buffs then
        root.Print("  (the game won't say what buffs you have right now)")
    end
    for _, g in ipairs(MyGroups()) do
        local st = GroupState(g, book, buffs, track, c)
        local text
        if st.state == "unlearned" then
            text = "not learned yet"
        elseif not GroupOn(g, c) then
            text = "switched off"
        elseif st.state == "unknown" then
            text = "can't tell right now"
        elseif st.state == "missing" then
            text = "missing, a click casts " .. tostring(st.cast)
                .. (st.track and " (through the minimap)" or "")
        elseif st.state == "soon" then
            text = st.name .. " runs out in " .. root.Clock(st.left)
        else
            text = "ok: " .. tostring(st.name) .. (st.left and (", " .. root.Clock(st.left) .. " left") or "")
        end
        root.Print("  " .. g.label .. ": " .. text)
    end
    if not root.ModuleOn("buffs") then
        root.Print("  (the Buff reminders part is switched off)")
    end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_ALIVE")
events:RegisterEvent("PLAYER_UNGHOST")
events:RegisterEvent("MINIMAP_UPDATE_TRACKING")
events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
events:RegisterUnitEvent("UNIT_AURA", "player")

local updateQueued = false
local function QueueUpdate()
    if not updateQueued then
        updateQueued = true
        C_Timer.After(0.2, function()
            updateQueued = false
            Buffs.Update()
        end)
    end
end

events:SetScript("OnEvent", function(_, event)
    if not root.db then
        return
    end
    if event == "PLAYER_LOGIN" then
        local ok, err = pcall(BuildPage)
        if not ok then
            root.Print("buff reminders page: " .. tostring(err))
        end
        StartTicking()
        return
    end
    if event == "SPELLS_CHANGED" then
        bookCache = nil
    end
    if event == "PLAYER_ENTERING_WORLD" then
        quietUntil = GetTime() + QUIET_AFTER_LOAD
        C_Timer.After(QUIET_AFTER_LOAD + 0.1, function() Buffs.Update() end)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if needsLayout then
            Buffs.Update()
            return
        end
    end
    if root.ModuleOn("buffs") then
        QueueUpdate()
    end
end)
