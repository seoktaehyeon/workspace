#!/bin/bash
# Author: v.stone@163.com
# Config hostname, network, selinux, iptable

_OS=''
_OS_RELEASE=$(cat /etc/*release)
echo "${_OS_RELEASE}" | grep -q CentOS && _OS='centos'
echo "${_OS_RELEASE}" | grep -q Ubuntu && _OS='ubuntu'
[[ "${_OS}" == "" ]] && {
    echo "Unknown OS"
    echo "${_OS_RELEASE}"
    exit 1
}

while true
do
    read -p "Host IP [No Default]: " _READ_IP
    [[ -z "${_READ_IP}" ]] || {
        _IP="${_READ_IP}"
        break
    }
done

_DEFAULT_NETMASK="255.255.0.0"
read -p "Netmask [${_DEFAULT_NETMASK}]: " _READ_NETMASK
if [[ -z "${_READ_NETMASK}" ]]; then
    _NETMASK="${_DEFAULT_NETMASK}"
else
    _NETMASK="${_READ_NETMASK}"
fi

_DEFAULT_GATEWAY=$(echo ${_IP} | awk -F '.' '{print $1"."$2".0.1"}')
read -p "Gateway [${_DEFAULT_GATEWAY}]: " _READ_GATEWAY
if [[ -z "${_READ_GATEWAY}" ]]; then
    _GATEWAY="${_DEFAULT_GATEWAY}"
else
    _GATEWAY="${_READ_GATEWAY}"
fi

_DEFAULT_DNS1="223.5.5.5"
read -p "DNS 1   [${_DEFAULT_DNS1}]: " _READ_DNS1
if [[ -z "${_READ_DNS1}" ]]; then
    _DNS1="${_DEFAULT_DNS1}"
else
    _DNS1="${_READ_DNS1}"
fi

#_DEFAULT_DNS2=""
read -p "DNS 2   [No Default]: " _READ_DNS2
#if [[ -z "${_READ_DNS2}" ]]; then
#    _DNS2="${_DEFAULT_DNS2}"
#else
#    _DNS2="${_DEFAULT_DNS2}"
#fi
_DNS2="${_READ_DNS2}"

_DEFAULT_HOSTNAME="${HOSTNAME}"
read -p "Hostname[${_DEFAULT_HOSTNAME}]: " _READ_HOSTNAME
if [[ -z "${_READ_HOSTNAME}" ]]; then
    _HOSTNAME="${_DEFAULT_HOSTNAME}"
else
    _HOSTNAME="${_READ_HOSTNAME}"
fi

ping -c 2 ${_IP}
(( $? == 0 )) && {
    echo "${_IP} has been used, need change another one"
    exit 1
}

echo "== Config network =="
if [[ "${_OS}" == "centos" ]]; then
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

    [[ -z "${_DNS2}" ]] || {
        echo ">> Config dns2"
        grep -q 'DNS2=' ${_IFCFG}
        if (( $? == 0 )); then
            sed -i "s/DNS2=.*/DNS2=${_DNS2}/" ${_IFCFG}
        else
            echo "DNS2=${_DNS2}" >> ${_IFCFG}
        fi
    }
elif [[ "${_OS}" == "ubuntu" ]]; then
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
fi

echo "== Modify hostname =="
echo "${_HOSTNAME}" > /etc/hostname

echo "== Disable SeLinux =="
which getenforce && setenforce 0
[[ -f "/etc/selinux/config" ]] && sed -i 's/^SELINUX=.*/SELINUX=disable/' /etc/selinux/config 

echo "== Disable Firewall =="
if [[ "${_OS}" == "centos" ]]; then
    systemctl stop firewalld
    systemctl disable firewalld
elif [[ "${_OS}" == "ubuntu" ]]; then
    systemctl stop ufw
    systemctl disable ufw
fi

echo "== Set Time Zone =="
which timedatectl && timedatectl set-timezone Asia/Shanghai

echo "== Reboot VM =="
echo "Reboot after 5 seconds"
sleep 5
reboot
