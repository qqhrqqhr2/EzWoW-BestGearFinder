--===========================================================================
-- EzWoW - Best Gear Finder
-- UI/Launcher.lua : Draggable Floating Quick-Launch Button
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local QuickLauncherButton = ns.QuickLauncherButton or {}
ns.QuickLauncherButton = QuickLauncherButton
local L = ns.L

local iconTex = "Interface\\AddOns\\EzWoW-BestGearFinder\\Media\\icon"
local SIZE = 36
local actionBtn

function QuickLauncherButton.persistPosition(self)
    local cx, cy = self:GetCenter()
    if cx and cy then
        ns.db.iconPos = { "CENTER", "BOTTOMLEFT", math.floor(cx + 0.5), math.floor(cy + 0.5) }
    else
        local point, _, relPoint, coordX, coordY = self:GetPoint()
        ns.db.iconPos = { point, relPoint, coordX, coordY }
    end
end

function QuickLauncherButton.commitPosition()
    if not actionBtn then return end
    actionBtn:SetScale(1)
    actionBtn:ClearAllPoints()
    local anchorTarget = ns.db and ns.db.iconPos
    if type(anchorTarget) == "table" and type(anchorTarget[1]) == "string" then
        local pt = anchorTarget[1]
        local relPt = type(anchorTarget[2]) == "string" and anchorTarget[2] or pt
        local ox = tonumber(anchorTarget[3]) or 0
        local oy = tonumber(anchorTarget[4]) or 0
        local ok = pcall(actionBtn.SetPoint, actionBtn, pt, UIParent, relPt, ox, oy)
        if ok then
            local cx, cy = actionBtn:GetCenter()
            local uiW = (UIParent and UIParent:GetWidth()) or 1920
            local uiH = (UIParent and UIParent:GetHeight()) or 1080
            if cx and cy and uiW > 100 and uiH > 100 then
                if cx < 12 or cy < 12 or cx > (uiW - 12) or cy > (uiH - 12) then
                    ns.db.iconPos = nil
                    actionBtn:ClearAllPoints()
                    actionBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -200)
                end
            end
            return
        end
    end
    actionBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -200)
end

function QuickLauncherButton.constructMainFrame()
    actionBtn = CreateFrame("Button", "EzWoWBestGearFinderLauncher", UIParent)
    actionBtn:SetSize(SIZE, SIZE)
    actionBtn:SetScale(1)
    actionBtn:SetFrameStrata("MEDIUM")
    actionBtn:SetFrameLevel(20)
    actionBtn:SetClampedToScreen(true)
    actionBtn:SetMovable(true)
    actionBtn:EnableMouse(true)
    actionBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    actionBtn:RegisterForDrag("LeftButton")

    actionBtn.icon = actionBtn:CreateTexture(nil, "ARTWORK")
    actionBtn.icon:SetTexture(iconTex)
    actionBtn.icon:SetAllPoints()

    actionBtn.hl = actionBtn:CreateTexture(nil, "HIGHLIGHT")
    actionBtn.hl:SetTexture(iconTex)
    actionBtn.hl:SetAllPoints()
    actionBtn.hl:SetBlendMode("ADD")
    actionBtn.hl:SetAlpha(0.35)

    local grabDX, grabDY = 0, 0
    actionBtn:SetScript("OnDragStart", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        self:SetScale(1)
        self.dragging = true
        GameTooltip:Hide()
        local effScale = self:GetEffectiveScale() or 1
        local curX, curY = GetCursorPosition()
        curX, curY = curX / effScale, curY / effScale
        local bx, by = self:GetCenter()
        if bx and by then
            grabDX = bx - curX
            grabDY = by - curY
        else
            grabDX, grabDY = 0, 0
        end
        self:SetScript("OnUpdate", function(btn)
            local es = btn:GetEffectiveScale() or 1
            local cx, cy = GetCursorPosition()
            cx, cy = cx / es + grabDX, cy / es + grabDY
            local uiW = (UIParent and UIParent:GetWidth()) or 1920
            local uiH = (UIParent and UIParent:GetHeight()) or 1080
            local half = SIZE * 0.5
            if cx < half then cx = half elseif cx > uiW - half then cx = uiW - half end
            if cy < half then cy = half elseif cy > uiH - half then cy = uiH - half end
            btn:ClearAllPoints()
            btn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
        end)
    end)
    actionBtn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:StopMovingOrSizing()
        QuickLauncherButton.persistPosition(self)
        self.dragging = false
    end)
    actionBtn:SetScript("OnClick", function(self, button)
        if self.dragging then return end
        if button == "RightButton" then
            if ns.ToggleSettingsWindow then ns:ToggleSettingsWindow() else ns:ToggleMainGearWindow() end
        else
            ns:ToggleMainGearWindow()
        end
    end)
    actionBtn:SetScript("OnEnter", function(self)
        if self.dragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("EzWoW - Best Gear Finder", 0.945, 0.741, 0.341)
        GameTooltip:AddLine(L["왼쪽 클릭: 추천 장비 창 열기/닫기"], 0.929, 0.957, 0.969)
        GameTooltip:AddLine(L["오른쪽 클릭: 설정 열기/닫기"], 0.655, 0.725, 0.773)
        GameTooltip:AddLine(L["드래그: 아이콘 위치 이동"], 0.655, 0.725, 0.773)
        GameTooltip:Show()
    end)
    actionBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

function ns:UpdateLauncher()
    if not self.db then return end
    if not actionBtn then
        QuickLauncherButton.constructMainFrame()
    end
    QuickLauncherButton.commitPosition()
    if self.db.iconShown ~= false then
        actionBtn:Show()
    else
        actionBtn:Hide()
    end
end

function ns:ResetLauncher()
    if not self.db then return end
    self.db.iconPos = nil
    self.db.iconShown = true
    if not actionBtn then
        QuickLauncherButton.constructMainFrame()
    end
    QuickLauncherButton.commitPosition()
    actionBtn:Show()
end
