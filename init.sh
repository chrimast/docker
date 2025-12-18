#!/bin/bash
# VPS 初始化脚本 (Debian/Ubuntu)

# 1. 修改时区为上海
echo ">>> 设置时区为 Asia/Shanghai"
timedatectl set-timezone Asia/Shanghai

# 2. 设置虚拟内存 (Swap)，可输入大小，默认 2048 MB (2G)
read -p "请输入要设置的 Swap 大小 (MB，默认 2000): " SWAP_SIZE
SWAP_SIZE=${SWAP_SIZE:-2000}

echo ">>> 设置 ${SWAP_SIZE} MB Swap"
swapoff -a
dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

# 3. 开启 BBR + FQ 优化
echo ">>> 开启 BBR + FQ"
cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl -p

# 4. 编辑 /etc/gai.conf 开启 IPv4 优先
echo ">>> 设置 IPv4 优先"
sed -i 's/^#precedence ::ffff:0:0\/96  100/precedence ::ffff:0:0\/96  100/' /etc/gai.conf

# 5. 开启 root 登录并修改 root 密码
echo ">>> 开启 root 登录"
sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

echo ">>> 修改 root 密码"
echo "请输入新的 root 密码:"
passwd root

# 6. 修改 SSH 端口，默认 22
read -p "请输入新的 SSH 端口 (默认 22): " SSH_PORT
SSH_PORT=${SSH_PORT:-22}

echo ">>> 修改 SSH 端口为 ${SSH_PORT}"
sed -i "s/^#Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
sed -i "s/^Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
systemctl restart sshd

# 7. 检测防火墙并开放新 SSH 端口
echo ">>> 检测防火墙状态并开放端口 ${SSH_PORT}"

# 检查 ufw 是否启用
if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -q "Status: active"; then
        echo ">>> 检测到 ufw 已启用，开放端口 ${SSH_PORT}"
        ufw allow ${SSH_PORT}/tcp
    else
        echo ">>> ufw 未启用，不做操作"
    fi
fi

# 检查 iptables 是否有规则
if command -v iptables >/dev/null 2>&1; then
    IPTABLES_RULES=$(iptables -L INPUT -n)
    if [ -n "$IPTABLES_RULES" ] && ! echo "$IPTABLES_RULES" | grep -q "ACCEPT.*tcp.*dpt:${SSH_PORT}"; then
        echo ">>> 检测到 iptables 已启用，开放端口 ${SSH_PORT}"
        iptables -A INPUT -p tcp --dport ${SSH_PORT} -j ACCEPT
        # 保存规则
        if command -v netfilter-persistent >/dev/null 2>&1; then
            netfilter-persistent save
        elif command -v iptables-save >/dev/null 2>&1; then
            iptables-save > /etc/iptables/rules.v4
        fi
    else
        echo ">>> iptables 未启用或已存在规则，不做操作"
    fi
fi

echo ">>> 初始化完成，请重新登录 VPS 生效"
