-- Ziri's Toolkit: console settings
-- A settings page (Esc > Options > AddOns > Ziri's Toolkit > Console settings)
-- for game settings that are normally only reachable with /console.
--
-- These are the game's own settings: the page reads and writes them
-- directly and keeps no copy. The game saves them, so they stay as you set
-- them even if the toolkit is switched off or removed.
-- Settings this game version doesn't have are left off the page.

local ADDON_NAME, root = ...

local Console = {}
root.Console = Console

local WEATHER = { [0] = "off", [1] = "low", [2] = "medium", [3] = "full" }

local function Fixed(decimals, unit)
    return function(v)
        return ("%." .. decimals .. "f"):format(v) .. (unit or "")
    end
end

-- kind "slider": min, max, step, decimals, format
-- kind "check": checked when the setting is on (or off, with invert)
Console.GROUPS = {
    {
        title = "Camera",
        items = {
            { cvar = "cameraDistanceMaxZoomFactor", kind = "slider", label = "Max camera distance",
              tip = "How far you can zoom out. The game's own Options stop at 2.0; this goes up to the most the game allows.",
              min = 1, max = 2.6, step = 0.1, decimals = 1, format = Fixed(1) },
        },
    },
    {
        title = "World and screen",
        items = {
            { cvar = "groundEffectDensity", kind = "slider", label = "Grass and foliage amount",
              tip = "How much grass and small plants cover the ground. Lower is clearer and faster. Changing Ground Clutter in the game's Graphics options sets this again.",
              min = 16, max = 256, step = 16, decimals = 0 },
            { cvar = "groundEffectDist", kind = "slider", label = "Grass and foliage distance",
              tip = "How far away grass and small plants are drawn. Changing Ground Clutter in the game's Graphics options sets this again.",
              min = 0, max = 300, step = 10, decimals = 0, format = Fixed(0, " yards") },
            { cvar = "weatherDensity", kind = "slider", label = "Weather",
              tip = "How much rain, snow and dust is drawn.",
              min = 0, max = 3, step = 1, decimals = 0,
              format = function(v) return WEATHER[math.floor(v + 0.5)] or tostring(v) end },
            { cvar = "ffxGlow", kind = "check", label = "Screen glow",
              tip = "The soft full-screen glow over bright areas. Off gives a sharper picture." },
            { cvar = "ffxDeath", kind = "check", label = "Grey screen when dead",
              tip = "The screen turns grey while you are a ghost." },
        },
    },
    {
        title = "Combat and items",
        items = {
            { cvar = "SpellQueueWindow", kind = "slider", label = "Spell queue window",
              tip = "How early you can press your next spell while the current one is still casting, and still have it go off right after. Lower if spells you pressed too early go off when you didn't want them to.",
              min = 0, max = 400, step = 10, decimals = 0, format = Fixed(0, " ms") },
            { cvar = "nameplateMaxDistance", kind = "slider", label = "Nameplate distance",
              tip = "How far away nameplates are shown. The game has its own maximum and will not go past it.",
              min = 10, max = 60, step = 1, decimals = 0, format = Fixed(0, " yards") },
            { cvar = "alwaysCompareItems", kind = "check", label = "Always compare items",
              tip = "Item tooltips show the gear you have on next to them without holding Shift." },
        },
    },
    {
        title = "Other",
        items = {
            { cvar = "worldPreloadNonCritical", kind = "check", invert = true, label = "Shorter loading screens",
              tip = "The loading screen ends as soon as the area around you is ready, and the rest loads while you play. You may see a short stutter after loading." },
            { cvar = "screenshotQuality", kind = "slider", label = "Screenshot quality",
              tip = "Picture quality of screenshots (Print Screen). 10 is the best and the biggest files.",
              min = 1, max = 10, step = 1, decimals = 0 },
        },
    },
}

-------------------------------------------------------------------------------
-- Reading and writing the game's settings
-------------------------------------------------------------------------------

local function CallCVar(apiName, ...)
    local fn = (C_CVar and C_CVar[apiName]) or _G[apiName]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn, ...)
    if not ok or root.IsSecret(v) then
        return nil
    end
    return v
end

-- True if this game version has the setting.
function Console.Exists(cvar)
    return CallCVar("GetCVarDefault", cvar) ~= nil or CallCVar("GetCVar", cvar) ~= nil
end

function Console.Get(cvar)
    return tonumber(CallCVar("GetCVar", cvar))
end

function Console.Default(cvar)
    return tonumber(CallCVar("GetCVarDefault", cvar))
end

-- Writes a value. Returns true if the game now has it (the game may refuse
-- or round it; the page then shows what the game kept).
function Console.Set(item, value)
    if InCombatLockdown() then
        root.Print("console settings can't be changed during a fight")
        return false
    end
    local text = ("%." .. (item.decimals or 0) .. "f"):format(value)
    local fn = (C_CVar and C_CVar.SetCVar) or SetCVar
    if type(fn) ~= "function" or not pcall(fn, item.cvar, text) then
        root.Print("the game did not accept " .. item.label:lower() .. ".")
        return false
    end
    local now = Console.Get(item.cvar)
    return now ~= nil and math.abs(now - tonumber(text)) < 1e-6
end

function Console.IsChecked(item)
    local on = (Console.Get(item.cvar) or 0) ~= 0
    if item.invert then
        return not on
    end
    return on
end

function Console.SetChecked(item, checked)
    local on = checked
    if item.invert then
        on = not on
    end
    return Console.Set(item, on and 1 or 0)
end

-- Puts every setting on the page back to the game's default.
function Console.ResetAll()
    if InCombatLockdown() then
        root.Print("console settings can't be changed during a fight")
        return
    end
    for _, group in ipairs(Console.GROUPS) do
        for _, item in ipairs(group.items) do
            local default = Console.Exists(item.cvar) and Console.Default(item.cvar)
            if default then
                Console.Set(item, default)
            end
        end
    end
    root.Print("console settings are back to the game's defaults.")
end

local function DefaultText(item)
    local d = Console.Default(item.cvar)
    if d == nil then
        return nil
    end
    if item.kind == "check" then
        local on = d ~= 0
        if item.invert then
            on = not on
        end
        return on and "on" or "off"
    end
    return item.format and item.format(d) or tostring(d)
end

-------------------------------------------------------------------------------
-- Settings page
-------------------------------------------------------------------------------

local function BuildPage()
    local UI = root.UI
    local panel = CreateFrame("Frame", "ZirisToolkitConsoleOptions", UIParent)
    panel:Hide()
    local page = UI.ScrollArea(panel)
    local x, y = 16, -16

    local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", x, y)
    title:SetText("Console settings")
    y = y - 26
    UI.Note(page, "Game settings that are otherwise only reachable with /console. These are the game's own settings: they apply at once and stay as you set them, even without the toolkit.", x, y)
    y = y - 40

    Console.shown = {}
    for _, group in ipairs(Console.GROUPS) do
        local items = {}
        for _, item in ipairs(group.items) do
            if Console.Exists(item.cvar) then
                items[#items + 1] = item
            end
        end
        if #items > 0 then
            UI.Heading(page, group.title, x, y)
            y = y - 22
            for _, item in ipairs(items) do
                Console.shown[#Console.shown + 1] = item.cvar
                local d = DefaultText(item)
                local tip = item.tip .. (d and ("\n\nGame default: " .. d .. ".") or "")
                if item.kind == "check" then
                    UI.Check(page, item.label, tip, x, y,
                        function() return Console.IsChecked(item) end,
                        function(v) Console.SetChecked(item, v) end)
                    y = y - 30
                else
                    UI.Slider(page, item.label, tip, x, y, item.min, item.max, item.step,
                        function() return Console.Get(item.cvar) end,
                        function(v) Console.Set(item, v) end,
                        { format = item.format, after = UI.RefreshAll })
                    y = y - 48
                end
            end
            y = y - 10
        end
    end

    UI.Button(page, "Reset to game defaults",
        "Puts every setting on this page back to the game's default.", x, y, 180, Console.ResetAll)
    y = y - 36

    page:SetHeight(-y + 16)
    panel:SetScript("OnShow", UI.RefreshAll)
    Console.page = root.RegisterSubPage(panel, "Console settings")
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    local ok, err = pcall(BuildPage)
    if not ok then
        root.Print("the console settings page could not be built: " .. tostring(err))
    end
end)
