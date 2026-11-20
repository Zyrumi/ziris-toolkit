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
-- Settings live in ZirisToolkitDB.photo: afk, card, and the look (layout,
-- side, size, facing, anim, center, crest), all on the Photo mode page.

local ADDON_NAME, root = ...

local AfkScreen = {}
root.AfkScreen = AfkScreen

local IsSecret = root.IsSecret

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
-- Options (ZirisToolkitDB.photo, defaults in Photo.lua)
-------------------------------------------------------------------------------

-- layout:  "one" = bottom bar, "two" = top and bottom bars
-- side:    "left", "right", "off"
-- size:    1..4
-- facing:  "in" (toward the middle), "front" (you), "out"
-- anim:    a key of AfkScreen.ANIMS
-- center:  "logo", "class", "faction", "none"
-- crest:   true = faction crest by your name

AfkScreen.SIZES = { 260, 340, 430, 540 } -- character height in interface pixels
AfkScreen.SIZE_NAMES = { "small", "medium", "large", "huge" }

-- Animation numbers of the game's character models.
local A_STAND, A_WAVE, A_CHEER, A_DANCE, A_SLEEP, A_SIT = 0, 67, 68, 69, 71, 97

AfkScreen.ANIM_ORDER = { "wave", "stand", "turn", "dance", "sit", "sleep", "cheer" }
AfkScreen.ANIMS = {
    wave = { text = "Waves, then stands" },
    stand = { text = "Stands still" },
    turn = { text = "Turns slowly" },
    dance = { text = "Dances" },
    sit = { text = "Sits down" },
    sleep = { text = "Sleeps" },
    cheer = { text = "Cheers now and then" },
}

-- Model facing in radians; positive turns it toward the right of the screen.
AfkScreen.FACE_ANGLE = 0.6

local function Opt(key)
    local p = root.db and root.db.photo
    if type(p) == "table" and p[key] ~= nil then
        return p[key]
    end
    return root.Photo and root.Photo.DEFAULTS[key]
end

-- Which animation the model should play t seconds after the card showed.
function AfkScreen.AnimAt(kind, t)
    if kind == "wave" then
        return t < 2.6 and A_WAVE or A_STAND
    elseif kind == "dance" then
        return A_DANCE
    elseif kind == "sit" then
        return A_SIT
    elseif kind == "sleep" then
        return A_SLEEP
    elseif kind == "cheer" then
        return (t % 15) < 2.6 and A_CHEER or A_STAND
    end
    return A_STAND
end

-- Facing for the side the character stands on.
function AfkScreen.Facing(side, facing)
    if facing == "front" then
        return 0
    end
    local towardMiddle = (side == "right") and -AfkScreen.FACE_ANGLE or AfkScreen.FACE_ANGLE
    return facing == "out" and -towardMiddle or towardMiddle
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

local function ClassToken()
    local _, token = Call(UnitClass, "player")
    if type(token) == "string" and not IsSecret(token) then
        return token
    end
    return nil
end

local function ClassColor()
    local token = ClassToken()
    if token then
        local c = (C_ClassColor and Call(C_ClassColor.GetClassColor, token))
            or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token])
        if c and c.r then
            return c.r, c.g, c.b
        end
    end
    return 1, 0.82, 0
end

local function Faction()
    local f = Text((Call(UnitFactionGroup, "player")))
    if f == "Alliance" or f == "Horde" then
        return f
    end
    return nil
end

-- Puts a picture on a texture. kind "logo", "class" or "faction".
-- Returns width, height, or nil when there is nothing to show.
function AfkScreen.SetPicture(tex, kind, big)
    if kind == "logo" then
        local info = C_GameRules and Call(C_GameRules.GetCurrentGameModeDisplayInfo)
        local logo = type(info) == "table" and info.logo
        if logo and not IsSecret(logo) and logo ~= 0 then
            tex:SetTexCoord(0, 1, 0, 1)
            tex:SetTexture(logo)
            return 256, 128
        end
        return nil
    elseif kind == "class" then
        local token = ClassToken()
        if not token then
            return nil
        end
        local atlas = GetClassAtlas and Call(GetClassAtlas, token)
        if type(atlas) == "string" and tex.SetAtlas and pcall(tex.SetAtlas, tex, atlas) then
            tex:SetTexCoord(0, 1, 0, 1)
        else
            local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
            if not c then
                return nil
            end
            tex:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
            tex:SetTexCoord(c[1], c[2], c[3], c[4])
        end
        return big, big
    elseif kind == "faction" then
        local f = Faction()
        if not f then
            return nil
        end
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetTexture("Interface\\FriendsFrame\\PlusManz-" .. f)
        return big, big
    end
    return nil
end

local function Font(fs, size, r, g, b)
    local file, flags
    if GameFontNormal and GameFontNormal.GetFont then
        local f, _, fl = GameFontNormal:GetFont()
        file, flags = f, fl
    end
    if file then
        fs:SetFont(file, size, flags)
    else
        fs:SetFontObject("GameFontNormalLarge")
    end
    if r then
        fs:SetTextColor(r, g, b)
    end
end

local function Bar(parent)
    local f = CreateFrame("Frame", nil, parent)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.045, 0.04, 0.92)
    local line = f:CreateTexture(nil, "BORDER")
    line:SetHeight(1)
    line:SetColorTexture(0.91, 0.78, 0.42, 0.8)
    f.line = line
    return f
end

local GREY = { 0.75, 0.73, 0.68 }

local function Build()
    if card then
        return card
    end
    -- On the world frame: it stays on screen while the interface is hidden.
    card = CreateFrame("Frame", "ZirisToolkitAfkCard", WorldFrame)
    card:SetFrameStrata("DIALOG")
    card:SetAllPoints(WorldFrame)
    card:Hide()

    card.bottom = Bar(card)
    card.bottom:SetPoint("BOTTOMLEFT")
    card.bottom:SetPoint("BOTTOMRIGHT")
    card.bottom.line:SetPoint("TOPLEFT")
    card.bottom.line:SetPoint("TOPRIGHT")
    card.top = Bar(card)
    card.top:SetPoint("TOPLEFT")
    card.top:SetPoint("TOPRIGHT")
    card.top:SetHeight(40)
    card.top.line:SetPoint("BOTTOMLEFT")
    card.top.line:SetPoint("BOTTOMRIGHT")

    local text = CreateFrame("Frame", nil, card)
    text:SetAllPoints()
    text:SetFrameLevel((card:GetFrameLevel() or 1) + 20)
    card.text = text

    local function FS(size, r, g, b, justify)
        local fs = text:CreateFontString(nil, "OVERLAY")
        Font(fs, size, r, g, b)
        fs:SetJustifyH(justify or "LEFT")
        return fs
    end
    card.name = FS(28)
    card.desc = FS(18, 0.95, 0.95, 0.95)
    card.guild = FS(16, GREY[1], GREY[2], GREY[3])
    card.caption = FS(15, GREY[1], GREY[2], GREY[3], "RIGHT")
    card.big = FS(34, 1, 1, 1, "RIGHT")
    card.clock = FS(16, 0.91, 0.78, 0.42, "RIGHT")
    card.dateText = FS(16, GREY[1], GREY[2], GREY[3], "RIGHT")
    card.topDate = FS(16, 0.91, 0.78, 0.42)
    card.topClockLabel = FS(16, GREY[1], GREY[2], GREY[3], "RIGHT")

    card.crest = text:CreateTexture(nil, "OVERLAY")
    card.center = text:CreateTexture(nil, "OVERLAY")

    -- Your character, in front of the bars.
    local okModel, model = pcall(CreateFrame, "PlayerModel", nil, card)
    if okModel and model then
        model:SetFrameLevel((card:GetFrameLevel() or 1) + 10)
        model:SetScript("OnModelLoaded", function(self)
            self.applied = nil
        end)
        card.model = model
    end

    local tick = 0
    card:SetScript("OnUpdate", function(self, dt)
        AfkScreen.Animate(dt)
        tick = tick + dt
        if tick >= 0.5 then
            tick = 0
            AfkScreen.Refresh()
        end
    end)
    return card
end

-- Places everything for the current options.
function AfkScreen.Layout()
    local two = Opt("layout") == "two"
    local side = Opt("side")
    local barH = two and 104 or 124
    local m = card.model
    local modelH = AfkScreen.SIZES[Opt("size")] or AfkScreen.SIZES[3]
    local modelW = math.floor(modelH * 0.55)
    local leftIn, rightIn = 40, 40
    if m then
        m:ClearAllPoints()
        m:SetSize(modelW, modelH)
        if side == "left" then
            m:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 0)
            leftIn = modelW + 20
        elseif side == "right" then
            m:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 0)
            rightIn = modelW + 20
        end
        m:SetShown(side == "left" or side == "right")
    end

    card.bottom:SetHeight(barH)
    card.top:SetShown(two)
    card.topDate:SetShown(two)
    card.topClockLabel:SetShown(two)
    card.dateText:SetShown(not two)

    for _, r in ipairs({ card.name, card.desc, card.guild, card.caption, card.big, card.clock,
        card.dateText, card.topDate, card.topClockLabel, card.crest }) do
        r:ClearAllPoints()
    end
    local crestSize = two and 44 or 52
    local crestOn = Opt("crest") and AfkScreen.SetPicture(card.crest, "faction", crestSize) ~= nil
    card.crest:SetShown(crestOn and true or false)
    card.crest:SetSize(crestSize, crestSize)

    if not two then
        -- Left: crest, name, level and class, guild.
        local x = leftIn
        if crestOn then
            card.crest:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", x, 34)
            x = x + crestSize + 10
        end
        card.name:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", x, 70)
        card.desc:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -6)
        card.guild:SetPoint("TOPLEFT", card.desc, "BOTTOMLEFT", 0, -4)
        -- Right: away timer (or where you are), date and time.
        card.caption:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -rightIn, 84)
        card.big:SetPoint("TOPRIGHT", card.caption, "BOTTOMRIGHT", 0, -2)
        card.clock:SetPoint("TOPRIGHT", card.big, "BOTTOMRIGHT", 0, -4)
        card.dateText:SetPoint("RIGHT", card.clock, "LEFT", -8, 0)
    else
        -- Top bar: date left, local time right.
        card.topDate:SetPoint("LEFT", card.top, "LEFT", 24, 0)
        card.clock:SetPoint("RIGHT", card.top, "RIGHT", -24, 0)
        card.topClockLabel:SetPoint("RIGHT", card.clock, "LEFT", -6, 0)
        -- Bottom bar: name in the middle, crest and away timer on the left.
        card.name:SetPoint("BOTTOM", card, "BOTTOM", 0, 58)
        card.desc:SetPoint("TOP", card.name, "BOTTOM", 0, -4)
        card.guild:SetPoint("TOP", card.desc, "BOTTOM", 0, -4)
        local x = leftIn
        if crestOn then
            card.crest:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", x, 30)
            x = x + crestSize + 10
        end
        card.caption:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", x, 62)
        card.big:SetPoint("TOPLEFT", card.caption, "BOTTOMLEFT", 0, -2)
    end
    local nameAlign = two and "CENTER" or "LEFT"
    card.name:SetJustifyH(nameAlign)
    card.desc:SetJustifyH(nameAlign)
    card.guild:SetJustifyH(nameAlign)
    card.caption:SetJustifyH(two and "LEFT" or "RIGHT")
    card.big:SetJustifyH(two and "LEFT" or "RIGHT")

    -- The picture in the middle.
    local tex = card.center
    tex:ClearAllPoints()
    local w, h = AfkScreen.SetPicture(tex, Opt("center"), 96)
    if w then
        tex:SetSize(w, h)
        if two then
            tex:SetPoint("TOP", card, "TOP", 0, -52)
        else
            tex:SetPoint("BOTTOM", card, "BOTTOM", 0, barH - math.floor(h * 0.45))
        end
        tex:Show()
    else
        tex:Hide()
    end
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
    local day = date and date("%A %d %B") or ""
    card.dateText:SetText(day)
    card.topDate:SetText(day)
    card.topClockLabel:SetText("Local time")
end

-- Plays the chosen animation and turns the model if asked.
local shownFor = 0
function AfkScreen.Animate(dt)
    local m = card and card.model
    if not m or not m:IsShown() then
        return
    end
    shownFor = shownFor + dt
    local kind = Opt("anim")
    local want = AfkScreen.AnimAt(kind, shownFor)
    if m.applied ~= want and m.SetAnimation then
        pcall(m.SetAnimation, m, want)
        m.applied = want
    end
    if kind == "turn" and m.SetFacing then
        m.facing = (m.facing or 0) + dt * 0.5
        pcall(m.SetFacing, m, m.facing)
    end
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
        AfkScreen.Layout()
        local m = card.model
        if m then
            shownFor = 0
            m.applied = nil
            pcall(m.SetUnit, m, "player")
            pcall(m.SetCamDistanceScale, m, 0.9)
            m.facing = AfkScreen.Facing(Opt("side"), Opt("facing"))
            pcall(m.SetFacing, m, m.facing)
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
