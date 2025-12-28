#!/bin/sh

# Load UCI config
enabled=$(uci -q get proxy-upgrade.@proxy[0].enabled)
proxy_ip=$(uci -q get proxy-upgrade.@proxy[0].proxy_ip)
proxy_port=$(uci -q get proxy-upgrade.@proxy[0].proxy_port)
proxy_type=$(uci -q get proxy-upgrade.@proxy[0].proxy_type)
global_proxy=$(uci -q get proxy-upgrade.@proxy[0].global_proxy)

OPKG_CONF="/etc/opkg.conf"
PROFILE_SCRIPT="/etc/profile.d/proxy_upgrade.sh"

# Function to clear proxy settings
clear_proxy() {
    # Remove from opkg.conf
    sed -i '/option http_proxy/d' "$OPKG_CONF"
    sed -i '/option https_proxy/d' "$OPKG_CONF"
    sed -i '/option ftp_proxy/d' "$OPKG_CONF"
    
    # Remove profile script
    rm -f "$PROFILE_SCRIPT"
    
    # Unset vars in current environment (though this script runs in subshell usually)
    unset http_proxy https_proxy ftp_proxy all_proxy
    
    echo "Global Proxy Disabled"
}

if [ "$enabled" = "1" ] && [ "$global_proxy" = "1" ] && [ -n "$proxy_ip" ] && [ -n "$proxy_port" ]; then
    # Construct Proxy URL
    if [ "$proxy_type" = "socks5" ]; then
        # Use socks5h for remote DNS
        PROXY_URL="socks5h://$proxy_ip:$proxy_port"
    else
        PROXY_URL="$proxy_type://$proxy_ip:$proxy_port"
    fi
    
    echo "Setting Global Proxy to $PROXY_URL"
    
    # 1. Configure opkg
    # Clean old entries first
    sed -i '/option http_proxy/d' "$OPKG_CONF"
    sed -i '/option https_proxy/d' "$OPKG_CONF"
    sed -i '/option ftp_proxy/d' "$OPKG_CONF"
    
    echo "option http_proxy $PROXY_URL" >> "$OPKG_CONF"
    echo "option https_proxy $PROXY_URL" >> "$OPKG_CONF"
    echo "option ftp_proxy $PROXY_URL" >> "$OPKG_CONF"
    
    # 2. Configure shell environment via profile.d
    mkdir -p /etc/profile.d
    cat > "$PROFILE_SCRIPT" <<EOT
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export ftp_proxy="$PROXY_URL"
export all_proxy="$PROXY_URL"
EOT
    chmod +x "$PROFILE_SCRIPT"
    
else
    clear_proxy
fi
