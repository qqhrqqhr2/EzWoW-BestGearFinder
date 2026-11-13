--===========================================================================
-- EzWoW - Best Gear Finder
-- Modules/LiveLearner.lua : Live Loot, Quest & Merchant Source Learner
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local LiveLootLearner = ns.LiveLootLearner or {}
ns.LiveLootLearner = LiveLootLearner
local L = ns.L

local resolveItemInfoInstantC = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

function LiveLootLearner.safeCoerceConcat(val)
    return val .. ""
end

function LiveLootLearner.safeMatchItemID(linkStr)
    return tonumber(linkStr:match("item:(%d+)"))
end

function LiveLootLearner.safeMatchNpcGUID(guidStr)
    return tonumber(guidStr:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
end

function LiveLootLearner.unwrapNonSecretValue(v)
    if issecretvalue and issecretvalue(v) then return nil end
    local resolvedValue = type(v)
    if resolvedValue == "string" or resolvedValue == "number" then
        local isCallOk = pcall(LiveLootLearner.safeCoerceConcat, v)
        if isCallOk then return v end
    end
    return nil
end

function LiveLootLearner.resolveItemID(link)
    link = LiveLootLearner.unwrapNonSecretValue(link)
    if not link then return nil end
    local isCallOk, entityID = pcall(LiveLootLearner.safeMatchItemID, link)
    return isCallOk and entityID or nil
end

function LiveLootLearner.hasGear(entityID)
    local isCallOk, _, _, _, localeTbl = pcall(resolveItemInfoInstantC, entityID)
    localeTbl = isCallOk and LiveLootLearner.unwrapNonSecretValue(localeTbl) or nil
    return localeTbl and ns.EQUIP_LOCS and ns.EQUIP_LOCS[localeTbl] and true or false
end

function LiveLootLearner.resolvePlayerLocationContext()
    local displayName, itype = GetInstanceInfo()
    displayName, itype = LiveLootLearner.unwrapNonSecretValue(displayName), LiveLootLearner.unwrapNonSecretValue(itype)
    if displayName and itype and itype ~= "none" then return displayName end
    return LiveLootLearner.unwrapNonSecretValue(GetRealZoneText and GetRealZoneText()) or LiveLootLearner.unwrapNonSecretValue(GetZoneText and GetZoneText()) or "?"
end

local guidNames = {}
function LiveLootLearner.recordDiscoveredEntry(unit)
    local greenVal = LiveLootLearner.unwrapNonSecretValue(UnitGUID(unit))
    local nodeEntry = LiveLootLearner.unwrapNonSecretValue(UnitName(unit))
    if greenVal and nodeEntry then guidNames[greenVal] = nodeEntry end
end

function LiveLootLearner.resolveNpcID(guid)
    if not guid then return nil end
    local isCallOk, entityID = pcall(LiveLootLearner.safeMatchNpcGUID, guid)
    return isCallOk and entityID or nil
end

-- Poor-quality (grey) items are junk: never learn sources for them.
-- Quality comes from the item API; if the item is not cached yet, the link's grey colour code decides.
local POOR_QUALITY = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
function LiveLootLearner.isJunkItem(entityID, link)
    local quality
    if C_Item and C_Item.GetItemQualityByID then
        local isCallOk, q = pcall(C_Item.GetItemQualityByID, entityID)
        quality = isCallOk and LiveLootLearner.unwrapNonSecretValue(q) or nil
    end
    if quality == nil then
        local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if type(getInfo) == "function" then
            local isCallOk, _, _, q = pcall(getInfo, entityID)
            quality = isCallOk and LiveLootLearner.unwrapNonSecretValue(q) or nil
        end
    end
    if type(quality) == "number" then return quality == POOR_QUALITY end
    link = LiveLootLearner.unwrapNonSecretValue(link)
    return type(link) == "string" and link:lower():find("|cff9d9d9d", 1, true) ~= nil
end

function LiveLootLearner.isItemTrackedForLearning(entityID, link)
    return LiveLootLearner.hasGear(entityID) and not LiveLootLearner.isJunkItem(entityID, link)
end

-- Chat lines printed during combat can taint the chat history: notices that come in
-- combat (looting mid-fight) are printed when it ends.
local pendingNotices = {}
function LiveLootLearner.printLearnedSourceNotice(entityID, link)
    if ns.db and ns.db.learnNotify and link then
        local text = "|cffF1BD57EzWoW - Best Gear Finder|r: " .. L["획득처를 기록했습니다: "] .. link
        if InCombatLockdown and InCombatLockdown() then
            if #pendingNotices < 10 then pendingNotices[#pendingNotices + 1] = text end
        else
            print(text)
        end
    end
end

function LiveLootLearner.flushLearnedNotices()
    if InCombatLockdown and InCombatLockdown() then return end
    local list = pendingNotices
    pendingNotices = {}
    for _, text in ipairs(list) do print(text) end
end

-- Only items with no known source are learned. Loot seen before the source index is built waits for it.
local pendingLearn, pendingCount = {}, 0
local indexBuildScheduled = false
-- Index still idle (login timer fell in combat, rescan with the window closed): build it out of combat.
function LiveLootLearner.scheduleIndexBuild()
    if indexBuildScheduled or ns.indexState ~= "idle" or not ns.db or ns.db.learn == false or not C_Timer then return end
    if InCombatLockdown and InCombatLockdown() then return end
    indexBuildScheduled = true
    C_Timer.After(1, function()
        indexBuildScheduled = false
        if ns.indexState == "idle" and not (InCombatLockdown and InCombatLockdown()) then ns:EnsureIndex() end
    end)
end

function LiveLootLearner.learnOrQueue(entityID, kind, entry, link)
    local known = ns:HasKnownSource(entityID)
    if known == nil then
        if ns.indexState ~= "empty" and pendingCount < 200 then
            pendingCount = pendingCount + 1
            pendingLearn[pendingCount] = { entityID, kind, entry, link }
            LiveLootLearner.scheduleIndexBuild()
        end
        return
    end
    if known == false and ns:LearnSource(entityID, kind, entry) and kind ~= "vendors" then
        LiveLootLearner.printLearnedSourceNotice(entityID, link)
    end
end

function LiveLootLearner.flushPendingLearn()
    if ns.indexState ~= "done" or pendingCount == 0 then return end
    local list = pendingLearn
    pendingLearn, pendingCount = {}, 0
    if not ns.db or ns.db.learn == false then return end
    for _, p in ipairs(list) do LiveLootLearner.learnOrQueue(p[1], p[2], p[3], p[4]) end
end

function LiveLootLearner.hasPendingLearn() return pendingCount > 0 end
ns.FlushPendingLearn = LiveLootLearner.flushPendingLearn

function LiveLootLearner.handleChatLootMessage()
    local nodeEntry = GetNumLootItems and GetNumLootItems() or 0
    local where = LiveLootLearner.resolvePlayerLocationContext()
    for slot = 1, nodeEntry do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        local entityID = LiveLootLearner.resolveItemID(link)
        if entityID and LiveLootLearner.isItemTrackedForLearning(entityID, link) then
            local boss, npc = nil, nil
            local srcs = { pcall(GetLootSourceInfo, slot) }
            if srcs[1] then
                local greenVal = LiveLootLearner.unwrapNonSecretValue(srcs[2])
                if greenVal then
                    if greenVal:find("^GameObject") then
                        boss = L["상자"]
                    else
                        npc = LiveLootLearner.resolveNpcID(greenVal)
                        boss = guidNames[greenVal]
                    end
                end
            end
            if not boss then
                local tnVal = LiveLootLearner.unwrapNonSecretValue(UnitName("target"))
                if tnVal and UnitIsDead and UnitIsDead("target") then boss = tnVal end
            end
            LiveLootLearner.learnOrQueue(entityID, "drops", { inst = where, boss = boss or L["몹"], npc = npc }, link)
        end
    end
end

function LiveLootLearner.onQuestComplete()
    local questIDVal = LiveLootLearner.unwrapNonSecretValue(GetQuestID and GetQuestID())
    local titleStr = LiveLootLearner.unwrapNonSecretValue(GetTitleText and GetTitleText())
    if not questIDVal or not titleStr then return end
    local function scanActiveTargetAndLoot(kind, count)
        for index = 1, count or 0 do
            local link = GetQuestItemLink and GetQuestItemLink(kind, index)
            local entityID = LiveLootLearner.resolveItemID(link)
            if entityID and LiveLootLearner.isItemTrackedForLearning(entityID, link) then
                LiveLootLearner.learnOrQueue(entityID, "quests", { qid = questIDVal, title = titleStr, lvl = 0 }, link)
            end
        end
    end
    scanActiveTargetAndLoot("choice", GetNumQuestChoices and GetNumQuestChoices())
    scanActiveTargetAndLoot("reward", GetNumQuestRewards and GetNumQuestRewards())
end

function LiveLootLearner.onMerchant()
    local displayName = LiveLootLearner.unwrapNonSecretValue(UnitName("npc"))
    if not displayName then return end
    local greenVal = LiveLootLearner.unwrapNonSecretValue(UnitGUID("npc"))
    local npc = greenVal and LiveLootLearner.resolveNpcID(greenVal)
    local zone = LiveLootLearner.resolvePlayerLocationContext()
    for index = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
        local link = GetMerchantItemLink and GetMerchantItemLink(index)
        local entityID = LiveLootLearner.resolveItemID(link)
        if entityID and LiveLootLearner.isItemTrackedForLearning(entityID, link) then
            LiveLootLearner.learnOrQueue(entityID, "vendors", { zone = zone, boss = displayName, npc = npc }, link)
        end
    end
end

local windowFrame = CreateFrame("Frame")
for _, eventFrame in ipairs({ "LOOT_OPENED", "QUEST_COMPLETE", "MERCHANT_SHOW", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_REGEN_ENABLED" }) do
    pcall(windowFrame.RegisterEvent, windowFrame, eventFrame)
end
windowFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        pcall(LiveLootLearner.flushLearnedNotices)
        -- index not started (login or rescan in combat): build it now so queued loot is checked
        if LiveLootLearner.hasPendingLearn() then LiveLootLearner.scheduleIndexBuild() end
        return
    end
    if not ns.db or ns.db.learn == false then return end
    pcall(function()
        if event == "LOOT_OPENED" then LiveLootLearner.handleChatLootMessage()
        elseif event == "QUEST_COMPLETE" then LiveLootLearner.onQuestComplete()
        elseif event == "MERCHANT_SHOW" then LiveLootLearner.onMerchant()
        elseif event == "PLAYER_TARGET_CHANGED" then LiveLootLearner.recordDiscoveredEntry("target")
        elseif event == "UPDATE_MOUSEOVER_UNIT" then LiveLootLearner.recordDiscoveredEntry("mouseover") end
    end)
end)

-- Remove sources that were learned for grey (junk) items before junk was excluded.
-- Items whose quality is not known yet are requested and checked again when their data arrives.
local pendingJunkCheck = {}
function LiveLootLearner.pruneJunkEntry(entityID)
    local learned = ns.db and ns.db.learned
    if not learned then return end
    local quality
    if C_Item and C_Item.GetItemQualityByID then
        local isCallOk, q = pcall(C_Item.GetItemQualityByID, entityID)
        quality = isCallOk and LiveLootLearner.unwrapNonSecretValue(q) or nil
    end
    if type(quality) ~= "number" then
        pendingJunkCheck[entityID] = true
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, entityID) end
        return
    end
    pendingJunkCheck[entityID] = nil
    if quality ~= POOR_QUALITY then return end
    for _, kind in ipairs({ "drops", "quests", "vendors" }) do
        if learned[kind] then learned[kind][entityID] = nil end
    end
end

function LiveLootLearner.pruneLearnedJunk()
    local learned = ns.db and ns.db.learned
    if not learned then return end
    local ids = {}
    for _, kind in ipairs({ "drops", "quests", "vendors" }) do
        for entityID in pairs(learned[kind] or {}) do
            if type(entityID) == "number" then ids[entityID] = true end
        end
    end
    for entityID in pairs(ids) do LiveLootLearner.pruneJunkEntry(entityID) end
end

local pruneFrame = CreateFrame("Frame")
pcall(pruneFrame.RegisterEvent, pruneFrame, "PLAYER_ENTERING_WORLD")
pcall(pruneFrame.RegisterEvent, pruneFrame, "GET_ITEM_INFO_RECEIVED")
pruneFrame:SetScript("OnEvent", function(self, event, itemID)
    if event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if C_Timer and C_Timer.After then
            C_Timer.After(5, function() pcall(LiveLootLearner.pruneLearnedJunk) end)
        else
            pcall(LiveLootLearner.pruneLearnedJunk)
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        itemID = LiveLootLearner.unwrapNonSecretValue(itemID)
        if itemID and pendingJunkCheck[itemID] then pcall(LiveLootLearner.pruneJunkEntry, itemID) end
    end
end)

function ns:LearnedCount()
    local nodeEntry = 0
    for _, kind in ipairs({ "drops", "quests", "vendors" }) do
        for _ in pairs(ns.db and ns.db.learned and ns.db.learned[kind] or {}) do nodeEntry = nodeEntry + 1 end
    end
    return nodeEntry
end

local exportFrame
function ns:ShowLearnedExport()
    local lineList = {}
    local payloadData = ns.db and ns.db.learned or {}
    for _, kind in ipairs({ "drops", "quests", "vendors" }) do
        local ids = {}
        for entityID in pairs(payloadData[kind] or {}) do ids[#ids + 1] = entityID end
        table.sort(ids)
        for _, entityID in ipairs(ids) do
            for _, recordEntry in ipairs(payloadData[kind][entityID]) do
                if kind == "quests" then
                    lineList[#lineList + 1] = string.format("%s\t%d\t%s\t%s", kind, entityID, tostring(recordEntry.qid), tostring(recordEntry.title))
                else
                    lineList[#lineList + 1] = string.format("%s\t%d\t%s\t%s\t%s", kind, entityID, tostring(recordEntry.inst or recordEntry.zone), tostring(recordEntry.boss), tostring(recordEntry.npc or ""))
                end
            end
        end
    end
    if not exportFrame then
        local windowFrame = CreateFrame("Frame", "EzWoWBestGearFinderExport", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        windowFrame:SetSize(560, 360)
        windowFrame:SetPoint("CENTER")
        ns.UIKit:ElevateModal(windowFrame, 250)
        if ns.ApplyWindowTheme then ns.ApplyWindowTheme(windowFrame) end
        if ns.ApplySolidBackdrop then ns.ApplySolidBackdrop(windowFrame) end
        windowFrame:EnableMouse(true); windowFrame:SetMovable(true); windowFrame:RegisterForDrag("LeftButton")
        windowFrame:SetScript("OnDragStart", windowFrame.StartMoving); windowFrame:SetScript("OnDragStop", windowFrame.StopMovingOrSizing)
        local resolvedValue = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        resolvedValue:SetPoint("TOPLEFT", 20, -18)
        resolvedValue:SetTextColor(0.945, 0.741, 0.341)
        resolvedValue:SetText(L["기록한 획득처 (Ctrl+A, Ctrl+C로 복사)"])
        local close = ns.CreateStyledButton and ns.CreateStyledButton(windowFrame, 22, 22, "X", false, function() windowFrame:Hide() end) or CreateFrame("Button", nil, windowFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -10, -10)
        local sfVal = CreateFrame("ScrollFrame", "EzWoWBestGearFinderExportScroll", windowFrame, "UIPanelScrollFrameTemplate")
        sfVal:SetPoint("TOPLEFT", 20, -44); sfVal:SetPoint("BOTTOMRIGHT", -36, 20)
        local inputBox = CreateFrame("EditBox", nil, sfVal)
        inputBox:SetMultiLine(true); inputBox:SetAutoFocus(true); inputBox:SetFontObject(ChatFontNormal); inputBox:SetWidth(490)
        inputBox:SetScript("OnEscapePressed", function() windowFrame:Hide() end)
        sfVal:SetScrollChild(inputBox)
        windowFrame.eb = inputBox
        tinsert(UISpecialFrames, "EzWoWBestGearFinderExport")
        exportFrame = windowFrame
    end
    exportFrame.eb:SetText(#lineList > 0 and table.concat(lineList, "\n") or L["아직 기록한 획득처가 없습니다."])
    exportFrame.eb:HighlightText()
    ns.UIKit:ElevateModal(exportFrame, 250)
    exportFrame:Show()
    if exportFrame.Raise then exportFrame:Raise() end
end
