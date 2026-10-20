--===========================================================================
-- EzWoW - Best Gear Finder
-- UI/MainWindow.lua : Slot-by-Slot Best Gear Recommendation Window
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local MainGearAdvisorWindow = ns.MainGearAdvisorWindow or {}
ns.MainGearAdvisorWindow = MainGearAdvisorWindow
local L = ns.L

local FRAME_H = 604
local MIN_FRAME_W = 800      
local COL_MIN_W = 236
local SIDE_PAD = 56          
local ROW_H, HEADER_H = 62, 32

local rowWidgets, headerPool, colHeaders, dividers, hbtns = {}, {}, {}, {}, {}
local qualChk, menuChecks, chanceEdit = {}, {}, nil
local aucChk
local progress
local containerFrame, scrollFrame, child, statusRegion, perBtn, minEdit, maxEdit, upChk, craftChk, questChk, titleText
local nCols, colW, frameW = 1, 400, MIN_FRAME_W

local EN_CLASS = { WARRIOR="Warrior", PALADIN="Paladin", HUNTER="Hunter", ROGUE="Rogue", PRIEST="Priest", SHAMAN="Shaman", MAGE="Mage", WARLOCK="Warlock", DRUID="Druid" }
function ns:ClassLabel(class)
    if L["요구 레벨"] ~= "요구 레벨" and EN_CLASS[class] then return EN_CLASS[class] end
    local resolvedValue = LOCALIZED_CLASS_NAMES_MALE
    if resolvedValue and resolvedValue[class] and class ~= select(2, UnitClass("player")) then return resolvedValue[class] end
    return UnitClass("player")
end

function MainGearAdvisorWindow.resolveSolidBG(f)
    local resolvedValue = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    resolvedValue:SetColorTexture(0.071, 0.094, 0.122, 1)
    resolvedValue:SetPoint("TOPLEFT", 3, -3)
    resolvedValue:SetPoint("BOTTOMRIGHT", -3, 3)
    f.solidBG = resolvedValue
end
ns.ApplySolidBackdrop = MainGearAdvisorWindow.resolveSolidBG

function ns.ConfigureScrollWheelStep(sf, step)
    if not sf or not sf.SetScript then return end
    local statusBar = sf.ScrollBar or (sf.GetName and sf:GetName() and _G[sf:GetName() .. "ScrollBar"])
    if statusBar then statusBar.scrollStep = step end
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local entryValue = (self:GetVerticalScroll() or 0) - delta * step * (IsShiftKeyDown and IsShiftKeyDown() and 4 or 1)
        if entryValue < 0 then entryValue = 0 elseif entryValue > range then entryValue = range end
        self:SetVerticalScroll(entryValue)
    end)
end

function ns.ApplyWindowTheme(f)
    ns.UIKit:ApplyBackdrop(f, 1, 1)
    f:SetBackdropColor(0.071, 0.094, 0.122, 0.96)
    f:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.945, 0.741, 0.341, 0.90)
    line:SetPoint("TOPLEFT", 1, -1)
    line:SetPoint("TOPRIGHT", -1, -1)
    line:SetHeight(2)
end

function ns.CreateStyledButton(parent, w, h, text, isAccent, onClick)
    local buttonWidget = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    buttonWidget:SetSize(w, h)
    if buttonWidget.SetBackdrop then
        ns.UIKit:ApplyBackdrop(buttonWidget, 1, 1)
    end
    local function applyNormalButtonLook()
        if not buttonWidget.SetBackdropColor then return end
        if isAccent then
            buttonWidget:SetBackdropColor(0.23, 0.19, 0.11, 0.96)
            buttonWidget:SetBackdropBorderColor(0.945, 0.741, 0.341, 1.00)
        else
            buttonWidget:SetBackdropColor(0.114, 0.157, 0.192, 0.96)
            buttonWidget:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
        end
    end
    applyNormalButtonLook()
    buttonWidget.normalStyle = applyNormalButtonLook
    local formatLocalizedLabel = buttonWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    formatLocalizedLabel:SetPoint("CENTER")
    if isAccent then
        formatLocalizedLabel:SetTextColor(0.945, 0.741, 0.341, 1.00)
    else
        formatLocalizedLabel:SetTextColor(0.929, 0.957, 0.969, 1.00)
    end
    formatLocalizedLabel:SetText(text or "")
    buttonWidget.label = formatLocalizedLabel
    function buttonWidget:SetText(txt) formatLocalizedLabel:SetText(txt or "") end
    function buttonWidget:GetText() return formatLocalizedLabel:GetText() end
    function buttonWidget:GetFontString() return formatLocalizedLabel end
    buttonWidget:HookScript("OnEnter", function()
        if buttonWidget.SetBackdropColor then
            buttonWidget:SetBackdropColor(0.20, 0.25, 0.30, 1)
            buttonWidget:SetBackdropBorderColor(0.945, 0.741, 0.341, 1.00)
        end
    end)
    buttonWidget:HookScript("OnLeave", applyNormalButtonLook)
    buttonWidget:SetScript("OnMouseDown", function() formatLocalizedLabel:SetPoint("CENTER", 1, -1) end)
    buttonWidget:SetScript("OnMouseUp", function() formatLocalizedLabel:SetPoint("CENTER", 0, 0) end)
    if onClick then buttonWidget:SetScript("OnClick", onClick) end
    return buttonWidget
end

function ns.CreateStyledEditBox(parent, w, h)
    local recordEntry = CreateFrame("EditBox", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    recordEntry:SetSize(w, h)
    recordEntry:SetFontObject(ChatFontNormal)
    recordEntry:SetTextInsets(6, 6, 0, 0)
    recordEntry:SetAutoFocus(false)
    if recordEntry.SetBackdrop then
        ns.UIKit:ApplyBackdrop(recordEntry, 1, 1)
        recordEntry:SetBackdropColor(0.047, 0.067, 0.086, 0.96)
        recordEntry:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
    end
    recordEntry:HookScript("OnEditFocusGained", function(self)
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(0.945, 0.741, 0.341, 1.00)
        end
    end)
    recordEntry:HookScript("OnEditFocusLost", function(self)
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
        end
    end)
    return recordEntry
end

function MainGearAdvisorWindow.formatColorAsHexCode(c) return c and format("|cff%02x%02x%02x", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255)) or "|cffffffff" end

function MainGearAdvisorWindow.resolveRoleColor(name)
    if name:find("탱") or name:find("Tank") then return 0.45, 0.74, 1 end
    if name:find("힐") or name:find("Heal") then return 0.376, 0.808, 0.639 end
    return 0.945, 0.741, 0.341
end

function MainGearAdvisorWindow.buildRow(i)
    local rowEntry = CreateFrame("Button", nil, child)
    rowEntry:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    rowEntry.icon = rowEntry:CreateTexture(nil, "ARTWORK")
    rowEntry.bg = rowEntry:CreateTexture(nil, "BACKGROUND")
    rowEntry.bg:SetPoint("TOPLEFT", 0, 0); rowEntry.bg:SetPoint("BOTTOMRIGHT", 0, 4)
    rowEntry.bg:SetColorTexture(0.114, 0.157, 0.192, 0.95)
    rowEntry.accent = rowEntry:CreateTexture(nil, "ARTWORK")
    rowEntry.accent:SetPoint("TOPLEFT", 0, 0); rowEntry.accent:SetPoint("BOTTOMLEFT", 0, 4)
    rowEntry.accent:SetWidth(2)
    rowEntry.icon:SetSize(34, 34)
    rowEntry.icon:SetPoint("TOPLEFT", 8, -8)
    rowEntry.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    rowEntry.name = rowEntry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rowEntry.name:SetPoint("TOPLEFT", rowEntry.icon, "TOPRIGHT", 8, 0)
    rowEntry.name:SetPoint("TOPRIGHT", rowEntry, "TOPRIGHT", -8, -8)
    rowEntry.name:SetJustifyH("LEFT")
    rowEntry.name:SetWordWrap(false)
    rowEntry.sub = rowEntry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rowEntry.sub:SetPoint("TOPLEFT", rowEntry.name, "BOTTOMLEFT", 0, -4)
    rowEntry.sub:SetPoint("TOPRIGHT", rowEntry.name, "BOTTOMRIGHT", 0, -4)
    rowEntry.sub:SetJustifyH("LEFT")
    rowEntry.sub:SetWordWrap(false)
    rowEntry.source = rowEntry:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rowEntry.source:SetPoint("TOPLEFT", rowEntry.sub, "BOTTOMLEFT", 0, -4)
    rowEntry.source:SetPoint("TOPRIGHT", rowEntry.sub, "BOTTOMRIGHT", 0, -4)
    rowEntry.source:SetJustifyH("LEFT")
    rowEntry.source:SetWordWrap(false)
    rowEntry.hl = rowEntry:CreateTexture(nil, "HIGHLIGHT")
    rowEntry.hl:SetAllPoints()
    rowEntry.hl:SetColorTexture(1, 1, 1, 0.08)
    rowEntry:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        
        GameTooltip:SetHyperlink(self.link)
        
        GameTooltip:AddLine(" ")
        if self.compareNote then
            GameTooltip:AddLine(self.compareNote, 0.8, 0.85, 0.95, true)
        end
        if not self.comparable then
            
        elseif self.baseIlvl then
            GameTooltip:AddLine(L["현재 착용 장비 아이템 레벨: "] .. self.baseIlvl, 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine(L["현재 이 슬롯: 비어 있음"], 0.7, 0.7, 0.7)
        end
        if self.comparable and not self.compareNote and self.weights and self.link and ns.FormatStatComparisonDelta then
            local okD, txt = pcall(ns.FormatStatComparisonDelta, self.link, self.baseLink, self.weights, 4)
            if okD and txt and txt ~= "" then
                GameTooltip:AddLine(format(L["현재 장비 대비: %s"], txt), 0.6, 0.8, 1, true)
            end
        end
        if self.score and self.comparable then
            GameTooltip:AddLine(format(L["추정 점수: 이 아이템 %.1f / 착용 중 %.1f"], self.score, self.baseScore or 0), 0.6, 0.9, 0.6)
            GameTooltip:AddLine(L["표시된 %는 추정 점수 변화입니다."], 0.65, 0.72, 0.8)
        end
        if _G.SlashCmdList and _G.SlashCmdList.EZWOWMAPFINDER then
            GameTooltip:AddLine(L["우클릭: 지도에서 획득처 찾기"], 0.294, 0.784, 0.910)
        end
        GameTooltip:Show()
        if (ns.db and ns.db.showEquipCompare ~= false) or (IsShiftKeyDown and IsShiftKeyDown()) then
            if GameTooltip_ShowCompareItem then
                pcall(GameTooltip_ShowCompareItem, GameTooltip)
            end
        end
    end)
    rowEntry:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
        if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
    end)
    rowEntry:SetScript("OnClick", function(self, button)
        if not self.link then return end
        if button == "RightButton" then
            if ns.OpenInMapFinder then
                ns:OpenInMapFinder(self.id, self.rec, self.link)
            end
            return
        end
        if IsModifiedClick("CHATLINK") then
            local ins = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)
            if ins then ins(self.link) end
        elseif IsModifiedClick("DRESSUP") then
            local dress = DressUpItemLink or (C_Item and C_Item.DressUpItemLink)
            if dress then dress(self.link) end
        end
    end)
    rowWidgets[i] = rowEntry
    return rowEntry
end

function MainGearAdvisorWindow.buildHeader(i)
    local h = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetJustifyH("LEFT")
    headerPool[i] = h
    return h
end

function MainGearAdvisorWindow.buildSlotHeader(i)
    local buttonWidget = CreateFrame("Button", nil, child)
    buttonWidget:RegisterForClicks("LeftButtonUp")
    buttonWidget.bg = buttonWidget:CreateTexture(nil, "BACKGROUND")
    buttonWidget.bg:SetAllPoints()
    buttonWidget.bg:SetColorTexture(0.114, 0.157, 0.192, 0.96)
    buttonWidget.highlight = buttonWidget:CreateTexture(nil, "HIGHLIGHT")
    buttonWidget.highlight:SetAllPoints()
    buttonWidget.highlight:SetColorTexture(0.945, 0.741, 0.341, 0.18)
    buttonWidget.indicator = buttonWidget:CreateTexture(nil, "ARTWORK")
    buttonWidget.indicator:SetSize(18, 18)
    buttonWidget.indicator:SetPoint("LEFT", 6, 0)
    buttonWidget.action = buttonWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    buttonWidget.action:SetPoint("RIGHT", -10, 0)
    buttonWidget.action:SetWidth(70)
    buttonWidget.action:SetJustifyH("RIGHT")
    buttonWidget.label = buttonWidget:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buttonWidget.label:SetPoint("LEFT", buttonWidget.indicator, "RIGHT", 6, 0)
    buttonWidget.label:SetPoint("RIGHT", buttonWidget.action, "LEFT", -10, 0)
    buttonWidget.label:SetJustifyH("LEFT")
    buttonWidget.label:SetWordWrap(false)
    buttonWidget.label:SetTextColor(0.945, 0.741, 0.341)
    buttonWidget:SetScript("OnClick", function(btn)
        if not btn.key or not ns.db then return end
        ns.db.collapsed = ns.db.collapsed or {}
        ns.db.collapsed[btn.key] = not ns.db.collapsed[btn.key] or nil
        ns:UpdateUI()
    end)
    buttonWidget:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["클릭하면 이 슬롯을 접거나 펼칩니다."], 1, 1, 1)
        GameTooltip:Show()
    end)
    buttonWidget:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hbtns[i] = buttonWidget
    return buttonWidget
end

function MainGearAdvisorWindow.assembleFrame()
    local specs = ns:GetSpecList()
    nCols = #specs
    frameW = math.max(MIN_FRAME_W, SIDE_PAD + nCols * COL_MIN_W)
    colW = (frameW - SIDE_PAD) / nCols

    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local function attachHoverTooltip(btn, title, text)
        btn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(title, 1, 1, 1)
            if text then GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end)
        btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    containerFrame = CreateFrame("Frame", "EzWoWBestGearFinderFrame", UIParent, template)
    containerFrame:SetSize(frameW, math.max(320, math.min(1000, (ns.db and ns.db.height) or FRAME_H)))
    containerFrame:SetFrameStrata("HIGH")
    containerFrame:SetClampedToScreen(true)
    containerFrame:SetMovable(true)
    containerFrame:EnableMouse(true)
    containerFrame:RegisterForDrag("LeftButton")
    ns.ApplyWindowTheme(containerFrame)
    
    local maxW = UIParent:GetWidth() * 0.96
    if maxW and maxW > 0 and frameW > maxW then containerFrame:SetScale(maxW / frameW) end

    containerFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    containerFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local anchorTarget, _, relativePoint, coordX, coordY = self:GetPoint()
        ns.db.point = { anchorTarget, relativePoint, coordX, coordY }
    end)
    containerFrame:SetScript("OnShow", function() ns:Refresh(true) end)
    containerFrame:Hide()
    tinsert(UISpecialFrames, "EzWoWBestGearFinderFrame")

    local anchorPoint = ns.db.point
    if anchorPoint then containerFrame:SetPoint(anchorPoint[1], UIParent, anchorPoint[2], anchorPoint[3], anchorPoint[4]) else containerFrame:SetPoint("CENTER") end

    local close = ns.CreateStyledButton(containerFrame, 22, 22, "X", false, function() containerFrame:Hide() end)
    close:SetPoint("TOPRIGHT", -10, -8)

    titleText = containerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleText:SetPoint("TOPLEFT", 18, -14)

    local sortBtn = ns.CreateStyledButton(containerFrame, 168, 22, "", false)
    sortBtn:SetPoint("TOPLEFT", 16, -34)
    local sortMenu = CreateFrame("Frame", nil, containerFrame, template)
    sortMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    sortMenu:SetFrameLevel(containerFrame:GetFrameLevel() + 30)
    ns.ApplyWindowTheme(sortMenu)
    MainGearAdvisorWindow.resolveSolidBG(sortMenu)
    sortMenu:SetPoint("TOPLEFT", sortBtn, "BOTTOMLEFT", 0, -2)
    sortMenu:Hide()
    local sortChecks = {}
    local function sortLabel()
        local sel = {}
        for _, stateEntry in ipairs(ns.SORT_STATS or {}) do
            if ns.db.sortStats and ns.db.sortStats[stateEntry.key] then sel[#sel + 1] = L[stateEntry.label] end
        end
        if #sel == 0 then return ns.db.bisPriority and L["30레벨 BiS 우선"] or L["추천순"] end
        if #sel == 1 then return sel[1] end
        return sel[1] .. " +" .. (#sel - 1)
    end
    local function sortChanged()
        sortBtn:SetText(L["정렬: "] .. sortLabel() .. " ▼")
        ns:Refresh(true)
    end
    local syVal = -8
    local defBtn = ns.CreateStyledButton(sortMenu, 180, 20, L["추천순 (기본)"], false, function()
        ns.db.sortStats = {}
        ns.db.bisPriority = false
        for _, checkWidget in ipairs(sortChecks) do checkWidget:SetChecked(false) end
        sortChanged()
    end)
    defBtn:SetPoint("TOPLEFT", 10, syVal)
    syVal = syVal - 24
    local bisBtn = ns.CreateStyledButton(sortMenu, 180, 20, L["30레벨 BiS 우선"], false, function()
        ns.db.sortStats, ns.db.bisPriority = {}, true
        for _, checkWidget in ipairs(sortChecks) do checkWidget:SetChecked(false) end
        sortChanged()
    end)
    bisBtn:SetPoint("TOPLEFT", 10, syVal)
    syVal = syVal - 24
    for _, stateEntry in ipairs(ns.SORT_STATS or {}) do
        local checkWidget = CreateFrame("CheckButton", nil, sortMenu, "UICheckButtonTemplate")
        checkWidget:SetSize(22, 22)
        checkWidget:SetPoint("TOPLEFT", 8, syVal)
        local resolvedValue = checkWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        resolvedValue:SetPoint("LEFT", checkWidget, "RIGHT", 2, 0)
        resolvedValue:SetText(L[stateEntry.label])
        checkWidget:SetChecked(ns.db.sortStats and ns.db.sortStats[stateEntry.key] and true or false)
        checkWidget:SetScript("OnClick", function(self)
            ns.db.sortStats = ns.db.sortStats or {}
            ns.db.sortStats[stateEntry.key] = self:GetChecked() and true or nil
            sortChanged()
        end)
        sortChecks[#sortChecks + 1] = checkWidget
        syVal = syVal - 22
    end
    local shVal = sortMenu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    shVal:SetPoint("TOPLEFT", 12, syVal - 4)
    shVal:SetWidth(176)
    shVal:SetJustifyH("LEFT")
    shVal:SetText(L["여러 개를 고르면 합계가 큰 순서"])
    sortMenu:SetSize(200, -syVal + 44)
    sortBtn:SetText(L["정렬: "] .. sortLabel() .. " ▼")
    sortBtn:SetScript("OnClick", function()
        if sortMenu:IsShown() then sortMenu:Hide() else sortMenu:Show() end
    end)
    attachHoverTooltip(sortBtn, L["정렬"], L["슬롯마다 아이템을 어떤 순서로 보여줄지 고릅니다. 방어도, 초당 공격력, 힘·민첩성·체력·지능 등을 체크하면 그 값이 큰 순서로 나옵니다."])
    containerFrame:HookScript("OnHide", function() sortMenu:Hide() end)

    local cfgBtn = ns.CreateStyledButton(containerFrame, 76, 20, (SETTINGS or "설정"), false, function() ns:ToggleSettingsWindow() end)
    cfgBtn:SetPoint("TOPRIGHT", -18, -36)
    attachHoverTooltip(cfgBtn, "EzWoW - Best Gear Finder", L["출처, 조건, 아이템 등급을 선택합니다."] .. " (/ezbg config)")

    local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
    local classBtn = ns.CreateStyledButton(containerFrame, 110, 20, (ns.viewClass and ns:ClassLabel(ns.viewClass) or L["내 캐릭터"]) .. " ▼", false)
    classBtn:SetPoint("RIGHT", cfgBtn, "LEFT", -6, 0)

    local itemBtn = ns.CreateStyledButton(containerFrame, 96, 20, L["아이템 검색"], false, function() if ns.ToggleCatalogSearchWindow then ns:ToggleCatalogSearchWindow() end end)
    itemBtn:SetPoint("RIGHT", classBtn, "LEFT", -6, 0)
    attachHoverTooltip(itemBtn, L["아이템 검색"], L["이름, 등급, 요구 레벨, 부위, 방어구/무기 종류, 획득처로 전체 아이템을 검색하는 창을 엽니다."])

    local classMenu = CreateFrame("Frame", nil, containerFrame, template)
    classMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    classMenu:SetFrameLevel(containerFrame:GetFrameLevel() + 30)
    classMenu:SetSize(120, (#CLASS_ORDER + 1) * 20 + 16)
    classMenu:SetPoint("TOPRIGHT", classBtn, "BOTTOMRIGHT", 0, -2)
    ns.ApplyWindowTheme(classMenu)
    MainGearAdvisorWindow.resolveSolidBG(classMenu)
    classMenu:Hide()
    local opts = { { nil, L["내 캐릭터"] } }
    for _, classToken in ipairs(CLASS_ORDER) do opts[#opts + 1] = { classToken, ns:ClassLabel(classToken) } end
    for i, optionRef in ipairs(opts) do
        local buttonWidget = CreateFrame("Button", nil, classMenu)
        buttonWidget:SetSize(110, 20)
        buttonWidget:SetPoint("TOPLEFT", 5, -8 - (i - 1) * 20)
        local resolvedValue = buttonWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        resolvedValue:SetPoint("CENTER")
        resolvedValue:SetText(optionRef[2])
        buttonWidget:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        buttonWidget:SetScript("OnClick", function()
            classMenu:Hide()
            ns:SetViewClass(optionRef[1])
            ns:RebuildMainGearWindow()
        end)
    end
    attachHoverTooltip(classBtn, L["직업 보기"], L["다른 직업의 추천 장비를 봅니다. 이때는 내 장비와 비교하지 않는 보기 전용입니다. '내 캐릭터'를 고르면 돌아갑니다."])
    classBtn:SetScript("OnClick", function()
        if classMenu:IsShown() then classMenu:Hide() else classMenu:Show() end
    end)
    containerFrame:HookScript("OnHide", function() classMenu:Hide() end)

    MainGearAdvisorWindow.resolveSolidBG(containerFrame)
    local function ApplyAlpha(a)
        a = math.max(0.3, math.min(1, a or 0.92))
        if containerFrame.solidBG then containerFrame.solidBG:SetAlpha(a) end
        if containerFrame.SetBackdropColor then containerFrame:SetBackdropColor(0.071, 0.094, 0.122, a) end
        if containerFrame.SetBackdropBorderColor then containerFrame:SetBackdropBorderColor(0.204, 0.298, 0.357, math.min(1, a + 0.2)) end
    end
    ns.ApplyMainAlpha = ApplyAlpha
    ApplyAlpha(ns.db.mainAlpha or 0.92)

    local lbl = containerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", 20, -66)
    lbl:SetText(L["요구 레벨"])

    local function constructEdit(anchor, dx)
        local recordEntry = ns.CreateStyledEditBox(containerFrame, 36, 20)
        recordEntry:SetPoint("LEFT", anchor, "RIGHT", dx, 0)
        recordEntry:SetTextInsets(2, 2, 0, 0)
        recordEntry:SetNumeric(true)
        recordEntry:SetMaxLetters(2)
        recordEntry:SetJustifyH("CENTER")
        recordEntry:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return recordEntry
    end
    minEdit = constructEdit(lbl, 16)
    local tilde = containerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tilde:SetPoint("LEFT", minEdit, "RIGHT", 4, 0)
    tilde:SetText("~")
    maxEdit = constructEdit(tilde, 4)

    local function applyConfiguration()
        ns:SetLevelFilterRange(minEdit:GetText(), maxEdit:GetText())
        minEdit:ClearFocus()
        maxEdit:ClearFocus()
        ns:ForceRefresh()
    end
    minEdit:SetScript("OnEnterPressed", applyConfiguration)
    maxEdit:SetScript("OnEnterPressed", applyConfiguration)
    minEdit:SetScript("OnTabPressed", function() maxEdit:SetFocus() end)
    maxEdit:SetScript("OnTabPressed", function() minEdit:SetFocus() end)

    local searchBtn = ns.CreateStyledButton(containerFrame, 64, 22, L["검색"], true, applyConfiguration)
    searchBtn:SetPoint("LEFT", maxEdit, "RIGHT", 8, 0)
    attachHoverTooltip(searchBtn, L["검색 / 새로고침"], L["입력한 요구 레벨 범위로, 현재 착용 중인 장비 기준으로 다시 계산합니다."])

    local autoBtn = ns.CreateStyledButton(containerFrame, 86, 22, L["자동(현재-10)"], false, function()
        ns:ResetLevelFilterRange()
        ns:ForceRefresh()
    end)
    autoBtn:SetPoint("LEFT", searchBtn, "RIGHT", 4, 0)
    attachHoverTooltip(autoBtn, L["자동 범위"], L["현재 레벨 -10 ~ 현재 레벨로 되돌립니다. 레벨업하면 같이 올라갑니다."])

    for i, spec in ipairs(specs) do
        local labelRegion = containerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelRegion:SetPoint("TOPLEFT", containerFrame, "TOPLEFT", 18 + (i - 1) * colW + 4, -92)
        labelRegion:SetWidth(colW - 8)
        labelRegion:SetJustifyH("LEFT")
        labelRegion:SetWordWrap(false)
        labelRegion:SetTextColor(MainGearAdvisorWindow.resolveRoleColor(spec.nameKo or spec.name))
        labelRegion:SetText(spec.name)
        colHeaders[i] = labelRegion
        local accent = containerFrame:CreateTexture(nil, "ARTWORK")
        accent:SetColorTexture(MainGearAdvisorWindow.resolveRoleColor(spec.nameKo or spec.name))
        accent:SetPoint("TOPLEFT", containerFrame, "TOPLEFT", 22 + (i - 1) * colW, -109)
        accent:SetSize(colW - 10, 2)
    end
    local line = containerFrame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.204, 0.298, 0.357, 0.85)
    line:SetPoint("TOPLEFT", containerFrame, "TOPLEFT", 18, -110)
    line:SetSize(colW * nCols, 1)

    scrollFrame = CreateFrame("ScrollFrame", "EzWoWBestGearFinderScroll", containerFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 18, -114)
    scrollFrame:SetPoint("BOTTOMRIGHT", -36, 38)
    child = CreateFrame("Frame", nil, scrollFrame)
    child:SetSize(colW * nCols, 10)
    scrollFrame:SetScrollChild(child)
    ns.ConfigureScrollWheelStep(scrollFrame, ROW_H)

    for i = 1, nCols - 1 do
        local dataEntry = child:CreateTexture(nil, "BACKGROUND")
        dataEntry:SetColorTexture(0.204, 0.298, 0.357, 0.5)
        dataEntry:SetWidth(1)
        dividers[i] = dataEntry
    end

    statusRegion = containerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusRegion:SetPoint("BOTTOMLEFT", 20, 18)
    statusRegion:SetPoint("BOTTOMRIGHT", -20, 18)
    statusRegion:SetJustifyH("LEFT")
    statusRegion:SetWordWrap(false)

    progress = CreateFrame("StatusBar", nil, containerFrame)
    progress:SetPoint("BOTTOMLEFT", 20, 9)
    progress:SetPoint("BOTTOMRIGHT", -40, 9)
    progress:SetHeight(6)
    progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    progress:SetStatusBarColor(0.945, 0.741, 0.341)
    progress:SetMinMaxValues(0, 1)
    local pbg = progress:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    pbg:SetColorTexture(0, 0, 0, 0.6)
    progress:Hide()

    local statusBtn = CreateFrame("Button", nil, containerFrame)
    statusBtn:SetPoint("BOTTOMLEFT", 20, 14)
    statusBtn:SetPoint("BOTTOMRIGHT", -40, 14)
    statusBtn:SetHeight(18)
    statusBtn:SetScript("OnEnter", function(btn)
        local stateEntry = ns.stats
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:AddLine(L["아이템 현황"], 1, 1, 1)
        GameTooltip:AddLine(format(L["조건에 맞는 후보: %d개"], stateEntry.candidates), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(format(L["게임에서 확인된 아이템: %d개"], stateEntry.ready), 0.6, 0.9, 0.6)
        if stateEntry.pending + (stateEntry.skipped or 0) > 0 then
            GameTooltip:AddLine(format(L["확인되지 않은 아이템: %d개 (게임에 없는 아이템이면 계속 확인되지 않습니다)"], stateEntry.pending + (stateEntry.skipped or 0)), 1, 0.82, 0, true)
        end
        GameTooltip:AddLine(L["점수는 직업·역할별 스탯 가중치로 계산한 추정치입니다."], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    statusBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    pcall(function()
        containerFrame:SetResizable(true)
        if containerFrame.SetResizeBounds then containerFrame:SetResizeBounds(frameW, 320, frameW, 1000)
        elseif containerFrame.SetMinResize then containerFrame:SetMinResize(frameW, 320) containerFrame:SetMaxResize(frameW, 1000) end
    end)
    local cornerResizeGrip = CreateFrame("Button", nil, containerFrame)
    cornerResizeGrip:SetSize(16, 16)
    cornerResizeGrip:SetPoint("BOTTOMRIGHT", -8, 8)
    cornerResizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    cornerResizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    cornerResizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    cornerResizeGrip:SetScript("OnMouseDown", function() containerFrame:StartSizing("BOTTOM") end)
    cornerResizeGrip:SetScript("OnMouseUp", function()
        containerFrame:StopMovingOrSizing()
        ns.db.height = math.floor(containerFrame:GetHeight())
    end)
    cornerResizeGrip:SetScript("OnEnter", function(g)
        GameTooltip:SetOwner(g, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["드래그해서 창 높이를 조절합니다."], 1, 1, 1)
        GameTooltip:Show()
    end)
    cornerResizeGrip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ns.frame = containerFrame
end

function MainGearAdvisorWindow.dismissAll()
    for _, buttonWidget in ipairs(hbtns) do buttonWidget:Hide() end
    for _, rowEntry in ipairs(rowWidgets) do rowEntry:Hide() end
    for _, h in ipairs(headerPool) do h:Hide() end
    for _, dataEntry in ipairs(dividers) do dataEntry:Hide() end
end

function MainGearAdvisorWindow.presentMessage(text)
    MainGearAdvisorWindow.dismissAll()
    local h = headerPool[1] or MainGearAdvisorWindow.buildHeader(1)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -8)
    h:SetWidth(math.min(colW * nCols - 8, 420))
    h:SetWordWrap(true)
    h:SetTextColor(1, 0.82, 0)
    h:SetText(text)
    h:Show()
    child:SetHeight(120)
end

function MainGearAdvisorWindow.assignProgress(frac)
    if not progress then return end
    if frac == nil then progress:Hide(); return end
    progress:SetValue(math.max(0, math.min(1, frac)))
    progress:Show()
end

function ns:UpdateProgress()
    if statusRegion and self.indexState == "running" then
        if self.indexStats.scanned then
            MainGearAdvisorWindow.assignProgress(self.indexStats.scanned / 400000)
        else
            MainGearAdvisorWindow.assignProgress(nil)
        end
        statusRegion:SetText("")
    end
end

function ns:UpdateUI()
    if ns.UpdateLauncher then ns:UpdateLauncher() end
    if not containerFrame then return end
    local class = ns:GetActiveClassToken()
    titleText:SetText(format("EzWoW - Best Gear Finder  %s%s|r  Lv.%d", MainGearAdvisorWindow.formatColorAsHexCode(RAID_CLASS_COLORS[class]), (ns.ClassLabel and ns:ClassLabel(class)) or ns:GetActiveClassDisplayName() or "", UnitLevel("player")))
    local loVal, hiVal, hasAuto = self:GetLevelFilterRange()
    if not minEdit:HasFocus() then minEdit:SetText(tostring(loVal)) end
    if not maxEdit:HasFocus() then maxEdit:SetText(tostring(hiVal)) end
    if configFrame and configFrame:IsShown() and configFrame.RefreshCfg then
        configFrame.RefreshCfg()
    end

    MainGearAdvisorWindow.assignProgress(nil)
    local unitState = self.indexState
    if self.lastError and unitState == "done" then
        MainGearAdvisorWindow.presentMessage(L["계산 중 오류가 발생했습니다.\n\n"] .. tostring(self.lastError):sub(1, 400) .. L["\n\n(채팅창에도 출력됩니다. 이 내용을 알려주세요)"])
        statusRegion:SetText("")
        return
    end
    if unitState == "idle" or (unitState == "running" and not self.indexBaseReady) then
        MainGearAdvisorWindow.presentMessage(L["아이템 정보를 불러오는 중입니다..."])
        self:UpdateProgress()
        return
    elseif unitState == "empty" then
        MainGearAdvisorWindow.presentMessage(L["기본 장비 드랍 데이터를 읽지 못했습니다.\n\n/ezbg 진단 내용을 확인해 주세요."])
        statusRegion:SetText("")
        return
    end

    MainGearAdvisorWindow.dismissAll()
    local function isElementCurrentlyVisible(list)
        if not list or not self.db.upgradeOnly or (ns.searchText or "") ~= "" then return list end
        local outputList = {}
        for _, recordEntry in ipairs(list) do if recordEntry.upgrade or not recordEntry.comparable then outputList[#outputList + 1] = recordEntry end end
        return #outputList > 0 and outputList or nil
    end
    local plotBands = {}
    for _, band in ipairs(self.bands) do
        local itemCount = 0
        for siVal = 1, nCols do
            local leftPos = isElementCurrentlyVisible(self.views[siVal] and self.views[siVal][band.group.key])
            if leftPos and #leftPos > itemCount then itemCount = #leftPos end
        end
        if itemCount > 0 then plotBands[#plotBands + 1] = { group = band.group, count = itemCount } end
    end
    local coordY, hdrN, riVal = 0, 0, 0
    for _, band in ipairs(plotBands) do
        hdrN = hdrN + 1
        local collapsed = self.db.collapsed and self.db.collapsed[band.group.key]
        local hbVal = hbtns[hdrN] or MainGearAdvisorWindow.buildSlotHeader(hdrN)
        hbVal.key = band.group.key
        hbVal.label:SetText(band.group.label)
        hbVal.action:SetText(collapsed and L["펼치기"] or L["접기"])
        hbVal.indicator:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
        hbVal:ClearAllPoints()
        hbVal:SetPoint("TOPLEFT", child, "TOPLEFT", 2, -coordY)
        hbVal:SetSize(colW * nCols - 4, HEADER_H)
        hbVal:Show()
        coordY = coordY + HEADER_H
        if collapsed then coordY = coordY + 4 else
        for siVal = 1, nCols do
            local list = isElementCurrentlyVisible(self.views[siVal] and self.views[siVal][band.group.key])
            if list then
                for nodeEntry, recordEntry in ipairs(list) do
                    riVal = riVal + 1
                    local rowEntry = rowWidgets[riVal] or MainGearAdvisorWindow.buildRow(riVal)
                    rowEntry:SetSize(colW - 6, ROW_H)
                    rowEntry:ClearAllPoints()
                    rowEntry:SetPoint("TOPLEFT", child, "TOPLEFT", (siVal - 1) * colW + 2, -(coordY + (nodeEntry - 1) * ROW_H))
                    rowEntry.link, rowEntry.rec, rowEntry.baseIlvl, rowEntry.score, rowEntry.baseScore, rowEntry.bis = recordEntry.link, recordEntry.rec, recordEntry.baseIlvl, recordEntry.score, recordEntry.baseScore, recordEntry.bis
                    rowEntry.id = recordEntry.id
                    rowEntry.baseLink, rowEntry.weights = recordEntry.baseLink, recordEntry.weights
                    rowEntry.comparable, rowEntry.compareNote = recordEntry.comparable, recordEntry.compareNote
                    rowEntry.icon:SetTexture(recordEntry.rec.icon)
                    local quality = ITEM_QUALITY_COLORS[recordEntry.quality] or { r = 0.5, g = 0.6, b = 0.7 }
                    rowEntry.accent:SetColorTexture(quality.r, quality.g, quality.b, 0.85)
                    rowEntry.bg:SetColorTexture(recordEntry.upgrade and 0.095 or 0.114, recordEntry.upgrade and 0.185 or 0.157, recordEntry.upgrade and 0.175 or 0.192, 0.95)
                    rowEntry.name:SetText(recordEntry.link)
                    local comparison
                    if not recordEntry.comparable then comparison = "|cff8ba9c4" .. (recordEntry.compareNote or L["참고 장비"]) .. "|r"
                    elseif (recordEntry.baseScore or 0) <= 0 then comparison = "|cff68d9a4" .. L["빈 슬롯"] .. "|r"
                    else
                        local delta = (recordEntry.score - recordEntry.baseScore) / recordEntry.baseScore * 100
                        comparison = (recordEntry.upgrade and "|cff68d9a4▲ " or "|cff9baabd") .. format("%+.1f%%", delta) .. "|r"
                    end
                    local badge = recordEntry.bis == 2 and " |cffffcf68BiS|r" or (recordEntry.bis == 1 and " |cff9baabdBiS*|r" or "")
                    rowEntry.sub:SetText(comparison .. " · " .. (recordEntry.sortVal and format(L["정렬 %.1f"], recordEntry.sortVal) or format(L["점수 %.1f"], recordEntry.score)) .. badge)
                    local req = (recordEntry.req or 0) > 0 and format(L["요구 %d"], recordEntry.req) or L["요구 없음"]
                    rowEntry.source:SetText(req .. " · " .. self:FormatCompactDropSource(recordEntry.rec, recordEntry.id))
                    rowEntry:Show()
                end
            end
        end
        coordY = coordY + band.count * ROW_H + 6
        end
    end
    child:SetHeight(math.max(coordY, 10))
    
    if scrollFrame.UpdateScrollChildRect then scrollFrame:UpdateScrollChildRect() end
    C_Timer.After(0, function()
        if scrollFrame and scrollFrame.UpdateScrollChildRect then scrollFrame:UpdateScrollChildRect() end
        local range = scrollFrame and scrollFrame.GetVerticalScrollRange and scrollFrame:GetVerticalScrollRange()
        if range and scrollFrame:GetVerticalScroll() > range then scrollFrame:SetVerticalScroll(range) end
    end)
    for i, dataEntry in ipairs(dividers) do
        dataEntry:ClearAllPoints()
        dataEntry:SetPoint("TOPLEFT", child, "TOPLEFT", i * colW, 0)
        dataEntry:SetHeight(math.max(coordY, 10))
        dataEntry:Show()
    end

    if #plotBands == 0 then
        local rawMessage = self.stats.pending > 0 and L["아이템 정보를 불러오는 중입니다..."] or
            (self.db.upgradeOnly and L["현재 조건에서 업그레이드할 아이템이 없습니다.\n('업그레이드만' 체크를 풀거나 요구 레벨 범위를 넓혀보세요)"] or L["추천할 아이템이 없습니다."])
        MainGearAdvisorWindow.presentMessage(rawMessage)
    end

    local stateFlag = self.stats
    if (self.itemErrors or 0) > 0 then
        statusRegion:SetText(format(L["일부 아이템 처리 오류 %d건 (/ezbg 진단)"], self.itemErrors))
        return
    end
    local pend = ""
    if stateFlag.pending > 0 then
        MainGearAdvisorWindow.assignProgress(stateFlag.ready / math.max(1, stateFlag.ready + stateFlag.pending))
        pend = format(L[" · %d개 불러오는 중"], stateFlag.pending)
    elseif (stateFlag.skipped or 0) > 0 then
        pend = format(L[" · 게임에 없는 %d개 제외"], stateFlag.skipped)
    end
    statusRegion:SetText(format(L["요구 레벨 %d~%d%s · 확인된 아이템 %d개%s · 점수는 추정치"], loVal, hiVal, hasAuto and L["(자동)"] or "", stateFlag.ready, pend))
end

local configFrame, BlizzardOptionsCanvas

function ns:RebuildMainGearWindow()
    if containerFrame then
        local wasShown = containerFrame:IsShown()
        containerFrame:Hide()
        containerFrame:ClearAllPoints()
        for i = #UISpecialFrames, 1, -1 do
            if UISpecialFrames[i] == "EzWoWBestGearFinderFrame" then table.remove(UISpecialFrames, i) end
        end
        wipe(rowWidgets) wipe(headerPool) wipe(colHeaders) wipe(dividers) wipe(qualChk) wipe(menuChecks) wipe(hbtns)
        chanceEdit, aucChk, containerFrame, ns.frame = nil, nil, nil, nil
        MainGearAdvisorWindow.assembleFrame()
        if wasShown then containerFrame:Show() end
    end
    if ns.RebuildCatalogSearchWindow then ns:RebuildCatalogSearchWindow() end
    if configFrame then
        local wasCfgShown = configFrame:IsShown()
        configFrame:Hide()
        configFrame = nil
        if wasCfgShown then ns:ToggleSettingsWindow() end
    end
    if BlizzardOptionsCanvas and BlizzardOptionsCanvas.RefreshTexts then
        BlizzardOptionsCanvas:RefreshTexts()
    end
end

function ns:ToggleMainGearWindow()
    if not containerFrame then
        if not self.db then return end
        MainGearAdvisorWindow.assembleFrame()
    end
    if containerFrame:IsShown() then containerFrame:Hide() else containerFrame:Show() end
end

ns.ApplyAlpha = ApplyAlpha
ns.GetConfigFrame = function() return configFrame end
ns.SetConfigFrame = function(f) configFrame = f end
ns.GetOptionsPanel = function() return BlizzardOptionsCanvas end
ns.SetOptionsPanel = function(anchorTarget) BlizzardOptionsCanvas = anchorTarget end

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
MainGearAdvisorWindow.CreateStyledButton = ns.CreateStyledButton
MainGearAdvisorWindow.CreateStyledEditBox = ns.CreateStyledEditBox
MainGearAdvisorWindow.RebuildMainGearWindow = ns.RebuildMainGearWindow
MainGearAdvisorWindow.ConfigureScrollWheelStep = ns.ConfigureScrollWheelStep
MainGearAdvisorWindow.ApplySolidBackdrop = ns.ApplySolidBackdrop
MainGearAdvisorWindow.ApplyWindowTheme = ns.ApplyWindowTheme
MainGearAdvisorWindow.ToggleMainGearWindow = ns.ToggleMainGearWindow
