--===========================================================================
-- EzWoW - Best Gear Finder
-- UI/SearchWindow.lua : Interactive Item Catalog Browser & Filter Tree
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local CatalogSearchWindow = ns.CatalogSearchWindow or {}
ns.CatalogSearchWindow = CatalogSearchWindow
local L = ns.L

local widgetHelper, headerFrameRef = 780, 640
local ROW_H, MAX_ROWS = 40, 150
local windowFrame, listChild, countText, noteText, nameBox, minBox, maxBox, mineChk
local rowWidgets = {}
local resolveCatMatch
local filter = { text = "", noReq = true, q = {}, src = {}, mine = false, cat = nil, catKey = nil }

function CatalogSearchWindow.commitDefaults()
    filter.text, filter.mine, filter.noReq = "", false, true
    filter.cat, filter.catKey = nil, nil
    for _, set in ipairs({ filter.q, filter.src }) do wipe(set) end
    filter.q[2], filter.q[3] = true, true
    for _, entryKey in ipairs({ "drop", "quest", "craft", "vendor", "unknown" }) do filter.src[entryKey] = true end
end
CatalogSearchWindow.commitDefaults()
local timer, polling = nil, false
local token = 0
local running = false
local lastPending, lastChange = -1, 0
local syncQueued = false
local searchEpoch, searchCo = 0, nil
local resolved = {}
local searchSteps = 0
function CatalogSearchWindow.searchYield()
    searchSteps = searchSteps + 1
    if searchSteps >= 250 then
        searchSteps = 0
        if debugprofilestop() - ns.searchBudgetStart >= 10 then coroutine.yield() end
    end
end
local searchBtn, qualChecks, noReqChk = nil, {}, nil
local statusBar
local expanded = {}   

local ARMOR_KINDS = { { 4, 1 }, { 4, 2 }, { 4, 3 }, { 4, 4 }, { 4, 6 }, { 4, 0 }, { 4, 7 }, { 4, 8 }, { 4, 9 } }
local WEAPON_KINDS = { { 2, 0 }, { 2, 1 }, { 2, 4 }, { 2, 5 }, { 2, 7 }, { 2, 8 }, { 2, 15 }, { 2, 13 }, { 2, 6 }, { 2, 10 },
                       { 2, 2 }, { 2, 18 }, { 2, 3 }, { 2, 16 }, { 2, 19 }, { 2, 14 }, { 2, 20 } }
local FALLBACK = {
    ["4:0"] = "장신구/목걸이/반지/기타", ["4:1"] = "천", ["4:2"] = "가죽", ["4:3"] = "사슬", ["4:4"] = "판금", ["4:6"] = "방패",
    ["4:7"] = "성서", ["4:8"] = "우상", ["4:9"] = "토템",
    ["2:0"] = "한손 도끼", ["2:1"] = "양손 도끼", ["2:2"] = "활", ["2:3"] = "총", ["2:4"] = "한손 둔기", ["2:5"] = "양손 둔기",
    ["2:6"] = "장창", ["2:7"] = "한손 검", ["2:8"] = "양손 검", ["2:10"] = "지팡이", ["2:13"] = "격투 무기", ["2:15"] = "단검",
    ["2:16"] = "투척 무기", ["2:18"] = "석궁", ["2:19"] = "마법봉", ["2:14"] = "기타 무기", ["2:20"] = "낚싯대",
}

local EN_KIND = {
    ["4:1"] = "Cloth", ["4:2"] = "Leather", ["4:3"] = "Mail", ["4:4"] = "Plate", ["4:6"] = "Shields",
    ["4:7"] = "Librams", ["4:8"] = "Idols", ["4:9"] = "Totems",
    ["2:0"] = "One-Handed Axes", ["2:1"] = "Two-Handed Axes", ["2:2"] = "Bows", ["2:3"] = "Guns",
    ["2:4"] = "One-Handed Maces", ["2:5"] = "Two-Handed Maces", ["2:6"] = "Polearms", ["2:7"] = "One-Handed Swords",
    ["2:8"] = "Two-Handed Swords", ["2:10"] = "Staves", ["2:13"] = "Fist Weapons", ["2:14"] = "Miscellaneous",
    ["2:15"] = "Daggers", ["2:16"] = "Thrown", ["2:18"] = "Crossbows", ["2:19"] = "Wands", ["2:20"] = "Fishing Poles",
}
local QUAL_KEYS = { [1] = "일반", [2] = "고급", [3] = "희귀", [4] = "영웅", [5] = "전설" }

function CatalogSearchWindow.useAddonLocale()
    local active = ns.GetActiveLocale and ns.GetActiveLocale()
    local clientLoc = GetLocale and GetLocale()
    return active and clientLoc and active ~= clientLoc
end

function CatalogSearchWindow.resolveKindName(cID, sID)
    local lookupKey = cID .. ":" .. sID
    if cID == 4 and sID == 0 then return L["장신구/목걸이/반지/기타"] end
    if CatalogSearchWindow.useAddonLocale() and FALLBACK[lookupKey] then
        return L[FALLBACK[lookupKey]]
    end
    local resolveCallback = GetItemSubClassInfo or (C_Item and C_Item.GetItemSubClassInfo)
    if resolveCallback then
        local isCallOk, nodeEntry = pcall(resolveCallback, cID, sID)
        if isCallOk and type(nodeEntry) == "string" and nodeEntry ~= "" then return nodeEntry end
    end
    return L[FALLBACK[lookupKey] or lookupKey]
end

function CatalogSearchWindow.resolveQualityName(q)
    local nodeEntry
    if CatalogSearchWindow.useAddonLocale() and QUAL_KEYS[q] then
        nodeEntry = L[QUAL_KEYS[q]]
    else
        nodeEntry = _G["ITEM_QUALITY" .. q .. "_DESC"] or (QUAL_KEYS[q] and L[QUAL_KEYS[q]])
    end
    local columnIndex = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if type(nodeEntry) ~= "string" then nodeEntry = tostring(q) end
    if columnIndex and type(columnIndex.hex) == "string" then return columnIndex.hex .. nodeEntry .. "|r" end
    return nodeEntry
end

local locToGroup = {}
for _, greenVal in ipairs(ns.GROUPS) do
    for localeTbl in pairs(greenVal.locs) do locToGroup[localeTbl] = greenVal.key end
end

-----------------------------------------------------------------------------
-- Resolve Item Hyperlink
-----------------------------------------------------------------------------
function CatalogSearchWindow.resolveItemHyperlink(row, data)
    row.data = data
end

function CatalogSearchWindow.resolveRow(i)
    local rowEntry = rowWidgets[i]
    if rowEntry then return rowEntry end
    rowEntry = CreateFrame("Button", nil, listChild)
    rowEntry:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    rowEntry:SetHeight(ROW_H)
    rowEntry:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    rowEntry:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
    rowEntry:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    rowEntry.icon = rowEntry:CreateTexture(nil, "ARTWORK")
    local backdropTex = rowEntry:CreateTexture(nil, "BACKGROUND")
    backdropTex:SetPoint("TOPLEFT", 0, 0); backdropTex:SetPoint("BOTTOMRIGHT", 0, 2)
    backdropTex:SetColorTexture(0.114, 0.157, 0.192, 0.95)
    rowEntry.icon:SetSize(28, 28)
    rowEntry.icon:SetPoint("TOPLEFT", 8, -5)
    rowEntry.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    rowEntry.name = rowEntry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rowEntry.name:SetPoint("TOPLEFT", rowEntry.icon, "TOPRIGHT", 8, 0)
    rowEntry.name:SetPoint("TOPRIGHT", rowEntry, "TOPRIGHT", -126, -5)
    rowEntry.name:SetJustifyH("LEFT")
    rowEntry.name:SetWordWrap(false)
    rowEntry.info = rowEntry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rowEntry.info:SetPoint("TOPRIGHT", -8, -5)
    rowEntry.info:SetWidth(114)
    rowEntry.info:SetJustifyH("RIGHT")
    rowEntry.info:SetWordWrap(false)
    rowEntry.src = rowEntry:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rowEntry.src:SetPoint("TOPLEFT", rowEntry.name, "BOTTOMLEFT", 0, -5)
    rowEntry.src:SetPoint("TOPRIGHT", rowEntry.info, "BOTTOMRIGHT", 0, -5)
    rowEntry.src:SetJustifyH("LEFT")
    rowEntry.src:SetWordWrap(false)
    rowEntry:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        if _G.SlashCmdList and _G.SlashCmdList.EZWOWMAPFINDER then
            GameTooltip:AddLine(" ")
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
        if IsShiftKeyDown() and ChatEdit_InsertLink then ChatEdit_InsertLink(self.link)
        elseif IsControlKeyDown() and DressUpItemLink then DressUpItemLink(self.link) end
    end)
    rowWidgets[i] = rowEntry
    return rowEntry
end

-----------------------------------------------------------------------------
-- Group Node
-----------------------------------------------------------------------------
function CatalogSearchWindow.groupNode(lookupKey)
    for _, greenVal in ipairs(ns.GROUPS) do
        if greenVal.key == lookupKey then return { label = greenVal.label, locs = greenVal.locs } end
    end
    return { label = lookupKey }
end
function CatalogSearchWindow.withBase(node, c, s)
    node.c, node.s = c, s
    return node
end
local TREE
function CatalogSearchWindow.constructCategoryFilterTree()
    local weapon = { label = L["무기"], c = 2, children = {} }
    for _, entryKey in ipairs(WEAPON_KINDS) do
        weapon.children[#weapon.children + 1] = { label = CatalogSearchWindow.resolveKindName(entryKey[1], entryKey[2]), c = entryKey[1], s = entryKey[2] }
    end
    local armor = { label = L["방어구"], c = 4, ss = { [1] = true, [2] = true, [3] = true, [4] = true }, children = {} }
    local slotKeys = { "HEAD", "SHOULDER", "CHEST", "WRIST", "HAND", "WAIST", "LEGS", "FEET" }
    for _, spellIDVal in ipairs({ 1, 2, 3, 4 }) do
        local nodeEntry = { label = CatalogSearchWindow.resolveKindName(4, spellIDVal), c = 4, s = spellIDVal, children = {} }
        for _, lookupKey in ipairs(slotKeys) do nodeEntry.children[#nodeEntry.children + 1] = CatalogSearchWindow.withBase(CatalogSearchWindow.groupNode(lookupKey), 4, spellIDVal) end
        armor.children[#armor.children + 1] = nodeEntry
    end
    armor.children[#armor.children + 1] = CatalogSearchWindow.withBase(CatalogSearchWindow.groupNode("CLOAK"), 4, nil)   
    local top = { weapon, armor, { label = CatalogSearchWindow.resolveKindName(4, 6), c = 4, s = 6 } }
    for _, spellIDVal in ipairs({ 7, 8, 9 }) do
        top[#top + 1] = { label = CatalogSearchWindow.resolveKindName(4, spellIDVal), c = 4, s = spellIDVal }
    end
    for _, lookupKey in ipairs({ "NECK", "FINGER", "TRINKET" }) do
        top[#top + 1] = CatalogSearchWindow.withBase(CatalogSearchWindow.groupNode(lookupKey), 4, nil)   
    end
    top[#top + 1] = { label = L["보조 장비"], c = 4, locs = { INVTYPE_HOLDABLE = true } }
    return top
end

resolveCatMatch = function(node, rec)
    if node.c and rec.classID ~= node.c then return false end
    if node.s and rec.subID ~= node.s then return false end
    if node.ss and not node.ss[rec.subID] then return false end
    if node.locs and not node.locs[rec.loc] then return false end
    return true
end

function CatalogSearchWindow.resolveSrcMatch(rec, set)
    if next(set) == nil then return true end
    for lookupKey in pairs(set) do
        if lookupKey == "unknown" then
            if rec.kinds.unknown or next(rec.kinds) == nil then return true end
        elseif rec.kinds[lookupKey] then
            return true
        end
    end
    return false
end

function CatalogSearchWindow.containsQuality() return next(filter.q) ~= nil end
function CatalogSearchWindow.containsFilter(minL, maxL)
    return filter.text ~= "" or CatalogSearchWindow.containsQuality() or filter.cat or next(filter.src) or filter.mine or minL or maxL
end
function CatalogSearchWindow.assignRunning(v)
    running = v
    ns.fastLoad = v        
    if not v and statusBar then statusBar:Hide() end
    if searchBtn then searchBtn:SetText(v and L["중지"] or L["검색"]) end
end

local runCatalogSearchTick
function CatalogSearchWindow.scheduleNextSearchTick(delay)
    token = token + 1
    local myVal = token
    timer = true
    C_Timer.After(delay or 0.3, function()
        if myVal ~= token then return end
        timer = nil
        runCatalogSearchTick()
    end)
end

function CatalogSearchWindow.executeCatalogSearchBatch()
    if not windowFrame or not windowFrame:IsShown() or not running then return end
    if ns.indexState == "empty" then
        noteText:SetText(L["검색 결과가 없습니다."])
        CatalogSearchWindow.assignRunning(false)
        return
    end
    if ns.indexState ~= "done" and not ns.indexBaseReady then
        ns:EnsureIndex()
        countText:SetText("")
        noteText:SetText(L["아이템 정보를 불러오는 중입니다..."])
        CatalogSearchWindow.scheduleNextSearchTick(1)
        return
    end
    local minL, maxL = tonumber(minBox:GetText()), tonumber(maxBox:GetText())
    if not CatalogSearchWindow.containsFilter(minL, maxL) then
        countText:SetText("")
        noteText:SetText(L["조건을 고르면 해당하는 아이템이 모두 표시됩니다."])
        CatalogSearchWindow.assignRunning(false)
        return
    end
    local extractSafeTooltipText = filter.text
    local pending, results, cand, waitingQueue, unavailable = 0, {}, 0, false, 0
    for entityID, rec in pairs(ns.index) do
        if rec then
            local isCallOk = true
            if filter.cat and not resolveCatMatch(filter.cat, rec) then isCallOk = false end
            if isCallOk and not CatalogSearchWindow.resolveSrcMatch(rec, filter.src) then isCallOk = false end
            if isCallOk and filter.mine and not ns:IsItemUsableByActiveClass(rec) then isCallOk = false end
            if isCallOk then
                cand = cand + 1
                local cached = resolved[entityID]
                if cached ~= nil then
                    if cached then results[#results + 1] = cached end
                else
                local displayName, link, quality, ilvl, req, _, _, _, _, iconTex = ns:GetCachedItemInfo(entityID)
                if not displayName then
                    if ns:RequestItem(entityID) then
                        pending = pending + 1
                        if ns:IsItemQueued(entityID) then waitingQueue = true end
                    else
                        unavailable = unavailable + 1
                    end
                else
                    local good = true
                    if CatalogSearchWindow.containsQuality() and not filter.q[quality or 0] then good = false end
                    if good and filter.mine and not ns:IsItemUsableByActiveClass(rec, entityID) then good = false end
                    if good and not (filter.noReq and (req or 0) == 0) then
                        if minL and (req or 0) < minL then good = false end
                        if good and maxL and (req or 0) > maxL then good = false end
                    end
                    if good and extractSafeTooltipText ~= "" then
                        local hit = string.find(string.lower(displayName), extractSafeTooltipText, 1, true)
                        if not hit then
                            for _, s in ipairs(rec.src) do
                                if string.find(string.lower((s.boss or "") .. " " .. (s.inst or "")), extractSafeTooltipText, 1, true) then hit = true; break end
                            end
                        end
                        good = hit and true or false
                    end
                    resolved[entityID] = false
                    if good then
                        local result = { id = entityID, rec = rec, name = displayName, link = link, quality = quality or 1,
                                         ilvl = ilvl or 0, req = req or 0, icon = iconTex or rec.icon }
                        resolved[entityID] = result
                        results[#results + 1] = result
                    end
                end
                end
            end
        end
        CatalogSearchWindow.searchYield()
    end
    for _, rowEntry in ipairs(rowWidgets) do rowEntry:Hide() end
    table.sort(results, function(a, b)
        if a.req ~= b.req then return a.req > b.req end
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
        return a.id < b.id
    end)
    local grandTotal = #results
    for i = 1, math.min(grandTotal, MAX_ROWS) do
        local dataEntry = results[i]
        local rowEntry = CatalogSearchWindow.resolveRow(i)
        rowEntry.id = dataEntry.id
        rowEntry.rec = dataEntry.rec
        rowEntry.link = dataEntry.link
        rowEntry.icon:SetTexture(dataEntry.icon)
        local columnIndex = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[dataEntry.quality]
        rowEntry.name:SetText(((columnIndex and type(columnIndex.hex) == "string" and columnIndex.hex) or "|cffffffff") .. dataEntry.name .. "|r")
        rowEntry.info:SetText(format("%s %d · ilvl %d", L["요구"], dataEntry.req, dataEntry.ilvl))
        rowEntry.src:SetText(CatalogSearchWindow.resolveKindName(dataEntry.rec.classID, dataEntry.rec.subID) .. " · " .. (ns.FormatCompactDropSource and ns:FormatCompactDropSource(dataEntry.rec, dataEntry.id) or ""))
        rowEntry:Show()
    end
    listChild:SetHeight(math.max(1, math.min(grandTotal, MAX_ROWS) * ROW_H))
    if grandTotal > MAX_ROWS then
        countText:SetText(format(L["%d개 중 %d개 표시"], grandTotal, MAX_ROWS))
    else
        countText:SetText(format(L["%d개"], grandTotal))
    end
    noteText:SetText(pending > 0 and format(L["%d개 불러오는 중..."], pending) or (grandTotal == 0 and L["검색 결과가 없습니다."] or ""))
    if pending == 0 and ns.indexState == "running" then
        noteText:SetText(L["기존 결과 표시 중 · 신규 아이템 탐색 중..."])
    elseif pending == 0 and unavailable > 0 then
        noteText:SetText(format(L["%d개는 불러오지 못해 제외했습니다"], unavailable))
    end
    
    if statusBar then
        if pending > 0 and cand > 0 then
            statusBar:SetValue((cand - pending - unavailable) / cand)
            statusBar:Show()
        else
            statusBar:Hide()
        end
    end
    
    local currentTime = GetTime()
    if pending ~= lastPending then lastChange = currentTime end
    lastPending = pending
    if ns.indexState == "running" or (pending > 0 and (waitingQueue or currentTime - lastChange < 35)) then
        CatalogSearchWindow.scheduleNextSearchTick(0.25)         
    else
        if pending > 0 then noteText:SetText(format(L["%d개는 불러오지 못해 제외했습니다"], pending)) end
        CatalogSearchWindow.assignRunning(false)      
    end
end

function runCatalogSearchTick()
    if searchCo or not running or not windowFrame or not windowFrame:IsShown() then return end
    local epoch = searchEpoch
    local coVal = coroutine.create(CatalogSearchWindow.executeCatalogSearchBatch)
    searchCo = coVal
    local function executeSingleSearchStep()
        if epoch ~= searchEpoch or not running or not windowFrame:IsShown() then
            if searchCo == coVal then searchCo = nil end
            return
        end
        ns.searchBudgetStart = debugprofilestop()
        local isCallOk, errorObj = coroutine.resume(coVal)
        if not isCallOk then
            searchCo = nil
            CatalogSearchWindow.assignRunning(false)
            noteText:SetText(L["검색 중 오류가 발생했습니다. /ezbg 진단을 확인하세요."])
            ns.Print(L["데이터 읽기 오류: "] .. tostring(errorObj))
        elseif coroutine.status(coVal) == "dead" then
            searchCo = nil
        else
            C_Timer.After(0, executeSingleSearchStep)
        end
    end
    executeSingleSearchStep()
end

function CatalogSearchWindow.startSearch()
    if not windowFrame then return end
    searchEpoch = searchEpoch + 1
    searchCo = nil
    ns:CancelSearchRequests()
    wipe(resolved)
    token = token + 1
    timer = nil
    lastPending, lastChange = -1, GetTime()
    CatalogSearchWindow.assignRunning(true)
    CatalogSearchWindow.scheduleNextSearchTick(0.01)
end
function CatalogSearchWindow.stopSearch()
    searchEpoch = searchEpoch + 1
    searchCo = nil
    ns:CancelSearchRequests()
    token = token + 1          
    CatalogSearchWindow.assignRunning(false)
    if noteText then
        local resolvedValue = noteText:GetText() or ""
        noteText:SetText(resolvedValue:find("%.%.%.") and L["중지됨"] or resolvedValue)
    end
end

function ns.HandleItemInfoReceived(entityID, success)
    
    if entityID then resolved[entityID] = nil end
    if running and not syncQueued and not searchCo then
        syncQueued = true
        C_Timer.After(0.15, function()
            syncQueued = false
            if running then runCatalogSearchTick() end
        end)
    end
end

-----------------------------------------------------------------------------
-- Construct Main Frame
-----------------------------------------------------------------------------
function CatalogSearchWindow.constructMainFrame()
    windowFrame = CreateFrame("Frame", "EzWoWBestGearFinderSearchFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    windowFrame:SetSize(widgetHelper, headerFrameRef)
    windowFrame:SetPoint("CENTER", 60, 0)
    windowFrame:SetFrameStrata("DIALOG")
    windowFrame:SetClampedToScreen(true)
    windowFrame:SetMovable(true)
    windowFrame:EnableMouse(true)
    windowFrame:RegisterForDrag("LeftButton")
    if ns.ApplyWindowTheme then ns.ApplyWindowTheme(windowFrame) end
    if ns.ApplySolidBackdrop then ns.ApplySolidBackdrop(windowFrame) end
    local function commitAlpha(a)
        a = math.max(0.3, math.min(1, a or 0.92))
        if windowFrame.solidBG then windowFrame.solidBG:SetAlpha(a) end
        if windowFrame.SetBackdropColor then windowFrame.SetBackdropColor(windowFrame, 0.071, 0.094, 0.122, a) end
        if windowFrame.SetBackdropBorderColor then windowFrame.SetBackdropBorderColor(windowFrame, 0.204, 0.298, 0.357, math.min(1, a + 0.2)) end
    end
    commitAlpha(ns.db and ns.db.searchAlpha or 0.92)
    windowFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    windowFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    windowFrame:Hide()
    tinsert(UISpecialFrames, "EzWoWBestGearFinderSearchFrame")

    local titleStr = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleStr:SetPoint("TOPLEFT", 20, -18)
    titleStr:SetTextColor(0.945, 0.741, 0.341)
    titleStr:SetText(L["아이템 검색"])
    local close = ns.CreateStyledButton(windowFrame, 22, 22, "X", false, function() windowFrame:Hide() end)
    close:SetPoint("TOPRIGHT", -12, -14)

    local slVal = CreateFrame("Slider", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    slVal:SetOrientation("HORIZONTAL")
    slVal:SetPoint("TOPRIGHT", -70, -24)
    slVal:SetSize(110, 12)
    if slVal.SetBackdrop then
        ns.UIKit:ApplyBackdrop(slVal, 1, 1)
        slVal:SetBackdropColor(0.047, 0.067, 0.086, 0.96)
        slVal:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
    end
    slVal:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slVal:SetMinMaxValues(0.3, 1)
    slVal:SetValueStep(0.05)
    if slVal.SetObeyStepOnDrag then slVal:SetObeyStepOnDrag(true) end
    local slLabel = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slLabel:SetPoint("RIGHT", slVal, "LEFT", -8, 0)
    slLabel:SetText(L["투명도"])
    slVal:SetValue(ns.db and ns.db.searchAlpha or 0.85)
    slVal:SetScript("OnValueChanged", function(_, v)
        if ns.db then ns.db.searchAlpha = v end
        commitAlpha(v)
    end)

    local nlVal = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nlVal:SetPoint("TOPLEFT", 22, -52)
    nlVal:SetText(L["이름/보스"])
    nameBox = ns.CreateStyledEditBox and ns.CreateStyledEditBox(windowFrame, 168, 20) or CreateFrame("EditBox", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    nameBox:SetSize(168, 20)
    nameBox:SetPoint("LEFT", nlVal, "RIGHT", 8, 0)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(40)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); CatalogSearchWindow.startSearch() end)
    
    local nameHint = nameBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    nameHint:SetPoint("LEFT", nameBox, "LEFT", 6, 0)
    nameHint:SetText(L["선택 입력 · 비워 두면 전체"])
    local function refreshHint()
        local empty = (nameBox:GetText() or "") == ""
        nameHint:SetShown(empty and not nameBox:HasFocus())
    end
    nameBox:SetScript("OnTextChanged", function(self)
        filter.text = string.lower((self:GetText() or ""):match("^%s*(.-)%s*$"))
        refreshHint()
        if windowFrame:IsShown() and minBox and maxBox then CatalogSearchWindow.startSearch() end
    end)
    nameBox:HookScript("OnEditFocusGained", function() nameHint:Hide() end)
    nameBox:HookScript("OnEditFocusLost", refreshHint)

    local llVal = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    llVal:SetPoint("LEFT", nameBox, "RIGHT", 12, 0)
    llVal:SetText(L["요구 레벨"])
    local function resolveLevelEdit(anchor, dx)
        local recordEntry = ns.CreateStyledEditBox and ns.CreateStyledEditBox(windowFrame, 36, 20) or CreateFrame("EditBox", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        recordEntry:SetSize(36, 20)
        recordEntry:SetPoint("LEFT", anchor, "RIGHT", dx, 0)
        recordEntry:SetTextInsets(2, 2, 0, 0)
        recordEntry:SetAutoFocus(false)
        recordEntry:SetNumeric(true)
        recordEntry:SetMaxLetters(2)
        recordEntry:SetJustifyH("CENTER")
        recordEntry:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        recordEntry:SetScript("OnEnterPressed", function(self) self:ClearFocus(); CatalogSearchWindow.startSearch() end)
        recordEntry:SetScript("OnTextChanged", function()
            if windowFrame:IsShown() and minBox and maxBox then CatalogSearchWindow.startSearch() end
        end)
        return recordEntry
    end
    minBox = resolveLevelEdit(llVal, 12)
    local tlVal = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tlVal:SetPoint("LEFT", minBox, "RIGHT", 4, 0)
    tlVal:SetText("~")
    maxBox = resolveLevelEdit(tlVal, 4)
    noReqChk = CreateFrame("CheckButton", nil, windowFrame, "UICheckButtonTemplate")
    noReqChk:SetSize(22, 22)
    noReqChk:SetPoint("LEFT", maxBox, "RIGHT", 6, 0)
    local nrl = noReqChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nrl:SetPoint("LEFT", noReqChk, "RIGHT", 2, 0)
    nrl:SetWidth(185)
    nrl:SetJustifyH("LEFT")
    if nrl.SetWordWrap then nrl:SetWordWrap(false) end
    nrl:SetText(L["레벨 제한 없음 포함"])
    noReqChk:SetChecked(filter.noReq)
    noReqChk:SetScript("OnClick", function(self) filter.noReq = self:GetChecked() and true or false; CatalogSearchWindow.startSearch() end)

    local verifyLists = {}
    local coordY = -80
    local CELL = 112
    local function constructChecks(titleStr, entries, set)
        local txVal = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txVal:SetPoint("TOPLEFT", 22, coordY - 5)
        txVal:SetText(titleStr)
        for entryIndex, recordEntry in ipairs(entries) do
            local checkWidget = CreateFrame("CheckButton", nil, windowFrame, "UICheckButtonTemplate")
            checkWidget:SetSize(22, 22)
            checkWidget:SetPoint("TOPLEFT", 78 + (entryIndex - 1) * CELL, coordY)
            checkWidget.label = checkWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            checkWidget.label:SetPoint("LEFT", checkWidget, "RIGHT", 2, 0)
            checkWidget.label:SetWidth(CELL - 26)
            checkWidget.label:SetJustifyH("LEFT")
            if checkWidget.label.SetWordWrap then checkWidget.label:SetWordWrap(false) end
            checkWidget.label:SetText(recordEntry.label)
            checkWidget:SetChecked(set[recordEntry.key] and true or false)
            checkWidget:SetScript("OnClick", function(self) set[recordEntry.key] = self:GetChecked() and true or nil; CatalogSearchWindow.startSearch() end)
            verifyLists[#verifyLists + 1] = { cb = checkWidget, set = set, key = recordEntry.key }
        end
        coordY = coordY - 26
    end
    local qEntries = {}
    for q = 1, 5 do qEntries[#qEntries + 1] = { key = q, label = CatalogSearchWindow.resolveQualityName(q) } end
    constructChecks(L["등급"], qEntries, filter.q)
    constructChecks(L["획득처"], {
        { key = "drop", label = L["드랍"] }, { key = "quest", label = L["퀘스트"] }, { key = "craft", label = L["제작"] },
        { key = "vendor", label = L["상점"] }, { key = "unknown", label = L["출처 불명"] },
    }, filter.src)

    mineChk = CreateFrame("CheckButton", nil, windowFrame, "UICheckButtonTemplate")
    mineChk:SetPoint("TOPLEFT", 16, coordY - 2)
    mineChk:SetSize(24, 24)
    local mlVal = mineChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mlVal:SetPoint("LEFT", mineChk, "RIGHT", 2, 0)
    mlVal:SetText(L["착용 가능한 아이템만"])
    mineChk:SetChecked(filter.mine)
    mineChk:SetScript("OnClick", function(self) filter.mine = self:GetChecked() and true or false; CatalogSearchWindow.startSearch() end)

    searchBtn = ns.CreateStyledButton(windowFrame, 80, 22, L["검색"], true, function()
        if running then CatalogSearchWindow.stopSearch() else CatalogSearchWindow.startSearch() end
    end)
    searchBtn:SetPoint("TOPRIGHT", -108, coordY - 2)

    local treeRefresh
    local reset = ns.CreateStyledButton(windowFrame, 80, 22, L["초기화"], false, function()
        CatalogSearchWindow.stopSearch()
        CatalogSearchWindow.commitDefaults()
        nameBox:SetText(""); ns.SearchDefaultRange(); mineChk:SetChecked(false); noReqChk:SetChecked(true)
        for _, c in ipairs(verifyLists) do c.cb:SetChecked(c.set[c.key] and true or false) end
        treeRefresh()
    end)
    reset:SetPoint("TOPRIGHT", -24, coordY - 2)
    coordY = coordY - 32

    countText = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("TOPLEFT", 22, coordY)
    noteText = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    noteText:SetPoint("LEFT", countText, "RIGHT", 10, 0)
    statusBar = CreateFrame("StatusBar", nil, windowFrame)
    statusBar:SetPoint("TOPRIGHT", -36, coordY + 5)
    statusBar:SetSize(260, 10)
    statusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    statusBar:SetStatusBarColor(0.945, 0.741, 0.341)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0)
    local bbg = statusBar:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(0, 0, 0, 0.6)
    statusBar:Hide()
    coordY = coordY - 18

    local hint = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 22, 16)
    hint:SetText(L["Shift+클릭: 채팅창에 링크 / Ctrl+클릭: 미리보기"])

    local TREE_W = 190
    local tscroll = CreateFrame("ScrollFrame", "EzWoWBestGearFinderSearchTree", windowFrame, "UIPanelScrollFrameTemplate")
    tscroll:SetPoint("TOPLEFT", 18, coordY)
    tscroll:SetPoint("BOTTOMLEFT", 18, 34)
    tscroll:SetWidth(TREE_W)
    local tchild = CreateFrame("Frame", nil, tscroll)
    tchild:SetSize(TREE_W - 4, 1)
    tscroll:SetScrollChild(tchild)
    if ns.ConfigureScrollWheelStep then ns.ConfigureScrollWheelStep(tscroll, 40) end
    TREE = CatalogSearchWindow.constructCategoryFilterTree()
    
    if filter.catKey then
        local itemList, node = TREE, nil
        for entryIndex in filter.catKey:gmatch("/(%d+)") do
            node = itemList and itemList[tonumber(entryIndex)]
            itemList = node and node.children
        end
        filter.cat = node
    end
    local trows = {}
    local flat

    local function flattenCategoryTreeNodes(itemList, depth, prefix, out)
        for i, nodeEntry in ipairs(itemList) do
            local lookupKey = prefix .. "/" .. i
            out[#out + 1] = { node = nodeEntry, depth = depth, key = lookupKey }
            if nodeEntry.children and expanded[lookupKey] then flattenCategoryTreeNodes(nodeEntry.children, depth + 1, lookupKey, out) end
        end
    end
    function treeRefresh()
        flat = { { node = nil, depth = 0, key = "all", label = L["전체"] } }
        flattenCategoryTreeNodes(TREE, 0, "", flat)
        for i, windowFrameEntry in ipairs(flat) do
            local b = trows[i]
            if not b then
                b = CreateFrame("Button", nil, tchild)
                b:SetHeight(20)
                b:SetPoint("TOPLEFT", 0, -(i - 1) * 20)
                b:SetPoint("TOPRIGHT", 0, -(i - 1) * 20)
                b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                b.sel = b:CreateTexture(nil, "BACKGROUND")
                b.sel:SetAllPoints()
                b.sel:SetColorTexture(0.945, 0.741, 0.341, 0.28)
                b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                b.t:SetJustifyH("LEFT")
                b.t:SetWordWrap(false)
                trows[i] = b
            end
            b.t:ClearAllPoints()
            b.t:SetPoint("LEFT", 4 + windowFrameEntry.depth * 12, 0)
            b.t:SetPoint("RIGHT", -2, 0)
            local nodeEntry = windowFrameEntry.node
            local formatLocalizedLabel = windowFrameEntry.label or nodeEntry.label
            if nodeEntry and nodeEntry.children then formatLocalizedLabel = (expanded[windowFrameEntry.key] and "- " or "+ ") .. formatLocalizedLabel end
            b.t:SetText(formatLocalizedLabel)
            b.sel:SetShown(filter.cat == nodeEntry)
            b:SetScript("OnClick", function()
                if nodeEntry and nodeEntry.children then expanded[windowFrameEntry.key] = not expanded[windowFrameEntry.key] end
                filter.cat, filter.catKey = nodeEntry, (nodeEntry and windowFrameEntry.key or nil)
                treeRefresh()
                CatalogSearchWindow.startSearch()
            end)
            b:Show()
        end
        for i = #flat + 1, #trows do trows[i]:Hide() end
        tchild:SetHeight(math.max(1, #flat * 20))
    end
    treeRefresh()

    local scrollFrame = CreateFrame("ScrollFrame", "EzWoWBestGearFinderSearchScroll", windowFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 18 + TREE_W + 26, coordY)
    scrollFrame:SetPoint("BOTTOMRIGHT", -36, 34)
    listChild = CreateFrame("Frame", nil, scrollFrame)
    listChild:SetSize(widgetHelper - TREE_W - 90, 1)
    scrollFrame:SetScrollChild(listChild)
    if ns.ConfigureScrollWheelStep then ns.ConfigureScrollWheelStep(scrollFrame, ROW_H * 1.5) end

    local function resolveDefaultRange()
        local loVal, hiVal = ns:GetLevelFilterRange()
        minBox:SetText(tostring(loVal)); maxBox:SetText(tostring(hiVal))
    end
    ns.SearchDefaultRange = resolveDefaultRange
    resolveDefaultRange()
    windowFrame:SetScript("OnHide", function() CatalogSearchWindow.stopSearch() end)
end

function ns:RebuildCatalogSearchWindow()
    if not windowFrame then return end
    local wasShown = windowFrame:IsShown()
    local nameT, minT, maxT = nameBox:GetText(), minBox:GetText(), maxBox:GetText()
    CatalogSearchWindow.stopSearch()
    windowFrame:Hide()
    windowFrame:ClearAllPoints()
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == "EzWoWBestGearFinderSearchFrame" then table.remove(UISpecialFrames, i) end
    end
    wipe(rowWidgets)
    windowFrame, listChild, countText, noteText, nameBox, minBox, maxBox, mineChk, searchBtn, noReqChk, statusBar = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
    CatalogSearchWindow.constructMainFrame()
    nameBox:SetText(nameT or ""); minBox:SetText(minT or ""); maxBox:SetText(maxT or "")
    if wasShown then windowFrame:Show() end
end

function ns:ToggleCatalogSearchWindow()
    if not windowFrame then CatalogSearchWindow.constructMainFrame() end
    if windowFrame:IsShown() then windowFrame:Hide() else windowFrame:Show(); CatalogSearchWindow.startSearch() end
end

function ns:SearchFor(extractSafeTooltipText)
    if not windowFrame then CatalogSearchWindow.constructMainFrame() end
    windowFrame:Show()
    nameBox:SetText(extractSafeTooltipText or "")
    filter.text = string.lower((extractSafeTooltipText or ""):match("^%s*(.-)%s*$"))
    CatalogSearchWindow.startSearch()
end

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
CatalogSearchWindow.HandleItemInfoReceived = ns.HandleItemInfoReceived
CatalogSearchWindow.RebuildCatalogSearchWindow = ns.RebuildCatalogSearchWindow
CatalogSearchWindow.ToggleCatalogSearchWindow = ns.ToggleCatalogSearchWindow
