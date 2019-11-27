#!/bin/bash

HELP_DOC="

Usage:
$0 <ip_list> <ssh_password>

Example:
$0 \"192.168.1.1 192.168.1.2\" \"password\"
"

IPS=${1?$(echo -e "\033[31;40;1m [ ERROR ] \033[0m") "Please provide ip list, e.g. '192.168.1.1 192.168.1.2' $HELP_DOC"}
PASSWORD=${2?$(echo -e "\033[31;40;1m [ ERROR ] \033[0m") "Please provide cluster ssh password $HELP_DOC"}
HOSTS="## Cluster Hosts Start"
SSH_ROOT="/root/.ssh"

function log_note
{
    echo -e "\033[33;40;1m $@ \033[0m"
    return 0
}

function log_pass
{
    echo -e "\033[32;40;1m [ PASS ] \033[0m" $@ "\n"
    return 0
}

function log_fail
{
    echo -e "\033[31;40;1m [ FAIL ] \033[0m" $@
    exit 1
}

function check_env
{
    log_note "Start to check env"
    for _cmd in ssh expect ssh-keygen ssh-copy-id 
    do
        which $_cmd || log_fail "$_cmd not found"
    done
    log_pass "Checking complete"
    return 0
}

function generate_ssh_key
{
    log_note "Generate id_rsa and id_rsa.pub"
    ssh-keygen -t rsa -N '' -f ${SSH_ROOT}/id_rsa || log_fail "Generation failure"
    log_pass "Generation complete"
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
     echo ""
     return 0
}

function copy_ssh_id
{
    log_note "Start to config ssh"
    for ip in ${IPS}
    do
        log_note "Copy id_rsa.pub into node ${ip}"
        _copy_ssh_id ${ip} ${PASSWORD} || log_fail "Failed to copy id_rsa.pub to node ${ip}"
        log_note "Copy id_rsa into node ${ip}"
        scp ${SSH_ROOT}/id_rsa root@${ip}:${SSH_ROOT}/id_rsa || log_fail "Failed to copy id_rsa to node ${ip}"
    done
    log_pass "Complete"
    return 0
}

function update_etc_hosts
{
    log_note "Update /etc/hosts in all nodes"
    for ip in ${IPS}
    do
        host=$(ssh root@${ip} 'echo $HOSTNAME') || log_fail "Failed to get ${ip}'s hostname"
        HOSTS="$HOSTS
$ip    $host"
    done
    HOSTS="$HOSTS
## Cluster Hosts End"
    for ip in ${IPS}
    do
        log_note "Append all nodes hosts into ${ip}"
        ssh root@${ip} "echo \"$HOSTS\" >> /etc/hosts" || log_fail "ssh execution failure"
    done
    log_pass "Update complete"
    return 0
}

function generate_cluster_exec
{
    log_note "Generate temp scripts of cluster-exec"
    temp_scripts='/tmp/cluster-exec'
    echo '#!/bin/bash' > ${temp_scripts}
    echo 'cmd=${1?}' >> ${temp_scripts}
    echo "start_line=\$(grep '## Cluster Hosts Start' -n /etc/hosts | awk -F ':' '{print \$1}')" >> ${temp_scripts}
    echo "end_line=\$(grep '## Cluster Hosts End' -n /etc/hosts | awk -F ':' '{print \$1}')" >> ${temp_scripts}
    echo "host_list=\$(sed -n \${start_line},\${end_line}p /etc/hosts | grep -v '##' | awk '{print \$2}')" >> ${temp_scripts}
    echo "for host in \${host_list}" >> ${temp_scripts}
    echo 'do' >> ${temp_scripts}
    echo '    echo ""' >> ${temp_scripts}
    echo '    echo "Executed Command In ${host} :"' >> ${temp_scripts}
    echo '    ssh root@${host} "$cmd"' >> ${temp_scripts}
    echo '    echo ""' >> ${temp_scripts}
    echo 'done' >> ${temp_scripts}
    chmod +x ${temp_scripts}
    log_pass "Generation complete"
    log_note "Copy cluster-exec into all nodes"
    for ip in ${IPS}
    do
        log_note "scp to ${ip}"
        scp ${temp_scripts} root@${ip}:/usr/local/bin/ || log_fail "scp failure"
    done
    log_pass "Complete"
    return 0
}

function _ssh_try
{
    _host=${1?}
    expect <<EOF
        set time 3
        spawn ssh root@${_host}
        expect {
            "*yes/no" { send "yes\r"}
        }
        expect "*#"
        send "exit\r"
        interact
        expect eof
EOF
     echo ""
     return 0
}

function try_exec
{
    log_note "Try to run cluster-exec"
    which cluster-exec || log_fail "cluster-exec not found"
    for ip in $IPS
    do
        _host=$(grep ${ip} /etc/hosts | awk '{print $2}')
        _ssh_try ${_host} || log_fail "Failed to ssh ${_host}"
    done
    log_note "Run cluster-exec 'free -h'"
    cluster-exec "free -h" || log_fail "Execute cluster-exec failure"
    log_pass "cluster-exec works fine"
    return 0
}

## Main
check_env
generate_ssh_key
copy_ssh_id
update_etc_hosts
generate_cluster_exec
try_exec

