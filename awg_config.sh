#!/bin/sh

install_awg_packages() {
    PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3>max) {max=$3; arch=$2}} END {print arch}')
    TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f1)
    SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f2)
    VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
    PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
    BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/"
    AWG_DIR="/tmp/amneziawg"
    mkdir -p "$AWG_DIR"

    if ! opkg list-installed | grep -q kmod-amneziawg; then
        KFN="kmod-amneziawg${PKGPOSTFIX}"
        wget -O "$AWG_DIR/$KFN" "${BASE_URL}v${VERSION}/$KFN" || { echo "Download kmod failed"; exit 1; }
        opkg install "$AWG_DIR/$KFN" || { echo "Install kmod failed"; exit 1; }
    fi

    if ! opkg list-installed | grep -q amneziawg-tools; then
        TFN="amneziawg-tools${PKGPOSTFIX}"
        wget -O "$AWG_DIR/$TFN" "${BASE_URL}v${VERSION}/$TFN" || { echo "Download tools failed"; exit 1; }
        opkg install "$AWG_DIR/$TFN" || { echo "Install tools failed"; exit 1; }
    fi

    if ! opkg list-installed | grep -q luci-app-amneziawg; then
        LFN="luci-app-amneziawg${PKGPOSTFIX}"
        wget -O "$AWG_DIR/$LFN" "${BASE_URL}v${VERSION}/$LFN" || { echo "Download luci-app failed"; exit 1; }
        opkg install "$AWG_DIR/$LFN" || { echo "Install luci-app failed"; exit 1; }
    fi

    rm -rf "$AWG_DIR"
}

manage_package() {
    local name="$1" as="$2" ps="$3"
    if opkg list-installed | grep -q "^$name"; then
        if /etc/init.d/$name enabled; then
            [ "$as" = "disable" ] && /etc/init.d/$name disable
        else
            [ "$as" = "enable" ] && /etc/init.d/$name enable
        fi
        if pidof $name >/dev/null; then
            [ "$ps" = "stop" ] && /etc/init.d/$name stop
        else
            [ "$ps" = "start" ] && /etc/init.d/$name start
        fi
    fi
}

checkPackageAndInstall() {
    local name="$1" req="$2"
    if ! opkg list-installed | grep -q "^$name "; then
        opkg install "$name" || { echo "Error installing $name"; [ "$req" = "1" ] && exit 1; }
    fi
}

echo "Updating package lists..."
opkg update

echo "Removing https-dns-proxy and opera-proxy conflicts..."
opkg remove https-dns-proxy --force-removal-of-dependent-packages 2>/dev/null || true
opkg remove luci-app-https-dns-proxy --force-removal-of-dependent-packages 2>/dev/null || true
opkg remove opera-proxy --force-removal-of-dependent-packages 2>/dev/null || true

checkPackageAndInstall "coreutils-base64" 1
checkPackageAndInstall "jq" 1
checkPackageAndInstall "curl" 1
checkPackageAndInstall "unzip" 1
checkPackageAndInstall "sing-box" 1

install_awg_packages

# dnsmasq-full
if ! opkg list-installed | grep -q dnsmasq-full; then
    cd /tmp/ && opkg download dnsmasq-full
    opkg remove dnsmasq
    opkg install dnsmasq-full --cache /tmp/
    [ -f /etc/config/dhcp-opkg ] && mv /etc/config/dhcp /etc/config/dhcp-old && mv /etc/config/dhcp-opkg /etc/config/dhcp
fi
uci set dhcp.@dnsmasq[0].confdir='/tmp/dnsmasq.d'
uci commit dhcp

# Backup configs
DIR="/etc/config"
DIR_BAK="/root/backup2"
FILES="network firewall dhcp"
URL="https://raw.githubusercontent.com/mvrvntn/OpenWRT_configs/refs/heads/main"
[ ! -d "$DIR_BAK" ] && mkdir -p "$DIR_BAK"
for f in $FILES; do cp -f "$DIR/$f" "$DIR_BAK/$f"; done

# Replace configs
for f in $FILES; do
    wget -O "$DIR/$f" "$URL/config_files/$f"
done

uci set dhcp.cfg01411c.strictorder=1
uci set dhcp.cfg01411c.filter_aaaa=1
uci commit dhcp

printf "\nManual AmneziaWG configuration\n"
read -p "PrivateKey: " PrivateKey
read -p "S1: " S1
read -p "S2: " S2
read -p "Jc: " Jc
read -p "Jmin: " Jmin
read -p "Jmax: " Jmax
read -p "H1: " H1
read -p "H2: " H2
read -p "H3: " H3
read -p "H4: " H4
while :; do
  read -p "Address (IP/Subnet): " Address
  echo "$Address" | egrep -oq '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]+)?$' && break
  echo "Invalid, retry"
done
read -p "PublicKey: " PublicKey
read -p "EndpointIP: " EndpointIP
read -p "EndpointPort [51820]: " EndpointPort

DNS="1.1.1.1"; MTU=1280; AllowedIPs="0.0.0.0/0"

# Configure AWG
INTERFACE=awg10; CONF=amneziawg_awg10; ZONE=awg
uci set network.$INTERFACE=interface
uci set network.$INTERFACE.proto=amneziawg
[ -z "$(uci show network | grep $CONF)" ] && uci add network $CONF
uci set network.$INTERFACE.private_key=$PrivateKey
uci del network.$INTERFACE.addresses
uci add_list network.$INTERFACE.addresses=$Address
uci set network.$INTERFACE.mtu=$MTU
uci set network.$INTERFACE.awg_jc=$Jc
uci set network.$INTERFACE.awg_jmin=$Jmin
uci set network.$INTERFACE.awg_jmax=$Jmax
uci set network.$INTERFACE.awg_s1=$S1
uci set network.$INTERFACE.awg_s2=$S2
uci set network.$INTERFACE.awg_h1=$H1
uci set network.$INTERFACE.awg_h2=$H2
uci set network.$INTERFACE.awg_h3=$H3
uci set network.$INTERFACE.awg_h4=$H4
uci set network.$INTERFACE.nohostroute=1
uci set network.@$CONF[-1].description="${INTERFACE}_peer"
uci set network.@$CONF[-1].public_key=$PublicKey
uci set network.@$CONF[-1].endpoint_host=$EndpointIP
uci set network.@$CONF[-1].endpoint_port=$EndpointPort
uci set network.@$CONF[-1].persistent_keepalive=25
uci set network.@$CONF[-1].allowed_ips=$AllowedIPs
uci set network.@$CONF[-1].route_allowed_ips=0
uci commit network

# Firewall zone & forwarding
if ! uci show firewall | grep -q "zone.*name='$ZONE'"; then
  uci add firewall zone
  uci set firewall.@zone[-1].name=$ZONE
  uci set firewall.@zone[-1].network=$INTERFACE
  uci set firewall.@zone[-1].forward=REJECT
  uci set firewall.@zone[-1].output=ACCEPT
  uci set firewall.@zone[-1].input=REJECT
  uci set firewall.@zone[-1].masq=1
  uci set firewall.@zone[-1].mtu_fix=1
  uci set firewall.@zone[-1].family=ipv4
  uci commit firewall
fi
if ! uci show firewall | grep -q "forwarding.*name='$ZONE'"; then
  uci add firewall forwarding
  uci set firewall.@forwarding[-1].name=$ZONE
  uci set firewall.@forwarding[-1].src=lan
  uci set firewall.@forwarding[-1].dest=$ZONE
  uci set firewall.@forwarding[-1].family=ipv4
  uci commit firewall
fi
for zone in $(uci show firewall | grep zone$ | cut -d= -f1); do
  [ "$(uci get $zone.name)" = "$ZONE" ] && {
    uci add_list $zone.network=$INTERFACE
    uci commit firewall
  }
done

# Block QUIC
nameRule="option name 'Block_UDP_443'"
if ! grep -iq "$nameRule" /etc/config/firewall; then
  uci add firewall rule
  uci set firewall.@rule[-1].name='Block_UDP_80'
  uci add_list firewall.@rule[-1].proto='udp'
  uci set firewall.@rule[-1].src='lan'
  uci set firewall.@rule[-1].dest='wan'
  uci set firewall.@rule[-1].dest_port='80'
  uci set firewall.@rule[-1].target='REJECT'
  uci add firewall rule
  uci set firewall.@rule[-1].name='Block_UDP_443'
  uci add_list firewall.@rule[-1].proto='udp'
  uci set firewall.@rule[-1].src='lan'
  uci set firewall.@rule[-1].dest='wan'
  uci set firewall.@rule[-1].dest_port='443'
  uci set firewall.@rule[-1].target='REJECT'
  uci commit firewall
fi

service dnsmasq restart
service odhcpd restart

# Podkop v0.5.6 install
PACKAGE="podkop"
REQUIRED="0.5.6-1"
URL="https://raw.githubusercontent.com/mvrvntn/OpenWRT_configs/refs/heads/main"

INSTALLED=$(opkg list-installed | grep "^$PACKAGE" | cut -d' ' -f3)
if [ -n "$INSTALLED" ] && [ "$INSTALLED" != "$REQUIRED" ]; then
  opkg remove --force-removal-of-dependent-packages $PACKAGE
fi

CFG="/etc/config/podkop"; CFGBAK="/root/podkop"
if [ -f "/etc/init.d/podkop" ]; then
  echo "Podkop already installed. Reconfigure? (y/n):"
  read yn
  if [ "$yn" = "y" ]; then
    cp $CFG $CFGBAK
    wget -O $CFG "$URL/config_files/podkop"
    echo "Podkop reconfigured."
  fi
else
  echo "Install Podkop? (y/n):"
  read yn
  if [ "$yn" = "y" ]; then
    DLD="/tmp/podkop"; mkdir -p $DLD
    wget -qO $DLD/podkop_v0.5.6-r1_all.ipk "$URL/podkop_packets/podkop_v0.5.6-r1_all.ipk"
    wget -qO $DLD/luci-app-podkop_v0.5.6-r1_all.ipk "$URL/podkop_packets/luci-app-podkop_v0.5.6-r1_all.ipk"
    wget -qO $DLD/luci-i18n-podkop-ru_0.5.6.ipk "$URL/podkop_packets/luci-i18n-podkop-ru_0.5.6.ipk"
    opkg install $DLD/podkop_v0.5.6-r1_all.ipk
    opkg install $DLD/luci-app-podkop_v0.5.6-r1_all.ipk
    opkg install $DLD/luci-i18n-podkop-ru_0.5.6.ipk
    rm -rf $DLD
    wget -O $CFG "$URL/config_files/podkop"
    echo "Podkop installed."
  fi
fi

service firewall restart
ifdown $INTERFACE; sleep 2; ifup $INTERFACE

service sing-box enable; service sing-box restart
if [ -f "/etc/init.d/podkop" ]; then
  service podkop enable; service podkop restart
fi

echo "Setup completed. youtubeUnblock is removed from this script and can be installed separately."
