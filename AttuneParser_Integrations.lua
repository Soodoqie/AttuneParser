-- AttuneParser_Integrations.lua - Тесная интеграция с Путеводителем по приключениям (EJ),
-- самодостаточный помощник аукциона (PrimeAH + 3.3.5) и оповещения обмена (Trade).
local AP = rawget(_G, "AttuneParser")
if not AP then return end

AP._hasStandaloneUI = true
AP._hasStandaloneAuctionUI = true
AP._hasStandaloneTradeAlert = true

local PS = AP.Skin

local QUAL_HEX = {
    [0] = "|cff9d9d9d",
    [1] = "|cffffffff",
    [2] = "|cff1eff00",
    [3] = "|cff0070dd",
    [4] = "|cffa335ee",
    [5] = "|cffff8000",
}

local function ItemColorName(it)
    local qCol = QUAL_HEX[(it and it.quality) or 2] or "|cffffffff"
    return qCol .. tostring((it and it.name) or ("Предмет #" .. tostring(it and it.itemId or "?"))) .. "|r"
end

---------------------------------------------------------------------------
-- 1. Путеводитель по приключениям (EncounterJournal): API, оверлей, метки лута
---------------------------------------------------------------------------
do
    local ejCache = { built = false, byZoneId = {}, byEjId = {}, entries = {} }
    local ejOverlay
    local pendingOpen = nil
    local hookInstalled = false
    local badgeTimer = 0

    local function SafeCall(fn, ...)
        if type(fn) ~= "function" then return false end
        return pcall(fn, ...)
    end

    local function BuildEJIndex(force)
        if ejCache.built and not force then return #ejCache.entries > 0 end
        local getNumTiers = rawget(_G, "EJ_GetNumTiers")
        local selTier = rawget(_G, "EJ_SelectTier")
        local curTierFn = rawget(_G, "EJ_GetCurrentTier")
        local getInstByIdx = rawget(_G, "EJ_GetInstanceByIndex")
        if type(getInstByIdx) ~= "function" then return false end

        local prevTier = nil
        if type(curTierFn) == "function" then
            local ok, t = pcall(curTierFn)
            if ok and t then prevTier = t end
        end

        ejCache.byZoneId = {}
        ejCache.byEjId = {}
        ejCache.entries = {}

        local numTiers = 3
        if type(getNumTiers) == "function" then
            local ok, nt = pcall(getNumTiers)
            if ok and nt and nt > 0 then numTiers = nt end
        end

        for tier = 1, numTiers do
            if type(selTier) == "function" then pcall(selTier, tier) end
            for _, isRaid in ipairs({ false, true }) do
                for idx = 1, 60 do
                    local ok, ejId, name, _, _, _, _, areaMapId = pcall(getInstByIdx, idx, isRaid)
                    if not ok or not ejId then break end
                    local zid = AP:FindZoneByName(name, isRaid)
                    local rec = {
                        ejId = ejId,
                        name = name,
                        isRaid = isRaid,
                        tier = tier,
                        areaMapId = areaMapId,
                        zoneId = zid,
                    }
                    table.insert(ejCache.entries, rec)
                    ejCache.byEjId[ejId] = rec
                    if zid and not ejCache.byZoneId[zid] then
                        ejCache.byZoneId[zid] = rec
                    end
                end
            end
        end

        if prevTier and type(selTier) == "function" then
            pcall(selTier, prevTier)
        end
        if #ejCache.entries > 0 then
            ejCache.built = true
        end
        return ejCache.built
    end

    local function ExtractEJText(obj)
        if not obj or type(obj) ~= "table" then return nil end
        if type(obj.GetText) == "function" then
            local ok, txt = pcall(obj.GetText, obj)
            if ok and type(txt) == "string" and txt ~= "" then return txt end
        end
        return nil
    end

    function AP:GetCurrentEJContext()
        local ej = rawget(_G, "EncounterJournal")
        if not ej or not ej:IsShown() then
            return { open = false }
        end
        BuildEJIndex(false)

        local ejId = tonumber(ej.instanceID)
        if (not ejId) and ej.encounter then
            ejId = tonumber(ej.encounter.instanceID)
        end
        if (not ejId) and type(ej.instance) == "table" then
            ejId = tonumber(ej.instance.instanceID)
        end

        local rec = ejId and ejCache.byEjId[ejId] or nil
        local zid = rec and rec.zoneId or nil
        local zName = rec and rec.name or nil

        if not zid then
            local titleCandidates = {}
            if ej.encounter and ej.encounter.instance then
                table.insert(titleCandidates, ExtractEJText(ej.encounter.instance.title))
                table.insert(titleCandidates, ExtractEJText(ej.encounter.instance.Title))
            end
            if ej.encounter and ej.encounter.info then
                table.insert(titleCandidates, ExtractEJText(ej.encounter.info.instanceTitle))
            end
            if ej.instanceSelect and ej.instanceSelect.bg and ej.instanceSelect.title then
                table.insert(titleCandidates, ExtractEJText(ej.instanceSelect.title))
            end
            local navBar = rawget(_G, "EncounterJournalNavBar")
            if navBar and navBar.navList and type(navBar.navList) == "table" and navBar.navList[2] then
                table.insert(titleCandidates, ExtractEJText(navBar.navList[2]))
            end
            for _, cand in ipairs(titleCandidates) do
                if cand and cand ~= "" then
                    local fz, zMeta = AP:FindZoneByName(cand)
                    if fz then
                        zid = fz
                        zName = (zMeta and zMeta.name) or cand
                        break
                    end
                end
            end
        end

        if zid and not zName then
            local zMeta = AP.Data and AP.Data.Zones and AP.Data.Zones[zid]
            zName = zMeta and zMeta.name or ("Зона " .. zid)
        end

        return {
            open = true,
            ejId = ejId,
            zoneId = zid,
            zoneName = zName,
            rec = rec,
        }
    end

    local function WalkEJWidgets(root, fn, depth, seen)
        if not root then return end
        seen = seen or {}
        if seen[root] then return end
        seen[root] = true
        depth = depth or 0
        if depth > 10 then return end
        local okVis, vis = pcall(root.IsVisible, root)
        if not okVis or not vis then return end
        if fn(root) == true then return true end
        local okC, kids = pcall(function() return { root:GetChildren() } end)
        if okC and type(kids) == "table" then
            for _, ch in ipairs(kids) do
                if WalkEJWidgets(ch, fn, depth + 1, seen) then return true end
            end
        end
        return false
    end

    local function ExtractButtonText(btn)
        if not btn then return "" end
        local parts = {}
        if type(btn.GetText) == "function" then
            local ok, t = pcall(btn.GetText, btn)
            if ok and type(t) == "string" and t ~= "" then table.insert(parts, t) end
        end
        if type(btn.GetRegions) == "function" then
            local okR, regs = pcall(function() return { btn:GetRegions() } end)
            if okR and type(regs) == "table" then
                for _, rg in ipairs(regs) do
                    if rg and type(rg.GetObjectType) == "function" and rg:GetObjectType() == "FontString" and type(rg.GetText) == "function" then
                        local okT, rt = pcall(rg.GetText, rg)
                        if okT and type(rt) == "string" and rt ~= "" then table.insert(parts, rt) end
                    end
                end
            end
        end
        if type(btn.Text) == "table" and type(btn.Text.GetText) == "function" then
            local okT, rt = pcall(btn.Text.GetText, btn.Text)
            if okT and type(rt) == "string" and rt ~= "" then table.insert(parts, rt) end
        end
        if type(btn.text) == "table" and type(btn.text.GetText) == "function" then
            local okT, rt = pcall(btn.text.GetText, btn.text)
            if okT and type(rt) == "string" and rt ~= "" then table.insert(parts, rt) end
        end
        local bNm = type(btn.GetName) == "function" and btn:GetName() or nil
        if bNm then
            local txObj = rawget(_G, bNm .. "Text")
            if txObj and type(txObj.GetText) == "function" then
                local okT, rt = pcall(txObj.GetText, txObj)
                if okT and type(rt) == "string" and rt ~= "" then table.insert(parts, rt) end
            end
        end
        if type(btn.title) == "table" and type(btn.title.GetText) == "function" then
            local okT, rt = pcall(btn.title.GetText, btn.title)
            if okT and type(rt) == "string" and rt ~= "" then table.insert(parts, rt) end
        end
        if type(btn.name) == "table" and type(btn.name.GetText) == "function" then
            local okT, rt = pcall(btn.name.GetText, btn.name)
            if okT and type(rt) == "string" and rt ~= "" then table.insert(parts, rt) end
        end
        return table.concat(parts, " ")
    end

    local function DiffTextMatches(txt, wantPlayers, wantHeroic)
        local n = AP.Norm(txt or "")
        if n == "" then return false end
        if wantPlayers and not n:find(tostring(wantPlayers), 1, true) then
            return false
        end
        local looksHeroic = (n:find("гер", 1, true) ~= nil) or (n:find("hero", 1, true) ~= nil)
        if wantHeroic == true then
            return looksHeroic
        elseif wantHeroic == false then
            return not looksHeroic
        end
        return true
    end

    local function FindEJDifficultyButtons(ej)
        local list, seen = {}, {}
        local function AddBtn(b)
            if b and not seen[b] and b.IsVisible and b:IsVisible() then
                seen[b] = true
                table.insert(list, b)
            end
        end
        AddBtn(rawget(_G, "EncounterJournalEncounterFrameInfoDifficulty"))
        AddBtn(rawget(_G, "EncounterJournalEncounterFrameInstanceDifficulty"))
        if ej and ej.encounter and ej.encounter.info then AddBtn(ej.encounter.info.difficulty) end
        if ej and ej.encounter and ej.encounter.instance then AddBtn(ej.encounter.instance.difficulty) end
        WalkEJWidgets(ej, function(w)
            if w and type(w.GetObjectType) == "function" and w:GetObjectType() == "Button" then
                local nm = (type(w.GetName) == "function" and w:GetName()) or ""
                local low = AP.Norm(ExtractButtonText(w))
                if nm:find("Difficulty", 1, true) or low:find("обыч", 1, true) or low:find("героич", 1, true) or low:find("игрок", 1, true) then
                    AddBtn(w)
                end
            end
        end)
        return list
    end

    local function FindEJDifficultyButton(ej)
        return FindEJDifficultyButtons(ej)[1]
    end

    local function GetValidEJDiffIDs()
        local isValidFn = rawget(_G, "EJ_IsValidInstanceDifficulty")
        local out = {}
        for _, did in ipairs({ 6, 5, 4, 3, 2, 1, 16, 15, 14 }) do
            if type(isValidFn) == "function" then
                local ok, valid = pcall(isValidFn, did)
                if ok and valid then table.insert(out, did) end
            end
        end
        if #out == 0 then
            out = { 6, 5, 4, 3, 2, 1 }
        end
        return out
    end

    local function ResolveTargetDiffIntent(zoneId, itemId, diffMask)
        if not itemId then return nil, nil, nil end
        local dTag = AP.GetItemDiffTag and AP:GetItemDiffTag(itemId, zoneId, diffMask, true) or ""
        if dTag == "" then return nil, nil, nil end
        local wantPlayers = dTag:find("25", 1, true) and 25 or (dTag:find("10", 1, true) and 10 or nil)
        local wantHeroic = nil
        if dTag:find("гер", 1, true) ~= nil or dTag:find("Героич", 1, true) ~= nil then
            wantHeroic = true
        elseif dTag:find("об", 1, true) ~= nil or dTag:find("Обыч", 1, true) ~= nil then
            wantHeroic = false
        end

        local isValidFn = rawget(_G, "EJ_IsValidInstanceDifficulty")
        local getDiffInfoFn = rawget(_G, "GetDifficultyInfo")
        local targetId = nil

        if type(getDiffInfoFn) == "function" then
            for _, did in ipairs(GetValidEJDiffIDs()) do
                local ok, dName, _, isH = pcall(getDiffInfoFn, did)
                if ok and dName then
                    local nmMatch = DiffTextMatches(dName, wantPlayers, wantHeroic)
                    if nmMatch and (wantHeroic == nil or isH == wantHeroic or (dName:find("гер", 1, true) ~= nil) == wantHeroic) then
                        targetId = did
                        break
                    end
                end
            end
        end

        if not targetId then
            local isRetailRaid = (type(isValidFn) == "function") and (
                select(2, pcall(isValidFn, 3)) == true
                or select(2, pcall(isValidFn, 5)) == true
                or select(2, pcall(isValidFn, 6)) == true
            )
            if wantPlayers == 25 and wantHeroic == true then
                targetId = isRetailRaid and 6 or 4
            elseif wantPlayers == 10 and wantHeroic == true then
                targetId = isRetailRaid and 5 or 3
            elseif wantPlayers == 25 and wantHeroic == false then
                targetId = isRetailRaid and 4 or 2
            elseif wantPlayers == 10 and wantHeroic == false then
                targetId = isRetailRaid and 3 or 1
            elseif wantHeroic == true then
                targetId = 2
            elseif wantHeroic == false then
                targetId = 1
            end
        end
        return targetId, wantPlayers, wantHeroic
    end

    local function TriggerButtonMenu(btn)
        if not btn then return false end
        if type(btn.Click) == "function" then pcall(btn.Click, btn) end
        local dd1 = rawget(_G, "DropDownList1")
        if dd1 and dd1:IsShown() then return true end
        local bName = (type(btn.GetName) == "function") and btn:GetName() or nil
        local subBtn = btn.Button or (bName and rawget(_G, bName .. "Button"))
        if subBtn and type(subBtn.Click) == "function" then
            pcall(subBtn.Click, subBtn)
            dd1 = rawget(_G, "DropDownList1")
            if dd1 and dd1:IsShown() then return true end
        end
        local onMD = btn.GetScript and btn:GetScript("OnMouseDown")
        if type(onMD) == "function" then pcall(onMD, btn, "LeftButton") end
        dd1 = rawget(_G, "DropDownList1")
        return (dd1 and dd1:IsShown()) and true or false
    end

    local function ApplyEJDifficultyID(ej, diffId, wantPlayers, wantHeroic)
        if diffId then
            local setDiff = rawget(_G, "EJ_SetDifficulty")
            local ejSetDiff = rawget(_G, "EncounterJournal_SetDifficulty")
            local selDiff = rawget(_G, "EncounterJournal_SelectDifficulty")
            local updDiff = rawget(_G, "EncounterJournal_UpdateDifficulty")
            local lootUpd = rawget(_G, "EncounterJournal_LootUpdate")
            if type(setDiff) == "function" then pcall(setDiff, diffId) end
            if type(ejSetDiff) == "function" then pcall(ejSetDiff, diffId) end
            if type(selDiff) == "function" then
                pcall(selDiff, nil, diffId)
                local getDiff = rawget(_G, "EJ_GetDifficulty")
                local curD = nil
                if type(getDiff) == "function" then
                    local okG, dVal = pcall(getDiff)
                    if okG then curD = dVal end
                end
                if curD ~= diffId then
                    pcall(selDiff, diffId)
                end
            end
            if type(updDiff) == "function" then pcall(updDiff, diffId) end
            if type(lootUpd) == "function" then pcall(lootUpd) end
        end

        if wantPlayers or wantHeroic ~= nil then
            for _, dbBtn in ipairs(FindEJDifficultyButtons(ej)) do
                local curTxt = ExtractButtonText(dbBtn)
                if not DiffTextMatches(curTxt, wantPlayers, wantHeroic) then
                    if TriggerButtonMenu(dbBtn) then
                        for listIdx = 1, 2 do
                            local dd = rawget(_G, "DropDownList" .. listIdx)
                            if dd and dd:IsShown() then
                                for bi = 1, 16 do
                                    local itemBtn = rawget(_G, "DropDownList" .. listIdx .. "Button" .. bi)
                                    if itemBtn and itemBtn:IsShown() then
                                        local bTxt = ExtractButtonText(itemBtn)
                                        if DiffTextMatches(bTxt, wantPlayers, wantHeroic) then
                                            if type(itemBtn.Click) == "function" then pcall(itemBtn.Click, itemBtn) end
                                            break
                                        end
                                    end
                                end
                            end
                        end
                        if type(_G.CloseDropDownMenus) == "function" then
                            pcall(_G.CloseDropDownMenus)
                        end
                    end
                    if DiffTextMatches(ExtractButtonText(dbBtn), wantPlayers, wantHeroic) then
                        break
                    end
                end
            end
        end
    end

    local function ClearEJClassFilter(ej)
        local resetFilter = rawget(_G, "EJ_ResetLootFilter")
        local setFilter = rawget(_G, "EJ_SetLootFilter")
        if type(resetFilter) == "function" then
            pcall(resetFilter)
        elseif type(setFilter) == "function" then
            pcall(setFilter, 0, 0)
        end

        local clearFrame = rawget(_G, "EncounterJournalEncounterFrameInfoLootScrollFrameClassFilterClearFrame")
            or (ej and ej.encounter and ej.encounter.info and ej.encounter.info.lootScroll and ej.encounter.info.lootScroll.classClearFilter)
        local function ClickBtnOrMouse(b)
            if not b then return false end
            if type(b.Click) == "function" then pcall(b.Click, b); return true end
            local onUp = b.GetScript and b:GetScript("OnMouseUp")
            if type(onUp) == "function" then pcall(onUp, b, "LeftButton"); return true end
            return false
        end

        local function ClickClearChildren(frm)
            if not frm or (frm.IsVisible and not frm:IsVisible()) then return false end
            if frm.GetObjectType and frm:GetObjectType() == "Button" then
                return ClickBtnOrMouse(frm)
            end
            for _, fn in ipairs({ frm.exitButton, frm.clearButton, frm.ExitButton, frm.ClearButton, frm.close, frm.CloseButton }) do
                if ClickBtnOrMouse(fn) then return true end
            end
            local okC, kids = pcall(function() return { frm:GetChildren() } end)
            if okC and type(kids) == "table" then
                for _, ch in ipairs(kids) do
                    if ch and ch.GetObjectType and ch:GetObjectType() == "Button" then
                        if ClickBtnOrMouse(ch) then return true end
                    end
                end
            end
            return false
        end

        if not ClickClearChildren(clearFrame) and ej then
            WalkEJWidgets(ej, function(w)
                local txt = AP.Norm(ExtractButtonText(w))
                local nm = (type(w.GetName) == "function" and w:GetName()) or ""
                if nm:find("ClassFilter", 1, true) or txt:find("фильтр по классу", 1, true) or txt:find("class filter", 1, true) then
                    if ClickClearChildren(w) then return true end
                end
            end)
        end
        if type(_G.EncounterJournal_LootUpdate) == "function" then
            pcall(_G.EncounterJournal_LootUpdate)
        end
    end

    local function ExtractEncounterEntry(getNumEnc, eIdx, ejId)
        local r = { pcall(getNumEnc, eIdx) }
        if (not r[1]) or (#r < 2) then
            r = { pcall(getNumEnc, eIdx, ejId) }
        end
        if not r[1] or not r[2] then return nil, nil end
        local eName, eId = nil, nil
        for k = 2, 7 do
            local v = r[k]
            if (not eName) and type(v) == "string" and v ~= "" and not v:find("^|H") and not v:find("^Interface\\") then
                eName = v
            elseif (not eId) and type(v) == "number" and v > 0 then
                eId = v
            end
        end
        return eId, eName
    end

    local function CheckLootMatchesItem(getLoot, lIdx, itemId)
        local r = { pcall(getLoot, lIdx) }
        if not r[1] then return false end
        if type(r[2]) == "table" then
            local t = r[2]
            local lid = tonumber(t.itemID or t.itemId) or (t.link and AP.ExtractItemId(t.link))
            return lid == itemId
        end
        for k = 2, 8 do
            local v = r[k]
            if type(v) == "number" and v == itemId then
                return true
            elseif type(v) == "string" and v:find("item:" .. itemId, 1, true) then
                if AP.ExtractItemId(v) == itemId then return true end
            end
        end
        return false
    end

    local function ScanEncountersForItem(itemId, ejId)
        local getNumEnc = rawget(_G, "EJ_GetEncounterInfoByIndex")
        local selEnc = rawget(_G, "EJ_SelectEncounter")
        local getNumLoot = rawget(_G, "EJ_GetNumLoot")
        local getLoot = rawget(_G, "EJ_GetLootInfoByIndex")
        if type(getNumEnc) ~= "function" then return nil, nil end

        local list = {}
        for eIdx = 1, 35 do
            local encId, encName = ExtractEncounterEntry(getNumEnc, eIdx, ejId)
            if not encId then break end
            table.insert(list, { encId = encId, encName = encName })
            if type(selEnc) == "function" and type(getNumLoot) == "function" and type(getLoot) == "function" then
                pcall(selEnc, encId)
                local okN, nLoot = pcall(getNumLoot)
                if okN and nLoot and nLoot > 0 then
                    for lIdx = 1, nLoot do
                        if CheckLootMatchesItem(getLoot, lIdx, itemId) then
                            return encId, encName
                        end
                    end
                end
            end
        end
        return nil, nil, list
    end

    local function OpenLootTabInEJ(ej)
        if type(_G.EncounterJournal_ShowLootTab) == "function" then
            pcall(_G.EncounterJournal_ShowLootTab)
        end
        if type(_G.EncounterJournal_SetTab) == "function" then
            pcall(_G.EncounterJournal_SetTab, 2)
        end
        local lt = rawget(_G, "EncounterJournalEncounterFrameInfoLootTab")
            or (ej and ej.encounter and ej.encounter.info and ej.encounter.info.lootTab)
        if lt and type(lt.Click) == "function" then
            pcall(lt.Click, lt)
            return true
        end
        WalkEJWidgets(ej, function(w)
            if w and type(w.GetObjectType) == "function" and w:GetObjectType() == "Button" then
                local nm = (type(w.GetName) == "function" and w:GetName()) or ""
                local txt = AP.Norm(ExtractButtonText(w))
                if nm:find("LootTab", 1, true) or txt == "добыча" or txt == "loot" then
                    if type(w.Click) == "function" then pcall(w.Click, w) end
                    return true
                end
            end
        end)
        return false
    end

    local function ClickBossButtonInEJ(ej, bossNameNorm)
        if not ej or not bossNameNorm or bossNameNorm == "" then return false end
        local clicked = false
        WalkEJWidgets(ej, function(w)
            if w and type(w.GetObjectType) == "function" and w:GetObjectType() == "Button" then
                local nm = (type(w.GetName) == "function" and w:GetName()) or ""
                if not nm:find("Tab", 1, true) and not nm:find("Difficulty", 1, true) and not nm:find("Close", 1, true) then
                    local txt = AP.Norm(ExtractButtonText(w))
                    if txt ~= "" and (txt == bossNameNorm or txt:find(bossNameNorm, 1, true) or bossNameNorm:find(txt, 1, true)) then
                        if type(w.Click) == "function" then
                            pcall(w.Click, w)
                            clicked = true
                            return true
                        end
                    end
                end
            end
        end)
        return clicked
    end

    local function FindAndFocusBossForItem(ej, rec, zoneId, itemId, diffMask)
        local targetDiffId, wantPlayers, wantHeroic = ResolveTargetDiffIntent(zoneId, itemId, diffMask)
        ApplyEJDifficultyID(ej, targetDiffId, wantPlayers, wantHeroic)
        ClearEJClassFilter(ej)

        local encId, encName, encList = ScanEncountersForItem(itemId, rec and rec.ejId)
        local usedDiffId = targetDiffId

        if not encId then
            local setDiff = rawget(_G, "EJ_SetDifficulty")
            for _, altId in ipairs(GetValidEJDiffIDs()) do
                if altId ~= targetDiffId and type(setDiff) == "function" then
                    pcall(setDiff, altId)
                    local e2, n2 = ScanEncountersForItem(itemId, rec and rec.ejId)
                    if e2 then
                        encId, encName, usedDiffId = e2, n2, altId
                        break
                    end
                end
            end
            if not encId and targetDiffId then
                ApplyEJDifficultyID(ej, targetDiffId, wantPlayers, wantHeroic)
            end
        end

        if (not encId) and type(rawget(_G, "EJ_SetSearch")) == "function" and type(rawget(_G, "EJ_GetNumSearchResults")) == "function" and type(rawget(_G, "EJ_GetSearchResult")) == "function" then
            local info = AP:GetItemInfo(itemId)
            local qName = info and info.name
            if qName and qName ~= "" then
                pcall(_G.EJ_SetSearch, qName)
                local okS, cnt = pcall(_G.EJ_GetNumSearchResults)
                if okS and cnt and cnt > 0 then
                    for si = 1, math.min(20, cnt) do
                        local r = { pcall(_G.EJ_GetSearchResult, si) }
                        if r[1] then
                            local matchedItem = false
                            for k = 2, 8 do
                                if r[k] == itemId or (type(r[k]) == "string" and AP.ExtractItemId(r[k]) == itemId) then
                                    matchedItem = true
                                    break
                                end
                            end
                            if matchedItem then
                                local sEnc = tonumber(r[6]) or tonumber(r[5])
                                if sEnc and sEnc > 0 then
                                    encId = sEnc
                                    break
                                end
                            end
                        end
                    end
                end
                if type(_G.EJ_ClearSearch) == "function" then pcall(_G.EJ_ClearSearch) end
            end
        end

        if (not encId) and type(AP.GetItemSources) == "function" then
            local src = AP:GetItemSources(itemId)
            for _, sc in ipairs((src and src.list) or {}) do
                if sc.st == 1 and sc.name and sc.name ~= "" then
                    local q = AP.Norm(sc.name)
                    if encList then
                        for _, ec in ipairs(encList) do
                            local en = AP.Norm(ec.encName or "")
                            if en ~= "" and (en == q or en:find(q, 1, true) or q:find(en, 1, true)) then
                                encId, encName = ec.encId, ec.encName
                                break
                            end
                        end
                    end
                    if not encId then
                        encName = sc.name
                    end
                    if encId then break end
                end
            end
        end

        if usedDiffId then
            ApplyEJDifficultyID(ej, usedDiffId, wantPlayers, wantHeroic)
        end

        local openedBoss = false
        if encId then
            local selEnc = rawget(_G, "EJ_SelectEncounter")
            local dispEnc = rawget(_G, "EncounterJournal_DisplayEncounter")
            local openFn = rawget(_G, "EncounterJournal_OpenJournal")
            if type(selEnc) == "function" then pcall(selEnc, encId) end
            if type(dispEnc) == "function" then
                pcall(dispEnc, encId)
                openedBoss = true
            elseif type(openFn) == "function" then
                pcall(openFn, rec and rec.tier, rec and rec.ejId, encId)
                openedBoss = true
            end
        end

        local infoShown = ej and ej.encounter and ej.encounter.info and ej.encounter.info:IsShown()
        if (not openedBoss or not infoShown) and encName then
            ClickBossButtonInEJ(ej, AP.Norm(encName))
        end

        ClearEJClassFilter(ej)
        OpenLootTabInEJ(ej)
        AP.After(0.12, function()
            local tDiff, wPl, wHr = usedDiffId or targetDiffId, wantPlayers, wantHeroic
            if tDiff or wPl or wHr ~= nil then
                ApplyEJDifficultyID(ej, tDiff, wPl, wHr)
            end
            ClearEJClassFilter(ej)
            OpenLootTabInEJ(ej)
            UpdateEJLootBadges()
        end, "ap_ej_boss_loot")
    end

    local function ApplyPendingEJTarget()
        if not pendingOpen then return end
        local p = pendingOpen
        pendingOpen = nil
        local ej = rawget(_G, "EncounterJournal")
        if not ej then return end
        if not ej:IsShown() then
            if type(_G.ShowUIPanel) == "function" then
                pcall(_G.ShowUIPanel, ej)
            else
                ej:Show()
            end
        end
        BuildEJIndex(false)
        local curCtx = AP:GetCurrentEJContext()
        local rec = (p.zoneId and ejCache.byZoneId[p.zoneId]) or curCtx.rec
        if not rec and p.zoneName then
            local fz = AP:FindZoneByName(p.zoneName)
            if fz then rec = ejCache.byZoneId[fz] end
        end
        if not rec and p.zoneName then
            local q = AP.Norm(p.zoneName)
            for _, cand in ipairs(ejCache.entries) do
                if cand.name and (AP.Norm(cand.name) == q or AP.Norm(cand.name):find(q, 1, true)) then
                    rec = cand
                    break
                end
            end
        end
        if rec or (p.zoneId and curCtx.zoneId == p.zoneId) then
            local sameInst = rec and (curCtx.ejId == rec.ejId or curCtx.zoneId == rec.zoneId)
            if rec and not sameInst then
                local selTier = rawget(_G, "EJ_SelectTier")
                if selTier and rec.tier then pcall(selTier, rec.tier) end
                local dispInst = rawget(_G, "EncounterJournal_DisplayInstance")
                local selInst = rawget(_G, "EJ_SelectInstance")
                local openFn = rawget(_G, "EncounterJournal_OpenJournal")
                if type(dispInst) == "function" then
                    pcall(dispInst, rec.ejId)
                elseif type(openFn) == "function" then
                    pcall(openFn, rec.tier, rec.ejId)
                elseif type(selInst) == "function" then
                    pcall(selInst, rec.ejId)
                end
            end
            if p.itemId then
                FindAndFocusBossForItem(ej, rec, p.zoneId or (rec and rec.zoneId), p.itemId, p.diffMask)
            end
        elseif p.zoneName then
            DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Инст не найден в Путеводителе: " .. tostring(p.zoneName))
        end
        AP.After(0.18, function()
            if AP.RefreshEJOverlay then AP:RefreshEJOverlay() end
        end, "ap_ej_post_open")
    end

    function AP:OpenEncounterJournal(zoneIdOrName, itemId, diffMask)
        local zid, zName = nil, nil
        if type(zoneIdOrName) == "number" then
            zid = (AP.Data and AP.Data.TopMap and AP.Data.TopMap[zoneIdOrName]) or zoneIdOrName
            local zm = AP.Data and AP.Data.Zones and AP.Data.Zones[zid]
            zName = zm and zm.name or nil
        elseif type(zoneIdOrName) == "string" and zoneIdOrName ~= "" then
            zid = AP:FindZoneByName(zoneIdOrName)
            local zm = zid and AP.Data and AP.Data.Zones and AP.Data.Zones[zid]
            zName = (zm and zm.name) or zoneIdOrName
        end

        if zid and zid > 0 and type(AP.IsZoneInstance) == "function" and not AP:IsZoneInstance(zid) then
            DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r " .. tostring(zName or zid) .. " - открытая локация (не инст Путеводителя).")
            return false
        end

        pendingOpen = (zid or zName or itemId) and { zoneId = zid, zoneName = zName, itemId = itemId, diffMask = diffMask } or nil

        local ej = rawget(_G, "EncounterJournal")
        if not ej then
            if type(_G.EncounterJournal_LoadUI) == "function" then
                pcall(_G.EncounterJournal_LoadUI)
            elseif type(_G.UIParentLoadAddOn) == "function" then
                pcall(_G.UIParentLoadAddOn, "Blizzard_EncounterJournal")
            end
            ej = rawget(_G, "EncounterJournal")
            if not ej then
                local mb = rawget(_G, "EncounterJournalMicroButton")
                if mb and type(mb.Click) == "function" then
                    pcall(mb.Click, mb)
                end
            end
        end

        ej = rawget(_G, "EncounterJournal")
        if not ej then
            if pendingOpen then
                AP.After(0.25, ApplyPendingEJTarget, "ap_ej_wait_load")
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Путеводитель по приключениям недоступен на этом клиенте.")
            end
            return false
        end

        if not ej:IsShown() then
            local toggleFn = rawget(_G, "ToggleEncounterJournal")
            if type(toggleFn) == "function" then
                pcall(toggleFn)
            elseif _G.EncounterJournalMicroButton and type(_G.EncounterJournalMicroButton.Click) == "function" then
                pcall(_G.EncounterJournalMicroButton.Click, _G.EncounterJournalMicroButton)
            elseif type(_G.ShowUIPanel) == "function" then
                pcall(_G.ShowUIPanel, ej)
            else
                ej:Show()
            end
        end

        if pendingOpen then
            AP.After(0.06, ApplyPendingEJTarget, "ap_ej_apply")
        else
            AP.After(0.08, function()
                if AP.RefreshEJOverlay then AP:RefreshEJOverlay() end
            end, "ap_ej_refresh")
        end
        return true
    end

    function AP:ToggleEncounterJournal()
        local ej = rawget(_G, "EncounterJournal")
        if ej and ej:IsShown() then
            local toggleFn = rawget(_G, "ToggleEncounterJournal")
            if type(toggleFn) == "function" then
                pcall(toggleFn)
            elseif type(_G.HideUIPanel) == "function" then
                pcall(_G.HideUIPanel, ej)
                if ej:IsShown() then ej:Hide() end
            else
                ej:Hide()
            end
            return false
        end
        return AP:OpenEncounterJournal()
    end

    function AP:DebugEJ()
        local ej = rawget(_G, "EncounterJournal")
        local ctx = AP:GetCurrentEJContext()
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff38bdf8[EJ Debug]|r frame=%s shown=%s ejId=%s zone=%s entries=%d",
            tostring(ej ~= nil), tostring(ej and ej:IsShown()), tostring(ctx.ejId), tostring(ctx.zoneId), #ejCache.entries))
        local fns = {}
        for _, fn in ipairs({ "EJ_SetDifficulty", "EJ_GetDifficulty", "EJ_IsValidInstanceDifficulty", "EJ_GetEncounterInfoByIndex", "EJ_SelectEncounter", "EJ_GetNumLoot", "EJ_GetLootInfoByIndex", "EncounterJournal_DisplayEncounter", "EncounterJournal_OpenJournal", "EncounterJournal_SelectDifficulty", "EncounterJournal_ShowLootTab", "EncounterJournal_SetTab" }) do
            if type(rawget(_G, fn)) == "function" then table.insert(fns, fn) end
        end
        DEFAULT_CHAT_FRAME:AddMessage("  APIs: " .. (#fns > 0 and table.concat(fns, ", ") or "none"))
        local dbList = FindEJDifficultyButtons(ej)
        local dbParts = {}
        for _, db in ipairs(dbList) do
            table.insert(dbParts, tostring(db:GetName() or "anon") .. "=" .. tostring(ExtractButtonText(db)))
        end
        DEFAULT_CHAT_FRAME:AddMessage("  DiffBtns(" .. #dbParts .. "): " .. table.concat(dbParts, " | "))
        local vDiffs = GetValidEJDiffIDs()
        local gdi = rawget(_G, "GetDifficultyInfo")
        local vdParts = {}
        for _, did in ipairs(vDiffs) do
            local dNm = gdi and select(2, pcall(gdi, did)) or "?"
            table.insert(vdParts, did .. "(" .. tostring(dNm) .. ")")
        end
        DEFAULT_CHAT_FRAME:AddMessage("  ValidDiffs: " .. table.concat(vdParts, ", ") .. " cur=" .. tostring(_G.EJ_GetDifficulty and select(2, pcall(_G.EJ_GetDifficulty))))
        local c1, c2 = nil, nil
        if _G.EJ_GetLootFilter then
            local okF, f1, f2 = pcall(_G.EJ_GetLootFilter)
            if okF then c1, c2 = f1, f2 end
        end
        DEFAULT_CHAT_FRAME:AddMessage("  LootFilter: cls=" .. tostring(c1) .. " spec=" .. tostring(c2) .. " clearBtn=" .. tostring(rawget(_G, "EncounterJournalEncounterFrameInfoLootScrollFrameClassFilterClearFrame") ~= nil))
        local gEnc = rawget(_G, "EJ_GetEncounterInfoByIndex")
        if gEnc then
            local eId, eNm = ExtractEncounterEntry(gEnc, 1, ctx.ejId)
            DEFAULT_CHAT_FRAME:AddMessage("  Boss#1: id=" .. tostring(eId) .. " name=" .. tostring(eNm))
        end
    end

    local function UpdateSingleLootButton(btn)
        if not btn or not btn:IsShown() then return end
        if AP:GetSetting("showEJBadges") == false then
            if btn._apBadge then btn._apBadge:Hide() end
            return
        end
        local itemId = tonumber(btn.itemID or btn.itemId)
        if not itemId and type(btn.link) == "string" then
            itemId = AP.ExtractItemId(btn.link)
        end
        if not itemId and btn.itemLink then
            itemId = AP.ExtractItemId(btn.itemLink)
        end
        if not itemId then
            if btn._apBadge then btn._apBadge:Hide() end
            return
        end
        if not btn._apBadge then
            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -6, -4)
            fs:SetJustifyH("RIGHT")
            btn._apBadge = fs
        end
        local link = btn.link or btn.itemLink
        local usable, accOk = AP:CanHeroAbsorb(itemId, link)
        local info = AP:GetItemInfo(itemId, link)
        if not info or info.noAttune then
            btn._apBadge:Hide()
            return
        end
        local txt = ""
        if info.isCompleted then
            txt = "|cff64748b90%|r"
        elseif usable then
            if info.isNew then
                txt = "|cff40ff40+" .. (info.newBasePct or 20) .. "%|r"
            elseif info.needsForge then
                txt = "|cffffd200Ков " .. (info.curPct or 0) .. "%->90%|r"
            end
            if AP:IsItemBlacklisted(itemId, nil) then
                txt = txt .. " |cffff5050[ЧС]|r"
            end
        elseif accOk then
            txt = "|cff38bdf8Твин|r"
        end
        if txt ~= "" then
            btn._apBadge:SetText(txt)
            btn._apBadge:Show()
        else
            btn._apBadge:Hide()
        end
    end

    local function UpdateEJLootBadges()
        local ej = rawget(_G, "EncounterJournal")
        if not ej or not ej:IsShown() then return end
        local scrollChild = rawget(_G, "EncounterJournalEncounterFrameInfoLootScrollFrameScrollChild")
        if (not scrollChild) and ej.encounter and ej.encounter.info and ej.encounter.info.lootScroll then
            local ls = ej.encounter.info.lootScroll
            if type(ls.buttons) == "table" then
                for _, b in ipairs(ls.buttons) do
                    pcall(UpdateSingleLootButton, b)
                end
                return
            end
            scrollChild = ls.scrollChild
        end
        if scrollChild and scrollChild.GetChildren then
            for _, child in ipairs({ scrollChild:GetChildren() }) do
                pcall(UpdateSingleLootButton, child)
            end
        end
    end

    local function AnchorEJOverlay()
        if not ejOverlay then return end
        local ej = rawget(_G, "EncounterJournal")
        local docked = AP:GetSetting("ejDocked") ~= false
        if ejOverlay.dockBtn and ejOverlay.dockBtn.label then
            ejOverlay.dockBtn.label:SetText(docked and "Открепить" or "Прикрепить")
        end
        ejOverlay:ClearAllPoints()
        if not docked then
            local pos = AP:GetSetting("ejFramePos")
            if type(pos) == "table" and pos.point and pos.x and pos.y then
                ejOverlay:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
                return
            end
        end
        if not ej then
            ejOverlay:SetPoint("RIGHT", UIParent, "RIGHT", -24, 0)
            return
        end
        local side = AP:GetSetting("ejOverlaySide")
        if side == "LEFT" then
            ejOverlay:SetPoint("TOPRIGHT", ej, "TOPLEFT", -4, 0)
        else
            ejOverlay:SetPoint("TOPLEFT", ej, "TOPRIGHT", 4, 0)
        end
    end

    local function EnsureEJOverlay()
        if ejOverlay then return ejOverlay end
        local f = CreateFrame("Frame", "AttuneParserEJOverlay", UIParent)
        f:SetSize(318, 480)
        f:SetFrameStrata("MEDIUM")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self)
            self._dragging = true
            self:StartMoving()
        end)
        f:SetScript("OnDragStop", function(self)
            if not self._dragging then return end
            self._dragging = false
            self:StopMovingOrSizing()
            local pt, _, rpt, x, y = self:GetPoint(1)
            if pt then
                AP:SetSetting("ejFramePos", { point = pt, relPoint = rpt or pt, x = math.floor(x + 0.5), y = math.floor(y + 0.5) })
            end
            AP:SetSetting("ejDocked", false)
            AnchorEJOverlay()
        end)
        f:SetClampedToScreen(true)
        f:Hide()
        PS.ApplyWindow(f)

        local closeBtn = CreateFrame("Button", nil, f)
        closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
        PS.StyleClose(closeBtn, 22)
        closeBtn:SetScript("OnClick", function()
            AP:SetSetting("showEJOverlay", false)
            f:Hide()
        end)

        f.dockBtn = PS.MakeBtn(f, 84, 20, "Открепить", "dark")
        f.dockBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -38, -10)
        f.dockBtn:SetScript("OnClick", function()
            if AP:GetSetting("ejDocked") == false then
                AP:SetSetting("ejFramePos", nil)
                AP:SetSetting("ejDocked", true)
            else
                local pt, _, rpt, x, y = f:GetPoint(1)
                if pt then
                    AP:SetSetting("ejFramePos", { point = pt, relPoint = rpt or pt, x = math.floor(x + 0.5), y = math.floor(y + 0.5) })
                end
                AP:SetSetting("ejDocked", false)
            end
            AnchorEJOverlay()
        end)
        f.dockBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:SetText("|cffffd200Закрепление панели|r")
            GameTooltip:AddLine("Прикреплено: панель следует за Путеводителем.", 0.9, 0.9, 0.9, true)
            GameTooltip:AddLine("Откреплено: можно свободно перетаскивать окно.", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        f.dockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        f.hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.hdr:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
        f.hdr:SetSize(180, 16)
        f.hdr:SetJustifyH("LEFT")
        if f.hdr.SetWordWrap then f.hdr:SetWordWrap(false) end

        f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.sub:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -31)
        f.sub:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -31)
        f.sub:SetHeight(15)
        f.sub:SetJustifyH("LEFT")
        if f.sub.SetWordWrap then f.sub:SetWordWrap(false) end

        f.statsBox = CreateFrame("Frame", nil, f)
        f.statsBox:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -50)
        f.statsBox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -50)
        f.statsBox:SetHeight(106)
        PS.StyleBox(f.statsBox, 0.50, false)

        f.statsTxt = f.statsBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.statsTxt:SetPoint("TOPLEFT", f.statsBox, "TOPLEFT", 8, -7)
        f.statsTxt:SetPoint("BOTTOMRIGHT", f.statsBox, "BOTTOMRIGHT", -8, 7)
        f.statsTxt:SetJustifyH("LEFT")
        f.statsTxt:SetJustifyV("TOP")

        f.listBox = CreateFrame("Frame", nil, f)
        f.listBox:SetPoint("TOPLEFT", f.statsBox, "BOTTOMLEFT", 0, -6)
        f.listBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 42)
        PS.StyleBox(f.listBox, 0.36, false)

        f.rows = {}
        local RVIS = 9
        for i = 1, RVIS do
            local r = CreateFrame("Button", nil, f.listBox)
            r:SetHeight(27)
            r:SetPoint("TOPLEFT", f.listBox, "TOPLEFT", 4, -5 - (i - 1) * 29)
            r:SetPoint("TOPRIGHT", f.listBox, "TOPRIGHT", -4, -5 - (i - 1) * 29)
            PS.StyleScrollRow(r, (i % 2) == 1)

            r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.left:SetPoint("LEFT", r, "LEFT", 6, 0)
            r.left:SetSize(222, 16)
            r.left:SetJustifyH("LEFT")
            if r.left.SetWordWrap then r.left:SetWordWrap(false) end

            r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.right:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            r.right:SetSize(64, 16)
            r.right:SetJustifyH("RIGHT")
            if r.right.SetWordWrap then r.right:SetWordWrap(false) end

            r:SetScript("OnClick", function(self)
                local d = self._d
                if not d then return end
                if d.kind == "zone" then
                    AP:OpenEncounterJournal(d.zone.zoneId)
                elseif d.kind == "item" and d.itemId then
                    if IsShiftKeyDown() or IsControlKeyDown() or (IsModifiedClick and IsModifiedClick("CHATLINK")) then
                        AP:InsertItemLink(d.itemId, d.link or d.sfx, d.info and d.info.name, d.info and d.info.quality)
                    elseif f._curZoneId then
                        AP:OpenEncounterJournal(f._curZoneId, d.itemId, d.diffMask)
                    end
                end
            end)

            r:SetScript("OnEnter", function(self)
                local d = self._d
                if not d then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if d.kind == "zone" then
                    local z = d.zone
                    GameTooltip:SetText((z.isRaid and "|cffff8000" or "|cff38bdf8") .. (z.zoneName or "?") .. "|r")
                    GameTooltip:AddLine(string.format("%s | id:%s | %s",
                        z.isRaid and "Рейд" or "Подземелье",
                        tostring(z.zoneId or "?"),
                        z.isLocked and "|cffff5050Есть КД|r" or "|cff40ff40Свободно (без КД)|r"), 0.9, 0.9, 0.9)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(string.format("Новых: |cff40ff40%d|r (+%d стат макс) | Ковка: |cffffd200%d|r (+%d стат ост.)",
                        z.newCount or 0, z.newMaxStats or 0, z.forgeCount or 0, z.forgeRemainStats or 0), 1, 1, 1)
                    if z.byDiff then
                        local parts = {}
                        local maxD = z.maxDiffs or 4
                        local dn4 = { "10об", "25об", "10гер", "25гер" }
                        for did = 1, maxD do
                            local df = z.byDiff[did]
                            if df and ((df.newCount or 0) + (df.forgeCount or 0)) > 0 then
                                local lbl = (maxD == 4 and dn4[did]) or ((not z.isRaid) and (did == 1 and "Об" or "Гер")) or dn4[did]
                                table.insert(parts, string.format("%s: %d+%d", lbl, df.newCount or 0, df.forgeCount or 0))
                            end
                        end
                        if #parts > 0 then
                            GameTooltip:AddLine("По сложностям: " .. table.concat(parts, ", "), 0.85, 0.85, 0.85, true)
                        end
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff94a3b8ЛКМ: Открыть в Путеводителе|r", 1, 1, 1)
                elseif d.kind == "item" then
                    AP:BuildItemTooltip(GameTooltip, d.itemId, {
                        sfx = d.sfx,
                        link = d.link,
                        name = d.info and d.info.name,
                        quality = d.info and d.info.quality,
                        zoneId = f._curZoneId,
                        diffMask = d.diffMask,
                        tier = d.tier,
                        extraLine = d.extraLine,
                        hint = "|cff94a3b8ЛКМ: к боссу в Путеводителе | Shift+ЛКМ: ссылка в чат | Ctrl+ЛКМ: примерить|r",
                    })
                end
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            f.rows[i] = r
        end

        f.openApBtn = PS.MakeBtn(f, 138, 24, "AttuneParser", "dark")
        f.openApBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
        f.openApBtn:SetScript("OnClick", function() AP:OpenUI("top") end)

        f.talBtn = PS.MakeBtn(f, 138, 24, "Цель Талориана", "green")
        f.talBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
        f.talBtn:SetScript("OnClick", function()
            if f._curZoneId then
                AP:SelectZoneInTalorian(f._curZoneId, f._curZoneName)
                AP:OpenTalorianUI()
            end
        end)

        ejOverlay = f
        return f
    end

    function AP:RefreshEJOverlay()
        local ej = rawget(_G, "EncounterJournal")
        if not ej or not ej:IsShown() or AP:GetSetting("showEJOverlay") == false then
            if ejOverlay then ejOverlay:Hide() end
            return
        end
        local ov = EnsureEJOverlay()
        AnchorEJOverlay()
        ov:Show()

        local ctx = AP:GetCurrentEJContext()
        local scope = AP:GetSetting("scope")
        local exclHeavy = AP:GetSetting("excludeHeavyQuests") ~= false
        local gift = AP:GetActiveDailyGift(false)

        ov._curZoneId = ctx.zoneId
        ov._curZoneName = ctx.zoneName

        if ctx.zoneId then
            local za = AP:GetZoneAnalysis(ctx.zoneId, {
                scope = scope,
                excludeHeavyQuests = exclHeavy,
                includeItems = true,
            })
            local locked = AP:IsZoneLocked(ctx.zoneId, ctx.zoneName)
            ov.hdr:SetText("|cffffd200" .. tostring(ctx.zoneName or (za and za.zoneName) or "Инст") .. "|r")
            local giftStr = gift.isWednesday and "|cffa855f7[Дар Среды]|r  " or ""
            ov.sub:SetText(giftStr .. (locked and "|cffff5050Есть КД|r" or "|cff40ff40Свободно (без КД)|r") .. "  |  Режим: " .. ((scope == "account") and "Аккаунт" or "Перс"))

            if za then
                local fb = za.forgeByTier or {}
                local diffLine = ""
                if za.byDiff then
                    local parts = {}
                    local dLbls = { "10о", "25о", "10г", "25г" }
                    for d = 1, (za.maxDiffs or 4) do
                        local df = za.byDiff[d]
                        if df and ((df.newCount or 0) + (df.forgeCount or 0)) > 0 then
                            local nm = (za.maxDiffs == 4 and dLbls[d]) or ((not za.isRaid) and (d == 1 and "Об" or "Гер")) or dLbls[d]
                            table.insert(parts, string.format("%s:%d+%d", nm, df.newCount or 0, df.forgeCount or 0))
                        end
                    end
                    if #parts > 0 then diffLine = "\nРежимы: " .. table.concat(parts, " | ") end
                end
                ov.statsTxt:SetText(string.format(
                    "Новых: |cff40ff40%d|r (сразу +%d, макс +%d стат)\nКовка 90%%: |cffffd200%d|r (Обычн:%d Эпик:%d Лег:%d, +%d стат)\n1-lvl (req<=1): %d%s",
                    za.newCount or 0, za.newImmediateStats or 0, za.newMaxStats or 0,
                    za.forgeCount or 0, fb[0] or 0, fb[1] or 0, fb[2] or 0, za.forgeRemainStats or 0,
                    za.noReqCount or 0, diffLine
                ))

                local function FormatDiffPrefix(eid, zId, dMask)
                    local dt = AP.GetItemDiffTag and AP:GetItemDiffTag(eid, zId, dMask, false) or ""
                    if dt == "" then return "" end
                    local c = (dt:find("25г", 1, true) and "|cffff8000")
                        or (dt:find("10г", 1, true) and "|cffffb040")
                        or ((dt:find("25о", 1, true) or dt:find("Гер", 1, true)) and "|cff38bdf8")
                        or "|cff94a3b8"
                    return c .. "[" .. dt .. "]|r "
                end

                local rowData = {}
                local EJ_WHERE_TAG = {
                    petloot = "|cffff80ff[Сборщик]|r ",
                    itembank = "|cff38bdf8[Банк вещ.]|r ",
                    bank = "|cffffd200[Банк]|r ",
                    guild = "|cffa335ee[Гильдбанк]|r ",
                    equip = "|cffffffff[Надетые]|r ",
                }
                local owned = AP:GetOwnedUpgradeCandidates(ctx.zoneId)
                for _, oit in ipairs(owned) do
                    if #rowData >= 9 then break end
                    local dPre = FormatDiffPrefix(oit.itemId, ctx.zoneId, oit.diffMask)
                    local wTag = EJ_WHERE_TAG[oit.where or ""] or "|cff40ff40[Сумки]|r "
                    table.insert(rowData, {
                        kind = "item",
                        itemId = oit.itemId,
                        sfx = oit.sfx,
                        link = oit.link,
                        diffMask = oit.diffMask,
                        tier = oit.instanceTier,
                        info = oit,
                        leftTxt = wTag .. dPre .. ItemColorName(oit),
                        rightTxt = "|cff40ff40+" .. (oit.gainNowStats or 0) .. "|r",
                        extraLine = string.format("Уже у вас (%s): тир %s -> +%d%% (+%d стат)", oit.where or "bag", oit.instanceTierName or "?", oit.gainNowPct or 0, oit.gainNowStats or 0),
                    })
                end

                local merged = {}
                for _, ni in ipairs(za.newItems or {}) do
                    table.insert(merged, { id = ni.id, sfx = ni.sfx, gain = ni.gainMax or 0, diffMask = ni.diffMask, isNew = true })
                end
                for _, fi in ipairs(za.forgeItems or {}) do
                    table.insert(merged, { id = fi.id, sfx = fi.sfx, gain = fi.gainRem or 0, tier = fi.tier, diffMask = fi.diffMask, isNew = false })
                end
                table.sort(merged, function(a, b) return (a.gain or 0) > (b.gain or 0) end)

                for _, mi in ipairs(merged) do
                    if #rowData >= 9 then break end
                    local info = AP:GetItemInfo(mi.id, mi.sfx)
                    if info then
                        local tag = mi.isNew and "|cff40ff40[Н]|r" or ("|cffffd200[" .. (info.curPct or 0) .. "%]|r")
                        local dPre = FormatDiffPrefix(mi.id, ctx.zoneId, mi.diffMask)
                        table.insert(rowData, {
                            kind = "item",
                            itemId = mi.id,
                            sfx = mi.sfx,
                            diffMask = mi.diffMask,
                            tier = mi.tier,
                            info = info,
                            leftTxt = tag .. (dPre ~= "" and dPre or " ") .. ItemColorName(info),
                            rightTxt = "|cffffd200+" .. (mi.gain or 0) .. "|r",
                        })
                    end
                end

                for i = 1, 9 do
                    local r = ov.rows[i]
                    local d = rowData[i]
                    if d then
                        r._d = d
                        r.left:SetText(d.leftTxt)
                        r.right:SetText(d.rightTxt)
                        r:Show()
                    else
                        r._d = nil
                        r:Hide()
                    end
                end
            else
                ov.statsTxt:SetText("|cff94a3b8Нет данных AttuneParser для этой зоны.|r")
                for i = 1, 9 do ov.rows[i]:Hide() end
            end

            if AP:IsTalorianBridgeActive() then
                ov.talBtn:Show()
            else
                ov.talBtn:Hide()
            end
        else
            ov.hdr:SetText("|cffffd200Топ инстов (Путеводитель)|r")
            local useWed = (AP:GetSetting("wedAuto") ~= false and gift.isWednesday)
            ov.sub:SetText(useWed and "|cffa855f7Режим: Дар Среды (Ковка)|r" or "|cffb0a080Выберите инст для фарма или оценки|r")
            local cat = AP:GetAccountCatalogSummary()
            local ms = AP:GetMilestonesSummary()
            ov.statsTxt:SetText(string.format(
                "Каталог: |cffffffff%d / %d|r (%d%%)\nВехи: %d (наград: |cff40ff40%d|r)\nДар: %s\nТалориан: %s",
                cat.doneBase or 0, cat.totalBase or 0, cat.pctBase or 0,
                ms.done or 0, ms.claimable or 0,
                gift.active and (gift.name or "?") or "нет",
                AP:IsTalorianBridgeActive() and "|cff40ff40Подключен|r" or "|cff94a3b8Автономный|r"
            ))

            local list = AP:GetRecommendations({
                mode = useWed and "wednesday" or AP:GetSetting("topMode"),
                scope = scope,
                onlyInstances = true,
                lockedZones = AP:GetLockedZonesMap(),
                unlockedOnly = AP:GetSetting("onlyUnlocked") == true,
                excludeHeavyQuests = exclHeavy,
                limit = 9,
            })
            if #list == 0 then
                list = AP:GetRecommendations({ mode = "new", scope = scope, onlyInstances = true, limit = 9 })
            end
            for i = 1, 9 do
                local r = ov.rows[i]
                local z = list[i]
                if z then
                    r._d = { kind = "zone", zone = z }
                    local kCol = z.isRaid and "|cffff8000[Р]|r " or "|cff38bdf8[П]|r "
                    local cdStr = z.isLocked and " |cffff5050КД|r" or ""
                    r.left:SetText(kCol .. (z.zoneName or "?") .. cdStr)
                    r.right:SetText(string.format("|cff40ff40%d|r/|cffffd200%d|r", z.newCount or 0, z.forgeCount or 0))
                    r:Show()
                else
                    r._d = nil
                    r:Hide()
                end
            end
            ov.talBtn:Hide()
        end

        UpdateEJLootBadges()
    end

    local function TryHookEJ()
        if hookInstalled then return end
        local ej = rawget(_G, "EncounterJournal")
        if not ej then return end
        hookInstalled = true

        ej:HookScript("OnShow", function()
            AP.After(0.05, function() AP:RefreshEJOverlay() end, "ap_ej_onshow")
        end)
        ej:HookScript("OnHide", function()
            if ejOverlay then ejOverlay:Hide() end
        end)

        for _, fnName in ipairs({
            "EncounterJournal_DisplayInstance",
            "EncounterJournal_DisplayEncounter",
            "EncounterJournal_ListInstances",
            "EncounterJournal_LootUpdate",
        }) do
            if type(rawget(_G, fnName)) == "function" and type(hooksecurefunc) == "function" then
                pcall(hooksecurefunc, fnName, function()
                    AP.After(0.05, function() AP:RefreshEJOverlay() end, "ap_ej_hook")
                end)
            end
        end

        local watcher = CreateFrame("Frame", nil, ej)
        watcher:SetScript("OnUpdate", function(_, elapsed)
            badgeTimer = badgeTimer + elapsed
            if badgeTimer >= 0.35 then
                badgeTimer = 0
                local ctx = AP:GetCurrentEJContext()
                if ejOverlay and (ctx.zoneId ~= ejOverlay._curZoneId) then
                    AP:RefreshEJOverlay()
                else
                    UpdateEJLootBadges()
                end
            end
        end)
    end

    AP:RegisterCallback("ATTUNE_UPDATED", function() AP:RefreshEJOverlay() end)
    AP:RegisterCallback("SETTINGS_UPDATED", function(_, k)
        if k == "showEJOverlay" or k == "ejOverlaySide" or k == "ejDocked" or k == "showEJBadges" or k == "scope" or k == "excludeHeavyQuests" or k == "talorianMode" then
            AP:RefreshEJOverlay()
        end
    end)
    AP:RegisterCallback("TALORIAN_BRIDGE_UPDATED", function() AP:RefreshEJOverlay() end)

    local ejEv = CreateFrame("Frame")
    ejEv:RegisterEvent("PLAYER_LOGIN")
    ejEv:RegisterEvent("ADDON_LOADED")
    ejEv:SetScript("OnEvent", function(_, event, a1)
        if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and a1 == "Blizzard_EncounterJournal") then
            TryHookEJ()
        end
    end)
end

---------------------------------------------------------------------------
-- 2. Самодостаточный помощник аукциона (PrimeAuctionHouse + 3.3.5 Blizzard_AuctionUI)
---------------------------------------------------------------------------
do
    local aucBtn, aucFrame
    local aucRows = {}
    local aucData = {}
    local hookState = { prime = false, blizz = false }

    local function IsAnyAuctionOpen()
        local pf = rawget(_G, "PrimeAuctionHouseFrame")
        if pf and pf:IsShown() then return true, "prime", pf end
        local af = rawget(_G, "AuctionFrame")
        if af and af:IsShown() then return true, "blizz", af end
        return false, nil, nil
    end

    local function ApplyDefaultAuctionBtnSkin(b)
        b:SetSize(134, 24)
        local n = b:CreateTexture(nil, "BACKGROUND")
        n:SetTexture("Interface\\Buttons\\UI-Panel-Button-Up")
        n:SetTexCoord(0, 0.625, 0, 0.6875)
        n:SetAllPoints(b)
        b:SetNormalTexture(n)

        local p = b:CreateTexture(nil, "BACKGROUND")
        p:SetTexture("Interface\\Buttons\\UI-Panel-Button-Down")
        p:SetTexCoord(0, 0.625, 0, 0.6875)
        p:SetAllPoints(b)
        b:SetPushedTexture(p)

        local h = b:CreateTexture(nil, "HIGHLIGHT")
        h:SetTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
        h:SetTexCoord(0, 0.625, 0, 0.6875)
        h:SetBlendMode("ADD")
        h:SetAllPoints(b)
        b:SetHighlightTexture(h)

        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER", 0, 1)
        fs:SetText("Поглощение")
        b.label = fs
    end

    local curAucAnchor = nil

    local function PositionAuctionBtn(anchor)
        if not aucBtn then return end
        local saved = AP:GetSetting("aucBtnPos")
        aucBtn:ClearAllPoints()
        if type(saved) == "table" and saved.point and saved.x and saved.y then
            aucBtn:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x, saved.y)
        elseif anchor then
            local aname = anchor.GetName and anchor:GetName() or ""
            if aname == "PrimeAuctionHouseFrame" then
                aucBtn:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -12, 6)
            else
                aucBtn:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -38, -6)
            end
        else
            aucBtn:SetPoint("TOP", UIParent, "TOP", 0, -40)
        end
    end

    local function AnchorAuctionFrame(anchor)
        if not aucFrame then return end
        anchor = anchor or curAucAnchor or select(3, IsAnyAuctionOpen())
        curAucAnchor = anchor
        local docked = AP:GetSetting("aucDocked") ~= false
        if aucFrame.dockBtn and aucFrame.dockBtn.label then
            aucFrame.dockBtn.label:SetText(docked and "Открепить" or "Прикрепить")
        end
        aucFrame:ClearAllPoints()
        if not docked then
            local pos = AP:GetSetting("aucFramePos")
            if type(pos) == "table" and pos.point and pos.x and pos.y then
                aucFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
                return
            end
        end
        if anchor then
            local right = anchor.GetRight and anchor:GetRight() or 0
            local uiRight = UIParent.GetRight and UIParent:GetRight() or 1280
            local w = aucFrame:GetWidth() or 418
            if right > 0 and (right + w + 8) > uiRight then
                aucFrame:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
            else
                aucFrame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
            end
        else
            aucFrame:SetPoint("RIGHT", UIParent, "RIGHT", -24, 20)
        end
    end

    local function FormatCoins(c)
        c = tonumber(c) or 0
        if c <= 0 then return "-" end
        local g = math.floor(c / 10000)
        local s = math.floor((c % 10000) / 100)
        if g > 0 then
            return string.format("%dg %ds", g, s)
        end
        return string.format("%ds %dc", s, c % 100)
    end

    local lastAucErr = nil
    local function ReportAucErr(where, err)
        local msg = tostring(where) .. ": " .. tostring(err)
        if lastAucErr ~= msg then
            lastAucErr = msg
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040[AttuneParser AucErr]|r " .. msg)
        end
    end

    local function EnsureAuctionFrame()
        if aucFrame then return aucFrame end
        local f = CreateFrame("Frame", "AP_AuctionFrame", UIParent)
        f:SetSize(418, 538)
        f:SetPoint("RIGHT", UIParent, "RIGHT", -24, 20)
        f:SetFrameStrata("MEDIUM")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self)
            self._dragging = true
            self:StartMoving()
        end)
        f:SetScript("OnDragStop", function(self)
            if not self._dragging then return end
            self._dragging = false
            self:StopMovingOrSizing()
            local pt, _, rpt, x, y = self:GetPoint(1)
            if pt then
                AP:SetSetting("aucFramePos", { point = pt, relPoint = rpt or pt, x = math.floor(x + 0.5), y = math.floor(y + 0.5) })
            end
            AP:SetSetting("aucDocked", false)
            AnchorAuctionFrame()
        end)
        f:SetClampedToScreen(true)
        f:Hide()
        PS.ApplyWindow(f)
        table.insert(UISpecialFrames, "AP_AuctionFrame")

        local cl = CreateFrame("Button", nil, f)
        cl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
        PS.StyleClose(cl, 22)
        cl:SetScript("OnClick", function()
            AP:SetSetting("aucFrameOpen", false)
            f:Hide()
        end)

        f.dockBtn = PS.MakeBtn(f, 84, 20, "Открепить", "dark")
        f.dockBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -38, -10)
        f.dockBtn:SetScript("OnClick", function()
            if AP:GetSetting("aucDocked") == false then
                AP:SetSetting("aucFramePos", nil)
                AP:SetSetting("aucDocked", true)
            else
                local pt, _, rpt, x, y = f:GetPoint(1)
                if pt then
                    AP:SetSetting("aucFramePos", { point = pt, relPoint = rpt or pt, x = math.floor(x + 0.5), y = math.floor(y + 0.5) })
                end
                AP:SetSetting("aucDocked", false)
            end
            AnchorAuctionFrame()
        end)
        f.dockBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:SetText("|cffffd200Закрепление окна|r")
            GameTooltip:AddLine("Прикреплено: панель прилипает к интерфейсу аукциона.", 0.9, 0.9, 0.9, true)
            GameTooltip:AddLine("Откреплено: можно перетаскивать за рамку в любое место.", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        f.dockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hdr:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
        hdr:SetSize(276, 16)
        hdr:SetJustifyH("LEFT")
        if hdr.SetWordWrap then hdr:SetWordWrap(false) end
        hdr:SetText("|cffffd200AttuneParser - Аукцион Поглощения|r")

        f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.sub:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -32)
        f.sub:SetSize(388, 16)
        f.sub:SetJustifyH("LEFT")
        f.sub:SetText("Найденные лоты для поглощения и ковки")

        local listBox = CreateFrame("Frame", nil, f)
        listBox:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -52)
        listBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 38)
        PS.StyleBox(listBox, 0.42, false)

        f.emptyTxt = listBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.emptyTxt:SetPoint("CENTER", listBox, "CENTER", 0, 0)
        f.emptyTxt:SetSize(350, 48)
        f.emptyTxt:SetJustifyH("CENTER")
        f.emptyTxt:SetText("|cff94a3b8Подходящих лотов не найдено.\nВыберите категорию или выполните поиск.|r")
        f.emptyTxt:Hide()

        local RVIS = 15
        local RH = 29
        local sf
        sf = PS.AttachScroll(listBox, RVIS * RH, RH, RVIS, function(offArg)
            local off = offArg or (sf and sf.offset) or 0
            for i = 1, RVIS do
                local r = aucRows[i]
                local it = aucData[off + i]
                if r then
                    if it then
                        r._it = it
                        local tg = it.isNew and "|cff40ff40[Нов]|r " or (it.needsForgeCheck and "|cffff8000[Чек]|r " or "|cffffd200[Ков]|r ")
                        r.nameTxt:SetText(tg .. ItemColorName(it))
                        r.tierTxt:SetText((it.lotTierName or "?") .. " |cff40ff40+" .. (it.gainNowStats or 0) .. "|r")
                        r.priceTxt:SetText(FormatCoins(it.buyout))
                        r:Show()
                    else
                        r._it = nil
                        r:Hide()
                    end
                end
            end
        end)
        sf:SetPoint("TOPLEFT", listBox, "TOPLEFT", 4, -4)
        sf:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -4, 4)
        f.sf = sf

        for i = 1, RVIS do
            local r = CreateFrame("Button", nil, sf)
            r:SetHeight(RH - 2)
            r:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i - 1) * RH)
            r:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -16, -(i - 1) * RH)
            r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            PS.StyleScrollRow(r, (i % 2) == 1)

            r.nameTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.nameTxt:SetPoint("LEFT", r, "LEFT", 6, 0)
            r.nameTxt:SetSize(188, 16)
            r.nameTxt:SetJustifyH("LEFT")
            if r.nameTxt.SetWordWrap then r.nameTxt:SetWordWrap(false) end

            r.tierTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.tierTxt:SetPoint("LEFT", r.nameTxt, "RIGHT", 4, 0)
            r.tierTxt:SetSize(106, 16)
            r.tierTxt:SetJustifyH("LEFT")
            if r.tierTxt.SetWordWrap then r.tierTxt:SetWordWrap(false) end

            r.priceTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.priceTxt:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            r.priceTxt:SetSize(64, 16)
            r.priceTxt:SetJustifyH("RIGHT")
            if r.priceTxt.SetWordWrap then r.priceTxt:SetWordWrap(false) end

            r:SetScript("OnClick", function(self, mBtn)
                local it = self._it
                if not it then return end
                if IsControlKeyDown() and it.itemId and type(DressUpItemLink) == "function" then
                    local lnk = AP:GetItemHyperlink(it.itemId, it.link or it.sfx, it.name, it.quality)
                    if lnk then
                        pcall(DressUpItemLink, lnk)
                        return
                    end
                end
                if (IsShiftKeyDown() or (IsModifiedClick and IsModifiedClick("CHATLINK"))) and it.itemId then
                    AP:InsertItemLink(it.itemId, it.link or it.sfx, it.name, it.quality)
                    return
                end
                local pah = rawget(_G, "PrimeAH")
                if mBtn == "RightButton" then
                    if pah and type(pah.SearchByName) == "function" and it.name then
                        pcall(pah.SearchByName, it.name)
                    elseif _G.BrowseName and it.name then
                        _G.BrowseName:SetText(it.name)
                    end
                    return
                end
                if pah then
                    if pah.panels and pah.panels.itemBuy and pah.panels.itemBuy:IsShown() and it.primeLot and type(pah.panels.itemBuy.Select) == "function" then
                        pcall(pah.panels.itemBuy.Select, pah.panels.itemBuy, it.primeLot)
                        return
                    end
                    if it.primeRow then
                        if it.commodity and type(pah.ShowCommodityBuy) == "function" then
                            pcall(pah.ShowCommodityBuy, it.primeRow)
                            return
                        elseif type(pah.ShowItemBuy) == "function" then
                            pcall(pah.ShowItemBuy, it.primeRow)
                            return
                        end
                    end
                    if type(pah.SearchByName) == "function" and it.name then
                        pcall(pah.SearchByName, it.name)
                    end
                elseif _G.BrowseName and it.name then
                    _G.BrowseName:SetText(it.name)
                end
            end)

            r:SetScript("OnEnter", function(self)
                local it = self._it
                if not it then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                AP:BuildItemTooltip(GameTooltip, it.itemId, {
                    sfx = it.sfx,
                    link = it.link,
                    name = it.name,
                    quality = it.quality,
                    tier = it.lotTier,
                    extraLine = string.format("Лот аука: %s | Выкуп: %s%s (+%d%% / +%d стат сейчас)",
                        tostring(it.lotTierName or "?"), FormatCoins(it.buyout), it.own and " (ваш)" or "", it.gainNowPct or 0, it.gainNowStats or 0),
                    hint = "|cff94a3b8ЛКМ: открыть лот | ПКМ: поиск по имени | Shift+ЛКМ: в чат | Ctrl+ЛКМ: примерить|r",
                })
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)

            aucRows[i] = r
        end

        local refBtn = PS.MakeBtn(f, 100, 22, "Обновить", "dark")
        refBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
        refBtn:SetScript("OnClick", function() AP:RefreshAuctionHelper() end)

        local openAp = PS.MakeBtn(f, 134, 22, "Открыть AttuneParser", "dark")
        openAp:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 8)
        openAp:SetScript("OnClick", function() AP:OpenUI("top") end)

        aucFrame = f
        return f
    end

    local function UpdatePrimeAHRowBadges()
        if AP:GetSetting("showAuctionUI") == false then return end
        local pah = rawget(_G, "PrimeAH")
        if not pah or not pah.browse or not pah.browse.list or not pah.browse.list.rows then return end
        for _, row in ipairs(pah.browse.list.rows) do
            if row and row:IsShown() and row.data and row.data.entry then
                local eid = row.data.entry
                local sfx = row.data.randProp or 0
                local link = "item:" .. eid .. ":0:0:0:0:0:" .. sfx
                local host = (row.cells and row.cells[2]) or row
                if not row._apTag then
                    local holder = CreateFrame("Frame", nil, host)
                    holder:SetSize(44, 16)
                    holder:SetFrameLevel((host:GetFrameLevel() or 1) + 6)
                    holder:SetBackdrop({
                        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        tile = true, tileSize = 8, edgeSize = 8,
                        insets = { left = 2, right = 2, top = 2, bottom = 2 },
                    })
                    holder:SetBackdropColor(0.05, 0.08, 0.12, 0.88)
                    holder:SetBackdropBorderColor(0.25, 0.55, 0.45, 0.7)
                    if host ~= row then
                        holder:SetPoint("RIGHT", host, "RIGHT", -6, 0)
                    else
                        holder:SetPoint("RIGHT", row, "RIGHT", -156, 0)
                    end
                    local fs = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    fs:SetPoint("CENTER", holder, "CENTER", 0, 0)
                    fs:SetJustifyH("CENTER")
                    row._apTagBox = holder
                    row._apTag = fs
                end
                local usable = AP:CanHeroAbsorb(eid, link)
                local info = usable and AP:GetItemInfo(eid, link) or nil
                local isBl = AP.IsItemBlacklisted and AP:IsItemBlacklisted(eid, nil)
                if info and not info.isCompleted then
                    if isBl then
                        row._apTag:SetText("|cffff5050[ЧС]|r")
                        row._apTagBox:SetBackdropBorderColor(0.85, 0.25, 0.25, 0.85)
                        row._apTagBox:Show()
                    elseif info.isNew then
                        row._apTag:SetText("|cff40ff40+Нов|r")
                        row._apTagBox:SetBackdropBorderColor(0.25, 0.85, 0.35, 0.85)
                        row._apTagBox:Show()
                    elseif info.needsForge then
                        row._apTag:SetText("|cffffd200" .. (info.curPct or 0) .. "%|r")
                        row._apTagBox:SetBackdropBorderColor(0.95, 0.72, 0.18, 0.85)
                        row._apTagBox:Show()
                    else
                        row._apTagBox:Hide()
                    end
                else
                    row._apTagBox:Hide()
                end
            elseif row and row._apTagBox then
                row._apTagBox:Hide()
            end
        end
    end

    function AP:RefreshAuctionHelper()
        local isOpen, _, anchor = IsAnyAuctionOpen()
        if AP:GetSetting("showAuctionUI") == false or not isOpen then
            if aucBtn then aucBtn:Hide() end
            if aucFrame then aucFrame:Hide() end
            return
        end
        curAucAnchor = anchor

        if not aucBtn then
            local b = CreateFrame("Button", "AP_AuctionButton", UIParent)
            b:SetFrameStrata("HIGH")
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            b:SetMovable(true)
            b:SetClampedToScreen(true)
            ApplyDefaultAuctionBtnSkin(b)

            b:SetScript("OnMouseDown", function(self, mBtn)
                if mBtn == "LeftButton" and IsShiftKeyDown() then
                    self._dragging = true
                    self:StartMoving()
                end
            end)
            b:SetScript("OnMouseUp", function(self)
                if self._dragging then
                    self._dragging = false
                    self._justDragged = true
                    self:StopMovingOrSizing()
                    local pt, _, rpt, x, y = self:GetPoint(1)
                    if pt and x and y then
                        AP:SetSetting("aucBtnPos", { point = pt, relPoint = rpt or pt, x = math.floor(x + 0.5), y = math.floor(y + 0.5) })
                    end
                end
            end)
            b:SetScript("OnClick", function(self, mBtn)
                if self._justDragged then
                    self._justDragged = false
                    return
                end
                if mBtn == "RightButton" then
                    AP:OpenUI("settings")
                else
                    local ok, af = pcall(EnsureAuctionFrame)
                    if not ok or not af then
                        ReportAucErr("EnsureAuctionFrame(click)", af)
                        return
                    end
                    if af:IsShown() then
                        AP:SetSetting("aucFrameOpen", false)
                        af:Hide()
                    else
                        AP:SetSetting("aucFrameOpen", true)
                        af:Show()
                        local okA, errA = pcall(AnchorAuctionFrame, curAucAnchor or anchor)
                        if not okA then ReportAucErr("AnchorAuctionFrame(click)", errA) end
                        AP:RefreshAuctionHelper()
                    end
                end
            end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:SetText("|cffffd200AttuneParser: Помощник аукциона|r")
                GameTooltip:AddLine("ЛКМ: Открыть/скрыть список поглощения", 0.9, 0.9, 0.9)
                GameTooltip:AddLine("ПКМ: Настройки | Shift+ЛКМ: Переместить", 0.9, 0.9, 0.9)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            aucBtn = b
        end

        PositionAuctionBtn(anchor)
        aucBtn:Show()

        if AP:GetSetting("aucDocked") ~= false and AP:GetSetting("aucFrameOpen") ~= false then
            local okF, af = pcall(EnsureAuctionFrame)
            if okF and af then
                local okA, errA = pcall(AnchorAuctionFrame, anchor)
                if not okA then ReportAucErr("AnchorAuctionFrame", errA) end
                if not af:IsShown() then af:Show() end
            else
                ReportAucErr("EnsureAuctionFrame", af)
            end
        elseif aucFrame and aucFrame:IsShown() then
            local okA, errA = pcall(AnchorAuctionFrame, anchor)
            if not okA then ReportAucErr("AnchorAuctionFrame(shown)", errA) end
        end

        local okC, cands = pcall(AP.GetAuctionForgeCandidates, AP)
        if not okC or type(cands) ~= "table" then
            if not okC then ReportAucErr("GetAuctionForgeCandidates", cands) end
            cands = {}
        end
        local newCnt = 0
        for _, c in ipairs(cands) do
            if c.isNew then newCnt = newCnt + 1 end
        end
        if #cands > 0 then
            aucBtn.label:SetText(string.format("Лоты: |cff40ff40%d|r", #cands))
        else
            aucBtn.label:SetText("Поглощение")
        end

        if aucFrame and aucFrame:IsShown() then
            aucData = cands
            aucFrame.sub:SetText(string.format("Найдено лотов: |cff40ff40%d|r (новых: %d)", #cands, newCnt))
            if aucFrame.emptyTxt then
                if #cands == 0 then aucFrame.emptyTxt:Show() else aucFrame.emptyTxt:Hide() end
            end
            local okS, errS = pcall(aucFrame.sf.SetTotal, aucFrame.sf, #cands, false)
            if not okS then ReportAucErr("SetTotal", errS) end
        end

        local okB, errB = pcall(UpdatePrimeAHRowBadges)
        if not okB then ReportAucErr("UpdatePrimeAHRowBadges", errB) end
    end

    function AP:DebugAuction()
        local isOpen, kind, anchor = IsAnyAuctionOpen()
        local pah = rawget(_G, "PrimeAH")
        local brCnt = (pah and pah.browse and pah.browse.list and type(pah.browse.list.data) == "table") and #pah.browse.list.data or -1
        local cCnt = #AP:GetAuctionForgeCandidates()
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff38bdf8[AP AucDebug]|r open=%s (%s) btn=%s frame=%s docked=%s autoOpen=%s rows=%d cands=%d err=%s",
            tostring(isOpen), tostring(kind),
            tostring(aucBtn and aucBtn:IsShown()),
            tostring(aucFrame and aucFrame:IsShown()),
            tostring(AP:GetSetting("aucDocked")),
            tostring(AP:GetSetting("aucFrameOpen")),
            brCnt, cCnt, tostring(lastAucErr)
        ))
    end

    local function TryHookAuctionFrames()
        local pf = rawget(_G, "PrimeAuctionHouseFrame")
        if pf and not hookState.prime then
            hookState.prime = true
            pf:HookScript("OnShow", function() AP.After(0.08, function() AP:RefreshAuctionHelper() end, "ap_auc_show") end)
            pf:HookScript("OnHide", function() AP:RefreshAuctionHelper() end)
            local pah = rawget(_G, "PrimeAH")
            if pah and type(hooksecurefunc) == "function" then
                if type(pah.SetTab) == "function" then
                    pcall(hooksecurefunc, pah, "SetTab", function()
                        AP.After(0.05, function() AP:RefreshAuctionHelper() end, "ap_auc_tab")
                    end)
                end
                if pah.browse and pah.browse.list then
                    pcall(hooksecurefunc, pah.browse.list, "Refresh", function()
                        AP.After(0.05, function() AP:RefreshAuctionHelper() end, "ap_auc_list")
                    end)
                end
                if pah.panels and pah.panels.itemBuy and pah.panels.itemBuy.ItemList then
                    pcall(hooksecurefunc, pah.panels.itemBuy.ItemList, "Refresh", function()
                        AP.After(0.05, function() AP:RefreshAuctionHelper() end, "ap_auc_ib")
                    end)
                end
            end
        end
        local af = rawget(_G, "AuctionFrame")
        if af and not hookState.blizz then
            hookState.blizz = true
            af:HookScript("OnShow", function() AP.After(0.08, function() AP:RefreshAuctionHelper() end, "ap_blizz_auc_show") end)
            af:HookScript("OnHide", function() AP:RefreshAuctionHelper() end)
            if type(rawget(_G, "AuctionFrameBrowse_Update")) == "function" and type(hooksecurefunc) == "function" then
                pcall(hooksecurefunc, "AuctionFrameBrowse_Update", function()
                    AP.After(0.05, function() AP:RefreshAuctionHelper() end, "ap_blizz_auc_upd")
                end)
            end
        end
    end

    AP:RegisterCallback("AUCTION_FORGE_UPDATED", function()
        AP.After(0.06, function() AP:RefreshAuctionHelper() end, "ap_auc_forge")
    end)
    AP:RegisterCallback("SETTINGS_UPDATED", function(_, k)
        if k == "showAuctionUI" or k == "aucBtnPos" or k == "aucDocked" or k == "aucFramePos" then
            AP:RefreshAuctionHelper()
        end
    end)

    local aucEv = CreateFrame("Frame")
    aucEv:RegisterEvent("PLAYER_LOGIN")
    aucEv:RegisterEvent("ADDON_LOADED")
    aucEv:RegisterEvent("AUCTION_HOUSE_SHOW")
    aucEv:RegisterEvent("AUCTION_HOUSE_CLOSED")
    aucEv:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
    aucEv:SetScript("OnEvent", function(_, event, a1)
        if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and (a1 == "PrimeAuctionHouse" or a1 == "Blizzard_AuctionUI")) then
            TryHookAuctionFrames()
        elseif event == "AUCTION_HOUSE_SHOW" or event == "AUCTION_ITEM_LIST_UPDATE" then
            TryHookAuctionFrames()
            AP.After(0.10, function() AP:RefreshAuctionHelper() end, "ap_auc_ev")
        elseif event == "AUCTION_HOUSE_CLOSED" then
            AP:RefreshAuctionHelper()
        end
    end)
end

---------------------------------------------------------------------------
-- 3. Оповещение в чате для окна обмена (Trade / Inspect FORGE_VIEW_UPDATED)
---------------------------------------------------------------------------
do
    local lastTradeSig = ""
    local trEv = CreateFrame("Frame")
    trEv:RegisterEvent("TRADE_CLOSED")
    trEv:SetScript("OnEvent", function() lastTradeSig = "" end)
    AP:RegisterCallback("FORGE_VIEW_UPDATED", function(_, ctx)
        if ctx ~= "TRADE" then return end
        if AP:GetSetting("tradeAlert") == false then return end
        if not (_G.TradeFrame and _G.TradeFrame:IsShown()) then return end
        local list = AP:GetInspectTradeCandidates("TRADE")
        if not list or #list == 0 then return end

        local parts = {}
        local totalGain = 0
        for i = 1, math.min(4, #list) do
            local it = list[i]
            if it.canGainNow or it.isNew then
                totalGain = totalGain + (it.gainNowStats or 0)
                table.insert(parts, string.format("%s (+%d%%, +%d стат)", ItemColorName(it), it.gainNowPct or 0, it.gainNowStats or 0))
            end
        end
        if #parts > 0 then
            local sig = tostring(#parts) .. ":" .. tostring(totalGain)
            if sig ~= lastTradeSig then
                lastTradeSig = sig
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff38bdf8[AttuneParser Trade]|r Полезно к поглощению (|cff40ff40+%d стат|r): %s", totalGain, table.concat(parts, "; ")))
            end
        end
    end)
end

---------------------------------------------------------------------------
-- 4. ServerSync (встроено в Integrations для мгновенной работы по /reload)
---------------------------------------------------------------------------
do
local math_floor, math_max, math_min = math.floor, math.max, math.min
local tonumber, tostring, pairs, ipairs = tonumber, tostring, pairs, ipairs

local PLAYER_DIST = { WHISPER = true, PARTY = true, RAID = true, GUILD = true, BATTLEGROUND = true }

local function IsServerAddonMsg(dist, sender)
    if dist and PLAYER_DIST[dist] and sender and sender ~= "" and type(UnitName) == "function" then
        local me = UnitName("player")
        if me and me ~= "" and sender ~= me then
            return false
        end
    end
    return true
end

local function HasBit(mask, bitIdx)
    mask = tonumber(mask) or 0
    local p = 2 ^ bitIdx
    return math_floor(mask / p) % 2 == 1
end

local function ToggleBitVal(mask, bitVal, maxMask, on)
    mask = tonumber(mask) or 0
    local cur = (bit and bit.band) and (bit.band(mask, bitVal) ~= 0) or (math_floor(mask / bitVal) % 2 == 1)
    local want = (on == nil) and (not cur) or (on and true or false)
    if want == cur then return mask % maxMask end
    if want then
        return (mask + bitVal) % maxMask
    else
        return (mask - bitVal) % maxMask
    end
end

local function SendAddonWhisp(prefix, body)
    if type(SendAddonMessage) ~= "function" then return false end
    local me = type(UnitName) == "function" and UnitName("player")
    if not me or me == "" then return false end
    return pcall(SendAddonMessage, prefix, body or "", "WHISPER", me)
end

local function SendSrv(prefix, body)
    if type(SendServerMessage) == "function" then
        if body ~= nil then
            return pcall(SendServerMessage, prefix, tostring(body))
        end
        return pcall(SendServerMessage, prefix)
    end
    return SendAddonWhisp(prefix, body and tostring(body) or "")
end

local function CharKey()
    local r = (type(GetRealmName) == "function" and GetRealmName()) or "Default"
    local p = (type(UnitName) == "function" and UnitName("player")) or "Player"
    return r .. "|" .. p
end

local function FormatDuration(sec)
    sec = math_max(0, math_floor(tonumber(sec) or 0))
    if sec >= 3600 then
        return string.format("%dч %02dм", math_floor(sec / 3600), math_floor((sec % 3600) / 60))
    elseif sec >= 60 then
        return string.format("%dм %02dс", math_floor(sec / 60), sec % 60)
    end
    return string.format("%dс", sec)
end

local SS = {
    ib = { items = {}, byGuid = {}, cap = 0, capLvl = 0, capMax = 0, dspSkill = 0, dspBatch = false, sfxBatch = false, loaded = false, fullLoaded = false },
    wh = { bk = {}, pl = {}, ib = {}, ibg = {}, loaded = false },
    rb = { contents = {}, used = 0, max = 0, loaded = false },
    dsp = { skill = 0, maxSkill = 0, rank = 0, alertOn = true, shards = {}, sessionDust = 0, sessionGained = 0 },
    wb = { cd = {}, names = {}, srvNow = nil, locSnap = nil, loaded = false, lastReq = 0 },
    vault = { state = 0, quick = 0, curBest = 0, curMap = "", curStage = 0, curIlvl = 0, best = 0, mapName = "", stage = 0, ilvl = 0, claimed = 0, resetIn = 0, resetAt = 0, opts = {}, pending = nil, loaded = false },
    ibEq = { pending = false, scheduledAt = 0, inFlightGuid = nil, inFlightAt = 0, inFlightSlot = nil, inFlightSlotId = nil, prevForgeEquip = nil, prevIBWorn = nil, lastSwapAt = 0, lastTryAt = 0, graceUntil = 0, failUntil = {}, bagFailUntil = {}, lastError = nil, lastEquipped = nil, countSession = 0, warmRetries = 0, combatWaitRegen = false, ibCombatBlocked = false, bagNonWeaponCombatBlocked = false, bagAllCombatBlocked = false, lastBagSwapAt = 0, lastBagSwapGrp = nil, lastBagSwapKey = nil, lastBagSwapSlotId = nil, prevBagForgeEquip = nil, prevBagIBWorn = nil, combatNotified = false },
    ibPut = { pending = false, scheduledAt = 0, inFlightBag = nil, inFlightSlot = nil, inFlightKey = nil, inFlightAt = 0, lastTryAt = 0, manualPauseUntil = 0, fullUntil = 0, failUntil = {}, lastError = nil, lastPutName = nil, countSession = 0, warmRetries = 0 },
    ibSplit = { running = false, keepForgeCopy = true, inFlightAt = 0, inFlightKind = nil, inFlightGuid = nil, lastTryAt = 0, pending = false, scheduledAt = 0, failUntil = {}, doneCount = 0, lastError = nil },
    _ibSendAddon = SendAddonWhisp,

    valdris = { running = false, hookDone = false, altHookDone = false, slotHookDone = false, pending = false, scheduledAt = 0, nextDoAt = 0, throttleSec = 3.1, enabled = true, hello = nil, inFlightQuery = nil, inFlightDo = nil, readyInfo = {}, skip = {}, blockedByTier = {}, doneCount = 0, lastError = nil, lastName = nil, warmRetries = 0, pauseEquipUntil = 0, pendingUnequip = nil, pendingBankTake = nil, pendingBankReturn = nil, pendingRelocate = nil, activeEquippedRestore = nil, activeBankReturn = nil, lastPicked = nil, bankSpaceFull = false },
}
AP.serverSync = SS

---------------------------------------------------------------------------
-- 1. Parsing server messages & reading native Prime globals
---------------------------------------------------------------------------
local function ParseIBToken(tok)
    if type(tok) ~= "string" or tok == "" then return nil end
    local f = { strsplit(":", tok) }
    if #f < 11 then return nil end
    local guid = tonumber(f[1])
    local entry = tonumber(f[2])
    if not guid or not entry then return nil end
    local suffix = tonumber(f[3]) or 0
    local perm = tonumber(f[4]) or 0
    local g1 = tonumber(f[5]) or 0
    local g2 = tonumber(f[6]) or 0
    local g3 = tonumber(f[7]) or 0
    local forge = tonumber(f[8]) or 0
    local tier = tonumber(f[9]) or 0
    local flags = tonumber(f[10]) or 0
    local added = tonumber(f[11]) or 0
    local dsp = tonumber(f[12]) or 0
    local seed = tonumber(f[13]) or 0
    local lvl = (type(UnitLevel) == "function" and UnitLevel("player")) or 80
    local link = string.format("item:%d:%d:%d:%d:%d:0:%d:%d:%d", entry, perm, g1, g2, g3, suffix, seed, lvl)
    return {
        guid = guid, entry = entry, suffix = suffix, perm = perm,
        g1 = g1, g2 = g2, g3 = g3, forge = forge, tier = tier,
        flags = flags, added = added, dsp = dsp, seed = seed, link = link,
    }
end

local function SaveRBCacheToDB()
    if type(AttuneParserDB) ~= "table" then return end
    AttuneParserDB.rbCache = AttuneParserDB.rbCache or {}
    local copy = {}
    for id, cnt in pairs(SS.rb.contents) do
        if cnt and cnt > 0 then copy[id] = cnt end
    end
    AttuneParserDB.rbCache[CharKey()] = {
        contents = copy,
        used = SS.rb.used,
        max = SS.rb.max,
        ts = type(time) == "function" and time() or 0,
    }
end

local function LoadRBCacheFromDB()
    if SS.rb.loaded then return end
    if type(AttuneParserDB) ~= "table" or type(AttuneParserDB.rbCache) ~= "table" then return end
    local saved = AttuneParserDB.rbCache[CharKey()]
    if type(saved) == "table" and type(saved.contents) == "table" then
        for id, cnt in pairs(saved.contents) do
            if SS.rb.contents[id] == nil and (tonumber(cnt) or 0) > 0 then
                SS.rb.contents[tonumber(id)] = tonumber(cnt)
            end
        end
        if SS.rb.used == 0 then SS.rb.used = tonumber(saved.used) or 0 end
        if SS.rb.max == 0 then SS.rb.max = tonumber(saved.max) or 0 end
    end
end

local function HandleServerAddon(prefix, msg)
    msg = tostring(msg or "")
    if prefix == "ASMSG_IB_RESET" then
        local a = { strsplit("\t", msg) }
        SS.ib.byGuid = {}
        SS.ib.items = {}
        SS.ib.cap = tonumber(a[2]) or SS.ib.cap
        SS.ib.dspSkill = tonumber(a[5]) or SS.ib.dspSkill
        SS.ib.dspBatch = (tonumber(a[6]) == 1)
        SS.ib.capLvl = tonumber(a[7]) or SS.ib.capLvl
        SS.ib.capMax = tonumber(a[8]) or SS.ib.capMax
        SS.ib.sfxBatch = (tonumber(a[9]) == 1)
        SS.ib.loaded = true
        SS.ib.fullLoaded = ((tonumber(a[1]) or 0) == 0)
    elseif prefix == "ASMSG_IB_ITEM" then
        for tok in msg:gmatch("[^;]+") do
            local it = ParseIBToken(tok)
            if it then
                if SS.ib.byGuid[it.guid] then
                    for i = #SS.ib.items, 1, -1 do
                        if SS.ib.items[i].guid == it.guid then table.remove(SS.ib.items, i) end
                    end
                end
                SS.ib.items[#SS.ib.items + 1] = it
                SS.ib.byGuid[it.guid] = it
            end
        end
        SS.ib.loaded = true
    elseif prefix == "ASMSG_IB_ADD" then
        local it = ParseIBToken(msg)
        if it then
            if SS.ib.byGuid[it.guid] then
                for i = #SS.ib.items, 1, -1 do
                    if SS.ib.items[i].guid == it.guid then table.remove(SS.ib.items, i) end
                end
            end
            SS.ib.items[#SS.ib.items + 1] = it
            SS.ib.byGuid[it.guid] = it
            SS.ib.loaded = true
            if type(SS.onIBUpdate) == "function" then SS.onIBUpdate(prefix) end
            AP:Fire("SERVER_SYNC_UPDATED", prefix)
            AP:Fire("ATTUNE_UPDATED", prefix)
        end
    elseif prefix == "ASMSG_IB_DEL" then
        local guid = tonumber(msg:match("^(%d+)"))
        if guid and type(SS.onIBDel) == "function" then SS.onIBDel(guid) end
        if guid and SS.ib.byGuid[guid] then
            SS.ib.byGuid[guid] = nil
            for i = #SS.ib.items, 1, -1 do
                if SS.ib.items[i].guid == guid then table.remove(SS.ib.items, i) end
            end
            AP:Fire("SERVER_SYNC_UPDATED", prefix)
            AP:Fire("ATTUNE_UPDATED", prefix)
        end
    elseif prefix == "ASMSG_IB_DONE" or prefix == "ASMSG_IB_CAP" then
        if prefix == "ASMSG_IB_CAP" then
            local a = { strsplit("\t", msg) }
            SS.ib.capLvl = tonumber(a[1]) or SS.ib.capLvl
            SS.ib.capMax = tonumber(a[2]) or SS.ib.capMax
            SS.ib.cap = tonumber(a[3]) or SS.ib.cap
        end
        SS.ib.loaded = true
        if prefix == "ASMSG_IB_DONE" then
            SS.ib.fullLoaded = true
            if type(SS.onIBUpdate) == "function" then SS.onIBUpdate(prefix) end
        end
        AP:Fire("SERVER_SYNC_UPDATED", prefix)
        AP:Fire("ATTUNE_UPDATED", prefix)
    elseif prefix == "ASMSG_IB_RES" then
        local cStr, rTxt, nStr = strsplit("\t", msg)
        if type(SS.onIBRes) == "function" then
            SS.onIBRes(tonumber(cStr) or 0, rTxt or "", tonumber(nStr))
        end
    elseif prefix == "ASMSG_IB_WORN" then
        SS.ib.worn = SS.ib.worn or {}
        for k in pairs(SS.ib.worn) do SS.ib.worn[k] = nil end
        for sl, t in msg:gmatch("(%d+):(%d+)") do
            local sid = tonumber(sl)
            if sid then SS.ib.worn[sid + 1] = tonumber(t) or 0 end
        end
    elseif prefix == "ASMSG_WH_RESET" then
        local src = msg:match("^(%S+)")
        if src == "bk" then SS.wh.bk = {}
        elseif src == "pl" then SS.wh.pl = {}
        elseif src == "ib" then SS.wh.ib = {}; SS.wh.ibg = {} end
        SS.wh.loaded = true
    elseif prefix == "ASMSG_WH_SET" then
        local src, body = msg:match("^(%S+)\t(.*)$")
        local dst = (src == "bk" and SS.wh.bk) or (src == "pl" and SS.wh.pl) or (src == "ib" and SS.wh.ib)
        if dst then
            for e, c in (body or ""):gmatch("(%d+):(%d+)") do
                local eid, cnt = tonumber(e), tonumber(c)
                if eid then dst[eid] = (cnt and cnt > 0) and cnt or nil end
            end
            SS.wh.loaded = true
            AP:Fire("SERVER_SYNC_UPDATED", prefix)
        end
    elseif prefix == "ASMSG_WH_IBG" then
        SS.wh.ibg = {}
        SS.wh.ib = {}
        for g, e in msg:gmatch("(%d+):(%d+)") do
            local guid, eid = tonumber(g), tonumber(e)
            if guid and eid then
                SS.wh.ibg[guid] = eid
                SS.wh.ib[eid] = (SS.wh.ib[eid] or 0) + 1
            end
        end
        SS.wh.loaded = true
        AP:Fire("SERVER_SYNC_UPDATED", prefix)
        AP:Fire("ATTUNE_UPDATED", prefix)
    elseif prefix == "ASMSG_RB_RESET" then
        local used, mx = msg:match("^%s*(%d+)%s*:%s*(%d+)%s*$")
        SS.rb.contents = {}
        SS.rb.used = tonumber(used) or 0
        SS.rb.max = tonumber(mx) or 0
        SS.rb.loaded = true
    elseif prefix == "ASMSG_RB_LIST" then
        for id, cnt in msg:gmatch("(%d+):(%d+)") do
            local iid, c = tonumber(id), tonumber(cnt)
            if iid then SS.rb.contents[iid] = (c and c > 0) and c or nil end
        end
        SS.rb.loaded = true
    elseif prefix == "ASMSG_RB_UPDATE" then
        local id, cnt = msg:match("(%d+):(%d+)")
        local iid, c = tonumber(id), tonumber(cnt)
        if iid then
            local prev = SS.rb.contents[iid]
            SS.rb.contents[iid] = (c and c > 0) and c or nil
            if (prev == nil) and (c and c > 0) then SS.rb.used = (SS.rb.used or 0) + 1
            elseif prev and (not c or c == 0) then SS.rb.used = math_max(0, (SS.rb.used or 0) - 1) end
            SS.rb.loaded = true
            SaveRBCacheToDB()
            AP:Fire("SERVER_SYNC_UPDATED", prefix)
            AP:Fire("ATTUNE_UPDATED", prefix)
        end
    elseif prefix == "ASMSG_RB_OPEN" or prefix == "ASMSG_RB_RESULT" then
        if prefix == "ASMSG_RB_OPEN" then
            SaveRBCacheToDB()
            AP:Fire("ATTUNE_UPDATED", prefix)
        end
        AP:Fire("SERVER_SYNC_UPDATED", prefix)
    elseif prefix == "ASMSG_DSP_END" then
        local sk, mx, rk = strsplit("\t", msg)
        if tonumber(sk) then SS.dsp.skill = tonumber(sk) end
        if tonumber(mx) then SS.dsp.maxSkill = tonumber(mx) end
        if tonumber(rk) then SS.dsp.rank = tonumber(rk) end
        AP:Fire("SERVER_SYNC_UPDATED", prefix)
    elseif prefix == "ASMSG_DSP_RANK" then
        local code, nr = strsplit("\t", msg)
        if code == "ok" and tonumber(nr) then SS.dsp.rank = tonumber(nr) end
        AP:Fire("SERVER_SYNC_UPDATED", prefix)
    elseif prefix == "ASMSG_DSP_PREF" then
        SS.dsp.alertOn = (msg:match("^([^\t]*)") ~= "0")
        AP:Fire("SERVER_SYNC_UPDATED", prefix)
    elseif prefix == "ASMSG_DSP_RES" then
        local code, _, qty, _, bQty, gained, newSkill = strsplit("\t", msg)
        if code == "ok" then
            SS.dsp.sessionDust = (SS.dsp.sessionDust or 0) + (tonumber(qty) or 0) + (tonumber(bQty) or 0)
            SS.dsp.sessionGained = (SS.dsp.sessionGained or 0) + (tonumber(gained) or 0)
        end
        local nsk = tonumber(newSkill)
        if nsk and nsk > 0 then
            SS.dsp.skill = nsk
            SS.ib.dspSkill = math_max(SS.ib.dspSkill or 0, nsk)
        end
        AP:Fire("SERVER_SYNC_UPDATED", prefix)
    elseif prefix == "ASMSG_DSP_SHARD" then
        local g, k = strsplit("\t", msg)
        g = tostring(g or ""):gsub("%s+", "")
        if g ~= "" then
            if not g:find("^0[xX]") then g = "0x" .. g end
            SS.dsp.shards[g:lower()] = { kind = tonumber(k) or 1, expiresAt = GetTime() + 95 }
            AP:Fire("SERVER_SYNC_UPDATED", prefix)
        end
    elseif prefix == "ASMSG_DSP_SHARDX" then
        local g = (strsplit("\t", msg) or ""):gsub("%s+", "")
        if g ~= "" then
            if not g:find("^0[xX]") then g = "0x" .. g end
            SS.dsp.shards[g:lower()] = nil
            AP:Fire("SERVER_SYNC_UPDATED", prefix)
        end
    elseif prefix == "ASMSG_WB_CD" then
        local now, first, chunk = strsplit("\t", msg)
        SS.wb.srvNow = tonumber(now)
        SS.wb.locSnap = GetTime()
        if first == "1" then SS.wb.cd = {} end
        if chunk and chunk ~= "" then
            for pr in chunk:gmatch("[^;]+") do
                local e, r = strsplit(":", pr)
                local eid, rdy = tonumber(e), tonumber(r)
                if eid and rdy then SS.wb.cd[eid] = rdy end
            end
        end
        SS.wb.loaded = true
        AP:Fire("SERVER_SYNC_UPDATED", prefix)
    elseif prefix == "ASMSG_WV2_WBOSS" then
        local a = { strsplit("\t", msg) }
        local entry = tonumber(a[4])
        if entry and a[8] and a[8] ~= "" then
            SS.wb.names[entry] = a[8]
        end
    elseif prefix == "ASMSG_MPLUS_M_VAULT" then
        SS.vault.quick = tonumber(msg) or 0
        SS.vault.loaded = true
        AP:Fire("SERVER_SYNC_UPDATED", prefix)
    elseif prefix == "ASMSG_MPLUS_VAULT" then
        local a = { strsplit("\t", msg) }
        SS.vault.pending = {
            state = tonumber(a[1]) or 0,
            curBest = tonumber(a[2]) or 0,
            curMap = a[3] or "",
            curStage = tonumber(a[4]) or 0,
            curIlvl = tonumber(a[5]) or 0,
            best = tonumber(a[6]) or 0,
            mapName = a[7] or "",
            stage = tonumber(a[8]) or 0,
            ilvl = tonumber(a[9]) or 0,
            claimed = tonumber(a[10]) or 0,
            resetIn = tonumber(a[11]) or 0,
            opts = {},
        }
    elseif prefix == "ASMSG_MPLUS_VAULT_OPT" and SS.vault.pending then
        local idx, entry = strsplit("\t", msg)
        local i, e = tonumber(idx), tonumber(entry)
        if i and e and i >= 0 and i < 3 then
            SS.vault.pending.opts[i + 1] = e
        end
    elseif prefix == "ASMSG_MPLUS_VAULT_END" and SS.vault.pending then
        local p = SS.vault.pending
        SS.vault.pending = nil
        for k, v in pairs(p) do SS.vault[k] = v end
        SS.vault.resetAt = GetTime() + (p.resetIn or 0)
        SS.vault.quick = (p.state == 1) and 1 or ((p.state == 2) and 2 or 0)
        SS.vault.loaded = true
        AP:Fire("SERVER_SYNC_UPDATED", prefix)
    end
end

local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("ADDON_LOADED")
evFrame:RegisterEvent("PLAYER_LOGIN")
evFrame:RegisterEvent("CHAT_MSG_ADDON")
evFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
evFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
evFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
evFrame:RegisterEvent("BAG_UPDATE")
evFrame:RegisterEvent("UI_ERROR_MESSAGE")
evFrame:RegisterEvent("PLAYER_LEVEL_UP")
evFrame:RegisterEvent("SKILL_LINES_CHANGED")
evFrame:RegisterEvent("LEARNED_SPELL_IN_TAB")
evFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
evFrame:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if event == "ADDON_LOADED" and a1 == "AttuneParser" then
        LoadRBCacheFromDB()
    elseif event == "PLAYER_LOGIN" then
        LoadRBCacheFromDB()
        if type(SS.tryHookValdris) == "function" then SS.tryHookValdris() end
    elseif event == "CHAT_MSG_ADDON" then
        if type(a1) == "string" and IsServerAddonMsg(a3, a4) then
            local p4 = a1:sub(1, 9)
            local p2 = a1:sub(1, 10)
            if p4 == "ASMSG_IB_" or p4 == "ASMSG_WH_" or p4 == "ASMSG_RB_"
               or p2 == "ASMSG_DSP_" or a1 == "ASMSG_WB_CD" or a1 == "ASMSG_WV2_WBOSS"
               or a1:sub(1, 17) == "ASMSG_MPLUS_VAULT" or a1 == "ASMSG_MPLUS_M_VAULT" then
                HandleServerAddon(a1, a2)
            elseif a1:sub(1, 12) == "ASMSG_IPROG_" and type(SS.onIProgMsg) == "function" then
                SS.onIProgMsg(a1, a2)
            end
        end
    elseif type(SS.onWoWEvent) == "function" then
        SS.onWoWEvent(event, a1, a2)
    end
end)

---------------------------------------------------------------------------
-- 2. Public actions & enriched queries on AP
---------------------------------------------------------------------------
function AP:RequestWhereItemsSync()
    return SendAddonWhisp("ACMSG_WH_SYNC", "")
end

function AP:RequestWorldBossCD()
    local now = GetTime()
    if (now - (SS.wb.lastReq or 0)) < 2 then return false end
    SS.wb.lastReq = now
    return SendSrv("ACMSG_WB_CD")
end

function AP:OpenItemBank()
    return SendAddonWhisp("ACMSG_IB_OPEN", "")
end

function AP:TakeItemBankItem(guid)
    guid = tonumber(guid)
    if not guid then return false end
    return SendAddonWhisp("ACMSG_IB_TAKE", tostring(guid))
end

function AP:SplitItemBankItem(guid)
    guid = tonumber(guid)
    if not guid then return false end
    return SendAddonWhisp("ACMSG_IB_SPLIT", tostring(guid))
end

function AP:PutAllToItemBank(tabMode)
    return SendAddonWhisp("ACMSG_IB_PUTALL", tostring(tonumber(tabMode) or 1))
end

function AP:OpenResourceBank()
    return SendSrv("ACMSG_RB_OPEN", "")
end

function AP:DepositAllResources(catId)
    local arg = (catId and tonumber(catId) and tonumber(catId) > 0) and tostring(tonumber(catId)) or ""
    return SendSrv("ACMSG_RB_DEPOSIT_ALL", arg)
end

function AP:ToggleDisperseAlert()
    local d = AP:GetDisperseSummary()
    local newVal = not d.alertOn
    local pd = rawget(_G, "PRIME_Disperse")
    if pd then pd.alertOn = newVal end
    SS.dsp.alertOn = newVal
    return SendSrv("ACMSG_DSP_PREF", newVal and "1" or "0")
end

function AP:RequestMPlusVault()
    return SendSrv("ACMSG_MPLUS_VAULT", "")
end

function AP:GetMPlusVaultSummary()
    return {
        state = SS.vault.state or 0,
        quick = SS.vault.quick or 0,
        curBest = SS.vault.curBest or 0,
        curMap = SS.vault.curMap or "",
        curIlvl = SS.vault.curIlvl or 0,
        best = SS.vault.best or 0,
        mapName = SS.vault.mapName or "",
        ilvl = SS.vault.ilvl or 0,
        claimed = SS.vault.claimed or 0,
        loaded = SS.vault.loaded == true,
        opts = SS.vault.opts or {},
    }
end

function AP:GetResourceBankCounts()
    LoadRBCacheFromDB()
    local out = {}
    local used, maxCap = SS.rb.used or 0, SS.rb.max or 0
    local rb = rawget(_G, "ResourceBank")
    if type(rb) == "table" and type(rb.contents) == "table" and next(rb.contents) ~= nil then
        for id, cnt in pairs(rb.contents) do
            local iid, c = tonumber(id), tonumber(cnt)
            if iid and c and c > 0 then out[iid] = c end
        end
        used = tonumber(rb.usedEntries) or used
        maxCap = tonumber(rb.maxEntries) or maxCap
    else
        for id, cnt in pairs(SS.rb.contents) do
            if cnt and cnt > 0 then out[id] = cnt end
        end
    end
    return out, used, maxCap
end

function AP:GetDisperseSummary()
    local pd = rawget(_G, "PRIME_Disperse")
    local st = (type(pd) == "table" and type(pd.state) == "table") and pd.state or {}
    local now = GetTime()
    local merged = {}
    local function CollectShards(tbl, pruneExpired)
        if type(tbl) ~= "table" then return end
        for k, v in pairs(tbl) do
            if type(v) == "table" then
                local alive = (v.expiresAt and v.expiresAt > now) or (v.at and (now - v.at) < 95)
                if alive then
                    local gk = tostring(k):lower()
                    if not gk:find("^0x") then gk = "0x" .. gk end
                    merged[gk] = v.kind or 1
                elseif pruneExpired and v.expiresAt then
                    tbl[k] = nil
                end
            end
        end
    end
    CollectShards(type(pd) == "table" and pd.shards or nil, false)
    CollectShards(SS.dsp.shards, true)
    local activeShards, cnt1, cnt2, cnt3 = 0, 0, 0, 0
    for _, kind in pairs(merged) do
        activeShards = activeShards + 1
        if kind == 1 then cnt1 = cnt1 + 1
        elseif kind == 2 then cnt2 = cnt2 + 1
        elseif kind == 3 then cnt3 = cnt3 + 1 end
    end
    local alertOn
    if type(pd) == "table" and pd.alertOn ~= nil then
        alertOn = (pd.alertOn == true)
    else
        alertOn = (SS.dsp.alertOn ~= false)
    end
    return {
        skill = tonumber(st.srvSkill) or tonumber(st.skill) or SS.dsp.skill or 0,
        maxSkill = tonumber(st.srvMax) or tonumber(st.maxSkill) or SS.dsp.maxSkill or 0,
        rank = tonumber(st.srvRank) or tonumber(st.rank) or SS.dsp.rank or 0,
        alertOn = alertOn,
        activeShards = activeShards,
        violetShards = cnt1,
        orangeShards = cnt2,
        radiantShards = cnt3,
        sessionDust = SS.dsp.sessionDust or 0,
        sessionGained = SS.dsp.sessionGained or 0,
    }
end

local function ResolveWorldBossName(entry)
    if SS.wb.names[entry] then return SS.wb.names[entry] end
    if entry == 909999 then return "Марафон мировых боссов (CD)" end
    if entry == 909998 then return "Марафон: завершен" end
    if entry == 909997 then return "Марафон: провален" end
    local wt = rawget(_G, "WaveTrial")
    local byE = wt and wt.data and wt.data.bosses and wt.data.bosses.byEntry
    if byE and byE[entry] and byE[entry].name then
        SS.wb.names[entry] = byE[entry].name
        return byE[entry].name
    end
    local je = rawget(_G, "JOURNALENCOUNTER")
    if type(je) == "table" then
        local encId = entry + 80040
        for cid = 990001, 990004 do
            local catList = je[cid]
            if type(catList) == "table" then
                for _, row in ipairs(catList) do
                    if type(row) == "table" and row[1] == encId and row[2] then
                        SS.wb.names[entry] = row[2]
                        return row[2]
                    end
                end
            end
        end
    end
    local cre = AP.Data and AP.Data.Creatures
    if cre and cre[entry] then
        return tostring(cre[entry])
    end
    return "Мировой босс #" .. tostring(entry)
end

function AP:GetWorldBossList()
    local nowOffset = 0
    if SS.wb.srvNow and SS.wb.locSnap then
        nowOffset = SS.wb.srvNow + (GetTime() - SS.wb.locSnap)
    end
    local seen, out = {}, {}
    -- Check standard range 910060..910099 if JOURNALENCOUNTER or CD table has them
    local je = rawget(_G, "JOURNALENCOUNTER")
    if type(je) == "table" then
        for cid = 990001, 990004 do
            for _, row in ipairs(je[cid] or {}) do
                if type(row) == "table" and row[1] then
                    local entry = row[1] - 80040
                    seen[entry] = true
                    if row[2] then SS.wb.names[entry] = row[2] end
                end
            end
        end
    end
    for e in pairs(SS.wb.cd) do seen[e] = true end
    for entry in pairs(seen) do
        local readyAt = SS.wb.cd[entry] or 0
        local rem = (nowOffset > 0 and readyAt > nowOffset) and (readyAt - nowOffset) or 0
        out[#out + 1] = {
            entry = entry,
            name = ResolveWorldBossName(entry),
            ready = (rem <= 0),
            remSec = math_floor(rem),
            remText = (rem > 0) and FormatDuration(rem) or "Готов",
            isMarathon = (entry >= 909997 and entry <= 909999),
        }
    end
    table.sort(out, function(a, b)
        if a.isMarathon ~= b.isMarathon then return a.isMarathon end
        if a.ready ~= b.ready then return a.ready end
        if a.remSec ~= b.remSec then return a.remSec < b.remSec end
        return a.entry < b.entry
    end)
    return out
end

-- AutoAbsorb & AutoSell direct server setters
function AP:SetAutoAbsorbGroupBit(bitVal, on)
    local cur = (AP.autoSwap and AP.autoSwap.groupMask) or 3
    local nxt = ToggleBitVal(cur, bitVal, 32, on)
    AP.autoSwap.groupMask = nxt
    SendSrv("ACMSG_AAMASK_SET", tostring(nxt))
    AP:Fire("AUTOSWAP_UPDATED", "LOCAL")
    return nxt
end

function AP:SetAutoAbsorbQualBit(bitVal, on)
    local cur = (AP.autoSwap and AP.autoSwap.qualMask) or 60
    local nxt = ToggleBitVal(cur, bitVal, 64, on)
    AP.autoSwap.qualMask = nxt
    SendSrv("ACMSG_AAQUAL_SET", tostring(nxt))
    AP:Fire("AUTOSWAP_UPDATED", "LOCAL")
    return nxt
end

function AP:SetAutoSellQualBit(bitVal, on)
    if not (AP.autoSwap and AP.autoSwap.unlocked) then return nil end
    local cur = AP.autoSwap.sellMask or 0
    local nxt = ToggleBitVal(cur, bitVal, 64, on)
    AP.autoSwap.sellMask = nxt
    SendSrv("ACMSG_AS_QMASK_SET", tostring(nxt))
    AP:Fire("AUTOSWAP_UPDATED", "LOCAL")
    return nxt
end

function AP:SetAutoSellSrcBit(bitVal, on)
    if not (AP.autoSwap and AP.autoSwap.unlocked) then return nil end
    local cur = AP.autoSwap.srcMask or 2
    local nxt = ToggleBitVal(cur, bitVal, 4, on)
    AP.autoSwap.srcMask = nxt
    SendSrv("ACMSG_AS_SRC_SET", tostring(nxt))
    AP:Fire("AUTOSWAP_UPDATED", "LOCAL")
    return nxt
end

function AP:SetAutoSellConfirm(on)
    if not (AP.autoSwap and AP.autoSwap.unlocked) then return false end
    AP.autoSwap.confirm = on and true or false
    SendSrv("ACMSG_AS_CONFIRM_SET", AP.autoSwap.confirm and "1" or "0")
    AP:Fire("AUTOSWAP_UPDATED", "LOCAL")
    return true
end

function AP:PromptUnlockAutoSell()
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs["ATTUNEPARSER_UNLOCK_AS"] = {
            text = "Разблокировать авто-продажу поглощенных за 30 Донат монет?\nДействует на весь аккаунт.",
            button1 = YES or "Да",
            button2 = NO or "Нет",
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            OnAccept = function()
                SendSrv("ACMSG_AS_UNLOCK", "1")
            end,
        }
        StaticPopup_Show("ATTUNEPARSER_UNLOCK_AS")
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- 3. Wrappers on AttuneParser core (safe, preserves original logic)
---------------------------------------------------------------------------
do
    local origReqSync = AP.RequestServerSync
    if type(origReqSync) == "function" then
        function AP:RequestServerSync(force)
            origReqSync(self, force)
            AP:RequestWhereItemsSync()
            AP:RequestWorldBossCD()
            local pc = rawget(_G, "ParagonCore")
            local sd = rawget(_G, "serverData")
            if type(pc) == "table" and type(pc.RequestData) == "function"
               and (force or not (type(sd) == "table" and (tonumber(sd.level) or 0) > 0)) then
                pcall(pc.RequestData, force)
            end
        end
    end

    local origStock = AP.GetForgeMaterialStock
    if type(origStock) == "function" then
        function AP:GetForgeMaterialStock()
            local st = origStock(self)
            local rb, rbUsed, rbMax = AP:GetResourceBankCounts()
            local ids = AP.FORGE_ITEM_IDS or {}
            local r1 = (st.rate1 and st.rate1 > 0) and st.rate1 or 3
            local r2 = (st.rate2 and st.rate2 > 0) and st.rate2 or 3
            local fee = st.bagumFeeCopper or 1000000

            local rbEp = rb[ids.dustEpic or 70017] or 0
            local rbLg = rb[ids.dustLeg or 70018] or 0
            local rbTi = rb[ids.dustTit or 70019] or 0
            local rbFr = rb[ids.frostEmblem or 49426] or 0
            local rbTr = rb[ids.triumphEmblem or 47241] or 0

            st.rbDustEpic = rbEp
            st.rbDustLeg = rbLg
            st.rbDustTit = rbTi
            st.rbPartEpic = rb[70021] or 0
            st.rbPartLeg = rb[70022] or 0
            st.rbPartTit = rb[70023] or 0
            st.rbUsed = rbUsed or 0
            st.rbMax = rbMax or 0
            st.rbActive = (next(rb) ~= nil) or (rbMax > 0)

            st.dustEpic = (st.dustEpic or 0) + rbEp
            st.dustLeg = (st.dustLeg or 0) + rbLg
            st.dustTit = (st.dustTit or 0) + rbTi
            st.totalTitanInstant = (st.totalTitanInstant or 0) + rbTi

            st.epicToLeg = math_floor(st.dustEpic / r1)
            st.epicRem = st.dustEpic % r1
            st.legAfterCraft = st.dustLeg + st.epicToLeg
            st.legToTit = math_floor(st.legAfterCraft / r2)
            st.legDirectToTit = math_floor(st.dustLeg / r2)
            st.legRem = st.legAfterCraft % r2
            st.craftableTit = st.legToTit
            st.totalTitPotential = st.dustTit + (st.titanBoxes or 0) + st.legToTit
            st.bagumTitCostCopper = (st.epicToLeg + st.legToTit) * fee

            st.frostEmblem = (st.frostEmblem or 0) + rbFr
            st.triumphEmblem = (st.triumphEmblem or 0) + rbTr
            st.triToFrost = math_floor(st.triumphEmblem / 2)
            st.frostFromLowerEmblems = st.triToFrost
                + math_floor(((rb[45624] or 0) + ((type(GetItemCount) == "function" and tonumber(GetItemCount(45624, true))) or 0)) / 3)
                + math_floor(((rb[40753] or 0) + ((type(GetItemCount) == "function" and tonumber(GetItemCount(40753, true))) or 0)) / 3)
                + math_floor(((rb[40752] or 0) + ((type(GetItemCount) == "function" and tonumber(GetItemCount(40752, true))) or 0)) / 3)
            st.totalFrostPotential = st.frostEmblem + st.frostFromLowerEmblems
            return st
        end
    end

    local origOwned = AP.GetOwnedUpgradeCandidates
    if type(origOwned) == "function" then
        function AP:GetOwnedUpgradeCandidates(zoneIdFilter, includeNeedsForge)
            -- Ensure equipped forge tiers from item bank worn state are reflected before scanning slots
            local pib = rawget(_G, "PRIME_ItemBank")
            local wornTbl = (type(SS.ib.worn) == "table" and next(SS.ib.worn) ~= nil and SS.ib.worn) or nil
            if wornTbl or (type(pib) == "table" and type(pib.worn) == "table") then
                AP.forgeEquip = AP.forgeEquip or {}
                for slot = 1, 18 do
                    if AP.forgeEquip[slot] == nil then
                        local wt = (wornTbl and wornTbl[slot]) or (pib and pib.worn and pib.worn[slot - 1])
                        if type(wt) == "number" and wt >= 0 then
                            AP.forgeEquip[slot] = wt
                        end
                    end
                end
            end

            local out = origOwned(self, zoneIdFilter, includeNeedsForge)
            local hasBank = false
            local seenKey = {}
            for _, row in ipairs(out) do
                if row.where == "bank" then hasBank = true end
                if row.where == "itembank" and row.guid then
                    seenKey["itembank:g:" .. row.guid] = true
                else
                    seenKey[(row.where or "") .. ":" .. (row.itemId or 0) .. ":" .. (row.instanceTier or 0)] = true
                end
            end

            local topFilter = (zoneIdFilter and AP.Data and AP.Data.TopMap and AP.Data.TopMap[zoneIdFilter]) or zoneIdFilter
            local function TryPush(whereLabel, eid, link, pTier, guid, cntVal, dspVal)
                if not eid or eid <= 0 then return end
                if not AP:CanHeroAbsorb(eid, link) then return end
                local info = AP:GetItemInfo(eid, link)
                if not info or info.isCompleted then return end
                pTier = tonumber(pTier) or 0
                local doneTier = (info.doneTier ~= nil) and info.doneTier or -1
                if (not includeNeedsForge) and pTier <= doneTier then return end
                if zoneIdFilter and info.primaryZone ~= topFilter and info.primaryZone ~= zoneIdFilter then return end
                local dupK = whereLabel .. ":" .. eid .. ":" .. pTier
                if guid then dupK = whereLabel .. ":g:" .. guid end
                if seenKey[dupK] then return end
                seenKey[dupK] = true

                local gPct = (AP.TIER_PCT and AP.TIER_PCT[pTier]) or 20
                local canNow = pTier > doneTier
                info.where = whereLabel
                info.guid = guid
                info.count = cntVal or 1
                info.dsp = dspVal or 0
                info.link = link
                info.instanceTier = pTier
                info.instanceTierName = (AP.TIER_NAMES and AP.TIER_NAMES[pTier]) or ""
                info.isBlacklisted = AP:IsItemBlacklisted(eid, pTier)
                info.canGainNow = canNow
                info.needsForgeUpgrade = not canNow
                info.gainNowPct = canNow and math_max(0, gPct - (info.curPct or 0)) or 0
                info.gainNowStats = canNow and math_floor((info.coreStatsSum or 0) * (info.gainNowPct / 100) + 0.5) or 0
                out[#out + 1] = info
            end

            -- 1) Live PRIME_ItemBank / SS.ib merged with ASMSG_WH_IBG until full IB snapshot loads
            local ibItems = (SS._ibGetItems and SS._ibGetItems()) or SS.ib.items or {}
            for _, it in ipairs(ibItems) do
                if type(it) == "table" and it.entry then
                    local fTier = it.forge or (AP.forgeByEntry and AP.forgeByEntry[it.entry]) or 0
                    TryPush("itembank", it.entry, it.link, fTier, it.guid, 1, it.dsp)
                end
            end

            -- 2) Fallback bank items from WhereItems if WoW Bank hasn't been opened yet
            if not hasBank then
                local pwh = rawget(_G, "PRIME_WhereItems")
                local bk = (type(pwh) == "table" and type(pwh.bk) == "table" and next(pwh.bk) ~= nil) and pwh.bk or SS.wh.bk
                for eid, cnt in pairs(bk) do
                    if (cnt or 0) > 0 then
                        local fTier = (AP.forgeByEntry and AP.forgeByEntry[eid]) or 0
                        TryPush("bank", eid, "item:" .. eid, fTier, nil, cnt, 0)
                    end
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
    end

    local origSlash = SlashCmdList and SlashCmdList["ATTUNEPARSER"]
    if type(origSlash) == "function" then
        SlashCmdList["ATTUNEPARSER"] = function(msg)
            local norm = AP.Norm and AP.Norm(msg or "") or string.lower(msg or "")
            if norm == "server" or norm == "wb" or norm == "boss" or norm == "vault" then
                if type(AP.OpenUI) == "function" then
                    AP:OpenUI("server")
                    return
                end
            elseif norm == "rb" then
                AP:OpenResourceBank()
                return
            elseif norm == "ibauto" or norm == "ibauto on" or norm == "ibauto off" then
                local want
                if norm == "ibauto on" then want = true
                elseif norm == "ibauto off" then want = false
                else want = not (AP:GetSetting("ibAutoEquip") == true) end
                AP:SetItemBankAutoEquip(want)
                local sum = AP:GetItemBankEquipSummary(true)
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format(
                        "|cff38bdf8[AttuneParser]|r Автонадевание из Банка вещей: %s | В банке: %d шт., подходящих сейчас: %d",
                        want and "|cff40ff40ВКЛ|r" or "|cffff6060ВЫКЛ|r",
                        sum.itemCount or 0, sum.eligibleCount or 0
                    ))
                end
                return
            elseif norm == "ibequip" then
                local ok, reason, cand = AP:RunItemBankAutoEquip(true)
                if DEFAULT_CHAT_FRAME then
                    if ok and type(cand) == "table" then
                        DEFAULT_CHAT_FRAME:AddMessage(string.format(
                            "|cff38bdf8[AttuneParser]|r Надет предмет из Банка вещей: %s (ilvl %d)",
                            cand.link or cand.name or ("#" .. tostring(cand.entry)), cand.ilvl or 0
                        ))
                    else
                        DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Автонадевание: " .. tostring(reason or "нет подходящих"))
                    end
                end
                return
            elseif norm == "ibputauto" or norm == "ibputauto on" or norm == "ibputauto off" then
                local want
                if norm == "ibputauto on" then want = true
                elseif norm == "ibputauto off" then want = false
                else want = not (AP:GetSetting("ibAutoPut") == true) end
                AP:SetItemBankAutoPut(want)
                local psum = AP:GetItemBankPutSummary(true)
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format(
                        "|cff38bdf8[AttuneParser]|r Автосклад в Банк вещей: %s | Режим: %s | Готово к переносу: %d",
                        want and "|cff40ff40ВКЛ|r" or "|cffff6060ВЫКЛ|r",
                        tostring(psum.modeLabel or "?"),
                        psum.eligibleCount or 0
                    ))
                end
                return
            elseif norm == "ibputmode" then
                local nm, lbl = AP:CycleItemBankPutMode()
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Режим автосклада в Банк вещей: " .. tostring(lbl or nm))
                end
                return
            elseif norm == "ibput" then
                local ok, reason, cand = AP:RunItemBankAutoPut(true)
                if DEFAULT_CHAT_FRAME then
                    if ok and type(cand) == "table" then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Положено в Банк вещей: " .. tostring(cand.link or cand.name or cand.eid))
                    else
                        DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Автосклад: " .. tostring(reason or "нет подходящих"))
                    end
                end
                return
            elseif norm == "ibdebug" then
                if type(AP.DebugItemBankAuto) == "function" then
                    AP:DebugItemBankAuto()
                end
                return
            elseif norm == "ibsplit" or norm == "ibsplit go" or norm == "ibsplit stop" then
                if norm == "ibsplit stop" and type(AP.StopItemBankSplit) == "function" then
                    AP:StopItemBankSplit("user")
                    return
                elseif norm == "ibsplit go" and type(AP.StartItemBankSplit) == "function" then
                    AP:StartItemBankSplit(true)
                    return
                elseif type(AP.GetItemBankSplitPlan) == "function" then
                    local sp = AP:GetItemBankSplitPlan(true)
                    if DEFAULT_CHAT_FRAME then
                        if not sp.available then
                            DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Расщепление дублей недоступно: " .. tostring(sp.reason or "?"))
                        elseif (sp.totalCount or 0) == 0 then
                            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff38bdf8[AttuneParser]|r В Банке вещей нет лишних поглощенных вещей для расщепления (оставлено под ковку: %d).", sp.keptForge or 0))
                        else
                            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff38bdf8[AttuneParser]|r К расщеплению в Банке вещей: %d шт. (%d групп, пакетно=%s; под ковку оставлено: %d). Запуск: /ap ibsplit go | стоп: /ap ibsplit stop",
                                sp.totalCount or 0, sp.groupCount or 0, sp.dspBatch and "да" or "нет", sp.keptForge or 0))
                        end
                    end
                    return
                end
            elseif norm == "valdris" or norm == "valdris go" or norm == "valdris stop" or norm == "valdris auto" or norm == "valdris eq" or norm == "valdris bank" or norm:sub(1, 11) == "valdris max" then
                if norm == "valdris stop" and type(AP.StopValdrisAutoUpgrade) == "function" then
                    AP:StopValdrisAutoUpgrade("user")
                    return
                elseif norm == "valdris go" and type(AP.StartValdrisAutoUpgrade) == "function" then
                    local ok, reason = AP:StartValdrisAutoUpgrade()
                    if not ok and DEFAULT_CHAT_FRAME then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Прогрессия: " .. tostring(reason or "недоступно"))
                    end
                    return
                elseif norm == "valdris auto" and type(AP.SetValdrisAutoOpen) == "function" then
                    local nv = AP:SetValdrisAutoOpen(not (AP:GetSetting("valdrisAutoOpen") == true))
                    if DEFAULT_CHAT_FRAME then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Авто-старт при открытии окна улучшения: " .. (nv and "|cff40ff40ВКЛ|r" or "|cffff6060ВЫКЛ|r"))
                    end
                    return
                elseif norm == "valdris eq" and type(AP.SetValdrisIncludeEquipped) == "function" then
                    local nv = AP:SetValdrisIncludeEquipped(not (AP:GetSetting("valdrisIncludeEquipped") == true))
                    if DEFAULT_CHAT_FRAME then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Снимать надетые для автоулучшения: " .. (nv and "|cff40ff40ВКЛ|r" or "|cffff6060ВЫКЛ|r"))
                    end
                    return
                elseif norm == "valdris bank" and type(AP.SetValdrisIncludeBank) == "function" then
                    local nv = AP:SetValdrisIncludeBank(not (AP:GetSetting("valdrisIncludeBank") ~= false))
                    if DEFAULT_CHAT_FRAME then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Брать из Банка вещей для автоулучшения: " .. (nv and "|cff40ff40ВКЛ|r" or "|cffff6060ВЫКЛ|r"))
                    end
                    return
                elseif norm:sub(1, 11) == "valdris max" and type(AP.SetValdrisMaxTier) == "function" then
                    local tNum = tonumber(norm:match("(%d+)"))
                    if tNum and tNum >= 1 and tNum <= 3 then
                        local nt = AP:SetValdrisMaxTier(tNum)
                        if DEFAULT_CHAT_FRAME then
                            DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Макс. ступень улучшения: " .. tostring(nt))
                        end
                    end
                    return
                elseif type(AP.GetValdrisUpgradeSummary) == "function" then
                    local vs = AP:GetValdrisUpgradeSummary(true)
                    if DEFAULT_CHAT_FRAME then
                        DEFAULT_CHAT_FRAME:AddMessage(string.format(
                            "|cff38bdf8[AttuneParser]|r Прогрессия: окно=%s | готово=%d | цель<=%d | авто=%s | Банк вещей=%s | надетые=%s | /ap valdris go | stop | bank | eq",
                            vs.windowOpen and "|cff40ff40откр.|r" or "|cffff6060закр.|r",
                            vs.eligibleCount or 0, vs.maxTier or 3, vs.autoOpen and "ВКЛ" or "ВЫКЛ", vs.includeBank and "ВКЛ" or "ВЫКЛ", vs.includeEquipped and "ВКЛ" or "ВЫКЛ"
                        ))
                    end
                    return
                end
            end
            return origSlash(msg)
        end
    end
end

---------------------------------------------------------------------------
-- 3b. Auto-Equip from ItemBank (ACMSG_IB_EQUIP)
---------------------------------------------------------------------------
do
    local ibEq = SS.ibEq
    local SLOT_FALLBACK = {
        HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, BackSlot = 15, ChestSlot = 5,
        WristSlot = 9, HandsSlot = 10, WaistSlot = 6, LegsSlot = 7, FeetSlot = 8,
        Finger0Slot = 11, Finger1Slot = 12, Trinket0Slot = 13, Trinket1Slot = 14,
        MainHandSlot = 16, SecondaryHandSlot = 17, RangedSlot = 18,
    }
    local IB_SLOT_DEFS = {
        { inv = "HeadSlot",          grp = 1,  loc = { INVTYPE_HEAD = true } },
        { inv = "NeckSlot",          grp = 2,  loc = { INVTYPE_NECK = true } },
        { inv = "ShoulderSlot",      grp = 1,  loc = { INVTYPE_SHOULDER = true } },
        { inv = "BackSlot",          grp = 1,  loc = { INVTYPE_CLOAK = true } },
        { inv = "ChestSlot",         grp = 1,  loc = { INVTYPE_CHEST = true, INVTYPE_ROBE = true } },
        { inv = "WristSlot",         grp = 1,  loc = { INVTYPE_WRIST = true } },
        { inv = "HandsSlot",         grp = 1,  loc = { INVTYPE_HAND = true } },
        { inv = "WaistSlot",         grp = 1,  loc = { INVTYPE_WAIST = true } },
        { inv = "LegsSlot",          grp = 1,  loc = { INVTYPE_LEGS = true } },
        { inv = "FeetSlot",          grp = 1,  loc = { INVTYPE_FEET = true } },
        { inv = "Finger0Slot",       grp = 2,  loc = { INVTYPE_FINGER = true } },
        { inv = "Finger1Slot",       grp = 2,  loc = { INVTYPE_FINGER = true } },
        { inv = "Trinket0Slot",      grp = 2,  loc = { INVTYPE_TRINKET = true } },
        { inv = "Trinket1Slot",      grp = 2,  loc = { INVTYPE_TRINKET = true } },
        { inv = "MainHandSlot",      grp = 4,  loc = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true } },
        { inv = "SecondaryHandSlot", grp = 8,  loc = { INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPON = true } },
        { inv = "RangedSlot",        grp = 16, loc = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true } },
    }
    for _, d in ipairs(IB_SLOT_DEFS) do
        local sid = (type(GetInventorySlotInfo) == "function") and select(1, GetInventorySlotInfo(d.inv))
        d.id = sid or SLOT_FALLBACK[d.inv]
    end

    local SLOT_ID_BY_INV = {}
    for _, d in ipairs(IB_SLOT_DEFS) do
        SLOT_ID_BY_INV[d.inv] = d.id
    end

    local scanTip
    local function EnsureScanTip()
        if not scanTip and type(CreateFrame) == "function" then
            scanTip = CreateFrame("GameTooltip", "AP_IBAutoScanTip", UIParent, "GameTooltipTemplate")
            if scanTip and scanTip.SetOwner then
                scanTip:SetOwner(UIParent, "ANCHOR_NONE")
            end
        end
        return scanTip
    end

    local IB_SLOT_LOCS = {}
    for _, d in ipairs(IB_SLOT_DEFS) do
        for loc in pairs(d.loc) do IB_SLOT_LOCS[loc] = true end
    end
    SS._ibSlotLocs = IB_SLOT_LOCS

    local function WarmItemCache(link)
        local t = EnsureScanTip()
        if not t or type(t.SetHyperlink) ~= "function" then return end
        t:SetOwner(UIParent, "ANCHOR_NONE")
        if t.ClearLines then t:ClearLines() end
        pcall(t.SetHyperlink, t, link)
        if t.Hide then t:Hide() end
    end
    SS._ibWarmCache = WarmItemCache
    SS._ibEnsureScanTip = EnsureScanTip

    local boeCache = {}
    local canEquipCache = {}
    local recentEquipTier = {}

    local function ScanBindFromTip(t)
        local n = (t.NumLines and t:NumLines()) or 0
        if n > 7 then n = 7 end
        local boeGlobal = rawget(_G, "ITEM_BIND_ON_EQUIP")
        local sbGlobal = rawget(_G, "ITEM_SOULBOUND")
        local bopGlobal = rawget(_G, "ITEM_BIND_ON_PICKUP")
        for i = 2, n do
            local fs = rawget(_G, "AP_IBAutoScanTipTextLeft" .. i)
            local txt = fs and fs.GetText and fs:GetText()
            if txt then
                if (boeGlobal and txt == boeGlobal)
                   or txt == "Становится персональным при надевании"
                   or txt == "Binds when equipped" then
                    return true, n
                end
                if (sbGlobal and txt == sbGlobal)
                   or (bopGlobal and txt == bopGlobal)
                   or txt == "Персональный предмет"
                   or txt == "Становится персональным при получении" then
                    return false, n
                end
            end
        end
        return false, n
    end

    local function IsTipLineRed(fs)
        if not fs or not fs.GetTextColor then return false end
        local txt = fs.GetText and fs:GetText()
        if txt and ((txt:find(" со стороны ", 1, true) and txt:find("^Требуется")) or txt:find("^Requires .+ %- ")) then
            return false
        end
        local r, g, b = fs:GetTextColor()
        return r and r > 0.8 and (g or 1) < 0.3 and (b or 1) < 0.3
    end

    local function CanPlayerEquipTip(eid, link, bag, slot)
        if not link and not bag then return true end
        if eid and canEquipCache[eid] ~= nil and not bag then
            return canEquipCache[eid]
        end
        local t = EnsureScanTip()
        if not t then return true end
        t:SetOwner(UIParent, "ANCHOR_NONE")
        if t.ClearLines then t:ClearLines() end
        local ok = false
        if bag and slot and type(t.SetBagItem) == "function" then
            ok = pcall(t.SetBagItem, t, bag, slot)
        end
        if (not ok or ((t.NumLines and t:NumLines()) or 0) == 0) and link and type(t.SetHyperlink) == "function" then
            if t.ClearLines then t:ClearLines() end
            ok = pcall(t.SetHyperlink, t, link)
        end
        if not ok then return true end
        local n = (t.NumLines and t:NumLines()) or 0
        if n < 2 then return true end
        local res = true
        for i = 2, n do
            if IsTipLineRed(rawget(_G, "AP_IBAutoScanTipTextLeft" .. i))
               or IsTipLineRed(rawget(_G, "AP_IBAutoScanTipTextRight" .. i)) then
                res = false
                break
            end
        end
        if eid then canEquipCache[eid] = res end
        if t.Hide then t:Hide() end
        return res
    end

    local function IsItemBoE(link, bag, slot, eid)
        if not link and not bag then return false end
        local t = EnsureScanTip()
        if not t then return false end
        if bag and slot and type(t.SetBagItem) == "function" then
            t:SetOwner(UIParent, "ANCHOR_NONE")
            if t.ClearLines then t:ClearLines() end
            local ok = pcall(t.SetBagItem, t, bag, slot)
            if ok then
                local isB, n = ScanBindFromTip(t)
                if n >= 2 then
                    if t.Hide then t:Hide() end
                    return isB
                end
            end
        end
        if eid and boeCache[eid] ~= nil then
            return boeCache[eid]
        end
        if type(t.SetHyperlink) ~= "function" or not link then return false end
        t:SetOwner(UIParent, "ANCHOR_NONE")
        if t.ClearLines then t:ClearLines() end
        local ok = pcall(t.SetHyperlink, t, link)
        if not ok then return false end
        local isB, n = ScanBindFromTip(t)
        if t.Hide then t:Hide() end
        if eid and n >= 2 then boeCache[eid] = isB end
        return isB
    end
    SS._ibIsBoE = IsItemBoE
    SS._ibCanEquip = CanPlayerEquipTip

    local function CanPlayerDW()
        local cdw = rawget(_G, "CanDualWield")
        if type(cdw) == "function" then
            local ok, res = pcall(cdw)
            if ok then return res and true or false end
        end
        if type(IsSpellKnown) == "function" and (IsSpellKnown(674) or IsSpellKnown(30798) or IsSpellKnown(46917)) then
            return true
        end
        if type(UnitClass) == "function" then
            local _, cls = UnitClass("player")
            if cls == "WARRIOR" or cls == "ROGUE" or cls == "HUNTER" or cls == "DEATHKNIGHT" or cls == "DEMONHUNTER" then
                return true
            end
        end
        local ohId = SLOT_ID_BY_INV.SecondaryHandSlot
        local oh = ohId and type(GetInventoryItemLink) == "function" and GetInventoryItemLink("player", ohId)
        if oh and type(GetItemInfo) == "function" then
            local _, _, _, _, _, _, _, _, el = GetItemInfo(oh)
            if el == "INVTYPE_WEAPON" then return true end
        end
        return false
    end

    local function CanPlayerTG()
        if type(IsSpellKnown) == "function" and IsSpellKnown(46917) then
            return true
        end
        if type(IsPlayerSpell) == "function" and IsPlayerSpell(46917) then
            return true
        end
        local ohId = SLOT_ID_BY_INV.SecondaryHandSlot
        local oh = ohId and type(GetInventoryItemLink) == "function" and GetInventoryItemLink("player", ohId)
        if oh and type(GetItemInfo) == "function" then
            local _, _, _, _, _, _, _, _, el = GetItemInfo(oh)
            if el == "INVTYPE_2HWEAPON" then return true end
        end
        return false
    end

    local function IsTGTwoHandSubType(st)
        if not st or st == "" then return true end
        return st ~= "Посохи" and st ~= "Staves"
            and st ~= "Древковое" and st ~= "Polearms"
            and st ~= "Удочки" and st ~= "Fishing Poles"
    end
    SS._ibCanDW = CanPlayerDW
    SS._ibCanTG = CanPlayerTG

    local function GetIBItems()
        local pib = rawget(_G, "PRIME_ItemBank")
        if type(pib) == "table" and type(pib.items) == "table" and #pib.items > 0 then
            return pib.items, true
        end
        if SS.ib.fullLoaded then
            return SS.ib.items, true
        end
        local pwh = rawget(_G, "PRIME_WhereItems")
        local ibg = (type(pwh) == "table" and type(pwh.ibg) == "table" and next(pwh.ibg) ~= nil) and pwh.ibg or SS.wh.ibg
        if (type(ibg) == "table" and next(ibg) ~= nil) or #SS.ib.items > 0 then
            local merged = {}
            local seen = {}
            for _, it in ipairs(SS.ib.items or {}) do
                if it and it.guid then
                    seen[it.guid] = true
                    merged[#merged + 1] = it
                end
            end
            if type(ibg) == "table" then
                for guid, eid in pairs(ibg) do
                    local g = tonumber(guid)
                    local e = tonumber(eid)
                    if g and e and e > 0 and not seen[g] then
                        seen[g] = true
                        local pibIt = (type(pib) == "table" and type(pib.byGuid) == "table") and pib.byGuid[g] or nil
                        merged[#merged + 1] = {
                            guid = g,
                            entry = e,
                            suffix = (pibIt and tonumber(pibIt.suffix)) or 0,
                            forge = (pibIt and tonumber(pibIt.forge)) or (AP.forgeByEntry and AP.forgeByEntry[e]) or 0,
                            link = (pibIt and pibIt.link) or ("item:" .. e),
                        }
                    end
                end
            end
            return merged, true
        end
        return SS.ib.items or {}, false
    end
    SS._ibGetItems = GetIBItems

    local function IsEquippedSlotReplaceable(curLink, slotId)
        if not curLink then return true end
        local eid = AP.ExtractItemId and AP.ExtractItemId(curLink)
        if not eid then return false end
        local curSfx = AP.ExtractSuffix and AP.ExtractSuffix(curLink) or 0
        local pib = rawget(_G, "PRIME_ItemBank")
        local curForge = (AP.forgeEquip and AP.forgeEquip[slotId])
            or (SS.ib.worn and SS.ib.worn[slotId])
            or (type(pib) == "table" and type(pib.worn) == "table" and slotId and pib.worn[slotId - 1])
            or 0
        local rec = slotId and recentEquipTier[slotId]
        if rec and rec.eid == eid and GetTime() < (rec.untilAt or 0) and (rec.forge or 0) > curForge then
            curForge = rec.forge
        end
        local fnSrv = rawget(_G, "CustomAttuneItemStatus")
        if type(fnSrv) == "function" then
            local ok, done = pcall(fnSrv, eid, curForge, curSfx)
            if ok then return done == true end
        end
        if type(AP.CanHeroAbsorb) == "function" then
            local usable = AP:CanHeroAbsorb(eid, curLink)
            if not usable then return false end
        end
        if type(AP.GetItemServerStatus) == "function" then
            local st = AP:GetItemServerStatus(eid, curLink)
            if st then
                return (st.isCompleted == true) or ((st.doneTier or -1) >= curForge)
            end
        end
        return false
    end

    local function GetIBCandidateMeta(it, now, plvl, qualMask, boeAllowed, usedKeys, seenWarm)
        local guid = tonumber(it and it.guid)
        local eid = tonumber(it and it.entry)
        if not guid or not eid or eid <= 0 then return nil end
        if eid >= 1702000 and eid <= 1702999 then return nil end
        if (ibEq.failUntil[guid] or 0) > now then return nil end

        if it.flags ~= nil then
            if not HasBit(it.flags, 0) or not HasBit(it.flags, 4) then
                return nil, "not_usable"
            end
        end

        local forge = tonumber(it.forge) or 0
        local sfx = tonumber(it.suffix) or 0
        local link = it.link or ("item:" .. eid)
        if type(AP.IsItemBlacklisted) == "function" and AP:IsItemBlacklisted(eid, forge) then
            return nil, "blacklist"
        end

        local fnSrv = rawget(_G, "CustomAttuneItemStatus")
        local srvChecked = false
        if type(fnSrv) == "function" then
            local ok, done, cant, _, attun = pcall(fnSrv, eid, forge, sfx)
            if ok and attun ~= nil then
                srvChecked = true
                if attun == false or cant then
                    return nil, "not_usable"
                end
                if done then
                    return nil, "absorbed"
                end
            end
        end
        if not srvChecked then
            if type(AP.CanHeroAbsorb) == "function" then
                local usable = AP:CanHeroAbsorb(eid, link)
                if not usable then return nil, "not_usable" end
            end
            if type(AP.GetItemServerStatus) == "function" then
                local st = AP:GetItemServerStatus(eid, link)
                if st and (st.isCompleted or (st.doneTier or -1) >= forge) then
                    return nil, "absorbed"
                end
            end
        end

        local key = eid .. ":" .. sfx
        if usedKeys[key] then return nil, "dup_equipped" end

        local name, fullLink, q, ilvl, minLevel, _, subType, _, equipLoc
        if type(GetItemInfo) == "function" then
            name, fullLink, q, ilvl, minLevel, _, subType, _, equipLoc = GetItemInfo(link)
            if not equipLoc or equipLoc == "" then
                name, fullLink, q, ilvl, minLevel, _, subType, _, equipLoc = GetItemInfo(eid)
            end
        end
        if not equipLoc or equipLoc == "" then
            if seenWarm.n < 5 then
                seenWarm.n = seenWarm.n + 1
                WarmItemCache("item:" .. eid)
            end
            return "warm"
        end
        if (minLevel or 0) > plvl then return nil, "level" end

        q = tonumber(q) or tonumber(it.q) or 0
        if not HasBit(qualMask, q) then return nil, "quality" end
        if it.flags == nil and not CanPlayerEquipTip(eid, fullLink or link, it.bag, it.slot) then
            return nil, "not_usable"
        end
        if not boeAllowed and IsItemBoE(fullLink or link, it.bag, it.slot, eid) then return nil, "boe" end

        return {
            guid = guid,
            entry = eid,
            forge = forge,
            suffix = sfx,
            key = key,
            q = q,
            ilvl = tonumber(ilvl) or tonumber(it.ilvl) or 0,
            loc = equipLoc,
            subType = subType,
            name = name or it.name or ("#" .. eid),
            link = fullLink or link,
        }
    end

    local function IsBetterCandidate(a, b, orderWorst)
        if not b then return true end
        if orderWorst then
            if a.q ~= b.q then return a.q < b.q end
            if a.ilvl ~= b.ilvl then return a.ilvl < b.ilvl end
            return a.forge < b.forge
        end
        if a.q ~= b.q then return a.q > b.q end
        if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
        return a.forge > b.forge
    end

    local function PairedSlotSafe(invName, candLoc, replaceableById, canTG, isDirectBag, candSubType)
        if invName == "MainHandSlot" and candLoc == "INVTYPE_2HWEAPON"
           and not (canTG and IsTGTwoHandSubType(candSubType)) then
            local ohId = SLOT_ID_BY_INV.SecondaryHandSlot
            if ohId and type(GetInventoryItemLink) == "function" and GetInventoryItemLink("player", ohId) then
                return replaceableById[ohId] == true
            end
            return true
        end
        if isDirectBag then return true end
        local pairInv
        if invName == "Finger1Slot" then
            pairInv = "Finger0Slot"
        elseif invName == "Trinket1Slot" then
            pairInv = "Trinket0Slot"
        elseif invName == "SecondaryHandSlot" and candLoc == "INVTYPE_WEAPON" then
            pairInv = "MainHandSlot"
        end
        if not pairInv then return true end
        local curId = SLOT_ID_BY_INV[invName]
        local curLink = curId and type(GetInventoryItemLink) == "function" and GetInventoryItemLink("player", curId)
        if not curLink then return true end
        local pairId = SLOT_ID_BY_INV[pairInv]
        return pairId and (replaceableById[pairId] == true)
    end

    local function EvaluateIBPlan()
        local now = GetTime()
        local items, loaded = GetIBItems()
        local as = (type(AP.GetAutoSwapSummary) == "function" and AP:GetAutoSwapSummary()) or {}
        local useAAMask = (AP:GetSetting("ibUseAAMask") == true)
        local groupMask = useAAMask and (tonumber(as.groupMask) or 3) or 31
        local qualMask = tonumber(as.qualMask) or 60
        local orderWorst = (as.orderWorst == true)
        local boeAllowed = (as.boeAllowed == true)
        local plvl = (type(UnitLevel) == "function" and UnitLevel("player")) or 80

        local mhLink = SLOT_ID_BY_INV.MainHandSlot and type(GetInventoryItemLink) == "function"
            and GetInventoryItemLink("player", SLOT_ID_BY_INV.MainHandSlot)
        local mh2h = false
        if mhLink and type(GetItemInfo) == "function" then
            local _, _, _, _, _, _, _, _, el = GetItemInfo(mhLink)
            mh2h = (el == "INVTYPE_2HWEAPON")
        end

        local replaceableById = {}
        local usedKeys = {}
        for _, d in ipairs(IB_SLOT_DEFS) do
            local cur = (d.id and type(GetInventoryItemLink) == "function") and GetInventoryItemLink("player", d.id) or nil
            local rep = IsEquippedSlotReplaceable(cur, d.id)
            replaceableById[d.id] = rep
            if cur and not rep then
                local ceid = AP.ExtractItemId and AP.ExtractItemId(cur)
                if ceid then
                    local csfx = AP.ExtractSuffix and AP.ExtractSuffix(cur) or 0
                    usedKeys[ceid .. ":" .. csfx] = true
                end
            end
        end

        local cands = {}
        local seenWarm = { n = 0 }
        local needsWarm = false
        local stats = { qual = 0, boe = 0, absorbed = 0, blockedSlot = 0, busySlot = 0 }
        for _, it in ipairs(items) do
            local meta, skipWhy = GetIBCandidateMeta(it, now, plvl, qualMask, boeAllowed, usedKeys, seenWarm)
            if meta == "warm" then
                needsWarm = true
            elseif type(meta) == "table" then
                cands[#cands + 1] = meta
            elseif skipWhy == "quality" then
                stats.qual = stats.qual + 1
            elseif skipWhy == "boe" then
                stats.boe = stats.boe + 1
            elseif skipWhy == "absorbed" then
                stats.absorbed = stats.absorbed + 1
            end
        end

        local canDW = CanPlayerDW()
        local canTG = CanPlayerTG()
        local blockOH2H = mh2h and (not canTG)
        local firstCand, firstSlot = nil, nil
        local eligibleCands = {}
        local blockedMaskCands, busyCands = {}, {}
        for _, d in ipairs(IB_SLOT_DEFS) do
            local grpOk = ((math_floor(groupMask / d.grp) % 2) == 1)
            local handOk = not (d.inv == "SecondaryHandSlot" and blockOH2H)
            if grpOk and handOk and replaceableById[d.id] then
                local best = nil
                for _, c in ipairs(cands) do
                    local locOk = d.loc[c.loc] or (d.inv == "SecondaryHandSlot" and canTG and c.loc == "INVTYPE_2HWEAPON" and IsTGTwoHandSubType(c.subType))
                    if locOk
                       and not (d.inv == "SecondaryHandSlot" and c.loc == "INVTYPE_WEAPON" and not canDW)
                       and PairedSlotSafe(d.inv, c.loc, replaceableById, canTG, false, c.subType) then
                        eligibleCands[c.guid] = true
                        if IsBetterCandidate(c, best, orderWorst) then
                            best = c
                        end
                    end
                end
                if best and not firstCand then
                    firstCand, firstSlot = best, d
                end
            elseif handOk then
                for _, c in ipairs(cands) do
                    local locOk = d.loc[c.loc] or (d.inv == "SecondaryHandSlot" and canTG and c.loc == "INVTYPE_2HWEAPON" and IsTGTwoHandSubType(c.subType))
                    if locOk and not (d.inv == "SecondaryHandSlot" and c.loc == "INVTYPE_WEAPON" and not canDW) then
                        if not grpOk then
                            blockedMaskCands[c.guid] = true
                        elseif not replaceableById[d.id] then
                            busyCands[c.guid] = true
                        end
                    end
                end
            end
        end

        local eligibleCount = 0
        for _ in pairs(eligibleCands) do eligibleCount = eligibleCount + 1 end
        for g in pairs(blockedMaskCands) do
            if not eligibleCands[g] then stats.blockedSlot = stats.blockedSlot + 1 end
        end
        for g in pairs(busyCands) do
            if not eligibleCands[g] and not blockedMaskCands[g] then stats.busySlot = stats.busySlot + 1 end
        end
        return {
            loaded = loaded,
            itemCount = #items,
            eligibleCount = eligibleCount,
            needsWarm = needsWarm,
            cand = firstCand,
            slotDef = firstSlot,
            stats = stats,
            replaceableById = replaceableById,
            usedKeys = usedKeys,
            groupMask = groupMask,
            qualMask = qualMask,
            orderWorst = orderWorst,
            boeAllowed = boeAllowed,
            mh2h = mh2h,
            canDW = canDW,
            canTG = canTG,
            blockOH2H = blockOH2H,
        }
    end

    local function ScanBagCandidatesPlan(basePlan, inCombat, manual)
        local now = GetTime()
        local plvl = (type(UnitLevel) == "function" and UnitLevel("player")) or 80
        local replaceableById = basePlan.replaceableById or {}
        local usedKeys = basePlan.usedKeys or {}
        local groupMask = basePlan.groupMask or 31
        local qualMask = basePlan.qualMask or 60
        local orderWorst = (basePlan.orderWorst == true)
        local boeAllowed = (basePlan.boeAllowed == true)
        local mh2h = (basePlan.mh2h == true)
        local canDW = (basePlan.canDW == true)
        local canTG = (basePlan.canTG == true)
        local blockOH2H = (basePlan.blockOH2H ~= nil) and basePlan.blockOH2H or (mh2h and not canTG)
        local cands = {}
        local seenWarm = { n = 0 }
        local needsWarm = false

        for bag = 0, 4 do
            local nSlots = (type(GetContainerNumSlots) == "function" and GetContainerNumSlots(bag)) or 0
            for slot = 1, nSlots do
                local link = (type(GetContainerItemLink) == "function") and GetContainerItemLink(bag, slot)
                if link then
                    local locked = false
                    if type(GetContainerItemInfo) == "function" then
                        local _, _, lck = GetContainerItemInfo(bag, slot)
                        locked = (lck == true or lck == 1)
                    end
                    if not locked then
                        local eid = AP.ExtractItemId and AP.ExtractItemId(link)
                        local sfx = AP.ExtractSuffix and AP.ExtractSuffix(link) or 0
                        local bagForge = (AP.forgeBag and AP.forgeBag[bag] and AP.forgeBag[bag][slot]) or 0
                        local key = eid and (eid .. ":" .. sfx) or nil
                        if eid and key and (ibEq.bagFailUntil[key] or 0) <= now then
                            local meta = GetIBCandidateMeta({
                                guid = -(bag * 100 + slot + 1),
                                entry = eid,
                                forge = bagForge,
                                suffix = sfx,
                                link = link,
                                bag = bag,
                                slot = slot,
                            }, now, plvl, qualMask, boeAllowed, usedKeys, seenWarm)
                            if meta == "warm" then
                                needsWarm = true
                            elseif type(meta) == "table" then
                                meta.bag = bag
                                meta.slot = slot
                                meta.fromBag = true
                                cands[#cands + 1] = meta
                            end
                        end
                    end
                end
            end
        end

        local firstCand, firstSlot = nil, nil
        local eligibleCands = {}
        for _, d in ipairs(IB_SLOT_DEFS) do
            local combatAllowSlot = (not inCombat) or (not ibEq.bagAllCombatBlocked and (d.grp >= 4 or not ibEq.bagNonWeaponCombatBlocked))
            if combatAllowSlot and ((math_floor(groupMask / d.grp) % 2) == 1)
               and not (d.inv == "SecondaryHandSlot" and blockOH2H)
               and replaceableById[d.id] then
                local best = nil
                for _, c in ipairs(cands) do
                    local locOk = d.loc[c.loc] or (d.inv == "SecondaryHandSlot" and canTG and c.loc == "INVTYPE_2HWEAPON" and IsTGTwoHandSubType(c.subType))
                    if locOk
                       and not (d.inv == "SecondaryHandSlot" and c.loc == "INVTYPE_WEAPON" and not canDW)
                       and PairedSlotSafe(d.inv, c.loc, replaceableById, canTG, true, c.subType) then
                        eligibleCands[c.key] = true
                        if IsBetterCandidate(c, best, orderWorst) then
                            best = c
                        end
                    end
                end
                if best and not firstCand then
                    firstCand, firstSlot = best, d
                end
            end
        end
        local cnt = 0
        for _ in pairs(eligibleCands) do cnt = cnt + 1 end
        return {
            eligibleCount = cnt,
            needsWarm = needsWarm,
            cand = firstCand,
            slotDef = firstSlot,
        }
    end

    local function EquipCandidateFromBag(cand, slotDef, boeAllowed)
        if not cand or not slotDef or not slotDef.id then return false end
        if type(PickupContainerItem) ~= "function" or type(EquipCursorItem) ~= "function" then
            return false
        end
        local now = GetTime()
        ibEq.lastSwapAt = now
        ibEq.lastTryAt = now
        ibEq.lastBagSwapAt = now
        ibEq.lastBagSwapGrp = slotDef.grp
        ibEq.lastBagSwapKey = cand.key
        ibEq.lastBagSwapSlotId = slotDef.id
        ibEq.prevBagForgeEquip = (AP.forgeEquip and AP.forgeEquip[slotDef.id]) or nil
        ibEq.prevBagIBWorn = (SS.ib and SS.ib.worn and SS.ib.worn[slotDef.id]) or nil
        ibEq.lastEquipped = cand.name
        ibEq.countSession = (ibEq.countSession or 0) + 1
        recentEquipTier[slotDef.id] = { eid = cand.entry, forge = cand.forge or 0, untilAt = now + 2.5 }
        AP.forgeEquip = AP.forgeEquip or {}
        AP.forgeEquip[slotDef.id] = cand.forge or 0
        if SS.ib and SS.ib.worn then SS.ib.worn[slotDef.id] = cand.forge or 0 end
        if type(ClearCursor) == "function" then ClearCursor() end
        PickupContainerItem(cand.bag, cand.slot)
        if type(CursorHasItem) ~= "function" or CursorHasItem() then
            EquipCursorItem(slotDef.id)
        end
        if boeAllowed and _G.StaticPopupDialogs then
            for i = 1, (_G.STATICPOPUP_NUMDIALOGS or 4) do
                local d = _G["StaticPopup" .. i]
                if d and d:IsShown() and (d.which == "AUTOEQUIP_BIND" or d.which == "EQUIP_BIND") then
                    local okb = _G["StaticPopup" .. i .. "Button1"]
                    if okb and okb.Click then okb:Click() end
                end
            end
        end
        if type(ClearCursor) == "function" then ClearCursor() end
        return true
    end

    function AP:CanItemBankAutoEquipNow(ignoreAutoSetting)
        if not ignoreAutoSetting and not (AP:GetSetting("ibAutoEquip") == true) then
            return false, "disabled"
        end
        local inCombat = (type(InCombatLockdown) == "function" and InCombatLockdown())
            or (type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player"))
        if inCombat and not (AP:GetSetting("ibEquipInCombat") == true) then
            return false, "combat"
        end
        if type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost("player") then
            return false, "dead"
        end
        if type(CursorHasItem) == "function" and CursorHasItem() then
            return false, "cursor"
        end
        local vp = SS.valdris
        local ipf = rawget(_G, "ItemProgressFrame")
        local ipfOpen = type(ipf) == "table" and type(ipf.IsShown) == "function" and ipf:IsShown()
        if not ignoreAutoSetting and vp and (vp.running or vp.pendingBankTake or vp.pendingBankReturn or vp.pendingUnequip or vp.pendingRelocate or ipfOpen or GetTime() < (vp.pauseEquipUntil or 0)) then
            return false, "valdris"
        end
        if not ignoreAutoSetting and GetTime() < (ibEq.graceUntil or 0) then
            return false, "grace"
        end
        return true, "ok"
    end

    local ibDrv = CreateFrame("Frame")
    ibDrv:Hide()
    ibDrv._acc = 0

    function AP:ScheduleItemBankAutoEquip(delay)
        if not (AP:GetSetting("ibAutoEquip") == true) then
            ibEq.pending = false
            ibDrv:Hide()
            return false
        end
        local targetAt = GetTime() + (delay or 0.25)
        if not ibEq.pending or targetAt < (ibEq.scheduledAt or 0) or (ibEq.scheduledAt or 0) <= GetTime() then
            ibEq.scheduledAt = targetAt
        end
        ibEq.pending = true
        ibDrv:Show()
        return true
    end

    function AP:GetItemBankEquipSummary(withCounts)
        local now = GetTime()
        local items, loaded = GetIBItems()
        local ok, reason = AP:CanItemBankAutoEquipNow(false)
        local graceRem = math_max(0, math_floor((ibEq.graceUntil or 0) - now + 0.5))
        local eligible, eligibleBag = 0, 0
        if withCounts then
            local p = EvaluateIBPlan()
            eligible = p.eligibleCount or 0
            local inC = (type(InCombatLockdown) == "function" and InCombatLockdown())
                or (type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player"))
            local bp = ScanBagCandidatesPlan(p, inC, false)
            eligibleBag = bp.eligibleCount or 0
        end
        return {
            on = (AP:GetSetting("ibAutoEquip") == true),
            available = ok,
            reason = reason,
            loaded = loaded,
            itemCount = #items,
            eligibleCount = eligible + eligibleBag,
            eligibleIB = eligible,
            eligibleBag = eligibleBag,
            inFlight = (ibEq.inFlightGuid ~= nil) and ((now - (ibEq.inFlightAt or 0)) < 3.0),
            inFlightGuid = ibEq.inFlightGuid,
            lastEquipped = ibEq.lastEquipped,
            lastError = ibEq.lastError,
            graceRemain = graceRem,
            countSession = ibEq.countSession or 0,
        }
    end

    function AP:RunItemBankAutoEquip(manual)
        local now = GetTime()
        local canGo, reason = AP:CanItemBankAutoEquipNow(manual == true)
        ibEq.lastReason = reason
        if not canGo then
            if reason == "combat" or reason == "dead" or reason == "cursor" or reason == "grace" or reason == "valdris" then
                if AP:GetSetting("ibAutoEquip") == true then
                    ibEq.pending = true
                    if reason == "grace" then
                        ibEq.scheduledAt = (ibEq.graceUntil or now) + 0.25
                    elseif reason == "valdris" then
                        local vUntil = (SS.valdris and SS.valdris.pauseEquipUntil) or 0
                        ibEq.scheduledAt = (vUntil > now) and (vUntil + 0.25) or (now + 1.5)
                    else
                        ibEq.scheduledAt = now + 1.0
                    end
                    ibDrv:Show()
                end
            end
            return false, reason
        end

        if ibEq.inFlightGuid then
            if (now - (ibEq.inFlightAt or 0)) < 3.0 then
                if not manual and AP:GetSetting("ibAutoEquip") == true then
                    AP:ScheduleItemBankAutoEquip(0.35)
                end
                return false, "in_flight"
            end
            ibEq.failUntil[ibEq.inFlightGuid] = now + 15
            ibEq.inFlightGuid = nil
        end

        if not manual and (now - (ibEq.lastTryAt or 0)) < 0.40 then
            AP:ScheduleItemBankAutoEquip(0.45 - (now - (ibEq.lastTryAt or 0)))
            return false, "rate_limit"
        end

        local inCombat = (type(InCombatLockdown) == "function" and InCombatLockdown())
            or (type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player"))

        local plan = EvaluateIBPlan()
        local tryIB = plan.cand and (not inCombat or not ibEq.ibCombatBlocked)
        if tryIB then
            local cand = plan.cand
            local sent = SendAddonWhisp("ACMSG_IB_EQUIP", tostring(cand.guid))
            if sent then
                ibEq.warmRetries = 0
                ibEq.inFlightGuid = cand.guid
                ibEq.inFlightAt = now
                ibEq.inFlightSlot = plan.slotDef and plan.slotDef.inv or nil
                ibEq.inFlightSlotId = plan.slotDef and plan.slotDef.id or nil
                ibEq.lastTryAt = now
                ibEq.lastSwapAt = now
                ibEq.lastError = nil
                ibEq.lastEquipped = cand.name
                ibEq.countSession = (ibEq.countSession or 0) + 1
                if plan.slotDef and plan.slotDef.id then
                    local sid = plan.slotDef.id
                    ibEq.prevForgeEquip = (AP.forgeEquip and AP.forgeEquip[sid]) or nil
                    ibEq.prevIBWorn = (SS.ib and SS.ib.worn and SS.ib.worn[sid]) or nil
                    recentEquipTier[sid] = { eid = cand.entry, forge = cand.forge or 0, untilAt = now + 2.5 }
                    AP.forgeEquip = AP.forgeEquip or {}
                    AP.forgeEquip[sid] = cand.forge or 0
                    if SS.ib and SS.ib.worn then SS.ib.worn[sid] = cand.forge or 0 end
                else
                    ibEq.prevForgeEquip = nil
                    ibEq.prevIBWorn = nil
                end
                if AP:GetSetting("ibAutoEquip") == true then
                    AP:ScheduleItemBankAutoEquip(0.65)
                end
                AP:Fire("SERVER_SYNC_UPDATED", "IB_AUTO_EQUIP")
                return true, "equipped", cand
            end
        end

        -- Try equipping straight from bags (especially crucial in combat when custom_attune AutoSwap pauses or IB is combat-blocked!)
        local bagPlan = ScanBagCandidatesPlan(plan, inCombat, manual == true)
        if bagPlan.cand then
            local did = EquipCandidateFromBag(bagPlan.cand, bagPlan.slotDef, plan.boeAllowed)
            if did then
                ibEq.warmRetries = 0
                ibEq.lastError = nil
                if AP:GetSetting("ibAutoEquip") == true then
                    AP:ScheduleItemBankAutoEquip(0.45)
                end
                AP:Fire("SERVER_SYNC_UPDATED", "IB_AUTO_EQUIP")
                return true, "equipped_bag", bagPlan.cand
            end
        end

        if (plan.needsWarm or bagPlan.needsWarm) and (ibEq.warmRetries or 0) < 3 and AP:GetSetting("ibAutoEquip") == true then
            ibEq.warmRetries = (ibEq.warmRetries or 0) + 1
            AP:ScheduleItemBankAutoEquip(1.0)
        elseif inCombat and AP:GetSetting("ibAutoEquip") == true and AP:GetSetting("ibEquipInCombat") == true
               and (not ibEq.ibCombatBlocked or not ibEq.bagAllCombatBlocked) then
            -- Keep periodic light scan alive during combat so any attunement completion flips immediately
            AP:ScheduleItemBankAutoEquip(1.5)
        end

        if inCombat and ibEq.ibCombatBlocked and not bagPlan.cand then
            return false, (manual and "в бою ИБ отклонен сервером, подходящих в сумках нет" or "combat")
        end
        if (not plan.loaded or plan.itemCount == 0) and bagPlan.eligibleCount == 0 then
            return false, "ib_empty"
        end
        if manual then
            local st = plan.stats or {}
            local parts = {}
            if (st.busySlot or 0) > 0 then parts[#parts + 1] = "слоты заняты непоглощенными вещами (" .. st.busySlot .. ")" end
            if (st.blockedSlot or 0) > 0 then parts[#parts + 1] = "отключено фильтром слотов (" .. st.blockedSlot .. ")" end
            if (st.boe or 0) > 0 then parts[#parts + 1] = "скрыто BoE (" .. st.boe .. ")" end
            if (st.qual or 0) > 0 then parts[#parts + 1] = "фильтр качества (" .. st.qual .. ")" end
            if #parts > 0 then
                return false, table.concat(parts, ", ")
            end
        end
        return false, "no_candidates"
    end

    SS._ibClearCaches = function()
        boeCache = {}
        canEquipCache = {}
    end
    SS._ibClearRecentTier = function(slotId, prevForge, prevWorn)
        if not slotId then return end
        recentEquipTier[slotId] = nil
        if AP.forgeEquip then AP.forgeEquip[slotId] = prevForge end
        if SS.ib and SS.ib.worn then SS.ib.worn[slotId] = prevWorn end
    end

    function AP:SetItemBankAutoEquip(on)
        local val = (on == true)
        AP:SetSetting("ibAutoEquip", val)
        if val then
            boeCache = {}
            canEquipCache = {}
            ibEq.warmRetries = 0
            ibEq.graceUntil = 0
            ibEq.combatWaitRegen = false
            ibEq.ibCombatBlocked = false
            ibEq.bagNonWeaponCombatBlocked = false
            ibEq.bagAllCombatBlocked = false
            ibEq.lastError = nil
            if not SS.wh.loaded and type(AP.RequestWhereItemsSync) == "function" then
                AP:RequestWhereItemsSync()
            end
            if type(AP.forgeEquip) ~= "table" or next(AP.forgeEquip) == nil then
                SendAddonWhisp("ACMSG_IB_WORN", "")
                if type(SendServerMessage) == "function" then
                    pcall(SendServerMessage, "ACMSG_FORGE_SYNC")
                end
            end
            AP:ScheduleItemBankAutoEquip(0.10)
        else
            ibEq.pending = false
            ibDrv:Hide()
        end
        AP:Fire("SERVER_SYNC_UPDATED", "IB_AUTO_TOGGLE")
        return val
    end

    function AP:DebugItemBankAuto()
        if not DEFAULT_CHAT_FRAME then return end
        local sum = AP:GetItemBankEquipSummary(true)
        local plan = EvaluateIBPlan()
        local inC = (type(InCombatLockdown) == "function" and InCombatLockdown())
            or (type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player"))
        local bp = ScanBagCandidatesPlan(plan, inC, true)
        local sp = (type(AP.GetItemBankSplitPlan) == "function") and AP:GetItemBankSplitPlan(true) or nil
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff38bdf8[IB-Debug]|r Auto=%s CombatOpt=%s InCombat=%s DW=%s TG=%s | IB=%d(подх:%d, blk:%s) Bag(подх:%d, nWBlk:%s, allBlk:%s) Split=%d Grace=%dс Err=%s",
            tostring(sum.on), tostring(AP:GetSetting("ibEquipInCombat")), tostring(inC == true),
            tostring(plan.canDW == true), tostring(plan.canTG == true),
            sum.itemCount or 0, sum.eligibleIB or 0, tostring(ibEq.ibCombatBlocked),
            bp.eligibleCount or 0, tostring(ibEq.bagNonWeaponCombatBlocked), tostring(ibEq.bagAllCombatBlocked),
            (sp and sp.totalCount) or 0, sum.graceRemain or 0, tostring(ibEq.lastError)
        ))
        local openSlots, busySlots = {}, {}
        for _, d in ipairs(IB_SLOT_DEFS) do
            if plan.replaceableById and plan.replaceableById[d.id] then
                openSlots[#openSlots + 1] = d.inv:gsub("Slot", "")
            else
                busySlots[#busySlots + 1] = d.inv:gsub("Slot", "")
            end
        end
        DEFAULT_CHAT_FRAME:AddMessage("  Открытые/погл. слоты: " .. (#openSlots > 0 and table.concat(openSlots, ", ") or "нет"))
        DEFAULT_CHAT_FRAME:AddMessage("  Занятые (качаются/защищ.): " .. (#busySlots > 0 and table.concat(busySlots, ", ") or "нет"))
    end

    ibDrv:SetScript("OnUpdate", function(self, elapsed)
        self._acc = (self._acc or 0) + (elapsed or 0)
        if self._acc < 0.12 then return end
        self._acc = 0
        if not ibEq.pending then
            self:Hide()
            return
        end
        if GetTime() < (ibEq.scheduledAt or 0) then
            return
        end
        ibEq.pending = false
        local ok = AP:RunItemBankAutoEquip(false)
        if not ok and not ibEq.pending then
            self:Hide()
        end
    end)

    function SS.onIBUpdate()
        if AP:GetSetting("ibAutoEquip") == true then
            AP:ScheduleItemBankAutoEquip(0.15)
        end
        if SS.valdris then
            if type(SS.valdrisRefreshPicker) == "function" then SS.valdrisRefreshPicker() end
            if type(SS.valdrisRefreshBar) == "function" then SS.valdrisRefreshBar() end
        end
    end

    function SS.onIBDel(guid)
        if guid and SS.wh and SS.wh.ibg then
            SS.wh.ibg[guid] = nil
        end
        if SS.valdris then
            if type(SS.valdrisRefreshPicker) == "function" then SS.valdrisRefreshPicker() end
            if type(SS.valdrisRefreshBar) == "function" then SS.valdrisRefreshBar() end
        end
        if guid and ibEq.inFlightGuid == guid then
            ibEq.inFlightGuid = nil
            ibEq.inFlightAt = 0
            ibEq.lastError = nil
            if AP:GetSetting("ibAutoEquip") == true then
                AP:ScheduleItemBankAutoEquip(0.35)
            end
        end
    end

    function SS.onIBRes(code, text)
        local now = GetTime()
        local isPutAck = (text == "put" or text == "putall")
        local pr = SS.valdris and SS.valdris.pendingBankReturn
        if pr and (now - (pr.at or 0)) < 3.5 then
            local putAtCheck = (SS.ibPut and SS.ibPut.inFlightKey and (SS.ibPut.inFlightAt or 0)) or 0
            local splitAtCheck = (SS.ibSplit and SS.ibSplit.inFlightKind and (SS.ibSplit.inFlightAt or 0)) or 0
            local eqAtCheck = (ibEq.inFlightGuid and (ibEq.inFlightAt or 0)) or 0
            local prAt = pr.at or 0
            local prIsNewest = (prAt >= putAtCheck and prAt >= splitAtCheck and prAt >= eqAtCheck)
            if (isPutAck and (not SS.ibPut or not SS.ibPut.inFlightKey or prAt >= putAtCheck))
               or (code and code ~= 0 and text ~= "split" and text ~= "take" and prIsNewest) then
                SS.valdris.pendingBankReturn = nil
                if code and code ~= 0 then
                    SS.valdris.lastError = (text and text ~= "") and text or ("Код " .. tostring(code))
                    if DEFAULT_CHAT_FRAME then
                        DEFAULT_CHAT_FRAME:AddMessage("|cffff8040[Прогрессия]|r Не удалось вернуть в Банк вещей: " .. tostring(text or code))
                    end
                end
                if type(SS.valdrisRefreshBar) == "function" then SS.valdrisRefreshBar() end
                if SS.valdris.running and type(AP.ScheduleValdrisStep) == "function" then
                    AP:ScheduleValdrisStep(0.01)
                end
                AP:Fire("SERVER_SYNC_UPDATED", "ASMSG_IB_RES")
                return
            end
        end
        if isPutAck and type(SS.onIBPutRes) == "function" then
            SS.onIBPutRes(code, text)
            return
        end
        if text == "split" and type(SS.onIBSplitRes) == "function" then
            SS.onIBSplitRes(code, text)
            return
        end
        if code == 0 and text == "take" then
            if type(SS.onIBManualTake) == "function" then
                SS.onIBManualTake()
            end
            AP:Fire("SERVER_SYNC_UPDATED", "ASMSG_IB_RES")
            return
        end
        if code and code ~= 0 then
            if SS.valdris and SS.valdris.pendingBankTake then
                local bt = SS.valdris.pendingBankTake
                if (now - (bt.at or 0)) < 3.5 then
                    SS.valdris.pendingBankTake = nil
                    if bt.guid and SS.valdris.skip then
                        SS.valdris.skip["ib:" .. bt.guid .. ":" .. (tonumber(bt.forge) or 0)] = code
                    end
                    SS.valdris.lastError = (text and text ~= "") and text or ("Код " .. tostring(code))
                    if DEFAULT_CHAT_FRAME then
                        DEFAULT_CHAT_FRAME:AddMessage("|cffff8040[Прогрессия]|r Не удалось забрать из Банка вещей: " .. tostring(text or code))
                    end
                    if type(SS.valdrisRefreshBar) == "function" then SS.valdrisRefreshBar() end
                    if SS.valdris.running and type(AP.ScheduleValdrisStep) == "function" then
                        AP:ScheduleValdrisStep(0.01)
                    end
                    AP:Fire("SERVER_SYNC_UPDATED", "ASMSG_IB_RES")
                    return
                end
            end
            local putAt = (SS.ibPut and SS.ibPut.inFlightKey and (SS.ibPut.inFlightAt or 0)) or 0
            local splitAt = (SS.ibSplit and SS.ibSplit.inFlightKind and (SS.ibSplit.inFlightAt or 0)) or 0
            local eqAt = (ibEq.inFlightGuid and (ibEq.inFlightAt or 0)) or 0
            if splitAt > putAt and splitAt > eqAt and type(SS.onIBSplitRes) == "function" then
                SS.onIBSplitRes(code, text)
                return
            end
            if putAt > eqAt and type(SS.onIBPutRes) == "function" then
                SS.onIBPutRes(code, text)
                return
            end
            if ibEq.inFlightSlotId and type(SS._ibClearRecentTier) == "function" then
                SS._ibClearRecentTier(ibEq.inFlightSlotId, ibEq.prevForgeEquip, ibEq.prevIBWorn)
            end
            ibEq.inFlightSlotId = nil
            local inCombat = (type(InCombatLockdown) == "function" and InCombatLockdown())
                or (type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player"))
            if inCombat and ibEq.inFlightGuid then
                ibEq.ibCombatBlocked = true
                ibEq.inFlightGuid = nil
                if DEFAULT_CHAT_FRAME and not ibEq.combatNotified then
                    ibEq.combatNotified = true
                    DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[AttuneParser]|r Банк вещей в бою отклонен (" .. tostring(text or code) .. ") - пробую надевать из сумок / до конца боя.")
                end
            elseif ibEq.inFlightGuid then
                ibEq.failUntil[ibEq.inFlightGuid] = now + 30
                ibEq.inFlightGuid = nil
            end
            ibEq.lastError = (text and text ~= "") and text or ("Код " .. tostring(code))
            if AP:GetSetting("ibAutoEquip") == true then
                AP:ScheduleItemBankAutoEquip(0.25)
            end
        else
            if ibEq.inFlightGuid and SS.wh and SS.wh.ibg then
                SS.wh.ibg[ibEq.inFlightGuid] = nil
            end
            ibEq.inFlightGuid = nil
            ibEq.inFlightSlotId = nil
            ibEq.combatWaitRegen = false
            ibEq.ibCombatBlocked = false
            ibEq.lastError = nil
            if AP:GetSetting("ibAutoEquip") == true then
                AP:ScheduleItemBankAutoEquip(0.35)
            end
        end
        AP:Fire("SERVER_SYNC_UPDATED", "ASMSG_IB_RES")
    end

    function SS.onWoWEvent(event, a1)
        if event == "PLAYER_REGEN_DISABLED" then
            ibEq.combatNotified = false
            if SS.ibSplit and SS.ibSplit.running and type(AP.StopItemBankSplit) == "function" then
                AP:StopItemBankSplit("combat")
            end
            if SS.valdris and SS.valdris.running and type(AP.StopValdrisAutoUpgrade) == "function" then
                AP:StopValdrisAutoUpgrade("combat")
            end
            if AP:GetSetting("ibAutoEquip") == true and AP:GetSetting("ibEquipInCombat") == true then
                AP:ScheduleItemBankAutoEquip(0.5)
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            ibEq.combatWaitRegen = false
            ibEq.ibCombatBlocked = false
            ibEq.bagNonWeaponCombatBlocked = false
            ibEq.bagAllCombatBlocked = false
            ibEq.combatNotified = false
            if SS.ibPut then SS.ibPut.combatBlocked = false end
            if AP:GetSetting("ibAutoEquip") == true then
                AP:ScheduleItemBankAutoEquip(0.30)
            end
            if AP:GetSetting("ibAutoPut") == true and type(AP.ScheduleItemBankAutoPut) == "function" then
                AP:ScheduleItemBankAutoPut(0.55)
            end
        elseif event == "PLAYER_LEVEL_UP" or event == "SKILL_LINES_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
            if type(SS._ibClearCaches) == "function" then
                SS._ibClearCaches()
            end
            if event ~= "SKILL_LINES_CHANGED" and type(AP.InvalidateCaches) == "function" then
                AP:InvalidateCaches(false)
            end
            ibEq.bagNonWeaponCombatBlocked = false
            ibEq.bagAllCombatBlocked = false
            if AP:GetSetting("ibAutoEquip") == true then
                AP:ScheduleItemBankAutoEquip(0.35)
            end
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            local now = GetTime()
            if (now - (ibEq.lastSwapAt or 0)) < 2.5 then
                ibEq.inFlightGuid = nil
                if AP:GetSetting("ibAutoEquip") == true then
                    AP:ScheduleItemBankAutoEquip(0.35)
                end
            else
                ibEq.graceUntil = now + 15.0
                if AP:GetSetting("ibAutoEquip") == true then
                    AP:ScheduleItemBankAutoEquip(15.2)
                end
            end
        elseif event == "UI_ERROR_MESSAGE" then
            local now = GetTime()
            if (now - (ibEq.lastBagSwapAt or 0)) < 0.4 then
                if ibEq.lastBagSwapSlotId and type(SS._ibClearRecentTier) == "function" then
                    SS._ibClearRecentTier(ibEq.lastBagSwapSlotId, ibEq.prevBagForgeEquip, ibEq.prevBagIBWorn)
                    ibEq.lastBagSwapSlotId = nil
                end
                local msg = tostring(a1 or "")
                local inC = (type(InCombatLockdown) == "function" and InCombatLockdown())
                    or (type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player"))
                if inC and (msg:find("бо", 1, true) or msg:find("combat", 1, true)) then
                    if (ibEq.lastBagSwapGrp or 0) < 4 then
                        ibEq.bagNonWeaponCombatBlocked = true
                    else
                        ibEq.bagAllCombatBlocked = true
                    end
                    if DEFAULT_CHAT_FRAME and not ibEq.combatNotified then
                        ibEq.combatNotified = true
                        DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[AttuneParser]|r Клиент/сервер не дал сменить этот слот из сумки в бою (" .. msg .. ").")
                    end
                elseif ibEq.lastBagSwapKey then
                    ibEq.bagFailUntil[ibEq.lastBagSwapKey] = now + 15
                end
                if type(ClearCursor) == "function" then ClearCursor() end
            end
        elseif event == "BAG_UPDATE" then
            if AP:GetSetting("ibAutoEquip") == true then
                AP:ScheduleItemBankAutoEquip(0.15)
            end
            if type(SS.onIBBagUpdate) == "function" then
                SS.onIBBagUpdate()
            end
            if type(SS.onValdrisBagUpdate) == "function" then
                SS.onValdrisBagUpdate()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            if type(SS.tryHookValdris) == "function" then SS.tryHookValdris() end
            if not SS.wh.loaded and type(AP.RequestWhereItemsSync) == "function" then
                AP:RequestWhereItemsSync()
            end
            if AP:GetSetting("ibAutoEquip") == true then
                if type(AP.forgeEquip) ~= "table" or next(AP.forgeEquip) == nil then
                    SendAddonWhisp("ACMSG_IB_WORN", "")
                end
                AP:ScheduleItemBankAutoEquip(1.0)
            end
            if AP:GetSetting("ibAutoPut") == true and type(AP.ScheduleItemBankAutoPut) == "function" then
                AP:ScheduleItemBankAutoPut(1.8)
            end
        end
    end

    AP:RegisterCallback("ATTUNE_UPDATED", function()
        if AP:GetSetting("ibAutoEquip") == true then
            AP:ScheduleItemBankAutoEquip(0.12)
        end
        if AP:GetSetting("ibAutoPut") == true and type(AP.ScheduleItemBankAutoPut) == "function" then
            AP:ScheduleItemBankAutoPut(0.85)
        end
    end)
    AP:RegisterCallback("AUTOSWAP_UPDATED", function()
        if AP:GetSetting("ibAutoEquip") == true then
            AP:ScheduleItemBankAutoEquip(0.25)
        end
    end)
    AP:RegisterCallback("FORGE_UPDATED", function()
        if AP:GetSetting("ibAutoEquip") == true then
            AP:ScheduleItemBankAutoEquip(0.25)
        end
        if AP:GetSetting("ibAutoPut") == true and type(AP.ScheduleItemBankAutoPut) == "function" then
            AP:ScheduleItemBankAutoPut(0.85)
        end
    end)
    AP:RegisterCallback("SETTINGS_UPDATED", function(_, key, val)
        if key == "ibAutoEquip" and val == true then
            AP:ScheduleItemBankAutoEquip(0.10)
        elseif key == "ibEquipInCombat" and val == true then
            ibEq.combatWaitRegen = false
            ibEq.ibCombatBlocked = false
            ibEq.bagNonWeaponCombatBlocked = false
            ibEq.bagAllCombatBlocked = false
            if AP:GetSetting("ibAutoEquip") == true then
                AP:ScheduleItemBankAutoEquip(0.10)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- 3c. Auto-Put to ItemBank (ACMSG_IB_PUT)
---------------------------------------------------------------------------
do
    local ibPut = SS.ibPut
    local PUT_MODE_ORDER = { "unabsorbed", "unabsorbed_other", "all_except_upgrade" }
    local PUT_MODE_SHORT = {
        unabsorbed = "Непогл.",
        unabsorbed_other = "Непогл.+Чужое",
        all_except_upgrade = "Всё (кр.ковки)",
    }
    local PUT_MODE_LONG = {
        unabsorbed = "Только непоглощенные вещи (поглощенные под вендор/ковку и чужие остаются в сумках)",
        unabsorbed_other = "Непоглощенные + чужое оружие/броня (уже поглощенные для ковки и вендора остаются)",
        all_except_upgrade = "Вся экипировка, кроме готовой к апгрейду ковки (< тира 3), серого/белого и комплектов",
    }

    local function IsFrameShown(name)
        local f = rawget(_G, name)
        return (type(f) == "table" and type(f.IsShown) == "function" and f:IsShown()) and true or false
    end

    local function IsBlockedPutWindowOpen()
        local pib = rawget(_G, "PRIME_ItemBank")
        if type(pib) == "table" and type(pib.F) == "table" and type(pib.F.IsShown) == "function" and pib.F:IsShown() then
            return true
        end
        if IsFrameShown("MerchantFrame") or IsFrameShown("BankFrame") or IsFrameShown("TradeFrame")
           or IsFrameShown("MailFrame") or IsFrameShown("SendMailFrame") or IsFrameShown("AuctionFrame")
           or IsFrameShown("PrimeAuctionFrame") or IsFrameShown("PrimeAuctionHouseFrame") or IsFrameShown("ItemProgressFrame")
           or IsFrameShown("CustomItemProgressFrame") or IsFrameShown("GuildBankFrame") then
            return true
        end
        return false
    end

    local function GetEquipmentSetBagSlots()
        local out = {}
        if type(GetNumEquipmentSets) ~= "function" or type(GetEquipmentSetInfo) ~= "function"
           or type(GetEquipmentSetLocations) ~= "function" then
            return out
        end
        local okN, num = pcall(GetNumEquipmentSets)
        if not okN or not num or num <= 0 then return out end
        for i = 1, num do
            local okI, name = pcall(GetEquipmentSetInfo, i)
            if okI and name then
                local okL, locs = pcall(GetEquipmentSetLocations, name)
                if okL and type(locs) == "table" then
                    for _, loc in pairs(locs) do
                        if type(loc) == "number" and loc > 0 and type(EquipmentManager_UnpackLocation) == "function" then
                            local okU, _, bank, bags, slot, bag = pcall(EquipmentManager_UnpackLocation, loc)
                            if okU and not bank and bags and bag and slot and bag >= 0 and bag <= 4 then
                                out[bag * 100 + slot] = true
                            end
                        end
                    end
                end
            end
        end
        return out
    end

    local function ClassifyBagItem(eid, bagForge, sfx, link)
        if eid >= 1702000 and eid <= 1702999 then
            return "cant", false
        end
        local fnSrv = rawget(_G, "CustomAttuneItemStatus")
        if type(fnSrv) == "function" then
            local ok, done, cant, _, attun = pcall(fnSrv, eid, bagForge, sfx)
            if ok and attun ~= nil then
                if done then
                    local isUpgrade = (bagForge < 3)
                    if isUpgrade then
                        local ok3, done3 = pcall(fnSrv, eid, 3, sfx)
                        if ok3 and done3 == true then
                            isUpgrade = false
                        elseif type(AP.GetItemServerStatus) == "function" then
                            local st = AP:GetItemServerStatus(eid, link)
                            if st and st.isCompleted == true then
                                isUpgrade = false
                            end
                        end
                    end
                    return "done", isUpgrade
                end
                if attun == false or cant then
                    return "cant", false
                end
                return "need", false
            end
        end
        if type(AP.CanHeroAbsorb) == "function" then
            local usable = AP:CanHeroAbsorb(eid, link)
            if not usable then
                return "cant", false
            end
        end
        if type(AP.GetItemServerStatus) == "function" then
            local st = AP:GetItemServerStatus(eid, link)
            if st and (st.isCompleted or (st.doneTier or -1) >= bagForge) then
                return "done", ((st.doneTier or bagForge) < 3 and not st.isCompleted)
            end
        end
        return "need", false
    end

    local function EvaluateIBPutPlan()
        local now = GetTime()
        local ibItems, ibLoaded = (SS._ibGetItems and SS._ibGetItems()) or {}, false
        local pib = rawget(_G, "PRIME_ItemBank")
        local cap = (type(pib) == "table" and tonumber(pib.cap)) or SS.ib.cap or 0
        if cap > 0 and #ibItems >= cap then
            return { isFull = true, itemCount = #ibItems, cap = cap, eligibleCount = 0, keptUpgrade = 0, stats = {} }
        end

        local mode = AP:GetSetting("ibAutoPutMode") or "unabsorbed"
        local keepSets = (AP:GetSetting("ibPutKeepSets") ~= false)
        local eqSetSlots = keepSets and GetEquipmentSetBagSlots() or {}
        local as = (type(AP.GetAutoSwapSummary) == "function" and AP:GetAutoSwapSummary()) or {}
        local qualMask = tonumber(as.qualMask) or 60
        local boeAllowed = (as.boeAllowed == true)
        local slotLocs = SS._ibSlotLocs or {}

        local candidates = {}
        local seenWarm = 0
        local needsWarm = false
        local keptUpgrade, keptSets, keptDoneOrCant = 0, 0, 0
        for bag = 0, 4 do
            local nSlots = (type(GetContainerNumSlots) == "function" and GetContainerNumSlots(bag)) or 0
            for slot = 1, nSlots do
                local link = (type(GetContainerItemLink) == "function") and GetContainerItemLink(bag, slot)
                if link then
                    local locked = false
                    if type(GetContainerItemInfo) == "function" then
                        local _, _, lck = GetContainerItemInfo(bag, slot)
                        locked = (lck == true or lck == 1)
                    end
                    if not locked then
                        if keepSets and eqSetSlots[bag * 100 + slot] then
                            keptSets = keptSets + 1
                        else
                            local eid = AP.ExtractItemId and AP.ExtractItemId(link)
                            if eid then
                                local name, fullLink, q, ilvl, _, _, _, _, equipLoc
                                if type(GetItemInfo) == "function" then
                                    name, fullLink, q, ilvl, _, _, _, _, equipLoc = GetItemInfo(link)
                                    if not equipLoc or equipLoc == "" then
                                        name, fullLink, q, ilvl, _, _, _, _, equipLoc = GetItemInfo(eid)
                                    end
                                end
                                if not equipLoc or equipLoc == "" then
                                    if seenWarm < 3 and SS._ibWarmCache then
                                        seenWarm = seenWarm + 1
                                        SS._ibWarmCache("item:" .. eid)
                                    end
                                    needsWarm = true
                                elseif slotLocs[equipLoc] then
                                    local sfx = AP.ExtractSuffix and AP.ExtractSuffix(link) or 0
                                    local key = eid .. ":" .. sfx
                                    if (ibPut.failUntil[key] or 0) <= now then
                                        q = tonumber(q) or 0
                                        local bagForge = (AP.forgeBag and AP.forgeBag[bag] and AP.forgeBag[bag][slot]) or 0
                                        local kind, isUpgrade = ClassifyBagItem(eid, bagForge, sfx, fullLink or link)
                                        if kind == "done" and isUpgrade then
                                            keptUpgrade = keptUpgrade + 1
                                        end

                                        local putOk = false
                                        if q >= 2 then
                                            local boeBlock = (not boeAllowed) and SS._ibIsBoE and SS._ibIsBoE(fullLink or link, bag, slot, eid)
                                            if mode == "unabsorbed" then
                                                putOk = (kind == "need") and HasBit(qualMask, q) and (not boeBlock)
                                            elseif mode == "unabsorbed_other" then
                                                if kind == "need" then
                                                    putOk = HasBit(qualMask, q) and (not boeBlock)
                                                elseif kind == "cant" then
                                                    putOk = (not boeBlock)
                                                end
                                            elseif mode == "all_except_upgrade" then
                                                putOk = not (kind == "done" and isUpgrade)
                                            end
                                        end

                                        if putOk then
                                            candidates[#candidates + 1] = {
                                                bag = bag,
                                                slot = slot,
                                                srvBag = (bag == 0) and 255 or (18 + bag),
                                                srvSlot = (bag == 0) and (22 + slot) or (slot - 1),
                                                eid = eid,
                                                forge = bagForge,
                                                key = key,
                                                name = name or ("#" .. eid),
                                                link = fullLink or link,
                                            }
                                        else
                                            keptDoneOrCant = keptDoneOrCant + 1
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        return {
            loaded = ibLoaded,
            isFull = false,
            itemCount = #ibItems,
            cap = cap,
            eligibleCount = #candidates,
            keptUpgrade = keptUpgrade,
            keptSets = keptSets,
            keptOther = keptDoneOrCant,
            needsWarm = needsWarm,
            cand = candidates[1],
        }
    end

    function AP:CanItemBankAutoPutNow(ignoreAutoSetting)
        local now = GetTime()
        if not ignoreAutoSetting then
            if not (AP:GetSetting("ibAutoPut") == true) then
                return false, "disabled"
            end
            if now < (ibPut.manualPauseUntil or 0) then
                return false, "manual_pause"
            end
            if now < (ibPut.fullUntil or 0) then
                return false, "ib_full"
            end
            local inC = (type(InCombatLockdown) == "function" and InCombatLockdown())
                or (type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player"))
            if inC and ibPut.combatBlocked then
                return false, "combat"
            end
            if IsBlockedPutWindowOpen() then
                return false, "window_open"
            end
        end
        if type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost("player") then
            return false, "dead"
        end
        if type(CursorHasItem) == "function" and CursorHasItem() then
            return false, "cursor"
        end
        return true, "ok"
    end

    local putDrv = CreateFrame("Frame")
    putDrv:Hide()
    putDrv._acc = 0

    function AP:ScheduleItemBankAutoPut(delay)
        if not (AP:GetSetting("ibAutoPut") == true) then
            ibPut.pending = false
            putDrv:Hide()
            return false
        end
        local targetAt = GetTime() + (delay or 0.5)
        if not ibPut.pending or targetAt < (ibPut.scheduledAt or 0) or (ibPut.scheduledAt or 0) <= GetTime() then
            ibPut.scheduledAt = targetAt
        end
        ibPut.pending = true
        putDrv:Show()
        return true
    end

    function AP:GetItemBankPutSummary(withCounts)
        local now = GetTime()
        local mode = AP:GetSetting("ibAutoPutMode") or "unabsorbed"
        local eligible, keptUpgrade = 0, 0
        if withCounts then
            local p = EvaluateIBPutPlan()
            eligible = p.eligibleCount or 0
            keptUpgrade = p.keptUpgrade or 0
        end
        local ok, reason = AP:CanItemBankAutoPutNow(false)
        return {
            on = (AP:GetSetting("ibAutoPut") == true),
            available = ok,
            reason = reason,
            mode = mode,
            modeLabel = PUT_MODE_SHORT[mode] or mode,
            modeDesc = PUT_MODE_LONG[mode] or "",
            eligibleCount = eligible,
            keptUpgrade = keptUpgrade,
            pauseRemain = math_max(0, math_floor((ibPut.manualPauseUntil or 0) - now + 0.5)),
            countSession = ibPut.countSession or 0,
            lastPutName = ibPut.lastPutName,
            lastError = ibPut.lastError,
        }
    end

    function AP:RunItemBankAutoPut(manual)
        local now = GetTime()
        local canGo, reason = AP:CanItemBankAutoPutNow(manual == true)
        if not canGo then
            if AP:GetSetting("ibAutoPut") == true and (reason == "manual_pause" or reason == "window_open" or reason == "cursor" or reason == "dead") then
                local d = (reason == "manual_pause") and math_max(0.5, (ibPut.manualPauseUntil or now) - now + 0.25) or 1.5
                AP:ScheduleItemBankAutoPut(d)
            end
            return false, reason
        end

        if ibPut.inFlightKey then
            if (now - (ibPut.inFlightAt or 0)) < 2.5 then
                if not manual and AP:GetSetting("ibAutoPut") == true then
                    AP:ScheduleItemBankAutoPut(0.45)
                end
                return false, "in_flight"
            end
            ibPut.failUntil[ibPut.inFlightKey] = now + 15
            ibPut.inFlightKey = nil
        end

        if not manual and (now - (ibPut.lastTryAt or 0)) < 0.35 then
            AP:ScheduleItemBankAutoPut(0.40)
            return false, "rate_limit"
        end

        local plan = EvaluateIBPutPlan()
        if plan.isFull then
            ibPut.fullUntil = now + 15
            return false, "Банк предметов заполнен (" .. tostring(plan.itemCount) .. "/" .. tostring(plan.cap) .. ")"
        end
        if not plan.cand then
            if plan.needsWarm and (ibPut.warmRetries or 0) < 3 and AP:GetSetting("ibAutoPut") == true then
                ibPut.warmRetries = (ibPut.warmRetries or 0) + 1
                AP:ScheduleItemBankAutoPut(1.2)
            end
            if manual then
                return false, string.format("нет вещей для переноса (оставлено под ковку/вендора: %d, комплекты: %d)", plan.keptUpgrade or 0, plan.keptSets or 0)
            end
            return false, "no_candidates"
        end

        local cand = plan.cand
        local body = cand.srvBag .. ":" .. cand.srvSlot
        local sent = SendAddonWhisp("ACMSG_IB_PUT", body)
        if not sent then
            return false, "send_failed"
        end

        ibPut.warmRetries = 0
        ibPut.inFlightBag = cand.bag
        ibPut.inFlightSlot = cand.slot
        ibPut.inFlightKey = cand.key
        ibPut.inFlightAt = now
        ibPut.lastTryAt = now
        ibPut.lastError = nil
        ibPut.lastPutName = cand.name
        ibPut.countSession = (ibPut.countSession or 0) + 1

        if AP:GetSetting("ibAutoPut") == true then
            AP:ScheduleItemBankAutoPut(0.45)
        end
        AP:Fire("SERVER_SYNC_UPDATED", "IB_AUTO_PUT")
        return true, "put", cand
    end

    function AP:SetItemBankAutoPut(on)
        local val = (on == true)
        AP:SetSetting("ibAutoPut", val)
        if val then
            ibPut.warmRetries = 0
            ibPut.manualPauseUntil = 0
            ibPut.fullUntil = 0
            ibPut.lastError = nil
            AP:ScheduleItemBankAutoPut(0.25)
        else
            ibPut.pending = false
            putDrv:Hide()
        end
        AP:Fire("SERVER_SYNC_UPDATED", "IB_PUT_TOGGLE")
        return val
    end

    function AP:CycleItemBankPutMode()
        local cur = AP:GetSetting("ibAutoPutMode") or "unabsorbed"
        local nxt = PUT_MODE_ORDER[1]
        for i, m in ipairs(PUT_MODE_ORDER) do
            if m == cur then
                nxt = PUT_MODE_ORDER[(i % #PUT_MODE_ORDER) + 1]
                break
            end
        end
        AP:SetSetting("ibAutoPutMode", nxt)
        if AP:GetSetting("ibAutoPut") == true then
            AP:ScheduleItemBankAutoPut(0.25)
        end
        AP:Fire("SERVER_SYNC_UPDATED", "IB_PUT_MODE")
        return nxt, PUT_MODE_SHORT[nxt], PUT_MODE_LONG[nxt]
    end

    putDrv:SetScript("OnUpdate", function(self, elapsed)
        self._acc = (self._acc or 0) + (elapsed or 0)
        if self._acc < 0.25 then return end
        self._acc = 0
        if not ibPut.pending then
            self:Hide()
            return
        end
        if GetTime() < (ibPut.scheduledAt or 0) then
            return
        end
        ibPut.pending = false
        local ok = AP:RunItemBankAutoPut(false)
        if not ok and not ibPut.pending then
            self:Hide()
        end
    end)

    function SS.onIBManualTake()
        ibPut.manualPauseUntil = GetTime() + 45.0
    end

    function SS.onIBPutRes(code, text)
        local now = GetTime()
        if code and code ~= 0 then
            if ibPut.inFlightKey then
                ibPut.failUntil[ibPut.inFlightKey] = now + 30
                ibPut.inFlightKey = nil
            end
            ibPut.lastError = (text and text ~= "") and text or ("Код " .. tostring(code))
            if type(text) == "string" and (text:find("полн", 1, true) or text:find("мест", 1, true) or text:find("full", 1, true)) then
                ibPut.fullUntil = now + 15
            elseif ((type(InCombatLockdown) == "function" and InCombatLockdown()) or (type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player")))
                   and type(text) == "string" and (text:find("бо", 1, true) or text:lower():find("combat", 1, true)) then
                ibPut.combatBlocked = true
            elseif AP:GetSetting("ibAutoPut") == true then
                AP:ScheduleItemBankAutoPut(0.8)
            end
        else
            ibPut.inFlightKey = nil
            ibPut.inFlightBag = nil
            ibPut.inFlightSlot = nil
            ibPut.lastError = nil
            if AP:GetSetting("ibAutoPut") == true then
                AP:ScheduleItemBankAutoPut(0.35)
            end
        end
        AP:Fire("SERVER_SYNC_UPDATED", "ASMSG_IB_RES")
    end

    function SS.onIBBagUpdate()
        if ibPut.inFlightKey then
            ibPut.inFlightKey = nil
        end
        if AP:GetSetting("ibAutoPut") == true then
            AP:ScheduleItemBankAutoPut(1.6)
        end
    end

    AP:RegisterCallback("SETTINGS_UPDATED", function(_, key, val)
        if key == "ibAutoPut" and val == true then
            AP:ScheduleItemBankAutoPut(0.25)
        end
    end)
end

---------------------------------------------------------------------------
-- 4. UI Tab: "Server & Bosses" (AutoAbsorb/AutoSell + Vault + WB + RB/Dsp)
---------------------------------------------------------------------------
function AP.BuildServerSyncTab(parent)
    local PS = AP.Skin
    local box = CreateFrame("Frame", nil, parent)
    box:SetAllPoints(parent)

    local leftCard = CreateFrame("Frame", nil, box)
    leftCard:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    leftCard:SetSize(326, 392)
    PS.StyleBox(leftCard, 0.50, false)

    local rightCard = CreateFrame("Frame", nil, box)
    rightCard:SetPoint("TOPLEFT", leftCard, "TOPRIGHT", 8, 0)
    rightCard:SetSize(326, 392)
    PS.StyleBox(rightCard, 0.50, false)

    local function MakeCheck(p, x, y, w, label, getFn, onClickFn, tip)
        local row = CreateFrame("Button", nil, p)
        row:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
        row:SetSize(w, 20)
        local chk = CreateFrame("Frame", nil, row)
        chk:SetPoint("LEFT", row, "LEFT", 0, 0)
        chk:SetSize(16, 16)
        PS.StyleBox(chk, 0.70, false)
        local mk = chk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mk:SetPoint("CENTER", 0, 0)
        local txt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", chk, "RIGHT", 5, 0)
        txt:SetText(label)
        row:SetScript("OnClick", function()
            onClickFn()
            box.RefreshData()
        end)
        if tip then
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(label)
                GameTooltip:AddLine(tip, 0.9, 0.9, 0.9, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return function(enabled)
            local on = getFn()
            if on then
                mk:SetText("|cff40ff40V|r")
                PS.StyleBox(chk, 0.75, true)
            else
                mk:SetText("")
                PS.StyleBox(chk, 0.55, false)
            end
            txt:SetTextColor(enabled == false and 0.5 or 0.92, enabled == false and 0.5 or 0.92, enabled == false and 0.5 or 0.92)
        end
    end

    -- Left Column: AutoAbsorb + AutoSell settings
    local lHdr1 = leftCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lHdr1:SetPoint("TOPLEFT", 10, -8)
    lHdr1:SetText("|cffffd200Автоматическое поглощение|r")

    local updaters = {}
    local function AddUpd(fn, isSell)
        updaters[#updaters + 1] = { fn = fn, isSell = isSell }
    end

    AddUpd(MakeCheck(leftCard, 10, -28, 152, "Автоэкипировка", function()
        return AP:GetAutoSwapSummary().on == true
    end, function()
        AP:SetAutoAbsorb(not (AP:GetAutoSwapSummary().on == true))
    end, "Включает или выключает автоматический подбор и надевание вещей для поглощения."))

    AddUpd(MakeCheck(leftCard, 166, -28, 150, "Разрешить BoE", function()
        return AP:GetAutoSwapSummary().boeAllowed == true
    end, function()
        AP:SetAutoAbsorbBoE(not (AP:GetAutoSwapSummary().boeAllowed == true))
    end, "Разрешает надевать не персональные (BoE) вещи из сумок."))

    AddUpd(MakeCheck(leftCard, 10, -48, 300, "Порядок: сначала худшие по качеству/ilvl", function()
        return AP:GetAutoSwapSummary().orderWorst == true
    end, function()
        AP:SetAutoAbsorbOrder(not (AP:GetAutoSwapSummary().orderWorst == true))
    end, "Меняет приоритет выбора: от слабых вещей к сильным или наоборот."))

    local grpLbl = leftCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    grpLbl:SetPoint("TOPLEFT", 10, -72)
    grpLbl:SetText("|cffb0a080Какие слоты проверять:|r")

    local grps = { {1, 0, "Броня"}, {2, 1, "Украшения"}, {4, 2, "Оружие"}, {8, 3, "Левая рука"}, {16, 4, "Дальний бой"} }
    for i, g in ipairs(grps) do
        local col = ((i - 1) % 3)
        local row = math_floor((i - 1) / 3)
        AddUpd(MakeCheck(leftCard, 10 + col * 102, -88 - row * 20, 100, g[3], function()
            return HasBit(AP:GetAutoSwapSummary().groupMask or 3, g[2])
        end, function()
            AP:SetAutoAbsorbGroupBit(g[1])
        end))
    end

    local qualLbl = leftCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qualLbl:SetPoint("TOPLEFT", 10, -132)
    qualLbl:SetText("|cffb0a080Качество автопоглощения:|r")

    local aaQuals = { {4, "|cff1eff00Зеленые|r"}, {8, "|cff0070ddСиние|r"}, {16, "|cffa335eeЭпик|r"}, {32, "|cffff8000Легенд.|r"} }
    for i, qd in ipairs(aaQuals) do
        AddUpd(MakeCheck(leftCard, 10 + (i - 1) * 76, -148, 74, qd[2], function()
            local m = AP:GetAutoSwapSummary().qualMask or 60
            return (math_floor(m / qd[1]) % 2) == 1
        end, function()
            AP:SetAutoAbsorbQualBit(qd[1])
        end))
    end

    local lHdr2 = leftCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lHdr2:SetPoint("TOPLEFT", 10, -170)
    lHdr2:SetText("|cffffd200Автопродажа освоенных дублей|r")

    AddUpd(MakeCheck(leftCard, 10, -190, 148, "Автопродажа", function()
        return AP:GetAutoSwapSummary().active == true
    end, function()
        AP:SetAutoSellActive(not (AP:GetAutoSwapSummary().active == true))
    end), true)

    AddUpd(MakeCheck(leftCard, 166, -190, 150, "Запрос при входе", function()
        return AP:GetAutoSwapSummary().confirm == true
    end, function()
        AP:SetAutoSellConfirm(not (AP:GetAutoSwapSummary().confirm == true))
    end), true)

    local asQualLbl = leftCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    asQualLbl:SetPoint("TOPLEFT", 10, -214)
    asQualLbl:SetText("|cffb0a080Качество для автопродажи:|r")

    local asQuals = {
        {1, "|cff9d9d9dСерый|r"}, {2, "|cffffffffБелый|r"}, {4, "|cff1eff00Зеленый|r"},
        {8, "|cff0070ddСиний|r"}, {16, "|cffa335eeЭпик|r"}, {32, "|cffff8000Легенд.|r"},
    }
    for i, qd in ipairs(asQuals) do
        local col = ((i - 1) % 3)
        local row = math_floor((i - 1) / 3)
        AddUpd(MakeCheck(leftCard, 10 + col * 102, -230 - row * 20, 100, qd[2], function()
            local m = AP:GetAutoSwapSummary().sellMask or 0
            return (math_floor(m / qd[1]) % 2) == 1
        end, function()
            AP:SetAutoSellQualBit(qd[1])
        end), true)
    end

    local asSrcLbl = leftCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    asSrcLbl:SetPoint("TOPLEFT", 10, -274)
    asSrcLbl:SetText("|cffb0a080Откуда продавать:|r")

    AddUpd(MakeCheck(leftCard, 10, -290, 148, "Только надетые", function()
        return (math_floor((AP:GetAutoSwapSummary().srcMask or 0) / 1) % 2) == 1
    end, function()
        AP:SetAutoSellSrcBit(1)
    end), true)

    AddUpd(MakeCheck(leftCard, 166, -290, 150, "Из сумок", function()
        return (math_floor((AP:GetAutoSwapSummary().srcMask or 0) / 2) % 2) == 1
    end, function()
        AP:SetAutoSellSrcBit(2)
    end), true)

    AddUpd(MakeCheck(leftCard, 10, -314, 122, "Автонадевание", function()
        return AP:GetSetting("ibAutoEquip") == true
    end, function()
        AP:SetItemBankAutoEquip(not (AP:GetSetting("ibAutoEquip") == true))
    end, "Надевает непоглощенные вещи из Банка вещей и сумок (если слоты свободны или уже освоены), с паузой 15 сек после ручной замены."))

    AddUpd(MakeCheck(leftCard, 134, -314, 68, "В бою", function()
        return AP:GetSetting("ibEquipInCombat") == true
    end, function()
        AP:SetSetting("ibEquipInCombat", not (AP:GetSetting("ibEquipInCombat") == true))
    end, "Меняет вещи из Банка вещей и сумок прямо во время боя по мере поглощения."))

    AddUpd(MakeCheck(leftCard, 204, -314, 114, "Фильтр слотов", function()
        return AP:GetSetting("ibUseAAMask") == true
    end, function()
        local nw = not (AP:GetSetting("ibUseAAMask") == true)
        AP:SetSetting("ibUseAAMask", nw)
        if AP:GetSetting("ibAutoEquip") == true then
            AP:ScheduleItemBankAutoEquip(0.25)
        end
    end, "ВЫКЛ (по умолчанию): автонадевание проверяет все слоты экипировки. ВКЛ: только отмеченные выше слоты."))

    AddUpd(MakeCheck(leftCard, 10, -334, 132, "Автосклад", function()
        return AP:GetSetting("ibAutoPut") == true
    end, function()
        AP:SetItemBankAutoPut(not (AP:GetSetting("ibAutoPut") == true))
    end, "Автоматически переносит лишние вещи из сумок в Банк вещей, оставляя предметы под ковку, продажу и комплекты."))

    local ibPutModeBtn = PS.MakeBtn(leftCard, 170, 19, "Режим: Неосвоенные", "dark")
    ibPutModeBtn:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 146, -334)
    ibPutModeBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ibPutModeBtn:SetScript("OnClick", function(_, mBtn)
        if mBtn == "RightButton" then
            local ok, reason, cand = AP:RunItemBankAutoPut(true)
            if DEFAULT_CHAT_FRAME then
                if ok and cand then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Положено в Банк вещей: " .. tostring(cand.link or cand.name or cand.eid))
                else
                    DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Автосклад: " .. tostring(reason or "нет подходящих вещей"))
                end
            end
        else
            AP:CycleItemBankPutMode()
        end
        AP.After(0.15, function() box.RefreshData() end, "ap_ib_put_ref")
    end)
    ibPutModeBtn:SetScript("OnEnter", function(self)
        local ps = AP:GetItemBankPutSummary(true)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Режим автосклада в Банк вещей")
        GameTooltip:AddLine("ЛКМ: сменить режим (" .. tostring(ps.modeLabel or "?") .. ").", 1, 0.85, 0.2, true)
        GameTooltip:AddLine(tostring(ps.modeDesc or ""), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(string.format("Готово к переносу: %d | Оставлено под ковку/торговца: %d", ps.eligibleCount or 0, ps.keptUpgrade or 0), 0.7, 0.85, 1.0, true)
        GameTooltip:AddLine("ПКМ: положить 1 подходящую вещь прямо сейчас.", 0.4, 1.0, 0.4, true)
        GameTooltip:Show()
    end)
    ibPutModeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local sweepNowBtn = PS.MakeBtn(leftCard, 150, 24, "Продать сейчас", "green")
    sweepNowBtn:SetPoint("BOTTOMLEFT", leftCard, "BOTTOMLEFT", 10, 10)
    sweepNowBtn:SetScript("OnClick", function()
        if StaticPopupDialogs and StaticPopup_Show then
            StaticPopupDialogs["ATTUNEPARSER_SWEEP_SRV"] = {
                text = "Продать СЕЙЧАС освоенные дубликаты по выбранным фильтрам?",
                button1 = YES or "Да",
                button2 = NO or "Нет",
                timeout = 0, whileDead = 1, hideOnEscape = 1,
                OnAccept = function() AP:SweepAbsorbedNow(true) end,
            }
            StaticPopup_Show("ATTUNEPARSER_SWEEP_SRV")
        else
            AP:SweepAbsorbedNow(true)
        end
    end)

    local unlockBtn = PS.MakeBtn(leftCard, 148, 24, "Разблокировать", "dark")
    unlockBtn:SetPoint("BOTTOMRIGHT", leftCard, "BOTTOMRIGHT", -10, 10)
    unlockBtn:SetScript("OnClick", function()
        if AP:GetAutoSwapSummary().unlocked then
            AP:RequestServerSync(true)
        else
            AP:PromptUnlockAutoSell()
        end
    end)

    -- Right Column: Storage, Disperse, Vault & World Boss Cooldowns
    local rHdr1 = rightCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rHdr1:SetPoint("TOPLEFT", 10, -8)
    rHdr1:SetText("|cffffd200Хранилища, Расщепление и Ключи M+|r")

    local statusTxt = rightCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusTxt:SetPoint("TOPLEFT", 10, -28)
    statusTxt:SetSize(306, 102)
    statusTxt:SetJustifyH("LEFT")
    statusTxt:SetJustifyV("TOP")

    local openIbBtn = PS.MakeBtn(rightCard, 76, 22, "Банк вещей", "dark")
    openIbBtn:SetPoint("TOPLEFT", 10, -134)
    openIbBtn:SetScript("OnClick", function() AP:OpenItemBank() end)

    local ibEquipNowBtn = PS.MakeBtn(rightCard, 90, 22, "Надеть / Склад", "dark")
    ibEquipNowBtn:SetPoint("LEFT", openIbBtn, "RIGHT", 3, 0)
    ibEquipNowBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ibEquipNowBtn:SetScript("OnClick", function(_, mBtn)
        if mBtn == "RightButton" then
            local ok, reason, cand = AP:RunItemBankAutoPut(true)
            if DEFAULT_CHAT_FRAME then
                if ok and cand then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Положено в Банк вещей: " .. tostring(cand.link or cand.name or cand.eid))
                else
                    DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Автосклад: " .. tostring(reason or "нет подходящих вещей"))
                end
            end
        else
            local ok, reason, cand = AP:RunItemBankAutoEquip(true)
            if DEFAULT_CHAT_FRAME then
                if ok and cand then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Надето из Банка вещей: " .. tostring(cand.link or cand.name or cand.entry))
                else
                    DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Автонадевание: " .. tostring(reason or "нет подходящих вещей"))
                end
            end
        end
        AP.After(0.25, function() box.RefreshData() end, "ap_ib_now_ref")
    end)
    ibEquipNowBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Банк вещей: Надеть или Сложить")
        GameTooltip:AddLine("ЛКМ: надеть 1 подходящую вещь в свободный или уже освоенный слот.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("ПКМ: положить 1 подходящую вещь из сумки в Банк вещей.", 0.4, 1.0, 0.4, true)
        GameTooltip:Show()
    end)
    ibEquipNowBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local depRbBtn = PS.MakeBtn(rightCard, 68, 22, "Ресурсы", "green")
    depRbBtn:SetPoint("LEFT", ibEquipNowBtn, "RIGHT", 3, 0)
    depRbBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    depRbBtn:SetScript("OnClick", function(_, mBtn)
        if mBtn == "RightButton" then AP:OpenResourceBank() else AP:DepositAllResources(0) end
    end)
    depRbBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Банк ресурсов")
        GameTooltip:AddLine("ЛКМ: сдать все подходящие ресурсы из сумок в Банк ресурсов (ПКМ: открыть окно).", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    depRbBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local vaultBtn = PS.MakeBtn(rightCard, 62, 22, "Ключи M+", "dark")
    vaultBtn:SetPoint("LEFT", depRbBtn, "RIGHT", 3, 0)
    vaultBtn:SetScript("OnClick", function() AP:RequestMPlusVault() end)

    local dspAlertBtn = PS.MakeBtn(rightCard, 96, 22, "Осколки: ?", "dark")
    dspAlertBtn:SetPoint("TOPLEFT", 10, -162)
    dspAlertBtn:SetScript("OnClick", function()
        AP:ToggleDisperseAlert()
        AP.After(0.15, function() box.RefreshData() end, "ap_dsp_pref_ref")
    end)

    local ibSplitBtn = PS.MakeBtn(rightCard, 108, 22, "Разбор дублей", "dark")
    ibSplitBtn:SetPoint("LEFT", dspAlertBtn, "RIGHT", 3, 0)
    ibSplitBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ibSplitBtn:SetScript("OnClick", function(_, mBtn)
        if SS.ibSplit and SS.ibSplit.running and type(AP.StopItemBankSplit) == "function" then
            AP:StopItemBankSplit("user")
        elseif mBtn == "RightButton" and type(AP.GetItemBankSplitPlan) == "function" then
            local sp = AP:GetItemBankSplitPlan(true)
            if DEFAULT_CHAT_FRAME then
                if not sp.available then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Разбор дублей: " .. tostring(sp.reason or "?"))
                else
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff38bdf8[AttuneParser]|r К разбору готово: %d шт. (%d групп; оставлено под ковку: %d).", sp.totalCount or 0, sp.groupCount or 0, sp.keptForge or 0))
                end
            end
        elseif type(AP.PromptItemBankSplit) == "function" then
            AP:PromptItemBankSplit(true)
        end
        AP.After(0.20, function() box.RefreshData() end, "ap_ib_split_ref")
    end)
    ibSplitBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Расщепление освоенных дубликатов")
        GameTooltip:AddLine("ЛКМ: расщепить полностью освоенные копии из Банка вещей (сохраняет 1 копию под ковку и черный список).", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("ПКМ: вывести сводку в чат.", 0.4, 1.0, 0.4, true)
        if type(AP.GetItemBankSplitPlan) == "function" then
            local sp = AP:GetItemBankSplitPlan(true)
            if sp.available then
                GameTooltip:AddLine(string.format("К расщеплению: %d шт. (%d групп) | Оставлено под ковку: %d",
                    sp.totalCount or 0, sp.groupCount or 0, sp.keptForge or 0), 0.7, 0.85, 1.0, true)
            else
                GameTooltip:AddLine(tostring(sp.reason or "Недоступно"), 1, 0.5, 0.5, true)
            end
        end
        GameTooltip:Show()
    end)
    ibSplitBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local wbSyncBtn = PS.MakeBtn(rightCard, 98, 22, "Таймеры боссов", "dark")
    wbSyncBtn:SetPoint("LEFT", ibSplitBtn, "RIGHT", 3, 0)
    wbSyncBtn:SetScript("OnClick", function()
        AP:RequestWorldBossCD()
        AP:RequestWhereItemsSync()
        AP.After(0.35, function() box.RefreshData() end, "ap_wb_ref")
    end)

    local wbHdr = rightCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    wbHdr:SetPoint("TOPLEFT", 10, -194)
    wbHdr:SetText("|cffffd200Мировые боссы и таймеры|r")

    local wbListBox = CreateFrame("Frame", nil, rightCard)
    wbListBox:SetPoint("TOPLEFT", 10, -214)
    wbListBox:SetSize(306, 168)
    PS.StyleBox(wbListBox, 0.36, false)

    box.wbRows = {}
    local WB_VIS = 8
    local WB_H = 20
    local sf = PS.AttachScroll(wbListBox, WB_VIS * WB_H, WB_H, WB_VIS, function()
        local off = wbListBox.sf.offset or 0
        local list = box.wbData or {}
        for i = 1, WB_VIS do
            local r = box.wbRows[i]
            local b = list[off + i]
            if not b then
                r:Hide()
            else
                r:Show()
                r.nm:SetText(b.name)
                if b.ready then
                    r.cd:SetText("|cff40ff40Готов|r")
                else
                    r.cd:SetText("|cffff8040" .. b.remText .. "|r")
                end
            end
        end
    end)
    wbListBox.sf = sf
    sf:SetPoint("TOPLEFT", wbListBox, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", wbListBox, "BOTTOMRIGHT", -4, 4)

    for i = 1, WB_VIS do
        local r = CreateFrame("Frame", nil, sf)
        r:SetHeight(WB_H - 1)
        r:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i - 1) * WB_H)
        r:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -16, -(i - 1) * WB_H)
        r.nm = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.nm:SetPoint("LEFT", 4, 0)
        r.nm:SetSize(210, 14)
        r.nm:SetJustifyH("LEFT")
        r.cd = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.cd:SetPoint("RIGHT", -4, 0)
        r.cd:SetSize(74, 14)
        r.cd:SetJustifyH("RIGHT")
        r:Hide()
        box.wbRows[i] = r
    end

    function box.RefreshData()
        local as = AP:GetAutoSwapSummary()
        for _, u in ipairs(updaters) do
            u.fn(not u.isSell or as.unlocked)
        end
        PS.PaintBtn(sweepNowBtn, as.unlocked and "green" or "gray")
        if as.unlocked then
            unlockBtn.label:SetText("Обновить фильтры")
            PS.PaintBtn(unlockBtn, "dark")
        else
            unlockBtn.label:SetText("Разблокировать")
            PS.PaintBtn(unlockBtn, "dark")
        end

        local st = AP:GetForgeMaterialStock()
        local dsp = AP:GetDisperseSummary()
        local vt = AP:GetMPlusVaultSummary()
        local ibSum = AP:GetItemBankEquipSummary(true)
        local ibPutSum = AP:GetItemBankPutSummary(true)
        local ibCnt = ibSum.itemCount or 0
        PS.PaintBtn(ibEquipNowBtn, ((ibSum.eligibleCount or 0) > 0 or (ibPutSum.eligibleCount or 0) > 0) and "green" or "dark")
        ibPutModeBtn.label:SetText("Режим: " .. tostring(ibPutSum.modeLabel or "Неосвоенные"))
        PS.PaintBtn(ibPutModeBtn, ibPutSum.on and "green" or "dark")

        local vtStr = "|cff94a3b8нет данных|r"
        if vt.quick == 1 then
            vtStr = "|cff40ff40Награда ждет выбора!|r"
        elseif vt.quick == 2 then
            vtStr = "|cff94a3b8Получена на этой неделе|r"
        elseif vt.loaded then
            vtStr = string.format("Лучший ключ: |cff38bdf8+%d|r (ilvl %d)", vt.curBest or 0, vt.curIlvl or 0)
        end

        local shardStr = (dsp.activeShards > 0)
            and string.format("|cff40ff40%d рядом|r (Ф:%d / О:%d / С:%d)", dsp.activeShards, dsp.violetShards, dsp.orangeShards, dsp.radiantShards)
            or "|cff94a3b80|r"

        local ibAutoStr = ibSum.on
            and ((ibSum.graceRemain or 0) > 0 and string.format("|cffffd200пауза %dс|r", ibSum.graceRemain) or "|cff40ff40ВКЛ|r")
            or "|cff94a3b8ВЫКЛ|r"
        local ibPutStr = ibPutSum.on
            and ((ibPutSum.pauseRemain or 0) > 0 and string.format("|cffffd200пауза %dс|r", ibPutSum.pauseRemain) or "|cff40ff40ВКЛ|r")
            or "|cff94a3b8ВЫКЛ|r"

        statusTxt:SetText(string.format(
            "Банк вещей: |cffffffff%d/%d|r | Автонадевание:%s(%d) | Склад:%s(%d)\nБанк ресурсов: |cffffffff%d/%d|r видов | Пыль: %d М / %d П / %d А\nРасщепление: навык |cff38bdf8%d/%d|r (ранг %d) | Осколки: %s\nЭфир сессии: +%d пыли (+%d навык)\nНаграда ключей M+: %s",
            ibCnt, SS.ib.cap or 0, ibAutoStr, ibSum.eligibleCount or 0, ibPutStr, ibPutSum.eligibleCount or 0,
            st.rbUsed or 0, st.rbMax or 0, st.rbDustEpic or 0, st.rbDustLeg or 0, st.rbDustTit or 0,
            dsp.skill or 0, dsp.maxSkill or 0, dsp.rank or 0, shardStr,
            dsp.sessionDust or 0, dsp.sessionGained or 0,
            vtStr
        ))

        PS.PaintBtn(vaultBtn, (vt.quick == 1) and "green" or "dark")
        PS.PaintBtn(dspAlertBtn, dsp.alertOn and "green" or "dark")
        dspAlertBtn.label:SetText("Осколки: " .. (dsp.alertOn and "ВКЛ" or "ВЫКЛ"))
        if SS.ibSplit and SS.ibSplit.running then
            PS.PaintBtn(ibSplitBtn, "red")
            ibSplitBtn.label:SetText("Стоп разбор")
        else
            local sp = (type(AP.GetItemBankSplitPlan) == "function") and AP:GetItemBankSplitPlan(true) or nil
            local sc = (sp and sp.totalCount) or 0
            PS.PaintBtn(ibSplitBtn, sc > 0 and "green" or "dark")
            ibSplitBtn.label:SetText("Разбор (" .. sc .. ")")
        end

        box.wbData = AP:GetWorldBossList()
        wbListBox.sf:SetTotal(#box.wbData, true)
    end

    return box
end
end

---------------------------------------------------------------------------
-- 5. Safe ItemBank Duplicate Splitter (ACMSG_IB_SPLIT / ACMSG_IB_SPLITN)
---------------------------------------------------------------------------
do
    local SS = AP.serverSync
    local ibSplit = SS.ibSplit
    local splitDrv = CreateFrame("Frame")
    splitDrv:Hide()

    local function SendSplitWhisp(prefix, body)
        if type(SendAddonMessage) ~= "function" or type(UnitName) ~= "function" then return false end
        local me = UnitName("player")
        if not me or me == "" then return false end
        return pcall(SendAddonMessage, prefix, body or "", "WHISPER", me)
    end

    local function ResolveIBSplitSkill(pib)
        local sk = (SS.ib and SS.ib.dspSkill) or 0
        if type(pib) == "table" and tonumber(pib.dspSkill) and tonumber(pib.dspSkill) > sk then
            sk = tonumber(pib.dspSkill)
        end
        if SS.dsp and tonumber(SS.dsp.skill) and tonumber(SS.dsp.skill) > sk then
            sk = tonumber(SS.dsp.skill)
        end
        return sk
    end

    local function CheckIBCopyStatus(eid, forge, sfx)
        local fnSrv = rawget(_G, "CustomAttuneItemStatus")
        if type(fnSrv) == "function" then
            local ok, done, cant, _, attun = pcall(fnSrv, eid, forge, sfx)
            if ok and attun ~= nil then
                if cant or attun == false then
                    return false, false
                end
                local isDone = (done == true)
                local isCompleted = isDone and (forge >= 3)
                if isDone and not isCompleted then
                    local ok3, done3 = pcall(fnSrv, eid, 3, sfx)
                    if ok3 and done3 == true then
                        isCompleted = true
                    elseif type(AP.GetItemServerStatus) == "function" then
                        local st = AP:GetItemServerStatus(eid)
                        if st and st.isCompleted == true then
                            isCompleted = true
                        end
                    end
                end
                return isDone, isCompleted
            end
        end
        if type(AP.GetItemServerStatus) == "function" then
            local st = AP:GetItemServerStatus(eid)
            if st then
                local isDone = (st.isCompleted == true) or ((st.doneTier or -1) >= forge)
                local isCompleted = (st.isCompleted == true) or (forge >= 3)
                return isDone, isCompleted
            end
        end
        return false, false
    end

    function AP:GetItemBankSplitPlan(keepForgeCopy)
        local keep = (keepForgeCopy ~= false)
        local now = GetTime()
        local pib = rawget(_G, "PRIME_ItemBank")
        local ibItems = (type(pib) == "table" and type(pib.items) == "table" and #pib.items > 0) and pib.items
            or ((SS.ib and SS.ib.fullLoaded) and SS.ib.items or nil)
        if not ibItems then
            return {
                available = false,
                reason = "Сначала открой Банк предметов (/ibank)",
                totalCount = 0,
                groupCount = 0,
                keptForge = 0,
                groups = {},
            }
        end

        local dspSkill = ResolveIBSplitSkill(pib)
        if dspSkill <= 0 then
            return {
                available = false,
                reason = "Нет навыка «Расщепление эссенций»",
                totalCount = 0,
                groupCount = 0,
                keptForge = 0,
                groups = {},
            }
        end

        local dspBatch = ((type(pib) == "table" and pib.dspBatch == true) or (SS.ib and SS.ib.dspBatch == true)) == true
        local sfxBatch = ((type(pib) == "table" and pib.sfxBatch == true) or (SS.ib and SS.ib.sfxBatch == true)) == true

        local evalList = {}
        local bucketUnsafe = {}
        local bucketKept = {}
        local keepPickByEid = {}

        for _, it in ipairs(ibItems) do
            local eid = tonumber(it and it.entry)
            local guid = tonumber(it and it.guid)
            if eid and guid and eid > 0 and (eid < 1702000 or eid > 1702999) then
                local sfx = tonumber(it.suffix) or 0
                local forge = tonumber(it.forge) or 0
                local dsp = tonumber(it.dsp) or 0
                local bKey = sfxBatch and (eid .. ":" .. sfx) or tostring(eid)
                local isDone, isCompleted = CheckIBCopyStatus(eid, forge, sfx)
                local bl = (type(AP.IsItemBlacklisted) == "function") and AP:IsItemBlacklisted(eid, forge)
                local failed = ((ibSplit.failUntil[guid] or 0) > now)
                if not isDone or bl or failed or dsp <= 0 or dspSkill < dsp then
                    bucketUnsafe[bKey] = true
                else
                    local needKeep = keep and (not isCompleted) and (forge < 3)
                    if needKeep then
                        local cur = keepPickByEid[eid]
                        if not cur or forge > cur.forge then
                            keepPickByEid[eid] = { guid = guid, forge = forge, bKey = bKey }
                        end
                    end
                    evalList[#evalList + 1] = {
                        guid = guid,
                        entry = eid,
                        sfx = sfx,
                        forge = forge,
                        dsp = dsp,
                        bKey = bKey,
                        link = it.link or ("item:" .. eid),
                    }
                end
            end
        end

        local keptGuids = {}
        local keptForge = 0
        for _, kp in pairs(keepPickByEid) do
            keptGuids[kp.guid] = true
            bucketKept[kp.bKey] = (bucketKept[kp.bKey] or 0) + 1
            keptForge = keptForge + 1
        end

        local groupsByKey = {}
        local groups = {}
        local totalCount = 0
        for _, rec in ipairs(evalList) do
            if not keptGuids[rec.guid] then
                totalCount = totalCount + 1
                local gKey = rec.entry .. ":" .. rec.sfx .. ":" .. rec.forge
                local g = groupsByKey[gKey]
                if not g then
                    local nm = (type(GetItemInfo) == "function" and GetItemInfo(rec.link)) or ("#" .. rec.entry)
                    g = {
                        entry = rec.entry,
                        sfx = rec.sfx,
                        forge = rec.forge,
                        dsp = rec.dsp,
                        bKey = rec.bKey,
                        name = nm,
                        link = rec.link,
                        guids = {},
                    }
                    groupsByKey[gKey] = g
                    groups[#groups + 1] = g
                end
                g.guids[#g.guids + 1] = rec.guid
            end
        end

        for _, g in ipairs(groups) do
            local canBatch = dspBatch and (#g.guids >= 2) and (g.sfx == 0 or sfxBatch)
                and (not bucketUnsafe[g.bKey]) and ((bucketKept[g.bKey] or 0) == 0)
            g.canBatch = canBatch
            if canBatch then
                g.sendOp = "ACMSG_IB_SPLITN"
                g.sendBody = sfxBatch
                    and string.format("%d:%d:%d", g.entry, #g.guids, g.sfx)
                    or string.format("%d:%d", g.entry, #g.guids)
            else
                g.sendOp = "ACMSG_IB_SPLIT"
                g.sendBody = tostring(g.guids[1])
            end
        end

        table.sort(groups, function(a, b)
            if a.canBatch ~= b.canBatch then return a.canBatch end
            if #a.guids ~= #b.guids then return #a.guids > #b.guids end
            return a.entry < b.entry
        end)

        return {
            available = true,
            dspSkill = dspSkill,
            dspBatch = dspBatch,
            sfxBatch = sfxBatch,
            totalCount = totalCount,
            groupCount = #groups,
            keptForge = keptForge,
            groups = groups,
            first = groups[1],
        }
    end

    function AP:StopItemBankSplit(why)
        ibSplit.running = false
        ibSplit.pending = false
        ibSplit.inFlightKind = nil
        ibSplit.inFlightGuid = nil
        splitDrv:Hide()
        if why and DEFAULT_CHAT_FRAME then
            local msg = (why == "combat") and "остановлено (бой)"
                or ((why == "user") and "остановлено пользователем" or tostring(why))
            DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Расщепление дублей " .. msg .. ".")
        end
        AP:Fire("SERVER_SYNC_UPDATED", "IB_SPLIT_STOP")
    end

    function AP:RunItemBankSplitStep()
        if not ibSplit.running then
            return false, "stopped"
        end
        local inC = (type(InCombatLockdown) == "function" and InCombatLockdown())
            or (type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player"))
        if inC then
            AP:StopItemBankSplit("combat")
            return false, "combat"
        end
        if type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost("player") then
            AP:StopItemBankSplit("мертв")
            return false, "dead"
        end
        local now = GetTime()
        if ibSplit.inFlightKind then
            if (now - (ibSplit.inFlightAt or 0)) < 3.5 then
                ibSplit.pending = true
                ibSplit.scheduledAt = now + 0.35
                splitDrv:Show()
                return false, "in_flight"
            end
            if ibSplit.inFlightGuid then
                ibSplit.failUntil[ibSplit.inFlightGuid] = now + 30
            end
            ibSplit.inFlightKind = nil
            ibSplit.inFlightGuid = nil
        end

        local sp = AP:GetItemBankSplitPlan(ibSplit.keepForgeCopy ~= false)
        if not sp.available or not sp.first then
            local cnt = ibSplit.doneCount or 0
            AP:StopItemBankSplit(cnt > 0 and ("завершено (запросов: " .. cnt .. ")") or (sp.reason or "готово"))
            return false, sp.reason or "done"
        end

        local g = sp.first
        local sent = SendSplitWhisp(g.sendOp, g.sendBody)
        if not sent then
            AP:StopItemBankSplit("ошибка отправки")
            return false, "send_failed"
        end

        ibSplit.inFlightKind = g.canBatch and "splitn" or "split"
        ibSplit.inFlightGuid = (not g.canBatch) and g.guids[1] or nil
        ibSplit.inFlightAt = now
        ibSplit.lastTryAt = now
        ibSplit.doneCount = (ibSplit.doneCount or 0) + (g.canBatch and #g.guids or 1)
        ibSplit.pending = true
        ibSplit.scheduledAt = now + (sp.dspBatch and 0.40 or 1.75)
        splitDrv:Show()
        AP:Fire("SERVER_SYNC_UPDATED", "IB_SPLIT_STEP")
        return true, g.canBatch and "splitn" or "split", g
    end

    function AP:StartItemBankSplit(keepForgeCopy)
        local inC = (type(InCombatLockdown) == "function" and InCombatLockdown())
            or (type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player"))
        if inC then
            return false, "combat"
        end
        local sp = AP:GetItemBankSplitPlan(keepForgeCopy)
        if not sp.available or (sp.totalCount or 0) == 0 then
            return false, sp.reason or "no_candidates"
        end
        ibSplit.running = true
        ibSplit.keepForgeCopy = (keepForgeCopy ~= false)
        ibSplit.doneCount = 0
        ibSplit.lastError = nil
        ibSplit.inFlightKind = nil
        ibSplit.inFlightGuid = nil
        return AP:RunItemBankSplitStep()
    end

    function AP:PromptItemBankSplit(keepForgeCopy)
        local sp = AP:GetItemBankSplitPlan(keepForgeCopy)
        if not sp.available or (sp.totalCount or 0) == 0 then
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Расщепление дублей: " .. tostring(sp.reason or ("нет лишних поглощенных копий (под ковку оставлено: " .. tostring(sp.keptForge or 0) .. ")")))
            end
            return false, sp.reason or "no_candidates"
        end
        if _G.StaticPopupDialogs and _G.StaticPopup_Show then
            _G.StaticPopupDialogs["ATTUNEPARSER_IB_SPLIT"] = {
                text = string.format(
                    "Расщепить из Банка вещей: %d шт. (%d групп)?\n\nЗатрагиваются только полностью поглощенные дубли (сохранено копий под ковку до Титанического: %d; ЧС не трогается).",
                    sp.totalCount or 0, sp.groupCount or 0, sp.keptForge or 0
                ),
                button1 = YES or "Расщепить",
                button2 = NO or "Отмена",
                timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1,
                OnAccept = function() AP:StartItemBankSplit(keepForgeCopy) end,
            }
            _G.StaticPopup_Show("ATTUNEPARSER_IB_SPLIT")
            return true, "prompt"
        end
        return AP:StartItemBankSplit(keepForgeCopy)
    end

    function SS.onIBSplitRes(code, text)
        local now = GetTime()
        if code and code ~= 0 then
            if ibSplit.inFlightGuid then
                ibSplit.failUntil[ibSplit.inFlightGuid] = now + 30
            end
            ibSplit.inFlightKind = nil
            ibSplit.inFlightGuid = nil
            ibSplit.lastError = (text and text ~= "") and text or ("Код " .. tostring(code))
            AP:StopItemBankSplit("отклонен: " .. ibSplit.lastError)
            return
        end
        ibSplit.inFlightKind = nil
        ibSplit.inFlightGuid = nil
        ibSplit.lastError = nil
        if ibSplit.running then
            ibSplit.pending = true
            ibSplit.scheduledAt = now + ((SS.ib and SS.ib.dspBatch) and 0.20 or 1.45)
            splitDrv:Show()
        end
        AP:Fire("SERVER_SYNC_UPDATED", "ASMSG_IB_RES")
    end

    splitDrv:SetScript("OnUpdate", function(self, elapsed)
        self._acc = (self._acc or 0) + (elapsed or 0)
        if self._acc < 0.12 then return end
        self._acc = 0
        if not ibSplit.running or not ibSplit.pending then
            self:Hide()
            return
        end
        if GetTime() < (ibSplit.scheduledAt or 0) then
            return
        end
        ibSplit.pending = false
        AP:RunItemBankSplitStep()
    end)
end

---------------------------------------------------------------------------
-- 6. Valdris Auto-Upgrader + Item Picker + Alt-Click (Custom_ItemProgress)
---------------------------------------------------------------------------
do
    local math_floor, math_max = math.floor, math.max
    local tonumber, tostring, pairs, ipairs = tonumber, tostring, pairs, ipairs
    local SS = AP.serverSync
    local vp = SS.valdris
    local vpDrv = CreateFrame("Frame")
    vpDrv:Hide()
    local vpBar, vpPicker = nil, nil

    local DEFAULT_PICK_ICON = "Interface\\Icons\\INV_Hammer_20"
    local TIER_SHORT = {
        [1] = "Эпик (1)",
        [2] = "Лег. (2)",
        [3] = "Титан (3)",
    }
    local FORGE_VIS = {
        [1] = { name = "Эпический",    short = "Эпик",  r = 0.733, g = 0.475, b = 0.910, hex = "ffbb79e8", blp = "Interface\\FrameXML\\Custom_Attune\\attune_epic" },
        [2] = { name = "Легендарный",  short = "Лег.",  r = 1.000, g = 0.500, b = 0.000, hex = "ffff8000", blp = "Interface\\FrameXML\\Custom_Attune\\attune_legendary" },
        [3] = { name = "Титанический", short = "Титан", r = 0.000, g = 1.000, b = 0.800, hex = "ff00ffcc", blp = "Interface\\FrameXML\\Custom_Attune\\attune_titanic" },
    }
    local INV_ID_TO_LOC = {
        [1]  = "INVTYPE_HEAD",
        [2]  = "INVTYPE_NECK",
        [3]  = "INVTYPE_SHOULDER",
        [5]  = "INVTYPE_CHEST",
        [6]  = "INVTYPE_WAIST",
        [7]  = "INVTYPE_LEGS",
        [8]  = "INVTYPE_FEET",
        [9]  = "INVTYPE_WRIST",
        [10] = "INVTYPE_HAND",
        [11] = "INVTYPE_FINGER",
        [12] = "INVTYPE_TRINKET",
        [13] = "INVTYPE_WEAPON",
        [14] = "INVTYPE_SHIELD",
        [15] = "INVTYPE_RANGED",
        [16] = "INVTYPE_CLOAK",
        [17] = "INVTYPE_2HWEAPON",
        [20] = "INVTYPE_ROBE",
        [21] = "INVTYPE_WEAPONMAINHAND",
        [22] = "INVTYPE_WEAPONOFFHAND",
        [23] = "INVTYPE_HOLDABLE",
        [25] = "INVTYPE_THROWN",
        [26] = "INVTYPE_RANGEDRIGHT",
        [28] = "INVTYPE_RELIC",
    }
    local function ResolveBagForge(bag, slot, eid)
        local t = (bag and slot and AP.forgeBag and AP.forgeBag[bag]) and AP.forgeBag[bag][slot]
        if t ~= nil then return tonumber(t) or 0 end
        return 0
    end
    local function ResolveEquipForge(invSlot, eid)
        if invSlot and AP.forgeEquip and AP.forgeEquip[invSlot] ~= nil then
            return tonumber(AP.forgeEquip[invSlot]) or 0
        end
        if invSlot and SS.ib and SS.ib.worn and SS.ib.worn[invSlot] ~= nil then
            return tonumber(SS.ib.worn[invSlot]) or 0
        end
        local pib = rawget(_G, "PRIME_ItemBank")
        if invSlot and type(pib) == "table" and type(pib.worn) == "table" and pib.worn[invSlot - 1] ~= nil then
            return tonumber(pib.worn[invSlot - 1]) or 0
        end
        if eid and AP.forgeByEntry and AP.forgeByEntry[eid] ~= nil then
            return tonumber(AP.forgeByEntry[eid]) or 0
        end
        return 0
    end
    local function ApplyForgeIconVisual(iconBox, forgeBadge, absChk, forgeTier, qual, isAbsorbed)
        local fv = forgeTier and FORGE_VIS[forgeTier]
        if iconBox and iconBox.SetBackdropBorderColor then
            if fv then
                iconBox:SetBackdropBorderColor(fv.r, fv.g, fv.b, 1)
            elseif qual and qual >= 2 and type(GetItemQualityColor) == "function" then
                local qr, qg, qb = GetItemQualityColor(qual)
                if qr then
                    iconBox:SetBackdropBorderColor(qr, qg, qb, 0.85)
                else
                    iconBox:SetBackdropBorderColor(0.45, 0.38, 0.22, 0.82)
                end
            else
                iconBox:SetBackdropBorderColor(0.45, 0.38, 0.22, 0.82)
            end
        end
        if forgeBadge then
            if fv and fv.blp then
                forgeBadge:SetTexture(fv.blp)
                forgeBadge:Show()
            else
                forgeBadge:Hide()
            end
        end
        if absChk then
            if isAbsorbed then absChk:Show() else absChk:Hide() end
        end
    end
    local EQUIP_SLOTS = {
        { id = 1,  label = "Голова" },
        { id = 2,  label = "Шея" },
        { id = 3,  label = "Плечи" },
        { id = 15, label = "Спина" },
        { id = 5,  label = "Грудь" },
        { id = 9,  label = "Запястья" },
        { id = 10, label = "Кисти" },
        { id = 6,  label = "Пояс" },
        { id = 7,  label = "Ноги" },
        { id = 8,  label = "Ступни" },
        { id = 11, label = "Кольцо 1" },
        { id = 12, label = "Кольцо 2" },
        { id = 13, label = "Тринка 1" },
        { id = 14, label = "Тринка 2" },
        { id = 16, label = "Пр. рука" },
        { id = 17, label = "Лев. рука" },
        { id = 18, label = "Дальн." },
    }

    -- Exact 855 Tier-9 / Tier-10 set items upgraded by NPC Mor'Kel (57 sets x 15 items, IPStatus 21 at Valdris)
    local MORKEL_ITEMS = {
        -- [843] Регалии Кадгара
        [47748]=true,[47749]=true,[47750]=true,[47751]=true,[47752]=true,[47753]=true,[47754]=true,[47755]=true,[47756]=true,[47757]=true,[47758]=true,[47759]=true,[47760]=true,[47761]=true,[47762]=true,
        -- [844] Регалии Солнечного Скитальца
        [47763]=true,[47764]=true,[47765]=true,[47766]=true,[47767]=true,[47768]=true,[47769]=true,[47770]=true,[47771]=true,[47772]=true,[47773]=true,[47774]=true,[47775]=true,[47776]=true,[47777]=true,
        -- [845] Регалии Гул'дана
        [47793]=true,[47794]=true,[47795]=true,[47796]=true,[47797]=true,[47798]=true,[47799]=true,[47800]=true,[47801]=true,[47802]=true,[47803]=true,[47804]=true,[47805]=true,[47806]=true,[47807]=true,
        -- [846] Регалии Кел'Тузада
        [47778]=true,[47779]=true,[47780]=true,[47781]=true,[47782]=true,[47783]=true,[47784]=true,[47785]=true,[47786]=true,[47787]=true,[47788]=true,[47789]=true,[47790]=true,[47791]=true,[47792]=true,
        -- [847] Облачение Велена
        [47914]=true,[47936]=true,[47980]=true,[47981]=true,[47982]=true,[47983]=true,[47984]=true,[47985]=true,[47986]=true,[47987]=true,[48029]=true,[48031]=true,[48033]=true,[48035]=true,[48037]=true,
        -- [848] Облачение Забры
        [48057]=true,[48058]=true,[48059]=true,[48060]=true,[48061]=true,[48062]=true,[48063]=true,[48064]=true,[48065]=true,[48066]=true,[48067]=true,[48068]=true,[48069]=true,[48070]=true,[48071]=true,
        -- [849] Регалии Велена
        [48072]=true,[48073]=true,[48074]=true,[48075]=true,[48076]=true,[48077]=true,[48078]=true,[48079]=true,[48080]=true,[48081]=true,[48082]=true,[48083]=true,[48084]=true,[48085]=true,[48086]=true,
        -- [850] Регалии Забры
        [48087]=true,[48088]=true,[48089]=true,[48090]=true,[48091]=true,[48092]=true,[48093]=true,[48094]=true,[48095]=true,[48096]=true,[48097]=true,[48098]=true,[48099]=true,[48100]=true,[48101]=true,
        -- [851] Наряд Малфуриона
        [48102]=true,[48129]=true,[48130]=true,[48131]=true,[48132]=true,[48133]=true,[48134]=true,[48135]=true,[48136]=true,[48137]=true,[48138]=true,[48139]=true,[48140]=true,[48141]=true,[48142]=true,
        -- [852] Наряд Рунического Тотема
        [48143]=true,[48144]=true,[48145]=true,[48146]=true,[48147]=true,[48148]=true,[48149]=true,[48150]=true,[48151]=true,[48152]=true,[48153]=true,[48154]=true,[48155]=true,[48156]=true,[48157]=true,
        -- [853] Регалии Малфуриона
        [48158]=true,[48159]=true,[48160]=true,[48161]=true,[48162]=true,[48163]=true,[48164]=true,[48165]=true,[48166]=true,[48167]=true,[48168]=true,[48169]=true,[48170]=true,[48171]=true,[48172]=true,
        -- [854] Регалии Рунического Тотема
        [48173]=true,[48174]=true,[48175]=true,[48176]=true,[48177]=true,[48178]=true,[48179]=true,[48180]=true,[48181]=true,[48182]=true,[48183]=true,[48184]=true,[48185]=true,[48186]=true,[48187]=true,
        -- [855] Броня Малфуриона
        [48203]=true,[48204]=true,[48205]=true,[48206]=true,[48207]=true,[48208]=true,[48209]=true,[48210]=true,[48211]=true,[48212]=true,[48213]=true,[48214]=true,[48215]=true,[48216]=true,[48217]=true,
        -- [856] Броня Рунического Тотема
        [48188]=true,[48189]=true,[48190]=true,[48191]=true,[48192]=true,[48193]=true,[48194]=true,[48195]=true,[48196]=true,[48197]=true,[48198]=true,[48199]=true,[48200]=true,[48201]=true,[48202]=true,
        -- [857] Броня ван Клифа
        [48218]=true,[48219]=true,[48220]=true,[48221]=true,[48222]=true,[48223]=true,[48224]=true,[48225]=true,[48226]=true,[48227]=true,[48228]=true,[48229]=true,[48230]=true,[48231]=true,[48232]=true,
        -- [858] Броня Гароны
        [48233]=true,[48234]=true,[48235]=true,[48236]=true,[48237]=true,[48238]=true,[48239]=true,[48240]=true,[48241]=true,[48242]=true,[48243]=true,[48244]=true,[48245]=true,[48246]=true,[48247]=true,
        -- [859] Броня Ветрокрылой
        [48250]=true,[48251]=true,[48252]=true,[48253]=true,[48254]=true,[48255]=true,[48256]=true,[48257]=true,[48258]=true,[48259]=true,[48260]=true,[48261]=true,[48262]=true,[48263]=true,[48264]=true,
        -- [860] Одеяние Ветрокрылой
        [48265]=true,[48266]=true,[48267]=true,[48268]=true,[48269]=true,[48270]=true,[48271]=true,[48272]=true,[48273]=true,[48274]=true,[48275]=true,[48276]=true,[48277]=true,[48278]=true,[48279]=true,
        -- [861] Наряд Нобундо
        [48280]=true,[48281]=true,[48282]=true,[48283]=true,[48284]=true,[48285]=true,[48286]=true,[48287]=true,[48288]=true,[48289]=true,[48290]=true,[48291]=true,[48292]=true,[48293]=true,[48294]=true,
        -- [862] Наряд Тралла
        [48295]=true,[48296]=true,[48297]=true,[48298]=true,[48299]=true,[48300]=true,[48301]=true,[48302]=true,[48303]=true,[48304]=true,[48305]=true,[48306]=true,[48307]=true,[48308]=true,[48309]=true,
        -- [863] Регалии Тралла
        [48326]=true,[48327]=true,[48328]=true,[48329]=true,[48330]=true,[48331]=true,[48332]=true,[48333]=true,[48334]=true,[48335]=true,[48336]=true,[48337]=true,[48338]=true,[48339]=true,[48340]=true,
        -- [864] Регалии Нобундо
        [48310]=true,[48312]=true,[48313]=true,[48314]=true,[48315]=true,[48316]=true,[48317]=true,[48318]=true,[48319]=true,[48320]=true,[48321]=true,[48322]=true,[48323]=true,[48324]=true,[48325]=true,
        -- [865] Броня Нобундо
        [48341]=true,[48342]=true,[48343]=true,[48344]=true,[48345]=true,[48346]=true,[48347]=true,[48348]=true,[48349]=true,[48350]=true,[48351]=true,[48352]=true,[48353]=true,[48354]=true,[48355]=true,
        -- [866] Броня Тралла
        [48356]=true,[48357]=true,[48358]=true,[48359]=true,[48360]=true,[48361]=true,[48362]=true,[48363]=true,[48364]=true,[48365]=true,[48366]=true,[48367]=true,[48368]=true,[48369]=true,[48370]=true,
        -- [867] Броня Ринна
        [48371]=true,[48372]=true,[48373]=true,[48374]=true,[48375]=true,[48376]=true,[48377]=true,[48378]=true,[48379]=true,[48380]=true,[48381]=true,[48382]=true,[48383]=true,[48384]=true,[48385]=true,
        -- [868] Броня Адского Крика
        [48386]=true,[48387]=true,[48388]=true,[48389]=true,[48390]=true,[48391]=true,[48392]=true,[48393]=true,[48394]=true,[48395]=true,[48396]=true,[48397]=true,[48398]=true,[48399]=true,[48400]=true,
        -- [869] Латы Ринна
        [48429]=true,[48430]=true,[48433]=true,[48436]=true,[48445]=true,[48446]=true,[48447]=true,[48448]=true,[48449]=true,[48450]=true,[48451]=true,[48452]=true,[48453]=true,[48454]=true,[48455]=true,
        -- [870] Латы Адского Крика
        [48456]=true,[48457]=true,[48458]=true,[48459]=true,[48460]=true,[48461]=true,[48462]=true,[48463]=true,[48464]=true,[48465]=true,[48466]=true,[48467]=true,[48468]=true,[48469]=true,[48470]=true,
        -- [871] Броня Тассариана
        [48472]=true,[48474]=true,[48476]=true,[48478]=true,[48480]=true,[48481]=true,[48482]=true,[48483]=true,[48484]=true,[48485]=true,[48486]=true,[48487]=true,[48488]=true,[48489]=true,[48490]=true,
        -- [872] Броня Кольтиры
        [48491]=true,[48492]=true,[48493]=true,[48494]=true,[48495]=true,[48496]=true,[48497]=true,[48498]=true,[48499]=true,[48500]=true,[48501]=true,[48502]=true,[48503]=true,[48504]=true,[48505]=true,
        -- [873] Латы Тассариана
        [48529]=true,[48531]=true,[48533]=true,[48535]=true,[48537]=true,[48538]=true,[48539]=true,[48540]=true,[48541]=true,[48542]=true,[48543]=true,[48544]=true,[48545]=true,[48546]=true,[48547]=true,
        -- [874] Латы Кольтиры
        [48548]=true,[48549]=true,[48550]=true,[48551]=true,[48552]=true,[48553]=true,[48554]=true,[48555]=true,[48556]=true,[48557]=true,[48558]=true,[48559]=true,[48560]=true,[48561]=true,[48562]=true,
        -- [875] Наряд Туралиона
        [48564]=true,[48566]=true,[48568]=true,[48572]=true,[48574]=true,[48575]=true,[48576]=true,[48577]=true,[48578]=true,[48579]=true,[48580]=true,[48581]=true,[48582]=true,[48583]=true,[48584]=true,
        -- [876] Наряд Лиадрин
        [48585]=true,[48586]=true,[48587]=true,[48588]=true,[48589]=true,[48590]=true,[48591]=true,[48592]=true,[48593]=true,[48594]=true,[48595]=true,[48596]=true,[48597]=true,[48598]=true,[48599]=true,
        -- [877] Броня Туралиона
        [48602]=true,[48603]=true,[48604]=true,[48605]=true,[48606]=true,[48607]=true,[48608]=true,[48609]=true,[48610]=true,[48611]=true,[48612]=true,[48613]=true,[48614]=true,[48615]=true,[48616]=true,
        -- [878] Броня Лиадрин
        [48617]=true,[48618]=true,[48619]=true,[48620]=true,[48621]=true,[48622]=true,[48623]=true,[48624]=true,[48625]=true,[48626]=true,[48627]=true,[48628]=true,[48629]=true,[48630]=true,[48631]=true,
        -- [879] Латы Туралиона
        [48632]=true,[48633]=true,[48634]=true,[48635]=true,[48636]=true,[48637]=true,[48638]=true,[48639]=true,[48640]=true,[48641]=true,[48642]=true,[48643]=true,[48644]=true,[48645]=true,[48646]=true,
        -- [880] Латы Лиадрин
        [48647]=true,[48648]=true,[48649]=true,[48650]=true,[48651]=true,[48652]=true,[48653]=true,[48654]=true,[48655]=true,[48656]=true,[48657]=true,[48658]=true,[48659]=true,[48660]=true,[48661]=true,
        -- [883] Регалии волшебника крови
        [50275]=true,[50276]=true,[50277]=true,[50278]=true,[50279]=true,[51155]=true,[51156]=true,[51157]=true,[51158]=true,[51159]=true,[51280]=true,[51281]=true,[51282]=true,[51283]=true,[51284]=true,
        -- [884] Регалии мрачного шабаша
        [50240]=true,[50241]=true,[50242]=true,[50243]=true,[50244]=true,[51205]=true,[51206]=true,[51207]=true,[51208]=true,[51209]=true,[51230]=true,[51231]=true,[51232]=true,[51233]=true,[51234]=true,
        -- [885] Облачение послушника из Багрового Легиона
        [50765]=true,[50766]=true,[50767]=true,[50768]=true,[50769]=true,[51175]=true,[51176]=true,[51177]=true,[51178]=true,[51179]=true,[51260]=true,[51261]=true,[51262]=true,[51263]=true,[51264]=true,
        -- [886] Регалии послушника из Багрового Легиона
        [50391]=true,[50392]=true,[50393]=true,[50394]=true,[50396]=true,[51180]=true,[51181]=true,[51182]=true,[51183]=true,[51184]=true,[51255]=true,[51256]=true,[51257]=true,[51258]=true,[51259]=true,
        -- [887] Плеточные одеяния
        [50106]=true,[50107]=true,[50108]=true,[50109]=true,[50113]=true,[51135]=true,[51136]=true,[51137]=true,[51138]=true,[51139]=true,[51300]=true,[51301]=true,[51302]=true,[51303]=true,[51304]=true,
        -- [888] Плеточные регалии
        [50819]=true,[50820]=true,[50821]=true,[50822]=true,[50823]=true,[51145]=true,[51146]=true,[51147]=true,[51148]=true,[51149]=true,[51290]=true,[51291]=true,[51292]=true,[51293]=true,[51294]=true,
        -- [889] Плеточная броня
        [50824]=true,[50825]=true,[50826]=true,[50827]=true,[50828]=true,[51140]=true,[51141]=true,[51142]=true,[51143]=true,[51144]=true,[51295]=true,[51296]=true,[51297]=true,[51298]=true,[51299]=true,
        -- [890] Броня теневого клинка
        [50087]=true,[50088]=true,[50089]=true,[50090]=true,[50105]=true,[51185]=true,[51186]=true,[51187]=true,[51188]=true,[51189]=true,[51250]=true,[51251]=true,[51252]=true,[51253]=true,[51254]=true,
        -- [891] Броня ан'кахарского охотника за кровью
        [50114]=true,[50115]=true,[50116]=true,[50117]=true,[50118]=true,[51150]=true,[51151]=true,[51152]=true,[51153]=true,[51154]=true,[51285]=true,[51286]=true,[51287]=true,[51288]=true,[51289]=true,
        -- [892] Одеяния ледяной ведьмы
        [50835]=true,[50836]=true,[50837]=true,[50838]=true,[50839]=true,[51190]=true,[51191]=true,[51192]=true,[51193]=true,[51194]=true,[51245]=true,[51246]=true,[51247]=true,[51248]=true,[51249]=true,
        -- [893] Регалии ледяной ведьмы
        [50841]=true,[50842]=true,[50843]=true,[50844]=true,[50845]=true,[51200]=true,[51201]=true,[51202]=true,[51203]=true,[51204]=true,[51235]=true,[51236]=true,[51237]=true,[51238]=true,[51239]=true,
        -- [894] Броня ледяной ведьмы
        [50830]=true,[50831]=true,[50832]=true,[50833]=true,[50834]=true,[51195]=true,[51196]=true,[51197]=true,[51198]=true,[51199]=true,[51240]=true,[51241]=true,[51242]=true,[51243]=true,[51244]=true,
        -- [895] Броня имирьярского повелителя
        [50078]=true,[50079]=true,[50080]=true,[50081]=true,[50082]=true,[51210]=true,[51211]=true,[51212]=true,[51213]=true,[51214]=true,[51225]=true,[51226]=true,[51227]=true,[51228]=true,[51229]=true,
        -- [896] Латы имирьярского повелителя
        [50846]=true,[50847]=true,[50848]=true,[50849]=true,[50850]=true,[51215]=true,[51216]=true,[51217]=true,[51218]=true,[51219]=true,[51220]=true,[51221]=true,[51222]=true,[51223]=true,[51224]=true,
        -- [897] Броня повелителя Плети
        [50094]=true,[50095]=true,[50096]=true,[50097]=true,[50098]=true,[51125]=true,[51126]=true,[51127]=true,[51128]=true,[51129]=true,[51310]=true,[51311]=true,[51312]=true,[51313]=true,[51314]=true,
        -- [898] Латы повелителя Плети
        [50853]=true,[50854]=true,[50855]=true,[50856]=true,[50857]=true,[51130]=true,[51131]=true,[51132]=true,[51133]=true,[51134]=true,[51305]=true,[51306]=true,[51307]=true,[51308]=true,[51309]=true,
        -- [899] Одеяния клятвы Свету
        [50865]=true,[50866]=true,[50867]=true,[50868]=true,[50869]=true,[51165]=true,[51166]=true,[51167]=true,[51168]=true,[51169]=true,[51270]=true,[51271]=true,[51272]=true,[51273]=true,[51274]=true,
        -- [900] Броня клятвы Свету
        [50324]=true,[50325]=true,[50326]=true,[50327]=true,[50328]=true,[51160]=true,[51161]=true,[51162]=true,[51163]=true,[51164]=true,[51275]=true,[51276]=true,[51277]=true,[51278]=true,[51279]=true,
        -- [901] Латы клятвы Свету
        [50860]=true,[50861]=true,[50862]=true,[50863]=true,[50864]=true,[51170]=true,[51171]=true,[51172]=true,[51173]=true,[51174]=true,[51265]=true,[51266]=true,[51267]=true,[51268]=true,[51269]=true,
    }
    AP.MORKEL_ITEMS = MORKEL_ITEMS

    local function GetValdrisKnownSkip(eid)
        if not eid then return nil end
        local db = rawget(_G, "AttuneParserDB")
        local ks = type(db) == "table" and db.valdrisKnownSkip
        return type(ks) == "table" and ks[eid] or nil
    end

    local function SaveValdrisKnownSkip(eid, st)
        if not eid or eid <= 0 or not st then return end
        local db = rawget(_G, "AttuneParserDB")
        if type(db) == "table" then
            db.valdrisKnownSkip = db.valdrisKnownSkip or {}
            db.valdrisKnownSkip[eid] = st
        end
    end

    local function IsMorKelOrNoRuleItem(eid)
        if not eid or eid <= 0 then return true, "no_rule" end
        local ks = GetValdrisKnownSkip(eid)
        if ks == 21 or MORKEL_ITEMS[eid] then return true, "morkel" end
        if ks == 9 or ks == 10 or (eid >= 1702000 and eid <= 1702999) then return true, "no_rule" end
        return false, nil
    end

    local RefreshValdrisBar, RefreshValdrisPicker

    local function SendIProgSrv(prefix, body)
        if type(SendServerMessage) ~= "function" then return false end
        return pcall(SendServerMessage, prefix, body or "")
    end

    local function IsValdrisFrameOpen()
        local f = rawget(_G, "ItemProgressFrame")
        return (type(f) == "table" and type(f.IsShown) == "function" and f:IsShown()) and true or false
    end

    local function IsValdrisDispTabOpen()
        local f = rawget(_G, "ItemProgressFrame")
        local d = f and f.DispLeftInset
        return (type(d) == "table" and type(d.IsShown) == "function" and d:IsShown()) and true or false
    end

    local function IsItemBankOpen()
        local pib = rawget(_G, "PRIME_ItemBank")
        if type(pib) == "table" and type(pib.F) == "table" and type(pib.F.IsShown) == "function" and pib.F:IsShown() then
            return true
        end
        local ibf = rawget(_G, "PrimeItemBankFrame")
        return (type(ibf) == "table" and type(ibf.IsShown) == "function" and ibf:IsShown()) and true or false
    end

    local function IsPlayerBusyCombatOrDead()
        local inC = (type(InCombatLockdown) == "function" and InCombatLockdown())
            or (type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player"))
        if inC then return true, "combat" end
        if type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost("player") then
            return true, "dead"
        end
        return false, nil
    end

    local function NormalizeIProgBagSlot(bag, slot)
        bag, slot = tonumber(bag), tonumber(slot)
        if not bag or not slot then return nil, nil end
        if bag == 255 then
            return 0, (slot >= 23) and (slot - 22) or slot
        elseif bag >= 19 and bag <= 22 then
            return bag - 18, slot + 1
        end
        return bag, slot
    end

    local function FindFreeNormalBagSlot()
        for bag = 0, 4 do
            local allow = true
            if bag > 0 and type(GetContainerNumFreeSlots) == "function" then
                local free, fam = GetContainerNumFreeSlots(bag)
                if free ~= nil then
                    allow = (free > 0) and ((tonumber(fam) or 0) == 0)
                end
            end
            if allow then
                local nSlots = (type(GetContainerNumSlots) == "function" and GetContainerNumSlots(bag)) or 0
                for slot = 1, nSlots do
                    if not (type(GetContainerItemLink) == "function" and GetContainerItemLink(bag, slot)) then
                        return bag, slot
                    end
                end
            end
        end
        return nil, nil
    end

    local function ClearCursorSafe()
        if type(CursorHasItem) == "function" and CursorHasItem() and type(ClearCursor) == "function" then
            ClearCursor()
        elseif type(ClearCursor) == "function" then
            ClearCursor()
        end
    end

    local function CropText(s, maxChars)
        s = tostring(s or "")
        if s == "" then return "" end
        maxChars = tonumber(maxChars) or 32
        local total, cutByte = 0, #s
        local limit = (maxChars > 3) and (maxChars - 2) or maxChars
        local i, len = 1, #s
        while i <= len do
            local b = s:byte(i)
            local cl = 1
            if b >= 240 then cl = 4
            elseif b >= 224 then cl = 3
            elseif b >= 192 then cl = 2 end
            if i + cl - 1 > len then break end
            total = total + 1
            if total == limit then cutByte = i + cl - 1 end
            i = i + cl
        end
        if total <= maxChars then return s end
        if limit <= 0 then return ".." end
        return s:sub(1, cutByte) .. ".."
    end

    function AP:GetValdrisMaxTier()
        local t = tonumber(AP:GetSetting("valdrisMaxTier")) or 3
        if t < 1 then t = 1 elseif t > 3 then t = 3 end
        return math_floor(t)
    end

    function AP:SetValdrisMaxTier(tier)
        local t = math_floor(tonumber(tier) or 3)
        if t < 1 then t = 1 elseif t > 3 then t = 3 end
        AP:SetSetting("valdrisMaxTier", t)
        vp.skip = {}
        vp.blockedByTier = {}
        vp.readyInfo = {}
        if RefreshValdrisBar then RefreshValdrisBar() end
        if RefreshValdrisPicker then RefreshValdrisPicker() end
        AP:Fire("SERVER_SYNC_UPDATED", "VALDRIS_TIER")
        return t
    end

    function AP:CycleValdrisMaxTier()
        local cur = AP:GetValdrisMaxTier()
        local nxt = (cur >= 3) and 1 or (cur + 1)
        return AP:SetValdrisMaxTier(nxt)
    end

    function AP:SetValdrisAutoOpen(on)
        local val = (on == true)
        AP:SetSetting("valdrisAutoOpen", val)
        if RefreshValdrisBar then RefreshValdrisBar() end
        return val
    end

    function AP:SetValdrisIncludeEquipped(on)
        local val = (on == true)
        AP:SetSetting("valdrisIncludeEquipped", val)
        vp.skip = {}
        vp.blockedByTier = {}
        if RefreshValdrisBar then RefreshValdrisBar() end
        if RefreshValdrisPicker then RefreshValdrisPicker() end
        AP:Fire("SERVER_SYNC_UPDATED", "VALDRIS_EQUIPPED")
        return val
    end

    function AP:SetValdrisIncludeBank(on)
        local val = (on == true)
        AP:SetSetting("valdrisIncludeBank", val)
        vp.skip = {}
        vp.blockedByTier = {}
        vp.bankSpaceFull = false
        if RefreshValdrisBar then RefreshValdrisBar() end
        if RefreshValdrisPicker then RefreshValdrisPicker() end
        AP:Fire("SERVER_SYNC_UPDATED", "VALDRIS_BANK")
        return val
    end

    local function EvalItemForValdris(eid, sfx, bagForge, wantMax, link, equipLoc, bag, slot, invSlot)
        if not eid or eid <= 0 or (eid >= 1702000 and eid <= 1702999) then
            return false, "no_rule"
        end
        local skipSet, skipWhy = IsMorKelOrNoRuleItem(eid, link, equipLoc, bag, slot, invSlot)
        if skipSet then
            return false, skipWhy or "morkel"
        end
        if type(AP.IsItemBlacklisted) == "function" and AP:IsItemBlacklisted(eid, bagForge) then
            return false, "blacklist"
        end
        if bagForge >= wantMax then
            return false, "max_tier"
        end
        local fnSrv = rawget(_G, "CustomAttuneItemStatus")
        local curDone, nextOpen = false, true
        if type(fnSrv) == "function" then
            local ok, done, cant, _, attun = pcall(fnSrv, eid, bagForge, sfx)
            if ok and attun ~= nil then
                curDone = (done == true) and (not cant) and (attun ~= false)
                if curDone then
                    local okM, doneM = pcall(fnSrv, eid, wantMax, sfx)
                    if okM and doneM == true then nextOpen = false end
                end
            elseif ok and attun == false then
                return false, "no_attune"
            end
        elseif type(AP.GetItemServerStatus) == "function" then
            local st = AP:GetItemServerStatus(eid, "item:" .. eid)
            if st and (st.doneTier or -1) >= bagForge and not st.isCompleted then
                curDone = true
                if (st.doneTier or -1) >= wantMax then nextOpen = false end
            end
        end
        if not curDone then return false, "unabsorbed" end
        if not nextOpen then return false, "max_tier" end
        return true, "ready"
    end

    local function MakeBagCand(bag, slot, invSlot, link, eid, sfx, bagForge, ilvl, name, ibGuid)
        return {
            bag = bag,
            slot = slot,
            invSlot = invSlot,
            ibGuid = ibGuid,
            isEquipped = (invSlot ~= nil),
            isBank = (ibGuid ~= nil),
            link = link,
            eid = eid,
            entry = eid,
            sfx = sfx,
            forge = bagForge,
            ilvl = tonumber(ilvl) or 0,
            name = name or ("#" .. eid),
            key = ibGuid and ("ib:" .. ibGuid .. ":" .. bagForge)
                  or (invSlot and ("eq:" .. invSlot .. ":" .. link .. ":" .. bagForge)
                  or (bag .. ":" .. slot .. ":" .. link .. ":" .. bagForge)),
        }
    end

    local function TryWarmValdrisItem(eid, seenWarm, slotLocs)
        if not eid or eid <= 0 then return seenWarm, false end
        if IsMorKelOrNoRuleItem(eid) then return seenWarm, false end
        if type(AP.ParseItemRecord) == "function" then
            local rec = AP.ParseItemRecord(eid)
            if rec and rec.statsKnown then
                local loc = INV_ID_TO_LOC[rec.inv or 0]
                if not loc or not slotLocs[loc] or (tonumber(rec.quality) or 0) < 2 then
                    return seenWarm, false
                end
            end
        end
        vp.warmAttempts = vp.warmAttempts or {}
        local tries = vp.warmAttempts[eid] or 0
        if tries >= 4 then
            return seenWarm, false
        end
        if seenWarm < 20 and SS._ibWarmCache then
            vp.warmAttempts[eid] = tries + 1
            seenWarm = seenWarm + 1
            SS._ibWarmCache("item:" .. eid)
        end
        return seenWarm, true
    end

    function AP:GetValdrisCandidates(maxTierOverride)
        local wantMax = maxTierOverride and math_floor(tonumber(maxTierOverride) or 3) or AP:GetValdrisMaxTier()
        if wantMax < 1 then wantMax = 1 elseif wantMax > 3 then wantMax = 3 end
        local incEq = (AP:GetSetting("valdrisIncludeEquipped") == true)
        local incBank = (AP:GetSetting("valdrisIncludeBank") ~= false)
        local slotLocs = SS._ibSlotLocs or {}
        local out, totalEligible = {}, 0
        local seenWarm, needsWarm = 0, false

        for bag = 0, 4 do
            local nSlots = (type(GetContainerNumSlots) == "function" and GetContainerNumSlots(bag)) or 0
            for slot = 1, nSlots do
                local link = (type(GetContainerItemLink) == "function") and GetContainerItemLink(bag, slot)
                if link then
                    local locked = false
                    if type(GetContainerItemInfo) == "function" then
                        local _, _, lck = GetContainerItemInfo(bag, slot)
                        locked = (lck == true or lck == 1)
                    end
                    if not locked then
                        local eid = AP.ExtractItemId and AP.ExtractItemId(link)
                        if eid and eid > 0 and (eid < 1702000 or eid > 1702999) then
                            local bagForge = ResolveBagForge(bag, slot, eid)
                            if bagForge < wantMax then
                                local name, _, q, ilvl, _, _, _, _, equipLoc
                                if type(GetItemInfo) == "function" then
                                    name, _, q, ilvl, _, _, _, _, equipLoc = GetItemInfo(link)
                                    if not equipLoc or equipLoc == "" then
                                        name, _, q, ilvl, _, _, _, _, equipLoc = GetItemInfo(eid)
                                    end
                                end
                                if not equipLoc or equipLoc == "" then
                                    local didNeed
                                    seenWarm, didNeed = TryWarmValdrisItem(eid, seenWarm, slotLocs)
                                    if didNeed then needsWarm = true end
                                elseif slotLocs[equipLoc] and (tonumber(q) or 0) >= 2 then
                                    local sfx = AP.ExtractSuffix and AP.ExtractSuffix(link) or 0
                                    if EvalItemForValdris(eid, sfx, bagForge, wantMax, link, equipLoc, bag, slot, nil) then
                                        totalEligible = totalEligible + 1
                                        local cand = MakeBagCand(bag, slot, nil, link, eid, sfx, bagForge, ilvl, name, nil)
                                        if not vp.skip[cand.key] and not vp.blockedByTier[bagForge + 1] then
                                            out[#out + 1] = cand
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        if incBank and type(SS._ibGetItems) == "function" then
            local ibItems = SS._ibGetItems()
            for _, it in ipairs(ibItems) do
                if type(it) == "table" and it.guid and (it.entry or it.link) then
                    local eid = tonumber(it.entry) or (AP.ExtractItemId and AP.ExtractItemId(it.link))
                    if eid and eid > 0 and not IsMorKelOrNoRuleItem(eid) then
                        local fTier = tonumber(it.forge) or (AP.forgeByEntry and AP.forgeByEntry[eid]) or 0
                        if fTier < wantMax then
                            local lk = it.link or ("item:" .. eid)
                            local name, _, q, ilvl, _, _, _, _, equipLoc
                            if type(GetItemInfo) == "function" then
                                name, _, q, ilvl, _, _, _, _, equipLoc = GetItemInfo(lk)
                                if not equipLoc or equipLoc == "" then
                                    name, _, q, ilvl, _, _, _, _, equipLoc = GetItemInfo(eid)
                                end
                            end
                            if not equipLoc or equipLoc == "" then
                                local didNeed
                                seenWarm, didNeed = TryWarmValdrisItem(eid, seenWarm, slotLocs)
                                if didNeed then needsWarm = true end
                            elseif slotLocs[equipLoc] and (tonumber(q) or 0) >= 2 then
                                local sfx = tonumber(it.suffix) or (AP.ExtractSuffix and AP.ExtractSuffix(lk)) or 0
                                if EvalItemForValdris(eid, sfx, fTier, wantMax, lk, equipLoc, nil, nil, nil) then
                                    totalEligible = totalEligible + 1
                                    local cand = MakeBagCand(nil, nil, nil, lk, eid, sfx, fTier, ilvl, name, it.guid)
                                    if not vp.skip[cand.key] and not vp.blockedByTier[fTier + 1] and not vp.bankSpaceFull then
                                        out[#out + 1] = cand
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        if incEq and type(GetInventoryItemLink) == "function" then
            for _, eqDef in ipairs(EQUIP_SLOTS) do
                local link = GetInventoryItemLink("player", eqDef.id)
                if link then
                    local eid = AP.ExtractItemId and AP.ExtractItemId(link)
                    if eid and eid > 0 and (eid < 1702000 or eid > 1702999) then
                        local eqForge = ResolveEquipForge(eqDef.id, eid)
                        if eqForge < wantMax then
                            local name, _, q, ilvl, _, _, _, _, equipLoc
                            if type(GetItemInfo) == "function" then
                                name, _, q, ilvl, _, _, _, _, equipLoc = GetItemInfo(link)
                                if not equipLoc or equipLoc == "" then
                                    name, _, q, ilvl, _, _, _, _, equipLoc = GetItemInfo(eid)
                                end
                            end
                            if equipLoc and slotLocs[equipLoc] and (tonumber(q) or 0) >= 2 then
                                local sfx = AP.ExtractSuffix and AP.ExtractSuffix(link) or 0
                                if EvalItemForValdris(eid, sfx, eqForge, wantMax, link, equipLoc, nil, nil, eqDef.id) then
                                    totalEligible = totalEligible + 1
                                    local cand = MakeBagCand(nil, nil, eqDef.id, link, eid, sfx, eqForge, ilvl, name, nil)
                                    if not vp.skip[cand.key] and not vp.blockedByTier[eqForge + 1] then
                                        out[#out + 1] = cand
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        table.sort(out, function(a, b)
            local sa = a.isBank and 2 or (a.isEquipped and 3 or 1)
            local sb = b.isBank and 2 or (b.isEquipped and 3 or 1)
            if sa ~= sb then return sa < sb end
            if a.forge ~= b.forge then return a.forge < b.forge end
            if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
            if (a.bag or 99) ~= (b.bag or 99) then return (a.bag or 99) < (b.bag or 99) end
            return (a.slot or a.invSlot or a.ibGuid or 0) < (b.slot or b.invSlot or b.ibGuid or 0)
        end)

        return out, totalEligible, needsWarm
    end

    function AP:GetValdrisPickerItems(filterKind, searchText)
        filterKind = filterKind or "all"
        local qStr = (type(searchText) == "string" and searchText ~= "") and AP.Norm(searchText) or nil
        local wantMax = AP:GetValdrisMaxTier()
        local isDisp = IsValdrisDispTabOpen()
        local slotLocs = SS._ibSlotLocs or {}
        local items = {}
        local warmBank = 0

        local function AddEntry(bag, slot, invSlot, slotLabel, link, forge, ibGuid)
            local eid = AP.ExtractItemId and AP.ExtractItemId(link)
            if not eid or eid <= 0 then return end
            local isBank = (ibGuid ~= nil)
            local name, fullLink, qual, ilvl, _, _, _, _, equipLoc, tex
            if type(GetItemInfo) == "function" then
                name, fullLink, qual, ilvl, _, _, _, _, equipLoc, tex = GetItemInfo(link)
                if not name then
                    name, fullLink, qual, ilvl, _, _, _, _, equipLoc, tex = GetItemInfo(eid)
                end
            end
            if not tex and type(GetItemTexture) == "function" then tex = GetItemTexture(link) end
            if isBank and not name and warmBank < 6 and SS._ibWarmCache then
                warmBank = warmBank + 1
                SS._ibWarmCache("item:" .. eid)
            end
            if not isDisp then
                if isBank then
                    if equipLoc and equipLoc ~= "" and (not slotLocs[equipLoc] or (tonumber(qual) or 0) < 2) then
                        return
                    end
                elseif not equipLoc or not slotLocs[equipLoc] or (tonumber(qual) or 0) < 2 then
                    return
                end
            else
                if forge <= 0 and equipLoc and not slotLocs[equipLoc] then
                    return
                end
            end
            local dName = name or ("Предмет #" .. eid)
            if qStr and not AP.Norm(dName):find(qStr, 1, true) then
                return
            end
            local sfx = AP.ExtractSuffix and AP.ExtractSuffix(link) or 0
            local statusTag, statusOrder, statusKey = "", 4, nil
            if isDisp then
                if forge > 0 then
                    statusTag = "|cff38bdf8Т" .. forge .. " (распыл)|r"
                    statusOrder = 1
                else
                    statusTag = "|cff888888Без ковки|r"
                    statusOrder = 5
                end
            else
                local quickSkip, quickWhy = IsMorKelOrNoRuleItem(eid)
                if quickSkip then
                    if quickWhy == "morkel" then
                        return
                    end
                    statusKey = quickWhy or "no_rule"
                    statusTag = "|cff888888Не улучш.|r"
                    statusOrder = 6
                elseif isBank and not name then
                    statusTag = "|cff888888Загрузка...|r"
                    statusKey = "warming"
                    statusOrder = 5
                else
                    local ready, why = EvalItemForValdris(eid, sfx, forge, wantMax, link, equipLoc, bag, slot, invSlot)
                    statusKey = why
                    if ready then
                        statusTag = "|cff40ff40-> " .. (TIER_SHORT[forge + 1] or ("Т" .. (forge + 1))) .. "|r"
                        statusOrder = 1
                    elseif why == "unabsorbed" then
                        statusTag = "|cffffb020Не погл.|r"
                        statusOrder = 2
                    elseif why == "max_tier" then
                        statusTag = "|cff888888Готово (Т" .. forge .. ")|r"
                        statusOrder = 4
                    elseif why == "morkel" then
                        statusTag = "|cffff9f40Другой мастер|r"
                        statusOrder = 5
                    elseif why == "blacklist" then
                        statusTag = "|cffff4040[ЧС]|r"
                        statusOrder = 7
                    else
                        statusTag = "|cff888888Не улучш.|r"
                        statusOrder = 6
                    end
                end
            end
            items[#items + 1] = {
                bag = bag,
                slot = slot,
                invSlot = invSlot,
                ibGuid = ibGuid,
                isEquipped = (invSlot ~= nil),
                isBank = isBank,
                slotLabel = slotLabel,
                link = fullLink or link,
                eid = eid,
                sfx = sfx,
                forge = forge,
                qual = tonumber(qual) or (isBank and 4 or 1),
                ilvl = tonumber(ilvl) or 0,
                name = dName,
                tex = tex or DEFAULT_PICK_ICON,
                statusTag = statusTag,
                statusKey = statusKey,
                statusOrder = statusOrder,
            }
        end

        if filterKind == "all" or filterKind == "equipped" then
            if type(GetInventoryItemLink) == "function" then
                for _, eqDef in ipairs(EQUIP_SLOTS) do
                    local link = GetInventoryItemLink("player", eqDef.id)
                    if link then
                        local eid = AP.ExtractItemId and AP.ExtractItemId(link)
                        local eqForge = ResolveEquipForge(eqDef.id, eid)
                        AddEntry(nil, nil, eqDef.id, eqDef.label, link, eqForge, nil)
                    end
                end
            end
        end

        if filterKind == "all" or filterKind == "bags" then
            for bag = 0, 4 do
                local nSlots = (type(GetContainerNumSlots) == "function" and GetContainerNumSlots(bag)) or 0
                for slot = 1, nSlots do
                    local link = (type(GetContainerItemLink) == "function") and GetContainerItemLink(bag, slot)
                    if link then
                        local eid = AP.ExtractItemId and AP.ExtractItemId(link)
                        local bagForge = ResolveBagForge(bag, slot, eid)
                        AddEntry(bag, slot, nil, "Сумка", link, bagForge, nil)
                    end
                end
            end
        end

        if filterKind == "all" or filterKind == "bank" then
            local ibItems = (type(SS._ibGetItems) == "function") and SS._ibGetItems() or (SS.ib and SS.ib.items) or {}
            for _, it in ipairs(ibItems) do
                if type(it) == "table" and it.guid and (it.entry or it.link) then
                    local eid = tonumber(it.entry) or (AP.ExtractItemId and AP.ExtractItemId(it.link))
                    if eid and eid > 0 then
                        local lk = it.link or ("item:" .. eid)
                        local fTier = tonumber(it.forge) or (AP.forgeByEntry and AP.forgeByEntry[eid]) or 0
                        AddEntry(nil, nil, nil, "Банк вещей", lk, fTier, it.guid)
                    end
                end
            end
        end

        table.sort(items, function(a, b)
            if a.statusOrder ~= b.statusOrder then return a.statusOrder < b.statusOrder end
            local ka = a.isEquipped and 1 or (a.isBank and 3 or 2)
            local kb = b.isEquipped and 1 or (b.isBank and 3 or 2)
            if ka ~= kb then return ka < kb end
            if a.forge ~= b.forge then return a.forge < b.forge end
            if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
            return tostring(a.name) < tostring(b.name)
        end)
        if warmBank > 0 and AP.After and SS.valdrisRefreshPicker then
            AP.After(0.65, SS.valdrisRefreshPicker, "ap_vp_warm_refresh")
        end
        return items
    end

    local function RecordSelectedVisual(bag, slot, link)
        if not bag or not slot or not link then
            vp.lastPicked = nil
            if RefreshValdrisBar then RefreshValdrisBar() end
            return
        end
        local name, _, q, _, _, _, _, _, _, tex
        if type(GetItemInfo) == "function" then
            name, _, q, _, _, _, _, _, _, tex = GetItemInfo(link)
        end
        if not tex and type(GetContainerItemInfo) == "function" then
            tex = GetContainerItemInfo(bag, slot)
        end
        vp.lastPicked = {
            bag = bag,
            slot = slot,
            link = link,
            name = name,
            q = tonumber(q) or 1,
            tex = tex or DEFAULT_PICK_ICON,
        }
        if RefreshValdrisBar then RefreshValdrisBar() end
    end

    local function SelectBagSlotInValdris(bag, slot)
        if not IsValdrisFrameOpen() then
            return false, "Окно улучшения предметов закрыто"
        end
        local link = (type(GetContainerItemLink) == "function") and GetContainerItemLink(bag, slot)
        if not link then
            return false, "В этой ячейке нет предмета"
        end
        ClearCursorSafe()

        local ipf = rawget(_G, "ItemProgressFrame")
        if ipf and ipf.DustLeftInset and type(ipf.DustLeftInset.IsShown) == "function" and ipf.DustLeftInset:IsShown()
           and type(_G.ItemProgress_SetTab) == "function" then
            _G.ItemProgress_SetTab(1)
        end

        RecordSelectedVisual(bag, slot, link)

        local didUI = false
        if IsValdrisDispTabOpen() and rawget(_G, "ItemProgressDispSlot") and type(_G.ItemProgressDispSlot_OnReceiveDrag) == "function" then
            if type(PickupContainerItem) == "function" then PickupContainerItem(bag, slot) end
            pcall(_G.ItemProgressDispSlot_OnReceiveDrag, _G.ItemProgressDispSlot)
            didUI = true
        elseif rawget(_G, "ItemProgressItemSlot") and type(_G.ItemProgressSlot_OnReceiveDrag) == "function" then
            if type(PickupContainerItem) == "function" then PickupContainerItem(bag, slot) end
            pcall(_G.ItemProgressSlot_OnReceiveDrag, _G.ItemProgressItemSlot)
            didUI = true
        end
        ClearCursorSafe()

        if not didUI then
            if IsValdrisDispTabOpen() then
                SendIProgSrv("ACMSG_IPROG_DQ", bag .. ":" .. slot)
            else
                SendIProgSrv("ACMSG_IPROG_QUERY", bag .. ":" .. slot)
            end
        end
        return true, "selected"
    end

    function AP:PickBagItemForValdris(bag, slot)
        if type(SpellIsTargeting) == "function" and SpellIsTargeting() then
            return false, "Курсор занят заклинанием"
        end
        if not IsValdrisDispTabOpen() and type(GetContainerItemLink) == "function" then
            local link = GetContainerItemLink(bag, slot)
            local eid = link and AP.ExtractItemId and AP.ExtractItemId(link)
            if eid then
                local skip, skipWhy = IsMorKelOrNoRuleItem(eid)
                if skip then
                    return false, (skipWhy == "morkel") and "Эту вещь улучшает другой мастер (не Прогрессия)" or "Этот предмет не улучшается в Прогрессии"
                end
            end
        end
        local ok, err = SelectBagSlotInValdris(bag, slot)
        if vpPicker and vpPicker:IsShown() then vpPicker:Hide() end
        return ok, err
    end

    function AP:PickEquippedItemForValdris(invSlot, opts)
        if not IsValdrisFrameOpen() then
            return false, "Откройте окно улучшения (Прогрессия предметов)"
        end
        local busy, why = IsPlayerBusyCombatOrDead()
        if busy then return false, (why == "combat") and "В бою нельзя снимать вещи" or "Персонаж мертв" end
        if type(SpellIsTargeting) == "function" and SpellIsTargeting() then
            return false, "Курсор занят заклинанием"
        end
        if type(CursorHasItem) == "function" and CursorHasItem() then
            return false, "Освободите курсор"
        end
        local link = (type(GetInventoryItemLink) == "function") and GetInventoryItemLink("player", invSlot)
        if not link then
            return false, "Слот пуст"
        end
        local eid = AP.ExtractItemId and AP.ExtractItemId(link)
        if not IsValdrisDispTabOpen() and eid then
            local skip, skipWhy = IsMorKelOrNoRuleItem(eid)
            if skip then
                return false, (skipWhy == "morkel") and "Эту вещь улучшает другой мастер (не Прогрессия)" or "Этот предмет не улучшается в Прогрессии"
            end
        end
        if type(PickupInventoryItem) ~= "function" or type(PickupContainerItem) ~= "function" then
            return false, "API недоступен"
        end
        local fb, fs = FindFreeNormalBagSlot()
        if not fb or not fs then
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[Прогрессия]|r Нет свободного места в обычных сумках, чтобы снять " .. tostring(link))
            end
            return false, "bag_full"
        end

        local now = GetTime()
        local eqForge = ResolveEquipForge(invSlot, eid)
        vp.pauseEquipUntil = now + 12.0
        PickupInventoryItem(invSlot)
        if type(CursorHasItem) ~= "function" or CursorHasItem() then
            PickupContainerItem(fb, fs)
        end
        if type(CursorHasItem) == "function" and CursorHasItem() then
            if type(EquipCursorItem) == "function" then pcall(EquipCursorItem, invSlot) end
            ClearCursorSafe()
            vp.pauseEquipUntil = 0
            return false, "unequip_failed"
        end

        if vpPicker and vpPicker:IsShown() and not (opts and opts.keepPicker) then
            vpPicker:Hide()
        end

        local silent = opts and opts.silent
        local onReady = opts and opts.onReady

        local curLk = (type(GetContainerItemLink) == "function") and GetContainerItemLink(fb, fs)
        if curLk == link or (curLk and eid and AP.ExtractItemId and AP.ExtractItemId(curLk) == eid) then
            vp.pendingUnequip = nil
            AP.forgeBag = AP.forgeBag or {}
            AP.forgeBag[fb] = AP.forgeBag[fb] or {}
            AP.forgeBag[fb][fs] = eqForge
            if not vp.running then
                SelectBagSlotInValdris(fb, fs)
            end
            if not silent and DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[Прогрессия]|r Снято в сумку и выбрано: " .. tostring(link))
            end
            if onReady then pcall(onReady, fb, fs, invSlot) end
            return true, "picked", fb, fs
        end

        vp.pendingUnequip = {
            bag = fb,
            slot = fs,
            invSlot = invSlot,
            link = link,
            eid = eid,
            forge = eqForge,
            at = now,
            silent = silent,
            onReady = onReady,
        }
        vpDrv:Show()
        return true, "waiting_bag", fb, fs
    end

    local function RestoreActiveEquippedItem()
        local r = vp.activeEquippedRestore
        if not r then return false end
        vp.activeEquippedRestore = nil
        local busy = IsPlayerBusyCombatOrDead()
        if busy or (type(CursorHasItem) == "function" and CursorHasItem()) then return false end
        if type(GetInventoryItemLink) == "function" and GetInventoryItemLink("player", r.invSlot) then
            return false
        end
        if type(PickupContainerItem) ~= "function" or type(EquipCursorItem) ~= "function" then return false end

        local bestB, bestS, bestF = nil, nil, -1
        for b = 0, 4 do
            local nS = (type(GetContainerNumSlots) == "function" and GetContainerNumSlots(b)) or 0
            for s = 1, nS do
                local lk = GetContainerItemLink(b, s)
                local e = lk and AP.ExtractItemId and AP.ExtractItemId(lk)
                if e and e == r.entry then
                    local f = ResolveBagForge(b, s, e)
                    if b == r.bag and s == r.slot then
                        bestB, bestS, bestF = b, s, f
                        break
                    elseif f > bestF then
                        bestB, bestS, bestF = b, s, f
                    end
                end
            end
            if bestB == r.bag and bestS == r.slot then break end
        end
        if bestB and bestS then
            PickupContainerItem(bestB, bestS)
            if type(CursorHasItem) ~= "function" or CursorHasItem() then
                EquipCursorItem(r.invSlot)
            end
            ClearCursorSafe()
            if bestF >= 0 then
                AP.forgeEquip = AP.forgeEquip or {}
                AP.forgeEquip[r.invSlot] = bestF
            end
            return true
        end
        return false
    end

    local function CheckPendingUnequip()
        local u = vp.pendingUnequip
        if not u then return false end
        local now = GetTime()
        if (now - (u.at or 0)) > 2.2 then
            vp.pendingUnequip = nil
            if vp.running then AP:ScheduleValdrisStep(0.01) end
            return false
        end
        local ab, as
        local lk = (type(GetContainerItemLink) == "function") and GetContainerItemLink(u.bag, u.slot)
        if lk and (lk == u.link or (u.eid and AP.ExtractItemId and AP.ExtractItemId(lk) == u.eid)) then
            ab, as = u.bag, u.slot
        elseif u.link and type(GetContainerItemLink) == "function" then
            for b = 0, 4 do
                local nS = (type(GetContainerNumSlots) == "function" and GetContainerNumSlots(b)) or 0
                for s = 1, nS do
                    local cl = GetContainerItemLink(b, s)
                    if cl == u.link then
                        ab, as = b, s
                        break
                    end
                end
                if ab then break end
            end
        end
        if ab and as then
            vp.pendingUnequip = nil
            if u.forge ~= nil then
                AP.forgeBag = AP.forgeBag or {}
                AP.forgeBag[ab] = AP.forgeBag[ab] or {}
                AP.forgeBag[ab][as] = u.forge
            end
            if not vp.running then
                SelectBagSlotInValdris(ab, as)
            end
            if not u.silent and DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[Прогрессия]|r Снято в сумку и выбрано: " .. tostring(u.link))
            end
            if u.onReady then pcall(u.onReady, ab, as, u.invSlot) end
            return true
        end
        return false
    end

    local function CheckPendingBankTake()
        local bt = vp.pendingBankTake
        if not bt then return false end
        local now = GetTime()
        if (now - (bt.at or 0)) > 3.2 then
            vp.pendingBankTake = nil
            if vp.running then AP:ScheduleValdrisStep(0.10) end
            return false
        end
        if type(GetContainerNumSlots) ~= "function" or type(GetContainerItemLink) ~= "function" then return false end
        local ab, as, alk
        for b = 0, 4 do
            local nS = GetContainerNumSlots(b) or 0
            for s = 1, nS do
                local lk = GetContainerItemLink(b, s)
                if lk and lk ~= (bt.beforeLinks and bt.beforeLinks[b * 100 + s]) then
                    local eid = AP.ExtractItemId and AP.ExtractItemId(lk)
                    if (bt.entry and eid == bt.entry) or (bt.link and lk == bt.link) then
                        ab, as, alk = b, s, lk
                        break
                    end
                end
            end
            if ab then break end
        end
        if ab and as then
            vp.pendingBankTake = nil
            AP.forgeBag = AP.forgeBag or {}
            AP.forgeBag[ab] = AP.forgeBag[ab] or {}
            if bt.forge and bt.forge >= 0 then
                AP.forgeBag[ab][as] = bt.forge
            end
            if not vp.running then
                SelectBagSlotInValdris(ab, as)
            end
            if not bt.silent and DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[Прогрессия]|r Забрано из Банка вещей и выбрано: " .. tostring(alk or bt.link))
            end
            if bt.onReady then pcall(bt.onReady, ab, as, bt.entry, alk or bt.link) end
            return true
        end
        return false
    end

    local function ReturnActiveBankItem()
        local br = vp.activeBankReturn
        if not br then return false end
        vp.activeBankReturn = nil
        local busy = IsPlayerBusyCombatOrDead()
        if busy or type(SS._ibSendAddon) ~= "function" then return false end
        if type(GetContainerNumSlots) ~= "function" or type(GetContainerItemLink) ~= "function" then return false end
        local b, s, lk
        if br.bag and br.slot then
            local cl = GetContainerItemLink(br.bag, br.slot)
            if cl and AP.ExtractItemId and AP.ExtractItemId(cl) == br.entry then
                b, s, lk = br.bag, br.slot, cl
            end
        end
        if not b then
            for cb = 0, 4 do
                local nS = GetContainerNumSlots(cb) or 0
                for cs = 1, nS do
                    local cl = GetContainerItemLink(cb, cs)
                    if cl and AP.ExtractItemId and AP.ExtractItemId(cl) == br.entry then
                        b, s, lk = cb, cs, cl
                        break
                    end
                end
                if b then break end
            end
        end
        if not b or not s then return false end
        local srvBag = (b == 0) and 255 or (18 + b)
        local srvSlot = (b == 0) and (22 + s) or (s - 1)
        if SS._ibSendAddon("ACMSG_IB_PUT", srvBag .. ":" .. srvSlot) then
            vp.pendingBankReturn = { bag = b, slot = s, entry = br.entry, link = lk, at = GetTime() }
            return true
        end
        return false
    end

    local function CheckPendingBankReturn()
        local pr = vp.pendingBankReturn
        if not pr then return false end
        local now = GetTime()
        if (now - (pr.at or 0)) > 1.4 then
            vp.pendingBankReturn = nil
            return false
        end
        local lk = (type(GetContainerItemLink) == "function") and GetContainerItemLink(pr.bag, pr.slot)
        if not lk or (pr.entry and AP.ExtractItemId and AP.ExtractItemId(lk) ~= pr.entry) then
            vp.pendingBankReturn = nil
            return true
        end
        return false
    end

    function AP:PickBankItemForValdris(guid, link, forge, opts)
        if not IsValdrisFrameOpen() then
            return false, "Откройте окно улучшения (Прогрессия предметов)"
        end
        local busy, why = IsPlayerBusyCombatOrDead()
        if busy then return false, (why == "combat") and "В бою недоступно" or "Персонаж мертв" end
        if type(CursorHasItem) == "function" and CursorHasItem() then
            return false, "Освободите курсор"
        end
        guid = tonumber(guid)
        if not guid or guid <= 0 then return false, "Некорректный предмет" end
        local eid = AP.ExtractItemId and AP.ExtractItemId(link)
        if not IsValdrisDispTabOpen() and eid then
            local skip, skipWhy = IsMorKelOrNoRuleItem(eid)
            if skip then
                return false, (skipWhy == "morkel") and "Эту вещь улучшает другой мастер (не Прогрессия)" or "Этот предмет не улучшается в Прогрессии"
            end
        end
        if vp.pendingBankTake and (GetTime() - (vp.pendingBankTake.at or 0)) <= 3.2 then
            return false, "Ожидается забор вещи из Банка вещей"
        end
        local fb, fs = FindFreeNormalBagSlot()
        if not fb or not fs then
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[Прогрессия]|r Нет свободного места в обычных сумках, чтобы забрать вещь из Банка вещей.")
            end
            return false, "bag_full"
        end
        local beforeLinks = {}
        if type(GetContainerNumSlots) == "function" and type(GetContainerItemLink) == "function" then
            for b = 0, 4 do
                local nS = GetContainerNumSlots(b) or 0
                for s = 1, nS do
                    local lk = GetContainerItemLink(b, s)
                    if lk then beforeLinks[b * 100 + s] = lk end
                end
            end
        end
        local eid = AP.ExtractItemId and AP.ExtractItemId(link)
        vp.pauseEquipUntil = GetTime() + 12.0
        vp.pendingBankTake = {
            guid = guid,
            entry = eid,
            forge = tonumber(forge) or 0,
            link = link,
            beforeLinks = beforeLinks,
            at = GetTime(),
            silent = opts and opts.silent,
            onReady = opts and opts.onReady,
        }
        if not AP:TakeItemBankItem(guid) then
            vp.pendingBankTake = nil
            return false, "Ошибка запроса предмета из Банка вещей"
        end
        if vpPicker and vpPicker:IsShown() and not (opts and opts.keepPicker) then vpPicker:Hide() end
        if CheckPendingBankTake() then
            return true, "picked"
        end
        vpDrv:Show()
        return true, "waiting_bag"
    end

    local function ResolvePendingRelocate()
        local pr = vp.pendingRelocate
        if not pr then return false end
        local now = GetTime()
        if (now - (pr.at or 0)) > 2.5 then
            vp.pendingRelocate = nil
            return false
        end
        local lkR = (pr.rBag and pr.rSlot and type(GetContainerItemLink) == "function") and GetContainerItemLink(pr.rBag, pr.rSlot)
        if lkR and AP.ExtractItemId and AP.ExtractItemId(lkR) == pr.entry then
            AP.forgeBag = AP.forgeBag or {}
            AP.forgeBag[pr.rBag] = AP.forgeBag[pr.rBag] or {}
            AP.forgeBag[pr.rBag][pr.rSlot] = pr.to
            vp.pendingRelocate = nil
            return true
        end
        return false
    end

    function AP:GetValdrisUpgradeSummary(fastOnly)
        local cands, totalEligible, needsWarm = AP:GetValdrisCandidates()
        return {
            running = vp.running == true,
            windowOpen = IsValdrisFrameOpen(),
            maxTier = AP:GetValdrisMaxTier(),
            autoOpen = (AP:GetSetting("valdrisAutoOpen") == true),
            includeEquipped = (AP:GetSetting("valdrisIncludeEquipped") == true),
            includeBank = (AP:GetSetting("valdrisIncludeBank") ~= false),
            eligibleCount = #cands,
            totalEligible = totalEligible or 0,
            needsWarm = needsWarm == true,
            doneCount = vp.doneCount or 0,
            lastName = vp.lastName,
            lastError = vp.lastError,
            nextCand = cands[1],
        }
    end

    RefreshValdrisBar = function()
        if not vpBar then return end
        local open = IsValdrisFrameOpen()
        if not open then
            vpBar:Hide()
            if vpPicker then vpPicker:Hide() end
            return
        end
        vp.lastBarUiAt = GetTime()
        vpBar:Show()
        local sum = AP:GetValdrisUpgradeSummary(false)
        local maxT = sum.maxTier or 3
        if vpBar.pickBtn then
            local lp = vp.lastPicked
            local curLk = (lp and lp.bag and lp.slot and type(GetContainerItemLink) == "function")
                and GetContainerItemLink(lp.bag, lp.slot) or nil
            if lp and curLk == lp.link then
                local lpEid = AP.ExtractItemId and AP.ExtractItemId(curLk)
                local lpForge = ResolveBagForge(lp.bag, lp.slot, lpEid)
                if vpBar.pickBtn.icon then vpBar.pickBtn.icon:SetTexture(lp.tex or DEFAULT_PICK_ICON) end
                ApplyForgeIconVisual(vpBar.pickBtn.iconBox, vpBar.pickBtn.forgeBadge, nil, lpForge, lp.q, false)
                if vpBar.pickBtn.label then vpBar.pickBtn.label:SetText(CropText(lp.name or "Выбрано", 17)) end
            else
                if vpBar.pickBtn.icon then vpBar.pickBtn.icon:SetTexture(DEFAULT_PICK_ICON) end
                ApplyForgeIconVisual(vpBar.pickBtn.iconBox, vpBar.pickBtn.forgeBadge, nil, 0, nil, false)
                if vpBar.pickBtn.label then vpBar.pickBtn.label:SetText("Выбрать вещь") end
            end
        end
        if vpBar.tierBtn and vpBar.tierBtn.label then
            vpBar.tierBtn.label:SetText("Цель: " .. (TIER_SHORT[maxT] or tostring(maxT)))
        end
        if vpBar.incBkChk then
            local bkOn = (AP:GetSetting("valdrisIncludeBank") ~= false)
            vpBar.incBkChk._mk:SetText(bkOn and "|cff40ff40V|r" or "")
            PS.StyleBox(vpBar.incBkChk._box, bkOn and 0.75 or 0.55, bkOn)
        end
        if vpBar.incEqChk then
            local eqOn = (AP:GetSetting("valdrisIncludeEquipped") == true)
            vpBar.incEqChk._mk:SetText(eqOn and "|cff40ff40V|r" or "")
            PS.StyleBox(vpBar.incEqChk._box, eqOn and 0.75 or 0.55, eqOn)
        end
        if vpBar.autoChk then
            local on = (AP:GetSetting("valdrisAutoOpen") == true)
            vpBar.autoChk._mk:SetText(on and "|cff40ff40V|r" or "")
            PS.StyleBox(vpBar.autoChk._box, on and 0.75 or 0.55, on)
        end
        if vpBar.goBtn and vpBar.goBtn.label then
            if vp.running then
                PS.PaintBtn(vpBar.goBtn, "red")
                local now = GetTime()
                local wait = (vp.nextDoAt or 0) - now
                if wait > 0.2 then
                    vpBar.goBtn.label:SetText(string.format("Стоп %dс (%d)", math.ceil(wait), vp.doneCount or 0))
                elseif (vp.warmRetries or 0) > 0 and not vp.inFlightQuery and not vp.inFlightDo then
                    vpBar.goBtn.label:SetText("Кэш (" .. (vp.doneCount or 0) .. ")...")
                else
                    vpBar.goBtn.label:SetText("Стоп (" .. (vp.doneCount or 0) .. ")")
                end
            else
                local cnt = sum.totalEligible or 0
                PS.PaintBtn(vpBar.goBtn, cnt > 0 and "green" or "dark")
                vpBar.goBtn.label:SetText("Улучшать (" .. cnt .. ")")
            end
        end
        if sum.needsWarm and not vp.running and AP.After and not vp.barWarmScheduled and (vp.barWarmCount or 0) < 3 then
            vp.barWarmScheduled = true
            vp.barWarmCount = (vp.barWarmCount or 0) + 1
            AP.After(0.75, function()
                vp.barWarmScheduled = false
                if IsValdrisFrameOpen() and not vp.running then RefreshValdrisBar() end
            end, "ap_vp_bar_warm")
        end
    end

    function AP:StopValdrisAutoUpgrade(why)
        local wasRunning = vp.running == true
        vp.running = false
        vp.pending = false
        vp.inFlightQuery = nil
        vp.inFlightDo = nil
        vp.pendingRelocate = nil
        if why ~= "combat" and why ~= "dead" then
            RestoreActiveEquippedItem()
            ReturnActiveBankItem()
        end
        if not vp.pendingUnequip and not vp.pendingBankTake and not vp.pendingBankReturn then vpDrv:Hide() end
        RefreshValdrisBar()
        if wasRunning and DEFAULT_CHAT_FRAME and why then
            if why == "done" then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff40ff40[Прогрессия]|r Готово! Улучшено предметов: %d.", vp.doneCount or 0))
            elseif why == "combat" then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[Прогрессия]|r Автоулучшение остановлено (вход в бой).")
            elseif why == "user" then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff38bdf8[Прогрессия]|r Автоулучшение остановлено (улучшено: %d).", vp.doneCount or 0))
            elseif why ~= "closed" then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[Прогрессия]|r Остановлено: " .. tostring(why))
            end
        end
        if AP:GetSetting("ibAutoEquip") == true and type(AP.ScheduleItemBankAutoEquip) == "function" then
            AP:ScheduleItemBankAutoEquip(0.35)
        end
        AP:Fire("SERVER_SYNC_UPDATED", "VALDRIS_STOP")
    end

    function AP:ScheduleValdrisStep(delay)
        if not vp.running then
            vp.pending = false
            if not vp.pendingUnequip and not vp.pendingBankTake and not vp.pendingBankReturn then vpDrv:Hide() end
            return false
        end
        local now = GetTime()
        local targetAt = now + (delay or 0.15)
        if not vp.pending or targetAt < (vp.scheduledAt or 0) or (vp.scheduledAt or 0) <= now then
            vp.scheduledAt = targetAt
        end
        vp.pending = true
        vpDrv:Show()
        return true
    end

    function AP:RunValdrisStep()
        if not vp.running then return false, "stopped" end
        if not IsValdrisFrameOpen() then
            AP:StopValdrisAutoUpgrade("closed")
            return false, "closed"
        end
        if vp.hello and vp.hello.enabled == false then
            AP:StopValdrisAutoUpgrade("Ковка выключена сервером")
            return false, "disabled"
        end
        local busy, why = IsPlayerBusyCombatOrDead()
        if busy then
            AP:StopValdrisAutoUpgrade(why == "combat" and "combat" or "Персонаж мертв")
            return false, why
        end

        if vp.pendingUnequip then
            if CheckPendingUnequip() then
                AP:ScheduleValdrisStep(0.01)
            else
                AP:ScheduleValdrisStep(0.08)
            end
            return false, "unequipping"
        end
        if vp.pendingBankTake then
            if CheckPendingBankTake() then
                AP:ScheduleValdrisStep(0.01)
            else
                AP:ScheduleValdrisStep(0.08)
            end
            return false, "bank_taking"
        end
        if vp.pendingBankReturn then
            if not CheckPendingBankReturn() then
                AP:ScheduleValdrisStep(0.08)
                return false, "bank_returning"
            end
        end
        if vp.pendingRelocate then
            if ResolvePendingRelocate() then
                AP:ScheduleValdrisStep(0.01)
            else
                AP:ScheduleValdrisStep(0.08)
            end
            return false, "relocating"
        end

        local now = GetTime()
        if vp.inFlightDo then
            if (now - (vp.inFlightDo.at or 0)) < 5.0 then
                AP:ScheduleValdrisStep(0.20)
                return false, "in_flight_do"
            end
            vp.skip[vp.inFlightDo.key] = "timeout"
            vp.inFlightDo = nil
        end
        if vp.inFlightQuery then
            if (now - (vp.inFlightQuery.at or 0)) < 2.2 then
                AP:ScheduleValdrisStep(0.15)
                return false, "in_flight_query"
            end
            vp.skip[vp.inFlightQuery.key] = "q_timeout"
            vp.inFlightQuery = nil
        end

        local cands, _, needsWarm = AP:GetValdrisCandidates()
        local cand = cands[1]
        if vp.activeEquippedRestore then
            local ar = vp.activeEquippedRestore
            if not cand or cand.isEquipped or cand.isBank or cand.eid ~= ar.entry then
                RestoreActiveEquippedItem()
                cands, _, needsWarm = AP:GetValdrisCandidates()
                cand = cands[1]
            end
        end
        if vp.activeBankReturn then
            local br = vp.activeBankReturn
            if not cand or cand.isBank or cand.isEquipped or cand.eid ~= br.entry then
                if ReturnActiveBankItem() then
                    AP:ScheduleValdrisStep(0.08)
                    return false, "bank_returning"
                end
                cands, _, needsWarm = AP:GetValdrisCandidates()
                cand = cands[1]
            end
        end

        if not cand then
            if needsWarm and (vp.warmRetries or 0) < 6 then
                vp.warmRetries = (vp.warmRetries or 0) + 1
                if vp.warmRetries == 1 and DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[Прогрессия]|r Загрузка кэша предметов...")
                end
                AP:ScheduleValdrisStep(0.50)
                RefreshValdrisBar()
                return true, "warming"
            end
            AP:StopValdrisAutoUpgrade((vp.doneCount or 0) > 0 and "done" or "Нет вещей, готовых к улучшению")
            return false, "done"
        end
        vp.warmRetries = 0

        if cand.isBank then
            local okBk, resBk = AP:PickBankItemForValdris(cand.ibGuid, cand.link, cand.forge, {
                silent = true,
                keepPicker = true,
                onReady = function(ab, as, eid)
                    vp.activeBankReturn = { entry = eid, bag = ab, slot = as, link = cand.link }
                    if vp.running then AP:ScheduleValdrisStep(0.01) end
                end,
            })
            if not okBk then
                if resBk == "bag_full" then
                    vp.bankSpaceFull = true
                else
                    vp.skip[cand.key] = resBk or "bank_take_err"
                end
                AP:ScheduleValdrisStep(0.01)
                return false, resBk
            end
            AP:ScheduleValdrisStep((resBk == "picked") and 0.01 or 0.08)
            return true, "bank_take", cand
        end

        if cand.isEquipped then
            local okEq, resEq = AP:PickEquippedItemForValdris(cand.invSlot, {
                silent = true,
                keepPicker = true,
                onReady = function(fb, fs, origInv)
                    vp.activeEquippedRestore = { invSlot = origInv, entry = cand.eid, bag = fb, slot = fs }
                    if vp.running then AP:ScheduleValdrisStep(0.01) end
                end,
            })
            if not okEq then
                vp.skip[cand.key] = resEq or "unequip_err"
                AP:ScheduleValdrisStep(0.01)
                return false, resEq
            end
            AP:ScheduleValdrisStep((resEq == "picked") and 0.01 or 0.08)
            return true, "unequip", cand
        end

        local rec = vp.readyInfo[cand.key]
        if not rec then
            local sent = SendIProgSrv("ACMSG_IPROG_QUERY", cand.bag .. ":" .. cand.slot)
            if not sent then
                AP:StopValdrisAutoUpgrade("Ошибка отправки запроса")
                return false, "send_failed"
            end
            vp.inFlightQuery = { key = cand.key, bag = cand.bag, slot = cand.slot, link = cand.link, at = now }
            AP:ScheduleValdrisStep(0.25)
            RefreshValdrisBar()
            return true, "query", cand
        end

        local curLk = (type(GetContainerItemLink) == "function") and GetContainerItemLink(cand.bag, cand.slot)
        if curLk ~= cand.link or not rec.guid or rec.guid <= 0 then
            vp.readyInfo[cand.key] = nil
            AP:ScheduleValdrisStep(0.01)
            return false, "stale_slot"
        end

        if now < (vp.nextDoAt or 0) then
            AP:ScheduleValdrisStep(math_max(0.01, (vp.nextDoAt or now) - now))
            RefreshValdrisBar()
            return false, "throttle_wait"
        end

        local sent = SendIProgSrv("ACMSG_IPROG_DO", rec.bag .. ":" .. rec.slot .. ":" .. rec.guid)
        if not sent then
            AP:StopValdrisAutoUpgrade("Ошибка отправки улучшения")
            return false, "send_failed"
        end
        vp.lastDoSentAt = now
        vp.inFlightDo = {
            key = cand.key,
            bag = rec.bag,
            slot = rec.slot,
            guid = rec.guid,
            entry = rec.entry,
            from = rec.cur,
            to = rec.next,
            name = cand.name,
            link = cand.link,
            at = now,
        }
        vp.lastName = cand.name
        AP:ScheduleValdrisStep(0.35)
        RefreshValdrisBar()
        return true, "do", cand
    end

    function AP:StartValdrisAutoUpgrade()
        if not IsValdrisFrameOpen() then
            return false, "Откройте окно улучшения (Прогрессия предметов)"
        end
        local busy = IsPlayerBusyCombatOrDead()
        if busy then return false, "В бою недоступно" end
        local ipf = rawget(_G, "ItemProgressFrame")
        if IsValdrisDispTabOpen() and type(_G.ItemProgress_SetTab) == "function" then
            pcall(_G.ItemProgress_SetTab, 1)
        elseif ipf and ipf.DustLeftInset and type(ipf.DustLeftInset.IsShown) == "function" and ipf.DustLeftInset:IsShown()
           and type(_G.ItemProgress_SetTab) == "function" then
            pcall(_G.ItemProgress_SetTab, 1)
        end
        vp.running = true
        vp.skip = {}
        vp.blockedByTier = {}
        vp.readyInfo = {}
        if type(vp.passiveInfo) == "table" and type(GetContainerItemLink) == "function" then
            local now = GetTime()
            local maxT = AP:GetValdrisMaxTier()
            for slotKey, p in pairs(vp.passiveInfo) do
                local lkNow = GetContainerItemLink(p.bag, p.slot)
                if lkNow and lkNow == p.link and (now - (p.at or 0)) < 25 and (p.cur or 0) < maxT and (p.nxt or 0) <= maxT then
                    vp.readyInfo[p.bag .. ":" .. p.slot .. ":" .. lkNow .. ":" .. (p.cur or 0)] = {
                        bag = p.bag,
                        slot = p.slot,
                        guid = p.guid,
                        entry = p.entry,
                        suffix = p.suffix,
                        cur = p.cur,
                        next = p.nxt,
                    }
                else
                    vp.passiveInfo[slotKey] = nil
                end
            end
        end
        vp.doneCount = 0
        vp.warmRetries = 0
        vp.warmAttempts = {}
        vp.lastError = nil
        vp.inFlightQuery = nil
        vp.inFlightDo = nil
        vp.activeEquippedRestore = nil
        vp.activeBankReturn = nil
        vp.pendingBankReturn = nil
        vp.bankSpaceFull = false
        if vpPicker and vpPicker:IsShown() then vpPicker:Hide() end
        RefreshValdrisBar()
        return AP:RunValdrisStep()
    end

    function SS.onIProgMsg(prefix, msg)
        SS.tryHookValdris()
        msg = tostring(msg or "")
        local now = GetTime()
        if prefix == "ASMSG_IPROG_OPEN" then
            local mode, preSlot = strsplit("\t", msg)
            if tonumber(mode) == 0 then
                AP:StopValdrisAutoUpgrade("closed")
                return
            end
            if type(preSlot) == "string" and preSlot:find(":", 1, true) then
                local pb, ps = strsplit(":", preSlot)
                pb, ps = tonumber(pb), tonumber(ps)
                if pb and ps then
                    local lk = (type(GetContainerItemLink) == "function") and GetContainerItemLink(pb, ps)
                    if lk then RecordSelectedVisual(pb, ps, lk) end
                end
            end
            AP.After(0.05, function()
                SS.tryHookValdris()
                RefreshValdrisBar()
                if AP:GetSetting("valdrisAutoOpen") == true and IsValdrisFrameOpen() and not vp.running then
                    AP.After(0.25, function()
                        if IsValdrisFrameOpen() and not vp.running and AP:GetSetting("valdrisAutoOpen") == true then
                            AP:StartValdrisAutoUpgrade()
                        end
                    end, "ap_valdris_autoopen")
                end
            end, "ap_valdris_open")
        elseif prefix == "ASMSG_IPROG_HELLO" then
            local proto, maxT, thrMs, rules, en = strsplit(":", msg)
            local thr = tonumber(thrMs) or 3000
            vp.hello = {
                proto = tonumber(proto) or 0,
                maxTier = tonumber(maxT) or 3,
                throttleMs = thr,
                rules = tonumber(rules) or 0,
                enabled = (tonumber(en) or 0) ~= 0,
            }
            vp.throttleMargin = vp.throttleMargin or 0.04
            vp.throttleSec = (thr > 0) and (thr / 1000 + vp.throttleMargin) or 0.03
            RefreshValdrisBar()
        elseif prefix == "ASMSG_IPROG_INFO" then
            local head = strsplit("\t", msg)
            if not head then return end
            local bag, slot, guid, entry, sfx, cur, nxt, _, st = strsplit(":", head)
            bag, slot, st = tonumber(bag), tonumber(slot), tonumber(st)
            if not bag or not slot or not st then return end
            local curN, nxtN = tonumber(cur) or 0, tonumber(nxt) or 0
            local guidN = tonumber(guid) or 0
            local rBag, rSlot = NormalizeIProgBagSlot(bag, slot)
            local linkHere = (rBag and rSlot and type(GetContainerItemLink) == "function") and GetContainerItemLink(rBag, rSlot) or nil
            local entryNum = tonumber(entry) or 0
            if (st == 21 or st == 9 or st == 10) and entryNum > 0 then
                SaveValdrisKnownSkip(entryNum, st)
            end
            if linkHere and entryNum > 0 and AP.ExtractItemId and AP.ExtractItemId(linkHere) == entryNum and st ~= 9 and st ~= 10 and st ~= 21 then
                AP.forgeBag = AP.forgeBag or {}
                AP.forgeBag[rBag] = AP.forgeBag[rBag] or {}
                AP.forgeBag[rBag][rSlot] = curN
                if st == 0 and guidN > 0 then
                    vp.passiveInfo = vp.passiveInfo or {}
                    vp.passiveInfo[rBag .. ":" .. rSlot] = {
                        bag = rBag,
                        slot = rSlot,
                        guid = guidN,
                        entry = entryNum,
                        suffix = tonumber(sfx) or 0,
                        cur = curN,
                        nxt = nxtN,
                        link = linkHere,
                        at = now,
                    }
                end
            end
            local q = vp.inFlightQuery
            if not vp.running or not q or q.bag ~= rBag or q.slot ~= rSlot then
                RefreshValdrisBar()
                return
            end
            vp.inFlightQuery = nil
            local maxT = AP:GetValdrisMaxTier()
            if st == 0 then
                if curN < maxT and nxtN <= maxT then
                    vp.readyInfo[q.key] = {
                        bag = rBag,
                        slot = rSlot,
                        guid = guidN,
                        entry = entryNum,
                        suffix = tonumber(sfx) or 0,
                        cur = curN,
                        next = nxtN,
                    }
                    if now >= (vp.nextDoAt or 0) then
                        AP:RunValdrisStep()
                    else
                        AP:ScheduleValdrisStep(math_max(0.01, (vp.nextDoAt or now) - now))
                    end
                else
                    vp.skip[q.key] = "max_tier"
                    AP:ScheduleValdrisStep(0.01)
                end
            elseif st == 2 then
                local thr = (vp.hello and vp.hello.throttleMs) or 3000
                vp.throttleMargin = math.min(0.25, (vp.throttleMargin or 0.04) + 0.06)
                vp.throttleSec = (thr > 0) and (thr / 1000 + vp.throttleMargin) or 0.03
                vp.nextDoAt = math_max(vp.nextDoAt or 0, now + 0.25)
                AP:ScheduleValdrisStep(0.25)
            elseif st == 3 then
                vp.nextDoAt = math_max(vp.nextDoAt or 0, now + 0.20)
                AP:ScheduleValdrisStep(0.20)
            elseif st == 13 then
                local needTier = (nxtN > 0) and nxtN or (curN + 1)
                vp.blockedByTier[needTier] = true
                vp.skip[q.key] = 13
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffd200[Прогрессия]|r Не хватает ресурсов для ступени %d - пропускаю.", needTier))
                end
                AP:ScheduleValdrisStep(0.01)
            else
                vp.skip[q.key] = st
                AP:ScheduleValdrisStep(0.01)
            end
        elseif prefix == "ASMSG_IPROG_RESULT" then
            local head, text = strsplit("\t", msg)
            local st, bag, slot, entry, from, to = strsplit(":", head or "")
            st = tonumber(st)
            bag, slot = tonumber(bag), tonumber(slot)
            entry = tonumber(entry) or 0
            from, to = tonumber(from) or 0, tonumber(to) or 0
            local d = vp.inFlightDo
            if not d then return end
            vp.inFlightDo = nil
            if st == 0 then
                vp.doneCount = (vp.doneCount or 0) + 1
                local thrSec = vp.throttleSec or 3.04
                local refAt = (d and d.at) or vp.lastDoSentAt or now
                vp.nextDoAt = math_max(now, refAt + thrSec)
                vp.readyInfo = {}
                local rBag, rSlot = NormalizeIProgBagSlot(bag, slot)
                rBag = rBag or d.bag
                rSlot = rSlot or d.slot
                if vp.passiveInfo then
                    if d.bag and d.slot then vp.passiveInfo[d.bag .. ":" .. d.slot] = nil end
                    if rBag and rSlot then vp.passiveInfo[rBag .. ":" .. rSlot] = nil end
                end
                AP.forgeBag = AP.forgeBag or {}
                -- Clear stale tier if recreated item moved out of old slot
                local oldLk = (d.bag and d.slot and type(GetContainerItemLink) == "function") and GetContainerItemLink(d.bag, d.slot) or nil
                if d.bag and d.slot and (not oldLk or (entry > 0 and AP.ExtractItemId and AP.ExtractItemId(oldLk) ~= entry)) then
                    if AP.forgeBag[d.bag] then AP.forgeBag[d.bag][d.slot] = nil end
                end
                local newLk = (rBag and rSlot and type(GetContainerItemLink) == "function") and GetContainerItemLink(rBag, rSlot) or nil
                if rBag and rSlot and newLk and (entry == 0 or not AP.ExtractItemId or AP.ExtractItemId(newLk) == entry) then
                    AP.forgeBag[rBag] = AP.forgeBag[rBag] or {}
                    AP.forgeBag[rBag][rSlot] = to
                    vp.pendingRelocate = nil
                    if vp.activeEquippedRestore and vp.activeEquippedRestore.entry == entry then
                        vp.activeEquippedRestore.bag = rBag
                        vp.activeEquippedRestore.slot = rSlot
                    end
                    if vp.activeBankReturn and vp.activeBankReturn.entry == entry then
                        vp.activeBankReturn.bag = rBag
                        vp.activeBankReturn.slot = rSlot
                        vp.activeBankReturn.link = newLk or vp.activeBankReturn.link
                    end
                elseif entry > 0 then
                    vp.pendingRelocate = { entry = entry, fromBag = d.bag, fromSlot = d.slot, rBag = rBag, rSlot = rSlot, to = to, at = now }
                end
                local slotPfx = (d.bag or 0) .. ":" .. (d.slot or 0) .. ":"
                for k in pairs(vp.skip) do
                    if k:sub(1, #slotPfx) == slotPfx then vp.skip[k] = nil end
                end
                if entry > 0 then
                    if AP.InvalidateItemStatus then AP:InvalidateItemStatus(entry) end
                    if AP.InvalidateZoneCache then AP:InvalidateZoneCache(nil) end
                end
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff40ff40[Прогрессия]|r +%d: %s (%d -> %d)", vp.doneCount, tostring(d.link or d.name or entry), from, to))
                end
                RefreshValdrisBar()
                if vp.running then
                    AP:ScheduleValdrisStep(vp.pendingRelocate and 0.05 or 0.01)
                end
            elseif st == 2 then
                local thr = (vp.hello and vp.hello.throttleMs) or 3000
                vp.throttleMargin = math.min(0.25, (vp.throttleMargin or 0.04) + 0.06)
                vp.throttleSec = (thr > 0) and (thr / 1000 + vp.throttleMargin) or 0.03
                vp.nextDoAt = now + 0.28
                if vp.running then AP:ScheduleValdrisStep(0.28) end
            elseif st == 13 then
                local needTier = (to > 0) and to or ((from or 0) + 1)
                vp.blockedByTier[needTier] = true
                vp.skip[d.key] = 13
                vp.lastError = (text and text ~= "") and text or "Не хватает ресурсов"
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[Прогрессия]|r " .. vp.lastError .. " (пропускаю ступень " .. needTier .. ").")
                end
                if vp.running then AP:ScheduleValdrisStep(0.01) end
            else
                vp.skip[d.key] = st or "err"
                vp.lastError = (text and text ~= "") and text or ("Код " .. tostring(st))
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff8040[Прогрессия]|r Пропуск " .. tostring(d.name or entry) .. ": " .. vp.lastError)
                end
                if vp.running then AP:ScheduleValdrisStep(0.01) end
            end
        end
    end

    function SS.onValdrisBagUpdate()
        if not IsValdrisFrameOpen() then return end
        ResolvePendingRelocate()
        CheckPendingUnequip()
        CheckPendingBankTake()
        CheckPendingBankReturn()
        RefreshValdrisBar()
        if vpPicker and vpPicker:IsShown() and RefreshValdrisPicker then RefreshValdrisPicker() end
        if vp.running then
            AP:ScheduleValdrisStep(0.01)
        end
    end

    local function EnsureValdrisPicker(ipf, anchorBtn)
        if vpPicker then return vpPicker end
        local pf = CreateFrame("Frame", "AP_ValdrisPickerFrame", ipf)
        pf:SetSize(486, 352)
        pf:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -4)
        pf:SetFrameStrata("DIALOG")
        pf:SetFrameLevel((ipf.GetFrameLevel and ipf:GetFrameLevel() or 1) + 30)
        pf:EnableMouse(true)
        pf:SetClampedToScreen(true)
        pf:Hide()
        PS.StyleBox(pf, 0.96, true)

        local title = pf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 10, -8)
        title:SetText("|cffffd200Выбор предмета для улучшения|r")

        local closeBtn = CreateFrame("Button", nil, pf)
        closeBtn:SetPoint("TOPRIGHT", -6, -6)
        PS.StyleClose(closeBtn, 20)
        closeBtn:SetScript("OnClick", function() pf:Hide() end)

        pf.filterKind = "all"
        pf.offset = 0
        pf.listData = {}

        local fBtns = {}
        local tabs = {
            { k = "all", txt = "Все", w = 42 },
            { k = "bags", txt = "Сумки", w = 56 },
            { k = "equipped", txt = "Надетые", w = 64 },
            { k = "bank", txt = "Банк вещей", w = 82 },
        }
        local prevTab = nil
        for _, td in ipairs(tabs) do
            local b = PS.MakeBtn(pf, td.w, 20, td.txt, "dark")
            if prevTab then
                b:SetPoint("LEFT", prevTab, "RIGHT", 3, 0)
            else
                b:SetPoint("TOPLEFT", 10, -30)
            end
            b.key = td.k
            b:SetScript("OnClick", function(self)
                pf.filterKind = self.key
                pf.offset = 0
                RefreshValdrisPicker()
            end)
            fBtns[#fBtns + 1] = b
            prevTab = b
        end
        pf.filterBtns = fBtns

        local srchBg = CreateFrame("Frame", nil, pf)
        srchBg:SetSize(218, 20)
        srchBg:SetPoint("TOPRIGHT", -10, -30)
        PS.StyleBox(srchBg, 0.75, false)
        local srch = CreateFrame("EditBox", nil, srchBg)
        srch:SetPoint("TOPLEFT", 5, -2)
        srch:SetPoint("BOTTOMRIGHT", -5, 2)
        srch:SetAutoFocus(false)
        srch:SetFontObject(GameFontHighlightSmall)
        srch:SetScript("OnEscapePressed", function(self) self:ClearFocus(); pf:Hide() end)
        srch:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        srch:SetScript("OnTextChanged", function()
            pf.offset = 0
            RefreshValdrisPicker()
        end)
        pf.searchBox = srch

        local emptyFs = pf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        emptyFs:SetPoint("CENTER", 0, -10)
        emptyFs:SetText("Нет подходящих вещей")
        emptyFs:Hide()
        pf.emptyFs = emptyFs

        local ROWS = 8
        local rows = {}
        for i = 1, ROWS do
            local r = CreateFrame("Button", nil, pf)
            r:SetSize(462, 32)
            r:SetPoint("TOPLEFT", 10, -56 - (i - 1) * 33)
            PS.StyleBox(r, 0.55, false)

            local icBox = CreateFrame("Frame", nil, r)
            icBox:SetSize(28, 28)
            icBox:SetPoint("LEFT", 4, 0)
            PS.StyleBox(icBox, 0.85, false)
            r.iconBox = icBox

            local ic = icBox:CreateTexture(nil, "ARTWORK")
            ic:SetPoint("TOPLEFT", 1, -1)
            ic:SetPoint("BOTTOMRIGHT", -1, 1)
            ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.icon = ic

            local icOv = CreateFrame("Frame", nil, icBox)
            icOv:SetAllPoints(icBox)
            icOv:SetFrameLevel((icBox.GetFrameLevel and icBox:GetFrameLevel() or 1) + 3)
            r.iconOv = icOv

            local fb = icOv:CreateTexture(nil, "OVERLAY")
            fb:SetSize(13, 13)
            fb:SetPoint("BOTTOMRIGHT", icBox, "BOTTOMRIGHT", 2, -2)
            fb:Hide()
            r.forgeBadge = fb

            local ac = icOv:CreateTexture(nil, "OVERLAY")
            ac:SetSize(11, 11)
            ac:SetPoint("TOPRIGHT", icBox, "TOPRIGHT", 1, 1)
            ac:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            ac:Hide()
            r.absChk = ac

            local nm = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nm:SetPoint("TOPLEFT", icBox, "TOPRIGHT", 6, -1)
            nm:SetSize(308, 14)
            nm:SetJustifyH("LEFT")
            if nm.SetWordWrap then nm:SetWordWrap(false) end
            r.nameFs = nm

            local sub = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            sub:SetPoint("BOTTOMLEFT", icBox, "BOTTOMRIGHT", 6, 1)
            sub:SetSize(308, 12)
            sub:SetJustifyH("LEFT")
            if sub.SetWordWrap then sub:SetWordWrap(false) end
            r.subFs = sub

            local st = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            st:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            st:SetSize(106, 26)
            st:SetJustifyH("RIGHT")
            r.statusFs = st

            r:SetScript("OnEnter", function(self)
                PS.StyleBox(self, 0.85, true)
                local d = self.itemData
                if not d or not GameTooltip then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if d.isEquipped then
                    pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", d.invSlot)
                elseif d.isBank then
                    if d.link then pcall(GameTooltip.SetHyperlink, GameTooltip, d.link) end
                else
                    pcall(GameTooltip.SetBagItem, GameTooltip, d.bag, d.slot)
                end
                GameTooltip:AddLine(" ")
                if d.statusKey == "morkel" then
                    GameTooltip:AddLine("Эту сетовую вещь улучшает другой мастер (не Прогрессия).", 1.0, 0.62, 0.25, true)
                elseif d.statusKey == "warming" then
                    GameTooltip:AddLine("Загрузка информации о предмете с сервера...", 0.75, 0.75, 0.75, true)
                elseif d.statusKey == "no_rule" then
                    GameTooltip:AddLine("Этот предмет не улучшается в Прогрессии.", 0.75, 0.75, 0.75, true)
                elseif d.isEquipped then
                    GameTooltip:AddLine("Клик: снять в сумку и выбрать для улучшения.", 0.4, 1.0, 0.4, true)
                elseif d.isBank then
                    GameTooltip:AddLine("Клик: забрать из Банка вещей и выбрать для улучшения.", 0.65, 0.55, 1.0, true)
                else
                    GameTooltip:AddLine("Клик: выбрать для улучшения.", 0.4, 1.0, 0.4, true)
                end
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function(self)
                PS.StyleBox(self, 0.55, false)
                if GameTooltip then GameTooltip:Hide() end
            end)
            r:SetScript("OnClick", function(self)
                local d = self.itemData
                if not d then return end
                if not IsValdrisDispTabOpen() and (d.statusKey == "morkel" or d.statusKey == "no_rule") then
                    if DEFAULT_CHAT_FRAME then
                        local msg = (d.statusKey == "morkel") and "Эту сетовую вещь улучшает другой мастер (не Прогрессия)." or "Этот предмет не улучшается в Прогрессии."
                        DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[Прогрессия]|r " .. msg)
                    end
                    return
                end
                if d.isEquipped then
                    local ok, reason = AP:PickEquippedItemForValdris(d.invSlot)
                    if not ok and DEFAULT_CHAT_FRAME then
                        DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[Прогрессия]|r " .. tostring(reason))
                    end
                elseif d.isBank then
                    local ok, reason = AP:PickBankItemForValdris(d.ibGuid, d.link, d.forge)
                    if not ok and DEFAULT_CHAT_FRAME then
                        DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[Прогрессия]|r " .. tostring(reason))
                    end
                else
                    local ok, reason = AP:PickBagItemForValdris(d.bag, d.slot)
                    if not ok and reason and DEFAULT_CHAT_FRAME then
                        DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[Прогрессия]|r " .. tostring(reason))
                    end
                end
            end)
            rows[i] = r
        end
        pf.rows = rows

        local footFs = pf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        footFs:SetPoint("BOTTOMLEFT", 10, 8)
        footFs:SetText("Колесо: прокрутка | Alt+ЛКМ: сумка или слот персонажа")
        pf.footFs = footFs

        local pageFs = pf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pageFs:SetPoint("BOTTOMRIGHT", -10, 8)
        pf.pageFs = pageFs

        pf:EnableMouseWheel(true)
        pf:SetScript("OnMouseWheel", function(self, delta)
            local mx = math_max(0, #(self.listData or {}) - ROWS)
            self.offset = math_max(0, math_floor((self.offset or 0) - delta * 2))
            if self.offset > mx then self.offset = mx end
            RefreshValdrisPicker()
        end)

        RefreshValdrisPicker = function()
            if not vpPicker then return end
            for _, b in ipairs(vpPicker.filterBtns or {}) do
                PS.PaintBtn(b, b.key == vpPicker.filterKind and "green" or "dark")
            end
            local txt = vpPicker.searchBox and vpPicker.searchBox:GetText() or ""
            local data = AP:GetValdrisPickerItems(vpPicker.filterKind, txt)
            vpPicker.listData = data
            local total = #data
            local mx = math_max(0, total - ROWS)
            if (vpPicker.offset or 0) > mx then vpPicker.offset = mx end
            local off = vpPicker.offset or 0
            if total == 0 then vpPicker.emptyFs:Show() else vpPicker.emptyFs:Hide() end
            for i = 1, ROWS do
                local r = vpPicker.rows[i]
                local d = data[off + i]
                if d then
                    r.itemData = d
                    r.icon:SetTexture(d.tex or DEFAULT_PICK_ICON)
                    local fTier = d.forge or 0
                    local fv = FORGE_VIS[fTier]
                    ApplyForgeIconVisual(r.iconBox, r.forgeBadge, r.absChk, fTier, d.qual, (d.statusKey == "ready" or d.statusKey == "max_tier"))
                    local qr, qg, qb = 1, 1, 1
                    if type(GetItemQualityColor) == "function" then
                        local r1, g1, b1 = GetItemQualityColor(d.qual or 1)
                        if r1 then qr, qg, qb = r1, g1, b1 end
                    end
                    r.nameFs:SetText(CropText(d.name, 42))
                    r.nameFs:SetTextColor(qr, qg, qb)
                    local forgeLbl = fv and string.format("  |c%s[%s]|r", fv.hex, fv.name) or ""
                    if d.isEquipped then
                        r.subFs:SetText("|cffffd200[Надето: " .. tostring(d.slotLabel) .. "]|r  ilvl " .. (d.ilvl or 0) .. forgeLbl)
                    elseif d.isBank then
                        r.subFs:SetText("|cffa78bfa[Банк вещей]|r  ilvl " .. (d.ilvl or 0) .. forgeLbl)
                    else
                        r.subFs:SetText("|cff38bdf8[Сумка " .. d.bag .. ":" .. d.slot .. "]|r  ilvl " .. (d.ilvl or 0) .. forgeLbl)
                    end
                    r.statusFs:SetText(d.statusTag or "")
                    r:Show()
                else
                    r.itemData = nil
                    ApplyForgeIconVisual(r.iconBox, r.forgeBadge, r.absChk, 0, nil, false)
                    r:Hide()
                end
            end
            vpPicker.pageFs:SetText(string.format("%d/%d", total > 0 and (off + 1) or 0, total))
        end
        SS.valdrisRefreshPicker = function()
            if vpPicker and vpPicker:IsShown() then RefreshValdrisPicker() end
        end
        SS.valdrisRefreshBar = RefreshValdrisBar

        vpPicker = pf
        return pf
    end

    local function EnsureValdrisBar(ipf)
        if vpBar then return vpBar end
        local f = CreateFrame("Frame", "AP_ValdrisAutoBar", ipf)
        f:SetSize(674, 26)
        f:SetPoint("TOPLEFT", ipf, "TOPLEFT", 14, -45)
        f:SetFrameStrata("HIGH")
        f:SetFrameLevel((ipf.GetFrameLevel and ipf:GetFrameLevel() or 1) + 12)
        PS.StyleBox(f, 0.90, true)

        local pickBtn = PS.MakeBtn(f, 152, 20, "", "dark")
        pickBtn:SetPoint("LEFT", f, "LEFT", 6, 0)
        pickBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local pBox = CreateFrame("Frame", nil, pickBtn)
        pBox:SetSize(18, 18)
        pBox:SetPoint("LEFT", pickBtn, "LEFT", 4, 0)
        PS.StyleBox(pBox, 0.85, false)
        pickBtn.iconBox = pBox
        local pIc = pBox:CreateTexture(nil, "ARTWORK")
        pIc:SetPoint("TOPLEFT", 1, -1)
        pIc:SetPoint("BOTTOMRIGHT", -1, 1)
        pIc:SetTexture(DEFAULT_PICK_ICON)
        pIc:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        pickBtn.icon = pIc
        local pOv = CreateFrame("Frame", nil, pBox)
        pOv:SetAllPoints(pBox)
        pOv:SetFrameLevel((pBox.GetFrameLevel and pBox:GetFrameLevel() or 1) + 3)
        local pBadge = pOv:CreateTexture(nil, "OVERLAY")
        pBadge:SetSize(10, 10)
        pBadge:SetPoint("BOTTOMRIGHT", pBox, "BOTTOMRIGHT", 2, -2)
        pBadge:Hide()
        pickBtn.forgeBadge = pBadge
        if pickBtn.label then
            pickBtn.label:ClearAllPoints()
            pickBtn.label:SetPoint("LEFT", pBox, "RIGHT", 5, 0)
            pickBtn.label:SetPoint("RIGHT", pickBtn, "RIGHT", -6, 0)
            pickBtn.label:SetJustifyH("LEFT")
            if pickBtn.label.SetWordWrap then pickBtn.label:SetWordWrap(false) end
            pickBtn.label:SetText("Выбрать вещь")
        end
        EnsureValdrisPicker(ipf, pickBtn)
        pickBtn:SetScript("OnClick", function(_, mBtn)
            if mBtn == "RightButton" then
                vp.lastPicked = nil
                RefreshValdrisBar()
                if vpPicker and vpPicker:IsShown() and RefreshValdrisPicker then RefreshValdrisPicker() end
                return
            end
            local pf = EnsureValdrisPicker(ipf, pickBtn)
            if pf:IsShown() then
                pf:Hide()
            else
                if RefreshValdrisPicker then RefreshValdrisPicker() end
                pf:Show()
            end
        end)
        pickBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("|cffffd200Выбор предмета для улучшения|r")
            GameTooltip:AddLine("ЛКМ: открыть список вещей с иконками (включая надетые на персонаже).", 0.9, 0.9, 0.9, true)
            GameTooltip:AddLine("ALT + ЛКМ: по любой вещи в сумке или в окне персонажа -> сразу снять в сумку и выбрать!", 0.4, 1.0, 0.4, true)
            GameTooltip:AddLine("ПКМ: сбросить иконку выбора.", 0.7, 0.8, 0.9, true)
            GameTooltip:Show()
        end)
        pickBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.pickBtn = pickBtn

        local goBtn = PS.MakeBtn(f, 100, 20, "Улучшать (0)", "dark")
        goBtn:SetPoint("LEFT", pickBtn, "RIGHT", 4, 0)
        goBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        goBtn:SetScript("OnClick", function(_, mBtn)
            if vp.running then
                AP:StopValdrisAutoUpgrade("user")
            elseif mBtn == "RightButton" then
                vp.skip = {}
                vp.blockedByTier = {}
                vp.readyInfo = {}
                vp.bankSpaceFull = false
                local sum = AP:GetValdrisUpgradeSummary(false)
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff38bdf8[Прогрессия]|r Найдено к улучшению: %d (цель<=%d, Банк вещей=%s, надетые=%s).",
                        sum.totalEligible or 0, sum.maxTier or 3, sum.includeBank and "да" or "нет", sum.includeEquipped and "да" or "нет"))
                end
                RefreshValdrisBar()
            else
                local ok, reason = AP:StartValdrisAutoUpgrade()
                if not ok and reason ~= "done" and reason ~= "closed" and reason ~= "warming" and reason ~= "stopped" and DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[Прогрессия]|r " .. tostring(reason or "нет подходящих вещей"))
                end
            end
        end)
        goBtn:SetScript("OnEnter", function(self)
            local sum = AP:GetValdrisUpgradeSummary(false)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("|cffffd200Автоулучшение вещей (AttuneParser)|r")
            GameTooltip:AddLine("ЛКМ: старт/стоп авто-повышения ковки для поглощенных несетовых вещей (сумки + Банк вещей).", 0.9, 0.9, 0.9, true)
            GameTooltip:AddLine("ПКМ: пересканировать.", 0.4, 1.0, 0.4, true)
            GameTooltip:AddLine(string.format("Готово к улучшению: %d | Улучшено за сессию: %d", sum.totalEligible or 0, sum.doneCount or 0), 0.7, 0.85, 1.0, true)
            GameTooltip:Show()
        end)
        goBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.goBtn = goBtn

        local tierBtn = PS.MakeBtn(f, 108, 20, "Цель: Титан (3)", "dark")
        tierBtn:SetPoint("LEFT", goBtn, "RIGHT", 4, 0)
        tierBtn:SetScript("OnClick", function() AP:CycleValdrisMaxTier() end)
        tierBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Потолок автоулучшения")
            GameTooltip:AddLine("ЛКМ: переключить максимальную ступень (1 Эпик / 2 Лег. / 3 Титан).", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        tierBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.tierBtn = tierBtn

        local incBkChk = CreateFrame("Button", nil, f)
        incBkChk:SetPoint("LEFT", tierBtn, "RIGHT", 5, 0)
        incBkChk:SetSize(78, 20)
        local bBox = CreateFrame("Frame", nil, incBkChk)
        bBox:SetPoint("LEFT", incBkChk, "LEFT", 0, 0)
        bBox:SetSize(15, 15)
        PS.StyleBox(bBox, 0.55, false)
        local bmk = bBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bmk:SetPoint("CENTER", 0, 0)
        local blbl = incBkChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        blbl:SetPoint("LEFT", bBox, "RIGHT", 4, 0)
        blbl:SetText("Из банка")
        incBkChk._box = bBox
        incBkChk._mk = bmk
        incBkChk:SetScript("OnClick", function()
            AP:SetValdrisIncludeBank(not (AP:GetSetting("valdrisIncludeBank") ~= false))
        end)
        incBkChk:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Брать вещи из Банка вещей")
            GameTooltip:AddLine("Если включено, автоулучшение забирает подходящие вещи из Банка вещей, улучшает и возвращает их обратно.", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        incBkChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.incBkChk = incBkChk

        local incEqChk = CreateFrame("Button", nil, f)
        incEqChk:SetPoint("LEFT", incBkChk, "RIGHT", 4, 0)
        incEqChk:SetSize(102, 20)
        local eBox = CreateFrame("Frame", nil, incEqChk)
        eBox:SetPoint("LEFT", incEqChk, "LEFT", 0, 0)
        eBox:SetSize(15, 15)
        PS.StyleBox(eBox, 0.55, false)
        local emk = eBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        emk:SetPoint("CENTER", 0, 0)
        local elbl = incEqChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        elbl:SetPoint("LEFT", eBox, "RIGHT", 4, 0)
        elbl:SetText("Снять надетое")
        incEqChk._box = eBox
        incEqChk._mk = emk
        incEqChk:SetScript("OnClick", function()
            AP:SetValdrisIncludeEquipped(not (AP:GetSetting("valdrisIncludeEquipped") == true))
        end)
        incEqChk:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Автоснятие надетых вещей для улучшения")
            GameTooltip:AddLine("Если включено, автоулучшение снимает подходящие надетые вещи в сумку, улучшает их и надевает обратно.", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        incEqChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.incEqChk = incEqChk

        local autoChk = CreateFrame("Button", nil, f)
        autoChk:SetPoint("LEFT", incEqChk, "RIGHT", 4, 0)
        autoChk:SetSize(90, 20)
        local cBox = CreateFrame("Frame", nil, autoChk)
        cBox:SetPoint("LEFT", autoChk, "LEFT", 0, 0)
        cBox:SetSize(15, 15)
        PS.StyleBox(cBox, 0.55, false)
        local mk = cBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mk:SetPoint("CENTER", 0, 0)
        local lbl = autoChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cBox, "RIGHT", 5, 0)
        lbl:SetText("Авто-старт")
        autoChk._box = cBox
        autoChk._mk = mk
        autoChk:SetScript("OnClick", function()
            AP:SetValdrisAutoOpen(not (AP:GetSetting("valdrisAutoOpen") == true))
        end)
        autoChk:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Авто-старт улучшения")
            GameTooltip:AddLine("При включении автоматически запускает улучшение сразу при открытии окна Прогрессии.", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        autoChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.autoChk = autoChk

        vpBar = f
        return f
    end

    local function TryValdrisBagAltClick(self, button)
        if not IsValdrisFrameOpen() or button ~= "LeftButton" or IsItemBankOpen() then return false end
        if not (type(IsAltKeyDown) == "function" and IsAltKeyDown()) then return false end
        if (type(IsControlKeyDown) == "function" and IsControlKeyDown()) or (type(IsShiftKeyDown) == "function" and IsShiftKeyDown()) then
            return false
        end
        if type(SpellIsTargeting) == "function" and SpellIsTargeting() then return false end
        if type(CursorHasItem) == "function" and CursorHasItem() then return false end
        if (_G.MerchantFrame and _G.MerchantFrame:IsShown())
           or (_G.SendMailFrame and _G.SendMailFrame:IsShown())
           or (_G.TradeFrame and _G.TradeFrame:IsShown())
           or (_G.AuctionFrame and _G.AuctionFrame:IsShown())
           or (_G.ResourceBankFrame and _G.ResourceBankFrame:IsShown()) then
            return false
        end
        if type(self) ~= "table" or (type(self.IsCached) == "function" and self:IsCached()) then return false end
        local parent = self.GetParent and self:GetParent()
        local bag = (type(self.GetBag) == "function" and self:GetBag()) or (parent and parent.GetID and parent:GetID())
        local slot = self.GetID and self:GetID()
        if type(bag) ~= "number" or type(slot) ~= "number" or bag < 0 or bag > 4 or slot < 1 then return false end
        local link = (type(GetContainerItemLink) == "function") and GetContainerItemLink(bag, slot)
        if not link then return false end
        local ok, reason = AP:PickBagItemForValdris(bag, slot)
        if not ok and reason and DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[Прогрессия]|r " .. tostring(reason))
        end
        return true
    end

    local function TryValdrisPaperDollAltClick(self, button)
        if not IsValdrisFrameOpen() or button ~= "LeftButton" or IsItemBankOpen() then return false end
        if not (type(IsAltKeyDown) == "function" and IsAltKeyDown()) then return false end
        if (type(IsControlKeyDown) == "function" and IsControlKeyDown()) or (type(IsShiftKeyDown) == "function" and IsShiftKeyDown()) then
            return false
        end
        if type(SpellIsTargeting) == "function" and SpellIsTargeting() then return false end
        if type(CursorHasItem) == "function" and CursorHasItem() then return false end
        if type(self) ~= "table" then return false end
        local fn = self.GetName and self:GetName()
        if type(fn) == "string" and fn:find("^Inspect") then return false end
        local p = self.GetParent and self:GetParent()
        local pn = p and p.GetName and p:GetName()
        if type(pn) == "string" and pn:find("^Inspect") then return false end
        local invId = self.GetID and self:GetID()
        if type(invId) ~= "number" or invId < 1 or invId > 18 or invId == 4 then return false end
        local link = (type(GetInventoryItemLink) == "function") and GetInventoryItemLink("player", invId)
        if not link then return false end
        local ok, reason = AP:PickEquippedItemForValdris(invId)
        if not ok and DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[Прогрессия]|r " .. tostring(reason))
        end
        return true
    end

    local function SetupValdrisAltHooks()
        if type(hooksecurefunc) ~= "function" then return end
        if not vp.hookedModClick and type(_G.ContainerFrameItemButton_OnModifiedClick) == "function" then
            vp.hookedModClick = true
            hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, button)
                TryValdrisBagAltClick(self, button)
            end)
        end
        if not vp.hookedPdMod and type(_G.PaperDollItemSlotButton_OnModifiedClick) == "function" then
            vp.hookedPdMod = true
            hooksecurefunc("PaperDollItemSlotButton_OnModifiedClick", function(self, button)
                TryValdrisPaperDollAltClick(self, button)
            end)
        end
        if not vp.slotHookDone then
            local anySlot = false
            for _, fnName in ipairs({ "ItemProgressSlot_OnClick", "ItemProgressDispSlot_OnClick" }) do
                if type(_G[fnName]) == "function" then
                    anySlot = true
                    hooksecurefunc(fnName, function(_, button)
                        if button == "RightButton" then
                            vp.lastPicked = nil
                            RefreshValdrisBar()
                        end
                    end)
                end
            end
            if anySlot then vp.slotHookDone = true end
        end
    end

    function SS.tryHookValdris()
        SetupValdrisAltHooks()
        local ipf = rawget(_G, "ItemProgressFrame")
        if not ipf then return false end
        if vp.hookedFrame ~= ipf then
            vp.hookDone = true
            vp.hookedFrame = ipf
            EnsureValdrisBar(ipf)
            if vpBar and vpBar.SetParent then
                vpBar:SetParent(ipf)
                vpBar:ClearAllPoints()
                vpBar:SetPoint("TOPLEFT", ipf, "TOPLEFT", 14, -45)
                if vpBar.SetFrameLevel and ipf.GetFrameLevel then
                    vpBar:SetFrameLevel((ipf:GetFrameLevel() or 1) + 12)
                end
            end
            if type(ipf.HookScript) == "function" then
                ipf:HookScript("OnShow", function()
                    vp.skip = {}
                    vp.blockedByTier = {}
                    vp.readyInfo = {}
                    vp.doneCount = 0
                    vp.warmRetries = 0
                    vp.warmAttempts = {}
                    vp.barWarmCount = 0
                    vp.barWarmScheduled = false
                    vp.lastError = nil
                    vp.lastPicked = nil
                    vp.pendingUnequip = nil
                    vp.pendingBankTake = nil
                    local now = GetTime()
                    if type(SendServerMessage) == "function" and (now - (vp.lastForgeSyncAt or 0)) >= 1.5 then
                        vp.lastForgeSyncAt = now
                        pcall(SendServerMessage, "ACMSG_FORGE_SYNC")
                    end
                    RefreshValdrisBar()
                    if vpPicker and vpPicker:IsShown() and RefreshValdrisPicker then RefreshValdrisPicker() end
                end)
                ipf:HookScript("OnHide", function()
                    vp.pauseEquipUntil = 0
                    vp.pendingUnequip = nil
                    vp.pendingBankTake = nil
                    if vpPicker then vpPicker:Hide() end
                    AP:StopValdrisAutoUpgrade("closed")
                    RefreshValdrisBar()
                end)
            end
        end
        RefreshValdrisBar()
        return true
    end

    local function RefreshValdrisLive(_, tag)
        if type(tag) == "string" and tag:sub(1, 8) == "VALDRIS_" then return end
        if not IsValdrisFrameOpen() then return end
        RefreshValdrisBar()
        if vpPicker and vpPicker:IsShown() and RefreshValdrisPicker then RefreshValdrisPicker() end
    end
    AP:RegisterCallback("FORGE_UPDATED", RefreshValdrisLive)
    AP:RegisterCallback("ATTUNE_UPDATED", RefreshValdrisLive)
    AP:RegisterCallback("SERVER_SYNC_UPDATED", RefreshValdrisLive)

    vpDrv:SetScript("OnUpdate", function(self, elapsed)
        if vp.running and vp.pending and GetTime() >= (vp.scheduledAt or 0) then
            vp.pending = false
            AP:RunValdrisStep()
        end
        self._acc = (self._acc or 0) + (elapsed or 0)
        if self._acc < 0.08 then return end
        self._acc = 0
        if vp.pendingUnequip then
            CheckPendingUnequip()
        end
        if vp.pendingBankTake then
            CheckPendingBankTake()
        end
        if vp.pendingBankReturn then
            CheckPendingBankReturn()
        end
        if vp.running then
            local now = GetTime()
            if (now - (vp.lastBarUiAt or 0)) >= 0.35 then
                RefreshValdrisBar()
            end
        elseif not vp.pendingUnequip and not vp.pendingBankTake and not vp.pendingBankReturn then
            self:Hide()
        end
    end)

    SS.tryHookValdris()
end

do
    local pf = rawget(_G, "AttuneParserFrame")
    if pf and pf.tabPanels and pf.content and type(AP.BuildServerSyncTab) == "function" then
        if pf.tabPanels.server and pf.tabPanels.server.Hide then pf.tabPanels.server:Hide() end
        pf.tabPanels.server = AP.BuildServerSyncTab(pf.content)
        if pf.activeTab ~= "server" then pf.tabPanels.server:Hide() end
    end
end
