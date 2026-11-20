-- Ziri's Toolkit: AFK screen
-- When you go AFK: the interface hides (the same way as the game's Toggle
-- UI key, so photo mode hides names and the rest too), the camera slowly
-- circles your character, and a card along the bottom of the screen shows
-- your character in 3D, your name, level, race and class, guild, and how
-- long you have been away. Coming back (moving, casting, chatting: the game
-- ends AFK) or a fight starting puts everything back.
--
-- The card can also show with the Toggle UI key (setting on the Photo mode
-- page); then it shows where you are instead of the away timer.
-- Settings live in ZirisToolkitDB.photo (afk, card).

local ADDON_NAME, root = ...

local AfkScreen = {}
root.AfkScreen = AfkScreen

local IsSecret = root.IsSecret

local ICON = "Interface\\AddOns\\ZirisToolkit\\Media\\MinimapIcon"
local BAND_HEIGHT = 120

local card
local ours = false -- the interface is hidden because of the AFK screen
local awaySince

local function Text(v)
    if type(v) == "string" and v ~= "" and not IsSecret(v) then
        return v
    end
    return nil
end

local function Call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        return nil
    end
    return a, b, c
end

-- true / false, or nil when the game won't say (in an instance the AFK flag
-- can be hidden from addons).
function AfkScreen.IsAfk()
    local v = Call(UnitIsAFK, "player")
    if v == nil or IsSecret(v) then
        return nil
    end
    return v and true or false
end

-------------------------------------------------------------------------------
-- The card
-------------------------------------------------------------------------------

-- "Level 42 Gnome Paladin"
function AfkScreen.Description()
    local level = Call(UnitLevel, "player")
    local race = Text((Call(UnitRace, "player")))
    local class = Text((Call(UnitClass, "player")))
    local parts = {}
    if type(level) == "number" and not IsSecret(level) and level > 0 then
        parts[#parts + 1] = "Level " .. level
    end
    parts[#parts + 1] = race
    parts[#parts + 1] = class
    return table.concat(parts, " ")
end

function AfkScreen.Guild()
    local guild = Text((Call(GetGuildInfo, "player")))
    return guild and ("<" .. guild .. ">") or ""
end

-- "Stormwind City, Trade District"
function AfkScreen.Place()
    local zone = Text(Call(GetZoneText))
    local sub = Text(Call(GetSubZoneText))
    if zone and sub and sub ~= zone then
        return zone .. ", " .. sub
    end
    return zone or sub or ""
end

local function ClassColor()
    local _, token = Call(UnitClass, "player")
    if type(token) == "string" and not IsSecret(token) then
        local c = (C_ClassColor and Call(C_ClassColor.GetClassColor, token))
            or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token])
        if c and c.r then
            return c.r, c.g, c.b
        end
    end
    return 1, 0.82, 0
end

local function Build()
    if card then
        return card
    end
    -- On the world frame: it stays on screen while the interface is hidden.
    card = CreateFrame("Frame", "ZirisToolkitAfkCard", WorldFrame)
    card:SetFrameStrata("DIALOG")
    card:SetPoint("BOTTOMLEFT")
    card:SetPoint("BOTTOMRIGHT")
    card:SetHeight(BAND_HEIGHT)
    card:Hide()

    -- Dark band fading out upwards.
    local band = card:CreateTexture(nil, "BACKGROUND")
    band:SetAllPoints()
    band:SetColorTexture(1, 1, 1, 1)
    if band.SetGradient and CreateColor then
        band:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.85), CreateColor(0, 0, 0, 0))
    else
        band:SetColorTexture(0, 0, 0, 0.6)
    end
    local line = card:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetHeight(2)
    line:SetColorTexture(1, 0.82, 0, 0.5)

    -- Your character, standing on the band.
    local okModel, model = pcall(CreateFrame, "PlayerModel", nil, card)
    if okModel and model then
        model:SetSize(220, 300)
        model:SetPoint("BOTTOMLEFT", 40, 4)
        card.model = model
    end

    local textLeft = card.model and 270 or 40
    local name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    name:SetPoint("BOTTOMLEFT", textLeft, 66)
    name:SetJustifyH("LEFT")
    card.name = name
    local desc = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
    desc:SetJustifyH("LEFT")
    card.desc = desc
    local guild = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    guild:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -4)
    guild:SetJustifyH("LEFT")
    guild:SetTextColor(0.75, 0.75, 0.75)
    card.guild = guild

    -- Right side: away timer (or where you are) and the time of day.
    local caption = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    caption:SetPoint("BOTTOMRIGHT", -40, 76)
    caption:SetJustifyH("RIGHT")
    caption:SetTextColor(0.75, 0.75, 0.75)
    card.caption = caption
    local big = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    big:SetPoint("TOPRIGHT", caption, "BOTTOMRIGHT", 0, -4)
    big:SetJustifyH("RIGHT")
    card.big = big
    local clock = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    clock:SetPoint("TOPRIGHT", big, "BOTTOMRIGHT", 0, -6)
    clock:SetJustifyH("RIGHT")
    clock:SetTextColor(0.75, 0.75, 0.75)
    card.clock = clock

    -- Ziri, small, in the middle.
    local face = card:CreateTexture(nil, "OVERLAY")
    face:SetSize(36, 36)
    face:SetPoint("BOTTOM", 0, 10)
    face:SetTexture(ICON)
    face:SetAlpha(0.8)

    local elapsed = 0
    card:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.5 then
            elapsed = 0
            AfkScreen.Refresh()
        end
    end)
    return card
end

-- Right-hand lines: away timer while AFK, else where you are.
function AfkScreen.RightLines(now)
    local time = date and date("%H:%M") or ""
    if card and card.reason == "afk" and awaySince then
        return "Away for", root.Clock(now - awaySince), time
    end
    return AfkScreen.Place(), "", time
end

function AfkScreen.Refresh()
    if not card or not card:IsShown() then
        return
    end
    local caption, big, clock = AfkScreen.RightLines(GetTime())
    card.caption:SetText(caption)
    card.big:SetText(big)
    card.clock:SetText(clock)
end

function AfkScreen.ShowCard(reason)
    local ok, err = pcall(function()
        Build()
        card.reason = reason
        -- Same size as the interface would have.
        local ui = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
        local world = WorldFrame.GetEffectiveScale and WorldFrame:GetEffectiveScale()
        if type(ui) == "number" and type(world) == "number" and world > 0 then
            card:SetScale(ui / world)
        end
        card.name:SetText(root.CharKey() or "")
        card.name:SetTextColor(ClassColor())
        card.desc:SetText(AfkScreen.Description())
        card.guild:SetText(AfkScreen.Guild())
        if card.model then
            pcall(card.model.SetUnit, card.model, "player")
            pcall(card.model.SetFacing, card.model, 0.4)
        end
        card:Show()
        AfkScreen.Refresh()
    end)
    if not ok then
        root.Print("the AFK screen ran into a problem: " .. tostring(err))
    end
end

function AfkScreen.HideCard()
    if card then
        card:Hide()
    end
end

-------------------------------------------------------------------------------
-- Going away and coming back
-------------------------------------------------------------------------------

local function Wanted()
    local db = root.db
    return db and root.ModuleOn("photo") and type(db.photo) == "table" and db.photo.afk == true
end

function AfkScreen.Start()
    if ours or not Wanted() or InCombatLockdown() then
        return
    end
    if not (UIParent and UIParent:IsShown()) then
        return -- already hidden (Toggle UI key, a cinematic): leave it
    end
    if Call(InCinematic) then
        return
    end
    awaySince = GetTime()
    ours = true
    root.Photo.Enter("afk")
    -- The same call as the Toggle UI key.
    if CloseMenus then
        pcall(CloseMenus)
    end
    Call(SetUIVisibility, false)
    if UIParent:IsShown() then
        -- The game didn't hide it: don't leave names hidden on a normal screen.
        ours = false
        awaySince = nil
        root.Photo.Leave()
    end
end

function AfkScreen.Stop()
    if not ours then
        return
    end
    ours = false
    awaySince = nil
    if UIParent and not UIParent:IsShown() then
        Call(SetUIVisibility, true)
    end
    root.Photo.Leave() -- in case the interface was already back
end

function AfkScreen.IsShown()
    return ours
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        if events.RegisterUnitEvent then
            events:RegisterUnitEvent("PLAYER_FLAGS_CHANGED", "player")
        else
            events:RegisterEvent("PLAYER_FLAGS_CHANGED")
        end
        -- The interface showing again (Toggle UI key while away) ends it too.
        if UIParent and UIParent.HookScript then
            UIParent:HookScript("OnShow", function()
                ours = false
                awaySince = nil
            end)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        AfkScreen.Stop()
    elseif event == "PLAYER_FLAGS_CHANGED" then
        if unit ~= nil and unit ~= "player" then
            return
        end
        local afk = AfkScreen.IsAfk()
        if afk == true then
            AfkScreen.Start()
        elseif afk == false then
            AfkScreen.Stop()
        end
    end
end)
