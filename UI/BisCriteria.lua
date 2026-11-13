--===========================================================================
-- EzWoW - Best Gear Finder
-- UI/BisCriteria.lua : "BiS criteria" window - how the score and BiS are worked out
--===========================================================================
-- Opened by the button next to the sort menu, and once per session when the
-- gear window opens (unless "don't show again" is ticked). The numbers are
-- the weights the window really uses, from Core/StatWeights.lua.
local ADDON, ns = ...
local L = ns.L

local BisCriteria = {}
local popup, dontShow
local shownThisSession = false
local WIDTH = 560
local PER_LINE = 5

local K = ns.StatWeights.KEYS
-- stats listed, in this order when their worth is equal
local SHOW = {
    { key = K.HIT, label = "적중도" }, { key = K.EXP, label = "숙련도" }, { key = K.CRIT, label = "치명타" },
    { key = K.HASTE, label = "가속" }, { key = K.STR, label = "힘" }, { key = K.AGI, label = "민첩성" },
    { key = K.STA, label = "체력" }, { key = K.INT, label = "지능" }, { key = K.SPI, label = "정신력" },
    { key = K.AP, label = "전투력" }, { key = K.RAP, label = "원거리 전투력" }, { key = K.FAP, label = "야성 전투력" },
    { key = K.SP, label = "주문력" }, { key = K.HEAL, label = "치유량" }, { key = K.MP5, label = "5초당 마나 회복" },
    { key = K.PIERCE, label = "주문 관통력" }, { key = K.DEF, label = "방어 숙련도" }, { key = K.DODGE, label = "회피" },
    { key = K.PARRY, label = "무기 막기" }, { key = K.BLOCKR, label = "방패 막기" }, { key = K.BLOCKV, label = "방패 피해 방어량" },
    { key = K.ARMOR, label = "방어도" },
    { key = K.SHADOW, label = "암흑 주문력" }, { key = K.FIRE, label = "화염 주문력" }, { key = K.FROST, label = "냉기 주문력" },
    { key = K.ARCANE, label = "비전 주문력" }, { key = K.NATURE, label = "자연 주문력" }, { key = K.HOLY, label = "신성 주문력" },
}
local UNIT_LABEL = { phys = "전투력 기준", caster = "주문력 기준", heal = "치유량 기준" }

local function fmt(x)
    if x >= 10 then return ("%.0f"):format(x) end
    if x >= 1 then return ("%.1f"):format(x) end
    return ("%.2f"):format(x)
end

local function statLabel(entry)
    local text = _G[entry.key]
    if type(text) == "string" and text ~= "" and not text:find("%%") then return text end
    return L[entry.label]
end

-- "stat worth · stat worth ..." lines (PER_LINE a line) and the worth unit
function BisCriteria.statLines(w, v)
    local unit = (v.role == "heal" and w[K.HEAL]) or (v.role == "caster" and w[K.SP]) or w[K.AP]
    if type(unit) ~= "number" or unit <= 0 then unit = 1 end
    local list = {}
    for order, entry in ipairs(SHOW) do
        local skip = (entry.key == K.SP and v.role == "heal") or (entry.key == K.HEAL and v.role ~= "heal")
            or (entry.key == K.RAP and not v.ranged)
        local value = (type(w[entry.key]) == "number" and w[entry.key] or 0) / unit
        if not skip and value >= 0.05 then list[#list + 1] = { label = statLabel(entry), value = value, order = order } end
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.order < b.order
    end)
    local lines, parts = {}, {}
    for i = 1, math.min(10, #list) do
        parts[#parts + 1] = list[i].label .. " " .. fmt(list[i].value)
        if #parts == PER_LINE then lines[#lines + 1] = table.concat(parts, "  ·  "); parts = {} end
    end
    if #parts > 0 then lines[#lines + 1] = table.concat(parts, "  ·  ") end
    return table.concat(lines, "\n"), unit
end

-- present hit / expertise / defense against their caps (own character only)
function BisCriteria.capLine(info, v)
    if ns.viewClass or type(info) ~= "table" then return nil end
    local floor = math.floor
    local parts = {}
    if v.hit or v.hitOver then parts[#parts + 1] = format(L["적중 %.1f%% / 상한 %d%%"], info.hitPhys, floor(info.capPhys)) end
    if v.spellHit then parts[#parts + 1] = format(L["주문 적중 %.1f%% / 상한 %d%%"], info.hitSpell, floor(info.capSpell)) end
    if v.exp then parts[#parts + 1] = format(L["숙련 %.1f%% / %.1f%%"], info.expertise, 6.5) end
    if v.def and info.defCap ~= math.huge then parts[#parts + 1] = format(L["방어 숙련 %d / %d"], floor(info.defense), floor(info.defCap)) end
    if #parts == 0 then return nil end
    return table.concat(parts, "  ·  ")
end

function BisCriteria.build()
    popup = CreateFrame("Frame", "EzWoWBestGearFinderCriteria", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    popup:SetSize(WIDTH, 300)
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function(self) self:StartMoving() end)
    popup:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    ns.ApplyWindowTheme(popup)
    local bg = popup:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetColorTexture(0.071, 0.094, 0.122, 1)
    bg:SetPoint("TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    popup:Hide()
    tinsert(UISpecialFrames, "EzWoWBestGearFinderCriteria")

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText(L["BiS 기준"])
    local close = ns.CreateStyledButton(popup, 22, 22, "X", false, function() popup:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)

    dontShow = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
    dontShow:SetSize(22, 22)
    dontShow:SetPoint("BOTTOMLEFT", 12, 10)
    local dontLabel = dontShow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dontLabel:SetPoint("LEFT", dontShow, "RIGHT", 2, 0)
    dontLabel:SetText(L["다시 보지 않기"])
    dontShow:SetScript("OnClick", function(self)
        if ns.db then ns.db.bisInfoHidden = self:GetChecked() and true or nil end
    end)
    popup.lines = {}
end

function BisCriteria.refresh()
    local rows = {}
    local function add(text, font, r, g, b, gap)
        if text and text ~= "" then rows[#rows + 1] = { text = text, font = font, r = r, g = g, b = b, gap = gap or 0 } end
    end
    local level = UnitLevel("player") or 60
    add(format(L["레벨 %d 기준"], level), "GameFontNormalSmall", 0.6, 0.8, 1)
    add(L["BiS: 지금 보이는 범위(요구 레벨·획득처 설정)에서 점수 1위"], "GameFontHighlightSmall", 0.93, 0.95, 0.97, 4)
    add(L["반지·장신구는 1·2위가 BiS입니다. 그 아래 순위는 대체품입니다."], "GameFontHighlightSmall", 0.93, 0.95, 0.97)
    if ns.db and ns.db.upgradeOnly then
        add(L["BiS는 늘 보이고, 대체품은 지금 장비보다 좋은 것만 보입니다."], "GameFontHighlightSmall", 0.93, 0.95, 0.97)
    else
        add(L["BiS 아래로 다음 순위를 차례로 보여 줍니다."], "GameFontHighlightSmall", 0.93, 0.95, 0.97)
    end
    add(L["점수: 아이템 능력치마다 아래 '1점의 가치'를 곱해 더한 값"], "GameFontHighlightSmall", 0.93, 0.95, 0.97)
    add(L["가치: 60레벨 기준값을 지금 레벨과 내 전투력·주문력에 맞춘 값"], "GameFontHighlightSmall", 0.93, 0.95, 0.97)
    add(L["적중·숙련·방어 숙련은 상한까지만 높게 칩니다."], "GameFontHighlightSmall", 0.93, 0.95, 0.97)
    local rules = ns.CLASS_RULES and ns.CLASS_RULES[ns:GetActiveClassToken()]
    if rules and rules.relic then
        add(L["성물은 효과를 점수로 셀 수 없어 아이템 레벨 순입니다."], "GameFontHighlightSmall", 0.93, 0.95, 0.97)
    end
    add(L["60레벨 기준값은 추정값이라 실제와 다를 수 있습니다."], "GameFontDisableSmall", 0.62, 0.68, 0.75)
    if ns.viewClass then
        add(L["다른 직업 보기: 적중·전투력은 레벨 평균으로 계산합니다."], "GameFontDisableSmall", 0.62, 0.68, 0.75)
    end
    for si, spec in ipairs(ns:GetSpecList()) do
        local v = spec.v
        if v then
            local w = ns.StatWeights.For(si, spec, nil)
            local statText, unit = BisCriteria.statLines(w, v)
            add((spec.name or "") .. "  |cff9baabd(" .. L[UNIT_LABEL[v.role] or "전투력 기준"] .. ")|r", "GameFontNormal", 0.945, 0.741, 0.341, 10)
            add(statText, "GameFontHighlightSmall", 0.93, 0.95, 0.97, 2)
            add(BisCriteria.capLine(w.__info, v), "GameFontDisableSmall", 0.62, 0.68, 0.75)
            local d = v.dps or {}
            if v.ranged and (d.ranged or 0) > 0 then
                add(format(L["원거리 무기 초당 공격력 1: %s"], fmt(d.ranged / unit)), "GameFontDisableSmall", 0.62, 0.68, 0.75)
            elseif (d.main or 0) > 0 then
                add(format(L["무기 초당 공격력 1: %s"], fmt(d.main / unit)), "GameFontDisableSmall", 0.62, 0.68, 0.75)
            end
        end
    end

    local y = -40
    for i, row in ipairs(rows) do
        local fs = popup.lines[i]
        if not fs then
            fs = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetJustifyH("LEFT")
            fs:SetWidth(WIDTH - 32)
            fs:SetWordWrap(true)
            popup.lines[i] = fs
        end
        fs:SetFontObject(_G[row.font] or GameFontHighlightSmall)
        fs:SetTextColor(row.r, row.g, row.b)
        fs:SetText(row.text)
        y = y - row.gap
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 16, y)
        fs:Show()
        y = y - (fs:GetStringHeight() or 12) - 3
    end
    for i = #rows + 1, #popup.lines do popup.lines[i]:Hide() end
    popup:SetHeight(-y + 44)
    dontShow:SetChecked(ns.db and ns.db.bisInfoHidden and true or false)
end

function BisCriteria.show()
    if not popup then BisCriteria.build() end
    local ok, err = pcall(BisCriteria.refresh)
    if not ok then
        if ns.Print then ns.Print(tostring(err)) end
        return
    end
    -- beside the gear window so the list stays in view (kept on screen when there is no room)
    popup:ClearAllPoints()
    if ns.frame and ns.frame:IsShown() then
        popup:SetPoint("TOPLEFT", ns.frame, "TOPRIGHT", 6, 0)
    else
        popup:SetPoint("CENTER")
    end
    popup:Show()
    popup:Raise()
end

function ns:ToggleBisCriteria()
    if popup and popup:IsShown() then popup:Hide() else BisCriteria.show() end
end
function ns:ShowBisCriteriaOnOpen()
    if shownThisSession or (ns.db and ns.db.bisInfoHidden) then return end
    shownThisSession = true
    BisCriteria.show()
end
function ns:HideBisCriteria()
    if popup then popup:Hide() end
end
ns.BisCriteria = BisCriteria
