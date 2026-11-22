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

-- The old size steps (character height in interface pixels); only used to
-- move old settings over to the size slider.
AfkScreen.SIZES = { 260, 340, 430, 540 }

-- Character size slider: height in interface pixels.
AfkScreen.HEIGHT_MIN, AfkScreen.HEIGHT_MAX, AfkScreen.HEIGHT_STEP = 150, 1600, 10

-- Animation numbers of the game's character models.
local A_STAND, A_WAVE, A_CHEER, A_DANCE, A_SIT = 0, 67, 68, 69, 97
-- The lean NPCs do against walls (WALean01). No emote plays it, but the
-- character models from Warlords of Draenor on should have it (unverified on
-- Forever); a model without it
-- stands instead.
local A_LEAN = 1260

-- What /zt afk checks on your character's model.
AfkScreen.LEAN_CHECKS = {
    { 1260, "lean" }, { 1262, "lean and scrub" }, { 1264, "lean 3" }, { 1266, "lean and talk" },
}

-- The few choices that are more than one animation; every other choice is
-- an animation number from root.AnimData (AnimData.lua).
AfkScreen.ANIM_ORDER = { "wave", "stand", "turn", "cheer" }
AfkScreen.ANIMS = {
    wave = { text = "Wave, then stand" },
    stand = { text = "Stand still" },
    turn = { text = "Turn slowly" },
    cheer = { text = "Cheer now and then" },
}
-- Choices that used to be named and are numbers now.
AfkScreen.OLD_ANIMS = { dance = A_DANCE, sit = A_SIT, sleep = 100, lean = A_LEAN }

-- The model frame leaves empty space under the feet that grows with the
-- character's size; this much of the height is moved down into the bar so
-- the feet stand on it (seen in game: 70 of 430 is right).
AfkScreen.FEET_RATIO = 0.163

-- The lowest line of text sits this far above the bottom edge (pixels).
AfkScreen.TEXT_LOW = 30

-- Model facing in radians; positive turns it toward the right of the screen.
AfkScreen.FACE_ANGLE = 0.6

-- show:   your character on the AFK screen at all
-- x:      across the screen, 0-100 % (middle of the character)
-- y:      up from standing on the bar, % of the screen height
-- z:      which way the character faces, degrees (0 = at you)
-- height: character size in interface pixels
AfkScreen.DEFAULTS = {
    layout = "one", show = true, x = 92, y = 0, z = 325, height = 430, anim = "wave",
    center = "logo", crest = true,
}
-- Older settings, moved over to the ones above once.
AfkScreen.LEGACY = { "side", "size", "facing" }

-- Radians for the model from the z setting in degrees.
function AfkScreen.FacingRad(z)
    return (tonumber(z) or 0) * math.pi / 180
end

-- Degrees (0-355, steps of 5) from radians.
function AfkScreen.Degrees(rad)
    local d = math.floor(rad * 180 / math.pi / 5 + 0.5) * 5
    return d % 360
end

-- Moves the old fixed choices (left/right, four sizes, three facings,
-- named animations) over to the sliders and animation numbers.
function AfkScreen.Migrate(a)
    if a.height == nil and (a.size ~= nil or a.side ~= nil or a.facing ~= nil) then
        local side = a.side or "right"
        a.height = AfkScreen.SIZES[a.size] or 430
        a.show = side ~= "off"
        a.x = (side == "left") and 8 or 92
        a.z = AfkScreen.Degrees(AfkScreen.Facing(side == "left" and "left" or "right", a.facing or "in"))
    end
    for _, key in ipairs(AfkScreen.LEGACY) do
        a[key] = nil
    end
    if type(a.anim) == "string" and AfkScreen.OLD_ANIMS[a.anim] then
        a.anim = AfkScreen.OLD_ANIMS[a.anim]
    end
end

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
            for _, key in ipairs(AfkScreen.LEGACY) do
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
    AfkScreen.Migrate(db.afk)
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
    if type(kind) == "number" then
        return kind
    elseif kind == "wave" then
        return t < 2.6 and A_WAVE or A_STAND
    elseif kind == "cheer" then
        return (t % 15) < 2.6 and A_CHEER or A_STAND
    end
    return A_STAND
end

-- Facing for the old side and facing choices (moving old settings over).
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
-- An invisible model of your character, to ask which animations it has.
-- Shown while asked for; loading takes a moment.
function AfkScreen.LoadProbe()
    if not probe then
        local ok, m = pcall(CreateFrame, "PlayerModel", nil, UIParent)
        if not ok or not m then
            return nil
        end
        probe = m
        probe:SetSize(64, 64)
        probe:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
        probe:SetAlpha(0)
    end
    probe:Show()
    pcall(probe.SetUnit, probe, "player")
    return probe
end

function AfkScreen.HideProbe()
    if probe then
        probe:Hide()
    end
end

-- true / false when the loaded model says, nil when it can't say yet.
function AfkScreen.ModelHas(anim, model)
    local m = model or probe
    if not m or not m.HasAnimation then
        return nil
    end
    local ok, loaded = pcall(m.HasAnimation, m, A_STAND)
    if not ok or loaded ~= true then
        return nil
    end
    local okHas, has = pcall(m.HasAnimation, m, anim)
    if not okHas or type(has) ~= "boolean" then
        return nil
    end
    return has
end

function AfkScreen.CheckLean()
    local m = AfkScreen.LoadProbe()
    if not m then
        root.Print("lean: no model to check with")
        return
    end
    root.Print("lean: checking your character's model...")
    C_Timer.After(1.5, function()
        AfkScreen.ReportLean(m)
        if not (AfkScreen.page and AfkScreen.pagePanel and AfkScreen.pagePanel:IsShown()) then
            m:Hide()
        end
    end)
end

-- Name of an animation choice, for the dropdown.
function AfkScreen.AnimName(v)
    if type(v) == "string" and AfkScreen.ANIMS[v] then
        return AfkScreen.ANIMS[v].text
    end
    for _, group in ipairs(root.AnimData or {}) do
        for _, item in ipairs(group.list) do
            if item[1] == v then
                return item[2]
            end
        end
    end
    return "Animation " .. tostring(v)
end

-- Fills the animation dropdown: the special choices, then a submenu per
-- group with the animations your character's model has (all of them while
-- the model is still loading). Returns how many animations were offered.
AfkScreen.MENU_ROWS = 18
function AfkScreen.FillAnimMenu(rootDesc, get, set)
    local function IsSelected(v) return get() == v end
    local function SetSelected(v) set(v) end
    for _, key in ipairs(AfkScreen.ANIM_ORDER) do
        rootDesc:CreateRadio(AfkScreen.ANIMS[key].text, IsSelected, SetSelected, key)
    end
    if rootDesc.CreateDivider then
        rootDesc:CreateDivider()
    end
    local offered = 0
    for _, group in ipairs(root.AnimData or {}) do
        local items = {}
        for _, item in ipairs(group.list) do
            if AfkScreen.ModelHas(item[1]) ~= false then
                items[#items + 1] = item
            end
        end
        if #items > 0 then
            local sub = rootDesc:CreateButton(group.name)
            for _, item in ipairs(items) do
                sub:CreateRadio(item[2], IsSelected, SetSelected, item[1])
            end
            if #items > AfkScreen.MENU_ROWS and sub.SetScrollMode then
                sub:SetScrollMode(AfkScreen.MENU_ROWS * 20)
            end
            offered = offered + #items
        end
    end
    return offered
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
    card.editor = false -- the preview panel, built the first time it is needed
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

-- Where the character's feet go: pixels from the left edge, and pixels up
-- from standing on the bar, for the x and y settings (both in %).
function AfkScreen.ModelSpot(w, h, x, y)
    w = (type(w) == "number" and w > 0) and w or 1920
    h = (type(h) == "number" and h > 0) and h or 1080
    return math.floor(w * (tonumber(x) or 92) / 100 + 0.5), math.floor(h * (tonumber(y) or 0) / 100 + 0.5)
end

-- Places everything for the current options.
function AfkScreen.Layout()
    local two = Opt("layout") == "two"
    local barH = two and 104 or 124
    local m = card.model
    local modelH = math.max(AfkScreen.HEIGHT_MIN, math.min(AfkScreen.HEIGHT_MAX, tonumber(Opt("height")) or 430))
    local modelW = math.floor(modelH * 0.55)
    -- The corner text stays in the corner; the character stands on the bar
    -- above it, feet a little into the bar (the text is drawn over them).
    local leftIn, rightIn = 40, 40
    if m then
        m:ClearAllPoints()
        m:SetSize(modelW, modelH)
        local feet = barH - math.floor(modelH * AfkScreen.FEET_RATIO + 0.5)
        local x, y = AfkScreen.ModelSpot(card:GetWidth(), card:GetHeight(), Opt("x"), Opt("y"))
        m:SetPoint("BOTTOM", card, "BOTTOMLEFT", x, feet + y)
        m:SetShown(Opt("show") and true or false)
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
            m.facing = AfkScreen.FacingRad(Opt("z"))
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
    local wasPreview = AfkScreen.previewing
    AfkScreen.previewing = false
    if card then
        if card.editor then
            card.editor:Hide()
        end
        card:Hide()
    end
    -- The settings window stayed open underneath: show what was changed.
    if wasPreview then
        pcall(root.UI.RefreshAll)
        if AfkScreen.ShowAnimChoice then
            pcall(AfkScreen.ShowAnimChoice)
        end
    end
end

-------------------------------------------------------------------------------
-- Preview: the AFK screen with a small panel on it to change the look and
-- see each change at once. The settings window stays open underneath (it
-- hides with the rest of the interface) and is back after Done.
-------------------------------------------------------------------------------

-- Puts the current options on the card at once: place, size, facing, and
-- the chosen animation from its start.
function AfkScreen.ApplyLive()
    if not (card and card:IsShown()) then
        return
    end
    AfkScreen.Layout()
    local m = card.model
    if m then
        m.facing = AfkScreen.FacingRad(Opt("z"))
        pcall(m.SetFacing, m, m.facing)
        m.applied = nil
        shownFor = 0
    end
    if card.editor and card.editor.ShowAnim then
        card.editor.ShowAnim()
    end
end

-- The animation choices in order: the special ones, then every listed
-- animation the AFK screen's model has (all while it can't say yet).
function AfkScreen.AnimChoices(model)
    local list = {}
    for _, key in ipairs(AfkScreen.ANIM_ORDER) do
        list[#list + 1] = key
    end
    for _, group in ipairs(root.AnimData or {}) do
        for _, item in ipairs(group.list) do
            if AfkScreen.ModelHas(item[1], model) ~= false then
                list[#list + 1] = item[1]
            end
        end
    end
    return list
end

-- The next (step 1) or previous (step -1) animation choice.
function AfkScreen.StepAnim(step)
    local p = DB()
    local list = AfkScreen.AnimChoices(card and card.model)
    local at = 0
    for i, v in ipairs(list) do
        if v == p.anim then
            at = i
        end
    end
    at = ((at - 1 + step) % #list) + 1
    p.anim = list[at]
    AfkScreen.ApplyLive()
    return at, #list
end

local editorRefreshers = {}
local function BuildEditor()
    if card.editor then
        return card.editor
    end
    local UI = root.UI
    local p = DB()
    local f = CreateFrame("Frame", nil, card, "BackdropTemplate")
    f:SetFrameLevel((card:GetFrameLevel() or 1) + 50)
    f:SetSize(312, 386)
    f:SetPoint("TOP", card, "TOP", 0, -60)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0, 0, 0, 0.85)
    end
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("AFK screen preview")
    local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPRIGHT", -14, -14)
    hint:SetText("Drag to move")

    local y = -38
    local function Slide(label, key, minV, maxV, step, format)
        UI.Slider(f, label, "", 10, y, minV, maxV, step,
            function() return p[key] end,
            function(v) p[key] = v end,
            { format = format, refreshers = editorRefreshers, after = AfkScreen.ApplyLive })
        y = y - 52
    end
    Slide("Across (X)", "x", 0, 100, 1, function(v) return v .. " %" end)
    Slide("Up (Y)", "y", -20, 80, 1, function(v) return v .. " %" end)
    Slide("Turn (Z)", "z", 0, 355, 5, function(v) return v .. " degrees" end)
    Slide("Character size", "height", AfkScreen.HEIGHT_MIN, AfkScreen.HEIGHT_MAX, AfkScreen.HEIGHT_STEP,
        function(v) return tostring(v) end)

    local animTitle = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    animTitle:SetPoint("TOPLEFT", 14, y)
    animTitle:SetText("What the character does")
    local prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    prev:SetSize(32, 22)
    prev:SetPoint("TOPLEFT", 14, y - 18)
    prev:SetText("<")
    local nextB = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nextB:SetSize(32, 22)
    nextB:SetPoint("TOPRIGHT", -14, y - 18)
    nextB:SetText(">")
    local name = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    name:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    name:SetPoint("RIGHT", nextB, "LEFT", -6, 0)
    local count = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    count:SetPoint("TOP", name, "BOTTOM", 0, -6)
    f.ShowAnim = function()
        name:SetText(AfkScreen.AnimName(p.anim))
        local list = AfkScreen.AnimChoices(card.model)
        local at
        for i, v in ipairs(list) do
            if v == p.anim then
                at = i
            end
        end
        count:SetText(at and (at .. " of " .. #list) or "")
    end
    prev:SetScript("OnClick", function() AfkScreen.StepAnim(-1) end)
    nextB:SetScript("OnClick", function() AfkScreen.StepAnim(1) end)
    y = y - 70

    local done = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    done:SetSize(120, 24)
    done:SetPoint("TOP", f, "TOP", 0, y)
    done:SetText("Done")
    done:SetScript("OnClick", function() AfkScreen.EndPreview() end)
    f.done = done

    f:Hide()
    card.editor = f
    return f
end

function AfkScreen.Preview()
    if InCombatLockdown() then
        root.Print("the AFK screen preview can't open during a fight")
        return
    end
    if not root.ModuleOn("afk") then
        root.Print("switch the AFK screen on first (Ziri's Toolkit page)")
        return
    end
    if ours then
        return
    end
    AfkScreen.Start()
    if not (ours and card and card:IsShown()) then
        return
    end
    AfkScreen.previewing = true
    local f = BuildEditor()
    for _, refresh in ipairs(editorRefreshers) do
        refresh()
    end
    f:Show()
    f.ShowAnim()
end

-- Hiding the card (HideCard) ends the preview and refreshes the settings.
function AfkScreen.EndPreview()
    AfkScreen.Stop()
    if AfkScreen.previewing then
        AfkScreen.HideCard()
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

    UI.Button(page, "Preview and adjust",
        "Shows the AFK screen with a small panel on it for where your character stands, its size and what it does, so you see each change at once. Done brings these settings back.",
        x + 4, y, 170, AfkScreen.Preview)
    y = y - 34

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
    UI.Check(page, "Show your character", "Your character in 3D on the AFK screen.", x, y,
        function() return p.show end,
        function(v) p.show = v end, on)
    y = y - 32
    local function Slide(label, tip, key, minV, maxV, step, format)
        UI.Slider(page, label, tip, x, y, minV, maxV, step,
            function() return p[key] end,
            function(v) p[key] = v end,
            { format = format })
        y = y - 52
    end
    Slide("Across (X)", "Where your character stands, from the left edge (0) to the right edge (100).", "x",
        0, 100, 1, function(v) return v .. " %" end)
    Slide("Up (Y)", "How high your character stands: 0 is on the bar, higher numbers lift it up the screen, lower ones sink it into the bar.", "y",
        -20, 80, 1, function(v) return v .. " %" end)
    Slide("Turn (Z)", "Which way your character faces, all the way round: 0 is at you, 180 is away from you.", "z",
        0, 355, 5, function(v) return v .. " degrees" end)
    Slide("Character size", "How tall your character is on the AFK screen, in interface pixels.", "height",
        AfkScreen.HEIGHT_MIN, AfkScreen.HEIGHT_MAX, AfkScreen.HEIGHT_STEP, function(v) return tostring(v) end)

    local animTitle = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    animTitle:SetPoint("TOPLEFT", x + 4, y)
    animTitle:SetText("What the character does")
    local okDd, dd = pcall(CreateFrame, "DropdownButton", nil, page, "WowStyle1DropdownTemplate")
    if okDd and dd then
        dd:SetPoint("TOPLEFT", x + 4, y - 18)
        dd:SetWidth(280)
        local function ShowChoice()
            if dd.OverrideText then
                dd:OverrideText(AfkScreen.AnimName(p.anim))
            end
        end
        dd:SetupMenu(function(_, rootDesc)
            AfkScreen.FillAnimMenu(rootDesc,
                function() return p.anim end,
                function(v)
                    p.anim = v
                    ShowChoice()
                end)
        end)
        ShowChoice()
        AfkScreen.ShowAnimChoice = ShowChoice
        UI.AddTooltip(dd, "What the character does",
            "Your character on the AFK screen only; you don't do it in the game. Animations your character's model doesn't have are left out.")
    end
    y = y - 52
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
    panel:SetScript("OnShow", function()
        UI.RefreshAll()
        if AfkScreen.ShowAnimChoice then
            AfkScreen.ShowAnimChoice()
        end
        -- So the animation list knows what your character's model has.
        AfkScreen.LoadProbe()
    end)
    panel:SetScript("OnHide", AfkScreen.HideProbe)
    AfkScreen.pagePanel = panel
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
