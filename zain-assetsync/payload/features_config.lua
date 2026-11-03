-- إعدادات تفعيلات "نسخة زين" — كل المفاتيح مستخرجة من بايتكود الهاك الأصلي
-- المصدر: luasource.bin (Delta Force Mobile Lua 5.3)

return {
    sections = {
        {
            id = "aim", icon = "🎯", name = "الإيم أسيست",
            items = {
                { key = "aim_enabled",        type = "toggle", name = "تفعيل الإيم",      desc = "تشغيل الإيم أسيست المعدل", default = false },
                { key = "custom_aim_speed",   type = "slider", name = "قوة الإيم",        desc = "سرعة التصويب التلقائي",   min = 1, max = 100, default = 50 },
                { key = "custom_aim_range",   type = "slider", name = "مدى الإيم",        desc = "نطاق التقاط الهدف",       min = 10, max = 500, default = 150 },
                { key = "custom_aim_distance",type = "slider", name = "مسافة الإيم",      desc = "أقصى مسافة للتصويب",      min = 10, max = 1000, default = 300 },
                { key = "aim_fov_reset",      type = "button", name = "إعادة ضبط FOV",  desc = "RESET_FOV slider=",       action = "reset_fov" },
            },
        },
        {
            id = "recoil", icon = "🔫", name = "الاستقرار والارتداد",
            items = {
                { key = "no_recoil",               type = "toggle", name = "إلغاء الارتداد",     desc = "تعطيل WeaponRecoilTable", default = false },
                { key = "recoil_pitch",          type = "slider", name = "ارتداد رأسي",         desc = "RecoilShakePitch",        min = 0, max = 100, default = 0 },
                { key = "recoil_yaw",            type = "slider", name = "ارتداد أفقي",         desc = "RecoilShakeYaw",          min = 0, max = 100, default = 0 },
                { key = "recoil_spring",         type = "toggle", name = "إلغاء النبضة",        desc = "EnableSpringGunKick",     default = true },
            },
        },
        {
            id = "esp", icon = "👁", name = "الرؤية ESP",
            items = {
                { key = "esp_enabled",       type = "toggle", name = "تفعيل ESP",           desc = "LDV_ESP_VISIBILITY",      default = false },
                { key = "esp_lines",       type = "toggle", name = "خطوط للأعداء",        desc = "خط منك للهدف",            default = true },
                { key = "esp_los_check",   type = "toggle", name = "فحص الرؤية",          desc = "LineOfSightTo — هل الهدف ظاهر", default = true },
                { key = "esp_traces",      type = "slider", name = "دقة الفحص",           desc = "esp_visibility_traces",   min = 1, max = 32, default = 8 },
                { key = "loot_color",      type = "color",  name = "لون الصناديق",        desc = "loot_color",              default = {r=1,g=0.8,b=0} },
            },
        },
        {
            id = "skins", icon = "🎨", name = "السكنات",
            items = {
                { key = "skins_unlock",    type = "toggle", name = "فتح كل السكنات",      desc = "ASGA8_UNLOCK_SKIN",       default = false },
                { key = "skins_firearm",   type = "toggle", name = "سكنات الأسلحة",       desc = "_allFirearmSkins",        default = true },
                { key = "skins_melee",     type = "toggle", name = "سكنات السكاكين",      desc = "_allMeleeSkins",        default = true },
                { key = "skins_vehicle",   type = "toggle", name = "سكنات المركبات",      desc = "_allVehicleSkins",      default = true },
                { key = "skins_hero",      type = "toggle", name = "أزياء الشخصيات",      desc = "_unlockedFashionIds",     default = true },
            },
        },
        {
            id = "stealth", icon = "🛡️", name = "التخفي ضد الباند",
            items = {
                { key = "gradual",    type = "toggle", name = "تفعيل تدريجي",     desc = "تأخير 120 ثانية بعد الدخول", default = true },
                { key = "jitter",     type = "toggle", name = "فواصل عشوائية",    desc = "تمويه نمط التطبيق",          default = true },
                { key = "panic_hint", type = "button", name = "إخفاء طارئ",       desc = "٤ أصابع = إيقاف فوري",       action = "panic" },
            },
        },
        {
            id = "misc", icon = "⚙️", name = "عام",
            items = {
                { key = "menu_pin",     type = "toggle", name = "قفل القائمة برمز",  desc = "يطلب رمز قبل الفتح",  default = false },
                { key = "cfg_export",   type = "button", name = "تصدير الإعدادات",    desc = "نسخة احتياطية JSON",   action = "export_cfg" },
                { key = "cfg_import",   type = "button", name = "استيراد الإعدادات",  desc = "استرجاع نسخة",          action = "import_cfg" },
                { key = "cfg_reset",    type = "button", name = "إعادة الضبط",        desc = "رجوع للافتراضي",       action = "reset_cfg" },
            },
        },
    },
}
