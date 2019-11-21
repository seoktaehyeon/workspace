#!/bin/bash
## Usage
## ./cluster-exec-install.sh "192.168.1.1 192.168.1.2" "password"
##
set -ex

IPS=${1?"Please provide ip list"}
PASSWORD=${2?"Please provide cluster password"}
HOSTS="## Cluster Hosts Start"
SSH_ROOT="/root/.ssh"

function check_env
{
    which ssh
    which expect
    which ssh-keygen
    which ssh-copy-id
    return 0
}

function generate_ssh_key
{
    echo "Generate id_rsa and id_rsa.pub"
    ssh-keygen -t rsa -N '' -f ${SSH_ROOT}/id_rsa 
    return 0
}

function _copy_ssh_id
{
    _ip=${1?}
    _password=${2?}
    expect <<EOF
        set time 3
        spawn ssh-copy-id root@${_ip}
        expect {
            "*yes/no" { send "yes\r"; exp_continue }
            "*assword*" { send "${_password}\r" }
        }
        interact
        expect eof
EOF
     return 0
}

function copy_ssh_id
{
    for ip in ${IPS}
    do
        _copy_ssh_id ${ip} ${PASSWORD}
        scp ${SSH_ROOT}/id_rsa root@${ip}:${SSH_ROOT}/id_rsa
    done
    return 0
}

function update_etc_hosts
{
    for ip in ${IPS}
    do
        host=$(ssh root@${ip} 'echo $HOSTNAME')
        HOSTS="$HOSTS
$ip    $host"
    done
    HOSTS="$HOSTS
## Cluster Hosts End"
    for ip in ${IPS}
    do
        ssh root@${ip} "echo \"$HOSTS\" >> /etc/hosts"
    done
    return 0
}

function generate_cluster_exec
{
    temp_scripts='/tmp/cluster-exec'
    echo '#!/bin/bash' > ${temp_scripts}
    echo 'cmd=${1?}' >> ${temp_scripts}
    echo "start_line=\$(grep '## Cluster Hosts Start' -n /etc/hosts | awk -F ':' '{print \$1}')" >> ${temp_scripts}
    echo "end_line=\$(grep '## Cluster Hosts End' -n /etc/hosts | awk -F ':' '{print \$1}')" >> ${temp_scripts}
    echo "host_list=\$(sed -n \${start_line},\${end_line}p /etc/hosts | grep -v '##' | awk '{print \$2}')" >> ${temp_scripts}
    echo "for host in \${host_list}" >> ${temp_scripts}
    echo 'do' >> ${temp_scripts}
    echo '    echo "Executed Command In ${host} :"' >> ${temp_scripts}
    echo '    ssh root@${host} "$cmd"' >> ${temp_scripts}
    echo '    echo ""' >> ${temp_scripts}
    echo 'done' >> ${temp_scripts}
    chmod +x ${temp_scripts}
    for ip in ${IPS}
    do
        scp ${temp_scripts} root@${ip}:/usr/local/bin/
    done
    which cluster-exec
    cluster-exec "free -h"
    return 0
}

## Main
check_env
generate_ssh_key
copy_ssh_id
update_etc_hosts
generate_cluster_exec

