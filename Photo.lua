-- Ziri's Toolkit: photo mode (and the AFK screen's settings, see AfkScreen.lua)
-- When you hide the game's interface with its own Toggle UI key (Alt+Z
-- unless you changed it), this also hides what Alt+Z leaves in the world:
-- names over players, NPCs and pets, nameplates, chat bubbles and the
-- damage and healing numbers over targets. Optionally the camera slowly
-- circles your character. Press the key again and everything is back.
--
-- These are the game's own settings. Your values are kept in
-- ZirisToolkitDB.photo.saved while the interface is hidden and put back
-- when it shows again. If the game closes in between, they are put back at
-- the next login.

local ADDON_NAME, root = ...

local Photo = {}
root.Photo = Photo

local IsSecret = root.IsSecret

Photo.SPIN_SPEED = 0.03 -- part of the game's camera turn speed, about a minute per circle

-- What to hide. Each group is one check box on the Photo mode page.
-- Settings this game version doesn't have are skipped.
Photo.GROUPS = {
    {
        key = "names", label = "Names over heads",
        tip = "Names of players, NPCs and pets, and your own name. Guild names and titles go with them.",
        cvars = {
            "UnitNameOwn", "UnitNameNPC", "UnitNameHostleNPC", "UnitNameInteractiveNPC",
            "UnitNameFriendlySpecialNPCName", "UnitNameNonCombatCreatureName",
            "UnitNameFriendlyPlayerName", "UnitNameFriendlyMinionName",
            "UnitNameEnemyPlayerName", "UnitNameEnemyMinionName",
        },
    },
    {
        key = "nameplates", label = "Nameplates",
        tip = "Health bars over enemies and anyone else, and the bar under your own character. During a fight they go when the fight is over: the game doesn't allow changing them sooner.",
        cvars = {
            "nameplateShowEnemies", "nameplateShowFriendlyPlayers", "nameplateShowFriendlyNpcs",
            "nameplateShowFriends", "nameplateShowSelf",
        },
    },
    {
        key = "bubbles", label = "Chat bubbles",
        tip = "Speech bubbles over people who /say or /yell, and over talking NPCs.",
        cvars = { "chatBubbles", "chatBubblesParty", "chatBubblesRaid" },
    },
    {
        key = "numbers", label = "Damage and healing numbers",
        tip = "The numbers that pop up over your target when you hit or heal it.",
        cvars = {
            "floatingCombatTextCombatDamage_v2", "floatingCombatTextCombatHealing_v2",
            "floatingCombatTextCombatDamage", "floatingCombatTextCombatHealing",
        },
    },
}

local DEFAULTS = {
    names = true, nameplates = true, bubbles = true, numbers = true, spin = false,
    afk = true,   -- AFK screen when you go AFK (AfkScreen.lua)
    card = false, -- the same screen with the Toggle UI key
}

local active = false
local spinning = false
local hooked = false

local function DB()
    local db = root.db
    if type(db.photo) ~= "table" then
        db.photo = {}
    end
    local p = db.photo
    for k, v in pairs(DEFAULTS) do
        if p[k] == nil then
            p[k] = v
        end
    end
    if type(p.saved) ~= "table" then
        p.saved = {}
    end
    return p
end
Photo.DB = DB

-------------------------------------------------------------------------------
-- The game's settings
-------------------------------------------------------------------------------

-- Current value as text (nil if this game version has no such setting),
-- and whether the game refuses changes to it during a fight.
local function Read(cvar)
    if C_CVar and C_CVar.GetCVarInfo then
        local ok, value, _, _, _, _, isSecure = pcall(C_CVar.GetCVarInfo, cvar)
        if ok and type(value) == "string" and not IsSecret(value) then
            return value, not IsSecret(isSecure) and isSecure == true
        end
        if ok then
            return nil, false
        end
    end
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if type(get) ~= "function" then
        return nil, false
    end
    local ok, value = pcall(get, cvar)
    if ok and type(value) == "string" and not IsSecret(value) then
        return value, false
    end
    return nil, false
end
Photo.Read = Read

local function Same(a, b)
    return a == b or (tonumber(a) ~= nil and tonumber(a) == tonumber(b))
end

-- Sets a setting. True when it now has that value (or doesn't exist);
-- false when it has to wait for the fight to end. Only writes on a real
-- change: every write runs the game's own handlers in our name.
local function Write(cvar, value)
    local current, secure = Read(cvar)
    if current == nil or Same(current, value) then
        return true
    end
    if secure and InCombatLockdown() then
        return false
    end
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if type(set) ~= "function" then
        return true
    end
    pcall(set, cvar, value)
    return Same(Read(cvar), value)
end

-- Brings every setting in the saved list in line: hidden ("0") while photo
-- mode is on, your own value once it is off. A setting stays in the list
-- until your value is really back.
local function Sync()
    local saved = DB().saved
    for cvar, original in pairs(saved) do
        if active then
            Write(cvar, "0")
        elseif Write(cvar, original) then
            saved[cvar] = nil
        end
    end
end

-------------------------------------------------------------------------------
-- Camera
-------------------------------------------------------------------------------

local function StartSpin()
    if spinning or type(MoveViewLeftStart) ~= "function" then
        return
    end
    if pcall(MoveViewLeftStart, Photo.SPIN_SPEED) then
        spinning = true
    end
end

local function StopSpin()
    if not spinning then
        return
    end
    spinning = false
    if type(MoveViewLeftStop) == "function" then
        pcall(MoveViewLeftStop)
    end
end

-------------------------------------------------------------------------------
-- On and off
-------------------------------------------------------------------------------

function Photo.IsActive()
    return active
end

-- reason "afk": started by the AFK screen, which always circles the
-- camera and shows its card.
function Photo.Enter(reason)
    if active or not root.ModuleOn("photo") then
        return
    end
    active = true
    local p = DB()
    for _, group in ipairs(Photo.GROUPS) do
        if p[group.key] then
            for _, cvar in ipairs(group.cvars) do
                if p.saved[cvar] == nil then
                    local value = Read(cvar)
                    if value ~= nil then
                        p.saved[cvar] = value
                    end
                end
            end
        end
    end
    Sync()
    if p.spin or reason == "afk" then
        StartSpin()
    end
    if (p.card or reason == "afk") and root.AfkScreen then
        root.AfkScreen.ShowCard(reason)
    end
end

function Photo.Leave()
    StopSpin()
    if root.AfkScreen then
        root.AfkScreen.HideCard()
    end
    if not active and next(DB().saved) == nil then
        return
    end
    active = false
    Sync()
end

local reported = false
local function Safely(fn)
    local ok, err = pcall(fn)
    if not ok and not reported then
        reported = true
        root.Print("photo mode ran into a problem: " .. tostring(err))
    end
end

local function Hook()
    if hooked then
        return
    end
    hooked = true
    -- The game's Toggle UI key calls SetUIVisibility(false) / (true).
    if type(SetUIVisibility) == "function" and hooksecurefunc then
        hooksecurefunc("SetUIVisibility", function(visible)
            if visible then
                Safely(Photo.Leave)
            else
                Safely(Photo.Enter)
            end
        end)
        Photo.hookedToggle = true
    end
    -- However the interface comes back, photo mode ends with it.
    if UIParent and UIParent.HookScript then
        UIParent:HookScript("OnShow", function()
            Safely(Photo.Leave)
        end)
    end
end

root.OnModuleChanged("photo", function(on)
    if not on then
        Photo.Leave()
    end
end)

-------------------------------------------------------------------------------
-- /zt photo
-------------------------------------------------------------------------------

function Photo.Report()
    local p = DB()
    root.Print("photo mode " .. (root.ModuleOn("photo") and "is on" or "is switched off")
        .. (Photo.hookedToggle and ", listening to the Toggle UI key (Alt+Z)." or ", but the Toggle UI key could not be found."))
    for _, group in ipairs(Photo.GROUPS) do
        local found, missing = {}, {}
        for _, cvar in ipairs(group.cvars) do
            local value = Read(cvar)
            if value ~= nil then
                found[#found + 1] = cvar .. "=" .. value
            else
                missing[#missing + 1] = cvar
            end
        end
        local line = group.label .. (p[group.key] and " (hidden): " or " (left alone): ")
            .. (#found > 0 and table.concat(found, ", ") or "none found")
        if #missing > 0 then
            line = line .. "; not in this game: " .. table.concat(missing, ", ")
        end
        root.Print(line)
    end
    local waiting = {}
    for cvar, value in pairs(p.saved) do
        waiting[#waiting + 1] = cvar .. "=" .. value
    end
    if #waiting > 0 then
        table.sort(waiting)
        root.Print("your own values waiting to go back: " .. table.concat(waiting, ", "))
    end
end

-------------------------------------------------------------------------------
-- Settings page
-------------------------------------------------------------------------------

local function BuildPage()
    local UI = root.UI
    local panel = CreateFrame("Frame", "ZirisToolkitPhotoOptions", UIParent)
    panel:Hide()
    local page = UI.ScrollArea(panel)
    local x, y = 16, -16

    local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", x, y)
    title:SetText("Photo mode")
    y = y - 26
    UI.Note(page, "Press the game's Toggle UI key (Alt+Z unless you changed it) to hide the interface. Photo mode then also hides what is checked below. Press it again and everything is back as you had it.", x, y)
    y = y - 44

    local p = DB()
    for _, group in ipairs(Photo.GROUPS) do
        UI.Check(page, group.label, group.tip, x, y,
            function() return p[group.key] end,
            function(v) p[group.key] = v end,
            function() return root.ModuleOn("photo") end)
        y = y - 30
    end

    y = y - 8
    UI.Heading(page, "Camera", x, y)
    y = y - 22
    UI.Check(page, "Circle slowly around you",
        "While the interface is hidden, the camera turns slowly around your character, about once a minute. It stops when the interface comes back.",
        x, y,
        function() return p.spin end,
        function(v) p.spin = v end,
        function() return root.ModuleOn("photo") end)
    y = y - 38

    UI.Heading(page, "AFK screen", x, y)
    y = y - 22
    UI.Check(page, "Show when you go AFK",
        "When you go AFK (/afk, or after a few minutes without doing anything), the interface hides, the camera circles your character and a card at the bottom shows your character, name, guild and how long you have been away. Move, or press any key that does something, and it ends.",
        x, y,
        function() return p.afk end,
        function(v) p.afk = v end,
        function() return root.ModuleOn("photo") end)
    y = y - 30
    UI.Check(page, "Show the card with the Toggle UI key too",
        "The same card (your character, name, guild, and where you are) also shows when you hide the interface yourself.",
        x, y,
        function() return p.card end,
        function(v) p.card = v end,
        function() return root.ModuleOn("photo") end)
    y = y - 30
    UI.Note(page, "A fight ends the AFK screen at once. The things checked above are hidden on the AFK screen too.", x, y)
    y = y - 36

    page:SetHeight(-y + 16)
    panel:SetScript("OnShow", UI.RefreshAll)
    Photo.page = root.RegisterSubPage(panel, "Photo mode")
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        Hook()
        -- Values left over from a session that ended with the interface
        -- hidden go back now.
        active = false
        Safely(Sync)
        local ok, err = pcall(BuildPage)
        if not ok then
            root.Print("the photo mode page could not be built: " .. tostring(err))
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Settings the game kept locked during the fight.
        if next(DB().saved) ~= nil then
            Safely(Sync)
        end
    elseif event == "PLAYER_LOGOUT" then
        -- The game saves its settings as you log out: put yours back first.
        StopSpin()
        active = false
        Safely(Sync)
    end
end)
