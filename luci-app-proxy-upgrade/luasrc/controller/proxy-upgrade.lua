module("luci.controller.proxy-upgrade", package.seeall)

function index()
    entry({"admin", "system", "proxy-upgrade"}, cbi("proxy-upgrade"), _("代理升级"), 60)
    entry({"admin", "system", "proxy-upgrade", "device_info"}, call("get_device_info"), nil).leaf = true
    entry({"admin", "system", "proxy-upgrade", "test"}, call("test_proxy"), nil).leaf = true
    entry({"admin", "system", "proxy-upgrade", "upgrade"}, call("do_upgrade"), nil).leaf = true
    entry({"admin", "system", "proxy-upgrade", "log"}, call("get_log"), nil).leaf = true
end

function get_device_info()
    -- Debug logging helper
    local function log_debug(msg)
        local f = io.open("/tmp/proxy-upgrade-debug.log", "a")
        if f then
            f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(msg) .. "\n")
            f:close()
        end
    end

    local ip = luci.http.formvalue("ip")
    if not ip then
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "No IP provided"})
        return
    end
    
    log_debug("Requesting info for IP: " .. ip)
    
    local info = {}
    info.ip = ip
    
    -- Wrap in pcall to catch errors
    local status, err = pcall(function()
        -- Get MAC address from ARP table
        local arp = io.popen("cat /proc/net/arp | grep " .. ip)
        if arp then
            local line = arp:read("*line")
            if line then
                local _, _, _, mac = line:match("(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
                info.mac = mac or "Unknown"
            end
            arp:close()
        end
        
        -- Get DHCP lease information
        local dhcp = io.open("/tmp/dhcp.leases", "r")
        if dhcp then
            for line in dhcp:lines() do
                local ts, mac, lease_ip, name = line:match("(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
                if lease_ip == ip then
                    info.hostname = name ~= "*" and name or "Unknown"
                    info.lease_time = ts
                    -- Calculate connection time
                    local current_time = os.time()
                    local lease_timestamp = tonumber(ts)
                    if lease_timestamp then
                        info.connect_timestamp = os.date("%Y-%m-%d %H:%M:%S", lease_timestamp)
                        info.connected_time = "租约过期时间"
                    end
                    break
                end
            end
            dhcp:close()
        end
        
        -- Try to detect OS type via TTL
        local ping_cmd = "ping -c 1 -W 1 -w 1 " .. ip .. " 2>&1"
        log_debug("Running ping: " .. ping_cmd)
        local ping = io.popen(ping_cmd)
        if ping then
            local output = ping:read("*all")
            log_debug("Ping output: " .. (output or "nil"))
            local ttl = output:match("ttl=(%d+)")
            if ttl then
                ttl = tonumber(ttl)
                if ttl <= 64 then
                    info.os_type = "Linux/Android/iOS"
                elseif ttl <= 128 then
                    info.os_type = "Windows"
                else
                    info.os_type = "Unknown"
                end
                info.ttl = ttl
            else
                info.os_type = "无法探测 (Ping不可达)"
                info.ttl = "N/A"
            end
            ping:close()
        end
        
        -- Get connection count
        local conn_count = io.popen("cat /proc/net/nf_conntrack 2>/dev/null | grep -c " .. ip .. " || echo 0")
        if conn_count then
            info.connections = conn_count:read("*line") or "0"
            conn_count:close()
        end
    end)

    if not status then
        log_debug("Error occurred: " .. tostring(err))
        info.error = tostring(err)
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json(info)
    log_debug("Response sent")
end

function test_proxy()
    local uci = require "luci.model.uci".cursor()
    
    -- Prioritize form values (unsaved), fallback to UCI (saved)
    local proxy_ip = luci.http.formvalue("ip")
    if not proxy_ip or proxy_ip == "" then
        proxy_ip = uci:get("proxy-upgrade", "@proxy[0]", "proxy_ip")
    end
    
    local proxy_port = luci.http.formvalue("port")
    if not proxy_port or proxy_port == "" then
        proxy_port = uci:get("proxy-upgrade", "@proxy[0]", "proxy_port")
    end
    
    local proxy_type = luci.http.formvalue("type")
    if not proxy_type or proxy_type == "" then
        proxy_type = uci:get("proxy-upgrade", "@proxy[0]", "proxy_type") or "http"
    end
    
    if not proxy_ip or proxy_ip == "" or not proxy_port or proxy_port == "" then
        luci.http.prepare_content("application/json")
        luci.http.write_json({success = false, message = "配置不完整: 请填写IP和端口"})
        return
    end
    
    -- Construct Proxy URL
    local proxy_url = ""
    if proxy_type == "socks5" then
        -- Use socks5h to resolve DNS remotely
        proxy_url = "socks5h://" .. proxy_ip .. ":" .. proxy_port
    else
        proxy_url = proxy_type .. "://" .. proxy_ip .. ":" .. proxy_port
    end
    
    -- Use -sS to hide progress but show errors, -m 5 for timeout, -I for HEAD request
    local cmd = string.format("curl -sS -x %s -m 5 -I https://www.google.com 2>&1", proxy_url)
    local result = luci.sys.exec(cmd)
    
    luci.http.prepare_content("application/json")
    -- Updated regex to match HTTP/2 200 as well as HTTP/1.1 200
    -- Matches "HTTP/" followed by any non-space characters (version), then space, then "200"
    if result:match("HTTP/%S+%s+200") then
        luci.http.write_json({success = true, message = "连接成功 (HTTP 200)"})
    else
        -- Extract a brief error message
        local err_msg = ""
        local code = result:match("curl: %((%d+)%)")
        
        if code then
             if code == "35" then
                err_msg = "SSL握手失败 (Code 35)。\n原因可能是：\n1. 路由器时间不准\n2. 代理服务器不支持SOCKS5 UDP\n建议：尝试切换为 HTTP 代理类型。"
             elseif code == "7" then
                err_msg = "连接被拒绝 (Code 7)。\n请检查：\n1. 代理软件是否开启了'允许局域网连接'\n2. 电脑防火墙是否放行了端口 " .. proxy_port
             elseif code == "28" then
                err_msg = "连接超时 (Code 28)。\n请检查IP地址是否正确，或网络是否通畅。"
             else
                err_msg = result
             end
        else
             err_msg = result
        end

        if #err_msg > 150 then err_msg = err_msg:sub(1, 150) .. "..." end
        luci.http.write_json({success = false, message = "失败: " .. err_msg})
    end
end

function do_upgrade()
    luci.http.write("开始升级...\n")
    luci.sys.exec("/usr/lib/proxy-upgrade/upgrade.sh > /tmp/proxy-upgrade.log 2>&1 &")
    luci.http.write("升级任务已启动，请查看日志。\n")
end

function get_log()
    local log = io.open("/tmp/proxy-upgrade.log", "r")
    if log then
        luci.http.write(log:read("*all"))
        log:close()
    else
        luci.http.write("暂无日志")
    end
end
