-- Ziri's Toolkit: tidy friends list
-- Battle.net friends who are online somewhere you can't join them (another
-- rule set, another WoW version, another game, the Battle.net app) move to
-- the bottom of the friends list, below your offline friends. Nobody is
-- removed: switch this off and the list is back to normal.
--
-- "Can't join them" is the game's own answer: the same check that greys out
-- the invite button next to a friend's name. Favorites always stay on top.

local ADDON_NAME, root = ...

local Friends = {}
root.Friends = Friends

local IsSecret = root.IsSecret
local hooked = false

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

-- FriendsFrame_GetInviteRestriction() answers 9 when a friend can be
-- invited (INVITE_RESTRICTION_NONE, a local in Blizzard's Forever code).
local INVITE_OK = 9

-- True if this Battle.net friend is online but you can't group with them.
function Friends.OutOfReach(index)
    local info = Safe(C_BattleNet and C_BattleNet.GetFriendAccountInfo, index)
    if type(info) ~= "table" or info.isFavorite then
        return false
    end
    local game = info.gameAccountInfo
    if type(game) ~= "table" or not game.isOnline then
        return false -- offline friends stay where they are
    end
    local restriction = Safe(FriendsFrame_GetInviteRestriction, index)
    if type(restriction) ~= "number" then
        return false -- unknown: leave them alone
    end
    return restriction ~= INVITE_OK
end

local function Rebuild()
    if not root.ModuleOn("friends") then
        return
    end
    if not (FriendsListFrame and FriendsListFrame:IsShown() and FriendsListFrame.ScrollBox) then
        return
    end
    local box = FriendsListFrame.ScrollBox
    local old = box.GetDataProvider and box:GetDataProvider()
    if not old or type(old.Enumerate) ~= "function" or type(CreateDataProvider) ~= "function" then
        return
    end
    local BNET = FRIENDS_BUTTON_TYPE_BNET
    local DIVIDER = FRIENDS_BUTTON_TYPE_DIVIDER

    local kept, moved = {}, {}
    for _, element in old:Enumerate() do
        if element.buttonType == BNET and Friends.OutOfReach(element.id) then
            moved[#moved + 1] = element
        else
            kept[#kept + 1] = element
        end
    end
    if #moved == 0 then
        return
    end
    -- Removing people can leave two dividers in a row (or one at the end).
    local tidy = {}
    for _, element in ipairs(kept) do
        local last = tidy[#tidy]
        if not (element.buttonType == DIVIDER and (last == nil or last.buttonType == DIVIDER)) then
            tidy[#tidy + 1] = element
        end
    end
    if tidy[#tidy] and tidy[#tidy].buttonType == DIVIDER then
        tidy[#tidy] = nil
    end

    local provider = CreateDataProvider()
    for _, element in ipairs(tidy) do
        provider:Insert(element)
    end
    if #tidy > 0 then
        provider:Insert({ buttonType = DIVIDER })
    end
    for _, element in ipairs(moved) do
        provider:Insert(element)
    end
    local keepScroll = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    box:SetDataProvider(provider, keepScroll)
end

local function Hook()
    if hooked or type(FriendsList_Update) ~= "function" then
        return
    end
    hooked = true
    hooksecurefunc("FriendsList_Update", function()
        local ok, err = pcall(Rebuild)
        if not ok and not root.friendsError then
            root.friendsError = true
            root.Print("friends list: something went wrong: " .. tostring(err))
        end
    end)
end

-- Redraws the list now (after switching the part on or off).
function Friends.Refresh()
    Hook()
    if FriendsListFrame and FriendsListFrame:IsShown() and type(FriendsList_Update) == "function" then
        pcall(FriendsList_Update, true)
    end
end

root.OnModuleChanged("friends", function()
    Friends.Refresh()
end)

-- /zt friends: what the game says about each online friend, for checking
-- why someone stays or moves.
function Friends.Report()
    local total = Safe(BNGetNumFriends) or 0
    local shown = 0
    for i = 1, total do
        local info = Safe(C_BattleNet and C_BattleNet.GetFriendAccountInfo, i)
        local game = type(info) == "table" and info.gameAccountInfo
        if type(game) == "table" and game.isOnline then
            shown = shown + 1
            root.Print(("%s: %s | realm %s (%s) | invite %s | %s"):format(
                tostring(info.accountName),
                tostring(game.clientProgram),
                tostring(game.realmName), tostring(game.realmID),
                tostring(Safe(FriendsFrame_GetInviteRestriction, i)),
                Friends.OutOfReach(i) and "moved down" or "stays"))
        end
    end
    if shown == 0 then
        root.Print("no Battle.net friends online.")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    Hook() -- the friends window may load after us
end)
