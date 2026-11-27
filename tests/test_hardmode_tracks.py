import argparse
import os
import re
import lupa

AP_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TALORIAN_DIR = os.environ.get("TALORIAN_TP_DIR") or os.path.join(os.path.dirname(AP_ROOT), "TalorianTP")

def resolve_addon_path(rel):
    parts = rel.replace("\\", "/").split("/", 1)
    if parts[0] == "AttuneParser":
        return os.path.join(AP_ROOT, parts[1])
    if parts[0] == "TalorianTP":
        return os.path.join(TALORIAN_DIR, parts[1])
    return os.path.join(AP_ROOT, rel)

WOW_SHIM = r'''
unpack = table.unpack
table.getn = function(t) return #t end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strsplit(sep, str)
    local out = {}
    if type(str) ~= "string" then return "" end
    if sep == "" then return str end
    local pos = 1
    while true do
        local a, b = string.find(str, sep, pos, true)
        if not a then
            table.insert(out, string.sub(str, pos))
            break
        end
        table.insert(out, string.sub(str, pos, a - 1))
        pos = b + 1
    end
    return unpack(out)
end

bit = {
    band = function(a, b) return (a & b) end,
    bor  = function(a, b) return (a | b) end,
    bxor = function(a, b) return (a ~ b) end,
    lshift = function(a, n) return (a << n) end,
    rshift = function(a, n) return (a >> n) end,
}

_G._SENT_SRV = {}
_G._SENT_ADDON = {}
_G._MAC_CALLS = {}
_G._FRAMES = {}
_G._REGIONS = {}
_G._TIME = 100.0
_G._IN_COMBAT = false
_G._MONEY = 25000 * 10000
_G._TARGET_GUID = "0xF130001234000001"
_G._FOCUS_GUID  = "0xF130005678000002"
_G._TARGET_EXISTS = true
_G._FOCUS_EXISTS = true

function GetTime() return _G._TIME end
function time() return math.floor(_G._TIME + 1700000000) end
function UnitName(u)
    if u == "player" then return "TestHero" end
    if u == "target" then return "TestBoss" end
    if u == "focus" then return "FocusMob" end
    return "Unknown"
end
function UnitLevel() return 80 end
function UnitClass() return "Воин", "WARRIOR" end
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "Человек", "Human" end
function UnitGUID(u)
    if u == "player" then return "0x00000000000ABCDE" end
    if u == "target" then return _G._TARGET_GUID end
    if u == "focus" then return _G._FOCUS_GUID end
    return nil
end
function UnitExists(u)
    if u == "target" then return _G._TARGET_EXISTS end
    if u == "focus" then return _G._FOCUS_EXISTS end
    return u == "player"
end
function GetRealmName() return "Hardmode" end
function InCombatLockdown() return _G._IN_COMBAT end
function UnitAffectingCombat() return _G._IN_COMBAT end
function UnitIsDeadOrGhost() return false end
function CursorHasItem() return false end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function GetInventorySlotInfo(inv)
    local m = { HeadSlot=1, NeckSlot=2, ShoulderSlot=3, ChestSlot=5, WaistSlot=6, LegsSlot=7, FeetSlot=8, WristSlot=9, HandsSlot=10, Finger0Slot=11, Finger1Slot=12, Trinket0Slot=13, Trinket1Slot=14, BackSlot=15, MainHandSlot=16, SecondaryHandSlot=17, RangedSlot=18 }
    return m[inv]
end
function GetMoney() return _G._MONEY end
function GetCVar() return "1" end
function SetDungeonDifficulty(d) _G._DUNGEON_DIFF = d; return true end
function PlaySound() end
function GetGameTime() return 14, 30 end
function GetNumCompanions() return 1 end
function GetCompanionInfo(kind, idx)
    -- Simulate renamed Talorian companion using spellID 91200
    if kind == "CRITTER" and idx == 1 then
        return 500031, "МойСпутник", 91200, "Interface\\Icons\\Spell_Arcane_TeleportMoonglade", 1
    end
    return nil
end
function GetNumSavedInstances() return 0 end
function GetInventoryItemLink() return nil end
function GetContainerNumSlots() return 0 end
function GetItemCount() return 0 end
function hooksecurefunc(tbl, name, hookFn)
    if type(tbl) == "string" then
        hookFn = name
        name = tbl
        tbl = _G
    end
    if type(tbl) ~= "table" or type(name) ~= "string" or type(hookFn) ~= "function" then return end
    local orig = tbl[name]
    if type(orig) ~= "function" then return end
    tbl[name] = function(...)
        local r1, r2, r3, r4 = orig(...)
        hookFn(...)
        return r1, r2, r3, r4
    end
end
function SpellIsTargeting() return false end
function GetActiveTalentGroup() return 1 end
function GetSpecName() return "Оружие" end
function RequestRaidInfo() end
function QueryQuestsCompleted() end
function GetQuestsCompleted() return {} end
function IsAltKeyDown() return false end
function IsControlKeyDown() return false end
function IsShiftKeyDown() return false end
function GetCursorPosition() return 500, 500 end
function GetNumMacros() return 0, 0 end
function GetMacroInfo() return nil end
function GetMacroIndexByName() return nil end
function CreateMacro() return 1 end
function GetCurrentBindingSet() return 1 end
function SetBinding() return true end
function SaveBindings() end
function GetItemInfo(x)
    local id = tonumber(tostring(x):match("(%d+)")) or 1
    return "Item_"..id, "item:"..id..":0:0:0:0:0:0", 4, 245, 80, "Доспехи", "Латы", 1, "INVTYPE_CHEST", "Interface\\Icons\\INV_Misc_QuestionMark"
end
function GetLocale() return "ruRU" end

function SendServerMessage(prefix, body)
    table.insert(_G._SENT_SRV, { prefix = prefix, body = body })
end
function SendAddonMessage(prefix, body, dist, target)
    table.insert(_G._SENT_ADDON, { prefix = prefix, body = body, dist = dist, target = target })
end

local function MakeRegion(kind, parent)
    local r = { _kind = kind, _parent = parent, _shown = true, _text = "" }
    function r:SetPoint() assert(self == r, "Attempt to find 'this' in non-table object (used '.' instead of ':' ?)") end
    function r:ClearAllPoints() end
    function r:SetAllPoints() end
    function r:SetSize() end
    function r:SetWidth() end
    function r:SetHeight() end
    function r:SetTexture(t) assert(self == r, "Attempt to find 'this' in non-table object"); self._tex = t end
    function r:GetTexture() return nil end
    function r:SetTexCoord() end
    function r:SetVertexColor() end
    function r:SetBlendMode() end
    function r:SetAlpha() end
    function r:SetText(t) assert(self == r, "Attempt to find 'this' in non-table object"); self._text = tostring(t or "") end
    function r:GetText() return self._text end
    function r:SetTextColor() end
    function r:SetFont() end
    function r:SetFontObject() end
    function r:GetFontObject() return "GameFontNormalSmall" end
    function r:GetStringWidth() return #self._text * 6 end
    function r:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
    function r:SetJustifyH() end
    function r:SetJustifyV() end
    function r:SetWordWrap() assert(self == r, "Attempt to find 'this' in non-table object (used '.' instead of ':' ?)") end
    function r:Show() assert(self == r, "Attempt to find 'this' in non-table object"); self._shown = true end
    function r:Hide() assert(self == r, "Attempt to find 'this' in non-table object"); self._shown = false end
    function r:IsShown() return self._shown end
    function r:GetObjectType() return self._kind end
    table.insert(_G._REGIONS, r)
    return r
end

function CreateFrame(ftype, name, parent, template)
    local f = {
        _ftype = ftype, _name = name, _parent = parent, _events = {}, _scripts = {}, _children = {},
        _shown = true, _attrs = {},
    }
    if name then _G[name] = f end
    function f:RegisterEvent(e) self._events[e] = true end
    function f:UnregisterEvent(e) self._events[e] = nil end
    function f:SetScript(ev, fn) self._scripts[ev] = fn end
    function f:HookScript(ev, fn)
        local prev = self._scripts[ev]
        self._scripts[ev] = function(...) if prev then prev(...) end return fn(...) end
    end
    function f:GetScript(ev) return self._scripts[ev] end
    function f:SetPoint() end
    function f:ClearAllPoints() end
    function f:SetAllPoints() end
    function f:SetSize(w, h) self._w = w; self._h = h end
    function f:SetWidth(w) self._w = w end
    function f:SetHeight(h) self._h = h end
    function f:GetWidth() return self._w or 800 end
    function f:GetHeight() return self._h or 600 end
    function f:SetFrameStrata(s) self._strata = s end
    function f:GetFrameStrata() return self._strata or "MEDIUM" end
    function f:SetFrameLevel() end
    function f:GetFrameLevel() return 1 end
    function f:SetToplevel() end
    function f:EnableMouse() end
    function f:EnableMouseWheel() end
    function f:SetMovable() end
    function f:RegisterForDrag() end
    function f:RegisterForClicks() end
    function f:SetClampedToScreen() end
    function f:SetBackdrop() end
    function f:SetBackdropColor() end
    function f:SetBackdropBorderColor(r, g, b, a) self._borderColor = { r, g, b, a } end
    function f:SetAttribute(k, v) self._attrs[k] = v end
    function f:GetAttribute(k) return self._attrs[k] end
    function f:Show()
        self._shown = true
        if self._scripts.OnShow then self._scripts.OnShow(self) end
    end
    function f:Hide()
        self._shown = false
        if self._scripts.OnHide then self._scripts.OnHide(self) end
    end
    function f:IsShown() return self._shown and 1 or nil end
    function f:IsVisible() return self._shown and 1 or nil end
    function f:SetAlpha() end
    function f:Raise()
        _G._RAISE_SEQ = (_G._RAISE_SEQ or 0) + 1
        self._raisedAt = _G._RAISE_SEQ
        _G._RAISE_LOG = _G._RAISE_LOG or {}
        table.insert(_G._RAISE_LOG, self._name or "<anon>")
    end
    function f:Enable() end
    function f:Disable() end
    function f:SetHighlightTexture() end
    function f:SetNormalTexture() end
    function f:SetPushedTexture() end
    function f:SetDisabledTexture() end
    function f:SetMotionScriptsWhileDisabled() end
    function f:GetCenter() return 100, 100 end
    function f:GetEffectiveScale() return 1 end
    function f:GetLeft() return 0 end
    function f:GetRight() return (self._w or 800) end
    function f:GetTop() return (self._h or 600) end
    function f:GetBottom() return 0 end
    function f:SetUserPlaced() end
    function f:SetMaxLetters() end
    function f:SetAutoFocus() end
    function f:SetTextInsets() end
    function f:SetNumeric() end
    function f:SetFontObject() end
    function f:GetFontObject() return "GameFontHighlightSmall" end
    function f:GetStringWidth() return #(self._text or "") * 6 end
    function f:SetFocus() self._focused = true end
    function f:ClearFocus() self._focused = false end
    function f:HasFocus() return self._focused == true end
    function f:SetChecked() end
    function f:GetChecked() return false end
    function f:SetScale() end
    function f:GetScale() return 1 end
    function f:StartMoving() end
    function f:StopMovingOrSizing() end
    function f:CreateTexture() return MakeRegion("Texture", self) end
    function f:CreateFontString() return MakeRegion("FontString", self) end
    function f:GetRegions() return {} end
    function f:SetOwner() end
    function f:ClearLines() end
    function f:AddLine() end
    function f:AddDoubleLine() end
    function f:SetText(t) self._text = tostring(t or "") end
    function f:GetText() return self._text or "" end
    function f:NumLines() return 0 end
    table.insert(_G._FRAMES, f)
    return f
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
Minimap = CreateFrame("Frame", "Minimap")
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
DEFAULT_CHAT_FRAME = { AddMessage = function(self, m) _G._LAST_CHAT = m end }
UISpecialFrames = {}
StaticPopupDialogs = {}
function StaticPopup_Show(k) _G._LAST_POPUP = k end
SlashCmdList = {}
function FauxScrollFrame_GetOffset() return 0 end
function FauxScrollFrame_Update() end

local _realMac = function(key, val)
    table.insert(_G._MAC_CALLS, { key = key, val = val })
    if key == "QNP" then
        if not val then return 100.0, 200.0, 50.0, 0.0 end
        return 110.0, 210.0, 50.0
    elseif key == "QNW" then
        return 0.55, 0.45, 14.1, 1, 0, 0, 1, 1
    end
    return nil
end
local _lordOther, _lordMine = "", "0xLOR:1.0,0.80,0.15"
function IsMacClient(key, val, ...)
    if key == "QNC" then
        _lordOther = val or ""
        local m = (_lordOther == "" and _lordMine) or (_lordOther .. ";" .. _lordMine)
        return _realMac("QNC", m)
    end
    return _realMac(key, val, ...)
end

function _G._FireEvent(ev, ...)
    for _, f in ipairs(_G._FRAMES) do
        if f._events[ev] and f._scripts.OnEvent then
            f._scripts.OnEvent(f, ev, ...)
        end
    end
end
function _G._TickAll(el)
    _G._TIME = _G._TIME + el
    for _, f in ipairs(_G._FRAMES) do
        if f:IsShown() and f._scripts.OnUpdate then
            f._scripts.OnUpdate(f, el)
        end
    end
end
'''

AP_CORE_SHIM = r'''
AttuneParserDB = AttuneParserDB or { settings = {} }
local AP = {
    VERSION = "1.1.3",
    _isShim = true,
    Data = { BuildInfo = { items = 18106 }, Zones = {}, TopMap = {}, Creatures = {} },
    TIER_PCT = { [0] = 20, [1] = 45, [2] = 75, [3] = 100 },
    TIER_NAMES = { [0] = "Обычный", [1] = "Эпический", [2] = "Легендарный", [3] = "Титанический" },
    FORGE_ITEM_IDS = { dustEpic = 70017, dustLeg = 70018, dustTit = 70019, titanBoxes = { 90636 }, frostEmblem = 49426, triumphEmblem = 47241 },
    autoSwap = { on = false, groupMask = 3, qualMask = 60, orderWorst = false, boeAllowed = false, unlocked = false, sellMask = 0, srcMask = 2, confirm = true, active = false, blacklist = {} },
    bagum = { open = false, dustEn = true, r1 = 3, r2 = 3, fee = 1000000 },
    forgeByEntry = {},
    paragon = { level = 0, curXP = 0, maxXP = 0, loaded = false },
    _cbs = {},
    DEFAULT_SETTINGS = { showMinimap = true, minimapAngle = 225, showPrimeHub = true, showAuctionUI = true, showEJOverlay = true, showEJBadges = true, tradeAlert = true, wedAuto = true, onlyUnlocked = false, excludeHeavyQuests = true, autoWarmStats = true, talorianMode = "auto", topMode = "new", scope = "hero", eraFilter = "All", kindFilter = "All", sortBy = "default", ejOverlaySide = "RIGHT", ejDocked = true, aucDocked = true, aucFrameOpen = true, ibAutoEquip = false, ibUseAAMask = false, ibEquipInCombat = true, ibAutoPut = false, ibAutoPutMode = "unabsorbed", ibPutKeepSets = true },
    forgeEquip = {},
    forgeBag = {},
}
_G.AttuneParser = AP

function AP:EnsureSettings() return AttuneParserDB.settings end
function AP:GetSettings() return AttuneParserDB.settings end
function AP:GetSetting(k)
    local v = AttuneParserDB.settings[k]
    if v == nil then return AP.DEFAULT_SETTINGS[k] end
    return v
end
function AP:SetSetting(k, v) AttuneParserDB.settings[k] = v; AP:Fire("SETTINGS_UPDATED", k, v); return v end
function AP:RegisterCallback(ev, fn) AP._cbs[ev] = AP._cbs[ev] or {}; table.insert(AP._cbs[ev], fn) end
function AP:Fire(ev, ...) for _, fn in ipairs(AP._cbs[ev] or {}) do pcall(fn, ev, ...) end end
function AP.After(sec, fn) pcall(fn) end
function AP.Norm(s) return string.lower(tostring(s or "")) end
function AP.ExtractItemId(l) return tonumber(tostring(l):match("(%d+)")) end
function AP:HasTalorianPet()
    local n = GetNumCompanions("CRITTER") or 0
    for i = 1, n do
        local _, cName, cSpell, _, active = GetCompanionInfo("CRITTER", i)
        if cSpell == 91200 or (cName and (cName:find("Талориан", 1, true) or cName:lower():find("talorian", 1, true))) then
            return true, (active == 1 or active == true), i
        end
    end
    return false, false, nil
end
function AP:RegisterTalorianBridge(b) AP._talorianBridge = b; AP:Fire("TALORIAN_BRIDGE_UPDATED", b) end
function AP:IsTalorianBridgeActive()
    if AP:GetSetting("talorianMode") == "off" then return false end
    local b = AP._talorianBridge
    if b and type(b.IsAvailable) == "function" then
        local ok, avail = pcall(b.IsAvailable)
        if ok then return avail == true end
    end
    local ttp = rawget(_G, "TalorianTP")
    if type(ttp) == "table" and (not _G.TalorianTP_DB or _G.TalorianTP_DB.enabled ~= false) then
        return AP:HasTalorianPet()
    end
    return false
end
function AP:CanHeroAbsorb() return true, true end
function AP:GetItemInfo(eid)
    local dt = -1
    if type(rawget(_G, "CustomAttuneProgress")) == "function" then
        local ok, d = pcall(_G.CustomAttuneProgress, eid, 0)
        if ok and type(d) == "number" then dt = d end
    end
    local curPct = (dt >= 0) and (AP.TIER_PCT[dt] or 0) or 0
    local remPct = math.max(0, 90 - curPct)
    return { itemId = eid, name = "Test Chest", quality = 4, ilvl = 245, doneTier = dt, curPct = curPct, remainStats = math.floor(500 * (remPct / 100) + 0.5), coreStatsSum = 500, isCompleted = (dt >= 3), needsForge = (dt >= 0 and dt < 3) }
end
function AP:IsItemBlacklisted(eid, tier)
    if not AP.blacklist or not eid then return false end
    if AP.blacklist[eid .. ":-1"] then return true end
    if tier ~= nil and AP.blacklist[eid .. ":" .. tostring(tier)] then return true end
    return false
end
function AP:RequestServerSync() end
function AP:RequestPetLootState() end
function AP:SyncGuildBankForge() end
function AP:CanPetLootJunk() return false end
function AP:GetAutoSwapSummary()
    return { on = AP.autoSwap.on, groupMask = AP.autoSwap.groupMask, qualMask = AP.autoSwap.qualMask, orderWorst = AP.autoSwap.orderWorst, boeAllowed = AP.autoSwap.boeAllowed, unlocked = AP.autoSwap.unlocked, sellMask = AP.autoSwap.sellMask, srcMask = AP.autoSwap.srcMask, confirm = AP.autoSwap.confirm, active = AP.autoSwap.active, blacklistCount = 0 }
end
function AP:SetAutoAbsorb(on) AP.autoSwap.on = on and true or false end
function AP:SetAutoAbsorbBoE(allow) AP.autoSwap.boeAllowed = allow and true or false end
function AP:SetAutoAbsorbOrder(worst) AP.autoSwap.orderWorst = worst and true or false end
function AP:SetAutoSellActive(on) AP.autoSwap.active = on and true or false end
function AP:SweepAbsorbedNow() end
function AP:GetForgeMaterialStock()
    return { dustEpic = 0, dustLeg = 0, dustTit = 0, titanBoxes = 0, totalTitanInstant = 0, epicToLeg = 0, epicRem = 0, legAfterCraft = 0, legToTit = 0, legDirectToTit = 0, legRem = 0, craftableTit = 0, totalTitPotential = 0, rate1 = 3, rate2 = 3, bagumFeeCopper = 1000000, bagumTitCostCopper = 0, bagumOpen = false, bagumDustEnabled = true, frostEmblem = 0, triumphEmblem = 0, triToFrost = 0, frostFromLowerEmblems = 0, totalFrostPotential = 0 }
end
function AP:GetOwnedUpgradeCandidates() return {} end
function AP:GetAccountCatalogSummary() return { doneBase = 100, totalBase = 1000, pctBase = 10, acc = 100, hero = 50 } end
function AP:GetMilestonesSummary() return { done = 100, claimable = 0, loaded = true } end
function AP:GetScanProgress() return false, 0, 0 end
function AP:GetActiveDailyGift() return { active = false } end
function AP:GetEquippedAttuneProgress() return { xpMult = 1, guildPct = 0, questsToFinishAllNormal = 0, questsToFinishAllDungeon = 0 } end
function AP:GetParagonInfo()
    local sd = rawget(_G, "serverData")
    local p = AP.paragon or {}
    local lvl, cur, mx = p.level or 0, p.curXP or 0, p.maxXP or 0
    if type(sd) == "table" and ((tonumber(sd.level) or 0) > 0 or (tonumber(sd.expMax) or 0) > 0) then
        lvl = tonumber(sd.level) or lvl; cur = tonumber(sd.experience) or cur; mx = tonumber(sd.expMax) or mx
    end
    return { loaded = (lvl > 0), level = lvl, curXP = cur, maxXP = mx, pct = (mx > 0) and math.floor((cur / mx) * 100 + 0.5) or 0 }
end
function AP:GetPlayerSpecInfo() return { specName = "Воздаяние" } end
function AP:GetAbsorbedAccountStats() return { statsTotal = {}, statOrder = {} } end
function AP:GetEraTopStats() return {} end
function AP:GetInstanceRecommendations() return {} end
function AP:GetRecommendations() return {}, 0, 0 end
function AP:GetNoReqLevelItems() return {}, 0, 0, 0 end
function AP:GetItemDiffTag() return "" end
function AP:IsZoneInstance() return false end
function AP:OpenTalorianUI()
    local b = AP._talorianBridge
    if b and type(b.OpenUI) == "function" then
        b.OpenUI()
        if type(AP.RaiseFrameFront) == "function" then
            AP.RaiseFrameFront(rawget(_G, "TalorianMainFrame"))
        end
        return true
    end
    return false
end
function AP:StartBackgroundScan() end
function AP:ClaimAllMilestones() return 0 end
function AP:InvalidateCaches() end
function AP:BuildItemTooltip() end
function AP:GetAvailableEras() return { "All" } end
function AP:GetZonesList() return {} end
function AP.FormatMult(m)
    m = tonumber(m) or 1
    local s = string.format("%.2f", m):gsub("0+$", ""):gsub("%.$", "")
    return s == "" and "1" or s
end
function AP:GetZoneIcon() return "Interface\\Icons\\INV_Misc_Map_01" end
function AP:GetParagonXPBreakdown()
    return {
        attuneMult = 1, attuneIsSaturday = false, attuneHasElixir = false, attuneGuildPct = 0, attuneGuildKnown = true,
        paragonX2Active = false, paragonX2Mult = 1, paragonX2Sources = {}, paragonX2Wasted = false,
        paragonPerkPts = nil, paragonPerkPct = 0, paragonMapXP = 100, paragonMobMult = 1, guildExpPct = 0, guildExpKnown = true,
    }
end
function AP:GetLockedZonesMap() return {} end
function AP:GetBagItemsStatus() return { readyToAbsorb = {}, completedItems = {}, newItems = {}, forgeItems = {} } end
SLASH_ATTUNEPARSER1 = "/ap"
SlashCmdList["ATTUNEPARSER"] = function() end
'''

def check_lua51_scopes(include_talorian=True):
    print("=== LUA 5.1 NESTED CHUNK LOCAL AUDIT ===")
    rels = [
        r"AttuneParser\AttuneParser.lua",
        r"AttuneParser\AttuneParser_UI.lua",
        r"AttuneParser\AttuneParser_Integrations.lua",
    ]
    if include_talorian:
        rels.append(r"TalorianTP\TalorianTP.lua")
    for rel in rels:
        p = resolve_addon_path(rel)
        lines = open(p, encoding="utf-8").read().splitlines()
        # Count max simultaneous locals visible at chunk level or inside top-level do..end blocks
        chunk_locals = 0
        do_depth = 0
        fn_depth = 0
        do_locals = []
        peak_chunk_regs = 0
        for l in lines:
            s = re.sub(r'--.*$', '', l).strip()
            if not s: continue
            if re.search(r'\bfunction\b', s) and not re.search(r'\bend\b', s):
                fn_depth += 1
            elif fn_depth == 0:
                if s == 'do' or s.startswith('do '):
                    do_depth += 1
                    do_locals.append(0)
                elif s == 'end':
                    if do_depth > 0:
                        do_depth -= 1
                        do_locals.pop()
                if s.startswith('local '):
                    decl = s[6:].split('=')[0]
                    n = 1 if decl.startswith('function') else len([x for x in decl.split(',') if x.strip()])
                    if do_depth == 0:
                        chunk_locals += n
                    else:
                        do_locals[-1] += n
                    cur = chunk_locals + sum(do_locals)
                    if cur > peak_chunk_regs:
                        peak_chunk_regs = cur
            else:
                if s == 'end' or s.startswith('end)') or s.startswith('end,'):
                    fn_depth = max(0, fn_depth - 1)
        print(f"  {rel}: file_chunk_locals={chunk_locals}, peak_chunk_registers~={peak_chunk_regs} (<200 OK)")

def run_tests():
    check_lua51_scopes()
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(WOW_SHIM)

    lua.execute(r'''
    -- Real Hardmode Paragon 405 data table!
    _G.serverData = { level = 405, experience = 4500000, expMax = 9000000, availablePoints = 3 }
    _G.C_Talent = {
        _active = 1,
        GetActiveTalentGroup = function() return _G.C_Talent._active end,
        GetSelectedCurrency = function() return 1 end,
        SetActiveTalentGroup = function(g) _G.C_Talent._active = g; SendServerMessage("ACMSG_ACTIVATE_SPEC", g .. ":-1") end,
    }
    _G.PearkProgress = {
        [101] = { currentRank = 1, maxRank = 1, active = true },
        [102] = { currentRank = 1, maxRank = 1, active = true },
        [103] = { currentRank = 1, maxRank = 1, active = false },
        [104] = { currentRank = 1, maxRank = 1, active = false },
    }
    _G.PRIME_SetForge = { activeTree = 0, branches = { [0] = { tree = 0, v2 = 12, v4 = 34, active = true } } }
    _G.PrimePepe = {
        cur = 1, mask = (1 << 1) + (1 << 7) + (1 << 10) + (1 << 15) + (1 << 17) + (1 << 18), sel = 0, slots = 3,
        Send = function(body) SendAddonMessage("ACMSG_PEPE", body, "WHISPER", "TestHero") end,
    }
    _G.PRIME_ItemBank = { items = { { guid = 9001, entry = 50001, suffix = 0, perm = 0, g1 = 0, g2 = 0, g3 = 0, forge = 2, tier = 0, flags = 17, added = 1, dsp = 0, link = "item:50001:0:0:0:0:0:0" } }, cap = 100 }
    _G.ResourceBank = { usedEntries = 3, maxEntries = 120, contents = { [70017] = 15, [70018] = 6, [70019] = 2 } }
    _G.PRIME_Disperse = { state = { srvSkill = 450, srvMax = 450, srvRank = 6 }, alertOn = true, shards = {} }
    _G.JOURNALENCOUNTER = { [990001] = { { 170100, "Лесной повелитель" } } }
    ''')

    lua.execute(AP_CORE_SHIM)

    # Load actual .toc files (in exact .toc order!)
    for rel in [
        r"AttuneParser\AttuneParser_Data.lua",
        r"AttuneParser\AttuneParser_UI.lua",
        r"AttuneParser\AttuneParser_Integrations.lua",
        r"TalorianTP\TalorianLootDB.lua",
        r"TalorianTP\TalorianTP.lua",
    ]:
        p = resolve_addon_path(rel)
        with open(p, "r", encoding="utf-8") as fh:
            lua.execute(fh.read())

    res = lua.execute(r'''
    local AP = AttuneParser
    local TTP = TalorianTP
    local SC = TTP.serverCtrl

    _G._FireEvent("ADDON_LOADED", "AttuneParser")
    _G._FireEvent("ADDON_LOADED", "TalorianTP")
    _G._FireEvent("PLAYER_LOGIN")

    -- Test 1: ResourceBank dust merged
    local stock = AP:GetForgeMaterialStock()
    assert(stock.rbDustEpic == 15 and stock.totalTitPotential == 5, "ResourceBank stock merge failed")

    -- Test 2: ItemBank candidate
    local cands = AP:GetOwnedUpgradeCandidates()
    local foundIB = false
    for _, c in ipairs(cands) do
        if c.where == "itembank" and c.itemId == 50001 and c.instanceTier == 2 and c.guid == 9001 then foundIB = true end
    end
    assert(foundIB, "ItemBank candidate missing")

    -- Test 3: WB CD + built-in 40 world boss name resolution + Disperse shards + Vault spoof protection
    do
        local _origJE_t3 = _G.JOURNALENCOUNTER
        _G.JOURNALENCOUNTER = nil
        for eid = 910060, 910099 do
            local bn = AP:GetWorldBossName(eid)
            assert(bn and not bn:find("#", 1, true), "WB name fell back to raw ID for " .. tostring(eid) .. ": " .. tostring(bn))
        end
        assert(AP:GetWorldBossName(910060) == "Хмуродроб Лютый", "WB 910060 mismatch")
        assert(AP:GetWorldBossName(910099) == "Один", "WB 910099 mismatch")
        assert(AP:GetWorldBossName(90075) == "Хелия", "WB alias 90075 mismatch")
        assert(AP:GetWorldBossName(911005) == "Слияние душ", "WB wave 911005 mismatch")
        AP.serverSync.wb.names = {}
        _G.JOURNALENCOUNTER = _origJE_t3
        _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_WB_CD", "1000\t1\t90060:1120;909999:1060", "UNKNOWN", "TestHero")
        assert(#AP:GetWorldBossList() == 2, "WB list failed")
        _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_WB_CD", "1000\t1\t910060:1120;910075:1250;909999:1060", "UNKNOWN", "TestHero")
        local wbDedup = AP:GetWorldBossList()
        assert(#wbDedup == 3, "WB 910060+910075+909999 dedup count failed: got " .. #wbDedup)
        for _, b in ipairs(wbDedup) do
            assert(b.name and not b.name:find("#", 1, true), "WB row leaked ID: " .. tostring(b.name))
        end
        _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_WV2_WBOSS", "0\t0\t0\t910066\t0\t0\t0\tКорстилакс (тест)", "UNKNOWN", "TestHero")
        assert(AP:GetWorldBossName(910066) == "Корстилакс (тест)", "ASMSG_WV2_WBOSS override failed")
        AP.serverSync.wb.names = {}
        _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_WB_CD", "1000\t1\t90060:1120;909999:1060", "UNKNOWN", "TestHero")
    end
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_DSP_SHARD", "0xAABBCC\t2\t1", "UNKNOWN", "TestHero")
    assert(AP:GetDisperseSummary().activeShards == 1, "Disperse shard add failed")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_MPLUS_M_VAULT", "1", "WHISPER", "EvilSpoofer")
    assert(AP:GetMPlusVaultSummary().quick == 0, "Spoofed whisper not ignored")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_MPLUS_M_VAULT", "1", "WHISPER", "TestHero")
    assert(AP:GetMPlusVaultSummary().quick == 1, "Valid MPlus Vault failed")

    -- Test 4: AutoAbsorb & AutoSell
    AP.autoSwap.unlocked = true
    AP:SetAutoAbsorbGroupBit(4, true)
    assert(AP.autoSwap.groupMask == 7, "AAMASK failed")

    -- Test 5: ALL AttuneParser tabs including "sets" and "server" (via AttuneParser_Integrations)
    for _, tabName in ipairs({ "top", "summary", "bags", "sets", "settings", "server" }) do
        AP:OpenUI(tabName)
        assert(AttuneParserFrame and AttuneParserFrame:IsShown() and AttuneParserFrame.activeTab == tabName, "AP tab failed: " .. tabName)
    end
    assert(AttuneParserFrame.tabPanels.server.wbRows ~= nil, "ServerSync tab was not populated!")
    assert(AttuneParserFrame.tabPanels.sets and AttuneParserFrame.tabPanels.sets.lRows ~= nil and AttuneParserFrame.tabPanels.sets.rRows ~= nil, "MorKel sets tab was not populated!")

    -- Test 6: TalorianTP Track 2 (buffs guard before load + bit toggle after state, retinue, GoldVault, Pepe throttle & mask)
    assert(SC:ToggleTalBuffBit(0, false) == nil, "Must guard buff toggle until ASMSG_TALORIAN_STATE arrives")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_TALORIAN_STATE", "0 1", "WHISPER", "TestHero")
    assert(SC.tal.loaded == true, "ASMSG_TALORIAN_STATE must mark SC.tal.loaded")
    SC:ToggleTalBuffBit(0, false)
    SC:ToggleTalBuffBit(1, true)
    SC:ToggleTalBuffBit(3, true)
    assert(SC.tal.mask == 9, "Talorian buffs failed")
    assert(SC:CycleRetinueSlot(2) == 4, "Retinue cycle failed")

    _G._TickAll(0.5)
    _G._SENT_ADDON = {}
    SC:SendPepeQueued("req")
    _G._TickAll(0.1)
    SC:SendPepeQueued("perks:2")
    assert(#_G._SENT_ADDON == 1, "Pepe throttle failed")
    _G._TickAll(0.4)
    assert(#_G._SENT_ADDON == 2, "Pepe flush failed")

    -- Test 7: Build Presets
    SC:CaptureBuildPreset(1, "Fury Raid")
    _G.C_Talent._active = 2; _G.PearkProgress[101].active = false; _G.PearkProgress[103].active = true; _G.PRIME_SetForge.branches[0].v2 = 1
    _G._SENT_SRV = {}; _G._SENT_ADDON = {}
    assert(SC:ApplyBuildPreset(1) == true, "ApplyBuildPreset failed")
    for s = 1, 6 do _G._TickAll(0.35) end
    assert(#_G._SENT_SRV >= 3, "Build preset did not emit spec + peark commands")

    -- Test 8: Cooperative QNC + QNP/QNW HUD + PRIMEMTR
    TalorianTP_DB.serverCtrl.qncEnabled = true
    SC:RefreshQNCHighlight()
    local lastQ = _G._MAC_CALLS[#_G._MAC_CALLS]
    assert(lastQ.val:find("0xLOR:1.0,0.80,0.15", 1, true) and lastQ.val:find(_G._TARGET_GUID, 1, true), "QNC chaining failed")
    assert(SC:SetCustomPinHere() == true and TalorianHUD3DFrame:IsShown(), "HUD QNP failed")
    SC:ClearCustomPin()

    -- Test 9: TalorianTP Tabs 1..5 non-empty + progress bars & item % under destination buttons!
    local ui
    do
        local _origGZA_t9 = AP.GetZoneAnalysis
        AP.GetZoneAnalysis = function(self, zoneId)
            if zoneId == 4812 then
                return { totalPool = 40, completedCount = 20, newCount = 10, forgeCount = 10, totalRemainStats = 1500, modeAvailable = true }
            end
            return { totalPool = 0, completedCount = 0, newCount = 0, forgeCount = 0, totalRemainStats = 0, modeAvailable = true }
        end
        for tabId = 1, 5 do
            ui = TTP:OpenUI(tabId)
            assert(ui and ui:IsShown(), "TalorianTP tab failed: " .. tabId)
        end
        assert(ui and ui.serverPanel and ui.serverPanel.Refresh ~= nil, "TalorianTP Tab 5 is STILL empty!")
        ui = TTP:OpenUI(1)
        local btn0 = ui.destButtons[1]
        assert(btn0 and btn0.progBg and btn0.progBg:IsShown(), "Tab 1 dest button progBg must be shown!")
        assert(btn0.progFill and btn0.progFill:IsShown() and btn0.progAbsFill and btn0.progAbsFill:IsShown(),
            "Tab 1 dest button progFill & progAbsFill must be shown when partially absorbed!")
        assert(btn0.subtitle and btn0.subtitle:GetText():find("50%", 1, true) and btn0.subtitle:GetText():find("(20/40)", 1, true),
            "Tab 1 dest button subtitle must display item %! got=" .. tostring(btn0.subtitle and btn0.subtitle:GetText()))
        assert(ui.quickRaidBtns and ui.quickRaidBtns[1] and ui.quickRaidBtns[1].progBg and ui.quickRaidBtns[1].progBg:IsShown(),
            "Quick raid button ЦЛК progBg must be shown!")
        ui = TTP:OpenUI(3)
        assert(ui.destButtons[1] and ui.destButtons[1].progBg and not ui.destButtons[1].progBg:IsShown(),
            "Tab 3 (Capitals) dest button progBg must be hidden!")
        AP.GetZoneAnalysis = _origGZA_t9
    end

    -- Test 10: Real Hardmode Paragon 405 (ignores zero ASMSG_NECK_INFO, tracks ASMSG_PARAGON_XP!)
    local apPar = AP:GetParagonInfo()
    assert(apPar.level == 405 and apPar.curXP == 4500000 and apPar.pct == 50, "AP Paragon 405 failed: " .. tostring(apPar.level))
    assert(SC.neck.level == 405, "TalorianTP Paragon 405 from serverData failed: " .. tostring(SC.neck.level))

    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_PARAGON_XP", "5000000\t9000000\t405", "WHISPER", "TestHero")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_NECK_INFO", "0:0:0:0:0", "UNKNOWN", "TestHero")
    assert(SC.neck.level == 405 and SC.neck.xp == 5000000, "Zero ASMSG_NECK_INFO overwrote Paragon 405!")

    -- Test 11: Companion spellID 91200 + Bridge ACTIVE even with renamed Talorian ("МойСпутник")
    assert(AP:HasTalorianPet() == true, "HasTalorianPet spell 91200 failed")
    assert(AP:IsTalorianBridgeActive() == true, "Talorian bridge not active despite loaded TalorianTP!")

    -- Test 12: ItemBank Auto-Equip (ACMSG_IB_EQUIP, server filters, BoE, DW/2H, paired slots, combat, 15s grace, ASMSG_IB_RES backoff, WH_IBG fallback)
    assert(AP:GetSetting("ibAutoEquip") == false, "ibAutoEquip must default to false")

    -- Configure rich item & attune mocks for Test 12
    local MOCK_ITEMS = {
        [60001] = { name="Кираса А", q=4, ilvl=232, loc="INVTYPE_CHEST", done=false, boe=false },
        [60002] = { name="Кираса Б", q=4, ilvl=264, loc="INVTYPE_CHEST", done=false, boe=false },
        [60003] = { name="Зеленый шлем", q=2, ilvl=200, loc="INVTYPE_HEAD", done=false, boe=false },
        [60010] = { name="BoE Плечи", q=4, ilvl=251, loc="INVTYPE_SHOULDER", done=false, boe=true },
        [60020] = { name="Надетый шлем", q=4, ilvl=245, loc="INVTYPE_HEAD", done=false, boe=false },
        [60021] = { name="Шлем из ИБ", q=4, ilvl=258, loc="INVTYPE_HEAD", done=false, boe=false },
        [60030] = { name="Двуручка", q=4, ilvl=264, loc="INVTYPE_2HWEAPON", done=false, boe=false },
        [60031] = { name="Одноручка ОХ", q=4, ilvl=251, loc="INVTYPE_WEAPON", done=false, boe=false },
        [60040] = { name="Кольцо 1", q=4, ilvl=251, loc="INVTYPE_FINGER", done=false, boe=false },
        [60041] = { name="Кольцо 2", q=4, ilvl=251, loc="INVTYPE_FINGER", done=false, boe=false },
        [60042] = { name="Поглощ. кольцо", q=4, ilvl=226, loc="INVTYPE_FINGER", done=true, boe=false },
        [60050] = { name="Ремень ИБ WH", q=4, ilvl=251, loc="INVTYPE_WAIST", done=false, boe=false },
        [1702100] = { name="Т11 Шлем", q=4, ilvl=277, loc="INVTYPE_HEAD", done=false, boe=false },
    }
    local MOCK_EQUIP = {}
    _G.GetInventoryItemLink = function(_, slot) return MOCK_EQUIP[slot] end
    _G.GetItemInfo = function(x)
        local id = tonumber(tostring(x):match("(%d+)"))
        local m = id and MOCK_ITEMS[id]
        if not m then return nil end
        return m.name, "item:"..id..":0:0:0:0:0:0", m.q, m.ilvl, 80, "Доспехи", (m.subType or "Латы"), 1, m.loc, "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    _G.CustomAttuneItemStatus = function(eid, forge, sfx)
        local m = MOCK_ITEMS[eid]
        if not m then return false, false, 0, true end
        if m.cant then return false, true, 0, true end
        local d = (m.done == true)
        if m.doneMaxForge ~= nil then
            d = ((forge or 0) <= m.doneMaxForge)
        end
        return d, false, d and 100 or 0, true
    end
    if AP_IBAutoScanTip then
        AP_IBAutoScanTipTextLeft2 = {
            _t = "", _red = false,
            GetText = function(self) return self._t end,
            GetTextColor = function(self)
                if self._red then return 1.0, 0.1, 0.1 else return 1.0, 1.0, 1.0 end
            end,
        }
        function AP_IBAutoScanTip:SetHyperlink(lk)
            local id = tonumber(tostring(lk):match("(%d+)"))
            local m = id and MOCK_ITEMS[id]
            AP_IBAutoScanTipTextLeft2._red = (m and m.red) or false
            AP_IBAutoScanTipTextLeft2._t = (m and m.boe) and "Становится персональным при надевании" or "Персональный предмет"
            self._lines = 2
        end
        function AP_IBAutoScanTip:NumLines() return self._lines or 0 end
    end

    local function PopLastIBEquip()
        for i = #_G._SENT_ADDON, 1, -1 do
            if _G._SENT_ADDON[i].prefix == "ACMSG_IB_EQUIP" then
                return tonumber(_G._SENT_ADDON[i].body), #_G._SENT_ADDON
            end
        end
        return nil, 0
    end

    -- Helper reset
    local function ResetIBScenario(items)
        _G._SENT_ADDON = {}
        MOCK_EQUIP = {}
        _G._IN_COMBAT = false
        _G.PRIME_ItemBank = { items = items, cap = 200 }
        if AP.serverSync and AP.serverSync.ib then
            AP.serverSync.ib.items = {}
            AP.serverSync.ib.byGuid = {}
            AP.serverSync.ib.loaded = false
            AP.serverSync.ib.fullLoaded = false
            AP.serverSync.ib.worn = {}
            AP.serverSync.ib.lastSwapAt = 0
        end
        if AP.serverSync and AP.serverSync.wh then
            AP.serverSync.wh.ibg = {}
        end
        AP.forgeEquip = {}
        AP.autoSwap.groupMask = 31
        AP.autoSwap.qualMask = 60
        AP.autoSwap.orderWorst = false
        AP.autoSwap.boeAllowed = false
    end

    -- 12a: Disabled -> sends nothing even on manual schedule or IB update
    ResetIBScenario({ { guid = 1001, entry = 60001, forge = 0, flags = 49, link = "item:60001:0:0:0:0:0:0" } })
    local okOff, rOff = AP:RunItemBankAutoEquip(false)
    assert(okOff == false and rOff == "disabled", "Should stay disabled by default")
    assert(#_G._SENT_ADDON == 0, "Disabled ibAutoEquip sent ACMSG_IB_EQUIP!")

    -- 12b: Best-first vs orderWorst, T11 + non-attunable flags excluded
    ResetIBScenario({
        { guid = 1001, entry = 60001, forge = 0, flags = 49, link = "item:60001:0:0:0:0:0:0" }, -- 232 chest
        { guid = 1002, entry = 60002, forge = 0, flags = 49, link = "item:60002:0:0:0:0:0:0" }, -- 264 chest
        { guid = 1003, entry = 1702100, forge = 0, flags = 49, link = "item:1702100:0:0:0:0:0:0" }, -- T11 excluded
        { guid = 1004, entry = 60021, forge = 0, flags = 1, link = "item:60021:0:0:0:0:0:0" }, -- flags missing bit 16 (not attunable)
    })
    AP.autoSwap.orderWorst = false
    local okB, _, cB = AP:RunItemBankAutoEquip(true)
    assert(okB == true and cB.guid == 1002, "Best-first should pick ilvl 264 chest (1002), got " .. tostring(cB and cB.guid))
    -- Simulate server response fail on 1002 -> 30s backoff, next pass picks 1001 (NOT 1003 or 1004!)
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "1\tСумки полны", "WHISPER", "TestHero")
    _G._SENT_ADDON = {}
    local okB2, _, cB2 = AP:RunItemBankAutoEquip(true)
    assert(okB2 == true and cB2.guid == 1001, "After 1002 backoff should skip T11/no-flag16 and pick 1001, got " .. tostring(cB2 and cB2.guid))
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\tequip", "WHISPER", "TestHero")

    -- Test orderWorst picks ilvl 232 first (with time > failUntil for clean 1001/1002)
    _G._TIME = _G._TIME + 35
    ResetIBScenario({
        { guid = 1011, entry = 60001, forge = 0, flags = 49, link = "item:60001:0:0:0:0:0:0" },
        { guid = 1012, entry = 60002, forge = 0, flags = 49, link = "item:60002:0:0:0:0:0:0" },
    })
    AP.autoSwap.orderWorst = true
    local okW, _, cW = AP:RunItemBankAutoEquip(true)
    assert(okW == true and cW.guid == 1011, "orderWorst should pick ilvl 232 chest (1011)")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\tequip", "WHISPER", "TestHero")

    -- 12c: BoE gate & quality mask filter
    ResetIBScenario({
        { guid = 1020, entry = 60010, forge = 0, flags = 49, link = "item:60010:0:0:0:0:0:0" }, -- BoE shoulder
        { guid = 1021, entry = 60003, forge = 0, flags = 49, link = "item:60003:0:0:0:0:0:0" }, -- Green head
    })
    AP.autoSwap.qualMask = 16 -- Epic only
    AP.autoSwap.boeAllowed = false
    local okG1, rG1 = AP:RunItemBankAutoEquip(true)
    assert(okG1 == false and rG1:find("BoE", 1, true) and rG1:find("качества", 1, true), "BoE & qualMask diagnostic expected, got: " .. tostring(rG1))
    AP.autoSwap.boeAllowed = true
    local okG2, _, cG2 = AP:RunItemBankAutoEquip(true)
    assert(okG2 == true and cG2.guid == 1020, "BoE should equip once boeAllowed=true")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\tequip", "WHISPER", "TestHero")

    -- 12d: Un-absorbed equipped slot preserved; 2H MH blocks 1H OH; duplicate Ring prevented
    ResetIBScenario({
        { guid = 1031, entry = 60021, forge = 0, flags = 49, link = "item:60021:0:0:0:0:0:0" }, -- head
        { guid = 1032, entry = 60031, forge = 0, flags = 49, link = "item:60031:0:0:0:0:0:0" }, -- 1H weapon
        { guid = 1033, entry = 60040, forge = 0, flags = 49, link = "item:60040:0:0:0:0:0:0" }, -- duplicate ring 1
        { guid = 1034, entry = 60041, forge = 0, flags = 49, link = "item:60041:0:0:0:0:0:0" }, -- distinct ring 2
    })
    MOCK_EQUIP[1] = "item:60020:0:0:0:0:0:0"   -- HeadSlot: unabsorbed
    MOCK_EQUIP[16] = "item:60030:0:0:0:0:0:0"  -- MainHand: 2H unabsorbed
    MOCK_EQUIP[11] = "item:60040:0:0:0:0:0:0"  -- Finger0: unabsorbed Ring 1 (Finger1 empty)
    local okP1, _, cP1 = AP:RunItemBankAutoEquip(true)
    assert(okP1 == true and cP1.guid == 1034, "Should skip busy Head, 2H-blocked OH, and duplicate Ring 1, picking 1034 into empty Finger1!")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\tequip", "WHISPER", "TestHero")

    -- If Finger1 is ALSO occupied (even if absorbed), while Finger0 is unabsorbed -> do NOT equip rings blindly!
    MOCK_EQUIP[12] = "item:60042:0:0:0:0:0:0"
    local okP2, rP2 = AP:RunItemBankAutoEquip(true)
    assert(okP2 == false and (rP2 == "no_candidates" or rP2:find("слоты заняты", 1, true)), "Should protect unabsorbed Finger0 when Finger1 is occupied, got: " .. tostring(rP2))

    -- Once Head item finishes absorbing, ATTUNE_UPDATED schedules & auto-equips 1031!
    AP:SetItemBankAutoEquip(true)
    _G._TIME = _G._TIME + 5.0 -- clear grace/cooldowns cleanly
    _G._SENT_ADDON = {}
    MOCK_ITEMS[60020].done = true
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_ATTUNE_GAINED", "60020", "WHISPER", "TestHero")
    AP:Fire("ATTUNE_UPDATED", "ASMSG_ATTUNE_GAINED")
    _G._TickAll(0.45)
    local eqGuid = PopLastIBEquip()
    assert(eqGuid == 1031, "Finished Head slot should auto-trigger 1031 from IB! got=" .. tostring(eqGuid))
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\tequip", "WHISPER", "TestHero")

    -- 12e: Combat behavior: allowed from IB OR bags! If server rejects ACMSG_IB_EQUIP in combat -> immediately falls back to bags in combat + unlocks IB at PLAYER_REGEN_ENABLED!
    _G._TIME = _G._TIME + 5.0
    ResetIBScenario({ { guid = 1050, entry = 60002, forge = 0, flags = 49, link = "item:60002:0:0:0:0:0:0" } })
    local COMBAT_BAG_SWAPS = {}
    local _pickedItem = nil
    local _testBags12e = { [0] = { [1] = "item:60021:0:0:0:0:0:0" } } -- Head item in bag!
    _G.GetContainerNumSlots = function(b) return (b == 0) and 16 or 0 end
    _G.GetContainerItemLink = function(b, s) return _testBags12e[b] and _testBags12e[b][s] end
    _G.GetContainerItemInfo = function() return nil, 1, false end
    _G.ClearCursor = function() _pickedItem = nil end
    _G.PickupContainerItem = function(b, s) _pickedItem = { b = b, s = s, link = _testBags12e[b] and _testBags12e[b][s] } end
    _G.CursorHasItem = function() return _pickedItem ~= nil end
    _G.EquipCursorItem = function(invId)
        if _pickedItem then
            table.insert(COMBAT_BAG_SWAPS, { invId = invId, link = _pickedItem.link })
            MOCK_EQUIP[invId] = _pickedItem.link
            _testBags12e[_pickedItem.b][_pickedItem.s] = nil
            _pickedItem = nil
        end
    end

    _G._IN_COMBAT = true
    AP:SetSetting("ibEquipInCombat", true)
    local okCombOn, _, cComb = AP:RunItemBankAutoEquip(false)
    assert(okCombOn == true and cComb.guid == 1050, "With ibEquipInCombat=true, IB auto-equip must attempt ACMSG_IB_EQUIP in combat!")
    -- Server rejects ACMSG_IB_EQUIP in combat -> blocks IB until regen, AND immediately falls back to bags in combat!
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "1\tВ бою предметы не надеть", "WHISPER", "TestHero")
    _G._TIME = _G._TIME + 0.5
    local okBagComb, reasonBagComb, cBagComb = AP:RunItemBankAutoEquip(false)
    assert(okBagComb == true and reasonBagComb == "equipped_bag" and #COMBAT_BAG_SWAPS == 1 and cBagComb.entry == 60021, "Should fall back to equipping straight from bags in combat! got: " .. tostring(reasonBagComb))
    assert(AP:GetItemBankEquipSummary(false).itemCount == 1, "Summary intact")

    -- Clean test bag before regen & check regen flushes IB item 1050!
    _G.GetContainerNumSlots = function() return 0 end
    _G.GetContainerItemLink = function() return nil end
    _G._IN_COMBAT = false
    _G._FireEvent("PLAYER_REGEN_ENABLED")
    _G._TickAll(0.5)
    assert(PopLastIBEquip() == 1050, "PLAYER_REGEN_ENABLED must clear ibCombatBlocked and flush IB equip!")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\tequip", "WHISPER", "TestHero")

    -- And when ibEquipInCombat=false -> combat blocks proactively until regen
    _G._TIME = _G._TIME + 5.0
    ResetIBScenario({ { guid = 1051, entry = 60002, forge = 0, flags = 49, link = "item:60002:0:0:0:0:0:0" } })
    AP:SetSetting("ibEquipInCombat", false)
    _G._IN_COMBAT = true
    local okC1, rC1 = AP:RunItemBankAutoEquip(false)
    assert(okC1 == false and rC1 == "combat", "ibEquipInCombat=false must defer combat IB auto-equip")
    _G._IN_COMBAT = false
    _G._FireEvent("PLAYER_REGEN_ENABLED")
    _G._TickAll(0.6)
    assert(PopLastIBEquip() == 1051, "PLAYER_REGEN_ENABLED must flush deferred IB equip!")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\tequip", "WHISPER", "TestHero")
    AP:SetSetting("ibEquipInCombat", true)
    _G.CursorHasItem = function() return false end

    -- 12f: Manual equipment change triggers 15s grace period
    _G._TIME = _G._TIME + 5.0 -- > 2.5s after last auto-swap -> treated as manual user swap
    ResetIBScenario({ { guid = 1060, entry = 60002, forge = 0, flags = 49, link = "item:60002:0:0:0:0:0:0" } })
    _G._FireEvent("PLAYER_EQUIPMENT_CHANGED", 1, true)
    local okGr, rGr = AP:RunItemBankAutoEquip(false)
    assert(okGr == false and rGr == "grace", "Manual equip must trigger 15s grace pause")
    assert(AP:GetItemBankEquipSummary(true).graceRemain >= 14, "graceRemain should report ~15s")
    _G._TickAll(15.5)
    assert(PopLastIBEquip() == 1060, "After 15s grace expires, auto-equip must resume!")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\tequip", "WHISPER", "TestHero")

    -- 12g: ASMSG_WH_IBG fallback before /ibank is opened
    _G._TIME = _G._TIME + 5.0
    _G.PRIME_ItemBank = nil
    AP.serverSync.ib.items = {}
    AP.serverSync.ib.loaded = false
    MOCK_EQUIP = {}
    _G._SENT_ADDON = {}
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_WH_IBG", "5555:60050", "WHISPER", "TestHero")
    local okWh, _, cWh = AP:RunItemBankAutoEquip(true)
    assert(okWh == true and cWh.guid == 5555 and PopLastIBEquip() == 5555, "ASMSG_WH_IBG fallback equip failed!")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\tequip", "WHISPER", "TestHero")

    -- 12h: Armor equips even when AAMASK has Броня unchecked (ibUseAAMask=false default), AND respects ibUseAAMask=true + ASMSG_IB_WORN!
    _G._TIME = _G._TIME + 5.0
    ResetIBScenario({ { guid = 2001, entry = 60002, forge = 0, flags = 49, link = "item:60002:0:0:0:0:0:0" } }) -- Chest (Броня, grp=1)
    AP.autoSwap.groupMask = 22 -- Украш.(2) + Оруж.(4) + Дальн.(16), Броня(1) = OFF!
    AP:SetSetting("ibUseAAMask", false)
    local okIndep, _, cIndep = AP:RunItemBankAutoEquip(true)
    assert(okIndep == true and cIndep.guid == 2001, "With ibUseAAMask=false, Armor in IB must still equip when AAMASK lacks Броня!")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\tequip", "WHISPER", "TestHero")

    _G._TIME = _G._TIME + 5.0
    ResetIBScenario({ { guid = 2002, entry = 60002, forge = 0, flags = 49, link = "item:60002:0:0:0:0:0:0" } })
    AP.autoSwap.groupMask = 22 -- Украш.(2) + Оруж.(4) + Дальн.(16), Броня(1) = OFF!
    AP:SetSetting("ibUseAAMask", true)
    local okAAM, rAAM = AP:RunItemBankAutoEquip(true)
    assert(okAAM == false and rAAM:find("фильтр", 1, true), "With ibUseAAMask=true and Броня OFF, should skip and report filter, got: " .. tostring(rAAM))
    AP:SetSetting("ibUseAAMask", false)

    -- Test ASMSG_IB_WORN protects tier-2 forged chest even if AP.forgeEquip is empty (e.g. fresh /reload)
    AP.forgeEquip = {}
    MOCK_EQUIP[5] = "item:60001:0:0:0:0:0:0"
    MOCK_ITEMS[60001].done = false
    local _origStatus = _G.CustomAttuneItemStatus
    _G.CustomAttuneItemStatus = function(eid, forge, sfx)
        if eid == 60001 and (forge or 0) == 0 then return true, false, 100, true end -- absorbed at tier 0
        if eid == 60001 and forge == 2 then return false, false, 45, true end       -- NOT absorbed at tier 2!
        return _origStatus(eid, forge, sfx)
    end
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_WORN", "4:2", "WHISPER", "TestHero") -- 0-based slot 4 == ChestSlot (5), tier 2!
    local okWorn, rWorn = AP:RunItemBankAutoEquip(true)
    assert(okWorn == false and rWorn:find("слоты заняты", 1, true), "ASMSG_IB_WORN tier 2 should protect Chest from premature swap, got: " .. tostring(rWorn))
    _G.CustomAttuneItemStatus = _origStatus

    AP:SetItemBankAutoEquip(false)

    -- Test 13: Auto-Put to ItemBank (ACMSG_IB_PUT, keeps vendor/forge-upgrade items & equipment sets!)
    assert(AP:GetSetting("ibAutoPut") == false, "ibAutoPut must default to false")
    assert(AP:GetSetting("ibAutoPutMode") == "unabsorbed", "ibAutoPutMode must default to unabsorbed")

    local MOCK_BAGS = {}
    local MOCK_SET_BAGSLOTS = {}
    _G.GetContainerNumSlots = function(bag) return (bag >= 0 and bag <= 4) and 16 or 0 end
    _G.GetContainerItemLink = function(bag, slot) return MOCK_BAGS[bag] and MOCK_BAGS[bag][slot] end
    _G.GetContainerItemInfo = function() return nil, 1, false end
    _G.GetNumEquipmentSets = function() return 1 end
    _G.GetEquipmentSetInfo = function() return "PvE" end
    _G.GetEquipmentSetLocations = function() return { [1] = 101 } end
    _G.EquipmentManager_UnpackLocation = function(loc)
        local pair = MOCK_SET_BAGSLOTS[loc]
        if pair then return false, false, true, pair[2], pair[1] end
        return false, false, false, 0, 0
    end

    local function PopLastIBPut()
        for i = #_G._SENT_ADDON, 1, -1 do
            if _G._SENT_ADDON[i].prefix == "ACMSG_IB_PUT" then
                return _G._SENT_ADDON[i].body
            end
        end
        return nil
    end

    -- Reset items + add bag-only mocks
    MOCK_ITEMS[60060] = { name="Чужая ткань", q=4, ilvl=251, loc="INVTYPE_CHEST", done=false, boe=false, cant=true }
    MOCK_ITEMS[60061] = { name="Погл. тир 0 (под ковку)", q=4, ilvl=245, loc="INVTYPE_WAIST", doneMaxForge=0, boe=false }
    MOCK_ITEMS[60062] = { name="Титан погл. (под вендор/алл)", q=4, ilvl=277, loc="INVTYPE_LEGS", done=true, boe=false }
    MOCK_ITEMS[60063] = { name="Сет экип.", q=4, ilvl=264, loc="INVTYPE_SHOULDER", done=false, boe=false }

    -- 13a: mode = "unabsorbed" keeps absorbed (vendor/forge upgrade), cant (vendor/other class), and EquipmentSet; puts bag=0 slot=3 -> "255:25" and bag=2 slot=5 -> "20:4"
    _G._TIME = _G._TIME + 5.0
    _G.PRIME_ItemBank = { items = {}, cap = 200 }
    AP.forgeBag = { [0] = { [4] = 3 }, [2] = {} } -- slot 4 of bag 0 is forged tier 3!
    MOCK_SET_BAGSLOTS = { [101] = { 1, 2 } } -- bag 1, slot 2 is in EquipmentSet!
    MOCK_BAGS = {
        [0] = {
            [1] = "item:60061:0:0:0:0:0:0", -- absorbed tier 0 (needs forge upgrade -> STAY in bag!)
            [2] = "item:60060:0:0:0:0:0:0", -- cant (STAY in bag under unabsorbed!)
            [3] = "item:60002:0:0:0:0:0:0", -- unabsorbed Chest (SHOULD PUT -> 255:25!)
            [4] = "item:60062:0:0:0:0:0:0", -- absorbed tier 3 (STAY in bag under unabsorbed!)
        },
        [1] = {
            [2] = "item:60063:0:0:0:0:0:0", -- in EquipmentSet (MUST STAY!)
        },
        [2] = {
            [5] = "item:60021:0:0:0:0:0:0", -- unabsorbed Head (SHOULD PUT -> 20:4!)
        },
    }
    _G._SENT_ADDON = {}
    local okP1, _, cP1 = AP:RunItemBankAutoPut(true)
    assert(okP1 == true and PopLastIBPut() == "255:25", "Bag 0 slot 3 should translate to 255:25, got: " .. tostring(PopLastIBPut()))
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\tput", "WHISPER", "TestHero")
    MOCK_BAGS[0][3] = nil
    _G._TIME = _G._TIME + 1.0
    local okP2, _, cP2 = AP:RunItemBankAutoPut(true)
    assert(okP2 == true and PopLastIBPut() == "20:4", "Bag 2 slot 5 should translate to 20:4, got: " .. tostring(PopLastIBPut()))
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\tput", "WHISPER", "TestHero")
    MOCK_BAGS[2][5] = nil

    -- Now in mode "unabsorbed", remaining items (absorbed tier 0/3, cant, set) MUST STAY in bags!
    _G._TIME = _G._TIME + 1.0
    local okP3, rP3 = AP:RunItemBankAutoPut(true)
    assert(okP3 == false and rP3:find("ковку", 1, true), "Absorbed/cant/set items must stay in bags in unabsorbed mode, got: " .. tostring(rP3))

    -- 13b: Cycle to "unabsorbed_other" -> moves cant (60060 at 255:24), still keeps absorbed upgrade & set!
    local m2 = AP:CycleItemBankPutMode()
    assert(m2 == "unabsorbed_other", "Cycle mode 2 failed")
    local okP4 = AP:RunItemBankAutoPut(true)
    assert(okP4 == true and PopLastIBPut() == "255:24", "unabsorbed_other should put cant chest (255:24), got: " .. tostring(PopLastIBPut()))
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\tput", "WHISPER", "TestHero")
    MOCK_BAGS[0][2] = nil

    -- 13c: Cycle to "all_except_upgrade" -> moves absorbed tier 3 (255:26), STILL keeps absorbed tier 0 upgrade (60061) and set (60063)!
    local m3 = AP:CycleItemBankPutMode()
    assert(m3 == "all_except_upgrade", "Cycle mode 3 failed")
    _G._TIME = _G._TIME + 1.0
    local okP5 = AP:RunItemBankAutoPut(true)
    assert(okP5 == true and PopLastIBPut() == "255:26", "all_except_upgrade should put max-tier item (255:26), got: " .. tostring(PopLastIBPut()))
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\tput", "WHISPER", "TestHero")
    MOCK_BAGS[0][4] = nil

    _G._TIME = _G._TIME + 1.0
    local okP6, rP6 = AP:RunItemBankAutoPut(true)
    assert(okP6 == false and rP6:find("ковку", 1, true), "Upgrade-eligible tier 0 + EquipmentSet must STILL stay even in all_except_upgrade! got: " .. tostring(rP6))

    -- 13d: Manual ASMSG_IB_RES take pauses auto-put for 45s; MerchantFrame open pauses auto-put; full IB stops auto-put!
    AP:SetSetting("ibAutoPutMode", "unabsorbed")
    MOCK_BAGS[0][3] = "item:60002:0:0:0:0:0:0"
    AP:SetItemBankAutoPut(true)
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\ttake", "WHISPER", "TestHero")
    local okTk, rTk = AP:RunItemBankAutoPut(false)
    assert(okTk == false and rTk == "manual_pause", "Manual take should pause auto-put for 45s, got: " .. tostring(rTk))

    _G._TIME = _G._TIME + 50.0
    _G.PRIME_ItemBank = { items = { { guid=1 }, { guid=2 } }, cap = 2 }
    local okFull, rFull = AP:RunItemBankAutoPut(false)
    assert(okFull == false and rFull:find("заполнен", 1, true), "Full IB must stop auto-put, got: " .. tostring(rFull))

    AP:SetItemBankAutoPut(false)

    -- Test 14: Regression checks for audit fixes (ASMSG_IB_ADD + WH_IBG merge, recentEquipTier guard, SetBagItem Soulbound BoE override, RedLine vs Rep exemption, bag Finger1 direct equip)
    _G._TIME = _G._TIME + 10.0
    _G.PRIME_ItemBank = nil
    AP.serverSync.ib.items = {}
    AP.serverSync.ib.byGuid = {}
    AP.serverSync.ib.loaded = false
    AP.serverSync.ib.fullLoaded = false
    AP.serverSync.wh.ibg = {}
    _G.GetContainerNumSlots = function() return 0 end
    _G.GetContainerItemLink = function() return nil end
    MOCK_EQUIP = {}

    -- 14a: ASMSG_WH_IBG (2 items) + incremental ASMSG_IB_ADD (1 item) MUST merge into 3 items (never wipe WH_IBG!)
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_WH_IBG", "8101:60050;8102:60021", "WHISPER", "TestHero")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_ADD", "8103:60002:0:0:0:0:0:0:0:49:10:0", "WHISPER", "TestHero")
    assert(AP:GetItemBankEquipSummary(false).itemCount == 3, "ASMSG_IB_ADD must merge with WH_IBG before fullLoaded, got " .. tostring(AP:GetItemBankEquipSummary(false).itemCount))
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RESET", "1\t200\t0\t0\t0\t0\t0\t1", "WHISPER", "TestHero")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_ITEM", "8103:60002:0:0:0:0:0:0:0:49:10:0", "WHISPER", "TestHero")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_DONE", "", "WHISPER", "TestHero")
    assert(AP:GetItemBankEquipSummary(false).itemCount == 1, "After full ASMSG_IB_RESET + DONE, fullLoaded should switch to exact dump (1)")

    -- 14b: Equipping tier-2 copy of same entry (60001) protects ChestSlot for 2.5s before ASMSG_FORGE_MAP arrives
    _G._TIME = _G._TIME + 5.0
    ResetIBScenario({
        { guid = 8201, entry = 60001, forge = 2, flags = 49, link = "item:60001:0:0:0:0:0:0" },
        { guid = 8202, entry = 60002, forge = 0, flags = 49, link = "item:60002:0:0:0:0:0:0" },
    })
    AP.forgeEquip = {}
    MOCK_EQUIP[5] = nil
    local _origSt2 = _G.CustomAttuneItemStatus
    _G.CustomAttuneItemStatus = function(eid, forge, sfx)
        if eid == 60001 and (forge or 0) < 2 then return true, false, 100, true end
        if eid == 60001 and forge == 2 then return false, false, 10, true end
        return _origSt2(eid, forge, sfx)
    end
    AP.autoSwap.orderWorst = false -- ilvl 264 (60002) first? Set orderWorst=true so 60001 (ilvl 232) equips first!
    AP.autoSwap.orderWorst = true
    local okT2, _, cT2 = AP:RunItemBankAutoEquip(true)
    assert(okT2 == true and cT2.guid == 8201, "Should equip tier-2 60001")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\tequip", "WHISPER", "TestHero")
    MOCK_EQUIP[5] = "item:60001:0:0:0:0:0:0"
    AP.forgeEquip = {} -- Simulate delay before ASMSG_FORGE_MAP!
    _G._TIME = _G._TIME + 0.5
    local okT2b, rT2b = AP:RunItemBankAutoEquip(true)
    assert(okT2b == false and rT2b:find("слоты заняты", 1, true), "recentEquipTier guard must protect newly equipped tier-2 60001 from being replaced before ASMSG_FORGE_MAP! got: " .. tostring(rT2b))
    _G.CustomAttuneItemStatus = _origSt2

    -- 14c: SetBagItem soulbound override on BoE template + CanPlayerEquipTip red-line check + direct bag Finger1 equip!
    _G._TIME = _G._TIME + 5.0
    ResetIBScenario({})
    MOCK_EQUIP[11] = "item:60040:0:0:0:0:0:0" -- Finger0 unabsorbed
    MOCK_EQUIP[12] = "item:60042:0:0:0:0:0:0" -- Finger1 absorbed (done=true)
    MOCK_ITEMS[60045] = { name="Кольчужные сапоги (чуж.)", q=4, ilvl=245, loc="INVTYPE_FEET", done=false, boe=false, red=true }
    MOCK_ITEMS[60046] = { name="Боевой BoE привязан", q=4, ilvl=251, loc="INVTYPE_FINGER", done=false, boe=true, soulboundInBag=true }
    local _bag14 = { [0] = { [1] = "item:60045:0:0:0:0:0:0", [2] = "item:60046:0:0:0:0:0:0" } }
    _G.GetContainerNumSlots = function(b) return (b == 0) and 16 or 0 end
    _G.GetContainerItemLink = function(b, s) return _bag14[b] and _bag14[b][s] end
    _G.GetContainerItemInfo = function() return nil, 1, false end
    _G.AP_IBAutoScanTipTextLeft2 = AP_IBAutoScanTipTextLeft2 or { _t = "", GetText = function(self) return self._t end }
    AP_IBAutoScanTipTextLeft2.GetTextColor = function(self) if self._red then return 1.0, 0.1, 0.1 else return 1.0, 1.0, 1.0 end end
    function AP_IBAutoScanTip:SetBagItem(b, s)
        local lk = _bag14[b] and _bag14[b][s]
        local id = lk and tonumber(tostring(lk):match("(%d+)"))
        local m = id and MOCK_ITEMS[id]
        AP_IBAutoScanTipTextLeft2._red = (m and m.red) or false
        if m and m.soulboundInBag then
            AP_IBAutoScanTipTextLeft2._t = "Персональный предмет"
        elseif m and m.red then
            AP_IBAutoScanTipTextLeft2._t = "Требуется: Кольчуга"
        else
            AP_IBAutoScanTipTextLeft2._t = "Персональный предмет"
        end
        self._lines = 2
    end
    local _swaps14 = {}
    local _pick14 = nil
    _G.ClearCursor = function() _pick14 = nil end
    _G.PickupContainerItem = function(b, s) _pick14 = { b=b, s=s, lk=_bag14[b][s] } end
    _G.CursorHasItem = function() return _pick14 ~= nil end
    _G.EquipCursorItem = function(id) table.insert(_swaps14, id); _pick14 = nil end

    AP.autoSwap.boeAllowed = false -- BoE off, BUT 60046 is already soulbound in bag -> allowed directly into Finger1 (slot 12), while red-line 60045 is blocked!
    AP:SetSetting("ibAutoEquip", true)
    local ok14, r14, c14 = AP:RunItemBankAutoEquip(true)
    assert(ok14 == true and r14 == "equipped_bag" and c14.entry == 60046 and _swaps14[1] == 12,
        "Bag Finger1 should skip red-line 60045 and equip soulbound BoE 60046 into slot 12 directly! got: " .. tostring(r14))
    AP:SetItemBankAutoEquip(false)
    _G.CursorHasItem = function() return false end
    _G.GetContainerNumSlots = function() return 0 end
    _G.GetContainerItemLink = function() return nil end

    -- Test 15: GetOwnedUpgradeCandidates merge, Titan's Grip OH, ASMSG_IB_RES rollback, skill cache reset, and Safe IB Splitter
    -- 15a: ASMSG_IB_ADD before full /ibank still keeps ASMSG_WH_IBG items in GetOwnedUpgradeCandidates
    ResetIBScenario({})
    AP.Data = AP.Data or { TopMap = {} }
    local _origGetInfo = AP.GetItemInfo
    AP.GetItemInfo = function(self, eid)
        local m = MOCK_ITEMS[eid]
        if not m then return nil end
        return {
            itemId = eid, name = m.name, quality = m.q, ilvl = m.ilvl,
            doneTier = m.done and 3 or -1, isCompleted = m.done == true,
            curPct = m.done and 100 or 0, coreStatsSum = 1000, primaryZone = 1,
        }
    end
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_WH_IBG", "9501:60001;9502:60002", "WHISPER", "TestHero")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_ADD", "9501:60001:0:0:0:0:0:0:0:49:100:50:1", "WHISPER", "TestHero")
    local owned15 = AP:GetOwnedUpgradeCandidates()
    local seen60001, seen60002 = false, false
    for _, row in ipairs(owned15) do
        if row.itemId == 60001 and row.where == "itembank" then seen60001 = true end
        if row.itemId == 60002 and row.where == "itembank" then seen60002 = true end
    end
    assert(seen60001 and seen60002, "GetOwnedUpgradeCandidates must merge SS.ib.items + SS.wh.ibg before fullLoaded!")
    AP.GetItemInfo = _origGetInfo

    -- 15b: Warrior Titan's Grip (46917) unlocks SecondaryHandSlot when MH holds 2H, equips 2H sword in bag to slot 17, skips 2H staff
    _G._TIME = _G._TIME + 5.0
    ResetIBScenario({})
    local _origKnown = _G.IsSpellKnown
    _G.IsSpellKnown = function(sp) return sp == 46917 or sp == 674 end
    MOCK_EQUIP[16] = "item:60030:0:0:0:0:0:0" -- MH 2H NOT absorbed (busy), so only SecondaryHandSlot (17) is replaceable!
    MOCK_ITEMS[60030].done = false
    MOCK_ITEMS[60032] = { name="Посох неподх.", q=4, ilvl=264, loc="INVTYPE_2HWEAPON", subType="Посохи", done=false }
    MOCK_ITEMS[60033] = { name="Титанический двуручник ОХ", q=4, ilvl=251, loc="INVTYPE_2HWEAPON", subType="Двуручные мечи", done=false }
    local _bag15b = { [0] = { [1] = "item:60032:0:0:0:0:0:0", [2] = "item:60033:0:0:0:0:0:0" } }
    _G.GetContainerNumSlots = function(b) return (b == 0) and 16 or 0 end
    _G.GetContainerItemLink = function(b, s) return _bag15b[b] and _bag15b[b][s] end
    function AP_IBAutoScanTip:SetBagItem(b, s)
        AP_IBAutoScanTipTextLeft2._red = false
        AP_IBAutoScanTipTextLeft2._t = "Персональный предмет"
        self._lines = 2
    end
    local _swaps15b = {}
    local _pick15b = nil
    _G.ClearCursor = function() _pick15b = nil end
    _G.PickupContainerItem = function(b, s) _pick15b = { b=b, s=s } end
    _G.CursorHasItem = function() return _pick15b ~= nil end
    _G.EquipCursorItem = function(id) table.insert(_swaps15b, id); _pick15b = nil end

    AP:SetSetting("ibAutoEquip", true)
    local ok15b, r15b, c15b = AP:RunItemBankAutoEquip(true)
    assert(ok15b == true and r15b == "equipped_bag" and c15b.entry == 60033 and _swaps15b[1] == 17,
        "Titan's Grip should skip 2H staff 60032 and equip 2H sword 60033 directly to slot 17! got: " .. tostring(r15b))
    AP:SetItemBankAutoEquip(false)
    MOCK_ITEMS[60030].done = false
    _G.IsSpellKnown = _origKnown
    _G.CursorHasItem = function() return false end
    _G.GetContainerNumSlots = function() return 0 end
    _G.GetContainerItemLink = function() return nil end

    -- 15c: ASMSG_IB_RES failure rolls back recentEquipTier/forgeEquip AND PLAYER_LEVEL_UP clears canEquipCache
    _G._TIME = _G._TIME + 5.0
    ResetIBScenario({
        { guid = 9601, entry = 60001, forge = 2, flags = 49, link = "item:60001:0:0:0:0:0:0" },
    })
    MOCK_ITEMS[60001].done = false
    AP:SetSetting("ibAutoEquip", true)
    local ok15c = AP:RunItemBankAutoEquip(true)
    assert(ok15c == true and AP.forgeEquip[5] == 2, "Pending equip should set forgeEquip[5]=2")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "4\tОшибка боя", "WHISPER", "TestHero")
    assert(AP.forgeEquip[5] == nil, "Failed ASMSG_IB_RES must restore AP.forgeEquip[5] to previous value!")
    AP:SetItemBankAutoEquip(false)

    -- Test dynamic skill cache invalidation via PLAYER_LEVEL_UP
    _G._TIME = _G._TIME + 5.0
    ResetIBScenario({})
    MOCK_ITEMS[60047] = { name="Кольчужные наручи (позже изучено)", q=4, ilvl=245, loc="INVTYPE_WRIST", done=false, red=true }
    local _bag15c = { [0] = { [1] = "item:60047:0:0:0:0:0:0" } }
    _G.GetContainerNumSlots = function(b) return (b == 0) and 16 or 0 end
    _G.GetContainerItemLink = function(b, s) return _bag15c[b] and _bag15c[b][s] end
    function AP_IBAutoScanTip:SetBagItem(b, s)
        local lk = _bag15c[b] and _bag15c[b][s]
        local id = lk and tonumber(tostring(lk):match("(%d+)"))
        local m = id and MOCK_ITEMS[id]
        AP_IBAutoScanTipTextLeft2._red = (m and m.red) or false
        AP_IBAutoScanTipTextLeft2._t = "Персональный предмет"
        self._lines = 2
    end
    local _swaps15c = {}
    local _pick15c = nil
    _G.ClearCursor = function() _pick15c = nil end
    _G.PickupContainerItem = function(b, s) _pick15c = { b=b, s=s } end
    _G.CursorHasItem = function() return _pick15c ~= nil end
    _G.EquipCursorItem = function(id) table.insert(_swaps15c, id); _pick15c = nil end
    AP:SetSetting("ibAutoEquip", true)
    local ok15cPre = AP:RunItemBankAutoEquip(true)
    assert(ok15cPre == false, "Red-line 60047 should initially be skipped and cached")
    -- Now player learns skill and gains a level!
    MOCK_ITEMS[60047].red = false
    _G._FireEvent("PLAYER_LEVEL_UP", 80)
    _G._TIME = _G._TIME + 1.0
    local ok15cPost, r15cPost, c15cPost = AP:RunItemBankAutoEquip(true)
    assert(ok15cPost == true and r15cPost == "equipped_bag" and c15cPost.entry == 60047,
        "PLAYER_LEVEL_UP must clear canEquipCache so 60047 becomes equippable! got: " .. tostring(r15cPost))
    AP:SetItemBankAutoEquip(false)
    _G.CursorHasItem = function() return false end
    _G.GetContainerNumSlots = function() return 0 end
    _G.GetContainerItemLink = function() return nil end

    -- 15d: Safe ItemBank Duplicate Splitter (protects unabsorbed, blacklist, mixed forge buckets, and 1 copy < forge 3; batches uniform stacks via SPLITN!)
    _G._TIME = _G._TIME + 5.0
    ResetIBScenario({})
    MOCK_ITEMS[61001] = { name="Непогл. вещь", q=4, ilvl=251, loc="INVTYPE_CHEST", done=false, doneMaxForge=-1 }
    MOCK_ITEMS[61002] = { name="В ЧС вещь", q=4, ilvl=251, loc="INVTYPE_HEAD", done=true }
    MOCK_ITEMS[61003] = { name="Смешанный тир", q=4, ilvl=251, loc="INVTYPE_LEGS", doneMaxForge=0 }
    MOCK_ITEMS[61004] = { name="Ковка дублей", q=4, ilvl=251, loc="INVTYPE_WAIST", doneMaxForge=1 }
    MOCK_ITEMS[61005] = { name="Полностью погл. стек", q=4, ilvl=264, loc="INVTYPE_FEET", done=true }
    AP.blacklist = AP.blacklist or {}
    AP.blacklist["61002:-1"] = true

    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RESET", "1\t200\t0\t1\t450\t1\t0\t5\t1", "WHISPER", "TestHero")
    local splitBody15 = table.concat({
        "9001:61001:0:0:0:0:0:0:0:49:100:50:1", -- unabsorbed -> NEVER split
        "9002:61002:0:0:0:0:0:3:0:49:100:50:1", -- blacklisted -> NEVER split
        "9101:61003:0:0:0:0:0:0:0:49:100:50:1", -- absorbed forge 0 (mixed bucket with 9102!) -> single SPLIT 9101 only!
        "9102:61003:0:0:0:0:0:2:0:49:100:50:1", -- unabsorbed forge 2 -> NEVER split, blocks SPLITN for 61003!
        "9201:61004:0:0:0:0:0:0:0:49:100:50:1", -- forge 0 duplicate -> split single 9201
        "9202:61004:0:0:0:0:0:1:0:49:100:50:1", -- highest forge < 3 -> KEPT for forge upgrade!
        "9301:61005:12:0:0:0:0:3:0:49:100:50:1", -- uniform completed stack x3 sfx=12 -> batch SPLITN 61005:3:12!
        "9302:61005:12:0:0:0:0:3:0:49:100:50:1",
        "9303:61005:12:0:0:0:0:3:0:49:100:50:1",
    }, ";")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_ITEM", splitBody15, "WHISPER", "TestHero")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_DONE", "", "WHISPER", "TestHero")

    local plan15d = AP:GetItemBankSplitPlan(true)
    assert(plan15d.available == true and plan15d.dspBatch == true and plan15d.sfxBatch == true, "IB split plan metadata invalid")
    assert(plan15d.keptForge == 2, "Must keep 1 copy each for <t3 61003 (only 1 done? wait 9101) & 61004! got: " .. tostring(plan15d.keptForge))
    -- Wait: let's check what 61003 did: 9101 has forge=0, doneMaxForge=0 -> done, not done at 3 -> ALSO kept 1 copy!
    -- Good! Both 61003 (1 copy at forge 0) AND 61004 (highest copy 9202 at forge 1) get kept for <t3 forge upgrades, leaving 9201 (61004) + 3x 61005 = 4 split items!
    assert(plan15d.totalCount == 4 and plan15d.groupCount == 2,
        "Expected 4 split items across 2 groups (61005 x3 batch + 61004 duplicate 9201); got total=" .. tostring(plan15d.totalCount) .. " grp=" .. tostring(plan15d.groupCount))

    _G._SENT_ADDON = {}
    local okSp1, kindSp1 = AP:StartItemBankSplit(true)
    assert(okSp1 == true and kindSp1 == "splitn", "First split step must send batch ACMSG_IB_SPLITN! got: " .. tostring(kindSp1))
    assert(_G._SENT_ADDON[1].prefix == "ACMSG_IB_SPLITN" and _G._SENT_ADDON[1].body == "61005:3:12",
        "Unexpected SPLITN payload: " .. tostring(_G._SENT_ADDON[1].prefix) .. "=" .. tostring(_G._SENT_ADDON[1].body))

    -- Simulate server removing 61005 stack & acknowledging split -> next step splits 9201 via single ACMSG_IB_SPLIT!
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_DEL", "9301", "WHISPER", "TestHero")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_DEL", "9302", "WHISPER", "TestHero")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_DEL", "9303", "WHISPER", "TestHero")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\tsplit", "WHISPER", "TestHero")
    _G._TickAll(0.45)
    assert(_G._SENT_ADDON[#_G._SENT_ADDON].prefix == "ACMSG_IB_SPLIT" and _G._SENT_ADDON[#_G._SENT_ADDON].body == "9201",
        "Second split step must send single ACMSG_IB_SPLIT 9201 preserving 9202! got: " .. tostring(_G._SENT_ADDON[#_G._SENT_ADDON].prefix) .. "=" .. tostring(_G._SENT_ADDON[#_G._SENT_ADDON].body))
    AP:StopItemBankSplit()
    AP.blacklist["61002:-1"] = nil

    -- Test 16: ClassifyBagItem respects tier-3 completion under ibAutoPut all_except_upgrade + ACTIVE_TALENT_GROUP_CHANGED triggers InvalidateCaches(false)
    _G._TIME = _G._TIME + 5.0
    ResetIBScenario({})
    local _invCalls16 = 0
    local _origInv16 = AP.InvalidateCaches
    AP.InvalidateCaches = function(self, zoneOnly) if zoneOnly == false then _invCalls16 = _invCalls16 + 1 end end
    _G._FireEvent("ACTIVE_TALENT_GROUP_CHANGED")
    assert(_invCalls16 == 1, "ACTIVE_TALENT_GROUP_CHANGED must call AP:InvalidateCaches(false)")
    AP.InvalidateCaches = _origInv16

    AP:SetSetting("ibAutoPutMode", "all_except_upgrade")
    AP.forgeBag = { [0] = {}, [1] = {} }
    MOCK_ITEMS[61010] = { name="Базовый 0/3 (погл. только т0)", q=4, ilvl=245, loc="INVTYPE_WAIST", doneMaxForge=0 }
    MOCK_ITEMS[61011] = { name="Базовый 0 (но тир 3 уже закрыт)", q=4, ilvl=251, loc="INVTYPE_LEGS", done=true }
    local _bag16 = { [0] = { [1] = "item:61010:0:0:0:0:0:0", [2] = "item:61011:0:0:0:0:0:0" } }
    _G.GetContainerNumSlots = function(b) return (b == 0) and 16 or 0 end
    _G.GetContainerItemLink = function(b, s) return _bag16[b] and _bag16[b][s] end
    _G.GetContainerItemInfo = function() return nil, 1, false end
    _G._SENT_ADDON = {}
    local ok16, r16, c16 = AP:RunItemBankAutoPut(true)
    assert(ok16 == true and c16 and c16.eid == 61011,
        "all_except_upgrade should keep 61010 (needs tier 1..3) and deposit completed-tier3 61011! got: " .. tostring(c16 and c16.eid) .. " (" .. tostring(r16) .. ")")
    AP:SetSetting("ibAutoPutMode", "unabsorbed")
    _G.GetContainerNumSlots = function() return 0 end
    _G.GetContainerItemLink = function() return nil end

    -- Test 17: Renamed Talorian summon (91200) + Secure macro target + RaidMark + PrimeAH [BL] badge
    local _origComp = _G.GetCompanionInfo
    local _calledComp = nil
    _G.CallCompanion = function(kind, idx) _calledComp = { kind = kind, idx = idx } end
    _G.GetCompanionInfo = function(kind, idx)
        if kind == "CRITTER" and idx == 1 then
            return 500031, "МойСпутник", 91200, "Interface\\Icons\\Spell_Arcane_TeleportMoonglade", 0
        end
        return nil
    end
    _G._TIME = _G._TIME + 5.0
    local sumOk = TalorianTP_SummonIfNeeded()
    assert(sumOk == true and _calledComp and _calledComp.idx == 1, "Renamed Talorian (spell 91200) must summon via CallCompanion!")
    local secBtn = TalorianTP_EnsureSecureExecButton()
    local macTxt = secBtn and secBtn.GetAttribute and secBtn:GetAttribute("macrotext") or ""
    assert(macTxt:find("/targetexact МойСпутник", 1, true), "SecureExecBtn macro must target renamed Talorian! got: " .. tostring(macTxt))

    -- 17b: Target named "МойСпутник" gets recognized & marked (raid icon 3), including genitive declension, npc token & freshly-summoned grace
    do
        local _marks17 = {}
        local _origUnitName = _G.UnitName
        local _origUnitExists = _G.UnitExists
        local _origTipSetUnit = TalorianUnitScanTooltip and TalorianUnitScanTooltip.SetUnit
        local _origTipNumLines = TalorianUnitScanTooltip and TalorianUnitScanTooltip.NumLines
        _G.UnitExists = function(u)
            if u == "npc" or u == "target" then return true end
            return _origUnitExists(u)
        end
        _G.UnitName = function(u)
            if u == "player" then return "Саша" end
            if u == "target" or u == "npc" then return "МойСпутник" end
            return _origUnitName(u)
        end
        _G.UnitIsVisible = function() return nil end
        _G.GetRaidTargetIndex = function() return nil end
        _G.SetRaidTarget = function(u, idx) _marks17[u] = idx end
        _G.GetCompanionInfo = function(kind, idx)
            if kind == "CRITTER" and idx == 1 then
                return 500031, "МойСпутник", 91200, "Interface\\Icons\\Spell_Arcane_TeleportMoonglade", 0
            end
            return nil
        end
        if TalorianUnitScanTooltip then
            TalorianUnitScanTooltip.SetUnit = function(self)
                self.lines = { "МойСпутник", "Спутник Саши" }
                return true
            end
            TalorianUnitScanTooltip.NumLines = function() return 2 end
        end
        -- Freshly summoned grace (lastSummonTime recent -> isCurrent=0 allowed) + nil UnitIsVisible + Russian genitive + "npc" token!
        _G._TIME = _G._TIME + 0.5
        TalorianTP_SummonIfNeeded()
        TalorianTP_CheckAndMark(false)
        assert(_marks17.target == 3 and _marks17.npc == 3,
            "Talorian target & npc must be marked with diamond (3)! t=" .. tostring(_marks17.target) .. " n=" .. tostring(_marks17.npc))
        local _origGGO = _G.GetGossipOptions
        _G.GetGossipOptions = function() return end
        _marks17 = {}
        _G._FireEvent("GOSSIP_SHOW")
        _G.GetGossipOptions = _origGGO
        assert(_marks17.npc == 3, "GOSSIP_SHOW must mark npc Talorian with diamond (3)!")
        -- Verify SecureExecBtn macro starts with /cleartarget when not yet summoned
        local secBtn2 = TalorianTP_EnsureSecureExecButton()
        local mac2 = secBtn2 and secBtn2.GetAttribute and secBtn2:GetAttribute("macrotext") or ""
        assert(mac2:find("/cleartarget", 1, true) and mac2:find("/targetexact МойСпутник", 1, true),
            "Unsummoned SecureExecBtn macro must /cleartarget + target custom name! got=" .. tostring(mac2))
        if TalorianUnitScanTooltip then
            TalorianUnitScanTooltip.SetUnit = _origTipSetUnit
            TalorianUnitScanTooltip.NumLines = _origTipNumLines
        end
        _G.UnitIsVisible = function() return true end
        _G.UnitExists = _origUnitExists
        _G.UnitName = _origUnitName
        _G.GetCompanionInfo = _origComp
    end

    -- 17c: PrimeAH row badge shows [ЧС] on blacklisted item
    MOCK_ITEMS[61015] = { name="В ЧС на ауке", q=4, ilvl=251, loc="INVTYPE_CHEST", done=false }
    AP.blacklist = AP.blacklist or {}
    AP.blacklist["61015:-1"] = true
    local _ahRow = CreateFrame("Frame", "AP_TestAHRow")
    _ahRow:Show()
    _ahRow.data = { entry = 61015, randProp = 0 }
    local _ahFrame = CreateFrame("Frame", "PrimeAuctionHouseFrame")
    _ahFrame:Show()
    _G.PrimeAH = { frame = _ahFrame, panels = { browse = { IsShown = function() return true end } }, browse = { list = { rows = { _ahRow }, data = { { entry = 61015, minBuy = 1000, qty = 1 } } } } }
    AP:RefreshAuctionHelper()
    assert(_ahRow._apTag and _ahRow._apTag:GetText():find("ЧС", 1, true), "PrimeAH badge must warn [ЧС] on blacklisted item!")
    _ahFrame:Hide()
    _G.PrimeAH = nil
    AP.blacklist["61015:-1"] = nil

    -- Test 18: Valdris Auto-Upgrader (ASMSG_IPROG_OPEN / HELLO / INFO / RESULT, Mor'Kel skip 21, tier resource isolation 13, 3s throttle pipelining, target tier cap)
    _G._TIME = _G._TIME + 5.0
    ResetIBScenario({})
    MOCK_ITEMS[62001] = { name="Кольцо 0/3 (погл.)", q=4, ilvl=245, loc="INVTYPE_FINGER", doneMaxForge=0 }
    MOCK_ITEMS[62002] = { name="Перчатки Мор'Кела 0/3", q=4, ilvl=251, loc="INVTYPE_HAND", doneMaxForge=0 }
    MOCK_ITEMS[62003] = { name="Наплечники 2/3 (нет астр. пыли)", q=4, ilvl=264, loc="INVTYPE_SHOULDER", doneMaxForge=2 }
    MOCK_ITEMS[62004] = { name="Плащ непоглощ. 0/3", q=4, ilvl=251, loc="INVTYPE_CLOAK", done=false, doneMaxForge=-1 }
    local _bag18 = {
        [0] = {
            [1] = "item:62001:0:0:0:0:0:0", -- forge 0, absorbed -> valid 0->1
            [2] = "item:62002:0:0:0:0:0:0", -- forge 0, absorbed -> Mor'Kel status 21 -> skip
            [3] = "item:62003:0:0:0:0:0:0", -- forge 2, absorbed -> lack dust status 13 -> block tier 3, MUST still upgrade 62001!
            [4] = "item:62004:0:0:0:0:0:0", -- unabsorbed -> filtered out locally!
        },
    }
    AP.forgeBag = { [0] = { [1] = 0, [2] = 0, [3] = 2, [4] = 0 } }
    _G.GetContainerNumSlots = function(b) return (b == 0) and 16 or 0 end
    _G.GetContainerItemLink = function(b, s) return _bag18[b] and _bag18[b][s] end
    _G.GetContainerItemInfo = function() return nil, 1, false end

    -- Before ItemProgressFrame opens, StartValdrisAutoUpgrade must refuse
    local okClosed, rClosed = AP:StartValdrisAutoUpgrade()
    assert(okClosed == false and rClosed:find("улучш", 1, true), "Must not upgrade when Progression window is closed! got: " .. tostring(rClosed))

    local _ipf = CreateFrame("Frame", "ItemProgressFrame")
    _ipf:Show()
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IPROG_HELLO", "2:3:3000:120:1:1:1", "WHISPER", "TestHero")
    local _ipf4 = _G.ItemProgressFrame or CreateFrame("Frame", "ItemProgressFrame")
    _ipf4:Show()
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IPROG_OPEN", "1", "WHISPER", "TestHero")
    assert(_G.AP_ValdrisAutoBar and _G.AP_ValdrisAutoBar:IsShown(), "Valdris auto toolbar must attach and show on ItemProgressFrame!")

    -- Scan candidates locally (62004 filtered locally -> 3 items left)
    local cands18, tot18 = AP:GetValdrisCandidates()
    assert(tot18 == 3 and cands18[1].entry == 62002 and cands18[2].entry == 62001 and cands18[3].entry == 62003,
        "Candidates must exclude unabsorbed 62004 and sort tier ASC then ilvl DESC! got tot=" .. tostring(tot18))

    -- Step 1: StartValdrisAutoUpgrade queries 62002 (0:2) -> server returns 21 (Mor'Kel) -> skips & queries 62001 (0:1) -> status 0 -> sends DO!
    _G._SENT_SRV = {}
    local okSt, rSt = AP:StartValdrisAutoUpgrade()
    assert(okSt == true and rSt == "query", "Start must query top candidate 0:2! got: " .. tostring(rSt))
    assert(_G._SENT_SRV[1].prefix == "ACMSG_IPROG_QUERY" and _G._SENT_SRV[1].body == "0:2",
        "First query should be 0:2, got: " .. tostring(_G._SENT_SRV[1].body))

    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IPROG_INFO", "0:2:7702:62002:0:0:1:0:21\t\tПерчатки", "WHISPER", "TestHero")
    _G._TickAll(0.10)
    assert(_G._SENT_SRV[#_G._SENT_SRV].prefix == "ACMSG_IPROG_QUERY" and _G._SENT_SRV[#_G._SENT_SRV].body == "0:1",
        "After Mor'Kel 21, must immediately query 0:1! got: " .. tostring(_G._SENT_SRV[#_G._SENT_SRV].body))

    -- Server confirms 0:1 status 0 with guid 7701 -> immediately sends ACMSG_IPROG_DO "0:1:7701"!
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IPROG_INFO", "0:1:7701:62001:0:0:1:10:0\t70017,5,10\tКольцо", "WHISPER", "TestHero")
    _G._TickAll(0.10)
    assert(_G._SENT_SRV[#_G._SENT_SRV].prefix == "ACMSG_IPROG_DO" and _G._SENT_SRV[#_G._SENT_SRV].body == "0:1:7701",
        "Confirmed item must send ACMSG_IPROG_DO 0:1:7701! got: " .. tostring(_G._SENT_SRV[#_G._SENT_SRV].prefix) .. "=" .. tostring(_G._SENT_SRV[#_G._SENT_SRV].body))

    -- Server returns success RESULT (0:0:1:62001:0:1:8801) -> eagerly sets forgeBag[0][1]=1 and queries 0:3 even during 3.1s DO cooldown!
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IPROG_RESULT", "0:0:1:62001:0:1:8801\tГотово", "WHISPER", "TestHero")
    assert(AP.forgeBag[0][1] == 1 and AP:GetValdrisUpgradeSummary().doneCount == 1, "Success RESULT must bump forgeBag and doneCount!")
    _G._TickAll(0.30)
    assert(_G._SENT_SRV[#_G._SENT_SRV].prefix == "ACMSG_IPROG_QUERY" and _G._SENT_SRV[#_G._SENT_SRV].body == "0:3",
        "During DO throttle cooldown, should already query next candidate 0:3! got: " .. tostring(_G._SENT_SRV[#_G._SENT_SRV].body))

    -- Test tier target limit (maxTier=2) excludes forge>=2 items cleanly (while keeping persistent st=21 item 62002 excluded!)
    AP:StopValdrisAutoUpgrade()
    AP:SetValdrisMaxTier(2)
    AP.forgeBag[0][1] = 2 -- pretend 62001 now forge=2 as well
    local candsMax2Zero, totMax2Zero = AP:GetValdrisCandidates()
    assert(totMax2Zero == 0, "maxTier=2 must exclude forge>=2 and learned st=21 items! got tot=" .. tostring(totMax2Zero))
    MOCK_ITEMS[62001].doneMaxForge = 1
    AP.forgeBag[0][1] = 1 -- forge=1 (absorbed) < maxTier=2 must be eligible while forge=2 (62003) and st=21 (62002) remain excluded
    local candsMax2, totMax2 = AP:GetValdrisCandidates()
    assert(totMax2 == 1 and candsMax2[1].entry == 62001, "maxTier=2 must allow forge<2 and exclude forge>=2! got tot=" .. tostring(totMax2))
    MOCK_ITEMS[62001].doneMaxForge = 0
    AP:SetValdrisMaxTier(3)
    AttuneParserDB.valdrisKnownSkip = nil
    _ipf:Hide()
    _G.ItemProgressFrame = nil
    _G.GetContainerNumSlots = function() return 0 end
    _G.GetContainerItemLink = function() return nil end

    -- Test 19: Valdris Item Picker with icons, Alt+Click (bag & PaperDoll), specialty bag skip, equipped unequip+select, RESULT relocation, PairedSlotSafe 2H guard
    _G._TIME = _G._TIME + 5.0
    ResetIBScenario({})
    MOCK_EQUIP[1] = "item:63001:0:0:0:0:0:0"
    MOCK_ITEMS[63001] = { name="Шлем надетый 0/3", q=4, ilvl=258, loc="INVTYPE_HEAD", doneMaxForge=0 }
    MOCK_ITEMS[63002] = { name="Ботинки в сумке 0/3", q=4, ilvl=245, loc="INVTYPE_FEET", doneMaxForge=0 }
    AP.forgeEquip = { [1] = 0 }
    AP.forgeBag = { [0] = { [1] = 0 }, [1] = {} }
    local _bag19 = {
        [0] = { [1] = "item:63002:0:0:0:0:0:0" }, -- [0][2] empty!
        [1] = {}, -- specialty bag (bagType = 64 e.g. Enchanting bag) must be skipped!
    }
    local _cursorItem = nil
    _G.GetContainerNumSlots = function(b) return (b == 0 or b == 1) and 4 or 0 end
    _G.GetContainerNumFreeSlots = function(b)
        if b == 0 then return 3, 0 end
        if b == 1 then return 4, 64 end
        return 0, 0
    end
    _G.GetContainerItemLink = function(b, s) return _bag19[b] and _bag19[b][s] end
    _G.GetContainerItemInfo = function(b, s) return (_bag19[b] and _bag19[b][s]) and "Interface\\Icons\\INV_Misc_Gear_01" or nil, 1, false end
    _G.CursorHasItem = function() return _cursorItem ~= nil end
    _G.ClearCursor = function() _cursorItem = nil end
    _G.PickupInventoryItem = function(invId)
        local lk = GetInventoryItemLink("player", invId)
        if lk then
            _cursorItem = { from = "inv", invId = invId, link = lk }
            MOCK_EQUIP[invId] = nil
        end
    end
    _G.PickupContainerItem = function(bag, slot)
        if _cursorItem then
            if not _bag19[bag] or not _bag19[bag][slot] then
                _bag19[bag] = _bag19[bag] or {}
                _bag19[bag][slot] = _cursorItem.link
                _cursorItem = nil
                return
            end
        elseif _bag19[bag] and _bag19[bag][slot] then
            _cursorItem = { from = "bag", bag = bag, slot = slot, link = _bag19[bag][slot] }
        end
    end
    _G.IsAltKeyDown = function() return true end
    _G.IsControlKeyDown = function() return false end
    _G.IsShiftKeyDown = function() return false end

    local _dragReceived = nil
    _G.ItemProgressItemSlot = CreateFrame("Button", "ItemProgressItemSlot")
    _G.ItemProgressSlot_OnReceiveDrag = function(self) _dragReceived = _cursorItem and (_cursorItem.bag .. ":" .. _cursorItem.slot) or nil; _G.ClearCursor() end
    _G._bagClickSentinel = function() _G._BAG_CLICK_RAN = true end
    _G.ContainerFrameItemButton_OnClick = _G._bagClickSentinel
    _G.ContainerFrameItemButton_OnModifiedClick = function() _G._RB_CALLED = true end
    _G.PaperDollItemSlotButton_OnModifiedClick = function() end
    _G._RB_CALLED = false

    local _ipf19 = CreateFrame("Frame", "ItemProgressFrame")
    _ipf19:Show()
    local _ipf4 = _G.ItemProgressFrame or CreateFrame("Frame", "ItemProgressFrame")
    _ipf4:Show()
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IPROG_OPEN", "1", "WHISPER", "TestHero")

    -- Security/taint check: AttuneParser MUST NOT overwrite _G.ContainerFrameItemButton_OnClick!
    assert(_G.ContainerFrameItemButton_OnClick == _G._bagClickSentinel,
        "AttuneParser MUST NOT overwrite _G.ContainerFrameItemButton_OnClick (taints SpellCanTargetItem/Расщепление)!")

    -- Picker items must include BOTH equipped 63001 and bag 63002 with icons!
    local pickList = AP:GetValdrisPickerItems("all", "")
    local sawEq, sawBag = false, false
    for _, it in ipairs(pickList) do
        if it.isEquipped and it.eid == 63001 and it.tex then sawEq = true end
        if not it.isEquipped and it.eid == 63002 and it.tex then sawBag = true end
    end
    assert(sawEq and sawBag, "Valdris picker list must include both equipped and bag items with icons!")

    -- Toggle Picker UI open & verify rows populated
    AP_ValdrisAutoBar.pickBtn:GetScript("OnClick")(AP_ValdrisAutoBar.pickBtn, "LeftButton")
    assert(_G.AP_ValdrisPickerFrame and _G.AP_ValdrisPickerFrame:IsShown(), "Clicking pickBtn must open AP_ValdrisPickerFrame!")

    -- While SpellIsTargeting() (e.g. Расщепление), Alt+Click must NOT steal click into Valdris!
    local _bagFrame0 = { GetID = function() return 0 end }
    local _bagBtn1 = { GetParent = function() return _bagFrame0 end, GetID = function() return 1 end }
    _G.SpellIsTargeting = function() return true end
    ContainerFrameItemButton_OnModifiedClick(_bagBtn1, "LeftButton")
    assert(_dragReceived == nil, "SpellIsTargeting() active must prevent Valdris Alt+Click hijack!")
    _G.SpellIsTargeting = function() return false end

    -- Normal Alt+Click bag item -> selects via hooksecurefunc(ContainerFrameItemButton_OnModifiedClick) without taint
    ContainerFrameItemButton_OnModifiedClick(_bagBtn1, "LeftButton")
    assert(_dragReceived == "0:1", "Alt+LMB bag item must select 0:1 in Valdris! got=" .. tostring(_dragReceived))

    -- Alt+Click PaperDoll HeadSlot (inv 1) -> must skip Enchanting Bag 1, unequip into normal bag [0][2], pause ibAutoEquip, and select 0:2!
    _dragReceived = nil
    local _pdBtnHead = { GetID = function() return 1 end }
    PaperDollItemSlotButton_OnModifiedClick(_pdBtnHead, "LeftButton")
    assert(_bag19[0][2] == "item:63001:0:0:0:0:0:0" and not _bag19[1][1] and _dragReceived == "0:2",
        "Equipped item must unequip into general bag 0:2 (skipping specialty bag 1) and fill Valdris slot! got=" .. tostring(_dragReceived))
    AP:SetSetting("ibAutoEquip", true)
    local canEqVal, reasonEqVal = AP:CanItemBankAutoEquipNow(false)
    assert(canEqVal == false and reasonEqVal == "valdris", "Auto-equip must pause briefly after unequipping item to Valdris! got=" .. tostring(reasonEqVal))
    AP:SetSetting("ibAutoEquip", false)

    -- Result relocation check: upgrade [0][2], server moves item to [0][3] -> forgeBag clears stale [0][2] and updates [0][3]=1!
    AP.forgeBag[0][2] = 0
    _G._SENT_SRV = {}
    _G._TIME = _G._TIME + 5.0
    AP:StartValdrisAutoUpgrade() -- [0][2] 63001 or [0][1] 63002; head 63001 has ilvl 258 > 245 so [0][2] first!
    assert(_G._SENT_SRV[1].body == "0:2", "Expected ilvl 258 unequipped helm 0:2 first, got: " .. tostring(_G._SENT_SRV[1].body))
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IPROG_INFO", "0:2:9901:63001:0:0:1:10:0\t\tШлем", "WHISPER", "TestHero")
    _G._TickAll(0.10)
    -- Simulate server relocating recreated 63001 from 0:2 -> 0:3!
    _bag19[0][2] = nil
    _bag19[0][3] = "item:63001:0:0:0:0:0:0"
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IPROG_RESULT", "0:0:3:63001:0:1:9902\tГотово", "WHISPER", "TestHero")
    assert(AP.forgeBag[0][2] == nil and AP.forgeBag[0][3] == 1,
        "ASMSG_IPROG_RESULT relocation must clear empty 0:2 and set 0:3=1! got 0:2=" .. tostring(AP.forgeBag[0][2]) .. " 0:3=" .. tostring(AP.forgeBag[0][3]))
    AP:StopValdrisAutoUpgrade()

    -- Bank item picker & ACMSG_IB_TAKE -> bag slot -> Валдрис selection test!
    ResetIBScenario({
        { guid = 7771, entry = 63005, forge = 2, flags = 49, link = "item:63005:0:0:0:0:0:0" },
    })
    MOCK_ITEMS[63005] = { name="Кольцо из ИБ 2/3", q=4, ilvl=264, loc="INVTYPE_FINGER", doneMaxForge=2 }
    _bag19 = { [0] = {}, [1] = {} }
    AP.forgeBag = { [0] = {}, [1] = {} }
    local bankList = AP:GetValdrisPickerItems("bank", "")
    assert(#bankList == 1 and bankList[1].isBank and bankList[1].ibGuid == 7771 and bankList[1].forge == 2,
        "Picker bank filter must list Item Bank item 63005! got=" .. tostring(#bankList))
    _dragReceived = nil
    _G._SENT_ADDON = {}
    local okBk, rBk = AP:PickBankItemForValdris(7771, "item:63005:0:0:0:0:0:0", 2)
    assert(okBk and rBk == "waiting_bag", "PickBankItemForValdris must send ACMSG_IB_TAKE and wait for BAG_UPDATE! got=" .. tostring(rBk))
    assert(_G._SENT_ADDON[1].prefix == "ACMSG_IB_TAKE" and _G._SENT_ADDON[1].body == "7771", "Expected ACMSG_IB_TAKE 7771")
    -- Simulate server delivering 63005 into bag [0][3] via BAG_UPDATE!
    _bag19[0][3] = "item:63005:0:0:0:0:0:0"
    _G._FireEvent("BAG_UPDATE", 0)
    assert(AP.forgeBag[0][3] == 2 and _dragReceived == "0:3",
        "Bank item take + BAG_UPDATE must sync forgeBag=2 and select 0:3 in Valdris! got drag=" .. tostring(_dragReceived) .. " forge=" .. tostring(AP.forgeBag[0][3]))

    -- Test 20: Mor'Kel exact 855-item catalog (T9 843..880 + T10 883..901, incl. 48640 Turalyon Triumph gloves + uncached Bank IB + persistent 21 cache) & Auto-Upgrade pull/return
    do
        local mkCount = 0
        for _ in pairs(AP.MORKEL_ITEMS or {}) do mkCount = mkCount + 1 end
        assert(mkCount == 855, "Expected exact 855 Mor'Kel T9/T10 items in AP.MORKEL_ITEMS! got=" .. tostring(mkCount))
        assert(AP.MORKEL_ITEMS[48640] and AP.MORKEL_ITEMS[47753] and AP.MORKEL_ITEMS[48250] and AP.MORKEL_ITEMS[50094] and AP.MORKEL_ITEMS[51284],
            "Key T9/T10 items (incl. 48640) must be present in AP.MORKEL_ITEMS!")
    end
    _G._TIME = _G._TIME + 5.0
    ResetIBScenario({
        { guid = 8801, entry = 48640, forge = 0, flags = 49, link = "item:48640:0:0:0:0:0:0" }, -- Mor'Kel T9 Turalyon Triumph gloves in IB -> skipped BEFORE ACMSG_IB_TAKE!
        { guid = 8803, entry = 50094, forge = 0, flags = 49, link = "item:50094:0:0:0:0:0:0" }, -- Uncached Mor'Kel T10 item in IB (no MOCK_ITEMS!) -> still classified morkel & skipped without warm!
        { guid = 8802, entry = 63021, forge = 0, flags = 49, link = "item:63021:0:0:0:0:0:0" }, -- Non-set wrist in IB -> auto-pulled, upgraded 0->1, then returned to IB!
    })
    MOCK_ITEMS[48640] = { name="Боевые рукавицы триумфа Туралиона", q=4, ilvl=245, loc="INVTYPE_HAND", doneMaxForge=0 }
    MOCK_ITEMS[63021] = { name="Наручи несетовые", q=4, ilvl=264, loc="INVTYPE_WRIST", doneMaxForge=0 }
    MOCK_ITEMS[63022] = { name="Особый пояс 21", q=4, ilvl=251, loc="INVTYPE_WAIST", doneMaxForge=0 }

    _bag19 = { [0] = { [1] = "item:63022:0:0:0:0:0:0" }, [1] = {} }
    AP.forgeBag = { [0] = { [1] = 0 }, [1] = {} }
    AttuneParserDB.valdrisKnownSkip = nil

    -- Direct Bank/Equipped/Bag guards must refuse Mor'Kel 48640 without ACMSG_IB_TAKE, unequip, or slot selection!
    _G._SENT_ADDON = {}
    local okBkMk, rBkMk = AP:PickBankItemForValdris(8801, "item:48640:0:0:0:0:0:0", 0)
    assert(okBkMk == false and tostring(rBkMk):find("другой мастер", 1, true) and #_G._SENT_ADDON == 0,
        "PickBankItemForValdris must refuse Mor'Kel 48640 before ACMSG_IB_TAKE! got=" .. tostring(rBkMk))
    local oldEq10 = MOCK_EQUIP[10]
    MOCK_EQUIP[10] = "item:48640:0:0:0:0:0:0"
    _dragReceived = nil
    local okEqMk, rEqMk = AP:PickEquippedItemForValdris(10)
    assert(okEqMk == false and tostring(rEqMk):find("другой мастер", 1, true) and MOCK_EQUIP[10] == "item:48640:0:0:0:0:0:0" and _dragReceived == nil,
        "PickEquippedItemForValdris must refuse equipped Mor'Kel 48640 without unequipping! got=" .. tostring(rEqMk))
    MOCK_EQUIP[10] = oldEq10
    _bag19[0][2] = "item:48640:0:0:0:0:0:0"
    local okBgMk, rBgMk = AP:PickBagItemForValdris(0, 2)
    assert(okBgMk == false and tostring(rBgMk):find("другой мастер", 1, true) and _dragReceived == nil,
        "PickBagItemForValdris must refuse bag Mor'Kel 48640 on Progression tab! got=" .. tostring(rBgMk))
    _bag19[0][2] = nil

    -- Check Picker hides Mor'Kel items (48640 & uncached 50094) completely on Progression tab AND GetValdrisCandidates excludes both!
    local pk20 = AP:GetValdrisPickerItems("bank", "")
    local mkFound, nonMkFound = false, false
    for _, it in ipairs(pk20) do
        if it.eid == 48640 or it.eid == 50094 then mkFound = true end
        if it.eid == 63021 then nonMkFound = true end
    end
    assert(not mkFound and nonMkFound,
        "Mor'Kel items (48640 / 50094) must NOT be shown in Valdris Picker list while non-Morkel 63021 stays! mkFound=" .. tostring(mkFound))

    local cands20, tot20, warm20 = AP:GetValdrisCandidates(1) -- maxTier=1
    assert(tot20 == 2 and not warm20 and cands20[1].eid == 63022 and cands20[2].isBank and cands20[2].eid == 63021,
        "Candidates must exclude Mor'Kel 48640/50094 without warming and put bag 63022 before bank 63021! got tot=" .. tostring(tot20) .. " warm=" .. tostring(warm20))

    -- Check Forge icon badges/borders ("как в сумке или на герое сразу") & UTF-8 safe item name display in AP_ValdrisPickerFrame!
    MOCK_ITEMS[63024] = { name="Перстень закаленного воина", q=4, ilvl=258, loc="INVTYPE_FINGER", doneMaxForge=1 }
    MOCK_ITEMS[63025] = { name="Наплечные щитки триумфального повелителя длинного имени Плети", q=4, ilvl=251, loc="INVTYPE_SHOULDER", doneMaxForge=0 }
    _bag19[0][2] = "item:63024:0:0:0:0:0:0"
    _bag19[0][3] = "item:63025:0:0:0:0:0:0"
    AP.forgeBag[0][2] = 1 -- Epic tier 1!
    local _ipf4 = _G.ItemProgressFrame or CreateFrame("Frame", "ItemProgressFrame")
    _ipf4:Show()
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IPROG_OPEN", "1", "WHISPER", "TestHero")
    if _G.AP_ValdrisAutoBar and _G.AP_ValdrisAutoBar.pickBtn and _G.AP_ValdrisAutoBar.pickBtn._scripts and _G.AP_ValdrisAutoBar.pickBtn._scripts.OnClick then
        _G.AP_ValdrisAutoBar.pickBtn._scripts.OnClick(_G.AP_ValdrisAutoBar.pickBtn, "LeftButton")
    end
    local pf20 = _G.AP_ValdrisPickerFrame
    assert(pf20 and pf20:IsShown() and pf20.rows[1], "Picker must open on pickBtn click!")
    local forgedRow, fullCyrRow, longCropRow, anyMkRow = nil, nil, nil, false
    for ri = 1, 8 do
        local rw = pf20.rows[ri]
        if rw and rw:IsShown() and rw.itemData then
            if rw.itemData.eid == 48640 or rw.itemData.eid == 50094 then anyMkRow = true end
            if rw.itemData.eid == 63024 then forgedRow = rw; fullCyrRow = rw.nameFs:GetText()
            elseif rw.itemData.eid == 63025 then longCropRow = rw.nameFs:GetText() end
        end
    end
    assert(not anyMkRow, "UI Picker rows must not render Mor'Kel items on Progression tab!")
    assert(fullCyrRow == "Перстень закаленного воина", "Clean name without [T1] clutter must stay intact! got=" .. tostring(fullCyrRow))
    assert(forgedRow and forgedRow.forgeBadge and forgedRow.forgeBadge:IsShown()
        and tostring(forgedRow.forgeBadge._tex):find("attune_epic", 1, true),
        "Forged item in Picker must render Custom_Attune attune_epic corner badge!")
    assert(forgedRow.absChk and forgedRow.absChk:IsShown(), "Ready/absorbed item must show ReadyCheck checkmark on icon!")
    assert(forgedRow.iconBox and forgedRow.iconBox._borderColor and math.abs(forgedRow.iconBox._borderColor[1] - 0.733) < 0.02,
        "Forged item border must match Epic tier color!")
    assert(forgedRow.subFs:GetText():find("Эпический", 1, true), "Sub-line must label current forge tier Эпический!")
    -- Test live FORGE_UPDATED sync bumps 63024 from Epic (1) -> Legendary (2) immediately in open Picker!
    MOCK_ITEMS[63024].doneMaxForge = 2
    AP.forgeBag[0][2] = 2
    AP:Fire("FORGE_UPDATED", "ASMSG_FORGE_MAP")
    local forgedRow2 = nil
    for ri = 1, 8 do
        local rw = pf20.rows[ri]
        if rw and rw:IsShown() and rw.itemData and rw.itemData.eid == 63024 then forgedRow2 = rw; break end
    end
    assert(forgedRow2 and forgedRow2.forgeBadge._tex and tostring(forgedRow2.forgeBadge._tex):find("attune_legendary", 1, true),
        "FORGE_UPDATED must immediately update Picker corner badge to attune_legendary!")
    assert(forgedRow2.subFs:GetText():find("Легендарный", 1, true), "Sub-line must update to Легендарный!")
    -- Check longCropRow ends with '..' on a clean UTF-8 boundary (each continuation byte 128..191 follows lead byte)
    assert(longCropRow and longCropRow:sub(-2) == "..", "Overlong name must end with '..'! got=" .. tostring(longCropRow))
    local cutPrefix = longCropRow:sub(1, #longCropRow - 2)
    local lastByte = cutPrefix:byte(#cutPrefix)
    assert(not (lastByte >= 192), "UTF-8 lead byte must NEVER be left dangling before '..'! lastByte=" .. tostring(lastByte))
    pf20:Hide()
    _bag19[0][2] = nil
    _bag19[0][3] = nil
    AP.forgeBag[0][2] = nil

    -- Step 1: starts with 63022 -> server returns st=21 (Mor'Kel) -> persists valdrisKnownSkip[63022]=21, then pulls 63021 from IB!
    AP:SetValdrisMaxTier(1)
    _G._SENT_SRV = {}
    _G._SENT_ADDON = {}
    AP:StartValdrisAutoUpgrade()
    assert(_G._SENT_SRV[1].prefix == "ACMSG_IPROG_QUERY" and _G._SENT_SRV[1].body == "0:1", "Expected query 0:1 first")
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IPROG_INFO", "0:1:9022:63022:0:0:1:0:21\t\tПояс", "WHISPER", "TestHero")
    assert(AttuneParserDB.valdrisKnownSkip and AttuneParserDB.valdrisKnownSkip[63022] == 21, "st=21 must persist in valdrisKnownSkip!")
    _G._TickAll(0.02)
    -- Now Auto-Upgrade should have pulled 8802 (63021) via ACMSG_IB_TAKE!
    assert(_G._SENT_ADDON[#_G._SENT_ADDON].prefix == "ACMSG_IB_TAKE" and _G._SENT_ADDON[#_G._SENT_ADDON].body == "8802",
        "Auto-Upgrade must automatically take 8802 from Item Bank! got=" .. tostring(_G._SENT_ADDON[#_G._SENT_ADDON].prefix))
    -- Deliver 63021 to [0][2], query -> status 0 -> immediately sends DO -> RESULT -> stop -> returns 0:2 via ACMSG_IB_PUT "255:24"!
    _G.PRIME_ItemBank.items = { { guid = 8801, entry = 48640, forge = 0, flags = 49, link = "item:48640:0:0:0:0:0:0" } }
    _bag19[0][2] = "item:63021:0:0:0:0:0:0"
    _G._FireEvent("BAG_UPDATE", 0)
    _G._TickAll(0.02)
    assert(_G._SENT_SRV[#_G._SENT_SRV].prefix == "ACMSG_IPROG_QUERY" and _G._SENT_SRV[#_G._SENT_SRV].body == "0:2",
        "After IB item arrives in 0:2, must query 0:2! got=" .. tostring(_G._SENT_SRV[#_G._SENT_SRV].body))
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IPROG_INFO", "0:2:9021:63021:0:0:1:10:0\t\tНаручи", "WHISPER", "TestHero")
    assert(_G._SENT_SRV[#_G._SENT_SRV].prefix == "ACMSG_IPROG_DO" and _G._SENT_SRV[#_G._SENT_SRV].body == "0:2:9021",
        "When cooldown elapsed, INFO st=0 must immediately fire ACMSG_IPROG_DO without extra tick delay! got=" .. tostring(_G._SENT_SRV[#_G._SENT_SRV].prefix))
    local doSentAt20 = _G._TIME
    _G._TIME = _G._TIME + 0.15
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IPROG_RESULT", "0:0:2:63021:0:1:9099\tГотово", "WHISPER", "TestHero")
    assert(AP.serverSync.valdris.nextDoAt and math.abs(AP.serverSync.valdris.nextDoAt - (doSentAt20 + 3.04)) < 0.05,
        "Cooldown nextDoAt must anchor to DO send time (not delayed RESULT arrival)! got diff=" .. tostring((AP.serverSync.valdris.nextDoAt or 0) - doSentAt20))
    _G._TickAll(0.02)
    assert(AP.forgeBag[0][2] == 1 and _G._SENT_ADDON[#_G._SENT_ADDON].prefix == "ACMSG_IB_PUT" and _G._SENT_ADDON[#_G._SENT_ADDON].body == "255:24",
        "Done bank item 0:2 must return immediately via ACMSG_IB_PUT 255:24! got=" .. tostring(_G._SENT_ADDON[#_G._SENT_ADDON].prefix) .. ":" .. tostring(_G._SENT_ADDON[#_G._SENT_ADDON].body))

    AP:SetValdrisMaxTier(3)
    AttuneParserDB.valdrisKnownSkip = nil

    -- Check CanItemBankAutoEquipNow waits while pendingBankReturn is active (even if window just closed!)
    AP:SetSetting("ibAutoEquip", true)
    _ipf19:Hide()
    AP.serverSync.valdris.pendingBankReturn = { entry = 63021, bag = 0, slot = 2, at = _G._TIME }
    local okAE, rAE = AP:CanItemBankAutoEquipNow(false)
    assert(not okAE and rAE == "valdris", "AutoEquip must wait for Valdris pendingBankReturn! got " .. tostring(rAE))
    AP.serverSync.valdris.pendingBankReturn = nil
    AP:SetSetting("ibAutoEquip", false)
    _ipf19:Show()

    -- Bugfix test: PairedSlotSafe 2H weapon in bag must NOT break unabsorbed Off-Hand/Shield (non-TG)!
    ResetIBScenario({})
    MOCK_EQUIP[16] = "item:63010:0:0:0:0:0:0"
    MOCK_EQUIP[17] = "item:63011:0:0:0:0:0:0"
    MOCK_ITEMS[63010] = { name="Меч 1H погл.", q=4, ilvl=245, loc="INVTYPE_WEAPON", doneMaxForge=0 }
    MOCK_ITEMS[63011] = { name="Щит непогл.", q=4, ilvl=245, loc="INVTYPE_SHIELD", done=false, doneMaxForge=-1 }
    MOCK_ITEMS[63012] = { name="Двуруч непогл.", q=4, ilvl=264, loc="INVTYPE_2HWEAPON", done=false, doneMaxForge=-1 }
    _bag19 = { [0] = { [1] = "item:63012:0:0:0:0:0:0" } }
    AP.forgeBag = { [0] = { [1] = 0 } }
    _G.IsAltKeyDown = function() return false end
    _ipf19:Hide()
    _G.ItemProgressFrame = nil
    _G._TIME = _G._TIME + 5.0
    AP:SetSetting("ibAutoEquip", true)
    local ok2H, r2H = AP:RunItemBankAutoEquip(false)
    assert(not ok2H and (r2H == "no_candidates" or r2H == "ib_empty") and GetInventoryItemLink("player", 17) == "item:63011:0:0:0:0:0:0",
        "2H weapon in bag must NOT unequip unabsorbed Shield in SecondaryHandSlot! got ok=" .. tostring(ok2H) .. " r=" .. tostring(r2H))
    AP:SetSetting("ibAutoEquip", false)

    _G.GetContainerNumSlots = function() return 0 end
    _G.GetContainerNumFreeSlots = nil
    _G.GetContainerItemLink = function() return nil end

    -- Suite 21: Pass 3 Audit Regressions (CustomAttuneAbsorbedTier -1, TG EvaluateIBPlan & Staff PairedSlotSafe, IBRes pendingBankReturn/Take, alertOn)
    -- 21a: TalorianTP_ScanAbsorbedItems with CustomAttuneAbsorbedTier == -1 MUST NOT treat item as absorbed!
    MOCK_ITEMS[77001] = { name="Непогл. грудак", q=4, ilvl=245, loc="INVTYPE_CHEST", done=false, doneMaxForge=-1 }
    MOCK_ITEMS[77002] = { name="Лег. шлем", q=4, ilvl=264, loc="INVTYPE_HEAD", done=true, doneMaxForge=2 }
    local _origAbsTier = _G.CustomAttuneAbsorbedTier
    local _origProg = _G.CustomAttuneProgress
    local _origTierFn = _G.CustomAttuneTier
    local _origPac = _G.PrimeAttuneCore
    _G.CustomAttuneProgress = nil
    _G.CustomAttuneTier = nil
    _G.CustomAttuneAbsorbedTier = function(eid, sfx)
        if eid == 77001 then return -1 end
        if eid == 77002 then return 2 end
        return -1
    end
    _G.PrimeAttuneCore = { absorbedCache = {}, forgeTierCache = {} }
    local _bag21 = { [0] = { [1] = "item:77001:0:0:0:0:0:0", [2] = "item:77002:0:0:0:0:0:0" } }
    _G.GetContainerNumSlots = function(b) return (b == 0) and 16 or 0 end
    _G.GetContainerItemLink = function(b, s) return _bag21[b] and _bag21[b][s] end
    AP.forgeBag = { [0] = { [1] = 0, [2] = 2 } }
    local _origSrvSt = AP.GetItemServerStatus
    AP.GetItemServerStatus = function(self, eid, sfx)
        if eid == 77001 or eid == 77002 then return nil end
        if _origSrvSt then return _origSrvSt(self, eid, sfx) end
        return nil
    end
    TalorianTP_ScanAbsorbedItems()
    assert(_G.PrimeAttuneCore.absorbedCache[77001] == nil, "CustomAttuneAbsorbedTier(-1) MUST NOT mark item 77001 absorbed!")
    assert(_G.PrimeAttuneCore.forgeTierCache[77001] == nil, "CustomAttuneAbsorbedTier(-1) MUST NOT cache forgeTier for 77001!")
    assert(_G.PrimeAttuneCore.forgeTierCache[77002] == 3,
        "Absorbed tier 2 item 77002 must cache uiTier=3 (Legend), got " .. tostring(_G.PrimeAttuneCore.forgeTierCache[77002]))
    AP.GetItemServerStatus = _origSrvSt
    _G.CustomAttuneAbsorbedTier = _origAbsTier
    _G.CustomAttuneProgress = _origProg
    _G.CustomAttuneTier = _origTierFn
    _G.PrimeAttuneCore = _origPac
    _G.GetContainerNumSlots = function() return 0 end
    _G.GetContainerItemLink = function() return nil end

    -- 21b: EvaluateIBPlan supports Warrior Titan's Grip 2H in SecondaryHandSlot AND PairedSlotSafe blocks 2H Staff when OH busy!
    _G._TIME = _G._TIME + 5.0
    local _origKnown21 = _G.IsSpellKnown
    local _origPlSp21 = _G.IsPlayerSpell
    _G.IsSpellKnown = function() return false end
    _G.IsPlayerSpell = function(sp) return sp == 46917 end
    ResetIBScenario({
        { guid = 9701, entry = 60033, forge = 0, flags = 49, link = "item:60033:0:0:0:0:0:0" }, -- Двуручные мечи
        { guid = 9702, entry = 60032, forge = 0, flags = 49, link = "item:60032:0:0:0:0:0:0" }, -- Посохи (not TG!)
    })
    MOCK_EQUIP[16] = "item:60030:0:0:0:0:0:0" -- busy MH 2H
    MOCK_EQUIP[17] = nil                     -- empty OH
    MOCK_ITEMS[60030].done = false
    MOCK_ITEMS[60032].done = false
    MOCK_ITEMS[60033].done = false
    AP:SetSetting("ibAutoEquip", true)
    local ok21b, r21b, c21b = AP:RunItemBankAutoEquip(true)
    assert(ok21b == true and c21b and c21b.guid == 9701,
        "EvaluateIBPlan must equip TG 2H sword 9701 into empty OH, skipping Staff 9702! got ok=" .. tostring(ok21b) .. " r=" .. tostring(r21b))

    _G._TIME = _G._TIME + 5.0
    MOCK_ITEMS[60034] = { name="Меч 1H погл.", q=4, ilvl=232, loc="INVTYPE_WEAPON", done=true }
    ResetIBScenario({
        { guid = 9703, entry = 60032, forge = 0, flags = 49, link = "item:60032:0:0:0:0:0:0" }, -- Посох
    })
    MOCK_EQUIP[16] = "item:60034:0:0:0:0:0:0" -- replaceable MH
    MOCK_EQUIP[17] = "item:63011:0:0:0:0:0:0" -- busy Shield in OH!
    local ok21b2, r21b2 = AP:RunItemBankAutoEquip(true)
    assert(not ok21b2 and r21b2 == "no_candidates",
        "PairedSlotSafe must reject 2H Staff from IB when Warrior has TG + busy OH shield! got " .. tostring(ok21b2) .. " r=" .. tostring(r21b2))
    AP:SetSetting("ibAutoEquip", false)
    _G.IsSpellKnown = _origKnown21
    _G.IsPlayerSpell = _origPlSp21

    -- 21c: SS.onIBRes Valdris pendingBankReturn & pendingBankTake fail + GetDisperseSummary alertOn=false
    AP.serverSync.valdris.pendingBankReturn = { entry = 63021, bag = 0, slot = 2, at = _G._TIME }
    AP.serverSync.valdris.running = false
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "0\tput", "WHISPER", "TestHero")
    assert(AP.serverSync.valdris.pendingBankReturn == nil, "ASMSG_IB_RES put ok must clear Valdris pendingBankReturn!")

    AP.serverSync.valdris.pendingBankTake = { guid = 9901, entry = 63021, forge = 1, at = _G._TIME }
    AP.serverSync.valdris.skip = {}
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IB_RES", "5\tНет места", "WHISPER", "TestHero")
    assert(AP.serverSync.valdris.pendingBankTake == nil and AP.serverSync.valdris.skip["ib:9901:1"] == 5,
        "ASMSG_IB_RES failed take must mark ib:9901:1 in valdris.skip!")

    local _origDspAlert = _G.PRIME_Disperse.alertOn
    _G.PRIME_Disperse.alertOn = false
    assert(AP:GetDisperseSummary().alertOn == false, "GetDisperseSummary must respect PRIME_Disperse.alertOn == false!")
    _G.PRIME_Disperse.alertOn = _origDspAlert

    return "ALL_21_SUITES_PASSED"
    ''')
    print("LUPA RESULT:", res)
    assert res == "ALL_21_SUITES_PASSED"
    run_suite_21de(lua)
    res21f = lua.execute(r'''
    -- 21f: TalorianTP windows register once in UISpecialFrames and clear EditBox focus cleanly for ESC
    local ui21f = TalorianTP:OpenUI(4)
    assert(ui21f and ui21f:IsShown() and _G.TalorianMainFrame == ui21f, "TalorianMainFrame must open")
    if _G.TalorianBugLinkEditBox and _G.TalorianBugLinkEditBox.SetFocus then
        _G.TalorianBugLinkEditBox:SetFocus()
        assert(_G.TalorianBugLinkEditBox:HasFocus() == true)
    end
    ui21f:SwitchTab(1)
    if _G.TalorianBugLinkEditBox and _G.TalorianBugLinkEditBox.HasFocus then
        assert(_G.TalorianBugLinkEditBox:HasFocus() == false, "Switching tab must clear bugEdit focus!")
    end
    if TalorianTP_ToggleAnalysisWindow then TalorianTP_ToggleAnalysisWindow() end
    if TalorianTP_ToggleTopWindow then TalorianTP_ToggleTopWindow() end
    local seenSpecial = {}
    for _, nm in ipairs(_G.UISpecialFrames or {}) do
        seenSpecial[nm] = (seenSpecial[nm] or 0) + 1
    end
    assert(seenSpecial["TalorianMainFrame"] == 1, "TalorianMainFrame must be registered once in UISpecialFrames!")
    assert(seenSpecial["TalorianAnalysisFrame"] == 1, "TalorianAnalysisFrame must be registered once in UISpecialFrames!")
    assert(seenSpecial["TalorianTopFrame"] == 1, "TalorianTopFrame must be registered once in UISpecialFrames!")
    assert(_G.TalorianAnalysisFrame:IsShown() and _G.TalorianTopFrame:IsShown(), "Analysis & Top windows must open cleanly")
    -- Re-focus on tab 4 then simulate ESC CloseSpecialWindows()
    ui21f:SwitchTab(4)
    if _G.TalorianBugLinkEditBox and _G.TalorianBugLinkEditBox.SetFocus then _G.TalorianBugLinkEditBox:SetFocus() end
    for _, nm in ipairs(_G.UISpecialFrames or {}) do
        local fr = _G[nm]
        if fr and fr:IsShown() then fr:Hide() end
    end
    assert(not ui21f:IsShown(), "ESC CloseSpecialWindows must hide TalorianMainFrame!")
    assert(not _G.TalorianAnalysisFrame:IsShown(), "ESC CloseSpecialWindows must hide TalorianAnalysisFrame!")
    assert(not _G.TalorianTopFrame:IsShown(), "ESC CloseSpecialWindows must hide TalorianTopFrame!")
    if _G.TalorianBugLinkEditBox and _G.TalorianBugLinkEditBox.HasFocus then
        assert(_G.TalorianBugLinkEditBox:HasFocus() == false, "Hiding TalorianMainFrame must clear bugEdit focus!")
    end

    -- 21i: Z-order priority (RaiseFrameFront), Tab 1 & Tab 5 UI polish, and Interactive Zone/Dungeon Item Explorer
    local function tickUpdates21i()
        for _, fr in ipairs(_G._FRAMES) do
            if fr and fr:IsShown() and fr._scripts and fr._scripts.OnUpdate then
                fr._scripts.OnUpdate(fr, 0.05)
            end
        end
    end

    local ui21i = TalorianTP:OpenUI(1)
    assert(ui21i:GetWidth() == 896, "21i: TalorianMainFrame must be widened to 896, got=" .. tostring(ui21i:GetWidth()))
    tickUpdates21i()

    -- Simulate clicking atlasBtn while TalorianMainFrame had Toplevel focus
    ui21i:Raise()
    AttuneParser:OpenUI("top")
    tickUpdates21i()
    assert(_G.AttuneParserFrame and _G.AttuneParserFrame:IsShown(), "21i: AttuneParserFrame must show")
    assert((_G.AttuneParserFrame._raisedAt or 0) > (ui21i._raisedAt or 0),
        "21i: AttuneParserFrame must raise ABOVE TalorianMainFrame on open!")

    -- Already-open buried window must still rise on re-open
    ui21i:Raise()
    AttuneParser:OpenUI("top")
    tickUpdates21i()
    assert((_G.AttuneParserFrame._raisedAt or 0) > (ui21i._raisedAt or 0),
        "21i: Already-shown AttuneParserFrame must raise ABOVE TalorianMainFrame!")

    -- Symmetrically opening Talorian from AttuneParser must raise TalorianMainFrame on top
    AttuneParser:OpenTalorianUI()
    tickUpdates21i()
    assert((ui21i._raisedAt or 0) > (_G.AttuneParserFrame._raisedAt or 0),
        "21i: OpenTalorianUI must raise TalorianMainFrame ABOVE AttuneParserFrame!")

    -- Opening Analysis/Explorer must raise TalorianAnalysisFrame above TalorianMainFrame
    ui21i:Raise()
    TalorianTP_ToggleAnalysisWindow()
    tickUpdates21i()
    local af21i = _G.TalorianAnalysisFrame
    assert(af21i and af21i:IsShown() and (af21i._raisedAt or 0) > (ui21i._raisedAt or 0),
        "21i: TalorianAnalysisFrame must raise ABOVE TalorianMainFrame!")

    -- Verify Interactive Zone/Dungeon Item Explorer populates both left zones and right zone items
    assert(af21i.zoneRows and af21i.zoneRows[1] and af21i.zoneRows[1]:IsShown() and af21i.zoneRows[1].zoneRec,
        "21i: Explorer must populate left raid/dungeon rows!")
    local selTit = af21i.selTitle and af21i.selTitle:GetText() or ""
    assert(selTit:find("Цитадель Ледяной Короны", 1, true),
        "21i: Explorer must default-select active targetRaid! got=" .. tostring(selTit))
    -- Switch status filter to "all" so ICC items appear even if absorbed
    local allStatusBtn = nil
    for _, sb in ipairs(af21i.statusBtns or {}) do
        if sb.id == "all" then allStatusBtn = sb end
    end
    assert(allStatusBtn and allStatusBtn._scripts and allStatusBtn._scripts.OnClick, "21i: expected 'all' status button")
    allStatusBtn._scripts.OnClick(allStatusBtn, "LeftButton")
    assert(af21i.itemRows and af21i.itemRows[1] and af21i.itemRows[1]:IsShown() and af21i.itemRows[1].itemData,
        "21i: Explorer must show interactive item rows in right pane for selected instance!")
    -- Hover row safely triggers GameTooltip without errors
    if af21i.itemRows[1]._scripts and af21i.itemRows[1]._scripts.OnEnter then
        af21i.itemRows[1]._scripts.OnEnter(af21i.itemRows[1])
    end
    -- Click second zone on left and set as Talorian target
    if af21i.zoneRows[2] and af21i.zoneRows[2]:IsShown() and af21i.zoneRows[2]._scripts and af21i.zoneRows[2]._scripts.OnClick then
        local z2Name = af21i.zoneRows[2].zoneRec.dest.name
        af21i.zoneRows[2]._scripts.OnClick(af21i.zoneRows[2])
        assert((af21i.selTitle:GetText() or ""):find(z2Name, 1, true), "21i: clicking zone row must switch selected zone!")
        if af21i.targetBtn and af21i.targetBtn._scripts and af21i.targetBtn._scripts.OnClick then
            af21i.targetBtn._scripts.OnClick(af21i.targetBtn)
            assert(TalorianTP_DB.targetRaid == z2Name, "21i: targetBtn must set TalorianTP_DB.targetRaid!")
        end
    end
    af21i:Hide()
    _G.AttuneParserFrame:Hide()

    -- Tab 5 polish checks: Pepe skin/perk labels, Russian gold format, accurate U torgovtsa label, no old jargon
    ui21i:SwitchTab(5)
    assert(ui21i.tabs and ui21i.tabs[5] and ui21i.tabs[5].txt:GetText() == "Спутники и Наборы",
        "21i: Tab 5 title must be 'Спутники и Наборы'! got=" .. tostring(ui21i.tabs and ui21i.tabs[5] and ui21i.tabs[5].txt:GetText()))
    local _origPepeSel = _G.PrimePepe and _G.PrimePepe.sel
    local _origPepeSlots = _G.PrimePepe and _G.PrimePepe.slots
    if _G.PrimePepe then _G.PrimePepe.sel = 1; _G.PrimePepe.slots = 1 end
    TalorianTP.serverCtrl.gv.balance = 0
    TalorianTP.serverCtrl.pepe.cur = 1
    TalorianTP.serverCtrl.pepe.sel = 1 -- bit 0 -> index 1
    TalorianTP.serverCtrl.pepe.slots = 1
    if ui21i.serverPanel and ui21i.serverPanel.Refresh then ui21i.serverPanel:Refresh() end
    if _G.PrimePepe then _G.PrimePepe.sel = _origPepeSel; _G.PrimePepe.slots = _origPepeSlots end

    -- Check created regions text specifically inside Tab 5 (ui21i.serverPanel)
    local function isInside21i(node, anc)
        local cur = node and node._parent
        while cur do
            if cur == anc then return true end
            cur = cur._parent
        end
        return false
    end
    local sawRuGold, sawRawEnGold, sawBadAutomail, sawMerchPerkLbl, sawPepeClean, sawBareHash1 = false, false, false, false, false, false
    local function checkStr21i(s)
        if type(s) ~= "string" then return end
        if s:find("0 зол.", 1, true) then sawRuGold = true end
        if s:find("0g 00s", 1, true) then sawRawEnGold = true end
        if s:find("Автопродажа:", 1, true) then sawBadAutomail = true end
        if s:find("У торговца:", 1, true) then sawMerchPerkLbl = true end
        if s:find("Облик #1", 1, true) and s:find("Бонус #1", 1, true) then sawPepeClean = true end
        if s == "#1" then sawBareHash1 = true end
    end
    for _, rg in ipairs(_G._REGIONS or {}) do
        if isInside21i(rg, ui21i.serverPanel) then
            checkStr21i(rg._text)
        end
    end
    assert(sawRuGold and not sawRawEnGold, "21i: GoldVault must display Russian gold ('0 зол.') instead of '0g 00s'!")
    assert(sawMerchPerkLbl and not sawBadAutomail, "21i: Tab 5 must use 'У торговца:' instead of misleading 'Автопродажа:'!")
    assert(sawPepeClean and not sawBareHash1, "21i: Tab 5 Pepe must show 'Облик #1' / 'Бонус #1' instead of bare '#1'! sawPepeClean=" .. tostring(sawPepeClean))
    ui21i:Hide()

    return "SUITE_21F_PASSED"
    ''')
    assert res21f == "SUITE_21F_PASSED"
    print("LUPA 21F:", res21f)
    run_real_attune_parser_core_tests()


SUITE_21DE_LUA = r'''
    local AP = AttuneParser
    -- 21d: EnsureAuctionFrame SetWordWrap colon call (must never emit AucErr!)
    _G._LAST_CHAT = nil
    _G.PrimeAuctionHouseFrame = CreateFrame("Frame", "PrimeAuctionHouseFrame")
    _G.PrimeAuctionHouseFrame:Show()
    AP:SetSetting("showAuctionUI", true)
    AP:SetSetting("aucDocked", true)
    AP:SetSetting("aucFrameOpen", true)
    AP:RefreshAuctionHelper()
    assert(_G.AP_AuctionFrame and _G.AP_AuctionFrame:IsShown(), "AP_AuctionFrame must build cleanly!")
    assert(not tostring(_G._LAST_CHAT or ""):find("AucErr", 1, true),
        "EnsureAuctionFrame must not emit AucErr! got=" .. tostring(_G._LAST_CHAT))
    _G.PrimeAuctionHouseFrame:Hide()
    _G.PrimeAuctionHouseFrame = nil

    -- 21e: Valdris uncached warming returns true + Russian notice (never prints raw 'warming') and caps stubborn uncached IDs!
    _G.PRIME_ItemBank = _G.PRIME_ItemBank or {}
    _G.PRIME_ItemBank.items = {
        { guid = 9951, entry = 63099, forge = 0, flags = 49, link = "item:63099:0:0:0:0:0:0" },
    }
    _G.PRIME_ItemBank.byGuid = { [9951] = _G.PRIME_ItemBank.items[1] }
    local _origGII21 = _G.GetItemInfo
    _G.GetItemInfo = function(x)
        local eid = tonumber(tostring(x):match("(%d+)"))
        if eid == 63099 then return nil end
        return _origGII21(x)
    end
    local ipf21 = CreateFrame("Frame", "ItemProgressFrame")
    ipf21:Show()
    _G.ItemProgressFrame = ipf21
    AP.serverSync.tryHookValdris()
    _G._LAST_CHAT = nil
    local goBtn21 = _G.AP_ValdrisAutoBar and _G.AP_ValdrisAutoBar.goBtn
    assert(goBtn21 and goBtn21._scripts and goBtn21._scripts.OnClick, "Expected goBtn")
    goBtn21._scripts.OnClick(goBtn21, "LeftButton")
    assert(AP.serverSync.valdris.running == true, "Warming click must keep valdris running!")
    assert(not tostring(_G._LAST_CHAT or ""):find("warming", 1, true),
        "goBtn click must NOT print raw 'warming' to chat! got=" .. tostring(_G._LAST_CHAT))
    assert(tostring(_G._LAST_CHAT or ""):find("Загрузка кэша", 1, true),
        "First warming retry should show clean Russian status! got=" .. tostring(_G._LAST_CHAT))
    for _ = 1, 6 do _G._TickAll(0.6) end
    assert(AP.serverSync.valdris.running == false, "Stubborn uncached ID must stop cleanly after warm retry cap!")
    ipf21:Hide()
    _G.ItemProgressFrame = nil
    _G.GetItemInfo = _origGII21

    -- 21g: Сумки и Ковка tab & GetOwnedUpgradeCandidates(..., true) show absorbed items awaiting forge (even when auto-absorb ON)
    local _origGCS21, _origGCL21, _origCAIS21, _origGIL21 = _G.GetContainerNumSlots, _G.GetContainerItemLink, _G.CustomAttuneItemStatus, _G.GetInventoryItemLink
    local _origCAP21, _origCAAT21, _origGII21g = _G.CustomAttuneProgress, _G.CustomAttuneAbsorbedTier, _G.GetItemInfo
    AP.Data.Items = AP.Data.Items or {}
    AP.Data.Items[88802] = "4|4|5|4|251|80|1000|1|0|100|-1|0|7:60,4:40|КованыйПоясТест"
    _G.GetItemInfo = function(x)
        local eid = tonumber(tostring(x):match("(%d+)"))
        if eid == 88802 then return "КованыйПоясТест", "item:88802", 4, 251, 80, "Доспехи", "Латы", 1, "INVTYPE_WAIST", "tex", 1000 end
        return _origGII21g(x)
    end
    _G.CustomAttuneProgress = function(eid, sfx)
        if eid == 88802 then return 0, nil, 0, 0 end
        if _origCAP21 then return _origCAP21(eid, sfx) end
        return nil
    end
    _G.CustomAttuneAbsorbedTier = function(eid, sfx)
        if eid == 88802 then return 0 end
        if _origCAAT21 then return _origCAAT21(eid, sfx) end
        return nil
    end
    _G.CustomAttuneItemStatus = function(eid, forge, sfx)
        if eid == 88802 then return true, false, 100, true end
        if _origCAIS21 then return _origCAIS21(eid, forge, sfx) end
        return false, false, 0, true
    end
    _G.GetContainerNumSlots = function(b) return b == 0 and 2 or 0 end
    _G.GetContainerItemLink = function(b, s) return (b == 0 and s == 1) and "|cffa335ee|Hitem:88802:0:0:0:0:0:0:0:80|h[КованыйПоясТест]|h|r" or nil end
    _G.GetInventoryItemLink = function() return nil end
    _G.PRIME_ItemBank.items = { { guid = 9952, entry = 88802, forge = 0, flags = 49, link = "item:88802:0:0:0:0:0:0" } }
    _G.PRIME_ItemBank.byGuid = { [9952] = _G.PRIME_ItemBank.items[1] }
    if AP.serverSync and AP.serverSync.ib then AP.serverSync.ib.items = _G.PRIME_ItemBank.items end
    AP.forgeBag = { [0] = { [1] = 0 } }
    AP:InvalidateCaches(true)
    local strictC21 = AP:GetOwnedUpgradeCandidates(nil, false)
    local uiC21 = AP:GetOwnedUpgradeCandidates(nil, true)
    local sawStrict88802 = false
    for _, c in ipairs(strictC21) do
        if c.itemId == 88802 then sawStrict88802 = true end
    end
    local sawBag88802, sawIb88802 = false, false
    for _, c in ipairs(uiC21) do
        if c.itemId == 88802 and c.needsForgeUpgrade then
            if c.where == "bag" then sawBag88802 = true end
            if c.where == "itembank" then sawIb88802 = true end
        end
    end
    assert((not sawStrict88802) and sawIb88802 and (AP._isShim or sawBag88802),
        "21g: absorbed uncompleted item 88802 in bag & itembank must show under includeNeedsForge=true and hide in strict mode! sawStrict=" .. tostring(sawStrict88802))
    AP:OpenUI("bags")
    local bagsPanel = AttuneParserFrame and AttuneParserFrame.tabPanels and AttuneParserFrame.tabPanels.bags
    local needMin = AP._isShim and 1 or 2
    assert(bagsPanel and bagsPanel:IsShown() and #(bagsPanel.data or {}) >= needMin,
        "21g: BuildBagsTab must populate rows for needsForge items! count=" .. tostring(bagsPanel and #(bagsPanel.data or {})))
    local sawRow88802Stat = false
    for _, rd in ipairs(bagsPanel.data or {}) do
        if rd.itemId == 88802 and rd.needsForgeUpgrade then sawRow88802Stat = true end
    end
    local foundPotRow = false
    for _, r in ipairs(bagsPanel.rows or {}) do
        local stTxt = (r and r:IsShown() and r.statTxt and r.statTxt:GetText()) or ""
        if stTxt:find("пот.", 1, true) then foundPotRow = true; break end
    end
    assert(sawRow88802Stat and foundPotRow, "21g: bagsPanel must display 88802 as needsForgeUpgrade with potential stats!")
    _G.GetContainerNumSlots, _G.GetContainerItemLink, _G.CustomAttuneItemStatus, _G.GetInventoryItemLink, _G.GetItemInfo =
        _origGCS21, _origGCL21, _origCAIS21, _origGIL21, _origGII21g
    _G.CustomAttuneProgress, _G.CustomAttuneAbsorbedTier = _origCAP21, _origCAAT21
    _G.PRIME_ItemBank.items = {}
    _G.PRIME_ItemBank.byGuid = {}
    if AP.serverSync and AP.serverSync.ib then AP.serverSync.ib.items = {} end
    AP.forgeBag = {}
    AP:InvalidateCaches(true)

    -- 21h: Mor'Kel T9/T10 exclusion from "Сумки и Ковка" (while keeping non-Mor'Kel sets) + Sets Tab tracker!
    assert(type(AP.MORKEL_SETS) == "table" and #AP.MORKEL_SETS == 57, "21h: expected 57 MorKel sets, got " .. tostring(AP.MORKEL_SETS and #AP.MORKEL_SETS))
    local mkItemCount = 0
    for _ in pairs(AP.MORKEL_ITEMS or {}) do mkItemCount = mkItemCount + 1 end
    assert(mkItemCount == 855, "21h: expected 855 MorKel set items, got " .. tostring(mkItemCount))
    assert(AP:IsMorKelItem(48640) and AP:IsMorKelItem(51170) and (not AP:IsMorKelItem(45320)) and (not AP:IsMorKelItem(88802)),
        "21h: IsMorKelItem mismatch for T9/T10 vs T8/non-set!")

    local _origGCS21h, _origGCL21h, _origCAIS21h, _origGII21h =
        _G.GetContainerNumSlots, _G.GetContainerItemLink, _G.CustomAttuneItemStatus, _G.GetItemInfo
    local _origCAP21h, _origCAAT21h = _G.CustomAttuneProgress, _G.CustomAttuneAbsorbedTier
    _G.GetContainerNumSlots = function(b) return b == 0 and 4 or 0 end
    _G.GetContainerItemLink = function(b, s)
        if b ~= 0 then return nil end
        if s == 1 then return "|cffa335ee|Hitem:48640:0:0:0:0:0:0:0:80|h[Шлем триумфа Туралиона]|h|r" end
        if s == 2 then return "|cffa335ee|Hitem:51170:0:0:0:0:0:0:0:80|h[Освященный полный шлем клятвы Свету]|h|r" end
        if s == 3 then return "|cffa335ee|Hitem:45320:0:0:0:0:0:0:0:80|h[Латные наплечники Завоевателя эгиды]|h|r" end
        if s == 4 then return "|cffa335ee|Hitem:88802:0:0:0:0:0:0:0:80|h[ТестНеСет]|h|r" end
        return nil
    end
    _G.GetItemInfo = function(arg)
        local id = type(arg) == "number" and arg or tonumber(tostring(arg):match("item:(%d+)"))
        if id == 48640 then return "Шлем триумфа Туралиона", "|cffa335ee|Hitem:48640:0:0:0:0:0:0:0:80|h[Шлем триумфа Туралиона]|h|r", 4, 245, 80, "Доспехи", "Латы", 1, "INVTYPE_HEAD", "Interface\\Icons\\INV_Helmet_01", 50000 end
        if id == 51170 then return "Освященный полный шлем клятвы Свету", "|cffa335ee|Hitem:51170:0:0:0:0:0:0:0:80|h[Освященный полный шлем клятвы Свету]|h|r", 4, 264, 80, "Доспехи", "Латы", 1, "INVTYPE_HEAD", "Interface\\Icons\\INV_Helmet_02", 50000 end
        if id == 45320 then return "Латные наплечники Завоевателя эгиды", "|cffa335ee|Hitem:45320:0:0:0:0:0:0:0:80|h[Латные наплечники Завоевателя эгиды]|h|r", 4, 226, 80, "Доспехи", "Латы", 1, "INVTYPE_SHOULDER", "Interface\\Icons\\INV_Shoulder_01", 50000 end
        if id == 88802 then return "ТестНеСет", "|cffa335ee|Hitem:88802:0:0:0:0:0:0:0:80|h[ТестНеСет]|h|r", 4, 245, 80, "Доспехи", "Латы", 1, "INVTYPE_CHEST", "Interface\\Icons\\INV_Chest_Chain", 50000 end
        if _origGII21h then return _origGII21h(arg) end
        return nil
    end
    _G.CustomAttuneProgress = function(eid, sfx)
        if eid == 51170 then return nil end
        if eid == 48640 or eid == 45320 or eid == 88802 then return 0, nil, 0, 0 end
        if _origCAP21h then return _origCAP21h(eid, sfx) end
        return nil
    end
    _G.CustomAttuneAbsorbedTier = function(eid, sfx)
        if eid == 51170 then return -1 end
        if eid == 48640 or eid == 45320 or eid == 88802 then return 0 end
        if _origCAAT21h then return _origCAAT21h(eid, sfx) end
        return nil
    end
    _G.CustomAttuneItemStatus = function(eid, forge, sfx)
        if eid == 51170 then return false, false, 0, true end
        if eid == 48640 or eid == 45320 or eid == 88802 then return true, false, 100, true end
        if _origCAIS21h then return _origCAIS21h(eid, forge, sfx) end
        return false, false, 0, true
    end
    _G.PRIME_ItemBank.items = {
        { guid = 99101, entry = 51170, suffix = 0, perm = 0, g1 = 0, g2 = 0, g3 = 0, forge = 0, tier = 0, flags = 1, added = 1, dsp = 0, link = "item:51170:0:0:0:0:0:0" },
        { guid = 99102, entry = 48640, suffix = 0, perm = 0, g1 = 0, g2 = 0, g3 = 0, forge = 0, tier = 0, flags = 1, added = 1, dsp = 0, link = "item:48640:0:0:0:0:0:0" },
        { guid = 99103, entry = 45320, suffix = 0, perm = 0, g1 = 0, g2 = 0, g3 = 0, forge = 0, tier = 0, flags = 1, added = 1, dsp = 0, link = "item:45320:0:0:0:0:0:0" },
        { guid = 99104, entry = 88802, suffix = 0, perm = 0, g1 = 0, g2 = 0, g3 = 0, forge = 0, tier = 0, flags = 1, added = 1, dsp = 0, link = "item:88802:0:0:0:0:0:0" },
    }
    _G.PRIME_ItemBank.byGuid = {
        [99101] = _G.PRIME_ItemBank.items[1], [99102] = _G.PRIME_ItemBank.items[2],
        [99103] = _G.PRIME_ItemBank.items[3], [99104] = _G.PRIME_ItemBank.items[4],
    }
    AP.forgeBag = { [0] = { [1] = 0, [3] = 0, [4] = 0 } }
    if AP.serverSync and AP.serverSync.ib then AP.serverSync.ib.items = _G.PRIME_ItemBank.items end
    AP:InvalidateCaches(true)

    AP:OpenUI("bags")
    local bagsPanel21h = AttuneParserFrame and AttuneParserFrame.tabPanels and AttuneParserFrame.tabPanels.bags
    local sawMkBag, saw45320Bag, saw88802Bag = false, false, false
    for _, rd in ipairs((bagsPanel21h and bagsPanel21h.data) or {}) do
        if rd.itemId == 48640 or rd.itemId == 51170 then sawMkBag = true end
        if rd.itemId == 45320 then saw45320Bag = true end
        if rd.itemId == 88802 then saw88802Bag = true end
    end
    assert((not sawMkBag) and saw45320Bag and saw88802Bag,
        "21h: BuildBagsTab must hide MorKel sets (48640/51170) while keeping non-MorKel set 45320 and 88802! mk=" .. tostring(sawMkBag) .. " t8=" .. tostring(saw45320Bag) .. " n8=" .. tostring(saw88802Bag))

    local progAll = AP:GetMorKelSetsProgress({ classFilter = "ALL" })
    assert(progAll and #progAll.groups == 171 and progAll.totalPieces == 855,
        "21h: GetMorKelSetsProgress(ALL) must return 171 groups / 855 pieces! got g=" .. tostring(progAll and #progAll.groups) .. " p=" .. tostring(progAll and progAll.totalPieces))
    local found48640Slot, found51170Slot = nil, nil
    for _, g in ipairs(progAll.groups) do
        for _, it in ipairs(g.items or {}) do
            if it.eid == 48640 then found48640Slot = it end
            if it.eid == 51170 then found51170Slot = it end
        end
    end
    assert(found48640Slot and found48640Slot.owned and found48640Slot.curPct == (AP.TIER_PCT[0] or 20),
        "21h: 48640 must appear in MorKel progress as owned at 20%! got=" .. tostring(found48640Slot and found48640Slot.curPct))
    assert(found51170Slot and found51170Slot.owned and (found51170Slot.curPct or 0) == 0,
        "21h: 51170 must appear in MorKel progress as owned unabsorbed!")

    local progPl = AP:GetMorKelSetsProgress({ classFilter = "HERO" })
    assert(progPl and #progPl.groups >= 12, "21h: HERO class filter (WARRIOR Alliance) must match >= 12 sub-tier groups! got=" .. tostring(progPl and #progPl.groups))
    for _, g in ipairs(progPl.groups) do
        assert(g.cls == "WARRIOR", "21h: HERO classFilter leaked non-WARRIOR set: " .. tostring(g.cls))
    end

    AP:OpenUI("sets")
    local setsPanel21h = AttuneParserFrame and AttuneParserFrame.tabPanels and AttuneParserFrame.tabPanels.sets
    assert(setsPanel21h and setsPanel21h:IsShown() and #(setsPanel21h.groups or {}) >= 4 and #(setsPanel21h.slots or {}) >= 5,
        "21h: BuildSetsTab did not render groups/slots! g=" .. tostring(setsPanel21h and #(setsPanel21h.groups or {})) .. " s=" .. tostring(setsPanel21h and #(setsPanel21h.slots or {})))

    _G.GetContainerNumSlots, _G.GetContainerItemLink, _G.CustomAttuneItemStatus, _G.GetItemInfo =
        _origGCS21h, _origGCL21h, _origCAIS21h, _origGII21h
    _G.CustomAttuneProgress, _G.CustomAttuneAbsorbedTier = _origCAP21h, _origCAAT21h
    _G.PRIME_ItemBank.items = {}
    _G.PRIME_ItemBank.byGuid = {}
    if AP.serverSync and AP.serverSync.ib then AP.serverSync.ib.items = {} end
    AP.forgeBag = {}
    AP:InvalidateCaches(true)
    return "SUITE_21DE_PASSED"
'''


def run_suite_21de(lua_rt):
    res21d = lua_rt.execute(SUITE_21DE_LUA)
    assert res21d == "SUITE_21DE_PASSED"
    print("LUPA 21D/E:", res21d)

def run_real_attune_parser_core_tests():
    lua2 = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua2.execute(WOW_SHIM)
    lua2.execute(r'''
    function IsQuestFlaggedCompleted() return false end
    function GetAuctionItemInfo(listType, idx)
        if idx == 1 then
            -- Standard WoW 3.3.5a 13-value return: buyout at #9, itemId at #17 is nil!
            return "Сапоги льда", "tex", 1, 4, true, 80, 100000, 5000, 987654, 0, nil, "Seller", 0
        end
        return nil
    end
    function GetAuctionItemLink(listType, idx)
        if idx == 1 then
            return "|cffa335ee|Hitem:40384:0:0:0:0:0:0:0:80|h[Сапоги льда]|h|r"
        end
        return nil
    end
    AuctionFrameBrowse = { IsShown = function() return true end }
    BrowseScrollFrame = {}
    NUM_BROWSE_TO_DISPLAY = 8
    FauxScrollFrame_GetOffset = function() return 0 end
    ''')
    for rel in [r"AttuneParser\AttuneParser_Data.lua", r"AttuneParser\AttuneParser_Data2.lua", r"AttuneParser\AttuneParser.lua", r"AttuneParser\AttuneParser_UI.lua"]:
        p = resolve_addon_path(rel)
        with open(p, "r", encoding="utf-8") as fh:
            lua2.execute(fh.read())
    res2 = lua2.execute(r'''
    local AP = AttuneParser
    _G._FireEvent("ADDON_LOADED", "AttuneParser")
    _G._FireEvent("PLAYER_LOGIN")
    -- Test A: Standard 3.3.5a GetAuctionItemInfo (13 args, #17 nil) fallback to GetAuctionItemLink & #9 buyout
    AP.auctionForge["40384:987654:1"] = 1
    local cands = AP:GetAuctionForgeCandidates()
    assert(#cands == 1 and cands[1].itemId == 40384 and cands[1].buyout == 987654 and cands[1].lotTier == 1,
        "Standard 3.3.5a AH candidate fallback failed! count=" .. tostring(#cands))

    -- Test B: GetRecommendations({ excludeHeavyQuests = false }) must NOT fall back to true setting!
    AP.Data.Zones = AP.Data.Zones or {}
    AP.Data.ZoneItems = AP.Data.ZoneItems or {}
    AP.Data.Sources = AP.Data.Sources or {}
    AP.Data.Zones[999001] = { name = "HeavyQuestTestZone", exp = 3, isRaid = false }
    AP.Data.ZoneItems[999001] = { 88801 }
    AP.Data.Items[88801] = "4|4|5|4|245|80|1000|1|0|999001|-1|0|7:50,4:50|ТестТяжКв"
    AP.Data.Sources[88801] = "4:99001:999001:0:1:0:8:0"
    AP:InvalidateCaches(false)
    AP:SetSetting("excludeHeavyQuests", true)
    local rTrue = AP:GetRecommendations({ mode = "combined", scope = "hero", excludeHeavyQuests = true, limit = 500 })
    local rFalse = AP:GetRecommendations({ mode = "combined", scope = "hero", excludeHeavyQuests = false, limit = 500 })
    local sawT, sawF = false, false
    for _, z in ipairs(rTrue) do if z.zoneId == 999001 then sawT = true end end
    for _, z in ipairs(rFalse) do if z.zoneId == 999001 and (z.newCount or 0) == 1 then sawF = true end end
    assert((not sawT) and sawF,
        "GetRecommendations(excludeHeavyQuests=false) must override excludeHeavyQuests=true setting! sawT=" .. tostring(sawT) .. " sawF=" .. tostring(sawF))

    -- Test C: Elixirs (900211 Эликсир двойного опыта vs Эликсир поглощения) & Guild Attune Perk Bonus
    local _auras = {
        { name = "Дар Пятницы", sid = 900205 },
        { name = "Эликсир двойного опыта", sid = 900211 },
    }
    _G.UnitAura = function(u, idx, flt)
        local a = _auras[idx]
        if a then return a.name, "", "tex", 0, nil, 3600, 100, nil, nil, nil, a.sid end
        return nil
    end
    _G.IsInGuild = function() return true end
    _G.GetGuildXP = function() return nil end
    local gift1 = AP:GetActiveDailyGift(true)
    local eq1 = AP:GetEquippedAttuneProgress()
    assert(gift1.hasElixir == false and gift1.hasExpElixir == true and eq1.hasExpElixir == true and eq1.xpMult == 1 and eq1.guildKnown == false,
        "900211 must set hasExpElixir=true without faking attune xpMult, and unloaded guild must set guildKnown=false!")

    _G.GetGuildXP = function() return 15 end
    _G.GetGuildNumPerks = function() return 1 end
    _G.GetGuildPerks = function(i) return 88899, 10 end
    _G.GetSpellLink = function(id) return "spell:" .. id end
    local _origTipSetH = AttuneParserScanTip.SetHyperlink
    local _origTipNL = AttuneParserScanTip.NumLines
    local _origTipClear = AttuneParserScanTip.ClearLines
    function AttuneParserScanTip:ClearLines() _G.AttuneParserScanTipTextLeft1 = nil end
    function AttuneParserScanTip:SetHyperlink(lk)
        if lk == "spell:88899" then
            _G.AttuneParserScanTipTextLeft1 = { GetText = function() return "Увеличивает опыт поглощения на 10%." end }
            self._nl = 1
        end
    end
    function AttuneParserScanTip:NumLines() return self._nl or 0 end
    local eq2 = AP:GetEquippedAttuneProgress()
    assert(eq2.guildKnown == true and eq2.guildPct == 10 and math.abs(eq2.xpMult - 1.1) < 0.001,
        "Guild perk scan must resolve +10%! got guildPct=" .. tostring(eq2.guildPct) .. " xpMult=" .. tostring(eq2.xpMult))
    AttuneParserScanTip.SetHyperlink = _origTipSetH
    AttuneParserScanTip.NumLines = _origTipNL
    AttuneParserScanTip.ClearLines = _origTipClear

    -- Test D: Loaded but disabled TalorianTP_DB.enabled=false MUST NOT display "TalorianTP не загружен"!
    _G.TalorianTP = { OpenUI = function() end }
    _G.TalorianTP_DB = { enabled = false }
    AP:RegisterTalorianBridge({
        HasPet = function() return true, true end,
        IsAvailable = function() return false end,
        OpenUI = function() return true end,
    })
    local talL, talEn, talAct, talOff = AP:GetTalorianStatus()
    assert(talL == true and talEn == false and talAct == false and talOff == false, "GetTalorianStatus mismatch!")
    AP:OpenUI("summary")
    assert(AttuneParserFrame and AttuneParserFrame:IsShown() and AttuneParserFrame.talBtn:IsShown(),
        "Header talBtn must stay visible when TalorianTP is loaded (even if disabled in /ttp)!")
    local c1Txt = AttuneParserFrame.tabPanels.summary._testBody1
    local hdrTxt = AttuneParserFrame.subText:GetText()
    assert(type(hdrTxt) == "string" and hdrTxt:find("Выкл", 1, true) and not hdrTxt:find("Автономный режим", 1, true),
        "Header must show disabled-in-ttp instead of Автономный режим! got=" .. tostring(hdrTxt))

    -- Test E (21g core): Core BuildBagsTab & GetOwnedUpgradeCandidates(nil, true) show forge-pending items when auto-absorb is ON
    local _oGCS, _oGCL, _oCAIS, _oCAP, _oCAAT = _G.GetContainerNumSlots, _G.GetContainerItemLink, _G.CustomAttuneItemStatus, _G.CustomAttuneProgress, _G.CustomAttuneAbsorbedTier
    _G.GetContainerNumSlots = function(b) return b == 0 and 2 or 0 end
    _G.GetContainerItemLink = function(b, s) return (b == 0 and s == 1) and "|cffa335ee|Hitem:88801:0:0:0:0:0:0:0:80|h[ТестТяжКв]|h|r" or nil end
    _G.CustomAttuneProgress = function(eid, sfx)
        if eid == 88801 then return 0, nil, 0, 0 end
        if _oCAP then return _oCAP(eid, sfx) end
        return nil
    end
    _G.CustomAttuneAbsorbedTier = function(eid, sfx)
        if eid == 88801 then return 0 end
        if _oCAAT then return _oCAAT(eid, sfx) end
        return nil
    end
    _G.CustomAttuneItemStatus = function(eid, forge, sfx)
        if eid == 88801 then return true, false, 100, true end
        return false, false, 0, true
    end
    AP.forgeBag = { [0] = { [1] = 0 } }
    AP:InvalidateCaches(true)
    local sc = AP:GetOwnedUpgradeCandidates(nil, false)
    local uc = AP:GetOwnedUpgradeCandidates(nil, true)
    assert(#sc == 0 and #uc == 1 and uc[1].itemId == 88801 and uc[1].needsForgeUpgrade == true,
        "Core GetOwnedUpgradeCandidates(nil, true) must include forge-pending 88801! #sc=" .. #sc .. " #uc=" .. #uc)
    AP:OpenUI("bags")
    local bp = AttuneParserFrame and AttuneParserFrame.tabPanels and AttuneParserFrame.tabPanels.bags
    assert(bp and #(bp.data or {}) == 1 and bp.rows[1].statTxt:GetText():find("пот.", 1, true),
        "Core BuildBagsTab must display forge-pending bag item!")
    _G.GetContainerNumSlots, _G.GetContainerItemLink, _G.CustomAttuneItemStatus, _G.CustomAttuneProgress, _G.CustomAttuneAbsorbedTier = _oGCS, _oGCL, _oCAIS, _oCAP, _oCAAT
    AP.forgeBag = {}
    AP:InvalidateCaches(true)

    _G._RAISE_SEQ = 100
    AP:OpenUI("top")
    for _, fr in ipairs(_G._FRAMES) do
        if fr and fr:IsShown() and fr._scripts and fr._scripts.OnUpdate then fr._scripts.OnUpdate(fr, 0.05) end
    end
    assert((_G.AttuneParserFrame._raisedAt or 0) > 100, "Core AP:OpenUI must call Raise() on AttuneParserFrame!")

    -- Test F (21j core): Zone icons, Kind/Dungeon filter fix, Difficulty selector, and Attune vs Paragon XP rules
    assert(AP.FormatMult(1.25) == "1.25" and AP.FormatMult(1.2) == "1.2" and AP.FormatMult(2.0) == "2" and AP.FormatMult(3.75) == "3.75",
        "AP.FormatMult must preserve exact decimals without 2-sig-digit truncation!")
    assert(AP:GetZoneIcon(4812, true, true) == "Interface\\Icons\\Achievement_Boss_LichKing", "Missing ICC icon in AP.ZONE_ICONS")
    assert(AP:GetZoneIcon(4809, false, true) == "Interface\\Icons\\Achievement_Dungeon_Icecrown_ForgeofSouls", "Missing FoS icon in AP.ZONE_ICONS")
    local _oUL = _G.UnitLevel
    _G.UnitLevel = function() return 80 end
    AP:SetSetting("topMode", "new")
    AP:SetSetting("kindFilter", "All")
    AP:SetSetting("diffFilter", 0)
    AP:InvalidateCaches(true)
    AP:OpenUI("top")
    local tp = AttuneParserFrame and AttuneParserFrame.tabPanels and AttuneParserFrame.tabPanels.top
    assert(tp and tp._kindBtn and tp._diffBtn, "TopTab must expose _kindBtn and _diffBtn!")
    -- Click Kind once -> Raid, click again -> Dungeon
    tp._kindBtn._scripts.OnClick(tp._kindBtn, "LeftButton")
    assert(AP:GetSetting("kindFilter") == "Raid", "First Kind click must switch to Raid")
    assert(#(tp.data or {}) > 0, "Raid list must not be empty")
    for _, rowD in ipairs(tp.data) do
        assert(rowD.kind == "zone" and rowD.zone.isRaid == true, "Raid filter must only return raids!")
    end
    tp._kindBtn._scripts.OnClick(tp._kindBtn, "LeftButton")
    assert(AP:GetSetting("kindFilter") == "Dungeon", "Second Kind click must switch to Dungeon")
    assert(#(tp.data or {}) > 0, "Dungeon list must not be empty")
    for _, rowD in ipairs(tp.data) do
        assert(rowD.kind == "zone" and rowD.zone.isRaid == false,
            "Dungeon filter must NEVER leak raids (false or nil regression)! leaked=" .. tostring(rowD.zone.zoneName))
    end
    assert(tp.rows[1] and tp.rows[1].ic and tp.rows[1].ic._tex and tp.rows[1].ic._tex:find("Interface\\Icons\\", 1, true),
        "Top row must render zone icon texture! got=" .. tostring(tp.rows[1] and tp.rows[1].ic and tp.rows[1].ic._tex))
    assert(tp.rows[1].progTxt:GetText():find("%%", 1, false), "Top row progress bar must show pct text!")
    -- Switch to All and cycle diff to 4 (25 heroic)
    tp._kindBtn._scripts.OnClick(tp._kindBtn, "LeftButton")
    assert(AP:GetSetting("kindFilter") == "All")
    AP:SetSetting("diffFilter", 4)
    tp.RefreshData()
    assert(#(tp.data or {}) > 0, "25H diffFilter must return 4-diff raids")
    for _, rowD in ipairs(tp.data) do
        assert((rowD.zone.maxDiffs or 1) >= 4, "25H diffFilter must exclude 1-diff/2-diff instances! got=" .. tostring(rowD.zone.zoneName))
    end
    assert(tp.rows[1].subTxt:GetText():find("25 гер", 1, true), "Top row subline must reflect active 25 гер difficulty filter!")
    AP:SetSetting("diffFilter", 0)

    -- Attune vs Paragon XP rules: Sat + Attune Elixir ADD (x3) * Guild 25% = x3.75; Paragon x2 buffs DO NOT stack (>1 gives x2 only + warning)
    local _oUA, _oSD, _oMW, _oGP = _G.UnitAura, _G.serverData, AP.mentorWhere, AP.guildAttuneBonusPct
    local mockAuras = {
        { "Дар Субботы", 900206 },
        { "Эликсир поглощения предметов", 900210 },
        { "Эликсир двойного опыта", 900211 },
        { "Благословение новичка", 1040174 },
    }
    _G.UnitAura = function(unit, idx, flt)
        local a = (unit == "player") and mockAuras[idx] or nil
        if not a then return nil end
        return a[1], "", "Interface\\Icons\\INV_Misc_QuestionMark", 1, nil, 3600, 0, "player", false, false, a[2]
    end
    _G.serverData = { level = 120, experience = 500, expMax = 2000, stats = { [19] = 50 } }
    AP.mentorWhere = { v2 = true, gift = 1, elixir = 1, guildPct = 25 }
    AP.guildAttuneBonusPct = 25
    local eqXP = AP:GetEquippedAttuneProgress()
    assert(math.abs((eqXP.xpMult or 0) - 3.75) < 0.001, "Attune XP must be (1+1+1)*1.25 = 3.75! got=" .. tostring(eqXP.xpMult))
    local px = AP:GetParagonXPBreakdown()
    assert(px.paragonX2Mult == 2 and px.paragonX2Wasted == true, "Multiple x2 Paragon sources must stay x2 and flag overlap!")
    assert(math.abs((px.paragonMobMult or 0) - 2.5) < 0.001, "Paragon mob mult with x2 + 25% perk must be 2.5! got=" .. tostring(px.paragonMobMult))
    AP:OpenUI("summary")
    local sp = AttuneParserFrame and AttuneParserFrame.tabPanels and AttuneParserFrame.tabPanels.summary
    local c2Txt = sp and sp._c2 and sp._c2.body and sp._c2.body:GetText() or ""
    assert(c2Txt:find("x3.75", 1, true) and c2Txt:find("Гильдия +25%", 1, true), "Card 2 must show x3.75 (not x3.7) and Гильдия +25%! got=" .. c2Txt)
    assert(c2Txt:find("x2.5", 1, true) and c2Txt:find("x2 не стак.", 1, true), "Card 2 must show Paragon x2.5 and non-stacking notice! got=" .. c2Txt)
    assert(c2Txt:find("0 зол.", 1, true) and not c2Txt:find("~0g", 1, true), "Card 2 must use зол. instead of ~0g!")
    assert(c2Txt:find("все поглощены на 100%", 1, true) and not c2Txt:find("~0 кв.", 1, true), "Card 2 must show completed status when eq.count==0!")
    sp._c2._xpHelpBtn._scripts.OnEnter(sp._c2._xpHelpBtn)
    _G.UnitAura, _G.serverData, AP.mentorWhere, AP.guildAttuneBonusPct, _G.UnitLevel = _oUA, _oSD, _oMW, _oGP, _oUL

    -- Test G (21k core audit fixes): GetItemHyperlink full-link 2nd return, BuildItemTooltip real SetHyperlink,
    -- StartBackgroundScan restart after completion, ASMSG_FORGE_MAP stale forgeByEntry reset, HIGH strata
    local gl, gr = AP:GetItemHyperlink(50603, "|cffa335ee|Hitem:50603:0:0:0:0:0:0:0:80|h[Тест]|h|r")
    assert(gl and gr == "item:50603:0:0:0:0:0:0:0:80", "GetItemHyperlink must extract rawItemStr from full |Hitem link! got=" .. tostring(gr))
    local tipCalled = nil
    local mockTip = {
        ClearLines = function() end,
        SetHyperlink = function(self, s) tipCalled = s end,
        NumLines = function() return 3 end,
        AddLine = function() end,
        AddDoubleLine = function() end,
    }
    AP:BuildItemTooltip(mockTip, 50603, { link = gl, name = "Тест", quality = 4 })
    assert(tipCalled == "item:50603:0:0:0:0:0:0:0:80", "BuildItemTooltip must invoke SetHyperlink on full hyperlink!")

    assert(AttuneParserFrame and AttuneParserFrame:GetFrameStrata() == "HIGH", "AttuneParserFrame must use HIGH strata!")
    local scan1 = AP:StartBackgroundScan()
    AP:StopBackgroundScan()
    local scan2 = AP:StartBackgroundScan()
    assert(type(scan1) == "number" and type(scan2) == "number", "StartBackgroundScan must remain restartable")

    AP.forgeByEntry[77701] = 3
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_FORGE_MAP", "E:1:2", "UNKNOWN", UnitName("player"))
    assert(AP.forgeMapLoaded == true and AP.forgeByEntry[77701] == nil, "ASMSG_FORGE_MAP must clear stale AP.forgeByEntry!")

    return "REAL_AP_CORE_PASSED"
    ''')
    print("REAL AP CORE RESULT:", res2)
    assert res2 == "REAL_AP_CORE_PASSED"

def run_standalone_integrations_tests():
    lua3 = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua3.execute(WOW_SHIM)
    lua3.execute(r'''
    _G.ResourceBank = { usedEntries = 0, maxEntries = 120, contents = {} }
    _G.PRIME_ItemBank = { items = {}, byGuid = {}, cap = 100 }
    ''')
    for rel in [
        r"AttuneParser\AttuneParser_Data.lua",
        r"AttuneParser\AttuneParser_Data2.lua",
        r"AttuneParser\AttuneParser.lua",
        r"AttuneParser\AttuneParser_UI.lua",
        r"AttuneParser\AttuneParser_Integrations.lua",
    ]:
        p = resolve_addon_path(rel)
        with open(p, "r", encoding="utf-8") as fh:
            lua3.execute(fh.read())
    lua3.execute(r'''
    _G._FireEvent("ADDON_LOADED", "AttuneParser")
    _G._FireEvent("PLAYER_LOGIN")
    AttuneParser:OpenUI("top")
    AttuneParser:OpenUI("summary")
    AttuneParser:OpenUI("bags")
    AttuneParser:OpenUI("sets")
    AttuneParser:OpenUI("settings")
    AttuneParser:OpenUI("server")

    -- Interactive scrollbar tests (buttons, track click, thumb drag)
    local apFrame = _G.AttuneParserFrame
    assert(apFrame and apFrame.tabPanels and apFrame.tabPanels.top and apFrame.tabPanels.top.sf, "Expected top tab scroll frame")
    local topSf = apFrame.tabPanels.top.sf
    topSf:SetTotal(40, false)
    assert(topSf._bar:IsShown() and topSf.offset == 0, "Scroll bar must show when total > visCount")
    -- Mouse click down+up+click on dn must step ONCE (not double)
    local prevStep = topSf._dn._step
    topSf._dn._scripts.OnMouseDown(topSf._dn, "LeftButton")
    topSf._dn._scripts.OnMouseUp(topSf._dn, "LeftButton")
    topSf._dn._scripts.OnClick(topSf._dn, "LeftButton")
    assert(topSf.offset == prevStep, "Down button click must step once! got=" .. tostring(topSf.offset))
    -- Hold-to-repeat while button is held down
    topSf._dn._scripts.OnMouseDown(topSf._dn, "LeftButton")
    _G._TickAll(0.30)
    _G._TickAll(0.08)
    topSf._dn._scripts.OnMouseUp(topSf._dn, "LeftButton")
    topSf._dn._scripts.OnClick(topSf._dn, "LeftButton")
    assert(topSf.offset > prevStep * 2, "Holding down button must repeat scroll! got=" .. tostring(topSf.offset))
    -- Programmatic OnClick on up steps back up cleanly
    local beforeUp = topSf.offset
    topSf._up._scripts.OnClick(topSf._up, "LeftButton")
    assert(topSf.offset == beforeUp - prevStep, "Up button OnClick must decrease offset! got=" .. tostring(topSf.offset))
    -- Dragging thumb with mouse
    local _oGCP = _G.GetCursorPosition
    local curY = 300
    _G.GetCursorPosition = function() return 500, curY end
    topSf:_ScrollTo(0)
    topSf._thumb._scripts.OnMouseDown(topSf._thumb, "LeftButton")
    curY = 120
    _G._TickAll(0.05)
    local draggedOff = topSf.offset
    assert(draggedOff >= 10, "Dragging thumb downward must advance offset! got=" .. tostring(draggedOff))
    topSf._thumb._scripts.OnMouseUp(topSf._thumb, "LeftButton")
    curY = 10
    _G._TickAll(0.05)
    assert(topSf.offset == draggedOff, "Offset must stay fixed after thumb OnMouseUp! got=" .. tostring(topSf.offset))
    -- Track click near top jumps toward 0
    curY = (topSf._bar:GetTop() or 376) - 24
    topSf._bar._scripts.OnMouseDown(topSf._bar, "LeftButton")
    topSf._bar._scripts.OnMouseUp(topSf._bar, "LeftButton")
    assert(topSf.offset < draggedOff, "Clicking upper scrollbar track must jump offset toward 0! got=" .. tostring(topSf.offset))
    _G.GetCursorPosition = _oGCP
    ''')
    run_suite_21de(lua3)
    print("STANDALONE AP INTEGRATIONS: PASSED")


def run_real_full_integrated_tests():
    lua4 = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua4.execute(WOW_SHIM)
    lua4.execute(r'''
    _G.ResourceBank = { usedEntries = 0, maxEntries = 120, contents = {} }
    _G.PRIME_ItemBank = { items = {}, byGuid = {}, cap = 100 }
    ''')
    for rel in [
        r"AttuneParser\AttuneParser_Data.lua",
        r"AttuneParser\AttuneParser_Data2.lua",
        r"AttuneParser\AttuneParser.lua",
        r"AttuneParser\AttuneParser_UI.lua",
        r"AttuneParser\AttuneParser_Integrations.lua",
        r"TalorianTP\TalorianLootDB.lua",
        r"TalorianTP\TalorianTP.lua",
    ]:
        p = resolve_addon_path(rel)
        with open(p, "r", encoding="utf-8") as fh:
            lua4.execute(fh.read())
    res4 = lua4.execute(r'''
    _G._FireEvent("ADDON_LOADED", "AttuneParser")
    _G._FireEvent("ADDON_LOADED", "TalorianTP")
    _G._FireEvent("PLAYER_LOGIN")
    local function tick4()
        for _, fr in ipairs(_G._FRAMES) do
            if fr and fr:IsShown() and fr._scripts and fr._scripts.OnUpdate then fr._scripts.OnUpdate(fr, 0.05) end
        end
    end
    local ui = TalorianTP:OpenUI(1)
    tick4()
    ui:Raise()
    AttuneParser:OpenUI("top")
    tick4()
    assert(_G.AttuneParserFrame and (_G.AttuneParserFrame._raisedAt or 0) > (ui._raisedAt or 0),
        "Full integrated: AttuneParserFrame must raise above TalorianMainFrame!")
    AttuneParser:OpenTalorianUI()
    tick4()
    assert((ui._raisedAt or 0) > (_G.AttuneParserFrame._raisedAt or 0),
        "Full integrated: OpenTalorianUI must raise TalorianMainFrame above AttuneParserFrame!")
    TalorianTP_ToggleAnalysisWindow()
    tick4()
    local af = _G.TalorianAnalysisFrame
    assert(af and af:IsShown() and (af._raisedAt or 0) > (ui._raisedAt or 0),
        "Full integrated: TalorianAnalysisFrame must raise above TalorianMainFrame!")
    local allBtn
    for _, sb in ipairs(af.statusBtns or {}) do if sb.id == "all" then allBtn = sb end end
    assert(allBtn, "Expected 'all' filter button")
    allBtn._scripts.OnClick(allBtn)
    assert(af.itemRows[1] and af.itemRows[1]:IsShown() and af.itemRows[1].itemData and (af.itemRows[1].itemData.coreStats or 0) >= 0,
        "Full integrated: Explorer must populate real AttuneParser ZoneItems for ICC!")
    af.itemRows[1]._scripts.OnEnter(af.itemRows[1])

    -- Suite 21k Integrated & TalorianTP audit regressions:
    -- 1. Frame stratas match HIGH across both addons
    assert(ui:GetFrameStrata() == "HIGH", "TalorianMainFrame must use HIGH strata!")
    assert(af:GetFrameStrata() == "HIGH", "TalorianAnalysisFrame must use HIGH strata!")
    assert(_G.AttuneParserFrame:GetFrameStrata() == "HIGH", "AttuneParserFrame must use HIGH strata!")
    -- 2. SelectDestInTalorianUI & FindDestByZoneOrName preserve UBRS by name on shared zoneId 1583
    assert(TalorianTP_SelectZone(1583, "Верхняя часть пика Черной горы") == true)
    assert(TalorianTP_DB.targetRaid == "Верхняя часть пика Черной горы" and TalorianTP_DB.dungeonEra == "Classic",
        "UBRS selection on zoneId 1583 must pick UBRS & Classic! got=" .. tostring(TalorianTP_DB.targetRaid))
    -- 3. Dungeon filter in Explorer hides 3/4 diff buttons & clamps diff > 2
    local dngBtn, d3Btn
    for _, b in ipairs(af.kindBtns or {}) do if b.id == "dungeon" then dngBtn = b end end
    for _, b in ipairs(af.diffBtns or {}) do if b.id == 3 then d3Btn = b end end
    assert(dngBtn and d3Btn)
    d3Btn._scripts.OnClick(d3Btn)
    dngBtn._scripts.OnClick(dngBtn)
    assert(not d3Btn:IsShown(), "10H/25H diff buttons must hide in Explorer Dungeon mode!")
    -- 4. ResolveWorldBossName strips |count|flags from AP.Data.Creatures
    AttuneParser.Data.Creatures[999111] = "ТестБосс|12|0"
    assert(AttuneParser:GetWorldBossName(999111) == "ТестБосс", "Creature name must strip |count|flags!")
    AttuneParser.Data.Creatures[999111] = nil
    -- 5. GetValdrisPickerItems -> EvalItemForValdris handles attun == false as no_attune
    local _oCAIS2, _oGCS2, _oGCL2, _oGII2 = _G.CustomAttuneItemStatus, _G.GetContainerNumSlots, _G.GetContainerItemLink, _G.GetItemInfo
    _G.GetContainerNumSlots = function(b) return b == 0 and 1 or 0 end
    _G.GetContainerItemLink = function(b, s) return (b == 0 and s == 1) and "|cffa335ee|Hitem:999222:0:0:0:0:0:0:0:80|h[НепоглТест]|h|r" or nil end
    _G.GetItemInfo = function(x)
        if tostring(x):find("999222", 1, true) then
            return "НепоглТест", "|cffa335ee|Hitem:999222:0:0:0:0:0:0:0:80|h[НепоглТест]|h|r", 4, 245, 80, "Доспехи", "Латы", 1, "INVTYPE_CHEST", "Interface\\Icons\\INV_Misc_QuestionMark"
        end
        return _oGII2(x)
    end
    _G.CustomAttuneItemStatus = function(eid)
        if eid == 999222 then return false, false, 0, false end
        return _oCAIS2 and _oCAIS2(eid) or false, false, 0, true
    end
    local pItems = AttuneParser:GetValdrisPickerItems("bags")
    _G.CustomAttuneItemStatus, _G.GetContainerNumSlots, _G.GetContainerItemLink, _G.GetItemInfo = _oCAIS2, _oGCS2, _oGCL2, _oGII2
    assert(pItems and pItems[1] and pItems[1].statusKey == "no_attune",
        "Valdris picker must classify attun==false as no_attune! got=" .. tostring(pItems and pItems[1] and pItems[1].statusKey))
    -- 6. TalorianTP_DeleteAllTalorianMacros combat guard & account+char cleanup
    local _oICL, _oGNM, _oGMI, _oDM = _G.InCombatLockdown, _G.GetNumMacros, _G.GetMacroInfo, _G.DeleteMacro
    _G.InCombatLockdown = function() return true end
    local deletedC = TalorianTP_DeleteAllTalorianMacros()
    assert(deletedC == 0, "DeleteAllTalorianMacros must abort cleanly in combat!")
    _G.InCombatLockdown = function() return false end
    local mockMacros = { [1] = "T_ЦЛК", [37] = "T_БВЛ", [38] = "MyCustom" }
    local deletedIds = {}
    _G.GetNumMacros = function() return 2, 2 end
    _G.GetMacroInfo = function(idx) return mockMacros[idx] end
    _G.DeleteMacro = function(idx) table.insert(deletedIds, idx) end
    local deletedAll = TalorianTP_DeleteAllTalorianMacros()
    _G.InCombatLockdown, _G.GetNumMacros, _G.GetMacroInfo, _G.DeleteMacro = _oICL, _oGNM, _oGMI, _oDM
    assert(deletedAll == 2 and #deletedIds == 2, "DeleteAllTalorianMacros must clean both general and char T_* macros! got=" .. tostring(deletedAll))

    -- Suite 21l: Interactive mouse scrollbars in TalorianTP Explorer, TalorianTopFrame, and AP_ValdrisPickerFrame
    assert(af.zoneScroll and af.zoneScroll._bar and af.zoneScroll._thumb and af.zoneScroll._up and af.zoneScroll._dn,
        "Explorer zoneScroll must use PS.AttachScroll interactive controls!")
    assert(af.itemScroll and af.itemScroll._bar and af.itemScroll._thumb and af.itemScroll._up and af.itemScroll._dn,
        "Explorer itemScroll must use PS.AttachScroll interactive controls!")
    assert(af.zoneScroll._bar:IsShown(), "Explorer zoneScroll bar must show when raids > VIS_ZONES!")
    local zFirst0 = af.zoneRows[1] and af.zoneRows[1].zoneRec and af.zoneRows[1].zoneRec.dest and af.zoneRows[1].zoneRec.dest.name
    af.zoneScroll._dn._scripts.OnMouseDown(af.zoneScroll._dn, "LeftButton")
    af.zoneScroll._dn._scripts.OnMouseUp(af.zoneScroll._dn, "LeftButton")
    af.zoneScroll._dn._scripts.OnClick(af.zoneScroll._dn, "LeftButton")
    local zOffAfterDn = af.zoneScroll.offset
    local zFirst1 = af.zoneRows[1] and af.zoneRows[1].zoneRec and af.zoneRows[1].zoneRec.dest and af.zoneRows[1].zoneRec.dest.name
    assert(zOffAfterDn > 0 and zFirst1 ~= zFirst0, "Explorer zoneScroll down button must shift zone rows! got off=" .. tostring(zOffAfterDn))
    af.zoneScroll._up._scripts.OnClick(af.zoneScroll._up, "LeftButton")
    assert(af.zoneScroll.offset == 0, "Explorer zoneScroll up button must return to 0! got=" .. tostring(af.zoneScroll.offset))

    -- Dragging itemScroll thumb in Explorer
    assert(af.itemScroll._bar:IsShown() and (af.itemScroll.total or 0) > 10, "ICC 'all' status must fill > 10 items for scrollbar test!")
    local iFirst0 = af.itemRows[1] and af.itemRows[1].itemData and af.itemRows[1].itemData.id
    local _oGCP2, cy2 = _G.GetCursorPosition, 300
    _G.GetCursorPosition = function() return 600, cy2 end
    af.itemScroll._thumb._scripts.OnMouseDown(af.itemScroll._thumb, "LeftButton")
    cy2 = 120
    _G._TickAll(0.05)
    local iOffDrag = af.itemScroll.offset
    local iFirst1 = af.itemRows[1] and af.itemRows[1].itemData and af.itemRows[1].itemData.id
    af.itemScroll._thumb._scripts.OnMouseUp(af.itemScroll._thumb, "LeftButton")
    assert(iOffDrag > 0 and iFirst1 ~= iFirst0, "Dragging Explorer itemScroll thumb must scroll items! got off=" .. tostring(iOffDrag))
    cy2 = 120
    af.itemScroll._thumb._scripts.OnMouseDown(af.itemScroll._thumb, "LeftButton")
    cy2 = 290
    _G._TickAll(0.05)
    af.itemScroll._thumb._scripts.OnMouseUp(af.itemScroll._thumb, "LeftButton")
    assert(af.itemScroll.offset < iOffDrag, "Dragging thumb upward must scroll back up! got=" .. tostring(af.itemScroll.offset))

    -- TalorianTopFrame scrollFrame buttons, drag & wheel
    TalorianTP_ToggleTopWindow()
    tick4()
    local tf = _G.TalorianTopFrame
    assert(tf and tf:IsShown() and tf.scrollFrame and tf.scrollFrame._bar and tf.scrollFrame._bar:IsShown(),
        "TalorianTopFrame must display interactive scrollbar when rows > 14!")
    tf.scrollFrame._dn._scripts.OnClick(tf.scrollFrame._dn, "LeftButton")
    assert(tf.scrollFrame.offset > 0, "TalorianTopFrame dn button must scroll! got=" .. tostring(tf.scrollFrame.offset))
    tf.scrollFrame._up._scripts.OnClick(tf.scrollFrame._up, "LeftButton")
    assert(tf.scrollFrame.offset == 0, "TalorianTopFrame up button must return to 0! got=" .. tostring(tf.scrollFrame.offset))
    cy2 = 300
    tf.scrollFrame._thumb._scripts.OnMouseDown(tf.scrollFrame._thumb, "LeftButton")
    cy2 = 100
    _G._TickAll(0.05)
    tf.scrollFrame._thumb._scripts.OnMouseUp(tf.scrollFrame._thumb, "LeftButton")
    assert(tf.scrollFrame.offset > 0, "TalorianTopFrame thumb drag must scroll! got=" .. tostring(tf.scrollFrame.offset))
    local sb = tf.scrollFrame._parent
    sb._scripts.OnMouseWheel(sb, 1)
    assert(tf.scrollFrame.offset >= 0, "TalorianTopFrame scrollBox OnMouseWheel must execute cleanly!")
    af.zoneScroll:_ScrollTo(0)
    af.zoneScroll._parent._scripts.OnMouseWheel(af.zoneScroll._parent, -1)
    assert(af.zoneScroll.offset == 2, "Explorer leftBox wheel downward must step +2! got=" .. tostring(af.zoneScroll.offset))

    -- AP_ValdrisPickerFrame interactive scrollbar when > 8 items exist
    local _oGII3, _oGCS3, _oGCL3 = _G.GetItemInfo, _G.GetContainerNumSlots, _G.GetContainerItemLink
    _G.GetContainerNumSlots = function(b) return b == 0 and 12 or 0 end
    _G.GetContainerItemLink = function(b, s)
        if b == 0 and s >= 1 and s <= 12 then
            return "|cffa335ee|Hitem:" .. (999300 + s) .. ":0:0:0:0:0:0:0:80|h[ВальдрисТест" .. s .. "]|h|r"
        end
        return nil
    end
    _G.GetItemInfo = function(x)
        local sid = tostring(x):match("9993(%d%d)")
        if sid then
            local id = 999300 + tonumber(sid)
            return "ВальдрисТест" .. sid, "|cffa335ee|Hitem:" .. id .. ":0:0:0:0:0:0:0:80|h[ВальдрисТест" .. sid .. "]|h|r",
                4, 245, 80, "Доспехи", "Латы", 1, "INVTYPE_CHEST", "Interface\\Icons\\INV_Misc_QuestionMark"
        end
        return _oGII3(x)
    end
    local _ipf4 = _G.ItemProgressFrame or CreateFrame("Frame", "ItemProgressFrame")
    _ipf4:Show()
    _G._FireEvent("CHAT_MSG_ADDON", "ASMSG_IPROG_OPEN", "1", "WHISPER", "TestHero")
    if _G.AP_ValdrisAutoBar and _G.AP_ValdrisAutoBar.pickBtn then
        _G.AP_ValdrisAutoBar.pickBtn._scripts.OnClick(_G.AP_ValdrisAutoBar.pickBtn, "LeftButton")
    end
    local vpf = _G.AP_ValdrisPickerFrame
    assert(vpf and vpf.sf and vpf.sf._bar and vpf.sf._bar:IsShown(), "Valdris picker scrollbar must show with 12 items!")
    vpf.sf._dn._scripts.OnClick(vpf.sf._dn, "LeftButton")
    assert(vpf.offset > 0, "Valdris picker down button must advance offset! got=" .. tostring(vpf.offset))
    cy2 = 240
    vpf.sf._thumb._scripts.OnMouseDown(vpf.sf._thumb, "LeftButton")
    cy2 = 120
    _G._TickAll(0.05)
    vpf.sf._thumb._scripts.OnMouseUp(vpf.sf._thumb, "LeftButton")
    assert(vpf.offset >= 2, "Valdris picker thumb drag must scroll! got=" .. tostring(vpf.offset))
    _G.GetCursorPosition = _oGCP2
    _G.GetItemInfo, _G.GetContainerNumSlots, _G.GetContainerItemLink = _oGII3, _oGCS3, _oGCL3

    return "FULL_INTEGRATED_PASSED"
    ''')
    print("FULL INTEGRATED RESULT:", res4)
    assert res4 == "FULL_INTEGRATED_PASSED"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--talorian-dir", default=None)
    args = parser.parse_args()
    if args.talorian_dir:
        TALORIAN_DIR = args.talorian_dir
    if os.path.isfile(os.path.join(TALORIAN_DIR, "TalorianTP.lua")):
        run_tests()
        run_real_full_integrated_tests()
    else:
        print("TalorianTP not found at", TALORIAN_DIR, "-> running standalone AttuneParser suites only")
        check_lua51_scopes(include_talorian=False)
        run_standalone_integrations_tests()
        run_real_attune_parser_core_tests()
