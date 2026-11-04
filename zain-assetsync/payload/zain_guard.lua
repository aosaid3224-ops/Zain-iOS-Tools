--[[ زين جارد v2 — آمن على الـ Sandbox (يقرأ داخل الحاوية فقط) ]]
local Guard = {}
local TOKEN = (os.getenv("HOME") or "") .. "/Documents/.zain_token"
local MAX_AGE = 30*24*3600
local BAKED_ID = "179375585118303"   -- معرّف الجهاز المخبوز وقت التركيب

local function readf(p)
    local f = io.open(p,"r"); if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end

function Guard.check()
    local t = readf(TOKEN)
    if not t then return false end
    local uuid, ts = t:match("^(%S+)|(%d+)$")
    if not uuid or not ts then return false end
    if uuid ~= BAKED_ID then return false end        -- نُقل لجهاز آخر
    local now = os.time()
    local age = tonumber(ts) or 0
    if now - age > MAX_AGE or age > now + 3600 then return false end
    return true
end
return Guard
