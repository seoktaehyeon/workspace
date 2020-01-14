#!/bin/bash
# Author: v.stone@163.com

function log_note
{
    echo -e "\033[34;40;1m $@ \033[0m"
    return 0
}

function log_succeed
{
    echo -e "\033[32;40;1m [ SUCCEED ] \033[0m" $@ "\n"
    return 0
}

function log_error
{
    echo -e "\033[31;40;1m [ ERROR ] \033[0m" $@
    exit 1
}

function install_docker
{
    which docker || {
        curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
    }
    systemctl restart docker
    systemctl enable docker
    return 0
}

function config_env
{
    swapoff -a
    echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
    which cluster-exec || log_error "Not found cluster-exec"
}

function install_kube
{
    which yum && {
        cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=http://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=http://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg
        http://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
        yum install -y kubectl kubelet kubeadm
    }
    which apt && {
        apt update
        apt install -y apt-transport-https curl
        curl -s https://gitee.com/vstone/workspace/raw/master/static/google-apt-key.gpg | sudo apt-key add -
        cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb http://mirrors.ustc.edu.cn/kubernetes/apt kubernetes-xenial main
EOF
        apt-get update
        apt install -y kubernetes kubelet kubeadm
    }
    systemctl restart kubelet
    systemctl enable kubelet
    return 0
}

function get_master_node
{
    node_ip=$(grep '## Cluster Hosts Start' /etc/hosts -A 1 | tail -1 | awk '{print $1}')
    [[ -z "${node_ip}" ]] && log_error "Failed to get master node IP"
    return 0
}

function config_kube_master
{
    docker info | grep -i 'cgroup driver' | grep -i 'systemd' || log_error 'Dont know how to do'

    for kube_yaml in kube-controller-manager kube-apiserver kube-scheduler etcd
    do
        [[ -f "/etc/kubernetes/manifests/${kube_yaml}.yaml" ]] && rm -rf /etc/kubernetes/manifests/${kube_yaml}.yaml
    done
    kubeadm init \
        --pod-network-cidr=10.244.0.0/16 \
        --image-repository=registry.cn-hangzhou.aliyuncs.com/google_containers || \
        log_error "Failed to init pod network"

    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config || log_error "Failed to copy kubernetes admin conf"
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    kubectl apply -f https://gitee.com/vstone/workspace/raw/master/static/kube-flannel.yml || \
        log_error "Failed to apply kube flannel yaml"
    log_succeed "Kube master configuration complete"
    return 0
}

function config_kube_slave
{
    master_node=$(grep '## Cluster Hosts Start' /etc/hosts -A 1 | tail -1 | awk '{print $1}')
    [[ -z "${master_node}" ]] && log_error "Failed to get master node IP"
    kube_join_cmd=$(kubeadm token create --print-join-command | grep 'kubeadm join')
    [[ -z "${kube_join_cmd}" ]] && log_error "Failed to get kube join command"
    cluster-exec "ifconfig | grep \"${master_node}\" || cd /tmp && wget https://gitee.com/vstone/workspace/raw/master/tools/k8s-install.sh"
    cluster-exec "ifconfig | grep \"${master_node}\" || chmod +x /tmp/k8s-install.sh && /tmp/k8s-install.sh prepare"
    cluster-exec "ifconfig | grep \"${master_node}\" || ${kube_join_cmd}"
    log_succeed "Kube slave configuration complete"
    kubectl get node || log_error "Failed to get node"
    return 0
}

# Main
node_type=${1-'master'}
install_docker
config_env
install_kube
[[ "${node_type}" != "prepare" ]] && {
    config_kube_master
    config_kube_slave
}

