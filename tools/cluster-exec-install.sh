#!/bin/bash
# Author: v.stone@163.com

IP_LIST=""
ROOT_PASSWORD=""
SSH_ROOT="/root/.ssh"
SCRIPTS_VERSION="cluster-exec v1.0"

function help_doc
{
    cat <<EOF
Usage: $0 <options> <arguments>
Options:
    --ips       IP List.
                e.g.
                    192.168.1.100-103
                    192.168.1.100 192.168.1.101 192.168.1.102 192.168.1.103
    --password  Root Password
    --help      Print Help

Example:
    $0 --ips "192.168.1.100-103" --password "password"
    $0 --help
EOF
    exit 1
}

function log_note
{
    echo -e "\033[34;6m$@ \033[0m"
    return 0
}

function log_succeed
{
    echo -e "\033[32;6m[ SUCCEED ] $@ \n \033[0m"
    return 0
}

function log_error
{
    echo -e "\033[31;6m[ ERROR ] $@ \033[0m"
    exit 1
}

function check_env
{
    [[ "$(uname)" == "Linux" ]] || log_error "Only support Linux"
    [[ -z "${IP_LIST}" ]] && help_doc
    [[ -z "${ROOT_PASSWORD}" ]] && help_doc
    log_note "Start to check env"
    echo "${IP_LIST}" | grep -q '-' && {
        IP_PREFIX=$(echo "${IP_LIST}" | awk -F '.' '{print $1"."$2"."$3}')
        IP_START=$(echo "${IP_LIST}" | awk -F '.' '{print $4}' | awk -F '-' '{print $1}')
        IP_END=$(echo "${IP_LIST}" | awk -F '.' '{print $4}' | awk -F '-' '{print $2}')
        IP_LIST=""
        for ip_end in `seq ${IP_START} ${IP_END}`
        do
            IP_LIST="${IP_LIST} ${IP_PREFIX}.${ip_end}"
        done
    }
    for ip in ${IP_LIST}
    do
        ping -c 1 ${ip} || log_error "$ip cannot be ping"
    done
    which yum && PKG_INSTALL="yum install -y "
    which apt && PKG_INSTALL="apt install -y "
    for _cmd in ssh expect ssh-keygen ssh-copy-id
    do
        which ${_cmd} || ${PKG_INSTALL} ${_cmd}
        which ${_cmd} || log_error "$_cmd not found"
    done
    log_succeed "Checking complete"
    return 0
}

function generate_ssh_key
{
    log_note "Generate id_rsa and id_rsa.pub"
    [[ -f "${SSH_ROOT}/id_rsa" ]] && [[ -f "${SSH_ROOT}/id_rsa.pub" ]] && {
        log_succeed "ssh key is already in this machine"
        return 0
    }
    ssh-keygen -t rsa -N '' -f ${SSH_ROOT}/id_rsa || log_error "Generation failure"
    log_succeed "Generation complete"
    return 0
}

function _copy_ssh_id
{
    _ip=${1?}
    _password=${2?}
    expect <<EOF
        set timeout 3
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
    for ip in ${IP_LIST}
    do
        log_note "Copy id_rsa.pub into node ${ip}"
        _copy_ssh_id ${ip} ${ROOT_PASSWORD} || log_error "Failed to copy id_rsa.pub to node ${ip}"
        log_note "Copy id_rsa into node ${ip}"
        scp ${SSH_ROOT}/id_rsa root@${ip}:${SSH_ROOT}/id_rsa || log_error "Failed to copy id_rsa to node ${ip}"
    done
    log_succeed "Complete to config ssh"
    return 0
}

function update_etc_hosts
{
    log_note "Update /etc/hosts in all nodes"
    hosts_text="## Cluster Hosts Start"
    node_master="true"
    for ip in ${IP_LIST}
    do
        host=$(ssh root@${ip} 'echo $HOSTNAME') || log_error "Failed to get ${ip}'s hostname"
        if [[ "${node_master}" == "true" ]]; then
            hosts_text="$hosts_text
$ip    $host    # cluster-exec master"
            node_master="false"
        else
            hosts_text="$hosts_text
$ip    $host    # cluster-exec slave"
        fi
    done
    hosts_text="$hosts_text
## Cluster Hosts End"
    for ip in ${IP_LIST}
    do
        log_note "Append all nodes hosts into ${ip}"
        ssh root@${ip} "echo \"$hosts_text\" >> /etc/hosts" || log_error "ssh execution failure"
    done
    log_succeed "Complete to update all /etc/hosts files"
    return 0
}

function generate_cluster_exec
{
   log_note "Generate temp scripts of cluster-exec"
    temp_scripts='/tmp/cluster-exec'
    cat <<EOF > ${temp_scripts}
#!/bin/bash
node=\${1?}
cmd=\${2?}
master=\$(grep '# cluster-exec master' /etc/hosts | awk '{print \$1}')
slaves=\$(grep '# cluster-exec slave' /etc/hosts | awk '{print \$1}')
exec_nodes=""
if [[ "\${node}" == "all" ]]; then
    exec_nodes="\$master \$slaves"
elif [[ "\${node}" == "master" ]]; then
    exec_nodes="\$master"
elif [[ "\${node}" == "slave" ]]; then
    exec_nodes="\$slaves"
fi
for host in \${exec_nodes}
do
    echo -e "\nExecuted Command In \${host}:"
    ssh root@\${host} "\$cmd"
done
echo -e "\n"
EOF
    chmod +x ${temp_scripts}
    log_succeed "cluster-exec scripts generation complete"
    log_note "Copy cluster-exec into all nodes"
    for ip in ${IP_LIST}
    do
        log_note "scp to ${ip}"
        scp ${temp_scripts} root@${ip}:/usr/local/bin/ || log_error "scp failure"
    done
    log_succeed "Complete to copy cluster-exec"
    return 0
}

function _ssh_try
{
    _host=${1?}
    expect <<EOF
        set timeout 3
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
    which cluster-exec || log_error "cluster-exec not found"
    for ip in ${IP_LIST}
    do
        _host=$(grep ${ip} /etc/hosts | awk '{print $2}')
        _ssh_try ${_host} || log_error "Failed to ssh ${_host}"
    done
    log_note "Run cluster-exec 'free -h'"
    cluster-exec all "free -h" || log_error "Execute cluster-exec failure"
    log_succeed "cluster-exec works fine"
    return 0
}

## Main
eval set -- $(getopt -o "" -l ips:,password:,help --name "$0" -- "$@")
while (( $# != 0 ))
do
    case $1 in
        --ips)
            IP_LIST=$2
            [[ -z "${IP_LIST}" ]] && {
                log_error "option ips' value is empty"
                help_doc
            }
            shift 2
            ;;
        --password)
            ROOT_PASSWORD=$2
            [[ -z "${ROOT_PASSWORD}" ]] && {
                log_error "option password's value is empty"
                help_doc
            }
            shift 2
            ;;
        --help)
            help_doc
            ;;
        --)
            shift
            ;;

        *)
            help_doc
            exit 1
            ;;
    esac
done
log_note "${SCRIPTS_VERSION}"
check_env
generate_ssh_key
copy_ssh_id
update_etc_hosts
generate_cluster_exec
try_exec

