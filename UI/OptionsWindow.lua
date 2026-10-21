--===========================================================================
-- EzWoW - Best Gear Finder
-- UI/OptionsWindow.lua : EzWoW Style Settings Dialog & Blizzard Options Panel
--===========================================================================
local ADDON, ns = ...
-- Text for the game's AddOns panel in the six languages without their own line: { deDE, frFR, esES, ruRU, zhCN, zhTW }
local PANEL_LANG_INDEX = { deDE = 1, frFR = 2, esES = 3, esMX = 3, ruRU = 4, zhCN = 5, zhTW = 6, de = 1, fr = 2, es = 3, ru = 4 }
local function panelText(code, ko, en, others)
    if code == "koKR" or code == "ko" then return ko end
    local index = PANEL_LANG_INDEX[code or ""]
    return (index and others and others[index]) or en
end
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
        ns.UIKit:FitFontString(formatLocalizedLabel, w - 8, 1)
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
        ns.UIKit:FitFontString(displayText, w or 180, 2)
        cfgChecks[#cfgChecks + 1] = themeColor
        return themeColor
    end

    createSectionDivider(-70, L["조건"])
    local langOpts = ns.LANGUAGE_OPTIONS or { { nil, "Auto" }, { "koKR", "한국어" }, { "enUS", "English" } }
    local langBtn = createStyledButton(250, -66, 190, 20, "", false, nil)
    local langItems = {}
    for index, optionRef in ipairs(langOpts) do langItems[index] = { value = optionRef[1], text = optionRef[2] } end
    -- click the box, then pick a language from the list
    ns.LanguageDropdown.Attach(langBtn, {
        items = langItems,
        colors = { bg = Theme.bg, border = Theme.border, accent = Theme.accent, text = Theme.text },
        get = function() return ns.db.lang end,
        set = function(code)
            ns.db.lang = code
            if ns.SetLang then ns.SetLang(ns.db.lang) end
            if ns.RelabelData then ns.RelabelData() end
            ns:RebuildMainGearWindow()
        end,
    })

    createStyledCheckbox(18, -94, 180, L["업그레이드만"], "upgradeOnly", L["현재 착용 장비보다 점수가 높은 것만 보여줍니다."])
    createStyledCheckbox(232, -94, 180, L["출처가 확인된 것만"], "sourcedOnly", L["던전·제작·퀘스트 등 획득처가 확인된 아이템만 보여줍니다. 출처를 알 수 없는 신규 아이템과 저확률 월드 드랍은 제외됩니다."])
    createStyledCheckbox(18, -120, 180, L["다른 직업 전용 숨김"], "classFilter", L["툴팁에 직업 제한이 있고 내 직업이 아니면 제외합니다."])
    createStyledCheckbox(232, -120, 180, L["몹 레벨 제한 (범위+8)"], "mobCut", L["출처 몬스터의 레벨이 요구 레벨 상한+8을 넘으면 제외합니다."])
    createStyledCheckbox(18, -146, 180, L["아이템 툴팁에 획득처 표시"], "itemTooltip", L["가방·채팅 링크·상인 창 등 게임의 아이템 툴팁에 이 애드온이 아는 획득처와 BiS 여부를 붙입니다."])
    createStyledCheckbox(232, -146, 180, L["착용 장비 비교 툴팁 자동 표시"], "showEquipCompare", L["아이템에 마우스를 올리면 Shift 키를 누르지 않아도 현재 착용 중인 장비 비교 툴팁을 나란히 표시합니다."])
    createStyledCheckbox(18, -172, 180, L["화면에 아이콘 표시"], "iconShown", L["게임 화면에 떠 있는 실행 아이콘을 보여줍니다. 드래그해서 옮길 수 있습니다."])
    createStyledCheckbox(232, -172, 180, L["획득처 자동 기록"], "learn", L["던전·필드에서 줍거나 퀘스트 보상·상인에서 본 장비 중 데이터에 획득처가 없는 것을 자동으로 기록해, 툴팁과 목록에 '(직접 확인)'으로 보여줍니다."])

    local perLbl = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    perLbl:SetPoint("TOPLEFT", 20, -202)
    perLbl:SetTextColor(unpack(Theme.muted))
    perLbl:SetText(L["슬롯당 표시 개수"])
    ns.UIKit:FitFontString(perLbl, 116, 1)
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
    createStyledCheckbox(18, -252, 180, L["제작템 포함"], "crafting", L["전문기술로 만드는 장비를 포함합니다."])
    createStyledCheckbox(232, -252, 180, L["퀘스트 보상"], "quests", L["퀘스트 보상을 포함합니다. (완료 여부와 상관없이 표시)"])
    createStyledCheckbox(18, -278, 180, L["월드 드랍 (저확률)"], "auction", L["던전이 아닌 월드의 여러 잡몹이 아주 낮은 확률로 떨어뜨리는 아이템을 포함합니다."])
    createStyledCheckbox(232, -278, 180, L["신규 아이템 포함 (출처 불명)"], "newItems", L["1.12 DB에 없는 Forever 신규 장비를 게임에서 직접 찾아 포함합니다. 어디서 나오는지는 알 수 없습니다."])

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
        ns.UIKit:FitFontString(qtVal, 108, 1)
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
    ns.UIKit:FitFontString(alphaLbl, 96, 1)
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
    ns.UIKit:FitFontString(chanceLbl, 112, 2)
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
        ns.UIKit:FitFontString(langBtn.label, 182, 1)
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
        local code = ns.GetActiveLocale and ns.GetActiveLocale() or "koKR"
        desc:SetText(panelText(code, "내 직업과 레벨에서 착용할 수 있는 추천 장비와 획득처(던전·제작·퀘스트)를 딜·탱·힐 역할별로 비교합니다.", "Finds the best gear for your class and level with drop, craft, and quest sources across DPS, Tank, and Healer roles.", { "Findet die beste Ausrüstung für deine Klasse und Stufe samt Quelle (Beute, Herstellung, Quest) und vergleicht Schaden, Tank und Heiler.", "Trouve le meilleur équipement pour votre classe et votre niveau, avec sa source (butin, artisanat, quête), en comparant DPS, tank et soigneur.", "Encuentra el mejor equipo para tu clase y nivel, con su origen (botín, fabricación, misión), comparando DPS, tanque y sanador.", "Подбирает лучшую экипировку для вашего класса и уровня с источником (добыча, ремесло, задание) и сравнивает роли бойца, танка и лекаря.", "为你的职业和等级找出最佳装备及其来源（掉落、制造、任务），并比较输出、坦克和治疗。", "為你的職業和等級找出最佳裝備及其來源（掉落、製造、任務），並比較輸出、坦克和治療。" }))
        launchBtn:SetText(panelText(code, "설정", "Settings", { "Einstellungen", "Options", "Opciones", "Настройки", "设置", "設定" }) .. " (/ezbg)")
        hint:SetText(panelText(code, "채팅창에 /ezbg 또는 /ezbg config를 입력해도 열립니다.", "Type /ezbg or /ezbg config in chat to open settings.", { "Du kannst die Einstellungen auch mit /ezbg oder /ezbg config im Chat öffnen.", "Vous pouvez aussi ouvrir les options en tapant /ezbg ou /ezbg config dans le chat.", "También puedes abrir las opciones escribiendo /ezbg o /ezbg config en el chat.", "Настройки также открываются командой /ezbg или /ezbg config в чате.", "也可以在聊天框输入 /ezbg 或 /ezbg config 打开设置。", "也可以在聊天框輸入 /ezbg 或 /ezbg config 開啟設定。" }))
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
