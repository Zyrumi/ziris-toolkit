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
--   Boat times      (Boats.lua, uses the DockWatch addon's public API)

local ADDON_NAME, root = ...

root.TITLE = "Ziri's Toolkit"
local PREFIX = "|cff66ccffZiri's Toolkit:|r "

local DEFAULTS = {
    modules = {
        freshRanks = true,
        cleanse = true,
        thanks = true,
        undress = true,
        boats = true,
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

root.skip = {
    lootHighlight = OldAddonActive("LootHighlight"),
    freshRanks = OldAddonActive("FreshRanks"),
}

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
    if root.skip[key] then
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

local function BuildMainPage()
    local panel = CreateFrame("Frame", "ZirisToolkitOptions", UIParent)
    panel:Hide()
    local x, y = 16, -16

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", x, y)
    title:SetText(root.TITLE)
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, 0)
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local okV, v = pcall(meta, ADDON_NAME, "Version")
    version:SetText(okV and v and ("version " .. v) or "")
    y = y - 26
    Note(panel, "Switch each part on or off. Changes apply at once.", x, y)
    y = y - 28

    -- Loot Highlight
    Check(panel, "Loot Highlight",
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
        Note(panel, OLD_NOTE:format("Loot Highlight"), x + 30, y)
    else
        Note(panel, "Points out nearby herbs, ore, chests and loot. More settings on its own page.", x + 30, y)
    end
    y = y - 30

    -- Fresh Ranks
    Check(panel, "Fresh Ranks",
        "When you learn a new rank, your action buttons with the old rank get the new one. New spells go into an empty slot.",
        x, y,
        function() return root.ModuleOn("freshRanks") end,
        function(v) root.SetModule("freshRanks", v) end,
        function() return not root.skip.freshRanks end)
    y = y - 26
    if root.skip.freshRanks then
        Note(panel, OLD_NOTE:format("Fresh Ranks"), x + 30, y)
    else
        Note(panel, "Keeps your action bars up to date when you learn spells.", x + 30, y)
    end
    y = y - 30

    -- Cleanse buttons
    Check(panel, "Cleanse buttons",
        "A small button beside your own frame and each party member's frame. Click it to cast your cleanse spell on that person, no targeting needed.",
        x, y,
        function() return root.ModuleOn("cleanse") end,
        function(v) root.SetModule("cleanse", v) end)
    y = y - 26
    Note(panel, "Click the button beside a frame to cleanse that person. Left and right click use different spells if your class has two.", x + 30, y)
    y = y - 34

    -- Thanks
    Check(panel, "Thank people who buff you",
        "Does the /thank emote at players who give you a buff out in the world.",
        x, y,
        function() return root.ModuleOn("thanks") end,
        function(v) root.SetModule("thanks", v) end)
    y = y - 26
    Note(panel, "Out in the world only: party and raid members are never thanked, and each person at most once a minute.", x + 30, y)
    y = y - 34

    -- Undress
    Check(panel, "Undress button",
        "A button beside the character window (C) that puts your gear into your bags and back on again.",
        x, y,
        function() return root.ModuleOn("undress") end,
        function(v) root.SetModule("undress", v) end)
    y = y - 26
    Note(panel, "For corpse runs: gear in your bags loses no durability when you die. Rings, necklace and trinkets stay on.", x + 30, y)
    y = y - 34

    -- Boat times
    Check(panel, "Boat times",
        "At a dock: when each boat or zeppelin from there leaves. On board: when you arrive. Shown at the top of the screen, only then.",
        x, y,
        function() return root.ModuleOn("boats") end,
        function(v) root.SetModule("boats", v) end)
    y = y - 26
    local boatsNote = Note(panel, "", x + 30, y)
    refreshers[#refreshers + 1] = function()
        if root.Boats and root.Boats.HasDockWatch() then
            boatsNote:SetText("Times come from DockWatch. You can switch off DockWatch's own map and window in its options (/dw options).")
        else
            boatsNote:SetText("Needs the DockWatch addon, which learns and shares the times. Install it to see boat times.")
        end
    end

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
SlashCmdList.ZIRISTOOLKIT = function()
    if not root.OpenOptions() then
        root.Print("the settings page could not be opened")
    end
end
