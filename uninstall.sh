#!/bin/sh
# ==============================================================================
# zapret2-secondlife: Uninstall / Revert Second Life rules
# https://github.com/PinyaGit/zapret2-secondlife
# ==============================================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}Удаление настроек Second Life из zapret2...${NC}"

# Удаление стратегий zapret2
uci -q delete zapret2.secondlife_tls || true
uci -q delete zapret2.secondlife_udp || true
uci -q delete zapret2.list_hosts_secondlife || true

if uci -q get zapret2.V_circular >/dev/null; then
    uci -q del_list zapret2.V_circular.hostlist_exclude='list_hosts_secondlife' || true
fi
uci commit zapret2

# Удаление файла со списком доменов
rm -f /opt/zapret2/ipset/zapret_hosts_secondlife.txt

# Удаление записей из dnsmasq
for dom in secondlife.com lindenlab.com secondlife.io secondlifegrid.net akamaized.net vivox.com; do
    uci -q del_list dhcp.@dnsmasq[0].server="/$dom/1.1.1.1" || true
    uci -q del_list dhcp.@dnsmasq[0].server="/$dom/8.8.8.8" || true
    uci -q del_list dhcp.@dnsmasq[0].server="/$dom/9.9.9.9" || true
done
uci commit dhcp

# Перезапуск служб
/etc/init.d/dnsmasq restart
/etc/init.d/zapret2 restart

echo -e "${GREEN}Настройки Second Life успешно удалены.${NC}"
