-- Ziri's Toolkit: minimap button
-- A round button on the edge of the minimap with Ziri's face.
--   Left-click: open the toolkit's settings.
--   Drag:       move it around the minimap's edge (remembered).
-- It can be hidden on the settings page.

local ADDON_NAME, root = ...

local MinimapButton = {}
root.MinimapButton = MinimapButton

local ICON = "Interface\\AddOns\\ZirisToolkit\\Media\\MinimapIcon"
local GAP = 5 -- how far outside the minimap's edge

local button

local function Settings()
    local db = root.db
    if type(db.minimap) ~= "table" then
        db.minimap = {}
    end
    if type(db.minimap.angle) ~= "number" then
        db.minimap.angle = 200 -- degrees, 0 = right, counter-clockwise
    end
    return db.minimap
end

-- x, y from the minimap's center for an angle in degrees.
function MinimapButton.Offset(angle, radius)
    local r = math.rad(angle)
    return math.cos(r) * radius, math.sin(r) * radius
end

-- Angle in degrees (0..360) of a point seen from the minimap's center.
function MinimapButton.Angle(dx, dy)
    local a = math.deg(math.atan2 and math.atan2(dy, dx) or math.atan(dy, dx))
    if a < 0 then
        a = a + 360
    end
    return a
end

local function Place()
    if not button then
        return
    end
    local radius = (Minimap:GetWidth() or 140) / 2 + GAP
    local x, y = MinimapButton.Offset(Settings().angle, radius)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale() or 1
    if not (mx and my and cx and cy) then
        return
    end
    Settings().angle = MinimapButton.Angle(cx / scale - mx, cy / scale - my)
    Place()
end

local function Create()
    button = CreateFrame("Button", "ZirisToolkitMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(22, 22)
    bg:SetPoint("CENTER", 0, 1)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER", 0, 1)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function()
        if not root.OpenOptions() then
            root.Print("the settings page could not be opened")
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", FollowCursor)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        -- Same style as our other addons: gold title, white actions, grey extras.
        GameTooltip:SetText(root.TITLE, 1, 0.82, 0)
        GameTooltip:AddLine("Left-click: Settings", 1, 1, 1, true)
        GameTooltip:AddLine("Drag: Move", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

function MinimapButton.Refresh()
    if not Minimap then
        return
    end
    if Settings().hide then
        if button then
            button:Hide()
        end
        return
    end
    if not button then
        Create()
    end
    Place()
    button:Show()
end

function MinimapButton.IsShown()
    return not Settings().hide
end

function MinimapButton.SetShown(on)
    Settings().hide = not on
    MinimapButton.Refresh()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    local ok, err = pcall(MinimapButton.Refresh)
    if not ok then
        root.Print("minimap button: " .. tostring(err))
    end
end)
