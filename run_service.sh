#!/usr/bin/env bash

# use hostname if not paramter is provided
[ -z $1 ] && export NF=$(hostname | cut -f1 -d -) || export NF=$1

#set -o errexit
#set -o pipefail
#set -o nounset
#set -o xtrace

# source config_env and ip-export-gen
ROOT_PATH="/opt"
source ${ROOT_PATH}/config_env.sh
source ${ROOT_PATH}/ip-export-gen.sh

### turn of checksum on interfaces mainly required on datapath
for iface in $(/sbin/ip -br -4 a | awk "/192.168.*.*/" | awk '{split($1,a,"@");print a[1]}'); do
	ethtool -K $iface tso off gro off gso off tx off rx off || true >/dev/null 2>&1
done

components_commands_fn() 
{
    if [[ "${NF}" == "upf1" ]]; then 
        ip r a default via 192.168.14.40 
        sysctl -w net.ipv4.ip_forward=1 
        ip link set n6 mtu 1456 
        sysctl -w net.ipv6.conf.upi_eth.disable_ipv6=1 
        ip tuntap add mode tun user root name n6_tun 
        ip link set n6_tun up 
        ip r a 192.168.11.0/24 dev n6_tun 
        ip r a 192.168.12.0/24 dev n6_tun 
        ip r a 10.11.22.0/24 dev n6_tun 
        ip r a 10.168.0.0/16 dev n6_tun
    fi

    if [[ "${NF}" == "igw" ]]; then 
        ip r a 192.168.12.0/24 via 192.168.14.210 
        ip r a 10.11.22.0/24 via 192.168.14.210 
        ip r a 192.168.11.0/24 via 192.168.14.210 
        ip r a 10.168.0.0/16 via 192.168.14.210 
        ip r a 192.168.10.0/24 via 192.168.14.220 
        ip link set n6 mtu 1456 
        sysctl net.ipv4.ip_forward=1 
        dn_common_configuration
    fi

    if [[ "${NF}" == "upf2" ]]; then 
        sysctl -w net.ipv4.ip_forward=1 
        ip link set n6 mtu 1456 
        ip tuntap add mode tun user root name n6_tun 
        ip link set n6_tun up 
        ip r a 192.168.10.0/24 dev n6_tun
    fi

    if [[ "${NF}" == "gnb1" ]]; then 
        sysctl -w net.ipv4.ip_forward=0 
        iptables -D OUTPUT -p icmp --icmp-type destination-unreachable -j DROP 
        iptables -I OUTPUT -p icmp --icmp-type destination-unreachable -j DROP
    fi

    if [[ "${NF}" == "ue1" ]]; then 
        ue_common_configuration
    fi

    if [[ "${NF}" == "btup" ]]; then 
        ip tuntap add mode tun user root name btuptun 
        ip link set btuptun up 
        ip link set btuptun mtu 1470
    fi
}

ue_common_configuration()
{ 
    ip link set air mtu 1470
    ip r d default || true >/dev/null 2>&1
    NF_CAP_AIR="${NF^^}_AIR_IP"
    [ ! -z $NF_CAP_AIR ] && INTAIR=$(/sbin/ip -br -4 a | awk "/${!NF_CAP_AIR}\//"'{print $1}' | cut -f1 -d "@")
}

dn_common_configuration()
{
   # start dns server
   [ ! -z ${BIND_DIR} ] && cp -r ${BIND_DIR}/* /etc/bind/
   service bind9 restart
 
   sysctl net.ipv4.ip_forward=1
 
   ## UPI interface
   NF_CAP_UPI="${NF^^}_N6_IP"
   [ ! -z $NF_CAP_UPI ] && INTUPI=$(/sbin/ip -br -4 a | awk "/${!NF_CAP_UPI}\//"'{print $1}' | cut -f1 -d "@")
   ip link set ${INTUPI} mtu 1424
 
   if [ "$(ip r | grep default | wc -l)" = 1 ]; then
       # only masqurade rules when 1 default route is present
       I_FACE=$(ip r | grep -m1 default | awk '{print $5}')
       iptables -t nat -D POSTROUTING -o ${I_FACE} -j MASQUERADE || true >/dev/null 2>&1
       iptables -w -t nat -A POSTROUTING -o ${I_FACE} -j MASQUERADE
   else
       # gateway interface masqurade
       I_FACE=$(ip -br -4 a | egrep 'mgmt|ens3|eth0' | awk 'NR==1{print $1}')
       iptables -t nat -D POSTROUTING -o ${I_FACE} -j MASQUERADE || true >/dev/null 2>&1
       iptables -w -t nat -A POSTROUTING -o ${I_FACE} -j MASQUERADE
 
       # add default route with lower metric to override default route
       ROUTE_IFACE=$(ip r | egrep "default .* $(ip -br -4 a | egrep 'mgmt|ens3|eth0' | awk '{print $1}')" | awk '{print $3}')
       ip route add default via ${ROUTE_IFACE} metric 50 || true >/dev/null 2>&1
   fi
}

components_commands_fn ;;

