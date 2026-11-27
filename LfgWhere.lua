-- Ziri's Toolkit: where players are, in Looking For Group
-- Hovering a listing in the game's Looking For Group window shows a small
-- box under Blizzard's tooltip with the zone of each player in it:
--   Where
--   Sylrea Shadow     Elwynn Forest
--   Sigurd Redmane    Stormwind City (3 min ago)
--   Meylin Nox        click to look up
--
-- The zone comes from the listing itself when the game sends it. When it
-- doesn't, a left-click on the listing looks up the next unknown player with
-- /who (the game only allows that on a click, about one every 5 seconds).
-- Zones are kept for this session only.

local ADDON_NAME, root = ...

local LfgWhere = {}
root.LfgWhere = LfgWhere

local IsSecret = root.IsSecret

local WHO_GAP = 5        -- seconds between /who lookups
local WHO_TIMEOUT = 6    -- give up on an answer after this long
local STALE = 120        -- a zone older than this is looked up again on click

local zones = {}         -- [lower name] = { zone = text or false, t = GetTime() }
local pending = nil      -- { key, name, t } while a /who is out
local lastWho = -WHO_GAP
local shownResult = nil  -- resultID the box is showing
local hookedEntries = setmetatable({}, { __mode = "k" })
local hooked = false
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
local function Key(name)
    return (name:gsub("%-.*$", "")):lower()
end

local function MyName()
    return Text(Safe(UnitName, "player"))
end

-- Leader first, then the others, each { name, area }.
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
    local leader = Safe(C_LFGList.GetSearchResultLeaderInfo, resultID)
    if type(leader) == "table" and Text(leader.name) then
        list[1] = { name = leader.name, area = Text(leader.areaName) }
    end
    if count > 1 and count <= 40 then
        for i = 1, count do
            local m = Safe(C_LFGList.GetSearchResultPlayerInfo, resultID, i)
            if type(m) == "table" and Text(m.name) and not (IsSecret(m.isLeader) or m.isLeader) then
                list[#list + 1] = { name = m.name, area = Text(m.areaName) }
            end
        end
    end
    return list
end

local function Ago(t)
    local s = GetTime() - t
    if s < 60 then
        return nil
    end
    return ("%d min ago"):format(math.floor(s / 60))
end

-- Zone text and colour for one member, plus whether it still needs a lookup.
local function Where(member)
    local me = MyName()
    if me and Key(member.name) == Key(me) then
        return Text(Safe(GetRealZoneText)) or "?", HIGHLIGHT_FONT_COLOR, false
    end
    if member.area then
        return member.area, HIGHLIGHT_FONT_COLOR, false
    end
    local key = Key(member.name)
    if pending and pending.key == key then
        return "looking up...", GRAY_FONT_COLOR, false
    end
    local known = zones[key]
    if known then
        local stale = GetTime() - known.t > STALE
        if known.zone then
            local ago = Ago(known.t)
            return ago and (known.zone .. " (" .. ago .. ")") or known.zone, HIGHLIGHT_FONT_COLOR, stale
        end
        return "not found", GRAY_FONT_COLOR, stale
    end
    return "click to look up", GRAY_FONT_COLOR, true
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
        local zone, color, missing = Where(member)
        anyMissing = anyMissing or missing
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
        local wait = math.ceil(lastWho + WHO_GAP - GetTime())
        if pending then
            box.hint:SetText("Looking up...")
        elseif wait > 0 then
            box.hint:SetText(("Click the listing again in %d s for the next one."):format(wait))
        else
            box.hint:SetText("Left-click the listing to look up the next one.")
        end
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

local function Finish(zone)
    if not pending then
        return
    end
    zones[pending.key] = { zone = zone or false, t = GetTime() }
    pending = nil
    RestoreWhoToUi()
    Redraw()
    -- and again when the next lookup is allowed, so the hint stays right
    C_Timer.After(math.max(0.1, lastWho + WHO_GAP - GetTime()), Redraw)
end

local function OnWhoList()
    if not pending then
        return
    end
    local count = Safe(C_FriendList.GetNumWhoResults) or 0
    for i = 1, count do
        local info = Safe(C_FriendList.GetWhoInfo, i)
        local name = type(info) == "table" and Text(info.fullName)
        if name and Key(name) == pending.key then
            Finish(Text(info.area))
            return
        end
    end
    Finish(nil)
end

-- Runs inside the click on a listing, so the game allows the /who.
local function LookUp(resultID)
    if pending or GetTime() - lastWho < WHO_GAP then
        Redraw()
        return
    end
    local list = Members(resultID)
    if not list then
        return
    end
    for _, member in ipairs(list) do
        local _, _, missing = Where(member)
        if missing then
            local key = Key(member.name)
            local plain = member.name:gsub("%-.*$", "")
            pending = { key = key, t = GetTime() }
            lastWho = GetTime()
            pcall(C_FriendList.SetWhoToUi, true)
            local ok = pcall(C_FriendList.SendWho, 'n-"' .. plain .. '"')
            if not ok then
                pending = nil
                RestoreWhoToUi()
            else
                C_Timer.After(WHO_TIMEOUT, function()
                    if pending and pending.key == key then
                        Finish(nil)
                    end
                end)
            end
            Redraw()
            return
        end
    end
end

-------------------------------------------------------------------------------
-- Hooks into Blizzard's Looking For Group window (loads on demand)
-------------------------------------------------------------------------------

local function HookEntry(entry)
    if hookedEntries[entry] or type(entry.HookScript) ~= "function" then
        return
    end
    hookedEntries[entry] = true
    entry:HookScript("OnClick", function(self, button)
        if button == "LeftButton" and root.ModuleOn("lfgWhere") and self.resultID and not self.hasSelf then
            pcall(LookUp, self.resultID)
        end
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
    if LFGBrowseSearchEntryTooltip then
        LFGBrowseSearchEntryTooltip:HookScript("OnHide", function()
            if box then box:Hide() end
            shownResult = nil
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
        local zone = Where(member)
        root.Print(("%s: zone from listing %s, shown \"%s\""):format(
            member.name, member.area and ('"' .. member.area .. '"') or "none", zone))
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("WHO_LIST_UPDATE")
events:SetScript("OnEvent", function(_, event)
    if event == "WHO_LIST_UPDATE" then
        pcall(OnWhoList)
    else
        Hook()
    end
end)
