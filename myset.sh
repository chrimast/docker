#!/bin/bash
set -o pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 运行此脚本"
    exit 1
fi

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
if [ -f "$SCRIPT_PATH" ]; then
    ln -sf "$SCRIPT_PATH" /usr/local/bin/o
fi

ip_address() {
    ipv4_address=$(curl -fsS --max-time 8 https://ipv4.ip.sb 2>/dev/null)
    ipv6_address=$(curl -fsS --max-time 3 https://ipv6.ip.sb 2>/dev/null)
}

confirm_action() {
    local prompt="${1:-确定继续吗？}"
    local answer=""
    read -r -p "$prompt (y/N): " answer
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

pause_after_action() {
    if [ -t 0 ]; then
        read -r -n 1 -s -p "按任意键继续..." _ || true
        printf '\n'
    fi
}

valid_port() {
    local port="${1:-}"
    [[ "$port" =~ ^[0-9]{1,5}$ ]] && (( 10#$port >= 1 && 10#$port <= 65535 ))
}

pkg_installed() {
    local package="${1:-}"
    [ -n "$package" ] || return 1
    if command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed' && return 0
    fi
    if command -v rpm >/dev/null 2>&1; then
        rpm -q "$package" >/dev/null 2>&1 && return 0
    fi
    if command -v apk >/dev/null 2>&1; then
        apk info -e "$package" >/dev/null 2>&1 && return 0
    fi
    command -v "$package" >/dev/null 2>&1
}

install() {
    if [ $# -eq 0 ]; then
        echo "未提供软件包参数!"
        return 1
    fi

    local need=()
    local package
    for package in "$@"; do
        if ! pkg_installed "$package"; then
            need+=("$package")
        fi
    done
    if [ ${#need[@]} -eq 0 ]; then
        return 0
    fi

    if command -v dnf >/dev/null 2>&1; then
        dnf install -y "${need[@]}"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y "${need[@]}"
    elif command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${need[@]}"
    elif command -v apk >/dev/null 2>&1; then
        apk add "${need[@]}"
    else
        echo "未知的包管理器!"
        return 1
    fi
}

install_dependency() {
    clear
    install wget socat unzip tar
}

remove() {
    if [ $# -eq 0 ]; then
        echo "未提供软件包参数!"
        return 1
    fi

    if command -v dnf >/dev/null 2>&1; then
        dnf remove -y "$@"
    elif command -v yum >/dev/null 2>&1; then
        yum remove -y "$@"
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get purge -y "$@"
    elif command -v apk >/dev/null 2>&1; then
        apk del "$@"
    else
        echo "未知的包管理器!"
        return 1
    fi
}

break_end() {
    echo -e "\033[0;32m操作完成\033[0m"
    echo "按任意键继续..."
    read -n 1 -s -r -p ""
    echo ""
    clear
}

ssh_listen_port() {
    local port
    port=$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}')
    if [ -z "$port" ]; then
        port=$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/{print $2; exit}' /etc/ssh/sshd_config 2>/dev/null)
    fi
    echo "${port:-22}"
}

sysctl_set_file() {
    local file="$1"
    shift
    mkdir -p /etc/sysctl.d
    printf '%s\n' "$@" > "$file"
    sysctl -p "$file" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1 || true
}

current_timezone() {
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl show --property=Timezone --value 2>/dev/null && return 0
    fi
    if [ -L /etc/localtime ]; then
        readlink /etc/localtime | sed 's|.*/zoneinfo/||'
        return 0
    fi
    cat /etc/timezone 2>/dev/null || echo "unknown"
}

set_timezone() {
    local tz="$1"
    if [ ! -f "/usr/share/zoneinfo/$tz" ]; then
        echo "时区文件不存在: $tz"
        return 1
    fi
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl set-timezone "$tz"
    else
        ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
        echo "$tz" > /etc/timezone 2>/dev/null || true
    fi
    echo "时区已设置为 $tz"
}

apt_source_files() {
    local files=()
    [ -f /etc/apt/sources.list ] && files+=(/etc/apt/sources.list)
    local f
    for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [ -f "$f" ] && files+=("$f")
    done
    printf '%s\n' "${files[@]}"
}

rewrite_apt_mirror() {
    local from="${1%/}"
    local to="${2%/}"
    local file
    [ -n "$from" ] && [ -n "$to" ] && [ "$from" != "$to" ] || return 0
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        sed -i "s|${from}|${to}|g" "$file"
    done < <(apt_source_files)
}

install_add_docker() {
    if [ -f "/etc/alpine-release" ]; then
        apk update
        apk add docker docker-cli-compose || apk add docker docker-compose
        rc-update add docker default
        service docker start
    else
        curl -fsSL https://get.docker.com | sh
        if [ -x /usr/libexec/docker/cli-plugins/docker-compose ]; then
            ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
        fi
        systemctl start docker
        systemctl enable docker
    fi
    sleep 2
}

install_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        install_add_docker
    else
        echo "Docker 已经安装"
    fi
}

iptables_open() {
    echo "警告: 将清空 iptables/ip6tables 规则，并把默认策略改为 ACCEPT。"
    if ! confirm_action "确认清空当前防火墙规则"; then
        echo "已取消"
        return 1
    fi
    iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT && iptables -F || return 1
    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -P INPUT ACCEPT && ip6tables -P FORWARD ACCEPT && ip6tables -P OUTPUT ACCEPT && ip6tables -F || true
    fi
}

add_swap() {
    if ! [[ "${new_swap:-}" =~ ^[1-9][0-9]*$ ]] || (( 10#$new_swap > 1048576 )); then
        echo "无效大小；请输入 1-1048576 MB"
        return 1
    fi
    if ! confirm_action "创建 ${new_swap}MB swap；成功后替换 /swapfile，现有磁盘 swap 分区不变"; then
        echo "已取消"
        return 1
    fi

    local tmp_swap="/swapfile.new.$$"
    local fstab_tmp
    fstab_tmp=$(mktemp /etc/fstab.XXXXXX) || return 1

    if command -v fallocate >/dev/null 2>&1; then
        fallocate -l "${new_swap}M" "$tmp_swap" 2>/dev/null || rm -f "$tmp_swap"
    fi
    if [ ! -f "$tmp_swap" ]; then
        dd if=/dev/zero of="$tmp_swap" bs=1M count="$new_swap" status=none || {
            rm -f "$tmp_swap" "$fstab_tmp"
            return 1
        }
    fi
    chmod 600 "$tmp_swap" || { rm -f "$tmp_swap" "$fstab_tmp"; return 1; }
    mkswap "$tmp_swap" >/dev/null || { rm -f "$tmp_swap" "$fstab_tmp"; return 1; }
    local old_swap_backup=""
    if [ -e /swapfile ]; then
        old_swap_backup="/swapfile.backup.$$"
        if swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq /swapfile; then
            swapoff /swapfile || { rm -f "$tmp_swap" "$fstab_tmp"; echo "无法停用旧 swap，未修改"; return 1; }
        fi
        mv /swapfile "$old_swap_backup" || { rm -f "$tmp_swap" "$fstab_tmp"; echo "无法备份旧 swap，未修改"; return 1; }
    fi
    if ! mv "$tmp_swap" /swapfile || ! mkswap /swapfile >/dev/null || ! swapon /swapfile; then
        echo "新 /swapfile 启用失败，尝试恢复旧 swap"
        swapoff /swapfile 2>/dev/null || true
        rm -f /swapfile
        if [ -n "$old_swap_backup" ]; then mv "$old_swap_backup" /swapfile; swapon /swapfile 2>/dev/null || true; fi
        rm -f "$fstab_tmp"
        return 1
    fi
    if [ -n "$old_swap_backup" ]; then rm -f "$old_swap_backup"; fi

    if [ -f /etc/fstab ]; then
        grep -vE '^[[:space:]]*/swapfile[[:space:]]' /etc/fstab > "$fstab_tmp"
        printf '%s\n' '/swapfile swap swap defaults 0 0' >> "$fstab_tmp"
        cat "$fstab_tmp" > /etc/fstab
    fi
    rm -f "$fstab_tmp"

    if [ -f /etc/alpine-release ]; then
        mkdir -p /etc/local.d
        printf '%s\n' 'swapon /swapfile' > /etc/local.d/swap.start
        chmod +x /etc/local.d/swap.start
        rc-update add local >/dev/null 2>&1 || true
    fi
    echo "虚拟内存大小已调整为 ${new_swap}MB（仅管理 /swapfile，未改动磁盘 swap 分区）"
}

docker_app() {
    if docker inspect "$docker_name" &>/dev/null; then
        clear
        echo "$docker_name 已安装，访问地址: "
        ip_address
        echo "http://${ipv4_address}:$docker_port"
        echo ""
        echo "应用操作"
        echo "------------------------"
        echo "1. 更新应用             2. 卸载应用"
        echo "------------------------"
        echo "0. 返回上一级选单"
        echo "------------------------"
        read -p "请输入你的选择: " sub_choice

        case $sub_choice in
            1)
                clear
                docker rm -f "$docker_name"
                docker rmi -f "$docker_img"
                eval "$docker_rum"
                clear
                echo "$docker_name 已经安装完成"
                echo "------------------------"
                ip_address
                echo "您可以使用以下地址访问:"
                echo "http://${ipv4_address}:$docker_port"
                eval "$docker_use"
                eval "$docker_passwd"
                ;;
            2)
                clear
                echo "此操作会删除容器 $docker_name、镜像 $docker_img 及数据目录 /home/docker/$docker_name。"
                if ! confirm_action "确认卸载并删除该数据目录"; then
                    echo "已取消"
                    continue
                fi
                docker rm -f "$docker_name" 2>/dev/null || true
                docker rmi -f "$docker_img" 2>/dev/null || true
                rm -rf -- "/home/docker/$docker_name"
                echo "应用已卸载"
                ;;
            0|*)
                ;;
        esac
    else
        clear
        echo "安装提示"
        echo "$docker_describe"
        echo "$docker_url"
        echo ""
        read -p "确定安装吗？(Y/N): " choice
        case "$choice" in
            [Yy])
                clear
                install_docker
                eval "$docker_rum"
                clear
                echo "$docker_name 已经安装完成"
                echo "------------------------"
                ip_address
                echo "您可以使用以下地址访问:"
                echo "http://${ipv4_address}:$docker_port"
                eval "$docker_use"
                eval "$docker_passwd"
                ;;
            *)
                ;;
        esac
    fi
}

cluster_python3() {
    mkdir -p "$HOME/cluster"
    cd "$HOME/cluster/" || return 1
    curl -fsS -O "https://raw.githubusercontent.com/kejilion/python-for-vps/main/cluster/${py_task}"
    python3 "$HOME/cluster/$py_task"
}

tmux_run() {
    if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        tmux new -s "$SESSION_NAME"
    else
        tmux attach-session -t "$SESSION_NAME"
    fi
}

server_reboot() {
    read -p $'\e[33m现在重启服务器吗？(Y/N): \e[0m' rboot
    case "$rboot" in
        [Yy])
            echo "已重启"
            reboot
            ;;
        [Nn])
            echo "已取消"
            ;;
        *)
            echo "无效的选择，请输入 Y 或 N。"
            ;;
    esac
}

while true; do
clear

echo -e "\033[96m一键脚本工具 v1.1.3 （支持Ubuntu/Debian/CentOS/Alpine系统）\033[0m"
echo -e "\033[96m-输入\033[93m字母【o】\033[96m可快速启动此脚本-\033[0m"
echo "------------------------"
echo "1. 系统信息"
echo "2. 系统更新"
echo "3. 系统清理"
echo "4. 常用工具 ▶"
echo "5. BBR管理 ▶"
echo "6. Docker管理 ▶ "
echo "7. WARP管理 ▶ "
echo "9. 甲骨文云脚本合集 ▶ "
echo "10. 备份与还原"
echo "12. 我的工作区 ▶ "
echo "13. 系统工具 ▶ "
echo "------------------------"
echo "99. 重启服务器"
echo "------------------------"
echo "0. 退出脚本"
echo "------------------------"
read -p "请输入你的选择: " choice

case $choice in
  1)
    clear
    # 函数: 获取IPv4和IPv6地址
    ip_address

    if [ "$(uname -m)" == "x86_64" ]; then
      cpu_info=$(cat /proc/cpuinfo | grep 'model name' | uniq | sed -e 's/model name[[:space:]]*: //')
    else
      cpu_info=$(lscpu | grep 'BIOS Model name' | awk -F': ' '{print $2}' | sed 's/^[ \t]*//')
    fi

    if [ -f /etc/alpine-release ]; then
        # Alpine Linux 使用以下命令获取 CPU 使用率
        cpu_usage_percent=$(top -bn1 | grep '^CPU' | awk '{print " "$4}' | cut -c 1-2)
    else
        # 其他系统使用以下命令获取 CPU 使用率
        cpu_usage_percent=$(top -bn1 | grep "Cpu(s)" | awk '{print " "$2}')
    fi


    cpu_cores=$(nproc)

    mem_info=$(free -b | awk 'NR==2{printf "%.2f/%.2f MB (%.2f%%)", $3/1024/1024, $2/1024/1024, $3*100/$2}')

    disk_info=$(df -h | awk '$NF=="/"{printf "%s/%s (%s)", $3, $2, $5}')

    ipinfo_json=$(curl -fsS --max-time 8 https://ipinfo.io/json 2>/dev/null)
    country=$(printf '%s' "$ipinfo_json" | awk -F'"' '/"country"/{print $4; exit}')
    city=$(printf '%s' "$ipinfo_json" | awk -F'"' '/"city"/{print $4; exit}')
    isp_info=$(printf '%s' "$ipinfo_json" | awk -F'"' '/"org"/{print $4; exit}')

    cpu_arch=$(uname -m)

    hostname=$(hostname)

    kernel_version=$(uname -r)

    congestion_algorithm=$(sysctl -n net.ipv4.tcp_congestion_control)
    queue_algorithm=$(sysctl -n net.core.default_qdisc)

    # 尝试使用 lsb_release 获取系统信息
    os_info=$(lsb_release -ds 2>/dev/null)

    # 如果 lsb_release 命令失败，则尝试其他方法
    if [ -z "$os_info" ]; then
      # 检查常见的发行文件
      if [ -f "/etc/os-release" ]; then
        os_info=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release)
      elif [ -f "/etc/debian_version" ]; then
        os_info="Debian $(cat /etc/debian_version)"
      elif [ -f "/etc/redhat-release" ]; then
        os_info=$(cat /etc/redhat-release)
      else
        os_info="Unknown"
      fi
    fi

    output=$(awk 'BEGIN { rx_total = 0; tx_total = 0 }
        NR > 2 { rx_total += $2; tx_total += $10 }
        END {
            rx_units = "Bytes";
            tx_units = "Bytes";
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "KB"; }
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "MB"; }
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "GB"; }

            if (tx_total > 1024) { tx_total /= 1024; tx_units = "KB"; }
            if (tx_total > 1024) { tx_total /= 1024; tx_units = "MB"; }
            if (tx_total > 1024) { tx_total /= 1024; tx_units = "GB"; }

            printf("总接收: %.2f %s\n总发送: %.2f %s\n", rx_total, rx_units, tx_total, tx_units);
        }' /proc/net/dev)


    current_time=$(date "+%Y-%m-%d %H:%M")


    swap_used=$(free -m | awk 'NR==3{print $3}')
    swap_total=$(free -m | awk 'NR==3{print $2}')

    if [ "$swap_total" -eq 0 ]; then
        swap_percentage=0
    else
        swap_percentage=$((swap_used * 100 / swap_total))
    fi

    swap_info="${swap_used}MB/${swap_total}MB (${swap_percentage}%)"

    runtime=$(cat /proc/uptime | awk -F. '{run_days=int($1 / 86400);run_hours=int(($1 % 86400) / 3600);run_minutes=int(($1 % 3600) / 60); if (run_days > 0) printf("%d天 ", run_days); if (run_hours > 0) printf("%d时 ", run_hours); printf("%d分\n", run_minutes)}')

    echo ""
    echo "系统信息查询"
    echo "------------------------"
    echo "主机名: $hostname"
    echo "运营商: $isp_info"
    echo "------------------------"
    echo "系统版本: $os_info"
    echo "Linux版本: $kernel_version"
    echo "------------------------"
    echo "CPU架构: $cpu_arch"
    echo "CPU型号: $cpu_info"
    echo "CPU核心数: $cpu_cores"
    echo "------------------------"
    echo "CPU占用: $cpu_usage_percent%"
    echo "物理内存: $mem_info"
    echo "虚拟内存: $swap_info"
    echo "硬盘占用: $disk_info"
    echo "------------------------"
    echo "$output"
    echo "------------------------"
    echo "网络拥堵算法: $congestion_algorithm $queue_algorithm"
    echo "------------------------"
    echo "公网IPv4地址: $ipv4_address"
    echo "公网IPv6地址: $ipv6_address"
    echo "------------------------"
    echo "地理位置: $country $city"
    echo "系统时间: $current_time"
    echo "------------------------"
    echo "系统运行时长: $runtime"
    echo

    ;;

  2)
    clear

    # Update system on Debian-based systems
    if [ -f "/etc/debian_version" ]; then
        apt update -y && DEBIAN_FRONTEND=noninteractive apt full-upgrade -y
    fi

    # Update system on Red Hat-based systems
    if [ -f "/etc/redhat-release" ]; then
        yum -y update
    fi

    # Update system on Alpine Linux
    if [ -f "/etc/alpine-release" ]; then
        apk update && apk upgrade
    fi


    ;;

  3)
    clear
    clean_debian() {
        apt-get autoremove --purge -y
        apt-get clean
        apt-get autoclean -y
        local residual_packages=()
        mapfile -t residual_packages < <(dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\\n' 2>/dev/null | awk '$1 == "rc" {print $2}')
        if [ "${#residual_packages[@]}" -gt 0 ]; then
            apt-get purge -y "${residual_packages[@]}"
        fi
        journalctl --rotate
        journalctl --vacuum-time=7d
        echo "已保留最近 7 天日志。旧内核未自动卸载，请手动确认后再删。"
    }

    clean_redhat() {
        dnf autoremove -y 2>/dev/null || yum autoremove -y 2>/dev/null || true
        dnf clean all 2>/dev/null || yum clean all
        journalctl --rotate
        journalctl --vacuum-time=7d
        echo "已保留最近 7 天日志。旧内核未自动卸载，请手动确认后再删。"
    }

    clean_alpine() {
        apk cache clean
        rm -f /var/cache/apk/*.apk
        apk info --orphaned 2>/dev/null || true
        find /var/log -type f \( -name '*.gz' -o -name '*.old' \) -delete
        echo "仅清理缓存和轮转日志；未自动卸载孤儿包。"
    }

    # Main script
    if [ -f "/etc/debian_version" ]; then
        # Debian-based systems
        clean_debian
    elif [ -f "/etc/redhat-release" ]; then
        # Red Hat-based systems
        clean_redhat
    elif [ -f "/etc/alpine-release" ]; then
        # Alpine Linux
        clean_alpine
    fi

    ;;

  4)
  while true; do
      clear
      echo "▶ 安装常用工具"
      echo "------------------------"
      echo "4. socat 通信连接工具 （申请域名证书必备）"
      echo "5. htop 系统监控工具"
      echo "6. iftop 网络流量监控工具"
      echo "9. tmux 多路后台运行工具"
      echo "10. ffmpeg 视频编码直播推流工具"
      echo "11. btop 现代化监控工具"
      echo "------------------------"
      echo "41. 安装指定工具"
      echo "42. 卸载指定工具"
      echo "------------------------"
      echo "0. 返回主菜单"
      echo "------------------------"
      read -p "请输入你的选择: " sub_choice

      case $sub_choice in
            4)
              clear
              install socat
              clear
              echo "工具已安装，使用方法如下："
              socat -h
              ;;
            5)
              clear
              install htop
              clear
              htop
              ;;
            6)
              clear
              install iftop
              clear
              iftop
              ;;
            9)
              clear
              install tmux
              clear
              echo "工具已安装，使用方法如下："
              tmux --help
              ;;
            10)
              clear
              install ffmpeg
              clear
              echo "工具已安装，使用方法如下："
              ffmpeg --help
              ;;

            11)
              clear
              install btop
              clear
              btop
              ;;
          41)
              clear
              read -r -p "请输入安装包名（空格分隔，例如 wget curl htop）: " -a package_args
              if [ "${#package_args[@]}" -gt 0 ]; then
                  install "${package_args[@]}"
              else
                  echo "未提供包名，已取消"
              fi
              ;;
          42)
              clear
              read -r -p "请输入卸载包名（空格分隔，例如 htop tmux）: " -a package_args
              if [ "${#package_args[@]}" -gt 0 ] && confirm_action "确认卸载: ${package_args[*]}"; then
                  remove "${package_args[@]}"
              else
                  echo "未提供包名或已取消"
              fi
              ;;

          99)
              clear
              server_reboot
              ;;
          0)
              break
              ;;

          *)
              echo "无效的输入!"
              ;;
      esac
  done

    ;;

  5)
    clear
        while true; do
              clear
              congestion_algorithm=$(sysctl -n net.ipv4.tcp_congestion_control)
              queue_algorithm=$(sysctl -n net.core.default_qdisc)
              echo "当前TCP阻塞算法: $congestion_algorithm $queue_algorithm"
              echo "------------------------"
              echo "如需开启BBR3请选择 系统工具 单独安装"
              echo "------------------------"
              read -p "是否开启原版BBR（Y/N） " sub_choice

              case $sub_choice in
                  [Yy])
                    sysctl_set_file /etc/sysctl.d/99-bbr.conf \
                        "net.core.default_qdisc=fq" \
                        "net.ipv4.tcp_congestion_control=bbr" \
                        "net.ipv4.tcp_syncookies=1" \
                        "net.ipv4.tcp_tw_reuse=1" \
                        "net.ipv4.tcp_fin_timeout=30" \
                        "net.ipv4.tcp_timestamps=1"
                    sysctl -w net.core.default_qdisc=fq
                    sysctl -w net.ipv4.tcp_congestion_control=bbr
                    lsmod | grep bbr || echo "bbr 模块未加载，重启后再查"
                    read -p "操作完成，按任意键退回..." -n 1 -s
                    break  # 退出循环
                      ;;

                  [Nn])
                      break  # 跳出循环，退出菜单
                      ;;

                  *)
                      echo "无效的选择，请输入 Y 或 N。"
                      ;;

              esac
        done
    ;;

  6)
    while true; do
      clear
      echo "▶ Docker管理器"
      echo "------------------------"
      echo "1. 安装更新Docker环境"
      echo "------------------------"
      echo "2. 查看 Docker 全局状态"
      echo "------------------------"
      echo "3. Docker 容器管理 ▶"
      echo "4. Docker 镜像管理 ▶"
      echo "5. Docker 网络管理 ▶"
      echo "6. Docker 卷管理 ▶"
      echo "------------------------"
      echo "7. 清理无用的docker容器和镜像网络数据卷"
      echo "------------------------"
      echo "8. 卸载 Docker 环境"
      echo "------------------------"
      echo "0. 返回主菜单"
      echo "------------------------"
      read -p "请输入你的选择: " sub_choice

      case $sub_choice in
          1)
            clear
            install_add_docker

              ;;
          2)
              clear
              echo "Docker 版本"
              docker --version
              docker-compose --version
              echo ""
              echo "Docker 镜像列表"
              docker image ls
              echo ""
              echo "Docker 容器列表"
              docker ps -a
              echo ""
              echo "Docker 卷列表"
              docker volume ls
              echo ""
              echo "Docker 网络列表"
              docker network ls
              echo ""

              ;;
          3)
              while true; do
                  clear
                  echo "Docker容器列表"
                  docker ps -a
                  echo ""
                  echo "容器操作"
                  echo "------------------------"
                  echo "1. 创建新的容器"
                  echo "------------------------"
                  echo "2. 启动指定容器             6. 启动所有容器"
                  echo "3. 停止指定容器             7. 暂停所有容器"
                  echo "4. 删除指定容器             8. 删除所有容器"
                  echo "5. 重启指定容器             9. 重启所有容器"
                  echo "------------------------"
                  echo "11. 进入指定容器           12. 查看容器日志           13. 查看容器网络"
                  echo "------------------------"
                  echo "0. 返回上一级选单"
                  echo "------------------------"
                  read -p "请输入你的选择: " sub_choice

                  case $sub_choice in
                      1)
                          read -r -p "请输入 docker run 参数（不要输入 docker 命令）: " -a docker_args
                          if [ "${#docker_args[@]}" -eq 0 ] || [ "${docker_args[0]}" != "run" ]; then
                              echo "仅接受以 run 开头的 docker run 参数；取消本次操作。"
                          elif confirm_action "将执行 docker ${docker_args[*]}"; then
                              docker "${docker_args[@]}"
                          else
                              echo "已取消"
                          fi
                          ;;

                      2)
                          read -p "请输入容器名: " dockername
                          docker start "$dockername"
                          ;;
                      3)
                          read -p "请输入容器名: " dockername
                          docker stop "$dockername"
                          ;;
                      4)
                          read -r -p "请输入容器名: " dockername
                          if [ -z "$dockername" ]; then
                              echo "容器名不能为空"
                          elif docker inspect "$dockername" >/dev/null 2>&1 && confirm_action "强制删除容器 $dockername"; then
                              docker rm -f "$dockername"
                          else
                              echo "容器不存在或已取消"
                          fi
                          ;;
                      5)
                          read -p "请输入容器名: " dockername
                          docker restart "$dockername"
                          ;;
                      6)
                          mapfile -t docker_targets < <(docker ps -aq)
                          if [ "${#docker_targets[@]}" -gt 0 ]; then
                              docker start "${docker_targets[@]}"
                          else
                              echo "没有容器"
                          fi
                          ;;
                      7)
                          mapfile -t docker_targets < <(docker ps -q)
                          if [ "${#docker_targets[@]}" -gt 0 ]; then
                              docker stop "${docker_targets[@]}"
                          else
                              echo "没有运行中的容器"
                          fi
                          ;;
                      8)
                          mapfile -t docker_targets < <(docker ps -aq)
                          if [ "${#docker_targets[@]}" -eq 0 ]; then
                              echo "没有容器"
                          else
                              printf '将删除以下容器：\n%s\n' "${docker_targets[@]}"
                              read -r -p "输入 DELETE 确认强制删除全部容器: " delete_confirm
                              if [ "$delete_confirm" = "DELETE" ]; then
                                  docker rm -f "${docker_targets[@]}"
                              else
                                  echo "已取消"
                              fi
                          fi
                          ;;
                      9)
                          mapfile -t docker_targets < <(docker ps -q)
                          if [ "${#docker_targets[@]}" -gt 0 ]; then
                              docker restart "${docker_targets[@]}"
                          else
                              echo "没有运行中的容器"
                          fi
                          ;;
                      11)
                          read -p "请输入容器名: " dockername
                          docker exec -it "$dockername" /bin/sh
                          break_end
                          ;;
                      12)
                          read -p "请输入容器名: " dockername
                          docker logs "$dockername"
                          break_end
                          ;;
                      13)
                          echo ""
                          container_ids=$(docker ps -q)

                          echo "------------------------------------------------------------"
                          printf "%-25s %-25s %-25s\n" "容器名称" "网络名称" "IP地址"

                          for container_id in $container_ids; do
                              container_info=$(docker inspect --format '{{ .Name }}{{ range $network, $config := .NetworkSettings.Networks }} {{ $network }} {{ $config.IPAddress }}{{ end }}' "$container_id")

                              container_name=$(echo "$container_info" | awk '{print $1}')
                              network_info=$(echo "$container_info" | cut -d' ' -f2-)

                              while IFS= read -r line; do
                                  network_name=$(echo "$line" | awk '{print $1}')
                                  ip_address=$(echo "$line" | awk '{print $2}')

                                  printf "%-20s %-20s %-15s\n" "$container_name" "$network_name" "$ip_address"
                              done <<< "$network_info"
                          done

                          break_end
                          ;;

                      0)
                          break  # 跳出循环，退出菜单
                          ;;

                      *)
                          echo "无效的选择，请重新输入。"
                          ;;
                  esac
              done
              ;;
          4)
              while true; do
                  clear
                  echo "Docker镜像列表"
                  docker image ls
                  echo ""
                  echo "镜像操作"
                  echo "------------------------"
                  echo "1. 获取指定镜像             3. 删除指定镜像"
                  echo "2. 更新指定镜像             4. 删除所有镜像"
                  echo "------------------------"
                  echo "0. 返回上一级选单"
                  echo "------------------------"
                  read -p "请输入你的选择: " sub_choice

                  case $sub_choice in
                      1)
                          read -p "请输入镜像名: " dockername
                          docker pull "$dockername"
                          ;;
                      2)
                          read -p "请输入镜像名: " dockername
                          docker pull "$dockername"
                          ;;
                      3)
                          read -p "请输入镜像名: " dockername
                          docker rmi -f "$dockername"
                          ;;
                      4)
                          mapfile -t image_targets < <(docker images -q | sort -u)
                          if [ "${#image_targets[@]}" -eq 0 ]; then
                              echo "没有镜像"
                          else
                              printf '将删除以下镜像 ID：\n%s\n' "${image_targets[@]}"
                              read -r -p "输入 DELETE 确认删除全部镜像: " delete_confirm
                              if [ "$delete_confirm" = "DELETE" ]; then
                                  docker rmi -f "${image_targets[@]}"
                              else
                                  echo "已取消"
                              fi
                          fi
                          ;;
                      0)
                          break  # 跳出循环，退出菜单
                          ;;

                      *)
                          echo "无效的选择，请重新输入。"
                          ;;
                  esac
              done
              ;;

          5)
              while true; do
                  clear
                  echo "Docker网络列表"
                  echo "------------------------------------------------------------"
                  docker network ls
                  echo ""

                  echo "------------------------------------------------------------"
                  container_ids=$(docker ps -q)
                  printf "%-25s %-25s %-25s\n" "容器名称" "网络名称" "IP地址"

                  for container_id in $container_ids; do
                      container_info=$(docker inspect --format '{{ .Name }}{{ range $network, $config := .NetworkSettings.Networks }} {{ $network }} {{ $config.IPAddress }}{{ end }}' "$container_id")

                      container_name=$(echo "$container_info" | awk '{print $1}')
                      network_info=$(echo "$container_info" | cut -d' ' -f2-)

                      while IFS= read -r line; do
                          network_name=$(echo "$line" | awk '{print $1}')
                          ip_address=$(echo "$line" | awk '{print $2}')

                          printf "%-20s %-20s %-15s\n" "$container_name" "$network_name" "$ip_address"
                      done <<< "$network_info"
                  done

                  echo ""
                  echo "网络操作"
                  echo "------------------------"
                  echo "1. 创建网络"
                  echo "2. 加入网络"
                  echo "3. 退出网络"
                  echo "4. 删除网络"
                  echo "------------------------"
                  echo "0. 返回上一级选单"
                  echo "------------------------"
                  read -p "请输入你的选择: " sub_choice

                  case $sub_choice in
                      1)
                          read -p "设置新网络名: " dockernetwork
                          docker network create "$dockernetwork"
                          ;;
                      2)
                          read -p "加入网络名: " dockernetwork
                          read -p "那些容器加入该网络: " dockername
                          docker network connect "$dockernetwork" "$dockername"
                          echo ""
                          ;;
                      3)
                          read -p "退出网络名: " dockernetwork
                          read -p "那些容器退出该网络: " dockername
                          docker network disconnect "$dockernetwork" "$dockername"
                          echo ""
                          ;;

                      4)
                          read -r -p "请输入要删除的网络名: " dockernetwork
                          if [ -z "$dockernetwork" ]; then
                              echo "网络名不能为空"
                          elif docker network inspect "$dockernetwork" >/dev/null 2>&1 && confirm_action "确认删除 Docker 网络 $dockernetwork"; then
                              docker network rm "$dockernetwork"
                          else
                              echo "网络不存在或已取消"
                          fi
                          ;;
                      0)
                          break  # 跳出循环，退出菜单
                          ;;

                      *)
                          echo "无效的选择，请重新输入。"
                          ;;
                  esac
              done
              ;;

          6)
              while true; do
                  clear
                  echo "Docker卷列表"
                  docker volume ls
                  echo ""
                  echo "卷操作"
                  echo "------------------------"
                  echo "1. 创建新卷"
                  echo "2. 删除卷"
                  echo "------------------------"
                  echo "0. 返回上一级选单"
                  echo "------------------------"
                  read -p "请输入你的选择: " sub_choice

                  case $sub_choice in
                      1)
                          read -p "设置新卷名: " dockerjuan
                          docker volume create "$dockerjuan"

                          ;;
                      2)
                          read -r -p "输入删除卷名: " dockerjuan
                          if [ -z "$dockerjuan" ]; then
                              echo "卷名不能为空"
                          elif docker volume inspect "$dockerjuan" >/dev/null 2>&1 && confirm_action "确认删除 Docker 卷 $dockerjuan"; then
                              docker volume rm "$dockerjuan"
                          else
                              echo "卷不存在或已取消"
                          fi
                          ;;
                      0)
                          break  # 跳出循环，退出菜单
                          ;;

                      *)
                          echo "无效的选择，请重新输入。"
                          ;;
                  esac
              done
              ;;
          7)
              clear
              echo "将列出 Docker 垃圾回收目标；只有明确输入 DELETE 才会删除未使用数据卷。"
              docker system df
              docker ps -a --filter status=exited
              docker images --filter dangling=true
              docker network ls --filter dangling=true
              docker volume ls --filter dangling=true
              if confirm_action "确认仅清理 Docker 未使用资源（包含未挂载卷）"; then
                  docker system prune -af --volumes
              else
                  echo "已取消"
              fi
              ;;
          8)
              clear
              echo "卸载 Docker 将影响该主机上的所有容器、镜像、网络和数据卷。"
              docker ps -a
              docker volume ls
              read -r -p "输入 REMOVE-DOCKER 确认卸载并清空所有 Docker 资源: " uninstall_confirm
              if [ "$uninstall_confirm" = "REMOVE-DOCKER" ]; then
                  mapfile -t docker_targets < <(docker ps -aq)
                  [ "${#docker_targets[@]}" -eq 0 ] || docker rm -f "${docker_targets[@]}"
                  mapfile -t image_targets < <(docker images -q | sort -u)
                  [ "${#image_targets[@]}" -eq 0 ] || docker rmi -f "${image_targets[@]}"
                  echo "为避免无意删除持久数据卷，卸载时保留 volumes。"
                  if [ -f /etc/alpine-release ]; then
                      rc-update del docker default 2>/dev/null || true
                      service docker stop 2>/dev/null || true
                      remove docker docker-cli-compose docker-compose
                  else
                      systemctl disable --now docker 2>/dev/null || true
                      remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-compose
                  fi
              else
                  echo "已取消"
              fi
              ;;
          0)
              break
              ;;
          *)
              echo "无效的输入!"
              ;;
      esac
  done
  ;;


  7)
    clear
    install wget
    wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh
    ;;


  9)
     while true; do
      clear
      echo "▶ 甲骨文云脚本合集"
      echo "------------------------"
      echo "1. 安装闲置机器活跃脚本"
      echo "2. 卸载闲置机器活跃脚本"
      echo "------------------------"
      echo "3. DD重装系统脚本"
      echo "------------------------"
      echo "5. 开启ROOT密码登录模式"
      echo "------------------------"
      echo "0. 返回主菜单"
      echo "------------------------"
      read -p "请输入你的选择: " sub_choice

      case $sub_choice in
          1)
              clear
              echo "活跃脚本: CPU占用10-20% 内存占用15%"
              echo "注意: 持续占资源可能违反云厂商条款，仅用于你自己的空闲机器保活。"
              read -p "确定安装吗？(Y/N): " choice
              case "$choice" in
                [Yy])

                  install_docker

                  docker run -itd --name=lookbusy --restart=always \
                          -e TZ=Asia/Shanghai \
                          -e CPU_UTIL=10-20 \
                          -e CPU_CORE=1 \
                          -e MEM_UTIL=15 \
                          -e SPEEDTEST_INTERVAL=120 \
                          fogforest/lookbusy
                  ;;
                [Nn])

                  ;;
                *)
                  echo "无效的选择，请输入 Y 或 N。"
                  ;;
              esac
              ;;
          2)
              clear
              docker rm -f lookbusy
              docker rmi fogforest/lookbusy
              ;;

          3)
          clear
          echo "请备份数据，将为你重装系统，预计花费15分钟。"
          read -p "确定继续吗？(Y/N): " choice

          case "$choice" in
            [Yy])
              while true; do
                read -p "请选择要重装的系统:  1. Debian12 | 2. Ubuntu20.04 : " sys_choice

                case "$sys_choice" in
                  1)
                    xitong="-d 12"
                    break  # 结束循环
                    ;;
                  2)
                    xitong="-u 20.04"
                    break  # 结束循环
                    ;;
                  *)
                    echo "无效的选择，请重新输入。"
                    ;;
                esac
              done

              read -p "请输入你重装后的密码: " vpspasswd
              install wget
              bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/MoeClub/Note/master/InstallNET.sh') $xitong -v 64 -p $vpspasswd -port 22
              ;;
            [Nn])
              echo "已取消"
              ;;
            *)
              echo "无效的选择，请输入 Y 或 N。"
              ;;
          esac
              ;;

          5)
              clear
              echo "设置你的ROOT密码"
              passwd
              sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config;
              sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config;
              service sshd restart
              echo "ROOT登录设置完毕！"
              server_reboot

              ;;
          0)
              break

              ;;
          *)
              echo "无效的输入!"
              ;;
      esac
  done
  ;;


  10)

  while true; do
    clear
    echo  "备份与还原"
    echo  "------------------------"
    echo  "1. 备份全站数据"
    echo  "2. 定时远程备份"
    echo  "3. 还原全站数据"
    echo  "------------------------"
    echo  "0. 返回主菜单"
    echo  "------------------------"
    read -p "请输入你的选择: " sub_choice

    case $sub_choice in
    1)
      clear
      cd /home/ && tar czvf web_$(date +"%Y%m%d%H%M%S").tar.gz web

      while true; do
        clear
        read -p "要传送文件到远程服务器吗？(Y/N): " choice
        case "$choice" in
          [Yy])
            read -p "请输入远端服务器IP:  " remote_ip
            if [ -z "$remote_ip" ]; then
              echo "错误: 请输入远端服务器IP。"
              continue
            fi
            latest_tar=$(ls -t /home/*.tar.gz | head -1)
            if [ -n "$latest_tar" ]; then
              ssh-keygen -f "/root/.ssh/known_hosts" -R "$remote_ip"
              sleep 2  # 添加等待时间
              scp -o StrictHostKeyChecking=no "$latest_tar" "root@$remote_ip:/home/"
              echo "文件已传送至远程服务器home目录。"
            else
              echo "未找到要传送的文件。"
            fi
            break
            ;;
          [Nn])
            break
            ;;
          *)
            echo "无效的选择，请输入 Y 或 N。"
            ;;
        esac
      done
      ;;

    2)
      clear
      read -p "输入远程服务器IP: " useip
      read -p "输入远程服务器密码: " usepasswd

      cd ~
      wget -O ${useip}_beifen.sh https://raw.githubusercontent.com/kejilion/sh/main/beifen.sh > /dev/null 2>&1
      chmod 700 ${useip}_beifen.sh
      echo "远程密码会写入本地脚本，权限已设为 700。建议改用 SSH 密钥后删除明文密码。"

      sed -i "s/0.0.0.0/$useip/g" ${useip}_beifen.sh
      sed -i "s/123456/$usepasswd/g" ${useip}_beifen.sh

      echo "------------------------"
      echo "1. 每周备份                 2. 每天备份"
      read -p "请输入你的选择: " dingshi

      case $dingshi in
          1)
              read -p "选择每周备份的星期几 (0-6，0代表星期日): " weekday
              (crontab -l 2>/dev/null; echo "0 0 * * $weekday $HOME/${useip}_beifen.sh") | crontab -
              ;;
          2)
              read -p "选择每天备份的时间（小时，0-23）: " hour
              (crontab -l 2>/dev/null; echo "0 $hour * * * $HOME/${useip}_beifen.sh") | crontab -
              ;;
          *)
              break  # 跳出
              ;;
      esac

      install sshpass

      ;;

    3)
      clear
      latest_tar=$(ls -t /home/web_*.tar.gz 2>/dev/null | head -1)
      if [ -n "$latest_tar" ]; then
        tar -xzf "$latest_tar" -C /home/
        echo "已还原: $latest_tar"
      else
        echo "未找到 /home/web_*.tar.gz 备份文件"
      fi
      install_dependency
      install_docker

      ;;

    0)
        break
      ;;

    *)
        echo "无效的输入!"
        ;;
    esac
  done
  ;;



  12)
    while true; do
      clear
      echo "▶ 我的工作区"
      echo "系统将为你提供10个后台运行的工作区，你可以用来执行长时间的任务"
      echo "即使你断开SSH，工作区中的任务也不会中断，非常方便！来试试吧！"
      echo -e "\033[33m注意: 进入工作区后使用Ctrl+b再单独按d，退出工作区！\033[0m"
      echo "------------------------"
      echo "a. 安装工作区环境"
      echo "------------------------"
      echo "1. 1号工作区"
      echo "2. 2号工作区"
      echo "3. 3号工作区"
      echo "4. 4号工作区"
      echo "5. 5号工作区"
      echo "6. 6号工作区"
      echo "7. 7号工作区"
      echo "8. 8号工作区"
      echo "9. 9号工作区"
      echo "10. 10号工作区"
      echo "------------------------"
      echo "99. 工作区状态"
      echo "------------------------"
      echo "b. 卸载工作区"
      echo "------------------------"
      echo "0. 返回主菜单"
      echo "------------------------"
      read -p "请输入你的选择: " sub_choice

      case $sub_choice in
          a)
              clear
              install tmux

              ;;
          b)
              clear
              remove tmux
              ;;
          1)
              clear
              SESSION_NAME="work1"
              tmux_run

              ;;
          2)
              clear
              SESSION_NAME="work2"
              tmux_run
              ;;
          3)
              clear
              SESSION_NAME="work3"
              tmux_run
              ;;
          4)
              clear
              SESSION_NAME="work4"
              tmux_run
              ;;
          5)
              clear
              SESSION_NAME="work5"
              tmux_run
              ;;
          6)
              clear
              SESSION_NAME="work6"
              tmux_run
              ;;
          7)
              clear
              SESSION_NAME="work7"
              tmux_run
              ;;
          8)
              clear
              SESSION_NAME="work8"
              tmux_run
              ;;
          9)
              clear
              SESSION_NAME="work9"
              tmux_run
              ;;
          10)
              clear
              SESSION_NAME="work10"
              tmux_run
              ;;

          99)
              clear
              tmux list-sessions
              ;;
          0)
              break
              ;;
          *)
              echo "无效的输入!"
              ;;
      esac
  done
  ;;

  13)
    while true; do
      clear
      echo "▶ 系统工具"
      echo "------------------------"
      echo "1. 设置脚本启动快捷键"
      echo "------------------------"
      echo "2. 修改ROOT密码"
      echo "3. 开启ROOT密码登录模式"
      echo "4. 安装Python最新版"
      echo "5. 开放所有端口"
      echo "6. 修改SSH连接端口"
      echo "7. 优化DNS地址"
      echo "8. 一键重装系统"
      echo "9. 禁用ROOT账户创建新账户"
      echo "10. 切换优先ipv4/ipv6"
      echo "11. 查看端口占用状态"
      echo "12. 修改虚拟内存大小"
      echo "13. 用户管理"
      echo "14. ☆fail2ban防御程序☆"
      echo "15. 系统时区调整"
      echo "16. 设置BBR3加速"
      echo "17. 防火墙高级管理器"
      echo "18. 修改主机名"
      echo "19. 切换系统更新源"
      echo "20. 定时任务管理"
      echo "21. 本机host解析"
      echo "------------------------"
      echo "99. 重启服务器"
      echo "------------------------"
      echo "0. 返回主菜单"
      echo "------------------------"
      read -p "请输入你的选择: " sub_choice

      case $sub_choice in
          1)
              clear
              read -p "请输入你的快捷按键: " kuaijiejian
              if [ -z "$kuaijiejian" ]; then
                  echo "快捷键不能为空"
              else
                  sed -i "/alias ${kuaijiejian}=/d" ~/.bashrc
                  echo "alias $kuaijiejian='$SCRIPT_PATH'" >> ~/.bashrc
                  echo "快捷键已设置，重新登录或执行 source ~/.bashrc 后生效"
              fi
              ;;

          2)
              clear
              echo "设置你的ROOT密码"
              passwd
              ;;
          3)
              clear
              echo "设置你的ROOT密码"
              passwd
              sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config;
              sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config;
              service sshd restart
              echo "ROOT登录设置完毕！"
              server_reboot

              ;;

          4)
            clear

            RED="\033[31m"
            GREEN="\033[32m"
            YELLOW="\033[33m"
            NC="\033[0m"

            # 系统检测
            OS=$(cat /etc/os-release | grep -o -E "Debian|Ubuntu|CentOS" | head -n 1)

            if [[ $OS == "Debian" || $OS == "Ubuntu" || $OS == "CentOS" ]]; then
                echo -e "检测到你的系统是 ${YELLOW}${OS}${NC}"
            else
                echo -e "${RED}很抱歉，你的系统不受支持！${NC}"
                continue
            fi

            # 检测安装Python3的版本
            VERSION=$(python3 -V 2>&1 | awk '{print $2}')

            # 获取最新Python3版本
            PY_VERSION=$(curl -s https://www.python.org/ | grep "downloads/release" | grep -o 'Python [0-9.]*' | grep -o '[0-9.]*')

            # 卸载Python3旧版本
            if [[ $VERSION == "3"* ]]; then
                echo -e "${YELLOW}你的Python3版本是${NC}${RED}${VERSION}${NC}，${YELLOW}最新版本是${NC}${RED}${PY_VERSION}${NC}"
                read -r -p "确认升级 /usr/local/python3（保留系统 Python，不预先删除旧安装）？默认不升级 [y/N]: " CONFIRM
                if [[ ! "$CONFIRM" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                    echo -e "${YELLOW}已取消升级Python3${NC}"
                    continue
                fi
                echo "旧版本保留在 /usr/local/python3；只有新版本安装成功后才切换链接。"
            else
                echo -e "${RED}检测到没有安装Python3。${NC}"
                read -p "是否确认安装最新版Python3？默认安装 [Y/n]: " CONFIRM
                if [[ $CONFIRM != "n" ]]; then
                    echo -e "${GREEN}开始安装最新版Python3...${NC}"
                else
                    echo -e "${YELLOW}已取消安装Python3${NC}"
                    continue
                fi
            fi

            # 安装相关依赖
            if [[ $OS == "CentOS" ]]; then
                yum update
                yum groupinstall -y "development tools"
                yum install wget openssl-devel bzip2-devel libffi-devel zlib-devel -y
            else
                apt update
                apt install wget build-essential libreadline-dev libncursesw5-dev libssl-dev libsqlite3-dev tk-dev libgdbm-dev libc6-dev libbz2-dev libffi-dev zlib1g-dev -y
            fi

            # 安装python3
            cd /root/
            wget https://www.python.org/ftp/python/${PY_VERSION}/Python-"$PY_VERSION".tgz
            tar -zxf Python-${PY_VERSION}.tgz
            cd Python-${PY_VERSION}
            ./configure --prefix=/usr/local/python3
            make -j $(nproc)
            make install
            if [ $? -eq 0 ];then
                rm -f /usr/local/bin/python3*
                rm -f /usr/local/bin/pip3*
                ln -sf /usr/local/python3/bin/python3 /usr/bin/python3
                ln -sf /usr/local/python3/bin/pip3 /usr/bin/pip3
                clear
                echo -e "${YELLOW}Python3安装${GREEN}成功，${NC}版本为: ${NC}${GREEN}${PY_VERSION}${NC}"
            else
                clear
                echo -e "${RED}Python3安装失败！${NC}"
                continue
            fi
            cd /root/ && rm -rf Python-${PY_VERSION}.tgz && rm -rf Python-${PY_VERSION}
              ;;

          5)
              clear
              iptables_open
              remove iptables-persistent ufw firewalld iptables-services > /dev/null 2>&1
              echo "端口已全部开放"

              ;;
          6)
              current_port=$(ssh_listen_port)
              echo "当前 SSH 端口：$current_port"
              read -r -p "请输入新的 SSH 端口: " new_port
              if ! valid_port "$new_port"; then
                  echo "端口须为 1-65535 的整数"
                  continue
              fi
              if [ "$new_port" = "$current_port" ]; then
                  echo "端口未变化"
                  continue
              fi
              if ! confirm_action "即将修改 SSH 端口 $current_port -> $new_port；请保持当前会话并用新端口测试"; then
                  echo "已取消"
                  continue
              fi

              ssh_config=/etc/ssh/sshd_config
              ssh_backup="${ssh_config}.bak.$(date +%Y%m%d-%H%M%S)"
              cp -a "$ssh_config" "$ssh_backup" || { echo "备份失败，未修改"; continue; }
              tmp_config=$(mktemp "${ssh_config}.XXXXXX") || { echo "无法创建临时文件"; continue; }
              awk -v port="$new_port" '
                  BEGIN { inserted=0 }
                  /^[[:space:]]*Port[[:space:]]+[0-9]+([[:space:]]|$)/ {
                      if (!inserted) { print "Port " port; inserted=1 }
                      next
                  }
                  { print }
                  END { if (!inserted) print "Port " port }
              ' "$ssh_config" > "$tmp_config" || { rm -f "$tmp_config"; echo "生成新配置失败"; continue; }
              chmod --reference="$ssh_config" "$tmp_config" 2>/dev/null || chmod 600 "$tmp_config"
              chown --reference="$ssh_config" "$tmp_config" 2>/dev/null || true
              mv "$tmp_config" "$ssh_config"

              if command -v sshd >/dev/null 2>&1 && ! sshd -t; then
                  cp -a "$ssh_backup" "$ssh_config"
                  echo "sshd 配置校验失败，已恢复备份: $ssh_backup"
                  continue
              fi
              if command -v systemctl >/dev/null 2>&1; then
                  if ! systemctl restart ssh 2>/dev/null && ! systemctl restart sshd 2>/dev/null; then
                      cp -a "$ssh_backup" "$ssh_config"
                      systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
                      echo "SSH 重启失败，已回滚配置"
                      continue
                  fi
              elif command -v service >/dev/null 2>&1; then
                  if ! service ssh restart 2>/dev/null && ! service sshd restart 2>/dev/null; then
                      cp -a "$ssh_backup" "$ssh_config"
                      service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || true
                      echo "SSH 重启失败，已回滚配置"
                      continue
                  fi
              fi

              if [ -f /etc/iptables/rules.v4 ]; then
                  grep -Fq -- "--dport $new_port -j ACCEPT" /etc/iptables/rules.v4 || sed -i "/COMMIT/i -A INPUT -p tcp --dport $new_port -j ACCEPT" /etc/iptables/rules.v4
                  iptables-restore < /etc/iptables/rules.v4 || true
              fi
              echo "SSH 端口已修改为 $new_port。保持当前会话并测试新端口后再断开。备份: $ssh_backup"
              ;;

          7)
            clear
            echo "当前DNS地址"
            echo "------------------------"
            cat /etc/resolv.conf
            echo "------------------------"
            echo ""
            # 询问用户是否要优化DNS设置
            read -p "是否要设置为Cloudflare和Google的DNS地址？(y/n): " choice

            if [ "$choice" == "y" ]; then
                # 定义DNS地址
                cloudflare_ipv4="1.1.1.1"
                google_ipv4="8.8.8.8"
                cloudflare_ipv6="2606:4700:4700::1111"
                google_ipv6="2001:4860:4860::8888"

                # 检查机器是否有IPv6地址
                ipv6_available=0
                if [[ $(ip -6 addr | grep -c "inet6") -gt 0 ]]; then
                    ipv6_available=1
                fi

                # 设置DNS地址为Cloudflare和Google（IPv4和IPv6）
                echo "设置DNS为Cloudflare和Google"

                # 设置IPv4地址
                echo "nameserver $cloudflare_ipv4" > /etc/resolv.conf
                echo "nameserver $google_ipv4" >> /etc/resolv.conf

                # 如果有IPv6地址，则设置IPv6地址
                if [[ $ipv6_available -eq 1 ]]; then
                    echo "nameserver $cloudflare_ipv6" >> /etc/resolv.conf
                    echo "nameserver $google_ipv6" >> /etc/resolv.conf
                fi

                echo "DNS地址已更新"
                echo "------------------------"
                cat /etc/resolv.conf
                echo "------------------------"
            else
                echo "DNS设置未更改"
            fi

              ;;

          8)
          dd_xitong_1() {
            read -p "请输入你重装后的密码: " vpspasswd
            echo "任意键继续，重装后初始用户名: root  初始密码: $vpspasswd  初始端口: 22"
            read -n 1 -s -r -p ""
            install wget
            bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/MoeClub/Note/master/InstallNET.sh') $xitong -v 64 -p $vpspasswd -port 22
          }

          dd_xitong_2() {
            echo "任意键继续，重装后初始用户名: root  初始密码: LeitboGi0ro  初始端口: 22"
            read -n 1 -s -r -p ""
            install wget
            wget --no-check-certificate -qO InstallNET.sh 'https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh' && chmod a+x InstallNET.sh
          }

          dd_xitong_3() {
            echo "任意键继续，重装后初始用户名: Administrator  初始密码: Teddysun.com  初始端口: 3389"
            read -n 1 -s -r -p ""
            install wget
            wget --no-check-certificate -qO InstallNET.sh 'https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh' && chmod a+x InstallNET.sh
          }

          clear
          echo "请备份数据，将为你重装系统，预计花费15分钟。"
          echo -e "\e[37m感谢MollyLau和MoeClub的脚本支持！\e[0m "
          read -p "确定继续吗？(Y/N): " choice

          case "$choice" in
            [Yy])
              while true; do

                echo "------------------------"
                echo "1. Debian 12"
                echo "2. Debian 11"
                echo "3. Debian 10"
                echo "4. Debian 9"
                echo "------------------------"
                echo "11. Ubuntu 24.04"
                echo "12. Ubuntu 22.04"
                echo "13. Ubuntu 20.04"
                echo "14. Ubuntu 18.04"
                echo "------------------------"
                echo "21. CentOS 9"
                echo "22. CentOS 8"
                echo "23. CentOS 7"
                echo "------------------------"
                echo "31. Alpine 3.19"
                echo "------------------------"
                echo "41. Windows 11"
                echo "42. Windows 10"
                echo "43. Windows Server 2022"
                echo "44. Windows Server 2019"
                echo "45. Windows Server 2016"
                echo "------------------------"
                read -p "请选择要重装的系统: " sys_choice

                case "$sys_choice" in
                  1)
                    xitong="-d 12"
                    dd_xitong_1
                    exit
                    reboot
                    ;;

                  2)
                    xitong="-d 11"
                    dd_xitong_1
                    reboot
                    exit
                    ;;

                  3)
                    xitong="-d 10"
                    dd_xitong_1
                    reboot
                    exit
                    ;;
                  4)
                    xitong="-d 9"
                    dd_xitong_1
                    reboot
                    exit
                    ;;

                  11)
                    dd_xitong_2
                    bash InstallNET.sh -ubuntu 24.04
                    reboot
                    exit
                    ;;
                  12)
                    dd_xitong_2
                    bash InstallNET.sh -ubuntu 22.04
                    reboot
                    exit
                    ;;

                  13)
                    xitong="-u 20.04"
                    dd_xitong_1
                    reboot
                    exit
                    ;;
                  14)
                    xitong="-u 18.04"
                    dd_xitong_1
                    reboot
                    exit
                    ;;


                  21)
                    dd_xitong_2
                    bash InstallNET.sh -centos 9
                    reboot
                    exit
                    ;;


                  22)
                    dd_xitong_2
                    bash InstallNET.sh -centos 8
                    reboot
                    exit
                    ;;

                  23)
                    dd_xitong_2
                    bash InstallNET.sh -centos 7
                    reboot
                    exit
                    ;;



                  31)
                    dd_xitong_2
                    bash InstallNET.sh -alpine
                    reboot
                    exit
                    ;;



                  41)
                    dd_xitong_3
                    bash InstallNET.sh -windows 11 -lang "cn"
                    reboot
                    exit
                    ;;

                  42)
                    dd_xitong_3
                    bash InstallNET.sh -windows 10 -lang "cn"
                    reboot
                    exit
                    ;;

                  43)
                    dd_xitong_3
                    bash InstallNET.sh -windows 2022 -lang "cn"
                    reboot
                    exit
                    ;;

                  44)
                    dd_xitong_3
                    bash InstallNET.sh -windows 2019 -lang "cn"
                    reboot
                    exit
                    ;;

                  45)
                    dd_xitong_3
                    bash InstallNET.sh -windows 2016 -lang "cn"
                    reboot
                    exit
                    ;;


                  *)
                    echo "无效的选择，请重新输入。"
                    ;;
                esac
              done
              ;;
            [Nn])
              echo "已取消"
              ;;
            *)
              echo "无效的选择，请输入 Y 或 N。"
              ;;
          esac
              ;;

          9)
            clear
            install sudo

            # 提示用户输入新用户名
            read -p "请输入新用户名: " new_username

            # 创建新用户并设置密码
            sudo useradd -m -s /bin/bash "$new_username"
            sudo passwd "$new_username"

            # 赋予新用户sudo权限
            echo "$new_username ALL=(ALL:ALL) ALL" | sudo tee "/etc/sudoers.d/$new_username" >/dev/null && sudo chmod 440 "/etc/sudoers.d/$new_username"

            # 禁用ROOT用户登录
            if id "$new_username" >/dev/null 2>&1; then
                sudo passwd -l root
                echo "已锁定 root 密码登录。请确认新用户可 SSH 登录后再断开当前会话。"
            else
                echo "新用户创建失败，未锁定 root。"
            fi
            echo "操作已完成。"
            ;;


          10)
            clear
            echo "通过 /etc/gai.conf 调整 getaddrinfo 优先级，不会关闭 IPv6。"
            echo "------------------------"
            echo "1. IPv4 优先          2. IPv6 优先（恢复默认）"
            echo "------------------------"
            read -p "选择优先的网络: " choice
            mkdir -p /etc
            touch /etc/gai.conf
            sed -i '/^precedence ::ffff:0:0\/96/d' /etc/gai.conf
            case $choice in
                1)
                    echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
                    echo "已切换为 IPv4 优先"
                    ;;
                2)
                    echo "已恢复 IPv6 默认优先级（未禁用 IPv6）"
                    ;;
                *)
                    echo "无效的选择"
                    ;;
            esac
            ;;

          11)
            clear
            ss -tulnape
            ;;

          12)
            clear
            # 获取当前交换空间信息
            swap_used=$(free -m | awk 'NR==3{print $3}')
            swap_total=$(free -m | awk 'NR==3{print $2}')

            if [ "$swap_total" -eq 0 ]; then
              swap_percentage=0
            else
              swap_percentage=$((swap_used * 100 / swap_total))
            fi

            swap_info="${swap_used}MB/${swap_total}MB (${swap_percentage}%)"

            echo "当前虚拟内存: $swap_info"

            read -p "是否调整大小?(Y/N): " choice

            case "$choice" in
              [Yy])
                # 输入新的虚拟内存大小
                read -p "请输入虚拟内存大小MB: " new_swap
                add_swap

                echo "添加完成"
                ;;
              [Nn])
                echo "已取消"
                ;;
              *)
                echo "无效的选择，请输入 Y 或 N。"
                ;;
            esac
            ;;

          13)
              while true; do
                clear
                install sudo
                clear
                # 显示所有用户、用户权限、用户组和是否在sudoers中
                echo "用户列表"
                echo "----------------------------------------------------------------------------"
                printf "%-24s %-34s %-20s %-10s\n" "用户名" "用户权限" "用户组" "sudo权限"
                while IFS=: read -r username _ userid groupid _ _ homedir shell; do
                    groups=$(groups "$username" | cut -d : -f 2)
                    sudo_status=$(sudo -n -lU "$username" 2>/dev/null | grep -q '(ALL : ALL)' && echo "Yes" || echo "No")
                    printf "%-20s %-30s %-20s %-10s\n" "$username" "$homedir" "$groups" "$sudo_status"
                done < /etc/passwd


                  echo ""
                  echo "账户操作"
                  echo "------------------------"
                  echo "1. 创建普通账户             2. 创建高级账户"
                  echo "------------------------"
                  echo "3. 赋予最高权限             4. 取消最高权限"
                  echo "------------------------"
                  echo "5. 删除账号"
                  echo "------------------------"
                  echo "0. 返回上一级选单"
                  echo "------------------------"
                  read -p "请输入你的选择: " sub_choice

                  case $sub_choice in
                      1)
                       # 提示用户输入新用户名
                       read -p "请输入新用户名: " new_username

                       # 创建新用户并设置密码
                       sudo useradd -m -s /bin/bash "$new_username"
                       sudo passwd "$new_username"

                       echo "操作已完成。"
                          ;;

                      2)
                       # 提示用户输入新用户名
                       read -p "请输入新用户名: " new_username

                       # 创建新用户并设置密码
                       sudo useradd -m -s /bin/bash "$new_username"
                       sudo passwd "$new_username"

                       # 赋予新用户sudo权限
                       echo "$new_username ALL=(ALL:ALL) ALL" | sudo tee "/etc/sudoers.d/$new_username" >/dev/null && sudo chmod 440 "/etc/sudoers.d/$new_username"

                       echo "操作已完成。"

                          ;;
                      3)
                       read -p "请输入用户名: " username
                       # 赋予新用户sudo权限
                       echo "$username ALL=(ALL:ALL) ALL" | sudo tee "/etc/sudoers.d/$username" >/dev/null && sudo chmod 440 "/etc/sudoers.d/$username"
                          ;;
                      4)
                       read -p "请输入用户名: " username
                       # 从sudoers文件中移除用户的sudo权限
                       sudo rm -f "/etc/sudoers.d/$username"
                       sudo sed -i "/^$username[[:space:]]ALL=(ALL:ALL)[[:space:]]ALL/d" /etc/sudoers

                          ;;
                      5)
                       read -p "请输入要删除的用户名: " username
                       # 删除用户及其主目录
                       sudo userdel -r "$username"
                          ;;

                      0)
                          break  # 跳出循环，退出菜单
                          ;;

                      *)
                          echo "无效的选择，请重新输入。"
                          ;;
                  esac
              done
              ;;

          14)
              while true; do
              clear

              echo "------------------------"
              echo "1. 查看SSH拦截记录                2. 查看网站拦截记录"
              echo "3. 查看防御规则列表               4. 查看日志实时监控"
              echo "------------------------"
              echo "11. 配置拦截参数（含cloudflare参数）"
              echo "------------------------"
              echo "0. 退出"
              echo "------------------------"
              read -p "请输入你的选择: " sub_choice
              case $sub_choice in
                  1)
                      echo "------------------------"
                      fail2ban-client status sshd
                      echo "------------------------"
                      ;;
                  2)
                      echo "------------------------"
                      fail2ban-client status docker-nginx-cc
                      echo "------------------------"
                      fail2ban-client status docker-nginx-badbots
                      echo "------------------------"
                      fail2ban-client status docker-nginx-botsearch
                      echo "------------------------"
                      fail2ban-client status docker-nginx-http-auth
                      echo "------------------------"
                      fail2ban-client status docker-nginx-limit-req
                      echo "------------------------"
                      fail2ban-client status docker-php-url-fopen
                      echo "------------------------"
                      ;;

                  3)
                      fail2ban-client status
                      ;;
                  4)
                      tail -f /var/log/fail2ban.log
                      ;;
                  11)
                      if ! command -v fail2ban-client >/dev/null 2>&1; then
                          echo "未检测到 fail2ban，先安装..."
                          if ! install fail2ban; then
                              echo "fail2ban 安装失败"
                              continue
                          fi
                      fi
                      f2b_script=$(mktemp /root/f2b.XXXXXX.sh)
                      if curl -fsSL -o "$f2b_script" https://raw.githubusercontent.com/chrimast/docker/main/f2b.sh; then
                          chmod 700 "$f2b_script"
                          "$f2b_script"
                      else
                          echo "下载 f2b.sh 失败"
                      fi
                      rm -f "$f2b_script"
                      fail2ban-client status || echo "fail2ban 未运行或尚未配置 jail"
                      ;;
                  0)
                      break
                      ;;
                  *)
                      echo "无效的选择，请重新输入。"
                      ;;
              esac
            done
              ;;

          15)
            while true; do
                clear
                echo "系统时间信息"

                # 获取当前系统时区
                tz_now=$(current_timezone)

                # 获取当前系统时间
                current_time=$(date +"%Y-%m-%d %H:%M:%S")

                # 显示时区和时间
                echo "当前系统时区：$tz_now"
                echo "当前系统时间：$current_time"

                echo ""
                echo "时区切换"
                echo "亚洲------------------------"
                echo "1. 中国上海时间              2. 中国香港时间"
                echo "3. 日本东京时间              4. 韩国首尔时间"
                echo "5. 新加坡时间                6. 印度加尔各答时间"
                echo "7. 阿联酋迪拜时间            8. 澳大利亚悉尼时间"
                echo "欧洲------------------------"
                echo "11. 英国伦敦时间             12. 法国巴黎时间"
                echo "13. 德国柏林时间             14. 俄罗斯莫斯科时间"
                echo "15. 荷兰尤特赖赫特时间       16. 西班牙马德里时间"
                echo "美洲------------------------"
                echo "21. 美国西部时间             22. 美国东部时间"
                echo "23. 加拿大时间               24. 墨西哥时间"
                echo "25. 巴西时间                 26. 阿根廷时间"
                echo "------------------------"
                echo "0. 返回上一级选单"
                echo "------------------------"
                read -p "请输入你的选择: " sub_choice

                case $sub_choice in
                    1) set_timezone Asia/Shanghai ;;
                    2) set_timezone Asia/Hong_Kong ;;
                    3) set_timezone Asia/Tokyo ;;
                    4) set_timezone Asia/Seoul ;;
                    5) set_timezone Asia/Singapore ;;
                    6) set_timezone Asia/Kolkata ;;
                    7) set_timezone Asia/Dubai ;;
                    8) set_timezone Australia/Sydney ;;
                    11) set_timezone Europe/London ;;
                    12) set_timezone Europe/Paris ;;
                    13) set_timezone Europe/Berlin ;;
                    14) set_timezone Europe/Moscow ;;
                    15) set_timezone Europe/Amsterdam ;;
                    16) set_timezone Europe/Madrid ;;
                    21) set_timezone America/Los_Angeles ;;
                    22) set_timezone America/New_York ;;
                    23) set_timezone America/Vancouver ;;
                    24) set_timezone America/Mexico_City ;;
                    25) set_timezone America/Sao_Paulo ;;
                    26) set_timezone America/Argentina/Buenos_Aires ;;
                    0) break ;; # 跳出循环，退出菜单
                    *) break ;; # 跳出循环，退出菜单
                esac
            done
              ;;

          16)
          if dpkg -l | grep -q 'linux-xanmod'; then
            while true; do
                  clear
                  kernel_version=$(uname -r)
                  echo "您已安装xanmod的BBRv3内核"
                  echo "当前内核版本: $kernel_version"

                  echo ""
                  echo "内核管理"
                  echo "------------------------"
                  echo "1. 更新BBRv3内核              2. 卸载BBRv3内核"
                  echo "------------------------"
                  echo "0. 返回上一级选单"
                  echo "------------------------"
                  read -p "请输入你的选择: " sub_choice

                  case $sub_choice in
                      1)
                        apt purge -y 'linux-*xanmod1*'
                        update-grub

                        # wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes
                        wget -qO - https://raw.githubusercontent.com/kejilion/sh/main/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes

                        # 步骤3：添加存储库
                        echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-release.list

                        # version=$(wget -q https://dl.xanmod.org/check_x86-64_psabi.sh && chmod +x check_x86-64_psabi.sh && ./check_x86-64_psabi.sh | grep -oP 'x86-64-v\K\d+|x86-64-v\d+')
                        version=$(wget -q https://raw.githubusercontent.com/kejilion/sh/main/check_x86-64_psabi.sh && chmod +x check_x86-64_psabi.sh && ./check_x86-64_psabi.sh | grep -oP 'x86-64-v\K\d+|x86-64-v\d+')

                        apt update -y
                        apt install -y linux-xanmod-x64v$version

                        echo "XanMod内核已更新。重启后生效"
                        rm -f /etc/apt/sources.list.d/xanmod-release.list
                        rm -f check_x86-64_psabi.sh*

                        server_reboot

                          ;;
                      2)
                        apt purge -y 'linux-*xanmod1*'
                        update-grub
                        echo "XanMod内核已卸载。重启后生效"
                        server_reboot
                          ;;
                      0)
                          break  # 跳出循环，退出菜单
                          ;;

                      *)
                          break  # 跳出循环，退出菜单
                          ;;

                  esac
            done
        else

          clear
          echo "请备份数据，将为你升级Linux内核开启BBR3"
          echo "官网介绍: https://xanmod.org/"
          echo "------------------------------------------------"
          echo "仅支持Debian/Ubuntu 仅支持x86_64架构"
          echo "VPS是512M内存的，请提前添加1G虚拟内存，防止因内存不足失联！"
          echo "------------------------------------------------"
          read -p "确定继续吗？(Y/N): " choice

          case "$choice" in
            [Yy])
            if [ -r /etc/os-release ]; then
                . /etc/os-release
                if [ "$ID" != "debian" ] && [ "$ID" != "ubuntu" ]; then
                    echo "当前环境不支持，仅支持Debian和Ubuntu系统"
                    break
                fi
            else
                echo "无法确定操作系统类型"
                break
            fi

            # 检查系统架构
            arch=$(dpkg --print-architecture)
            if [ "$arch" != "amd64" ]; then
              echo "当前环境不支持，仅支持x86_64架构"
              break
            fi

            new_swap=1024
            add_swap
            install wget gnupg

            # wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes
            wget -qO - https://raw.githubusercontent.com/kejilion/sh/main/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes

            # 步骤3：添加存储库
            echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-release.list

            # version=$(wget -q https://dl.xanmod.org/check_x86-64_psabi.sh && chmod +x check_x86-64_psabi.sh && ./check_x86-64_psabi.sh | grep -oP 'x86-64-v\K\d+|x86-64-v\d+')
            version=$(wget -q https://raw.githubusercontent.com/kejilion/sh/main/check_x86-64_psabi.sh && chmod +x check_x86-64_psabi.sh && ./check_x86-64_psabi.sh | grep -oP 'x86-64-v\K\d+|x86-64-v\d+')

            apt update -y
            apt install -y linux-xanmod-x64v$version

            # 步骤5：启用BBR3
            sysctl_set_file /etc/sysctl.d/99-bbr3.conf \
                "net.core.default_qdisc=fq_pie" \
                "net.ipv4.tcp_congestion_control=bbr"
            echo "XanMod内核安装并BBR3启用成功。重启后生效"
            rm -f /etc/apt/sources.list.d/xanmod-release.list
            rm -f check_x86-64_psabi.sh*
            server_reboot

              ;;
            [Nn])
              echo "已取消"
              ;;
            *)
              echo "无效的选择，请输入 Y 或 N。"
              ;;
          esac
        fi
              ;;

          17)
          if dpkg -l | grep -q iptables-persistent; then
            while true; do
                  clear
                  echo "防火墙已安装"
                  echo "------------------------"
                  iptables -L INPUT

                  echo ""
                  echo "防火墙管理"
                  echo "------------------------"
                  echo "1. 开放指定端口              2. 关闭指定端口"
                  echo "3. 放行全部入站              4. 仅放行 SSH（拒绝其他入站）"
                  echo "------------------------"
                  echo "5. IP白名单                  6. IP黑名单"
                  echo "7. 清除指定IP"
                  echo "------------------------"
                  echo "9. 卸载防火墙"
                  echo "------------------------"
                  echo "0. 返回上一级选单"
                  echo "------------------------"
                  read -p "请输入你的选择: " sub_choice

                  case $sub_choice in
                      1)
                      read -p "请输入开放的端口号: " o_port
                      sed -i "/COMMIT/i -A INPUT -p tcp --dport $o_port -j ACCEPT" /etc/iptables/rules.v4
                      sed -i "/COMMIT/i -A INPUT -p udp --dport $o_port -j ACCEPT" /etc/iptables/rules.v4
                      iptables-restore < /etc/iptables/rules.v4

                          ;;
                      2)
                      read -p "请输入关闭的端口号: " c_port
                      sed -i "/--dport $c_port/d" /etc/iptables/rules.v4
                      iptables-restore < /etc/iptables/rules.v4
                        ;;

                      3)
                      current_port=$(ssh_listen_port)

                      cat > /etc/iptables/rules.v4 << EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A FORWARD -i lo -j ACCEPT
-A INPUT -p tcp --dport $current_port -j ACCEPT
COMMIT
EOF
                      iptables-restore < /etc/iptables/rules.v4

                          ;;
                      4)
                      current_port=$(ssh_listen_port)

                      cat > /etc/iptables/rules.v4 << EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A FORWARD -i lo -j ACCEPT
-A INPUT -p tcp --dport $current_port -j ACCEPT
COMMIT
EOF
                      iptables-restore < /etc/iptables/rules.v4

                          ;;

                      5)
                      read -p "请输入放行的IP: " o_ip
                      sed -i "/COMMIT/i -A INPUT -s $o_ip -j ACCEPT" /etc/iptables/rules.v4
                      iptables-restore < /etc/iptables/rules.v4

                          ;;

                      6)
                      read -p "请输入封锁的IP: " c_ip
                      sed -i "/COMMIT/i -A INPUT -s $c_ip -j DROP" /etc/iptables/rules.v4
                      iptables-restore < /etc/iptables/rules.v4
                          ;;

                      7)
                     read -p "请输入清除的IP: " d_ip
                     sed -i "/-A INPUT -s $d_ip/d" /etc/iptables/rules.v4
                     iptables-restore < /etc/iptables/rules.v4
                          ;;

                      9)
                      remove iptables-persistent
                      rm /etc/iptables/rules.v4
                      break
                          ;;

                      0)
                          break  # 跳出循环，退出菜单
                          ;;

                      *)
                          break  # 跳出循环，退出菜单
                          ;;

                  esac
            done
        else

          clear
          echo "将为你安装防火墙，该防火墙仅支持Debian/Ubuntu"
          echo "------------------------------------------------"
          read -p "确定继续吗？(Y/N): " choice

          case "$choice" in
            [Yy])
            if [ -r /etc/os-release ]; then
                . /etc/os-release
                if [ "$ID" != "debian" ] && [ "$ID" != "ubuntu" ]; then
                    echo "当前环境不支持，仅支持Debian和Ubuntu系统"
                    break
                fi
            else
                echo "无法确定操作系统类型"
                break
            fi

          clear
          remove ufw
          mkdir -p /etc/iptables
          apt update -y && apt install -y iptables-persistent

          current_port=$(ssh_listen_port)

          cat > /etc/iptables/rules.v4 << EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A FORWARD -i lo -j ACCEPT
-A INPUT -p tcp --dport $current_port -j ACCEPT
COMMIT
EOF

          iptables-restore < /etc/iptables/rules.v4
          systemctl enable netfilter-persistent
          echo "防火墙安装完成"


              ;;
            [Nn])
              echo "已取消"
              ;;
            *)
              echo "无效的选择，请输入 Y 或 N。"
              ;;
          esac
        fi
              ;;

          18)
          current_hostname=$(hostname)
          echo "当前主机名: $current_hostname"
          read -r -p "是否更改主机名？(y/N): " answer
          if [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then
              read -r -p "请输入新的主机名（仅字母、数字、点、连字符）: " new_hostname
              if [[ ! "$new_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$ || "$new_hostname" == *..* ]]; then
                  echo "主机名格式无效，未更改"
                  continue
              fi
              if command -v hostnamectl >/dev/null 2>&1; then
                  hostnamectl set-hostname "$new_hostname" || { echo "设置失败"; continue; }
              else
                  echo "$new_hostname" > /etc/hostname || { echo "写入 /etc/hostname 失败"; continue; }
                  hostname "$new_hostname" || true
              fi
              echo "主机名已更改为: $new_hostname"
              echo "未改写 /etc/hosts；如有需要请手动增加精确主机名映射。"
          else
              echo "未更改主机名。"
          fi
          ;;

          19)

          # 获取系统信息
          source /etc/os-release

          # 定义 Ubuntu 更新源
          aliyun_ubuntu_source="http://mirrors.aliyun.com/ubuntu/"
          official_ubuntu_source="http://archive.ubuntu.com/ubuntu/"
          initial_ubuntu_source=""

          # 定义 Debian 更新源
          aliyun_debian_source="http://mirrors.aliyun.com/debian/"
          official_debian_source="http://deb.debian.org/debian/"
          aliyun_debian_security="http://mirrors.aliyun.com/debian-security/"
          official_debian_security="http://security.debian.org/debian-security/"
          initial_debian_source=""

          # 定义 CentOS 更新源
          aliyun_centos_source="http://mirrors.aliyun.com/centos/"
          official_centos_source="http://mirror.centos.org/centos/"
          initial_centos_source=""

          # 获取当前更新源并设置初始源
          case "$ID" in
              ubuntu)
                  initial_ubuntu_source=$(grep -hE '^URIs:|^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null | awk '{print $2}' | head -n 1)
                  ;;
              debian)
                  initial_debian_source=$(grep -hE '^URIs:|^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null | awk '{print $2}' | head -n 1)
                  ;;
              centos)
                  initial_centos_source=$(awk -F= '/^baseurl=/ {print $2}' /etc/yum.repos.d/CentOS-Base.repo | head -n 1 | tr -d ' ')
                  ;;
              *)
                  echo "未知系统，无法执行切换源脚本"
                  continue
                  ;;
          esac

          # 备份当前源
          backup_sources() {
              case "$ID" in
                  ubuntu|debian)
                      local file
                      while IFS= read -r file; do
                          [ -n "$file" ] || continue
                          [ -f "${file}.bak" ] || cp "$file" "${file}.bak"
                      done < <(apt_source_files)
                      echo "已备份 sources.list 与 sources.list.d 中的源文件为 *.bak"
                      ;;
                  centos)
                      if [ ! -f /etc/yum.repos.d/CentOS-Base.repo.bak ]; then
                          cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak
                      else
                          echo "备份已存在，无需重复备份"
                      fi
                      ;;
                  *)
                      echo "未知系统，无法执行备份操作"
                      return 1
                      ;;
              esac
          }

          # 还原初始更新源
          restore_initial_source() {
              case "$ID" in
                  ubuntu|debian)
                      local file
                      while IFS= read -r file; do
                          [ -f "${file}.bak" ] && cp "${file}.bak" "$file"
                      done < <(apt_source_files)
                      echo "已从 *.bak 还原更新源"
                      ;;
                  centos)
                      cp /etc/yum.repos.d/CentOS-Base.repo.bak /etc/yum.repos.d/CentOS-Base.repo
                      echo "已还原初始更新源"
                      ;;
                  *)
                      echo "未知系统，无法执行还原操作"
                      return 1
                      ;;
              esac
          }

          # 函数：切换更新源
          switch_source() {
              local main_mirror="$1"
              local security_mirror="${2:-}"
              case "$ID" in
                  ubuntu)
                      rewrite_apt_mirror "http://archive.ubuntu.com/ubuntu" "$main_mirror"
                      rewrite_apt_mirror "https://archive.ubuntu.com/ubuntu" "$main_mirror"
                      rewrite_apt_mirror "http://security.ubuntu.com/ubuntu" "$main_mirror"
                      rewrite_apt_mirror "https://security.ubuntu.com/ubuntu" "$main_mirror"
                      rewrite_apt_mirror "http://mirrors.aliyun.com/ubuntu" "$main_mirror"
                      rewrite_apt_mirror "https://mirrors.aliyun.com/ubuntu" "$main_mirror"
                      ;;
                  debian)
                      rewrite_apt_mirror "http://deb.debian.org/debian" "$main_mirror"
                      rewrite_apt_mirror "https://deb.debian.org/debian" "$main_mirror"
                      rewrite_apt_mirror "http://mirrors.aliyun.com/debian" "$main_mirror"
                      rewrite_apt_mirror "https://mirrors.aliyun.com/debian" "$main_mirror"
                      if [ -n "$security_mirror" ]; then
                          rewrite_apt_mirror "http://security.debian.org/debian-security" "$security_mirror"
                          rewrite_apt_mirror "https://security.debian.org/debian-security" "$security_mirror"
                          rewrite_apt_mirror "http://mirrors.aliyun.com/debian-security" "$security_mirror"
                          rewrite_apt_mirror "https://mirrors.aliyun.com/debian-security" "$security_mirror"
                          rewrite_apt_mirror "http://security.debian.org" "$security_mirror"
                          rewrite_apt_mirror "https://security.debian.org" "$security_mirror"
                      fi
                      ;;
                  centos)
                      sed -i "s|^baseurl=.*$|baseurl=$main_mirror|g" /etc/yum.repos.d/CentOS-Base.repo
                      ;;
                  *)
                      echo "未知系统，无法执行切换操作"
                      return 1
                      ;;
              esac
          }

          # 主菜单
          while true; do
              clear
              case "$ID" in
                  ubuntu)
                      echo "Ubuntu 更新源切换脚本"
                      echo "------------------------"
                      ;;
                  debian)
                      echo "Debian 更新源切换脚本"
                      echo "------------------------"
                      ;;
                  centos)
                      echo "CentOS 更新源切换脚本"
                      echo "------------------------"
                      ;;
                  *)
                      echo "未知系统，无法执行脚本"
                      break
                      ;;
              esac

              echo "1. 切换到阿里云源"
              echo "2. 切换到官方源"
              echo "------------------------"
              echo "3. 备份当前更新源"
              echo "4. 还原初始更新源"
              echo "------------------------"
              echo "0. 返回上一级"
              echo "------------------------"
              read -p "请选择操作: " choice

              case $choice in
                  1)
                      backup_sources
                      case "$ID" in
                          ubuntu)
                              switch_source "$aliyun_ubuntu_source"
                              ;;
                          debian)
                              switch_source "$aliyun_debian_source" "$aliyun_debian_security"
                              ;;
                          centos)
                              switch_source "$aliyun_centos_source"
                              ;;
                          *)
                              echo "未知系统，无法执行切换操作"
                              ;;
                      esac
                      echo "已切换到阿里云源"
                      ;;
                  2)
                      backup_sources
                      case "$ID" in
                          ubuntu)
                              switch_source "$official_ubuntu_source"
                              ;;
                          debian)
                              switch_source "$official_debian_source" "$official_debian_security"
                              ;;
                          centos)
                              switch_source "$official_centos_source"
                              ;;
                          *)
                              echo "未知系统，无法执行切换操作"
                              ;;
                      esac
                      echo "已切换到官方源"
                      ;;
                  3)
                      backup_sources
                      echo "已备份当前更新源"
                      ;;
                  4)
                      restore_initial_source
                      ;;
                  0)
                      break
                      ;;
                  *)
                      echo "无效的选择，请重新输入"
                      ;;
              esac
              break_end

          done

              ;;

          20)

              while true; do
                  clear
                  echo "定时任务列表"
                  crontab -l 2>/dev/null || echo "(当前没有 crontab)"
                  echo ""
                  echo "操作"
                  echo "------------------------"
                  echo "1. 添加定时任务              2. 删除定时任务"
                  echo "------------------------"
                  echo "0. 返回上一级选单"
                  echo "------------------------"
                  read -p "请输入你的选择: " sub_choice

                  case $sub_choice in
                      1)
                          read -r -p "请输入新任务执行命令: " newquest
                          if [ -z "$newquest" ]; then
                              echo "命令不能为空"
                              continue
                          fi
                          echo "1. 每周任务  2. 每天任务"
                          read -r -p "请输入你的选择: " dingshi
                          case $dingshi in
                              1)
                                  read -r -p "选择周几执行 (0-6，0=周日): " weekday
                                  if [[ ! "$weekday" =~ ^[0-6]$ ]]; then echo "星期输入无效"; continue; fi
                                  (crontab -l 2>/dev/null || true; printf '0 0 * * %s %s\n' "$weekday" "$newquest") | crontab -
                                  ;;
                              2)
                                  read -r -p "选择每天几点执行 (0-23): " hour
                                  if [[ ! "$hour" =~ ^([0-9]|1[0-9]|2[0-3])$ ]]; then echo "小时输入无效"; continue; fi
                                  (crontab -l 2>/dev/null || true; printf '0 %s * * * %s\n' "$hour" "$newquest") | crontab -
                                  ;;
                              *) echo "无效的选择，请重新输入" ;;
                          esac
                          ;;
                      2)
                          read -r -p "请输入要删除任务的完整命令片段（不能为空）: " kquest
                          if [ -z "$kquest" ]; then
                              echo "删除条件不能为空，未修改 crontab"
                              continue
                          fi
                          current_crontab=$(crontab -l 2>/dev/null || true)
                          matches=$(printf '%s\n' "$current_crontab" | grep -F -- "$kquest" || true)
                          match_count=$(printf '%s\n' "$matches" | awk 'NF{n++} END{print n+0}')
                          if [ "$match_count" -eq 0 ]; then
                              echo "没有匹配的任务"
                          elif [ "$match_count" -gt 1 ]; then
                              echo "匹配到多条任务，请输入更精确的完整命令："
                              printf '%s\n' "$matches"
                          elif confirm_action "确认删除以下任务"; then
                              printf '%s\n' "$matches"
                              printf '%s\n' "$current_crontab" | grep -Fv -- "$kquest" | crontab -
                          else
                              echo "已取消"
                          fi
                          ;;
                      0)
                          break  # 跳出循环，退出菜单
                          ;;

                      *)
                          echo "无效的选择，请重新输入。"
                          ;;
                  esac
              done

              ;;

          21)

              while true; do
                  clear
                  echo "本机host解析列表"
                  echo "如果你在这里添加解析匹配，将不再使用动态解析了"
                  cat /etc/hosts
                  echo ""
                  echo "操作"
                  echo "------------------------"
                  echo "1. 添加新的解析              2. 删除解析地址"
                  echo "------------------------"
                  echo "0. 返回上一级选单"
                  echo "------------------------"
                  read -p "请输入你的选择: " host_dns

                  case $host_dns in
                      1)
                          read -r -p "请输入解析记录（IP hostname）: " addhost
                          read -r host_ip host_name extra <<< "$addhost"
                          if [ -z "$host_ip" ] || [ -z "$host_name" ] || [ -n "$extra" ] || ! [[ "$host_name" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || ! getent ahosts "$host_ip" >/dev/null 2>&1; then
                              echo "格式无效；请使用有效 IP 和 hostname，例如 203.0.113.10 example.com"
                          elif awk -v ip="$host_ip" -v host="$host_name" '$1 == ip {for(i=2;i<=NF;i++) if($i==host) found=1} END{exit !found}' /etc/hosts; then
                              echo "该映射已存在"
                          else
                              cp -a /etc/hosts "/etc/hosts.bak.$(date +%Y%m%d-%H%M%S)"
                              printf '%s\t%s\n' "$host_ip" "$host_name" >> /etc/hosts
                              echo "已添加映射"
                          fi
                          ;;
                      2)
                          read -r -p "请输入要删除的精确 hostname: " delhost
                          if [ -z "$delhost" ] || [[ ! "$delhost" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || [[ "$delhost" == "localhost" ]]; then
                              echo "hostname 无效或受保护，未修改"
                          elif ! awk -v host="$delhost" '{for(i=2;i<=NF;i++) if($i==host) found=1} END{exit !found}' /etc/hosts; then
                              echo "没有找到精确匹配项"
                          elif confirm_action "确认删除 /etc/hosts 中 hostname=$delhost 的匹配项"; then
                              cp -a /etc/hosts "/etc/hosts.bak.$(date +%Y%m%d-%H%M%S)"
                              awk -v host="$delhost" '{keep=1; for(i=2;i<=NF;i++) if($i==host) keep=0; if(keep) print}' /etc/hosts > /etc/hosts.tmp && cat /etc/hosts.tmp > /etc/hosts && rm -f /etc/hosts.tmp
                          else
                              echo "已取消"
                          fi
                          ;;
                      0)
                          break  # 跳出循环，退出菜单
                          ;;

                      *)
                          echo "无效的选择，请重新输入。"
                          ;;
                  esac
              done
              ;;


          99)
              clear
              server_reboot
              ;;

          0)
              break
              ;;
          *)
              echo "无效的输入!"
              ;;
      esac
      break_end

    done
    ;;

  99)
    clear
    server_reboot
    ;;
  0)
    clear
    exit
    ;;

  *)
    echo "无效的输入!"
    ;;
esac
done
