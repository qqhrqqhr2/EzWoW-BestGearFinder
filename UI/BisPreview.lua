--===========================================================================
-- EzWoW - Best Gear Finder
-- UI/BisPreview.lua : "Try on BiS" window - the character window's layout
-- with the BiS of each slot, the player's model wearing them and the stats
-- that change against the gear worn now
--===========================================================================
-- The places come from the last weighing of the slots (ns.rankedLists, made by
-- EvaluateAllSlotCandidates in Core/Init.lua). A slot button picks another place
-- (2nd, 3rd ... or the item worn now) when the BiS can't be had.
local ADDON, ns = ...
local L = ns.L

local BisPreview = {}
ns.BisPreview = BisPreview

local WIDTH, HEIGHT = 790, 592
local SLOT, GAP = 40, 6
local LEFT_X = 16
local MODEL_X, MODEL_W, MODEL_H = LEFT_X + SLOT + 10, 290, 372
local RIGHT_X = MODEL_X + MODEL_W + 10
local STATS_X = RIGHT_X + SLOT + 64
local TOP = -84
local NONE = "none"   -- an empty off hand next to a two-hand weapon

-- character window layout: inventory slot -> slot group (MAIN = one-hand or two-hand)
local LEFT = {
    { inv = 1, group = "HEAD", slotName = "HeadSlot" }, { inv = 2, group = "NECK", slotName = "NeckSlot" },
    { inv = 3, group = "SHOULDER", slotName = "ShoulderSlot" }, { inv = 15, group = "CLOAK", slotName = "BackSlot" },
    { inv = 5, group = "CHEST", slotName = "ChestSlot" }, { inv = 9, group = "WRIST", slotName = "WristSlot" },
}
local RIGHT = {
    { inv = 10, group = "HAND", slotName = "HandsSlot" }, { inv = 6, group = "WAIST", slotName = "WaistSlot" },
    { inv = 7, group = "LEGS", slotName = "LegsSlot" }, { inv = 8, group = "FEET", slotName = "FeetSlot" },
    { inv = 11, group = "FINGER", slotName = "Finger0Slot" }, { inv = 12, group = "FINGER", slotName = "Finger1Slot" },
    { inv = 13, group = "TRINKET", slotName = "Trinket0Slot" }, { inv = 14, group = "TRINKET", slotName = "Trinket1Slot" },
}
local BOTTOM = {
    { inv = 16, group = "MAIN", slotName = "MainHandSlot" }, { inv = 17, group = "OFF", slotName = "SecondaryHandSlot" },
    { inv = 18, group = "RANGED", slotName = "RangedSlot" },
}
local ALL = {}
for _, list in ipairs({ LEFT, RIGHT, BOTTOM }) do for _, info in ipairs(list) do ALL[#ALL + 1] = info end end

local frame, model, menu, specTabs, statLines, noteText, scoreText
local slotButtons = {}
local state = { si = nil, sel = {}, custom = false }

local function groupByKey(key)
    for _, g in ipairs(ns.GROUPS or {}) do if g.key == key then return g end end
end

local function ranked(si, key)
    local lists = ns.rankedLists and ns.rankedLists[si]
    return lists and lists[key] or {}
end

-- the item worn in an inventory slot, as a list entry
local function wornEntry(inv)
    if ns.viewClass then return nil end
    local link = GetInventoryItemLink("player", inv)
    if not link then return nil end
    local name, _, quality, ilvl = ns.GetItemInfoC(link)
    return { id = GetInventoryItemID("player", inv), link = link, quality = quality, ilvl = ilvl or 0, worn = true, name = name }
end

local function entryLoc(entry)
    if not entry or entry == NONE or not entry.link then return nil end
    local ok, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, entry.link)
    return ok and loc or nil
end

-- the slot group an item is weighed in, for one inventory slot
local function groupForSlot(info, entry)
    if info.group == "MAIN" then
        return groupByKey(entryLoc(entry) == "INVTYPE_2HWEAPON" and "MAIN2H" or "MAIN1H")
    end
    return groupByKey(info.group)
end

-- the first entry of a list that isn't one of the ids given
local function firstOther(list, ...)
    local skip = {}
    for i = 1, select("#", ...) do local id = select(i, ...); if id then skip[id] = true end end
    for _, entry in ipairs(list) do if not skip[entry.id] then return entry end end
end

-- the BiS set of a spec: each slot's 1st place (rings and trinkets the 1st and 2nd, the worn
-- ones kept in their slots), the weapons as the better of two-hand or one-hand + off hand
function BisPreview.defaultSet(si)
    local sel = {}
    for _, info in ipairs(ALL) do
        if info.group ~= "MAIN" and info.group ~= "OFF" and info.group ~= "FINGER" and info.group ~= "TRINKET" then
            sel[info.inv] = ranked(si, info.group)[1] or wornEntry(info.inv)
        end
    end
    for _, pair in ipairs({ { "FINGER", 11, 12 }, { "TRINKET", 13, 14 } }) do
        local key, slotA, slotB = pair[1], pair[2], pair[3]
        local list = ranked(si, key)
        local best = { list[1], list[2] }
        local wornA, wornB = GetInventoryItemID("player", slotA), GetInventoryItemID("player", slotB)
        local free = {}
        for _, entry in ipairs(best) do
            if entry.id == wornA and not sel[slotA] then sel[slotA] = entry
            elseif entry.id == wornB and not sel[slotB] then sel[slotB] = entry
            else free[#free + 1] = entry end
        end
        for _, slot in ipairs({ slotA, slotB }) do
            if not sel[slot] then sel[slot] = table.remove(free, 1) or wornEntry(slot) end
        end
    end
    local twoHand = ranked(si, "MAIN2H")[1]
    local oneHand = ranked(si, "MAIN1H")[1]
    local offHand = firstOther(ranked(si, "OFF"), oneHand and oneHand.id)
    local pairScore = (oneHand and oneHand.score or 0) + (offHand and offHand.score or 0)
    if twoHand and twoHand.score >= pairScore then
        sel[16], sel[17] = twoHand, NONE
    else
        sel[16] = oneHand or wornEntry(16)
        sel[17] = offHand or wornEntry(17)
    end
    return sel
end

function BisPreview.currentSet()
    local sel = {}
    for _, info in ipairs(ALL) do sel[info.inv] = wornEntry(info.inv) end
    if sel[16] and entryLoc(sel[16]) == "INVTYPE_2HWEAPON" and not sel[17] then sel[17] = NONE end
    return sel
end

-----------------------------------------------------------------------------
-- Stats that change
-----------------------------------------------------------------------------
local K = ns.StatWeights.KEYS
local CR = ns.StatWeights.CR
-- stats listed: key, label when the game has no name for it, rating -> percent
local STAT_ROWS = {
    { key = K.STR, label = "힘" }, { key = K.AGI, label = "민첩성" }, { key = K.STA, label = "체력" },
    { key = K.INT, label = "지능" }, { key = K.SPI, label = "정신력" },
    { key = K.AP, label = "전투력" }, { key = K.RAP, label = "원거리 전투력" }, { key = K.FAP, label = "야성 전투력" },
    { key = K.SP, label = "주문력" }, { key = K.HEAL, label = "치유량" }, { key = K.SDMG, label = "주문력" },
    { key = K.MP5, label = "5초당 마나 회복" },
    { key = K.HIT, label = "적중도", cr = CR.HIT_MELEE }, { key = K.CRIT, label = "치명타", cr = CR.CRIT_MELEE },
    { key = K.HASTE, label = "가속", cr = CR.HASTE_MELEE }, { key = K.EXP, label = "숙련도", cr = CR.EXPERTISE },
    { key = K.PIERCE, label = "주문 관통력" },
    { key = K.SHADOW, label = "암흑 주문력" }, { key = K.FIRE, label = "화염 주문력" }, { key = K.FROST, label = "냉기 주문력" },
    { key = K.ARCANE, label = "비전 주문력" }, { key = K.NATURE, label = "자연 주문력" }, { key = K.HOLY, label = "신성 주문력" },
    { key = K.DEF, label = "방어 숙련도" }, { key = K.DODGE, label = "회피", cr = CR.DODGE }, { key = K.PARRY, label = "무기 막기", cr = CR.PARRY },
    { key = K.BLOCKR, label = "방패 막기", cr = CR.BLOCK }, { key = K.BLOCKV, label = "방패 피해 방어량" },
    { key = K.ARMOR, label = "방어도" },
}

local function statLabel(row)
    return ns.StatWeights.Label(row.key, row.label)
end

local function statsOf(entry)
    if not entry or entry == NONE or not entry.link then return {} end
    local stats = ns.GetStats and ns.GetStats(entry.link)
    return type(stats) == "table" and stats or {}
end

-- changes against the worn gear: { [stat key] = amount }, main-hand / ranged DPS, score change
function BisPreview.changes(si, sel)
    local spec = ns:GetSpecList()[si]
    local diff, score = {}, 0
    local dpsMain, dpsRanged = 0, 0
    local current = BisPreview.currentSet()
    for _, info in ipairs(ALL) do
        local new, old = sel[info.inv], current[info.inv]
        if new == NONE then new = nil end
        if old == NONE then old = nil end
        local same = (new and old and new.id == old.id) or (not new and not old)
        if not same then
            local newStats, oldStats = statsOf(new), statsOf(old)
            for key, amount in pairs(newStats) do
                if type(amount) == "number" then diff[key] = (diff[key] or 0) + amount end
            end
            for key, amount in pairs(oldStats) do
                if type(amount) == "number" then diff[key] = (diff[key] or 0) - amount end
            end
            if info.inv == 16 then dpsMain = (newStats[K.DPS] or 0) - (oldStats[K.DPS] or 0) end
            if info.inv == 18 then dpsRanged = (newStats[K.DPS] or 0) - (oldStats[K.DPS] or 0) end
            if spec then
                local engine = ns.GearScoringEngine
                local newScore = new and engine.evaluateItemRoleScore(new.link, new.ilvl, ns.StatWeights.For(si, spec, groupForSlot(info, new))) or 0
                local oldScore = old and engine.evaluateItemRoleScore(old.link, old.ilvl, ns.StatWeights.For(si, spec, groupForSlot(info, old))) or 0
                score = score + newScore - oldScore
            end
        end
    end
    return diff, dpsMain, dpsRanged, score
end

-----------------------------------------------------------------------------
-- Window
-----------------------------------------------------------------------------
local function qualityColor(quality)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    if c then return c.r, c.g, c.b end
    return 0.6, 0.6, 0.6
end

local function emptyIcon(info)
    local ok, _, texture = pcall(GetInventorySlotInfo, info.slotName)
    if ok and texture then return texture end
    return "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
end

local function tagFor(entry)
    if not entry or entry == NONE then return "" end
    if entry.worn and not entry.rank then return "|cff4bc8e8" .. L["착용"] .. "|r" end
    if entry.bis == 2 then return "|cffffcf68BiS|r" end
    if entry.rank then return "|cff9baabd" .. format(L["%d위"], entry.rank) .. "|r" end
    return ""
end

function BisPreview.refreshSlots()
    for _, info in ipairs(ALL) do
        local button = slotButtons[info.inv]
        local entry = state.sel[info.inv]
        if entry == NONE then
            button.icon:SetTexture(emptyIcon(info))
            button.icon:SetDesaturated(true)
            button:SetBackdropBorderColor(0.25, 0.3, 0.35, 1)
            button.tag:SetText("")
        elseif entry then
            local icon = entry.rec and entry.rec.icon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.id))
            button.icon:SetTexture(icon or emptyIcon(info))
            button.icon:SetDesaturated(false)
            button:SetBackdropBorderColor(qualityColor(entry.quality))
            -- a place that is the item worn now: "worn" next to the place
            local tag = tagFor(entry)
            local wornNow = GetInventoryItemID("player", info.inv) == entry.id
            if wornNow and entry.rank then tag = tag .. " |cff4bc8e8" .. L["착용"] .. "|r" end
            button.tag:SetText(tag)
        else
            button.icon:SetTexture(emptyIcon(info))
            button.icon:SetDesaturated(true)
            button:SetBackdropBorderColor(0.25, 0.3, 0.35, 1)
            button.tag:SetText("")
        end
    end
end

function BisPreview.dressModel()
    if not model then return end
    pcall(model.SetUnit, model, "player")
    for _, info in ipairs(ALL) do
        local entry = state.sel[info.inv]
        if entry == NONE then
            if model.UndressSlot then pcall(model.UndressSlot, model, info.inv) end
        elseif entry and entry.link and GetInventoryItemID("player", info.inv) ~= entry.id then
            if info.inv == 16 then pcall(model.TryOn, model, entry.link, "MAINHANDSLOT")
            elseif info.inv == 17 then pcall(model.TryOn, model, entry.link, "SECONDARYHANDSLOT")
            else pcall(model.TryOn, model, entry.link) end
        end
    end
end

local function fmtAmount(amount, row)
    if row.cr then
        local pct = amount * ns.StatWeights.PerRating(row.cr)
        return format("%+.1f%%", pct)
    end
    if math.abs(amount - math.floor(amount + 0.5)) < 0.05 then return format("%+d", math.floor(amount + 0.5)) end
    return format("%+.1f", amount)
end

function BisPreview.refreshStats()
    local si = state.si
    local spec = ns:GetSpecList()[si]
    local diff, dpsMain, dpsRanged, score = BisPreview.changes(si, state.sel)
    local weights = spec and ns.StatWeights.For(si, spec, nil) or {}
    local rows = {}
    for order, row in ipairs(STAT_ROWS) do
        local amount = diff[row.key]
        -- healing items also carry spell damage; the healing line says it
        local skip = (row.key == K.SDMG and (diff[K.SP] or diff[K.HEAL]))
        if amount and math.abs(amount) >= 0.5 and not skip then
            local weight = type(weights[row.key]) == "number" and weights[row.key] or 0
            rows[#rows + 1] = { label = statLabel(row), text = fmtAmount(amount, row), up = amount > 0, worth = math.abs(amount) * weight, order = order }
        end
    end
    if math.abs(dpsMain) >= 0.1 then
        rows[#rows + 1] = { label = L["주무기 초당 공격력"], text = format("%+.1f", dpsMain), up = dpsMain > 0, worth = math.abs(dpsMain) * 20, order = 0 }
    end
    if math.abs(dpsRanged) >= 0.1 then
        rows[#rows + 1] = { label = L["원거리 무기 초당 공격력"], text = format("%+.1f", dpsRanged), up = dpsRanged > 0, worth = math.abs(dpsRanged) * 20, order = 0 }
    end
    -- what the spec values most first
    table.sort(rows, function(a, b)
        if a.worth ~= b.worth then return a.worth > b.worth end
        return a.order < b.order
    end)
    scoreText:SetText(format(L["점수 %+.1f"], score) .. "  |cff9baabd(" .. (spec and spec.name or "") .. ")|r")
    if score >= 0 then scoreText:SetTextColor(0.41, 0.85, 0.64) else scoreText:SetTextColor(0.95, 0.45, 0.45) end
    for i, fs in ipairs(statLines) do
        local row = rows[i]
        if row then
            fs.left:SetText(row.label)
            fs.right:SetText(row.text)
            if row.up then fs.right:SetTextColor(0.41, 0.85, 0.64) else fs.right:SetTextColor(0.95, 0.45, 0.45) end
            fs.left:Show(); fs.right:Show()
        else
            fs.left:Hide(); fs.right:Hide()
        end
    end
    if #rows == 0 then
        statLines[1].left:SetText(L["바뀌는 능력치가 없습니다."])
        statLines[1].left:SetTextColor(0.62, 0.68, 0.75)
        statLines[1].left:Show()
    else
        statLines[1].left:SetTextColor(0.93, 0.95, 0.97)
    end
    local note
    if ns.viewClass then note = L["다른 직업 보기: 지금 장비와 비교하지 않습니다."]
    elseif (ns.stats and ns.stats.pending or 0) > 0 then note = L["아이템 정보를 불러오는 중입니다..."]
    else note = L["칸을 누르면 2위·3위나 지금 장비로 바꿀 수 있습니다."] end
    noteText:SetText(note)
end

function BisPreview.refresh()
    if not frame or not frame:IsShown() then return end
    local specs = ns:GetSpecList()
    if not state.si or not specs[state.si] then state.si = (ns.db and ns.db.previewSpec) or 1 end
    if not specs[state.si] then state.si = 1 end
    for i, tab in ipairs(specTabs) do
        local spec = specs[i]
        if spec then
            tab:SetText(spec.name)
            tab:Show()
            tab.sel:SetShown(i == state.si)
        else
            tab:Hide()
        end
    end
    if not state.custom then state.sel = BisPreview.defaultSet(state.si) end
    BisPreview.refreshSlots()
    BisPreview.dressModel()
    BisPreview.refreshStats()
end

-- new places from a weighing of the slots: shown again unless slots were picked by hand
function BisPreview.OnRanksUpdated()
    if frame and frame:IsShown() and not state.custom then BisPreview.refresh() end
end

-----------------------------------------------------------------------------
-- Picking another place for a slot
-----------------------------------------------------------------------------
local function choose(info, entry)
    state.custom = true
    local sel = state.sel
    if info.group == "FINGER" or info.group == "TRINKET" then
        local other = (info.inv == 11 and 12) or (info.inv == 12 and 11) or (info.inv == 13 and 14) or 13
        local otherEntry = sel[other]
        if otherEntry and otherEntry ~= NONE and entry and otherEntry.id == entry.id then sel[other] = sel[info.inv] end
    elseif info.inv == 16 then
        if entryLoc(entry) == "INVTYPE_2HWEAPON" then
            sel[17] = NONE
        elseif sel[17] == NONE then
            sel[17] = firstOther(ranked(state.si, "OFF"), entry and entry.id) or wornEntry(17)
        end
    elseif info.inv == 17 and sel[16] and sel[16] ~= NONE and entryLoc(sel[16]) == "INVTYPE_2HWEAPON" then
        sel[16] = firstOther(ranked(state.si, "MAIN1H"), entry and entry.id) or wornEntry(16)
    end
    sel[info.inv] = entry
    menu:Hide()
    BisPreview.refreshSlots()
    BisPreview.dressModel()
    BisPreview.refreshStats()
end

local menuRows = {}
local function menuRow(i)
    local row = menuRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, menu)
    row:SetSize(330, 24)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row:SetScript("OnEnter", function(self)
        if not self.entry or self.entry == NONE or not self.entry.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.entry.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    menuRows[i] = row
    return row
end

function BisPreview.openMenu(info, button)
    local items = {}
    local function addHeader(text) items[#items + 1] = { header = text } end
    local function addList(list) for _, entry in ipairs(list) do items[#items + 1] = { entry = entry } end end
    if info.group == "MAIN" then
        local twoHand, oneHand = ranked(state.si, "MAIN2H"), ranked(state.si, "MAIN1H")
        if #twoHand > 0 then addHeader(groupByKey("MAIN2H").label); addList(twoHand) end
        if #oneHand > 0 then addHeader(groupByKey("MAIN1H").label); addList(oneHand) end
    else
        addList(ranked(state.si, info.group))
    end
    local worn = wornEntry(info.inv)
    if worn then addHeader(L["지금 장비"]); items[#items + 1] = { entry = worn } end
    local y = -8
    local shown = 0
    for i, item in ipairs(items) do
        local row = menuRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, y)
        if item.header then
            row.entry = nil
            row.icon:Hide()
            row.text:SetText("|cfff1bd57" .. item.header .. "|r")
            row:SetScript("OnClick", nil)
            row:EnableMouse(false)
        else
            local entry = item.entry
            row.entry = entry
            row.icon:Show()
            row.icon:SetTexture(entry.rec and entry.rec.icon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.id)) or 134400)
            local r, g, b = qualityColor(entry.quality)
            local name = entry.name or (entry.link and entry.link:match("%[(.-)%]")) or "?"
            local place = tagFor(entry)
            local scoreText = entry.score and ("  |cff9baabd" .. format(L["점수 %.1f"], entry.score) .. "|r") or ""
            row.text:SetText(format("|cff%02x%02x%02x%s|r  %s%s", r * 255, g * 255, b * 255, name, place, scoreText))
            row:EnableMouse(true)
            row:SetScript("OnClick", function() choose(info, entry) end)
        end
        row:Show()
        y = y - 24
        shown = i
    end
    for i = shown + 1, #menuRows do menuRows[i]:Hide() end
    if shown == 0 then return end
    menu:SetSize(342, -y + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", button, "TOPRIGHT", 4, 0)
    menu:Show()
    menu:Raise()
end

-----------------------------------------------------------------------------
-- Building
-----------------------------------------------------------------------------
local function makeSlot(info, x, y)
    local button = CreateFrame("Button", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    button:SetSize(SLOT, SLOT)
    button:SetPoint("TOPLEFT", x, y)
    if button.SetBackdrop then
        button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        button:SetBackdropColor(0.05, 0.07, 0.09, 0.9)
    end
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.tag = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.tag:SetPoint("TOP", button, "BOTTOM", 0, -1)
    button.tag:SetJustifyH("CENTER")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(self, mouse)
        local entry = state.sel[info.inv]
        if mouse == "RightButton" then
            if entry and entry ~= NONE and entry.id and ns.OpenInMapFinder then ns:OpenInMapFinder(entry.id, entry.rec, entry.link) end
            return
        end
        if menu:IsShown() and menu.owner == self then menu:Hide(); return end
        menu.owner = self
        BisPreview.openMenu(info, self)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local entry = state.sel[info.inv]
        if entry and entry ~= NONE and entry.link then
            GameTooltip:SetHyperlink(entry.link)
        else
            local group = info.group == "MAIN" and groupByKey("MAIN1H") or groupByKey(info.group)
            GameTooltip:AddLine(entry == NONE and L["(양손 무기)"] or (group and group.label or ""), 1, 1, 1)
        end
        GameTooltip:AddLine(L["클릭: 다른 순위 고르기"], 0.294, 0.784, 0.910)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slotButtons[info.inv] = button
end

function BisPreview.build()
    frame = CreateFrame("Frame", "EzWoWBestGearFinderTryOn", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    ns.ApplyWindowTheme(frame)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetColorTexture(0.071, 0.094, 0.122, 1)
    bg:SetPoint("TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    frame:Hide()
    tinsert(UISpecialFrames, "EzWoWBestGearFinderTryOn")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 18, -14)
    title:SetText(L["BiS 착용 보기"])
    local close = ns.CreateStyledButton(frame, 22, 22, "X", false, function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -10, -8)

    -- spec tabs
    specTabs = {}
    for i = 1, 4 do
        local tab = ns.CreateStyledButton(frame, 118, 22, "", false, function()
            state.si, state.custom = i, false
            if ns.db then ns.db.previewSpec = i end
            menu:Hide()
            BisPreview.refresh()
        end)
        tab:SetPoint("TOPLEFT", 16 + (i - 1) * 124, -40)
        tab.sel = tab:CreateTexture(nil, "OVERLAY")
        tab.sel:SetPoint("BOTTOMLEFT", 2, 1)
        tab.sel:SetPoint("BOTTOMRIGHT", -2, 1)
        tab.sel:SetHeight(2)
        tab.sel:SetColorTexture(0.945, 0.741, 0.341, 1)
        specTabs[i] = tab
    end

    -- model in the middle, slots around it like the character window
    model = CreateFrame("DressUpModel", nil, frame)
    model:SetPoint("TOPLEFT", MODEL_X, TOP)
    model:SetSize(MODEL_W, MODEL_H)
    model:EnableMouse(true)
    model:SetScript("OnMouseDown", function(self) self.dragX = GetCursorPosition() end)
    model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    model:SetScript("OnHide", function(self) self.dragX = nil end)
    model:SetScript("OnUpdate", function(self)
        if not self.dragX then return end
        local x = GetCursorPosition()
        self.facing = (self.facing or 0) + (x - self.dragX) * 0.012
        self.dragX = x
        pcall(self.SetFacing, self, self.facing)
    end)
    local modelBg = frame:CreateTexture(nil, "BORDER")
    modelBg:SetPoint("TOPLEFT", model, "TOPLEFT")
    modelBg:SetPoint("BOTTOMRIGHT", model, "BOTTOMRIGHT")
    modelBg:SetColorTexture(0.04, 0.055, 0.07, 0.9)
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", model, "BOTTOM", 0, -4)
    hint:SetText(L["끌어서 돌리기"])

    for i, info in ipairs(LEFT) do makeSlot(info, LEFT_X, TOP - (i - 1) * (SLOT + 22)) end
    for i, info in ipairs(RIGHT) do makeSlot(info, RIGHT_X, TOP - (i - 1) * (SLOT + 6) + 0) end
    local weaponsX = MODEL_X + (MODEL_W - (3 * SLOT + 2 * 16)) / 2
    for i, info in ipairs(BOTTOM) do makeSlot(info, weaponsX + (i - 1) * (SLOT + 16), TOP - MODEL_H - 26) end
    -- the right column has eight slots: tags go beside them there
    for _, info in ipairs(RIGHT) do
        local button = slotButtons[info.inv]
        button.tag:ClearAllPoints()
        button.tag:SetPoint("LEFT", button, "RIGHT", 4, 0)
        button.tag:SetJustifyH("LEFT")
    end

    -- stat changes
    local statsTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statsTitle:SetPoint("TOPLEFT", STATS_X, TOP + 2)
    statsTitle:SetText(L["능력치 변화"])
    local statsSub = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statsSub:SetPoint("TOPLEFT", statsTitle, "BOTTOMLEFT", 0, -4)
    statsSub:SetText(L["지금 장비 → 고른 장비"])
    scoreText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scoreText:SetPoint("TOPLEFT", statsSub, "BOTTOMLEFT", 0, -10)
    statLines = {}
    local statsW = WIDTH - STATS_X - 18
    for i = 1, 16 do
        local left = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        left:SetPoint("TOPLEFT", scoreText, "BOTTOMLEFT", 0, -10 - (i - 1) * 18)
        left:SetWidth(statsW - 70)
        left:SetJustifyH("LEFT")
        left:SetWordWrap(false)
        local right = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        right:SetPoint("TOPRIGHT", scoreText, "BOTTOMLEFT", statsW, -10 - (i - 1) * 18)
        right:SetJustifyH("RIGHT")
        statLines[i] = { left = left, right = right }
    end

    -- bottom: note and buttons
    noteText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    noteText:SetPoint("BOTTOMLEFT", 18, 16)
    noteText:SetJustifyH("LEFT")
    local currentBtn = ns.CreateStyledButton(frame, 96, 22, L["지금 장비"], false, function()
        state.custom = true
        state.sel = BisPreview.currentSet()
        menu:Hide()
        BisPreview.refreshSlots(); BisPreview.dressModel(); BisPreview.refreshStats()
    end)
    currentBtn:SetPoint("BOTTOMRIGHT", -16, 12)
    local bisBtn = ns.CreateStyledButton(frame, 96, 22, L["모두 BiS"], true, function()
        state.custom = false
        menu:Hide()
        BisPreview.refresh()
    end)
    bisBtn:SetPoint("RIGHT", currentBtn, "LEFT", -6, 0)

    -- place list for a slot
    menu = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    ns.ApplyWindowTheme(menu)
    local menuBg = menu:CreateTexture(nil, "BACKGROUND", nil, -8)
    menuBg:SetColorTexture(0.071, 0.094, 0.122, 1)
    menuBg:SetPoint("TOPLEFT", 3, -3)
    menuBg:SetPoint("BOTTOMRIGHT", -3, 3)
    menu:Hide()
    frame:HookScript("OnHide", function() menu:Hide() end)

    frame:SetScript("OnShow", function() BisPreview.refresh() end)
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:SetScript("OnEvent", function()
        if frame:IsShown() then
            if state.custom then BisPreview.refreshSlots(); BisPreview.refreshStats() else BisPreview.refresh() end
        end
    end)
end

-- the places need the slots weighed once: done here when the gear window hasn't been opened
local waitTicker
local function ensureRanks()
    if ns.rankedLists and ns.rankedLists[1] and next(ns.rankedLists[1]) then return true end
    if ns.indexState == "done" then
        pcall(ns.EvaluateAllSlotCandidates, ns)
        return true
    end
    if ns.EnsureIndex then ns:EnsureIndex() end
    if not waitTicker then
        waitTicker = C_Timer.NewTicker(1, function()
            if ns.indexState == "done" then
                waitTicker:Cancel()
                waitTicker = nil
                pcall(ns.EvaluateAllSlotCandidates, ns)
                BisPreview.refresh()
            end
        end, 120)
    end
    return false
end

function ns:ToggleBisPreview()
    if not frame then BisPreview.build() end
    if frame:IsShown() then frame:Hide(); return end
    state.custom = false
    ensureRanks()
    frame:Show()
end
