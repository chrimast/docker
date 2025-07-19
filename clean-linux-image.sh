#!/bin/bash

# 获取当前正在使用的内核版本
current_kernel=$(uname -r)
echo "当前正在使用的内核版本: $current_kernel"

# 列出所有已安装的内核
installed_kernels=$(dpkg -l | grep linux-image | awk '{print $2}')
echo "已安装的内核版本:"
echo "$installed_kernels"

# 初始化一个变量来存储将被删除的内核版本
kernels_to_remove=""

# 遍历所有已安装的内核，排除当前内核
for kernel in $installed_kernels; do
    if [[ $kernel == *"$current_kernel"* ]]; then
        echo "保留当前使用的内核: $kernel"
    else
        echo "将删除旧内核: $kernel"
        kernels_to_remove="$kernels_to_remove $kernel"
    fi
done

# 检查是否有旧内核需要删除
if [[ -n $kernels_to_remove ]]; then
    echo "开始删除旧内核..."
    sudo apt remove --purge -y $kernels_to_remove
    echo "旧内核删除完成。"
else
    echo "没有旧内核需要删除。"
fi

# 清理系统的未使用包
echo "清理系统中未使用的包..."
sudo apt autoremove -y
sudo apt autoclean

# 更新引导程序配置
echo "更新引导程序配置..."
sudo update-grub

echo "操作完成！系统中仅保留了当前正在使用的内核。"
