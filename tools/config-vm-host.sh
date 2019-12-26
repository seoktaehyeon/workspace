#!/bin/bash
# Config hostname, network, selinux, iptable

_OS=''
cat /etc/*release | grep -q CentOS && _OS='centos'
cat /etc/*release | grep -q Ubuntu && _OS='ubuntu'
[[ "${_OS}" == "" ]] && {
    echo "Unknown OS"
    cat /etc/*release
    exit 1
}
_IP=${1?}
_NETMASK=${2-"255.255.0.0"}
_DEFAULT_GATEWAY=$(echo ${_IP} | awk -F '.' '{print $1"."$2".0.1"}')
_GATEWAY=${3-"${_DEFAULT_GATEWAY}"}
_DNS1=${4-"192.168.1.1"}
_DNS2=${5-"223.5.5.5"}
_HOSTNAME=${6-""}
ping -c 4 ${_IP}
(( $? == 0 )) && {
    echo "${_IP} has been used, need change another one"
    exit 1
}

echo "== Config network =="
echo "${_OS}" | grep -qE 'centos' && {
    _IFCFG="/etc/sysconfig/network-scripts/$(ls /etc/sysconfig/network-scripts/ | grep 'ifcfg-' | grep -v 'ifcfg-lo')"

    echo ">> Enable ONBOOT"
    sed -i 's/ONBOOT=.*/ONBOOT=yes/' ${_IFCFG}

    echo ">> Set BOOTPROTO"
    sed -i 's/BOOTPROTO=.*/BOOTPROTO=static/' ${_IFCFG}

    echo ">> Config ip address"
    grep -q 'IPADDR=' ${_IFCFG}
    if (( $? == 0 )); then
        sed -i "s/IPADDR=.*/IPADDR=${_IP}/" ${_IFCFG}
    else
        echo "IPADDR=${_IP}" >> ${_IFCFG}
    fi

    echo ">> Config netmask"
    grep -q 'NETMASK=' ${_IFCFG}
    if (( $? == 0 )); then
        sed -i "s/NETMASK=.*/NETMASK=${_NETMASK}/" ${_IFCFG}
    else
        echo "NETMASK=${_NETMASK}" >> ${_IFCFG}
    fi

    echo ">> Config gateway"
    grep -q 'GATEWAY=' ${_IFCFG}
    if (( $? == 0 )); then
        sed -i "s/GATEWAY=.*/GATEWAY=${_GATEWAY}/" ${_IFCFG}
    else
        echo "GATEWAY=${_GATEWAY}" >> ${_IFCFG}
    fi

    echo ">> Config dns1"
    grep -q 'DNS1=' ${_IFCFG}
    if (( $? == 0 )); then
        sed -i "s/DNS1=.*/DNS1=${_DNS1}/" ${_IFCFG}
    else
        echo "DNS1=${_DNS1}" >> ${_IFCFG}
    fi

    echo ">> Config dns2"
    grep -q 'DNS2=' ${_IFCFG}
    if (( $? == 0 )); then
        sed -i "s/DNS2=.*/DNS2=${_DNS2}/" ${_IFCFG}
    else
        echo "DNS2=${_DNS2}" >> ${_IFCFG}
    fi
}
echo "${_OS}" | grep -qE 'ubuntu' && {
    _IFCFG="/etc/network/interfaces"

#    echo ">> Enable ONBOOT"
#    sed -i 's/ONBOOT=.*/ONBOOT=yes/' ${_IFCFG}

#    echo ">> Set BOOTPROTO"
#    sed -i 's/BOOTPROTO=.*/BOOTPROTO=static/' ${_IFCFG}

    echo ">> Config ip address"
    grep -q 'address ' ${_IFCFG}
    if (( $? == 0 )); then
        sed -i "s/address .*/address ${_IP}/" ${_IFCFG}
    else
        echo "address ${_IP}" >> ${_IFCFG}
    fi

    echo ">> Config netmask"
    grep -q 'netmask ' ${_IFCFG}
    if (( $? == 0 )); then
        sed -i "s/netmask .*/netmask ${_NETMASK}/" ${_IFCFG}
    else
        echo "netmask ${_NETMASK}" >> ${_IFCFG}
    fi

    echo ">> Config gateway"
    grep -q 'gateway ' ${_IFCFG}
    if (( $? == 0 )); then
        sed -i "s/gateway .*/gateway ${_GATEWAY}/" ${_IFCFG}
    else
        echo "gateway ${_GATEWAY}" >> ${_IFCFG}
    fi

    echo ">> Config dns-servers"
    grep -q 'dns-servers ' ${_IFCFG}
    if (( $? == 0 )); then
        sed -i "s/dns-servers .*/dns-servers ${_DNS1} ${_DNS2}/" ${_IFCFG}
    else
        echo "dns-servers ${_DNS1} ${_DNS2}" >> ${_IFCFG}
    fi
}

echo "== Modify hostname =="
[[ "${_HOSTNAME}" == "" ]] || {
    echo "${HOSTNAME}" > /etc/hostname
}

echo "== Disable SeLinux =="
which getenforce && setenforce 0
[[ -f "/etc/selinux/config" ]] && sed -i 's/^SELINUX=.*/SELINUX=disable/' /etc/selinux/config 

echo "== Disable Firewall =="
echo "${_OS}" | grep -qE 'centos' && { 
    systemctl stop firewalld
    systemctl disable firewalld
}
echo "${_OS}" | grep -qE 'ubuntu' && { 
    systemctl stop ufw 
    systemctl disable ufw
}

echo "== Reboot VM =="
echo "Reboot after 5 seconds"
sleep 5
reboot
