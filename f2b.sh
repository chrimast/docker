#!/bin/bash

# --------------------------------------
# 1. 在 nginx.conf 中添加CF的IP库白名单
file_path="/opt/1panel/apps/openresty/openresty/conf/conf.d/default.conf"
# 要添加的内容
content="# CloudFlare IP
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 103.22.200.0/22;
set_real_ip_from 103.31.4.0/22;
set_real_ip_from 104.16.0.0/13;
set_real_ip_from 104.24.0.0/14;
set_real_ip_from 108.162.192.0/18;
set_real_ip_from 131.0.72.0/22;
set_real_ip_from 141.101.64.0/18;
set_real_ip_from 162.158.0.0/15;
set_real_ip_from 172.64.0.0/13;
set_real_ip_from 173.245.48.0/20;
set_real_ip_from 188.114.96.0/20;
set_real_ip_from 190.93.240.0/20;
set_real_ip_from 197.234.240.0/22;
set_real_ip_from 198.41.128.0/17;

set_real_ip_from 2400:cb00::/32;
set_real_ip_from 2606:4700::/32;
set_real_ip_from 2803:f800::/32;
set_real_ip_from 2405:b500::/32;
set_real_ip_from 2405:8100::/32;
set_real_ip_from 2a06:98c0::/29;
set_real_ip_from 2c0f:f248::/32;

real_ip_header    CF-Connecting-IP;"

# 要插入的行号
line_number=$(grep -n "1pwaf/data/conf/waf.conf" "$file_path" | cut -d':' -f1)

# 使用 sed 在指定行的下面添加内容
sed -i "${line_number}a\\
$content" "$file_path"

echo "内容添加完成"

# ------------------------------------------
# 2. 在文件 action.d/cloudflare.conf 中添加CF配置
sed -i "/^cfuser =/ s/$/ chrimast@gmail.com/" /etc/fail2ban/action.d/cloudflare.conf
sed -i "/^cftoken =/ s/$/ c85cf3a6a278ab2fb70629072677ca58b4ff3/" /etc/fail2ban/action.d/cloudflare.conf
echo -e "\ncftarget = ip" >> /etc/fail2ban/action.d/cloudflare.conf
echo -e "\ncftarget_v6 = ipv6" >> /etc/fail2ban/action.d/cloudflare.conf

# ------------------------------------------
# 3. 创建并写入 filter.d/nginx-cc.conf 文件
cat > /etc/fail2ban/filter.d/nginx-cc.conf <<EOF
[Definition]
# failregex = ^<HOST> .* "(GET|POST|HEAD).*HTTP.*" (404|503) .*$
# failregex = ^<HOST> .* "(GET|POST|HEAD).*HTTP.*" (404|503|444) .*
# failregex = ^<HOST> .* "(GET|POST|HEAD).*HTTP.*" (403|404|429) .*
# failregex = ^<HOST> .* "(GET|POST|HEAD).*HTTP.*" ([45]\d\d) .*
# ignoreregex =.*(robots.txt|favicon.ico|jpg|png)
failregex = ^<HOST> .* HTTP.* (403|429) .*$
ignoreregex = ^.*(\/(?:robots\.txt|favicon\.ico|.*\.(?:jpg|png|gif|jpeg|svg|webp|bmp|tiff|css|js|woff|woff2|eot|ttf|otf))$)

EOF

# ------------------------------------------
# 4. 追加配置到 jail.local 文件
cat >> /etc/fail2ban/jail.local <<EOF

# 自定义 fail2ban 配置
# DEFAULT-START
[DEFAULT]
bantime = 600
findtime = 300
maxretry = 5
banaction = iptables-allports
action = cloudflare
# DEFAULT-END

[sshd]
ignoreip = 127.0.0.1/8
enabled = true
filter = sshd
port = 2233
maxretry = 5
findtime = 300
bantime = 600
banaction = iptables-allports
action = cloudflare
logpath = /var/log/auth.log

[docker-nginx-cc]
enabled = true
chain = DOCKER-USER
filter = nginx-cc
port = http,https
banaction = iptables-allports
action = cloudflare
logpath = /opt/1panel/apps/openresty/openresty/log/*.log
          /opt/1panel/apps/openresty/openresty/www/sites/*/log/*.log
maxretry = 5
bantime = 3600
findtime = 600
ignoreip = 192.168.0.1/24

[docker-nginx-badbots]
enabled = true
chain = DOCKER-USER
filter = apache-badbots
port = http,https
banaction = iptables-allports
action = cloudflare
logpath = /opt/1panel/apps/openresty/openresty/log/*.log
          /opt/1panel/apps/openresty/openresty/www/sites/*/log/*.log
maxretry = 2

[docker-nginx-botsearch]
enabled = true
chain = DOCKER-USER
filter = nginx-botsearch
port = http,https
banaction = iptables-allports
action = cloudflare
logpath = /opt/1panel/apps/openresty/openresty/log/*.log
                /opt/1panel/apps/openresty/openresty/www/sites/*/log/*.log

[docker-nginx-http-auth]
enabled = true
chain = DOCKER-USER
filter = nginx-http-auth
port = http,https
banaction = iptables-allports
action = cloudflare
logpath = /opt/1panel/apps/openresty/openresty/log/*.log
                /opt/1panel/apps/openresty/openresty/www/sites/*/log/*.log

[docker-nginx-limit-req]
enabled = true
chain = DOCKER-USER
filter = nginx-limit-req
port = http,https
banaction = iptables-allports
action = cloudflare
logpath = /opt/1panel/apps/openresty/openresty/log/*.log
                /opt/1panel/apps/openresty/openresty/www/sites/*/log/*.log

[docker-php-url-fopen]
enabled = true
chain = DOCKER-USER
filter = php-url-fopen
port = http,https
banaction = iptables-allports
action = cloudflare
logpath = /opt/1panel/apps/openresty/openresty/log/*.log
                /opt/1panel/apps/openresty/openresty/www/sites/*/log/*.log

EOF

echo "配置添加完成"