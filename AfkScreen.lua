-- Ziri's Toolkit: AFK screen
-- When you go AFK: the interface hides (the same way as the game's Toggle
-- UI key, so photo mode hides names and the rest too), the camera slowly
-- circles your character, and a card along the bottom of the screen shows
-- your character in 3D, your name, level, race and class, guild, and how
-- long you have been away. Coming back (moving, casting, chatting: the game
-- ends AFK) or a fight starting puts everything back.
--
-- Its own part with its own switch ("afk") and settings page; the look is in
-- ZirisToolkitDB.afk. The bars can also show with the Toggle UI key
-- (ZirisToolkitDB.photo.card, on the Photo mode page); then they show where
-- you are instead of the away timer.

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
-- The lean NPCs do against walls (WALean01). No emote plays it, but the
-- character models from Warlords of Draenor on should have it (unverified on
-- Forever); a model without it
-- stands instead.
local A_LEAN = 1260

-- What /zt afk checks on your character's model.
AfkScreen.LEAN_CHECKS = {
    { 1260, "lean" }, { 1262, "lean and scrub" }, { 1264, "lean 3" }, { 1266, "lean and talk" },
}

AfkScreen.ANIM_ORDER = { "wave", "stand", "turn", "dance", "sit", "sleep", "cheer", "lean" }
AfkScreen.ANIMS = {
    wave = { text = "Waves, then stands" },
    stand = { text = "Stands still" },
    turn = { text = "Turns slowly" },
    dance = { text = "Dances" },
    sit = { text = "Sits down" },
    sleep = { text = "Sleeps" },
    cheer = { text = "Cheers now and then" },
    lean = { text = "Leans" },
}

-- The model frame leaves empty space under the feet that grows with the
-- character's size; this much of the height is moved down into the bar so
-- the feet stand on it (seen in game: 70 of 430 is right).
AfkScreen.FEET_RATIO = 0.163

-- The lowest line of text sits this far above the bottom edge (pixels).
AfkScreen.TEXT_LOW = 30

-- Model facing in radians; positive turns it toward the right of the screen.
AfkScreen.FACE_ANGLE = 0.6

AfkScreen.DEFAULTS = {
    layout = "one", side = "right", size = 3, facing = "in", anim = "wave",
    center = "logo", crest = true,
}

-- ZirisToolkitDB.afk. The first time, takes over what was set when these
-- settings still lived under photo mode.
local function DB()
    local db = root.db
    if type(db.afk) ~= "table" then
        db.afk = {}
        local old = db.photo
        if type(old) == "table" then
            for key in pairs(AfkScreen.DEFAULTS) do
                if old[key] ~= nil then
                    db.afk[key] = old[key]
                    old[key] = nil
                end
            end
            if old.afk == false then
                db.modules.afk = false
            end
            old.afk = nil
        end
    end
    for k, v in pairs(AfkScreen.DEFAULTS) do
        if db.afk[k] == nil then
            db.afk[k] = v
        end
    end
    return db.afk
end
AfkScreen.DB = DB

local function Opt(key)
    if root.db then
        local v = DB()[key]
        if v ~= nil then
            return v
        end
    end
    return AfkScreen.DEFAULTS[key]
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
    elseif kind == "lean" then
        return A_LEAN
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

-- The game's class crest pictures. "class": the big crest from behind the
-- Legion order hall report (see-through in the game, so it is drawn
-- EMBLEM_LAYERS times on top of itself to look solid), then the round ones.
-- "medallion": the round crest from the order hall missions, then the one
-- on the order hall minimap button.
AfkScreen.CREST_SIZE = 260
AfkScreen.EMBLEM_LAYERS = 3
function AfkScreen.CrestAtlases(token, kind)
    local round = {
        "classhall-circle-" .. token,
        "legionmission-landingbutton-" .. token .. "-up",
    }
    if kind == "medallion" then
        return round
    end
    return { "legionmission-landingpage-background-" .. token, round[1], round[2] }
end

-- Class crests shipped with the toolkit (Media\Crests, 256 x 256, Blizzard's
-- class crest art from the WoW blog via warcraft.wiki.gg, no ring).
-- "Class crest" uses these first.
AfkScreen.BUNDLED_CRESTS = {
    DEATHKNIGHT = true, DRUID = true, HUNTER = true, MAGE = true, PALADIN = true,
    PRIEST = true, ROGUE = true, SHAMAN = true, WARLOCK = true, WARRIOR = true,
}
function AfkScreen.BundledCrest(token)
    if token and AfkScreen.BUNDLED_CRESTS[token] then
        return "Interface\\AddOns\\ZirisToolkit\\Media\\Crests\\" .. token:lower()
    end
    return nil
end

function AfkScreen.IsEmblem(name)
    return type(name) == "string" and name:find("landingpage%-background") ~= nil
end

-- "Interface\ICONS\crest_paladin": the class crest icon the game has.
function AfkScreen.CrestFile(token)
    return "Interface\\ICONS\\crest_" .. token:lower()
end

-- Round cut for a texture (the crest), or none.
local rounded = setmetatable({}, { __mode = "k" })
local roundMask
function AfkScreen.IsRound(tex)
    return rounded[tex] == true
end
function AfkScreen.SetRound(tex, on)
    if not (tex.AddMaskTexture and card and card.text and card.text.CreateMaskTexture) then
        return
    end
    if not roundMask then
        roundMask = card.text:CreateMaskTexture()
        roundMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    local mask = roundMask
    if on and not rounded[tex] then
        mask:ClearAllPoints()
        mask:SetAllPoints(tex)
        pcall(tex.AddMaskTexture, tex, mask)
        rounded[tex] = true
    elseif not on and rounded[tex] then
        pcall(tex.RemoveMaskTexture, tex, mask)
        rounded[tex] = nil
    end
end

-- Where the game's logo can come from, best first: { name, file }.
function AfkScreen.LogoSources()
    local list = {}
    local function Add(name, file)
        if file ~= nil and not IsSecret(file) and file ~= 0 and file ~= "" then
            list[#list + 1] = { name, file }
        end
    end
    local info = C_GameRules and Call(C_GameRules.GetCurrentGameModeDisplayInfo)
    Add("game mode logo", type(info) == "table" and info.logo or nil)
    local level = Call(GetClientDisplayExpansionLevel)
    if type(level) == "number" and not IsSecret(level) then
        local exp = Call(GetExpansionDisplayInfo, level)
        Add("expansion " .. level .. " logo", type(exp) == "table" and exp.logo or nil)
    end
    Add("classic logo file", "Interface\\Glues\\Common\\Glues-WoW-ClassicLogo")
    Add("original logo file", "Interface\\Glues\\Common\\Glues-WoW-Logo")
    return list
end

-- /zt afk: what the AFK screen finds for its pictures.
function AfkScreen.Report()
    root.Print("AFK screen " .. (root.ModuleOn("afk") and "is on." or "is switched off."))
    local test = (card and card.center) or CreateFrame("Frame"):CreateTexture()
    for _, source in ipairs(AfkScreen.LogoSources()) do
        local ok, loaded = pcall(test.SetTexture, test, source[2])
        root.Print("logo: " .. source[1] .. " (" .. tostring(source[2]) .. "): "
            .. ((ok and loaded ~= false) and "loads" or "does not load"))
    end
    if #AfkScreen.LogoSources() == 0 then
        root.Print("logo: the game offers none")
    end
    local token = ClassToken()
    if token then
        for _, name in ipairs(AfkScreen.CrestAtlases(token, "class")) do
            local info = C_Texture and Call(C_Texture.GetAtlasInfo, name)
            root.Print("class crest: " .. name .. ": " .. (type(info) == "table"
                and ("in the game, " .. tostring(info.width) .. " x " .. tostring(info.height))
                or "not in the game"))
        end
        local ok, loaded = pcall(test.SetTexture, test, AfkScreen.CrestFile(token))
        root.Print("class crest: " .. AfkScreen.CrestFile(token) .. ": "
            .. ((ok and loaded ~= false) and "loads" or "does not load"))
    end
    root.Print("class icon: " .. tostring(token and GetClassAtlas and Call(GetClassAtlas, token) or "none"))
    root.Print("faction: " .. tostring(Faction() or "none"))
    AfkScreen.CheckLean()
    if card and card:IsShown() then
        AfkScreen.Layout()
    end
end

-- /zt afk: whether your character's model has the lean animations. Loads
-- your character into an invisible model and answers 1.5 s later, once the
-- model has had time to load.
local probe
function AfkScreen.CheckLean()
    if not probe then
        local ok, m = pcall(CreateFrame, "PlayerModel", nil, UIParent)
        if not ok or not m then
            root.Print("lean: no model to check with")
            return
        end
        probe = m
        probe:SetSize(64, 64)
        probe:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
        probe:SetAlpha(0)
    end
    probe:Show()
    pcall(probe.SetUnit, probe, "player")
    root.Print("lean: checking your character's model...")
    C_Timer.After(1.5, function()
        AfkScreen.ReportLean(probe)
        probe:Hide()
    end)
end

function AfkScreen.ReportLean(m)
    if not m.HasAnimation then
        root.Print("lean: the game can't say which animations a model has")
        return
    end
    local ok, stands = pcall(m.HasAnimation, m, A_STAND)
    if not ok or stands ~= true then
        root.Print("lean: your character's model didn't load in time, try /zt afk again")
        return
    end
    for _, check in ipairs(AfkScreen.LEAN_CHECKS) do
        local okHas, has = pcall(m.HasAnimation, m, check[1])
        root.Print("lean: " .. check[2] .. " (" .. check[1] .. "): "
            .. ((okHas and has == true) and "yes" or "no"))
    end
end

-- Puts a picture on a texture. kind "logo", "class" or "faction".
-- Returns width, height, or nil when there is nothing to show.
function AfkScreen.SetPicture(tex, kind, big)
    if kind == "logo" then
        tex:SetTexCoord(0, 1, 0, 1)
        for _, source in ipairs(AfkScreen.LogoSources()) do
            local ok, loaded = pcall(tex.SetTexture, tex, source[2])
            if ok and loaded ~= false then
                AfkScreen.logoUsed = source[1]
                return 256, 128
            end
        end
        AfkScreen.logoUsed = nil
        return nil
    elseif kind == "class" or kind == "medallion" then
        local token = ClassToken()
        if not token then
            return nil
        end
        -- The class crest: the toolkit's own crest picture, else a crest
        -- picture the game has, else the crest_<class> icon cut round so its
        -- dark square corners go.
        local bundled = kind == "class" and AfkScreen.BundledCrest(token)
        if bundled then
            local ok, loaded = pcall(tex.SetTexture, tex, bundled)
            if ok and loaded ~= false then
                tex:SetTexCoord(0, 1, 0, 1)
                AfkScreen.crestUsed = bundled
                return AfkScreen.CREST_SIZE, AfkScreen.CREST_SIZE
            end
        end
        for _, name in ipairs(AfkScreen.CrestAtlases(token, kind)) do
            local info = C_Texture and Call(C_Texture.GetAtlasInfo, name)
            if type(info) == "table" and tex.SetAtlas and pcall(tex.SetAtlas, tex, name) then
                local w, h = tonumber(info.width) or 1, tonumber(info.height) or 1
                local s = AfkScreen.CREST_SIZE / math.max(w, h, 1)
                AfkScreen.crestUsed = name
                return math.floor(w * s + 0.5), math.floor(h * s + 0.5)
            end
        end
        AfkScreen.crestUsed = AfkScreen.CrestFile(token)
        local ok, loaded = pcall(tex.SetTexture, tex, AfkScreen.CrestFile(token))
        if ok and loaded ~= false then
            tex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
            AfkScreen.SetRound(tex, true)
            return big, big
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

-- Bar shading: darkest at the screen edge, lighter toward the middle of the
-- screen, then a soft fade above (below, for the top bar) so there is no hard
-- edge. Alphas: at the edge, at the bar's inner edge; FADE pixels of fade.
AfkScreen.SHADE = { edge = 0.95, inner = 0.5, fade = 120 }

local function Shade(tex, fromAlpha, toAlpha)
    -- fromAlpha at the bottom of the texture, toAlpha at its top. A gradient
    -- needs a real (white) texture under it; on a plain colour fill it does
    -- nothing (seen in game: the bar stayed solid).
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    tex:SetVertexColor(1, 1, 1, 1)
    if tex.SetGradient and CreateColor then
        local ok = pcall(tex.SetGradient, tex, "VERTICAL",
            CreateColor(0.04, 0.035, 0.03, fromAlpha), CreateColor(0.04, 0.035, 0.03, toAlpha))
        if ok then
            return
        end
    end
    tex:SetColorTexture(0.04, 0.035, 0.03, (fromAlpha + toAlpha) / 2)
end

-- atTop: the bar along the top of the screen (dark at the top edge).
local function Bar(parent, atTop)
    local f = CreateFrame("Frame", nil, parent)
    local sh = AfkScreen.SHADE
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local fade = f:CreateTexture(nil, "BACKGROUND")
    fade:SetHeight(sh.fade)
    if atTop then
        Shade(bg, sh.inner, sh.edge)
        fade:SetPoint("TOPLEFT", f, "BOTTOMLEFT")
        fade:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT")
        Shade(fade, 0, sh.inner)
    else
        Shade(bg, sh.edge, sh.inner)
        fade:SetPoint("BOTTOMLEFT", f, "TOPLEFT")
        fade:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT")
        Shade(fade, sh.inner, 0)
    end
    f.fade = fade
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
    card.top = Bar(card, true)
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
    card.centerLayers = {}
    for i = 2, AfkScreen.EMBLEM_LAYERS do
        card.centerLayers[i - 1] = text:CreateTexture(nil, "OVERLAY")
    end

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
    -- The corner text stays in the corner; the character stands on the bar
    -- above it, feet a little into the bar (the text is drawn over them).
    local leftIn, rightIn = 40, 40
    if m then
        m:ClearAllPoints()
        m:SetSize(modelW, modelH)
        local feet = barH - math.floor(modelH * AfkScreen.FEET_RATIO + 0.5)
        if side == "left" then
            m:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 20, feet)
        elseif side == "right" then
            m:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -20, feet)
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

    -- All text sits low, near the bottom edge, stacked upward from there.
    local low = AfkScreen.TEXT_LOW
    local hasGuild = (card.guild:GetText() or "") ~= ""
    local hasTimer = card.reason == "afk"
    if not two then
        -- Left: crest, name, level and class, guild (bottom line).
        local x = leftIn
        if crestOn then
            card.crest:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", x, low)
            x = x + crestSize + 10
        end
        if hasGuild then
            card.guild:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", x, low)
            card.desc:SetPoint("BOTTOMLEFT", card.guild, "TOPLEFT", 0, 4)
        else
            card.desc:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", x, low)
        end
        card.name:SetPoint("BOTTOMLEFT", card.desc, "TOPLEFT", 0, 4)
        -- Right: date and time (bottom line), away timer or where you are above.
        card.clock:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -rightIn, low)
        card.dateText:SetPoint("RIGHT", card.clock, "LEFT", -8, 0)
        if hasTimer then
            card.big:SetPoint("BOTTOMRIGHT", card.clock, "TOPRIGHT", 0, 4)
            card.caption:SetPoint("BOTTOMRIGHT", card.big, "TOPRIGHT", 0, 2)
        else
            card.big:SetPoint("BOTTOMRIGHT", card.clock, "TOPRIGHT", 0, 4)
            card.caption:SetPoint("BOTTOMRIGHT", card.clock, "TOPRIGHT", 0, 4)
        end
    else
        -- Top bar: date left, local time right.
        card.topDate:SetPoint("LEFT", card.top, "LEFT", 24, 0)
        card.clock:SetPoint("RIGHT", card.top, "RIGHT", -24, 0)
        card.topClockLabel:SetPoint("RIGHT", card.clock, "LEFT", -6, 0)
        -- Bottom bar: name in the middle, crest and away timer on the left.
        if hasGuild then
            card.guild:SetPoint("BOTTOM", card, "BOTTOM", 0, low)
            card.desc:SetPoint("BOTTOM", card.guild, "TOP", 0, 4)
        else
            card.desc:SetPoint("BOTTOM", card, "BOTTOM", 0, low)
        end
        card.name:SetPoint("BOTTOM", card.desc, "TOP", 0, 4)
        local x = leftIn
        if crestOn then
            card.crest:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", x, low)
            x = x + crestSize + 10
        end
        card.big:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", x, low)
        if hasTimer then
            card.caption:SetPoint("BOTTOMLEFT", card.big, "TOPLEFT", 0, 2)
        else
            card.caption:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", x, low)
        end
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
    AfkScreen.SetRound(tex, false)
    AfkScreen.crestUsed = nil
    local w, h = AfkScreen.SetPicture(tex, Opt("center"), 112)
    -- The big emblem is see-through: more copies on top make it solid.
    local emblem = w and AfkScreen.IsEmblem(AfkScreen.crestUsed)
    for _, layer in ipairs(card.centerLayers) do
        if emblem and pcall(layer.SetAtlas, layer, AfkScreen.crestUsed) then
            layer:ClearAllPoints()
            layer:SetAllPoints(tex)
            layer:Show()
        else
            layer:Hide()
        end
    end
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

-- The animation itself, or standing when the model says it doesn't have
-- it (only a clear "no" counts; asked again every frame, so a model that
-- is still loading gets the real animation once it has loaded).
function AfkScreen.WithFallback(m, anim)
    if anim ~= A_STAND and m.HasAnimation then
        local ok, has = pcall(m.HasAnimation, m, anim)
        if ok and has == false then
            return A_STAND
        end
    end
    return anim
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
    local want = AfkScreen.WithFallback(m, AfkScreen.AnimAt(kind, shownFor))
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
    return root.db ~= nil and root.ModuleOn("afk")
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

root.OnModuleChanged("afk", function(on)
    if not on then
        AfkScreen.Stop()
    end
end)

-------------------------------------------------------------------------------
-- Settings page
-------------------------------------------------------------------------------

local function BuildPage()
    local UI = root.UI
    local panel = CreateFrame("Frame", "ZirisToolkitAfkOptions", UIParent)
    panel:Hide()
    local page = UI.ScrollArea(panel)
    local x, y = 16, -16

    local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", x, y)
    title:SetText("AFK screen")
    y = y - 26
    UI.Note(page, "When you go AFK, the interface hides, names and nameplates go, the camera circles your character and bars show who you are and how long you have been away. Moving, the Toggle UI key (Alt+Z) or a fight brings everything back. Switch it on or off on the Ziri's Toolkit page. Type /afk to try the look.", x, y)
    y = y - 58

    local p = DB()
    local on = function() return root.ModuleOn("afk") end
    local function Pick(label, tip, key, options)
        local h = UI.Choice(page, label, tip, x, y, options,
            function() return p[key] end,
            function(v) p[key] = v end, on)
        y = y - h - 6
    end
    Pick("Layout", "How the bars on the AFK screen are laid out.", "layout", {
        { value = "one", text = "Bottom bar", width = 150,
          tip = "One bar along the bottom: your name on the left, away timer, date and time on the right." },
        { value = "two", text = "Top and bottom bars", width = 170,
          tip = "Date and time in a bar at the top, your name in the middle of a bar at the bottom." },
    })
    Pick("Character", "Where your character stands on the AFK screen.", "side", {
        { value = "left", text = "Left" },
        { value = "right", text = "Right" },
        { value = "off", text = "None" },
    })
    UI.Slider(page, "Character size", "How big your character is on the AFK screen.", x, y, 1, 4, 1,
        function() return p.size end,
        function(v) p.size = math.floor(v + 0.5) end,
        { format = function(v) return AfkScreen.SIZE_NAMES[math.floor(v + 0.5)] or tostring(v) end })
    y = y - 52
    Pick("Facing", "Which way your character looks.", "facing", {
        { value = "in", text = "To the middle", width = 140 },
        { value = "front", text = "At you" },
        { value = "out", text = "Away" },
    })
    local anims = {}
    for _, key in ipairs(AfkScreen.ANIM_ORDER) do
        anims[#anims + 1] = { value = key, text = AfkScreen.ANIMS[key].text, width = 170 }
    end
    Pick("What the character does", "Your character on the AFK screen only; you don't do it in the game.", "anim", anims)
    Pick("Picture in the middle", "The picture in the middle of the AFK screen.", "center", {
        { value = "logo", text = "Game logo", tip = "The game's own World of Warcraft: Forever logo." },
        { value = "class", text = "Class crest", tip = "Your class's crest in full colour." },
        { value = "medallion", text = "Class medallion", width = 140, tip = "Your class's crest in a round medallion." },
        { value = "faction", text = "Alliance or Horde", width = 150 },
        { value = "none", text = "Nothing" },
    })
    UI.Check(page, "Alliance or Horde crest by your name", "Your faction's crest next to your name on the AFK screen.",
        x, y,
        function() return p.crest end,
        function(v) p.crest = v end, on)
    y = y - 40

    page:SetHeight(-y + 16)
    panel:SetScript("OnShow", UI.RefreshAll)
    AfkScreen.page = root.RegisterSubPage(panel, "AFK screen")
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        DB()
        local ok, err = pcall(BuildPage)
        if not ok then
            root.Print("the AFK screen page could not be built: " .. tostring(err))
        end
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
