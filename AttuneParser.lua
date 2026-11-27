-- ============================================================================
-- AttuneParser.lua (WoW Prime 3.3.5a)
-- Standalone server-synced absorption, stats & progression parser.
-- Serves as a shared bridge for TalorianTP and future recommendation addons.
-- Safe against taint (never mutates Blizzard/FrameXML globals) and #134 crashes
-- (warmer throttles outside combat and instances).
-- ============================================================================

local AP = _G.AttuneParser or {}
_G.AttuneParser = AP

AP.VERSION = "1.3.0"
AP.Data = AP.Data or {}

-- User-confirmed server tier defaults (replaced live when ASMSG_ATTUNE_TIERS arrives)
AP.TIER_NAMES = {
    [0] = "Обычный",
    [1] = "Эпический",
    [2] = "Легендарный",
    [3] = "Титанический",
}
AP.TIER_PCT = {
    [0] = 20,
    [1] = 30,
    [2] = 50,
    [3] = 90,
}
AP.TIER_SOURCE = "default"
AP.MAX_TIER = 3

AP.STAT_NAMES = {
    [4] = "Сила", [3] = "Ловкость", [7] = "Выносливость", [5] = "Интеллект", [6] = "Дух",
    [38] = "Сила атаки", [39] = "Сила атаки (дальн.)", [45] = "Сила заклинаний",
    [32] = "Крит. удар", [19] = "Крит в ближнем бою", [20] = "Крит в дальнем бою", [21] = "Крит заклинаний",
    [36] = "Скорость", [28] = "Скорость в ближнем бою", [29] = "Скорость дальнего боя", [30] = "Скорость заклинаний",
    [31] = "Меткость", [16] = "Меткость в ближнем бою", [17] = "Меткость дальнего боя", [18] = "Меткость заклинаний",
    [37] = "Мастерство", [44] = "Пробивание брони", [35] = "Устойчивость",
    [47] = "Проникающая способность", [43] = "Восстановление маны", [46] = "Восстановление здоровья",
    [12] = "Защита", [13] = "Уклонение", [14] = "Парирование",
    [15] = "Рейтинг блока", [48] = "Показатель блока",
    [1000] = "Броня", [1] = "Здоровье",
}

AP.STAT_ORDER = {
    4, 3, 7, 5, 6, 38, 39, 45,
    32, 19, 20, 21, 36, 28, 29, 30, 31, 16, 17, 18,
    37, 44, 35, 47, 43, 46, 12, 13, 14, 15, 48,
}

-- Server runtime state
AP.SOURCE_TYPES = {
    [1] = "Существо", [2] = "Объект", [3] = "Продавец", [4] = "Задание",
    [5] = "Рыбалка", [6] = "Снятие шкур", [7] = "Ремесло", [8] = "Эпохальный ключ",
}
AP.serverSummary = AP.serverSummary or nil
AP.serverZones = AP.serverZones or {}         -- [zoneId] = { id, remain, total, name }
AP.serverZoneItems = AP.serverZoneItems or {} -- [topZoneId][entry] = { quality, slot, srcType, absorbed, modeMask, pct, suffix }
AP.serverAbsorbedItems = AP.serverAbsorbedItems or {} -- [entry] = true (O(1) fast lookup)
AP.serverItemSources = AP.serverItemSources or {} -- [entry] = { {st, smp, z, mp, cnt, zn, sn, disp, chance, spawns, sx, sy}, ... }
AP.serverSpawns = AP.serverSpawns or {}      -- [cid] = { {map, zone, x, y}, ... }
AP.serverMilestones = AP.serverMilestones or { loaded = false, count = 0, list = {}, claimable = 0 }
AP.forgeEquip = AP.forgeEquip or {}          -- [invSlot] = tier (0..3)
AP.forgeBag = AP.forgeBag or {}              -- [bag][slot] = tier
AP.forgeGuild = AP.forgeGuild or {}          -- [tab][slot] = tier
AP.forgeByEntry = AP.forgeByEntry or {}      -- [entry] = tier
AP.auctionForge = AP.auctionForge or {}      -- ["entry:buyout:count"] = tier
AP.questCompleted = AP.questCompleted or {}  -- [questId] = true
AP.xItemCache = AP.xItemCache or {}           -- [entry] = { v, m, l, a, s }
AP.activeGift = AP.activeGift or nil
AP.paragon = AP.paragon or { level = 0, curXP = 0, maxXP = 0, loaded = false }
AP.guildAttuneBonusPct = AP.guildAttuneBonusPct or 0
AP.worldLocked80 = AP.worldLocked80 or false
AP.mentorWhere = AP.mentorWhere or nil
AP.petLootState = AP.petLootState or { rev = -1, count = 0, total = 0, dspHas = 0, dspSkill = 0, proto = 0, flags = 0, sellMask = 7, vendor = 0, balance = 0, loaded = false }
AP.petLootItems = AP.petLootItems or {}      -- [dbId] = { dbId, itemId, count, forgeTier, absBP, done, sfx, dspReq }
AP.petLootJunk = AP.petLootJunk or { summary = nil, running = nil, askPending = false }
AP.bagum = AP.bagum or { open = false, r1 = 3, r2 = 3, rev1 = 3, rev2 = 3, fee = 1000000, dustEn = false, d = { 0, 0, 0 }, c = { 0, 0, 0, 0 }, frost = 0 }
AP.autoSwap = AP.autoSwap or {
    on = nil, groupMask = nil, qualMask = nil, orderWorst = nil, boeAllowed = nil,
    unlocked = nil, sellMask = nil, srcMask = nil, confirm = nil, active = nil,
    blacklist = {}, blacklistByEntry = {},
}
AP.forgeViewTrade = AP.forgeViewTrade or {}
AP.forgeViewPlayerTrade = AP.forgeViewPlayerTrade or {}
AP.forgeViewInspect = AP.forgeViewInspect or {}
AP.DAILY_GIFT_NAMES = {
    ["Дар Понедельника"] = "mon",
    ["Дар Вторника"]     = "tue",
    ["Дар Среды"]        = "wed",
    ["Дар Четверга"]     = "thu",
    ["Дар Пятницы"]      = "fri",
    ["Дар Субботы"]      = "sat",
    ["Дар Воскресенья"]  = "sun",
}
AP.FORGE_ITEM_IDS = {
    dustEpic = 70017, -- Мерцающая пыль
    dustLeg  = 70018, -- Пылающая пыль
    dustTit  = 70019, -- Астральная пыль
    titanBoxes = { 90628, 90631, 90634, 90636 },
    frostEmblem = 49426,
    triumphEmblem = 47241,
}

AP.ZONE_ICONS = {
    [206]  = "Achievement_Dungeon_UtgardeKeep_Normal",
    [207]  = "INV_Misc_Map_01",
    [209]  = "Achievement_Boss_ArchmageArugal",
    [491]  = "Achievement_Boss_CharlgaRazorflank",
    [717]  = "Achievement_Boss_Bazil_Thredd",
    [718]  = "Achievement_Boss_Mutanus_the_Devourer",
    [719]  = "Achievement_Boss_Bazil_Akumai",
    [721]  = "INV_Misc_Head_Gnome_01",
    [722]  = "Achievement_Boss_Amnennar_the_Coldbringer",
    [796]  = "Spell_Holy_SealOfFury",
    [1176] = "Achievement_Boss_ChiefUkorzSandscalp",
    [1196] = "Achievement_Dungeon_UtgardePinnacle_Normal",
    [1337] = "Achievement_Boss_Archaedas",
    [1417] = "Achievement_Boss_ShadeOfEranikus",
    [1581] = "Achievement_Boss_EdwinVancleef",
    [1583] = "Achievement_Boss_GeneralDrakkisath",
    [1584] = "Achievement_Boss_EmperorDagranThaurissan",
    [1977] = "Achievement_Boss_Hakkar",
    [2017] = "Achievement_Zone_EasternPlaguelands",
    [2057] = "INV_Misc_Book_11",
    [2100] = "Achievement_Boss_PrincessTheradras",
    [2159] = "Achievement_Boss_Onyxia",
    [2366] = "Achievement_Boss_Aeonus_01",
    [2367] = "Achievement_Boss_EpochHunter",
    [2437] = "Achievement_Zone_Durotar",
    [2557] = "Achievement_Zone_Feralas",
    [2677] = "Achievement_Boss_Nefarion",
    [2717] = "Achievement_Boss_Ragnaros",
    [3428] = "Achievement_Boss_CThun",
    [3429] = "Achievement_Boss_OssirianTheUnscarred",
    [3456] = "Achievement_Dungeon_Naxxramas_Normal",
    [3457] = "Achievement_Boss_PrinceMalchezaar_02",
    [3535] = "Spell_Shadow_DeathCoil",
    [3562] = "Achievement_Boss_OmarTheUnscarred_01",
    [3606] = "INV_Offhand_Hyjal_D_01",
    [3607] = "Achievement_Boss_LadyVashj",
    [3713] = "Achievement_Boss_KelidanTheBreaker",
    [3714] = "Achievement_Boss_KargathBladefist_01",
    [3715] = "Achievement_Boss_Warlord_Kalithresh",
    [3716] = "Achievement_Boss_TheBlackStalker",
    [3717] = "Achievement_Boss_Quagmirran",
    [3789] = "Achievement_Boss_Murmur",
    [3790] = "Achievement_Boss_Exarch_Maladaar",
    [3791] = "Achievement_Boss_TalonKingIkiss",
    [3792] = "Achievement_Boss_Nexus_Prince_Shaffar",
    [3805] = "Achievement_Boss_Zuljin",
    [3836] = "Achievement_Boss_Magtheridon",
    [3842] = "Spell_Arcane_PortalShattrath",
    [3845] = "Achievement_Boss_Kael'thasSunstrider_01",
    [3847] = "Achievement_Boss_WarpSplinter",
    [3848] = "Achievement_Boss_Harbinger_Skyriss",
    [3849] = "Achievement_Boss_PathaleonTheCalculator",
    [3923] = "Achievement_Boss_GruulTheDragonkiller",
    [3959] = "Achievement_Boss_Illidan",
    [4075] = "Achievement_Boss_Kiljaedan",
    [4100] = "Achievement_Dungeon_CoTStratholme_Normal",
    [4131] = "Achievement_Boss_Kael'thasSunstrider_01",
    [4196] = "Achievement_Dungeon_Drak'Tharon_Normal",
    [4228] = "Achievement_Dungeon_Nexus80_Normal",
    [4264] = "Achievement_Dungeon_Ulduar77_Normal",
    [4265] = "Achievement_Dungeon_Nexus70_Normal",
    [4272] = "Achievement_Dungeon_Ulduar80_Normal",
    [4273] = "Achievement_Dungeon_UlduarRaid_Misc_01",
    [4277] = "Achievement_Dungeon_AzjolLowercity_Normal",
    [4415] = "Achievement_Dungeon_TheVioletHold_Normal",
    [4416] = "Achievement_Dungeon_Gundrak_Normal",
    [4493] = "Achievement_Boss_Sartharion_01",
    [4494] = "Achievement_Dungeon_AzjolUppercity_Normal",
    [4500] = "Achievement_Boss_Malygos_01",
    [4603] = "INV_Misc_Statue_07",
    [4722] = "Achievement_Reputation_ArgentCrusader",
    [4723] = "Achievement_Reputation_ArgentCrusader",
    [4809] = "Achievement_Dungeon_Icecrown_ForgeofSouls",
    [4812] = "Achievement_Boss_LichKing",
    [4813] = "Achievement_Dungeon_Icecrown_PitofSaron",
    [4820] = "Achievement_Dungeon_Icecrown_HallsofReflection",
    [4987] = "Spell_Shadow_Twilight",
}

function AP.FormatMult(m)
    m = tonumber(m) or 1
    local s = string.format("%.2f", m)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    return (s == "" or s == "-0") and "1" or s
end

function AP:GetZoneIcon(zoneId, isRaid, isInstanceZone)
    local ic = AP.ZONE_ICONS and AP.ZONE_ICONS[zoneId]
    if ic then
        return ic:find("\\", 1, true) and ic or ("Interface\\Icons\\" .. ic)
    end
    if isRaid == true then
        return "Interface\\Icons\\Achievement_Dungeon_GloryoftheRaider"
    elseif isInstanceZone ~= false then
        return "Interface\\Icons\\Achievement_Dungeon_Heroic_GloryoftheHero"
    end
    return "Interface\\Icons\\INV_Misc_Map_01"
end

-- ============================================================================
-- Module 1: Scheduler, Callbacks, Helpers & Memoization Caches
-- ============================================================================
do
    local jobs = {}
    local jobFrame = CreateFrame("Frame")
    jobFrame:Hide()
    jobFrame:SetScript("OnUpdate", function(self)
        local now = GetTime()
        local due = nil
        for i = #jobs, 1, -1 do
            if now >= jobs[i].t then
                due = due or {}
                table.insert(due, 1, table.remove(jobs, i))
            end
        end
        if due then
            table.sort(due, function(a, b) return a.t < b.t end)
            for _, j in ipairs(due) do
                local ok, err = pcall(j.f)
                if not ok and geterrorhandler then
                    geterrorhandler()(err)
                end
            end
        end
        if #jobs == 0 then
            self:Hide()
        end
    end)

    function AP.After(delay, fn, tag)
        if type(fn) ~= "function" then return end
        if tag then
            for i = #jobs, 1, -1 do
                if jobs[i].tag == tag then table.remove(jobs, i) end
            end
        end
        table.insert(jobs, { t = GetTime() + (tonumber(delay) or 0), f = fn, tag = tag })
        jobFrame:Show()
    end

    function AP.Cancel(tag)
        if not tag then return end
        for i = #jobs, 1, -1 do
            if jobs[i].tag == tag then table.remove(jobs, i) end
        end
        if #jobs == 0 then jobFrame:Hide() end
    end

    local callbacks = {}
    function AP:RegisterCallback(event, fn)
        if not event or type(fn) ~= "function" then return end
        callbacks[event] = callbacks[event] or {}
        table.insert(callbacks[event], fn)
    end

    function AP:UnregisterCallback(event, fn)
        local list = event and callbacks[event]
        if not list then return end
        for i = #list, 1, -1 do
            if list[i] == fn then table.remove(list, i) end
        end
    end

    function AP:Fire(event, a1, a2, a3)
        local list = callbacks[event]
        if not list then return end
        for _, fn in ipairs(list) do
            pcall(fn, event, a1, a2, a3)
        end
    end

    local zoneCache = {}
    local statusCache = {}
    local absorbCache = {}
    local heavyQuestCache = {}
    local itemMetaCache = {}
    local sourceCache = {}
    local noReqCache = nil

    function AP:InvalidateCaches(zoneOnly)
        zoneCache = {}
        statusCache = {}
        noReqCache = nil
        if not zoneOnly then
            itemMetaCache = {}
            absorbCache = {}
            heavyQuestCache = {}
            sourceCache = {}
        end
    end

    function AP:InvalidateZoneCache(zoneId)
        if not zoneId then
            zoneCache = {}
            return
        end
        local topId = (AP.Data and AP.Data.TopMap and AP.Data.TopMap[zoneId]) or zoneId
        local prefix = tostring(topId) .. ":"
        local plen = #prefix
        for k in pairs(zoneCache) do
            if k:sub(1, plen) == prefix then
                zoneCache[k] = nil
            end
        end
    end

    function AP:InvalidateItemStatus(eid)
        if eid then
            statusCache[eid] = nil
        else
            statusCache = {}
        end
    end

    function AP.FormatChance(ch)
        ch = tonumber(ch) or 0
        if ch <= 0 then return nil end
        local pc = ch / 100
        if pc >= 1 then
            return string.format("%.1f%%", pc)
        end
        return string.format("%.2f%%", pc)
    end

    AP._mem = {
        zoneCache = function() return zoneCache end,
        setZoneCache = function(k, v) zoneCache[k] = v end,
        statusCache = function() return statusCache end,
        absorbCache = function() return absorbCache end,
        heavyQuestCache = function() return heavyQuestCache end,
        itemMetaCache = itemMetaCache,
        sourceCache = sourceCache,
        getNoReqCache = function() return noReqCache end,
        setNoReqCache = function(v) noReqCache = v end,
    }

    function AP.ExtractItemId(linkOrId)
        if type(linkOrId) == "number" then return linkOrId end
        if type(linkOrId) == "string" then
            return tonumber(linkOrId:match("item:(%d+)") or linkOrId:match("^(%d+)$"))
        end
        return nil
    end

    function AP.ExtractSuffix(link)
        if type(link) ~= "string" then return 0 end
        return tonumber(link:match("item:%d+:%-?%d*:%-?%d*:%-?%d*:%-?%d*:%-?%d*:(%-?%d+)")) or 0
    end

    do
        local CYR_LOWER = {
            ["А"]="а",["Б"]="б",["В"]="в",["Г"]="г",["Д"]="д",["Е"]="е",["Ё"]="е",["ё"]="е",
            ["Ж"]="ж",["З"]="з",["И"]="и",["Й"]="й",["К"]="к",["Л"]="л",["М"]="м",["Н"]="н",
            ["О"]="о",["П"]="п",["Р"]="р",["С"]="с",["Т"]="т",["У"]="у",["Ф"]="ф",["Х"]="х",
            ["Ц"]="ц",["Ч"]="ч",["Ш"]="ш",["Щ"]="щ",["Ъ"]="ъ",["Ы"]="ы",["Ь"]="ь",["Э"]="э",
            ["Ю"]="ю",["Я"]="я",
        }

        function AP.Norm(s)
            if type(s) ~= "string" then return "" end
            s = s:lower()
            s = s:gsub("[%z\1-\127\194-\244][\128-\191]*", function(ch)
                return CYR_LOWER[ch] or ch
            end)
            s = s:gsub("[\"«»'`.,:;!?%(%)%[%]]+", " ")
            s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
            return s
        end

        AP.DEFAULT_SETTINGS = {
            showMinimap = true,
            minimapAngle = 225,
            showPrimeHub = true,
            showAuctionUI = true,
            showEJOverlay = true,
            showEJBadges = true,
            tradeAlert = true,
            wedAuto = true,
            onlyUnlocked = false,
            excludeHeavyQuests = true,
            autoWarmStats = true,
            talorianMode = "auto",
            topMode = "new",
            scope = "hero",
            eraFilter = "All",
            kindFilter = "All",
            sortBy = "default",
            ejOverlaySide = "RIGHT",
            ejDocked = true,
            aucDocked = true,
            aucFrameOpen = true,
            ibAutoEquip = false,
            ibUseAAMask = false,
            ibEquipInCombat = true,
            ibAutoPut = false,
            ibAutoPutMode = "unabsorbed",
            ibPutKeepSets = true,
            valdrisMaxTier = 3,
            valdrisAutoOpen = false,
            valdrisIncludeEquipped = false,
            valdrisIncludeBank = true,
            uiOnboardingDone = false,
            showValdrisBar = true,
            blkHeaderLinks = true,
            blkTabSummary = true,
            blkTabBags = true,
            blkTabSets = true,
            blkTabServer = true,
            blkSumCatalog = true,
            blkSumGiftsDust = true,
            blkSumParagonAuto = true,
            blkSumStats = true,
            blkBagsActions = true,
            blkSrvAuto = true,
            blkSrvBanks = true,
            blkSrvBosses = true,
        }

        AP.UI_BLOCK_DEFS = {
            {
                key = "blkHeaderLinks",
                title = "Быстрые кнопки в шапке окна",
                desc = "Кнопки «Талориан», «Атлас», «Путеводитель» и «Вехи» в правом верхнем углу окна. Уберите для минималистичной шапки.",
                default = true,
            },
            {
                key = "blkTabSummary",
                title = "Вкладка «Обзор и Дары»",
                desc = "Общий прогресс аккаунта и героя, вехи, множители опыта, запасы пыли, настройки автоматики и суммарные статы персонажа.",
                default = true,
            },
            {
                key = "blkTabBags",
                title = "Вкладка «Сумки и Ковка»",
                desc = "Список непоглощенных и недокованных вещей в сумках, банке, Хранилище, Банке вещей и гильдбанке + черный список.",
                default = true,
            },
            {
                key = "blkTabSets",
                title = "Вкладка «Сеты T9 / T10»",
                desc = "Таблица комплектов T9 и T10 с быстрой проверкой недостающих слотов и статуса поглощения.",
                default = true,
            },
            {
                key = "blkTabServer",
                title = "Вкладка «События и Боссы»",
                desc = "Серверная панель: автопоглощение, автопродажа, автосклад в Банк вещей, расщепление, Ключи M+ и таймеры мировых боссов.",
                default = true,
            },
            {
                key = "blkSumCatalog",
                title = "Обзор: Каталог, Вехи и Талориан",
                desc = "Первая карточка «Обзора»: число освоенных предметов, награды вех, прогресс скана и связь со спутником.",
                default = true,
            },
            {
                key = "blkSumGiftsDust",
                title = "Обзор: Бонус дня, Опыт и Пыль",
                desc = "Вторая карточка «Обзора»: текущий дар дня, формулы опыта поглощения и Paragon, остатки пыли и сундуков.",
                default = true,
            },
            {
                key = "blkSumParagonAuto",
                title = "Обзор: Доп. уровень, Спек и Автоматика",
                desc = "Третья карточка «Обзора»: уровень Paragon, активная специализация, статус автоэкипировки и Ключей M+.",
                default = true,
            },
            {
                key = "blkSumStats",
                title = "Обзор: Суммарные статы поглощения",
                desc = "Четвертая карточка «Обзора»: суммарная таблица характеристик (Сила, СПД, Крит, Скорость и т.д.) от поглощения.",
                default = true,
            },
            {
                key = "blkBagsActions",
                title = "Сумки: Нижняя панель действий",
                desc = "Кнопки внизу вкладки «Сумки и Ковка» для быстрого автопоглощения, автосклада и сдачи ресурсов.",
                default = true,
            },
            {
                key = "blkSrvAuto",
                title = "События: Блок Автопоглощения и Автопродажи",
                desc = "Левая колонка вкладки «События и Боссы»: слоты, качество, черный список, автонадевание и автосклад в Банк вещей.",
                default = true,
            },
            {
                key = "blkSrvBanks",
                title = "События: Хранилища, Расщепление и M+",
                desc = "Верхняя часть правой колонки: статусы банков, расщепления предметов и сундуков Ключей M+.",
                default = true,
            },
            {
                key = "blkSrvBosses",
                title = "События: Таймеры мировых боссов",
                desc = "Нижняя часть правой колонки: список мировых боссов и оставшееся время до их возрождения.",
                default = true,
            },
            {
                key = "showValdrisBar",
                title = "Панель прогрессии Вальдриса",
                desc = "Встроенная верхняя панель в окне улучшения вещей (выбор предмета по иконкам, цель до 90%% и автоулучшение).",
                default = true,
            },
            {
                key = "showAuctionUI",
                title = "Помощник ковки на аукционе",
                desc = "Кнопка и боковое окно на аукционе с подсветкой непоглощенных и выгодных для ковки лотов.",
                default = true,
            },
            {
                key = "showEJOverlay",
                title = "Боковая панель в Путеводителе",
                desc = "Оверлей рядом с Путеводителем по приключениям: сводка инста, вещи в сумках и телепорт Талориана.",
                default = true,
            },
            {
                key = "showEJBadges",
                title = "Значки добычи в Путеводителе",
                desc = "Цветные метки прогресса и процентов ковки прямо на строках предметов у боссов в Путеводителе.",
                default = true,
            },
            {
                key = "tradeAlert",
                title = "Оповещение в чате при обмене (Trade)",
                desc = "Подсказка в чат при получении вещей в обмене с расчетом прибавки статов от поглощения.",
                default = true,
            },
            {
                key = "showMinimap",
                title = "Кнопка у миникарты",
                desc = "Иконка AttuneParser вокруг миникарты (окно всегда можно открыть командой /ap).",
                default = true,
            },
            {
                key = "showPrimeHub",
                title = "Значок в общем меню PrimeHub",
                desc = "Плитка AttuneParser на общей панели аддонов PrimeHub.",
                default = true,
            },
        }

        function AP:IsBlockEnabled(key)
            return self:GetSetting(key) ~= false
        end

        function AP:SetBlockEnabled(key, val)
            return self:SetSetting(key, val and true or false)
        end

        function AP:ApplyUIBlockPreset(preset)
            local presets = {
                full = {},
                minimal = {
                    blkHeaderLinks = false,
                    blkTabSummary = false,
                    blkTabBags = false,
                    blkTabSets = false,
                    blkTabServer = false,
                    blkSumCatalog = true,
                    blkSumGiftsDust = true,
                    blkSumParagonAuto = true,
                    blkSumStats = true,
                    blkBagsActions = false,
                    blkSrvAuto = true,
                    blkSrvBanks = true,
                    blkSrvBosses = true,
                    showValdrisBar = true,
                    showAuctionUI = true,
                    showEJOverlay = false,
                    showEJBadges = true,
                    tradeAlert = false,
                    showMinimap = true,
                    showPrimeHub = true,
                },
                farm = {
                    blkHeaderLinks = true,
                    blkTabSummary = true,
                    blkTabBags = true,
                    blkTabSets = false,
                    blkTabServer = true,
                    blkSumCatalog = true,
                    blkSumGiftsDust = true,
                    blkSumParagonAuto = false,
                    blkSumStats = false,
                    blkBagsActions = true,
                    blkSrvAuto = true,
                    blkSrvBanks = false,
                    blkSrvBosses = true,
                    showValdrisBar = true,
                    showAuctionUI = true,
                    showEJOverlay = true,
                    showEJBadges = true,
                    tradeAlert = true,
                    showMinimap = true,
                    showPrimeHub = true,
                },
            }
            local map = presets[preset] or {}
            for _, def in ipairs(AP.UI_BLOCK_DEFS) do
                local v = map[def.key]
                if v == nil then v = true end
                self:SetSetting(def.key, v)
            end
        end

        function AP:EnsureSettings()
            AttuneParserDB = AttuneParserDB or {}
            if type(AttuneParserDB.settings) ~= "table" then
                AttuneParserDB.settings = {}
            end
            local st = AttuneParserDB.settings
            for k, v in pairs(AP.DEFAULT_SETTINGS) do
                if st[k] == nil then
                    st[k] = v
                end
            end
            return st
        end

        function AP:GetSettings()
            return AP:EnsureSettings()
        end

        function AP:GetSetting(k)
            local st = AP:EnsureSettings()
            return st[k]
        end

        function AP:SetSetting(k, v)
            local st = AP:EnsureSettings()
            local old = st[k]
            st[k] = v
            if old ~= v then
                if k == "excludeHeavyQuests" then
                    AP:InvalidateZoneCache(nil)
                end
                AP:Fire("SETTINGS_UPDATED", k, v)
                if k == "showPrimeHub" or k == "showMinimap" then
                    local ph = rawget(_G, "PrimeHub")
                    if ph and type(ph.Refresh) == "function" then
                        pcall(ph.Refresh, ph)
                    end
                end
            end
            return v
        end

        function AP:ResetAuctionPos()
            local st = AP:EnsureSettings()
            st.aucBtnPos = nil
            st.aucFramePos = nil
            st.aucDocked = true
            st.aucFrameOpen = true
            AP:Fire("SETTINGS_UPDATED", "aucBtnPos", nil)
        end

        function AP:GetLockedZonesMap()
            local locked = {}
            local byName = {}
            if type(GetNumSavedInstances) ~= "function" then return locked end
            local n = GetNumSavedInstances() or 0
            local zNameToId = AP._mem.normZoneLookup
            if not zNameToId then
                zNameToId = {}
                for zid, zMeta in pairs(AP.Data and AP.Data.Zones or {}) do
                    if zMeta.name then
                        local nz = AP.Norm(zMeta.name)
                        if nz ~= "" and not zNameToId[nz] then
                            zNameToId[nz] = zid
                        end
                    end
                end
                AP._mem.normZoneLookup = zNameToId
            end
            for i = 1, n do
                local instName, _, reset, diff, isLocked, _, _, isRaid, maxPlayers, diffName = GetSavedInstanceInfo(i)
                if instName and (isLocked or (reset and reset > 0)) then
                    local nn = AP.Norm(instName)
                    if nn ~= "" then
                        byName[nn] = true
                        local matchedId = zNameToId[nn]
                        if matchedId then
                            locked[matchedId] = true
                        end
                    end
                end
            end
            for zid, zMeta in pairs(AP.Data and AP.Data.Zones or {}) do
                if zMeta.name and not locked[zid] then
                    local nz = AP.Norm(zMeta.name)
                    if nz ~= "" and byName[nz] then
                        locked[zid] = true
                    end
                end
            end
            return locked
        end

        function AP:IsZoneLocked(zoneId, zoneName)
            local locked = AP:GetLockedZonesMap()
            if zoneId and locked[zoneId] then return true end
            if zoneName and zoneName ~= "" then
                local zid = AP:FindZoneByName(zoneName)
                if zid and locked[zid] then return true end
            end
            return false
        end

        function AP:FindZoneByName(name, isRaidHint)
            if type(name) ~= "string" or name == "" then return nil, nil end
            local q = AP.Norm(name)
            if q == "" then return nil, nil end
            local zones = AP.Data and AP.Data.Zones or {}
            local bestId, bestMeta = nil, nil
            for zid, zMeta in pairs(zones) do
                if AP.Data.ZoneItems and AP.Data.ZoneItems[zid] and zMeta.name then
                    if AP.Norm(zMeta.name) == q then
                        if isRaidHint == nil or (zMeta.isRaid == isRaidHint) then
                            return zid, zMeta
                        end
                        bestId, bestMeta = zid, zMeta
                    end
                end
            end
            if bestId then return bestId, bestMeta end
            local bestScore = 9999
            for zid, zMeta in pairs(zones) do
                if AP.Data.ZoneItems and AP.Data.ZoneItems[zid] and zMeta.name then
                    local nz = AP.Norm(zMeta.name)
                    if nz ~= "" and (nz:find(q, 1, true) or q:find(nz, 1, true)) then
                        local score = math.abs(#nz - #q) + ((isRaidHint ~= nil and zMeta.isRaid ~= isRaidHint) and 500 or 0)
                        if score < bestScore then
                            bestScore = score
                            bestId, bestMeta = zid, zMeta
                        end
                    end
                end
            end
            return bestId, bestMeta
        end

        function AP:IsZoneInstance(zoneId)
            local eid = tonumber(zoneId)
            if not eid or eid <= 0 then return false end
            local topId = (AP.Data and AP.Data.TopMap and AP.Data.TopMap[eid]) or eid
            local zm = AP.Data and AP.Data.Zones and AP.Data.Zones[topId]
            if not zm then return false end
            return ((zm.exp and zm.exp > 0) or zm.isRaid == true or zm.cat == 5 or zm.cat == 6) and true or false
        end

        function AP:HasTalorianPet()
            if type(GetNumCompanions) == "function" and type(GetCompanionInfo) == "function" then
                local n = GetNumCompanions("CRITTER") or 0
                for i = 1, n do
                    local _, cName, cSpell, _, active = GetCompanionInfo("CRITTER", i)
                    if cSpell == 91200 or (cName and (cName:find("Талориан", 1, true) or cName:lower():find("talorian", 1, true))) then
                        return true, (active == 1 or active == true), i
                    end
                end
            end
            local b = AP._talorianBridge
            if b and type(b.HasPet) == "function" then
                local ok, hasP, isSum = pcall(b.HasPet)
                if ok then return hasP == true, isSum == true, nil end
            end
            return false, false, nil
        end

        function AP:RegisterTalorianBridge(bridge)
            AP._talorianBridge = bridge
            AP:Fire("TALORIAN_BRIDGE_UPDATED", bridge)
        end

        function AP:GetTalorianStatus()
            local bridgeLoaded = (AP._talorianBridge ~= nil) or (type(rawget(_G, "TalorianTP")) == "table")
            local ttpDb = rawget(_G, "TalorianTP_DB")
            local ttpEnabled = not (type(ttpDb) == "table" and ttpDb.enabled == false)
            local modeOff = (AP:GetSetting("talorianMode") == "off")
            local active = AP:IsTalorianBridgeActive()
            return bridgeLoaded, ttpEnabled, active, modeOff
        end

        function AP:IsTalorianBridgeActive()
            if AP:GetSetting("talorianMode") == "off" then return false end
            local b = AP._talorianBridge
            if b then
                if type(b.IsAvailable) == "function" then
                    local ok, avail = pcall(b.IsAvailable)
                    if ok then return avail == true end
                end
                return AP:HasTalorianPet()
            end
            local ttp = rawget(_G, "TalorianTP")
            if type(ttp) == "table" and (not _G.TalorianTP_DB or _G.TalorianTP_DB.enabled ~= false) then
                return AP:HasTalorianPet()
            end
            return false
        end

        function AP:SelectZoneInTalorian(zoneId, zoneName)
            if not AP:IsTalorianBridgeActive() then return false end
            local b = AP._talorianBridge
            if b and type(b.SelectZone) == "function" then
                local ok, res = pcall(b.SelectZone, zoneId, zoneName)
                return ok and (res ~= false)
            end
            return false
        end

        function AP:OpenTalorianUI()
            local b = AP._talorianBridge
            if b and type(b.OpenUI) == "function" then
                local ok, r1, r2 = pcall(b.OpenUI)
                if type(AP.RaiseFrameFront) == "function" then
                    AP.RaiseFrameFront(rawget(_G, "TalorianMainFrame"))
                end
                return ok, r1, r2
            end
            local ttp = rawget(_G, "TalorianTP")
            if type(ttp) == "table" and type(ttp.OpenUI) == "function" then
                local ok, r1 = pcall(ttp.OpenUI, ttp)
                if type(AP.RaiseFrameFront) == "function" then
                    AP.RaiseFrameFront(rawget(_G, "TalorianMainFrame"))
                end
                return ok, r1
            end
            if SlashCmdList and type(SlashCmdList["TALORIANTP"]) == "function" then
                local ok = pcall(SlashCmdList["TALORIANTP"], "show")
                if type(AP.RaiseFrameFront) == "function" then
                    AP.RaiseFrameFront(rawget(_G, "TalorianMainFrame"))
                end
                return ok
            end
            return false
        end

        function AP:OpenAtlas()
            local fn = rawget(_G, "AttuneAtlas_Toggle")
            if type(fn) == "function" then
                pcall(fn)
                local af = rawget(_G, "AttuneAtlasFrame")
                if af and af:IsShown() and type(AP.RaiseFrameFront) == "function" then
                    AP.RaiseFrameFront(af)
                end
                return true
            end
            return false
        end
    end

    do
        local QHEX_FALLBACK = {
            [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00",
            [3] = "0070dd", [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80",
        }
        local STAT_SHORT = {
            [3] = "Ловкость", [4] = "Сила", [5] = "Интеллект", [6] = "Дух", [7] = "Выносливость",
            [12] = "Защита", [13] = "Уклонение", [14] = "Парирование", [15] = "Блок",
            [31] = "Меткость", [32] = "Крит", [35] = "Устойчивость", [36] = "Скорость",
            [37] = "Мастерство", [38] = "АП", [44] = "РПБ", [45] = "СПД",
            [46] = "МР5", [47] = "Проник. способн.", [48] = "Показ. блока",
        }

        function AP:GetItemHyperlink(itemId, sfxOrLink, nameHint, qualHint)
            if type(sfxOrLink) == "string" and sfxOrLink:find("|Hitem:%d+", 1, false) then
                return sfxOrLink, sfxOrLink:match("|H(item:[^|]+)|h")
            end
            local eid = AP.ExtractItemId(itemId)
            if not eid then return nil, nil end
            local sfx = (type(sfxOrLink) == "string") and AP.ExtractSuffix(sfxOrLink) or (tonumber(sfxOrLink) or 0)
            local rawItemStr = "item:" .. eid .. ":0:0:0:0:0:" .. tostring(sfx) .. ":0"

            local gName, gLink, gQual = GetItemInfo(rawItemStr)
            if (not gLink) and sfx == 0 then
                gName, gLink, gQual = GetItemInfo(eid)
            end
            if type(gLink) == "string" and gLink:find("|Hitem:%d+", 1, false) then
                return gLink, rawItemStr
            end

            local rec = AP.ParseItemRecord and AP.ParseItemRecord(eid) or nil
            local nm = gName or nameHint or (rec and rec.name) or ("Предмет #" .. eid)
            local q = tonumber(gQual or qualHint or (rec and rec.quality)) or 2
            local qHex = QHEX_FALLBACK[q] or "ffffff"
            if type(GetItemQualityColor) == "function" then
                local _, _, _, cCode = GetItemQualityColor(q)
                if type(cCode) == "string" then
                    local h6 = cCode:match("|cff(%x%x%x%x%x%x)")
                    if h6 then qHex = h6 end
                end
            end
            local built = string.format("|cff%s|H%s|h[%s]|h|r", qHex, rawItemStr, nm)
            return built, rawItemStr
        end

        function AP:InsertItemLink(itemId, sfxOrLink, nameHint, qualHint)
            local fullLink = AP:GetItemHyperlink(itemId, sfxOrLink, nameHint, qualHint)
            if not fullLink then return false end
            if IsControlKeyDown() and type(DressUpItemLink) == "function" then
                pcall(DressUpItemLink, fullLink)
                local df = rawget(_G, "DressUpFrame")
                if df and df:IsShown() then
                    pcall(df.Raise, df)
                    AP.After(0.02, function()
                        local d2 = rawget(_G, "DressUpFrame")
                        if d2 and d2:IsShown() then pcall(d2.Raise, d2) end
                    end, "ap_dressup_raise")
                end
                return true
            end
            if type(ChatEdit_InsertLink) == "function" and ChatEdit_InsertLink(fullLink) then
                return true
            end
            if type(ChatFrame_OpenChat) == "function" then
                ChatFrame_OpenChat("")
                if type(ChatEdit_InsertLink) == "function" then
                    ChatEdit_InsertLink(fullLink)
                end
                return true
            end
            return false
        end

        function AP:AppendSourcesLines(tt, itemId, maxLines)
            if not tt or not itemId then return end
            local src = AP:GetItemSources(itemId)
            if src and not src.hasServerSources and type(AP.RequestItemSources) == "function" then
                AP:RequestItemSources(itemId, false)
            end
            if not src or not src.list or #src.list == 0 then
                if src and src.hasServerSources == false then
                    tt:AddLine("|cff94a3b8Источники подгружаются с сервера...|r", 1, 1, 1)
                end
                return
            end
            tt:AddLine("|cffffd200Источники (" .. (src.hasServerSources and "сервер" or "база") .. "):|r", 1, 1, 1)
            local shown = 0
            local limit = maxLines or 5
            for _, sc in ipairs(src.list) do
                if shown >= limit then
                    tt:AddLine(string.format("  |cff94a3b8... и еще %d источник(ов)|r", #src.list - shown), 1, 1, 1)
                    break
                end
                local sType = (AP.SOURCE_TYPES and AP.SOURCE_TYPES[sc.st]) or "?"
                local zPart = (sc.zoneName and sc.zoneName ~= "") and (" |cffb0a080(" .. sc.zoneName .. ")|r") or ""
                if sc.st == 4 then
                    local qTag = sc.qDone and "|cff40ff40[Вып]|r " or "|cffffd200[Квест]|r "
                    local chStr = (sc.qlen and sc.qlen > 1) and string.format(" [цеп. %d]", sc.qlen) or ""
                    local gNm = sc.qGiver or sc.giver or sc.qStartGiver
                    local gStr = (gNm and gNm ~= "") and (" - от: " .. gNm) or ""
                    tt:AddLine("  " .. qTag .. (sc.name or ("Задание #" .. tostring(sc.smp))) .. chStr .. gStr .. zPart, 0.92, 0.90, 0.85, true)
                    if sc.chainNames and #sc.chainNames > 1 then
                        local chList = {}
                        for ci, cn in ipairs(sc.chainNames) do
                            if ci <= 4 then table.insert(chList, cn) end
                        end
                        if #sc.chainNames > 4 then table.insert(chList, "...") end
                        tt:AddLine("    |cffb0a080Цепочка: " .. table.concat(chList, " -> ") .. "|r", 1, 1, 1, true)
                    end
                else
                    local ch = (sc.chance and sc.chance > 0 and AP.FormatChance) and (" (" .. AP.FormatChance(sc.chance) .. ")") or ""
                    local nm = (sc.name and sc.name ~= "") and sc.name or ((sc.smp or 0) == 0 and "Боссы / сундуки инста" or "?")
                    tt:AddLine("  |cffd8c8a8[" .. sType .. "]|r " .. nm .. zPart .. ch, 0.92, 0.90, 0.85, true)
                end
                shown = shown + 1
            end
        end

        function AP:BuildItemTooltip(tt, itemId, opts)
            if not tt or not itemId then return end
            opts = opts or {}
            local eid = AP.ExtractItemId(itemId)
            if not eid then return end
            local sfx = (type(opts.sfxOrLink or opts.link) == "string") and AP.ExtractSuffix(opts.sfxOrLink or opts.link) or (tonumber(opts.sfx) or 0)
            local fullLink, rawItemStr = AP:GetItemHyperlink(eid, opts.link or sfx, opts.name, opts.quality)
            local info = AP:GetItemInfo(eid, opts.link or sfx)
            local nameStr = (info and info.name) or opts.name or ("Предмет #" .. eid)
            local q = (info and info.quality) or opts.quality or 2
            local qHex = QHEX_FALLBACK[q] or "ffffff"

            tt:ClearLines()
            local setOk = false
            local tipLink = rawItemStr or fullLink
            if tipLink then
                setOk = pcall(tt.SetHyperlink, tt, tipLink)
            end
            if (not setOk) or (tt:NumLines() <= 1) then
                tt:ClearLines()
                tt:AddLine("|cff" .. qHex .. nameStr .. "|r")
                if info then
                    tt:AddLine(string.format("Предмет #%d | Уровень предмета: %d%s",
                        eid, info.ilvl or 0, (info.reqLvl and info.reqLvl > 0) and (" | Треб. ур: " .. info.reqLvl) or ""), 0.85, 0.85, 0.85)
                    if (info.coreStatsSum or 0) > 0 then
                        local sParts = {}
                        for sid, sv in pairs(info.stats or {}) do
                            if sv > 0 and sid ~= 1 and sid ~= 1000 then
                                table.insert(sParts, (STAT_SHORT[sid] or ("#" .. sid)) .. " +" .. sv)
                            end
                        end
                        if #sParts > 0 then
                            tt:AddLine("Статы: " .. table.concat(sParts, ", "), 0.35, 1, 0.45, true)
                        end
                    end
                end
                tt:AddLine("|cff94a3b8Предмет еще загружается в кэш игры...|r", 1, 1, 1)
            end

            tt:AddLine(" ")
            tt:AddLine("|cff38bdf8-- AttuneParser: Поглощение --|r", 1, 1, 1)

            local zid = opts.zoneId or (info and (info.resolvedZone or info.primaryZone))
            local zName = (zid and zid > 0 and AP.Data and AP.Data.Zones and AP.Data.Zones[zid] and AP.Data.Zones[zid].name) or nil
            local isInstZone = (zid and zid > 0 and AP.IsZoneInstance) and AP:IsZoneInstance(zid) or false
            local diffLbl = (isInstZone and AP.GetItemDiffTag) and AP:GetItemDiffTag(eid, zid, opts.diffMask, true) or ""
            local metaParts = {}
            if diffLbl ~= "" then table.insert(metaParts, "|cffffd200" .. diffLbl .. "|r") end
            if zName and zName ~= "" then table.insert(metaParts, zName) end
            if info and (info.ilvl or 0) > 0 then table.insert(metaParts, "ilvl " .. info.ilvl) end
            if #metaParts > 0 then
                local locPrefix = isInstZone and "Инст: " or "Локация: "
                tt:AddLine(locPrefix .. table.concat(metaParts, " | "), 0.9, 0.9, 0.9)
            end

            if info then
                if info.noAttune then
                    tt:AddLine("Поглощение: |cff94a3b8не подлежит поглощению|r", 1, 1, 1)
                elseif info.isCompleted then
                    tt:AddLine(string.format("Прогресс: |cff40ff40Завершено (%s, %d%%)|r", info.doneTierName or "Титан", info.curPct or 90), 1, 1, 1)
                elseif info.isNew then
                    tt:AddDoubleLine(
                        "Статус: |cff40ff40Новый (0%)|r",
                        string.format("+%d%% сразу (+%d) | До 90%%: |cffffd200+%d стат|r",
                            info.newBasePct or 20, info.immediateNewStats or 0, info.fullMaxStats or 0),
                        0.9, 0.9, 0.9, 1, 1, 1
                    )
                else
                    local nxPct = (info.curPct or 0) + (info.nextStepPct or 0)
                    local nxName = (info.nextTier and AP.TIER_NAMES and AP.TIER_NAMES[info.nextTier]) or "след."
                    tt:AddDoubleLine(
                        string.format("Ковка: |cffffd200%s (%d%%)|r", info.doneTierName or "?", info.curPct or 0),
                        string.format("-> %s (%d%%): |cff40ff40+%d|r | До 90%%: |cffffd200+%d|r",
                            nxName, nxPct, info.nextStepStats or 0, info.remainStats or 0),
                        0.9, 0.9, 0.9, 1, 1, 1
                    )
                end

                if (info.ipXp or 0) > 0 and (info.ipNeed or 0) > 0 then
                    local ipPct = math.floor((info.ipXp / info.ipNeed) * 100 + 0.5)
                    tt:AddLine(string.format("Закалка сейчас: |cff38bdf8%d / %d XP (%d%%)|r", info.ipXp, info.ipNeed, ipPct), 1, 1, 1)
                end

                if not info.usableOnHero then
                    if info.absorbableOnAccount then
                        tt:AddLine("Персонаж: |cff38bdf8только для твинков на аккаунте|r", 1, 1, 1)
                    elseif info.cantReason then
                        tt:AddLine("Персонаж: |cffff6060недоступно (" .. tostring(info.cantReason) .. ")|r", 1, 1, 1)
                    end
                end
            end

            if opts.extraLine and opts.extraLine ~= "" then
                tt:AddLine(opts.extraLine, 0.4, 1, 0.55)
            end
            if AP:IsItemBlacklisted(eid, opts.tier) then
                tt:AddLine("|cffff5050В черном списке автопродажи!|r", 1, 1, 1)
            end

            local g = AP.GetActiveDailyGift and AP:GetActiveDailyGift(false) or nil
            if g and g.isThursday and info and info.sources then
                for _, sc in ipairs(info.sources) do
                    if sc.st == 3 then
                        tt:AddLine("|cff40ff40Дар Четверга: 100% возврат цены торговцу!|r", 1, 1, 1)
                        break
                    end
                end
            end

            if opts.showSources ~= false then
                AP:AppendSourcesLines(tt, eid, opts.maxSources or 5)
            end

            local hint = opts.hint or "|cff94a3b8Shift+ЛКМ: ссылка в чат | Ctrl+ЛКМ: примерить|r"
            tt:AddLine(" ")
            tt:AddLine(hint, 1, 1, 1)
        end
    end
end

-- ============================================================================
-- Module 2: Item Decoder, Runtime Stat Scanner & Class/Faction Compatibility
-- ============================================================================
do
    local ITEM_MOD_WHITELIST = {
        ITEM_MOD_STRENGTH_SHORT = 4,
        ITEM_MOD_AGILITY_SHORT = 3,
        ITEM_MOD_STAMINA_SHORT = 7,
        ITEM_MOD_INTELLECT_SHORT = 5,
        ITEM_MOD_SPIRIT_SHORT = 6,
        ITEM_MOD_ATTACK_POWER_SHORT = 38,
        ITEM_MOD_RANGED_ATTACK_POWER_SHORT = 39,
        ITEM_MOD_SPELL_POWER_SHORT = 45,
        ITEM_MOD_CRIT_RATING_SHORT = 32,
        ITEM_MOD_CRIT_MELEE_RATING_SHORT = 19,
        ITEM_MOD_CRIT_RANGED_RATING_SHORT = 20,
        ITEM_MOD_CRIT_SPELL_RATING_SHORT = 21,
        ITEM_MOD_HASTE_RATING_SHORT = 36,
        ITEM_MOD_HASTE_MELEE_RATING_SHORT = 28,
        ITEM_MOD_HASTE_RANGED_RATING_SHORT = 29,
        ITEM_MOD_HASTE_SPELL_RATING_SHORT = 30,
        ITEM_MOD_HIT_RATING_SHORT = 31,
        ITEM_MOD_HIT_MELEE_RATING_SHORT = 16,
        ITEM_MOD_HIT_RANGED_RATING_SHORT = 17,
        ITEM_MOD_HIT_SPELL_RATING_SHORT = 18,
        ITEM_MOD_EXPERTISE_RATING_SHORT = 37,
        ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = 44,
        ITEM_MOD_RESILIENCE_RATING_SHORT = 35,
        ITEM_MOD_SPELL_PENETRATION_SHORT = 47,
        ITEM_MOD_MANA_REGENERATION_SHORT = 43,
        ITEM_MOD_HEALTH_REGENERATION_SHORT = 46,
        ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 12,
        ITEM_MOD_DODGE_RATING_SHORT = 13,
        ITEM_MOD_PARRY_RATING_SHORT = 14,
        ITEM_MOD_BLOCK_RATING_SHORT = 15,
        ITEM_MOD_BLOCK_VALUE_SHORT = 48,
    }

    local EXCLUDED_INVTYPE = {
        INVTYPE_BAG = true,
        INVTYPE_QUIVER = true,
        INVTYPE_AMMO = true,
        INVTYPE_TABARD = true,
        INVTYPE_BODY = true,
    }
    local EXCLUDED_INVID = { [0] = true, [4] = true, [18] = true, [19] = true, [24] = true, [27] = true }

    -- Class bitmasks from WoW 3.3.5 Item.allowableClass
    local CLASS_BIT = {
        WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
        DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
        DEMONHUNTER = 2048,
    }
    local CLASS_ARMOR_SUB = {
        WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
        HUNTER = 3, SHAMAN = 3,
        ROGUE = 2, DRUID = 2, DEMONHUNTER = 2,
        PRIEST = 1, MAGE = 1, WARLOCK = 1,
    }
    -- Armor slots where armor subclass proficiency strictly applies (invType IDs)
    local BODY_INVID = { [1]=true, [3]=true, [5]=true, [6]=true, [7]=true, [8]=true, [9]=true, [10]=true, [20]=true }
    -- Weapon subclass IDs in Item.dbc: 0=Axe1,1=Axe2,2=Bow,3=Gun,4=Mace1,5=Mace2,6=Polearm,7=Sword1,8=Sword2,10=Staff,13=Fist,15=Dagger,16=Thrown,17=Spear,18=Crossbow,19=Wand
    local CLASS_WEP_SUB = {
        WARRIOR     = { [0]=1,[1]=1,[2]=1,[3]=1,[4]=1,[5]=1,[6]=1,[7]=1,[8]=1,[10]=1,[13]=1,[15]=1,[16]=1,[18]=1 },
        PALADIN     = { [0]=1,[1]=1,[4]=1,[5]=1,[6]=1,[7]=1,[8]=1 },
        DEATHKNIGHT = { [0]=1,[1]=1,[4]=1,[5]=1,[6]=1,[7]=1,[8]=1 },
        HUNTER      = { [0]=1,[1]=1,[2]=1,[3]=1,[6]=1,[7]=1,[8]=1,[10]=1,[13]=1,[15]=1,[16]=1,[18]=1 },
        SHAMAN      = { [0]=1,[1]=1,[4]=1,[5]=1,[10]=1,[13]=1,[15]=1 },
        ROGUE       = { [0]=1,[2]=1,[3]=1,[4]=1,[7]=1,[13]=1,[15]=1,[16]=1,[18]=1 },
        DRUID       = { [4]=1,[5]=1,[6]=1,[10]=1,[13]=1,[15]=1 },
        PRIEST      = { [4]=1,[10]=1,[15]=1,[19]=1 },
        MAGE        = { [7]=1,[10]=1,[15]=1,[19]=1 },
        WARLOCK     = { [7]=1,[10]=1,[15]=1,[19]=1 },
        DEMONHUNTER = { [0]=1,[7]=1,[13]=1,[15]=1 },
    }
    local RELIC_CLASS = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN", [11] = "DEATHKNIGHT" }
    local SHIELD_CLASS = { WARRIOR = true, PALADIN = true, SHAMAN = true }

    local scanTip = CreateFrame("GameTooltip", "AttuneParserScanTip", UIParent, "GameTooltipTemplate")
    local classNameMap = nil

    local function GetClassNameMap()
        if classNameMap then return classNameMap end
        classNameMap = {}
        for tok, nm in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do classNameMap[nm] = tok end
        for tok, nm in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do classNameMap[nm] = tok end
        return classNameMap
    end

    -- Helper bit-test avoiding bit.band crash if bit lib behaves differently across builds
    local function hasFlag(mask, flag)
        if not mask or mask == 0 then return false end
        if bit and bit.band then
            return bit.band(mask, flag) ~= 0
        end
        return math.floor(mask / flag) % 2 == 1
    end

    function AP.ParseItemRecord(eid)
        local cache = AP._mem.itemMetaCache
        if cache[eid] then return cache[eid] end

        local raw = AP.Data and AP.Data.Items and AP.Data.Items[eid]
        local rec
        if type(raw) == "string" then
            local cls, sub, inv, q, ilvl, req, armor, flags, dmask, pz, allowCls, hp, statStr, name =
                raw:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
            local stats = {}
            local coreSum = 0
            if statStr and statStr ~= "" then
                for pair in statStr:gmatch("[^,]+") do
                    local sk, sv = pair:match("^(%d+):(%-?%d+)$")
                    local sid, val = tonumber(sk), tonumber(sv)
                    if sid and val and val ~= 0 then
                        stats[sid] = (stats[sid] or 0) + val
                        if val > 0 then
                            coreSum = coreSum + val
                        end
                    end
                end
            end
            local fl = tonumber(flags) or 0
            rec = {
                id = eid,
                cls = tonumber(cls) or 0,
                sub = tonumber(sub) or 0,
                inv = tonumber(inv) or 0,
                quality = tonumber(q) or 0,
                ilvl = tonumber(ilvl) or 0,
                req = tonumber(req) or -1,
                armor = tonumber(armor) or 0,
                flags = fl,
                diffMask = tonumber(dmask) or 0,
                primaryZone = tonumber(pz) or 0,
                allowCls = tonumber(allowCls) or -1,
                hp = tonumber(hp) or 0,
                stats = stats,
                coreSum = coreSum,
                name = (name and name ~= "") and name or nil,
                statsKnown = hasFlag(fl, 1),
                hasRandomSuffix = hasFlag(fl, 2),
                isBoE = hasFlag(fl, 4),
                fac = hasFlag(fl, 8) and "A" or (hasFlag(fl, 16) and "H" or nil),
                noAttune = hasFlag(fl, 32),
                resOnly = hasFlag(fl, 64),
            }
        else
            rec = {
                id = eid, cls = 0, sub = 0, inv = 0, quality = 0, ilvl = 0,
                req = -1, armor = 0, flags = 0, diffMask = 0, primaryZone = 0,
                allowCls = -1, hp = 0, stats = {}, coreSum = 0,
                statsKnown = false, hasRandomSuffix = false, isBoE = false,
                noAttune = (eid >= 810000 and eid <= 810999),
            }
        end

        -- Overlay live AttuneAtlas faction if global loaded
        local ifac = rawget(_G, "AttuneAtlasItemFaction")
        if ifac and ifac[eid] and not rec.fac then
            rec.fac = ifac[eid]
        end

        -- Overlay SavedVariables runtime-learned data if offline record lacked WDB stats
        local sv = AttuneParserDB and AttuneParserDB.itemStats and AttuneParserDB.itemStats[eid]
        if sv and not rec.statsKnown then
            rec.statsKnown = true
            if sv.name and sv.name ~= "" then rec.name = sv.name end
            if sv.q and sv.q > 0 then rec.quality = sv.q end
            if sv.ilvl and sv.ilvl > 0 then rec.ilvl = sv.ilvl end
            if sv.req ~= nil then rec.req = sv.req end
            if sv.armor then rec.armor = sv.armor end
            if sv.hp then rec.hp = sv.hp end
            if sv.rand then rec.hasRandomSuffix = true end
            if sv.noAtt then rec.noAttune = true end
            if sv.resOnly then rec.resOnly = true end
            if sv.allowCls ~= nil then rec.allowCls = sv.allowCls end
            if sv.clsMask ~= nil then rec.allowCls = sv.clsMask end
            if sv.stats then
                local stTbl, cSum = {}, 0
                for sid, val in pairs(sv.stats) do
                    local nsid, nval = tonumber(sid), tonumber(val)
                    if nsid and nval and nval ~= 0 then
                        stTbl[nsid] = nval
                        if nval > 0 and nsid ~= 1 and nsid ~= 1000 then
                            cSum = cSum + nval
                        end
                    end
                end
                rec.stats = stTbl
                rec.coreSum = cSum
            end
        end

        cache[eid] = rec
        return rec
    end

    function AP.ExtractLiveStatsAndMeta(eid, link)
        local targetLink = link or ("item:" .. eid)
        local nm, _, q, ilvl, reqLvl, _, _, _, eqLoc = GetItemInfo(targetLink)
        if not nm then return nil end

        local stTbl = {}
        local coreSum = 0
        local armor = 0
        local hpVal = 0
        local hasAnyMod = false
        local hasRes = false

        if type(GetItemStats) == "function" then
            local ok, rawStats = pcall(GetItemStats, targetLink)
            if ok and type(rawStats) == "table" then
                for k, v in pairs(rawStats) do
                    if type(v) == "number" and v ~= 0 then
                        if k == "RESISTANCE0_NAME" then
                            armor = v
                        elseif k:find("RESISTANCE", 1, true) then
                            hasRes = true
                        elseif k == "ITEM_MOD_HEALTH_SHORT" then
                            hpVal = hpVal + v
                            hasAnyMod = true
                        elseif ITEM_MOD_WHITELIST[k] then
                            local sid = ITEM_MOD_WHITELIST[k]
                            stTbl[sid] = (stTbl[sid] or 0) + v
                            if v > 0 then coreSum = coreSum + v end
                            hasAnyMod = true
                        elseif k:find("ITEM_MOD_", 1, true) then
                            hasAnyMod = true
                        end
                    end
                end
            end
        end

        local excluded = EXCLUDED_INVTYPE[eqLoc or ""] or false
        if eqLoc == "" or (eid >= 810000 and eid <= 810999) or (q and q < 2) then
            excluded = true
        end
        if (ilvl or 0) <= 1 and not hasAnyMod and q ~= 7 then
            excluded = true
        end
        if type(_G.ATC_NoAttune) == "function" then
            local okn, na = pcall(_G.ATC_NoAttune, targetLink, eid)
            if okn and na then excluded = true end
        end

        -- Scan tooltip ONLY for class restriction and random-enchant detection when cached & out of combat
        local allowCls = -1
        local isRand = false
        if not (InCombatLockdown and InCombatLockdown()) then
            scanTip:SetOwner(UIParent, "ANCHOR_NONE")
            scanTip:ClearLines()
            local okt = pcall(function() scanTip:SetHyperlink(targetLink) end)
            if okt then
                local fmt = ITEM_CLASSES_ALLOWED or "Классы: %s"
                local clsPrefix = fmt:match("^(.-)%%s") or "Классы: "
                local cmap = GetClassNameMap()
                local bits = CLASS_BIT
                local rndTxt = ITEM_RANDOM_ENCHANT or "Случайное усиление"
                for i = 2, (scanTip:NumLines() or 0) do
                    local fs = _G["AttuneParserScanTipTextLeft" .. i]
                    local txt = fs and fs:GetText()
                    if txt then
                        if txt:sub(1, #clsPrefix) == clsPrefix then
                            local list = txt:sub(#clsPrefix + 1)
                            local mask = 0
                            local allKnown = true
                            for cnm in list:gmatch("[^,]+") do
                                local cnmTrim = cnm:gsub("^%s+", ""):gsub("%s+$", "")
                                local tok = cmap[cnmTrim]
                                if tok and bits[tok] then
                                    mask = mask + bits[tok]
                                else
                                    allKnown = false
                                end
                            end
                            if allKnown and mask > 0 then
                                allowCls = mask
                            end
                        elseif (txt:find(rndTxt, 1, true) or txt:find("<Случайные", 1, true) or txt:find("Random enchantment", 1, true)) and not link then
                            isRand = true
                        end
                    end
                end
            end
            scanTip:Hide()
        end

        local resOnly = (not hasAnyMod) and hasRes
        return {
            name = nm,
            q = q or 0,
            ilvl = ilvl or 0,
            req = reqLvl or 0,
            armor = armor,
            hp = hpVal,
            stats = stTbl,
            coreSum = coreSum,
            noAtt = excluded,
            resOnly = resOnly,
            rand = isRand,
            allowCls = allowCls,
        }
    end

    function AP:GetItemStats(itemId, sfxOrLink)
        local eid = AP.ExtractItemId(itemId)
        if not eid then return nil, 0, 0, 0 end

        local sfx = 0
        local fullLink = nil
        if type(sfxOrLink) == "string" and sfxOrLink:find("item:", 1, true) then
            fullLink = sfxOrLink
            sfx = AP.ExtractSuffix(sfxOrLink)
        elseif type(sfxOrLink) == "number" then
            sfx = sfxOrLink
        end

        if sfx ~= 0 and fullLink then
            AttuneParserDB = AttuneParserDB or {}
            AttuneParserDB.seenSuffixes = AttuneParserDB.seenSuffixes or {}
            AttuneParserDB.seenSuffixes[eid] = AttuneParserDB.seenSuffixes[eid] or {}
            local cachedSuf = AttuneParserDB.seenSuffixes[eid][sfx]
            if not cachedSuf then
                local ext = AP.ExtractLiveStatsAndMeta(eid, fullLink)
                if ext then
                    cachedSuf = {
                        name = ext.name,
                        stats = ext.stats,
                        coreSum = ext.coreSum,
                        armor = ext.armor,
                        hp = ext.hp,
                    }
                    AttuneParserDB.seenSuffixes[eid][sfx] = cachedSuf
                end
            end
            if cachedSuf then
                return cachedSuf.stats or {}, cachedSuf.coreSum or 0, cachedSuf.armor or 0, cachedSuf.hp or 0
            end
        end

        local rec = AP.ParseItemRecord(eid)
        return rec.stats, rec.coreSum, rec.armor, rec.hp
    end

    local absorbChecksRunning = false
    function AP:CanHeroAbsorb(itemId, link)
        local eid = AP.ExtractItemId(itemId)
        if not eid then return false, false, "invalid" end

        local useCache = (not link)
        local aCache = useCache and AP._mem.absorbCache() or nil
        if aCache and aCache[eid] then
            local c = aCache[eid]
            return c[1], c[2], c[3]
        end

        local rec = AP.ParseItemRecord(eid)
        local usable, accOk, reason = true, true, nil

        if rec.noAttune or EXCLUDED_INVID[rec.inv] or (rec.quality > 0 and rec.quality < 2) then
            usable, accOk, reason = false, false, "no_attune"
        else
            local blankTbl = rawget(_G, "STORE_DATA_BLANK")
            local cat3Tbl = rawget(_G, "ATC_CAT3")
            if (cat3Tbl and cat3Tbl[eid] == true) or (blankTbl and blankTbl[eid] == true) then
                usable, accOk, reason = false, false, "no_attune"
            elseif link and type(_G.ATC_NoAttune) == "function" then
                local okn, na = pcall(_G.ATC_NoAttune, link, eid)
                if okn and na then usable, accOk, reason = false, false, "no_attune" end
            end
        end

        if usable then
            local pf = UnitFactionGroup and UnitFactionGroup("player")
            local pChar = (pf == "Alliance" and "A") or (pf == "Horde" and "H") or nil
            if rec.fac and pChar and rec.fac ~= pChar then
                usable, accOk, reason = false, false, "faction"
            end
        end

        if usable then
            local _, playerClass = UnitClass("player")
            -- Call server CustomAttuneItemStatus only when link given or offline class/item metadata is missing
            if (link or (not rec.statsKnown and rec.allowCls == -1)) and type(_G.CustomAttuneItemStatus) == "function" then
                local sfx = link and AP.ExtractSuffix(link) or 0
                local oks, _, cant, _, attun = pcall(_G.CustomAttuneItemStatus, eid, 0, sfx)
                if oks and attun == false then
                    usable, accOk, reason = false, false, "no_attune"
                elseif oks and cant == true then
                    usable, accOk, reason = false, true, "class"
                end
            end

            if usable and rec.allowCls and rec.allowCls > 0 and playerClass and CLASS_BIT[playerClass] then
                if not hasFlag(rec.allowCls, CLASS_BIT[playerClass]) then
                    usable, accOk, reason = false, true, "class"
                end
            end

            if usable and rec.inv == 14 then
                if not SHIELD_CLASS[playerClass] then
                    usable, accOk, reason = false, true, "shield"
                end
            elseif usable and rec.inv == 28 then
                local rc = RELIC_CLASS[rec.sub]
                if rc and rc ~= playerClass then
                    usable, accOk, reason = false, true, "relic"
                end
            elseif usable and rec.cls == 4 and BODY_INVID[rec.inv] and rec.sub >= 1 and rec.sub <= 4 then
                local needSub = CLASS_ARMOR_SUB[playerClass]
                if needSub and rec.sub ~= needSub then
                    usable, accOk, reason = false, true, "armor"
                end
            elseif usable and rec.cls == 2 and rec.sub ~= 20 then
                local wepSet = CLASS_WEP_SUB[playerClass]
                if wepSet and not wepSet[rec.sub] then
                    usable, accOk, reason = false, true, "weapon"
                elseif rec.inv == 22 then
                    local dw = (playerClass == "WARRIOR" or playerClass == "ROGUE" or playerClass == "HUNTER" or playerClass == "DEATHKNIGHT" or playerClass == "DEMONHUNTER")
                    if not dw and type(_G.CanDualWield) == "function" then
                        local okD, resD = pcall(_G.CanDualWield)
                        if okD and resD then dw = true end
                    end
                    if not dw and playerClass == "SHAMAN" then
                        if type(_G.IsSpellKnown) == "function" and (_G.IsSpellKnown(30798) or _G.IsSpellKnown(674)) then
                            dw = true
                        else
                            local n = GetSpellInfo(30798) or GetSpellInfo(674)
                            dw = (n ~= nil and GetSpellInfo(n) ~= nil)
                        end
                    end
                    if not dw then
                        usable, accOk, reason = false, true, "weapon"
                    end
                end
            end
        end

        if aCache then
            aCache[eid] = { usable, accOk, reason }
        end
        return usable, accOk, reason
    end
end

-- ============================================================================
-- Module 3: Authoritative Server Status, Progression & Replacement Math
-- ============================================================================
do
    function AP:GetItemServerStatus(itemId, sfxOrLink)
        local eid = AP.ExtractItemId(itemId)
        if not eid then
            return { doneTier = -1, ipTier = nil, ipXp = 0, ipNeed = 0, curPct = 0, remainPct = AP.TIER_PCT[3] or 90 }
        end

        local sfx = 0
        if type(sfxOrLink) == "string" then
            sfx = AP.ExtractSuffix(sfxOrLink)
        elseif type(sfxOrLink) == "number" then
            sfx = sfxOrLink
        end

        local sCache = (sfx == 0) and AP._mem.statusCache() or nil
        if sCache and sCache[eid] then
            return sCache[eid]
        end

        local doneTier = -1
        local ipTier, ipXp, ipNeed = nil, 0, 0

        -- 1. Live server CustomAttuneProgress(entry, sfx)
        local fnProg = rawget(_G, "CustomAttuneProgress")
        if type(fnProg) == "function" then
            local ok, dt, ipt, xp, need = pcall(fnProg, eid, sfx)
            if ok and type(dt) == "number" then
                if dt > doneTier then doneTier = dt end
                ipTier, ipXp, ipNeed = ipt, xp or 0, need or 0
            end
        end

        -- 2. Authoritative server absSufTier via CustomAttuneAbsorbedTier(itemId, sfx) (upd-015)
        local fnAbsTier = rawget(_G, "CustomAttuneAbsorbedTier")
        if type(fnAbsTier) == "function" then
            local ok, at = pcall(fnAbsTier, eid, sfx)
            if ok and type(at) == "number" and at > doneTier then
                doneTier = at
            end
        end

        -- 3. Base absorbed set & O(1) ASMSG_ATC_ZONE absorbed map (for sfx == 0)
        if sfx == 0 and doneTier < 0 then
            local absSet = rawget(_G, "CustomAttuneAbsorbedSet")
            if (type(absSet) == "table" and absSet[eid]) or AP.serverAbsorbedItems[eid] then
                doneTier = 0
            end
        end

        -- 4. Legacy fallback probe ONLY if neither CustomAttuneProgress nor CustomAttuneAbsorbedTier exists
        if type(fnProg) ~= "function" and type(fnAbsTier) ~= "function" and doneTier < 3 then
            local fnTier = rawget(_G, "CustomAttuneTier")
            if type(fnTier) == "function" then
                for t = 3, math.max(0, doneTier + 1), -1 do
                    local ok, pct = pcall(fnTier, eid, t, sfx)
                    if ok and type(pct) == "number" and pct >= 100 then
                        doneTier = t
                        break
                    end
                end
            end
        end

        local tierPct = AP.TIER_PCT
        local curPct = (doneTier >= 0) and (tierPct[doneTier] or 0) or 0
        local maxPct = tierPct[3] or 90
        local remainPct = (doneTier >= 3) and 0 or math.max(0, maxPct - curPct)
        local isCompleted = (doneTier >= 3)
        local isNew = (doneTier < 0)
        local needsForge = (doneTier >= 0 and doneTier < 3)
        local nextTier = (not isCompleted) and (doneTier + 1) or nil
        local nextStepPct = (nextTier ~= nil) and math.max(0, (tierPct[nextTier] or maxPct) - curPct) or 0

        local res = {
            doneTier = doneTier,
            doneTierName = (doneTier >= 0) and AP.TIER_NAMES[doneTier] or nil,
            ipTier = ipTier,
            ipXp = ipXp,
            ipNeed = ipNeed,
            curPct = curPct,
            maxPct = maxPct,
            remainPct = remainPct,
            newBasePct = isNew and (tierPct[0] or 20) or 0,
            newMaxPct = isNew and maxPct or 0,
            forgeRemainPct = needsForge and remainPct or 0,
            nextTier = nextTier,
            nextStepPct = nextStepPct,
            isNew = isNew,
            needsForge = needsForge,
            isCompleted = isCompleted,
        }
        if sCache then
            sCache[eid] = res
        end
        return res
    end

    function AP.IsOnlyHeavyQuest(itemId)
        local eid = AP.ExtractItemId(itemId)
        if not eid then return false end
        local hqCache = AP._mem.heavyQuestCache()
        local cached = hqCache[eid]
        if cached ~= nil then return cached end

        local sCache = AP._mem.sourceCache
        if sCache[eid] then
            local flag = sCache[eid].onlyHeavyQuest and true or false
            hqCache[eid] = flag
            return flag
        end

        local raw = AP.Data and AP.Data.Sources and AP.Data.Sources[eid]
        if type(raw) == "string" and raw ~= "" then
            -- Fast path: if there is no quest record ("4:") anywhere in sources string, it can never be heavy-quest-only
            if raw:sub(1, 2) ~= "4:" and not raw:find(";4:", 1, true) then
                hqCache[eid] = false
                return false
            end
        elseif rawget(_G, "AAS") and _G.AAS[eid] then
            local araw = _G.AAS[eid]
            if araw:sub(1, 2) ~= "4:" and not araw:find(";4:", 1, true) then
                hqCache[eid] = false
                return false
            end
        else
            hqCache[eid] = false
            return false
        end

        local srcMeta = AP:GetItemSources(eid)
        local res = srcMeta.onlyHeavyQuest and true or false
        hqCache[eid] = res
        return res
    end

    local function IsQuestCompleted(qid)
        if not qid or qid <= 0 then return false end
        if AP.questCompleted and AP.questCompleted[qid] then return true end
        if type(IsQuestFlaggedCompleted) == "function" then
            local okq, done = pcall(IsQuestFlaggedCompleted, qid)
            if okq and done then return true end
        end
        return false
    end

    local function EnrichQuestEntry(entry, qid, qnTbl, qcTbl, qgTbl, isDoneFn)
        if not qid or qid <= 0 then return end
        local sep = string.char(1)
        local rawChain = qcTbl and qcTbl[qid]
        local chain, pos = { qid }, 1
        if type(rawChain) == "string" and rawChain ~= "" then
            local c, p = strsplit(sep, rawChain)
            local t = {}
            for nn in string.gmatch(c or "", "%d+") do
                local q = tonumber(nn)
                if q then table.insert(t, q) end
            end
            if #t > 0 then chain = t end
            pos = tonumber(p) or 1
        end
        local doneCnt, nextId, nextName = 0, nil, nil
        for _, stepId in ipairs(chain) do
            if isDoneFn(stepId) then
                doneCnt = doneCnt + 1
            elseif not nextId then
                nextId = stepId
                nextName = (qnTbl and qnTbl[stepId]) or ("Задание #" .. stepId)
            end
        end
        entry.qPos = pos
        entry.qChainLen = #chain
        entry.qChainDone = doneCnt
        entry.qNextId = nextId
        entry.qNextName = nextName
        if (#chain) > (entry.qlen or 0) then
            entry.qlen = #chain
        end
        local rawGiver = qgTbl and qgTbl[qid]
        if type(rawGiver) == "string" and rawGiver ~= "" then
            local gn, gf, gc = strsplit(sep, rawGiver)
            entry.qGiver = (gn ~= "" and gn) or nil
            entry.qFaction = (gf ~= "" and gf) or "both"
            entry.qGiverCid = tonumber(gc) or 0
        end
        local startId = chain[1]
        if startId and startId ~= qid and qgTbl and type(qgTbl[startId]) == "string" and qgTbl[startId] ~= "" then
            local fgn, fgf, fgc = strsplit(sep, qgTbl[startId])
            entry.qStartGiver = (fgn ~= "" and fgn) or nil
            entry.qStartFaction = (fgf ~= "" and fgf) or "both"
            entry.qStartCid = tonumber(fgc) or 0
        end
    end

    function AP:GetItemSources(itemId)
        local eid = AP.ExtractItemId(itemId)
        if not eid then return {} end
        local cache = AP._mem.sourceCache
        if cache[eid] then return cache[eid] end

        local parsed, staticList, staticByKey = {}, {}, {}
        local raw = AP.Data and AP.Data.Sources and AP.Data.Sources[eid]
        local topMap = AP.Data and AP.Data.TopMap or {}
        local zonesTbl = AP.Data and AP.Data.Zones or {}
        local creTbl = AP.Data and AP.Data.Creatures or {}
        local qn = rawget(_G, "AttuneAtlasQuestName") or {}
        local qc = rawget(_G, "AttuneAtlasQuest") or {}
        local qg = rawget(_G, "AttuneAtlasQuestGiver") or {}
        local aan = rawget(_G, "AAN") or {}
        local aac = rawget(_G, "AAC") or {}

        local minChainLen = 999
        local maxPool = 0
        local bestChance = 0
        local hasEasyDrop = false
        local hasHeavyQuest = false
        local hasVendor = false
        local hasAnyQuest = false
        local questCompletedAny = false
        local bestQuest = nil

        local function registerEntry(entry)
            local st, smp, tz, ch, pool = entry.st, entry.smp, entry.zoneId or 0, entry.chance or 0, entry.pool or 0
            if st == 4 then
                hasAnyQuest = true
                EnrichQuestEntry(entry, smp, qn, qc, qg, IsQuestCompleted)
                local qlen = entry.qlen or 0
                if qlen <= 0 then qlen = 1 end
                if qlen < minChainLen then minChainLen = qlen end
                if qlen >= 5 then hasHeavyQuest = true end
                if IsQuestCompleted(smp) then
                    entry.qDone = true
                    questCompletedAny = true
                end
                if (not bestQuest) or (bestQuest.qDone and not entry.qDone) then
                    bestQuest = entry
                end
            elseif st == 1 then
                if ch > bestChance then bestChance = ch end
                if pool > maxPool then maxPool = pool end
                if ch >= 500 or pool >= 5 or tz == 0 or (zonesTbl[tz] and zonesTbl[tz].exp and zonesTbl[tz].exp > 0) then
                    hasEasyDrop = true
                end
            elseif st == 3 then
                hasVendor = true
            end
            table.insert(parsed, entry)
        end

        if type(raw) == "string" and raw ~= "" then
            for rec in raw:gmatch("[^;]+") do
                local st, smp, z, mp, cnt, ch, qlen, pool =
                    rec:match("^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)")
                if st then
                    st = tonumber(st) or 0
                    smp = tonumber(smp) or 0
                    z = tonumber(z) or 0
                    ch = tonumber(ch) or 0
                    qlen = tonumber(qlen) or 0
                    pool = tonumber(pool) or 0
                    local tz = (z > 0 and (topMap[z] or z)) or 0
                    local sName = ""
                    if st == 1 or st == 3 then
                        if creTbl[smp] then
                            sName = creTbl[smp]:match("^([^|]+)") or ""
                        elseif aac[smp] then
                            sName = aac[smp]:match("^([^|]+)") or ""
                        end
                    elseif st == 4 then
                        sName = qn[smp] or aan["4:" .. smp] or ("Задание #" .. smp)
                    else
                        sName = aan[st .. ":" .. smp] or ""
                    end
                    local zName = (tz > 0 and zonesTbl[tz] and zonesTbl[tz].name) or ""
                    local itemRec = {
                        st = st, smp = smp, zoneId = tz, rawZoneId = z, mapId = tonumber(mp) or 0,
                        cnt = tonumber(cnt) or 0, chance = ch, qlen = qlen, pool = pool,
                        name = sName, zoneName = zName, qDone = false,
                    }
                    table.insert(staticList, itemRec)
                    if not staticByKey[st .. ":" .. smp] then
                        staticByKey[st .. ":" .. smp] = itemRec
                    end
                end
            end
        end

        local srvSrc = AP.serverItemSources[eid]
        if type(srvSrc) == "table" and #srvSrc > 0 then
            for _, sc in ipairs(srvSrc) do
                local key = (sc.st or 0) .. ":" .. (sc.smp or 0)
                local stMeta = staticByKey[key]
                local tz = (sc.z and sc.z > 0 and (topMap[sc.z] or sc.z)) or 0
                local zName = (sc.zn and sc.zn ~= "" and sc.zn) or (tz > 0 and zonesTbl[tz] and zonesTbl[tz].name) or ""
                local sName = (sc.sn and sc.sn ~= "" and sc.sn) or (stMeta and stMeta.name) or ""
                if sName == "" and sc.st == 4 then
                    sName = qn[sc.smp] or aan["4:" .. tostring(sc.smp)] or ("Задание #" .. tostring(sc.smp))
                end
                registerEntry({
                    st = sc.st or 0,
                    smp = sc.smp or 0,
                    zoneId = tz,
                    rawZoneId = sc.z or 0,
                    mapId = sc.mp or 0,
                    cnt = sc.cnt or 0,
                    chance = ((sc.chance or 0) > 0) and sc.chance or (stMeta and stMeta.chance or 0),
                    qlen = (stMeta and stMeta.qlen) or ((sc.st == 4) and 1 or 0),
                    pool = (stMeta and stMeta.pool) or 0,
                    spawns = sc.spawns or 0,
                    x = sc.sx or 0,
                    y = sc.sy or 0,
                    name = sName,
                    zoneName = zName,
                    fromServer = true,
                    qDone = false,
                })
            end
        elseif #staticList > 0 then
            for _, itemRec in ipairs(staticList) do
                registerEntry(itemRec)
            end
        elseif rawget(_G, "AAS") and _G.AAS[eid] then
            for rec in _G.AAS[eid]:gmatch("[^;]+") do
                local st, smp, z, mp, cnt, ch = rec:match("^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)")
                st = tonumber(st) or 0
                smp = tonumber(smp) or 0
                z = tonumber(z) or 0
                local tz = (z > 0 and (topMap[z] or z)) or 0
                local zName = (tz > 0 and zonesTbl[tz] and zonesTbl[tz].name) or ""
                registerEntry({
                    st = st, smp = smp, zoneId = tz, rawZoneId = z, mapId = tonumber(mp) or 0,
                    cnt = tonumber(cnt) or 0, chance = tonumber(ch) or 0, qlen = (st == 4) and 1 or 0, pool = 0, name = "", zoneName = zName,
                })
            end
        end

        local out = {
            list = parsed,
            hasServerSources = (type(srvSrc) == "table" and #srvSrc > 0),
            minChainLen = (minChainLen < 999) and minChainLen or 0,
            maxPool = maxPool,
            bestChance = bestChance,
            hasEasyDrop = hasEasyDrop,
            hasVendor = hasVendor,
            hasAnyQuest = hasAnyQuest,
            onlyHeavyQuest = hasAnyQuest and hasHeavyQuest and (not hasEasyDrop) and (not hasVendor) and (minChainLen >= 5),
            questCompletedAny = questCompletedAny,
            bestQuest = bestQuest,
        }
        cache[eid] = out
        return out
    end

    function AP:GetItemInfo(itemId, sfxOrLink)
        local eid = AP.ExtractItemId(itemId)
        if not eid then return nil end

        local sfx = (type(sfxOrLink) == "string") and AP.ExtractSuffix(sfxOrLink) or (tonumber(sfxOrLink) or 0)
        local rec = AP.ParseItemRecord(eid)
        local stats, coreSum, armor, hp = AP:GetItemStats(eid, sfxOrLink or sfx)
        local status = AP:GetItemServerStatus(eid, sfxOrLink or sfx)
        local usableOnHero, accountOk, cantReason = AP:CanHeroAbsorb(eid, (type(sfxOrLink) == "string") and sfxOrLink or nil)
        local srcMeta = AP:GetItemSources(eid)

        local isNoReqLevel = (rec.req >= 0 and rec.req <= 1) and (not rec.noAttune) and (rec.ilvl >= 20 or coreSum > 0)
        local isChest1_79 = (rec.req >= 2 and rec.req <= 79) and srcMeta.onlyHeavyQuest

        local gainRatioNew = (status.newBasePct or 20) / 100
        local gainRatioMax = (status.maxPct or 90) / 100
        local gainRatioRemain = (status.remainPct or 0) / 100

        return {
            itemId = eid,
            sfx = sfx,
            name = rec.name or GetItemInfo(eid) or ("Предмет #" .. eid),
            quality = rec.quality,
            ilvl = rec.ilvl,
            reqLvl = rec.req,
            invType = rec.inv,
            cls = rec.cls,
            sub = rec.sub,
            armor = armor,
            hp = hp,
            stats = stats,
            coreStatsSum = coreSum,
            statsKnown = rec.statsKnown,
            hasRandomSuffix = rec.hasRandomSuffix,
            isBoE = rec.isBoE,
            faction = rec.fac,
            wrongFaction = (cantReason == "faction"),
            usableOnHero = usableOnHero,
            absorbableOnAccount = accountOk,
            cantReason = cantReason,
            noAttune = rec.noAttune,
            resOnly = rec.resOnly,
            isNoReqLevel = isNoReqLevel,
            isChest1_79 = isChest1_79,
            onlyHeavyQuest = srcMeta.onlyHeavyQuest,
            minQuestChainLen = srcMeta.minChainLen,
            sources = srcMeta.list,
            primaryZone = rec.primaryZone,
            diffMask = rec.diffMask,

            doneTier = status.doneTier,
            doneTierName = status.doneTierName,
            curPct = status.curPct,
            maxPct = status.maxPct,
            remainPct = status.remainPct,
            newBasePct = status.newBasePct,
            forgeRemainPct = status.forgeRemainPct,
            nextTier = status.nextTier,
            nextStepPct = status.nextStepPct,
            isNew = status.isNew,
            needsForge = status.needsForge,
            isCompleted = status.isCompleted,
            ipTier = status.ipTier,
            ipXp = status.ipXp,
            ipNeed = status.ipNeed,

            -- Concrete stat gain projections (weighted by tier % replacement rule)
            immediateNewStats = math.floor(coreSum * gainRatioNew + 0.5),
            fullMaxStats = math.floor(coreSum * gainRatioMax + 0.5),
            remainStats = math.floor(coreSum * gainRatioRemain + 0.5),
            nextStepStats = math.floor(coreSum * ((status.nextStepPct or 0) / 100) + 0.5),
        }
    end
end

-- ============================================================================
-- Module 4: Zone Analysis, Recommendations, No-Req-Level & Bag Scanner
-- ============================================================================
do
    local DIFF_BITS = { [1] = 1, [2] = 2, [3] = 4, [4] = 8 }
    local EXP_STR_TO_NUM = { Classic = 1, Vanilla = 1, TBC = 2, WotLK = 3 }

    -- Exact difficulty count per zone on WoW Prime 3.3.5a:
    -- Only 3 WotLK raids have 4 modes (10n/25n/10h/25h); 6 WotLK raids have 2 modes (10n/25n).
    -- All Classic & TBC raids and all Classic dungeons have a single difficulty (1).
    local RAID_MAX_DIFFS = {
        [4812] = 4, -- Цитадель Ледяной Короны
        [4722] = 4, -- Испытание крестоносца
        [4987] = 4, -- Рубиновое святилище
        [3456] = 2, -- Наксрамас
        [4273] = 2, -- Ульдуар
        [4603] = 2, -- Склеп Аркавона
        [4500] = 2, -- Око Вечности
        [4493] = 2, -- Обсидиановое святилище
        [2159] = 2, -- Логово Ониксии
    }

    function AP:GetZoneMaxDiffs(zoneId, isRaidHint, expHint)
        local topId = (AP.Data and AP.Data.TopMap and AP.Data.TopMap[zoneId]) or zoneId
        local zMeta = (AP.Data and AP.Data.Zones and AP.Data.Zones[topId]) or {}
        local isRaid = (zMeta.isRaid ~= nil) and zMeta.isRaid or (isRaidHint == true)
        local expNum = (zMeta.exp and zMeta.exp > 0) and zMeta.exp or EXP_STR_TO_NUM[expHint] or tonumber(expHint) or 0

        if isRaid then
            return RAID_MAX_DIFFS[topId] or 1
        end
        if expNum == 2 or expNum == 3 then
            return 2
        end
        return 1
    end

    local function InferRuntimeDiffMask(zid, eid, ilvl, isRaid, expNum)
        if not ilvl or ilvl <= 0 then return 0 end
        if isRaid and (expNum == 1 or expNum == 2) then return 1 end
        if isRaid and expNum == 3 then
            if zid == 4812 then
                if (eid >= 50600 and eid <= 50738) or (eid >= 51210 and eid <= 51315) or ilvl >= 277 then return 8 end
                if eid >= 51782 and eid <= 51950 then return 4 end
                if ilvl == 251 or ilvl == 258 then return 1 end
                if ilvl == 264 or ilvl == 271 then return 2 end
            elseif zid == 4987 then
                if ilvl >= 284 then return 8 elseif ilvl == 271 then return 2 else return 1 end
            elseif zid == 4722 then
                if ilvl >= 258 then return 8 elseif ilvl == 245 then return (eid >= 47729) and 4 or 2 else return 1 end
            elseif zid == 4273 then
                return (ilvl >= 226) and 2 or 1
            else
                if ilvl >= 245 or (zid == 3456 and ilvl >= 213) or ((zid == 2159 or zid == 4493 or zid == 4500) and ilvl >= 226) then return 2 end
                return 1
            end
        elseif not isRaid and expNum == 3 then
            if zid == 4723 then return (ilvl >= 219) and 2 or 1 end
            if zid == 4809 or zid == 4813 or zid == 4820 then return (ilvl >= 232) and 2 or 1 end
            return (ilvl >= 200) and 2 or 1
        elseif not isRaid and expNum == 2 then
            return (ilvl >= 115) and 2 or 1
        elseif not isRaid and expNum == 1 then
            return 1
        end
        return 0
    end
    AP.InferRuntimeDiffMask = InferRuntimeDiffMask

    local DIFF_LONG_4 = { [8] = "25 гер", [4] = "10 гер", [2] = "25 об", [1] = "10 об" }
    local DIFF_SHORT_4 = { [8] = "25г", [4] = "10г", [2] = "25о", [1] = "10о" }
    local DIFF_LONG_2R = { [2] = "25 об", [1] = "10 об" }
    local DIFF_SHORT_2R = { [2] = "25о", [1] = "10о" }
    local DIFF_LONG_2D = { [2] = "Героический", [1] = "Обычный" }
    local DIFF_SHORT_2D = { [2] = "Гер", [1] = "Об" }

    function AP:GetItemDiffTag(itemId, zoneIdHint, diffMaskHint, longForm)
        local eid = AP.ExtractItemId(itemId)
        if not eid then return "" end
        local rec = AP.ParseItemRecord(eid)
        local zid = zoneIdHint or (rec and rec.primaryZone) or 0
        local topId = (zid > 0 and AP.Data and AP.Data.TopMap and AP.Data.TopMap[zid]) or zid
        local zMeta = (topId > 0 and AP.Data and AP.Data.Zones and AP.Data.Zones[topId]) or nil
        if not zMeta then return "" end

        local maxDiffs = AP:GetZoneMaxDiffs(topId, zMeta.isRaid, zMeta.exp)
        if maxDiffs <= 1 then return "" end

        local srvItems = AP.serverZoneItems and AP.serverZoneItems[topId]
        local srv = srvItems and srvItems[eid]
        local dMask = tonumber(diffMaskHint) or 0
        if dMask <= 0 then
            dMask = (srv and srv.modeMask and srv.modeMask > 0) and srv.modeMask or (rec and rec.diffMask) or 0
        end
        if dMask <= 0 then
            dMask = InferRuntimeDiffMask(topId, eid, rec and rec.ilvl or 0, zMeta.isRaid, zMeta.exp)
        end
        if dMask <= 0 then return "" end

        local tbl
        if maxDiffs == 4 then
            tbl = longForm and DIFF_LONG_4 or DIFF_SHORT_4
        elseif zMeta.isRaid then
            tbl = longForm and DIFF_LONG_2R or DIFF_SHORT_2R
        else
            tbl = longForm and DIFF_LONG_2D or DIFF_SHORT_2D
        end

        local bits = { 8, 4, 2, 1 }
        local out = {}
        for _, b in ipairs(bits) do
            if tbl[b] and ((dMask % (b * 2)) >= b) then
                table.insert(out, tbl[b])
            end
        end
        return table.concat(out, "/")
    end

    function AP:GetZoneAnalysis(zoneId, opts)
        if not zoneId then return nil end
        opts = opts or {}
        local scope = opts.scope or "hero" -- "hero" | "account"
        local diffId = opts.diffId         -- nil (all) or 1..4
        local excludeHeavyQuests = (opts.excludeHeavyQuests ~= false)
        local includeCompletedList = opts.includeItems == true

        local topId = (AP.Data.TopMap and AP.Data.TopMap[zoneId]) or zoneId
        local zMeta = (AP.Data.Zones and AP.Data.Zones[topId]) or {}
        local maxDiffs = AP:GetZoneMaxDiffs(topId, opts.isRaid, opts.exp)
        local isSingleDiff = (maxDiffs == 1)
        local modeAvailable = isSingleDiff or (not diffId) or (diffId <= maxDiffs)
        local effDiffId = isSingleDiff and nil or diffId

        local cacheKey = string.format("%d:%s:%s:%s:%d", topId, scope, tostring(effDiffId or 0), excludeHeavyQuests and "1" or "0", maxDiffs)
        local zc = AP._mem.zoneCache()
        if not includeCompletedList and zc[cacheKey] then
            return zc[cacheKey]
        end

        local poolSet = {}

        -- Merge static zone items + live server ASMSG_ATC_ZONE items
        local staticList = AP.Data.ZoneItems and AP.Data.ZoneItems[topId]
        if staticList then
            for _, eid in ipairs(staticList) do
                poolSet[eid] = true
            end
        end
        local srvItems = AP.serverZoneItems[topId]
        if srvItems then
            for eid in pairs(srvItems) do
                poolSet[eid] = true
            end
        end

        local newCount, forgeCount, completedCount, totalPool = 0, 0, 0, 0
        local newImmediateStats, newMaxStats, forgeRemainStats, forgeNextStepStats = 0, 0, 0, 0
        local randNew, randForge, randDone = 0, 0, 0
        local noReqCount, heavyQuestCount, unknownStatsCount = 0, 0, 0
        local ipMeta = { count = 0, bonus = 0, best = nil }
        local forgeByTier = { [0] = 0, [1] = 0, [2] = 0 }
        local statBreakdown = {}
        local newItemsList, forgeItemsList = {}, {}
        local byDiff = {}
        for d = 1, maxDiffs do
            byDiff[d] = {
                total = 0, completed = 0, newCount = 0, forgeCount = 0, inProgressCount = 0, bestProgressPct = 0,
                newMaxStats = 0, forgeRemainStats = 0, remainStats = 0,
                forgeByTier = { [0] = 0, [1] = 0, [2] = 0 },
            }
        end

        local needBit = effDiffId and DIFF_BITS[effDiffId] or nil

        for eid in pairs(poolSet) do
            local srv = srvItems and srvItems[eid]
            local sfx = (srv and srv.suffix) or 0
            local rec = AP.ParseItemRecord(eid)
            local dMask = 1
            if not isSingleDiff then
                dMask = (srv and srv.modeMask and srv.modeMask > 0) and srv.modeMask or rec.diffMask
                if (not dMask or dMask == 0) and zMeta.exp and zMeta.exp > 0 and rec.ilvl > 0 then
                    dMask = InferRuntimeDiffMask(topId, eid, rec.ilvl, zMeta.isRaid, zMeta.exp)
                end
                if maxDiffs == 2 and dMask and dMask >= 4 then
                    -- Clamp stray heroic bits on 2-diff WotLK raids/dungeons to 25n/Heroic bit 2
                    local clamped = 0
                    if bit and bit.band then
                        if bit.band(dMask, 1) ~= 0 or bit.band(dMask, 4) ~= 0 then clamped = clamped + 1 end
                        if bit.band(dMask, 2) ~= 0 or bit.band(dMask, 8) ~= 0 then clamped = clamped + 2 end
                    else
                        clamped = (dMask >= 8) and 2 or 1
                    end
                    dMask = clamped
                end
            end

            local matchesDiff = true
            if not modeAvailable then
                matchesDiff = false
            elseif needBit and dMask and dMask > 0 then
                if bit and bit.band then
                    matchesDiff = (bit.band(dMask, needBit) ~= 0)
                else
                    matchesDiff = (math.floor(dMask / needBit) % 2 == 1)
                end
            end

            local usable, accOk = AP:CanHeroAbsorb(eid)
            local allowed = (scope == "account") and accOk or usable

            if allowed then
                local isHeavyQ = AP.IsOnlyHeavyQuest(eid)
                if isHeavyQ then
                    heavyQuestCount = heavyQuestCount + 1
                end
                local skipHeavy = excludeHeavyQuests and isHeavyQ

                if not skipHeavy then
                    local st = AP:GetItemServerStatus(eid, sfx)
                    local stDone = st.doneTier
                    local stCurPct = st.curPct
                    local stMaxPct = st.maxPct or 90
                    local stRemainPct = st.remainPct or 0
                    local stNewBasePct = st.newBasePct or 20
                    local stNextStepPct = st.nextStepPct or 0
                    local stIsDone = st.isCompleted
                    local stIsNew = st.isNew
                    local stNeedsForge = st.needsForge

                    -- Do not mutate shared statusCache record when overriding from server zone roster
                    if srv and srv.absorbed and stDone < 0 then
                        stDone = 0
                        stCurPct = AP.TIER_PCT[0] or 20
                        stRemainPct = math.max(0, stMaxPct - stCurPct)
                        stIsNew = false
                        stNeedsForge = true
                        stIsDone = false
                        stNextStepPct = math.max(0, (AP.TIER_PCT[1] or 30) - stCurPct)
                    end

                    local isRand = rec.hasRandomSuffix
                    local stats, coreSum = AP:GetItemStats(eid, sfx)
                    local isNoReq = (rec.req >= 0 and rec.req <= 1) and (rec.ilvl >= 20 or coreSum > 0)
                    local ipPct = (not stIsDone and st.ipTier ~= nil and (st.ipNeed or 0) > 0)
                        and math.min(99, math.floor(((tonumber(st.ipXp) or 0) / st.ipNeed) * 100 + 0.5))
                        or 0

                    -- Per-difficulty bucket accumulation
                    if dMask and dMask > 0 then
                        for d = 1, maxDiffs do
                            local b = DIFF_BITS[d]
                            local hit = isSingleDiff or ((bit and bit.band) and (bit.band(dMask, b) ~= 0) or (math.floor(dMask / b) % 2 == 1))
                            if hit then
                                local bd = byDiff[d]
                                bd.total = bd.total + 1
                                if ipPct > 0 then
                                    bd.inProgressCount = bd.inProgressCount + 1
                                    if ipPct > (bd.bestProgressPct or 0) then bd.bestProgressPct = ipPct end
                                end
                                if stIsDone then
                                    bd.completed = bd.completed + 1
                                elseif stIsNew then
                                    bd.newCount = bd.newCount + 1
                                    if not isRand then
                                        local gMax = math.floor(coreSum * (stMaxPct / 100) + 0.5)
                                        bd.newMaxStats = bd.newMaxStats + gMax
                                        bd.remainStats = bd.remainStats + gMax
                                    end
                                elseif stNeedsForge then
                                    bd.forgeCount = bd.forgeCount + 1
                                    bd.forgeByTier[stDone] = (bd.forgeByTier[stDone] or 0) + 1
                                    if not isRand then
                                        local gRem = math.floor(coreSum * (stRemainPct / 100) + 0.5)
                                        bd.forgeRemainStats = bd.forgeRemainStats + gRem
                                        bd.remainStats = bd.remainStats + gRem
                                    end
                                end
                            end
                        end
                    end

                    if matchesDiff then
                        totalPool = totalPool + 1
                        if isNoReq and not stIsDone then
                            noReqCount = noReqCount + 1
                        end
                        if not rec.statsKnown and not isRand then
                            unknownStatsCount = unknownStatsCount + 1
                        end
                        if ipPct > 0 then
                            ipMeta.count = ipMeta.count + 1
                            ipMeta.bonus = ipMeta.bonus + math.floor((ipPct / 100) * math.max(10, coreSum) * 0.25)
                            if (not ipMeta.best) or ipPct > ipMeta.best.pct then
                                ipMeta.best = {
                                    id = eid,
                                    name = rec.name or GetItemInfo(eid) or ("Предмет #" .. eid),
                                    tier = st.ipTier,
                                    tierName = AP.TIER_NAMES[st.ipTier] or "",
                                    pct = ipPct,
                                    xp = st.ipXp or 0,
                                    need = st.ipNeed or 0,
                                }
                            end
                        end

                        if stIsDone then
                            completedCount = completedCount + 1
                            if isRand then randDone = randDone + 1 end
                        elseif stIsNew then
                            if isRand then
                                randNew = randNew + 1
                            else
                                newCount = newCount + 1
                                local gImm = math.floor(coreSum * (stNewBasePct / 100) + 0.5)
                                local gMax = math.floor(coreSum * (stMaxPct / 100) + 0.5)
                                newImmediateStats = newImmediateStats + gImm
                                newMaxStats = newMaxStats + gMax
                                for sid, sval in pairs(stats) do
                                    if sval > 0 and sid ~= 1 and sid ~= 1000 then
                                        statBreakdown[sid] = (statBreakdown[sid] or 0) + math.floor(sval * (stMaxPct / 100) + 0.5)
                                    end
                                end
                                if includeCompletedList then
                                    table.insert(newItemsList, { id = eid, sfx = sfx, stats = coreSum, gainMax = gMax, ilvl = rec.ilvl, req = rec.req, diffMask = dMask })
                                end
                            end
                        elseif stNeedsForge then
                            if isRand then
                                randForge = randForge + 1
                            else
                                forgeCount = forgeCount + 1
                                forgeByTier[stDone] = (forgeByTier[stDone] or 0) + 1
                                local gRem = math.floor(coreSum * (stRemainPct / 100) + 0.5)
                                local gNext = math.floor(coreSum * (stNextStepPct / 100) + 0.5)
                                forgeRemainStats = forgeRemainStats + gRem
                                forgeNextStepStats = forgeNextStepStats + gNext
                                for sid, sval in pairs(stats) do
                                    if sval > 0 and sid ~= 1 and sid ~= 1000 then
                                        statBreakdown[sid] = (statBreakdown[sid] or 0) + math.floor(sval * (stRemainPct / 100) + 0.5)
                                    end
                                end
                                if includeCompletedList then
                                    table.insert(forgeItemsList, { id = eid, sfx = sfx, tier = stDone, gainRem = gRem, ilvl = rec.ilvl, req = rec.req, diffMask = dMask })
                                end
                            end
                        end
                    end
                end
            end
        end

        local srvZ = AP.serverZones[topId] or AP.serverZones[zoneId]
        local res = {
            zoneId = topId,
            zoneName = (zMeta.name and zMeta.name ~= "" and zMeta.name) or (srvZ and srvZ.name) or ("Зона " .. topId),
            cat = zMeta.cat or 7,
            exp = zMeta.exp or 0,
            isRaid = zMeta.isRaid or false,
            minLvl = zMeta.minL or 0,
            maxLvl = zMeta.maxL or 0,
            scope = scope,
            diffId = diffId,
            maxDiffs = maxDiffs,
            isSingleDiff = isSingleDiff,
            modeAvailable = modeAvailable,

            totalPool = totalPool,
            completedCount = completedCount,
            newCount = newCount,
            newImmediateStats = newImmediateStats,
            newMaxStats = newMaxStats,
            newItems = newItemsList,

            forgeCount = forgeCount,
            forgeRemainStats = forgeRemainStats,
            forgeNextStepStats = forgeNextStepStats,
            forgeByTier = forgeByTier,
            forgeItems = forgeItemsList,

            totalRemainStats = newMaxStats + forgeRemainStats,
            statBreakdown = statBreakdown,

            randomSuffixNew = randNew,
            randomSuffixForge = randForge,
            randomSuffixDone = randDone,
            noReqCount = noReqCount,
            heavyQuestCount = heavyQuestCount,
            unknownStatsCount = unknownStatsCount,
            inProgressCount = ipMeta.count,
            inProgressBonus = ipMeta.bonus,
            bestProgressItem = ipMeta.best,

            byDiff = byDiff,
            serverTotal = srvZ and srvZ.total or nil,
            serverRemain = srvZ and srvZ.remain or nil,
            hasServerZoneRoster = (srvItems ~= nil),
        }

        if not includeCompletedList then
            AP._mem.setZoneCache(cacheKey, res)
        end
        return res
    end

    function AP:GetRecommendations(opts)
        opts = opts or {}
        local mode = opts.mode or "new" -- "new" | "forge" | "combined"
        local scope = opts.scope or "hero"
        local limit = opts.limit or 25
        local onlyInstances = opts.onlyInstances == true
        local filterIsRaid = opts.isRaid
        local filterExp = opts.exp
        local filterDiffId = opts.diffId
        local maxPlayerLvl = opts.maxLevel or UnitLevel("player") or 80

        local lockedZones = opts.lockedZones
        local unlockedOnly = (opts.unlockedOnly == true)
        local results = {}
        local zones = AP.Data and AP.Data.Zones or {}
        for zid, zMeta in pairs(zones) do
            if AP.Data.ZoneItems and AP.Data.ZoneItems[zid] then
                local isInst = (zMeta.exp and zMeta.exp > 0) or (zid >= 990001 and zid <= 990006)
                local matchFilter = true
                if filterIsRaid ~= nil and (zMeta.isRaid ~= filterIsRaid) then matchFilter = false end
                if filterExp ~= nil and zMeta.exp ~= filterExp then matchFilter = false end
                local isLocked = (lockedZones and (lockedZones[zid] or (zMeta.name and lockedZones[zMeta.name]))) and true or false
                if unlockedOnly and isLocked then matchFilter = false end
                local levelOk = true
                if zMeta.minL and zMeta.minL > 0 and zMeta.minL > (maxPlayerLvl + 2) then
                    levelOk = false
                end
                local exclHeavy
                if opts.excludeHeavyQuests ~= nil then
                    exclHeavy = (opts.excludeHeavyQuests ~= false)
                else
                    exclHeavy = (AP:GetSetting("excludeHeavyQuests") ~= false)
                end
                if matchFilter and (not onlyInstances or isInst) and levelOk then
                    local za = AP:GetZoneAnalysis(zid, { scope = scope, diffId = filterDiffId, excludeHeavyQuests = exclHeavy })
                    if za and za.modeAvailable ~= false then
                        za.isLocked = isLocked
                        local fb = za.forgeByTier or {}
                        local nonTit = (za.newCount or 0) + (za.forgeCount or 0)
                        za.nonTitanicCount = nonTit
                        local score = 0
                        if mode == "new" then
                            score = za.newMaxStats + (za.newCount * 10)
                        elseif mode == "forge" then
                            score = za.forgeRemainStats + (za.forgeCount * 10)
                        elseif mode == "wednesday" then
                            local forgeRollVal = (za.newCount or 0) * 140
                                + ((fb[0] or 0) * 100)
                                + ((fb[1] or 0) * 65)
                                + ((fb[2] or 0) * 35)
                            score = forgeRollVal + math.floor((za.totalRemainStats or 0) * 0.65)
                            if score > 0 then
                                if isLocked then
                                    score = math.floor(score * 0.45)
                                elseif not zMeta.isRaid then
                                    -- Dungeons have no daily normal lock and easy heroic resets
                                    score = math.floor(score * 1.35)
                                end
                            end
                        else
                            score = za.totalRemainStats + (nonTit * 10)
                        end
                        if score > 0 and opts.prioritizeInProgress ~= false and (za.inProgressCount or 0) > 0 then
                            score = score + (za.inProgressBonus or 0) + (za.inProgressCount * 25)
                        end
                        if score > 0 then
                            za.recScore = score
                            table.insert(results, za)
                        end
                    end
                end
            end
        end

        table.sort(results, function(a, b)
            if a.recScore ~= b.recScore then return a.recScore > b.recScore end
            return (a.zoneName or "") < (b.zoneName or "")
        end)

        if limit and #results > limit then
            local trimmed = {}
            for i = 1, limit do trimmed[i] = results[i] end
            return trimmed
        end
        return results
    end

    function AP:GetItemEraAndType(itemId, infoHint)
        local info = infoHint or AP:GetItemInfo(itemId)
        local eid = (info and info.itemId) or AP.ExtractItemId(itemId)
        local zonesTbl = AP.Data and AP.Data.Zones or {}
        local topMap = AP.Data and AP.Data.TopMap or {}
        local ilvl = (info and info.ilvl) or 0

        local bestZid = (info and info.primaryZone and info.primaryZone > 0) and (topMap[info.primaryZone] or info.primaryZone) or 0
        local isRaid, isDungeon = false, false

        local function inspectZone(rawZ)
            if not rawZ or rawZ <= 0 then return nil end
            local tz = topMap[rawZ] or rawZ
            local zm = zonesTbl[tz]
            if zm then
                if bestZid == 0 then bestZid = tz end
                if zm.isRaid then
                    isRaid = true
                elseif (zm.exp and zm.exp > 0) or zm.cat == 5 then
                    isDungeon = true
                end
            end
            return zm
        end

        local bestMeta = inspectZone(bestZid)
        if info and info.sources then
            for _, sc in ipairs(info.sources) do
                if sc.zoneId and sc.zoneId > 0 then
                    local zm = inspectZone(sc.zoneId)
                    if (not bestMeta) and zm then
                        bestMeta = zm
                        bestZid = topMap[sc.zoneId] or sc.zoneId
                    elseif bestMeta and (not bestMeta.exp or bestMeta.exp == 0) and zm and zm.exp and zm.exp > 0 then
                        bestMeta = zm
                        bestZid = topMap[sc.zoneId] or sc.zoneId
                    end
                end
            end
        end

        local itemExp = 1
        if bestMeta and bestMeta.exp and bestMeta.exp > 0 then
            itemExp = bestMeta.exp
        elseif ilvl >= 166 then
            itemExp = 3
        elseif ilvl >= 85 then
            itemExp = 2
        elseif bestMeta then
            if bestMeta.cat == 3 or bestMeta.cat == 7 then
                itemExp = 3
            elseif bestMeta.cat == 4 then
                itemExp = 2
            else
                itemExp = 1
            end
        end

        return itemExp, isRaid, isDungeon, bestZid
    end

    function AP:GetNoReqLevelItems(opts)
        opts = opts or {}
        local scope = opts.scope or "hero"
        local includeCompleted = opts.includeCompleted == true
        local filterExp = opts.exp
        local filterIsRaid = opts.isRaid
        local onlyWorld = (opts.onlyWorld == true)
        local onlyInst = (opts.onlyInst == true)
        local filterZoneId = tonumber(opts.zoneId)
        if filterZoneId and filterZoneId > 0 then
            filterZoneId = (AP.Data and AP.Data.TopMap and AP.Data.TopMap[filterZoneId]) or filterZoneId
        else
            filterZoneId = nil
        end
        local searchQ = (opts.searchText and opts.searchText ~= "") and AP.Norm(opts.searchText) or nil
        local lockedZones = opts.lockedZones
        local unlockedOnly = (opts.unlockedOnly == true)
        local exclHeavy = (opts.excludeHeavyQuests == true)
        local items = AP.Data and AP.Data.Items or {}
        local zonesTbl = AP.Data and AP.Data.Zones or {}

        local cached = AP._mem.getNoReqCache()
        if not cached then
            cached = {}
            for eid in pairs(items) do
                local rec = AP.ParseItemRecord(eid)
                if rec.req >= 0 and rec.req <= 1 and not rec.noAttune and (rec.ilvl >= 20 or rec.coreSum > 0) then
                    table.insert(cached, eid)
                end
            end
            AP._mem.setNoReqCache(cached)
        end

        local newList, forgeList, doneCount = {}, {}, 0
        for _, eid in ipairs(cached) do
            local usable, accOk = AP:CanHeroAbsorb(eid)
            local ok = (scope == "account") and accOk or usable
            if ok then
                local info = AP:GetItemInfo(eid)
                if info then
                    local iExp, iRaid, iDung, iZid = AP:GetItemEraAndType(eid, info)
                    local rZid = (iZid and iZid > 0) and iZid or info.primaryZone
                    local zMeta = (rZid and rZid > 0) and zonesTbl[rZid] or nil
                    info.itemExp = iExp
                    info.zoneIsRaid = iRaid
                    info.zoneIsDungeon = iDung
                    info.resolvedZone = rZid
                    info.isInstanceZone = (rZid and rZid > 0) and AP:IsZoneInstance(rZid) or false
                    info.zoneName = (zMeta and zMeta.name) or nil

                    local pass = true
                    if filterExp ~= nil and iExp ~= filterExp then pass = false end
                    if pass and onlyWorld and (iRaid or iDung) then pass = false end
                    if pass and onlyInst and not info.isInstanceZone then pass = false end
                    if pass and filterIsRaid == true and not iRaid then pass = false end
                    if pass and filterIsRaid == false and not iDung then pass = false end
                    if pass and filterZoneId then
                        local zHit = (rZid == filterZoneId)
                        if not zHit and info.sources then
                            for _, sc in ipairs(info.sources) do
                                if sc.zoneId == filterZoneId then zHit = true; break end
                            end
                        end
                        if not zHit then pass = false end
                    end
                    if pass and searchQ and searchQ ~= "" then
                        local nItem = AP.Norm(info.name or "")
                        local nZone = AP.Norm(info.zoneName or "")
                        if not (nItem:find(searchQ, 1, true) or nZone:find(searchQ, 1, true)) then
                            pass = false
                        end
                    end
                    if pass and exclHeavy and info.onlyHeavyQuest then pass = false end
                    if pass and unlockedOnly and lockedZones and rZid and lockedZones[rZid] then
                        pass = false
                    end

                    if pass then
                        if info.isCompleted then
                            doneCount = doneCount + 1
                            if includeCompleted then table.insert(forgeList, info) end
                        elseif info.isNew then
                            table.insert(newList, info)
                        elseif info.needsForge then
                            table.insert(forgeList, info)
                        end
                    end
                end
            end
        end

        local function byValDesc(a, b)
            if a.coreStatsSum ~= b.coreStatsSum then return a.coreStatsSum > b.coreStatsSum end
            if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
            return a.itemId < b.itemId
        end
        table.sort(newList, byValDesc)
        table.sort(forgeList, byValDesc)

        return {
            newItems = newList,
            forgeItems = forgeList,
            completedCount = doneCount,
            totalCount = #newList + #forgeList + doneCount,
        }
    end

    local function GetZonePoolLookup(zoneId)
        if not zoneId then return nil end
        local topId = (AP.Data and AP.Data.TopMap and AP.Data.TopMap[zoneId]) or zoneId
        local set = {}
        local zi = AP.Data and AP.Data.ZoneItems and AP.Data.ZoneItems[topId]
        if zi then
            for _, eid in ipairs(zi) do set[eid] = true end
        end
        local sz = AP.serverZoneItems and AP.serverZoneItems[topId]
        if sz then
            for eid in pairs(sz) do set[eid] = true end
        end
        return set
    end

    function AP:IsItemBlacklisted(itemId, tier)
        local eid = AP.ExtractItemId(itemId)
        if not eid then return false end
        local as = AP.autoSwap
        local bl = as and as.blacklist
        local blByE = as and as.blacklistByEntry
        if tier ~= nil then
            if bl and (bl[eid .. ":" .. tier] or bl[eid .. ":-1"]) then return true end
        elseif blByE and blByE[eid] then
            return true
        end
        local extLock = rawget(_G, "CustomAttuneAutoSwapLock")
        local extBl = extLock and extLock.bl
        if extBl then
            if tier ~= nil and extBl[eid .. ":" .. tier] then return true end
            if tier == nil then
                for t = 0, 3 do
                    if extBl[eid .. ":" .. t] then return true end
                end
            end
        end
        return false
    end

    function AP:GetAutoSwapSummary()
        local as = AP.autoSwap or {}
        local blCount = 0
        for _ in pairs(as.blacklist or {}) do blCount = blCount + 1 end
        return {
            on = as.on,
            groupMask = as.groupMask,
            qualMask = as.qualMask,
            orderWorst = as.orderWorst,
            boeAllowed = as.boeAllowed,
            unlocked = as.unlocked,
            sellMask = as.sellMask,
            srcMask = as.srcMask,
            confirm = as.confirm,
            active = as.active,
            blacklistCount = blCount,
        }
    end

    local function ScanContainerSlot(res, whereLabel, bag, slot, link, instTier)
        if not link then return end
        local eid = AP.ExtractItemId(link)
        if not eid then return end
        local usable, accOk = AP:CanHeroAbsorb(eid, link)
        if not (usable or accOk) then return end
        local info = AP:GetItemInfo(eid, link)
        if not info then return end

        local itemTier = instTier
        if itemTier == nil then
            if whereLabel == "equip" then
                itemTier = AP.forgeEquip[slot]
                if itemTier == nil and not AP.forgeMapLoaded then itemTier = AP.forgeByEntry[eid] end
            elseif whereLabel == "bag" then
                itemTier = AP.forgeBag[bag] and AP.forgeBag[bag][slot]
                if itemTier == nil and not AP.forgeMapLoaded then itemTier = AP.forgeByEntry[eid] end
            else
                if whereLabel == "bank" then
                    itemTier = AP.forgeBag[bag] and AP.forgeBag[bag][slot]
                end
                if itemTier == nil then
                    itemTier = AP.forgeByEntry[eid]
                end
            end
        end
        itemTier = itemTier or 0

        info.bag = bag
        info.slot = slot
        info.where = whereLabel
        info.link = link
        info.instanceTier = itemTier
        info.instanceTierName = AP.TIER_NAMES[itemTier] or AP.TIER_NAMES[0]
        info.isBlacklisted = AP:IsItemBlacklisted(eid, itemTier)
        local tierPct = AP.TIER_PCT
        local instPct = tierPct[itemTier] or 20
        info.canGainNow = usable and (not info.isCompleted) and (itemTier > info.doneTier)
        if info.canGainNow then
            info.gainNowPct = math.max(0, instPct - (info.curPct or 0))
            info.gainNowStats = math.floor((info.coreStatsSum or 0) * (info.gainNowPct / 100) + 0.5)
        else
            info.gainNowPct = 0
            info.gainNowStats = 0
        end

        if info.isCompleted then
            table.insert(res.completedItems, info)
        elseif info.isNew then
            table.insert(res.newItems, info)
        else
            table.insert(res.forgeItems, info)
        end
        if info.canGainNow then
            table.insert(res.readyToAbsorb, info)
        end
    end

    function AP:GetBagItemsStatus(includeBankAndEquip)
        local res = { newItems = {}, forgeItems = {}, completedItems = {}, readyToAbsorb = {} }
        if includeBankAndEquip ~= false then
            for slot = 1, 19 do
                local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
                if link then ScanContainerSlot(res, "equip", nil, slot, link, AP.forgeEquip[slot]) end
            end
        end
        for bag = 0, 4 do
            local slots = (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
            for slot = 1, slots do
                local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
                if link then ScanContainerSlot(res, "bag", bag, slot, link, nil) end
            end
        end
        if includeBankAndEquip ~= false and _G.BankFrame and _G.BankFrame:IsShown() then
            for _, bag in ipairs({ -1, 5, 6, 7, 8, 9, 10, 11 }) do
                local slots = (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
                for slot = 1, slots do
                    local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
                    if link then ScanContainerSlot(res, "bank", bag, slot, link, nil) end
                end
            end
        end
        return res
    end

    function AP:GetOwnedUpgradeCandidates(zoneIdFilter, includeNeedsForge)
        local st = AP:GetBagItemsStatus(true)
        local zonePool = zoneIdFilter and GetZonePoolLookup(zoneIdFilter) or nil
        local topFilter = (zoneIdFilter and AP.Data and AP.Data.TopMap and AP.Data.TopMap[zoneIdFilter]) or zoneIdFilter
        local out = {}
        local seenOwned = {}
        local function AddBagStatusList(list)
            for _, info in ipairs(list or {}) do
                if (not zonePool) or zonePool[info.itemId] or info.primaryZone == topFilter then
                    local okKey = (info.where or "") .. ":" .. tostring(info.bag or "") .. ":" .. tostring(info.slot or "") .. ":" .. tostring(info.itemId or 0)
                    if not seenOwned[okKey] then
                        seenOwned[okKey] = true
                        if not info.canGainNow then
                            info.needsForgeUpgrade = true
                        end
                        table.insert(out, info)
                    end
                end
            end
        end
        AddBagStatusList(st.readyToAbsorb)
        if includeNeedsForge then
            for _, bucket in ipairs({ st.newItems, st.forgeItems }) do
                for _, info in ipairs(bucket or {}) do
                    if (not info.isCompleted) and (info.usableOnHero ~= false) then
                        AddBagStatusList({ info })
                    end
                end
            end
        end
        local function PushExternal(whereLabel, bag, slot, dbId, eid, link, xTier, cntVal, dspReq)
            if not eid then return end
            if zonePool and not zonePool[eid] then return end
            local usable = AP:CanHeroAbsorb(eid, link)
            if not usable then return end
            local info = AP:GetItemInfo(eid, link)
            local pTier = xTier or 0
            if info and (not info.isCompleted) and ((pTier > info.doneTier) or includeNeedsForge) then
                local gPct = AP.TIER_PCT[pTier] or 20
                local canNow = (pTier > info.doneTier)
                info.where = whereLabel
                info.bag = bag
                info.slot = slot
                info.dbId = dbId
                info.count = cntVal or 1
                info.dspReq = dspReq or 0
                info.link = link
                info.instanceTier = pTier
                info.instanceTierName = AP.TIER_NAMES[pTier] or ""
                info.isBlacklisted = AP:IsItemBlacklisted(eid, pTier)
                info.canGainNow = canNow
                info.needsForgeUpgrade = not canNow
                info.gainNowPct = canNow and math.max(0, gPct - (info.curPct or 0)) or 0
                info.gainNowStats = canNow and math.floor((info.coreStatsSum or 0) * (info.gainNowPct / 100) + 0.5) or 0
                table.insert(out, info)
            end
        end
        if _G.GuildBankFrame and _G.GuildBankFrame:IsShown() and type(GetGuildBankItemLink) == "function" then
            for tab, slots in pairs(AP.forgeGuild or {}) do
                for slot, gTier in pairs(slots) do
                    local link = GetGuildBankItemLink(tab, slot)
                    if link then
                        PushExternal("guild", tab, slot, nil, AP.ExtractItemId(link), link, gTier, 1, 0)
                    end
                end
            end
        end
        local seenPetDb = {}
        local pl = rawget(_G, "PRIME_PetLoot")
        if pl and type(pl.items) == "table" then
            for _, it in pairs(pl.items) do
                if type(it) == "table" and it.itemId and it.itemId > 0 then
                    if it.dbId then seenPetDb[it.dbId] = true end
                    local lk = "item:" .. it.itemId .. ":0:0:0:0:0:" .. (it.sfx or 0)
                    PushExternal("petloot", nil, nil, it.dbId, it.itemId, lk, it.forgeTier or 0, it.count or 1, it.dspReq or 0)
                end
            end
        end
        for dbId, it in pairs(AP.petLootItems or {}) do
            if not seenPetDb[dbId] and it.itemId and it.itemId > 0 then
                local lk = "item:" .. it.itemId .. ":0:0:0:0:0:" .. (it.sfx or 0)
                PushExternal("petloot", nil, nil, dbId, it.itemId, lk, it.forgeTier or 0, it.count or 1, it.dspReq or 0)
            end
        end
        table.sort(out, function(a, b)
            local ra = a.canGainNow and 1 or 0
            local rb = b.canGainNow and 1 or 0
            if ra ~= rb then return ra > rb end
            if ra == 1 and (a.gainNowStats or 0) ~= (b.gainNowStats or 0) then
                return (a.gainNowStats or 0) > (b.gainNowStats or 0)
            end
            if (a.remainStats or 0) ~= (b.remainStats or 0) then
                return (a.remainStats or 0) > (b.remainStats or 0)
            end
            return (a.ilvl or 0) > (b.ilvl or 0)
        end)
        return out
    end

    function AP:GetAuctionForgeCandidates()
        local out = {}
        local pah = rawget(_G, "PrimeAH")
        if pah and pah.frame and pah.frame:IsShown() then
            local panels = pah.panels or {}
            local ib = panels.itemBuy
            if ib and ib:IsShown() and ib.entry and ib.ItemList and type(ib.ItemList.data) == "table" then
                local eid = ib.entry
                for idx, d in ipairs(ib.ItemList.data) do
                    if idx > 250 then break end
                    local link = "item:" .. eid .. ":" .. (d.ench or 0) .. ":0:0:0:0:" .. (d.randProp or 0) .. ":" .. (d.suffix or 0)
                    local usable = AP:CanHeroAbsorb(eid, link)
                    if usable then
                        local info = AP:GetItemInfo(eid, link)
                        if info and not info.isCompleted then
                            local bo = d.buyout or 0
                            local cnt = d.count or 1
                            local srvTier = AP.auctionForge[eid .. ":" .. bo .. ":" .. cnt]
                            if srvTier ~= nil and srvTier > info.doneTier then
                                local lotPct = AP.TIER_PCT[srvTier] or 20
                                info.buyout = bo
                                info.minBid = d.minBid or 0
                                info.count = cnt
                                info.own = d.own and true or false
                                info.lotTier = srvTier
                                info.lotTierName = AP.TIER_NAMES[srvTier] or AP.TIER_NAMES[0]
                                info.gainNowPct = math.max(0, lotPct - (info.curPct or 0))
                                info.gainNowStats = math.floor((info.coreStatsSum or 0) * (info.gainNowPct / 100) + 0.5)
                                info.primeRow = ib.row
                                info.primeLot = d
                                table.insert(out, info)
                            elseif srvTier == nil then
                                local lotTier = info.isNew and 0 or nil
                                local lotPct = info.isNew and (AP.TIER_PCT[0] or 20) or (AP.TIER_PCT[3] or 90)
                                info.buyout = bo
                                info.minBid = d.minBid or 0
                                info.count = cnt
                                info.own = d.own and true or false
                                info.lotTier = lotTier
                                info.lotTierName = info.isNew and AP.TIER_NAMES[0] or "Нужна ковка"
                                info.needsForgeCheck = not info.isNew
                                info.gainNowPct = info.isNew and (info.newBasePct or lotPct) or 0
                                info.gainNowStats = info.isNew and (info.newImmediateStats or 0) or 0
                                info.primeRow = ib.row
                                info.primeLot = d
                                table.insert(out, info)
                            end
                        end
                    end
                end
            elseif panels.browse and panels.browse:IsShown() and pah.browse and pah.browse.list and type(pah.browse.list.data) == "table" then
                for idx, d in ipairs(pah.browse.list.data) do
                    if idx > 250 then break end
                    local eid = d.entry
                    if eid then
                        local link = "item:" .. eid .. ":0:0:0:0:0:" .. (d.randProp or 0)
                        local usable, accOk = AP:CanHeroAbsorb(eid, link)
                        if usable then
                            local info = AP:GetItemInfo(eid, link)
                            if info and not info.isCompleted then
                                local srvTier = AP.auctionForge[eid .. ":" .. (d.minBuy or 0) .. ":" .. (d.qty or 1)]
                                info.buyout = d.minBuy or 0
                                info.count = d.qty or 1
                                info.own = d.own and true or false
                                info.primeRow = d
                                info.commodity = d.commodity and true or false
                                if srvTier ~= nil and srvTier > info.doneTier then
                                    local lotPct = AP.TIER_PCT[srvTier] or 20
                                    info.lotTier = srvTier
                                    info.lotTierName = AP.TIER_NAMES[srvTier] or AP.TIER_NAMES[0]
                                    info.gainNowPct = math.max(0, lotPct - (info.curPct or 0))
                                    info.gainNowStats = math.floor((info.coreStatsSum or 0) * (info.gainNowPct / 100) + 0.5)
                                    table.insert(out, info)
                                elseif srvTier == nil then
                                    info.lotTier = info.isNew and 0 or nil
                                    info.lotTierName = info.isNew and "Новый (+20%)" or ("Ковка (" .. (info.doneTierName or "") .. ")")
                                    info.needsForgeCheck = not info.isNew
                                    info.gainNowPct = info.isNew and (info.newBasePct or 20) or 0
                                    info.gainNowStats = info.isNew and (info.newImmediateStats or 0) or 0
                                    table.insert(out, info)
                                end
                            end
                        elseif accOk then
                            -- Track alt-usable info cleanly without polluting main hero list unless needed
                        end
                    end
                end
            end
            table.sort(out, function(a, b)
                if (a.gainNowStats or 0) ~= (b.gainNowStats or 0) then return (a.gainNowStats or 0) > (b.gainNowStats or 0) end
                if (a.isNew and 1 or 0) ~= (b.isNew and 1 or 0) then return a.isNew end
                if (a.remainStats or 0) ~= (b.remainStats or 0) then return (a.remainStats or 0) > (b.remainStats or 0) end
                return (a.buyout or 0) < (b.buyout or 0)
            end)
            return out
        end

        if not _G.AuctionFrameBrowse or not _G.AuctionFrameBrowse:IsShown() or type(GetAuctionItemInfo) ~= "function" then
            return out
        end
        local off = (type(FauxScrollFrame_GetOffset) == "function" and _G.BrowseScrollFrame and FauxScrollFrame_GetOffset(_G.BrowseScrollFrame)) or 0
        local n = _G.NUM_BROWSE_TO_DISPLAY or 8
        for i = 1, n do
            local idx = off + i
            local nm, _, count, _, _, _, _, _, buyout9, buyout10, _, _, _, _, _, _, itemId17 = GetAuctionItemInfo("list", idx)
            local link = (type(GetAuctionItemLink) == "function") and GetAuctionItemLink("list", idx) or nil
            local itemId = itemId17 or (link and AP.ExtractItemId(link))
            local buyout = (itemId17 and buyout10) or buyout9 or 0
            if nm and itemId then
                local srvTier = AP.auctionForge[itemId .. ":" .. buyout .. ":" .. (count or 1)]
                link = link or ("item:" .. itemId)
                local usable = AP:CanHeroAbsorb(itemId, link)
                if usable then
                    local info = AP:GetItemInfo(itemId, link)
                    if info and not info.isCompleted then
                        if srvTier ~= nil and srvTier > info.doneTier then
                            local lotPct = AP.TIER_PCT[srvTier] or 20
                            info.auctionIndex = idx
                            info.buyout = buyout or 0
                            info.lotTier = srvTier
                            info.lotTierName = AP.TIER_NAMES[srvTier] or AP.TIER_NAMES[0]
                            info.gainNowPct = math.max(0, lotPct - (info.curPct or 0))
                            info.gainNowStats = math.floor((info.coreStatsSum or 0) * (info.gainNowPct / 100) + 0.5)
                            table.insert(out, info)
                        elseif srvTier == nil then
                            info.auctionIndex = idx
                            info.buyout = buyout or 0
                            info.lotTier = info.isNew and 0 or nil
                            info.lotTierName = info.isNew and (AP.TIER_NAMES[0] or "Обычный") or "Нужна ковка"
                            info.needsForgeCheck = not info.isNew
                            info.gainNowPct = info.isNew and (info.newBasePct or AP.TIER_PCT[0] or 20) or 0
                            info.gainNowStats = info.isNew and (info.newImmediateStats or 0) or 0
                            table.insert(out, info)
                        end
                    end
                end
            end
        end
        table.sort(out, function(a, b)
            return (a.gainNowStats or 0) > (b.gainNowStats or 0)
        end)
        return out
    end

    local giftCache = { data = nil, key = nil, tipDescBySpell = {} }

    local function ComputeDayRemaining()
        local h, m = 0, 0
        if type(GetGameTime) == "function" then
            h, m = GetGameTime()
        end
        local rem = 24 * 3600 - ((tonumber(h) or 0) * 3600 + (tonumber(m) or 0) * 60)
        if rem <= 0 then rem = rem + 86400 end
        return rem, string.format("%02d:%02d:00", math.floor(rem / 3600), math.floor((rem % 3600) / 60))
    end

    local function ReadBuffDescriptionOnce(auraIndex, cacheKey)
        if giftCache.tipDescBySpell[cacheKey] ~= nil then
            return giftCache.tipDescBySpell[cacheKey]
        end
        if InCombatLockdown and InCombatLockdown() then return nil end
        local tip = _G.AttuneParserScanTip
        if not tip or type(tip.SetUnitBuff) ~= "function" then return nil end
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        tip:ClearLines()
        local ok = pcall(function() tip:SetUnitBuff("player", auraIndex) end)
        local parts = {}
        if ok then
            for lineIdx = 2, (tip:NumLines() or 0) do
                local fs = _G["AttuneParserScanTipTextLeft" .. lineIdx]
                local t = fs and fs:GetText()
                if t and t ~= "" and not t:find("Дар исчезнет через:", 1, true) and not t:find("Осталось", 1, true) then
                    table.insert(parts, t)
                end
            end
        end
        tip:Hide()
        local joined = (#parts > 0) and table.concat(parts, " ") or ""
        if ok and joined ~= "" then
            giftCache.tipDescBySpell[cacheKey] = joined
        end
        return joined
    end

    function AP:GetActiveDailyGift(forceRefresh)
        local remSec, remStr = ComputeDayRemaining()
        local gKey, gName, gIcon, gSpell, gIdx = nil, nil, nil, nil, nil
        local hasElixir = false
        local hasExpElixir = false
        local hasExpHoliday = false
        local hasNewbieBless = false
        local hasAuraFn = (type(UnitAura) == "function")
        if hasAuraFn then
            for i = 1, 40 do
                local nm, _, ic, _, _, _, _, _, _, _, sid = UnitAura("player", i, "HELPFUL")
                if not nm then break end
                local dk = AP.DAILY_GIFT_NAMES[nm]
                if not dk then
                    if sid == 900204 then
                        dk = "thu"
                    elseif sid == 900206 or sid == 900214 then
                        dk = "sat"
                    elseif sid == 900207 then
                        dk = "sun"
                    end
                end
                if dk then
                    gKey, gName, gIcon, gSpell, gIdx = dk, nm, ic, sid, i
                elseif sid == 900210 or nm:find("Эликсир поглощения", 1, true) then
                    hasElixir = true
                elseif sid == 900211 or nm:find("Эликсир двойного опыта", 1, true) then
                    hasExpElixir = true
                elseif sid == 900125 or nm:find("Праздник опыта", 1, true) then
                    hasExpHoliday = true
                elseif sid == 1040174 or sid == 1040079 or nm:find("Благословение новичка", 1, true) then
                    hasNewbieBless = true
                end
            end
        end

        local desc = ""
        local parsedNum, parsedUnit = nil, nil
        if gIdx then
            local cKey = tostring(gSpell or gName)
            desc = ReadBuffDescriptionOnce(gIdx, cKey) or ""
            if desc ~= "" then
                local pct = desc:match("(%d+)%%")
                if pct then
                    parsedNum, parsedUnit = tonumber(pct), "%"
                else
                    local mult = desc:match("[xхXХ](%d+[%.%,]?%d*)")
                    if mult then
                        mult = mult:gsub(",", ".")
                        parsedNum, parsedUnit = tonumber(mult), "x"
                    end
                end
            end
        end

        local mw = AP.mentorWhere
        local isWed = (gKey == "wed")
        local isThu = (gKey == "thu" or gSpell == 900204)
        local isSat = (gKey == "sat" or gSpell == 900206 or gSpell == 900214)
        local isSun = (gKey == "sun" or gSpell == 900207)
        if not hasAuraFn and mw and mw.v2 then
            if (mw.gift or 0) > 0 then isSat = true end
            if (mw.elixir or 0) > 0 then hasElixir = true end
        end
        local xpMult = 1 + (isSat and 1 or 0) + (hasElixir and 1 or 0)

        local res = {
            active = (gKey ~= nil),
            key = gKey,
            name = gName,
            spellId = gSpell,
            icon = gIcon,
            desc = desc,
            parsedNum = parsedNum,
            parsedUnit = parsedUnit,
            isWednesday = isWed,
            isThursday = isThu,
            isSaturday = isSat,
            isSunday = isSun,
            hasElixir = hasElixir,
            hasExpElixir = hasExpElixir,
            hasExpHoliday = hasExpHoliday,
            hasNewbieBless = hasNewbieBless,
            xpMult = xpMult,
            vendorRefundPct = isThu and 100 or 50,
            remSeconds = remSec,
            remText = remStr,
        }
        AP.activeGift = res
        return res
    end

    function AP:GetForgeMaterialStock()
        local ids = AP.FORGE_ITEM_IDS
        local cnt = function(id)
            if type(GetItemCount) ~= "function" then return 0 end
            return tonumber(GetItemCount(id, true)) or 0
        end
        local bg = AP.bagum or {}
        local r1 = (bg.r1 and bg.r1 > 0) and bg.r1 or 3
        local r2 = (bg.r2 and bg.r2 > 0) and bg.r2 or 3
        local fee = (bg.fee and bg.fee >= 0) and bg.fee or 1000000
        local boxes = 0
        for _, bid in ipairs(ids.titanBoxes) do
            boxes = boxes + cnt(bid)
        end
        local dEp = cnt(ids.dustEpic)
        local dLg = cnt(ids.dustLeg)
        local dTi = cnt(ids.dustTit)
        local epToLg = math.floor(dEp / r1)
        local lgAfterCraft = dLg + epToLg
        local lgToTi = math.floor(lgAfterCraft / r2)
        local frost = cnt(ids.frostEmblem)
        local triumph = cnt(ids.triumphEmblem)
        local triToFrost = math.floor(triumph / 2)
        local frostFromEmblems = triToFrost
            + math.floor(cnt(45624) / 3)
            + math.floor(cnt(40753) / 3)
            + math.floor(cnt(40752) / 3)
        return {
            dustEpic = dEp,
            dustLeg = dLg,
            dustTit = dTi,
            titanBoxes = boxes,
            totalTitanInstant = dTi + boxes,
            epicToLeg = epToLg,
            epicRem = dEp % r1,
            legAfterCraft = lgAfterCraft,
            legToTit = lgToTi,
            legDirectToTit = math.floor(dLg / r2),
            legRem = lgAfterCraft % r2,
            craftableTit = lgToTi,
            totalTitPotential = dTi + boxes + lgToTi,
            rate1 = r1,
            rate2 = r2,
            bagumFeeCopper = fee,
            bagumTitCostCopper = (epToLg + lgToTi) * fee,
            bagumOpen = (bg.open == true),
            bagumDustEnabled = (bg.dustEn == true),
            frostEmblem = frost,
            triumphEmblem = triumph,
            triToFrost = triToFrost,
            frostFromLowerEmblems = frostFromEmblems,
            totalFrostPotential = frost + frostFromEmblems,
        }
    end

    function AP.EstimateItemRequiredXp(ilvl)
        ilvl = tonumber(ilvl) or 0
        if ilvl <= 0 then return 0 end
        return math.floor(0.24 * ilvl * ilvl + 0.5)
    end

    local GUILD_ATTUNE_PERKS = { [900063] = 5, [900061] = 10, [900064] = 25 }
    local GUILD_EXP_PERKS = { [900065] = 5, [900066] = 10, [900067] = 15, [900068] = 25 }

    local function ScanGuildPerkBonuses()
        if type(IsInGuild) == "function" and not IsInGuild() then
            return 0, 0, true
        end
        if type(IsInGuild) ~= "function" then
            return AP.guildAttuneBonusPct or 0, giftCache.guildExpPct or 0, (AP.guildAttuneBonusPct or 0) > 0
        end
        local gLvl = (type(GetGuildXP) == "function") and tonumber((GetGuildXP())) or nil
        local nPerks = (type(GetGuildNumPerks) == "function") and (tonumber(GetGuildNumPerks()) or 0) or 0
        if not gLvl or nPerks <= 0 or type(GetGuildPerks) ~= "function" then
            if (AP.guildAttuneBonusPct or 0) > 0 then
                return AP.guildAttuneBonusPct, giftCache.guildExpPct or 0, true
            end
            return 0, 0, false
        end
        local cacheKey = gLvl .. ":" .. nPerks
        if giftCache.guildBonusKey == cacheKey and giftCache.guildBonusPct ~= nil then
            return giftCache.guildBonusPct, giftCache.guildExpPct or 0, true
        end
        local bestAttune, bestExp = 0, 0
        local needTip = false
        for i = 1, nPerks do
            local sid, reqLvl = GetGuildPerks(i)
            if sid and (not reqLvl or gLvl >= reqLvl) then
                if GUILD_ATTUNE_PERKS[sid] then
                    if GUILD_ATTUNE_PERKS[sid] > bestAttune then bestAttune = GUILD_ATTUNE_PERKS[sid] end
                elseif GUILD_EXP_PERKS[sid] then
                    if GUILD_EXP_PERKS[sid] > bestExp then bestExp = GUILD_EXP_PERKS[sid] end
                else
                    needTip = true
                end
            end
        end
        if needTip and not (InCombatLockdown and InCombatLockdown()) and _G.AttuneParserScanTip then
            local tip = _G.AttuneParserScanTip
            for i = 1, nPerks do
                local sid, reqLvl = GetGuildPerks(i)
                if sid and (not reqLvl or gLvl >= reqLvl) and not GUILD_ATTUNE_PERKS[sid] and not GUILD_EXP_PERKS[sid] then
                    local spLink = (type(GetSpellLink) == "function" and GetSpellLink(sid)) or ("spell:" .. sid)
                    tip:SetOwner(UIParent, "ANCHOR_NONE")
                    tip:ClearLines()
                    local ok = pcall(tip.SetHyperlink, tip, spLink)
                    if ok then
                        for li = 1, (tip:NumLines() or 0) do
                            local fs = _G["AttuneParserScanTipTextLeft" .. li]
                            local txt = fs and fs:GetText()
                            if txt then
                                if txt:find("поглощ", 1, true) then
                                    local pct = tonumber(txt:match("(%d+)%%"))
                                    if pct and pct > bestAttune then bestAttune = pct end
                                elseif txt:find("Опытност", 1, true) or (txt:find("опыт", 1, true) and not txt:find("гильди", 1, true)) then
                                    local pct = tonumber(txt:match("(%d+)%%"))
                                    if pct and pct > bestExp then bestExp = pct end
                                end
                            end
                        end
                    end
                    tip:Hide()
                end
            end
        elseif needTip and (InCombatLockdown and InCombatLockdown()) then
            return AP.guildAttuneBonusPct or bestAttune, giftCache.guildExpPct or bestExp, false
        end
        giftCache.guildBonusKey = cacheKey
        giftCache.guildBonusPct = bestAttune
        giftCache.guildExpPct = bestExp
        if bestAttune > (AP.guildAttuneBonusPct or 0) then
            AP.guildAttuneBonusPct = bestAttune
        end
        return bestAttune, bestExp, true
    end

    local function ResolveGuildAttuneBonus()
        local gAtt, _, gKnown = ScanGuildPerkBonuses()
        if AP.mentorWhere and AP.mentorWhere.v2 then
            return AP.guildAttuneBonusPct or gAtt or 0, true
        end
        return gAtt, gKnown
    end

    function AP:GetParagonXPBreakdown()
        local gift = AP:GetActiveDailyGift(false)
        local eq = AP:GetEquippedAttuneProgress()
        local _, gExpPct, gKnown = ScanGuildPerkBonuses()
        local sd = rawget(_G, "serverData")
        local x2Sources = {}
        if gift.hasExpElixir then table.insert(x2Sources, "Эликсир двойного опыта") end
        if gift.isSunday then table.insert(x2Sources, "Дар Воскресенья") end
        if gift.hasExpHoliday then table.insert(x2Sources, "Праздник опыта") end
        if gift.hasNewbieBless then table.insert(x2Sources, "Благословение новичка") end
        local sdX2 = (type(sd) == "table" and tonumber(sd.x2) and tonumber(sd.x2) > 0) and true or false
        if #x2Sources == 0 and sdX2 then
            table.insert(x2Sources, tostring(sd.x2src or "Бонус x2"))
        end
        local hasX2 = (#x2Sources > 0) or sdX2
        local x2Mult = hasX2 and 2 or 1
        local perkPts = (type(sd) == "table" and type(sd.stats) == "table") and tonumber(sd.stats[19]) or nil
        local perkPct = perkPts and (perkPts * 0.5) or 0
        local mapXP = (type(sd) == "table" and tonumber(sd.mapXP)) or 100
        if mapXP <= 0 then mapXP = 100 end
        local mobMultBase = x2Mult * (1 + perkPct / 100) * (mapXP / 100)
        return {
            attuneMult = eq.xpMult or 1,
            attuneIsSaturday = eq.isSaturday == true,
            attuneHasElixir = eq.hasElixir == true,
            attuneGuildPct = eq.guildPct or 0,
            attuneGuildKnown = eq.guildKnown ~= false,
            paragonX2Active = hasX2,
            paragonX2Mult = x2Mult,
            paragonX2Source = x2Sources[1],
            paragonX2Sources = x2Sources,
            paragonX2Wasted = (#x2Sources > 1),
            paragonPerkPts = perkPts,
            paragonPerkPct = perkPct,
            paragonMapXP = mapXP,
            paragonMobMult = mobMultBase,
            guildExpPct = gExpPct or 0,
            guildExpKnown = gKnown,
            hasExpElixir = gift.hasExpElixir == true,
        }
    end

    function AP:GetEquippedAttuneProgress()
        local gift = AP:GetActiveDailyGift()
        local baseMult = (gift and gift.xpMult) or 1
        local guildPct, guildKnown = ResolveGuildAttuneBonus()
        local mult = baseMult * (1 + guildPct / 100)
        local list = {}
        local maxXpLeft, totalXpLeft = 0, 0
        for slot = 1, 19 do
            local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
            if link then
                local eid = AP.ExtractItemId(link)
                if eid and AP:CanHeroAbsorb(eid, link) then
                    local st = AP:GetItemServerStatus(eid, link)
                    if not st.isCompleted and st.ipTier ~= nil and (st.ipNeed or 0) > 0 then
                        local left = math.max(0, (st.ipNeed or 0) - (st.ipXp or 0))
                        if left > 0 then
                            local nm, _, _, ilvl = GetItemInfo(link)
                            totalXpLeft = totalXpLeft + left
                            if left > maxXpLeft then maxXpLeft = left end
                            table.insert(list, {
                                slot = slot,
                                itemId = eid,
                                name = nm or ("Предмет #" .. eid),
                                ilvl = ilvl or 0,
                                ipTier = st.ipTier,
                                ipXp = st.ipXp or 0,
                                ipNeed = st.ipNeed or 0,
                                xpLeft = left,
                                pct = math.floor(((st.ipXp or 0) / st.ipNeed) * 100 + 0.5),
                            })
                        end
                    end
                end
            end
        end
        table.sort(list, function(a, b) return a.xpLeft < b.xpLeft end)
        return {
            items = list,
            count = #list,
            xpMult = mult,
            guildPct = guildPct,
            guildKnown = guildKnown,
            worldLocked80 = AP.worldLocked80 or false,
            isSaturday = gift and gift.isSaturday or false,
            hasElixir = gift and gift.hasElixir or false,
            hasExpElixir = gift and gift.hasExpElixir or false,
            maxXpLeft = maxXpLeft,
            questsToFinishAllNormal = (maxXpLeft > 0) and math.max(1, math.ceil(maxXpLeft / (100 * mult))) or 0,
            questsToFinishAllDungeon = (maxXpLeft > 0) and math.max(1, math.ceil(maxXpLeft / (350 * mult))) or 0,
        }
    end

    function AP:GetMilestonesSummary()
        local ms = AP.serverMilestones or {}
        local done = rawget(_G, "CustomAttuneAbsorbedCount") or (AP.serverSummary and AP.serverSummary.doneBase) or 0
        local nextM = nil
        for _, m in ipairs(ms.list or {}) do
            if m.state == 0 and (m.need or 0) > done then
                if (not nextM) or m.need < nextM.need then
                    nextM = m
                end
            end
        end
        return {
            loaded = ms.loaded == true,
            claimable = ms.claimable or 0,
            done = done,
            nextNeed = nextM and nextM.need or nil,
            nextRemain = nextM and math.max(0, nextM.need - done) or nil,
            nextMilestone = nextM,
            totalMilestones = ms.count or #(ms.list or {}),
        }
    end

    function AP:GetAbsorbedAccountStats()
        local getFn = rawget(_G, "CustomAttuneGetStats")
        if type(getFn) == "function" then
            local ok, statsTotal, statsCount, statOrder, statNameFn = pcall(getFn)
            if ok then
                return {
                    loaded = (_G.ATC_StatsLoaded == true),
                    statsTotal = statsTotal or {},
                    statsCount = statsCount or 0,
                    statOrder = statOrder or AP.STAT_ORDER,
                    statNameFn = statNameFn,
                    summary = AP.serverSummary,
                }
            end
        end
        return {
            loaded = (_G.ATC_StatsLoaded == true),
            statsTotal = {},
            statsCount = rawget(_G, "CustomAttuneAbsorbedCount") or 0,
            statOrder = AP.STAT_ORDER,
            summary = AP.serverSummary,
        }
    end

    function AP:GetAccountCatalogSummary()
        local s = AP.serverSummary
        local mw = AP.mentorWhere
        local doneBase = (s and s.doneBase) or (mw and mw.heroCat) or rawget(_G, "CustomAttuneAbsorbedCount") or 0
        local totalBase = (s and s.totalBase) or (mw and mw.catalog) or 0
        local pctBase = (totalBase > 0) and math.floor((doneBase / totalBase) * 100 + 0.5) or 0
        return {
            loaded = (s ~= nil),
            doneBase = doneBase,
            totalBase = totalBase,
            pctBase = pctBase,
            acc = (s and s.acc) or doneBase,
            hero = (s and s.hero) or doneBase,
            v2 = (s and s.v2) == true,
        }
    end

    function AP:GetParagonInfo()
        local sd = rawget(_G, "serverData")
        local p = AP.paragon or {}
        local mw = AP.mentorWhere
        local lvl, cur, mx = p.level or 0, p.curXP or 0, p.maxXP or 0
        local loaded = (p.loaded == true) or (mw ~= nil)
        if type(sd) == "table" and ((tonumber(sd.level) or 0) > 0 or (tonumber(sd.expMax) or 0) > 0) then
            lvl = tonumber(sd.level) or lvl
            cur = tonumber(sd.experience) or cur
            mx = tonumber(sd.expMax) or mx
            loaded = true
        end
        return {
            loaded = loaded,
            level = lvl,
            curXP = cur,
            maxXP = mx,
            pct = (mx > 0) and math.floor((cur / mx) * 100 + 0.5) or 0,
            guildPct = AP.guildAttuneBonusPct or 0,
            worldLocked80 = AP.worldLocked80 or false,
            extraKind = (mw and mw.extraKind) or 1,
        }
    end

    function AP:GetPlayerSpecInfo()
        local _, classFile = UnitClass("player")
        local pl = rawget(_G, "PrimeLegion")
        local grp = (type(GetActiveTalentGroup) == "function" and GetActiveTalentGroup()) or 1
        if pl and type(pl.IsActive) == "function" and pl.IsActive() then
            return {
                isCustomLegion = true,
                classFile = classFile or "",
                spec = pl.spec,
                specName = tostring(pl.spec or classFile or "Legion"),
                activeGroup = grp,
            }
        end
        local bestName, bestPts, bestIdx = nil, -1, 0
        if type(GetTalentTabInfo) == "function" then
            for tab = 1, 3 do
                local ok, tName, _, pts = pcall(GetTalentTabInfo, tab, false, false, grp)
                if ok and tName and (tonumber(pts) or 0) > bestPts then
                    bestPts = tonumber(pts) or 0
                    bestName = tName
                    bestIdx = tab
                end
            end
        end
        return {
            isCustomLegion = false,
            classFile = classFile or "",
            spec = bestIdx,
            specName = bestName or (classFile or ""),
            points = math.max(0, bestPts),
            activeGroup = grp,
        }
    end

    function AP:GetInspectTradeCandidates(ctx)
        local out = {}
        local function scanView(viewTbl, sourceTag, linkGetter)
            for slot, rec in pairs(viewTbl or {}) do
                local okLk, lk = pcall(linkGetter, slot)
                if okLk and lk then
                    local eid = AP.ExtractItemId(lk)
                    if eid and AP:CanHeroAbsorb(eid, lk) then
                        local info = AP:GetItemInfo(eid, lk)
                        local oTier = rec.tier or 0
                        if info and (not info.isCompleted) and (oTier > info.doneTier) then
                            local oPct = AP.TIER_PCT[oTier] or 20
                            info.viewCtx = sourceTag
                            info.slot = slot
                            info.link = lk
                            info.instanceTier = oTier
                            info.instanceTierName = AP.TIER_NAMES[oTier] or AP.TIER_NAMES[0]
                            info.gainNowPct = math.max(0, oPct - (info.curPct or 0))
                            info.gainNowStats = math.floor((info.coreStatsSum or 0) * (info.gainNowPct / 100) + 0.5)
                            info.canGainNow = true
                            table.insert(out, info)
                        end
                    end
                end
            end
        end
        if (not ctx or ctx == "TRADE") and type(GetTradeTargetItemLink) == "function" then
            scanView(AP.forgeViewTrade, "TRADE", function(sl) return GetTradeTargetItemLink(sl + 1) end)
        end
        if (not ctx or ctx == "TRADEP") and type(GetTradePlayerItemLink) == "function" then
            scanView(AP.forgeViewPlayerTrade, "TRADEP", function(sl) return GetTradePlayerItemLink(sl + 1) end)
        end
        if (not ctx or ctx == "INSPECT") and type(GetInventoryItemLink) == "function" then
            local unit = (_G.InspectFrame and _G.InspectFrame.unit) or "target"
            if UnitExists and UnitExists(unit) then
                scanView(AP.forgeViewInspect, "INSPECT", function(sl) return GetInventoryItemLink(unit, sl) end)
            end
        end
        table.sort(out, function(a, b) return (a.gainNowStats or 0) > (b.gainNowStats or 0) end)
        return out
    end
end

-- ============================================================================
-- Module 5: Server Packet Listeners, Safe Warmer & Slash Command (/ap)
-- ============================================================================
do
    local warmQueue = {}
    local warmZoneQueue = {}
    local warmZoneIdx = 1
    local warmActive = false
    local warmZoneActive = false
    local warmIdx = 1
    local warmAnyChanged = false
    local warmDriver = CreateFrame("Frame")
    warmDriver:Hide()
    warmDriver.acc = 0

    local function BuildWarmQueue()
        warmQueue = {}
        warmIdx = 1
        warmAnyChanged = false
        local items = AP.Data and AP.Data.Items
        local zones = AP.Data and AP.Data.Zones or {}
        if not items then return end
        local svStats = AttuneParserDB and AttuneParserDB.itemStats or {}
        for eid in pairs(items) do
            if not svStats[eid] then
                local rec = AP.ParseItemRecord(eid)
                local zMeta = (rec.primaryZone and rec.primaryZone > 0) and zones[rec.primaryZone] or nil
                local isInst = zMeta and zMeta.exp and zMeta.exp > 0
                if isInst and not rec.statsKnown and not rec.noAttune then
                    table.insert(warmQueue, eid)
                end
            end
        end
    end

    local function BuildWarmZoneQueue()
        warmZoneQueue = {}
        warmZoneIdx = 1
        local zones = AP.Data and AP.Data.Zones or {}
        local zi = AP.Data and AP.Data.ZoneItems or {}
        for zid, zMeta in pairs(zones) do
            if zMeta.exp and zMeta.exp > 0 and zi[zid] then
                table.insert(warmZoneQueue, { id = zid, isRaid = zMeta.isRaid and true or false, exp = zMeta.exp })
            end
        end
        table.sort(warmZoneQueue, function(a, b)
            if a.isRaid ~= b.isRaid then return a.isRaid end
            if a.exp ~= b.exp then return a.exp > b.exp end
            return a.id < b.id
        end)
    end

    warmDriver:SetScript("OnUpdate", function(self, elapsed)
        self.acc = self.acc + (elapsed or 0)

        -- Phase 1: pre-warm instance zone analyses gently 1 zone per tick (0.04s) while UI is closed
        if warmZoneActive then
            if self.acc < 0.04 then return end
            self.acc = 0
            if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
                return
            end
            if warmZoneIdx <= #warmZoneQueue then
                local z = warmZoneQueue[warmZoneIdx]
                warmZoneIdx = warmZoneIdx + 1
                AP:GetZoneAnalysis(z.id, { diffId = 1, isRaid = z.isRaid, exp = z.exp, scope = "hero" })
                return
            else
                warmZoneActive = false
                if not warmActive then
                    self:Hide()
                end
                return
            end
        end

        if self.acc < 0.30 then return end
        self.acc = 0

        if not warmActive or warmIdx > #warmQueue then
            warmActive = false
            self:Hide()
            if warmAnyChanged then
                warmAnyChanged = false
                AP:InvalidateCaches(true)
            end
            AP:Fire("SCAN_COMPLETE", #warmQueue)
            return
        end

        -- Guard against 32-bit #134 crashes: pause strictly in combat or instances
        if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
            return
        end
        if IsInInstance and select(1, IsInInstance()) then
            return
        end

        local processed = 0
        AttuneParserDB = AttuneParserDB or {}
        AttuneParserDB.itemStats = AttuneParserDB.itemStats or {}

        while warmIdx <= #warmQueue and processed < 6 do
            local eid = warmQueue[warmIdx]
            warmIdx = warmIdx + 1
            processed = processed + 1

            local name = GetItemInfo(eid)
            if name then
                local ext = AP.ExtractLiveStatsAndMeta(eid, nil)
                if ext then
                    AttuneParserDB.itemStats[eid] = ext
                    AP._mem.itemMetaCache[eid] = nil
                    if AP._mem.absorbCache then AP._mem.absorbCache()[eid] = nil end
                    warmAnyChanged = true
                end
            else
                -- Touch SetHyperlink only gently outside instances for uncached instance items
                local tip = _G.AttuneParserScanTip
                if tip then
                    tip:SetOwner(UIParent, "ANCHOR_NONE")
                    tip:ClearLines()
                    pcall(function() tip:SetHyperlink("item:" .. eid) end)
                    tip:Hide()
                end
            end
        end

        if warmIdx > #warmQueue and warmAnyChanged then
            warmAnyChanged = false
            AP:InvalidateCaches(true)
            AP:Fire("SCAN_PROGRESS", #warmQueue, #warmQueue)
        end
    end)

    function AP:StartZonePrewarm()
        if #warmZoneQueue == 0 then BuildWarmZoneQueue() end
        if #warmZoneQueue == 0 then return 0 end
        warmZoneActive = true
        warmDriver:Show()
        return #warmZoneQueue
    end

    function AP:WarmItemStatsFromCache(eid)
        eid = AP.ExtractItemId(eid)
        if not eid then return false end
        if InCombatLockdown and InCombatLockdown() then return false end
        local name = GetItemInfo(eid)
        if not name then return false end
        local ext = AP.ExtractLiveStatsAndMeta(eid, nil)
        if not ext then return false end
        AttuneParserDB = AttuneParserDB or {}
        AttuneParserDB.itemStats = AttuneParserDB.itemStats or {}
        AttuneParserDB.itemStats[eid] = ext
        AP._mem.itemMetaCache[eid] = nil
        if AP._mem.absorbCache then AP._mem.absorbCache()[eid] = nil end
        AP:InvalidateItemStatus(eid)
        return true
    end

    function AP:StartBackgroundScan()
        if #warmQueue == 0 or warmIdx > #warmQueue then BuildWarmQueue() end
        if #warmQueue == 0 then return 0 end
        warmActive = true
        warmDriver:Show()
        return #warmQueue
    end

    function AP:StopBackgroundScan()
        warmActive = false
        warmDriver:Hide()
    end

    function AP:GetScanProgress()
        return warmActive, math.max(0, warmIdx - 1), #warmQueue
    end

    -- Server packet queue for throttled zone, item & spawn queries
    local srvReqQueue = {}
    local zoneRequested = {}
    local itemRequested = {}
    local spawnRequested = {}
    local creatureRequested = {}
    local milestoneTmp = nil
    local questQueriedOnce = false
    local lastSyncTs = 0
    local zoneReqFrame = CreateFrame("Frame")
    zoneReqFrame:Hide()
    zoneReqFrame.acc = 0
    zoneReqFrame.wait = 0.35
    zoneReqFrame:SetScript("OnUpdate", function(self, elapsed)
        self.acc = self.acc + (elapsed or 0)
        if self.acc < (self.wait or 0.35) then return end
        self.acc = 0
        if #srvReqQueue == 0 then self.wait = 0.35; self:Hide(); return end
        if InCombatLockdown and InCombatLockdown() then return end
        local req = table.remove(srvReqQueue, 1)
        if req and type(SendServerMessage) == "function" then
            pcall(SendServerMessage, req.p, req.b)
            self.wait = (req.p == "ACMSG_ATM_CLAIM") and 1.75 or 0.35
        end
    end)

    function AP:ClaimMilestone(id)
        id = tonumber(id)
        if not id or type(SendServerMessage) ~= "function" then return false end
        if InCombatLockdown and InCombatLockdown() then return false end
        table.insert(srvReqQueue, { p = "ACMSG_ATM_CLAIM", b = tostring(id) })
        zoneReqFrame:Show()
        return true
    end

    function AP:ClaimAllMilestones()
        if type(SendServerMessage) ~= "function" then return 0 end
        local queued = 0
        for _, m in ipairs((AP.serverMilestones and AP.serverMilestones.list) or {}) do
            if m.state == 1 and m.id then
                table.insert(srvReqQueue, { p = "ACMSG_ATM_CLAIM", b = tostring(m.id) })
                queued = queued + 1
            end
        end
        if queued > 0 then zoneReqFrame:Show() end
        return queued
    end

    function AP:RequestZoneSync(zoneId, force)
        if not zoneId or type(SendServerMessage) ~= "function" then return end
        if not force and zoneRequested[zoneId] then return end
        zoneRequested[zoneId] = true
        table.insert(srvReqQueue, { p = "ACMSG_ATC_ZONE", b = tostring(zoneId) })
        zoneReqFrame:Show()
    end

    function AP:QueuePriorityZonesSync(zoneIds, force)
        if type(zoneIds) ~= "table" or type(SendServerMessage) ~= "function" then return 0 end
        local queued = 0
        for _, zid in ipairs(zoneIds) do
            if zid and zid > 0 and (force or not zoneRequested[zid]) then
                zoneRequested[zid] = true
                table.insert(srvReqQueue, { p = "ACMSG_ATC_ZONE", b = tostring(zid) })
                queued = queued + 1
            end
        end
        if queued > 0 then zoneReqFrame:Show() end
        return queued
    end

    function AP:RequestItemSources(itemId, force)
        local eid = AP.ExtractItemId(itemId)
        if not eid or type(SendServerMessage) ~= "function" then return end
        if not force and itemRequested[eid] then return end
        itemRequested[eid] = true
        table.insert(srvReqQueue, { p = "ACMSG_ATC_ITEM", b = tostring(eid) })
        zoneReqFrame:Show()
    end

    function AP:RequestNpcSpawns(cid, force)
        cid = tonumber(cid)
        if not cid or cid <= 0 or type(SendServerMessage) ~= "function" then return end
        if not force and spawnRequested[cid] then return end
        spawnRequested[cid] = true
        table.insert(srvReqQueue, { p = "ACMSG_ATC_SPAWNS", b = tostring(cid) })
        zoneReqFrame:Show()
    end

    function AP:WarmCreatureCache(idOrList)
        if type(SendServerMessage) ~= "function" then return end
        local parts = {}
        if type(idOrList) == "table" then
            for _, id in ipairs(idOrList) do
                id = tonumber(id)
                if id and id > 0 and not creatureRequested[id] then
                    creatureRequested[id] = true
                    table.insert(parts, tostring(id))
                    if #parts >= 60 then break end
                end
            end
        else
            local id = tonumber(idOrList)
            if id and id > 0 and not creatureRequested[id] then
                creatureRequested[id] = true
                table.insert(parts, tostring(id))
            end
        end
        if #parts > 0 then
            table.insert(srvReqQueue, { p = "ACMSG_ATC_CACHE", b = table.concat(parts, ";") })
            zoneReqFrame:Show()
        end
    end

    function AP:RequestServerSync(force)
        if type(SendServerMessage) ~= "function" then return end
        local now = GetTime()
        if not force and (now - lastSyncTs) < 8 then return end
        if InCombatLockdown and InCombatLockdown() then return end
        lastSyncTs = now
        pcall(SendServerMessage, "ACMSG_ATC_SUMMARY")
        pcall(SendServerMessage, "ACMSG_ATC_ZONES")
        pcall(SendServerMessage, "ACMSG_ATM_LIST")
        pcall(SendServerMessage, "ACMSG_FORGE_SYNC")
        if not _G.ATC_StatsLoaded or _G.ATC_StatsDirty then
            pcall(SendServerMessage, "ACMSG_ATTUNE_STATS_REQUEST")
        end
        if force then
            pcall(SendServerMessage, "ACMSG_ATTUNE_SYNC")
            pcall(SendServerMessage, "ACMSG_AS_REQ")
            pcall(SendServerMessage, "ACMSG_AAMASK_REQ")
            pcall(SendServerMessage, "ACMSG_AAQUAL_REQ")
            pcall(SendServerMessage, "ACMSG_AABOE_REQ")
            pcall(SendServerMessage, "ACMSG_FORGE_GSYNC")
            if type(QueryQuestsCompleted) == "function" then
                pcall(QueryQuestsCompleted)
            end
            if type(SendAddonMessage) == "function" then
                local me = UnitName and UnitName("player")
                if me and me ~= "" then
                    pcall(SendAddonMessage, "ACMSG_PETLOOT", "state", "WHISPER", me)
                end
            end
        end
    end

    local function SendPetLootCmd(cmd)
        if not cmd or type(SendAddonMessage) ~= "function" then return false end
        local me = UnitName and UnitName("player")
        if not me or me == "" then return false end
        return pcall(SendAddonMessage, "ACMSG_PETLOOT", tostring(cmd), "WHISPER", me)
    end

    function AP:CanPetLootSplit()
        local s = AP.petLootState or {}
        return (s.proto or 0) >= 7 and (s.dspHas or 0) == 1
    end

    function AP:CanPetLootJunk()
        local s = AP.petLootState or {}
        return (s.proto or 0) >= 10 and (s.dspHas or 0) == 1
    end

    function AP:RequestPetLootState()
        return SendPetLootCmd("state")
    end

    function AP:TakePetLootItem(dbId, count)
        dbId = tonumber(dbId)
        if not dbId then return false end
        if count and tonumber(count) and tonumber(count) > 1 then
            return SendPetLootCmd("take:" .. dbId .. ":" .. tonumber(count))
        end
        return SendPetLootCmd("take:" .. dbId)
    end

    function AP:SplitPetLootItem(dbId)
        dbId = tonumber(dbId)
        if not dbId or not AP:CanPetLootSplit() then return false end
        return SendPetLootCmd("split:" .. dbId)
    end

    function AP:ScanPetLootJunk(cat)
        if not AP:CanPetLootJunk() then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[AttuneParser]|r Массовое расщепление хлама доступно с профессией 'Расщепление эссенций' (навык 10; откройте Сборщик хотя бы раз).")
            return false
        end
        AP.petLootJunk = AP.petLootJunk or {}
        AP.petLootJunk.askPending = true
        return SendPetLootCmd("junkscan:" .. tostring(tonumber(cat) or 0))
    end

    function AP:RunPetLootJunk(cat)
        if not AP:CanPetLootJunk() then return false end
        return SendPetLootCmd("junkgo:" .. tostring(tonumber(cat) or 0))
    end

    function AP:StopPetLootJunk()
        return SendPetLootCmd("junkstop")
    end

    function AP:SetAutoAbsorb(on)
        if type(SendServerMessage) ~= "function" then return false end
        AP.autoSwap.on = on and true or false
        pcall(SendServerMessage, on and "ACMSG_AUTOABSORB_ON" or "ACMSG_AUTOABSORB_OFF")
        AP:Fire("AUTOSWAP_UPDATED", "LOCAL")
        return true
    end

    function AP:SetAutoAbsorbBoE(allow)
        if type(SendServerMessage) ~= "function" then return false end
        AP.autoSwap.boeAllowed = allow and true or false
        pcall(SendServerMessage, "ACMSG_AABOE_SET", allow and "1" or "0")
        AP:Fire("AUTOSWAP_UPDATED", "LOCAL")
        return true
    end

    function AP:SetAutoAbsorbOrder(worst)
        if type(SendServerMessage) ~= "function" then return false end
        AP.autoSwap.orderWorst = worst and true or false
        pcall(SendServerMessage, "ACMSG_AAORDER_SET", worst and "1" or "0")
        AP:Fire("AUTOSWAP_UPDATED", "LOCAL")
        return true
    end

    function AP:SetAutoSellActive(on)
        if type(SendServerMessage) ~= "function" or not (AP.autoSwap and AP.autoSwap.unlocked) then return false end
        AP.autoSwap.active = on and true or false
        pcall(SendServerMessage, "ACMSG_AS_ACTIVE_SET", on and "1" or "0")
        AP:Fire("AUTOSWAP_UPDATED", "LOCAL")
        return true
    end

    function AP:SweepAbsorbedNow(confirmManual)
        if type(SendServerMessage) ~= "function" then return false end
        if not (AP.autoSwap and AP.autoSwap.unlocked) then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[AttuneParser]|r Автопродажа поглощенных не разблокирована на аккаунте.")
            return false
        end
        pcall(SendServerMessage, "ACMSG_AS_SWEEP", confirmManual and "1" or "0")
        return true
    end

    function AP:ToggleItemBlacklist(itemId, tier)
        local eid = AP.ExtractItemId(itemId)
        tier = tonumber(tier) or 0
        if not eid or type(SendServerMessage) ~= "function" then return false end
        if not (AP.autoSwap and AP.autoSwap.unlocked) then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[AttuneParser]|r Черный список доступен после разблокировки автопродажи.")
            return false
        end
        if AP:IsItemBlacklisted(eid, tier) then
            pcall(SendServerMessage, "ACMSG_AS_BL_DEL", eid .. " " .. tier)
        else
            pcall(SendServerMessage, "ACMSG_AS_BL_ADD", eid .. " " .. tier)
        end
        return true
    end

    function AP:SyncGuildBankForge()
        if type(SendServerMessage) ~= "function" then return false end
        return pcall(SendServerMessage, "ACMSG_FORGE_GSYNC")
    end

    function AP:ExchangeBagum(dir, kind, qty)
        if type(SendServerMessage) ~= "function" then return false end
        if not (AP.bagum and AP.bagum.open) then return false end
        dir = tonumber(dir) or 0
        kind = tonumber(kind) or 0
        qty = math.max(1, tonumber(qty) or 1)
        pcall(SendServerMessage, "ACMSG_BAGUM_EXCHANGE", string.format("%d %d %d", dir, kind, qty))
        AP.After(0.25, function()
            if AP.bagum and AP.bagum.open and type(SendServerMessage) == "function" then
                pcall(SendServerMessage, "ACMSG_BAGUM_OPEN", "")
            end
        end, "ap_bagum_ref")
        return true
    end

    local function BuildPetLootJunkText(v)
        local n = v[2] or 0
        local parts = {}
        if (v[3] or 0) > 0 then table.insert(parts, "уже поглощено - " .. v[3]) end
        if (v[4] or 0) > 0 then table.insert(parts, "не на ваш класс - " .. v[4]) end
        if (v[5] or 0) > 0 then table.insert(parts, "нельзя поглотить - " .. v[5]) end
        local t = "Расщепить ненужное в хранилище сборщика?\n\nБудет расщеплено: |cffffffff" .. n .. "|r предм."
        if #parts > 0 then t = t .. "\n(" .. table.concat(parts, ", ") .. ")." end
        if n > 250 then t = t .. "\nЗа один запуск максимум 250 шт." end
        local skip = {}
        if (v[7] or 0) > 0 then table.insert(skip, "нужное/эпик - " .. v[7]) end
        if (v[6] or 0) > 0 then table.insert(skip, "мало навыка - " .. v[6]) end
        if #skip > 0 then t = t .. "\n\nНе тронет: " .. table.concat(skip, "; ") .. "." end
        return t .. "\n\nПредметы пропадут безвозвратно, взамен - эссенции."
    end

    local function FlushDebouncedZone(topId, rawZid)
        AP:Fire("ZONE_UPDATED", topId, rawZid)
    end

    local function OnAddonMessage(prefix, msg)
        if type(msg) ~= "string" then return end
        if prefix == "ASMSG_ATTUNE_TIERS" then
            for _, rec in ipairs({ strsplit(";", msg) }) do
                local t, p = strsplit(":", rec)
                t = tonumber(t)
                p = tonumber(p)
                if t and p and t >= 0 and t <= 3 then
                    AP.TIER_PCT[t] = p
                    AP.TIER_SOURCE = "server"
                end
            end
            AP:InvalidateCaches(true)
            AP:Fire("ATTUNE_UPDATED", prefix)
        elseif prefix == "ASMSG_ATTUNE_STATS" or prefix == "ASMSG_ATTUNE_GAINED" or prefix == "ASMSG_ATTUNE_LIST" then
            AP:InvalidateCaches(true)
            AP:Fire("ATTUNE_UPDATED", prefix)
            if prefix == "ASMSG_ATTUNE_GAINED" and type(SendServerMessage) == "function" then
                AP.After(3.0, function()
                    if not (InCombatLockdown and InCombatLockdown()) then
                        pcall(SendServerMessage, "ACMSG_ATM_LIST")
                    end
                end, "ap_rew_after_gain")
            end
        elseif prefix == "ASMSG_FORGE_MAP" then
            AP.forgeEquip = {}
            AP.forgeBag = {}
            AP.forgeByEntry = {}
            AP.forgeMapLoaded = true
            for _, rec in ipairs({ strsplit(";", msg) }) do
                if rec ~= "" then
                    local a, b, c, d = strsplit(":", rec)
                    if a == "E" then
                        local slot, tier = tonumber(b), tonumber(c)
                        if slot and tier then
                            AP.forgeEquip[slot] = tier
                            local lk = GetInventoryItemLink and GetInventoryItemLink("player", slot)
                            local eid = lk and AP.ExtractItemId(lk)
                            if eid then AP.forgeByEntry[eid] = tier end
                        end
                    elseif a == "B" then
                        local bg, slot, tier = tonumber(b), tonumber(c), tonumber(d)
                        if bg and slot and tier then
                            AP.forgeBag[bg] = AP.forgeBag[bg] or {}
                            AP.forgeBag[bg][slot] = tier
                            local lk = GetContainerItemLink and GetContainerItemLink(bg, slot)
                            local eid = lk and AP.ExtractItemId(lk)
                            if eid then AP.forgeByEntry[eid] = tier end
                        end
                    end
                end
            end
            AP:InvalidateItemStatus()
            AP:InvalidateZoneCache(nil)
            AP:Fire("FORGE_UPDATED", prefix)
        elseif prefix == "ASMSG_FORGE_GMAP" then
            local clearFlag, payload = strsplit("\t", msg, 2)
            if clearFlag ~= "1" and clearFlag ~= "0" then
                payload = msg
                clearFlag = "1"
            end
            if clearFlag == "1" then AP.forgeGuild = {} end
            if payload and payload ~= "" then
                for _, rec in ipairs({ strsplit(";", payload) }) do
                    local a, tab, slot, tier = strsplit(":", rec)
                    if a == "G" then
                        tab, slot, tier = tonumber(tab), tonumber(slot), tonumber(tier)
                        if tab and slot and tier then
                            AP.forgeGuild[tab] = AP.forgeGuild[tab] or {}
                            AP.forgeGuild[tab][slot] = tier
                        end
                    end
                end
            end
            AP:InvalidateItemStatus()
            AP:InvalidateZoneCache(nil)
            AP:Fire("FORGE_UPDATED", prefix)
        elseif prefix == "ASMSG_FORGE_NEW" then
            local tier, entry = strsplit("|", msg)
            tier, entry = tonumber(tier), tonumber(entry)
            if entry and tier then
                AP.forgeByEntry[entry] = tier
                AP:InvalidateItemStatus(entry)
                AP:InvalidateZoneCache(nil)
                AP:Fire("FORGE_UPDATED", prefix, entry, tier)
            end
        elseif prefix == "ASMSG_AUCTION_FORGE" then
            AP.auctionForge = {}
            for rec in msg:gmatch("[^;]+") do
                local e, bo, c, t = rec:match("(%d+):(%d+):(%d+):(%d+)")
                if e then
                    AP.auctionForge[e .. ":" .. bo .. ":" .. c] = tonumber(t)
                end
            end
            AP:Fire("AUCTION_FORGE_UPDATED")
        elseif prefix == "ASMSG_ATM_LIST" then
            local cnt, first, payload = strsplit("\t", msg, 3)
            if first == "1" or not milestoneTmp then milestoneTmp = {} end
            if payload and payload ~= "" then
                for rec in payload:gmatch("[^;]+") do
                    local id, need, st, el, ep, lg, ti, t2 = strsplit(":", rec)
                    id = tonumber(id)
                    if id then
                        table.insert(milestoneTmp, {
                            id = id,
                            need = tonumber(need) or 0,
                            state = tonumber(st) or 0,
                            elixir = tonumber(el) or 0,
                            epic = tonumber(ep) or 0,
                            leg = tonumber(lg) or 0,
                            tit = tonumber(ti) or 0,
                            tier2 = (t2 == "1"),
                        })
                    end
                end
            end
            local claimable = 0
            for _, m in ipairs(milestoneTmp) do
                if m.state == 1 then claimable = claimable + 1 end
            end
            AP.serverMilestones = {
                loaded = true,
                count = tonumber(cnt) or #milestoneTmp,
                list = milestoneTmp,
                claimable = claimable,
            }
            AP:Fire("MILESTONES_UPDATED", AP.serverMilestones)
        elseif prefix == "ASMSG_ATM_RESULT" then
            local code, id, mail = strsplit("\t", msg)
            local cNum = tonumber(code)
            local idNum = tonumber(id)
            if cNum == 0 and idNum then
                local needVal = nil
                for _, m in ipairs(AP.serverMilestones.list or {}) do
                    if m.id == idNum then
                        m.state = 2
                        needVal = m.need
                    end
                end
                local c = 0
                for _, m in ipairs(AP.serverMilestones.list or {}) do
                    if m.state == 1 then c = c + 1 end
                end
                AP.serverMilestones.claimable = c
                AP:Fire("MILESTONES_UPDATED", AP.serverMilestones)
                DEFAULT_CHAT_FRAME:AddMessage("|cff40ff40[AttuneParser]|r Награда за веху (" .. tostring(needVal or idNum) .. " предм.) получена!" .. (mail == "mail" and " Остаток отправлен на почту." or ""))
            elseif cNum and cNum > 0 then
                local errMap = { [1] = "такой вехи нет", [2] = "недостаточно поглощенных вещей", [3] = "награда уже получена", [4] = "слишком частый запрос", [5] = "веха пройдена до запуска наград" }
                DEFAULT_CHAT_FRAME:AddMessage("|cffff8040[AttuneParser]|r Веха: " .. (errMap[cNum] or ("ошибка #" .. cNum)))
            end
        elseif prefix == "ASMSG_ATC_SUMMARY" then
            local a, c, d, e, v = strsplit(":", msg)
            AP.serverSummary = {
                doneBase = tonumber(a) or 0,
                totalBase = tonumber(c) or 0,
                acc = tonumber(d) or 0,
                hero = tonumber(e) or 0,
                v2 = (v == "2"),
            }
            AP:Fire("ATTUNE_UPDATED", prefix)
        elseif prefix == "ASMSG_ATC_ZONES" then
            local clear, payload = strsplit("\t", msg, 2)
            if clear == "1" then AP.serverZones = {} end
            if payload and payload ~= "" then
                for rec in payload:gmatch("([^;]+)") do
                    local id, rem, tot, nm = strsplit(":", rec, 4)
                    local zid = tonumber(id)
                    if zid then
                        AP.serverZones[zid] = {
                            id = zid,
                            remain = tonumber(rem) or 0,
                            total = tonumber(tot) or 0,
                            name = nm or "",
                        }
                    end
                end
            end
            AP:InvalidateZoneCache(nil)
            AP:Fire("ATTUNE_UPDATED", prefix)
        elseif prefix == "ASMSG_ATC_ZONE" then
            local zidStr, clear, payload = strsplit("\t", msg, 3)
            local rawZid = tonumber(zidStr)
            if not rawZid then return end
            local topMap = AP.Data and AP.Data.TopMap or {}
            local topId = topMap[rawZid] or rawZid
            if clear == "1" or not AP.serverZoneItems[topId] then
                AP.serverZoneItems[topId] = AP.serverZoneItems[topId] or {}
            end
            local bucket = AP.serverZoneItems[topId]
            if payload and payload ~= "" then
                for rec in payload:gmatch("([^;]+)") do
                    local e, q, sl, st, ab, md, pc = rec:match("^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)")
                    local sfx = 0
                    if not e then
                        local e2, s2, q2, sl2, st2, md2, pc2 = rec:match("^(%d+):([-%d]+):(%d+):(%d+):(%d+):(%d+):(%d+)")
                        if e2 then
                            e, sfx, q, sl, st, md, pc = e2, tonumber(s2) or 0, q2, sl2, st2, md2, pc2
                            ab = ((tonumber(pc2) or 0) >= 100) and "1" or "0"
                        end
                    end
                    local eid = tonumber(e)
                    if eid and eid > 0 then
                        local isAbsItem = (tonumber(ab) == 1) or ((tonumber(pc) or 0) >= 100)
                        bucket[eid] = {
                            quality = tonumber(q) or 0,
                            slot = tonumber(sl) or 0,
                            srcType = tonumber(st) or 1,
                            absorbed = isAbsItem,
                            modeMask = tonumber(md) or 0,
                            pct = tonumber(pc) or 0,
                            suffix = sfx,
                        }
                        if isAbsItem and not AP.serverAbsorbedItems[eid] then
                            AP.serverAbsorbedItems[eid] = true
                            AP:InvalidateItemStatus(eid)
                        end
                    end
                end
            end
            AP:InvalidateZoneCache(topId)
            AP.After(0.08, function() FlushDebouncedZone(topId, rawZid) end, "ap_zone_upd_" .. topId)
        elseif prefix == "ASMSG_ATC_ITEM" then
            local entryStr, clear, payload = strsplit("\t", msg, 3)
            local eid = tonumber(entryStr)
            if not eid then return end
            local srcs = (clear == "1") and {} or (AP.serverItemSources[eid] or {})
            if payload and payload ~= "" then
                for rec in payload:gmatch("[^;]+") do
                    local st, smp, z, mp, cnt, zn, sn, disp, ch, sp, sx, sy = strsplit(":", rec, 12)
                    table.insert(srcs, {
                        st = tonumber(st) or 0,
                        smp = tonumber(smp) or 0,
                        z = tonumber(z) or 0,
                        mp = tonumber(mp) or 0,
                        cnt = tonumber(cnt) or 0,
                        zn = zn or "",
                        sn = sn or "",
                        disp = tonumber(disp) or 0,
                        chance = tonumber(ch) or 0,
                        spawns = tonumber(sp) or 0,
                        sx = tonumber(sx) or 0,
                        sy = tonumber(sy) or 0,
                    })
                end
            end
            AP.serverItemSources[eid] = srcs
            AP._mem.sourceCache[eid] = nil
            AP._mem.heavyQuestCache()[eid] = nil
            AP:Fire("ITEM_SOURCES_UPDATED", eid)
        elseif prefix == "ASMSG_ATC_SPAWNS" then
            local cidStr, clear, payload = strsplit("\t", msg, 3)
            local cid = tonumber(cidStr)
            if not cid then return end
            local pts = (clear == "1") and {} or (AP.serverSpawns[cid] or {})
            if payload and payload ~= "" then
                for rec in payload:gmatch("[^;]+") do
                    local mp, z, x, y = strsplit(":", rec, 4)
                    table.insert(pts, {
                        map = tonumber(mp) or 0,
                        zone = tonumber(z) or 0,
                        x = tonumber(x) or 0,
                        y = tonumber(y) or 0,
                    })
                end
            end
            AP.serverSpawns[cid] = pts
            AP:Fire("SPAWNS_UPDATED", cid)
        elseif prefix == "ASMSG_XITEM" then
            local v = { strsplit("\t", msg) }
            local eid = tonumber(v[1])
            if eid then
                AP.xItemCache[eid] = {
                    tonumber(v[2]) or 0, tonumber(v[3]) or 0,
                    tonumber(v[4]) or 0, tonumber(v[5]) or 0, tonumber(v[6]) or 0,
                }
            end
        elseif prefix == "ASMSG_PETLOOT_STATE" then
            local v = {}
            for x in (msg .. ":"):gmatch("([^:]*):") do v[#v + 1] = tonumber(x) end
            if #v >= 15 then
                local rev = v[21] or 0
                local cnt = v[9] or 0
                if (AP.petLootState and AP.petLootState.rev ~= rev) or cnt == 0 then
                    AP.petLootItems = {}
                end
                AP.petLootState = {
                    balance = v[1] or 0,
                    vendor = v[6] or 0,
                    rev = rev,
                    count = cnt,
                    total = cnt,
                    proto = v[20] or 0,
                    sellMask = v[22] or 7,
                    flags = v[23] or 0,
                    dspHas = v[28] or 0,
                    dspSkill = v[29] or 0,
                    loaded = true,
                }
                AP:Fire("PETLOOT_UPDATED", prefix)
            end
        elseif prefix == "ASMSG_PETLOOT_ITEMS" then
            local v = {}
            for x in (msg .. ":"):gmatch("([^:]*):") do v[#v + 1] = tonumber(x) end
            if v[1] and v[2] and v[3] then
                AP.petLootState.page = v[1]
                AP.petLootState.pages = math.max(1, v[2])
                AP.petLootState.total = v[3]
                if v[3] == 0 then AP.petLootItems = {} end
                AP:Fire("PETLOOT_UPDATED", prefix)
            end
        elseif prefix == "ASMSG_PETLOOT_ITEM" then
            local v = {}
            for x in (msg .. ":"):gmatch("([^:]*):") do v[#v + 1] = tonumber(x) end
            local row, dbId, itemId = v[1], v[2], v[3]
            if row and dbId and itemId then
                AP.petLootItems[dbId] = {
                    dbId = dbId,
                    itemId = itemId,
                    count = v[4] or 1,
                    forgeTier = v[5] or 0,
                    absBP = v[6] or 0,
                    done = v[7] or 0,
                    sfx = v[8] or 0,
                    dspReq = v[9] or 0,
                }
                AP.After(0.08, function() AP:Fire("PETLOOT_UPDATED", "ASMSG_PETLOOT_ITEM") end, "ap_petloot_upd")
            end
        elseif prefix == "ASMSG_DSP_RES" then
            local f = { strsplit("\t", msg) }
            local sk = tonumber(f[7])
            if sk and AP.petLootState then
                AP.petLootState.dspSkill = sk
                AP:Fire("PETLOOT_UPDATED", prefix)
            end
        elseif prefix == "ASMSG_PETLOOT_JUNK" then
            local v = {}
            for x in (msg .. ":"):gmatch("([^:]*):") do v[#v + 1] = tonumber(x) end
            local wasRun = AP.petLootJunk and AP.petLootJunk.running ~= nil
            local busy = v[10] == 1
            AP.petLootJunk = AP.petLootJunk or {}
            AP.petLootJunk.summary = v
            if busy then
                AP.petLootJunk.running = AP.petLootJunk.running or { 0, math.min(v[2] or 0, 250) }
            else
                AP.petLootJunk.running = nil
            end
            local ask = AP.petLootJunk.askPending
            AP.petLootJunk.askPending = false
            if ask and not busy then
                if v[9] ~= 1 then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[AttuneParser]|r Сборщик еще проверяет поглощение. Попробуйте через пару секунд.")
                elseif (v[2] or 0) == 0 then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r В хранилище сборщика нет ненужных вещей для расщепления.")
                elseif StaticPopupDialogs and StaticPopup_Show then
                    StaticPopupDialogs["ATTUNEPARSER_PETLOOT_JUNK"] = {
                        text = BuildPetLootJunkText(v),
                        button1 = YES or "Да",
                        button2 = NO or "Нет",
                        timeout = 0,
                        whileDead = 1,
                        hideOnEscape = 1,
                        OnAccept = function()
                            AP:RunPetLootJunk(v[1] or 0)
                        end,
                    }
                    StaticPopup_Show("ATTUNEPARSER_PETLOOT_JUNK")
                end
            elseif wasRun and not busy then
                local rem = v[2] or 0
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff40ff40[AttuneParser]|r Расщепление ненужного завершено. Осталось подходящего: %d.", rem))
            end
            AP:Fire("PETLOOT_JUNK_UPDATED", v)
        elseif prefix == "ASMSG_DSP_PROG" then
            local tag, done, asked = msg:match("^([^\t]*)\t(%d+)\t(%d+)")
            if tag == "junk" then
                AP.petLootJunk = AP.petLootJunk or {}
                AP.petLootJunk.running = { tonumber(done) or 0, tonumber(asked) or 0 }
                AP:Fire("PETLOOT_JUNK_UPDATED", AP.petLootJunk.running)
            end
        elseif prefix == "ASMSG_AUTOABSORB" then
            AP.autoSwap.on = (tonumber(msg:match("(%-?%d+)")) == 1)
            AP:Fire("AUTOSWAP_UPDATED", prefix)
        elseif prefix == "ASMSG_AAMASK" then
            local m = tonumber(msg:match("(%d+)"))
            if m then
                AP.autoSwap.groupMask = m
                AP:Fire("AUTOSWAP_UPDATED", prefix)
            end
        elseif prefix == "ASMSG_AAQUAL" then
            local q = tonumber(msg:match("(%d+)"))
            if q then
                AP.autoSwap.qualMask = q
                AP:Fire("AUTOSWAP_UPDATED", prefix)
            end
        elseif prefix == "ASMSG_AAORDER" then
            local oo = tonumber(msg:match("(%d+)"))
            if oo ~= nil then
                AP.autoSwap.orderWorst = (oo == 1)
                AP:Fire("AUTOSWAP_UPDATED", prefix)
            end
        elseif prefix == "ASMSG_AABOE" then
            local bb = tonumber(msg:match("(%d+)"))
            if bb ~= nil then
                AP.autoSwap.boeAllowed = (bb == 1)
                AP:Fire("AUTOSWAP_UPDATED", prefix)
            end
        elseif prefix == "ASMSG_AS_STATE" then
            local u, q, sm, cf, ac = msg:match("(%d+) (%d+) (%d+) (%d+) (%d+)")
            if u then
                AP.autoSwap.unlocked = (tonumber(u) or 0) ~= 0
                AP.autoSwap.sellMask = tonumber(q) or 0
                AP.autoSwap.srcMask = tonumber(sm) or 2
                AP.autoSwap.confirm = (tonumber(cf) or 1) ~= 0
                AP.autoSwap.active = (tonumber(ac) or 0) ~= 0
                AP:Fire("AUTOSWAP_UPDATED", prefix)
            end
        elseif prefix == "ASMSG_AS_BL" then
            AP.autoSwap.blacklist = {}
            AP.autoSwap.blacklistByEntry = {}
            for tok in msg:gmatch("[^,]+") do
                local _e, _t = tok:match("(%d+):(%d+)")
                local eid = tonumber(_e)
                local tier = tonumber(_t) or 0
                if eid then
                    AP.autoSwap.blacklist[eid .. ":" .. tier] = true
                    AP.autoSwap.blacklistByEntry[eid] = true
                end
            end
            AP:Fire("AUTOSWAP_UPDATED", prefix)
        elseif prefix == "ASMSG_FORGE_VIEW" then
            local ctx, payload = strsplit("\t", msg, 2)
            local tbl = (ctx == "TRADE") and AP.forgeViewTrade
                or (ctx == "TRADEP") and AP.forgeViewPlayerTrade
                or (ctx == "INSPECT") and AP.forgeViewInspect
                or nil
            if tbl then
                for k in pairs(tbl) do tbl[k] = nil end
                if payload and payload ~= "" then
                    for rec in payload:gmatch("[^;]+") do
                        local sl, tier, at, bp = strsplit(":", rec)
                        sl = tonumber(sl)
                        if sl then
                            tbl[sl] = { tier = tonumber(tier) or 0, at = tonumber(at) or 0, pct = tonumber(bp) or 0 }
                        end
                    end
                end
                AP:Fire("FORGE_VIEW_UPDATED", ctx)
            end
        elseif prefix == "ASMSG_PARAGON_DATA_RESPONSE" then
            local t = {}
            for k, v in msg:gmatch("([^:;]+):([^;]*)") do t[k] = v end
            if t.level ~= nil then
                AP.paragon = {
                    level = tonumber(t.level) or 0,
                    curXP = tonumber(t.experience) or 0,
                    maxXP = tonumber(t.expMax) or 0,
                    loaded = true,
                }
                AP:Fire("PARAGON_UPDATED", AP.paragon)
            end
        elseif prefix == "ASMSG_PARAGON_XP" then
            local e, r, l = strsplit("\t", msg)
            local lv, ex, mx = tonumber(l), tonumber(e), tonumber(r)
            if lv and ex and mx then
                AP.paragon = {
                    level = lv,
                    curXP = ex,
                    maxXP = mx,
                    loaded = true,
                }
                AP:Fire("PARAGON_UPDATED", AP.paragon)
            end
        elseif prefix == "ASMSG_NECK_INFO" then
            local lvl, cur, mx = msg:match("(%d+):(%d+):(%d+)")
            local sd = rawget(_G, "serverData")
            local hasRealParagon = type(sd) == "table" and ((tonumber(sd.level) or 0) > 0 or (tonumber(sd.expMax) or 0) > 0)
            if lvl and not hasRealParagon then
                local nl = tonumber(lvl) or 0
                if nl > 0 or not (AP.paragon and AP.paragon.loaded and (AP.paragon.level or 0) > 0) then
                    AP.paragon = {
                        level = nl,
                        curXP = tonumber(cur) or 0,
                        maxXP = tonumber(mx) or 0,
                        loaded = true,
                    }
                    AP:Fire("PARAGON_UPDATED", AP.paragon)
                end
            end
        elseif prefix == "ASMSG_LILY_WHERE" then
            local f = { strsplit("\t", msg) }
            if tonumber(f[1]) and tonumber(f[2]) and tonumber(f[3]) then
                local w = {
                    equip = tonumber(f[1]) or 0,
                    full = tonumber(f[2]) or 0,
                    avg = math.floor((tonumber(f[3]) or 0) + 0.5),
                    extra = tonumber(f[4]) or 0,
                }
                if f[5] == "w2" then
                    w.v2 = true
                    w.worldLocked = (tonumber(f[12]) or 0) ~= 0
                    local b = {}
                    for x in (f[18] or ""):gmatch("%d+") do table.insert(b, tonumber(x) or 0) end
                    w.gift = b[1] or 0
                    w.elixir = b[2] or 0
                    w.guildPct = b[3] or 0
                    w.extraKind = tonumber(f[19]) or 1
                    w.heroCat = tonumber(f[20])
                    w.catalog = tonumber(f[21])
                    AP.guildAttuneBonusPct = w.guildPct
                    AP.worldLocked80 = w.worldLocked
                end
                AP.mentorWhere = w
                AP:Fire("PARAGON_UPDATED", AP.paragon)
            end
        elseif prefix == "ASMSG_BAGUM_OPEN" then
            local a, b, c, d, f, tk, tc, tb, tl, de, x17, x18, x19, r1, r2, rv1, rv2, fee = strsplit("\t", msg)
            AP.bagum = {
                open = true,
                c = { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0, tonumber(d) or 0 },
                frost = tonumber(f) or 0,
                tok = tonumber(tk) or 0,
                tcost = tonumber(tc) or 8,
                tback = tonumber(tb) or 6,
                tleft = tonumber(tl) or 0,
                dustEn = (tonumber(de) == 1),
                d = { tonumber(x17) or 0, tonumber(x18) or 0, tonumber(x19) or 0 },
                r1 = tonumber(r1) or 3,
                r2 = tonumber(r2) or 3,
                rev1 = tonumber(rv1) or 3,
                rev2 = tonumber(rv2) or 3,
                fee = tonumber(fee) or 1000000,
            }
            AP:Fire("BAGUM_UPDATED", true)
        elseif prefix == "ASMSG_BAGUM_CLOSE" then
            AP.bagum = AP.bagum or {}
            AP.bagum.open = false
            AP:Fire("BAGUM_UPDATED", false)
        end
    end

    local evFrame = CreateFrame("Frame")
    evFrame:RegisterEvent("ADDON_LOADED")
    evFrame:RegisterEvent("PLAYER_LOGIN")
    evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    evFrame:RegisterEvent("CHAT_MSG_ADDON")
    evFrame:RegisterEvent("QUEST_QUERY_COMPLETE")
    evFrame:RegisterEvent("UNIT_AURA")
    evFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
    evFrame:RegisterEvent("COMPANION_LEARNED")
    evFrame:RegisterEvent("COMPANION_UPDATE")
    evFrame:RegisterEvent("GUILDBANKFRAME_OPENED")
    evFrame:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
    evFrame:SetScript("OnEvent", function(_, event, a1, a2, _, a4)
        if event == "ADDON_LOADED" and a1 == "AttuneParser" then
            AttuneParserDB = AttuneParserDB or {}
            AttuneParserDB.itemStats = AttuneParserDB.itemStats or {}
            AttuneParserDB.seenSuffixes = AttuneParserDB.seenSuffixes or {}
            AttuneParserDB.lastKnownTier = AttuneParserDB.lastKnownTier or {}
            AP:EnsureSettings()
        elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            AP:EnsureSettings()
            if type(RequestRaidInfo) == "function" then pcall(RequestRaidInfo) end
            AP.After(2.0, function()
                AP:GetActiveDailyGift(true)
                AP:RequestServerSync(false)
                AP:StartZonePrewarm()
            end, "ap_login_sync")
            if not questQueriedOnce then
                AP.After(3.2, function()
                    if not questQueriedOnce and not (InCombatLockdown and InCombatLockdown()) and type(QueryQuestsCompleted) == "function" then
                        questQueriedOnce = true
                        pcall(QueryQuestsCompleted)
                    end
                end, "ap_quest_sync")
            end
            AP.After(6.0, function()
                if AP:GetSetting("autoWarmStats") ~= false then
                    AP:StartBackgroundScan()
                end
            end, "ap_bg_stats_scan")
        elseif event == "UPDATE_INSTANCE_INFO" then
            AP._mem.normZoneLookup = nil
            AP:Fire("ATTUNE_UPDATED", "UPDATE_INSTANCE_INFO")
        elseif event == "COMPANION_LEARNED" or event == "COMPANION_UPDATE" then
            AP.After(0.4, function()
                AP:Fire("TALORIAN_BRIDGE_UPDATED", AP._talorianBridge)
            end, "ap_comp_upd")
        elseif event == "GUILDBANKFRAME_OPENED" or event == "GUILDBANKBAGSLOTS_CHANGED" then
            AP.After(0.25, function()
                AP:SyncGuildBankForge()
                AP:Fire("ATTUNE_UPDATED", event)
            end, "ap_gbank_sync")
        elseif event == "QUEST_QUERY_COMPLETE" then
            if type(GetQuestsCompleted) == "function" then
                AP.questCompleted = {}
                pcall(GetQuestsCompleted, AP.questCompleted)
            end
            AP._mem.sourceCache = {}
            AP:InvalidateZoneCache(nil)
            AP:Fire("ATTUNE_UPDATED", "QUEST_QUERY_COMPLETE")
        elseif event == "UNIT_AURA" and a1 == "player" then
            AP.After(0.25, function()
                local prevKey = AP.activeGift and AP.activeGift.key
                local prevElix = AP.activeGift and AP.activeGift.hasElixir
                local g = AP:GetActiveDailyGift(true)
                if g.key ~= prevKey or g.hasElixir ~= prevElix then
                    AP:Fire("DAILY_GIFT_UPDATED", g)
                end
            end, "ap_unit_aura")
        elseif event == "CHAT_MSG_ADDON" then
            local me = UnitName("player")
            if a4 == me then
                OnAddonMessage(a1, a2)
            end
        end
    end)

    SLASH_ATTUNEPARSER1 = "/ap"
    SLASH_ATTUNEPARSER2 = "/attuneparser"
    SlashCmdList["ATTUNEPARSER"] = function(msg)
        local rawMsg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
        msg = AP.Norm(rawMsg)
        local bi = AP.Data and AP.Data.BuildInfo or {}
        if msg == "" or msg == "ui" or msg == "gui" or msg == "show" then
            if type(AP.ToggleUI) == "function" then
                AP:ToggleUI("top")
                return
            end
        elseif msg == "top" or msg == "summary" or msg == "bags" or msg == "sets" or msg == "settings" or msg == "server" then
            if type(AP.OpenUI) == "function" then
                AP:OpenUI(msg)
                return
            end
        elseif msg == "blocks" or msg == "setup" or msg == "wizard" or msg == "master" then
            if type(AP.ShowOnboardingWizard) == "function" then
                AP:ShowOnboardingWizard(true)
                return
            end
        elseif msg == "config" or msg == "opt" or msg == "options" then
            if type(AP.OpenUI) == "function" then
                AP:OpenUI("settings")
                return
            end
        elseif msg == "minimap" then
            local nw = not AP:GetSetting("showMinimap")
            AP:SetSetting("showMinimap", nw)
            DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Кнопка у миникарты: " .. (nw and "ВКЛ" or "ВЫКЛ"))
            return
        elseif msg == "auc" then
            local nw = not AP:GetSetting("showAuctionUI")
            AP:SetSetting("showAuctionUI", nw)
            DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Панель аукциона: " .. (nw and "ВКЛ" or "ВЫКЛ"))
            return
        elseif msg == "aucreset" then
            AP:ResetAuctionPos()
            DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Позиция кнопки у аукциона сброшена.")
            return
        elseif msg == "aucdebug" then
            if type(AP.DebugAuction) == "function" then
                AP:DebugAuction()
            end
            return
        elseif msg == "ejdebug" then
            if type(AP.DebugEJ) == "function" then
                AP:DebugEJ()
            end
            return
        elseif msg:sub(1, 2) == "ej" or msg:sub(1, 7) == "journal" then
            local q = rawMsg:gsub("^%S+%s*", "")
            if type(AP.OpenEncounterJournal) == "function" then
                AP:OpenEncounterJournal(q ~= "" and q or nil)
            end
            return
        end
        if msg == "" or msg == "status" then
            local active, done, tot = AP:GetScanProgress()
            local acct = AP:GetAbsorbedAccountStats()
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cff38bdf8[AttuneParser]|r v%s | База: %d предм. | Тиры: %d%%/%d%%/%d%%/%d%% (%s) | Поглощено: %d | Скан: %s (%d/%d)",
                AP.VERSION, bi.items or 0,
                AP.TIER_PCT[0], AP.TIER_PCT[1], AP.TIER_PCT[2], AP.TIER_PCT[3], AP.TIER_SOURCE,
                acct.statsCount or 0, active and "идет" or "пауза/готов", done, tot
            ))
        elseif msg == "rec" or msg == "new" then
            local list = AP:GetRecommendations({ mode = "new", onlyInstances = true, limit = 8 })
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[AttuneParser] Топ инстов (Новые вещи):|r")
            for i, z in ipairs(list) do
                DEFAULT_CHAT_FRAME:AddMessage(string.format(
                    "  #%d |cffffffff%s|r: |cff40ff40+%d новых|r (+%d статов, макс +%d), Ковка: %d",
                    i, z.zoneName, z.newCount, z.newImmediateStats, z.newMaxStats, z.forgeCount
                ))
            end
        elseif msg == "topforge" then
            local list = AP:GetRecommendations({ mode = "forge", onlyInstances = true, limit = 8 })
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[AttuneParser] Топ инстов (Ковка до Титанического 90%%):|r")
            for i, z in ipairs(list) do
                DEFAULT_CHAT_FRAME:AddMessage(string.format(
                    "  #%d |cffffffff%s|r: |cffffd200%d на ковку|r (осталось +%d статов)",
                    i, z.zoneName, z.forgeCount, z.forgeRemainStats
                ))
            end
        elseif msg == "noreq" then
            local nr = AP:GetNoReqLevelItems()
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cffffd200[AttuneParser] Предметы без требуемого ур. (req<=1):|r Новые=%d, Ковка=%d, Титаник=%d",
                #nr.newItems, #nr.forgeItems, nr.completedCount
            ))
            for i = 1, math.min(8, #nr.newItems) do
                local it = nr.newItems[i]
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cff40ff40[Новый]|r [%d] %s (ilvl %d, статы %d)", it.itemId, it.name, it.ilvl, it.coreStatsSum))
            end
        elseif msg == "scan" then
            AP:InvalidateCaches(false)
            local n = AP:StartBackgroundScan()
            DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Фоновый до-скан запущен (" .. n .. " предметов вне кэша).")
        elseif msg == "bagslist" or msg == "bags" then
            local rawCands = AP:GetOwnedUpgradeCandidates(nil, true)
            local cands = {}
            for _, it in ipairs(rawCands) do
                local isMk = (AP.IsMorKelItem and AP:IsMorKelItem(it.itemId)) or (AP.MORKEL_ITEMS and AP.MORKEL_ITEMS[it.itemId])
                if not isMk then table.insert(cands, it) end
            end
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffd200[AttuneParser] Ваши вещи для поглощения и ковки: %d|r", #cands))
            local wMap = {
                petloot = "Сборщик", itembank = "Банк вещей", bank = "Банк",
                guild = "Гильдбанк", equip = "Надетые", bag = "Сумка",
            }
            for i = 1, math.min(10, #cands) do
                local it = cands[i]
                local wLbl = wMap[it.where or "bag"] or "Сумка"
                local blTag = it.isBlacklisted and " |cffff6060[Черный список]|r" or ""
                if it.canGainNow then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("  [%s] %s (%s -> +%d%%, +%d статов)%s", wLbl, it.name, it.instanceTierName or "?", it.gainNowPct or 0, it.gainNowStats or 0, blTag))
                else
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("  [%s] %s (нужна ковка, до 90%%: +%d статов)%s", wLbl, it.name, it.remainStats or 0, blTag))
                end
            end
        elseif msg == "milestones" or msg == "ms" then
            local ms = AP:GetMilestonesSummary()
            if not ms.loaded then
                DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Вехи еще не загружены с сервера (/ap sync).")
            else
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff38bdf8[AttuneParser]|r Вехи: поглощено=%d, доступно наград=%d%s", ms.done or 0, ms.claimable or 0, ms.nextNeed and string.format(", след. веха на %d (ост. %d)", ms.nextNeed, ms.nextRemain) or ""))
            end
        elseif msg == "gift" or msg == "gifts" then
            local g = AP:GetActiveDailyGift(true)
            local st = AP:GetForgeMaterialStock()
            local eq = AP:GetEquippedAttuneProgress()
            if g.active then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff38bdf8[AttuneParser]|r %s (ост. %s)%s", g.name or "Дар", g.remText or "?", (g.desc and g.desc ~= "") and (" - " .. g.desc) or ""))
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Активный Дар недели на персонаже не найден.")
            end
            local guildChatStr = (eq.guildKnown == false) and "?" or string.format("+%d%%", eq.guildPct or 0)
            local px = AP:GetParagonXPBreakdown()
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  Пыль: Мерцающая=%d, Пылающая=%d, Астральная=%d (обмен %d:1/%d:1: Астральная +%d, Титан=%d) | Сундуки=%d | Поглощение x%s (Гильдия %s%s%s) | Paragon x%s (%s)",
                st.dustEpic, st.dustLeg, st.dustTit, st.rate1 or 3, st.rate2 or 3, st.craftableTit or 0, st.totalTitPotential or 0, st.titanBoxes,
                AP.FormatMult(eq.xpMult or 1), guildChatStr, g.isSaturday and ", Дар Субботы x2" or "", g.hasElixir and ", Эликс. погл. x2" or "",
                AP.FormatMult(px.paragonMobMult or 1), px.paragonX2Active and (px.paragonX2Source or "x2") or "база"))
        elseif msg == "info" or msg == "spec" then
            local cat = AP:GetAccountCatalogSummary()
            local par = AP:GetParagonInfo()
            local sp = AP:GetPlayerSpecInfo()
            local as = AP:GetAutoSwapSummary()
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff38bdf8[AttuneParser]|r Каталог: %d/%d (%d%%) | Аккаунт=%d, Герой=%d | Доп. уровень %d (%d/%d) | Спек: %s%s | Автопоглощение: %s (ЧС=%d)",
                cat.doneBase, cat.totalBase, cat.pctBase, cat.acc, cat.hero, par.level, par.curXP, par.maxXP,
                sp.specName or "?", sp.isCustomLegion and " [Legion]" or "",
                as.on and "ВКЛ" or (as.on == false and "ВЫКЛ" or "?"), as.blacklistCount or 0))
        elseif msg == "claim" then
            local n = AP:ClaimAllMilestones()
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff38bdf8[AttuneParser]|r Отправлено запросов на сбор вех: %d", n))
        elseif msg == "sync" then
            AP:RequestServerSync(true)
            DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Запрошена синхронизация с сервером.")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Команды: /ap (окно) | /ap bags (сумки) | /ap sets (сеты T9/T10) | /ap server (события) | /ap info | /ap gift | /ap sync | /ap ej (путеводитель) | /ap auc (аукцион)")
        end
    end
end
