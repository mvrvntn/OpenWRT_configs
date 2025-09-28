#!/bin/sh

install_awg_packages() {
    # Получение pkgarch с наибольшим приоритетом
    PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max = $3; arch = $2}} END {print arch}')

    TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 1)
    SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 2)
    VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
    PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
    BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/"

    AWG_DIR="/tmp/amneziawg"
    mkdir -p "$AWG_DIR"
    
    if opkg list-installed | grep -q kmod-amneziawg; then
        echo "kmod-amneziawg already installed"
    else
        KMOD_AMNEZIAWG_FILENAME="kmod-amneziawg${PKGPOSTFIX}"
        DOWNLOAD_URL="${BASE_URL}v${VERSION}/${KMOD_AMNEZIAWG_FILENAME}"
        wget -O "$AWG_DIR/$KMOD_AMNEZIAWG_FILENAME" "$DOWNLOAD_URL"

        if [ $? -eq 0 ]; then
            echo "kmod-amneziawg file downloaded successfully"
        else
            echo "Error downloading kmod-amneziawg. Please, install kmod-amneziawg manually and run the script again"
            exit 1
        fi
        
        opkg install "$AWG_DIR/$KMOD_AMNEZIAWG_FILENAME"

        if [ $? -eq 0 ]; then
            echo "kmod-amneziawg file installed successfully"
        else
            echo "Error installing kmod-amneziawg. Please, install kmod-amneziawg manually and run the script again"
            exit 1
        fi
    fi

    if opkg list-installed | grep -q amneziawg-tools; then
        echo "amneziawg-tools already installed"
    else
        AMNEZIAWG_TOOLS_FILENAME="amneziawg-tools${PKGPOSTFIX}"
        DOWNLOAD_URL="${BASE_URL}v${VERSION}/${AMNEZIAWG_TOOLS_FILENAME}"
        wget -O "$AWG_DIR/$AMNEZIAWG_TOOLS_FILENAME" "$DOWNLOAD_URL"

        if [ $? -eq 0 ]; then
            echo "amneziawg-tools file downloaded successfully"
        else
            echo "Error downloading amneziawg-tools. Please, install amneziawg-tools manually and run the script again"
            exit 1
        fi

        opkg install "$AWG_DIR/$AMNEZIAWG_TOOLS_FILENAME"

        if [ $? -eq 0 ]; then
            echo "amneziawg-tools file installed successfully"
        else
            echo "Error installing amneziawg-tools. Please, install amneziawg-tools manually and run the script again"
            exit 1
        fi
    fi
    
    if opkg list-installed | grep -q luci-app-amneziawg; then
        echo "luci-app-amneziawg already installed"
    else
        LUCI_APP_AMNEZIAWG_FILENAME="luci-app-amneziawg${PKGPOSTFIX}"
        DOWNLOAD_URL="${BASE_URL}v${VERSION}/${LUCI_APP_AMNEZIAWG_FILENAME}"
        wget -O "$AWG_DIR/$LUCI_APP_AMNEZIAWG_FILENAME" "$DOWNLOAD_URL"

        if [ $? -eq 0 ]; then
            echo "luci-app-amneziawg file downloaded successfully"
        else
            echo "Error downloading luci-app-amneziawg. Please, install luci-app-amneziawg manually and run the script again"
            exit 1
        fi

        opkg install "$AWG_DIR/$LUCI_APP_AMNEZIAWG_FILENAME"

        if [ $? -eq 0 ]; then
            echo "luci-app-amneziawg file installed successfully"
        else
            echo "Error installing luci-app-amneziawg. Please, install luci-app-amneziawg manually and run the script again"
            exit 1
        fi
    fi

    rm -rf "$AWG_DIR"
}

manage_package() {
    local name="$1"
    local autostart="$2"
    local process="$3"

    # Проверка, установлен ли пакет
    if opkg list-installed | grep -q "^$name"; then
        
        # Проверка, включен ли автозапуск
        if /etc/init.d/$name enabled; then
            if [ "$autostart" = "disable" ]; then
                /etc/init.d/$name disable
            fi
        else
            if [ "$autostart" = "enable" ]; then
                /etc/init.d/$name enable
            fi
        fi

        # Проверка, запущен ли процесс
        if pidof $name > /dev/null; then
            if [ "$process" = "stop" ]; then
                /etc/init.d/$name stop
            fi
        else
            if [ "$process" = "start" ]; then
                /etc/init.d/$name start
            fi
        fi
    fi
}

checkPackageAndInstall()
{
    local name="$1"
    local isRequried="$2"
    #проверяем установлени ли библиотека $name
    if opkg list-installed | grep -q $name; then
        echo "$name already installed..."
    else
        echo "$name not installed. Installing $name..."
        opkg install $name
		res=$?
		if [ "$isRequried" = "1" ]; then
			if [ $res -eq 0 ]; then
				echo "$name installed successfully"
			else
				echo "Error installing $name. Please, install $name manually and run the script again"
				exit 1
			fi
		fi
    fi
}

checkAndAddDomainPermanentName()
{
  nameRule="option name '$1'"
  str=$(grep -i "$nameRule" /etc/config/dhcp)
  if [ -z "$str" ] 
  then 

    uci add dhcp domain
    uci set dhcp.@domain[-1].name="$1"
    uci set dhcp.@domain[-1].ip="$2"
    uci commit dhcp
  fi
}

echo "Update list packages..."
opkg update

checkPackageAndInstall "coreutils-base64" "1"

#проверка и установка пакетов AmneziaWG
install_awg_packages

checkPackageAndInstall "jq" "1"
checkPackageAndInstall "curl" "1"
checkPackageAndInstall "unzip" "1"
checkPackageAndInstall "sing-box" "1"

#проверяем установлени ли пакет dnsmasq-full
if opkg list-installed | grep -q dnsmasq-full; then
	echo "dnsmasq-full already installed..."
else
	echo "Installing dnsmasq-full..."
	cd /tmp/ && opkg download dnsmasq-full
	opkg remove dnsmasq && opkg install dnsmasq-full --cache /tmp/

	[ -f /etc/config/dhcp-opkg ] && cp /etc/config/dhcp /etc/config/dhcp-old && mv /etc/config/dhcp-opkg /etc/config/dhcp
fi

printf "Setting confdir dnsmasq\n"
uci set dhcp.@dnsmasq[0].confdir='/tmp/dnsmasq.d'
uci commit dhcp

DIR="/etc/config"
DIR_BACKUP="/root/backup2"
config_files="network
firewall
https-dns-proxy
dhcp"
URL="https://raw.githubusercontent.com/mvrvntn/OpenWRT_configs/refs/heads/main"

checkPackageAndInstall "https-dns-proxy" "0"

if [ ! -d "$DIR_BACKUP" ]
then
    echo "Backup files..."
    mkdir -p $DIR_BACKUP
    for file in $config_files
    do
        cp -f "$DIR/$file" "$DIR_BACKUP/$file"  
    done
	echo "Replace configs..."

	for file in $config_files
	do
		if [ "$file" == "https-dns-proxy" ] 
		then 
		  wget -O "$DIR/$file" "$URL/config_files/$file" 
		fi
	done
fi

echo "Configure dhcp..."

uci set dhcp.cfg01411c.strictorder='1'
uci set dhcp.cfg01411c.filter_aaaa='1'
uci commit dhcp

echo "Install opera-proxy client..."
service stop vpn > /dev/null 2>&1
rm -f /usr/bin/vpns /etc/init.d/vpn

url="https://github.com/NitroOxid/openwrt-opera-proxy-bin/releases/download/1.8.0/opera-proxy_1.8.0-1_aarch64_cortex-a53.ipk"
destination_file="/tmp/opera-proxy.ipk"

echo "Downloading opera-proxy..."
wget "$url" -O "$destination_file" || { echo "Failed to download the file"; exit 1; }
echo "Installing opera-proxy..."
opkg install $destination_file

echo "Setting sing-box..."
uci set sing-box.main.enabled='1'
uci set sing-box.main.user='root'
uci commit sing-box

printf "\033[32;1mManual AmneziaWG configuration...\033[0m\n"
read -r -p "Enter the private key (from [Interface]):"$'\n' PrivateKey
read -r -p "Enter S1 value (from [Interface]):"$'\n' S1
read -r -p "Enter S2 value (from [Interface]):"$'\n' S2
read -r -p "Enter Jc value (from [Interface]):"$'\n' Jc
read -r -p "Enter Jmin value (from [Interface]):"$'\n' Jmin
read -r -p "Enter Jmax value (from [Interface]):"$'\n' Jmax
read -r -p "Enter H1 value (from [Interface]):"$'\n' H1
read -r -p "Enter H2 value (from [Interface]):"$'\n' H2
read -r -p "Enter H3 value (from [Interface]):"$'\n' H3
read -r -p "Enter H4 value (from [Interface]):"$'\n' H4

while true; do
	read -r -p "Enter internal IP address with subnet, example 192.168.100.5/24 (from [Interface]):"$'\n' Address
	if echo "$Address" | egrep -oq '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]+)?$'; then
		break
	else
		echo "This IP is not valid. Please repeat"
	fi
done

read -r -p "Enter the public key (from [Peer]):"$'\n' PublicKey
read -r -p "Enter Endpoint host without port (Domain or IP) (from [Peer]):"$'\n' EndpointIP
read -r -p "Enter Endpoint host port (from [Peer]) [51820]:"$'\n' EndpointPort

DNS="1.1.1.1"
MTU=1280
AllowedIPs="0.0.0.0/0"

printf "\033[32;1mCreate and configure tunnel AmneziaWG...\033[0m\n"

#задаём имя интерфейса
INTERFACE_NAME="awg10"
CONFIG_NAME="amneziawg_awg10"
PROTO="amneziawg"
ZONE_NAME="awg"

uci set network.${INTERFACE_NAME}=interface
uci set network.${INTERFACE_NAME}.proto=$PROTO
if ! uci show network | grep -q ${CONFIG_NAME}; then
	uci add network ${CONFIG_NAME}
fi
uci set network.${INTERFACE_NAME}.private_key=$PrivateKey
uci del network.${INTERFACE_NAME}.addresses
uci add_list network.${INTERFACE_NAME}.addresses=$Address
uci set network.${INTERFACE_NAME}.mtu=$MTU
uci set network.${INTERFACE_NAME}.awg_jc=$Jc
uci set network.${INTERFACE_NAME}.awg_jmin=$Jmin
uci set network.${INTERFACE_NAME}.awg_jmax=$Jmax
uci set network.${INTERFACE_NAME}.awg_s1=$S1
uci set network.${INTERFACE_NAME}.awg_s2=$S2
uci set network.${INTERFACE_NAME}.awg_h1=$H1
uci set network.${INTERFACE_NAME}.awg_h2=$H2
uci set network.${INTERFACE_NAME}.awg_h3=$H3
uci set network.${INTERFACE_NAME}.awg_h4=$H4
uci set network.${INTERFACE_NAME}.nohostroute='1'
uci set network.@${CONFIG_NAME}[-1].description="${INTERFACE_NAME}_peer"
uci set network.@${CONFIG_NAME}[-1].public_key=$PublicKey
uci set network.@${CONFIG_NAME}[-1].endpoint_host=$EndpointIP
uci set network.@${CONFIG_NAME}[-1].endpoint_port=$EndpointPort
uci set network.@${CONFIG_NAME}[-1].persistent_keepalive='25'
uci set network.@${CONFIG_NAME}[-1].allowed_ips='0.0.0.0/0'
uci set network.@${CONFIG_NAME}[-1].route_allowed_ips='0'
uci commit network

if ! uci show firewall | grep -q "@zone.*name='${ZONE_NAME}'"; then
	printf "\033[32;1mZone Create\033[0m\n"
	uci add firewall zone
	uci set firewall.@zone[-1].name=$ZONE_NAME
	uci set firewall.@zone[-1].network=$INTERFACE_NAME
	uci set firewall.@zone[-1].forward='REJECT'
	uci set firewall.@zone[-1].output='ACCEPT'
	uci set firewall.@zone[-1].input='REJECT'
	uci set firewall.@zone[-1].masq='1'
	uci set firewall.@zone[-1].mtu_fix='1'
	uci set firewall.@zone[-1].family='ipv4'
	uci commit firewall
fi

if ! uci show firewall | grep -q "@forwarding.*name='${ZONE_NAME}'"; then
	printf "\033[32;1mConfigured forwarding\033[0m\n"
	uci add firewall forwarding
	uci set firewall.@forwarding[-1]=forwarding
	uci set firewall.@forwarding[-1].name="${ZONE_NAME}"
	uci set firewall.@forwarding[-1].dest=${ZONE_NAME}
	uci set firewall.@forwarding[-1].src='lan'
	uci set firewall.@forwarding[-1].family='ipv4'
	uci commit firewall
fi

# Получаем список всех зон
ZONES=$(uci show firewall | grep "zone$" | cut -d'=' -f1)
#echo $ZONES
# Циклически проходим по всем зонам
for zone in $ZONES; do
  # Получаем имя зоны
  CURR_ZONE_NAME=$(uci get $zone.name)
  #echo $CURR_ZONE_NAME
  # Проверяем, является ли это зона с именем "$ZONE_NAME"
  if [ "$CURR_ZONE_NAME" = "$ZONE_NAME" ]; then
    # Проверяем, существует ли интерфейс в зоне
    if ! uci get $zone.network | grep -q "$INTERFACE_NAME"; then
      # Добавляем интерфейс в зону
      uci add_list $zone.network="$INTERFACE_NAME"
      uci commit firewall
      #echo "Интерфейс '$INTERFACE_NAME' добавлен в зону '$ZONE_NAME'"
    fi
  fi
done

nameRule="option name 'Block_UDP_443'"
str=$(grep -i "$nameRule" /etc/config/firewall)
if [ -z "$str" ] 
then
  echo "Add block QUIC..."

  uci add firewall rule # =cfg2492bd
  uci set firewall.@rule[-1].name='Block_UDP_80'
  uci add_list firewall.@rule[-1].proto='udp'
  uci set firewall.@rule[-1].src='lan'
  uci set firewall.@rule[-1].dest='wan'
  uci set firewall.@rule[-1].dest_port='80'
  uci set firewall.@rule[-1].target='REJECT'
  uci add firewall rule # =cfg2592bd
  uci set firewall.@rule[-1].name='Block_UDP_443'
  uci add_list firewall.@rule[-1].proto='udp'
  uci set firewall.@rule[-1].src='lan'
  uci set firewall.@rule[-1].dest='wan'
  uci set firewall.@rule[-1].dest_port='443'
  uci set firewall.@rule[-1].target='REJECT'
  uci commit firewall
fi

printf  "\033[32;1mRestart service dnsmasq, odhcpd...\033[0m\n"
service dnsmasq restart
service odhcpd restart

PACKAGE="podkop"
REQUIRED_VERSION="0.5.6-1"

INSTALLED_VERSION=$(opkg list-installed | grep "^$PACKAGE" | cut -d ' ' -f 3)
if [ -n "$INSTALLED_VERSION" ] && [ "$INSTALLED_VERSION" != "$REQUIRED_VERSION" ]; then
    echo "Version package $PACKAGE not equal $REQUIRED_VERSION. Removed packages..."
    opkg remove --force-removal-of-dependent-packages $PACKAGE
fi

path_podkop_config="/etc/config/podkop"
path_podkop_config_backup="/root/podkop"

if [ -f "/etc/init.d/podkop" ]; then
	printf "Podkop installed. Reconfigure for AmneziaWG and Opera Proxy? (y/n): \n"
	is_reconfig_podkop="y"
	read is_reconfig_podkop
	if [ "$is_reconfig_podkop" = "y" ] || [ "$is_reconfig_podkop" = "Y" ]; then
		cp -f "$path_podkop_config" "$path_podkop_config_backup"
		wget -O "$path_podkop_config" "$URL/config_files/podkop" 
		echo "Backup of your config in path '$path_podkop_config_backup'"
		echo "Podkop reconfigured..."
	fi
else
	printf "\033[32;1mInstall and configure PODKOP (a tool for point routing of traffic)? (y/n): \033[0m\n"
	is_install_podkop="y"
	read is_install_podkop

	if [ "$is_install_podkop" = "y" ] || [ "$is_install_podkop" = "Y" ]; then
		DOWNLOAD_DIR="/tmp/podkop"
		mkdir -p "$DOWNLOAD_DIR"
		
		echo "Download podkop_v0.5.6-r1_all.ipk..."
		wget -q -O "$DOWNLOAD_DIR/podkop_v0.5.6-r1_all.ipk" "https://github.com/itdoginfo/podkop/releases/download/v0.5.6/podkop_v0.5.6-r1_all.ipk"
		
		echo "Download luci-app-podkop_v0.5.6-r1_all.ipk..."
		wget -q -O "$DOWNLOAD_DIR/luci-app-podkop_v0.5.6-r1_all.ipk" "https://github.com/itdoginfo/podkop/releases/download/v0.5.6/luci-app-podkop_v0.5.6-r1_all.ipk"
		
		echo "Download luci-i18n-podkop-ru_0.5.6.ipk..."
		wget -q -O "$DOWNLOAD_DIR/luci-i18n-podkop-ru_0.5.6.ipk" "https://github.com/itdoginfo/podkop/releases/download/v0.5.6/luci-i18n-podkop-ru_0.5.6.ipk"
		
		opkg install "$DOWNLOAD_DIR/podkop_v0.5.6-r1_all.ipk"
		opkg install "$DOWNLOAD_DIR/luci-app-podkop_v0.5.6-r1_all.ipk"
		opkg install "$DOWNLOAD_DIR/luci-i18n-podkop-ru_0.5.6.ipk"
		
		rm -rf "$DOWNLOAD_DIR"
		wget -O "$path_podkop_config" "$URL/config_files/podkop" 
		echo "Podkop installed..."
	fi
fi

printf  "\033[32;1mStart and enable service 'https-dns-proxy'...\033[0m\n"
manage_package "https-dns-proxy" "enable" "start"

str=$(grep -i "$URL/configure_zaprets.sh" /etc/crontabs/root)
if [ ! -z "$str" ]
then
	grep -v "$URL/configure_zaprets.sh" /etc/crontabs/root > /etc/crontabs/temp
	cp -f "/etc/crontabs/temp" "/etc/crontabs/root"
	rm -f "/etc/crontabs/temp"
fi

printf  "\033[32;1mRestart firewall and network...\033[0m\n"
service firewall restart
#service network restart

# Отключаем интерфейс
ifdown $INTERFACE_NAME
# Ждем несколько секунд (по желанию)
sleep 2
# Включаем интерфейс
ifup $INTERFACE_NAME

printf  "\033[32;1mService Podkop and Sing-Box restart...\033[0m\n"
service sing-box enable
service sing-box restart
service podkop enable
service podkop restart

printf  "\033[32;1mConfiguration completed...\033[0m\n"
printf  "\033[32;1mNote: youtubeUnblock can be installed later and will work alongside podkop without conflicts.\033[0m\n"
