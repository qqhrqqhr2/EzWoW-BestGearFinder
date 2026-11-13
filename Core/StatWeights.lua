--===========================================================================
-- EzWoW - Best Gear Finder
-- Core/StatWeights.lua : Per-spec stat weights from the game's own conversions
--===========================================================================
-- Each spec in Data/Rules.lua carries VALUES (field v) in its own currency:
-- physical specs count in attack power, casters in spell damage, healers in
-- healing. Percent stats (hit, crit, haste, expertise) and spell piercing are
-- given as their worth at level 60 and scaled to the character's present
-- power, so they are worth less while levelling, as they are in play.
-- Conversions (Agility / Intellect to crit, rating to percent, Strength to
-- attack power) come from the game at the character's level.
-- Hit, expertise and defense have caps: what an item adds below the cap
-- counts in full, the rest at the over-cap value, and the item worn in the
-- slot being judged is left out of the present total.
local ADDON, ns = ...
local type, pairs, ipairs, pcall = type, pairs, ipairs, pcall
local min, max, floor = math.min, math.max, math.floor

local StatWeights = {}
ns.StatWeights = StatWeights

-- item stat keys (GetItemStats)
local K = {
    STR = "ITEM_MOD_STRENGTH_SHORT", AGI = "ITEM_MOD_AGILITY_SHORT", STA = "ITEM_MOD_STAMINA_SHORT",
    INT = "ITEM_MOD_INTELLECT_SHORT", SPI = "ITEM_MOD_SPIRIT_SHORT",
    AP = "ITEM_MOD_ATTACK_POWER_SHORT", RAP = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", FAP = "ITEM_MOD_FERAL_ATTACK_POWER_SHORT",
    SP = "ITEM_MOD_SPELL_POWER_SHORT", SDMG = "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT",
    HEAL = "ITEM_MOD_SPELL_HEALING_DONE_SHORT", HEAL2 = "ITEM_MOD_HEALING_DONE_SHORT",
    MP5 = "ITEM_MOD_MANA_REGENERATION_SHORT", DPS = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", ARMOR = "RESISTANCE0_NAME",
    DEF = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", DODGE = "ITEM_MOD_DODGE_RATING_SHORT", PARRY = "ITEM_MOD_PARRY_RATING_SHORT",
    BLOCKV = "ITEM_MOD_BLOCK_VALUE_SHORT", BLOCKR = "ITEM_MOD_BLOCK_RATING_SHORT",
    HIT = "ITEM_MOD_HIT_RATING_SHORT", CRIT = "ITEM_MOD_CRIT_RATING_SHORT", HASTE = "ITEM_MOD_HASTE_RATING_SHORT",
    EXP = "ITEM_MOD_EXPERTISE_RATING_SHORT",
    SHIT = "ITEM_MOD_HIT_SPELL_RATING_SHORT", SCRIT = "ITEM_MOD_CRIT_SPELL_RATING_SHORT", SHASTE = "ITEM_MOD_HASTE_SPELL_RATING_SHORT",
    PIERCE = "ITEM_MOD_SPELL_PENETRATION_SHORT",
    -- one school's spell damage ("+X fire damage")
    ARCANE = "ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT", FIRE = "ITEM_MOD_FIRE_DAMAGE_DONE_SHORT", FROST = "ITEM_MOD_FROST_DAMAGE_DONE_SHORT",
    NATURE = "ITEM_MOD_NATURE_DAMAGE_DONE_SHORT", SHADOW = "ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT", HOLY = "ITEM_MOD_HOLY_DAMAGE_DONE_SHORT",
}
StatWeights.KEYS = K
-- shown name of a stat key: the game's own name when the addon shows the
-- game's language, else the addon's text (keys of Core/Locales.lua)
local LABELS = {
    [K.STR] = "힘", [K.AGI] = "민첩성", [K.STA] = "체력", [K.INT] = "지능", [K.SPI] = "정신력",
    [K.AP] = "전투력", [K.RAP] = "원거리 전투력", [K.FAP] = "야성 전투력", [K.SP] = "주문력", [K.SDMG] = "주문력",
    [K.HEAL] = "치유량", [K.HEAL2] = "치유량", [K.MP5] = "5초당 마나 회복", [K.DPS] = "초당 공격력", [K.ARMOR] = "방어도",
    [K.DEF] = "방어 숙련도", [K.DODGE] = "회피", [K.PARRY] = "무기 막기", [K.BLOCKV] = "방패 피해 방어량", [K.BLOCKR] = "방패 막기",
    [K.HIT] = "적중도", [K.CRIT] = "치명타", [K.HASTE] = "가속", [K.EXP] = "숙련도",
    [K.SHIT] = "적중도", [K.SCRIT] = "치명타", [K.SHASTE] = "가속", [K.PIERCE] = "주문 관통력",
    [K.ARCANE] = "비전 주문력", [K.FIRE] = "화염 주문력", [K.FROST] = "냉기 주문력",
    [K.NATURE] = "자연 주문력", [K.SHADOW] = "암흑 주문력", [K.HOLY] = "신성 주문력",
}
function StatWeights.Label(key, label)
    local active = ns.GetActiveLocale and ns.GetActiveLocale()
    local client = GetLocale and GetLocale()
    if not active or active == client then
        local text = _G[key]
        if type(text) == "string" and text ~= "" and not text:find("%%") then return text end
    end
    label = label or LABELS[key]
    if label and ns.L then return ns.L[label] end
    return (tostring(key):gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""))
end
-- spec field (v.school) for each school key
local SCHOOLS = { ARCANE = "arcane", FIRE = "fire", FROST = "frost", NATURE = "nature", SHADOW = "shadow", HOLY = "holy" }

-- combat rating ids, and the rating per 1 % (per 1 defense skill) when the game can't say
local CR = { DEFENSE = 2, DODGE = 3, PARRY = 4, BLOCK = 5, HIT_MELEE = 6, HIT_RANGED = 7, HIT_SPELL = 8,
    CRIT_MELEE = 9, CRIT_RANGED = 10, CRIT_SPELL = 11, HASTE_MELEE = 18, HASTE_RANGED = 19, HASTE_SPELL = 20, EXPERTISE = 24 }
StatWeights.CR = CR
local RATING_FALLBACK = { [2] = 1, [3] = 12, [4] = 15, [5] = 5, [6] = 10, [7] = 10, [8] = 10, [9] = 14, [10] = 14, [11] = 14,
    [18] = 10, [19] = 10, [20] = 10, [24] = 10 }

-- power the level-60 values were set for (attack power + 14 x weapon DPS, or base + bonus spell damage)
local REF_POWER = { phys = 2000, caster = 900, heal = 1200 }

-- class conversions used when the game can't be asked (another class shown):
-- Strength / Agility -> attack power, Agility per 1 % crit and Intellect per 1 % spell crit at 60
local CLASS_STR_AP = { WARRIOR = 2, PALADIN = 2, SHAMAN = 2, DRUID = 2, ROGUE = 1, HUNTER = 1, MAGE = 1, PRIEST = 1, WARLOCK = 1 }
local CLASS_AGI_AP = { ROGUE = 1, HUNTER = 1 }
local CLASS_AGI_CRIT60 = { WARRIOR = 20, PALADIN = 20, SHAMAN = 20, DRUID = 20, ROGUE = 29, HUNTER = 53 }
local CLASS_INT_CRIT60 = { MAGE = 59.5, PRIEST = 59.2, WARLOCK = 60.5, DRUID = 60, SHAMAN = 59, PALADIN = 54 }
-- hunters: ranged attack power per Agility (the game says 2 for 1, checked on a hunter)
local HUNTER_AGI_RAP = 2

-- caps (percent; defense in skill points)
local MELEE_CAP_LOW, SPELL_CAP_LOW, SPELL_CAP_60 = 5, 4, 17
local EXP_SOFT, EXP_HARD, DEF_CAP_60 = 6.5, 14, 440

local function secret(v) return issecretvalue and issecretvalue(v) end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok or secret(a) or secret(b) or secret(c) then return nil end
    return a, b, c
end
local function num(v) return type(v) == "number" and v or nil end

-----------------------------------------------------------------------------
-- What the game says about the character
-----------------------------------------------------------------------------
local function ownClass() return not ns.viewClass end
local function level() return num(call(UnitLevel, "player")) or 60 end

-- percent (or defense skill) per 1 rating point
function StatWeights.PerRating(cr)
    local v = num(call(GetCombatRatingBonusForCombatRatingValue, cr, 100))
    if v and v > 0 then return v / 100 end
    return 1 / (RATING_FALLBACK[cr] or 10)
end

-- percent crit per 1 Agility, percent spell crit per 1 Intellect
-- (the game gives a fraction for 100 points, which is the percent for 1 point)
function StatWeights.CritPerAgi(class)
    if ownClass() then
        local a, z = num(call(GetCritChanceFromStat, 2, 100)), num(call(GetCritChanceFromStat, 2, 0)) or 0
        if a and a > z then return a - z end
    end
    return 1 / max(1, (CLASS_AGI_CRIT60[class] or 20) * level() / 60)
end
function StatWeights.CritPerInt(class)
    if ownClass() then
        local a, z = num(call(GetSpellCritChanceFromStat, 4, 100)), num(call(GetSpellCritChanceFromStat, 4, 0)) or 0
        if a and a > z then return a - z end
    end
    return 1 / max(1, (CLASS_INT_CRIT60[class] or 60) * level() / 60)
end

local function strAP(class)
    if ownClass() then
        local v = num(call(GetAttackPowerForStat, 1, 100))
        if v and v > 0 then return v / 100 end
    end
    return CLASS_STR_AP[class] or 0
end
local function rangedAgiAP()
    if ownClass() then
        local v = num(call(GetRangedAttackPowerForStat, 2, 100))
        if v and v > 0 then return v / 100 end
    end
    return HUNTER_AGI_RAP
end
local function agiAP(class)
    if ownClass() then
        local v = num(call(GetAttackPowerForStat, 2, 100))
        if v then return v / 100 end
    end
    return CLASS_AGI_AP[class] or 0
end

local function statsOf(link)
    local stats = type(link) == "string" and ns.GetStats and ns.GetStats(link)
    return type(stats) == "table" and stats or {}
end

-- DPS of the weapon worn in an inventory slot
local function wornDPS(slot)
    return num(statsOf(call(GetInventoryItemLink, "player", slot))[K.DPS]) or 0
end

local function total(base, pos, neg) return (num(base) or 0) + (num(pos) or 0) + (num(neg) or 0) end

-- the power a spec's percent values scale with
local function presentPower(v)
    local lv = level()
    if v.role == "phys" then
        if ownClass() then
            if v.ranged then
                local base, pos, neg = call(UnitRangedAttackPower, "player")
                if num(base) then return max(60, total(base, pos, neg) + 14 * wornDPS(18)) end
            else
                local base, pos, neg = call(UnitAttackPower, "player")
                if num(base) then
                    local ap = total(base, pos, neg)
                    -- a druid out of cat / bear form: add what cat form gives (2 per level + Agility)
                    if v.feral then
                        local form = num(call(GetShapeshiftFormID))
                        if form ~= 1 and form ~= 5 and form ~= 8 then
                            local _, agi = call(UnitStat, "player", 2)
                            ap = ap + 2 * lv + (num(agi) or 0)
                        end
                    end
                    return max(60, ap + 14 * wornDPS(16))
                end
            end
        end
        return max(60, lv * lv / 2)
    end
    local bonus = 5 * lv
    if ownClass() then
        bonus = 0
        if v.role == "heal" then
            bonus = num(call(GetSpellBonusHealing)) or 0
        else
            for school = 2, 7 do bonus = max(bonus, num(call(GetSpellBonusDamage, school)) or 0) end
        end
    end
    return max(30, 10 * lv + bonus)
end

-- hit the character has now (percent): gear, talents and effects
local function presentHit(v)
    if not ownClass() then return 0, 0 end
    local physCR = v.ranged and CR.HIT_RANGED or CR.HIT_MELEE
    local phys = (num(call(GetHitModifier)) or 0) + (num(call(GetCombatRatingBonus, physCR)) or 0)
    local spell = (num(call(GetSpellHitModifier)) or 0) + (num(call(GetCombatRatingBonus, CR.HIT_SPELL)) or 0)
    return phys, spell
end
-- expertise from rating (percent)
local function presentExpertise()
    if not ownClass() then return 0 end
    return num(call(GetCombatRatingBonus, CR.EXPERTISE)) or 0
end
-- defense skill: 5 per level + rating
local function presentDefense()
    local lv = level()
    if not ownClass() then return lv * 5 end
    return lv * 5 + (num(call(GetCombatRatingBonus, CR.DEFENSE)) or 0)
end

function StatWeights.HitCaps(v)
    if level() >= 60 then return v.capMelee or 8, SPELL_CAP_60 end
    return MELEE_CAP_LOW, SPELL_CAP_LOW
end

-- hit (physical, spell), expertise (percent) and defense (skill) an item adds
local function itemHit(stats, ranged)
    local hit = num(stats[K.HIT]) or 0
    local phys = hit * StatWeights.PerRating(ranged and CR.HIT_RANGED or CR.HIT_MELEE)
    local spell = max(hit, num(stats[K.SHIT]) or 0) * StatWeights.PerRating(CR.HIT_SPELL)
    return phys, spell
end
local function itemExpertise(stats) return (num(stats[K.EXP]) or 0) * StatWeights.PerRating(CR.EXPERTISE) end
local function itemDefense(stats) return (num(stats[K.DEF]) or 0) * StatWeights.PerRating(CR.DEFENSE) end

-- of the items worn in a slot group, what the new item takes the place of:
-- one-slot groups their item, rings / trinkets the one with less (so the other stays),
-- a two-hand weapon both hands
local function wornCapped(group, ranged)
    local hp, hs, ex, df = 0, 0, 0, 0
    if not ownClass() or not group then return hp, hs, ex, df end
    local slots = group.key == "MAIN2H" and { 16, 17 } or group.inv or {}
    local first = true
    for _, slot in ipairs(slots) do
        local stats = statsOf(call(GetInventoryItemLink, "player", slot))
        local p, s = itemHit(stats, ranged)
        local e, d = itemExpertise(stats), itemDefense(stats)
        if group.key == "MAIN2H" then
            hp, hs, ex, df = hp + p, hs + s, ex + e, df + d
        elseif first then
            hp, hs, ex, df = p, s, e, d
        else
            hp, hs, ex, df = min(hp, p), min(hs, s), min(ex, e), min(df, d)
        end
        first = false
    end
    return hp, hs, ex, df
end

-- `amount` added on top of `start` counts at `below` up to `cap`, the rest at `over`
local function capped(amount, start, cap, below, over)
    if amount <= 0 then return 0 end
    local inside = min(amount, max(0, cap - start))
    return inside * below + (amount - inside) * (over or 0)
end

-----------------------------------------------------------------------------
-- Weights
-----------------------------------------------------------------------------
local ctxCache, ctxCount = {}, 0

function StatWeights.Reset()
    ctxCache, ctxCount = {}, 0
end

-- weights (currency per item stat point) of one spec for one slot group;
-- the same table comes back while nothing they depend on has changed.
-- hand = "OFF": weapon DPS at the off-hand worth (the off hand next to a two-hand comparison)
function StatWeights.For(si, spec, group, hand)
    local v = spec and spec.v
    if not v then return spec and spec.w or {} end
    local class = ns:GetActiveClassToken()
    local lv = level()
    local power = presentPower(v)
    local curPhys, curSpell = presentHit(v)
    local curExp, curDef = presentExpertise(), presentDefense()
    local wP, wS, wE, wD = wornCapped(group, v.ranged)
    local startPhys, startSpell = curPhys - wP, curSpell - wS
    local startExp, startDef = curExp - wE, curDef - wD

    local key = table.concat({ class or "", si or 0, group and group.key or "", hand or "", lv, floor(power / 10),
        floor(startPhys * 10), floor(startSpell * 10), floor(startExp * 10), floor(startDef) }, ":")
    local cached = ctxCache[key]
    if cached then return cached end

    local scale = power / (REF_POWER[v.role] or 2000)
    local capPhys, capSpell = StatWeights.HitCaps(v)
    local isSpell = v.role ~= "phys"
    local crit, haste = (v.crit or 0) * scale, (v.haste or 0) * scale
    local apv = v.ap or ((v.role == "phys") and 1 or 0)
    local w = {}

    -- main stats
    local toAP = v.strAP or strAP(class)
    w[K.STR] = (v.str or (toAP * apv)) + ((v.blockv or 0) / 20)
    local agiToAP = v.agiAP or (v.ranged and rangedAgiAP()) or agiAP(class)
    local critPerAgi = StatWeights.CritPerAgi(class)
    w[K.AGI] = agiToAP * apv + ((v.role == "phys") and critPerAgi * crit or 0)
        + critPerAgi * (v.dodge or 0) + 2 * (v.armor or 0) + (v.agi or 0)
    w[K.STA] = v.sta or 0
    w[K.INT] = (v.int or 0) + (v.intCrit and StatWeights.CritPerInt(class) * crit or 0)
    w[K.SPI] = v.spi or 0
    w[K.MP5] = v.mp5 or 0

    -- power
    w[K.AP] = apv
    w[K.RAP] = v.ranged and apv or 0
    w[K.FAP] = v.feral and apv or 0
    w[K.SP] = v.sp or v.heal or 0
    w[K.SDMG] = v.sdmg or v.sp or 0
    -- one school's spell damage counts for the share of the spec's damage in that school
    local schoolShare = v.school or {}
    for keyName, field in pairs(SCHOOLS) do w[K[keyName]] = w[K.SDMG] * (schoolShare[field] or 0) end
    w[K.HEAL] = v.heal or 0
    w[K.HEAL2] = v.heal or 0
    w[K.ARMOR] = v.armorItem or v.armor or 0

    -- ratings
    local critCR = isSpell and CR.CRIT_SPELL or (v.ranged and CR.CRIT_RANGED or CR.CRIT_MELEE)
    local hasteCR = isSpell and CR.HASTE_SPELL or (v.ranged and CR.HASTE_RANGED or CR.HASTE_MELEE)
    w[K.CRIT] = crit * StatWeights.PerRating(critCR)
    w[K.SCRIT] = isSpell and w[K.CRIT] or 0
    w[K.HASTE] = haste * StatWeights.PerRating(hasteCR)
    w[K.SHASTE] = isSpell and w[K.HASTE] or 0
    w[K.PIERCE] = (v.pierce or 0) * scale
    w[K.DODGE] = (v.dodge or 0) * StatWeights.PerRating(CR.DODGE)
    w[K.PARRY] = (v.parry or 0) * StatWeights.PerRating(CR.PARRY)
    w[K.BLOCKR] = (v.block or 0) * StatWeights.PerRating(CR.BLOCK)
    w[K.BLOCKV] = v.blockv or 0

    -- weapon DPS by hand; wands for casters while levelling
    local d = v.dps or {}
    local gk = hand or (group and group.key)
    if gk == "RANGED" then
        w[K.DPS] = d.ranged or ((isSpell and lv < 60) and 0.5 or 0)
    elseif gk == "OFF" then
        w[K.DPS] = d.off or 0
    else
        w[K.DPS] = d.main or 0
    end

    -- capped stats: worked out per item; the table shows their below-cap worth
    local hitP, hitPOver = (v.hit or 0) * scale, (v.hitOver or 0) * scale
    local hitS, hitSOver = (v.spellHit or 0) * scale, (v.spellHitOver or 0) * scale
    local expV, expOver = (v.exp or 0) * scale, (v.expOver or 0) * scale
    local defV, defOver = v.def or 0, v.defOver or v.def or 0
    local physCR = v.ranged and CR.HIT_RANGED or CR.HIT_MELEE
    w[K.HIT] = hitP * StatWeights.PerRating(physCR) + hitS * StatWeights.PerRating(CR.HIT_SPELL)
    w[K.SHIT] = hitS * StatWeights.PerRating(CR.HIT_SPELL)
    w[K.EXP] = expV * StatWeights.PerRating(CR.EXPERTISE)
    w[K.DEF] = defV * StatWeights.PerRating(CR.DEFENSE)
    w.__skip = { [K.HIT] = true, [K.SHIT] = true, [K.EXP] = true, [K.DEF] = true }
    local defCap = (lv >= 60) and DEF_CAP_60 or math.huge
    w.__special = function(stats)
        local p, s = itemHit(stats, v.ranged)
        local value = capped(p, startPhys, capPhys, hitP, hitPOver) + capped(s, startSpell, capSpell, hitS, hitSOver)
        local e = itemExpertise(stats)
        if e > 0 then
            local soft = min(e, max(0, EXP_SOFT - startExp))
            local mid = min(e - soft, max(0, EXP_HARD - max(startExp, EXP_SOFT)))
            value = value + soft * expV + mid * expOver
        end
        local df = itemDefense(stats)
        if df > 0 then value = value + capped(df, startDef, defCap, defV, defOver) end
        return value
    end
    -- for the criteria window
    w.__info = { scale = scale, power = power, hitPhys = startPhys, hitSpell = startSpell, capPhys = capPhys, capSpell = capSpell,
        expertise = startExp, defense = startDef, defCap = defCap }

    if ctxCount > 300 then StatWeights.Reset() end
    ctxCache[key] = w
    ctxCount = ctxCount + 1
    return w
end

-- the item's score with these weights (linear stats + capped stats)
function StatWeights.Score(stats, weights)
    if type(stats) ~= "table" then return 0 end
    local sc = 0
    local skip = weights.__skip
    for statKey, amount in pairs(stats) do
        local wt = weights[statKey]
        if type(wt) == "number" and type(amount) == "number" and not (skip and skip[statKey]) then
            sc = sc + amount * wt
        end
    end
    if weights.__special then sc = sc + weights.__special(stats) end
    return sc
end
