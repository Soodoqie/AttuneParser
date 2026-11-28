-- AttuneParser_UI.lua - Самодостаточный интерфейс AttuneParser в стиле WoW Prime,
-- кнопка миникарты, интеграция с PrimeHub и окно настроек.
local AP = rawget(_G, "AttuneParser")
if not AP then return end

---------------------------------------------------------------------------
-- 1. Фирменный скин WoW Prime (AtlasTexture.blp + бронзовый fallback)
---------------------------------------------------------------------------
local PS = {}
AP.Skin = PS

do
    local ATLAS_FILE = "Interface\\Peark\\AtlasTexture.blp"
    local WHITE = "Interface\\Buttons\\WHITE8X8"
    local CAP = 22
    local ATLAS = {
        WINDOW    = {    0,   0, 1366, 1024 },
        CLOSE     = { 1385,  16, 1428,   59 },
        BTN_GREEN = { 1382,  82, 1608,  129 },
        BTN_DARK  = { 1382, 141, 1608,  190 },
        BTN_RED   = { 1383, 347, 1650,  403 },
        BTN_GRAY  = { 1385, 433, 1650,  487 },
    }
    local KIND_KEY = {
        green = "BTN_GREEN",
        dark  = "BTN_DARK",
        red   = "BTN_RED",
        gray  = "BTN_GRAY",
        gold  = "BTN_DARK",
    }
    local FALLBACK_BG = {
        green = { 0.10, 0.34, 0.14, 0.95, 0.25, 0.78, 0.34, 1 },
        dark  = { 0.11, 0.10, 0.09, 0.95, 0.48, 0.40, 0.22, 0.9 },
        red   = { 0.38, 0.11, 0.11, 0.95, 0.74, 0.26, 0.24, 1 },
        gray  = { 0.15, 0.14, 0.13, 0.90, 0.35, 0.32, 0.28, 0.8 },
        gold  = { 0.25, 0.19, 0.08, 0.96, 0.98, 0.80, 0.28, 1 },
    }
    local hasAtlas = nil
    local function CheckAtlas()
        if hasAtlas ~= nil then return hasAtlas end
        local probe = UIParent:CreateTexture(nil, "BACKGROUND")
        local ok = probe:SetTexture(ATLAS_FILE)
        hasAtlas = (ok and probe:GetTexture() ~= nil) and true or false
        probe:SetTexture(nil)
        probe:Hide()
        return hasAtlas
    end
    local function SetAtlasUV(tex, r, u0, u1)
        local l, rt = r[1], r[3]
        if u0 then
            local span = rt - l
            rt = l + span * (u1 or 1)
            l = l + span * u0
        end
        tex:SetTexture(ATLAS_FILE)
        tex:SetTexCoord(l / 2048, rt / 2048, r[2] / 1024, r[4] / 1024)
    end
    function PS.ApplyWindow(f)
        if not f then return end
        if CheckAtlas() then
            f:SetBackdrop(nil)
            if not f._psBg then
                local bg = f:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints(f)
                SetAtlasUV(bg, ATLAS.WINDOW)
                f._psBg = bg
            end
        else
            f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
            f:SetBackdropColor(0.09, 0.08, 0.07, 0.96)
            f:SetBackdropBorderColor(0.62, 0.52, 0.30, 1)
        end
    end
    function PS.StyleBox(f, aBg, goldBorder)
        if not f then return end
        f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        f:SetBackdropColor(0.03, 0.03, 0.03, aBg or 0.52)
        if goldBorder then
            f:SetBackdropBorderColor(0.92, 0.74, 0.28, 0.95)
        else
            f:SetBackdropBorderColor(0.50, 0.42, 0.24, 0.82)
        end
    end
    function PS.StyleClose(btn, sz)
        if not btn then return end
        btn:SetSize(sz or 26, sz or 26)
        if CheckAtlas() then
            btn:SetBackdrop(nil)
            for _, rg in ipairs({ btn:GetRegions() }) do
                if rg.GetObjectType and rg:GetObjectType() == "FontString" then rg:Hide() end
            end
            if not btn._psTex then
                local t = btn:CreateTexture(nil, "ARTWORK")
                t:SetAllPoints(btn)
                SetAtlasUV(t, ATLAS.CLOSE)
                btn._psTex = t
                local hl = btn:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(btn)
                hl:SetBlendMode("ADD")
                hl:SetAlpha(0.45)
                SetAtlasUV(hl, ATLAS.CLOSE)
                btn:SetHighlightTexture(hl)
                btn:HookScript("OnMouseDown", function(self) self._psTex:SetVertexColor(0.75, 0.75, 0.75) end)
                btn:HookScript("OnMouseUp", function(self) self._psTex:SetVertexColor(1, 1, 1) end)
            end
        else
            btn:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
            btn:SetBackdropColor(0.38, 0.11, 0.11, 0.95)
            btn:SetBackdropBorderColor(0.65, 0.48, 0.22, 1)
        end
    end
    function PS.PaintBtn(b, kind, tint)
        if not b then return end
        kind = kind or b._psKind or "dark"
        b._psKind = kind
        if b._psSlices then
            local r = ATLAS[KIND_KEY[kind] or "BTN_DARK"]
            local u = CAP / (r[3] - r[1])
            SetAtlasUV(b._psSlices[1], r, 0, u)
            SetAtlasUV(b._psSlices[2], r, u, 1 - u)
            SetAtlasUV(b._psSlices[3], r, 1 - u, 1)
            for i = 1, 3 do
                if tint then
                    b._psSlices[i]:SetVertexColor(tint[1], tint[2], tint[3])
                else
                    b._psSlices[i]:SetVertexColor(1, 1, 1)
                end
            end
            if b._psGoldRing then
                if kind == "gold" then b._psGoldRing:Show() else b._psGoldRing:Hide() end
            end
        else
            local fb = FALLBACK_BG[kind] or FALLBACK_BG.dark
            b:SetBackdropColor(fb[1], fb[2], fb[3], fb[4])
            b:SetBackdropBorderColor(fb[5], fb[6], fb[7], fb[8])
        end
    end
    function PS.StyleBtn(b, kind)
        if not b then return end
        if CheckAtlas() then
            b:SetBackdrop(nil)
            local r = ATLAS[KIND_KEY[kind or "dark"] or "BTN_DARK"]
            local h = b:GetHeight()
            if not h or h < 1 then h = 24 end
            local cap = math.floor(CAP * h / (r[4] - r[2]) + 0.5)
            if cap < 4 then cap = 4 end
            if not b._psSlices then
                local sl = {}
                for i = 1, 3 do sl[i] = b:CreateTexture(nil, "BACKGROUND") end
                sl[1]:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
                sl[1]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
                sl[1]:SetWidth(cap)
                sl[3]:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
                sl[3]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
                sl[3]:SetWidth(cap)
                sl[2]:SetPoint("TOPLEFT", sl[1], "TOPRIGHT", 0, 0)
                sl[2]:SetPoint("BOTTOMRIGHT", sl[3], "BOTTOMLEFT", 0, 0)
                b._psSlices = sl

                local gr = CreateFrame("Frame", nil, b)
                gr:SetAllPoints(b)
                gr:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
                gr:SetBackdropBorderColor(1.00, 0.82, 0.30, 0.95)
                gr:Hide()
                b._psGoldRing = gr

                local hl = b:CreateTexture(nil, "HIGHLIGHT")
                hl:SetPoint("TOPLEFT", 1, -1)
                hl:SetPoint("BOTTOMRIGHT", -1, 1)
                hl:SetBlendMode("ADD")
                hl:SetAlpha(0.28)
                SetAtlasUV(hl, ATLAS.BTN_GREEN)
                b:SetHighlightTexture(hl)
            end
        else
            b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        end
        PS.PaintBtn(b, kind or "dark")
    end
    function PS.MakeBtn(parent, w, h, text, kind, fontObj)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(w, h)
        PS.StyleBtn(b, kind or "dark")
        local fs = b:CreateFontString(nil, "OVERLAY", fontObj or "GameFontHighlightSmall")
        fs:SetPoint("CENTER", 0, 0)
        fs:SetText(text or "")
        b.label = fs
        return b
    end
    function PS.StyleScrollRow(r, isOdd)
        PS.StyleBox(r, isOdd and 0.42 or 0.25, false)
        r:SetBackdropBorderColor(0.32, 0.27, 0.16, 0.45)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(r)
        hl:SetTexture(0.95, 0.78, 0.28, 0.16)
        r:SetHighlightTexture(hl)
    end
    function PS.AttachScroll(parent, listHeight, rowH, visCount, onUpdateFn)
        local sf = CreateFrame("Frame", nil, parent)
        sf.offset = 0
        sf.total = 0
        sf.visCount = visCount
        sf:EnableMouseWheel(true)

        local BTN_H = 16
        local bar = CreateFrame("Frame", nil, sf)
        bar:SetWidth(14)
        bar:SetHeight(math.max(40, (listHeight or 100) - 4))
        bar:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, -2)
        bar:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0, 2)
        bar:SetFrameLevel(((sf.GetFrameLevel and sf:GetFrameLevel()) or 1) + 6)
        bar:EnableMouse(true)
        bar:EnableMouseWheel(true)
        PS.StyleBox(bar, 0.72, false)

        local isDragging, dragStartY, dragStartOff = false, 0, 0
        local up, dn, thumb

        local function getCursorY()
            if type(GetCursorPosition) ~= "function" then return nil end
            local _, cy = GetCursorPosition()
            if not cy then return nil end
            local sc = (bar.GetEffectiveScale and bar:GetEffectiveScale()) or 1
            if not sc or sc <= 0 then sc = 1 end
            return cy / sc
        end

        local function paintThumb(active)
            if not thumb then return end
            if active then
                thumb:SetBackdropColor(0.98, 0.78, 0.30, 1.0)
                thumb:SetBackdropBorderColor(1.0, 0.92, 0.54, 1.0)
            else
                thumb:SetBackdropColor(0.82, 0.63, 0.22, 0.92)
                thumb:SetBackdropBorderColor(1.0, 0.86, 0.38, 0.95)
            end
        end

        local function clampAndRefresh(newOff)
            local maxOff = math.max(0, (sf.total or 0) - visCount)
            newOff = math.floor((newOff or 0) + 0.5)
            if newOff < 0 then newOff = 0 end
            if newOff > maxOff then newOff = maxOff end
            sf.offset = newOff
            if maxOff <= 0 then
                isDragging = false
                bar:Hide()
            else
                bar:Show()
                local bTop = bar.GetTop and bar:GetTop()
                local bBot = bar.GetBottom and bar:GetBottom()
                local bh = (bTop and bBot and (bTop > bBot)) and (bTop - bBot) or bar:GetHeight()
                if not bh or bh <= 1 then bh = math.max(40, (listHeight or 100) - 4) end
                local trackH = math.max(24, bh - (BTN_H * 2 + 4))
                local thumbH = math.max(20, math.floor(trackH * (visCount / math.max(1, sf.total))))
                if thumbH > trackH then thumbH = trackH end
                local travel = math.max(0, trackH - thumbH)
                sf._trackH = trackH
                sf._thumbH = thumbH
                sf._travel = travel
                if thumb then
                    thumb:SetHeight(thumbH)
                    local yOff = (maxOff > 0) and math.floor(travel * (sf.offset / maxOff) + 0.5) or 0
                    thumb:ClearAllPoints()
                    thumb:SetPoint("TOP", bar, "TOP", 0, -(BTN_H + 2 + yOff))
                end
            end
            if onUpdateFn then onUpdateFn(sf.offset) end
        end

        local function makeArrow(isUp)
            local b = CreateFrame("Button", nil, bar)
            b:SetSize(14, BTN_H)
            b:SetPoint(isUp and "TOP" or "BOTTOM", bar, isUp and "TOP" or "BOTTOM", 0, 0)
            b:SetFrameLevel(((bar.GetFrameLevel and bar:GetFrameLevel()) or 1) + 2)
            b:EnableMouse(true)
            b:EnableMouseWheel(true)
            PS.StyleBox(b, 0.92, false)
            b:SetBackdropBorderColor(0.58, 0.48, 0.25, 0.92)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetPoint("TOPLEFT", 1, -1)
            hl:SetPoint("BOTTOMRIGHT", -1, 1)
            hl:SetTexture(0.95, 0.78, 0.28, 0.28)
            b:SetHighlightTexture(hl)
            local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("CENTER", 0, isUp and -1 or 1)
            fs:SetText(isUp and "^" or "v")
            fs:SetTextColor(0.98, 0.84, 0.36)
            b._fs = fs
            local stepMag = math.max(1, math.floor(visCount / 5))
            b._step = isUp and -stepMag or stepMag
            b:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(0.96, 0.78, 0.30, 1)
            end)
            b:SetScript("OnLeave", function(self)
                if not self._held then self:SetBackdropBorderColor(0.58, 0.48, 0.25, 0.92) end
            end)
            b:SetScript("OnMouseDown", function(self, mBtn)
                if mBtn and mBtn ~= "LeftButton" then return end
                self._held = true
                self._holdT = 0
                self._repT = 0
                self._upAt = nil
                self._mouseStepped = true
                self:SetBackdropBorderColor(1.0, 0.86, 0.36, 1)
                clampAndRefresh((sf.offset or 0) + self._step)
            end)
            b:SetScript("OnMouseUp", function(self)
                self._held = false
                self._holdT = 0
                self._repT = 0
                self._upAt = 0
                self:SetBackdropBorderColor(0.58, 0.48, 0.25, 0.92)
            end)
            b:SetScript("OnClick", function(self)
                if self._mouseStepped then
                    self._mouseStepped = false
                    self._upAt = nil
                    return
                end
                clampAndRefresh((sf.offset or 0) + self._step)
            end)
            return b
        end

        up = makeArrow(true)
        dn = makeArrow(false)

        thumb = CreateFrame("Button", nil, bar)
        thumb:SetSize(12, 24)
        thumb:SetPoint("TOP", bar, "TOP", 0, -(BTN_H + 2))
        thumb:SetFrameLevel(((bar.GetFrameLevel and bar:GetFrameLevel()) or 1) + 2)
        thumb:EnableMouse(true)
        thumb:EnableMouseWheel(true)
        PS.StyleBox(thumb, 0.94, true)
        paintThumb(false)
        local thl = thumb:CreateTexture(nil, "HIGHLIGHT")
        thl:SetPoint("TOPLEFT", 1, -1)
        thl:SetPoint("BOTTOMRIGHT", -1, 1)
        thl:SetTexture(1.0, 0.88, 0.42, 0.26)
        thumb:SetHighlightTexture(thl)

        thumb:SetScript("OnEnter", function() paintThumb(true) end)
        thumb:SetScript("OnLeave", function() if not isDragging then paintThumb(false) end end)
        thumb:SetScript("OnMouseDown", function(_, mBtn)
            if mBtn and mBtn ~= "LeftButton" then return end
            local maxOff = math.max(0, (sf.total or 0) - visCount)
            if maxOff <= 0 then return end
            local cy = getCursorY()
            dragStartY = cy or 0
            dragStartOff = sf.offset or 0
            isDragging = (cy ~= nil)
            paintThumb(true)
        end)
        thumb:SetScript("OnMouseUp", function()
            isDragging = false
            paintThumb(false)
        end)

        bar:SetScript("OnMouseDown", function(self, mBtn)
            if mBtn and mBtn ~= "LeftButton" then return end
            local maxOff = math.max(0, (sf.total or 0) - visCount)
            if maxOff <= 0 then return end
            local cy = getCursorY()
            local bTop = self.GetTop and self:GetTop()
            local travel = sf._travel or 0
            if cy and bTop and travel > 0 then
                local frac = ((bTop - (BTN_H + 2)) - (sf._thumbH or 20) * 0.5 - cy) / travel
                if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
                clampAndRefresh(math.floor(frac * maxOff + 0.5))
                dragStartY = cy
                dragStartOff = sf.offset or 0
                isDragging = true
                paintThumb(true)
            else
                local pg = math.max(1, visCount - 1)
                local bCen = (bTop and self.GetBottom and self:GetBottom()) and ((bTop + self:GetBottom()) * 0.5)
                if cy and bCen and cy > bCen then pg = -pg end
                clampAndRefresh((sf.offset or 0) + pg)
            end
        end)
        bar:SetScript("OnMouseUp", function()
            isDragging = false
            paintThumb(false)
        end)
        bar:SetScript("OnHide", function()
            isDragging = false
            up._held = false; up._mouseStepped = false; up._upAt = nil
            dn._held = false; dn._mouseStepped = false; dn._upAt = nil
            paintThumb(false)
        end)
        bar:SetScript("OnUpdate", function(_, elapsed)
            if not isDragging and not up._held and not dn._held and not up._mouseStepped and not dn._mouseStepped then
                return
            end
            local el = elapsed or 0
            if isDragging then
                local cy = getCursorY()
                local travel = sf._travel or 0
                local maxOff = math.max(0, (sf.total or 0) - visCount)
                if cy and travel > 0 and maxOff > 0 then
                    local dy = dragStartY - cy
                    local tgt = math.floor(dragStartOff + (dy / travel) * maxOff + 0.5)
                    if tgt < 0 then tgt = 0 elseif tgt > maxOff then tgt = maxOff end
                    if tgt ~= (sf.offset or 0) then clampAndRefresh(tgt) end
                end
            end
            for _, btn in ipairs({ up, dn }) do
                if btn._held then
                    btn._holdT = (btn._holdT or 0) + el
                    if btn._holdT >= 0.28 then
                        btn._repT = (btn._repT or 0) + el
                        if btn._repT >= 0.065 then
                            btn._repT = 0
                            clampAndRefresh((sf.offset or 0) + btn._step)
                        end
                    end
                elseif btn._mouseStepped then
                    btn._upAt = (btn._upAt or 0) + el
                    if btn._upAt >= 0.12 then
                        btn._mouseStepped = false
                        btn._upAt = nil
                    end
                end
            end
        end)

        local function onWheel(_, delta)
            local step = (delta > 0) and -2 or 2
            clampAndRefresh((sf.offset or 0) + step)
        end
        sf:SetScript("OnMouseWheel", onWheel)
        bar:SetScript("OnMouseWheel", onWheel)
        up:SetScript("OnMouseWheel", onWheel)
        dn:SetScript("OnMouseWheel", onWheel)
        thumb:SetScript("OnMouseWheel", onWheel)

        function sf:SetTotal(totalCount, keepOffset)
            sf.total = totalCount or 0
            clampAndRefresh(keepOffset and (sf.offset or 0) or 0)
        end
        sf._bar = bar
        sf._up = up
        sf._dn = dn
        sf._thumb = thumb
        sf._OnWheel = function(arg1, arg2, arg3)
            onWheel(sf, (type(arg1) == "number" and arg1) or (type(arg2) == "number" and arg2) or arg3 or 0)
        end
        sf._ScrollTo = function(arg1, arg2)
            clampAndRefresh((type(arg1) == "number" and arg1) or arg2 or 0)
        end
        return sf
    end
end

---------------------------------------------------------------------------
-- 2. Общие помощники данных и качества
---------------------------------------------------------------------------
local UI_ROOT = {}
AP._ui = UI_ROOT

local function KeepAttuneMinimapInPrimeHub()
    local db = rawget(_G, "PrimeHubDB")
    if type(db) == "table" then
        db.keep = db.keep or {}
        db.keep["AttuneParserMinimapButton"] = true
        local ph = rawget(_G, "PrimeHub")
        if ph and ph.Shelf and type(ph.Shelf.Rescan) == "function" then pcall(ph.Shelf.Rescan) end
    end
end

local QUAL_HEX = {
    [0] = "|cff9d9d9d",
    [1] = "|cffffffff",
    [2] = "|cff1eff00",
    [3] = "|cff0070dd",
    [4] = "|cffa335ee",
    [5] = "|cffff8000",
}

local ERA_LABELS = {
    All = "Все",
    WotLK = "WotLK",
    TBC = "TBC",
    Classic = "Classic",
}
local ERA_EXP = {
    WotLK = 3,
    TBC = 2,
    Classic = 1,
}

local STAT_NAMES = {
    [3] = "Ловкость", [4] = "Сила", [5] = "Интеллект", [6] = "Дух", [7] = "Выносливость",
    [12] = "Защита", [13] = "Уклонение", [14] = "Парирование", [15] = "Блок щитом",
    [31] = "Меткость", [32] = "Крит. удар", [35] = "Устойчивость", [36] = "Скорость",
    [37] = "Мастерство", [38] = "Сила атаки", [44] = "Пробивание брони", [45] = "Сила заклинаний",
    [46] = "Восстановление маны", [47] = "Проник. заклинаний", [48] = "Показатель блока",
}

local function FormatLocation(w)
    if w == "petloot" then return "|cffff80ffСборщик|r" end
    if w == "itembank" then return "|cff60a5faБанк вещей|r" end
    if w == "guild" then return "|cff40ff80Гильдбанк|r" end
    if w == "bank" then return "|cff38bdf8Банк|r" end
    if w == "equip" then return "|cffffd200Надетые|r" end
    return "|cffffffffСумка|r"
end

local function ShortItemLink(itemId, name, quality, sfx)
    local qCol = QUAL_HEX[quality or 2] or "|cffffffff"
    if not itemId then return qCol .. tostring(name or "?") .. "|r" end
    return qCol .. tostring(name or ("Предмет #" .. itemId)) .. "|r"
end

local function AppendSourcesToTooltip(tt, itemId, maxLines)
    local src = AP:GetItemSources(itemId)
    if not src or not src.list or #src.list == 0 then
        if src and src.hasServerSources == false then
            tt:AddLine("|cff94a3b8Источники еще не запрошены с сервера...|r", 1, 1, 1)
            AP:RequestItemSources(itemId, false)
        end
        return
    end
    tt:AddLine(" ")
    tt:AddLine("|cffffd200Источники получения:|r", 1, 1, 1)
    local shown = 0
    for _, sc in ipairs(src.list) do
        if shown >= (maxLines or 5) then
            tt:AddLine(string.format("  |cff94a3b8... и еще %d источник(ов)|r", #src.list - shown), 1, 1, 1)
            break
        end
        local sType = (AP.SOURCE_TYPES and AP.SOURCE_TYPES[sc.st]) or "?"
        local zPart = (sc.zoneName and sc.zoneName ~= "") and (" (" .. sc.zoneName .. ")") or ""
        local extra = ""
        if sc.st == 4 then
            local qStatus = sc.qDone and "|cff40ff40[Вып]|r " or "|cffffd200[Кв]|r "
            local chStr = (sc.qlen and sc.qlen > 1) and string.format(" [цепочка %d]", sc.qlen) or ""
            local gStr = (sc.giver and sc.giver ~= "") and (" - от: " .. sc.giver) or ""
            tt:AddLine("  " .. qStatus .. (sc.name or ("Задание #" .. tostring(sc.smp))) .. chStr .. gStr .. zPart, 0.92, 0.90, 0.85, true)
            if sc.chainNames and #sc.chainNames > 1 then
                local chList = {}
                for ci, cn in ipairs(sc.chainNames) do
                    if ci <= 4 then table.insert(chList, cn) end
                end
                if #sc.chainNames > 4 then table.insert(chList, "...") end
                tt:AddLine("    |cffb0a080Цепочка: " .. table.concat(chList, " -> ") .. "|r", 1, 1, 1, true)
            end
        else
            if sc.chance and sc.chance > 0 then
                extra = " (" .. AP.FormatChance(sc.chance) .. ")"
            end
            tt:AddLine("  |cffd8c8a8[" .. sType .. "]|r " .. ((sc.name and sc.name ~= "") and sc.name or "?") .. zPart .. extra, 0.92, 0.90, 0.85, true)
        end
        shown = shown + 1
    end
end

---------------------------------------------------------------------------
-- 3. Главное окно AttuneParser (4 вкладки: Топ инстов, Обзор и Дары, Сумки и Ковка, Настройки)
---------------------------------------------------------------------------
local mainFrame

local function RefreshHeaderAndFooter()
    if not mainFrame or not mainFrame:IsShown() then return end
    local bi = AP.Data and AP.Data.BuildInfo or {}
    local gift = AP:GetActiveDailyGift(false)
    local ms = AP:GetMilestonesSummary()
    local talLoaded, talTtpOn, talActive, talOff = false, true, AP:IsTalorianBridgeActive(), (AP:GetSetting("talorianMode") == "off")
    if type(AP.GetTalorianStatus) == "function" then
        talLoaded, talTtpOn, talActive, talOff = AP:GetTalorianStatus()
    else
        talLoaded = (AP._talorianBridge ~= nil) or (type(rawget(_G, "TalorianTP")) == "table")
        talTtpOn = not (type(_G.TalorianTP_DB) == "table" and _G.TalorianTP_DB.enabled == false)
    end
    local talStr = talActive and "|cff40ff40Талориан: ВКЛ|r"
        or (talOff and "|cff94a3b8Талориан: Выкл|r"
        or ((talLoaded and not talTtpOn) and "|cffffd200Талориан: Выкл (/ttp)|r" or "|cff94a3b8Автономный режим|r"))

    local gStr = gift.active and ("|cffa855f7" .. (gift.name or "Дар") .. "|r (" .. (gift.remText or "?") .. ")") or "|cff94a3b8Дар не активен|r"
    mainFrame.subText:SetText(string.format("v%s | База: %d предм. | %s | %s", tostring(AP.VERSION), tonumber(bi.items) or 0, gStr, talStr))

    local showHeaderLinks = (type(AP.IsBlockEnabled) ~= "function") or AP:IsBlockEnabled("blkHeaderLinks")
    if showHeaderLinks then
        if ms.claimable and ms.claimable > 0 then
            mainFrame.claimBtn.label:SetText("Вехи (+" .. ms.claimable .. ")")
            PS.PaintBtn(mainFrame.claimBtn, "green")
        else
            mainFrame.claimBtn.label:SetText("Вехи")
            PS.PaintBtn(mainFrame.claimBtn, "dark")
        end
        mainFrame.claimBtn:Show()
        mainFrame.ejBtn:Show()
        mainFrame.atlasBtn:Show()
        if talActive or talLoaded then
            mainFrame.talBtn:Show()
        else
            mainFrame.talBtn:Hide()
        end
        if rawget(_G, "AttuneAtlas_Toggle") then
            PS.PaintBtn(mainFrame.atlasBtn, "dark")
        else
            PS.PaintBtn(mainFrame.atlasBtn, "gray")
        end
    else
        mainFrame.claimBtn:Hide()
        mainFrame.ejBtn:Hide()
        mainFrame.atlasBtn:Hide()
        mainFrame.talBtn:Hide()
    end

    if mainFrame.RelayoutTabs then
        mainFrame.RelayoutTabs()
    end

    for key, btn in pairs(mainFrame.tabBtns) do
        PS.PaintBtn(btn, (mainFrame.activeTab == key) and "gold" or "dark")
    end
end

local function CreateLocationDropdown(parentBox, anchorBtn, onSelectFn)
    local pop = CreateFrame("Frame", nil, parentBox)
    pop:SetSize(256, 236)
    pop:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
    pop:SetFrameStrata("DIALOG")
    pop:EnableMouse(true)
    pop:Hide()
    PS.StyleBox(pop, 0.96, true)

    local rows = {}
    local entries = {}
    local VIS = 10
    local RH = 22
    local sf
    sf = PS.AttachScroll(pop, VIS * RH, RH, VIS, function(offArg)
        local off = offArg or (sf and sf.offset) or 0
        for i = 1, VIS do
            local r = rows[i]
            local ent = entries[off + i]
            if ent then
                r._ent = ent
                r.txt:SetText(ent.label)
                r:Show()
            else
                r._ent = nil
                r:Hide()
            end
        end
    end)
    sf:SetPoint("TOPLEFT", pop, "TOPLEFT", 4, -6)
    sf:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -4, 6)

    for i = 1, VIS do
        local r = CreateFrame("Button", nil, sf)
        r:SetHeight(RH - 1)
        r:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i - 1) * RH)
        r:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -16, -(i - 1) * RH)
        PS.StyleScrollRow(r, (i % 2) == 1)

        r.txt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.txt:SetPoint("LEFT", r, "LEFT", 6, 0)
        r.txt:SetPoint("RIGHT", r, "RIGHT", -6, 0)
        r.txt:SetHeight(16)
        r.txt:SetJustifyH("LEFT")
        if r.txt.SetWordWrap then r.txt:SetWordWrap(false) end

        r:SetScript("OnClick", function(self)
            local ent = self._ent
            pop:Hide()
            if ent and onSelectFn then onSelectFn(ent) end
        end)
        rows[i] = r
    end

    function pop:OpenEntries(newEntries)
        entries = newEntries or {}
        sf:SetTotal(#entries, false)
        pop:Show()
    end

    return pop
end

-- Вкладка 1: Топ инстов / Без ур. (1-lvl)
local function FormatShortStat(v)
    v = math.floor(tonumber(v) or 0)
    if v >= 100000 then
        return tostring(math.floor(v / 1000 + 0.5)) .. "к"
    elseif v >= 1000 then
        local s = string.format("%.1f", v / 1000):gsub("%.0$", "")
        return s .. "к"
    end
    return tostring(v)
end

local DIFF_NAMES_4 = { [1] = "10 об", [2] = "25 об", [3] = "10 гер", [4] = "25 гер" }
local DIFF_NAMES_2R = { [1] = "10 об", [2] = "25 об" }
local DIFF_NAMES_2D = { [1] = "Обыч.", [2] = "Героич." }

local function FormatTopDiffLabel(diffF, kindF)
    if not diffF or diffF <= 0 then return "Все" end
    if kindF == "Dungeon" then
        return DIFF_NAMES_2D[diffF] or DIFF_NAMES_4[diffF] or "Все"
    end
    return DIFF_NAMES_4[diffF] or "Все"
end

local function FormatZoneSubline(z, diffF)
    local kindTxt = z.isRaid and "|cffff8000Рейд|r" or "|cff38bdf8Данж|r"
    local eraTxt = (z.exp == 3 and "WotLK") or (z.exp == 2 and "TBC") or (z.exp == 1 and "Classic") or ""
    local prefix = (eraTxt ~= "") and (kindTxt .. " |cff94a3b8(" .. eraTxt .. ")|r") or kindTxt
    if diffF and diffF > 0 then
        local maxD = z.maxDiffs or 4
        local dLbl = (maxD == 4 and DIFF_NAMES_4[diffF]) or (z.isRaid and DIFF_NAMES_2R[diffF]) or DIFF_NAMES_2D[diffF] or DIFF_NAMES_4[diffF] or "?"
        return prefix .. " |cff94a3b8- " .. dLbl .. "|r"
    end
    if z.isSingleDiff or not z.byDiff then
        return prefix .. " |cff64748b- 1 сложность|r"
    end
    local maxD = z.maxDiffs or 4
    local parts = {}
    for d = 1, maxD do
        local bd = z.byDiff[d]
        local rem = bd and ((bd.newCount or 0) + (bd.forgeCount or 0)) or 0
        if rem > 0 then
            local lbl = (maxD == 4 and DIFF_NAMES_4[d]) or (z.isRaid and DIFF_NAMES_2R[d]) or DIFF_NAMES_2D[d] or tostring(d)
            local col = (d >= 3 or (maxD == 2 and not z.isRaid and d == 2)) and "|cffffd200" or "|cff94a3b8"
            table.insert(parts, col .. lbl .. ":" .. rem .. "|r")
        end
    end
    if #parts == 0 then return prefix end
    return prefix .. " | " .. table.concat(parts, " ")
end

local function UpdateRowProgressBar(r, done, total)
    done = tonumber(done) or 0
    total = tonumber(total) or 0
    if total <= 0 then
        r.progBg:Hide()
        return
    end
    r.progBg:Show()
    local pct = math.min(100, math.max(0, math.floor((done / total) * 100 + 0.5)))
    if pct <= 0 then
        r.progFill:Hide()
    else
        r.progFill:Show()
        r.progFill:SetWidth(math.max(2, math.floor(170 * pct / 100 + 0.5)))
        if pct >= 75 then
            r.progFill:SetVertexColor(0.20, 0.78, 0.35, 0.85)
        elseif pct >= 35 then
            r.progFill:SetVertexColor(0.16, 0.66, 0.88, 0.85)
        else
            r.progFill:SetVertexColor(0.86, 0.58, 0.16, 0.85)
        end
    end
    r.progTxt:SetText(string.format("%d%% (%d/%d)", pct, done, total))
end

local function CreateTopRow(sf, i)
    local r = CreateFrame("Button", nil, sf)
    r:SetHeight(35)
    r:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i - 1) * 38)
    r:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -16, -(i - 1) * 38)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    PS.StyleScrollRow(r, (i % 2) == 1)

    r.idxTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.idxTxt:SetPoint("LEFT", r, "LEFT", 6, 0)
    r.idxTxt:SetSize(24, 16)
    r.idxTxt:SetJustifyH("LEFT")
    if r.idxTxt.SetWordWrap then r.idxTxt:SetWordWrap(false) end

    r.icBox = CreateFrame("Frame", nil, r)
    r.icBox:SetSize(28, 28)
    r.icBox:SetPoint("LEFT", r.idxTxt, "RIGHT", 4, 0)
    PS.StyleBox(r.icBox, 0.75, false)
    r.ic = r.icBox:CreateTexture(nil, "ARTWORK")
    r.ic:SetPoint("TOPLEFT", 2, -2)
    r.ic:SetPoint("BOTTOMRIGHT", -2, 2)
    r.ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    r.nameTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.nameTxt:SetPoint("TOPLEFT", r.icBox, "TOPRIGHT", 8, -1)
    r.nameTxt:SetSize(296, 15)
    r.nameTxt:SetJustifyH("LEFT")
    if r.nameTxt.SetWordWrap then r.nameTxt:SetWordWrap(false) end

    r.subTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.subTxt:SetPoint("BOTTOMLEFT", r.icBox, "BOTTOMRIGHT", 8, 0)
    r.subTxt:SetSize(296, 13)
    r.subTxt:SetJustifyH("LEFT")
    if r.subTxt.SetWordWrap then r.subTxt:SetWordWrap(false) end

    r.cntTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.cntTxt:SetPoint("TOPLEFT", r.nameTxt, "TOPRIGHT", 8, 0)
    r.cntTxt:SetSize(174, 14)
    r.cntTxt:SetJustifyH("LEFT")
    if r.cntTxt.SetWordWrap then r.cntTxt:SetWordWrap(false) end

    r.progBg = CreateFrame("Frame", nil, r)
    r.progBg:SetPoint("TOPLEFT", r.cntTxt, "BOTTOMLEFT", 0, -2)
    r.progBg:SetSize(172, 12)
    PS.StyleBox(r.progBg, 0.78, false)

    r.progFill = r.progBg:CreateTexture(nil, "ARTWORK")
    r.progFill:SetPoint("TOPLEFT", r.progBg, "TOPLEFT", 1, -1)
    r.progFill:SetPoint("BOTTOMLEFT", r.progBg, "BOTTOMLEFT", 1, 1)
    r.progFill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    r.progFill:SetWidth(1)

    r.progTxt = r.progBg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.progTxt:SetAllPoints(r.progBg)
    r.progTxt:SetJustifyH("CENTER")
    r.progTxt:SetJustifyV("MIDDLE")

    r.tpBtn = PS.MakeBtn(r, 34, 22, "ТП", "green")
    r.tpBtn:SetPoint("RIGHT", r, "RIGHT", -5, 0)

    r.ejBtn = PS.MakeBtn(r, 46, 22, "Гид", "dark")
    r.ejBtn:SetPoint("RIGHT", r.tpBtn, "LEFT", -4, 0)

    r.statTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.statTxt:SetPoint("RIGHT", r.ejBtn, "LEFT", -8, 0)
    r.statTxt:SetSize(76, 16)
    r.statTxt:SetJustifyH("RIGHT")
    if r.statTxt.SetWordWrap then r.statTxt:SetWordWrap(false) end

    return r
end

local function RenderTopRow(r, rankIdx, d, topMode, diffF, talActive)
    if not d then
        r._rowData = nil
        r:Hide()
        return
    end
    r._rowData = d
    r:Show()
    r.idxTxt:SetText(string.format("|cffb0a080#%d|r", rankIdx))
    if d.kind == "zone" then
        local z = d.zone
        if r.ic then
            local icPath = (type(AP.GetZoneIcon) == "function") and AP:GetZoneIcon(z.zoneId, z.isRaid, true) or "Interface\\Icons\\INV_Misc_Map_01"
            r.ic:SetTexture(icPath)
        end
        if z.isLocked then
            r.icBox:SetBackdropBorderColor(0.95, 0.25, 0.25, 0.85)
        elseif z.isRaid then
            r.icBox:SetBackdropBorderColor(1.0, 0.55, 0.15, 0.70)
        else
            r.icBox:SetBackdropBorderColor(0.22, 0.74, 0.97, 0.70)
        end

        local nameCol = z.isRaid and "|cffff9030" or "|cff60c8fa"
        local cdTag = z.isLocked and " |cffff5050[КД]|r" or ""
        local ownTag = (d.ownedCount and d.ownedCount > 0) and (" |cff40ff40[Есть: " .. d.ownedCount .. "]|r") or ""
        r.nameTxt:SetText(nameCol .. (z.zoneName or "?") .. "|r" .. cdTag .. ownTag)
        r.subTxt:SetText(FormatZoneSubline(z, diffF))

        if topMode == "forge" or topMode == "wednesday" then
            local fb = z.forgeByTier or {}
            local tParts = {}
            if (fb[0] or 0) > 0 then table.insert(tParts, "|cffa335eeОб:" .. fb[0] .. "|r") end
            if (fb[1] or 0) > 0 then table.insert(tParts, "|cffff8000Эп:" .. fb[1] .. "|r") end
            if (fb[2] or 0) > 0 then table.insert(tParts, "|cff38bdf8Лг:" .. fb[2] .. "|r") end
            local tStr = (#tParts > 0) and (" | " .. table.concat(tParts, " ")) or ""
            r.cntTxt:SetText(string.format("|cffffd200Ковка: %d|r%s", z.forgeCount or 0, tStr))
            r.statTxt:SetText("|cffffd200+" .. FormatShortStat(z.forgeRemainStats or 0) .. "|r")
        else
            local nrNote = ((z.noReqCount or 0) > 0) and (" |cff94a3b8| 1у:" .. z.noReqCount .. "|r") or ""
            r.cntTxt:SetText(string.format("|cff40ff40Нов: %d|r |cffffd200Ков: %d|r%s",
                z.newCount or 0, z.forgeCount or 0, nrNote))
            r.statTxt:SetText("|cff40ff40+" .. FormatShortStat(z.newMaxStats or 0) .. "|r")
        end
        UpdateRowProgressBar(r, z.completedCount, z.totalPool)

        r.ejBtn:Show()
        if talActive then
            r.tpBtn:Show()
            r.ejBtn:ClearAllPoints()
            r.ejBtn:SetPoint("RIGHT", r.tpBtn, "LEFT", -4, 0)
        else
            r.tpBtn:Hide()
            r.ejBtn:ClearAllPoints()
            r.ejBtn:SetPoint("RIGHT", r, "RIGHT", -5, 0)
        end
        r.statTxt:ClearAllPoints()
        r.statTxt:SetPoint("RIGHT", r.ejBtn, "LEFT", -8, 0)
    elseif d.kind == "noreq" then
        local it = d.item
        local tz = it.resolvedZone or it.primaryZone
        if r.ic then
            local iTex = (type(GetItemIcon) == "function" and it.itemId and GetItemIcon(it.itemId)) or select(10, GetItemInfo(it.link or it.itemId))
            r.ic:SetTexture(iTex or "Interface\\Icons\\INV_Misc_QuestionMark")
        end
        r.icBox:SetBackdropBorderColor(0.25, 0.85, 0.45, 0.70)
        local stateTag = it.isNew and "|cff40ff40[Нов]|r " or ("|cffffd200[" .. (it.curPct or 0) .. "%]|r ")
        local dTag = (it.isInstanceZone and AP.GetItemDiffTag and tz) and AP:GetItemDiffTag(it.itemId, tz, it.diffMask, false) or ""
        local dStr = (dTag ~= "") and ("|cff94a3b8[" .. dTag .. "]|r ") or ""
        r.nameTxt:SetText(stateTag .. dStr .. ShortItemLink(it.itemId, it.name, it.quality))
        r.subTxt:SetText(string.format("|cff94a3b8%s|r | ilvl %d | ур. %d",
            tostring(it.zoneName or "Мир / Квест"), it.ilvl or 0, it.reqLvl or 0))
        r.cntTxt:SetText(it.isNew and "|cff40ff40Не поглощен|r" or string.format("|cffffd200Поглощено %d%% -> 90%%|r", it.curPct or 0))
        UpdateRowProgressBar(r, it.curPct or 0, 90)
        r.statTxt:SetText("|cff40ff40+" .. FormatShortStat(it.totalRemainStats or 0) .. "|r")
        r.tpBtn:Hide()
        if it.isInstanceZone and tz and tz > 0 then
            r.ejBtn:Show()
            r.ejBtn:ClearAllPoints()
            r.ejBtn:SetPoint("RIGHT", r, "RIGHT", -5, 0)
            r.statTxt:ClearAllPoints()
            r.statTxt:SetPoint("RIGHT", r.ejBtn, "LEFT", -8, 0)
        else
            r.ejBtn:Hide()
            r.statTxt:ClearAllPoints()
            r.statTxt:SetPoint("RIGHT", r, "RIGHT", -8, 0)
        end
    end
end

local function BuildTopTab(parent)
    local box = CreateFrame("Frame", nil, parent)
    box:SetAllPoints(parent)
    box.rows = {}
    box.data = {}
    box.locMode = "ALL"
    box.locZoneId = nil
    box.locLabel = "Все"
    box.searchQuery = ""
    box.lastZones = {}

    local filterBar = CreateFrame("Frame", nil, box)
    filterBar:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    filterBar:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
    filterBar:SetHeight(58)
    PS.StyleBox(filterBar, 0.50, false)

    -- Строка 1: Режимы + Обхват + Обновить + Сброс
    local modeDefs = {
        { key = "new", label = "Новые", w = 82 },
        { key = "forge", label = "Ковка -> 90%", w = 104 },
        { key = "wednesday", label = "Дар среды", w = 96 },
        { key = "noreq", label = "Без ур. (1)", w = 94 },
    }
    local modeBtns = {}
    local mx = 8
    for _, md in ipairs(modeDefs) do
        local b = PS.MakeBtn(filterBar, md.w, 22, md.label, "dark")
        b:SetPoint("TOPLEFT", filterBar, "TOPLEFT", mx, -6)
        mx = mx + md.w + 6
        b:SetScript("OnClick", function()
            AP:SetSetting("topMode", md.key)
            box.RefreshData()
        end)
        modeBtns[md.key] = b
    end

    local resetBtn = PS.MakeBtn(filterBar, 64, 22, "Сброс", "dark")
    resetBtn:SetPoint("TOPRIGHT", filterBar, "TOPRIGHT", -6, -6)

    local syncBtn = PS.MakeBtn(filterBar, 82, 22, "Обновить", "green")
    syncBtn:SetPoint("RIGHT", resetBtn, "LEFT", -5, 0)
    syncBtn:SetScript("OnClick", function()
        AP:RequestServerSync(true)
        if type(RequestRaidInfo) == "function" then pcall(RequestRaidInfo) end
        AP.After(0.5, function() box.RefreshData() end, "ap_ui_sync")
    end)

    local scopeBtn = PS.MakeBtn(filterBar, 96, 22, "Персонаж", "dark")
    scopeBtn:SetPoint("RIGHT", syncBtn, "LEFT", -5, 0)
    scopeBtn:SetScript("OnClick", function()
        local cur = AP:GetSetting("scope")
        AP:SetSetting("scope", (cur == "account") and "hero" or "account")
        box.RefreshData()
    end)

    -- Строка 2: Категория + Эра + Сложность/Локация + КД + Квесты + Сорт + Поиск
    local kindBtn = PS.MakeBtn(filterBar, 92, 20, "Тип: Все", "dark")
    box._kindBtn = kindBtn
    kindBtn:SetPoint("TOPLEFT", filterBar, "TOPLEFT", 8, -32)
    kindBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    kindBtn:SetScript("OnClick", function(_, mBtn)
        if mBtn == "RightButton" then
            AP:SetSetting("kindFilter", "All")
            box.RefreshData()
            return
        end
        local c = AP:GetSetting("kindFilter")
        local tm = AP:GetSetting("topMode")
        local nxt
        if tm == "noreq" then
            nxt = (c == "All" and "Raid") or (c == "Raid" and "Dungeon") or (c == "Dungeon" and "World") or "All"
        else
            nxt = (c == "All" and "Raid") or (c == "Raid" and "Dungeon") or "All"
        end
        AP:SetSetting("kindFilter", nxt)
        if nxt == "Dungeon" and (tonumber(AP:GetSetting("diffFilter")) or 0) > 2 then
            AP:SetSetting("diffFilter", 0)
        end
        box.RefreshData()
    end)

    local eraBtn = PS.MakeBtn(filterBar, 88, 20, "Эра: Все", "dark")
    eraBtn:SetPoint("LEFT", kindBtn, "RIGHT", 4, 0)
    eraBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    eraBtn:SetScript("OnClick", function(_, mBtn)
        if mBtn == "RightButton" then
            AP:SetSetting("eraFilter", "All")
            box.RefreshData()
            return
        end
        local c = AP:GetSetting("eraFilter")
        local nxt = (c == "All" and "WotLK") or (c == "WotLK" and "TBC") or (c == "TBC" and "Classic") or "All"
        AP:SetSetting("eraFilter", nxt)
        box.RefreshData()
    end)

    local diffBtn = PS.MakeBtn(filterBar, 110, 20, "Слож.: Все", "dark")
    box._diffBtn = diffBtn
    diffBtn:SetPoint("LEFT", eraBtn, "RIGHT", 4, 0)
    diffBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    diffBtn:SetScript("OnClick", function(_, mBtn)
        if mBtn == "RightButton" then
            AP:SetSetting("diffFilter", 0)
            box.RefreshData()
            return
        end
        local cur = tonumber(AP:GetSetting("diffFilter")) or 0
        local maxCycle = (AP:GetSetting("kindFilter") == "Dungeon") and 2 or 4
        local nxt = (cur >= maxCycle) and 0 or (cur + 1)
        AP:SetSetting("diffFilter", nxt)
        box.RefreshData()
    end)

    local locBtn = PS.MakeBtn(filterBar, 110, 20, "Локация: Все", "dark")
    locBtn:SetPoint("LEFT", eraBtn, "RIGHT", 4, 0)
    locBtn.label:SetWidth(98)
    if locBtn.label.SetWordWrap then locBtn.label:SetWordWrap(false) end
    locBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    locBtn:Hide()

    local locMenu = CreateLocationDropdown(box, locBtn, function(ent)
        box.locMode = ent.mode or "ALL"
        box.locZoneId = ent.zoneId
        box.locLabel = ent.shortLabel or "Все"
        box.RefreshData()
    end)
    box._locMenu = locMenu

    locBtn:SetScript("OnClick", function(_, mBtn)
        if mBtn == "RightButton" then
            locMenu:Hide()
            box.locMode = "ALL"
            box.locZoneId = nil
            box.locLabel = "Все"
            box.RefreshData()
            return
        end
        if locMenu:IsShown() then locMenu:Hide(); return end
        local items = {
            { label = "|cffffffffВсе локации|r", shortLabel = "Все", mode = "ALL" },
            { label = "|cff38bdf8Только инсты (Рейды и Данжи)|r", shortLabel = "Только инсты", mode = "INST" },
            { label = "|cff40ff40Открытый мир / квесты|r", shortLabel = "Открытый мир", mode = "WORLD" },
        }
        for _, zEntry in ipairs(box.lastZones or {}) do
            local col = zEntry.isInst and "|cffffd200" or "|cff98fb98"
            table.insert(items, {
                label = string.format("%s%s|r |cff94a3b8(%d)|r", col, zEntry.name, zEntry.count),
                shortLabel = zEntry.name,
                mode = "ZONE",
                zoneId = zEntry.zoneId,
            })
        end
        locMenu:OpenEntries(items)
    end)

    local cdBtn = PS.MakeBtn(filterBar, 64, 20, "Без КД", "dark")
    cdBtn:SetPoint("LEFT", diffBtn, "RIGHT", 4, 0)
    cdBtn:SetScript("OnClick", function()
        AP:SetSetting("onlyUnlocked", not AP:GetSetting("onlyUnlocked"))
        box.RefreshData()
    end)

    local hqBtn = PS.MakeBtn(filterBar, 68, 20, "Без кв.", "dark")
    hqBtn:SetPoint("LEFT", cdBtn, "RIGHT", 4, 0)
    hqBtn:SetScript("OnClick", function()
        AP:SetSetting("excludeHeavyQuests", not AP:GetSetting("excludeHeavyQuests"))
        box.RefreshData()
    end)
    hqBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("|cffffd200Фильтр редких квестов|r")
        GameTooltip:AddLine("Скрывает предметы с долгими или сложными цепочками заданий при подсчете инстов.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    hqBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local sortBtn = PS.MakeBtn(filterBar, 102, 20, "Сорт: Рейтинг", "dark")
    sortBtn:SetPoint("LEFT", hqBtn, "RIGHT", 4, 0)
    sortBtn:SetScript("OnClick", function()
        local c = AP:GetSetting("sortBy")
        local nxt = (c == "default" and "count") or (c == "count" and "stats") or "default"
        AP:SetSetting("sortBy", nxt)
        box.RefreshData()
    end)

    local searchWrap = CreateFrame("Frame", nil, filterBar)
    searchWrap:SetPoint("LEFT", sortBtn, "RIGHT", 4, 0)
    searchWrap:SetPoint("RIGHT", filterBar, "RIGHT", -6, 0)
    searchWrap:SetHeight(20)
    PS.StyleBox(searchWrap, 0.72, false)

    local searchEdit = CreateFrame("EditBox", nil, searchWrap)
    searchEdit:SetPoint("TOPLEFT", searchWrap, "TOPLEFT", 6, -2)
    searchEdit:SetPoint("BOTTOMRIGHT", searchWrap, "BOTTOMRIGHT", -20, 2)
    searchEdit:SetFontObject(GameFontHighlightSmall)
    searchEdit:SetAutoFocus(false)
    searchEdit:SetMaxLetters(48)

    local searchPh = searchWrap:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPh:SetPoint("LEFT", searchWrap, "LEFT", 6, 0)
    searchPh:SetText("Поиск инста или вещи...")

    local searchClr = PS.MakeBtn(searchWrap, 18, 18, "x", "dark")
    searchClr:SetPoint("RIGHT", searchWrap, "RIGHT", -1, 0)
    searchClr:Hide()
    searchClr:SetScript("OnClick", function()
        searchEdit:SetText("")
        searchEdit:ClearFocus()
    end)

    searchEdit:SetScript("OnTextChanged", function(self)
        local t = (self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if t == "" then
            searchPh:Show(); searchClr:Hide()
        else
            searchPh:Hide(); searchClr:Show()
        end
        if box.searchQuery ~= t then
            box.searchQuery = t
            AP.After(0.08, function() box.RefreshData() end, "ap_ui_search_deb")
        end
    end)
    searchEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    resetBtn:SetScript("OnClick", function()
        AP:SetSetting("kindFilter", "All")
        AP:SetSetting("eraFilter", "All")
        AP:SetSetting("diffFilter", 0)
        AP:SetSetting("onlyUnlocked", false)
        box.locMode = "ALL"
        box.locZoneId = nil
        box.locLabel = "Все"
        box.searchQuery = ""
        searchEdit:SetText("")
        locMenu:Hide()
        box.RefreshData()
    end)

    local listBox = CreateFrame("Frame", nil, box)
    listBox:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -6)
    listBox:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 20)
    PS.StyleBox(listBox, 0.36, false)

    local statusFoot = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusFoot:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 4, 3)
    statusFoot:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -4, 3)
    statusFoot:SetJustifyH("LEFT")

    local VIS = 10
    local ROW_H = 38
    local sf = PS.AttachScroll(listBox, VIS * ROW_H, ROW_H, VIS, function() box.RenderRows() end)
    sf:SetPoint("TOPLEFT", listBox, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -4, 4)
    box.sf = sf

    for i = 1, VIS do
        local r = CreateTopRow(sf, i)
        r.tpBtn:SetScript("OnClick", function(btn)
            local d = btn:GetParent()._rowData
            if d and d.kind == "zone" then
                AP:SelectZoneInTalorian(d.zone.zoneId, d.zone.zoneName)
                AP:OpenTalorianUI()
            end
        end)
        r.ejBtn:SetScript("OnClick", function(btn)
            local d = btn:GetParent()._rowData
            if not d then return end
            if d.kind == "zone" and type(AP.OpenEncounterJournal) == "function" then
                AP:OpenEncounterJournal(d.zone.zoneId or d.zone.zoneName)
            elseif d.kind == "noreq" and d.item and d.item.isInstanceZone and type(AP.OpenEncounterJournal) == "function" then
                local tz = d.item.resolvedZone or d.item.primaryZone
                if tz and tz > 0 then
                    AP:OpenEncounterJournal(tz, d.item.itemId, d.item.diffMask)
                end
            end
        end)
        r.ejBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Открыть в Путеводителе")
            GameTooltip:Show()
        end)
        r.ejBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        r:SetScript("OnClick", function(self, mouseBtn)
            local d = self._rowData
            if not d then return end
            if d.kind == "noreq" then
                local it = d.item
                if (IsShiftKeyDown() or IsControlKeyDown() or (IsModifiedClick and IsModifiedClick("CHATLINK"))) and it.itemId then
                    AP:InsertItemLink(it.itemId, it.link or it.sfx, it.name, it.quality)
                    return
                end
                local tz = it.resolvedZone or it.primaryZone
                if it.isInstanceZone and tz and tz > 0 and type(AP.OpenEncounterJournal) == "function" then
                    AP:OpenEncounterJournal(tz, it.itemId, it.diffMask)
                end
            elseif d.kind == "zone" then
                if mouseBtn == "RightButton" and AP:IsTalorianBridgeActive() then
                    AP:SelectZoneInTalorian(d.zone.zoneId, d.zone.zoneName)
                elseif type(AP.OpenEncounterJournal) == "function" then
                    AP:OpenEncounterJournal(d.zone.zoneId or d.zone.zoneName)
                end
            end
        end)

        r:SetScript("OnEnter", function(self)
            local d = self._rowData
            if not d then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if d.kind == "zone" then
                local z = d.zone
                local zCol = z.isRaid and "|cffff8000" or "|cff38bdf8"
                GameTooltip:SetText(zCol .. (z.zoneName or "?") .. "|r")
                local pct = (z.totalPool and z.totalPool > 0) and math.floor(((z.completedCount or 0) / z.totalPool) * 100 + 0.5) or 0
                GameTooltip:AddLine(string.format("%s | Прогресс: %d%% (%d/%d) | %s",
                    z.isRaid and "Рейд" or "Подземелье",
                    pct, z.completedCount or 0, z.totalPool or 0,
                    z.isLocked and "|cffff5050Есть КД|r" or "|cff40ff40Свободно (без КД)|r"
                ), 0.9, 0.9, 0.9)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(string.format("Новых вещей: |cff40ff40%d|r (сразу +%d, макс +%d стат)",
                    z.newCount or 0, z.newImmediateStats or 0, z.newMaxStats or 0), 1, 1, 1)
                GameTooltip:AddLine(string.format("До Титана 90%% (Ковка): |cffffd200%d|r (ост. +%d стат)",
                    z.forgeCount or 0, z.forgeRemainStats or 0), 1, 1, 1)
                local fb = z.forgeByTier or {}
                if (fb[0] or 0) + (fb[1] or 0) + (fb[2] or 0) > 0 then
                    GameTooltip:AddLine(string.format("  Разбивка ковки: Обычный=%d, Эпический=%d, Легендарный=%d",
                        fb[0] or 0, fb[1] or 0, fb[2] or 0), 0.85, 0.82, 0.72)
                end
                if z.byDiff and type(z.byDiff) == "table" then
                    local hasDiff = false
                    local maxD = z.maxDiffs or 4
                    for dId, df in pairs(z.byDiff) do
                        if (df.newCount or 0) + (df.forgeCount or 0) > 0 then
                            if not hasDiff then
                                GameTooltip:AddLine(" ")
                                GameTooltip:AddLine("|cffffd200По сложностям:|r", 1, 1, 1)
                                hasDiff = true
                            end
                            local dLbl = (maxD == 4 and DIFF_NAMES_4[dId]) or (z.isRaid and DIFF_NAMES_2R[dId]) or DIFF_NAMES_2D[dId] or ("Слож. " .. tostring(dId))
                            GameTooltip:AddLine(string.format("  %s: нов=%d, ковка=%d, +стат=%d",
                                dLbl, df.newCount or 0, df.forgeCount or 0, df.remainStats or 0), 0.85, 0.85, 0.85)
                        end
                    end
                end
                if d.ownedCount and d.ownedCount > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff40ff40Уже есть у вас (сумки, банк или сборщик): " .. d.ownedCount .. " шт.|r", 1, 1, 1)
                    for oi = 1, math.min(4, #d.ownedList) do
                        local oit = d.ownedList[oi]
                        GameTooltip:AddLine("  [" .. FormatLocation(oit.where) .. "] " .. ShortItemLink(oit.itemId, oit.name, oit.quality) .. " (+" .. (oit.gainNowStats or 0) .. " стат)", 1, 1, 1)
                    end
                end
                GameTooltip:AddLine(" ")
                local hint = "|cff94a3b8ЛКМ / Гид: Путеводитель"
                if AP:IsTalorianBridgeActive() then
                    hint = hint .. " | ПКМ / ТП: Выбрать в Талориане"
                end
                GameTooltip:AddLine(hint .. "|r", 1, 1, 1)
            elseif d.kind == "noreq" then
                local it = d.item
                local tz = it.resolvedZone or it.primaryZone
                local isInst = it.isInstanceZone == true
                AP:BuildItemTooltip(GameTooltip, it.itemId, {
                    sfx = it.sfx, link = it.link, name = it.name, quality = it.quality,
                    zoneId = tz, diffMask = it.diffMask, maxSources = 6,
                    hint = isInst
                        and "|cff94a3b8Shift+ЛКМ: ссылка в чат | Ctrl+ЛКМ: примерить | ЛКМ: Открыть в Путеводителе|r"
                        or "|cff94a3b8Shift+ЛКМ: ссылка в чат | Ctrl+ЛКМ: примерить|r",
                })
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)

        box.rows[i] = r
    end

    function box.RenderRows()
        local off = sf.offset or 0
        local talActive = AP:IsTalorianBridgeActive()
        local topMode = AP:GetSetting("topMode")
        local diffF = tonumber(AP:GetSetting("diffFilter")) or 0
        for i = 1, VIS do
            RenderTopRow(box.rows[i], off + i, box.data[off + i], topMode, diffF, talActive)
        end
    end

    function box.RefreshData()
        local topMode = AP:GetSetting("topMode")
        local scope = AP:GetSetting("scope")
        local kindF = AP:GetSetting("kindFilter")
        local eraF = AP:GetSetting("eraFilter")
        local diffF = tonumber(AP:GetSetting("diffFilter")) or 0
        local onlyUnl = AP:GetSetting("onlyUnlocked") == true
        local exclHeavy = AP:GetSetting("excludeHeavyQuests") ~= false
        local sortBy = AP:GetSetting("sortBy")

        if topMode ~= "noreq" and kindF == "World" then
            kindF = "All"
        end
        if kindF == "Dungeon" and diffF > 2 then
            diffF = 0
            AP:SetSetting("diffFilter", 0)
        end

        local gift = AP:GetActiveDailyGift(false)
        if not AP._wedAutoApplied and AP:GetSetting("wedAuto") ~= false and gift.isWednesday then
            AP._wedAutoApplied = true
            if topMode == "new" then
                topMode = "wednesday"
                AP:EnsureSettings().topMode = "wednesday"
            end
        end

        for key, b in pairs(modeBtns) do
            if key == "wednesday" and gift.isWednesday and topMode ~= "wednesday" then
                PS.PaintBtn(b, "green")
            else
                PS.PaintBtn(b, (topMode == key) and "gold" or "dark")
            end
        end
        scopeBtn.label:SetText((scope == "account") and "Аккаунт" or "Персонаж")
        PS.PaintBtn(scopeBtn, (scope == "account") and "gold" or "dark")

        local kLabels = { All = "Все", Raid = "Рейды", Dungeon = "Данжи", World = "Мир/Кв" }
        kindBtn.label:SetText("Тип: " .. (kLabels[kindF] or "Все"))
        PS.PaintBtn(kindBtn, (kindF ~= "All") and "gold" or "dark")
        eraBtn.label:SetText("Эра: " .. (ERA_LABELS[eraF] or "Все"))
        PS.PaintBtn(eraBtn, (eraF ~= "All") and "gold" or "dark")
        PS.PaintBtn(cdBtn, onlyUnl and "green" or "dark")
        PS.PaintBtn(hqBtn, exclHeavy and "green" or "dark")
        sortBtn.label:SetText("Сорт: " .. (sortBy == "count" and "Кол-во" or (sortBy == "stats" and "Статы" or "Рейтинг")))

        if topMode == "noreq" then
            diffBtn:Hide()
            locBtn:Show()
            locBtn.label:SetText("Локация: " .. tostring(box.locLabel or "Все"))
            PS.PaintBtn(locBtn, (box.locMode ~= "ALL") and "gold" or "dark")
        else
            locBtn:Hide()
            if locMenu then locMenu:Hide() end
            diffBtn:Show()
            diffBtn.label:SetText("Слож.: " .. FormatTopDiffLabel(diffF, kindF))
            PS.PaintBtn(diffBtn, (diffF > 0) and "gold" or "dark")
        end

        local lockedMap = AP:GetLockedZonesMap()
        local isRaidOpt = nil
        if kindF == "Raid" then
            isRaidOpt = true
        elseif kindF == "Dungeon" then
            isRaidOpt = false
        end
        local expOpt = ERA_EXP[eraF]
        local searchQ = (box.searchQuery and box.searchQuery ~= "") and AP.Norm(box.searchQuery) or nil
        local rows = {}
        local zoneCounts = {}

        if topMode == "noreq" then
            local nr = AP:GetNoReqLevelItems({
                scope = scope, exp = expOpt, isRaid = isRaidOpt,
                onlyWorld = (kindF == "World"),
                lockedZones = lockedMap, unlockedOnly = onlyUnl,
                excludeHeavyQuests = exclHeavy,
            })
            local allItems = {}
            for _, it in ipairs(nr.newItems or {}) do
                it.totalRemainStats = it.maxStatsGain or math.floor((it.coreStatsSum or 0) * ((it.remainPct or 90) / 100) + 0.5)
                table.insert(allItems, it)
            end
            for _, it in ipairs(nr.forgeItems or {}) do
                it.totalRemainStats = math.floor((it.coreStatsSum or 0) * ((it.remainPct or 0) / 100) + 0.5)
                table.insert(allItems, it)
            end
            for _, it in ipairs(allItems) do
                local tz = it.resolvedZone or it.primaryZone
                if tz and tz > 0 and it.zoneName then
                    local zRec = zoneCounts[tz]
                    if not zRec then
                        zRec = { zoneId = tz, name = it.zoneName, isInst = it.isInstanceZone == true, count = 0 }
                        zoneCounts[tz] = zRec
                    end
                    zRec.count = zRec.count + 1
                end
                local pass = true
                if box.locMode == "INST" and not it.isInstanceZone then
                    pass = false
                elseif box.locMode == "WORLD" and it.isInstanceZone then
                    pass = false
                elseif box.locMode == "ZONE" and box.locZoneId and tz ~= box.locZoneId then
                    pass = false
                end
                if pass and searchQ and searchQ ~= "" then
                    local ni = AP.Norm(it.name or "")
                    local nz = AP.Norm(it.zoneName or "")
                    if not (ni:find(searchQ, 1, true) or nz:find(searchQ, 1, true)) then
                        pass = false
                    end
                end
                if pass then
                    table.insert(rows, { kind = "noreq", item = it })
                end
            end
            if sortBy == "count" then
                table.sort(rows, function(a, b)
                    if (a.item.ilvl or 0) ~= (b.item.ilvl or 0) then return (a.item.ilvl or 0) > (b.item.ilvl or 0) end
                    return (a.item.totalRemainStats or 0) > (b.item.totalRemainStats or 0)
                end)
            else
                table.sort(rows, function(a, b)
                    if (a.item.totalRemainStats or 0) ~= (b.item.totalRemainStats or 0) then
                        return (a.item.totalRemainStats or 0) > (b.item.totalRemainStats or 0)
                    end
                    return (a.item.ilvl or 0) > (b.item.ilvl or 0)
                end)
            end
            local fltNote = (eraF ~= "All" and (" | Эра: " .. eraF) or "")
                .. (kindF ~= "All" and (" | Тип: " .. (kLabels[kindF] or kindF)) or "")
                .. (box.locMode ~= "ALL" and (" | Лок: " .. tostring(box.locLabel or "")) or "")
            statusFoot:SetText(string.format("|cffb0a080Без треб. ур. (req<=1):|r Показано: |cffffffff%d|r (из %d) | Завершено: %d%s",
                #rows, #allItems, nr.completedCount or 0, fltNote))
        else
            local list = AP:GetRecommendations({
                mode = topMode, scope = scope, onlyInstances = true,
                isRaid = isRaidOpt, exp = expOpt,
                diffId = (diffF > 0) and diffF or nil,
                lockedZones = lockedMap, unlockedOnly = onlyUnl,
                excludeHeavyQuests = exclHeavy, limit = 80,
            })
            if sortBy == "count" then
                table.sort(list, function(a, b)
                    local ca = (topMode == "forge" or topMode == "wednesday") and (a.forgeCount or 0) or ((a.newCount or 0) + (a.forgeCount or 0))
                    local cb = (topMode == "forge" or topMode == "wednesday") and (b.forgeCount or 0) or ((b.newCount or 0) + (b.forgeCount or 0))
                    if ca ~= cb then return ca > cb end
                    return (a.totalRemainStats or 0) > (b.totalRemainStats or 0)
                end)
            elseif sortBy == "stats" then
                table.sort(list, function(a, b)
                    local sa = (topMode == "forge" or topMode == "wednesday") and (a.forgeRemainStats or 0) or (a.newMaxStats or 0)
                    local sb = (topMode == "forge" or topMode == "wednesday") and (b.forgeRemainStats or 0) or (b.newMaxStats or 0)
                    if sa ~= sb then return sa > sb end
                    return (a.newCount or 0) > (b.newCount or 0)
                end)
            end
            local owned = AP:GetOwnedUpgradeCandidates()
            local ownedByZone = {}
            for _, oit in ipairs(owned) do
                if oit.primaryZone and oit.primaryZone > 0 then
                    ownedByZone[oit.primaryZone] = ownedByZone[oit.primaryZone] or {}
                    table.insert(ownedByZone[oit.primaryZone], oit)
                end
            end
            for _, z in ipairs(list) do
                if z.zoneId and z.zoneName then
                    zoneCounts[z.zoneId] = {
                        zoneId = z.zoneId, name = z.zoneName, isInst = true,
                        count = (z.newCount or 0) + (z.forgeCount or 0),
                    }
                end
                local pass = true
                if diffF > 0 and z.maxDiffs and diffF > z.maxDiffs then
                    pass = false
                end
                if pass and searchQ and searchQ ~= "" then
                    if not AP.Norm(z.zoneName or ""):find(searchQ, 1, true) then
                        pass = false
                    end
                end
                if pass then
                    local ol = ownedByZone[z.zoneId]
                    table.insert(rows, { kind = "zone", zone = z, ownedList = ol, ownedCount = ol and #ol or 0 })
                end
            end
            local lockedCnt = 0
            for _, r in ipairs(rows) do if r.zone.isLocked then lockedCnt = lockedCnt + 1 end end
            local diffNote = (diffF > 0) and (" | Слож.: " .. FormatTopDiffLabel(diffF, kindF)) or ""
            statusFoot:SetText(string.format("|cffb0a080Найдено инстов: %d|r (с КД: %d)%s | ЛКМ: Путеводитель%s",
                #rows, lockedCnt, diffNote, AP:IsTalorianBridgeActive() and ", ПКМ/ТП: Талориан" or ""))
        end

        local sortedZones = {}
        for _, ze in pairs(zoneCounts) do table.insert(sortedZones, ze) end
        table.sort(sortedZones, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return (a.name or "") < (b.name or "")
        end)
        box.lastZones = sortedZones

        box.data = rows
        sf:SetTotal(#rows, false)
    end

    box:SetScript("OnHide", function()
        if locMenu then locMenu:Hide() end
    end)

    return box
end

-- Вкладка 2: Обзор и Дары
local function BuildSummaryTab(parent)
    local box = CreateFrame("Frame", nil, parent)
    box:SetAllPoints(parent)

    local function MakeCard(x, y, w, h, title)
        local c = CreateFrame("Frame", nil, box)
        c:SetPoint("TOPLEFT", box, "TOPLEFT", x, y)
        c:SetSize(w, h)
        PS.StyleBox(c, 0.50, false)
        local hd = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hd:SetPoint("TOPLEFT", c, "TOPLEFT", 10, -8)
        hd:SetText("|cffffd200" .. title .. "|r")
        local dv = c:CreateTexture(nil, "ARTWORK")
        dv:SetTexture("Interface\\Buttons\\WHITE8X8")
        dv:SetVertexColor(1, 1, 1, 0.08)
        dv:SetHeight(1)
        dv:SetPoint("TOPLEFT", c, "TOPLEFT", 10, -24)
        dv:SetPoint("TOPRIGHT", c, "TOPRIGHT", -10, -24)
        c.body = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.body:SetPoint("TOPLEFT", c, "TOPLEFT", 10, -30)
        c.body:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -10, 34)
        c.body:SetJustifyH("LEFT")
        c.body:SetJustifyV("TOP")
        if c.body.SetSpacing then c.body:SetSpacing(3) end
        return c
    end

    local c1 = MakeCard(0, 0, 368, 224, "Каталог, Вехи и Помощник")
    local c2 = MakeCard(376, 0, 368, 224, "Бонус дня, Опыт и Пыль")
    local c3 = MakeCard(0, -232, 368, 212, "Уровень, Специализация и Автоматика")
    local c4 = MakeCard(376, -232, 368, 212, "Суммарные статы поглощения")
    box._c1 = c1
    box._c3 = c3
    box._c4 = c4

    local cardDefs = {
        { key = "blkSumCatalog", card = c1 },
        { key = "blkSumGiftsDust", card = c2 },
        { key = "blkSumParagonAuto", card = c3 },
        { key = "blkSumStats", card = c4 },
    }
    local emptyTxt = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyTxt:SetPoint("CENTER", box, "CENTER", 0, 10)
    emptyTxt:SetText("|cff94a3b8Все карточки раздела «Обзор и Дары» скрыты.\nВключите нужные в Настройках или командой /ap blocks.|r")
    emptyTxt:Hide()

    function box.RelayoutCards()
        local vis = {}
        for _, item in ipairs(cardDefs) do
            local on = (type(AP.IsBlockEnabled) ~= "function") or AP:IsBlockEnabled(item.key)
            if on then
                vis[#vis + 1] = item.card
                item.card:Show()
            else
                item.card:Hide()
            end
        end
        if #vis == 0 then
            emptyTxt:Show()
            return
        end
        emptyTxt:Hide()
        if #vis == 1 then
            local c = vis[1]
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
            c:SetSize(744, 300)
        elseif #vis == 2 then
            for idx, c in ipairs(vis) do
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", box, "TOPLEFT", (idx - 1) * 376, 0)
                c:SetSize(368, 340)
            end
        else
            for idx, c in ipairs(vis) do
                local col = (idx - 1) % 2
                local row = math.floor((idx - 1) / 2)
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", box, "TOPLEFT", col * 376, row == 0 and 0 or -232)
                c:SetSize(368, row == 0 and 224 or 212)
            end
        end
    end

    local xpHelpBtn = PS.MakeBtn(c2, 108, 18, "Правила опыта (?)", "dark")
    xpHelpBtn:SetPoint("TOPRIGHT", c2, "TOPRIGHT", -8, -7)
    local function EnsureXPHelpFrame()
        local hf = _G.AP_XPHelpFrame
        if hf then return hf end
        hf = CreateFrame("Frame", "AP_XPHelpFrame", UIParent)
        hf:SetSize(486, 520)
        hf:SetFrameStrata("FULLSCREEN_DIALOG")
        hf:SetToplevel(true)
        hf:SetClampedToScreen(true)
        hf:EnableMouse(true)
        hf:SetMovable(true)
        hf:RegisterForDrag("LeftButton")
        hf:SetScript("OnDragStart", function(self) self:StartMoving() end)
        hf:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        hf:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        hf:SetBackdropColor(0.04, 0.05, 0.08, 0.99)
        hf:SetBackdropBorderColor(0.78, 0.62, 0.24, 0.95)
        hf:Hide()

        local hbg = hf:CreateTexture(nil, "BORDER")
        hbg:SetTexture("Interface\\Buttons\\WHITE8X8")
        hbg:SetVertexColor(0.11, 0.09, 0.06, 0.98)
        hbg:SetPoint("TOPLEFT", hf, "TOPLEFT", 1, -1)
        hbg:SetPoint("TOPRIGHT", hf, "TOPRIGHT", -1, -1)
        hbg:SetHeight(28)

        local sep = hf:CreateTexture(nil, "ARTWORK")
        sep:SetTexture("Interface\\Buttons\\WHITE8X8")
        sep:SetVertexColor(0.78, 0.62, 0.24, 0.55)
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", hf, "TOPLEFT", 1, -29)
        sep:SetPoint("TOPRIGHT", hf, "TOPRIGHT", -1, -29)

        hf.title = hf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hf.title:SetPoint("TOPLEFT", hf, "TOPLEFT", 12, -8)
        hf.title:SetText("|cffffd200Как складывается опыт на сервере (WoW Prime)|r")

        local closeBtn = CreateFrame("Button", nil, hf)
        closeBtn:SetSize(20, 20)
        closeBtn:SetPoint("TOPRIGHT", hf, "TOPRIGHT", -6, -5)
        PS.StyleClose(closeBtn, 20)
        closeBtn:SetScript("OnClick", function()
            hf.pinned = false
            hf:Hide()
        end)
        hf.closeBtn = closeBtn

        hf.body = hf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hf.body:SetPoint("TOPLEFT", hf, "TOPLEFT", 12, -36)
        hf.body:SetWidth(462)
        hf.body:SetJustifyH("LEFT")
        hf.body:SetJustifyV("TOP")
        if hf.body.SetSpacing then hf.body:SetSpacing(2) end

        hf.foot = hf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hf.foot:SetPoint("BOTTOMLEFT", hf, "BOTTOMLEFT", 12, 8)
        hf.foot:SetPoint("BOTTOMRIGHT", hf, "BOTTOMRIGHT", -12, 8)
        hf.foot:SetJustifyH("LEFT")
        hf.foot:SetText("|cff94a3b8ЛКМ по кнопке: закрепить/открепить окно | Перетаскивание: за шапку|r")

        if AttuneParserFrame and AttuneParserFrame.HookScript then
            AttuneParserFrame:HookScript("OnHide", function()
                hf.pinned = false
                hf:Hide()
            end)
        end
        return hf
    end
    local function BuildXPHelpText()
        local px = (type(AP.GetParagonXPBreakdown) == "function") and AP:GetParagonXPBreakdown() or {}
        local eq = (type(AP.GetEquippedAttuneProgress) == "function") and AP:GetEquippedAttuneProgress() or {}
        local fmt = (type(AP.FormatMult) == "function") and AP.FormatMult or function(m) return tostring(m or 1) end
        local lines = {}

        local dlvlNote = "вне сложного данжа"
        if (px.paragonDlvl or 0) > 0 then
            dlvlNote = string.format("%s (чат +%d%%, Paragon dlvlBonus +%d%%)",
                px.paragonDlvlName or ("#" .. tostring(px.paragonDlvl)),
                px.paragonDlvlChatBonus or 0,
                px.paragonDlvlBonus or 0)
        end
        local mapNote = ((px.paragonMapXP or 100) ~= 100) and string.format(", карта x%s", fmt((px.paragonMapXP or 100) / 100)) or ""
        local gAttStr = (eq.guildKnown == false) and "?" or string.format("+%d%%", eq.guildPct or 0)
        table.insert(lines, string.format(
            "|cffffd200Сейчас на персонаже:|r  Поглощение: |cff40ff40x%s|r (Гильдия %s%s%s) | Paragon (мобы): |cff38bdf8x%s|r (%s%s%s)",
            fmt(eq.xpMult or 1), gAttStr,
            eq.isSaturday and ", Дар Сб x2" or "",
            eq.hasElixir and ", Эликс. погл. x2" or "",
            fmt(px.paragonMobMult or 1),
            px.paragonX2Active and ("x2: " .. tostring(px.paragonX2Source or "бафф")) or "без x2",
            (px.paragonPerkPts and px.paragonPerkPts > 0) and (", перк +" .. fmt(px.paragonPerkPct or 0) .. "%") or "",
            mapNote
        ))
        table.insert(lines, "Активная сложность инста: |cffffffff" .. dlvlNote .. "|r")
        if px.paragonX2Wasted then
            table.insert(lines, "|cffff6060Внимание: активно несколько x2 (" .. table.concat(px.paragonX2Sources or {}, " + ") .. ") - лишний бафф не дает x4!|r")
        end

        table.insert(lines, "")
        table.insert(lines, "|cff40ff401. Опыт поглощения предметов:|r")
        table.insert(lines, "  Формула: (1 + Дар Субботы [+1] + Эликсир поглощения [+1]) x (1 + Гильдия +5/10/25%)")
        table.insert(lines, "  * Дар Субботы (900206) и Эликсир (900210) складываются (до x3), затем x Гильдия = до |cff40ff40x3.75|r.")
        table.insert(lines, "  * База: обычный квест 100, групповой 200, квест данжа 350, моб в мире = уровень/2 (40 для 80 ур.). Опыт идет всем надетым подходящим вещам; нужно 0.24 x ilvl^2.")
        table.insert(lines, "  * Вещи с требованием 80 ур. (кроме стартовых) не качаются на мобах в мире - только квесты и инсты.")
        table.insert(lines, "  * |cffff6060НЕ влияют|r на поглощение: Эликсир двойного опыта, Дар Воскресенья, Праздник опыта, Благословение новичка, перк Paragon и сложность данжа.")

        table.insert(lines, "")
        table.insert(lines, "|cff38bdf82. Опыт Paragon (Доп. уровень):|r")
        table.insert(lines, "  * Базовые x2 |cffff6060НЕ суммируются|r (действует только одно x2): Эликсир двойного опыта (900211), Дар Воскресенья (900207), Праздник опыта (Сб, 900125), Благословение новичка (1040174, до 100 ур. Paragon).")
        table.insert(lines, "  * За существ перемножаются: (x2 или x1) x (1 + перк «Опыт Paragon» до +25%) x (1 + dlvlBonus сложности с сервера) x коэф. карты (напр. Наксрамас x0.5). На квесты сложность и mapXP не действуют.")
        table.insert(lines, "  * На ExtraLevel-мирах у Луизы есть бафф «Опытный максималист» (+10% за 200 ур., стак до 100).")

        table.insert(lines, "")
        table.insert(lines, "|cffff9f403. Дополнительная сложность инстов ([Сложность]):|r")
        table.insert(lines, "  |cff1eff001 Необычная:|r урон -20%, хил -15%, |cff40ff40опыт +30%|r | враги: HP x1.48, удар 18%/36%, крит +20%/+24%")
        table.insert(lines, "  |cffbb79e82 Эпическая:|r урон -40%, укл/пар/бл -15, броня -15%, хил -30%, |cff40ff40опыт +60%|r | враги: HP x2.18, удар 60%/120%, крит +33%/+40%")
        table.insert(lines, "  |cffff80003 Легендарная:|r урон -60%, укл/пар/бл -40, броня -45%, хил -50%, |cff40ff40опыт +120%|r | враги: HP x2.96, удар 90%/180%, крит +42%/+50%")
        table.insert(lines, "  |cff00ffcc4 Титаническая:|r урон -75%, укл/пар/бл -75, броня -65%, хил -80%, |cff40ff40опыт +200%|r | враги: HP x3.80, удар 118%/236%, крит +48%/+57.6%")
        table.insert(lines, "  * В клиенте Paragon для dlvlBonus указаны ориентиры +0/5/15/25% за мобов, но аддон берет точное значение dlvlBonus напрямую с сервера.")

        table.insert(lines, "")
        table.insert(lines, "|cffffd2004. Обычный опыт (1-80) и гильдия:|r")
        table.insert(lines, "  * «Опытность» (+5/10/15/25%) ускоряет обычный опыт; Эликсир двойного опыта (900211) удваивает обычный, гильдейский и Paragon опыт.")
        table.insert(lines, "  * «Единство гильдии» (+5/10%) ускоряет только опыт гильдии (база 75+: +40/+80/+200 моб/элита/босс, квесты +100..+140).")
        return table.concat(lines, "\n")
    end
    local function ShowXPHelp(anchor, pinMode)
        local hf = EnsureXPHelpFrame()
        if pinMode then
            if hf:IsShown() and hf.pinned then
                hf.pinned = false
                hf:Hide()
                return
            end
            hf.pinned = true
        end
        hf.body:SetText(BuildXPHelpText())
        if hf.body.GetStringHeight then
            local h = math.max(360, math.min(600, (hf.body:GetStringHeight() or 460) + 64))
            hf:SetHeight(h)
        end
        hf:ClearAllPoints()
        local mainFr = AttuneParserFrame
        local scrRight = (UIParent and UIParent.GetRight and UIParent:GetRight()) or 1024
        local mainRight = (mainFr and mainFr.GetRight and mainFr:GetRight()) or 800
        local mainLeft = (mainFr and mainFr.GetLeft and mainFr:GetLeft()) or 0
        if mainFr and (scrRight - mainRight) >= 496 then
            hf:SetPoint("TOPLEFT", mainFr, "TOPRIGHT", 8, -28)
        elseif mainFr and mainLeft >= 496 then
            hf:SetPoint("TOPRIGHT", mainFr, "TOPLEFT", -8, -28)
        elseif mainFr then
            hf:SetPoint("TOPLEFT", mainFr, "TOPLEFT", 14, -34)
        else
            hf:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 0)
        end
        hf:Show()
        if type(hf.Raise) == "function" then pcall(hf.Raise, hf) end
    end
    xpHelpBtn:SetScript("OnEnter", function(self)
        ShowXPHelp(self, false)
    end)
    xpHelpBtn:SetScript("OnLeave", function()
        local hf = _G.AP_XPHelpFrame
        if hf and not hf.pinned then hf:Hide() end
    end)
    xpHelpBtn:SetScript("OnClick", function(self)
        ShowXPHelp(self, true)
    end)
    c2._xpHelpBtn = xpHelpBtn
    box._c2 = c2

    local claimBtn2 = PS.MakeBtn(c1, 130, 22, "Забрать вехи", "green")
    claimBtn2:SetPoint("BOTTOMLEFT", c1, "BOTTOMLEFT", 10, 6)
    claimBtn2:SetScript("OnClick", function()
        AP:ClaimAllMilestones()
        AP.After(0.6, function() box.RefreshData() end, "ap_ui_claim2")
    end)

    local scanBtn = PS.MakeBtn(c1, 136, 22, "До-скан предметов", "dark")
    scanBtn:SetPoint("LEFT", claimBtn2, "RIGHT", 6, 0)
    scanBtn:SetScript("OnClick", function()
        AP:InvalidateCaches(false)
        AP:StartBackgroundScan()
        box.RefreshData()
    end)

    local syncBtn2 = PS.MakeBtn(c2, 126, 22, "Обновить данные", "dark")
    syncBtn2:SetPoint("BOTTOMLEFT", c2, "BOTTOMLEFT", 10, 6)
    syncBtn2:SetScript("OnClick", function()
        AP:RequestServerSync(true)
        AP.After(0.5, function() box.RefreshData() end, "ap_ui_sync2")
    end)

    local bagumBtn = PS.MakeBtn(c2, 174, 22, "Обмен ресурсов", "green")
    bagumBtn:SetPoint("LEFT", syncBtn2, "RIGHT", 6, 0)
    bagumBtn:Hide()
    bagumBtn:SetScript("OnClick", function()
        local st = AP:GetForgeMaterialStock()
        if not (st.bagumOpen and st.bagumDustEnabled) then return end
        if (st.legDirectToTit or 0) > 0 then
            AP:ExchangeBagum(0, 6, 1)
        elseif (st.epicToLeg or 0) > 0 then
            AP:ExchangeBagum(0, 5, 1)
        elseif (st.triToFrost or 0) > 0 then
            AP:ExchangeBagum(0, 3, 1)
        end
    end)
    bagumBtn:SetScript("OnEnter", function(self)
        local st = AP:GetForgeMaterialStock()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("|cffffd200Быстрый обмен ресурсов|r")
        GameTooltip:AddLine("ЛКМ: обменять 1 шт. (Пылающая -> Астральная, Мерцающая -> Пылающая или Триумф -> Лед).", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(string.format("Курс пыли: %d:1 и %d:1 | Комиссия: %d зол. за крафт.", st.rate1 or 3, st.rate2 or 3, math.floor((st.bagumFeeCopper or 1000000) / 10000)), 0.85, 0.85, 0.85)
        GameTooltip:Show()
    end)
    bagumBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local openTalBtn = PS.MakeBtn(c3, 136, 22, "Открыть Талориана", "green")
    openTalBtn:SetPoint("BOTTOMLEFT", c3, "BOTTOMLEFT", 10, 6)
    openTalBtn:SetScript("OnClick", function()
        AP:OpenTalorianUI()
    end)

    local autoSwapBtn = PS.MakeBtn(c3, 164, 22, "Автопоглощение: ?", "dark")
    autoSwapBtn:SetPoint("BOTTOMRIGHT", c3, "BOTTOMRIGHT", -10, 6)
    autoSwapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    autoSwapBtn:SetScript("OnClick", function(_, mBtn)
        local as = AP:GetAutoSwapSummary()
        if mBtn == "RightButton" then
            AP:SetAutoAbsorbBoE(not (as.boeAllowed == true))
        else
            AP:SetAutoAbsorb(not (as.on == true))
        end
        AP.After(0.25, function() box.RefreshData() end, "ap_ui_as_c3")
    end)
    autoSwapBtn:SetScript("OnEnter", function(self)
        local as = AP:GetAutoSwapSummary()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("|cffffd200Автоматическое поглощение|r")
        GameTooltip:AddLine("ЛКМ: включить или выключить автоэкипировку для поглощения", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("ПКМ: разрешить не персональные (BoE) вещи (" .. (as.boeAllowed and "|cff40ff40да|r" or "|cffff8080нет|r") .. ")", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    autoSwapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    function box.RefreshData()
        if box.RelayoutCards then box.RelayoutCards() end
        local cat = AP:GetAccountCatalogSummary()
        local ms = AP:GetMilestonesSummary()
        local active, done, tot = AP:GetScanProgress()
        local hasPet, isSum = AP:HasTalorianPet()
        local talLoaded, talTtpOn, talBridgeOn, talOff = false, true, AP:IsTalorianBridgeActive(), (AP:GetSetting("talorianMode") == "off")
        if type(AP.GetTalorianStatus) == "function" then
            talLoaded, talTtpOn, talBridgeOn, talOff = AP:GetTalorianStatus()
        else
            talLoaded = (AP._talorianBridge ~= nil) or (type(rawget(_G, "TalorianTP")) == "table")
            talTtpOn = not (type(_G.TalorianTP_DB) == "table" and _G.TalorianTP_DB.enabled == false)
        end
        local petNote = isSum and " (призван)" or (hasPet and " (в коллекции)" or "")
        local talTxt = talOff and "|cff94a3b8Отключен в настройках|r"
            or (talBridgeOn and ("|cff40ff40Подключен|r" .. petNote))
            or ((talLoaded and not talTtpOn) and ("|cffffd200Выключен в настройках спутника|r" .. petNote))
            or (hasPet and "|cffffd200Питомец есть, модуль телепорта не загружен|r" or "|cff94a3b8Спутник не найден - автономный режим|r")
        local catLbl = cat.v2 and "Каталог класса" or "Каталог"

        c1.body:SetText(string.format(
            "%s: |cffffffff%d / %d|r (%d%%)\nАккаунт: |cff40ff40%d|r  |  Герой: |cff38bdf8%d|r\n\nВехи: поглощено |cffffffff%d|r\nДоступно наград: %s%d|r%s\n\nСкан предметов: %s (%d/%d)\nТалориан: %s",
            catLbl, cat.doneBase or 0, cat.totalBase or 0, cat.pctBase or 0,
            cat.acc or 0, cat.hero or 0,
            ms.done or 0,
            (ms.claimable or 0) > 0 and "|cff40ff40" or "|cff94a3b8", ms.claimable or 0,
            ms.nextNeed and string.format("\nСледующая веха: %d (ост. %d)", ms.nextNeed, ms.nextRemain or 0) or "",
            active and "идет" or "готов", done or 0, tot or 0,
            talTxt
        ))
        if (ms.claimable or 0) > 0 then
            PS.PaintBtn(claimBtn2, "green")
        else
            PS.PaintBtn(claimBtn2, "gray")
        end

        local g = AP:GetActiveDailyGift(false)
        local st = AP:GetForgeMaterialStock()
        local eq = AP:GetEquippedAttuneProgress()
        local px = (type(AP.GetParagonXPBreakdown) == "function") and AP:GetParagonXPBreakdown() or {
            attuneMult = eq.xpMult or 1,
            paragonMobMult = 1,
            paragonX2Active = false,
            paragonX2Sources = {},
        }
        local fmtMult = (type(AP.FormatMult) == "function") and AP.FormatMult or function(m) return tostring(m or 1) end
        local craftFeeG = math.floor((st.bagumTitCostCopper or 0) / 10000)
        local rbNote = st.rbActive and string.format(" (Банк ресурсов: %d/%d)", st.rbUsed or 0, st.rbMax or 0) or ""
        local guildStr = (eq.guildKnown == false) and "?" or string.format("+%d%%", eq.guildPct or 0)
        local attParts = { "Гильдия " .. guildStr }
        if g.isSaturday then table.insert(attParts, "Дар Сб x2") end
        if g.hasElixir then table.insert(attParts, "Эликс. погл. x2") end
        local parParts = {}
        if px.paragonX2Active then
            table.insert(parParts, "|cff40ff40x2:|r " .. tostring(px.paragonX2Source or "бафф"))
        else
            table.insert(parParts, "без x2")
        end
        if px.paragonPerkPts and px.paragonPerkPts > 0 then
            table.insert(parParts, string.format("перк +%s%%", fmtMult(px.paragonPerkPct or 0)))
        end
        if (px.paragonDlvlBonus or 0) > 0 then
            table.insert(parParts, string.format("%s +%d%%", px.paragonDlvlName or "сложн.", px.paragonDlvlBonus))
        end
        if (px.paragonMapXP or 100) ~= 100 then
            table.insert(parParts, string.format("карта x%s", fmtMult((px.paragonMapXP or 100) / 100)))
        end
        if (px.guildExpPct or 0) > 0 then
            table.insert(parParts, string.format("оп. ги +%d%%", px.guildExpPct))
        end
        if px.paragonX2Wasted then
            table.insert(parParts, "|cffff6060x2 не стак.|r")
        end
        local eqLine = ((eq.count or 0) > 0)
            and string.format("Надетые (%d шт.): ~%d кв. (мир) / %d (данж)", eq.count or 0, eq.questsToFinishAllNormal or 0, eq.questsToFinishAllDungeon or 0)
            or "|cff94a3b8Надетые: все поглощены на 100% (текущая ковка)|r"
        c2.body:SetText(string.format(
            "Бонус дня: %s\n%s\nПоглощение: |cff40ff40x%s|r (%s)\nParagon (мобы): |cff38bdf8x%s|r (%s)\nПыль (%d:1 / %d:1)%s:\n  Мерц: |cffa335ee%d|r (+%d Пыл.) | Пыл: |cffff8000%d|r (+%d Астр.) | Астр: |cff38bdf8%d|r\n  Тит. потенциал: |cff40ff40%d|r (%d зол.) | Сундуки: %d | Лед: %d (+%d)\n%s",
            g.active and ("|cffa855f7" .. (g.name or "Бонус") .. "|r (" .. (g.remText or "?") .. ")") or "|cff94a3b8нет|r",
            (g.desc and g.desc ~= "") and ("|cffb0a080" .. g.desc .. "|r") or (g.active and "|cff94a3b8Наведите курсор на бафф дня для описания|r" or "|cff94a3b8Бафф дня пока не активен|r"),
            fmtMult(eq.xpMult or 1), table.concat(attParts, ", "),
            fmtMult(px.paragonMobMult or 1), table.concat(parParts, ", "),
            st.rate1 or 3, st.rate2 or 3, rbNote,
            st.dustEpic or 0, st.epicToLeg or 0, st.dustLeg or 0, st.legToTit or 0,
            st.dustTit or 0, st.totalTitPotential or 0, craftFeeG,
            st.titanBoxes or 0, st.frostEmblem or 0, st.frostFromLowerEmblems or 0,
            eqLine
        ))
        if st.bagumOpen and st.bagumDustEnabled and ((st.legDirectToTit or 0) > 0 or (st.epicToLeg or 0) > 0 or (st.triToFrost or 0) > 0) then
            if (st.legDirectToTit or 0) > 0 then
                bagumBtn.label:SetText("Обмен: +1 Астральная")
            elseif (st.epicToLeg or 0) > 0 then
                bagumBtn.label:SetText("Обмен: +1 Пылающая")
            else
                bagumBtn.label:SetText("Обмен: +1 Лед")
            end
            bagumBtn:Show()
        else
            bagumBtn:Hide()
        end

        local par = AP:GetParagonInfo()
        local sp = AP:GetPlayerSpecInfo()
        local as = AP:GetAutoSwapSummary()
        local dsp = (type(AP.GetDisperseSummary) == "function") and AP:GetDisperseSummary() or {}
        local vt = (type(AP.GetMPlusVaultSummary) == "function") and AP:GetMPlusVaultSummary() or {}
        local vStr = (vt.quick == 1) and "|cff40ff40Награда!|r" or ((vt.quick == 2) and "получено" or "ожидание")
        c3.body:SetText(string.format(
            "Доп. уровень: |cffffd200ур. %d|r (%d / %d, %d%%) | 80 мир: %s\nСпециализация: |cff38bdf8%s|r%s\nАвтопоглощение: %s | BoE: %s\nАвтопродажа: %s | Черный список: |cffffd200%d|r\nРасщепление: %d | Осколки: %d | Ключи M+: %s",
            par.level or 0, par.curXP or 0, par.maxXP or 0, par.pct or 0,
            par.worldLocked80 and "|cffff6060Ограничен|r" or "|cff40ff40Нет|r",
            sp.specName or "?", sp.isCustomLegion and " [Legion]" or "",
            as.on == true and "|cff40ff40ВКЛ|r" or (as.on == false and "|cffff6060ВЫКЛ|r" or "|cff94a3b8?|r"),
            as.boeAllowed == true and "|cff40ff40Да|r" or "|cff94a3b8Нет|r",
            as.unlocked and (as.active and "|cff40ff40ВКЛ|r" or "|cffffd200Выкл|r") or "|cff94a3b8Замок|r",
            as.blacklistCount or 0,
            dsp.skill or 0, dsp.activeShards or 0, vStr
        ))
        autoSwapBtn.label:SetText("Автопоглощение: " .. (as.on == true and "|cff40ff40ВКЛ|r" or "|cffff8080ВЫКЛ|r"))
        PS.PaintBtn(autoSwapBtn, as.on == true and "green" or "dark")
        if talBridgeOn or talLoaded then
            openTalBtn:Show()
        else
            openTalBtn:Hide()
        end

        local acct = AP:GetAbsorbedAccountStats()
        local lines = {}
        local stTbl = acct.statsTotal or {}
        for _, sid in ipairs(acct.statOrder or {}) do
            local val = stTbl[sid]
            if val and val > 0 then
                local sNm = (acct.statNameFn and acct.statNameFn(sid)) or STAT_NAMES[sid] or ("Стат #" .. sid)
                table.insert(lines, string.format("%s: |cff40ff40+%d|r", tostring(sNm), val))
            end
        end
        if #lines == 0 then
            c4.body:SetText("|cff94a3b8Статы еще не загружены с сервера.\nНажмите «Обновить данные».|r")
        else
            local out = {}
            for i = 1, math.min(20, #lines), 2 do
                local l1 = lines[i]
                local l2 = lines[i + 1]
                if l2 then
                    table.insert(out, l1 .. "   |   " .. l2)
                else
                    table.insert(out, l1)
                end
            end
            c4.body:SetText(table.concat(out, "\n"))
        end
    end

    return box
end

-- Вкладка 3: Сумки и Ковка (сумки, банк, надетые, сборщик, гильдбанк + ЧС)
local function BuildBagsTab(parent)
    local box = CreateFrame("Frame", nil, parent)
    box:SetAllPoints(parent)
    box.filterWhere = "all"
    box.hideBlacklist = false
    box.rows = {}
    box.data = {}

    local topBar = CreateFrame("Frame", nil, box)
    topBar:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    topBar:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
    topBar:SetHeight(32)
    PS.StyleBox(topBar, 0.50, false)

    local wBtns = {}
    local filters = {
        { key = "all", label = "Все", w = 40 },
        { key = "bag", label = "Сумки", w = 54 },
        { key = "petloot", label = "Сборщик", w = 66 },
        { key = "itembank", label = "Банк вещей", w = 84 },
        { key = "equip", label = "Надетые", w = 64 },
        { key = "bank", label = "Банк", w = 48 },
        { key = "guild", label = "Гильдбанк", w = 74 },
    }
    local wx = 6
    for _, fl in ipairs(filters) do
        local bw = fl.w
        local b = PS.MakeBtn(topBar, bw, 22, fl.label, "dark")
        b:SetPoint("LEFT", topBar, "LEFT", wx, 0)
        wx = wx + bw + 4
        b:SetScript("OnClick", function()
            box.filterWhere = fl.key
            if fl.key == "guild" then AP:SyncGuildBankForge()
            elseif fl.key == "petloot" then AP:RequestPetLootState()
            elseif fl.key == "itembank" and type(AP.RequestWhereItemsSync) == "function" then AP:RequestWhereItemsSync() end
            box.RefreshData()
        end)
        wBtns[fl.key] = b
    end

    local blBtn = PS.MakeBtn(topBar, 86, 22, "Скрыть ЧС", "dark")
    blBtn:SetPoint("LEFT", wx + 4, 0)
    blBtn:SetScript("OnClick", function()
        box.hideBlacklist = not box.hideBlacklist
        box.RefreshData()
    end)

    local refBtn = PS.MakeBtn(topBar, 74, 22, "Обновить", "dark")
    refBtn:SetPoint("RIGHT", topBar, "RIGHT", -6, 0)
    refBtn:SetScript("OnClick", function()
        AP:RequestPetLootState()
        AP:SyncGuildBankForge()
        if type(AP.RequestWhereItemsSync) == "function" then AP:RequestWhereItemsSync() end
        box.RefreshData()
    end)

    local listBox = CreateFrame("Frame", nil, box)
    listBox:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -6)
    listBox:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 74)
    PS.StyleBox(listBox, 0.36, false)

    local actBar = CreateFrame("Frame", nil, box)
    actBar:SetPoint("TOPLEFT", listBox, "BOTTOMLEFT", 0, -4)
    actBar:SetPoint("TOPRIGHT", listBox, "BOTTOMRIGHT", 0, -4)
    actBar:SetHeight(50)

    local sweepBtn = PS.MakeBtn(actBar, 190, 22, "Продать поглощенные", "dark")
    sweepBtn:SetPoint("TOPLEFT", actBar, "TOPLEFT", 0, 0)
    sweepBtn:SetScript("OnClick", function()
        local as = AP:GetAutoSwapSummary()
        if not as.unlocked then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[AttuneParser]|r Автопродажа поглощенных не разблокирована на аккаунте.")
            return
        end
        if StaticPopupDialogs and StaticPopup_Show then
            StaticPopupDialogs["ATTUNEPARSER_SWEEP_NOW"] = {
                text = "Продать СЕЙЧАС поглощенные предметы выбранного качества?\n(надетые + сумки; заблокированные в ЧС не трогаются)",
                button1 = YES or "Да",
                button2 = NO or "Нет",
                timeout = 0,
                whileDead = 1,
                hideOnEscape = 1,
                OnAccept = function()
                    AP:SweepAbsorbedNow(true)
                end,
            }
            StaticPopup_Show("ATTUNEPARSER_SWEEP_NOW")
        else
            AP:SweepAbsorbedNow(true)
        end
    end)
    sweepBtn:SetScript("OnEnter", function(self)
        local as = AP:GetAutoSwapSummary()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("|cffffd200Продажа поглощенных вещей|r")
        if as.unlocked then
            GameTooltip:AddLine("ЛКМ: запросить подтверждение и продать поглощенные дубли по настройкам фильтра (кроме вещей в ЧС).", 0.9, 0.9, 0.9, true)
        else
            GameTooltip:AddLine("Требует разблокировку автопродажи поглощенных на аккаунте.", 1, 0.5, 0.5, true)
        end
        GameTooltip:Show()
    end)
    sweepBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local junkBtn = PS.MakeBtn(actBar, 190, 22, "Расщепить лишний лут", "dark")
    junkBtn:SetPoint("LEFT", sweepBtn, "RIGHT", 8, 0)
    junkBtn:SetScript("OnClick", function()
        if AP.petLootJunk and AP.petLootJunk.running then
            AP:StopPetLootJunk()
        else
            AP:ScanPetLootJunk(0)
        end
    end)
    junkBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("|cffffd200Сборщик: расщепление лишнего|r")
        GameTooltip:AddLine("Сканирует хранилище Сборщика (при навыке 10 и Расщеплении эссенций) и предлагает расщепить уже поглощенное/неподходящее.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    junkBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local autoTabBtn = PS.MakeBtn(actBar, 210, 22, "Автопоглощение: ?", "dark")
    autoTabBtn:SetPoint("LEFT", junkBtn, "RIGHT", 8, 0)
    autoTabBtn:SetScript("OnClick", function()
        local as = AP:GetAutoSwapSummary()
        AP:SetAutoAbsorb(not (as.on == true))
        AP.After(0.25, function() box.RefreshData() end, "ap_ui_as_bags")
    end)

    local rbIbBtn = PS.MakeBtn(actBar, 190, 22, "Банки ресурсов / вещей", "dark")
    rbIbBtn:SetPoint("TOPLEFT", actBar, "TOPLEFT", 0, -26)
    rbIbBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    rbIbBtn:SetScript("OnClick", function(_, mBtn)
        if mBtn == "RightButton" then
            if type(AP.OpenItemBank) == "function" then AP:OpenItemBank() end
        else
            if type(AP.DepositAllResources) == "function" then AP:DepositAllResources(0) end
        end
    end)

    local ibAutoBtn = PS.MakeBtn(actBar, 236, 22, "Автонадевание из банка: ?", "dark")
    ibAutoBtn:SetPoint("LEFT", rbIbBtn, "RIGHT", 8, 0)
    ibAutoBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ibAutoBtn:SetScript("OnClick", function(_, mBtn)
        if mBtn == "RightButton" then
            if type(AP.RunItemBankAutoEquip) == "function" then
                AP:RunItemBankAutoEquip(true)
            end
        else
            if type(AP.SetItemBankAutoEquip) == "function" then
                AP:SetItemBankAutoEquip(not (AP:GetSetting("ibAutoEquip") == true))
            else
                AP:SetSetting("ibAutoEquip", not (AP:GetSetting("ibAutoEquip") == true))
            end
        end
        AP.After(0.2, function() box.RefreshData() end, "ap_ui_ib_auto")
    end)
    ibAutoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("|cffffd200Автонадевание из Банка вещей|r")
        GameTooltip:AddLine("ЛКМ: вкл/выкл автонадевание непоглощенных вещей из Банка вещей (работает и в бою, пауза 15с после ручного обмена).", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("ПКМ: надеть 1 подходящую вещь из Банка вещей прямо сейчас.", 0.4, 1.0, 0.4, true)
        if type(AP.GetItemBankEquipSummary) == "function" then
            local sum = AP:GetItemBankEquipSummary(true)
            GameTooltip:AddLine(string.format("В Банке вещей: %d шт. | Подходящих сейчас: %d", sum.itemCount or 0, sum.eligibleCount or 0), 0.7, 0.85, 1.0, true)
        end
        GameTooltip:Show()
    end)
    ibAutoBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local ibPutBtn = PS.MakeBtn(actBar, 214, 22, "Автосклад в банк: ?", "dark")
    ibPutBtn:SetPoint("LEFT", ibAutoBtn, "RIGHT", 8, 0)
    ibPutBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ibPutBtn:SetScript("OnClick", function(_, mBtn)
        if mBtn == "RightButton" then
            if type(AP.RunItemBankAutoPut) == "function" then
                AP:RunItemBankAutoPut(true)
            end
        elseif IsShiftKeyDown and IsShiftKeyDown() and type(AP.CycleItemBankPutMode) == "function" then
            AP:CycleItemBankPutMode()
        else
            if type(AP.SetItemBankAutoPut) == "function" then
                AP:SetItemBankAutoPut(not (AP:GetSetting("ibAutoPut") == true))
            else
                AP:SetSetting("ibAutoPut", not (AP:GetSetting("ibAutoPut") == true))
            end
        end
        AP.After(0.2, function() box.RefreshData() end, "ap_ui_ib_put")
    end)
    ibPutBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("|cffffd200Автосклад в Банк вещей|r")
        GameTooltip:AddLine("ЛКМ: вкл/выкл автоперенос в Банк вещей (оставляет вещи до ковки и продажи).", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Shift+ЛКМ: сменить режим | ПКМ: положить 1 вещь сейчас.", 0.4, 1.0, 0.4, true)
        if type(AP.GetItemBankPutSummary) == "function" then
            local ps = AP:GetItemBankPutSummary(true)
            GameTooltip:AddLine(string.format("Режим: %s | Готово к переносу: %d | Оставлено на улучшение: %d", tostring(ps.modeLabel or "?"), ps.eligibleCount or 0, ps.keptUpgrade or 0), 0.7, 0.85, 1.0, true)
        end
        GameTooltip:Show()
    end)
    ibPutBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rbIbBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("|cffffd200Банк ресурсов и Банк вещей|r")
        GameTooltip:AddLine("ЛКМ: сдать все ресурсы из сумок в Банк ресурсов.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("ПКМ: открыть окно Банка вещей (/ibank).", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    rbIbBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local foot = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    foot:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 4, 2)
    foot:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -4, 2)
    foot:SetJustifyH("LEFT")

    local VIS = 12
    local ROW_H = 26
    local sf = PS.AttachScroll(listBox, VIS * ROW_H, ROW_H, VIS, function() box.RenderRows() end)
    sf:SetPoint("TOPLEFT", listBox, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -4, 4)
    box.sf = sf

    for i = 1, VIS do
        local r = CreateFrame("Button", nil, sf)
        r:SetHeight(ROW_H - 2)
        r:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -16, -(i - 1) * ROW_H)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        PS.StyleScrollRow(r, (i % 2) == 1)

        r.locTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.locTxt:SetPoint("LEFT", r, "LEFT", 6, 0)
        r.locTxt:SetSize(88, 16)
        r.locTxt:SetJustifyH("LEFT")
        if r.locTxt.SetWordWrap then r.locTxt:SetWordWrap(false) end

        r.nameTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.nameTxt:SetPoint("LEFT", r.locTxt, "RIGHT", 4, 0)
        r.nameTxt:SetSize(316, 16)
        r.nameTxt:SetJustifyH("LEFT")
        if r.nameTxt.SetWordWrap then r.nameTxt:SetWordWrap(false) end

        r.tierTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.tierTxt:SetPoint("LEFT", r.nameTxt, "RIGHT", 4, 0)
        r.tierTxt:SetSize(184, 16)
        r.tierTxt:SetJustifyH("LEFT")
        if r.tierTxt.SetWordWrap then r.tierTxt:SetWordWrap(false) end

        r.statTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.statTxt:SetPoint("RIGHT", r, "RIGHT", -8, 0)
        r.statTxt:SetSize(92, 16)
        r.statTxt:SetJustifyH("RIGHT")
        if r.statTxt.SetWordWrap then r.statTxt:SetWordWrap(false) end

        r:SetScript("OnClick", function(self, mBtn)
            local it = self._item
            if not it then return end
            if mBtn == "RightButton" then
                if AP:ToggleItemBlacklist(it.itemId, it.instanceTier) then
                    AP.After(0.25, function() box.RefreshData() end, "ap_ui_bl_ref")
                end
                return
            end
            if IsAltKeyDown and IsAltKeyDown() and it.where == "petloot" and it.dbId then
                if AP:TakePetLootItem(it.dbId, it.count) then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff40ff40[AttuneParser]|r Запрошено забрать из Сборщика: " .. tostring(it.name or it.itemId))
                end
                return
            elseif IsAltKeyDown and IsAltKeyDown() and it.where == "itembank" and it.guid then
                if type(AP.TakeItemBankItem) == "function" and AP:TakeItemBankItem(it.guid) then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff40ff40[AttuneParser]|r Запрошено забрать из Банка вещей: " .. tostring(it.name or it.itemId))
                end
                return
            end
            if IsControlKeyDown() and it.itemId and type(DressUpItemLink) == "function" then
                local lnk = AP:GetItemHyperlink(it.itemId, it.link or it.sfx, it.name, it.quality)
                if lnk then pcall(DressUpItemLink, lnk) end
                return
            end
            if (IsShiftKeyDown() or (IsModifiedClick and IsModifiedClick("CHATLINK"))) and it.itemId then
                AP:InsertItemLink(it.itemId, it.link or it.sfx, it.name, it.quality)
            elseif it.primaryZone and it.primaryZone > 0 and AP:IsZoneInstance(it.primaryZone) and type(AP.OpenEncounterJournal) == "function" then
                AP:OpenEncounterJournal(it.primaryZone, it.itemId, it.diffMask)
            end
        end)

        r:SetScript("OnEnter", function(self)
            local it = self._item
            if not it then return end
            local isInst = (it.primaryZone and it.primaryZone > 0 and AP:IsZoneInstance(it.primaryZone)) and true or false
            local petHint = (it.where == "petloot" and it.dbId) and " | Alt+ЛКМ: забрать в сумку" or ((it.where == "itembank" and it.guid) and " | Alt+ЛКМ: забрать из Банка вещей" or "")
            local blHint = " | ПКМ: вкл/выкл ЧС"
            local exLine = it.needsForgeUpgrade
                and string.format("В наличии (%s): тир %s | нужна ковка до 90%% (ост. +%d стат)",
                    FormatLocation(it.where), it.instanceTierName or "?", it.remainStats or 0)
                or string.format("В наличии (%s): тир %s -> +%d%% (+%d стат сейчас)",
                    FormatLocation(it.where), it.instanceTierName or "?", it.gainNowPct or 0, it.gainNowStats or 0)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            AP:BuildItemTooltip(GameTooltip, it.itemId, {
                sfx = it.sfx,
                link = it.link,
                name = it.name,
                quality = it.quality,
                tier = it.instanceTier,
                zoneId = it.primaryZone,
                extraLine = exLine,
                hint = isInst
                    and ("|cff94a3b8ЛКМ: Путеводитель | Shift+ЛКМ: в чат | Ctrl+ЛКМ: примерить" .. petHint .. blHint .. "|r")
                    or ("|cff94a3b8Shift+ЛКМ: в чат | Ctrl+ЛКМ: примерить" .. petHint .. blHint .. "|r"),
            })
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)

        box.rows[i] = r
    end

    function box.RenderRows()
        local off = sf.offset or 0
        for i = 1, VIS do
            local r = box.rows[i]
            local it = box.data[off + i]
            if not it then
                r._item = nil
                r:Hide()
            else
                r._item = it
                r:Show()
                r.locTxt:SetText("[" .. FormatLocation(it.where) .. "]")
                local dTag = (AP.GetItemDiffTag and it.primaryZone) and AP:GetItemDiffTag(it.itemId, it.primaryZone, it.diffMask, false) or ""
                local dStr = (dTag ~= "") and ("|cff94a3b8[" .. dTag .. "]|r ") or ""
                local bl = it.isBlacklisted and " |cffff5050[ЧС]|r" or ""
                r.nameTxt:SetText(dStr .. ShortItemLink(it.itemId, it.name, it.quality) .. bl)
                if it.needsForgeUpgrade then
                    r.tierTxt:SetText(string.format("%s | %d%% -> |cffffd200ковка|r", it.instanceTierName or "?", it.curPct or 0))
                    r.statTxt:SetText("|cffffd200+" .. (it.remainStats or 0) .. " пот.|r")
                else
                    r.tierTxt:SetText(string.format("%s -> |cff40ff40+%d%%|r", it.instanceTierName or "?", it.gainNowPct or 0))
                    r.statTxt:SetText("|cff40ff40+" .. (it.gainNowStats or 0) .. " стат|r")
                end
            end
        end
    end

    function box.RefreshData()
        local actOn = (type(AP.IsBlockEnabled) ~= "function") or AP:IsBlockEnabled("blkBagsActions")
        listBox:ClearAllPoints()
        listBox:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -6)
        if actOn then
            listBox:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 74)
            actBar:Show()
        else
            listBox:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 18)
            actBar:Hide()
        end

        for k, b in pairs(wBtns) do
            PS.PaintBtn(b, (box.filterWhere == k) and "gold" or "dark")
        end
        PS.PaintBtn(blBtn, box.hideBlacklist and "green" or "dark")

        local cands = AP:GetOwnedUpgradeCandidates(nil, true)
        local filtered = {}
        local readyCnt, forgeCnt, totGain, totForge, petCnt, blCnt = 0, 0, 0, 0, 0, 0
        for _, it in ipairs(cands) do
            local isMk = (AP.IsMorKelItem and AP:IsMorKelItem(it.itemId)) or (AP.MORKEL_ITEMS and AP.MORKEL_ITEMS[it.itemId])
            if not isMk then
                if it.where == "petloot" then petCnt = petCnt + 1 end
                if it.isBlacklisted then blCnt = blCnt + 1 end
                local wOk = (box.filterWhere == "all") or ((it.where or "bag") == box.filterWhere)
                local bOk = (not box.hideBlacklist) or (not it.isBlacklisted)
                if wOk and bOk then
                    table.insert(filtered, it)
                    if it.needsForgeUpgrade then
                        forgeCnt = forgeCnt + 1
                        totForge = totForge + (it.remainStats or 0)
                    else
                        readyCnt = readyCnt + 1
                        totGain = totGain + (it.gainNowStats or 0)
                    end
                end
            end
        end
        box.data = filtered
        sf:SetTotal(#filtered, false)
        local as = AP:GetAutoSwapSummary()
        PS.PaintBtn(sweepBtn, as.unlocked and "dark" or "gray")
        sweepBtn.label:SetText(as.unlocked and "Продать поглощенные" or "Продать (замок)")
        local jRun = AP.petLootJunk and AP.petLootJunk.running
        if jRun then
            PS.PaintBtn(junkBtn, "red")
            junkBtn.label:SetText(string.format("Стоп %d/%d", jRun[1] or 0, jRun[2] or 0))
        elseif AP:CanPetLootJunk() then
            PS.PaintBtn(junkBtn, "green")
            junkBtn.label:SetText("Расщепить лишний лут")
        else
            PS.PaintBtn(junkBtn, "gray")
            junkBtn.label:SetText("Расщепить лишний лут")
        end
        PS.PaintBtn(autoTabBtn, as.on == true and "green" or "dark")
        autoTabBtn.label:SetText("Автопоглощение: " .. (as.on == true and "ВКЛ" or "ВЫКЛ"))
        local ibOn = (AP:GetSetting("ibAutoEquip") == true)
        PS.PaintBtn(ibAutoBtn, ibOn and "green" or "dark")
        ibAutoBtn.label:SetText("Автонадевание из банка: " .. (ibOn and "ВКЛ" or "ВЫКЛ"))
        local putOn = (AP:GetSetting("ibAutoPut") == true)
        PS.PaintBtn(ibPutBtn, putOn and "green" or "dark")
        ibPutBtn.label:SetText("Автосклад в банк: " .. (putOn and "ВКЛ" or "ВЫКЛ"))
        foot:SetText(string.format("|cffb0a080Готово: %d (|cff40ff40+%d стат|r|cffb0a080) | На ковку: %d (|cffffd200+%d|r|cffb0a080) | Сборщик: %d | ЧС: %d|r",
            readyCnt, totGain, forgeCnt, totForge, petCnt, blCnt))
    end

    return box
end

-- Вкладка 4: Сеты T9 / T10 (отслеживание поглощения и ковки по ролям и уровням)
local function BuildSetsTab(parent)
    local box = CreateFrame("Frame", nil, parent)
    box:SetAllPoints(parent)
    box.tierFilter = "ALL"
    box.classFilter = "HERO"
    box.onlyIncomplete = false
    box.selectedKey = nil
    box.groups = {}
    box.slots = {}

    local topBar = CreateFrame("Frame", nil, box)
    topBar:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    topBar:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
    topBar:SetHeight(32)
    PS.StyleBox(topBar, 0.50, false)

    local tBtns = {}
    local tDefs = {
        { key = "ALL", label = "Все", w = 40 },
        { key = "T9", label = "T9", w = 40 },
        { key = "T10", label = "T10", w = 44 },
    }
    local tx = 6
    for _, td in ipairs(tDefs) do
        local b = PS.MakeBtn(topBar, td.w, 22, td.label, "dark")
        b:SetPoint("LEFT", topBar, "LEFT", tx, 0)
        tx = tx + td.w + 4
        b:SetScript("OnClick", function()
            box.tierFilter = td.key
            box.RefreshData()
        end)
        tBtns[td.key] = b
    end

    local incBtn = PS.MakeBtn(topBar, 92, 22, "Скрыть 90%", "dark")
    incBtn:SetPoint("LEFT", topBar, "LEFT", tx + 4, 0)
    incBtn:SetScript("OnClick", function()
        box.onlyIncomplete = not box.onlyIncomplete
        box.RefreshData()
    end)

    local clsBtn = PS.MakeBtn(topBar, 102, 22, "Мой класс", "dark")
    clsBtn:SetPoint("LEFT", incBtn, "RIGHT", 6, 0)
    clsBtn:SetScript("OnClick", function()
        box.classFilter = (box.classFilter == "HERO") and "ALL" or "HERO"
        box.RefreshData()
    end)

    local refBtn = PS.MakeBtn(topBar, 74, 22, "Обновить", "dark")
    refBtn:SetPoint("RIGHT", topBar, "RIGHT", -6, 0)
    refBtn:SetScript("OnClick", function()
        if type(AP.RequestWhereItemsSync) == "function" then AP:RequestWhereItemsSync() end
        box.RefreshData()
    end)

    local warmBtn = PS.MakeBtn(topBar, 114, 22, "Прогреть кэш", "dark")
    warmBtn:SetPoint("RIGHT", refBtn, "LEFT", -6, 0)
    warmBtn:SetScript("OnClick", function()
        if type(AP.WarmMorKelSetsCache) == "function" then
            local n = AP:WarmMorKelSetsCache({
                tierFilter = box.tierFilter,
                classFilter = box.classFilter,
                onlyIncomplete = box.onlyIncomplete,
            })
            if n == 0 and DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Все вещи выбранных комплектов уже в кэше.")
            end
            box.RefreshData()
        end
    end)

    local leftPane = CreateFrame("Frame", nil, box)
    leftPane:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -6)
    leftPane:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 24)
    leftPane:SetWidth(272)
    PS.StyleBox(leftPane, 0.36, false)

    local rightPane = CreateFrame("Frame", nil, box)
    rightPane:SetPoint("TOPLEFT", leftPane, "TOPRIGHT", 8, 0)
    rightPane:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 24)
    PS.StyleBox(rightPane, 0.40, false)

    local rHdr = CreateFrame("Frame", nil, rightPane)
    rHdr:SetPoint("TOPLEFT", rightPane, "TOPLEFT", 6, -6)
    rHdr:SetPoint("TOPRIGHT", rightPane, "TOPRIGHT", -6, -6)
    rHdr:SetHeight(48)
    PS.StyleBox(rHdr, 0.55, false)

    local rTitle = rHdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rTitle:SetPoint("TOPLEFT", rHdr, "TOPLEFT", 8, -6)
    rTitle:SetPoint("TOPRIGHT", rHdr, "TOPRIGHT", -8, -6)
    rTitle:SetJustifyH("LEFT")
    if rTitle.SetWordWrap then rTitle:SetWordWrap(false) end

    local rSub = rHdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rSub:SetPoint("TOPLEFT", rTitle, "BOTTOMLEFT", 0, -4)
    rSub:SetPoint("TOPRIGHT", rHdr, "TOPRIGHT", -8, -26)
    rSub:SetJustifyH("LEFT")
    if rSub.SetWordWrap then rSub:SetWordWrap(false) end

    local foot = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    foot:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 4, 2)
    foot:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -4, 2)
    foot:SetJustifyH("LEFT")

    local SVIS, SROW_H = 11, 33
    local lRows = {}
    local sfLeft = PS.AttachScroll(leftPane, SVIS * SROW_H, SROW_H, SVIS, function() box.RenderLeft() end)
    sfLeft:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 4, -4)
    sfLeft:SetPoint("BOTTOMRIGHT", leftPane, "BOTTOMRIGHT", -4, 4)
    box.sfLeft = sfLeft

    for i = 1, SVIS do
        local r = CreateFrame("Button", nil, sfLeft)
        r:SetHeight(SROW_H - 2)
        r:SetPoint("TOPLEFT", sfLeft, "TOPLEFT", 0, -(i - 1) * SROW_H)
        r:SetPoint("TOPRIGHT", sfLeft, "TOPRIGHT", -16, -(i - 1) * SROW_H)
        PS.StyleScrollRow(r, (i % 2) == 1)

        r.tTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.tTxt:SetPoint("TOPLEFT", r, "TOPLEFT", 6, -3)
        r.tTxt:SetPoint("TOPRIGHT", r, "TOPRIGHT", -56, -3)
        r.tTxt:SetJustifyH("LEFT")
        if r.tTxt.SetWordWrap then r.tTxt:SetWordWrap(false) end

        r.bTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.bTxt:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 6, 3)
        r.bTxt:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -56, 3)
        r.bTxt:SetJustifyH("LEFT")
        if r.bTxt.SetWordWrap then r.bTxt:SetWordWrap(false) end

        r.cntTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.cntTxt:SetPoint("RIGHT", r, "RIGHT", -6, 0)
        r.cntTxt:SetSize(48, 18)
        r.cntTxt:SetJustifyH("RIGHT")

        r:SetScript("OnClick", function(self)
            if self._grp then
                box.selectedKey = self._grp.key
                box.RenderLeft()
                box.SelectRight(false)
            end
        end)
        lRows[i] = r
    end
    box.lRows = lRows

    local RVIS, RROW_H = 6, 54
    local slotBox = CreateFrame("Frame", nil, rightPane)
    slotBox:SetPoint("TOPLEFT", rHdr, "BOTTOMLEFT", 0, -6)
    slotBox:SetPoint("BOTTOMRIGHT", rightPane, "BOTTOMRIGHT", -6, 4)

    local rRows = {}
    local sfRight = PS.AttachScroll(slotBox, RVIS * RROW_H, RROW_H, RVIS, function() box.RenderRight() end)
    sfRight:SetPoint("TOPLEFT", slotBox, "TOPLEFT", 0, 0)
    sfRight:SetPoint("BOTTOMRIGHT", slotBox, "BOTTOMRIGHT", 0, 0)
    box.sfRight = sfRight

    for i = 1, RVIS do
        local r = CreateFrame("Button", nil, sfRight)
        r:SetHeight(RROW_H - 3)
        r:SetPoint("TOPLEFT", sfRight, "TOPLEFT", 0, -(i - 1) * RROW_H)
        r:SetPoint("TOPRIGHT", sfRight, "TOPRIGHT", -16, -(i - 1) * RROW_H)
        PS.StyleScrollRow(r, (i % 2) == 1)

        local icBox = CreateFrame("Frame", nil, r)
        icBox:SetSize(34, 34)
        icBox:SetPoint("LEFT", r, "LEFT", 6, 0)
        PS.StyleBox(icBox, 0.75, false)
        local ic = icBox:CreateTexture(nil, "ARTWORK")
        ic:SetPoint("TOPLEFT", 2, -2)
        ic:SetPoint("BOTTOMRIGHT", -2, 2)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.icBox = icBox
        r.ic = ic

        r.nameTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.nameTxt:SetPoint("TOPLEFT", icBox, "TOPRIGHT", 8, 2)
        r.nameTxt:SetPoint("TOPRIGHT", r, "TOPRIGHT", -8, -5)
        r.nameTxt:SetJustifyH("LEFT")
        if r.nameTxt.SetWordWrap then r.nameTxt:SetWordWrap(false) end

        r.progTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.progTxt:SetPoint("TOPLEFT", r.nameTxt, "BOTTOMLEFT", 0, -3)
        r.progTxt:SetPoint("RIGHT", r, "RIGHT", -8, 0)
        r.progTxt:SetHeight(14)
        r.progTxt:SetJustifyH("LEFT")
        if r.progTxt.SetWordWrap then r.progTxt:SetWordWrap(false) end

        r.ownTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.ownTxt:SetPoint("BOTTOMLEFT", icBox, "BOTTOMRIGHT", 8, -2)
        r.ownTxt:SetPoint("RIGHT", r, "RIGHT", -8, 0)
        r.ownTxt:SetJustifyH("LEFT")
        if r.ownTxt.SetWordWrap then r.ownTxt:SetWordWrap(false) end

        r:SetScript("OnClick", function(self)
            local it = self._slot
            if not it then return end
            if IsControlKeyDown() and type(DressUpItemLink) == "function" then
                local lnk = AP:GetItemHyperlink(it.eid, nil, it.name, it.quality)
                if lnk then pcall(DressUpItemLink, lnk) end
            elseif IsShiftKeyDown() or (IsModifiedClick and IsModifiedClick("CHATLINK")) then
                AP:InsertItemLink(it.eid, nil, it.name, it.quality)
            end
        end)
        r:SetScript("OnEnter", function(self)
            local it = self._slot
            if not it then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local exLine = it.owned
                and string.format("У вас (%s): ковка %s", FormatLocation(it.owned.where), (AP.TIER_NAMES and AP.TIER_NAMES[it.ownedForge or 0]) or "Обычный")
                or "Предмета пока нет в сумках/банке"
            AP:BuildItemTooltip(GameTooltip, it.eid, {
                name = it.name,
                quality = it.quality,
                extraLine = exLine,
                hint = "|cff94a3b8Shift+ЛКМ: в чат | Ctrl+ЛКМ: примерить|r",
            })
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rRows[i] = r
    end
    box.rRows = rRows

    function box.RenderLeft()
        local off = sfLeft.offset or 0
        for i = 1, SVIS do
            local r = lRows[i]
            local g = box.groups[off + i]
            if not g then
                r._grp = nil
                r:Hide()
            else
                r._grp = g
                r:Show()
                local sel = (g.key == box.selectedKey)
                PS.StyleBox(r, sel and 0.65 or ((i % 2) == 1 and 0.42 or 0.25), sel)
                local facTag = (g.fac == "A" and "|cff38bdf8[А]|r ") or (g.fac == "H" and "|cffff6060[О]|r ") or ""
                local ilv = (g.gradeIlvl and g.gradeIlvl > 0) and (" (" .. g.gradeIlvl .. ")") or ""
                r.tTxt:SetText(facTag .. "|cffffd200" .. g.gradeLabel .. "|r" .. ilv .. " - " .. g.role)
                local owTxt = (g.ownedCount > 0) and (" |cff60a5fa(в наличии: " .. g.ownedCount .. ")|r") or ""
                local remTxt = (g.remainStats > 0) and string.format("|cffffd200+%d стат|r", g.remainStats) or "|cff40ff40Закрыто|r"
                r.bTxt:SetText(((box.classFilter == "ALL") and (g.className .. ": ") or "") .. remTxt .. owTxt)
                local tot = #g.items
                local col = (g.doneTit >= tot and tot > 0) and "|cff40ff40" or (g.inProg > 0 and "|cffffd200" or "|cff94a3b8")
                r.cntTxt:SetText(string.format("%s%d/%d|r", col, g.doneTit, tot))
            end
        end
    end

    function box.RenderRight()
        local selGrp = nil
        for _, g in ipairs(box.groups) do
            if g.key == box.selectedKey then selGrp = g; break end
        end
        if not selGrp then
            rTitle:SetText("|cff94a3b8Нет комплектов под выбранный фильтр|r")
            rSub:SetText("Попробуйте отключить «Скрыть 90%» или сменить фильтр тира.")
            box.slots = {}
            for i = 1, RVIS do rRows[i]._slot = nil; rRows[i]:Hide() end
            return
        end
        local ilv = (selGrp.gradeIlvl and selGrp.gradeIlvl > 0) and (" (ilvl " .. selGrp.gradeIlvl .. ")") or ""
        rTitle:SetText(string.format("|cffffd200%s|r - %s [%s]%s", selGrp.name, selGrp.role, selGrp.gradeLabel, ilv))
        local stk = AP.GetForgeMaterialStock and AP:GetForgeMaterialStock() or {}
        rSub:SetText(string.format("Титанический (90%%): |cff40ff40%d/%d|r | До 90%%: |cffffd200+%d стат|r | Эмблемы Триумфа: %d | Льда: %d",
            selGrp.doneTit, #selGrp.items, selGrp.remainStats, stk.triumphEmblem or 0, stk.frostEmblem or 0))
        box.slots = selGrp.items
        local off = sfRight.offset or 0
        for i = 1, RVIS do
            local r = rRows[i]
            local it = box.slots[off + i]
            if not it then
                r._slot = nil
                r:Hide()
            else
                r._slot = it
                r:Show()
                r.ic:SetTexture(it.tex or "Interface\\Icons\\INV_Misc_QuestionMark")
                r.nameTxt:SetText("|cff94a3b8[" .. it.slotLabel .. "]|r " .. ShortItemLink(it.eid, it.name, it.quality))
                if it.isCompleted then
                    r.progTxt:SetText("|cff40ff40Поглощение: Титанический (90%)|r")
                    PS.StyleBox(r.icBox, 0.75, false)
                    r.icBox:SetBackdropBorderColor(0.0, 1.0, 0.8, 0.9)
                elseif it.doneTier >= 0 then
                    local tNm = it.doneTierName or (AP.TIER_NAMES and AP.TIER_NAMES[it.doneTier]) or "?"
                    r.progTxt:SetText(string.format("|cffffd200Поглощение: %s (%d%%)|r -> ост. +%d стат", tNm, it.curPct or 0, it.remainStats or 0))
                    PS.StyleBox(r.icBox, 0.75, false)
                    r.icBox:SetBackdropBorderColor(1.0, 0.55, 0.1, 0.9)
                else
                    r.progTxt:SetText(string.format("|cff94a3b8Не поглощено (0%%)|r | До 90%%: +%d стат", it.remainStats or 0))
                    PS.StyleBox(r.icBox, 0.55, false)
                    r.icBox:SetBackdropBorderColor(0.45, 0.38, 0.22, 0.82)
                end
                if it.owned then
                    local fNm = (AP.TIER_NAMES and AP.TIER_NAMES[it.ownedForge or 0]) or "Обычный"
                    local aps = math.max(0, 3 - (it.ownedForge or 0))
                    local upgTxt = it.isCompleted and "" or (it.readyToAbsorb and " | |cff40ff40можно поглотить!|r" or (aps > 0 and (" -> еще " .. aps .. (aps == 1 and " шаг ковки" or " шага ковки")) or ""))
                    r.ownTxt:SetText("В наличии [" .. FormatLocation(it.owned.where) .. "] " .. fNm .. upgTxt)
                else
                    r.ownTxt:SetText("|cff888888Нет в сумках, на персонаже или в банке|r")
                end
            end
        end
    end

    function box.SelectRight(keepOffset)
        local selGrp = nil
        for _, g in ipairs(box.groups) do
            if g.key == box.selectedKey then selGrp = g; break end
        end
        box.slots = selGrp and selGrp.items or {}
        sfRight:SetTotal(#box.slots, keepOffset)
    end

    function box.RefreshData()
        for k, b in pairs(tBtns) do PS.PaintBtn(b, (box.tierFilter == k) and "gold" or "dark") end
        PS.PaintBtn(incBtn, box.onlyIncomplete and "green" or "dark")
        PS.PaintBtn(clsBtn, (box.classFilter == "ALL") and "gold" or "dark")
        clsBtn.label:SetText((box.classFilter == "ALL") and "Все классы" or "Мой класс")

        if type(AP.GetMorKelSetsProgress) ~= "function" then
            box.groups = {}
            box.slots = {}
            sfLeft:SetTotal(0, false)
            sfRight:SetTotal(0, false)
            foot:SetText("|cff94a3b8Данные сетов загружаются...|r")
            return
        end

        local res = AP:GetMorKelSetsProgress({
            tierFilter = box.tierFilter,
            classFilter = box.classFilter,
            onlyIncomplete = box.onlyIncomplete,
        })
        box.groups = res.groups or {}
        local keepSel = false
        for _, g in ipairs(box.groups) do
            if g.key == box.selectedKey then keepSel = true; break end
        end
        if not keepSel then
            box.selectedKey = box.groups[1] and box.groups[1].key or nil
        end
        sfLeft:SetTotal(#box.groups, keepSel)
        box.SelectRight(keepSel)

        if res.warming then
            warmBtn.label:SetText("Кэш: " .. (res.warmRemaining or 0) .. "...")
            PS.PaintBtn(warmBtn, "green")
        elseif (res.uncachedCount or 0) > 0 then
            warmBtn.label:SetText("Прогреть (" .. res.uncachedCount .. ")")
            PS.PaintBtn(warmBtn, "dark")
        else
            warmBtn.label:SetText("Кэш готов")
            PS.PaintBtn(warmBtn, "dark")
        end

        foot:SetText(string.format("|cffb0a080Наборов: %d | Закрыто (90%%): |cff40ff40%d/%d|r|cffb0a080 | В процессе: |cffffd200%d|r|cffb0a080 | На руках: %d | До 90%%: |cffffd200+%d стат|r",
            #box.groups, res.totalTit or 0, res.totalPieces or 0, res.totalInProg or 0, res.totalOwned or 0, res.totalRemainStats or 0))
    end

    return box
end

-- Вкладка 5: Настройки AttuneParser
local function BuildSettingsTab(parent)
    local box = CreateFrame("Frame", nil, parent)
    box:SetAllPoints(parent)

    local leftCard = CreateFrame("Frame", nil, box)
    leftCard:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    leftCard:SetSize(368, 428)
    PS.StyleBox(leftCard, 0.50, false)

    local rightCard = CreateFrame("Frame", nil, box)
    rightCard:SetPoint("TOPLEFT", leftCard, "TOPRIGHT", 8, 0)
    rightCard:SetSize(368, 428)
    PS.StyleBox(rightCard, 0.50, false)

    local function AddSetDiv(card, y)
        local d = card:CreateTexture(nil, "ARTWORK")
        d:SetTexture("Interface\\Buttons\\WHITE8X8")
        d:SetVertexColor(1, 1, 1, 0.08)
        d:SetHeight(1)
        d:SetPoint("TOPLEFT", card, "TOPLEFT", 12, y)
        d:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, y)
        return d
    end

    local lHdr = leftCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lHdr:SetPoint("TOPLEFT", 12, -10)
    lHdr:SetText("|cffffd200Интерфейс и блоки|r")

    box.subTab = "widgets"
    local tabBlkBtn = PS.MakeBtn(leftCard, 78, 20, "Блоки UI", "dark")
    tabBlkBtn:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -10, -7)
    local tabWidBtn = PS.MakeBtn(leftCard, 78, 20, "Виджеты", "gold")
    tabWidBtn:SetPoint("RIGHT", tabBlkBtn, "LEFT", -4, 0)

    AddSetDiv(leftCard, -32)

    local widGroup = CreateFrame("Frame", nil, leftCard)
    widGroup:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 0, -34)
    widGroup:SetPoint("BOTTOMRIGHT", leftCard, "BOTTOMRIGHT", 0, 74)

    local blkGroup = CreateFrame("Frame", nil, leftCard)
    blkGroup:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 0, -34)
    blkGroup:SetPoint("BOTTOMRIGHT", leftCard, "BOTTOMRIGHT", 0, 74)
    blkGroup:Hide()

    local rHdr = rightCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rHdr:SetPoint("TOPLEFT", 12, -10)
    rHdr:SetText("|cffffd200Расчеты, Скан и Питомец Талориан|r")
    AddSetDiv(rightCard, -32)

    local updaters = {}
    local function AddToggle(card, xOff, yOff, w, h, settingKey, label, tip)
        local row = CreateFrame("Button", nil, card)
        row:SetPoint("TOPLEFT", card, "TOPLEFT", xOff, yOff)
        row:SetSize(w, h)
        local chk = CreateFrame("Frame", nil, row)
        chk:SetPoint("LEFT", row, "LEFT", 0, 0)
        chk:SetSize(16, 16)
        PS.StyleBox(chk, 0.70, false)
        local mark = chk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mark:SetPoint("CENTER", 0, 0)
        local txt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", chk, "RIGHT", 6, 0)
        txt:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        txt:SetJustifyH("LEFT")
        if txt.SetWordWrap then txt:SetWordWrap(false) end
        txt:SetText(label)

        row:SetScript("OnClick", function()
            local cur = AP:GetSetting(settingKey) == true
            AP:SetSetting(settingKey, not cur)
            box.RefreshData()
        end)
        if tip then
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(label, 1, 0.85, 0.25)
                GameTooltip:AddLine(tip, 0.9, 0.9, 0.9, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        table.insert(updaters, function()
            local on = AP:GetSetting(settingKey) == true
            if on then
                mark:SetText("|cff40ff40V|r")
                PS.StyleBox(chk, 0.75, true)
                txt:SetTextColor(0.95, 0.95, 0.95)
            else
                mark:SetText("")
                PS.StyleBox(chk, 0.55, false)
                txt:SetTextColor(0.62, 0.66, 0.72)
            end
        end)
        return row
    end

    AddToggle(widGroup, 10, -4,  344, 22, "showMinimap", "Кнопка у миникарты", "Показывать или скрывать кнопку AttuneParser у миникарты (/ap minimap).")
    AddToggle(widGroup, 10, -28, 344, 22, "showPrimeHub", "Значок в меню аддонов (PrimeHub)", "Показывать плитку AttuneParser в общем центре аддонов.")
    AddToggle(widGroup, 10, -52, 344, 22, "showAuctionUI", "Помощник ковки на аукционе", "Показывать кнопку и панель фильтра поглощения на аукционе.")
    AddToggle(widGroup, 10, -76, 344, 22, "showValdrisBar", "Панель прогрессии Вальдриса", "Верхняя панель в окне улучшения вещей (выбор вещи по иконкам и автоулучшение).")
    AddToggle(widGroup, 10, -100, 344, 22, "showEJOverlay", "Панель в Путеводителе", "Боковая панель прогресса подземелья, вещей в сумках и бонусов в Путеводителе.")
    AddToggle(widGroup, 10, -124, 344, 22, "showEJBadges", "Отметки добычи в Путеводителе", "Показывать значки прогресса и ковки прямо на строках добычи.")
    AddToggle(widGroup, 10, -148, 344, 22, "tradeAlert", "Сводка в чате при обмене", "Выводить в чат сводку по поглощаемым и недокованным вещам в окне обмена.")

    AddSetDiv(widGroup, -176)

    local ejSideBtn = PS.MakeBtn(widGroup, 344, 24, "Сторона оверлея Путеводителя: Справа", "dark")
    ejSideBtn:SetPoint("TOPLEFT", widGroup, "TOPLEFT", 12, -184)
    ejSideBtn:SetScript("OnClick", function()
        local cur = AP:GetSetting("ejOverlaySide")
        AP:SetSetting("ejOverlaySide", (cur == "LEFT") and "RIGHT" or "LEFT")
        box.RefreshData()
    end)

    local resetMmBtn = PS.MakeBtn(widGroup, 169, 24, "Сброс миникарты", "dark")
    resetMmBtn:SetPoint("TOPLEFT", widGroup, "TOPLEFT", 12, -214)
    resetMmBtn:SetScript("OnClick", function()
        KeepAttuneMinimapInPrimeHub()
        AP:SetSetting("minimapAngle", 225)
        AP:SetSetting("showMinimap", true)
        box.RefreshData()
    end)

    local resetAucBtn = PS.MakeBtn(widGroup, 169, 24, "Сброс кнопки аука", "dark")
    resetAucBtn:SetPoint("LEFT", resetMmBtn, "RIGHT", 6, 0)
    resetAucBtn:SetScript("OnClick", function()
        AP:ResetAuctionPos()
        DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Позиция кнопки аукциона сброшена.")
    end)

    AddSetDiv(widGroup, -246)
    local preLbl = widGroup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    preLbl:SetPoint("TOPLEFT", 12, -254)
    preLbl:SetText("|cffb0a080Быстрые наборы блоков:|r")

    local preFullBtn = PS.MakeBtn(widGroup, 110, 22, "Все вкл.", "dark")
    preFullBtn:SetPoint("TOPLEFT", widGroup, "TOPLEFT", 12, -274)
    preFullBtn:SetScript("OnClick", function() AP:ApplyUIBlockPreset("full") end)

    local preMinBtn = PS.MakeBtn(widGroup, 112, 22, "Минимум (Топ)", "dark")
    preMinBtn:SetPoint("LEFT", preFullBtn, "RIGHT", 5, 0)
    preMinBtn:SetScript("OnClick", function() AP:ApplyUIBlockPreset("minimal") end)

    local preFarmBtn = PS.MakeBtn(widGroup, 112, 22, "Фарм и Ковка", "dark")
    preFarmBtn:SetPoint("LEFT", preMinBtn, "RIGHT", 5, 0)
    preFarmBtn:SetScript("OnClick", function() AP:ApplyUIBlockPreset("farm") end)

    -- Sub-tab 2: UI Blocks toggles
    local defByKey = {}
    for _, d in ipairs(AP.UI_BLOCK_DEFS or {}) do defByKey[d.key] = d end
    local uiBlkList = {
        { "blkHeaderLinks",    "Кнопки в шапке окна (Талориан/Атлас/Гид/Вехи)" },
        { "blkTabSummary",     "Вкладка: Обзор и Дары" },
        { "blkTabBags",        "Вкладка: Сумки и Ковка" },
        { "blkTabSets",        "Вкладка: Сеты T9 / T10" },
        { "blkTabServer",      "Вкладка: События и Боссы" },
        { "blkSumCatalog",     "Обзор - Карточка: Каталог и Вехи" },
        { "blkSumGiftsDust",   "Обзор - Карточка: Бонус дня и Пыль" },
        { "blkSumParagonAuto", "Обзор - Карточка: Уровень и Спек" },
        { "blkSumStats",       "Обзор - Карточка: Суммарные статы" },
        { "blkBagsActions",    "Сумки - Нижняя панель действий" },
        { "blkSrvAuto",        "События - Блок Автопоглощения/Продажи" },
        { "blkSrvBanks",       "События - Хранилища и Ключи M+" },
        { "blkSrvBosses",      "События - Таймеры мировых боссов" },
    }
    for idx, bDef in ipairs(uiBlkList) do
        local d = defByKey[bDef[1]]
        AddToggle(blkGroup, 10, -2 - (idx - 1) * 23, 346, 21, bDef[1], bDef[2], d and d.desc or bDef[2])
    end

    AddSetDiv(leftCard, -356)
    local wizardBtn = PS.MakeBtn(leftCard, 344, 28, "|cffffd200Мастер выбора блоков (первый запуск)|r", "gold")
    wizardBtn:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 12, -364)
    wizardBtn:SetScript("OnClick", function()
        if type(AP.ShowOnboardingWizard) == "function" then
            AP:ShowOnboardingWizard(true)
        end
    end)
    local wizardHint = leftCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    wizardHint:SetPoint("BOTTOMLEFT", 12, 10)
    wizardHint:SetText("|cff8896a8Также доступно в любое время по команде /ap blocks|r")

    local function UpdateSubTabs()
        local isW = (box.subTab ~= "blocks")
        PS.PaintBtn(tabWidBtn, isW and "gold" or "dark")
        PS.PaintBtn(tabBlkBtn, isW and "dark" or "gold")
        if isW then
            widGroup:Show(); blkGroup:Hide()
        else
            widGroup:Hide(); blkGroup:Show()
        end
    end
    tabWidBtn:SetScript("OnClick", function() box.subTab = "widgets"; UpdateSubTabs() end)
    tabBlkBtn:SetScript("OnClick", function() box.subTab = "blocks"; UpdateSubTabs() end)

    AddToggle(rightCard, 10, -40, 344, 22, "wedAuto", "Приоритет ковки по средам", "По средам при открытии списка автоматически включать приоритет ковки до 90%.")
    AddToggle(rightCard, 10, -68, 344, 22, "excludeHeavyQuests", "Исключать тяжелые квест-цепочки", "Скрывать труднодоступные квестовые награды из рекомендаций фарма.")
    AddToggle(rightCard, 10, -96, 344, 22, "autoWarmStats", "Фоновая загрузка характеристик", "После входа плавно до-загружать характеристики редких предметов без лагов.")

    AddSetDiv(rightCard, -126)
    local talHdr = rightCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    talHdr:SetPoint("TOPLEFT", 12, -134)
    talHdr:SetText("|cffffd200Взаимодействие с питомцем Талориан|r")

    local talModeBtn = PS.MakeBtn(rightCard, 344, 24, "Режим Талориана: Авто", "dark")
    talModeBtn:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 12, -156)
    talModeBtn:SetScript("OnClick", function()
        local cur = AP:GetSetting("talorianMode")
        AP:SetSetting("talorianMode", (cur == "off") and "auto" or "off")
        box.RefreshData()
    end)

    local talInfo = rightCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    talInfo:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 12, -188)
    talInfo:SetPoint("RIGHT", rightCard, "RIGHT", -12, 0)
    talInfo:SetJustifyH("LEFT")

    local testTalBtn = PS.MakeBtn(rightCard, 188, 24, "Открыть окно Талориана", "green")
    testTalBtn:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 12, -268)
    testTalBtn:SetScript("OnClick", function() AP:OpenTalorianUI() end)

    AddSetDiv(rightCard, -300)
    local srvHdr = rightCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    srvHdr:SetPoint("TOPLEFT", 12, -308)
    srvHdr:SetText("|cffffd200Автопоглощение и автопродажа|r")

    local srvAutoBtn = PS.MakeBtn(rightCard, 206, 22, "Автопоглощение: ?", "dark")
    srvAutoBtn:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 12, -330)
    srvAutoBtn:SetScript("OnClick", function()
        local as = AP:GetAutoSwapSummary()
        AP:SetAutoAbsorb(not (as.on == true))
        AP.After(0.25, function() box.RefreshData() end, "ap_ui_srv_ref")
    end)

    local srvBoeBtn = PS.MakeBtn(rightCard, 132, 22, "BoE: ?", "dark")
    srvBoeBtn:SetPoint("LEFT", srvAutoBtn, "RIGHT", 6, 0)
    srvBoeBtn:SetScript("OnClick", function()
        local as = AP:GetAutoSwapSummary()
        AP:SetAutoAbsorbBoE(not (as.boeAllowed == true))
        AP.After(0.25, function() box.RefreshData() end, "ap_ui_srv_ref")
    end)

    local srvSellBtn = PS.MakeBtn(rightCard, 344, 22, "Автопродажа поглощенных: ?", "dark")
    srvSellBtn:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 12, -358)
    srvSellBtn:SetScript("OnClick", function()
        local as = AP:GetAutoSwapSummary()
        if not as.unlocked then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[AttuneParser]|r Автопродажа поглощенных не разблокирована на аккаунте.")
            return
        end
        AP:SetAutoSellActive(not (as.active == true))
        AP.After(0.25, function() box.RefreshData() end, "ap_ui_srv_ref")
    end)

    function box.RefreshData()
        UpdateSubTabs()
        for _, fn in ipairs(updaters) do fn() end
        local side = AP:GetSetting("ejOverlaySide")
        ejSideBtn.label:SetText("Сторона оверлея Путеводителя: " .. (side == "LEFT" and "Слева" or "Справа"))

        local tm = AP:GetSetting("talorianMode")
        talModeBtn.label:SetText("Режим Талориана: " .. (tm == "off" and "|cffff8080Отключен|r" or "|cff40ff40Авто (при наличии питомца)|r"))

        local hasPet, isSum = AP:HasTalorianPet()
        local talLoaded, talTtpOn, bridgeOn, talOff = false, true, AP:IsTalorianBridgeActive(), (tm == "off")
        if type(AP.GetTalorianStatus) == "function" then
            talLoaded, talTtpOn, bridgeOn, talOff = AP:GetTalorianStatus()
        else
            talLoaded = (AP._talorianBridge ~= nil) or (type(rawget(_G, "TalorianTP")) == "table")
            talTtpOn = not (type(_G.TalorianTP_DB) == "table" and _G.TalorianTP_DB.enabled == false)
        end
        local petStr = hasPet and (isSum and "|cff40ff40Найден и призван|r" or "|cff40ff40Есть в коллекции|r") or "|cffff8080Отсутствует|r"
        local modStr = talLoaded and (talTtpOn and "|cff40ff40Подключен|r" or "|cffffd200Загружен (выкл в /ttp)|r") or "|cff94a3b8Не загружен|r"
        local linkStr = bridgeOn and "|cff40ff40Активна|r" or ((talLoaded and not talTtpOn) and "|cffffd200Выкл в TalorianTP|r" or (talOff and "|cff94a3b8Выкл в AttuneParser|r" or "|cff94a3b8Выкл|r"))
        talInfo:SetText(string.format(
            "Спутник Талориан: %s\nМодуль TalorianTP: %s\nАктивность связки: %s\n\nЕсли спутника нет, AttuneParser работает полностью автономно без ошибок и лишних кнопок.",
            petStr, modStr, linkStr
        ))
        if bridgeOn or talLoaded then
            testTalBtn:Show()
        else
            testTalBtn:Hide()
        end

        local as = AP:GetAutoSwapSummary()
        PS.PaintBtn(srvAutoBtn, as.on == true and "green" or "dark")
        srvAutoBtn.label:SetText("Автопоглощение: " .. (as.on == true and "ВКЛ" or "ВЫКЛ"))
        PS.PaintBtn(srvBoeBtn, as.boeAllowed == true and "green" or "dark")
        srvBoeBtn.label:SetText("BoE: " .. (as.boeAllowed == true and "ДА" or "НЕТ"))
        if as.unlocked then
            PS.PaintBtn(srvSellBtn, as.active and "green" or "dark")
            srvSellBtn.label:SetText("Автопродажа поглощенных: " .. (as.active and "ВКЛ" or "ВЫКЛ"))
        else
            PS.PaintBtn(srvSellBtn, "gray")
            srvSellBtn.label:SetText("Автопродажа: не разблокирована")
        end
    end

    return box
end

local raiseQueue = {}
local raiseDriver = CreateFrame("Frame")
raiseDriver:Hide()
raiseDriver:SetScript("OnUpdate", function(self)
    self:Hide()
    for fr in pairs(raiseQueue) do
        raiseQueue[fr] = nil
        if fr and fr:IsShown() and type(fr.Raise) == "function" then
            pcall(fr.Raise, fr)
        end
    end
end)

local function RaiseFrameFront(fr)
    if not fr then return end
    if type(fr.Raise) == "function" then pcall(fr.Raise, fr) end
    raiseQueue[fr] = true
    raiseDriver:Show()
end
AP.RaiseFrameFront = RaiseFrameFront

local function CreateMainWindow()
    if mainFrame then return mainFrame end
    local f = CreateFrame("Frame", "AttuneParserFrame", UIParent)
    f:SetSize(780, 580)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    PS.ApplyWindow(f)
    table.insert(UISpecialFrames, "AttuneParserFrame")
    mainFrame = f

    local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hdr:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -11)
    hdr:SetText("|cffffd200AttuneParser|r")

    f.subText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.subText:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -37)
    f.subText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -37)
    f.subText:SetHeight(16)
    f.subText:SetJustifyH("LEFT")
    if f.subText.SetWordWrap then f.subText:SetWordWrap(false) end

    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -10)
    PS.StyleClose(closeBtn, 24)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    f.claimBtn = PS.MakeBtn(f, 80, 22, "Вехи", "dark")
    f.claimBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    f.claimBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.claimBtn:SetScript("OnClick", function(_, mouseBtn)
        local ms = AP:GetMilestonesSummary()
        if mouseBtn == "RightButton" then
            AP:RequestServerSync(true)
            DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Запрошено обновление вех и прогресса с сервера.")
            AP.After(0.5, function() AP:RefreshUI() end, "ap_ui_claim_hdr")
            return
        end
        if (ms.claimable or 0) > 0 then
            local n = AP:ClaimAllMilestones()
            DEFAULT_CHAT_FRAME:AddMessage("|cff40ff40[AttuneParser]|r Отправлено запросов на награды вех: " .. n)
            AP.After(0.6, function() AP:RefreshUI() end, "ap_ui_claim_hdr")
        else
            AP:RequestServerSync(false)
            AP:OpenUI("summary")
            if not ms.loaded then
                DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[AttuneParser]|r Вехи загружаются с сервера... Открыт «Обзор и Дары».")
            else
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff38bdf8[AttuneParser]|r Вехи: поглощено %d | доступно наград: 0%s",
                    ms.done or 0, ms.nextNeed and (" | след. веха на " .. ms.nextNeed .. " (ост. " .. (ms.nextRemain or 0) .. ")") or ""))
            end
        end
    end)
    f.claimBtn:SetScript("OnEnter", function(self)
        local ms = AP:GetMilestonesSummary()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("|cffffd200Вехи поглощения|r")
        if not ms.loaded then
            GameTooltip:AddLine("Данные вех еще не загружены с сервера.", 0.9, 0.9, 0.9)
        else
            GameTooltip:AddLine(string.format("Поглощено: |cffffffff%d|r | Доступно наград: %s%d|r",
                ms.done or 0, (ms.claimable or 0) > 0 and "|cff40ff40" or "|cff94a3b8", ms.claimable or 0), 1, 1, 1)
            local list = (AP.serverMilestones and AP.serverMilestones.list) or {}
            local shown = 0
            for _, m in ipairs(list) do
                if m.state == 1 or (m.state == 0 and (m.need or 0) > (ms.done or 0)) then
                    local rew = {}
                    if (m.elixir or 0) > 0 then table.insert(rew, m.elixir .. " эликс.") end
                    if (m.epic or 0) > 0 then table.insert(rew, m.epic .. " эпик") end
                    if (m.leg or 0) > 0 then table.insert(rew, m.leg .. " лег") end
                    if (m.tit or 0) > 0 then table.insert(rew, m.tit .. " титан") end
                    local rStr = #rew > 0 and table.concat(rew, ", ") or "награда"
                    if m.state == 1 then
                        GameTooltip:AddLine(string.format("  |cff40ff40[Готово]|r %d предм. -> %s", m.need or 0, rStr), 1, 1, 1)
                    else
                        GameTooltip:AddLine(string.format("  |cffffd200[%d]|r ост. %d -> %s", m.need or 0, math.max(0, (m.need or 0) - (ms.done or 0)), rStr), 0.85, 0.85, 0.85)
                    end
                    shown = shown + 1
                    if shown >= 4 then break end
                end
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff94a3b8ЛКМ: забрать доступные вехи / открыть «Обзор и Дары»\nПКМ: обновить данные с сервера|r", 1, 1, 1)
        GameTooltip:Show()
    end)
    f.claimBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.ejBtn = PS.MakeBtn(f, 98, 22, "Путеводитель", "dark")
    f.ejBtn:SetPoint("RIGHT", f.claimBtn, "LEFT", -4, 0)
    f.ejBtn:SetScript("OnClick", function()
        if type(AP.ToggleEncounterJournal) == "function" then
            AP:ToggleEncounterJournal()
        elseif type(AP.OpenEncounterJournal) == "function" then
            AP:OpenEncounterJournal()
        end
    end)
    f.ejBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("|cffffd200Путеводитель по приключениям|r")
        GameTooltip:AddLine("ЛКМ: Открыть или закрыть Путеводитель", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    f.ejBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.atlasBtn = PS.MakeBtn(f, 60, 22, "Атлас", "dark")
    f.atlasBtn:SetPoint("RIGHT", f.ejBtn, "LEFT", -4, 0)
    f.atlasBtn:SetScript("OnClick", function() AP:OpenAtlas() end)

    f.talBtn = PS.MakeBtn(f, 76, 22, "Талориан", "green")
    f.talBtn:SetPoint("RIGHT", f.atlasBtn, "LEFT", -4, 0)
    f.talBtn:SetScript("OnClick", function() AP:OpenTalorianUI() end)

    local tabDefs = {
        { key = "top", label = "Топ инстов", w = 108 },
        { key = "summary", label = "Обзор и Дары", w = 122, blockKey = "blkTabSummary" },
        { key = "bags", label = "Сумки и Ковка", w = 130, blockKey = "blkTabBags" },
        { key = "sets", label = "Сеты T9 / T10", w = 124, blockKey = "blkTabSets" },
        { key = "settings", label = "Настройки", w = 104 },
        { key = "server", label = "События и Боссы", w = 131, blockKey = "blkTabServer" },
    }
    f.tabDefs = tabDefs
    f.tabBtns = {}
    f.tabPanels = {}
    local tx = 18
    for _, td in ipairs(tabDefs) do
        local tb = PS.MakeBtn(f, td.w, 26, td.label, "dark")
        tb:SetPoint("TOPLEFT", f, "TOPLEFT", tx, -58)
        tx = tx + td.w + 5
        tb:SetScript("OnClick", function() AP:OpenUI(td.key) end)
        f.tabBtns[td.key] = tb
    end

    local tabDiv = f:CreateTexture(nil, "ARTWORK")
    tabDiv:SetTexture("Interface\\Buttons\\WHITE8X8")
    tabDiv:SetVertexColor(0.95, 0.78, 0.28, 0.22)
    tabDiv:SetHeight(1)
    tabDiv:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -87)
    tabDiv:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -87)

    function f.RelayoutTabs()
        local xPos = 18
        local activeVis = false
        for _, td in ipairs(tabDefs) do
            local btn = f.tabBtns[td.key]
            local vis = (not td.blockKey) or (type(AP.IsBlockEnabled) ~= "function") or AP:IsBlockEnabled(td.blockKey)
            if vis then
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", f, "TOPLEFT", xPos, -58)
                btn:Show()
                xPos = xPos + td.w + 5
                if f.activeTab == td.key then activeVis = true end
            else
                btn:Hide()
            end
        end
        if not activeVis then
            f.activeTab = "top"
        end
    end

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -92)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 16)
    f.content = content

    f.tabPanels.top = BuildTopTab(content)
    f.tabPanels.summary = BuildSummaryTab(content)
    f.tabPanels.bags = BuildBagsTab(content)
    f.tabPanels.sets = BuildSetsTab(content)
    f.tabPanels.settings = BuildSettingsTab(content)
    f.tabPanels.server = (type(AP.BuildServerSyncTab) == "function") and AP.BuildServerSyncTab(content) or CreateFrame("Frame", nil, content)

    f.activeTab = "top"
    f:SetScript("OnShow", function()
        PlaySound("igCharacterInfoOpen")
        AP:RefreshUI()
    end)
    f:SetScript("OnHide", function()
        PlaySound("igCharacterInfoClose")
    end)
    return f
end

function AP:RefreshUI()
    if not mainFrame or not mainFrame:IsShown() then return end
    RefreshHeaderAndFooter()
    for k, panel in pairs(mainFrame.tabPanels) do
        if k == mainFrame.activeTab then
            panel:Show()
            if panel.RefreshData then panel.RefreshData() end
        else
            panel:Hide()
        end
    end
end

do
    local onboardingFrame = nil

    function AP:ShowOnboardingWizard(force)
        if not force and self:GetSetting("uiOnboardingDone") == true then
            return nil
        end
        if onboardingFrame then
            onboardingFrame:Show()
            if onboardingFrame.RefreshRows then onboardingFrame:RefreshRows() end
            RaiseFrameFront(onboardingFrame)
            return onboardingFrame
        end

        local wf = CreateFrame("Frame", "AP_OnboardingFrame", UIParent)
        wf:SetSize(610, 514)
        wf:SetPoint("CENTER", 20, -10)
        wf:SetFrameStrata("DIALOG")
        wf:SetToplevel(true)
        wf:EnableMouse(true)
        wf:SetMovable(true)
        wf:RegisterForDrag("LeftButton")
        wf:SetScript("OnDragStart", wf.StartMoving)
        wf:SetScript("OnDragStop", wf.StopMovingOrSizing)
        wf:SetClampedToScreen(true)
        PS.ApplyWindow(wf)
        table.insert(UISpecialFrames, "AP_OnboardingFrame")

        local wTitle = wf:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        wTitle:SetPoint("TOPLEFT", 16, -14)
        wTitle:SetText("|cffffd200Добро пожаловать в AttuneParser v" .. tostring(AP.VERSION) .. "|r")

        local wSub = wf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        wSub:SetPoint("TOPLEFT", 16, -34)
        wSub:SetPoint("TOPRIGHT", -46, -34)
        wSub:SetJustifyH("LEFT")
        wSub:SetText("|cffc8bea8Выберите нужные вкладки, карточки и панели (обновляется сразу). Вернуться можно в Настройках или /ap blocks.|r")

        local wClose = CreateFrame("Button", nil, wf)
        wClose:SetPoint("TOPRIGHT", wf, "TOPRIGHT", -12, -12)
        PS.StyleClose(wClose, 24)
        wClose:SetScript("OnClick", function()
            AP:SetSetting("uiOnboardingDone", true)
            wf:Hide()
        end)

        local preLbl = wf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        preLbl:SetPoint("TOPLEFT", 16, -66)
        preLbl:SetText("|cffffd200Готовые наборы:|r")

        wf.presetFullBtn = PS.MakeBtn(wf, 146, 22, "Все включено (Полный)", "green")
        wf.presetFullBtn:SetPoint("TOPLEFT", wf, "TOPLEFT", 128, -61)
        wf.presetFullBtn:SetScript("OnClick", function()
            AP:ApplyUIBlockPreset("full")
            wf:RefreshRows()
        end)

        wf.presetMinBtn = PS.MakeBtn(wf, 152, 22, "Минимум (Только Топ)", "dark")
        wf.presetMinBtn:SetPoint("TOPLEFT", wf, "TOPLEFT", 280, -61)
        wf.presetMinBtn:SetScript("OnClick", function()
            AP:ApplyUIBlockPreset("minimal")
            wf:RefreshRows()
        end)

        wf.presetFarmBtn = PS.MakeBtn(wf, 156, 22, "Фарм и Ковка", "dark")
        wf.presetFarmBtn:SetPoint("TOPLEFT", wf, "TOPLEFT", 438, -61)
        wf.presetFarmBtn:SetScript("OnClick", function()
            AP:ApplyUIBlockPreset("farm")
            wf:RefreshRows()
        end)

        local listBox = CreateFrame("Frame", nil, wf)
        listBox:SetPoint("TOPLEFT", 14, -90)
        listBox:SetPoint("BOTTOMRIGHT", -14, 48)
        PS.StyleBox(listBox, 0.50, false)

        local VIS = 7
        local ROW_H = 51
        local rows = {}
        local defs = AP.UI_BLOCK_DEFS or {}
        local sf
        sf = PS.AttachScroll(listBox, VIS * ROW_H, ROW_H, VIS, function()
            if wf.RenderRows then wf:RenderRows() end
        end)
        sf:SetPoint("TOPLEFT", listBox, "TOPLEFT", 4, -4)
        sf:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -4, 4)
        wf.sf = sf

        for i = 1, VIS do
            local r = CreateFrame("Button", nil, sf)
            r:SetHeight(ROW_H - 2)
            r:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i - 1) * ROW_H)
            r:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -16, -(i - 1) * ROW_H)
            PS.StyleScrollRow(r, (i % 2) == 1)

            local chk = CreateFrame("Frame", nil, r)
            chk:SetSize(18, 18)
            chk:SetPoint("TOPLEFT", r, "TOPLEFT", 8, -8)
            PS.StyleBox(chk, 0.72, false)
            r.chk = chk

            local mk = chk:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            mk:SetPoint("CENTER", 0, 0)
            r.mk = mk

            local ttl = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            ttl:SetPoint("TOPLEFT", chk, "TOPRIGHT", 8, 1)
            ttl:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            ttl:SetJustifyH("LEFT")
            r.ttl = ttl

            local dsc = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            dsc:SetPoint("TOPLEFT", ttl, "BOTTOMLEFT", 0, -2)
            dsc:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -8, 4)
            dsc:SetJustifyH("LEFT")
            dsc:SetJustifyV("TOP")
            dsc:SetTextColor(0.68, 0.74, 0.82)
            r.dsc = dsc

            r:SetScript("OnClick", function(self)
                if not self._def then return end
                local cur = AP:GetSetting(self._def.key) == true
                AP:SetSetting(self._def.key, not cur)
                wf:RefreshRows()
            end)
            rows[i] = r
        end
        wf.rows = rows

        function wf:RenderRows()
            local curDefs = AP.UI_BLOCK_DEFS or {}
            local off = sf.offset or 0
            for i = 1, VIS do
                local r = rows[i]
                local def = curDefs[off + i]
                if def then
                    r._def = def
                    local on = AP:GetSetting(def.key) == true
                    r.ttl:SetText(on and ("|cffffd200" .. def.title .. "|r") or ("|cff7c8594" .. def.title .. " (скрыт)|r"))
                    r.dsc:SetText(def.desc or "")
                    if on then
                        r.mk:SetText("|cff40ff40V|r")
                        PS.StyleBox(r.chk, 0.80, true)
                    else
                        r.mk:SetText("")
                        PS.StyleBox(r.chk, 0.55, false)
                    end
                    r:Show()
                else
                    r._def = nil
                    r:Hide()
                end
            end
        end

        function wf:RefreshRows()
            local curDefs = AP.UI_BLOCK_DEFS or {}
            sf:SetTotal(#curDefs, true)
        end

        local footNote = wf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        footNote:SetPoint("BOTTOMLEFT", 16, 17)
        footNote:SetText("Вы всегда можете изменить набор в Настройках.")

        wf.skipBtn = PS.MakeBtn(wf, 170, 26, "Оставить все и закрыть", "dark")
        wf.skipBtn:SetPoint("BOTTOMRIGHT", wf, "BOTTOMRIGHT", -196, 12)
        wf.skipBtn:SetScript("OnClick", function()
            if type(AP.ApplyUIBlockPreset) == "function" then AP:ApplyUIBlockPreset("full") end
            if type(AP.SetSetting) == "function" then AP:SetSetting("uiOnboardingDone", true) end
            wf:Hide()
        end)

        wf.applyBtn = PS.MakeBtn(wf, 176, 26, "|cff40ff40Применить и сохранить|r", "green")
        wf.applyBtn:SetPoint("BOTTOMRIGHT", wf, "BOTTOMRIGHT", -14, 12)
        wf.applyBtn:SetScript("OnClick", function()
            if type(AP.SetSetting) == "function" then AP:SetSetting("uiOnboardingDone", true) end
            wf:Hide()
        end)

        wf:RefreshRows()
        wf:Show()
        RaiseFrameFront(wf)
        onboardingFrame = wf
        return wf
    end

    AP._RefreshOnboardingWizard = function()
        if onboardingFrame and onboardingFrame:IsShown() and onboardingFrame.RenderRows then
            onboardingFrame:RenderRows()
        end
    end
end

function AP:OpenUI(tabKey)
    local f = CreateMainWindow()
    if tabKey and f.tabPanels[tabKey] then
        local tdMatch = nil
        for _, td in ipairs(f.tabDefs or {}) do
            if td.key == tabKey then tdMatch = td; break end
        end
        local canEnable = (type(self.IsBlockEnabled) ~= "function") or self:IsBlockEnabled(tdMatch and tdMatch.blockKey)
        if not tdMatch or not tdMatch.blockKey or canEnable then
            f.activeTab = tabKey
        else
            f.activeTab = "top"
        end
    end
    f:Show()
    RaiseFrameFront(f)
    AP:RefreshUI()
    if type(AP.UI_BLOCK_DEFS) == "table" and self:GetSetting("uiOnboardingDone") ~= true and not AP._onboardingAutoOpened then
        AP._onboardingAutoOpened = true
        AP:ShowOnboardingWizard(false)
    end
end

function AP:ToggleUI(tabKey)
    if mainFrame and mainFrame:IsShown() then
        if tabKey and mainFrame.activeTab ~= tabKey and mainFrame.tabPanels[tabKey] then
            AP:OpenUI(tabKey)
        else
            mainFrame:Hide()
        end
    else
        AP:OpenUI(tabKey or (mainFrame and mainFrame.activeTab) or "top")
    end
end

---------------------------------------------------------------------------
-- 4. Кнопка у миникарты (AttuneParserMinimapButton) и PrimeHub
---------------------------------------------------------------------------
do
    local mmBtn
    local MINIMAP_RADIUS = 80
    local isDragging = false

    local function UpdateMinimapPos()
        if not mmBtn or not Minimap then return end
        local deg = tonumber(AP:GetSetting("minimapAngle")) or 225
        local rad = math.rad(deg)
        local x = math.cos(rad) * MINIMAP_RADIUS
        local y = math.sin(rad) * MINIMAP_RADIUS
        mmBtn:ClearAllPoints()
        mmBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    local function UpdateMinimapVisibility()
        if not mmBtn then return end
        if AP:GetSetting("showMinimap") ~= false then
            mmBtn:Show()
            UpdateMinimapPos()
        else
            mmBtn:Hide()
        end
    end

    local function UpdateMinimapBadge()
        if not mmBtn then return end
        local ms = AP:GetMilestonesSummary()
        if ms and ms.claimable and ms.claimable > 0 then
            mmBtn.badge:SetText("|cff40ff40+" .. ms.claimable .. "|r")
            mmBtn.badge:Show()
        else
            mmBtn.badge:Hide()
        end
    end

    local function CreateMinimapButton()
        if mmBtn or not Minimap then return mmBtn end
        local b = CreateFrame("Button", "AttuneParserMinimapButton", Minimap)
        b:SetSize(32, 32)
        b:SetFrameStrata("MEDIUM")
        b:SetFrameLevel(8)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        b:SetClampedToScreen(true)

        local icon = b:CreateTexture(nil, "BACKGROUND")
        icon:SetTexture("Interface\\Icons\\INV_Enchant_EssenceCosmicGreater")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER", 0, 0)
        b.icon = icon

        local border = b:CreateTexture(nil, "OVERLAY")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        border:SetSize(52, 52)
        border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

        b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

        b.badge = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.badge:SetPoint("BOTTOM", b, "BOTTOM", 0, -2)
        b.badge:Hide()

        b:SetScript("OnDragStart", function(self)
            isDragging = true
            self:SetScript("OnUpdate", function()
                local mx, my = GetCursorPosition()
                local scale = Minimap:GetEffectiveScale()
                mx, my = mx / scale, my / scale
                local cx, cy = Minimap:GetCenter()
                if cx and cy then
                    local deg = math.deg(math.atan2(my - cy, mx - cx))
                    AP:EnsureSettings().minimapAngle = deg
                    UpdateMinimapPos()
                end
            end)
        end)

        b:SetScript("OnDragStop", function(self)
            isDragging = false
            self:SetScript("OnUpdate", nil)
            AP:Fire("SETTINGS_UPDATED", "minimapAngle", AP:GetSetting("minimapAngle"))
        end)

        b:SetScript("OnClick", function(_, mouseBtn)
            if isDragging then return end
            if mouseBtn == "RightButton" then
                AP:OpenUI("settings")
            elseif IsShiftKeyDown() and type(AP.ToggleEncounterJournal) == "function" then
                AP:ToggleEncounterJournal()
            elseif IsShiftKeyDown() and type(AP.OpenEncounterJournal) == "function" then
                AP:OpenEncounterJournal()
            else
                AP:ToggleUI()
            end
        end)

        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("|cffffd200AttuneParser|r v" .. tostring(AP.VERSION))
            local cat = AP:GetAccountCatalogSummary()
            local ms = AP:GetMilestonesSummary()
            local gift = AP:GetActiveDailyGift(false)
            GameTooltip:AddLine(string.format("Каталог: %d/%d (%d%%) | Вехи: %d",
                cat.doneBase or 0, cat.totalBase or 0, cat.pctBase or 0, ms.done or 0), 0.9, 0.9, 0.9)
            if (ms.claimable or 0) > 0 then
                GameTooltip:AddLine("Доступно наград за вехи: |cff40ff40" .. ms.claimable .. "|r", 1, 1, 1)
            end
            if gift.active then
                GameTooltip:AddLine("Дар недели: |cffa855f7" .. (gift.name or "?") .. "|r (" .. (gift.remText or "?") .. ")", 1, 1, 1)
            end
            local bagsRaw = AP:GetOwnedUpgradeCandidates(nil, true)
            local bagsCount = 0
            local mkMap = AP.MORKEL_ITEMS
            for _, it in ipairs(bagsRaw) do
                local isMk = (AP.IsMorKelItem and AP:IsMorKelItem(it.itemId)) or (mkMap and mkMap[it.itemId])
                if not isMk then bagsCount = bagsCount + 1 end
            end
            if bagsCount > 0 then
                GameTooltip:AddLine("Вещей к поглощению/ковке: |cff40ff40" .. bagsCount .. "|r", 1, 1, 1)
            end
            local talLoaded, talTtpOn, talBridgeOn = false, true, AP:IsTalorianBridgeActive()
            if type(AP.GetTalorianStatus) == "function" then
                talLoaded, talTtpOn, talBridgeOn = AP:GetTalorianStatus()
            else
                talLoaded = (AP._talorianBridge ~= nil) or (type(rawget(_G, "TalorianTP")) == "table")
                talTtpOn = not (type(_G.TalorianTP_DB) == "table" and _G.TalorianTP_DB.enabled == false)
            end
            local mmTalStr = talBridgeOn and "|cff40ff40Подключен|r"
                or ((talLoaded and not talTtpOn) and "|cffffd200Выключен в /ttp|r" or "|cff94a3b8Автономный режим|r")
            GameTooltip:AddLine("Талориан: " .. mmTalStr, 0.85, 0.85, 0.85)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff94a3b8ЛКМ: Открыть/скрыть окно\nПКМ: Настройки\nShift+ЛКМ: Путеводитель по приключениям\nЗажать ЛКМ: Переместить кнопку|r", 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)

        mmBtn = b
        UpdateMinimapVisibility()
        UpdateMinimapBadge()
        return mmBtn
    end

    local function RegisterPrimeHubTile()
        if AP._primeHubReg then return end
        local ph = rawget(_G, "PrimeHub")
        if not ph or type(ph.Register) ~= "function" then return end
        AP._primeHubReg = true
        pcall(ph.Register, ph, {
            id = "attune_parser",
            title = "AttuneParser",
            icon = "Interface\\Icons\\INV_Enchant_EssenceCosmicGreater",
            order = 36,
            status = function()
                if AP:GetSetting("showPrimeHub") == false then return nil end
                local cat = AP:GetAccountCatalogSummary()
                if (cat.totalBase or 0) > 0 then
                    return string.format("Каталог %d%%", cat.pctBase or 0)
                end
                return "Топ и анализ"
            end,
            badge = function()
                if AP:GetSetting("showPrimeHub") == false then return nil end
                local ms = AP:GetMilestonesSummary()
                if ms and (ms.claimable or 0) > 0 then
                    return ms.claimable
                end
                return nil
            end,
            open = function() AP:ToggleUI("top") end,
        })
    end

    local function OnLiveEvent(ev, a1)
        if ev == "SETTINGS_UPDATED" then
            if a1 == "showMinimap" or a1 == "minimapAngle" then
                if a1 == "showMinimap" and AP:GetSetting("showMinimap") ~= false then
                    KeepAttuneMinimapInPrimeHub()
                end
                UpdateMinimapVisibility()
            elseif a1 == "showPrimeHub" then
                local ph = rawget(_G, "PrimeHub")
                if ph and type(ph.Refresh) == "function" then pcall(ph.Refresh, ph) end
            elseif type(a1) == "string" and (a1:sub(1, 3) == "blk" or a1 == "showValdrisBar" or a1 == "showHeaderLinks") then
                if mainFrame and mainFrame:IsShown() then AP:RefreshUI() end
                if AP._RefreshOnboardingWizard then AP._RefreshOnboardingWizard() end
                return
            end
        end
        UpdateMinimapBadge()
        if AP._RefreshOnboardingWizard then AP._RefreshOnboardingWizard() end
        if mainFrame and mainFrame:IsShown() then
            AP.After(0.08, function() AP:RefreshUI() end, "ap_ui_debounced_refresh")
        end
    end

    AP:RegisterCallback("ATTUNE_UPDATED", OnLiveEvent)
    AP:RegisterCallback("ZONE_UPDATED", OnLiveEvent)
    AP:RegisterCallback("FORGE_UPDATED", OnLiveEvent)
    AP:RegisterCallback("MILESTONES_UPDATED", OnLiveEvent)
    AP:RegisterCallback("DAILY_GIFT_UPDATED", OnLiveEvent)
    AP:RegisterCallback("PETLOOT_UPDATED", OnLiveEvent)
    AP:RegisterCallback("PETLOOT_JUNK_UPDATED", OnLiveEvent)
    AP:RegisterCallback("BAGUM_UPDATED", OnLiveEvent)
    AP:RegisterCallback("AUTOSWAP_UPDATED", OnLiveEvent)
    AP:RegisterCallback("PARAGON_UPDATED", OnLiveEvent)
    AP:RegisterCallback("TALORIAN_BRIDGE_UPDATED", OnLiveEvent)
    AP:RegisterCallback("SETTINGS_UPDATED", OnLiveEvent)
    AP:RegisterCallback("SERVER_SYNC_UPDATED", OnLiveEvent)

    local uiEv = CreateFrame("Frame")
    uiEv:RegisterEvent("PLAYER_LOGIN")
    uiEv:RegisterEvent("ADDON_LOADED")
    uiEv:SetScript("OnEvent", function(_, event, a1)
        if event == "PLAYER_LOGIN" then
            AP:EnsureSettings()
            CreateMinimapButton()
            RegisterPrimeHubTile()
        elseif event == "ADDON_LOADED" and a1 == "PrimeHub" then
            RegisterPrimeHubTile()
        end
    end)
end
