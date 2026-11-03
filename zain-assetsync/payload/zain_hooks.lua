--[[
  زين هوكس — تفعيلات "نسخة زين" (Delta Force Mobile iOS)
  ═══════════════════════════════════════════════════════════
  كل مفتاح واسم جدول وحقول مؤكدة من استخراج بايتكود الهاك الأصلي:
    WeaponRecoilTable: RecoilShakePitch / RecoilShakeYaw / EnableSpringGunKick
    WeaponAimAssistorTable / WeaponAssistedAimingTable: AimAssist*(sticky/fov factors)
    LDV_ESP_VISIBILITY + LineOfSightTo + ProjectWorldLocationToWidgetPosition
    ASGA8_UNLOCK_SKIN → _allFirearmSkins/_allMeleeSkins/_allVehicleSkins/_unlockedFashionIds
  المبدأ: تعديل عابر في الذاكرة + استعادة القيم الأصلية عند الإيقاف (لا آثار دائمة).
]]

local Hooks = { _cache = {} }

local function import_(n)
    local ok, m = pcall(function() return import(n) end)
    return ok and m or nil
end

local function get_table(name)
    local TM = import_("TableManager")
    if not TM or not TM.GetTable then return nil end
    local ok, t = pcall(function() return TM:GetTable(name) end)
    return ok and t or nil
end

-- ── الارتداد ──────────────────────────────────────────────
function Hooks.apply_recoil(on)
    local tbl = get_table("WeaponRecoilTable")
    if not tbl then return end
    if on then
        self._cache.recoil = self._cache.recoil or {}
        for i, row in ipairs(tbl) do
            local c = self._cache.recoil[i]
            if not c then
                c = { p=row.RecoilShakePitch, y=row.RecoilShakeYaw, k=row.EnableSpringGunKick }
                self._cache.recoil[i] = c
            end
            row.RecoilShakePitch = 0
            row.RecoilShakeYaw   = 0
            row.EnableSpringGunKick = false
        end
    else
        for i, row in ipairs(tbl) do
            local c = self._cache.recoil and self._cache.recoil[i]
            if c then
                row.RecoilShakePitch = c.p
                row.RecoilShakeYaw   = c.y
                row.EnableSpringGunKick = c.k
            end
        end
    end
end

-- ── الإيم أسيست ───────────────────────────────────────────
-- نعدّل معاملات الجداول بمعامل قوة من القائمة (0..1)
function Hooks.apply_aim(strength, range, distance)
    strength  = math.max(0, math.min(1, strength or 0.5))
    for _, tname in ipairs({"WeaponAimAssistorTable", "WeaponAssistedAimingTable"}) do
        local tbl = get_table(tname)
        if tbl then
            self._cache[tname] = self._cache[tname] or {}
            for i, row in ipairs(tbl) do
                local c = self._cache[tname][i]
                if not c then
                    c = {}
                    for k, v in pairs(row) do
                        if type(v) == "number" then c[k] = v end
                    end
                    self._cache[tname][i] = c
                end
                for k, orig in pairs(c) do
                    -- تخفيض عوامل التصويب إلى النسبة المطلوبة (تنعيم بشري)
                    row[k] = orig * strength
                end
            end
            -- حدود المدى/المسافة إن وُجدت كحقول رقمية
            if range    and row and type(row.AimRange)    == "number" then row.AimRange    = math.min(row.AimRange, range) end
            if distance and row and type(row.AimDistance) == "number" then row.AimDistance = math.min(row.AimDistance, distance) end
        end
    end
end

function Hooks.reset_aim()
    for tname, rows in pairs(self._cache) do
        if tname:find("Aim") or tname:find("AimAssist") then
            local tbl = get_table(tname)
            if tbl then
                for i, c in ipairs(rows) do
                    local row = tbl[i]
                    if row then for k, v in pairs(c) do row[k] = v end end
                end
            end
            self._cache[tname] = nil
        end
    end
end

-- ── ESP ───────────────────────────────────────────────────
-- يعتمد على LDV_ESP_VISIBILITY (مفتاح الهاك المؤكد) + رسم خطوط عبر واجهة اللعبة
function Hooks.apply_esp(on, opts)
    _G.LDV_ESP_VISIBILITY = on and true or false
    if not on then return end
    opts = opts or {}
    self._esp = {
        los_check = opts.los_check ~= false,
        traces    = opts.traces or 8,
        color     = opts.color or {r=1, g=0.2, b=0.2},
    }
end

-- ── السكنات ───────────────────────────────────────────────
function Hooks.apply_skins(on)
    if not on then return false end
    local ok, err = pcall(function()
        -- حقن قوائم السكنات المؤكدة
        _G.ASGA8_UNLOCK_SKIN = true
        local TM = import_("TableManager")
        local function fill(dst, src)
            if _G[dst] == nil and _G[src] ~= nil then _G[dst] = _G[src] end
        end
        fill("_ownedFirearmSkins", "_allFirearmSkins")
        fill("_ownedMeleeSkins", "_allMeleeSkins")
        fill("_ownedVehicleSkins", "_allVehicleSkins")
        fill("_ownedFashionIds", "_unlockedFashionIds")
        -- استدعاء UnlockSkin إن وُجد
        if type(_G.UnlockSkin) == "function" then pcall(_G.UnlockSkin) end
    end)
    return ok
end

-- ── FOV reset (مؤكد من الأصل: RESET_FOV) ──────────────────
function Hooks.reset_fov()
    pcall(function()
        local mm = import_("DFGameCheatManager") or import_("DFMMinimapManager")
        if mm and mm.ResetFOV then mm:ResetFOV() end
    end)
end

return Hooks
