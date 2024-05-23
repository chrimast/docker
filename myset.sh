#!/bin/bash
ln -sf ~/myset.sh /usr/local/bin/o


ip_address() {
ipv4_address=$(curl -s ipv4.ip.sb)
ipv6_address=$(curl -s --max-time 1 ipv6.ip.sb)
}



install() {
    if [ $# -eq 0 ]; then
        echo "未提供软件包参数!"
        return 1
    fi

    for package in "$@"; do
        if ! command -v "$package" &>/dev/null; then
            if command -v dnf &>/dev/null; then
                dnf -y update && dnf install -y "$package"
            elif command -v yum &>/dev/null; then
                yum -y update && yum -y install "$package"
            elif command -v apt &>/dev/null; then
                apt update -y && apt install -y "$package"
            elif command -v apk &>/dev/null; then
                apk update && apk add "$package"
            else
                echo "未知的包管理器!"
                return 1
            fi
        fi
    done

    return 0
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

    for package in "$@"; do
        if command -v dnf &>/dev/null; then
            dnf remove -y "${package}*"
        elif command -v yum &>/dev/null; then
            yum remove -y "${package}*"
        elif command -v apt &>/dev/null; then
            apt purge -y "${package}*"
        elif command -v apk &>/dev/null; then
            apk del "${package}*"
        else
            echo "未知的包管理器!"
            return 1
        fi
    done

    return 0
}


break_end() {
      echo -e "\033[0;32m操作完成\033[0m"
      echo "按任意键继续..."
      read -n 1 -s -r -p ""
      echo ""
      clear
}

myset() {
            o
            exit
}

install_add_docker() {
    if [ -f "/etc/alpine-release" ]; then
        apk update
        apk add docker docker-compose
        rc-update add docker default
        service docker start
    else
        curl -fsSL https://get.docker.com | sh && ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin
        systemctl start docker
        systemctl enable docker
    fi

    sleep 2
}

install_docker() {
    if ! command -v docker &>/dev/null; then
        install_add_docker
    else
        echo "Docker 已经安装"
    fi
}


iptables_open() {
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -F

    ip6tables -P INPUT ACCEPT
    ip6tables -P FORWARD ACCEPT
    ip6tables -P OUTPUT ACCEPT
    ip6tables -F

}



add_swap() {
    # 获取当前系统中所有的 swap 分区
    swap_partitions=$(grep -E '^/dev/' /proc/swaps | awk '{print $1}')

    # 遍历并删除所有的 swap 分区
    for partition in $swap_partitions; do
      swapoff "$partition"
      wipefs -a "$partition"  # 清除文件系统标识符
      mkswap -f "$partition"
    done

    # 确保 /swapfile 不再被使用
    swapoff /swapfile

    # 删除旧的 /swapfile
    rm -f /swapfile

    # 创建新的 swap 分区
    dd if=/dev/zero of=/swapfile bs=1M count=$new_swap
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    if [ -f /etc/alpine-release ]; then
        echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
        echo "nohup swapon /swapfile" >> /etc/local.d/swap.start
        chmod +x /etc/local.d/swap.start
        rc-update add local
    else
        echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    fi

    echo "虚拟内存大小已调整为${new_swap}MB"
}

docker_app() {
if docker inspect "$docker_name" &>/dev/null; then
    clear
    echo "$docker_name 已安装，访问地址: "
    ip_address
    echo "http:$ipv4_address:$docker_port"
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

            $docker_rum
            clear
            echo "$docker_name 已经安装完成"
            echo "------------------------"
            # 获取外部 IP 地址
            ip_address
            echo "您可以使用以下地址访问:"
            echo "http:$ipv4_address:$docker_port"
            $docker_use
            $docker_passwd
            ;;
        2)
            clear
            docker rm -f "$docker_name"
            docker rmi -f "$docker_img"
            rm -rf "/home/docker/$docker_name"
            echo "应用已卸载"
            ;;
        0)
            # 跳出循环，退出菜单
            ;;
        *)
            # 跳出循环，退出菜单
            ;;
    esac
else
    clear
    echo "安装提示"
    echo "$docker_describe"
    echo "$docker_url"
    echo ""

    # 提示用户确认安装
    read -p "确定安装吗？(Y/N): " choice
    case "$choice" in
        [Yy])
            clear
            # 安装 Docker（请确保有 install_docker 函数）
            install_docker
            $docker_rum
            clear
            echo "$docker_name 已经安装完成"
            echo "------------------------"
            # 获取外部 IP 地址
            ip_address
            echo "您可以使用以下地址访问:"
            echo "http:$ipv4_address:$docker_port"
            $docker_use
            $docker_passwd
            ;;
        [Nn])
            # 用户选择不安装
            ;;
        *)
            # 无效输入
            ;;
    esac
fi

}

cluster_python3() {
    cd ~/cluster/
    curl -sS -O https://raw.githubusercontent.com/kejilion/python-for-vps/main/cluster/$py_task
    python3 ~/cluster/$py_task
}

tmux_run() {
    # Check if the session already exists
    tmux has-session -t $SESSION_NAME 2>/dev/null
    # $? is a special variable that holds the exit status of the last executed command
    if [ $? != 0 ]; then
      # Session doesn't exist, create a new one
      tmux new -s $SESSION_NAME
    else
      # Session exists, attach to it
      tmux attach-session -t $SESSION_NAME
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

echo -e "\033[96m一键脚本工具 v1.1.1 （支持Ubuntu/Debian/CentOS/Alpine系统）\033[0m"
echo -e "\033[96m-输入\033[93m字母【o】\033[96m可快速启动此脚本-\033[0m"
echo "------------------------"
echo "1. 系统信息"
echo "2. 系统更新"
echo "3. 系统清理"
echo "4. 常用工具 ▶"
echo "5. BBR管理 ▶"
echo "6. Docker管理 ▶ "
echo "7. WARP管理 ▶ "
echo "8. 测试脚本合集 ▶ "
echo "9. 甲骨文云脚本合集 ▶ "
echo "10. 备份与还原"
echo "11. 面板工具 ▶ "
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

    country=$(curl -s ipinfo.io/country)
    city=$(curl -s ipinfo.io/city)

    isp_info=$(curl -s ipinfo.io/org)

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
        os_info=$(source /etc/os-release && echo "$PRETTY_NAME")
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


    current_time=$(date "+%Y-%m-%d %I:%M %p")


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
        apt autoremove --purge -y
        apt clean -y
        apt autoclean -y
        apt remove --purge $(dpkg -l | awk '/^rc/ {print $2}') -y
        journalctl --rotate
        journalctl --vacuum-time=1s
        journalctl --vacuum-size=50M
        apt remove --purge $(dpkg -l | awk '/^ii linux-(image|headers)-[^ ]+/{print $2}' | grep -v $(uname -r | sed 's/-.*//') | xargs) -y
    }

    clean_redhat() {
        yum autoremove -y
        yum clean all
        journalctl --rotate
        journalctl --vacuum-time=1s
        journalctl --vacuum-size=50M
        yum remove $(rpm -q kernel | grep -v $(uname -r)) -y
    }

    clean_alpine() {
        apk del --purge $(apk info --installed | awk '{print $1}' | grep -v $(apk info --available | awk '{print $1}'))
        apk autoremove
        apk cache clean
        rm -rf /var/log/*
        rm -rf /var/cache/apk/*

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
      echo "1. curl 下载工具"
      echo "2. wget 下载工具"
      echo "3. sudo 超级管理权限工具"
      echo "4. socat 通信连接工具 （申请域名证书必备）"
      echo "5. htop 系统监控工具"
      echo "6. iftop 网络流量监控工具"
      echo "7. unzip ZIP压缩解压工具"
      echo "8. tar GZ压缩解压工具"
      echo "9. tmux 多路后台运行工具"
      echo "10. ffmpeg 视频编码直播推流工具"
      echo "11. btop 现代化监控工具"
      echo "------------------------"
      echo "31. 全部安装"
      echo "32. 全部卸载"
      echo "------------------------"
      echo "41. 安装指定工具"
      echo "42. 卸载指定工具"
      echo "------------------------"
      echo "0. 返回主菜单"
      echo "------------------------"
      read -p "请输入你的选择: " sub_choice

      case $sub_choice in
          1)
              clear
              install curl
              clear
              echo "工具已安装，使用方法如下："
              curl --help
              ;;
          2)
              clear
              install wget
              clear
              echo "工具已安装，使用方法如下："
              wget --help
              ;;
            3)
              clear
              install sudo
              clear
              echo "工具已安装，使用方法如下："
              sudo --help
              ;;
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
            7)
              clear
              install unzip
              clear
              echo "工具已安装，使用方法如下："
              unzip
              ;;
            8)
              clear
              install tar
              clear
              echo "工具已安装，使用方法如下："
              tar --help
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
          31)
              clear
              install curl wget sudo socat htop iftop unzip tar tmux ffmpeg btop ranger gdu fzf
              ;;

          32)
              clear
              remove htop iftop unzip tmux ffmpeg btop ranger gdu fzf
              ;;

          41)
              clear
              read -p "请输入安装的工具名（wget curl sudo htop）: " installname
              install $installname
              ;;
          42)
              clear
              read -p "请输入卸载的工具名（htop ufw tmux cmatrix）: " removename
              remove $removename
              ;;

          99)
              clear
              server_reboot
              ;;
          0)
              myset
              ;;

          *)
              echo "无效的输入!"
              ;;
      esac
      break_end
  done

    ;;

  5)
    clear
    if [ -f "/etc/alpine-release" ]; then
        while true; do
              clear
              congestion_algorithm=$(sysctl -n net.ipv4.tcp_congestion_control)
              queue_algorithm=$(sysctl -n net.core.default_qdisc)
              echo "当前TCP阻塞算法: $congestion_algorithm $queue_algorithm"

              echo ""
              echo "BBR管理"
              echo "------------------------"
              echo "1. 开启BBR              2. 关闭BBR（会重启）"
              echo "---最新XanMod内核BBR3在主菜单（系统工具）"
              echo "------------------------"
              echo "0. 返回上一级选单"
              echo "------------------------"
              read -p "请输入你的选择: " sub_choice

              case $sub_choice in
                  1)
                    cat > /etc/sysctl.conf << EOF
net.core.default_qdisc=fq_pie
net.ipv4.tcp_congestion_control=bbr
EOF
                    sysctl -p

                      ;;
                  2)
                    sed -i '/net.core.default_qdisc=fq_pie/d' /etc/sysctl.conf
                    sed -i '/net.ipv4.tcp_congestion_control=bbr/d' /etc/sysctl.conf
                    sysctl -p
                    reboot
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
        install wget
        wget --no-check-certificate -O tcpx.sh https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcpx.sh
        chmod +x tcpx.sh
        ./tcpx.sh
    fi

    ;;

  6)
    while true; do
      clear
      echo "▶ Docker管理器"
      echo "------------------------"
      echo "1. 安装更新Docker环境"
      echo "------------------------"
      echo "2. 查看Dcoker全局状态"
      echo "------------------------"
      echo "3. Dcoker容器管理 ▶"
      echo "4. Dcoker镜像管理 ▶"
      echo "5. Dcoker网络管理 ▶"
      echo "6. Dcoker卷管理 ▶"
      echo "------------------------"
      echo "7. 清理无用的docker容器和镜像网络数据卷"
      echo "------------------------"
      echo "8. 卸载Dcoker环境"
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
              echo "Dcoker版本"
              docker --version
              docker-compose --version
              echo ""
              echo "Dcoker镜像列表"
              docker image ls
              echo ""
              echo "Dcoker容器列表"
              docker ps -a
              echo ""
              echo "Dcoker卷列表"
              docker volume ls
              echo ""
              echo "Dcoker网络列表"
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
                          read -p "请输入创建命令: " dockername
                          $dockername
                          ;;

                      2)
                          read -p "请输入容器名: " dockername
                          docker start $dockername
                          ;;
                      3)
                          read -p "请输入容器名: " dockername
                          docker stop $dockername
                          ;;
                      4)
                          read -p "请输入容器名: " dockername
                          docker rm -f $dockername
                          ;;
                      5)
                          read -p "请输入容器名: " dockername
                          docker restart $dockername
                          ;;
                      6)
                          docker start $(docker ps -a -q)
                          ;;
                      7)
                          docker stop $(docker ps -q)
                          ;;
                      8)
                          read -p "确定删除所有容器吗？(Y/N): " choice
                          case "$choice" in
                            [Yy])
                              docker rm -f $(docker ps -a -q)
                              ;;
                            [Nn])
                              ;;
                            *)
                              echo "无效的选择，请输入 Y 或 N。"
                              ;;
                          esac
                          ;;
                      9)
                          docker restart $(docker ps -q)
                          ;;
                      11)
                          read -p "请输入容器名: " dockername
                          docker exec -it $dockername /bin/bash
                          break_end
                          ;;
                      12)
                          read -p "请输入容器名: " dockername
                          docker logs $dockername
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
                          break  # 跳出循环，退出菜单
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
                          docker pull $dockername
                          ;;
                      2)
                          read -p "请输入镜像名: " dockername
                          docker pull $dockername
                          ;;
                      3)
                          read -p "请输入镜像名: " dockername
                          docker rmi -f $dockername
                          ;;
                      4)
                          read -p "确定删除所有镜像吗？(Y/N): " choice
                          case "$choice" in
                            [Yy])
                              docker rmi -f $(docker images -q)
                              ;;
                            [Nn])

                              ;;
                            *)
                              echo "无效的选择，请输入 Y 或 N。"
                              ;;
                          esac
                          ;;
                      0)
                          break  # 跳出循环，退出菜单
                          ;;

                      *)
                          break  # 跳出循环，退出菜单
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
                          docker network create $dockernetwork
                          ;;
                      2)
                          read -p "加入网络名: " dockernetwork
                          read -p "那些容器加入该网络: " dockername
                          docker network connect $dockernetwork $dockername
                          echo ""
                          ;;
                      3)
                          read -p "退出网络名: " dockernetwork
                          read -p "那些容器退出该网络: " dockername
                          docker network disconnect $dockernetwork $dockername
                          echo ""
                          ;;

                      4)
                          read -p "请输入要删除的网络名: " dockernetwork
                          docker network rm $dockernetwork
                          ;;
                      0)
                          break  # 跳出循环，退出菜单
                          ;;

                      *)
                          break  # 跳出循环，退出菜单
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
                          docker volume create $dockerjuan

                          ;;
                      2)
                          read -p "输入删除卷名: " dockerjuan
                          docker volume rm $dockerjuan

                          ;;
                      0)
                          break  # 跳出循环，退出菜单
                          ;;

                      *)
                          break  # 跳出循环，退出菜单
                          ;;
                  esac
              done
              ;;
          7)
              clear
              read -p "确定清理无用的镜像容器网络吗？(Y/N): " choice
              case "$choice" in
                [Yy])
                  docker system prune -af --volumes
                  ;;
                [Nn])
                  ;;
                *)
                  echo "无效的选择，请输入 Y 或 N。"
                  ;;
              esac
              ;;
          8)
              clear
              read -p "确定卸载docker环境吗？(Y/N): " choice
              case "$choice" in
                [Yy])
                  docker rm $(docker ps -a -q) && docker rmi $(docker images -q) && docker network prune
                  remove docker docker-ce docker-compose > /dev/null 2>&1
                  ;;
                [Nn])
                  ;;
                *)
                  echo "无效的选择，请输入 Y 或 N。"
                  ;;
              esac
              ;;
          0)
              myset
              ;;
          *)
              echo "无效的输入!"
              ;;
      esac
      break_end


    done

    ;;


  7)
    clear
    install wget
    wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh [option] [lisence/url/token]
    ;;

  8)
    while true; do
      clear
      echo "▶ 测试脚本合集"
      echo ""
      echo "----解锁状态检测-----------"
      echo "1. ChatGPT解锁状态检测"
      echo "2. Region流媒体解锁测试"
      echo "3. yeahwu流媒体解锁检测"
      echo ""
      echo "----网络线路测速-----------"
      echo "11. besttrace三网回程延迟路由测试"
      echo "12. mtr_trace三网回程线路测试"
      echo "14. nxtrace快速回程测试脚本"
      echo "16. ludashi2020三网线路测试"
      echo ""
      echo "----硬件性能测试----------"
      echo "21. yabs性能测试"
      echo "22. icu/gb5 CPU性能测试脚本"
      echo ""
      echo "----综合性测试-----------"
      echo "31. bench性能测试"
      echo "32. spiritysdx融合怪测评"
      echo ""
      echo "------------------------"
      echo "0. 返回主菜单"
      echo "------------------------"
      read -p "请输入你的选择: " sub_choice

      case $sub_choice in
          1)
              clear
              bash <(curl -Ls https://cdn.jsdelivr.net/gh/missuo/OpenAI-Checker/openai.sh)
              ;;
          2)
              clear
              bash <(curl -L -s check.unlock.media)
              ;;
          3)
              clear
              install wget
              wget -qO- https://github.com/yeahwu/check/raw/main/check.sh | bash
              ;;
          11)
              clear
              install wget
              wget -qO- git.io/besttrace | bash
              ;;
          12)
              clear
              curl https://raw.githubusercontent.com/zhucaidan/mtr_trace/main/mtr_trace.sh | bash
              ;;
          14)
              clear
              curl nxtrace.org/nt |bash
              nexttrace --fast-trace --tcp
              ;;

          16)
              clear
              curl https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh -sSf | sh
              ;;

          21)
              clear
              new_swap=1024
              add_swap
              curl -sL yabs.sh | bash -s -- -i -5
              ;;
          22)
              clear
              new_swap=1024
              add_swap
              bash <(curl -sL bash.icu/gb5)
              ;;

          31)
              clear
              curl -Lso- bench.sh | bash
              ;;
          32)
              clear
              curl -L https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh -o ecs.sh && chmod +x ecs.sh && bash ecs.sh
              ;;


          0)
              myset

              ;;
          *)
              echo "无效的输入!"
              ;;
      esac
      break_end

    done
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
              echo "活跃脚本: CPU占用10-20% 内存占用15% "
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
              myset

              ;;
          *)
              echo "无效的输入!"
              ;;
      esac
      break_end

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
      chmod +x ${useip}_beifen.sh

      sed -i "s/0.0.0.0/$useip/g" ${useip}_beifen.sh
      sed -i "s/123456/$usepasswd/g" ${useip}_beifen.sh

      echo "------------------------"
      echo "1. 每周备份                 2. 每天备份"
      read -p "请输入你的选择: " dingshi

      case $dingshi in
          1)
              read -p "选择每周备份的星期几 (0-6，0代表星期日): " weekday
              (crontab -l ; echo "0 0 * * $weekday ./${useip}_beifen.sh") | crontab - > /dev/null 2>&1
              ;;
          2)
              read -p "选择每天备份的时间（小时，0-23）: " hour
              (crontab -l ; echo "0 $hour * * * ./${useip}_beifen.sh") | crontab - > /dev/null 2>&1
              ;;
          *)
              break  # 跳出
              ;;
      esac

      install sshpass

      ;;

    3)
      clear
      cd /home/ && ls -t /home/*.tar.gz | head -1 | xargs -I {} tar -xzf {}
      check_port
      install_dependency
      install_docker

      ;;

    0)
        myset
      ;;

    *)
        echo "无效的输入!"
    esac
    break_end

  done
      ;;

  11)
    while true; do
      clear
      echo "▶ 面板工具"
      echo "------------------------"
      echo "1. 宝塔面板修改版                       "
      echo "3. 1Panel新一代管理面板                 4. NginxProxyManager可视化面板"
      echo "5. AList多存储文件列表程序              6. Ubuntu远程桌面网页版"
      echo "7. 哪吒探针VPS监控面板                  8. QB离线BT磁力下载面板"
      echo "12. 青龙面板定时任务管理平台"
      echo "13. Cloudreve网盘                       14. 简单图床图片管理程序"
      echo "18. onlyoffice在线办公OFFICE              19. 雷池WAF防火墙面板"
      echo "20. portainer容器管理面板               21. VScode网页版"
      echo "22. UptimeKuma监控工具               24. Webtop远程桌面网页版"
      echo "25. Nextcloud网盘                       26. QD-Today定时任务管理框架"
      echo "27. Dockge容器堆栈管理面板              29. searxng聚合搜索站"
      echo "31. StirlingPDF工具大全                 32. drawio免费的在线图表软件"
      echo "33. Sun-Panel导航面板"
      echo "------------------------"
      echo "51. PVE开小鸡面板"
      echo "------------------------"
      echo "0. 返回主菜单"
      echo "------------------------"
      read -p "请输入你的选择: " sub_choice

      case $sub_choice in
          1)
            if [ -f "/etc/init.d/bt" ] && [ -d "/www/server/panel" ]; then
                clear
                echo "宝塔面板已安装，应用操作"
                echo ""
                echo "------------------------"
                echo "1. 管理宝塔面板           2. 卸载宝塔面板"
                echo "------------------------"
                echo "0. 返回上一级选单"
                echo "------------------------"
                read -p "请输入你的选择: " sub_choice

                case $sub_choice in
                    1)
                        clear
                        # 更新宝塔面板操作
                        bt
                        ;;
                    2)
                        clear
                        curl -o bt-uninstall.sh http://download.bt.cn/install/bt-uninstall.sh > /dev/null 2>&1
                        chmod +x bt-uninstall.sh
                        ./bt-uninstall.sh
                        ;;
                    0)
                        break  # 跳出循环，退出菜单
                        ;;
                    *)
                        break  # 跳出循环，退出菜单
                        ;;
                esac
            else
                clear
                echo "安装提示"
                echo "如果您已经安装了其他面板工具或者LDNMP建站环境，建议先卸载，再安装宝塔面板！"
                echo "会根据系统自动安装，支持Debian，Ubuntu，Centos"
                echo "官网介绍: https://www.bt.cn/new/index.html"
                echo ""

                # 获取当前系统类型
                get_system_type() {
                    if [ -f /etc/os-release ]; then
                        . /etc/os-release
                        if [ "$ID" == "centos" ]; then
                            echo "centos"
                        elif [ "$ID" == "ubuntu" ]; then
                            echo "ubuntu"
                        elif [ "$ID" == "debian" ]; then
                            echo "debian"
                        else
                            echo "unknown"
                        fi
                    else
                        echo "unknown"
                    fi
                }

                system_type=$(get_system_type)

                if [ "$system_type" == "unknown" ]; then
                    echo "不支持的操作系统类型"
                else
                    read -p "确定安装宝塔吗？(Y/N): " choice
                    case "$choice" in
                        [Yy])
                            iptables_open
                            install wget
                            if [ "$system_type" == "centos" ]; then
                                yum install -y wget && wget -O install.sh https://install.baota.sbs/install/install_6.0.sh && sh install.sh
                            elif [ "$system_type" == "ubuntu" ]; then
                                wget -O install.sh https://install.baota.sbs/install/install_6.0.sh && bash install.sh
                            elif [ "$system_type" == "debian" ]; then
                                wget -O install.sh https://install.baota.sbs/install/install_6.0.sh && bash install.sh
                            fi
                            ;;
                        [Nn])
                            ;;
                        *)
                            ;;
                    esac
                fi
            fi
              ;;

          3)
            if command -v 1pctl &> /dev/null; then
                clear
                echo "1Panel已安装，应用操作"
                echo ""
                echo "------------------------"
                echo "1. 查看1Panel信息           2. 卸载1Panel"
                echo "------------------------"
                echo "0. 返回上一级选单"
                echo "------------------------"
                read -p "请输入你的选择: " sub_choice

                case $sub_choice in
                    1)
                        clear
                        1pctl user-info
                        1pctl update password
                        ;;
                    2)
                        clear
                        1pctl uninstall

                        ;;
                    0)
                        break  # 跳出循环，退出菜单
                        ;;
                    *)
                        break  # 跳出循环，退出菜单
                        ;;
                esac
            else

                clear
                echo "安装提示"
                echo "如果您已经安装了其他面板工具或者LDNMP建站环境，建议先卸载，再安装1Panel！"
                echo "会根据系统自动安装，支持Debian，Ubuntu，Centos"
                echo "官网介绍: https://1panel.cn/"
                echo ""
                # 获取当前系统类型
                get_system_type() {
                  if [ -f /etc/os-release ]; then
                    . /etc/os-release
                    if [ "$ID" == "centos" ]; then
                      echo "centos"
                    elif [ "$ID" == "ubuntu" ]; then
                      echo "ubuntu"
                    elif [ "$ID" == "debian" ]; then
                      echo "debian"
                    else
                      echo "unknown"
                    fi
                  else
                    echo "unknown"
                  fi
                }

                system_type=$(get_system_type)

                if [ "$system_type" == "unknown" ]; then
                  echo "不支持的操作系统类型"
                else
                  read -p "确定安装1Panel吗？(Y/N): " choice
                  case "$choice" in
                    [Yy])
                      iptables_open
                      install_docker
                      if [ "$system_type" == "centos" ]; then
                        curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o quick_start.sh && sh quick_start.sh
                      elif [ "$system_type" == "ubuntu" ]; then
                        curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o quick_start.sh && bash quick_start.sh
                      elif [ "$system_type" == "debian" ]; then
                        curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o quick_start.sh && bash quick_start.sh
                      fi
                      ;;
                    [Nn])
                      ;;
                    *)
                      ;;
                  esac
                fi
            fi
            ;;


          4)

            docker_name="npm"
            docker_img="chishin/nginx-proxy-manager-zh:release"
            docker_port=81
            docker_rum="docker run -d \
                          --name=$docker_name \
                          -p 80:80 \
                          -p 81:$docker_port \
                          -p 443:443 \
                          -v /home/docker/npm/data:/data \
                          -v /home/docker/npm/letsencrypt:/etc/letsencrypt \
                          --restart=always \
                          $docker_img"
            docker_describe="如果您已经安装了其他面板工具或者LDNMP建站环境，建议先卸载，再安装npm！"
            docker_url="官网介绍: https://nginxproxymanager.com/"
            docker_use="echo \"初始用户名: admin@example.com\""
            docker_passwd="echo \"初始密码: changeme\""

            docker_app

              ;;

          5)

            docker_name="alist"
            docker_img="xhofe/alist:latest"
            docker_port=5244
            docker_rum="docker run -d \
                                --restart=always \
                                -v /home/docker/alist:/opt/alist/data \
                                -p 5244:5244 \
                                -e PUID=0 \
                                -e PGID=0 \
                                -e UMASK=022 \
                                --name="alist" \
                                xhofe/alist:latest"
            docker_describe="一个支持多种存储，支持网页浏览和 WebDAV 的文件列表程序，由 gin 和 Solidjs 驱动"
            docker_url="官网介绍: https://alist.nn.ci/zh/"
            docker_use="docker exec -it alist ./alist admin random"
            docker_passwd=""

            docker_app

              ;;

          6)
            docker_name="ubuntu-novnc"
            docker_img="fredblgr/ubuntu-novnc:20.04"
            docker_port=6080
            rootpasswd=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c16)
            docker_rum="docker run -d \
                                --name ubuntu-novnc \
                                -p 6080:80 \
                                -v /home/docker/ubuntu-novnc:/workspace:rw \
                                -e HTTP_PASSWORD=$rootpasswd \
                                -e RESOLUTION=1280x720 \
                                --restart=always \
                                fredblgr/ubuntu-novnc:20.04"
            docker_describe="一个网页版Ubuntu远程桌面，挺好用的！"
            docker_url="官网介绍: https://hub.docker.com/r/fredblgr/ubuntu-novnc"
            docker_use="echo \"用户名: root\""
            docker_passwd="echo \"密码: $rootpasswd\""

            docker_app

              ;;
          7)
            clear
            curl -L https://raw.githubusercontent.com/naiba/nezha/master/script/install.sh  -o nezha.sh && chmod +x nezha.sh
            ./nezha.sh
              ;;

          8)

            docker_name="qbittorrent"
            docker_img="lscr.io/linuxserver/qbittorrent:latest"
            docker_port=8081
            docker_rum="docker run -d \
                                  --name=qbittorrent \
                                  -e PUID=1000 \
                                  -e PGID=1000 \
                                  -e TZ=Etc/UTC \
                                  -e WEBUI_PORT=8081 \
                                  -p 8081:8081 \
                                  -p 6881:6881 \
                                  -p 6881:6881/udp \
                                  -v /home/docker/qbittorrent/config:/config \
                                  -v /home/docker/qbittorrent/downloads:/downloads \
                                  --restart unless-stopped \
                                  lscr.io/linuxserver/qbittorrent:latest"
            docker_describe="qbittorrent离线BT磁力下载服务"
            docker_url="官网介绍: https://hub.docker.com/r/linuxserver/qbittorrent"
            docker_use="sleep 3"
            docker_passwd="docker logs qbittorrent"

            docker_app

              ;;

          12)
            docker_name="qinglong"
            docker_img="whyour/qinglong:latest"
            docker_port=5700
            docker_rum="docker run -d \
                      -v /home/docker/qinglong/data:/ql/data \
                      -p 5700:5700 \
                      --name qinglong \
                      --hostname qinglong \
                      --restart unless-stopped \
                      whyour/qinglong:latest"
            docker_describe="青龙面板是一个定时任务管理平台"
            docker_url="官网介绍: https://github.com/whyour/qinglong"
            docker_use=""
            docker_passwd=""
            docker_app

              ;;
          13)
            if docker inspect cloudreve &>/dev/null; then

                    clear
                    echo "cloudreve已安装，访问地址: "
                    ip_address
                    echo "http:$ipv4_address:5212"
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
                            docker rm -f cloudreve
                            docker rmi -f cloudreve/cloudreve:latest
                            docker rm -f aria2
                            docker rmi -f p3terx/aria2-pro

                            cd /home/ && mkdir -p docker/cloud && cd docker/cloud && mkdir temp_data && mkdir -vp cloudreve/{uploads,avatar} && touch cloudreve/conf.ini && touch cloudreve/cloudreve.db && mkdir -p aria2/config && mkdir -p data/aria2 && chmod -R 777 data/aria2
                            curl -o /home/docker/cloud/docker-compose.yml https://raw.githubusercontent.com/kejilion/docker/main/cloudreve-docker-compose.yml
                            cd /home/docker/cloud/ && docker-compose up -d


                            clear
                            echo "cloudreve已经安装完成"
                            echo "------------------------"
                            echo "您可以使用以下地址访问cloudreve:"
                            ip_address
                            echo "http:$ipv4_address:5212"
                            sleep 3
                            docker logs cloudreve
                            echo ""
                            ;;
                        2)
                            clear
                            docker rm -f cloudreve
                            docker rmi -f cloudreve/cloudreve:latest
                            docker rm -f aria2
                            docker rmi -f p3terx/aria2-pro
                            rm -rf /home/docker/cloud
                            echo "应用已卸载"
                            ;;
                        0)
                            break  # 跳出循环，退出菜单
                            ;;
                        *)
                            break  # 跳出循环，退出菜单
                            ;;
                    esac
            else
                clear
                echo "安装提示"
                echo "cloudreve是一个支持多家云存储的网盘系统"
                echo "官网介绍: https://cloudreve.org/"
                echo ""

                # 提示用户确认安装
                read -p "确定安装cloudreve吗？(Y/N): " choice
                case "$choice" in
                    [Yy])
                    clear
                    install_docker
                    cd /home/ && mkdir -p docker/cloud && cd docker/cloud && mkdir temp_data && mkdir -vp cloudreve/{uploads,avatar} && touch cloudreve/conf.ini && touch cloudreve/cloudreve.db && mkdir -p aria2/config && mkdir -p data/aria2 && chmod -R 777 data/aria2
                    curl -o /home/docker/cloud/docker-compose.yml https://raw.githubusercontent.com/kejilion/docker/main/cloudreve-docker-compose.yml
                    cd /home/docker/cloud/ && docker-compose up -d


                    clear
                    echo "cloudreve已经安装完成"
                    echo "------------------------"
                    echo "您可以使用以下地址访问cloudreve:"
                    ip_address
                    echo "http:$ipv4_address:5212"
                    sleep 3
                    docker logs cloudreve
                    echo ""

                        ;;
                    [Nn])
                        ;;
                    *)
                        ;;
                esac
            fi

              ;;

          14)
            docker_name="easyimage"
            docker_img="ddsderek/easyimage:latest"
            docker_port=85
            docker_rum="docker run -d \
                      --name easyimage \
                      -p 85:80 \
                      -e TZ=Asia/Shanghai \
                      -e PUID=1000 \
                      -e PGID=1000 \
                      -v /home/docker/easyimage/config:/app/web/config \
                      -v /home/docker/easyimage/i:/app/web/i \
                      --restart unless-stopped \
                      ddsderek/easyimage:latest"
            docker_describe="简单图床是一个简单的图床程序"
            docker_url="官网介绍: https://github.com/icret/EasyImages2.0"
            docker_use=""
            docker_passwd=""
            docker_app
              ;;

          18)

            docker_name="onlyoffice"
            docker_img="onlyoffice/documentserver"
            docker_port=8082
            docker_rum="docker run -d -p 8082:80 \
                        --restart=always \
                        --name onlyoffice \
                        -v /home/docker/onlyoffice/DocumentServer/logs:/var/log/onlyoffice  \
                        -v /home/docker/onlyoffice/DocumentServer/data:/var/www/onlyoffice/Data  \
                         onlyoffice/documentserver"
            docker_describe="onlyoffice是一款开源的在线office工具，太强大了！"
            docker_url="官网介绍: https://www.onlyoffice.com/"
            docker_use=""
            docker_passwd=""
            docker_app

              ;;

          19)

            if docker inspect safeline-tengine &>/dev/null; then

                    clear
                    echo "雷池已安装，访问地址: "
                    ip_address
                    echo "http:$ipv4_address:9443"
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
                            echo "暂不支持"
                            echo ""
                            ;;
                        2)

                            clear
                            echo "cd命令到安装目录下执行: docker compose down"
                            echo ""
                            ;;
                        0)
                            break  # 跳出循环，退出菜单
                            ;;
                        *)
                            break  # 跳出循环，退出菜单
                            ;;
                    esac
            else
                clear
                echo "安装提示"
                echo "雷池是长亭科技开发的WAF站点防火墙程序面板，可以反代站点进行自动化防御"
                echo "80和443端口不能被占用，无法与宝塔，1panel，npm，ldnmp建站共存"
                echo "官网介绍: https://github.com/chaitin/safeline"
                echo ""

                # 提示用户确认安装
                read -p "确定安装吗？(Y/N): " choice
                case "$choice" in
                    [Yy])
                    clear
                    install_docker
                    bash -c "$(curl -fsSLk https://waf-ce.chaitin.cn/release/latest/setup.sh)"

                    clear
                    echo "雷池WAF面板已经安装完成"
                    echo "------------------------"
                    echo "您可以使用以下地址访问:"
                    ip_address
                    echo "http:$ipv4_address:9443"
                    echo ""

                        ;;
                    [Nn])
                        ;;
                    *)
                        ;;
                esac
            fi

              ;;

          20)
            docker_name="portainer"
            docker_img="outlovecn/portainer-cn:latest"
            docker_port=9050
            docker_rum="docker run -d \
                    --name portainer \
                    -p 9050:9000 \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    -v /home/docker/portainer:/data \
                    --restart always \
                    portainer/portainer"
            docker_describe="portainer是一个轻量级的docker容器管理面板"
            docker_url="官网介绍: https://www.portainer.io/"
            docker_use=""
            docker_passwd=""
            docker_app

              ;;

          21)
            docker_name="vscode-web"
            docker_img="codercom/code-server"
            docker_port=8180
            docker_rum="docker run -d -p 8180:8080 -v /home/docker/vscode-web:/home/coder/.local/share/code-server --name vscode-web --restart always codercom/code-server"
            docker_describe="VScode是一款强大的在线代码编写工具"
            docker_url="官网介绍: https://github.com/coder/code-server"
            docker_use="sleep 3"
            docker_passwd="docker exec vscode-web cat /home/coder/.config/code-server/config.yaml"
            docker_app
              ;;
          22)
            docker_name="uptime-kuma"
            docker_img="louislam/uptime-kuma:latest"
            docker_port=3003
            docker_rum="docker run -d \
                            --name=uptime-kuma \
                            -p 3003:3001 \
                            -v /home/docker/uptime-kuma/uptime-kuma-data:/app/data \
                            --restart=always \
                            louislam/uptime-kuma:latest"
            docker_describe="Uptime Kuma 易于使用的自托管监控工具"
            docker_url="官网介绍: https://github.com/louislam/uptime-kuma"
            docker_use=""
            docker_passwd=""
            docker_app
              ;;

          24)
            docker_name="webtop"
            docker_img="lscr.io/linuxserver/webtop:latest"
            docker_port=3083
            docker_rum="docker run -d \
                          --name=webtop \
                          --security-opt seccomp=unconfined \
                          -e PUID=1000 \
                          -e PGID=1000 \
                          -e TZ=Etc/UTC \
                          -e SUBFOLDER=/ \
                          -e TITLE=Webtop \
                          -e LC_ALL=zh_CN.UTF-8 \
                          -e DOCKER_MODS=linuxserver/mods:universal-package-install \
                          -e INSTALL_PACKAGES=font-noto-cjk \
                          -p 3083:3000 \
                          -v /home/docker/webtop/data:/config \
                          -v /var/run/docker.sock:/var/run/docker.sock \
                          --device /dev/dri:/dev/dri \
                          --shm-size="1gb" \
                          --restart unless-stopped \
                          lscr.io/linuxserver/webtop:latest"

            docker_describe="webtop基于 Alpine、Ubuntu、Fedora 和 Arch 的容器，包含官方支持的完整桌面环境，可通过任何现代 Web 浏览器访问"
            docker_url="官网介绍: https://docs.linuxserver.io/images/docker-webtop/"
            docker_use=""
            docker_passwd=""
            docker_app
              ;;

          25)
            docker_name="nextcloud"
            docker_img="nextcloud:latest"
            docker_port=8989
            rootpasswd=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c16)
            docker_rum="docker run -d --name nextcloud --restart=always -p 8989:80 -v /home/docker/nextcloud:/var/www/html -e NEXTCLOUD_ADMIN_USER=nextcloud -e NEXTCLOUD_ADMIN_PASSWORD=$rootpasswd nextcloud"
            docker_describe="Nextcloud拥有超过 400,000 个部署，是您可以下载的最受欢迎的本地内容协作平台"
            docker_url="官网介绍: https://nextcloud.com/"
            docker_use="echo \"账号: nextcloud  密码: $rootpasswd\""
            docker_passwd=""
            docker_app
              ;;

          26)
            docker_name="qd"
            docker_img="qdtoday/qd:latest"
            docker_port=8923
            docker_rum="docker run -d --name qd -p 8923:80 -v /home/docker/qd/config:/usr/src/app/config qdtoday/qd"
            docker_describe="QD-Today是一个HTTP请求定时任务自动执行框架"
            docker_url="官网介绍: https://qd-today.github.io/qd/zh_CN/"
            docker_use=""
            docker_passwd=""
            docker_app
              ;;
          27)
            docker_name="dockge"
            docker_img="louislam/dockge:latest"
            docker_port=5003
            docker_rum="docker run -d --name dockge --restart unless-stopped -p 5003:5001 -v /var/run/docker.sock:/var/run/docker.sock -v /home/docker/dockge/data:/app/data -v  /home/docker/dockge/stacks:/opt/stacks -e DOCKGE_STACKS_DIR=/home/docker/dockge/stacks louislam/dockge"
            docker_describe="dockge是一个可视化的docker-compose容器管理面板"
            docker_url="官网介绍: https://github.com/louislam/dockge"
            docker_use=""
            docker_passwd=""
            docker_app
              ;;

          29)
            docker_name="searxng"
            docker_img="alandoyle/searxng:latest"
            docker_port=8700
            docker_rum="docker run --name=searxng \
                            -d --init \
                            --restart=unless-stopped \
                            -v /home/docker/searxng/config:/etc/searxng \
                            -v /home/docker/searxng/templates:/usr/local/searxng/searx/templates/simple \
                            -v /home/docker/searxng/theme:/usr/local/searxng/searx/static/themes/simple \
                            -p 8700:8080/tcp \
                            alandoyle/searxng:latest"
            docker_describe="searxng是一个私有且隐私的搜索引擎站点"
            docker_url="官网介绍: https://hub.docker.com/r/alandoyle/searxng"
            docker_use=""
            docker_passwd=""
            docker_app
              ;;

          31)
            docker_name="s-pdf"
            docker_img="frooodle/s-pdf:latest"
            docker_port=8020
            docker_rum="docker run -d \
                            --name s-pdf \
                            --restart=always \
                             -p 8020:8080 \
                             -v /home/docker/s-pdf/trainingData:/usr/share/tesseract-ocr/5/tessdata \
                             -v /home/docker/s-pdf/extraConfigs:/configs \
                             -v /home/docker/s-pdf/logs:/logs \
                             -e DOCKER_ENABLE_SECURITY=false \
                             frooodle/s-pdf:latest"
            docker_describe="这是一个强大的本地托管基于 Web 的 PDF 操作工具，使用 docker，允许您对 PDF 文件执行各种操作，例如拆分合并、转换、重新组织、添加图像、旋转、压缩等。"
            docker_url="官网介绍: https://github.com/Stirling-Tools/Stirling-PDF"
            docker_use=""
            docker_passwd=""
            docker_app
              ;;

          32)
            docker_name="drawio"
            docker_img="jgraph/drawio"
            docker_port=7080
            docker_rum="docker run -d --restart=always --name drawio -p 7080:8080 -v /home/docker/drawio:/var/lib/drawio jgraph/drawio"
            docker_describe="这是一个强大图表绘制软件。思维导图，拓扑图，流程图，都能画"
            docker_url="官网介绍: https://www.drawio.com/"
            docker_use=""
            docker_passwd=""
            docker_app
              ;;

          33)
            docker_name="sun-panel"
            docker_img="hslr/sun-panel"
            docker_port=3009
            docker_rum="docker run -d --restart=always -p 3009:3002 \
                            -v /home/docker/sun-panel/conf:/app/conf \
                            -v /home/docker/sun-panel/uploads:/app/uploads \
                            -v /home/docker/sun-panel/database:/app/database \
                            --name sun-panel \
                            hslr/sun-panel"
            docker_describe="Sun-Panel服务器、NAS导航面板、Homepage、浏览器首页"
            docker_url="官网介绍: https://doc.sun-panel.top/zh_cn/"
            docker_use="echo \"账号: admin@sun.cc  密码: 12345678\""
            docker_passwd=""
            docker_app
              ;;

          51)
          clear
          curl -L https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/install_pve.sh -o install_pve.sh && chmod +x install_pve.sh && bash install_pve.sh
              ;;
          0)
              myset
              ;;
          *)
              echo "无效的输入!"
              ;;
      esac
      break_end

    done
    ;;

  12)
    while true; do
      clear
      echo "▶ 我的工作区"
      echo "系统将为你提供5个后台运行的工作区，你可以用来执行长时间的任务"
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
              myset
              ;;
          *)
              echo "无效的输入!"
              ;;
      esac
      break_end

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
              echo "alias $kuaijiejian='~/myset.sh'" >> ~/.bashrc
              source ~/.bashrc
              echo "快捷键已设置"
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
                exit 1
            fi

            # 检测安装Python3的版本
            VERSION=$(python3 -V 2>&1 | awk '{print $2}')

            # 获取最新Python3版本
            PY_VERSION=$(curl -s https://www.python.org/ | grep "downloads/release" | grep -o 'Python [0-9.]*' | grep -o '[0-9.]*')

            # 卸载Python3旧版本
            if [[ $VERSION == "3"* ]]; then
                echo -e "${YELLOW}你的Python3版本是${NC}${RED}${VERSION}${NC}，${YELLOW}最新版本是${NC}${RED}${PY_VERSION}${NC}"
                read -p "是否确认升级最新版Python3？默认不升级 [y/N]: " CONFIRM
                if [[ $CONFIRM == "y" ]]; then
                    if [[ $OS == "CentOS" ]]; then
                        echo ""
                        rm-rf /usr/local/python3* >/dev/null 2>&1
                    else
                        apt --purge remove python3 python3-pip -y
                        rm-rf /usr/local/python3*
                    fi
                else
                    echo -e "${YELLOW}已取消升级Python3${NC}"
                    exit 1
                fi
            else
                echo -e "${RED}检测到没有安装Python3。${NC}"
                read -p "是否确认安装最新版Python3？默认安装 [Y/n]: " CONFIRM
                if [[ $CONFIRM != "n" ]]; then
                    echo -e "${GREEN}开始安装最新版Python3...${NC}"
                else
                    echo -e "${YELLOW}已取消安装Python3${NC}"
                    exit 1
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
                exit 1
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
              clear
              #!/bin/bash

              # 去掉 #Port 的注释
              sed -i 's/#Port/Port/' /etc/ssh/sshd_config

              # 读取当前的 SSH 端口号
              current_port=$(grep -E '^ *Port [0-9]+' /etc/ssh/sshd_config | awk '{print $2}')

              # 打印当前的 SSH 端口号
              echo "当前的 SSH 端口号是: $current_port"

              echo "------------------------"

              # 提示用户输入新的 SSH 端口号
              read -p "请输入新的 SSH 端口号: " new_port

              # 备份 SSH 配置文件
              cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

              # 替换 SSH 配置文件中的端口号
              sed -i "s/Port [0-9]\+/Port $new_port/g" /etc/ssh/sshd_config

              # 重启 SSH 服务
              service sshd restart

              echo "SSH 端口已修改为: $new_port"

              clear
              iptables_open
              remove iptables-persistent ufw firewalld iptables-services > /dev/null 2>&1

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
                echo "44. Windows Server 2016"
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
            echo "$new_username ALL=(ALL:ALL) ALL" | sudo tee -a /etc/sudoers

            # 禁用ROOT用户登录
            sudo passwd -l root

            echo "操作已完成。"
            ;;


          10)
            clear
            ipv6_disabled=$(sysctl -n net.ipv6.conf.all.disable_ipv6)

            echo ""
            if [ "$ipv6_disabled" -eq 1 ]; then
                echo "当前网络优先级设置: IPv4 优先"
            else
                echo "当前网络优先级设置: IPv6 优先"
            fi
            echo "------------------------"

            echo ""
            echo "切换的网络优先级"
            echo "------------------------"
            echo "1. IPv4 优先          2. IPv6 优先"
            echo "------------------------"
            read -p "选择优先的网络: " choice

            case $choice in
                1)
                    sysctl -w net.ipv6.conf.all.disable_ipv6=1 > /dev/null 2>&1
                    echo "已切换为 IPv4 优先"
                    ;;
                2)
                    sysctl -w net.ipv6.conf.all.disable_ipv6=0 > /dev/null 2>&1
                    echo "已切换为 IPv6 优先"
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
                       echo "$new_username ALL=(ALL:ALL) ALL" | sudo tee -a /etc/sudoers

                       echo "操作已完成。"

                          ;;
                      3)
                       read -p "请输入用户名: " username
                       # 赋予新用户sudo权限
                       echo "$username ALL=(ALL:ALL) ALL" | sudo tee -a /etc/sudoers
                          ;;
                      4)
                       read -p "请输入用户名: " username
                       # 从sudoers文件中移除用户的sudo权限
                       sudo sed -i "/^$username\sALL=(ALL:ALL)\sALL/d" /etc/sudoers

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
                          break  # 跳出循环，退出菜单
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
                      curl -sS -O https://raw.gitmirror.com/chrimast/docker/main/f2b.sh && chmod +x f2b.sh && ./f2b.sh
                      fail2ban-client status
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
                current_timezone=$(timedatectl show --property=Timezone --value)

                # 获取当前系统时间
                current_time=$(date +"%Y-%m-%d %H:%M:%S")

                # 显示时区和时间
                echo "当前系统时区：$current_timezone"
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
                    1) timedatectl set-timezone Asia/Shanghai ;;
                    2) timedatectl set-timezone Asia/Hong_Kong ;;
                    3) timedatectl set-timezone Asia/Tokyo ;;
                    4) timedatectl set-timezone Asia/Seoul ;;
                    5) timedatectl set-timezone Asia/Singapore ;;
                    6) timedatectl set-timezone Asia/Kolkata ;;
                    7) timedatectl set-timezone Asia/Dubai ;;
                    8) timedatectl set-timezone Australia/Sydney ;;
                    11) timedatectl set-timezone Europe/London ;;
                    12) timedatectl set-timezone Europe/Paris ;;
                    13) timedatectl set-timezone Europe/Berlin ;;
                    14) timedatectl set-timezone Europe/Moscow ;;
                    15) timedatectl set-timezone Europe/Amsterdam ;;
                    16) timedatectl set-timezone Europe/Madrid ;;
                    21) timedatectl set-timezone America/Los_Angeles ;;
                    22) timedatectl set-timezone America/New_York ;;
                    23) timedatectl set-timezone America/Vancouver ;;
                    24) timedatectl set-timezone America/Mexico_City ;;
                    25) timedatectl set-timezone America/Sao_Paulo ;;
                    26) timedatectl set-timezone America/Argentina/Buenos_Aires ;;
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
            cat > /etc/sysctl.conf << EOF
net.core.default_qdisc=fq_pie
net.ipv4.tcp_congestion_control=bbr
EOF
            sysctl -p
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
                  echo "3. 开放所有端口              4. 关闭所有端口"
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
                      current_port=$(grep -E '^ *Port [0-9]+' /etc/ssh/sshd_config | awk '{print $2}')

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
                      current_port=$(grep -E '^ *Port [0-9]+' /etc/ssh/sshd_config | awk '{print $2}')

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
          iptables_open
          remove iptables-persistent ufw
          rm /etc/iptables/rules.v4

          apt update -y && apt install -y iptables-persistent

          current_port=$(grep -E '^ *Port [0-9]+' /etc/ssh/sshd_config | awk '{print $2}')

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
          clear
          current_hostname=$(hostname)
          echo "当前主机名: $current_hostname"
          read -p "是否要更改主机名？(y/n): " answer
          if [ "$answer" == "y" ]; then
              # 获取新的主机名
              read -p "请输入新的主机名: " new_hostname
              if [ -n "$new_hostname" ]; then
                  if [ -f /etc/alpine-release ]; then
                      # Alpine
                      echo "$new_hostname" > /etc/hostname
                      hostname "$new_hostname"
                  else
                      # 其他系统，如 Debian, Ubuntu, CentOS 等
                      hostnamectl set-hostname "$new_hostname"
                      sed -i "s/$current_hostname/$new_hostname/g" /etc/hostname
                      systemctl restart systemd-hostnamed
                  fi
                  echo "主机名已更改为: $new_hostname"
              else
                  echo "无效的主机名。未更改主机名。"
                  exit 1
              fi
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
          initial_debian_source=""

          # 定义 CentOS 更新源
          aliyun_centos_source="http://mirrors.aliyun.com/centos/"
          official_centos_source="http://mirror.centos.org/centos/"
          initial_centos_source=""

          # 获取当前更新源并设置初始源
          case "$ID" in
              ubuntu)
                  initial_ubuntu_source=$(grep -E '^deb ' /etc/apt/sources.list | head -n 1 | awk '{print $2}')
                  ;;
              debian)
                  initial_debian_source=$(grep -E '^deb ' /etc/apt/sources.list | head -n 1 | awk '{print $2}')
                  ;;
              centos)
                  initial_centos_source=$(awk -F= '/^baseurl=/ {print $2}' /etc/yum.repos.d/CentOS-Base.repo | head -n 1 | tr -d ' ')
                  ;;
              *)
                  echo "未知系统，无法执行切换源脚本"
                  exit 1
                  ;;
          esac

          # 备份当前源
          backup_sources() {
              case "$ID" in
                  ubuntu)
                      cp /etc/apt/sources.list /etc/apt/sources.list.bak
                      ;;
                  debian)
                      cp /etc/apt/sources.list /etc/apt/sources.list.bak
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
                      exit 1
                      ;;
              esac
              echo "已备份当前更新源为 /etc/apt/sources.list.bak 或 /etc/yum.repos.d/CentOS-Base.repo.bak"
          }

          # 还原初始更新源
          restore_initial_source() {
              case "$ID" in
                  ubuntu)
                      cp /etc/apt/sources.list.bak /etc/apt/sources.list
                      ;;
                  debian)
                      cp /etc/apt/sources.list.bak /etc/apt/sources.list
                      ;;
                  centos)
                      cp /etc/yum.repos.d/CentOS-Base.repo.bak /etc/yum.repos.d/CentOS-Base.repo
                      ;;
                  *)
                      echo "未知系统，无法执行还原操作"
                      exit 1
                      ;;
              esac
              echo "已还原初始更新源"
          }

          # 函数：切换更新源
          switch_source() {
              case "$ID" in
                  ubuntu)
                      sed -i 's|'"$initial_ubuntu_source"'|'"$1"'|g' /etc/apt/sources.list
                      ;;
                  debian)
                      sed -i 's|'"$initial_debian_source"'|'"$1"'|g' /etc/apt/sources.list
                      ;;
                  centos)
                      sed -i "s|^baseurl=.*$|baseurl=$1|g" /etc/yum.repos.d/CentOS-Base.repo
                      ;;
                  *)
                      echo "未知系统，无法执行切换操作"
                      exit 1
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
                      exit 1
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
                              switch_source $aliyun_ubuntu_source
                              ;;
                          debian)
                              switch_source $aliyun_debian_source
                              ;;
                          centos)
                              switch_source $aliyun_centos_source
                              ;;
                          *)
                              echo "未知系统，无法执行切换操作"
                              exit 1
                              ;;
                      esac
                      echo "已切换到阿里云源"
                      ;;
                  2)
                      backup_sources
                      case "$ID" in
                          ubuntu)
                              switch_source $official_ubuntu_source
                              ;;
                          debian)
                              switch_source $official_debian_source
                              ;;
                          centos)
                              switch_source $official_centos_source
                              ;;
                          *)
                              echo "未知系统，无法执行切换操作"
                              exit 1
                              ;;
                      esac
                      echo "已切换到官方源"
                      ;;
                  3)
                      backup_sources
                      case "$ID" in
                          ubuntu)
                              switch_source $initial_ubuntu_source
                              ;;
                          debian)
                              switch_source $initial_debian_source
                              ;;
                          centos)
                              switch_source $initial_centos_source
                              ;;
                          *)
                              echo "未知系统，无法执行切换操作"
                              exit 1
                              ;;
                      esac
                      echo "已切换到初始更新源"
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
                  crontab -l
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
                          read -p "请输入新任务的执行命令: " newquest
                          echo "------------------------"
                          echo "1. 每周任务                 2. 每天任务"
                          read -p "请输入你的选择: " dingshi

                          case $dingshi in
                              1)
                                  read -p "选择周几执行任务？ (0-6，0代表星期日): " weekday
                                  (crontab -l ; echo "0 0 * * $weekday $newquest") | crontab - > /dev/null 2>&1
                                  ;;
                              2)
                                  read -p "选择每天几点执行任务？（小时，0-23）: " hour
                                  (crontab -l ; echo "0 $hour * * * $newquest") | crontab - > /dev/null 2>&1
                                  ;;
                              *)
                                  break  # 跳出
                                  ;;
                          esac
                          ;;
                      2)
                          read -p "请输入需要删除任务的关键字: " kquest
                          crontab -l | grep -v "$kquest" | crontab -
                          ;;
                      0)
                          break  # 跳出循环，退出菜单
                          ;;

                      *)
                          break  # 跳出循环，退出菜单
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
                          read -p "请输入新的解析记录 格式: 110.25.5.33 kejilion.pro : " addhost
                          echo "$addhost" >> /etc/hosts

                          ;;
                      2)
                          read -p "请输入需要删除的解析内容关键字: " delhost
                          sed -i "/$delhost/d" /etc/hosts
                          ;;
                      0)
                          break  # 跳出循环，退出菜单
                          ;;

                      *)
                          break  # 跳出循环，退出菜单
                          ;;
                  esac
              done
              ;;


          99)
              clear
              server_reboot
              ;;

          0)
              myset
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
    break_end
done
