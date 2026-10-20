--===========================================================================
-- EzWoW - Best Gear Finder
-- Modules/TooltipHook.lua : Item Tooltip Stat Upgrade & Drop Source Hook
--===========================================================================
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local TooltipUpgradeAdvisor = ns.TooltipUpgradeAdvisor or {}
ns.TooltipUpgradeAdvisor = TooltipUpgradeAdvisor
local L = ns.L

local MAX_LINES = 5

function ns:SuppressItemTooltip(v) ns.tipSuppressed = v end

function TooltipUpgradeAdvisor.resolveItemIDFrom(tt, data)
    local entityID = data and data.id
    if type(entityID) == "number" then return entityID end
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

function TooltipUpgradeAdvisor.appendEntry(tt, entityID)
    if not ns.db or ns.db.itemTooltip == false then return end
    
    if tt == GameTooltip then
        if ns.tipSuppressed then return end
        local okO, ownerFrame = pcall(tt.GetOwner, tt)
        if okO and type(ownerFrame) == "table" and ownerFrame.bgfRow then return end
    end
    if ns.indexState ~= "done" or not ns.index then
        
        if ns.indexState == "idle" and not (InCombatLockdown and InCombatLockdown()) then ns:EnsureIndex() end
        return
    end
    local recordItem = ns.index[entityID]
    if not recordItem then
        
        if entityID < 200000 or not TooltipUpgradeAdvisor.hasGear(entityID) then return end
        local est = ns:EstimateSource(entityID)
        if not est then return end
        tt:AddLine(" ")
        tt:AddLine("EzWoW - Best Gear Finder", 0.945, 0.741, 0.341)
        ns:AddEstimateLines(tt, entityID)
        return
    end
    local etRef = _G.EzWoW_Tooltip or _G.EzWoW_Tooltip
    local etHasSource = etRef
        and etRef.db and etRef.db.item and etRef.db.item.showSourceInfo ~= false
        and ((etRef.ItemSourceDB and etRef.ItemSourceDB[entityID])
            or (etRef.CraftedItemDB and etRef.CraftedItemDB[entityID]))

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
    tt:AddLine("EzWoW - Best Gear Finder", 0.945, 0.741, 0.341)
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

local errShown = false
function TooltipUpgradeAdvisor.handleTooltipItemDisplayed(tt, data)
    local isCallOk, errorObj = pcall(function()
        local entityID = TooltipUpgradeAdvisor.resolveItemIDFrom(tt, data)
        if entityID then TooltipUpgradeAdvisor.appendEntry(tt, entityID) end
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
    local isCallOk, _, link = pcall(GameTooltip.GetItem, GameTooltip)
    local entityID = isCallOk and type(link) == "string" and tonumber(link:match("item:(%d+)"))
    platformHelper("hover item=" .. tostring(entityID) .. " inData=" .. tostring(entityID and ns.index and ns.index[entityID] and true or false)
        .. " hookCalls=" .. tostring(ns.tipCalls or 0))
    ns.db.tipDebug = true
    errShown = false
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
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
