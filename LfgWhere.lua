-- Ziri's Toolkit: where players are, in Looking For Group
-- Hovering a listing in the game's Looking For Group window shows a small
-- box under Blizzard's tooltip with the zone of each player in it:
--   Where
--   Sylrea Shadow     Elwynn Forest
--   Sigurd Redmane    Stormwind City (3 min ago)
--   Meylin Nox        not looked up yet
--
-- The zone comes from the listing itself when the game sends it. Otherwise
-- it is looked up with /who. The game only sends a /who during a key press
-- or click, about one every 5 seconds, so while the Looking For Group window
-- is open every key press or click there (walking, scrolling, clicking a
-- listing) sends the next lookup, in this order:
--   1. the group you are hovering: once its leader's zone is known, one
--      /who for that zone finds the members standing with the leader,
--      then the rest by name
--   2. everyone listed who is in your own zone, in one /who
--   3. the leaders of the listings on screen, one by name
-- Every player a /who returns is remembered, so one lookup often answers
-- for several listings. Zones are kept for this session only.

local ADDON_NAME, root = ...

local LfgWhere = {}
root.LfgWhere = LfgWhere

local IsSecret = root.IsSecret

local WHO_GAP = 5        -- seconds between /who lookups
local WHO_TIMEOUT = 6    -- give up on an answer after this long
local STALE = 120        -- a zone older than this is looked up again

local zones = {}         -- [lower name] = { zone = text or false, t = GetTime() }
local pending = nil      -- { kind = "name"/"zone", key, trigger } while a /who is out
local lastWho = -WHO_GAP
local shownResult = nil  -- resultID the box is showing
local sweptAt = nil      -- when your own zone was last looked up
local zoneTried = {}     -- ["resultID|zone"] = true: that group's zone query is done
local blocked = {}       -- [trigger] = true: the game refused a /who from it
local hookedEntries = setmetatable({}, { __mode = "k" })
local hooked = false
local keys = nil         -- frame that hears key presses while the window is open
local box

local function Safe(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn, ...)
    if not ok or IsSecret(v) then
        return nil
    end
    return v
end

local function Text(v)
    if v == nil or IsSecret(v) or type(v) ~= "string" or v == "" then
        return nil
    end
    return v
end

-- Names may come as "Name-Realm"; compare without the realm.
local function Plain(name)
    return (name:gsub("%-.*$", ""))
end

local function Key(name)
    return Plain(name):lower()
end

local function MyKey()
    local me = Text(Safe(UnitName, "player"))
    return me and Key(me)
end

local function Member(info)
    if type(info) ~= "table" or not Text(info.name) then
        return nil
    end
    local level = info.level
    if IsSecret(level) or type(level) ~= "number" then
        level = nil
    end
    return { name = info.name, key = Key(info.name), area = Text(info.areaName), level = level }
end

-- Leader first, then the others.
local function Members(resultID)
    local info = Safe(C_LFGList.GetSearchResultInfo, resultID)
    if type(info) ~= "table" then
        return nil
    end
    local count = info.numMembers
    if IsSecret(count) or type(count) ~= "number" then
        return nil
    end
    local list = {}
    local leader = Member(Safe(C_LFGList.GetSearchResultLeaderInfo, resultID))
    if leader then
        list[1] = leader
    end
    if count > 1 and count <= 40 then
        for i = 1, count do
            local raw = Safe(C_LFGList.GetSearchResultPlayerInfo, resultID, i)
            local m = Member(raw)
            if m and not (IsSecret(raw.isLeader) or raw.isLeader) then
                list[#list + 1] = m
            end
        end
    end
    return list
end

-- The zone we know for a member (nil if none), and whether to look it up.
local function Known(member)
    if member.key == MyKey() then
        return Text(Safe(GetRealZoneText)), false
    end
    if member.area then
        return member.area, false
    end
    local known = zones[member.key]
    if not known then
        return nil, true
    end
    return known.zone or nil, GetTime() - known.t > STALE
end

local function Ago(t)
    local s = GetTime() - t
    if s < 60 then
        return nil
    end
    return ("%d min ago"):format(math.floor(s / 60))
end

-- Text and colour for one member's zone in the box.
local function Shown(member)
    if pending and pending.kind == "name" and pending.key == member.key then
        return "looking up...", GRAY_FONT_COLOR
    end
    local zone = Known(member)
    local known = zones[member.key]
    if zone then
        local ago = not member.area and member.key ~= MyKey() and known and Ago(known.t)
        return ago and (zone .. " (" .. ago .. ")") or zone, HIGHLIGHT_FONT_COLOR
    end
    if known then
        return "not found", GRAY_FONT_COLOR
    end
    return "not looked up yet", GRAY_FONT_COLOR
end

-- Listings on screen, top to bottom where the list allows it.
local function VisibleResults()
    local ids, seen = {}, {}
    local scroll = LFGBrowseFrame and LFGBrowseFrame.ScrollBox
    if scroll and type(scroll.ForEachFrame) == "function" then
        pcall(scroll.ForEachFrame, scroll, function(frame)
            local id = frame.resultID
            if type(id) == "number" and not seen[id] and not frame.hasSelf then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end)
    end
    if #ids == 0 then
        local _, results = Safe(C_LFGList.GetSearchResults)
        for _, id in ipairs(type(results) == "table" and results or {}) do
            ids[#ids + 1] = id
        end
    end
    return ids
end

local function LevelRange(list)
    local low, high
    for _, m in ipairs(list) do
        if m.level then
            low = math.min(low or m.level, m.level)
            high = math.max(high or m.level, m.level)
        end
    end
    if low then
        return (" %d-%d"):format(low, high)
    end
    return ""
end

-- The next /who worth sending, or nil.
local function NextQuery()
    -- 1. the group under the mouse
    if shownResult and box and box:IsShown() then
        local list = Members(shownResult) or {}
        local missing = {}
        for _, m in ipairs(list) do
            local _, look = Known(m)
            if look then
                missing[#missing + 1] = m
            end
        end
        if #missing > 0 then
            local leaderZone = list[1] and Known(list[1])
            local tried = leaderZone and (shownResult .. "|" .. leaderZone)
            if leaderZone and #missing > 1 and not zoneTried[tried] then
                zoneTried[tried] = true
                return { kind = "zone", filter = 'z-"' .. leaderZone .. '"' .. LevelRange(missing) }
            end
            return { kind = "name", key = missing[1].key, filter = 'n-"' .. Plain(missing[1].name) .. '"' }
        end
    end

    local leaders = {}
    for _, id in ipairs(VisibleResults()) do
        local list = Members(id)
        local leader = list and list[1]
        if leader then
            local _, look = Known(leader)
            if look then
                leaders[#leaders + 1] = leader
            end
        end
    end
    if #leaders == 0 then
        return nil
    end

    -- 2. everyone listed who is where you are
    local here = Text(Safe(GetRealZoneText))
    if here and #leaders > 1 and (not sweptAt or GetTime() - sweptAt > STALE) then
        sweptAt = GetTime()
        return { kind = "zone", filter = 'z-"' .. here .. '"' .. LevelRange(leaders) }
    end

    -- 3. the next leader on screen
    local m = leaders[1]
    return { kind = "name", key = m.key, filter = 'n-"' .. Plain(m.name) .. '"' }
end

-------------------------------------------------------------------------------
-- The box under Blizzard's tooltip
-------------------------------------------------------------------------------

local rows = {}

local function Box()
    if box then
        return box
    end
    box = CreateFrame("Frame", "ZirisToolkitLfgWhere", UIParent, "TooltipBackdropTemplate")
    box:SetFrameStrata("TOOLTIP")
    box:Hide()
    box.title = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    box.title:SetPoint("TOPLEFT", 11, -10)
    box.title:SetText("Where")
    box.hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    box.hint:SetJustifyH("LEFT")
    return box
end

local function Row(i)
    local r = rows[i]
    if not r then
        r = {
            name = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"),
            zone = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"),
        }
        r.name:SetJustifyH("LEFT")
        r.zone:SetJustifyH("LEFT")
        rows[i] = r
    end
    return r
end

local function Draw(tooltip, resultID)
    local list = Members(resultID)
    Box()
    if not list or #list == 0 then
        box:Hide()
        return
    end
    shownResult = resultID

    local nameWidth, zoneWidth, anyMissing = 0, 0, false
    for i, member in ipairs(list) do
        local r = Row(i)
        local zone, color = Shown(member)
        local _, look = Known(member)
        anyMissing = anyMissing or look
        r.name:SetText(member.name)
        r.zone:SetText(zone)
        r.zone:SetTextColor(color.r, color.g, color.b)
        r.name:Show()
        r.zone:Show()
        nameWidth = math.max(nameWidth, r.name:GetStringWidth())
        zoneWidth = math.max(zoneWidth, r.zone:GetStringWidth())
    end
    for i = #list + 1, #rows do
        rows[i].name:Hide()
        rows[i].zone:Hide()
    end

    local y = -28
    for i = 1, #list do
        local r = rows[i]
        r.name:ClearAllPoints()
        r.name:SetPoint("TOPLEFT", 11, y)
        r.zone:ClearAllPoints()
        r.zone:SetPoint("TOPLEFT", 11 + nameWidth + 10, y)
        y = y - 14
    end

    local contentWidth = math.max(nameWidth + 10 + zoneWidth, box.title:GetStringWidth())
    if anyMissing then
        box.hint:SetText("Fills in as you press keys or click.")
        box.hint:ClearAllPoints()
        box.hint:SetPoint("TOPLEFT", 11, y - 4)
        box.hint:Show()
        contentWidth = math.max(contentWidth, box.hint:GetStringWidth())
        y = y - 18
    else
        box.hint:Hide()
    end

    local width = math.max(contentWidth + 22, tooltip:GetWidth())
    box:SetSize(width, -y + 8)
    box:ClearAllPoints()
    local bottom = tooltip:GetBottom()
    if bottom and bottom < box:GetHeight() + 4 then
        box:SetPoint("BOTTOMLEFT", tooltip, "TOPLEFT", 0, 2)
    else
        box:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 0, -2)
    end
    box:Show()
end

local function Redraw()
    local tooltip = LFGBrowseSearchEntryTooltip
    if box and box:IsShown() and tooltip and tooltip:IsShown() and shownResult then
        pcall(Draw, tooltip, shownResult)
    end
end

-------------------------------------------------------------------------------
-- /who lookups
-------------------------------------------------------------------------------

local function RestoreWhoToUi()
    local keep = LFGWhoListFrame and LFGWhoListFrame:IsShown() or false
    pcall(C_FriendList.SetWhoToUi, keep)
end

local function Finish()
    pending = nil
    RestoreWhoToUi()
    Redraw()
end

local function OnWhoList()
    if not pending then
        return
    end
    local now = GetTime()
    local found = false
    local count = Safe(C_FriendList.GetNumWhoResults) or 0
    for i = 1, count do
        local info = Safe(C_FriendList.GetWhoInfo, i)
        local name = type(info) == "table" and Text(info.fullName)
        if name then
            local key = Key(name)
            zones[key] = { zone = Text(info.area) or false, t = now }
            found = found or key == pending.key
        end
    end
    if pending.kind == "name" and not found then
        zones[pending.key] = { zone = false, t = now }
    end
    Finish()
end

-- Called from a key press or click (the game only sends a /who then).
local function Trigger(trigger)
    if pending or blocked[trigger] or not root.ModuleOn("lfgWhere") then
        return
    end
    if GetTime() - lastWho < WHO_GAP then
        return
    end
    local q = NextQuery()
    if not q then
        return
    end
    pending = { kind = q.kind, key = q.key, trigger = trigger }
    lastWho = GetTime()
    pcall(C_FriendList.SetWhoToUi, true)
    if not pcall(C_FriendList.SendWho, q.filter) then
        pending = nil
        RestoreWhoToUi()
        return
    end
    local sent = pending
    C_Timer.After(WHO_TIMEOUT, function()
        if pending == sent then
            if sent.kind == "name" then
                zones[sent.key] = { zone = false, t = GetTime() }
            end
            Finish()
        end
    end)
    Redraw()
end

-- The game refused a /who: stop asking from that kind of input.
local function OnBlocked(addon)
    if addon ~= ADDON_NAME or not pending then
        return
    end
    local trigger = pending.trigger
    blocked[trigger] = true
    pending = nil
    RestoreWhoToUi()
    if trigger == "key" then
        root.Print("Looking For Group zones: the game doesn't allow lookups on key presses, so clicks in the window do them instead.")
    elseif trigger == "wheel" then
        root.Print("Looking For Group zones: the game doesn't allow lookups while scrolling, so clicks in the window do them instead.")
    end
end

-------------------------------------------------------------------------------
-- Hooks into Blizzard's Looking For Group window (loads on demand)
-------------------------------------------------------------------------------

local function HookEntry(entry)
    if hookedEntries[entry] or type(entry) ~= "table" or type(entry.HookScript) ~= "function" then
        return
    end
    hookedEntries[entry] = true
    entry:HookScript("OnClick", function()
        pcall(Trigger, "click")
    end)
end

-- Key presses while the window is open. The keys still reach the game.
local function MakeKeys()
    if keys or not LFGParentFrame then
        return
    end
    if InCombatLockdown() then
        return -- try again after the fight
    end
    local f = CreateFrame("Frame", nil, LFGParentFrame)
    if not pcall(f.SetPropagateKeyboardInput, f, true) then
        return -- never take keys away from the game
    end
    keys = f
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function()
        pcall(Trigger, "key")
    end)
end

local function OnTooltip(tooltip, resultID)
    if not root.ModuleOn("lfgWhere") then
        if box then box:Hide() end
        return
    end
    for _, focus in ipairs(GetMouseFoci and GetMouseFoci() or {}) do
        if type(focus) == "table" and focus.resultID == resultID then
            HookEntry(focus)
        end
    end
    Draw(tooltip, resultID)
end

local function Hook()
    if hooked or type(LFGBrowseSearchEntryTooltip_UpdateAndShow) ~= "function" then
        return
    end
    hooked = true
    hooksecurefunc("LFGBrowseSearchEntryTooltip_UpdateAndShow", function(tooltip, resultID)
        local ok, err = pcall(OnTooltip, tooltip, resultID)
        if not ok and not root.lfgWhereError then
            root.lfgWhereError = true
            root.Print("Looking For Group zones: something went wrong: " .. tostring(err))
        end
    end)
    if type(LFGBrowseSearchEntry_Init) == "function" then
        hooksecurefunc("LFGBrowseSearchEntry_Init", function(entry)
            pcall(HookEntry, entry)
        end)
    end
    if LFGBrowseSearchEntryTooltip then
        LFGBrowseSearchEntryTooltip:HookScript("OnHide", function()
            if box then box:Hide() end
            shownResult = nil
        end)
    end
    local scroll = LFGBrowseFrame and LFGBrowseFrame.ScrollBox
    if scroll and type(scroll.HookScript) == "function" then
        scroll:HookScript("OnMouseWheel", function()
            pcall(Trigger, "wheel")
        end)
    end
end

root.OnModuleChanged("lfgWhere", function(on)
    if not on and box then
        box:Hide()
    end
end)

-- /zt lfg: what the game sends for the listing you hovered last.
function LfgWhere.Report()
    local off = {}
    for trigger in pairs(blocked) do
        off[#off + 1] = trigger
    end
    if #off > 0 then
        table.sort(off)
        root.Print("lookups the game refused this session: " .. table.concat(off, ", "))
    end
    if not shownResult then
        root.Print("hover a listing in Looking For Group first, then type /zt lfg again.")
        return
    end
    local list = Members(shownResult)
    if not list then
        root.Print("that listing is gone.")
        return
    end
    for _, member in ipairs(list) do
        root.Print(("%s: zone from listing %s, shown \"%s\""):format(
            member.name, member.area and ('"' .. member.area .. '"') or "none", (Shown(member))))
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("WHO_LIST_UPDATE")
events:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "WHO_LIST_UPDATE" then
        pcall(OnWhoList)
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        sweptAt = nil -- new listings: look around your zone again
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        pcall(OnBlocked, arg1)
    else
        Hook()
        MakeKeys()
    end
end)
