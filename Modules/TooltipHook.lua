--===========================================================================
-- EzWoW - Best Gear Finder
-- Modules/TooltipHook.lua : Item Tooltip Stat Upgrade & Drop Source Hook
--===========================================================================
local ADDON, ns = ...

-- The "EzWoW - ..." name line at the end of tooltip additions is drawn small.
-- Shared by the EzWoW addons: the first one loaded sets it up.
if not (_G.EzWoWTooltipTagSizer and _G.EzWoWTooltipTagSizer.version == 3) then
    local sizer = {}
    sizer.version = 3
    _G.EzWoWTooltipTagSizer = sizer
    local smallFont
    local original = setmetatable({}, { __mode = "k" })   -- font string -> its own font object
    local function tagFont()
        if not smallFont and CreateFont then
            smallFont = _G.EzWoWTooltipTagFont or CreateFont("EzWoWTooltipTagFont")
            smallFont:CopyFontObject(GameTooltipTextSmall or GameTooltipText)
            local path, _, flags = smallFont:GetFont()
            if path then smallFont:SetFont(path, 8, flags) end
        end
        return smallFont
    end
    local function isTag(text)
        if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return false end
        return text:find("^EzWoW %- ") ~= nil
    end
    local function fit(fs, tag)
        if not fs then return end
        if tag then
            if not original[fs] then original[fs] = fs:GetFontObject() or GameTooltipText end
            if tagFont() then fs:SetFontObject(smallFont) end
            fs:SetTextColor(0.5, 0.5, 0.5)
        elseif original[fs] then
            fs:SetFontObject(original[fs])
            original[fs] = nil
        end
    end
    function sizer.Refit(tip)
        local name = tip and tip.GetName and tip:GetName()
        if type(name) ~= "string" then return end
        local ok, count = pcall(tip.NumLines, tip)
        if not ok or type(count) ~= "number" or (issecretvalue and issecretvalue(count)) then return end
        for i = 1, count do
            local right = _G[name .. "TextRight" .. i]
            if right then fit(right, isTag(right:GetText())) end
            -- line 1 is the tooltip's title: a left "EzWoW - ..." there stays big
            local left = _G[name .. "TextLeft" .. i]
            if left then fit(left, i > 1 and isTag(left:GetText())) end
        end
    end
    local function restore(tip)
        local name = tip and tip.GetName and tip:GetName()
        if type(name) ~= "string" then return end
        local rightPrefix, leftPrefix = name .. "TextRight", name .. "TextLeft"
        for fs, font in pairs(original) do
            local fsName = fs.GetName and fs:GetName()
            if type(fsName) == "string" and (fsName:find(rightPrefix, 1, true) == 1 or fsName:find(leftPrefix, 1, true) == 1) then
                fs:SetFontObject(font)
                original[fs] = nil
            end
        end
    end
    for _, tip in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
        if tip then
            pcall(hooksecurefunc, tip, "Show", function(self) pcall(sizer.Refit, self) end)
            pcall(tip.HookScript, tip, "OnTooltipCleared", function(self) pcall(restore, self) end)
        end
    end
end
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local TooltipUpgradeAdvisor = ns.TooltipUpgradeAdvisor or {}
ns.TooltipUpgradeAdvisor = TooltipUpgradeAdvisor
local L = ns.L

local MAX_LINES = 5

function ns:SuppressItemTooltip(v) ns.tipSuppressed = v end

function TooltipUpgradeAdvisor.resolveItemIDFrom(tt, data)
    local entityID = data and data.id
    if issecretvalue and issecretvalue(entityID) then return nil end
    if type(entityID) == "number" then return entityID end
    if tt and TooltipUtil and TooltipUtil.GetDisplayedItem then
        local isCallOk, _, link, itemID = pcall(TooltipUtil.GetDisplayedItem, tt)
        if isCallOk and type(itemID) == "number" then return itemID end
        if isCallOk and type(link) == "string" then
            local nodeEntry = tonumber(link:match("item:(%d+)"))
            if nodeEntry then return nodeEntry end
        end
    end
    if tt and tt.GetItem then
        local isCallOk, _, link = pcall(tt.GetItem, tt)
        if isCallOk and type(link) == "string" then
            local nodeEntry = tonumber(link:match("item:(%d+)"))
            if nodeEntry then return nodeEntry end
        end
    end
end

local resolveItemInfoInstantC = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

function TooltipUpgradeAdvisor.hasGear(entityID)
    local isCallOk, _, _, _, localeTbl = pcall(resolveItemInfoInstantC, entityID)
    return isCallOk and type(localeTbl) == "string" and ns.EQUIP_LOCS and ns.EQUIP_LOCS[localeTbl] and true or false
end

function ns:AddEstimateLines(tt, entityID)
    if not TooltipUpgradeAdvisor.hasGear(entityID) then return false end
    local est = entityID and ns:EstimateSource(entityID)
    if not est then return false end
    tt:AddLine(L["추정 획득처: "] .. est.long, 0.75, 0.75, 0.75, true)
    if est.wide then
        tt:AddLine(string.format(L["(번호대 #%d 근처 아이템들이 모두 이 종류 · 구체적인 곳은 모름)"], est.near), 0.55, 0.55, 0.55, true)
    else
        tt:AddLine(string.format(L["(번호가 가까운 아이템 #%d 기준%s)"], est.near, est.sure and L[", 앞뒤 모두 같은 곳"] or ""), 0.55, 0.55, 0.55, true)
    end
    return true
end

-- Only the game's visible item tooltips get lines; hidden scan tooltips (this addon's
-- or any other addon's) are never touched.
local ALLOWED_TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }
function TooltipUpgradeAdvisor.isAllowedTooltip(tt)
    if type(tt) ~= "table" then return false end
    for _, name in ipairs(ALLOWED_TOOLTIPS) do
        if _G[name] == tt then return true end
    end
    return false
end

-----------------------------------------------------------------------------
-- Equipment comparison on this addon's list rows
-----------------------------------------------------------------------------
-- Comparing with equipped gear without Shift now belongs to EzWoW-Tooltip, which turns on the
-- game's own setting for every item tooltip (these rows included). Only while it is not loaded
-- do the rows open the comparison themselves.
ns.EQUIP_COMPARE_OWNER = "EzWoW-Tooltip"
function ns:IsAddOnLoadedSafe(name)
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    if type(isLoaded) ~= "function" then return false end
    local ok, loadedOrLoading, loaded = pcall(isLoaded, name)
    return ok and (loadedOrLoading or loaded) and true or false
end
function ns:ShowRowComparison(tt)
    if ns:IsAddOnLoadedSafe(ns.EQUIP_COMPARE_OWNER) then return end
    if (ns.db and ns.db.showEquipCompare ~= false) or (IsShiftKeyDown and IsShiftKeyDown()) then
        if GameTooltip_ShowCompareItem then pcall(GameTooltip_ShowCompareItem, tt or GameTooltip) end
    end
end

function TooltipUpgradeAdvisor.tooltipWanted(tt)
    if not ns.db or ns.db.itemTooltip == false then return false end
    if not TooltipUpgradeAdvisor.isAllowedTooltip(tt) then return false end
    if tt == GameTooltip then
        if ns.tipSuppressed then return false end
        local okO, ownerFrame = pcall(tt.GetOwner, tt)
        if okO and type(ownerFrame) == "table" and ownerFrame.bgfRow then return false end
    end
    return true
end

-- At least one real source (drop, quest, vendor, craft) is known for the item.
function TooltipUpgradeAdvisor.hasRealSource(recordItem)
    for _, stateFlag in ipairs(recordItem and recordItem.src or {}) do
        if stateFlag.kind ~= "unknown" then return true end
    end
    return false
end

-- Source lines in item tooltips are this addon's job while its option is on. EzWoW-Tooltip asks
-- here and leaves out its own source lines for the items this returns true for.
-- Returns: sources shown, craft reagents/recipe source shown.
function ns:CoversItemSource(tt, entityID)
    entityID = tonumber(entityID)
    if not entityID or not TooltipUpgradeAdvisor.tooltipWanted(tt) then return false, false end
    if ns.indexState ~= "done" or not ns.index then return false, false end
    local recordItem = ns.index[entityID]
    if not TooltipUpgradeAdvisor.hasRealSource(recordItem) then return false, false end
    local craft = false
    for _, stateFlag in ipairs(recordItem.src) do
        if stateFlag.kind == "craft" then craft = ns.CraftData and ns.CraftData.info and ns.CraftData.info[entityID] ~= nil; break end
    end
    return true, craft and true or false
end

function TooltipUpgradeAdvisor.appendEntry(tt, entityID)
    if not TooltipUpgradeAdvisor.tooltipWanted(tt) then return end
    if ns.indexState ~= "done" or not ns.index then
        
        if ns.indexState == "idle" and not (InCombatLockdown and InCombatLockdown()) then ns:EnsureIndex() end
        return
    end
    local recordItem = ns.index[entityID]
    -- EzWoW-Tooltip knows a source for the item: used only when this addon has no real one,
    -- so a guess or "unknown" line never sits next to an actual source.
    local etRef = _G.EzWoW_Tooltip
    local etHasSource = type(etRef) == "table"
        and etRef.db and etRef.db.item and etRef.db.item.showSourceInfo ~= false
        and ((etRef.ItemSourceDB and etRef.ItemSourceDB[entityID])
            or (etRef.CraftedItemDB and etRef.CraftedItemDB[entityID]))
    if not recordItem then

        if etHasSource or entityID < 200000 or not TooltipUpgradeAdvisor.hasGear(entityID) then return end
        local est = ns:EstimateSource(entityID)
        if not est then return end
        tt:AddLine(" ")
        ns:AddEstimateLines(tt, entityID)
        return
    end
    -- with a real source here, EzWoW-Tooltip leaves its source lines out (see CoversItemSource)
    if TooltipUpgradeAdvisor.hasRealSource(recordItem) then etHasSource = false end

    local bisLines = {}
    if ns.GetBestInSlotRank and ns.GetSpecList then
        for siVal, spec in ipairs(ns:GetSpecList()) do
            local rowEntry = ns:GetBestInSlotRank(siVal, entityID)
            if rowEntry == 2 then
                bisLines[#bisLines + 1] = { "[BiS] " .. (spec.name or ""), 1, 0.82, 0 }
            elseif rowEntry == 1 then
                bisLines[#bisLines + 1] = { L["BiS 대안: "] .. (spec.name or ""), 0.9, 0.8, 0.4 }
            end
        end
    end

    if etHasSource then
        for _, blVal in ipairs(bisLines) do
            tt:AddLine(blVal[1], blVal[2], blVal[3], blVal[4])
        end
        return
    end

    tt:AddLine(" ")
    for _, blVal in ipairs(bisLines) do
        tt:AddLine(blVal[1], blVal[2], blVal[3], blVal[4])
    end
    local shown, grandTotal = 0, 0
    local craftShown = false
    for _, stateFlag in ipairs(recordItem.src) do
        grandTotal = grandTotal + 1
        if shown < MAX_LINES then
            shown = shown + 1
            local displayText = ns:FormatDetailedDropSource(stateFlag)
            if stateFlag.kind == "craft" then
                tt:AddLine(displayText, 0.4, 0.8, 1, true)
                if not craftShown then
                    craftShown = true
                    for _, lnVal in ipairs(ns:CraftDetailLines(entityID) or {}) do tt:AddLine(lnVal, 0.7, 0.85, 1, true) end
                end
            elseif stateFlag.kind == "quest" then tt:AddLine(displayText, 1, 0.8, 0.3, true)
            elseif stateFlag.kind == "vendor" then tt:AddLine(displayText, 0.6, 1, 0.6, true)
            else tt:AddLine(displayText, 0.85, 0.85, 0.85, true) end
        end
    end
    if grandTotal > shown then tt:AddLine(string.format(L["... 외 %d곳"], grandTotal - shown), 0.6, 0.6, 0.6) end
    if grandTotal == 0 then tt:AddLine(L["획득처 정보 없음"], 0.6, 0.6, 0.6) end
    
    local onlyUnknown = grandTotal > 0
    for _, stateFlag in ipairs(recordItem.src) do if stateFlag.kind ~= "unknown" then onlyUnknown = false end end
    if onlyUnknown or grandTotal == 0 then
        ns:AddEstimateLines(tt, entityID)
    end
end

-- Attribution line under this addon's block: once per tooltip display, only when lines were added.
local TAG_TITLE = "EzWoW - Best Gear Finder"
local taggedTooltips = setmetatable({}, { __mode = "k" })
local tagClearHooked = setmetatable({}, { __mode = "k" })
function TooltipUpgradeAdvisor.lineCount(tt)
    if type(tt) ~= "table" or type(tt.NumLines) ~= "function" then return nil end
    local ok, n = pcall(tt.NumLines, tt)
    if not ok or (issecretvalue and issecretvalue(n)) or type(n) ~= "number" then return nil end
    return n
end
function TooltipUpgradeAdvisor.tagTooltip(tt)
    if type(tt) ~= "table" or taggedTooltips[tt] or type(tt.AddDoubleLine) ~= "function" then return end
    if not tagClearHooked[tt] and type(tt.HookScript) == "function" then
        tagClearHooked[tt] = true
        pcall(tt.HookScript, tt, "OnTooltipCleared", function(self) taggedTooltips[self] = nil end)
    end
    taggedTooltips[tt] = true
    tt:AddDoubleLine(" ", TAG_TITLE, 0, 0, 0, 0.5, 0.5, 0.5)
end

local errShown = false
function TooltipUpgradeAdvisor.handleTooltipItemDisplayed(tt, data)
    local isCallOk, errorObj = pcall(function()
        local entityID = TooltipUpgradeAdvisor.resolveItemIDFrom(tt, data)
        if not entityID then return end
        local linesBefore = TooltipUpgradeAdvisor.lineCount(tt)
        TooltipUpgradeAdvisor.appendEntry(tt, entityID)
        local linesAfter = TooltipUpgradeAdvisor.lineCount(tt)
        if linesBefore and linesAfter and linesAfter > linesBefore then TooltipUpgradeAdvisor.tagTooltip(tt) end
    end)
    if not isCallOk and not errShown and ns.db and ns.db.tipDebug then
        errShown = true
        print("|cff33ccffEzWoW - Best Gear Finder|r tooltip error: " .. tostring(errorObj))
    end
    return isCallOk
end

function ns:PrintTooltipDiagnostics()
    local platformHelper = function(t) print("|cff33ccffBGF tip|r " .. t) end
    platformHelper("TooltipDataProcessor=" .. tostring(TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and true or false)
        .. " option=" .. tostring(ns.db and ns.db.itemTooltip) .. " index=" .. tostring(ns.indexState))
    local isCallOk, entityID = pcall(TooltipUpgradeAdvisor.resolveItemIDFrom, GameTooltip, nil)
    entityID = isCallOk and entityID or nil
    platformHelper("hover item=" .. tostring(entityID) .. " inData=" .. tostring(entityID and ns.index and ns.index[entityID] and true or false)
        .. " hookCalls=" .. tostring(ns.tipCalls or 0))
    if ns.db then ns.db.tipDebug = true end
    errShown = false
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        if not TooltipUpgradeAdvisor.isAllowedTooltip(tt) then return end
        ns.tipCalls = (ns.tipCalls or 0) + 1
        
        if tt and tt.AddLine then TooltipUpgradeAdvisor.handleTooltipItemDisplayed(tt, data) end
    end)
else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2, ItemRefShoppingTooltip1, ItemRefShoppingTooltip2 }) do
        if tt and tt.HookScript then tt:HookScript("OnTooltipSetItem", function(self) TooltipUpgradeAdvisor.handleTooltipItemDisplayed(self, nil) end) end
    end
end

local windowFrame = CreateFrame("Frame")
windowFrame:RegisterEvent("PLAYER_LOGIN")
windowFrame:SetScript("OnEvent", function()
    C_Timer.After(5, function()
        if ns.db and ns.db.itemTooltip ~= false and not (InCombatLockdown and InCombatLockdown()) then
            ns:EnsureIndex()
        end
    end)
end)
ns._TooltipAdd = TooltipUpgradeAdvisor.appendEntry

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
TooltipUpgradeAdvisor.PrintTooltipDiagnostics = ns.PrintTooltipDiagnostics
