--[[ زين تريقر v2 — كشف لمس صحيح + زر عائم + إظهار تلقائي مرة ]]
local Trigger = {
    state=false, lastToggle=0, game_ready=false,
    DEBOUNCE=0.6, boot=nil, ready_at=nil, shown_once=false,
}
local function lib()
    local ok,m = pcall(function() return import("KismetInputLibrary") end)
    return ok and m or nil
end
local function finger_pressed(idx)
    local L = lib(); if not L or not L.GetInputTouchState then return false end
    -- GetInputTouchState ترجع قيمًا متعددة: الأولى bool = مضغوط أم لا
    local ok, pressed = pcall(function() return L.GetInputTouchState(idx) end)
    return ok and pressed == true
end
local function count_fingers()
    local n = 0
    for i = 0, 4 do if finger_pressed(i) then n = n + 1 end end
    return n
end
-- زر عائم: محاولة إنشاء واجهة (قد تنجح أو لا حسب تواقيع UMG)
local function try_float_button(ZM)
    pcall(function()
        local WBL = import("WidgetBlueprintLibrary")
        local btnClass = import("Button")
        if WBL and btnClass and WBL.Create then
            local btn = WBL:Create(btnClass, nil)
            if btn and btn.AddToViewport then btn:AddToViewport(999) end
        end
    end)
end
function Trigger.init(ZM)
    Trigger.boot = os.clock()
    local ok, LTC = pcall(function() return import("LuaTickController") end)
    if not (ok and LTC and LTC.RegisterTick) then return end
    Trigger.enabled = true
    try_float_button(ZM)
    LTC:RegisterTick("zain_trigger", function(dt)
        if not Trigger.game_ready then
            if os.clock() - Trigger.boot > 2 then
                Trigger.game_ready = true
                Trigger.ready_at = os.clock()
            else return end
        end
        -- إظهار تلقائي مرة واحدة (دليل عمل واضح)
        if not Trigger.shown_once and (os.clock() - Trigger.ready_at) > 3 then
            Trigger.shown_once = true
            Trigger.state = true
            ZM:toggle(true)
        end
        local n = count_fingers()
        local now = os.clock()
        if n >= 3 and (now - Trigger.lastToggle) > Trigger.DEBOUNCE then
            Trigger.lastToggle = now
            if n >= 4 then
                ZM:panic(); Trigger.state = false
            else
                Trigger.state = not Trigger.state
                ZM:toggle(Trigger.state)
            end
        end
    end)
    -- تطبيق متقطع بفواصل عشوائية (jitter)
    local acc, thr = 0, 0.25
    LTC:RegisterTick("zain_apply", function(dt)
        acc = acc + dt
        if acc >= thr then
            acc = 0; thr = 0.18 + math.random() * 0.16
            if ZM.gradually_active and ZM:gradually_active() then
                for k, v in pairs(ZM.settings) do
                    if v ~= ZM._last_applied[k] then
                        ZM:apply(k, v); ZM._last_applied[k] = v
                    end
                end
            end
        end
    end)
end
return Trigger
