-- Ziri's Toolkit: quiver in its own window
-- With the combined bag (one big bag window, the Enhanced preset's default)
-- a quiver or ammo pouch is mixed in with everything else. This part takes
-- its slots out of the combined bag and opens it as its own bag window
-- beside it, the way the game shows single bags.
--
-- The game's own bag code does the work, nothing of it is replaced:
--   * after the combined bag lays out its slots, the quiver's slots are
--     hidden, the rest close up and the window gets shorter (hooks only),
--   * the quiver opens in one of the game's normal bag windows, which sits
--     left of the combined bag like any other open bag.
-- Only with the combined bag: with single bags the quiver has its own
-- window already. Gamepad mode is left alone.

local ADDON_NAME, root = ...

local Quiver = {}
root.Quiver = Quiver

local IsSecret = root.IsSecret

local QUIVER_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Quiver) or 11

local opened = {} -- [bagID] = the game's bag window we opened it in

local function NumBags()
    local c = Constants and Constants.InventoryConstants
    return (c and c.NumBagSlots) or NUM_BAG_FRAMES or 4
end

local function SlotCount(bag)
    local n
    if ContainerFrame_GetContainerNumSlots then
        n = ContainerFrame_GetContainerNumSlots(bag)
    elseif C_Container and C_Container.GetContainerNumSlots then
        n = C_Container.GetContainerNumSlots(bag)
    end
    if type(n) ~= "number" or IsSecret(n) then
        return 0
    end
    return n
end

-- True if the bag in that bag slot (1-4) is a quiver or an ammo pouch.
function Quiver.IsAmmoBag(bag)
    if not (C_Container and C_Container.ContainerIDToInventoryID and C_Item and C_Item.GetItemInfoInstant) then
        return false
    end
    local ok, inv = pcall(C_Container.ContainerIDToInventoryID, bag)
    if not ok or type(inv) ~= "number" or IsSecret(inv) then
        return false
    end
    local itemID = GetInventoryItemID("player", inv)
    if type(itemID) ~= "number" or IsSecret(itemID) then
        return false
    end
    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
    return classID == QUIVER_CLASS
end

-- Quiver and ammo pouch bag IDs, lowest first.
function Quiver.AmmoBags()
    local list = {}
    for bag = 1, NumBags() do
        if Quiver.IsAmmoBag(bag) and SlotCount(bag) > 0 then
            list[#list + 1] = bag
        end
    end
    return list
end

local function Gamepad()
    return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() and true or false
end

-- True when the combined bag is in use and this part should act.
function Quiver.Active()
    if not root.db or not root.ModuleOn("quiver") then
        return false
    end
    local mgr = ContainerFrameSettingsManager
    if not (ContainerFrameCombinedBags and mgr and mgr.IsUsingCombinedBags) then
        return false
    end
    return mgr:IsUsingCombinedBags() and not Gamepad()
end

-- After the combined bag laid out its slots: hide the quiver's, close up
-- the rest in the game's own order.
function Quiver.Relayout(f)
    if not Quiver.Active() then
        return
    end
    local ammo = {}
    local any = false
    for _, bag in ipairs(Quiver.AmmoBags()) do
        ammo[bag] = true
        any = true
    end
    if not any then
        return
    end
    local keep = {}
    for _, btn in f:EnumerateValidItems() do
        if ammo[btn:GetBagID()] then
            btn:Hide()
        else
            keep[#keep + 1] = btn
        end
    end
    -- Same order as the game: on an unsecured account the extra (locked)
    -- slots first, then highest bag and slot first (laid out from the
    -- bottom right).
    local secured = not IsAccountSecured or IsAccountSecured()
    table.sort(keep, function(a, b)
        if not secured and a.IsExtended then
            local ea, eb = a:IsExtended() and true or false, b:IsExtended() and true or false
            if ea ~= eb then
                return not ea
            end
        end
        local ba, bb = a:GetBagID(), b:GetBagID()
        if ba ~= bb then
            return ba > bb
        end
        return a:GetID() > b:GetID()
    end)
    if #keep > 0 then
        AnchorUtil.GridLayout(keep, f:GetInitialItemAnchor(), f:GetAnchorLayout())
    end
    if f.LayoutAddSlots then
        f:LayoutAddSlots()
    end
end

local function ButtonHeight(f)
    local ok, info = pcall(function()
        return C_XMLUtil.GetTemplateInfo(f.itemButtonPool:GetTemplate())
    end)
    if ok and info and type(info.height) == "number" then
        return info.height
    end
    return 37
end

-- How many pixels shorter the combined bag gets without the quiver's slots.
function Quiver.HeightSaved(f)
    local hidden = 0
    for _, bag in ipairs(Quiver.AmmoBags()) do
        hidden = hidden + SlotCount(bag)
    end
    if hidden == 0 then
        return 0
    end
    local cols = f:GetColumns()
    local total = f:GetBagSize()
    local rows = math.ceil(total / cols)
    local newRows = math.ceil(math.max(total - hidden, 1) / cols)
    if newRows >= rows then
        return 0
    end
    return (rows - newRows) * (ButtonHeight(f) + (ITEM_SPACING_Y or 5))
end

-- Right after the game sized the combined bag: take off the quiver's rows.
function Quiver.Resize(f)
    if not Quiver.Active() then
        return
    end
    local saved = Quiver.HeightSaved(f)
    if saved <= 0 then
        return
    end
    local h = f:GetHeight() - saved
    f:SetHeight(h)
    if NineSliceUtil and NineSliceUtil.UpdateCornerCropping then
        NineSliceUtil.UpdateCornerCropping(f, h)
    end
end

local function OwnShown(bag)
    local fr = opened[bag]
    return fr ~= nil and fr:IsShown() and fr:GetBagID() == bag
end

function Quiver.CloseOwn()
    for bag, fr in pairs(opened) do
        if OwnShown(bag) then
            fr:Hide()
        end
    end
    opened = {}
end

-- The combined bag just opened (or was rebuilt): open each quiver in a
-- normal bag window of its own.
function Quiver.OpenOwn()
    if not Quiver.Active() then
        Quiver.CloseOwn()
        return
    end
    local list = Quiver.AmmoBags()
    local want = {}
    for _, bag in ipairs(list) do
        want[bag] = true
    end
    for bag in pairs(opened) do
        if not want[bag] or not OwnShown(bag) then
            if OwnShown(bag) then
                opened[bag]:Hide()
            end
            opened[bag] = nil
        end
    end
    for _, bag in ipairs(list) do
        if not opened[bag] then
            local fr = ContainerFrame_GetOpenFrame(bag)
            if fr and fr ~= ContainerFrameCombinedBags then
                ContainerFrame_GenerateFrame(fr, SlotCount(bag), bag)
                opened[bag] = fr
            end
        end
    end
end

-- The game greys out a slot while its item is picked up, but it looks for
-- the slot in the combined bag (where the quiver's slots are hidden). Do it
-- for the quiver's own window.
function Quiver.OnLockChanged(bag, slot)
    if not (bag and slot) or not OwnShown(bag) then
        return
    end
    for _, btn in opened[bag]:EnumerateValidItems() do
        if btn:GetID() == slot then
            local info = C_Container.GetContainerItemInfo(bag, slot)
            SetItemButtonDesaturated(btn, info and info.isLocked)
        end
    end
end

local function Safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        root.Print("quiver window: " .. tostring(err))
    end
end

root.OnModuleChanged("quiver", function(on)
    if not on then
        Quiver.CloseOwn()
    end
end)

local hooked = false
local function Hook()
    if hooked or not (ContainerFrameCombinedBags and ContainerFrame_GenerateFrame) then
        return
    end
    hooked = true
    local f = ContainerFrameCombinedBags
    hooksecurefunc(f, "UpdateFrameSize", function(self)
        Safe(Quiver.Resize, self)
    end)
    hooksecurefunc(f, "UpdateItemLayout", function(self)
        Safe(Quiver.Relayout, self)
    end)
    hooksecurefunc("ContainerFrame_GenerateFrame", function(frame)
        if frame == ContainerFrameCombinedBags then
            Safe(Quiver.OpenOwn)
        end
    end)
    f:HookScript("OnHide", function()
        Safe(Quiver.CloseOwn)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ITEM_LOCK_CHANGED")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        Hook()
    elseif event == "ITEM_LOCK_CHANGED" then
        Safe(Quiver.OnLockChanged, ...)
    end
end)
