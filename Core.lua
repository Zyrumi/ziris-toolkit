-- Ziri's Toolkit: core
-- Small quality of life parts in one addon. Each part can be switched on or
-- off on the settings page (Esc > Options > AddOns > Ziri's Toolkit).
--
-- Parts:
--   Loot Highlight  (LootHighlight\*.lua, settings in LootHighlightDB)
--   Fresh Ranks     (FreshRanks.lua)
--   Cleanse buttons (Cleanse.lua)
--   Thanks          (Thanks.lua)
--   Undress         (Undress.lua)
--   Quiver window   (Quiver.lua, quiver out of the combined bag)
--   Boat times      (Boats.lua, uses the DockWatch addon's public API)
--   Friends list    (Friends.lua)
--   Instance limit  (Instances.lua)
--   Rested XP       (Rested.lua)
--   Buff reminders  (Buffs.lua)
--   Flight timer    (Flights.lua)
--   Threat          (Threat.lua)
--   Photo mode      (Photo.lua, more hidden with the game's Toggle UI key)
--   AFK screen      (AfkScreen.lua, uses photo mode's hiding)
--   Minimap button  (MinimapButton.lua, opens these settings)
--   Console settings page (Console.lua, the game's own settings, no switch)

local ADDON_NAME, root = ...

root.TITLE = "Ziri's Toolkit"
local PREFIX = "|cff66ccffZiri's Toolkit:|r "

local DEFAULTS = {
    modules = {
        freshRanks = true,
        cleanse = true,
        thanks = true,
        undress = true,
        quiver = true,
        boats = true,
        friends = true,
        instances = true,
        rested = true,
        buffs = true,
        flights = true,
        threat = true,
        disconnects = true,
        healerMana = true,
        photo = true,
        afk = true,
    },
}

function root.Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
    end
end

-- Midnight-era clients can hand addons "secret" values that may not be
-- compared or read. Treat those as unknown.
function root.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- "Ziri Shortfuse": the character's name (and surname, on Forever).
function root.CharKey()
    local ok, name, second = pcall(UnitName, "player")
    if not ok or root.IsSecret(name) or type(name) ~= "string" then
        return nil
    end
    if type(second) == "string" and second ~= "" and not root.IsSecret(second) then
        return name .. " " .. second
    end
    return name
end

-- 0:42, 12:30, 1:05:00
function root.Clock(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
    if h > 0 then
        return ("%d:%02d:%02d"):format(h, m, s)
    end
    return ("%d:%02d"):format(m, s)
end

-------------------------------------------------------------------------------
-- The old separate addons
-------------------------------------------------------------------------------
-- Loot Highlight and Fresh Ranks used to be their own addons. If one of them
-- is still installed and on, that part of the toolkit stays out of the way
-- so the two copies don't fight. (They load before us: A-Z folder order.)

local function OldAddonActive(folder)
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if loaded then
        local ok, on = pcall(loaded, folder)
        if ok and on then
            return true
        end
    end
    return false
end

root.AddonLoaded = OldAddonActive

root.skip = {
    lootHighlight = OldAddonActive("LootHighlight"),
    freshRanks = OldAddonActive("FreshRanks"),
}

-- Zyrumi's Libram has the same cleanse buttons, threat icons and healer
-- mana warning for paladins. On a paladin with the Libram loaded and that
-- part switched on there, the toolkit leaves the part to the Libram so
-- nothing shows twice. (The Libram loads after us, so this is asked at
-- run time, never while the files load.)
local LIBRAM_PARTS = { cleanse = true, threat = true, healerMana = true }
local libramLoaded, playerClass

local function IsPaladin()
    if not playerClass then
        local ok, _, class = pcall(UnitClass, "player")
        if ok and type(class) == "string" and not root.IsSecret(class) then
            playerClass = class
        end
    end
    return playerClass == "PALADIN"
end

function root.LibramHas(key)
    if not LIBRAM_PARTS[key] then
        return false
    end
    libramLoaded = libramLoaded or OldAddonActive("ZyrumisLibram")
    if not libramLoaded or not IsPaladin() then
        return false
    end
    local db = ZyrumisLibramDB
    local features = type(db) == "table" and db.features
    return type(features) ~= "table" or features[key] ~= false
end

-------------------------------------------------------------------------------
-- Saved settings
-------------------------------------------------------------------------------

local function MergeDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            MergeDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- True if a part is switched on. Loot Highlight keeps its own on/off switch
-- in its own settings, so it is not listed here.
function root.ModuleOn(key)
    if root.skip[key] or root.LibramHas(key) then
        return false
    end
    local db = root.db
    if not db then
        return DEFAULTS.modules[key] == true
    end
    return db.modules[key] == true
end

-- Parts register here to hear when they are switched on or off.
root.moduleListeners = {}
function root.OnModuleChanged(key, fn)
    root.moduleListeners[key] = fn
end

function root.SetModule(key, on)
    root.db.modules[key] = on and true or false
    local fn = root.moduleListeners[key]
    if fn then
        local ok, err = pcall(fn, on)
        if not ok then
            root.Print("something went wrong: " .. tostring(err))
        end
    end
end

-------------------------------------------------------------------------------
-- Spell book (shared by the parts that need to know your spells)
-------------------------------------------------------------------------------

local PLAYER_BANK = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
local SPELL_ITEM = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1

-- The spell's name in the player's language, or nil.
function root.SpellName(id)
    local get = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
    if not get then
        return nil
    end
    local ok, name = pcall(get, id)
    if ok and type(name) == "string" and name ~= "" and not root.IsSecret(name) then
        return name
    end
    return nil
end

function root.IsPlayerSpell(id)
    if not IsPlayerSpell then
        return false
    end
    local ok, known = pcall(IsPlayerSpell, id)
    return ok and known == true
end

function root.SpellIcon(name)
    local get = C_Spell and C_Spell.GetSpellTexture
    if get and name then
        local ok, icon = pcall(get, name)
        if ok and icon and not root.IsSecret(icon) then
            return icon
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Calls fn(info) for every spell in the player's spell book.
function root.ForEachBookSpell(fn)
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then
        return
    end
    local ok, count = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    if not ok or type(count) ~= "number" then
        return
    end
    for line = 1, count do
        local okLine, li = pcall(C_SpellBook.GetSpellBookSkillLineInfo, line)
        if okLine and type(li) == "table" and li.itemIndexOffset and li.numSpellBookItems then
            for slot = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                local okItem, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, PLAYER_BANK)
                if okItem and type(info) == "table" and info.itemType == SPELL_ITEM
                    and type(info.spellID) == "number" then
                    fn(info)
                end
            end
        end
    end
end

-- Every spell in the spell book: [lower case name] = name as written there.
-- Casting by that name uses the highest rank.
function root.BookNames()
    local book = {}
    root.ForEachBookSpell(function(info)
        local n = info.name
        if type(n) ~= "string" or root.IsSecret(n) then
            n = root.SpellName(info.spellID)
        end
        if type(n) == "string" then
            book[n:lower()] = n
        end
    end)
    return book
end

-- The name to cast if the player knows the spell, else nil. id is the
-- classic spell ID; fallback is its English name, used if this client
-- numbers the spell differently.
function root.KnownSpell(id, fallback, book)
    book = book or root.BookNames()
    local n = root.SpellName(id)
    if n and book[n:lower()] then
        return book[n:lower()]
    end
    if n and root.IsPlayerSpell(id) then
        return n
    end
    if fallback and book[fallback:lower()] then
        return book[fallback:lower()]
    end
    return nil
end

-------------------------------------------------------------------------------
-- Settings page
-------------------------------------------------------------------------------

local refreshers = {}

local function RefreshAll()
    for _, fn in ipairs(refreshers) do
        pcall(fn)
    end
end
root.RefreshOptions = RefreshAll

local function AddTooltip(frame, title, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        if text then
            GameTooltip:AddLine(text, nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function Note(parent, text, x, y, width)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(width or 520)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

-- get() returns the value; set(v) stores it. enabled() (optional) greys the
-- box out when it returns false.
local function Check(parent, label, tip, x, y, get, set, enabled)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", x, y)
    for _, key in ipairs({ "Text", "text" }) do
        if type(cb[key]) == "table" and cb[key].SetText then
            cb[key]:SetText("")
        end
    end
    local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetText(label)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        RefreshAll()
    end)
    AddTooltip(cb, label, tip)
    refreshers[#refreshers + 1] = function()
        cb:SetChecked(get() and true or false)
        local on = (not enabled) or enabled()
        cb:SetEnabled(on)
        fs:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
    end
    return cb
end

local OLD_NOTE = "The separate %s addon is still installed, so this part is left to it. Remove the old addon to use this one."
local LIBRAM_NOTE = "Zyrumi's Libram does this on your paladin, so the toolkit leaves it to the Libram. Switch it off in the Libram to use this one."

-- A note under a part the Libram can take over on a paladin.
local function PartNote(parent, key, text, x, y)
    local fs = Note(parent, text, x, y)
    refreshers[#refreshers + 1] = function()
        fs:SetText(root.LibramHas(key) and LIBRAM_NOTE or text)
    end
    return fs
end

local function NotLibrams(key)
    return function() return not root.LibramHas(key) end
end

-- Puts a settings page in a scroll frame so it fits however many parts
-- there are. Returns the frame to put the page's contents on.
local SCROLL_TEMPLATES = { "ScrollFrameTemplate", "UIPanelScrollFrameTemplate" }

local function ScrollArea(panel)
    local scroll
    for _, template in ipairs(SCROLL_TEMPLATES) do
        local ok, frame = pcall(CreateFrame, "ScrollFrame", nil, panel, template)
        if ok and frame then
            scroll = frame
            break
        end
    end
    local hasBar = scroll ~= nil
    if not scroll then
        -- No template: scroll with the mouse wheel only.
        scroll = CreateFrame("ScrollFrame", nil, panel)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local range = self:GetVerticalScrollRange() or 0
            local v = (self:GetVerticalScroll() or 0) - delta * 40
            self:SetVerticalScroll(math.max(0, math.min(range, v)))
        end)
    end
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", hasBar and -28 or 0, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(580, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnSizeChanged", function(_, width)
        if type(width) == "number" and width > 0 then
            content:SetWidth(width)
        end
    end)
    return content
end

-- Plain slider built from game textures (no template needed).
-- opts (all optional):
--   format(v)  text after the label, default v .. unit
--   unit       added after the value when there is no format
--   refreshers list to register the refresh function in (default: Core's)
--   after()    called after set(v)
local function Slider(parent, label, tip, x, y, minV, maxV, step, get, set, opts)
    opts = opts or {}
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("TOPLEFT", x + 4, y)
    local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetSize(280, 17)
    s:SetPoint("TOPLEFT", x + 4, y - 18)
    s:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)

    local loading = false
    local function ShowValue(v)
        local text = opts.format and opts.format(v) or (tostring(v) .. (opts.unit or ""))
        title:SetText(label .. ": " .. text)
    end
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        ShowValue(v)
        local current = get()
        if not loading and (type(current) ~= "number" or math.abs(v - current) > step / 1000) then
            set(v)
            if opts.after then
                opts.after()
            end
        end
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * step)
    end)
    AddTooltip(s, label, tip)
    local list = opts.refreshers or refreshers
    list[#list + 1] = function()
        local v = get()
        if type(v) ~= "number" then
            return
        end
        loading = true
        s:SetValue(v)
        ShowValue(v)
        loading = false
    end
    return s, title
end

local function Button(parent, text, tip, x, y, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 140, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", function()
        onClick()
        RefreshAll()
    end)
    AddTooltip(b, text, tip)
    return b
end

local function Heading(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

-- A label with a row of buttons, one per option; the chosen one has a tick.
-- options: { { value = ..., text = "...", tip = "..." (optional) }, ... }
-- Rows wrap after maxWidth. Returns how far down it reaches (pixels).
local function Choice(parent, label, tip, x, y, options, get, set, enabled, maxWidth)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("TOPLEFT", x + 4, y)
    title:SetText(label)
    maxWidth = maxWidth or 540
    local buttons = {}
    local bx, by = 0, y - 18
    for i, opt in ipairs(options) do
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        local w = opt.width or 128
        if bx > 0 and bx + w > maxWidth then
            bx, by = 0, by - 26
        end
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", x + 4 + bx, by)
        bx = bx + w + 4
        b:SetText(opt.text)
        local mark = b:CreateTexture(nil, "OVERLAY")
        mark:SetSize(16, 16)
        mark:SetPoint("LEFT", 3, 0)
        mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        b.mark = mark
        b:SetScript("OnClick", function()
            set(opt.value)
            RefreshAll()
        end)
        AddTooltip(b, label .. ": " .. opt.text, opt.tip or tip)
        buttons[i] = b
    end
    refreshers[#refreshers + 1] = function()
        local v = get()
        local on = (not enabled) or enabled()
        for i, b in ipairs(buttons) do
            local chosen = options[i].value == v
            b.mark:SetShown(chosen)
            if chosen then b:LockHighlight() else b:UnlockHighlight() end
            b:SetEnabled(on)
        end
    end
    return y - by + 24
end

-- For parts that build their own settings page.
root.UI = {
    Check = Check, Note = Note, ScrollArea = ScrollArea, RefreshAll = RefreshAll,
    Slider = Slider, Button = Button, Heading = Heading, AddTooltip = AddTooltip,
    Choice = Choice,
}

local function BuildMainPage()
    local panel = CreateFrame("Frame", "ZirisToolkitOptions", UIParent)
    panel:Hide()
    local page = ScrollArea(panel)
    local x, y = 16, -16

    local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", x, y)
    title:SetText(root.TITLE)
    local version = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, 0)
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local okV, v = pcall(meta, ADDON_NAME, "Version")
    version:SetText(okV and v and ("version " .. v) or "")
    y = y - 26
    Note(page, "Switch each part on or off. Changes apply at once.", x, y)
    y = y - 28

    -- Minimap button
    Check(page, "Minimap button",
        "Ziri's face on the edge of the minimap. Click it to open these settings, drag it to move it.",
        x, y,
        function() return root.MinimapButton and root.MinimapButton.IsShown() end,
        function(v)
            if root.MinimapButton then
                root.MinimapButton.SetShown(v)
            end
        end)
    y = y - 36

    -- Loot Highlight
    Check(page, "Loot Highlight",
        "Points out nearby herbs, ore, chests, quest objects and corpses with loot. Its own settings are on the Loot Highlight page under Ziri's Toolkit.",
        x, y,
        function() return root.LH and root.LH.db and root.LH.db.enabled end,
        function(v)
            if root.LH and root.LH.SetEnabled then
                root.LH.SetEnabled(v)
            end
        end,
        function() return root.LH ~= nil and root.LH.db ~= nil end)
    y = y - 26
    if root.skip.lootHighlight then
        Note(page, OLD_NOTE:format("Loot Highlight"), x + 30, y)
    else
        Note(page, "Points out nearby herbs, ore, chests and loot. More settings on its own page.", x + 30, y)
    end
    y = y - 30

    -- Fresh Ranks
    Check(page, "Fresh Ranks",
        "When you learn a new rank, your action buttons with the old rank get the new one. New spells go into an empty slot.",
        x, y,
        function() return root.ModuleOn("freshRanks") end,
        function(v) root.SetModule("freshRanks", v) end,
        function() return not root.skip.freshRanks end)
    y = y - 26
    if root.skip.freshRanks then
        Note(page, OLD_NOTE:format("Fresh Ranks"), x + 30, y)
    else
        Note(page, "Keeps your action bars up to date when you learn spells.", x + 30, y)
    end
    y = y - 30

    -- Cleanse buttons
    Check(page, "Cleanse buttons",
        "A small button beside your own frame and each party member's frame. Click it to cast your cleanse spell on that person, no targeting needed.",
        x, y,
        function() return root.ModuleOn("cleanse") end,
        function(v) root.SetModule("cleanse", v) end,
        NotLibrams("cleanse"))
    y = y - 26
    PartNote(page, "cleanse", "Click the button beside a frame to cleanse that person. Left and right click use different spells if your class has two.", x + 30, y)
    y = y - 34

    -- Thanks
    Check(page, "Thank people who buff you",
        "Does the /thank emote at players who give you a buff out in the world.",
        x, y,
        function() return root.ModuleOn("thanks") end,
        function(v) root.SetModule("thanks", v) end)
    y = y - 26
    Note(page, "Out in the world only: party and raid members are never thanked, and each person at most once a minute. /zt thanks shows the last buffs and why.", x + 30, y)
    y = y - 34

    -- Undress
    Check(page, "Undress button",
        "A button beside the character window (C) that puts your gear into your bags and back on again.",
        x, y,
        function() return root.ModuleOn("undress") end,
        function(v) root.SetModule("undress", v) end)
    y = y - 26
    Note(page, "For corpse runs: gear in your bags loses no durability when you die. Rings, necklace and trinkets stay on.", x + 30, y)
    y = y - 34

    -- Quiver window
    Check(page, "Quiver in its own window",
        "With the combined bag (one big bag window), your quiver or ammo pouch opens as its own bag window beside it instead of being mixed in with your other bags.",
        x, y,
        function() return root.ModuleOn("quiver") end,
        function(v) root.SetModule("quiver", v) end)
    y = y - 26
    Note(page, "Only with the combined bag: single bags show the quiver on its own already. Takes effect the next time you open your bags.", x + 30, y)
    y = y - 34

    -- Boat times
    Check(page, "Boat times",
        "At a dock: when each boat or zeppelin from there leaves. On board: when you arrive. Shown at the top of the screen, only then.",
        x, y,
        function() return root.ModuleOn("boats") end,
        function(v) root.SetModule("boats", v) end)
    y = y - 26
    local boatsNote = Note(page, "", x + 30, y)
    refreshers[#refreshers + 1] = function()
        if root.Boats and root.Boats.HasDockWatch() then
            boatsNote:SetText("Times come from DockWatch. You can switch off DockWatch's own map and window in its options (/dw options). /zt boats shows what it sees where you stand.")
        else
            boatsNote:SetText("Needs the DockWatch addon, which learns and shares the times. Install it to see boat times.")
        end
    end
    y = y - 34

    -- Friends list
    Check(page, "Tidy friends list",
        "Battle.net friends who are online somewhere you can't join them (another rule set, another WoW version, another game) move to the bottom of your friends list. Nobody is removed.",
        x, y,
        function() return root.ModuleOn("friends") end,
        function(v) root.SetModule("friends", v) end)
    y = y - 26
    Note(page, "Uses the game's own check behind the invite button. Favorites stay on top. Type /zt friends to see why someone moved.", x + 30, y)
    y = y - 34

    -- Instance limit
    Check(page, "Instance limit",
        "Counts the new dungeon and raid instances you enter, on all your characters. The game allows 5 an hour and 30 a day.",
        x, y,
        function() return root.ModuleOn("instances") end,
        function(v) root.SetModule("instances", v) end)
    y = y - 26
    Note(page, "Says in chat which number each instance was, and shows when the next is allowed while you are at the limit. /zt instances lists them.", x + 30, y)
    y = y - 34

    -- Rested XP
    Check(page, "Rested XP per character",
        "Remembers each character's rested XP and works out how much more they have rested since you logged out.",
        x, y,
        function() return root.ModuleOn("rested") end,
        function(v) root.SetModule("rested", v) end)
    y = y - 26
    Note(page, "Type /zt rested to see every character, most rested first. Log in on each once to add them.", x + 30, y)
    y = y - 34

    -- Buff reminders
    Check(page, "Buff reminders",
        "Out of combat, shows an icon for each of your own buffs, auras and tracking that is missing or about to run out. Click the icon to cast it.",
        x, y,
        function() return root.ModuleOn("buffs") end,
        function(v) root.SetModule("buffs", v) end)
    y = y - 26
    Note(page, "Pick which ones on the Buff reminders page under Ziri's Toolkit. Shift-drag an icon to move them. /zt buffs lists them.", x + 30, y)
    y = y - 34

    -- Flight timer
    Check(page, "Flight timer",
        "While you are on a flight path, a bar at the top of the screen shows where you are going and how long is left.",
        x, y,
        function() return root.ModuleOn("flights") end,
        function(v) root.SetModule("flights", v) end)
    y = y - 26
    Note(page, "Each route is timed the first time you fly it all the way, then known on all your characters. /zt flights lists them.", x + 30, y)
    y = y - 34

    -- Threat
    Check(page, "Threat for tanks",
        "In combat: a small icon above each enemy nameplate's name and above your target's name bar, showing if the mob is yours, slipping, or on someone else (and who). Nothing shows when you are solo and the mob is on you.",
        x, y,
        function() return root.ModuleOn("threat") end,
        function(v) root.SetModule("threat", v) end,
        NotLibrams("threat"))
    y = y - 26
    PartNote(page, "threat", "Shield = yours, half shield = slipping, red warning = on someone else (name beside it). Hover the icon above your target's name for numbers. Needs enemy nameplates on (V).", x + 30, y)
    y = y - 44

    -- Healer mana after combat
    Check(page, "Healer mana after combat",
        "When a fight ends and you are tanking, a warning in the middle of the screen if a healer is under 20% mana.",
        x, y,
        function() return root.ModuleOn("healerMana") end,
        function(v) root.SetModule("healerMana", v) end,
        NotLibrams("healerMana"))
    y = y - 26
    PartNote(page, "healerMana", "Only people with the healer group role count. Tanking means a tank role, form or stance, or Righteous Fury. /zt healers shows what it sees.", x + 30, y)
    y = y - 34

    -- Disconnects
    Check(page, "Disconnect tracker",
        "In a group: chat says when someone disconnects and when they are back, and a line at the top of the screen counts how long they have been gone.",
        x, y,
        function() return root.ModuleOn("disconnects") end,
        function(v) root.SetModule("disconnects", v) end)
    y = y - 26
    Note(page, "Someone already offline when you join or reload shows as \"offline\" without a time: the game doesn't say since when.", x + 30, y)
    y = y - 44

    -- Photo mode
    Check(page, "Photo mode",
        "When you hide the interface with the game's Toggle UI key (Alt+Z), names over heads, nameplates, chat bubbles and damage numbers go too. Press it again and they are back.",
        x, y,
        function() return root.ModuleOn("photo") end,
        function(v) root.SetModule("photo", v) end)
    y = y - 26
    Note(page, "Pick what to hide on the Photo mode page under Ziri's Toolkit. /zt photo shows what it changes.", x + 30, y)
    y = y - 34

    -- AFK screen
    Check(page, "AFK screen",
        "When you go AFK, the interface hides, the camera circles your character and bars show who you are and how long you have been away. Moving or a fight brings everything back.",
        x, y,
        function() return root.ModuleOn("afk") end,
        function(v) root.SetModule("afk", v) end)
    y = y - 26
    Note(page, "Pick the layout, your character's pose and the picture on the AFK screen page under Ziri's Toolkit. Type /afk to try it.", x + 30, y)
    y = y - 34

    page:SetHeight(-y + 16)

    panel:SetScript("OnShow", RefreshAll)
    return panel
end

local mainCategory

-- Returns the main settings category, creating it the first time.
function root.MainCategory()
    if mainCategory then
        return mainCategory
    end
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return nil
    end
    local panel = BuildMainPage()
    mainCategory = Settings.RegisterCanvasLayoutCategory(panel, root.TITLE)
    Settings.RegisterAddOnCategory(mainCategory)
    root.mainPanel = panel
    return mainCategory
end

-- Puts a part's own settings page under Ziri's Toolkit.
function root.RegisterSubPage(panel, name)
    local parent = root.MainCategory()
    if parent and Settings.RegisterCanvasLayoutSubcategory then
        local ok, sub = pcall(Settings.RegisterCanvasLayoutSubcategory, parent, panel, name)
        if ok and sub then
            return sub
        end
    end
    -- Fallback: its own entry in the AddOns list.
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, name)
        Settings.RegisterAddOnCategory(category)
        return category
    end
    return nil
end

local openAfterCombat = false

function root.OpenOptions()
    local category = root.MainCategory()
    if not category or not Settings.OpenToCategory then
        return false
    end
    if InCombatLockdown() then
        openAfterCombat = true
        root.Print("the settings open when this fight is over")
        return true
    end
    Settings.OpenToCategory(category:GetID())
    return true
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            if type(ZirisToolkitDB) ~= "table" then
                ZirisToolkitDB = {}
            end
            root.db = MergeDefaults(DEFAULTS, ZirisToolkitDB)
        end
    elseif event == "PLAYER_LOGIN" then
        pcall(root.MainCategory)
        local old = {}
        if root.skip.lootHighlight then old[#old + 1] = "Loot Highlight" end
        if root.skip.freshRanks then old[#old + 1] = "Fresh Ranks" end
        if #old > 0 then
            root.Print("the separate " .. table.concat(old, " and ")
                .. (#old == 1 and " addon is" or " addons are")
                .. " still installed, so the toolkit leaves that part to "
                .. (#old == 1 and "it" or "them") .. ". Remove the old "
                .. (#old == 1 and "one" or "ones") .. " to use the toolkit's.")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if openAfterCombat then
            openAfterCombat = false
            root.OpenOptions()
        end
    end
end)

SLASH_ZIRISTOOLKIT1 = "/zt"
SLASH_ZIRISTOOLKIT2 = "/toolkit"
SlashCmdList.ZIRISTOOLKIT = function(input)
    local cmd = strtrim(input or ""):lower()
    if cmd == "friends" and root.Friends then
        root.Friends.Report()
        return
    end
    if cmd == "instances" and root.Instances then
        root.Instances.Report()
        return
    end
    if cmd == "buffs" and root.Buffs then
        root.Buffs.Report()
        return
    end
    if cmd == "boats" and root.Boats then
        root.Boats.Report()
        return
    end
    if cmd == "flights" and root.Flights then
        root.Flights.Report()
        return
    end
    if cmd == "thanks" and root.ThanksReport then
        root.ThanksReport()
        return
    end
    if cmd == "healers" and root.HealerMana then
        root.HealerMana.Report()
        return
    end
    if cmd == "afk" and root.AfkScreen then
        root.AfkScreen.Report()
        return
    end
    if cmd == "photo" and root.Photo then
        root.Photo.Report()
        return
    end
    if cmd == "rested" and root.Rested then
        root.Rested.Report()
        return
    end
    if not root.OpenOptions() then
        root.Print("the settings page could not be opened")
    end
end
