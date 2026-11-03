--[[
  زين لودر — نقطة الدخول
  يعمل بنفس آلية الهاك الأصلي:
    1) يكتب ملفاته في Documents/LuaSource + ../LuaSource
    2) يسجل تيك عبر LuaTickController:RegisterTick
    3) يحمّل الحارس ثم القائمة العربية
]]

local HOME = os.getenv("HOME") or ""

local function file_exists(p)
    local f = io.open(p, "r")
    if f then f:close() return true end
    return false
end

local function write_file(p, content)
    local f, err = io.open(p, "w")
    if not f then return false, err end
    f:write(content)
    f:close()
    return true
end

-- مسارات الحقن (مستخرجة من الهاك الأصلي)
local PATHS = {
    HOME .. "/Documents/LuaSource/",
    HOME .. "/Documents/../LuaSource/",
    "DeltaForce/Saved/LuaSource/",
    "Saved/LuaSource/",
}

local FILES = {
    ["zain_menu_framework.lua"] = ZM_MENU_SRC,
    ["features_config.lua"]    = ZM_CFG_SRC,
    ["zain_guard.lua"]         = ZM_GUARD_SRC,
    ["zain_trigger.lua"]       = ZM_TRIGGER_SRC,
}

local ok_any = false
for _, dir in ipairs(PATHS) do
    for name, content in pairs(FILES) do
        if write_file(dir .. name, content) then ok_any = true end
    end
end

-- تشغيل من المسار المتاح
local function try_require(path)
    local ok, mod = pcall(require, path)
    return ok and mod or nil
end

local guard = try_require("zain_guard")
if guard and not guard.check() then
    -- فشل التحقق: لا نعرض شيئًا (صامت — نموذج الحماية الجديد)
    return
end

local cfg    = try_require("features_config")
local ZM     = try_require("zain_menu_framework")
if not (cfg and ZM) then return end

ZM:build(cfg)
ZM:load()

-- ربط التيك عبر LuaTickController (الآلية الرسمية)
local okTick, LuaTickController = pcall(function()
    return import("LuaTickController")
end)
if okTick and LuaTickController then
    -- LateUpdate: تحديث الواجهة كل إطار
    LuaTickController:RegisterTick("zain_menu", function(dt)
        if ZM.state.open then
            ZM:tick(dt)
        end
    end)
end

-- تشغيل خفي للتفعيلات عند فتح اللعبة
for key, value in pairs(ZM.settings) do
    ZM:apply(key, value)
end

-- آلية الفتح (مستخرجة من الأصل): تيك LateUpdate + بوابة الجاهزية + إيماءة لمس
local Trigger = try_require("zain_trigger")
if Trigger then
    Trigger.init(ZM)
    -- تطبيق على فترات (IntervalTime) بدل كل إطار — أقل بصمة
    local applyTick = Trigger.applyInterval(ZM, 0.25)
    local okTick, LuaTickController2 = pcall(function() return import("LuaTickController") end)
    if okTick and LuaTickController2 then
        LuaTickController2:RegisterTick("zain_apply", applyTick)
    end
end

return ZM
