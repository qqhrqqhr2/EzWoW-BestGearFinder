--===========================================================================
-- EzWoW - Best Gear Finder
-- Core/Init.lua : Gear Scoring Engine, Source Indexer & Async Item Queue
--===========================================================================
local ADDON, ns = ...

local GearScoringEngine = ns.GearScoringEngine or {}
ns.GearScoringEngine = GearScoringEngine
local L = ns.L
_G.EzWoW_BestGearFinder = ns
_G.EzWoW_BestGearFinder = ns

local DEFAULTS = { bisPriority = false, perSlot = 2, upgradeOnly = true, range = {}, qual = { [2] = true, [3] = true, [4] = true }, allModules = false, crafting = true, quests = true, minChance = 1, auction = true, newItems = true, iconShown = true, scan = {}, mobCut = true, classFilter = true, sourcedOnly = false, collapsed = {}, spec = {}, itemTooltip = true, showEquipCompare = true, learn = true, learnNotify = true }

ns.index = {}          
ns.indexState = "idle" 
ns.indexStats = { bosses = 0, items = 0, modules = 0 }
ns.views = {}          
ns.bands = {}          
ns.stats = { candidates = 0, ready = 0, pending = 0 }

local savedDB
local scoreCache = {}
local requested, queueHi, queue, queueLo = {}, {}, {}, {}
local queueSearch, queued = {}, {}
local queueHiHead, queueHead, queueLoHead, searchHead = 1, 1, 1, 1
function GearScoringEngine.enqueue(id, tier)
    local previousVal = queued[id]
    if previousVal and previousVal <= tier then return end
    queued[id] = tier
    local priorityQueue = tier == 1 and queueSearch or (tier == 2 and queueHi or (tier == 3 and queue or queueLo))
    priorityQueue[#priorityQueue + 1] = id
end
function GearScoringEngine.popQueue(priorityQueue, head, tier)
    while head <= #priorityQueue do
        local id = priorityQueue[head]
        head = head + 1
        if queued[id] == tier then
            queued[id] = nil
            return id, head
        end
    end
    wipe(priorityQueue)
    return nil, 1
end
local attempts, dead = {}, {}  
local qdone = {}   

-----------------------------------------------------------------------------
-- Print Addon Chat Message
-----------------------------------------------------------------------------
local resolveItemInfoInstantC = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local resolveItemInfoC = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local resolveItemStatsC = (C_Item and C_Item.GetItemStats) or GetItemStats
local resolveItemCountC = (C_Item and C_Item.GetItemCount) or GetItemCount

function GearScoringEngine.printAddonChatMessage(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffF1BD57EzWoW - Best Gear Finder|r " .. tostring(msg)) end
ns.Print = GearScoringEngine.printAddonChatMessage

-----------------------------------------------------------------------------
-- Bootstrap Db
-----------------------------------------------------------------------------
function GearScoringEngine.bootstrapDB()
    if type(EzWoW_BestGearFinderDB) ~= "table" then
        if type(EzWoW_BestGearFinderDB) == "table" then
            EzWoW_BestGearFinderDB = EzWoW_BestGearFinderDB
        else
            EzWoW_BestGearFinderDB = {}
        end
    end
    EzWoW_BestGearFinderDB = EzWoW_BestGearFinderDB
    savedDB = EzWoW_BestGearFinderDB
    for entryKey, entryValue in pairs(DEFAULTS) do
        if savedDB[entryKey] == nil then
            if type(entryValue) == "table" then savedDB[entryKey] = {} for kkVal, vvVal in pairs(entryValue) do savedDB[entryKey][kkVal] = vvVal end else savedDB[entryKey] = entryValue end
        end
    end
    if type(savedDB.perSlot) ~= "number" or savedDB.perSlot < 2 then savedDB.perSlot = 2 elseif savedDB.perSlot > 10 then savedDB.perSlot = 10 end
    ns.db = savedDB
    if ns.SetLang then ns.SetLang(savedDB.lang) end
    if ns.RelabelData then ns.RelabelData() end
end

function ns:GetActiveClassToken()
    local _, class = UnitClass("player")
    return ns.viewClass or class
end
function ns:GetActiveClassDisplayName()
    local classToken = ns:GetActiveClassToken()
    if ns.viewClass then
        local resolvedValue = LOCALIZED_CLASS_NAMES_MALE
        return (resolvedValue and resolvedValue[classToken]) or classToken
    end
    return (UnitClass("player"))
end
function ns:GetCharacterProfileKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end

function ns:GetSpecList()
    local class = ns:GetActiveClassToken()
    return ns.SPECS[class] or ns.SPECS.WARRIOR
end

function ns:GetLevelFilterRange()
    local level = UnitLevel("player")
    local rowEntry = savedDB.range[self:GetCharacterProfileKey()]
    if rowEntry and rowEntry.min and rowEntry.max then return rowEntry.min, rowEntry.max, false end
    return math.max(1, level - 10), level, true
end

function ns:SetLevelFilterRange(lo, hi)
    local loVal, hiVal = self:GetLevelFilterRange()
    lo, hi = tonumber(lo) or loVal, tonumber(hi) or hiVal
    lo = math.max(1, math.min(99, math.floor(lo)))
    hi = math.max(1, math.min(99, math.floor(hi)))
    if lo > hi then lo, hi = hi, lo end
    savedDB.range[self:GetCharacterProfileKey()] = { min = lo, max = hi }
    return lo, hi
end

function ns:ResetLevelFilterRange()
    savedDB.range[self:GetCharacterProfileKey()] = nil
end

function GearScoringEngine.resolveArmorType(rules, level)
    local resolvedValue = rules.armor[1][2]
    for _, alphaVal in ipairs(rules.armor) do
        if level >= alphaVal[1] then resolvedValue = alphaVal[2] end
    end
    return resolvedValue
end

-----------------------------------------------------------------------------
-- Maybe Yield
-----------------------------------------------------------------------------

local budgetStart = 0
local yieldSteps = 0
function GearScoringEngine.maybeYield()
    yieldSteps = yieldSteps + 1
    if yieldSteps >= 250 then
        yieldSteps = 0
        if debugprofilestop() - budgetStart > 12 then coroutine.yield() end
    end
end

function GearScoringEngine.addSource(rec, inst, boss, minLvl, kind, skill, extra)
    rec.kinds[kind] = true
    extra = extra or {}
    for _, stateFlag in ipairs(rec.src) do
        if stateFlag.kind == kind then
            if kind == "quest" then
                if stateFlag.qid == extra.qid then return end
            elseif stateFlag.inst == inst and stateFlag.boss == boss and stateFlag.creature == extra.creature and stateFlag.map == extra.map then
                return
            end
        end
    end
    local sourceData = { inst = inst, boss = boss, kind = kind, skill = skill }
    for entryKey, entryValue in pairs(extra) do sourceData[entryKey] = entryValue end
    rec.src[#rec.src + 1] = sourceData
    if kind == "drop" and minLvl and minLvl > 0 then
        if not rec.minLvl or minLvl < rec.minLvl then rec.minLvl = minLvl end
        if not rec.estLvl or minLvl < rec.estLvl then rec.estLvl = minLvl end
    elseif kind == "quest" then
        local qlVal = (extra.ml and extra.ml > 0 and extra.ml) or (extra.ql and extra.ql > 0 and extra.ql) or 0
        if qlVal > 0 and (not rec.estLvl or qlVal < rec.estLvl) then rec.estLvl = qlVal end
    elseif kind == "craft" and skill and skill > 0 then
        local clVal = math.max(1, math.floor(skill / 5))
        if not rec.estLvl or clVal < rec.estLvl then rec.estLvl = clVal end
    end
end

local CLASS_BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
function GearScoringEngine.containsBit(mask, bitv)
    return (mask == 0) or not bitv or (math.floor(mask / bitv) % 2 == 1)
end
function GearScoringEngine.resolveQuestInfo(qid)
    return ns.ItemSources and ns.ItemSources.questInfo and ns.ItemSources.questInfo[qid]
end
function GearScoringEngine.resolveQuestMinLevel(qid, fallback)
    local apiInfo = GearScoringEngine.resolveQuestInfo(qid)
    if apiInfo and type(apiInfo.minLevel) == "number" then return apiInfo.minLevel end
    local priorityQueue = qid and ns.QUESTS and ns.QUESTS[qid]
    return (priorityQueue and priorityQueue[3]) or fallback or 0
end
ns.QuestMinLevel = GearScoringEngine.resolveQuestMinLevel
function GearScoringEngine.indexQuests()
    local questLookupTable = ns.QUESTS
    local stateEntry = ns.indexStats
    stateEntry.quest = 0
    if not questLookupTable then return end
    local entryIndex = ns.index
    local class = ns:GetActiveClassToken()
    local cbit = CLASS_BIT[class]
    local raceID = select(3, UnitRace("player"))
    local rbit = raceID and 2 ^ (raceID - 1) or nil
    for qid, priorityQueue in pairs(questLookupTable) do
        if GearScoringEngine.containsBit(priorityQueue[4], cbit) and GearScoringEngine.containsBit(priorityQueue[5], rbit) then
            for pass = 1, 2 do
                local itemList = (pass == 1) and priorityQueue[6] or priorityQueue[7]
                for _, id in ipairs(itemList) do
                    local rec = entryIndex[id]
                    if rec == nil then
                        local _, _, _, localeTbl, iconTex, cID, sID = resolveItemInfoInstantC(id)
                        if localeTbl and ns.EQUIP_LOCS[localeTbl] then
                            rec = { loc = localeTbl, classID = cID, subID = sID, icon = iconTex, src = {}, kinds = {} }
                            entryIndex[id] = rec
                            stateEntry.items = stateEntry.items + 1
                        else
                            entryIndex[id] = false
                        end
                    end
                    if rec then
                        if not rec.kinds.quest then stateEntry.quest = stateEntry.quest + 1 end
                        local apiInfo = GearScoringEngine.resolveQuestInfo(qid)
                        GearScoringEngine.addSource(rec, (apiInfo and apiInfo.title) or priorityQueue[1], "", nil, "quest", nil, {
                            qid = qid, ql = (apiInfo and apiInfo.level) or priorityQueue[2], ml = GearScoringEngine.resolveQuestMinLevel(qid, priorityQueue[3]),
                            choice = (pass == 1), titleEn = (apiInfo and apiInfo.titleEn) or priorityQueue[1],
                        })
                    end
                end
            end
            GearScoringEngine.maybeYield()
        end
    end
end

function GearScoringEngine.constructRecord(id)
    local _, _, _, localeTbl, iconTex, cID, sID = resolveItemInfoInstantC(id)
    if localeTbl and ns.EQUIP_LOCS[localeTbl] then
        return { loc = localeTbl, classID = cID, subID = sID, icon = iconTex, src = {}, kinds = {} }
    end
    return false
end

local SCAN_MAX = 400000
function GearScoringEngine.inspectNewItems()
    local dungeonCatalog = ns.GearDB
    local knVal = dungeonCatalog and dungeonCatalog.known
    if type(knVal) ~= "table" or #knVal == 0 then return end   
    local stateEntry = ns.indexStats
    local build = select(4, GetBuildInfo()) or 0
    local lookupCache = savedDB.scan
    local ids
    if type(lookupCache) == "table" and lookupCache.build == build and lookupCache.max == SCAN_MAX and lookupCache.ver == dungeonCatalog.version and type(lookupCache.ids) == "table" then
        ids = lookupCache.ids
    else
        local known = {}
        for index = 1, #knVal, 2 do
            for id = knVal[index], knVal[index + 1] do known[id] = true end
        end
        GearScoringEngine.maybeYield()
        ids = {}
        for id = 1, SCAN_MAX do
            if not known[id] then
                local _, _, _, localeTbl = resolveItemInfoInstantC(id)
                if localeTbl and ns.EQUIP_LOCS[localeTbl] then ids[#ids + 1] = id end
            end
            if id % 2000 == 0 then
                stateEntry.scanned = id
                yieldSteps = 250
                GearScoringEngine.maybeYield()
            end
        end
        savedDB.scan = { build = build, max = SCAN_MAX, ver = dungeonCatalog.version, ids = ids }
    end
    stateEntry.scanned = nil
    stateEntry.new = 0
    local function shouldIncludeGearCandidate(id)
        if ns.index[id] == nil then
            local rec = GearScoringEngine.constructRecord(id)
            if rec then
                rec.new = true
                GearScoringEngine.addSource(rec, L["Forever 신규"], L["획득처 불명"], nil, "unknown")
                ns.index[id] = rec
                stateEntry.items = stateEntry.items + 1
                stateEntry.new = stateEntry.new + 1
            end
        end
        GearScoringEngine.maybeYield()
    end

    for _, id in ipairs((ns.ItemSources and ns.ItemSources.items) or {}) do shouldIncludeGearCandidate(id) end
    for _, id in ipairs(ids) do shouldIncludeGearCandidate(id) end
end

function GearScoringEngine.containsKnown(rec)
    for _, stateFlag in ipairs(rec.src) do
        if stateFlag.kind ~= "unknown" and not stateFlag.learned then return true end
    end
    return false
end
function ns:HasKnownSource(id)
    if self.indexState ~= "done" then return nil end
    local rec = self.index[id]
    return rec and GearScoringEngine.containsKnown(rec) or false
end

function ns:LearnSource(id, kind, e)
    if type(id) ~= "number" or not savedDB then return false end
    savedDB.learned = savedDB.learned or {}
    local L2 = savedDB.learned
    L2[kind] = L2[kind] or {}
    local itemList = L2[kind][id]
    if not itemList then itemList = {}; L2[kind][id] = itemList end
    for _, optionRef in ipairs(itemList) do
        if (kind == "quests" and optionRef.qid == e.qid) or (kind ~= "quests" and optionRef.boss == e.boss and (optionRef.inst or optionRef.zone) == (e.inst or e.zone)) then
            return false
        end
    end
    e.t = time and time() or nil
    itemList[#itemList + 1] = e
    if ns.indexState == "done" then
        local rec = ns.index[id]
        if rec == nil then rec = GearScoringEngine.constructRecord(id); ns.index[id] = rec end
        if rec then
            if kind == "drops" then GearScoringEngine.addSource(rec, e.inst, e.boss, nil, "drop", nil, { creature = e.npc, learned = true })
            elseif kind == "quests" then GearScoringEngine.addSource(rec, e.title, "", nil, "quest", nil, { qid = e.qid, ql = e.lvl, ml = 0, choice = false, learned = true })
            else GearScoringEngine.addSource(rec, e.zone, e.boss, nil, "vendor", nil, { creature = e.npc, learned = true }) end
            
            for index = #rec.src, 1, -1 do if rec.src[index].kind == "unknown" then table.remove(rec.src, index) end end
            rec.kinds.unknown = nil
            ns.knownIDs = nil
        end
    end
    return true
end

function GearScoringEngine.indexForeverExtra()
    local qcbit = CLASS_BIT[ns:GetActiveClassToken()]
    local raceID = select(3, UnitRace("player"))
    local qrbit = raceID and 2 ^ (raceID - 1) or nil
    local stateEntry = ns.indexStats
    stateEntry.extra = 0
    local entryIndex = ns.index
    local function ensureItemIndexRecord(id)
        local rec = entryIndex[id]
        if rec == nil then
            rec = GearScoringEngine.constructRecord(id)
            entryIndex[id] = rec
            if rec then stateEntry.items = stateEntry.items + 1 end
        end
        return rec or nil
    end
    local skipKnown = false
    local function iterateEquipmentLocations(tbl, fn)
        if type(tbl) ~= "table" then return end
        for id, itemList in pairs(tbl) do
            local rec = ensureItemIndexRecord(id)
            if rec and not (skipKnown and GearScoringEngine.containsKnown(rec)) then
                stateEntry.extra = stateEntry.extra + 1
                for _, e in ipairs(itemList) do fn(rec, e) end
            end
            GearScoringEngine.maybeYield()
        end
    end
    
    local function containsBoss(rec, boss)
        local buttonWidget = tostring(boss or ""):lower()
        for _, stateFlag in ipairs(rec.src) do
            if stateFlag.kind == "drop" and tostring(stateFlag.boss or ""):lower() == buttonWidget then return true end
        end
        return false
    end
    
    local function containsCraft(rec, skill)
        for _, stateFlag in ipairs(rec.src) do
            if stateFlag.kind == "craft" and stateFlag.inst == skill then return true end
        end
        return false
    end
    local myFaction = (UnitFactionGroup and UnitFactionGroup("player") or ""):lower()   
    local function resolveSideOK(e) return not e.side or e.side == "both" or e.side == myFaction end
    for _, coordinateHelper in ipairs({ ns.CraftData, ns.ForeverExtra, ns.DungeonData, ns.WorldData, ns.ItemSources, savedDB and savedDB.learned }) do
        local learned = (savedDB and coordinateHelper == savedDB.learned) or nil   
        skipKnown = learned and true or false             
        
        local onlyNew = (coordinateHelper == ns.WorldData or coordinateHelper == ns.ItemSources)
        if type(coordinateHelper) == "table" then
            iterateEquipmentLocations(coordinateHelper.drops, function(rec, e) if not containsBoss(rec, e.boss) then GearScoringEngine.addSource(rec, e.inst, e.boss, nil, "drop", nil, { creature = e.npc, learned = learned }) end end)
            iterateEquipmentLocations(coordinateHelper.quests, function(rec, e)
                
                local priorityQueue = e.qid and e.qid > 0 and ns.QUESTS and ns.QUESTS[e.qid]
                if priorityQueue and not (GearScoringEngine.containsBit(priorityQueue[4], qcbit) and GearScoringEngine.containsBit(priorityQueue[5], qrbit)) then return end
                if not resolveSideOK(e) then return end
                if not (onlyNew and rec.kinds.quest) then
                    local apiInfo = GearScoringEngine.resolveQuestInfo(e.qid)
                    GearScoringEngine.addSource(rec, (apiInfo and apiInfo.title) or e.title, "", nil, "quest", nil, {
                        qid = e.qid, ql = (apiInfo and apiInfo.level) or (priorityQueue and priorityQueue[2]) or e.lvl,
                        ml = GearScoringEngine.resolveQuestMinLevel(e.qid, e.minLevel), choice = e.choice == true,
                        learned = learned, titleEn = (apiInfo and apiInfo.titleEn) or e.titleEn,
                    })
                end
            end)
            iterateEquipmentLocations(coordinateHelper.vendors, function(rec, e)
                if not resolveSideOK(e) then return end
                if not (onlyNew and rec.kinds.vendor) then
                    GearScoringEngine.addSource(rec, e.zone, e.boss, nil, "vendor", nil, { creature = e.npc, learned = learned })
                end
            end)
            iterateEquipmentLocations(coordinateHelper.craft, function(rec, e)
                if not containsCraft(rec, e.skill) then
                    GearScoringEngine.addSource(rec, e.skill, e.recipe and "도안 필요" or "", nil, "craft", e.lvl, e.spell and { spell = e.spell } or {})
                end
            end)
        end
    end
end

function GearScoringEngine.indexBody()
    local entryIndex = ns.index
    local stateEntry = ns.indexStats
    stateEntry.bosses, stateEntry.items, stateEntry.modules, stateEntry.craft = 0, 0, 1, 0

    local dungeonCatalog = ns.GearDB
    if dungeonCatalog and type(dungeonCatalog.sources) == "table" then
        for itemID, sources in pairs(dungeonCatalog.sources) do
            if type(itemID) == "number" and type(sources) == "table" then
                local rec = entryIndex[itemID]
                if rec == nil then
                    rec = GearScoringEngine.constructRecord(itemID)
                    entryIndex[itemID] = rec
                    if rec then stateEntry.items = stateEntry.items + 1 end
                end
                if rec then
                    for _, sourceData in ipairs(sources) do
                        stateEntry.bosses = stateEntry.bosses + 1
                        GearScoringEngine.addSource(rec, sourceData.inst or "?", sourceData.boss or "?", sourceData.minLvl, "drop", nil, {
                            creature = sourceData.creature, map = sourceData.map, chance = sourceData.chance
                        })
                    end
                end
                GearScoringEngine.maybeYield()
            end
        end
    end

    local categoryColors = dungeonCatalog and dungeonCatalog.crafting
    if savedDB.crafting and type(categoryColors) == "table" then
        for itemID, sources in pairs(categoryColors) do
            local rec = entryIndex[itemID]
            if rec == nil then
                rec = GearScoringEngine.constructRecord(itemID)
                entryIndex[itemID] = rec
                if rec then stateEntry.items = stateEntry.items + 1 end
            end
            if rec then
                for _, sourceData in ipairs(sources) do
                    stateEntry.craft = stateEntry.craft + 1
                    GearScoringEngine.addSource(rec, sourceData.inst or L["제작"], sourceData.boss or "", nil, "craft", sourceData.skill, { spell = sourceData.spell })
                end
            end
            GearScoringEngine.maybeYield()
        end
    end

    GearScoringEngine.indexQuests()
    GearScoringEngine.indexForeverExtra()
    ns.indexBaseReady = true   
    GearScoringEngine.inspectNewItems()
end

local indexCo
function ns:EnsureIndex()
    if self.indexState == "running" or self.indexState == "done" or self.indexState == "empty" then return end
    wipe(self.index)
    self.indexBaseReady = false
    scoreCache = {}
    self.indexState = "running"
    indexCo = coroutine.create(GearScoringEngine.indexBody)
end

function ns:ResetIndex()
    self.knownIDs = nil
    self.indexState = "idle"
    self.indexBaseReady = false
    indexCo = nil
end

local locToGroups = {}
for _, greenVal in ipairs(ns.GROUPS) do
    for localeTbl in pairs(greenVal.locs) do
        locToGroups[localeTbl] = locToGroups[localeTbl] or {}
        table.insert(locToGroups[localeTbl], greenVal)
    end
end

local EFFECT_TOKENS = {
    "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_HEALING_DONE_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
    "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
    "ITEM_MOD_FERAL_ATTACK_POWER_SHORT", "ITEM_MOD_MANA_REGENERATION_SHORT",
    "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", "ITEM_MOD_DODGE_RATING_SHORT", "ITEM_MOD_PARRY_RATING_SHORT",
    "ITEM_MOD_BLOCK_VALUE_SHORT",
}
local effectPatterns
function GearScoringEngine.escapeLuaPatternChars(str) return (str:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")) end
function GearScoringEngine.assembleEffectPatterns()
    effectPatterns = {}
    for _, queryToken in ipairs(EFFECT_TOKENS) do
        local pats = {}
        local base = queryToken:gsub("_SHORT$", "")
        local long, short = _G[base], _G[queryToken]
        if type(long) == "string" and long:find("%%d") then
            pats[#pats + 1] = GearScoringEngine.escapeLuaPatternChars(long):gsub("%%%%d", "(%%d+)")
        end
        if type(short) == "string" and short ~= "" then
            local e = GearScoringEngine.escapeLuaPatternChars(short)
            pats[#pats + 1] = "^%+?(%d+)%s*" .. e
            pats[#pats + 1] = e .. "%s*%+(%d+)"
        end
        if #pats > 0 then effectPatterns[queryToken] = pats end
    end
end
local tooltipStatsByID = {}
function GearScoringEngine.tooltipStats(id)
    if not id then return nil end
    if tooltipStatsByID[id] ~= nil then return tooltipStatsByID[id] end
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
    local isCallOk, payloadData = pcall(C_TooltipInfo.GetItemByID, id)
    if not isCallOk or type(payloadData) ~= "table" or type(payloadData.lines) ~= "table" or #payloadData.lines == 0 then return nil end
    if not effectPatterns then GearScoringEngine.assembleEffectPatterns() end
    local outputList = {}
    for _, lnVal in ipairs(payloadData.lines) do
        local resolvedValue = lnVal.leftText
        if type(resolvedValue) == "string" and resolvedValue ~= "" and resolvedValue:find("%d") then
            resolvedValue = resolvedValue:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            for queryToken, pats in pairs(effectPatterns) do
                for _, anchorTarget in ipairs(pats) do
                    local entryValue = tonumber(resolvedValue:match(anchorTarget))
                    if entryValue then
                        if (outputList[queryToken] or 0) < entryValue then outputList[queryToken] = entryValue end
                        break
                    end
                end
            end
        end
    end
    tooltipStatsByID[id] = outputList
    return outputList
end
ns.TooltipStats = GearScoringEngine.tooltipStats

local statsCache, statsLinks = {}, {}
function GearScoringEngine.resolveStats(link)
    local stateEntry = statsCache[link]
    if stateEntry == nil then
        local base = resolveItemStatsC and resolveItemStatsC(link) or false
        local id = tonumber(link:match("item:(%d+)"))
        local tipWidget = id and GearScoringEngine.tooltipStats(id)
        if tipWidget then
            local merged = {}
            if base then for entryKey, entryValue in pairs(base) do merged[entryKey] = entryValue end end
            for entryKey, entryValue in pairs(tipWidget) do
                if (merged[entryKey] or 0) < entryValue then merged[entryKey] = entryValue end   
            end
            stateEntry = merged
            statsCache[link] = stateEntry
            statsLinks[id] = statsLinks[id] or {}
            statsLinks[id][link] = true
        else
            stateEntry = base
            
            if base and not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then
                statsCache[link] = base
                if id then
                    statsLinks[id] = statsLinks[id] or {}
                    statsLinks[id][link] = true
                end
            end
        end
    end
    return stateEntry, statsCache[link] ~= nil
end
ns.GetStats = GearScoringEngine.resolveStats

function GearScoringEngine.evaluateItemRoleScore(link, ilvl, weights)
    local scVal = (ilvl or 0) * ns.ILVL_WEIGHT
    local stats, complete = GearScoringEngine.resolveStats(link)
    if stats then
        for entryKey, entryValue in pairs(stats) do
            local matchRef = weights[entryKey]
            if matchRef then scVal = scVal + entryValue * matchRef end
        end
    end
    return scVal, complete
end

local inspectTip, classPrefix
local allowCache = {}
function GearScoringEngine.invalidateItemCaches(id)
    for link in pairs(statsLinks[id] or {}) do statsCache[link] = nil end
    statsLinks[id] = nil
    allowCache[id] = nil
    local rec = ns.index and ns.index[id]
    if type(rec) == "table" then rec.junk = nil end
    for _, scores in pairs(scoreCache) do scores[id] = nil end
end

function GearScoringEngine.hasClassAllowed(id)
    local themeColor = allowCache[id]
    if themeColor ~= nil then return themeColor end
    if not inspectTip then
        inspectTip = CreateFrame("GameTooltip", "EzWoWBestGearFinderScanTip", UIParent, "GameTooltipTemplate")
        classPrefix = ((ITEM_CLASSES_ALLOWED or "Classes: %s"):gsub("%%s", ""))
    end
    inspectTip:SetOwner(UIParent, "ANCHOR_NONE")
    inspectTip:ClearLines()
    local isCallOk = pcall(inspectTip.SetHyperlink, inspectTip, "item:" .. id)
    local nodeEntry = inspectTip:NumLines()
    if not isCallOk or nodeEntry == 0 then return nil end
    local localized = ns:GetActiveClassDisplayName()
    local result = true
    for index = 2, nodeEntry do
        local labelRegion = _G["EzWoWBestGearFinderScanTipTextLeft" .. index]
        local resolvedValue = labelRegion and labelRegion:GetText()
        if resolvedValue then
            local _, e = resolvedValue:find(classPrefix, 1, true)
            if e then
                result = resolvedValue:sub(e + 1):find(localized, 1, true) ~= nil
                break
            end
        end
    end
    allowCache[id] = result
    return result
end

function GearScoringEngine.hasJunkName(name)
    if not name then return false end
    return name:find("^[Tt][Ee][Ss][Tt]") or name:find("^TEST") or name:lower():find("deprecated", 1, true)
        or name:find("^zz") or name:find("^ZZ") or name:find("^OLD") or name:find("^%[") or name:find("%[PH%]")
        or name:find("^Monster") or name:find("^PH ") or false
end

local resolveItemSpellC = (C_Item and C_Item.GetItemSpell) or GetItemSpell

function GearScoringEngine.containsUseLine(id)
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
    local isCallOk, payloadData = pcall(C_TooltipInfo.GetItemByID, id)
    if not isCallOk or type(payloadData) ~= "table" or type(payloadData.lines) ~= "table" then return nil end
    local prefix = ITEM_SPELL_TRIGGER_ONUSE or "Use:"
    for _, lnVal in ipairs(payloadData.lines) do
        local resolvedValue = lnVal.leftText
        if type(resolvedValue) == "string" and resolvedValue:sub(1, #prefix) == prefix then return true end
    end
    return false
end
function GearScoringEngine.hasAbilityRelic(id, rec)
    if not (rec.new and rec.loc == "INVTYPE_RELIC") then return false end
    local unitRef = GearScoringEngine.containsUseLine(id)
    if unitRef ~= nil then return unitRef end
    if not resolveItemSpellC then return false end
    local isCallOk, spell = pcall(resolveItemSpellC, id)
    return isCallOk and spell ~= nil
end

function GearScoringEngine.isItemUsableByClass(rec, rules, armorType, dwOK)
    local localeTbl, cID, sID = rec.loc, rec.classID, rec.subID
    if cID == ns.CLASS_WEAPON then
        if not rules.weapons[sID] then return false end
        if localeTbl == "INVTYPE_WEAPONOFFHAND" and not dwOK then return false end
        return true
    elseif cID == ns.CLASS_ARMOR then
        if ns.ARMOR_LOCS[localeTbl] then
            
            return type(sID) == "number" and sID >= 1 and sID <= armorType
        end
        if localeTbl == "INVTYPE_SHIELD" then return rules.shield and sID == 6 end
        if localeTbl == "INVTYPE_RELIC" then return rules.relic == sID end
        if localeTbl == "INVTYPE_RANGED" or localeTbl == "INVTYPE_RANGEDRIGHT" or localeTbl == "INVTYPE_THROWN" then return false end
    elseif cID ~= nil then
        return false   
    end
    return true
end

function GearScoringEngine.computeEquippedSlotScore(group, weights)
    local base, baseLink, complete = nil, nil, true
    if ns.viewClass then return 0, nil, false end
    for _, slot in ipairs(group.inv) do
        local link = GetInventoryItemLink("player", slot)
        local score = 0
        if link then
            local name, _, _, ilvl = resolveItemInfoC(link)
            if not name then
                complete = false
            else
                local ready
                score, ready = GearScoringEngine.evaluateItemRoleScore(link, ilvl, weights)
                if not ready then complete = false end
            end
        end
        if not base or score < base then base, baseLink = score, link end
    end
    return base or 0, baseLink, complete
end

function ns.FormatStatComparisonDelta(link, baseLink, weights, maxN)
    local alphaVal = GearScoringEngine.resolveStats(link) or {}
    local buttonWidget = (baseLink and GearScoringEngine.resolveStats(baseLink)) or {}
    local itemList = {}
    local visitedMap = {}
    for entryKey in pairs(alphaVal) do visitedMap[entryKey] = true end
    for entryKey in pairs(buttonWidget) do visitedMap[entryKey] = true end
    for entryKey in pairs(visitedMap) do
        local matchRef = weights[entryKey]
        if matchRef and matchRef > 0 then
            local dataEntry = (alphaVal[entryKey] or 0) - (buttonWidget[entryKey] or 0)
            if math.abs(dataEntry) >= 0.5 then itemList[#itemList + 1] = { k = entryKey, d = dataEntry, w = math.abs(dataEntry) * matchRef } end
        end
    end
    table.sort(itemList, function(x, y) return x.w > y.w end)
    local outputList = {}
    for index = 1, math.min(maxN or 4, #itemList) do
        local e = itemList[index]
        local formatLocalizedLabel = type(_G[e.k]) == "string" and _G[e.k] or e.k:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", "")
        outputList[#outputList + 1] = format("%s %+d", formatLocalizedLabel, (e.d >= 0 and math.floor(e.d + 0.5) or math.ceil(e.d - 0.5)))
    end
    return table.concat(outputList, ", ")
end

function GearScoringEngine.resolveEquippedIlvl(group)
    local best
    if ns.viewClass then return nil end
    for _, slot in ipairs(group.inv) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local _, _, _, ilvl = resolveItemInfoC(link)
            if ilvl and (not best or ilvl < best) then best = ilvl end
        end
    end
    return best
end

local hasCached = C_Item and C_Item.IsItemDataCachedByID

local requestUncachedItemData
function requestUncachedItemData(id, prio)
    if dead[id] then return false end
    local tier = type(prio) == "number" and prio or (prio and 2 or 3)
    if queued[id] then GearScoringEngine.enqueue(id, tier); return true end
    local resolvedValue = requested[id]
    if resolvedValue and GetTime() - resolvedValue < 10 then return true end
    if (attempts[id] or 0) >= 3 then dead[id] = true; return false end
    GearScoringEngine.enqueue(id, tier)
    return true
end

function ns:RequestItem(id)
    if dead[id] then return false end
    if queued[id] then GearScoringEngine.enqueue(id, 1); return true end
    local resolvedValue = requested[id]
    if resolvedValue and GetTime() - resolvedValue < 10 then return true end
    if (attempts[id] or 0) >= 3 then dead[id] = true; return false end
    GearScoringEngine.enqueue(id, 1)
    return true
end
function ns:CancelSearchRequests()
    for id, tier in pairs(queued) do
        if tier == 1 then queued[id] = nil end
    end
    wipe(queueSearch)
    searchHead = 1
end
function ns:IsItemQueued(id) return queued[id] ~= nil end
function ns:IsItemDead(id) return dead[id] and true or false end
function ns:GetCachedItemInfo(id)
    local rec = self.index and self.index[id]
    if type(rec) == "table" and rec.name then
        return rec.name, rec.link, rec.quality, rec.ilvl, rec.req, nil, nil, nil, rec.loc, rec.icon
    end
    if hasCached and not hasCached(id) then return nil end
    local name, link, quality, ilvl, req, alphaVal, buttonWidget, themeColor, localeTbl, iconTex = resolveItemInfoC(id)
    if name and type(rec) == "table" then
        rec.name, rec.link, rec.quality, rec.ilvl, rec.req = name, link, quality, ilvl or 0, req or 0
        if iconTex then rec.icon = iconTex end
    end
    return name, link, quality, ilvl, req, alphaVal, buttonWidget, themeColor, localeTbl, iconTex
end
ns.GetItemInfoC = resolveItemInfoC

function GearScoringEngine.inRange(req, minReq, maxReq, ilvl, isBis)
    if req and req > 0 then return req >= minReq and req <= maxReq end
    if isBis then return true end
    local lvVal = ilvl or 0
    return lvVal <= maxReq + 10 and lvVal >= maxReq - 2   
end

local bisCache = {}

function ns:IsItemUsableByActiveClass(rec, id)
    local rules = ns.CLASS_RULES[ns:GetActiveClassToken()]
    if not rules then return true end
    local level = UnitLevel("player")
    local class = ns:GetActiveClassToken()
    local dwOK = rules.dualWield and level >= (ns.DUAL_WIELD_LEVEL[class] or 99) or false
    return GearScoringEngine.isItemUsableByClass(rec, rules, GearScoringEngine.resolveArmorType(rules, level), dwOK)
        and (not id or GearScoringEngine.hasClassAllowed(id) ~= false)
end

function ns:SetViewClass(classToken)
    local _, mine = UnitClass("player")
    if classToken == mine then classToken = nil end
    ns.viewClass = classToken
    wipe(allowCache)
    wipe(bisCache)
    scoreCache = {}
    self:ResetIndex()
end

function GearScoringEngine.resolveBisLookup(si)
    local themeColor = bisCache[si]
    if themeColor then return themeColor end
    themeColor = { top = {}, alt = {} }
    local class = ns:GetActiveClassToken()
    local payloadData = ns.BiS and ns.BiS[class]
    local names = ns.BIS_MAP and ns.BIS_MAP[class] and ns.BIS_MAP[class][si]
    if payloadData and names then
        local side = (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "H" or "A"
        for _, nmVal in ipairs(names) do
            local resolvedValue = payloadData[nmVal] and (payloadData[nmVal][side] or payloadData[nmVal].A or payloadData[nmVal].H)
            if resolvedValue then
                for _, id in ipairs(resolvedValue.top) do themeColor.top[id] = true end
                for _, id in ipairs(resolvedValue.alt) do themeColor.alt[id] = true end
            end
        end
    end
    bisCache[si] = themeColor
    return themeColor
end
function ns:IsBestInSlotCandidate(id)
    local lo, hi = self:GetLevelFilterRange()
    if lo > 30 or hi < 30 then return false end
    for si = 1, #self:GetSpecList() do
        local themeColor = GearScoringEngine.resolveBisLookup(si)
        if themeColor.top[id] or themeColor.alt[id] then return true end
    end
    return false
end
function ns:GetBestInSlotRank(si, id)
    local lo, hi = self:GetLevelFilterRange()
    if lo > 30 or hi < 30 then return 0 end
    local themeColor = GearScoringEngine.resolveBisLookup(si)
    return themeColor.top[id] and 2 or (themeColor.alt[id] and 1 or 0)
end

function ns:EvaluateAllSlotCandidates()
    local class = ns:GetActiveClassToken()
    local other = ns.viewClass ~= nil   
    local rules = ns.CLASS_RULES[class]
    if not rules then return end
    local level = UnitLevel("player")
    local minReq, maxReq = self:GetLevelFilterRange()
    local sourceLevel = math.min(level, maxReq)
    wipe(qdone)
    local armorType = GearScoringEngine.resolveArmorType(rules, level)
    local dwOK = rules.dualWield and level >= (ns.DUAL_WIELD_LEVEL[class] or 99) or false
    local specs = self:GetSpecList()

    local buckets = {}
    for _, greenVal in ipairs(ns.GROUPS) do buckets[greenVal.key] = {} end
    local cand, ready, pending, skipped = 0, 0, 0, 0
    local errCount, firstErr = 0, nil
    local function handle(id, rec)
        if rec and GearScoringEngine.isItemUsableByClass(rec, rules, armorType, dwOK) and ns:IsItemSourceAllowed(rec, id, sourceLevel)
           and not (savedDB.mobCut and rec.minLvl and not ((rec.kinds.craft and savedDB.crafting) or (rec.kinds.quest and savedDB.quests)) and rec.minLvl > maxReq + 8) then
            cand = cand + 1
            local name, link, quality, ilvl, reqLevel = rec.name, rec.link, rec.quality, rec.ilvl, rec.req
            if not name and (not hasCached or hasCached(id)) then
                name, link, quality, ilvl, reqLevel = resolveItemInfoC(id)
                if name then
                    rec.name, rec.link, rec.quality, rec.ilvl, rec.req = name, link, quality, ilvl or 0, reqLevel or 0
                end
            end
            if not name then
                local tier = 4
                if not rec.new then
                    local elVal = rec.estLvl or rec.minLvl
                    if (elVal and elVal >= minReq - 8 and elVal <= maxReq + 10) or ns:IsBestInSlotCandidate(id) then
                        tier = 2
                    else
                        tier = 3
                    end
                end
                requestUncachedItemData(id, tier)
                if dead[id] then skipped = skipped + 1 else pending = pending + 1 end
            else
                ready = ready + 1
                if rec.junk == nil then
                    if rec.new and GearScoringEngine.hasJunkName(name) then
                        rec.junk = true
                    elseif rec.new and rec.loc == "INVTYPE_RELIC" then
                        local unitRef = GearScoringEngine.containsUseLine(id)
                        if unitRef ~= nil then rec.junk = unitRef end
                    else
                        rec.junk = false
                    end
                end
                local hasJunk = rec.junk or (rec.junk == nil and GearScoringEngine.hasAbilityRelic(id, rec))
                if quality and savedDB.qual[quality] and not hasJunk and GearScoringEngine.inRange(reqLevel, minReq, maxReq, ilvl, ns:IsBestInSlotCandidate(id)) then
                    local entry = { id = id, name = name, link = link, ilvl = ilvl or 0, req = reqLevel or 0, rec = rec, quality = quality }
                    for _, greenVal in ipairs(locToGroups[rec.loc]) do
                        table.insert(buckets[greenVal.key], entry)
                    end
                    if rec.loc == "INVTYPE_WEAPON" and dwOK then
                        table.insert(buckets.OFF, entry)
                    end
                end
            end
        end
    end
    for id, rec in pairs(self.index) do
        local isCallOk, errorObj = pcall(handle, id, rec)
        if not isCallOk then
            errCount = errCount + 1
            firstErr = firstErr or (tostring(id) .. ": " .. tostring(errorObj))
        end
    end
    self.itemErrors, self.firstItemError = errCount, firstErr

    local twoHanded = false
    local mhVal = (not other) and GetInventoryItemLink("player", 16) or nil
    if mhVal then
        local _, _, _, localeTbl = resolveItemInfoInstantC(mhVal)
        twoHanded = (localeTbl == "INVTYPE_2HWEAPON" or localeTbl == "INVTYPE_RANGED")
    end

    local perSlot = savedDB.perSlot
    self.funnel = {}
    local views = {}
    self.slotError = nil
    for si, spec in ipairs(specs) do
        local weights = spec.w
        scoreCache[si] = scoreCache[si] or {}
        local scVal = scoreCache[si]
        local picks = {}
        for _, greenVal in ipairs(ns.GROUPS) do
            local okSlot, errSlot = pcall(function()
                local itemList = {}
                
                local sortTokens   
                if savedDB.sortStats and next(savedDB.sortStats) then
                    sortTokens = {}
                    for _, stateEntry in ipairs(ns.SORT_STATS or {}) do
                        if savedDB.sortStats[stateEntry.key] then sortTokens[#sortTokens + 1] = stateEntry.tokens end
                    end
                end
                for _, e in ipairs(buckets[greenVal.key]) do
                    local score = scVal[e.id]
                    if not score then
                        local complete
                        score, complete = GearScoringEngine.evaluateItemRoleScore(e.link, e.ilvl, weights)
                        if complete then scVal[e.id] = score end
                    end
                    local svVal
                    if sortTokens then
                        svVal = 0
                        local stt = GearScoringEngine.resolveStats(e.link)
                        if stt then
                            for _, grp in ipairs(sortTokens) do
                                local matchRef = 0
                                for _, tkVal in ipairs(grp) do if (stt[tkVal] or 0) > matchRef then matchRef = stt[tkVal] end end
                                svVal = svVal + matchRef
                            end
                        end
                    end
                    itemList[#itemList + 1] = { e = e, score = score, bis = ns:GetBestInSlotRank(si, e.id), sv = svVal }
                end
                table.sort(itemList, function(alphaVal, buttonWidget)
                    if sortTokens and alphaVal.sv ~= buttonWidget.sv then return alphaVal.sv > buttonWidget.sv end
                    if savedDB.bisPriority and alphaVal.bis ~= buttonWidget.bis then return alphaVal.bis > buttonWidget.bis end
                    if alphaVal.score ~= buttonWidget.score then return alphaVal.score > buttonWidget.score end
                    if alphaVal.bis ~= buttonWidget.bis then return alphaVal.bis > buttonWidget.bis end
                    return alphaVal.e.id < buttonWidget.e.id
                end)
                local base, baseLink, baseReady = GearScoringEngine.computeEquippedSlotScore(greenVal, weights)
                local weaponSwitch = (greenVal.key == "MAIN1H" or greenVal.key == "OFF") and twoHanded
                if greenVal.key == "MAIN2H" and not other and not twoHanded then
                    local offLink = GetInventoryItemLink("player", 17)
                    if offLink then
                        local name, _, _, ilvl = resolveItemInfoC(offLink)
                        if name then
                            local offScore, offReady = GearScoringEngine.evaluateItemRoleScore(offLink, ilvl, weights)
                            base = base + offScore
                            baseReady = baseReady and offReady
                        else baseReady = false end
                        baseLink = nil 
                    end
                end
                local comparable = not other and baseReady and not weaponSwitch
                local compareNote = other and L["다른 직업 보기"] or (not baseReady and L["착용 장비 확인 중"])
                    or (weaponSwitch and L["무기 조합 확인 필요"])
                    or (greenVal.key == "MAIN2H" and not twoHanded and not baseLink and base > 0 and L["주무기 + 보조 장비 합산 비교"])
                local presentReference = other or weaponSwitch or not baseReady
                if si == 1 then self.funnel = self.funnel or {}; self.funnel[greenVal.key] = { cand = #itemList, base = base, top = itemList[1] and itemList[1].score or 0, topId = itemList[1] and itemList[1].e.id } end
                local baseIlvl = GearScoringEngine.resolveEquippedIlvl(greenVal)
                local picked = {}
                
                local worn = {}
                for _, invSlot in ipairs(greenVal.inv) do
                    local wid = (not other) and GetInventoryItemID and GetInventoryItemID("player", invSlot)
                    if wid then worn[wid] = true end
                end
                local priorityQueue = ns.searchText
                if priorityQueue == "" then priorityQueue = nil end
                local function doesCandidateMatchFilter(e)
                    if string.find(string.lower(e.name or ""), priorityQueue, 1, true) then return true end
                    for _, stateFlag in ipairs(e.rec.src) do
                        if string.find(string.lower((stateFlag.boss or "") .. " " .. (stateFlag.inst or "")), priorityQueue, 1, true) then return true end
                    end
                    return false
                end
                for _, boxWidth in ipairs(itemList) do
                    local hasUpgrade = comparable and boxWidth.score > base * (1 + ns.UPGRADE_MARGIN_PCT) + ns.UPGRADE_MARGIN_ABS
                    if priorityQueue and not doesCandidateMatchFilter(boxWidth.e) then
                        
                    elseif (priorityQueue or presentReference or not savedDB.upgradeOnly or hasUpgrade) and (priorityQueue or not (boxWidth.bis == 2 and worn[boxWidth.e.id])) then
                        local e = boxWidth.e
                        if not savedDB.classFilter or GearScoringEngine.hasClassAllowed(e.id) ~= false then
                            picked[#picked + 1] = { id = e.id, link = e.link, ilvl = e.ilvl, req = e.req, rec = e.rec,
                                quality = e.quality, score = boxWidth.score, upgrade = hasUpgrade, baseIlvl = baseIlvl, baseScore = base,
                                bis = boxWidth.bis, baseLink = baseLink, weights = weights, sortVal = boxWidth.sv, comparable = comparable, compareNote = compareNote }
                            if #picked >= (priorityQueue and 30 or perSlot) then break end
                        end
                    end
                end
                if #picked > 0 then picks[greenVal.key] = picked end
            end)
            if not okSlot then self.slotError = greenVal.key .. ": " .. tostring(errSlot) end
        end
        views[si] = picks
    end

    local bands = {}
    for _, greenVal in ipairs(ns.GROUPS) do
        local matchRef = 0
        for si = 1, #specs do
            local pkVal = views[si][greenVal.key]
            if pkVal and #pkVal > matchRef then matchRef = #pkVal end
        end
        if matchRef > 0 then bands[#bands + 1] = { group = greenVal, count = matchRef } end
    end

    self.views, self.bands = views, bands
    self.stats.candidates, self.stats.ready, self.stats.pending = cand, ready, pending
    self.stats.skipped = skipped
    return pending
end

local hasQuestDone = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
function GearScoringEngine.resolveQuestDone(qid)
    local entryValue = qdone[qid]
    if entryValue == nil then
        entryValue = false
        if hasQuestDone then
            local isCallOk, rowEntry = pcall(hasQuestDone, qid)
            entryValue = isCallOk and rowEntry and true or false
        end
        qdone[qid] = entryValue
    end
    return entryValue
end

function GearScoringEngine.resolveSrcAllowed(sourceData)
    local entryKey = sourceData.kind
    if entryKey == "craft" then return savedDB.crafting and true or false end
    if savedDB.sourcedOnly and (entryKey == "unknown" or (sourceData.chance and sourceData.chance < (savedDB.minChance or 0))) then return false end
    if entryKey == "unknown" then return savedDB.newItems and true or false end
    if entryKey == "quest" then return savedDB.quests and true or false end   

    if sourceData.chance and sourceData.chance < (savedDB.minChance or 0) then return savedDB.auction and true or false end
    return true
end
ns.IsDropSourceCategoryAllowed = GearScoringEngine.resolveSrcAllowed
ns.searchText = ""

function ns:IsItemSourceAllowed(rec, id, level)
    if not level then
        local _, maxReq = self:GetLevelFilterRange()
        level = math.min(UnitLevel("player") or maxReq, maxReq)
    end
    local enabled = false
    for _, stateFlag in ipairs(rec.src) do
        if GearScoringEngine.resolveSrcAllowed(stateFlag) then
            enabled = true
            if stateFlag.kind ~= "quest" or GearScoringEngine.resolveQuestMinLevel(stateFlag.qid, stateFlag.ml) <= level then return true end
        end
    end
    
    if enabled and id and resolveItemCountC then
        local isCallOk, totalCount = pcall(resolveItemCountC, id, false)
        return isCallOk and type(totalCount) == "number" and totalCount > 0
    end
    return false
end

local titleRequested = {}
function ns:QuestTitle(stateFlag)
    
    if L["요구 레벨"] ~= "요구 레벨" then
        if stateFlag.titleEn then return stateFlag.titleEn end
        if stateFlag.inst and not stateFlag.inst:find("[\128-\255]") then return stateFlag.inst end
    end
    local apiInfo = GearScoringEngine.resolveQuestInfo(stateFlag.qid)
    if L["요구 레벨"] == "요구 레벨" and apiInfo and type(apiInfo.title) == "string" and apiInfo.title:find("[\128-\255]") then
        return apiInfo.title
    end
    local resolvedValue
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local isCallOk, rowEntry = pcall(C_QuestLog.GetTitleForQuestID, stateFlag.qid)
        if isCallOk and type(rowEntry) == "string" and rowEntry ~= "" then resolvedValue = rowEntry end
    end
    if not resolvedValue then
        if not titleRequested[stateFlag.qid] and C_QuestLog and C_QuestLog.RequestLoadQuestByID then
            titleRequested[stateFlag.qid] = true
            pcall(C_QuestLog.RequestLoadQuestByID, stateFlag.qid)
        end
        resolvedValue = stateFlag.inst
    end
    return resolvedValue
end

local KIND_PRIORITY = { drop = 1, quest = 2, craft = 3, vendor = 4 }

function ns:PrimarySource(rec)
    local best, bestP
    for _, stateFlag in ipairs(rec.src) do
        if GearScoringEngine.resolveSrcAllowed(stateFlag) then
            local anchorTarget = KIND_PRIORITY[stateFlag.kind] or 4
            if not bestP or anchorTarget < bestP then best, bestP = stateFlag, anchorTarget end
        end
    end
    return best
end

function GearScoringEngine.hasKorean() return L["요구 레벨"] == "요구 레벨" end

local npcAsked = {}
function GearScoringEngine.resolveNpcName(id)
    if type(id) ~= "number" or id <= 0 then return nil end
    local lookupCache = savedDB and savedDB.npcNames
    if lookupCache and lookupCache[id] then return lookupCache[id] end
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil end
    local isCallOk, payloadData = pcall(C_TooltipInfo.GetHyperlink, ("unit:Creature-0-0-0-0-%d-0000000000"):format(id))
    local line = isCallOk and type(payloadData) == "table" and payloadData.lines and payloadData.lines[1]
    local name = line and line.leftText
    if type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then
        if savedDB then savedDB.npcNames = savedDB.npcNames or {}; savedDB.npcNames[id] = name end
        return name
    end
    npcAsked[id] = true
    return nil
end

function GearScoringEngine.locInst(name)
    if not name then return "?" end
    if GearScoringEngine.hasKorean() then
        local koVal = (ns.NamesKO and ns.NamesKO.zone[name]) or (ns.ItemSources and ns.ItemSources.names and ns.ItemSources.names[name])
        if koVal then return koVal end
    end
    return L[name]
end
function GearScoringEngine.locBoss(boss, npc)
    if not boss then return "?" end
    local base, nodeEntry = boss:match("^(.-) 외 (%d+)$")
    local name = base or boss
    if GearScoringEngine.hasKorean() then
        local koVal = (ns.NamesKO and ns.NamesKO.boss[name]) or (ns.ItemSources and ns.ItemSources.names and ns.ItemSources.names[name]) or (npc and GearScoringEngine.resolveNpcName(npc))
        if koVal then name = koVal end
    end
    if base then name = name .. string.format(L[" 외 %d"], tonumber(nodeEntry)) end
    local chest = name:match("^상자: (.+)$")
    if chest then name = L["상자: "] .. chest end
    return name
end
ns.GetLocalizedInstanceName, ns.GetLocalizedBossName = GearScoringEngine.locInst, GearScoringEngine.locBoss

function ns:FormatCompactDropSource(rec, id)
    local stateFlag = self:PrimarySource(rec)
    if not stateFlag then
        local est = id and self:EstimateSource(id)
        return est and (L["추정: "] .. est.short) or "?"
    end
    if stateFlag.kind == "unknown" then
        local est = id and self:EstimateSource(id)
        if est then return L["추정: "] .. est.short end
        return L["출처 불명 (신규)"]
    end
    if stateFlag.kind == "craft" then return L["제작:"] .. GearScoringEngine.locInst(stateFlag.inst) end
    if stateFlag.kind == "quest" then return L["퀘스트:"] .. self:QuestTitle(stateFlag) end
    if stateFlag.kind == "vendor" then return L["상인:"] .. GearScoringEngine.locBoss(stateFlag.boss or "?", stateFlag.creature) end
    if stateFlag.chance and stateFlag.chance < (savedDB.minChance or 0) then return L["월드 드랍"] end
    return GearScoringEngine.locInst(stateFlag.inst)
end

function ns:FormatDetailedDropSource(stateFlag)
    local displayText = self:FormatPrimaryDropSource(stateFlag)
    if stateFlag.learned then displayText = displayText .. L[" (직접 확인)"] end
    return displayText
end
function ns:FormatPrimaryDropSource(stateFlag)
    if stateFlag.kind == "unknown" then return L["획득처 불명 (Forever 신규 아이템)"] end
    if stateFlag.kind == "craft" then
        local resolvedValue = L["제작: "] .. GearScoringEngine.locInst(stateFlag.inst)
        if stateFlag.boss == "도안 필요" then resolvedValue = resolvedValue .. L[" [도안 필요]"] end
        if stateFlag.skill and stateFlag.skill > 0 then resolvedValue = resolvedValue .. L[" (숙련 "] .. stateFlag.skill .. ")" end
        return resolvedValue
    elseif stateFlag.kind == "quest" then
        local resolvedValue = L["퀘스트: "] .. self:QuestTitle(stateFlag) .. " (Lv." .. (stateFlag.ql or "?")
        local minimum = GearScoringEngine.resolveQuestMinLevel(stateFlag.qid, stateFlag.ml)
        if minimum > 0 then resolvedValue = resolvedValue .. L[", 수락 Lv."] .. minimum end
        return resolvedValue .. ") · " .. (stateFlag.choice and L["선택 보상"] or L["확정 보상"])
    end
    if stateFlag.kind == "vendor" then
        return L["상인: "] .. GearScoringEngine.locBoss(stateFlag.boss or "?", stateFlag.creature) .. " (" .. GearScoringEngine.locInst(stateFlag.inst) .. ")"
    end
    if stateFlag.chance and stateFlag.chance < (savedDB.minChance or 0) then
        return string.format(L["월드 드랍 - 잡몹 (%.3f%%)"], stateFlag.chance)
    end
    local resolvedValue = GearScoringEngine.locInst(stateFlag.inst) .. ((stateFlag.boss and stateFlag.boss ~= "") and (" - " .. GearScoringEngine.locBoss(stateFlag.boss, stateFlag.creature)) or "")
    if stateFlag.chance then resolvedValue = resolvedValue .. string.format(" (%.1f%%)", stateFlag.chance) end
    return resolvedValue
end

local EST_WINDOW = 3
local EST_WIDE = 25
local EST_KIND = { drop = 1, quest = 2, vendor = 3, craft = 4 }
function GearScoringEngine.resolveKnownSource(rec)
    local best, bpVal
    for _, stateFlag in ipairs(rec.src) do
        local anchorTarget = EST_KIND[stateFlag.kind]
        if anchorTarget and (not bpVal or anchorTarget < bpVal) then best, bpVal = stateFlag, anchorTarget end
    end
    return best
end
function ns:EstimateSource(id)
    if type(id) ~= "number" or self.indexState ~= "done" then return nil end
    local known = self.knownIDs
    if not known then
        known = {}
        for kid, rec in pairs(self.index) do
            if rec and GearScoringEngine.resolveKnownSource(rec) then known[kid] = true end
        end
        self.knownIDs = known
    end
    if known[id] then return nil end
    local best, bestD
    for dataEntry = 1, EST_WINDOW do
        for _, cand in ipairs({ id - dataEntry, id + dataEntry }) do
            if not best and known[cand] then best, bestD = cand, dataEntry end
        end
        if best then break end
    end
    if not best then
        
        local kinds, insts, nodeEntry, nearest, ndVal = {}, {}, 0, nil, nil
        for dataEntry = 1, EST_WIDE do
            for _, cand in ipairs({ id - dataEntry, id + dataEntry }) do
                if known[cand] then
                    local optionRef = GearScoringEngine.resolveKnownSource(self.index[cand])
                    nodeEntry = nodeEntry + 1
                    kinds[optionRef.kind] = true
                    insts[optionRef.inst or "?"] = true
                    if not nearest then nearest, ndVal = cand, dataEntry end
                end
            end
        end
        if nodeEntry < 2 then return nil end
        local kind, nkVal = nil, 0
        for entryKey in pairs(kinds) do kind = entryKey; nkVal = nkVal + 1 end
        if nkVal ~= 1 then return nil end
        local inst, niVal = nil, 0
        for entryKey in pairs(insts) do inst = entryKey; niVal = niVal + 1 end
        local extractSafeTooltipText
        if kind == "quest" then extractSafeTooltipText = L["퀘스트 보상"]
        elseif kind == "vendor" then extractSafeTooltipText = L["상인 판매"]
        elseif kind == "craft" then extractSafeTooltipText = L["제작"]
        elseif niVal == 1 then extractSafeTooltipText = GearScoringEngine.locInst(inst) .. L[" 드랍"]
        else return nil end
        return { short = extractSafeTooltipText, long = extractSafeTooltipText, near = nearest, dist = ndVal, sure = false, wide = true }
    end
    local stateFlag = GearScoringEngine.resolveKnownSource(self.index[best])
    local short, long
    if stateFlag.kind == "drop" then
        short = GearScoringEngine.locInst(stateFlag.inst)
        long = GearScoringEngine.locInst(stateFlag.inst) .. ((stateFlag.boss and stateFlag.boss ~= "" and stateFlag.boss ~= "?") and (" - " .. GearScoringEngine.locBoss(stateFlag.boss, stateFlag.creature)) or "")
    elseif stateFlag.kind == "quest" then
        short = L["퀘스트:"] .. self:QuestTitle(stateFlag)
        long = L["퀘스트: "] .. self:QuestTitle(stateFlag) .. L[" 근처 퀘스트"]
    elseif stateFlag.kind == "vendor" then
        short = L["상인:"] .. GearScoringEngine.locBoss(stateFlag.boss or "?", stateFlag.creature)
        long = L["상인: "] .. GearScoringEngine.locBoss(stateFlag.boss or "?", stateFlag.creature) .. " (" .. GearScoringEngine.locInst(stateFlag.inst) .. ")"
    else
        short = L["제작:"] .. GearScoringEngine.locInst(stateFlag.inst)
        long = L["제작: "] .. GearScoringEngine.locInst(stateFlag.inst)
    end
    
    local sure = false
    for dataEntry = 1, EST_WINDOW * 2 do
        local other = (best < id) and (id + dataEntry) or (id - dataEntry)
        if known[other] then
            local optionRef = GearScoringEngine.resolveKnownSource(self.index[other])
            sure = (optionRef.kind == stateFlag.kind and optionRef.inst == stateFlag.inst)
            break
        end
    end
    return { short = short, long = long, near = best, dist = bestD, sure = sure }
end

function GearScoringEngine.resolveItemNameOf(id)
    local nodeEntry
    if C_Item and C_Item.GetItemNameByID then
        local isCallOk, rowEntry = pcall(C_Item.GetItemNameByID, id)
        if isCallOk and type(rowEntry) == "string" then nodeEntry = rowEntry end
    end
    if not nodeEntry then
        local isCallOk, rowEntry = pcall(resolveItemInfoC, id)
        if isCallOk and type(rowEntry) == "string" then nodeEntry = rowEntry end
    end
    if not nodeEntry then
        local nmVal = ns.CraftData and ns.CraftData.names and ns.CraftData.names[id]
        if nmVal then nodeEntry = (L["요구 레벨"] ~= "요구 레벨") and nmVal[2] or nmVal[1] end
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    end
    return nodeEntry or ("#" .. id)
end
function ns:CraftDetailLines(id)
    local apiInfo = ns.CraftData and ns.CraftData.info and ns.CraftData.info[id]
    if not apiInfo then return nil end
    local outputList = {}
    if apiInfo.reag and #apiInfo.reag > 0 then
        local parts = {}
        for _, rowEntry in ipairs(apiInfo.reag) do
            parts[#parts + 1] = GearScoringEngine.resolveItemNameOf(rowEntry[1]) .. ((rowEntry[2] or 1) > 1 and (" x" .. rowEntry[2]) or "")
        end
        outputList[#outputList + 1] = L["  재료: "] .. table.concat(parts, ", ")
    end
    local english = L["요구 레벨"] ~= "요구 레벨"
    local sourceData = english and apiInfo.srcEn or apiInfo.src
    if sourceData and sourceData ~= "" then outputList[#outputList + 1] = L["  배우는 곳: "] .. sourceData end
    return outputList
end

function ns:BuildFullSourceDescription(rec)
    local stateFlag = self:PrimarySource(rec)
    if not stateFlag then return L["출처 불명"] end
    local nodeEntry = 0
    for _, optionRef in ipairs(rec.src) do if GearScoringEngine.resolveSrcAllowed(optionRef) then nodeEntry = nodeEntry + 1 end end
    local displayText = self:FormatDetailedDropSource(stateFlag)
    if nodeEntry > 1 then displayText = displayText .. string.format(L[" 외 %d곳"], nodeEntry - 1) end
    return displayText
end

-----------------------------------------------------------------------------
-- Schedule Refresh
-----------------------------------------------------------------------------
local syncScheduled = false
local syncDue = 0
local syncToken = 0
local lastPending, stall = -1, 0

function ns:ScheduleRefresh(delay)
    delay = delay or 0.25
    local targetKey = GetTime() + delay
    if syncScheduled and targetKey >= syncDue - 0.05 then return end
    syncScheduled = true
    syncDue = targetKey
    syncToken = syncToken + 1
    local myToken = syncToken
    C_Timer.After(delay, function()
        if myToken ~= syncToken then return end
        syncScheduled = false
        ns:Refresh()
    end)
end

local uiScheduled = false
function ns:ScheduleUIUpdate()
    if uiScheduled then return end
    uiScheduled = true
    C_Timer.After(0.25, function()
        uiScheduled = false
        if ns.frame and ns.frame:IsShown() and (ns.indexState == "done" or ns.indexBaseReady) and not ns.lastError then ns:UpdateUI() end
    end)
end

function ns:Prewarm()
    if not savedDB then return end
    local class = self:GetActiveClassToken()
    local rules = ns.CLASS_RULES[class]
    if not rules then return end
    local level = UnitLevel("player") or 1
    local minReq, maxReq = self:GetLevelFilterRange()
    local armorType = GearScoringEngine.resolveArmorType(rules, level)
    local dwOK = rules.dualWield and level >= (ns.DUAL_WIELD_LEVEL[class] or 99) or false
    for id, rec in pairs(self.index) do
        if rec and not rec.new and not rec.name and GearScoringEngine.isItemUsableByClass(rec, rules, armorType, dwOK) then
            if not hasCached or not hasCached(id) then
                local elVal = rec.estLvl or rec.minLvl
                if (elVal and elVal >= minReq - 8 and elVal <= maxReq + 10) or self:IsBestInSlotCandidate(id) then
                    requestUncachedItemData(id, 2)
                elseif not elVal then
                    requestUncachedItemData(id, 3)
                end
            end
        end
    end
end

function ns:Refresh(userAction)
    if not (self.frame and self.frame:IsShown()) then return end
    if userAction then stall = 0; lastPending = -1; self.pendingStalled = false end
    self:EnsureIndex()
    if self.indexState == "idle" or (self.indexState == "running" and not self.indexBaseReady) then
        self:UpdateUI()
        return
    end
    if self.indexState == "done" or self.indexBaseReady then
        self.lastError = nil
        local isCallOk, evalResult = xpcall(function() return self:EvaluateAllSlotCandidates() end, function(e)
            return tostring(e) .. "\n" .. (debugstack and debugstack(2, 6, 0) or "")
        end)
        if not isCallOk then
            self.lastError = evalResult
            if self.lastErrorPrinted ~= evalResult then
                self.lastErrorPrinted = evalResult
                GearScoringEngine.printAddonChatMessage(L["|cffff5555계산 중 오류:|r "] .. tostring(evalResult))
            end
            self:UpdateUI()
            return
        end
        local pending = evalResult or 0
        if pending > 0 then
            if pending >= lastPending and lastPending >= 0 then stall = stall + 1 else stall = 0 end
            lastPending = pending
            self.pendingStalled = stall >= 8
            if stall < 8 then self:ScheduleRefresh(0.8) end
        else
            lastPending, stall = -1, 0
            self.pendingStalled = false
        end
    end
    self:UpdateUI()
end

function ns:ForceRefresh()
    scoreCache = {}
    wipe(statsCache)
    wipe(statsLinks)
    wipe(allowCache)
    wipe(requested)
    wipe(queueHi)
    wipe(queue)
    wipe(queueLo)
    wipe(queueSearch)
    wipe(queued)
    queueHiHead, queueHead, queueLoHead, searchHead = 1, 1, 1, 1
    wipe(attempts)
    wipe(dead)
    if self.indexState == "empty" then self:ResetIndex() end
    self:Refresh(true)
end

local PulseAnimationDriver = CreateFrame("Frame")
local elapsedAcc = 0
local baseNotified = false
PulseAnimationDriver:SetScript("OnUpdate", function(_, dt)
    
    if indexCo and ns.indexState == "running" then
        budgetStart = debugprofilestop()
        local isCallOk, errorObj = coroutine.resume(indexCo)
        if not isCallOk then
            ns.indexState = "empty"
            indexCo = nil
            baseNotified = false
            GearScoringEngine.printAddonChatMessage(L["데이터 읽기 오류: "] .. tostring(errorObj))
            ns:Refresh()
        elseif coroutine.status(indexCo) == "dead" then
            indexCo = nil
            baseNotified = false
            ns.indexState = (ns.indexStats.items > 0) and "done" or "empty"
            if ns.frame and ns.frame:IsShown() then
                local okR, errR = pcall(ns.Refresh, ns)
                if not okR then ns.lastError = tostring(errR); GearScoringEngine.printAddonChatMessage(L["|cffff5555화면 갱신 오류:|r "] .. tostring(errR)) end
            elseif ns.indexState == "done" then
                pcall(ns.Prewarm, ns)
            end
        else
            if ns.indexBaseReady and not baseNotified then
                baseNotified = true
                if ns.frame and ns.frame:IsShown() then
                    pcall(ns.Refresh, ns)
                else
                    pcall(ns.Prewarm, ns)
                end
            elseif ns.frame and ns.frame:IsShown() and ns.UpdateProgress then
                ns:UpdateProgress()
            end
        end
    end
    
    elapsedAcc = elapsedAcc + dt
    local activeLoad = ns.fastLoad or (ns.frame and ns.frame:IsShown() and (ns.stats.pending or 0) > 0)
    if elapsedAcc >= (activeLoad and 0.025 or 0.05) then
        elapsedAcc = 0
        local limit = activeLoad and 80 or 40
        local sent = 0
        while sent < limit do
            local id
            id, searchHead = GearScoringEngine.popQueue(queueSearch, searchHead, 1)
            if not id then id, queueHiHead = GearScoringEngine.popQueue(queueHi, queueHiHead, 2) end
            if not id then id, queueHead = GearScoringEngine.popQueue(queue, queueHead, 3) end
            if not id then id, queueLoHead = GearScoringEngine.popQueue(queueLo, queueLoHead, 4) end
            if not id then break end
            if not dead[id] and not (hasCached and hasCached(id)) then
                sent = sent + 1
                requested[id] = GetTime()
                attempts[id] = (attempts[id] or 0) + 1
                if C_Item and C_Item.RequestLoadItemDataByID then
                    C_Item.RequestLoadItemDataByID(id)
                else
                    resolveItemInfoC(id)
                end
            end
        end
    end
end)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

pcall(eventFrame.RegisterEvent, eventFrame, "QUEST_TURNED_IN")
pcall(eventFrame.RegisterEvent, eventFrame, "QUEST_DATA_LOAD_RESULT")
pcall(eventFrame.RegisterEvent, eventFrame, "BAG_UPDATE_DELAYED")
eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then GearScoringEngine.bootstrapDB() end
    elseif event == "PLAYER_LOGIN" then
        if ns.UpdateLauncher then pcall(ns.UpdateLauncher, ns) end
        if ns.RegisterOptionsPanel then pcall(ns.RegisterOptionsPanel, ns) end
        C_Timer.After(0.5, function()
            if ns.UpdateLauncher then pcall(ns.UpdateLauncher, ns) end
            if ns.indexState == "idle" then ns:EnsureIndex() end
        end)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if arg2 == true then
            dead[arg1], requested[arg1], attempts[arg1] = nil, nil, nil
            GearScoringEngine.invalidateItemCaches(arg1)
        elseif arg2 == false and requested[arg1] then dead[arg1] = true end   
        if ns.frame and ns.frame:IsShown() and ns.stats.pending > 0 then ns:ScheduleRefresh(0.25) end
        if ns.HandleItemInfoReceived then ns.HandleItemInfoReceived(arg1, arg2) end
    elseif event == "QUEST_TURNED_IN" then
        ns:ScheduleRefresh(0.8)
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        ns:ScheduleUIUpdate()
    elseif event == "PLAYER_LEVEL_UP" then
        C_Timer.After(0.5, function() ns:Refresh(true) end)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_UPDATE_DELAYED" then
        ns:ScheduleRefresh(0.3)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.indexState == "idle" or ns.indexState == "empty" then ns:Refresh(true) end
    end
end)

SLASH_EZWOWBESTGEARFINDER1 = "/ezbg"
SLASH_EZWOWBESTGEARFINDER2 = "/bgf"
SLASH_EZWOWBESTGEARFINDER3 = "/내템"
SLASH_EZWOWBESTGEARFINDER4 = "/bestgear"
SlashCmdList["EZWOWBESTGEARFINDER"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local priorityQueue = msg:match("^find%s*(.*)$") or msg:match("^검색%s*(.*)$")
    if priorityQueue then
        if ns.SearchFor then ns:SearchFor(priorityQueue) end
    elseif msg == "config" or msg == "opt" or msg == "options" or msg == "settings" or msg == "설정" then
        if ns.ToggleSettingsWindow then ns:ToggleSettingsWindow() end
    elseif msg == "debug" or msg == "diag" or msg == "진단" then
        if ns.indexState == "done" and ns.frame then ns:Refresh(true) end
        GearScoringEngine.printAddonChatMessage(string.format(L["상태=%s, 모듈=%d, 보스=%d, 장비 아이템=%d(제작 %d, 퀘스트 %d), 후보=%d, 로딩완료=%d, 대기=%d"],
            ns.indexState, ns.indexStats.modules, ns.indexStats.bosses, ns.indexStats.items, ns.indexStats.craft or 0, ns.indexStats.quest or 0,
            ns.stats.candidates, ns.stats.ready, ns.stats.pending))
        GearScoringEngine.printAddonChatMessage(L["아이템 처리 오류 수: "] .. tostring(ns.itemErrors or 0) .. (ns.firstItemError and (L[" / 첫 오류: "] .. ns.firstItemError) or ""))
        if ns.slotError then GearScoringEngine.printAddonChatMessage(L["슬롯 처리 오류: "] .. ns.slotError) end
        if ns.lastError then GearScoringEngine.printAddonChatMessage(L["마지막 오류: "] .. ns.lastError) end
        local dataEntry = ns.GearDB or {}
        local sourceItems, sourceCount = 0, 0
        if type(dataEntry.sources) == "table" then
            for _, sourceData in pairs(dataEntry.sources) do sourceItems = sourceItems + 1; if type(sourceData) == "table" then sourceCount = sourceCount + #sourceData end end
        end
        GearScoringEngine.printAddonChatMessage(L["신규 아이템(출처 불명): "] .. tostring(ns.indexStats.new or 0))
        GearScoringEngine.printAddonChatMessage(L["기본 데이터: 아이템="] .. sourceItems .. L[", 출처="] .. sourceCount .. L[", 버전="] .. tostring(dataEntry.version or "?"))
    elseif msg:match("^why%s+%d+$") or msg:match("^왜%s+%d+$") then
        local id = tonumber(msg:match("%d+"))
        local rec = ns.index and ns.index[id]
        local function platformHelper(resolvedValue) GearScoringEngine.printAddonChatMessage("[why " .. id .. "] " .. resolvedValue) end
        if not rec then platformHelper("not in index (not equippable, or not in data)"); return end
        local _, class = UnitClass("player")
        local rules = ns.CLASS_RULES[class]
        local level = UnitLevel("player")
        local dwVal = rules.dualWield and level >= (ns.DUAL_WIELD_LEVEL[class] or 99) or false
        local minReq, maxReq = ns:GetLevelFilterRange()
        platformHelper(("loc=%s class=%s sub=%s new=%s"):format(tostring(rec.loc), tostring(rec.classID), tostring(rec.subID), tostring(rec.new)))
        for _, srVal in ipairs(rec.src) do
            platformHelper(("src kind=%s inst=%s allowed=%s%s"):format(tostring(srVal.kind), tostring(srVal.inst), tostring(GearScoringEngine.resolveSrcAllowed(srVal)),
                srVal.qid and (" qid=" .. srVal.qid .. " done=" .. tostring(GearScoringEngine.resolveQuestDone(srVal.qid))) or ""))
        end
        platformHelper("sourceAllowed=" .. tostring(ns:IsItemSourceAllowed(rec, id)) .. " usable=" .. tostring(GearScoringEngine.isItemUsableByClass(rec, rules, GearScoringEngine.resolveArmorType(rules, level), dwVal)))
        local name, _, quality, ilvl, req = resolveItemInfoC(id)
        platformHelper(("name=%s quality=%s ilvl=%s req=%s inRange=%s range=%d-%d"):format(tostring(name), tostring(quality), tostring(ilvl), tostring(req), tostring(name and GearScoringEngine.inRange(req, minReq, maxReq, ilvl, ns:IsBestInSlotCandidate(id))), minReq, maxReq))
        do
            local _, link = resolveItemInfoC(id)
            local stateEntry = link and GearScoringEngine.resolveStats(link)
            if type(stateEntry) == "table" then
                local parts = {}
                for entryKey, entryValue in pairs(stateEntry) do parts[#parts + 1] = entryKey:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", "") .. "=" .. tostring(entryValue) end
                table.sort(parts)
                platformHelper("stats: " .. (#parts > 0 and table.concat(parts, ", ") or "(none)"))
                for _, spawnCoord in ipairs(ns:GetSpecList()) do
                    platformHelper(("score[%s]=%.1f"):format(spawnCoord.nameKo or spawnCoord.name, GearScoringEngine.evaluateItemRoleScore(link, ilvl, spawnCoord.w)))
                end
            else
                platformHelper("stats: not available (" .. tostring(link and "no stats" or "not loaded") .. ")")
            end
        end
        do
            local tsVal = ns.TooltipStats(id)
            if tsVal then
                local parts = {}
                for entryKey, entryValue in pairs(tsVal) do parts[#parts + 1] = entryKey:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", "") .. "=" .. entryValue end
                table.sort(parts)
                platformHelper("tooltip stats: " .. (#parts > 0 and table.concat(parts, ", ") or "(none read)"))
            else
                platformHelper("tooltip stats: tooltip not readable")
            end
        end
        platformHelper("qualityAllowed=" .. tostring(quality and savedDB.qual[quality]) .. " junkName=" .. tostring(name and GearScoringEngine.hasJunkName(name) and true or false))
        platformHelper(("abilityRelic=%s useLine=%s itemSpell=%s"):format(tostring(GearScoringEngine.hasAbilityRelic(id, rec)), tostring(GearScoringEngine.containsUseLine(id)), tostring(resolveItemSpellC and select(1, resolveItemSpellC(id)))))
    elseif msg == "reset" or msg == "초기화" then
        savedDB.point = nil
        if ns.frame then ns.frame:ClearAllPoints() ns.frame:SetPoint("CENTER") end
        ns:ResetLauncher()
        GearScoringEngine.printAddonChatMessage(L["창 위치를 초기화했습니다."])
    elseif msg:match("^%d+%s*[~%-%s]%s*%d+$") then
        local alphaVal, buttonWidget = msg:match("^(%d+)%s*[~%-%s]%s*(%d+)$")
        local lo, hi = ns:SetLevelFilterRange(alphaVal, buttonWidget)
        GearScoringEngine.printAddonChatMessage(string.format(L["요구 레벨 범위: %d ~ %d"], lo, hi))
        if ns.frame and ns.frame:IsShown() then ns:ForceRefresh() else ns:ToggleMainGearWindow() end
    elseif msg == "craft" or msg == "crafting" or msg == "제작" then
        savedDB.crafting = not savedDB.crafting
        GearScoringEngine.printAddonChatMessage(L["제작템 포함: "] .. (savedDB.crafting and L["켜짐"] or L["꺼짐"]))
        ns:Refresh(true)
    elseif msg == "quest" or msg == "quests" or msg == "퀘스트" then
        savedDB.quests = not savedDB.quests
        GearScoringEngine.printAddonChatMessage(L["퀘스트 보상 포함: "] .. (savedDB.quests and L["켜짐"] or L["꺼짐"]))
        ns:Refresh(true)
    elseif msg:match("^확률%s*[%d%.]+$") or msg:match("^chance%s*[%d%.]+$") then
        savedDB.minChance = tonumber(msg:match("([%d%.]+)$")) or 1
        GearScoringEngine.printAddonChatMessage(string.format(L["최소 드랍률: %.1f%%"], savedDB.minChance))
        ns:Refresh(true)
    elseif msg:match("^등급") or msg:match("^quality") then
        local want = { ["하"] = 0, ["일"] = 1, ["녹"] = 2, ["청"] = 3, ["보"] = 4, ["주"] = 5 }
        local any = false
        savedDB.qual = {}
        for chVal, priorityQueue in pairs(want) do if msg:find(chVal, 1, true) then savedDB.qual[priorityQueue] = true; any = true end end
        for word, priorityQueue in pairs({ gray = 0, grey = 0, white = 1, green = 2, blue = 3, rare = 3, epic = 4, purple = 4, legendary = 5, orange = 5 }) do
            if msg:find(word, 1, true) then savedDB.qual[priorityQueue] = true; any = true end
        end
        if not any then savedDB.qual = { [2] = true, [3] = true, [4] = true } end
        GearScoringEngine.printAddonChatMessage(L["등급 필터를 바꿨습니다. 예: /ezbg 등급 녹청"])
        ns:Refresh(true)
    elseif msg == "슬롯" or msg == "slot" then
        if not ns.funnel then GearScoringEngine.printAddonChatMessage(L["먼저 창을 열어 검색하세요."]) else
            for _, greenVal in ipairs(ns.GROUPS) do
                local windowFrame = ns.funnel[greenVal.key]
                if windowFrame then GearScoringEngine.printAddonChatMessage(string.format(L["%s: 후보 %d개, 착용 점수 %.1f, 최고 후보 점수 %.1f (id %s)"], tostring(greenVal.name or greenVal.key), windowFrame.cand, windowFrame.base, windowFrame.top, tostring(windowFrame.topId))) end
            end
        end
    elseif msg == "월드드랍" or msg == "경매장" or msg == "auction" or msg == "worlddrop" then
        savedDB.auction = not savedDB.auction
        GearScoringEngine.printAddonChatMessage(L["월드 드랍(저확률 잡몹 드랍) 포함: "] .. (savedDB.auction and L["켜짐"] or L["꺼짐"]))
        ns:Refresh(true)
    elseif msg:match("^lang") or msg:match("^언어") then
        local alphaVal = msg:match("^%S+%s+(%S+)")
        if not alphaVal then
            GearScoringEngine.printAddonChatMessage("/ezbg lang auto | ko | en | de | fr | es | ru | cn | tw")
            return
        end
        if alphaVal == "auto" or alphaVal == "자동" then
            savedDB.lang = nil
        else
            local normalizeFullwidthCodepoint = ns.NormalizeLang and ns.NormalizeLang(alphaVal)
            if not normalizeFullwidthCodepoint then
                GearScoringEngine.printAddonChatMessage("/ezbg lang auto | ko | en | de | fr | es | ru | cn | tw")
                return
            end
            savedDB.lang = normalizeFullwidthCodepoint
        end
        ns.SetLang(savedDB.lang)
        if ns.RelabelData then ns.RelabelData() end
        if ns.RebuildMainGearWindow then ns:RebuildMainGearWindow() end
        GearScoringEngine.printAddonChatMessage("Language: " .. (savedDB.lang or "auto") .. " (" .. (ns.GetActiveLocale and ns.GetActiveLocale() or "enUS") .. ")")
    elseif msg == "tip" or msg == "툴팁" then
        if ns.PrintTooltipDiagnostics then ns:PrintTooltipDiagnostics() end
    elseif msg == "export" or msg == "내보내기" then
        if ns.ShowLearnedExport then ns:ShowLearnedExport() end
    elseif msg == "learned" or msg == "기록" then
        GearScoringEngine.printAddonChatMessage(string.format(L["게임에서 직접 기록한 획득처: 아이템 %d개"], ns.LearnedCount and ns:LearnedCount() or 0))
    elseif msg == "icon" or msg == "아이콘" then
        savedDB.iconShown = not savedDB.iconShown
        ns:UpdateLauncher()
        GearScoringEngine.printAddonChatMessage(L["화면 아이콘: "] .. (savedDB.iconShown and L["켜짐"] or L["꺼짐"]))
    elseif msg == "new" or msg == "신규" then
        savedDB.newItems = not savedDB.newItems
        GearScoringEngine.printAddonChatMessage(L["신규 아이템(출처 불명) 포함: "] .. (savedDB.newItems and L["켜짐"] or L["꺼짐"]))
        ns:Refresh(true)
    elseif msg == "rescan" or msg == "재검색" then
        savedDB.scan = {}
        GearScoringEngine.printAddonChatMessage(L["신규 아이템을 처음부터 다시 검색합니다."])
        ns:ResetIndex()
        ns:Refresh(true)
    elseif msg == "donate" or msg == "후원" then
        ns:ShowDonate()
    elseif msg == "all" or msg == "전체" then
        GearScoringEngine.printAddonChatMessage(L["기본 데이터 범위는 추출 옵션으로 결정됩니다."])
    else
        ns:ToggleMainGearWindow()
    end
end

function ns:OpenInMapFinder(id, rec, link)
    local fn = _G.SlashCmdList and _G.SlashCmdList.EZWOWMAPFINDER
    if type(fn) ~= "function" then
        local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if loader then
            pcall(loader, "EzWoW-MapFinder")
            pcall(loader, "EzWoW_MapFinder")
        end
        fn = _G.SlashCmdList and _G.SlashCmdList.EZWOWMAPFINDER
    end
    if type(fn) ~= "function" then return false end
    local query
    local itemName = (id and resolveItemInfoC and resolveItemInfoC(id)) or (type(link) == "string" and link:match("%[(.-)%]"))
    rec = rec or (id and self.index and self.index[id])
    if rec and type(rec.src) == "table" and #rec.src > 0 then
        local stateFlag = rec.src[1]
        if stateFlag.kind == "quest" and type(stateFlag.inst) == "string" and stateFlag.inst ~= "" then
            query = "Q " .. stateFlag.inst
        elseif stateFlag.kind == "vendor" and type(stateFlag.boss) == "string" and stateFlag.boss ~= "" then
            local cleanBoss = stateFlag.boss:gsub("%s+외%s+%d+.*$", "")
            query = "N " .. cleanBoss
        elseif stateFlag.kind == "drop" and type(stateFlag.boss) == "string" and stateFlag.boss ~= "" and stateFlag.boss ~= "?" then
            local cleanBoss = stateFlag.boss:gsub("%s+외%s+%d+.*$", "")
            query = cleanBoss
        end
    end
    if not query and type(itemName) == "string" and itemName ~= "" then
        query = "I " .. itemName
    end
    if query and query ~= "" then
        pcall(fn, query)
        return true
    end
    return false
end

-----------------------------------------------------------------------------
-- Show Donate
-----------------------------------------------------------------------------
ns.DONATE_URL = "https://buymeacoffee.com/qqhrqqhr2"
local gearDonateFrame
function ns:ShowDonate()
    if not gearDonateFrame then
        local windowFrame = CreateFrame("Frame", "EzWoWBestGearFinderDonate", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        windowFrame:SetSize(380, 132)
        windowFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        ns.UIKit:ElevateModal(windowFrame, 260)
        windowFrame:EnableMouse(true)
        windowFrame:SetMovable(true)
        windowFrame:RegisterForDrag("LeftButton")
        windowFrame:SetScript("OnDragStart", windowFrame.StartMoving)
        windowFrame:SetScript("OnDragStop", windowFrame.StopMovingOrSizing)
        if windowFrame.SetBackdrop then
            ns.UIKit:ApplyBackdrop(windowFrame, 1, 1)
            windowFrame:SetBackdropColor(0.071, 0.094, 0.122, 0.97)
            windowFrame:SetBackdropBorderColor(0.945, 0.741, 0.341, 1.00)
        end

        local titleStr = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleStr:SetPoint("TOP", windowFrame, "TOP", 0, -12)
        titleStr:SetTextColor(0.945, 0.741, 0.341)
        titleStr:SetText("EzWoW - Best Gear Finder · " .. (L["후원"] or "Donate"))
        windowFrame.title = titleStr

        local desc = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOP", titleStr, "BOTTOM", 0, -8)
        desc:SetWidth(344)
        windowFrame.desc = desc

        local inputBox = CreateFrame("EditBox", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        inputBox:SetSize(340, 24)
        inputBox:SetFrameLevel(windowFrame:GetFrameLevel() + 5)
        inputBox:SetPoint("BOTTOM", windowFrame, "BOTTOM", 0, 16)
        inputBox:SetFontObject(ChatFontNormal)
        inputBox:SetTextInsets(6, 6, 0, 0)
        inputBox:SetAutoFocus(false)
        if inputBox.SetBackdrop then
            ns.UIKit:ApplyBackdrop(inputBox, 1, 1)
            inputBox:SetBackdropColor(0.047, 0.067, 0.086, 0.96)
            inputBox:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
        end
        inputBox:SetText(ns.DONATE_URL)
        inputBox:SetScript("OnEditFocusGained", function(self)
            if self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(0.945, 0.741, 0.341, 1.00)
            end
        end)
        inputBox:SetScript("OnEditFocusLost", function(self)
            if self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
            end
        end)
        inputBox:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                self:SetText(ns.DONATE_URL)
                self:HighlightText()
            end
        end)
        inputBox:SetScript("OnEscapePressed", function() windowFrame:Hide() end)
        inputBox:SetScript("OnEnterPressed", function() windowFrame:Hide() end)
        inputBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        windowFrame.eb = inputBox

        local close = CreateFrame("Button", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        close:SetSize(22, 22)
        close:SetFrameLevel(windowFrame:GetFrameLevel() + 5)
        close:SetPoint("TOPRIGHT", windowFrame, "TOPRIGHT", -6, -6)
        if close.SetBackdrop then
            ns.UIKit:ApplyBackdrop(close)
            close:SetBackdropColor(0.114, 0.157, 0.192, 0.96)
            close:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
        end
        local dismissTxt = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dismissTxt:SetPoint("CENTER", 0, 0)
        dismissTxt:SetText("X")
        dismissTxt:SetTextColor(0.655, 0.725, 0.773, 1.00)
        close:SetScript("OnEnter", function(self)
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.906, 0.486, 0.439, 1.00) end
            dismissTxt:SetTextColor(0.906, 0.486, 0.439, 1.00)
        end)
        close:SetScript("OnLeave", function(self)
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00) end
            dismissTxt:SetTextColor(0.655, 0.725, 0.773, 1.00)
        end)
        close:SetScript("OnClick", function() windowFrame:Hide() end)
        if UISpecialFrames then tinsert(UISpecialFrames, "EzWoWBestGearFinderDonate") end
        gearDonateFrame = windowFrame
    end
    gearDonateFrame.title:SetText("EzWoW - Best Gear Finder · " .. (L["후원"] or "Donate"))
    gearDonateFrame.desc:SetText(L["도움이 되셨다면 커피 한 잔으로 응원해 주세요! (Ctrl+C로 복사)"])
    ns.UIKit:ElevateModal(gearDonateFrame, 260)
    gearDonateFrame:Show()
    if gearDonateFrame.Raise then gearDonateFrame:Raise() end
    gearDonateFrame.eb:SetText(ns.DONATE_URL)
    gearDonateFrame.eb:SetFocus()
    gearDonateFrame.eb:HighlightText()
end

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
GearScoringEngine.GetActiveClassToken = ns.GetActiveClassToken
GearScoringEngine.GetActiveClassDisplayName = ns.GetActiveClassDisplayName
GearScoringEngine.GetBestInSlotRank = ns.GetBestInSlotRank
GearScoringEngine.GetCharacterProfileKey = ns.GetCharacterProfileKey
GearScoringEngine.ResetLevelFilterRange = ns.ResetLevelFilterRange
GearScoringEngine.EvaluateAllSlotCandidates = ns.EvaluateAllSlotCandidates
GearScoringEngine.FormatDetailedDropSource = ns.FormatDetailedDropSource
GearScoringEngine.FormatPrimaryDropSource = ns.FormatPrimaryDropSource
GearScoringEngine.GetLevelFilterRange = ns.GetLevelFilterRange
GearScoringEngine.IsBestInSlotCandidate = ns.IsBestInSlotCandidate
GearScoringEngine.GetLocalizedBossName = ns.GetLocalizedBossName
GearScoringEngine.SetLevelFilterRange = ns.SetLevelFilterRange
GearScoringEngine.FormatCompactDropSource = ns.FormatCompactDropSource
GearScoringEngine.IsItemSourceAllowed = ns.IsItemSourceAllowed
GearScoringEngine.BuildFullSourceDescription = ns.BuildFullSourceDescription
GearScoringEngine.IsDropSourceCategoryAllowed = ns.IsDropSourceCategoryAllowed
GearScoringEngine.FormatStatComparisonDelta = ns.FormatStatComparisonDelta
GearScoringEngine.IsItemUsableByActiveClass = ns.IsItemUsableByActiveClass
