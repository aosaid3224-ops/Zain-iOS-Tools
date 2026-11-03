--[[ زين تريقر + إخفاء طارئ (4 أصابع) ]]
local Trigger = {
    state=false, lastToggle=0, game_ready=false,
    DEBOUNCE_MS=400, TITLE_WAIT_S=2.0, boot_time=nil,
    PANIC_FINGERS=4,
}
function Trigger.init(ZM)
    Trigger.boot_time = os.clock()
    local ok, LTC = pcall(function() return import("LuaTickController") end)
    if not (ok and LTC) then return end
    Trigger.enabled = true
    LTC:RegisterTick("zain_trigger", function(dt)
        if not Trigger.game_ready then
            if os.clock()-Trigger.boot_time > Trigger.TITLE_WAIT_S then Trigger.game_ready=true
            else return end
        end
        local t = Trigger.readTouch()
        local now = os.clock()
        if t and (now-Trigger.lastToggle)*1000 > Trigger.DEBOUNCE_MS then
            Trigger.lastToggle = now
            if t.fingers >= Trigger.PANIC_FINGERS then
                ZM:panic()                       -- إخفاء طارئ فوري
                return
            end
            Trigger.state = not Trigger.state
            ZM.state.custom_dongdong_toggle_state = Trigger.state
            ZM:toggle(Trigger.state)
        end
    end)
    -- jitter: تطبيق متقطع بفواصل عشوائية 0.18-0.34 ث (أقل بصمة)
    local acc, thresh = 0, 0.25
    LTC:RegisterTick("zain_apply", function(dt)
        acc = acc + dt
        if acc >= thresh then
            acc = 0
            thresh = 0.18 + math.random()*0.16
            if ZM:gradually_active() then
                for key, value in pairs(ZM.settings) do
                    if value ~= ZM._last_applied[key] then
                        ZM:apply(key, value)
                        ZM._last_applied[key] = value
                    end
                end
            end
        end
    end)
end
function Trigger.readTouch()
    local ok, st = pcall(function()
        local lib = import("KismetInputLibrary")
        return lib and lib.GetInputTouchState and lib.GetInputTouchState() or nil
    end)
    if not ok or not st then return nil end
    local n = st.TouchCount or st.touchCount or 0
    if n >= 3 then return { fingers = n } end
    return nil
end
return Trigger
