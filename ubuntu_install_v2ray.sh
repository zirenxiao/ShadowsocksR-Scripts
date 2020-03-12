#!/bin/bash
# v2ray Ubuntu系统一键安装脚本
# Author: hijk<https://www.hijk.pw>

echo "#############################################################"
echo "#         Ubuntu 16.04 TLS v2ray 带一键安装脚本              #"
echo "# 网址: https://www.hijk.pw                                 #"
echo "# 作者: hijk                                                #"
echo "#############################################################"
echo ""

red='\033[0;31m'
green="\033[0;32m"
plain='\033[0m'

function checkSystem()
{
    result=$(id | awk '{print $1}')
    if [ $result != "uid=0(root)" ]; then
        echo "请以root身份执行该脚本"
        exit 1
    fi

    res=`lsb_release -d | grep -i ubuntu`
    if [ "${res}" = "" ];then
        echo "系统不是Ubuntu"
        exit 1
    fi
    
    result=`lsb_release -d | grep -oE "[0-9.]+"`
    main=${result%%.*}
    if [ $main -lt 16 ]; then
        echo "不受支持的Ubuntu版本"
        exit 1
    fi
}

function getData()
{
    while true
    do
        read -p "请输入v2ray的端口[1-65535]:" port
        [ -z "$port" ] && port="21568"
        expr $port + 0 &>/dev/null
        if [ $? -eq 0 ]; then
            if [ $port -ge 1 ] && [ $port -le 65535 ]; then
                echo ""
                echo "端口号： $port"
                echo ""
                break
            else
                echo "输入错误，端口号为1-65535的数字"
            fi
        else
            echo "输入错误，端口号为1-65535的数字"
        fi
    done
}

function preinstall()
{
    sed -i 's/#ClientAliveInterval 0/ClientAliveInterval 60/' /etc/ssh/sshd_config
    systemctl restart sshd
    ret=`nginx -t`
    if [ "$?" != "0" ]; then
        echo "更新系统..."
        apt update && apt -y upgrade
    fi
    echo "安装必要软件"
    apt install -y telnet wget vim net-tools ntpdate unzip
    apt autoremove -y
}

function installV2ray()
{
    echo 安装v2ray...
    bash <(curl -L -s https://install.direct/go.sh)

    if [ ! -f /etc/v2ray/config.json ]; then
        echo "安装失败，请到 https://www.hijk.pw 网站反馈"
        exit 1
    fi

    sed -i -e "s/port\":.*[0-9]*,/port\": ${port},/" /etc/v2ray/config.json
    logsetting=`cat /etc/v2ray/config.json|grep loglevel`
    if [ "${logsetting}" = "" ]; then
        sed -i '1a\  "log": {\n    "loglevel": "info",\n    "access": "/var/log/v2ray/access.log",\n    "error": "/var/log/v2ray/error.log"\n  },' /etc/v2ray/config.json
    fi
    alterid=`shuf -i50-90 -n1`
    sed -i -e "s/alterId\":.*[0-9]*/alterId\": ${alterid}/" /etc/v2ray/config.json
    uid=`cat /etc/v2ray/config.json | grep id | cut -d: -f2 | tr -d \",' '`
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    ntpdate -u time.nist.gov
    systemctl enable v2ray && systemctl restart v2ray
    sleep 3
    res=`netstat -nltp | grep ${port} | grep v2ray`
    if [ "${res}" = "" ]; then
        echo "v2ray启动失败，请检查端口是否被占用！"
        exit 1
    fi
    echo "v2ray安装成功！"
}

function setFirewall()
{
    res=`ufw status | grep -i inactive`
    if [ "$res" = "" ];then
        ufw allow ${port}/tcp
        ufw allow ${port}/udp
    fi
}

function installBBR()
{
    result=$(lsmod | grep bbr)
    if [ "$result" != "" ]; then
        echo BBR模块已安装
        bbr=true
        echo "3" > /proc/sys/net/ipv4/tcp_fastopen
        echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
        return;
    fi

    echo 安装BBR模块...
    apt install -y --install-recommends linux-generic-hwe-16.04
    grub-set-default 0
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    echo "3" > /proc/sys/net/ipv4/tcp_fastopen
    echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
    bbr=false
}

function info()
{
    ip=`curl -s -4 icanhazip.com`
    port=`cat /etc/v2ray/config.json | grep port | cut -d: -f2 | tr -d \",' '`
    res=`netstat -nltp | grep ${port} | grep v2ray`
    [ -z "$res" ] && status="${red}已停止${plain}" || status="${green}正在运行${plain}"
    uid=`cat /etc/v2ray/config.json | grep id | cut -d: -f2 | tr -d \",' '`
    alterid=`cat /etc/v2ray/config.json | grep alterId | cut -d: -f2 | tr -d \",' '`
    res=`cat /etc/v2ray/config.json | grep network`
    [ -z "$res" ] && network="tcp" || network=`cat /etc/v2ray/config.json | grep network | cut -d: -f2 | tr -d \",' '`
    security="auto"
    
    echo ============================================
    echo -e " v2ray运行状态：${status}"
    echo -e " v2ray配置文件：${red}/etc/v2ray/config.json${plain}"
    echo ""
    echo -e "${red}v2ray配置信息：${plain}               "
    echo -e " IP(address):  ${red}${ip}${plain}"
    echo -e " 端口(port)：${red}${port}${plain}"
    echo -e " id(uuid)：${red}${uid}${plain}"
    echo -e " 额外id(alterid)： ${red}${alterid}${plain}"
    echo -e " 加密方式(security)： ${red}$security${plain}"
    echo -e " 传输协议(network)： ${red}${network}${plain}" 
    echo  
    echo ============================================
}

function bbrReboot()
{
    if [ "${bbr}" == "false" ]; then
        echo  
        echo  为使BBR模块生效，系统将在30秒后重启
        echo  
        echo -e "您可以按 ctrl + c 取消重启，稍后输入 ${red}reboot${plain} 重启系统"
        sleep 30
        reboot
    fi
}


function install()
{
    echo -n "系统版本:  "
    lsb_release -a

    checkSystem
    getData
    preinstall
    installBBR
    installV2ray
    setFirewall
    
    info
    bbrReboot
}

function uninstall()
{
    read -p "您确定真的要卸载v2ray吗？(y/n)" answer
    [ -z ${answer} ] && answer="n"

    if [ "${answer}" == "y" ] || [ "${answer}" == "Y" ]; then
        systemctl stop v2ray
        systemctl disable v2ray
        rm -rf /etc/v2ray/*
        rm -rf /usr/bin/v2ray/*
        rm -rf /var/log/v2ray/*
        rm -rf /etc/systemd/system/v2ray.service
        
        echo -e " ${red}卸载成功${plain}"
    fi
}

action=$1
[ -z $1 ] && action=install
case "$action" in
    install|uninstall|info)
        ${action}
        ;;
    *)
        echo "参数错误"
        echo "用法: `basename $0` [install|uninstall]"
        ;;
esac
