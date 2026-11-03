--[[ زين جارد — نسخة DEB المُحكّمة (ربط جهاز حقيقي) ]]
local Guard = {}
local TOKEN = (os.getenv("HOME") or "") .. "/Documents/.zain_token"
local SYSID = "/var/mobile/.zsys/id"
local MAX_AGE = 30*24*3600

local function readf(p)
    local f = io.open(p,"r"); if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end

function Guard.check()
    local t = readf(TOKEN)
    if not t then return false end
    local uuid, ts = t:match("^(%S+)|(%d+)$")
    if not uuid or not ts then return false end
    local now = os.time()
    local age = tonumber(ts) or 0
    if now - age > MAX_AGE or age > now + 3600 then return false end
    local sid = readf(SYSID)                      -- root-written, 444
    if not sid or sid:gsub("%s","") ~= uuid then return false end  -- نقل لجهاز آخر = فشل
    return true
end
function Guard.integrity() return true end
return Guard
