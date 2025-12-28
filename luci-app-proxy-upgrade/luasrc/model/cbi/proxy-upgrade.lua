m = Map("proxy-upgrade", translate("代理升级"), translate("<b>插件作用：</b>通过局域网内的其他设备（如电脑、手机）作为代理服务器，帮助OpenWrt系统进行更新或安装软件包。<br/>适用于OpenWrt本身无法访问外网，但局域网内有其他设备可以访问的场景。"))

s = m:section(TypedSection, "proxy", "")
s.anonymous = true

-- Enabled
o = s:option(ListValue, "enabled", translate("启用代理"))
o:value("1", translate("启用"))
o:value("0", translate("禁用"))
o.default = "0"
o.description = translate("开启或关闭此代理功能。")

-- Proxy IP
o = s:option(Value, "proxy_ip", translate("代理服务器IP"))
o.datatype = "ipaddr"
o.rmempty = false
o.description = translate("选择局域网内运行代理软件（如Clash, v2ray）的设备IP。<br/>系统会自动扫描并列出局域网内的活跃设备。")

-- Auto-discovery logic
local f = io.open("/proc/net/arp", "r")
local neighbors = {}
if f then
    f:read("*line") -- skip header
    for line in f:lines() do
        local ip, hw, flags, mac, mask, dev = line:match("(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
        if ip and mac and dev == "br-lan" then
            neighbors[ip] = {ip = ip, mac = mac}
        end
    end
    f:close()
end

-- Try to get device names from DHCP leases
f = io.open("/tmp/dhcp.leases", "r")
if f then
    for line in f:lines() do
        local ts, mac, ip, name = line:match("(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
        if ip and neighbors[ip] then
            neighbors[ip].dhcp_name = name
        end
    end
    f:close()
end

-- Try to get hostnames from /etc/hosts
f = io.open("/etc/hosts", "r")
if f then
    for line in f:lines() do
        local ip, hostname = line:match("^(%S+)%s+(%S+)")
        if ip and hostname and neighbors[ip] then
            neighbors[ip].hostname = hostname
        end
    end
    f:close()
end

-- MAC OUI database for device identification
local function identify_device(mac)
    local oui = mac:sub(1, 8):upper()
    
    local vendors = {
        ["3A:83:74"] = "Android手机",
        ["3C:CD:57"] = "vivo手机",
        ["4C:74:BF"] = "小米手机",
        ["50:8F:4C"] = "OPPO手机",
        ["AC:5F:3E"] = "华为手机",
        ["D0:C5:D3"] = "三星手机",
        ["E8:50:8B"] = "iPhone",
        ["F0:D1:A9"] = "Realme手机",
        ["8C:0E:60"] = "ZTE路由器",
        ["44:59:43"] = "网络设备",
        ["00:0C:29"] = "VMware虚拟机",
        ["08:00:27"] = "VirtualBox虚拟机",
        ["52:54:00"] = "QEMU虚拟机",
        ["00:50:56"] = "VMware虚拟机",
        ["B4:6E:10"] = "电脑",
        ["0C:D8:6C"] = "电脑",
        ["80:AE:54"] = "路由器",
        ["22:1D:BE"] = "虚拟网卡",
        ["18:FE:34"] = "小米IoT设备",
        ["34:CE:00"] = "小米IoT设备",
        ["78:11:DC"] = "小米IoT设备"
    }
    
    local second_char = mac:sub(2, 2)
    if second_char == "2" or second_char == "6" or second_char == "A" or second_char == "E" then
        return "虚拟设备/热点"
    end
    
    return vendors[oui] or nil
end

-- Display all devices from ARP table
for ip, info in pairs(neighbors) do
    local label = info.ip
    local display_name = ""
    
    if info.hostname then
        display_name = info.hostname
    elseif info.dhcp_name and info.dhcp_name ~= "*" then
        display_name = info.dhcp_name
    else
        local device_type = identify_device(info.mac)
        if device_type then
            display_name = device_type
        else
            display_name = "未知设备"
        end
    end
    
    label = label .. " - " .. display_name .. " [" .. info.mac:upper() .. "]"
    o:value(info.ip, label)
end

-- Proxy Port
o = s:option(Value, "proxy_port", translate("代理端口"))
o.datatype = "port"
o.description = translate("输入代理软件的监听端口。<br/>常见端口: Clash(7890), v2rayN(10809), SSR(1080)。")

-- Proxy Type
o = s:option(ListValue, "proxy_type", translate("代理类型"))
o:value("http", "HTTP")
o:value("socks5", "SOCKS5")
o.default = "http"
o.description = translate("选择代理协议类型。通常HTTP协议兼容性更好。")

-- Global Proxy
o = s:option(Flag, "global_proxy", translate("出口设置 (全局代理)"))
o.default = "0"
o.description = translate("<b>功能：</b>勾选后，OpenWrt自身的所有流量（如下载、更新）都会强制走此代理。<br/><b>注意：</b>仅在需要更新系统或安装软件时开启。平时建议关闭，以免影响路由器性能。")

-- Buttons Template
t = s:option(DummyValue, "_buttons")
t.template = "proxy-upgrade/status"

-- Usage Guide
local guide = s:option(DummyValue, "_guide")
guide.rawhtml = true
guide.default = [[
<div class="cbi-section-descr" style="margin-top: 20px; padding: 10px; background-color: #f9f9f9; border: 1px solid #ddd; border-radius: 5px;">
    <h4 style="margin-top: 0; color: #0088cc;">使用举例与功能说明</h4>
    
    <p><b>1. 基础配置举例：</b></p>
    <p>假设你的电脑 (IP: 192.168.1.5) 运行了Clash，端口7890，开启了“允许局域网连接”。</p>
    <ul style="margin-left: 20px;">
        <li><b>代理服务器IP：</b> 选择 <code>192.168.1.5</code></li>
        <li><b>代理端口：</b> 输入 <code>7890</code></li>
        <li><b>代理类型：</b> 选择 <code>HTTP</code></li>
    </ul>

    <p><b>2. “出口设置 (全局代理)” 功能详解：</b></p>
    <ul style="margin-left: 20px;">
        <li><b>[ ] 不勾选 (默认)：</b> 
            <br/>代理配置仅生效，但不会强制接管OpenWrt的所有流量。
            <br/>点击“升级”按钮时，升级脚本会临时使用此代理配置进行更新。
            <br/><b>适用场景：</b> 日常使用，仅在需要手动升级系统时使用。
        </li>
        <li><b>[x] 勾选：</b> 
            <br/>OpenWrt系统自身的<b>所有流量</b>（包括opkg软件安装、curl下载、系统时间同步等）都会强制转发到你配置的代理服务器。
            <br/><b>联动影响：</b> 它会直接使用你上方配置的 IP、端口和协议类型。
            <br/><b>适用场景：</b> 需要在终端安装软件(opkg install)或系统本身无法访问外网时。
            <br/><b>注意：</b> 用完建议关闭，否则如果代理设备关机，OpenWrt自身将无法上网。
        </li>
    </ul>
</div>
]]

function m.on_after_commit(self)
    luci.sys.call("/usr/lib/proxy-upgrade/set-global-proxy.sh > /dev/null 2>&1 &")
end

return m
