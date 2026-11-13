-- Ziri's Toolkit: undress
-- One button on the character window. "Undress" puts every equipped item
-- that can lose durability into your bags, so dying again and again (a
-- corpse run into enemy land) costs no repairs. "Dress" puts exactly those
-- items back where they were.
--
-- Rings, necklace, trinkets, shirt and tabard never lose durability, so
-- they stay on. Nothing is saved as an equipment set: the button always
-- takes off whatever you are wearing right now.

local ADDON_NAME, root = ...

local Undress = {}
root.Undress = Undress

local LAST_SLOT = 18 -- 1 head ... 16 main hand, 17 off hand, 18 ranged
-- Weapons go back on first, so an off hand never lands before its main hand.
local DRESS_ORDER = { 16, 17, 18, 1, 3, 5, 6, 7, 8, 9, 10, 15, 2, 4, 11, 12, 13, 14 }

local IsSecret = root.IsSecret
local button
-- While the game moves items they are locked and can't be picked up again.
-- The button waits for that, so clicking fast can't tangle things up.
local moving = false
local movingSince = 0
local MIN_WAIT, MAX_WAIT = 0.5, 5

local function Safe(fn, ...)
    if not fn then
        return nil
    end
    local ok, a, b = pcall(fn, ...)
    if not ok or IsSecret(a) then
        return nil
    end
    return a, b
end

-- Saved per character, so "Dress" still works after logging out naked.
local CharKey = root.CharKey

local function Saved()
    local key = CharKey()
    if not key or not root.db then
        return nil
    end
    root.db.undressed = root.db.undressed or {}
    root.db.undressed[key] = root.db.undressed[key] or {}
    return root.db.undressed[key]
end

-------------------------------------------------------------------------------
-- Items
-------------------------------------------------------------------------------

local function EquippedGUID(slot)
    if ItemLocation and ItemLocation.CreateFromEquipmentSlot and C_Item and C_Item.GetItemGUID then
        local loc = ItemLocation:CreateFromEquipmentSlot(slot)
        if Safe(C_Item.DoesItemExist, loc) then
            return Safe(C_Item.GetItemGUID, loc)
        end
    end
    return nil
end

local function BagGUID(bag, slot)
    if ItemLocation and ItemLocation.CreateFromBagAndSlot and C_Item and C_Item.GetItemGUID then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if Safe(C_Item.DoesItemExist, loc) then
            return Safe(C_Item.GetItemGUID, loc)
        end
    end
    return nil
end

local function NumBags()
    return NUM_BAG_SLOTS or 4
end

-- Empty slots in normal bags (herb bags, quivers and such can't hold gear).
local function FreeSlots()
    local free = {}
    for bag = 0, NumBags() do
        local _, bagType = Safe(C_Container.GetContainerNumFreeSlots, bag)
        if bagType == 0 then
            local size = Safe(C_Container.GetContainerNumSlots, bag) or 0
            for slot = 1, size do
                if not Safe(C_Container.GetContainerItemID, bag, slot) then
                    free[#free + 1] = { bag, slot }
                end
            end
        end
    end
    return free
end

-- Finds a saved item in the bags: by its unique ID, else by its link.
local function FindInBags(entry)
    local byLink
    for bag = 0, NumBags() do
        local size = Safe(C_Container.GetContainerNumSlots, bag) or 0
        for slot = 1, size do
            if entry.guid and BagGUID(bag, slot) == entry.guid then
                return bag, slot
            end
            if not byLink and entry.link and Safe(C_Container.GetContainerItemLink, bag, slot) == entry.link then
                byLink = { bag, slot }
            end
        end
    end
    if byLink then
        return byLink[1], byLink[2]
    end
    return nil
end

local function SlotLocked(slot)
    return Safe(IsInventoryItemLocked, slot) == true
end

local function BagItemLocked(bag, slot)
    local info = Safe(C_Container.GetContainerItemInfo, bag, slot)
    return type(info) == "table" and info.isLocked == true
end

local function AnyLocked()
    for slot = 1, LAST_SLOT do
        if SlotLocked(slot) then
            return true
        end
    end
    for bag = 0, NumBags() do
        local size = Safe(C_Container.GetContainerNumSlots, bag) or 0
        for slot = 1, size do
            if BagItemLocked(bag, slot) then
                return true
            end
        end
    end
    return false
end

local function WaitForMoves()
    if moving or GetTime() - movingSince < MIN_WAIT then
        if button then
            local ok = pcall(function()
                local waited = GetTime() - movingSince
                if waited >= MAX_WAIT or (waited >= MIN_WAIT and not AnyLocked()) then
                    moving = false
                    button:Enable()
                    Undress.UpdateButton()
                else
                    C_Timer.After(0.2, WaitForMoves)
                end
            end)
            if not ok then
                moving = false
                button:Enable()
            end
        else
            moving = false
        end
    end
end

local function StartWaiting()
    moving = true
    movingSince = GetTime()
    if button then
        button:Disable()
    end
    C_Timer.After(0.2, WaitForMoves)
end

local function Pending()
    local saved = Saved()
    return saved ~= nil and next(saved) ~= nil
end

local function CanChangeGear()
    if InCombatLockdown() or Safe(UnitAffectingCombat, "player") then
        root.Print("gear can't be changed in combat.")
        return false
    end
    if Safe(UnitIsDeadOrGhost, "player") then
        root.Print("gear can't be changed while you are dead.")
        return false
    end
    if GetCursorInfo and GetCursorInfo() then
        root.Print("put down what you are holding on the mouse first.")
        return false
    end
    return true
end

-------------------------------------------------------------------------------
-- Undress and dress
-------------------------------------------------------------------------------

function Undress.TakeOff()
    if not CanChangeGear() then
        return
    end
    local saved = Saved()
    if not saved then
        return
    end
    local free = FreeSlots()
    local moved, kept = 0, 0
    for slot = 1, LAST_SLOT do
        local _, maxDurability = Safe(GetInventoryItemDurability, slot)
        if maxDurability and maxDurability > 0 and not SlotLocked(slot) then
            local target = free[moved + 1]
            if not target then
                kept = kept + 1
            else
                saved[slot] = {
                    guid = EquippedGUID(slot),
                    link = Safe(GetInventoryItemLink, "player", slot),
                }
                PickupInventoryItem(slot)
                C_Container.PickupContainerItem(target[1], target[2])
                moved = moved + 1
            end
        end
    end
    if GetCursorInfo and GetCursorInfo() then
        ClearCursor()
    end
    if moved > 0 then
        StartWaiting()
    end
    if moved == 0 and kept == 0 then
        root.Print("nothing to take off.")
    elseif kept > 0 then
        root.Print(("took off %d items. %d more did not fit in your bags."):format(moved, kept))
    else
        root.Print(("took off %d items. Click Dress to put them back on."):format(moved))
    end
    Undress.UpdateButton()
end

function Undress.PutOn()
    if not CanChangeGear() then
        return
    end
    local saved = Saved()
    if not saved then
        return
    end
    local done, missing, busy, stillMoving = 0, 0, 0, 0
    for _, slot in ipairs(DRESS_ORDER) do
        local entry = saved[slot]
        if entry then
            if Safe(GetInventoryItemLink, "player", slot) then
                -- You put something else on this slot yourself: leave it.
                saved[slot] = nil
                busy = busy + 1
            else
                local bag, bagSlot = FindInBags(entry)
                if bag and BagItemLocked(bag, bagSlot) then
                    stillMoving = stillMoving + 1 -- kept for the next click
                elseif bag then
                    C_Container.PickupContainerItem(bag, bagSlot)
                    PickupInventoryItem(slot)
                    saved[slot] = nil
                    done = done + 1
                else
                    saved[slot] = nil
                    missing = missing + 1
                end
            end
        end
    end
    if GetCursorInfo and GetCursorInfo() then
        ClearCursor()
    end
    if done > 0 then
        StartWaiting()
    end
    local msg = ("put on %d items."):format(done)
    if missing > 0 then
        msg = msg .. (" %d are no longer in your bags."):format(missing)
    end
    if busy > 0 then
        msg = msg .. (" %d slots already had something on, left as is."):format(busy)
    end
    if stillMoving > 0 then
        msg = msg .. (" %d are still being moved, click Dress again in a moment."):format(stillMoving)
    end
    root.Print(msg)
    Undress.UpdateButton()
end

-------------------------------------------------------------------------------
-- The button on the character window
-------------------------------------------------------------------------------

function Undress.UpdateButton()
    if not button then
        return
    end
    if not root.ModuleOn("undress") then
        button:Hide()
        return
    end
    button:SetText(Pending() and "Dress" or "Undress")
    button:Show()
end

local function CreateButton()
    local parent = CharacterFrame or PaperDollFrame
    if not parent or button then
        return
    end
    button = CreateFrame("Button", "ZirisToolkitUndressButton", parent, "UIPanelButtonTemplate")
    button:SetSize(90, 22)
    -- On top of the window's top edge, right side: clear of the close
    -- button and the tabs beside the window.
    button:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", -4, 2)
    button:SetFrameLevel(parent:GetFrameLevel() + 20)
    button:SetScript("OnClick", function()
        if moving then
            return -- still moving the last batch
        end
        local ok, err = pcall(Pending() and Undress.PutOn or Undress.TakeOff)
        if not ok then
            root.Print("undress: something went wrong: " .. tostring(err))
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if Pending() then
            GameTooltip:SetText("Dress", 1, 1, 1)
            GameTooltip:AddLine("Puts the gear you took off back on.", nil, nil, nil, true)
        else
            GameTooltip:SetText("Undress", 1, 1, 1)
            GameTooltip:AddLine("Puts every item that can lose durability into your bags, so dying costs no repairs. Rings, necklace and trinkets stay on.", nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Undress.UpdateButton()
end

root.OnModuleChanged("undress", function()
    Undress.UpdateButton()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    local ok, err = pcall(CreateButton)
    if not ok then
        root.Print("undress: " .. tostring(err))
    end
end)
