#!/bin/bash
# Forked from binhex's OpenVPN dockers

# Wait until tunnel is up
while : ; do
	tunnelstat=$(netstat -ie | grep -E "tun|tap")
	if [[ ! -z "${tunnelstat}" ]]; then
		break
	else
		sleep 1
	fi
done

# ip route
###

DEBUG=false


# split comma seperated string into list from LAN_NETWORK env variable
IFS=',' read -ra lan_network_list <<< "${LAN_NETWORK}"

lancount=0
# process lan networks in the list
for lan_network_item in "${lan_network_list[@]}"; do

	# get default gateway of interfaces as looping through them
	DEFAULT_GATEWAY=$(ip -4 route list 0/${lancount} | cut -d ' ' -f 3)
	
	# strip whitespace from start and end of lan_network_item
	lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	echo "[info] Adding ${lan_network_item} as route via docker eth0"
	ip route add "${lan_network_item}" via "${DEFAULT_GATEWAY}" dev eth0

	lancount=$((lancount+1))
done

echo "[info] ip route defined as follows..."
echo "--------------------"
ip route
echo "--------------------"

# setup iptables marks to allow routing of defined ports via eth0
###

if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Modules currently loaded for kernel" ; lsmod
fi

# check we have iptable_mangle, if so setup fwmark
lsmod | grep iptable_mangle
iptable_mangle_exit_code=$?

if [[ $iptable_mangle_exit_code == 0 ]]; then

	echo "[info] iptable_mangle support detected, adding fwmark for tables"

	# setup route for qbittorrent webui using set-mark to route traffic for port 8990 to eth0
	echo "8990    webui" >> /etc/iproute2/rt_tables
	ip rule add fwmark 1 table webui
	ip route add default via $DEFAULT_GATEWAY table webui

fi

# identify docker bridge interface name (probably eth0)
 docker_interface=$(netstat -ie | grep -vE "lo|tun|tap" | sed -n '1!p' | grep -P -o -m 1 '^[\w]+')
if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Docker interface defined as ${docker_interface}"
fi

# identify ip for docker bridge interface
docker_ip=$(ifconfig "${docker_interface}" | grep -P -o -m 1 '(?<=inet\saddr:)[^\s]+')
if [[ "${DEBUG}" == "true" ]]; then
 	echo "[debug] Docker IP defined as ${docker_ip}"
fi

# identify netmask for docker bridge interface
docker_mask=$(ifconfig "${docker_interface}" | grep -P -o -m 1 '(?<=Mask:)[^\s]+')
if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Docker netmask defined as ${docker_mask}"
fi

# convert netmask into cidr format
docker_network_cidr=$(ipcalc "${docker_ip}" "${docker_mask}" | grep -P -o -m 1 "(?<=Network:)\s+[^\s]+" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
echo "[info] Docker network defined as ${docker_network_cidr}"
# input iptable rules
###

# set policy to drop ipv4 for input
iptables -P INPUT DROP

# set policy to drop ipv6 for input
ip6tables -P INPUT DROP 1>&- 2>&-

# accept input to tunnel adapter
iptables -A INPUT -i "${VPN_DEVICE_TYPE}" -j ACCEPT

# accept input to/from docker containers (172.x range is internal dhcp)
iptables -A INPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -j ACCEPT

# accept input to vpn gateway
iptables -A INPUT -i eth0 -p $VPN_PROTOCOL --sport $VPN_PORT -j ACCEPT

# accept input to qbittorrent webui port 8990
iptables -A INPUT -i eth0 -p tcp --dport 8990 -j ACCEPT
iptables -A INPUT -i eth0 -p tcp --sport 8990 -j ACCEPT

# process lan networks in the list
for lan_network_item in "${lan_network_list[@]}"; do

	# strip whitespace from start and end of lan_network_item
	lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	# accept input to qbittorrent daemon port - used for lan access
	iptables -A INPUT -i eth0 -s "${lan_network_item}" -p tcp --dport 8999 -j ACCEPT

done

# accept input icmp (ping)
iptables -A INPUT -p icmp --icmp-type echo-reply -j ACCEPT

# accept input to local loopback
iptables -A INPUT -i lo -j ACCEPT

# output iptable rules
###

# set policy to drop ipv4 for output
iptables -P OUTPUT DROP

# set policy to drop ipv6 for output
ip6tables -P OUTPUT DROP 1>&- 2>&-

# accept output from tunnel adapter
iptables -A OUTPUT -o "${VPN_DEVICE_TYPE}" -j ACCEPT

# accept output to/from docker containers (172.x range is internal dhcp)
iptables -A OUTPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -j ACCEPT

# accept output from vpn gateway
iptables -A OUTPUT -o eth0 -p $VPN_PROTOCOL --dport $VPN_PORT -j ACCEPT

# if iptable mangle is available (kernel module) then use mark
if [[ $iptable_mangle_exit_code == 0 ]]; then

	# accept output from deluge webui port 8112 - used for external access
	iptables -t mangle -A OUTPUT -p tcp --dport 8990 -j MARK --set-mark 1
	iptables -t mangle -A OUTPUT -p tcp --sport 8990 -j MARK --set-mark 1

fi

# accept output from deluge webui port 8112 - used for lan access
iptables -A OUTPUT -o eth0 -p tcp --dport 8990 -j ACCEPT
iptables -A OUTPUT -o eth0 -p tcp --sport 8990 -j ACCEPT

# process lan networks in the list
for lan_network_item in "${lan_network_list[@]}"; do

	# strip whitespace from start and end of lan_network_item
	lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	# accept output to deluge daemon port - used for lan access
	iptables -A OUTPUT -o eth0 -d "${lan_network_item}" -p tcp --sport 8999 -j ACCEPT

done

# accept output for icmp (ping)
iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT

# accept output from local loopback adapter
iptables -A OUTPUT -o lo -j ACCEPT

echo "[info] iptables defined as follows..."
echo "--------------------"
iptables -S
echo "--------------------"

exec /bin/bash /etc/qbittorrent/start.sh
