--===========================================================================
-- EzWoW - Best Gear Finder
-- UI/OptionsWindow.lua : EzWoW Style Settings Dialog & Blizzard Options Panel
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local SettingsDialog = ns.SettingsDialog or {}
ns.SettingsDialog = SettingsDialog
local L = ns.L
local commitAlpha = ns.ApplyAlpha

local Theme = {
    bg     = { 0.071, 0.094, 0.122, 0.97 },
    bgSub  = { 0.114, 0.157, 0.192, 0.96 },
    border = { 0.204, 0.298, 0.357, 1.00 },
    accent = { 0.945, 0.741, 0.341, 1.00 }, 
    text   = { 0.929, 0.957, 0.969, 1.00 },
    muted  = { 0.655, 0.725, 0.773, 1.00 },
}
local GEAR_FINDER_ICON = "Interface\\AddOns\\EzWoW-BestGearFinder\\Media\\icon"

function SettingsDialog.buildConfigWindow()
    if ns.GetConfigFrame() then return ns.GetConfigFrame() end
    local windowFrame = CreateFrame("Frame", "EzWoWBestGearFinderConfig", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    windowFrame:SetSize(460, 536)
    windowFrame:SetPoint("CENTER")
    windowFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    windowFrame:SetToplevel(true)
    windowFrame:SetClampedToScreen(true)
    windowFrame:SetMovable(true)
    windowFrame:EnableMouse(true)
    if windowFrame.SetBackdrop then
        ns.UIKit:ApplyBackdrop(windowFrame, 1, 1)
        windowFrame:SetBackdropColor(unpack(Theme.bg))
        windowFrame:SetBackdropBorderColor(unpack(Theme.border))
    end
    if UISpecialFrames then tinsert(UISpecialFrames, "EzWoWBestGearFinderConfig") end

    local top = CreateFrame("Frame", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    top:SetPoint("TOPLEFT", windowFrame, "TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", windowFrame, "TOPRIGHT", -1, -1)
    top:SetHeight(56)
    if top.SetBackdrop then
        top:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        top:SetBackdropColor(unpack(Theme.bgSub))
    end
    top:EnableMouse(true)
    top:RegisterForDrag("LeftButton")
    top:SetScript("OnDragStart", function() windowFrame:StartMoving() end)
    top:SetScript("OnDragStop", function() windowFrame:StopMovingOrSizing() end)

    local accentLine = top:CreateTexture(nil, "ARTWORK")
    accentLine:SetColorTexture(unpack(Theme.accent))
    accentLine:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", 0, 0)
    accentLine:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 0, 0)
    accentLine:SetHeight(2)

    local titleIcon = top:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(28, 28)
    titleIcon:SetPoint("TOPLEFT", 14, -14)
    titleIcon:SetTexture(GEAR_FINDER_ICON)

    local headingRegion = top:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    headingRegion:SetPoint("TOPLEFT", 48, -11)
    headingRegion:SetText("EzWoW - Best Gear Finder")
    headingRegion:SetTextColor(unpack(Theme.accent))

    local subtitleRegion = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitleRegion:SetPoint("TOPLEFT", headingRegion, "BOTTOMLEFT", 0, -3)
    subtitleRegion:SetWidth(365)
    subtitleRegion:SetJustifyH("LEFT")
    subtitleRegion:SetTextColor(unpack(Theme.muted))
    subtitleRegion:SetText(L["점수는 직업·역할별 스탯 가중치로 계산한 추정치입니다."])

    local cfgChecks = {}
    local qualChecks = {}
    local syncCfg

    local function createSectionDivider(y, text)
        local resolvedValue = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        resolvedValue:SetPoint("TOPLEFT", 20, y)
        resolvedValue:SetTextColor(unpack(Theme.accent))
        resolvedValue:SetText(text)
        local line = windowFrame:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.204, 0.298, 0.357, 0.85)
        line:SetPoint("TOPLEFT", windowFrame, "TOPLEFT", 20, y - 18)
        line:SetPoint("TOPRIGHT", windowFrame, "TOPRIGHT", -20, y - 18)
        line:SetHeight(1)
        return resolvedValue
    end

    local function createStyledButton(x, y, w, h, text, isAccent, onClick)
        local buttonWidget = CreateFrame("Button", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        buttonWidget:SetSize(w, h)
        buttonWidget:SetPoint("TOPLEFT", x, y)
        if buttonWidget.SetBackdrop then
            ns.UIKit:ApplyBackdrop(buttonWidget, 1, 1)
        end
        local function applyNormalButtonLook()
            if not buttonWidget.SetBackdropColor then return end
            if isAccent then
                buttonWidget:SetBackdropColor(0.23, 0.19, 0.11, 0.96)
                buttonWidget:SetBackdropBorderColor(unpack(Theme.accent))
            else
                buttonWidget:SetBackdropColor(unpack(Theme.bgSub))
                buttonWidget:SetBackdropBorderColor(unpack(Theme.border))
            end
        end
        applyNormalButtonLook()
        local formatLocalizedLabel = buttonWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        formatLocalizedLabel:SetPoint("CENTER")
        formatLocalizedLabel:SetTextColor(unpack(isAccent and Theme.accent or Theme.text))
        formatLocalizedLabel:SetText(text or "")
        buttonWidget.label = formatLocalizedLabel
        buttonWidget:SetScript("OnEnter", function()
            if buttonWidget.SetBackdropColor then
                buttonWidget:SetBackdropColor(0.20, 0.25, 0.30, 1)
                buttonWidget:SetBackdropBorderColor(unpack(Theme.accent))
            end
        end)
        buttonWidget:SetScript("OnLeave", applyNormalButtonLook)
        buttonWidget:SetScript("OnMouseDown", function() formatLocalizedLabel:SetPoint("CENTER", 1, -1) end)
        buttonWidget:SetScript("OnMouseUp", function() formatLocalizedLabel:SetPoint("CENTER", 0, 0) end)
        buttonWidget:SetScript("OnClick", onClick)
        return buttonWidget
    end

    local close = createStyledButton(428, -14, 22, 22, "X", false, function() windowFrame:Hide() end)
    close:SetFrameLevel(top:GetFrameLevel() + 3)

    local function createStyledCheckbox(x, y, w, text, key, tipText)
        local themeColor = CreateFrame("CheckButton", nil, windowFrame, "UICheckButtonTemplate")
        themeColor:SetSize(24, 24)
        themeColor:SetPoint("TOPLEFT", x, y)
        themeColor.key = key
        themeColor:SetScript("OnClick", function(self)
            ns.db[key] = self:GetChecked() and true or false
            if key == "iconShown" and ns.UpdateLauncher then ns:UpdateLauncher() end
            ns:Refresh(true)
            syncCfg()
        end)
        if tipText then
            themeColor:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(text, unpack(Theme.accent))
                GameTooltip:AddLine(tipText, 0.85, 0.90, 0.95, true)
                GameTooltip:Show()
            end)
            themeColor:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        local displayText = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        displayText:SetPoint("LEFT", themeColor, "RIGHT", 4, 0)
        displayText:SetWidth(w or 180)
        displayText:SetJustifyH("LEFT")
        displayText:SetTextColor(unpack(Theme.text))
        displayText:SetText(text)
        cfgChecks[#cfgChecks + 1] = themeColor
        return themeColor
    end

    createSectionDivider(-70, L["조건"])
    local langOpts = ns.LANGUAGE_OPTIONS or { { nil, "Auto" }, { "koKR", "한국어" }, { "enUS", "English" } }
    local langBtn = createStyledButton(250, -66, 190, 20, "", false, function(_, button)
        local currentState = ns.db.lang
        local entryIndex = 1
        for index, optionRef in ipairs(langOpts) do
            if optionRef[1] == currentState then entryIndex = index; break end
        end
        if button == "RightButton" then
            entryIndex = entryIndex - 1; if entryIndex < 1 then entryIndex = #langOpts end
        else
            entryIndex = entryIndex + 1; if entryIndex > #langOpts then entryIndex = 1 end
        end
        ns.db.lang = langOpts[entryIndex][1]
        if ns.SetLang then ns.SetLang(ns.db.lang) end
        if ns.RelabelData then ns.RelabelData() end
        ns:RebuildMainGearWindow()
    end)
    langBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    createStyledCheckbox(18, -94, 180, L["업그레이드만"], "upgradeOnly", L["착용 중인 장비보다 추정 점수가 높은 아이템만 추천 목록에 표시합니다."])
    createStyledCheckbox(232, -94, 180, L["출처가 확인된 것만"], "sourcedOnly", L["획득처 정보가 확인된 아이템만 추천 목록에 표시합니다."])
    createStyledCheckbox(18, -120, 180, L["다른 직업 전용 숨김"], "classFilter", L["다른 직업 전용 아이템을 추천 목록에서 제외합니다."])
    createStyledCheckbox(232, -120, 180, L["몹 레벨 제한 (범위+8)"], "mobCut", L["지정한 요구 레벨 상한보다 8레벨을 초과해 높은 몬스터가 드랍하는 아이템은 제외합니다."])
    createStyledCheckbox(18, -146, 180, L["아이템 툴팁에 획득처 표시"], "itemTooltip", L["마우스를 올린 아이템의 기본 툴팁에 드랍 보스·던전·30레벨 BiS 정보를 표시합니다."])
    createStyledCheckbox(232, -146, 180, L["착용 장비 비교 툴팁 자동 표시"], "showEquipCompare", L["장비 추천·검색 목록에 마우스를 올리면 현재 착용 중인 장비 비교 툴팁을 자동으로 함께 표시합니다."])
    createStyledCheckbox(18, -172, 180, L["화면에 아이콘 표시"], "iconShown", L["화면에 Best Gear Finder 실행 버튼 아이콘을 표시합니다."])
    createStyledCheckbox(232, -172, 180, L["획득처 자동 기록"], "learn", L["루팅 및 상점 이용 시 새로 확인된 아이템 획득처를 자동으로 기록합니다."])

    local perLbl = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    perLbl:SetPoint("TOPLEFT", 20, -202)
    perLbl:SetTextColor(unpack(Theme.muted))
    perLbl:SetText(L["슬롯당 표시 개수"])
    local perMinus = createStyledButton(140, -198, 22, 20, "-", false, function()
        ns.db.perSlot = math.max(2, (ns.db.perSlot or 2) - 1)
        ns:Refresh(true)
        syncCfg()
    end)
    local perVal = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    perVal:SetPoint("LEFT", perMinus, "RIGHT", 2, 0)
    perVal:SetWidth(38)
    perVal:SetJustifyH("CENTER")
    perVal:SetTextColor(unpack(Theme.text))
    createStyledButton(204, -198, 22, 20, "+", false, function()
        ns.db.perSlot = math.min(10, (ns.db.perSlot or 2) + 1)
        ns:Refresh(true)
        syncCfg()
    end)

    createSectionDivider(-228, L["출처"])
    createStyledCheckbox(18, -252, 180, L["제작템 포함"], "crafting", L["전문기술로 제작할 수 있는 장비도 추천 목록에 포함합니다."])
    createStyledCheckbox(232, -252, 180, L["퀘스트 보상"], "quests", L["퀘스트 보상으로 획득할 수 있는 장비도 추천 목록에 포함합니다."])
    createStyledCheckbox(18, -278, 180, L["월드 드랍 (저확률)"], "auction", L["드랍 확률이 기준치보다 낮은 월드 드랍(착용 시 귀속 등) 아이템도 포함합니다."])
    createStyledCheckbox(232, -278, 180, L["신규 아이템 포함 (출처 불명)"], "newItems", L["게임 클라이언트에서 새로 탐색된 출처 미확인 아이템도 포함합니다."])

    createSectionDivider(-310, L["등급"])
    local QUALS = {
        { 0, L["하급"], "|cff9d9d9d" }, { 1, L["일반"], "|cffffffff" }, { 2, L["고급"], "|cff1eff00" },
        { 3, L["희귀"], "|cff0070dd" }, { 4, L["영웅"], "|cffa335ee" }, { 5, L["전설"], "|cffff8000" },
    }
    for index, priorityQueue in ipairs(QUALS) do
        local columnIndex = (index - 1) % 3
        local rowWidget = math.floor((index - 1) / 3)
        local checkWidget = CreateFrame("CheckButton", nil, windowFrame, "UICheckButtonTemplate")
        checkWidget:SetSize(24, 24)
        checkWidget:SetPoint("TOPLEFT", 18 + columnIndex * 140, -332 - rowWidget * 26)
        checkWidget.q = priorityQueue[1]
        checkWidget:SetScript("OnClick", function(self)
            ns.db.qual[self.q] = self:GetChecked() and true or nil
            ns:Refresh(true)
            syncCfg()
        end)
        local qtVal = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        qtVal:SetPoint("LEFT", checkWidget, "RIGHT", 4, 0)
        qtVal:SetText(priorityQueue[3] .. priorityQueue[2] .. "|r")
        qualChecks[index] = checkWidget
    end

    createStyledButton(20, -396, 204, 26, "EzWoW - Best Gear Finder (/ezbg)", false, function()
        ns:ToggleMainGearWindow()
    end)
    createStyledButton(236, -396, 204, 26, L["아이템 검색"] .. " (/ezbg find)", false, function()
        if ns.ToggleCatalogSearchWindow then ns:ToggleCatalogSearchWindow() end
    end)

    local alphaLbl = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    alphaLbl:SetPoint("TOPLEFT", 20, -436)
    alphaLbl:SetTextColor(unpack(Theme.muted))
    alphaLbl:SetText(L["투명도"])
    local alphaMinus = createStyledButton(120, -432, 24, 20, "-", false, function()
        ns.db.mainAlpha = math.max(0.3, math.floor(((ns.db.mainAlpha or 0.92) - 0.05) * 20 + 0.5) / 20)
        if ns.ApplyMainAlpha then ns.ApplyMainAlpha(ns.db.mainAlpha) end
        syncCfg()
    end)
    local alphaVal = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    alphaVal:SetPoint("LEFT", alphaMinus, "RIGHT", 2, 0)
    alphaVal:SetWidth(46)
    alphaVal:SetJustifyH("CENTER")
    alphaVal:SetTextColor(unpack(Theme.text))
    createStyledButton(194, -432, 24, 20, "+", false, function()
        ns.db.mainAlpha = math.min(1.0, math.floor(((ns.db.mainAlpha or 0.92) + 0.05) * 20 + 0.5) / 20)
        if ns.ApplyMainAlpha then ns.ApplyMainAlpha(ns.db.mainAlpha) end
        syncCfg()
    end)

    local chanceLbl = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chanceLbl:SetPoint("TOPLEFT", 236, -436)
    chanceLbl:SetWidth(112)
    chanceLbl:SetJustifyH("LEFT")
    chanceLbl:SetTextColor(unpack(Theme.muted))
    chanceLbl:SetText(L["월드 드랍 (저확률)"])
    local chanceMinus = createStyledButton(354, -432, 22, 20, "-", false, function()
        ns.db.minChance = math.max(0, math.floor(((ns.db.minChance or 1) - 0.5) * 2 + 0.5) / 2)
        ns:Refresh(true)
        syncCfg()
    end)
    local chanceVal = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chanceVal:SetPoint("LEFT", chanceMinus, "RIGHT", 2, 0)
    chanceVal:SetWidth(38)
    chanceVal:SetJustifyH("CENTER")
    chanceVal:SetTextColor(unpack(Theme.text))
    createStyledButton(418, -432, 22, 20, "+", false, function()
        ns.db.minChance = math.min(20, math.floor(((ns.db.minChance or 1) + 0.5) * 2 + 0.5) / 2)
        ns:Refresh(true)
        syncCfg()
    end)

    createStyledButton(20, -472, 204, 28, L["창 위치 초기화"] .. " / " .. L["아이콘 복원"], false, function()
        ns.db.point = nil
        ns.db.iconShown = true
        if ns.frame then ns.frame:ClearAllPoints(); ns.frame:SetPoint("CENTER") end
        if ns.ResetLauncher then ns:ResetLauncher() end
        if syncCfg then syncCfg() end
        if ns.Print then ns.Print(L["창 위치를 초기화했습니다."]) end
    end)
    createStyledButton(236, -472, 204, 28, L["후원"], true, function()
        ns:ShowDonate()
    end)

    local footerRegion = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footerRegion:SetPoint("BOTTOMRIGHT", -20, 10)
    footerRegion:SetText("EzWoW - Best Gear Finder · /ezbg")
    footerRegion:SetTextColor(unpack(Theme.muted))

    syncCfg = function()
        if not ns.db then return end
        for _, themeColor in ipairs(cfgChecks) do
            themeColor:SetChecked(ns.db[themeColor.key] and true or false)
        end
        for _, qcVal in ipairs(qualChecks) do
            qcVal:SetChecked(ns.db.qual and ns.db.qual[qcVal.q] and true or false)
        end
        perVal:SetText((ns.db.perSlot or 2) .. L["개"])
        alphaVal:SetText(string.format("%d%%", (ns.db.mainAlpha or 0.92) * 100 + 0.5))
        chanceVal:SetText(string.format("<%.1f%%", ns.db.minChance or 1))
        local langLabel = "Auto"
        for _, optionRef in ipairs(langOpts) do
            if optionRef[1] == ns.db.lang then langLabel = optionRef[2]; break end
        end
        langBtn.label:SetText(L["언어"] .. ": " .. langLabel .. " ▼")
    end

    windowFrame.RefreshCfg = syncCfg
    windowFrame:SetScript("OnShow", syncCfg)
    syncCfg()
    windowFrame:Hide()
    ns.SetConfigFrame(windowFrame)
    return windowFrame
end

function ns:ToggleSettingsWindow()
    if not self.db then return end
    local windowFrame = SettingsDialog.buildConfigWindow()
    windowFrame:SetShown(not windowFrame:IsShown())
    if windowFrame:IsShown() then windowFrame:Raise() end
end

function ns:RegisterOptionsPanel()
    if ns.GetOptionsPanel() then return end
    local panelFrameEntry = CreateFrame("Frame", "EzWoWBestGearFinderOptionsPanel", UIParent)
    panelFrameEntry.name = "EzWoW - Best Gear Finder"
    ns.SetOptionsPanel(panelFrameEntry)

    local iconTex = panelFrameEntry:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(32, 32)
    iconTex:SetPoint("TOPLEFT", 18, -18)
    iconTex:SetTexture(GEAR_FINDER_ICON)

    local headingRegion = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    headingRegion:SetPoint("LEFT", iconTex, "RIGHT", 10, 0)
    headingRegion:SetText("EzWoW - Best Gear Finder")
    headingRegion:SetTextColor(unpack(Theme.accent))

    local desc = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", iconTex, "BOTTOMLEFT", 0, -14)
    desc:SetWidth(520)
    desc:SetJustifyH("LEFT")

    local launchBtn = ns.CreateStyledButton(panelFrameEntry, 240, 28, "", true, function()
        ns:ToggleSettingsWindow()
    end)
    launchBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)

    local hint = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", launchBtn, "BOTTOMLEFT", 0, -14)
    hint:SetTextColor(unpack(Theme.muted))

    function panelFrameEntry:RefreshTexts()
        local hasKo = (not ns.GetActiveLocale) or (ns.GetActiveLocale() == "koKR")
        desc:SetText(hasKo and "내 직업과 레벨에서 착용할 수 있는 추천 장비와 획득처(던전·제작·퀘스트)를 딜·탱·힐 역할별로 비교합니다." or "Finds the best gear for your class and level with drop, craft, and quest sources across DPS, Tank, and Healer roles.")
        launchBtn:SetText((hasKo and "설정" or (SETTINGS or "Settings")) .. " (/ezbg)")
        hint:SetText(hasKo and "채팅창에 /ezbg 또는 /ezbg config를 입력해도 열립니다." or "Type /ezbg or /ezbg config in chat to open settings.")
    end
    panelFrameEntry:SetScript("OnShow", function(self) self:RefreshTexts() end)
    panelFrameEntry:RefreshTexts()

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local isCallOk, categoryKey = pcall(Settings.RegisterCanvasLayoutCategory, panelFrameEntry, panelFrameEntry.name)
        if isCallOk and categoryKey then pcall(Settings.RegisterAddOnCategory, categoryKey) end
    elseif InterfaceOptions_AddCategory then
        pcall(InterfaceOptions_AddCategory, panelFrameEntry)
    end
end

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
SettingsDialog.ToggleSettingsWindow = ns.ToggleSettingsWindow
