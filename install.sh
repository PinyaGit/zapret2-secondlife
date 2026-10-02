#!/bin/sh
# ==============================================================================
# zapret2-secondlife: Unblock Second Life on OpenWrt via zapret2
# https://github.com/PinyaGit/zapret2-secondlife
# ==============================================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}   zapret2-secondlife: Настройка обхода блокировки   ${NC}"
echo -e "${BLUE}                 для Second Life                     ${NC}"
echo -e "${BLUE}=====================================================${NC}"

# Проверка, что скрипт запущен на OpenWrt
if [ ! -f /etc/openwrt_release ]; then
    echo -e "${RED}[ОШИБКА] Скрипт предназначен только для OpenWrt!${NC}" >&2
    exit 1
fi

# Проверка наличия zapret2
if [ ! -f /etc/config/zapret2 ] || [ ! -d /opt/zapret2 ]; then
    echo -e "${RED}[ОШИБКА] Пакет zapret2 не обнаружен!${NC}" >&2
    echo -e "${YELLOW}Для работы фикса на роутере уже должен быть установлен и настроен zapret2.${NC}" >&2
    echo -e "${YELLOW}Пожалуйста, сначала установите zapret2, затем повторите запуск.${NC}" >&2
    exit 1
fi

echo -e "${GREEN}[1/5] Создание списка доменов Second Life...${NC}"
mkdir -p /opt/zapret2/ipset
cat > /opt/zapret2/ipset/zapret_hosts_secondlife.txt << 'EOF'
secondlife.com
lindenlab.com
secondlife.io
secondlifegrid.net
akamaized.net
vivox.com
EOF
chmod 644 /opt/zapret2/ipset/zapret_hosts_secondlife.txt

echo -e "${GREEN}[2/5] Настройка стратегий zapret2 (TLS и UDP Circuit)...${NC}"
uci -q delete zapret2.list_hosts_secondlife || true
uci -q delete zapret2.secondlife_tls || true
uci -q delete zapret2.secondlife_udp || true

# Список доменов
uci set zapret2.list_hosts_secondlife=list
uci set zapret2.list_hosts_secondlife.path='/opt/zapret2/ipset/zapret_hosts_secondlife.txt'

# 1. TCP TLS desync (HTTP login, capabilities, textures, inventory)
uci set zapret2.secondlife_tls=strategy
uci set zapret2.secondlife_tls.enabled='1'
uci set zapret2.secondlife_tls.port='443,12043,12046'
uci add_list zapret2.secondlife_tls.filter_l3='ipv4'
uci add_list zapret2.secondlife_tls.protocol='tcp'
uci add_list zapret2.secondlife_tls.filter_l7='tls'
uci add_list zapret2.secondlife_tls.hostlist='list_hosts_secondlife'
uci set zapret2.secondlife_tls.script='--payload=tls_client_hello
--lua-desync=hostfakesplit:host=google.com:tcp_ts=-600000'

# 2. UDP desync для игрового протокола Linden UDP Circuit (симуляторы)
uci set zapret2.blob_quic_initial_www_google_com.enabled='1'
uci set zapret2.secondlife_udp=strategy
uci set zapret2.secondlife_udp.enabled='1'
uci set zapret2.secondlife_udp.port='12035,12036,13000-13050'
uci add_list zapret2.secondlife_udp.filter_l3='ipv4'
uci add_list zapret2.secondlife_udp.protocol='udp'
uci set zapret2.secondlife_udp.script='--out-range=<n4
--payload=known,unknown
--lua-desync=fake:blob=blob_quic_initial_www_google_com:badsum:ip_ttl=3:repeats=2:payload=known,unknown'

# Исключаем Second Life из общей стратегии V_circular
if uci -q get zapret2.V_circular >/dev/null; then
    uci -q del_list zapret2.V_circular.hostlist_exclude='list_hosts_secondlife' || true
    uci add_list zapret2.V_circular.hostlist_exclude='list_hosts_secondlife'
fi

# Исключаем порты симуляторов из games_udp (если стратегия включена)
if uci -q get zapret2.games_udp >/dev/null; then
    uci set zapret2.games_udp.port='88,1024-2407,2409-4499,4502-12034,12037-12999,13051-19293,19345-49999,50101-65535'
fi

# Не перехватывать входящий UDP до DNAT (защита conntrack и сокетов)
uci set zapret2.main.nfqws_udp_pkt_in='0'

# Перехват исходящих портов в nfqws
uci set zapret2.main.nfqws_ports_udp='53,80,88,443,1024-65535'

uci commit zapret2

echo -e "${GREEN}[3/5] Настройка фаервола (отключение аппаратного оффлоада)...${NC}"
# Аппаратный оффлоад (MT7981 PPE) ломает UDP-потоки после 30 пакетов
uci set firewall.@defaults[0].flow_offloading='0'
uci set firewall.@defaults[0].flow_offloading_hw='0'
uci commit firewall

echo -e "${GREEN}[4/5] Настройка прямого DNS (защита от DNS poisoning)...${NC}"
for dom in secondlife.com lindenlab.com secondlife.io secondlifegrid.net akamaized.net vivox.com; do
    uci -q del_list dhcp.@dnsmasq[0].server="/$dom/1.1.1.1" || true
    uci -q del_list dhcp.@dnsmasq[0].server="/$dom/8.8.8.8" || true
    uci add_list dhcp.@dnsmasq[0].server="/$dom/1.1.1.1"
    uci add_list dhcp.@dnsmasq[0].server="/$dom/8.8.8.8"
done
uci commit dhcp

echo -e "${GREEN}[5/5] Перезапуск служб...${NC}"
/etc/init.d/dnsmasq restart
/etc/init.d/firewall restart
/etc/init.d/zapret2 restart

echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}  Second Life успешно разблокирован через zapret2!   ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo -e "Теперь можно запускать клиент (BlackDragon, Firestorm и др.)"
echo -e "без использования VPN!"
