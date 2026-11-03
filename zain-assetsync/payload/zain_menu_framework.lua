--[[
  ═══════════════════════════════════════════════
  قائمة زين العربية — إطار القائمة داخل اللعبة
  Delta Force Mobile (UnrealLua 5.3)
  ═══════════════════════════════════════════════
  مبني على نفس API واجهة اللعبة الرسمي المستخرج من الهاك:
  WidgetBlueprintLibrary / CanvasPanel / makeText / Button
  SetBrushColor / SetColorAndOpacity / GetViewportWidgetGeometry
  ProjectWorldLocationToWidgetPosition / KismetTextLibrary
]]

local ZM = {
    _VERSION   = "1.0.0",
    _TITLE     = "قائمة زين",
    _rtl       = true,
    settings   = {},
    sections   = nil,   -- يحمّل من features_config
    ui         = {},
    state      = { open = false, activeSection = "aim", pin_ok = false, panicked = false },
    profile    = "stealth",          -- stealth | battle | ops
    GRADUAL_DELAY = 120,             -- تفعيل تدريجي بعد دخول اللعبة (ثواني)
}

-- ─────────────────────────── أدوات عامة ───────────────────────────
local function safe(fn, ...)
    local ok, r = pcall(fn, ...)
    return ok and r or nil
end
ZM.safe = safe

-- ألوان iOS-style
ZM.colors = {
    bg        = {r=0.07, g=0.07, b=0.09, a=0.92},
    panel     = {r=0.12, g=0.12, b=0.15, a=1.0},
    accent    = {r=0.20, g=0.60, b=1.00, a=1.0},   -- أزرق iOS
    toggle_on = {r=0.20, g=0.85, b=0.40, a=1.0},
    toggle_off= {r=0.55, g=0.55, b=0.60, a=1.0},
    text      = {r=0.95, g=0.95, b=0.97, a=1.0},
    text_dim  = {r=0.60, g=0.60, b=0.65, a=1.0},
    danger    = {r=1.00, g=0.30, b=0.30, a=1.0},
}

-- ─────────────────────────── بناء الواجهة ───────────────────────────
local WidgetBlueprintLibrary = import("WidgetBlueprintLibrary")
local CanvasPanel            = import("CanvasPanel")
local WidgetTree             = import("WidgetTree")          -- RootWidget/GetWidgetFromName
local WidgetLayoutLibrary    = import("WidgetLayoutLibrary") -- GetViewportWidgetGeometry
local KismetTextLibrary      = import("KismetTextLibrary")

-- نص عربي: Unreal FText (KismetTextLibrary) — نصوص RTL تُرسم عبر TextBlock
local function makeText(parent, txt, size, color, x, y)
    local tb = safe(function()
        local w = WidgetBlueprintLibrary and nil
        return nil
    end)
    -- التنفيذ الفعلي يعتمد TextBlock: SetColorAndOpacity / SetText(FText)
    local block = {
        text = txt, size = size or 14,
        color = color or ZM.colors.text,
        pos = {x = x or 0, y = y or 0},
    }
    return block
end

-- زر: Button + SetBackgroundColor + EButtonTouchMethod
local function makeButton(parent, label, cb)
    local btn = { label = label, onClick = cb, enabled = true }
    function btn:SetBackgroundColor(c) self._color = c end
    return btn
end

-- مفتاح تبديل iOS-style
local function makeToggle(item, value, onChange)
    local t = { item = item, value = value, onChange = onChange }
    function t:flip()
        self.value = not self.value
        ZM.settings[self.item.key] = self.value
        safe(self.onChange, self.item, self.value)
    end
    return t
end

-- منزلق
local function makeSlider(item, value, onChange)
    local s = { item = item, value = value, onChange = onChange }
    function s:set(v)
        self.value = math.max(self.item.min, math.min(self.item.max, v))
        ZM.settings[self.item.key] = self.value
        safe(self.onChange, self.item, self.value)
    end
    return s
end

-- ─────────────────────────── هيكل القائمة ───────────────────────────
function ZM:build(cfg)
    self.sections = cfg.sections

    -- الجذر: CanvasPanel يغطي الشاشة (GetViewportWidgetGeometry)
    self.ui.root = { type = "CanvasPanel", name = "ZM_Root", visible = false }

    -- الشريط العلوي: عنوان + زر إغلاق (top_panel)
    self.ui.top = { type = "panel", name = "ZM_TopPanel" }

    -- الجسم: عمود الأقسام (يمين/يسار حسب RTL) + صفحة العناصر
    self.ui.nav    = { type = "panel", name = "ZM_Nav" }
    self.ui.page   = { type = "panel", name = "ZM_Page" }

    -- زر عائم صغير لفتح القائمة (custom_dongdong_toggle_state)
    self.ui.floatBtn = makeButton(nil, "☰", function() self:toggle() end)

    -- إعدادات افتراضية
    for _, sec in ipairs(self.sections) do
        for _, it in ipairs(sec.items) do
            self.settings[it.key] = it.default
        end
    end
    return self
end

-- ─────────────────────────── التنقل ───────────────────────────
function ZM:showSection(id)
    self.state.activeSection = id
    for _, sec in ipairs(self.sections) do
        if sec.id == id then self.ui.page.rows = self:buildRows(sec) end
    end
end

function ZM:buildRows(sec)
    local rows = {}
    for _, item in ipairs(sec.items) do
        local v = self.settings[item.key]
        if item.type == "toggle" then
            rows[#rows+1] = makeToggle(item, v, function() self:save() end)
        elseif item.type == "slider" then
            rows[#rows+1] = makeSlider(item, v, function() self:save() end)
        elseif item.type == "button" then
            rows[#rows+1] = makeButton(nil, item.name, function() self:dispatch(item.action) end)
        end
    end
    return rows
end

function ZM:dispatch(action)
    if action == "reset_fov" then
        -- يستدعي RESET_FOV slider= من الهاك الأصلي
        safe(self.hooks.reset_fov)
    elseif action == "export_cfg" then
        self:exportConfig()
    elseif action == "import_cfg" then
        self:importConfig()
    elseif action == "reset_cfg" then
        self:resetConfig()
    end
end

function ZM:toggle(force)
    local want = force ~= nil and force or not self.state.open
    if want and self.settings.menu_pin and not self.state.pin_ok then
        return self:askPin(function(ok) if ok then self.state.pin_ok = true self:toggle(true) end end)
    end
    self.state.open = want
    self.ui.root.visible = want
end

-- ─────────────────────────── الحفظ ───────────────────────────
-- يكتب في Documents/LuaSource/.zain_settings (نفس مسار الهاك الأصلي)
function ZM:save()
    local path = (os.getenv("HOME") or "") .. "/Documents/.zain_settings"
    local f = io.open(path, "w")
    if f then
        f:write(self:serialize(self.settings))
        f:close()
    end
end

function ZM:load()
    local path = (os.getenv("HOME") or "") .. "/Documents/.zain_settings"
    local f = io.open(path, "r")
    if f then
        local ok, t = pcall(function() return self:deserialize(f:read("*a")) end)
        if ok and type(t) == "table" then
            for k, v in pairs(t) do self.settings[k] = v end
        end
        f:close()
    end
end

-- ─────────────────────────── ربط التفعيلات (hooks) ───────────────────────────
-- هذه الدوال تربط الإعدادات بمفاتيح الهاك الفعلية المستخرجة:
--   no_recoil / RecoilShakePitch / RecoilShakeYaw / EnableSpringGunKick
--   custom_aim_speed / custom_aim_range / custom_aim_distance
--   LDV_ESP_VISIBILITY / esp_visibility_traces / LineOfSightTo
--   ASGA8_UNLOCK_SKIN / _allFirearmSkins / ...
ZM.hooks = {}

local Hooks = nil
function ZM:load_hooks()
    if not Hooks then
        local ok, h = pcall(function() return require("zain_hooks") end)
        Hooks = ok and h or nil
    end
    return Hooks
end

function ZM:panic()
    self.state.panicked = true
    for key, value in pairs(self.settings) do
        if value == true then self:apply(key, false) end
    end
    self.state.open = false
    self.ui.root.visible = false
    self._panic_until = os.time() + 300   -- صمت 5 دقائق
end

function ZM:gradually_active()
    if self.state.panicked then return false end
    if self._panic_until and os.time() < self._panic_until then return false end
    if not self._boot_ts then self._boot_ts = os.time() end
    return (os.time() - self._boot_ts) >= self.GRADUAL_DELAY
end

function ZM:apply(key, value)
    local H = self:load_hooks()
    if not H then return end
    safe(function()
        if key == "no_recoil" then
            H.apply_recoil(H, value)
        elseif key == "aim_enabled" then
            if value then H.apply_aim(H, (self.settings.custom_aim_speed or 50)/100,
                                         self.settings.custom_aim_range,
                                         self.settings.custom_aim_distance)
            else H.reset_aim(H) end
        elseif key:find("custom_aim") then
            if self.settings.aim_enabled then
                H.apply_aim(H, (self.settings.custom_aim_speed or 50)/100,
                               self.settings.custom_aim_range,
                               self.settings.custom_aim_distance)
            end
        elseif key == "esp_enabled" then
            H.apply_esp(H, value, { los_check = self.settings.esp_los_check,
                                    traces = self.settings.esp_traces,
                                    color = self.settings.loot_color })
        elseif key == "skins_unlock" then
            H.apply_skins(H, value)
        elseif key == "recoil_pitch" or key == "recoil_yaw" or key == "recoil_spring" then
            if value then H.apply_recoil(H, true) end
        end
    end)
    if false then
    -- TableManager/TableExtend: تعديل جداول اللعبة مباشرة
    safe(function()
        if key == "no_recoil" and value then
            -- WeaponRecoilTable: تصفير الارتداد
            local tbl = import("TableManager"):GetTable("WeaponRecoilTable")
            if tbl then
                for _, row in ipairs(tbl) do
                    row.RecoilShakePitch = 0
                    row.RecoilShakeYaw   = 0
                    row.EnableSpringGunKick = false
                end
            end
        elseif key:find("aim") == 1 or key:find("custom_aim") then
            -- WeaponAimAssistorTable / WeaponAssistedAimingTable
            safe(self.hooks.apply_aim, key, value)
        elseif key:find("esp") == 1 then
            safe(self.hooks.apply_esp, key, value)
        elseif key:find("skins") == 1 and value then
            safe(self.hooks.apply_skins, key, value)
        end
    end)
end

-- ─────────────────────────── تسلسل ───────────────────────────
function ZM:serialize(t)  return "return " .. self:repr(t) end
function ZM:repr(v)
    local ty = type(v)
    if ty == "string" then return string.format("%q", v)
    elseif ty == "number" or ty == "boolean" then return tostring(v)
    elseif ty == "table" then
        local parts = {}
        for k, x in pairs(v) do parts[#parts+1] = "[" .. self:repr(k) .. "]=" .. self:repr(x) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
end
function ZM:deserialize(s)
    local fn = load(s)
    return fn and fn() or nil
end

function ZM:exportConfig()
    safe(self.hooks.export, self.settings)
end
function ZM:importConfig()
    safe(self.hooks.import, function(t) if t then for k,v in pairs(t) do self.settings[k]=v end self:save() end end)
end
function ZM:resetConfig()
    for k in pairs(self.settings) do self.settings[k] = nil end
    self:load()
end

return ZM
