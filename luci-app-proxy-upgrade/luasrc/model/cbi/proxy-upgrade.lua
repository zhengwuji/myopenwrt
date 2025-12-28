m = Map("proxy-upgrade", translate("代理升级"), translate("通过局域网代理服务器升级OpenWrt系统"))

s = m:section(TypedSection, "proxy", "")
s.anonymous = true

o = s:option(ListValue, "enabled", translate("启用代理"))
o:value("1", translate("启用"))
o:value("0", translate("禁用"))
o.default = "0"

o = s:option(Value, "proxy_ip", translate("代理服务器IP"))
o.datatype = "ipaddr"
o.rmempty = false

-- Auto-discovery logic
local f = io.open("/proc/net/arp", "r")
local neighbors = {}
if f then
    f:read("*line") -- skip header
    for line in f:lines() do
        local ip, hw, flags, mac, mask, dev = line:match("(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
        if ip and mac and dev == "br-lan" then
            -- Use IP as key to avoid MAC address conflicts (same device with multiple IPs)
            neighbors[ip] = {ip = ip, mac = mac}
        end
    end
    f:close()
end

-- Try to get device names from DHCP leases (optional, for display only)
f = io.open("/tmp/dhcp.leases", "r")
if f then
    for line in f:lines() do
        local ts, mac, ip, name = line:match("(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
        if ip and neighbors[ip] then
            neighbors[ip].name = name
        end
    end
    f:close()
end

-- Display all devices from ARP table
for ip, info in pairs(neighbors) do
    local label = info.ip
    if info.name and info.name ~= "*" then
        label = label .. " (" .. info.name .. ")"
    else
        label = label .. " (" .. info.mac .. ")"
    end
    o:value(info.ip, label)
end

o = s:option(Value, "proxy_port", translate("代理端口"))
o.datatype = "port"

o = s:option(ListValue, "proxy_type", translate("代理类型"))
o:value("http", "HTTP")
o:value("socks5", "SOCKS5")
o.default = "http"

o = s:option(Flag, "global_proxy", translate("出口UI设置"), translate("打勾代表，所有设备都会按照选择的IP，作为出口流量，也就是全局代理所有网路，使用的是选中的ip,确保网路软件配置不要冲突能正常使用，被选中的IP，不受影响"))
o.default = "0"

t = s:option(DummyValue, "_buttons")
t.template = "proxy-upgrade/status"

function m.on_after_commit(self)
    luci.sys.call("/usr/lib/proxy-upgrade/set-global-proxy.sh > /dev/null 2>&1 &")
end

return m
