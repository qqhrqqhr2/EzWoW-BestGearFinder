-- EzWoW_BestGearFinder : 정적 규칙 데이터 (직업별 방어구/무기 숙련, 슬롯 그룹, 스탯 가중치)
local ADDON, ns = ...
local L = ns.L

-- 아이템 classID / subClassID (언어와 무관한 숫자 ID 사용)
ns.CLASS_WEAPON, ns.CLASS_ARMOR = 2, 4
local W = { AXE1 = 0, AXE2 = 1, BOW = 2, GUN = 3, MACE1 = 4, MACE2 = 5, POLE = 6,
            SWORD1 = 7, SWORD2 = 8, STAFF = 10, FIST = 13, DAGGER = 15, THROWN = 16,
            XBOW = 18, WAND = 19 }
local A = { CLOTH = 1, LEATHER = 2, MAIL = 3, PLATE = 4, SHIELD = 6, LIBRAM = 7, IDOL = 8, TOTEM = 9 }

local function set(...) local t = {} for i = 1, select("#", ...) do t[select(i, ...)] = true end return t end

-- armorByLevel: { {최소레벨, 방어구종류}, ... } 마지막으로 만족하는 항목 사용
ns.CLASS_RULES = {
    WARRIOR = { armor = { {1, A.MAIL}, {40, A.PLATE} }, shield = true, dualWield = true,
        weapons = set(W.AXE1, W.AXE2, W.BOW, W.GUN, W.MACE1, W.MACE2, W.POLE, W.SWORD1, W.SWORD2, W.STAFF, W.FIST, W.DAGGER, W.THROWN, W.XBOW) },
    PALADIN = { armor = { {1, A.MAIL}, {40, A.PLATE} }, shield = true, relic = A.LIBRAM,
        weapons = set(W.AXE1, W.AXE2, W.MACE1, W.MACE2, W.POLE, W.SWORD1, W.SWORD2) },
    HUNTER  = { armor = { {1, A.LEATHER}, {40, A.MAIL} }, dualWield = true,
        weapons = set(W.AXE1, W.AXE2, W.BOW, W.GUN, W.POLE, W.SWORD1, W.SWORD2, W.STAFF, W.FIST, W.DAGGER, W.XBOW, W.THROWN) },
    ROGUE   = { armor = { {1, A.LEATHER} }, dualWield = true,
        weapons = set(W.DAGGER, W.FIST, W.MACE1, W.SWORD1, W.BOW, W.GUN, W.XBOW, W.THROWN) },
    PRIEST  = { armor = { {1, A.CLOTH} },
        weapons = set(W.MACE1, W.DAGGER, W.STAFF, W.WAND) },
    SHAMAN  = { armor = { {1, A.LEATHER}, {40, A.MAIL} }, shield = true, relic = A.TOTEM, dualWield = true,
        weapons = set(W.AXE1, W.AXE2, W.MACE1, W.MACE2, W.STAFF, W.FIST, W.DAGGER) },
    MAGE    = { armor = { {1, A.CLOTH} },
        weapons = set(W.SWORD1, W.DAGGER, W.STAFF, W.WAND) },
    WARLOCK = { armor = { {1, A.CLOTH} },
        weapons = set(W.SWORD1, W.DAGGER, W.STAFF, W.WAND) },
    DRUID   = { armor = { {1, A.LEATHER} }, relic = A.IDOL,
        weapons = set(W.MACE1, W.MACE2, W.STAFF, W.FIST, W.DAGGER, W.POLE) },
}

-- 이중무기 가능 레벨 (대략값)
ns.DUAL_WIELD_LEVEL = { WARRIOR = 20, ROGUE = 10, HUNTER = 20, SHAMAN = 40 }

-- 방어구 종류 제한을 적용할 장착 부위 (목걸이/반지/장신구/망토는 제한 없음)
ns.ARMOR_LOCS = set("INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_ROBE",
    "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND")

-- 슬롯 그룹: locs = 장착 부위, inv = 비교 대상 인벤토리 슬롯 ID
ns.GROUPS = {
    { key = "HEAD",     label = L["머리"], labelKo = "머리",      locs = set("INVTYPE_HEAD"), inv = {1} },
    { key = "NECK",     label = L["목걸이"], labelKo = "목걸이",    locs = set("INVTYPE_NECK"), inv = {2} },
    { key = "SHOULDER", label = L["어깨"], labelKo = "어깨",      locs = set("INVTYPE_SHOULDER"), inv = {3} },
    { key = "CLOAK",    label = L["등"], labelKo = "등",        locs = set("INVTYPE_CLOAK"), inv = {15} },
    { key = "CHEST",    label = L["가슴"], labelKo = "가슴",      locs = set("INVTYPE_CHEST", "INVTYPE_ROBE"), inv = {5} },
    { key = "WRIST",    label = L["손목"], labelKo = "손목",      locs = set("INVTYPE_WRIST"), inv = {9} },
    { key = "HAND",     label = L["손"], labelKo = "손",        locs = set("INVTYPE_HAND"), inv = {10} },
    { key = "WAIST",    label = L["허리"], labelKo = "허리",      locs = set("INVTYPE_WAIST"), inv = {6} },
    { key = "LEGS",     label = L["다리"], labelKo = "다리",      locs = set("INVTYPE_LEGS"), inv = {7} },
    { key = "FEET",     label = L["발"], labelKo = "발",        locs = set("INVTYPE_FEET"), inv = {8} },
    { key = "FINGER",   label = L["반지"], labelKo = "반지",      locs = set("INVTYPE_FINGER"), inv = {11, 12} },
    { key = "TRINKET",  label = L["장신구"], labelKo = "장신구",    locs = set("INVTYPE_TRINKET"), inv = {13, 14} },
    { key = "MAIN1H",   label = L["한손 무기"], labelKo = "한손 무기", locs = set("INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND"), inv = {16} },
    { key = "MAIN2H",   label = L["양손 무기"], labelKo = "양손 무기", locs = set("INVTYPE_2HWEAPON"), inv = {16} },
    { key = "OFF",      label = L["보조 장비"], labelKo = "보조 장비", locs = set("INVTYPE_SHIELD", "INVTYPE_HOLDABLE", "INVTYPE_WEAPONOFFHAND"), inv = {17} },
    { key = "RANGED",   label = L["원거리/성물"], labelKo = "원거리/성물", locs = set("INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC"), inv = {18} },
}
-- DW 가능 직업은 한손 무기도 보조 장비 후보가 됨 (Core에서 처리)
ns.OFF_EXTRA_LOCS = set("INVTYPE_WEAPON")

-- 아이템 장착 부위 -> 인덱싱 대상 여부
ns.EQUIP_LOCS = {}
for _, g in ipairs(ns.GROUPS) do
    for loc in pairs(g.locs) do ns.EQUIP_LOCS[loc] = true end
end

-- 능력치 토큰 (GetItemStats 기준)
local STR, AGI, STA, INT, SPI = "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT"
local AP, RAP = "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT"
local MP5, DPS, ARMOR = "ITEM_MOD_MANA_REGENERATION_SHORT", "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", "RESISTANCE0_NAME"
local DEF = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"

-- 정렬 기준으로 고를 수 있는 능력치 (여러 개를 고르면 합계 순)
ns.SORT_STATS = {
    { key = "armor", label = "방어도", tokens = { ARMOR } },
    { key = "dps",   label = "초당 공격력", tokens = { DPS } },
    { key = "str",   label = "힘", tokens = { STR } },
    { key = "agi",   label = "민첩성", tokens = { AGI } },
    { key = "sta",   label = "체력", tokens = { STA } },
    { key = "int",   label = "지능", tokens = { INT } },
    { key = "spi",   label = "정신력", tokens = { SPI } },
    { key = "sp",    label = "주문력", tokens = { "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" } },
    { key = "heal",  label = "치유량", tokens = { "ITEM_MOD_HEALING_DONE_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT" } },
    { key = "ap",    label = "전투력", tokens = { AP, RAP } },
    { key = "mp5",   label = "5초당 마나 회복", tokens = { MP5 } },
    { key = "def",   label = "방어 숙련도", tokens = { DEF } },
    { key = "hit",   label = "적중도", tokens = { "ITEM_MOD_HIT_RATING_SHORT" } },
    { key = "crit",  label = "치명타", tokens = { "ITEM_MOD_CRIT_RATING_SHORT" } },
}

-- 특성별 능력치 가치 (v). Core/StatWeights.lua가 게임 환산값으로 아이템 능력치 가중치를 만든다.
--  role: phys = 전투력 기준, caster = 주문 공격력 기준, heal = 치유량 기준 (그 단위로 값을 매김)
--  능력치 1점의 가치: str, agi(추가분), sta, int, spi, mp5, ap, sp, sdmg, heal, armor(민첩 방어도 포함), armorItem(아이템 방어도),
--                     def/defOver(방어 숙련 1, 440 넘으면), blockv(방패 피해 방어량), pierce(주문 관통력, 60레벨 기준)
--  1%의 가치 (60레벨 기준, 지금 전투력·주문력에 맞춰 줄어듦): crit, haste, hit/hitOver(근접·원거리 적중, 상한 넘으면),
--                     spellHit/spellHitOver(주문 적중), exp/expOver(숙련 6.5%까지 / 14%까지)
--  탱커 1%의 가치 (줄이지 않음): dodge, parry, block
--  intCrit = 지능의 주문 치명타도 셈, strAP/agiAP = 힘·민첩 1당 전투력(없으면 게임 값), capMelee = 60레벨 근접 적중 상한
--  dps = 무기 초당 공격력 1의 가치 (main 주무기, off 보조, ranged 원거리)
--  school = 계열별 주문 공격력("화염 계열 주문 공격력 +X")을 주문 공격력의 몇 배로 칠지 (그 계열 주문의 비중)
ns.SPECS = {
    WARRIOR = {
        { name = L["분노/무기 (딜)"], nameKo = "분노/무기 (딜)", v = { role = "phys",
            crit = 30, hit = 30, hitOver = 5, exp = 25, haste = 12, sta = 0.2, armor = 0.005, capMelee = 8,
            dps = { main = 20, off = 10, ranged = 0 } } },
        { name = L["방어 (탱)"], nameKo = "방어 (탱)", v = { role = "phys",
            sta = 12, armor = 0.3, blockv = 0.4, def = 5.5, defOver = 2, block = 10, dodge = 25, parry = 25,
            exp = 115, expOver = 46, hit = 60, crit = 34, haste = 21, capMelee = 8,
            dps = { main = 10, off = 0, ranged = 0 } } },
    },
    PALADIN = {
        { name = L["징벌 (딜)"], nameKo = "징벌 (딜)", v = { role = "phys", ap = 0.5, sp = 1.3, school = { holy = 1 }, int = 1.1, sta = 0.2,
            crit = 10, hit = 30, exp = 24, haste = 6, capMelee = 8,
            dps = { main = 40, off = 0, ranged = 0 } } },
        { name = L["신성 (힐)"], nameKo = "신성 (힐)", v = { role = "heal", heal = 1, sdmg = 0,
            int = 0.6, intCrit = true, spi = 0.25, mp5 = 1.2, sta = 0.05, crit = 7, haste = 5 } },
        { name = L["보호 (탱)"], nameKo = "보호 (탱)", v = { role = "caster", sp = 1, school = { holy = 1 },
            sta = 2.2, def = 1.2, defOver = 0.5, armor = 0.05, blockv = 0.3, int = 0.15, intCrit = true, str = 0.1,
            hit = 12, spellHit = 9, exp = 15, expOver = 7.5, crit = 12, haste = 7, dodge = 6, parry = 6, block = 2, capMelee = 8,
            dps = { main = 3, off = 0, ranged = 0 } } },
    },
    HUNTER = {
        { name = L["사냥꾼 (딜)"], nameKo = "사냥꾼 (딜)", v = { role = "phys", ranged = true,
            hit = 46, crit = 40, haste = 10, int = 1.2, spi = 0.2, sta = 0.15, str = 0.1, capMelee = 8,
            dps = { main = 2, off = 1, ranged = 30 } } },
    },
    ROGUE = {
        { name = L["도적 (딜)"], nameKo = "도적 (딜)", v = { role = "phys",
            crit = 20, hit = 13, spellHit = 17, exp = 26, haste = 14.3, sta = 0.2, capMelee = 8,
            dps = { main = 20, off = 10, ranged = 0 } } },
    },
    PRIEST = {
        { name = L["신성/수양 (힐)"], nameKo = "신성/수양 (힐)", v = { role = "heal", heal = 1, sdmg = 0,
            int = 0.5, intCrit = true, mp5 = 0.6, spi = 0.52, sta = 0.05, crit = 7, haste = 5 } },
        { name = L["암흑 (딜)"], nameKo = "암흑 (딜)", v = { role = "caster", sp = 1, school = { shadow = 1 },
            int = 0.3, intCrit = true, spi = 0.2, sta = 0.05, pierce = 0.6, spellHit = 15, crit = 12, haste = 6 } },
    },
    SHAMAN = {
        { name = L["정기 (딜)"], nameKo = "정기 (딜)", v = { role = "caster", sp = 1, school = { nature = 0.8, fire = 0.3 },
            pierce = 1.6, int = 0.3, intCrit = true, spi = 0.1, sta = 0.05, haste = 12, spellHit = 11, crit = 10 } },
        { name = L["고양 (딜)"], nameKo = "고양 (딜)", v = { role = "phys", school = { nature = 0.4, fire = 0.3, frost = 0.2 },
            int = 2.2, sp = 2.1, sdmg = 2.1, pierce = 1.9, spi = 0.3, sta = 0.2,
            haste = 18, crit = 24, hit = 20, spellHit = 10, exp = 25, capMelee = 8,
            dps = { main = 20, off = 10, ranged = 0 } } },
        { name = L["복원 (힐)"], nameKo = "복원 (힐)", v = { role = "heal", heal = 1, sdmg = 0,
            int = 0.5, intCrit = true, spi = 0.4, mp5 = 0.35, sta = 0.05, crit = 11, haste = 7 } },
    },
    MAGE = {
        { name = L["마법사 (딜)"], nameKo = "마법사 (딜)", v = { role = "caster", sp = 1, school = { fire = 0.45, frost = 0.45, arcane = 0.3 },
            pierce = 0.9, int = 0.35, intCrit = true, spi = 0.12, sta = 0.05, spellHit = 15, crit = 12, haste = 7 } },
    },
    WARLOCK = {
        { name = L["흑마법사 (딜)"], nameKo = "흑마법사 (딜)", v = { role = "caster", sp = 1, school = { shadow = 0.8, fire = 0.4 },
            pierce = 1.25, int = 0.25, intCrit = true, spi = 0.12, sta = 0.1, crit = 10, spellHit = 9, haste = 5 } },
    },
    DRUID = {
        { name = L["조화 (딜)"], nameKo = "조화 (딜)", v = { role = "caster", sp = 1, school = { arcane = 0.6, nature = 0.5 },
            pierce = 1.0, int = 0.3, intCrit = true, spi = 0.15, sta = 0.05, spellHit = 15, crit = 9, haste = 6 } },
        { name = L["야성 (딜)"], nameKo = "야성 (딜)", v = { role = "phys", feral = true, agiAP = 1,
            sta = 0.2, int = 0.05, spi = 0.05, crit = 30, hit = 27, exp = 24, haste = 18, capMelee = 8,
            dps = { main = 8, off = 0, ranged = 0 } } },
        { name = L["야성 (탱)"], nameKo = "야성 (탱)", v = { role = "phys", feral = true, agiAP = 0,
            sta = 10, armorItem = 1.2, armor = 0.3, def = 4, defOver = 1.5, dodge = 25, hit = 30, exp = 30, crit = 20, haste = 15, capMelee = 8,
            dps = { main = 5, off = 0, ranged = 0 } } },
        { name = L["회복 (힐)"], nameKo = "회복 (힐)", v = { role = "heal", heal = 1, sdmg = 0,
            int = 0.45, intCrit = true, spi = 0.62, mp5 = 0.4, sta = 0.05, crit = 9, haste = 6 } },
    },
}

-- 아이템 레벨 가중치: 점수가 같을 때만 순서를 가르는 아주 작은 보조점수
ns.ILVL_WEIGHT = 0.001

-- 업그레이드 판정: 착용 중인 장비보다 이 비율 + 고정치 이상 높아야 ▲ (미세한 차이는 무시)
ns.UPGRADE_MARGIN_PCT = 0.05
ns.UPGRADE_MARGIN_ABS = 0.5

-- 언어 강제 설정(/bgf lang)이 적용된 뒤 슬롯/스펙 이름을 다시 번역한다.
function ns.RelabelData()
    for _, g in ipairs(ns.GROUPS or {}) do
        if g.labelKo then g.label = L[g.labelKo] end
    end
    for _, list in pairs(ns.SPECS or {}) do
        for _, sp in ipairs(list) do
            if sp.nameKo then sp.name = L[sp.nameKo] end
        end
    end
end
