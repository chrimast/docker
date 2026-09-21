#!/bin/bash
# 1Panel fail2ban + Cloudflare/本机封禁
# v1 / v2 通过 PANEL_FLAVOR 或自动探测站点日志目录区分。
# Cloudflare 凭据: 环境变量 CF_EMAIL、CF_TOKEN，或 /root/.cloudflare.env
set -euo pipefail

PANEL_FLAVOR="${PANEL_FLAVOR:-v1}"

f2b_die() { echo "错误: $*" >&2; exit 1; }

f2b_load_secrets() {
    CF_EMAIL="${CF_EMAIL:-${CF_API_EMAIL:-${CLOUDFLARE_EMAIL:-}}}"
    CF_TOKEN="${CF_TOKEN:-${CF_API_KEY:-${CF_API_TOKEN:-${CLOUDFLARE_API_KEY:-}}}}"
    CF_ENV_FILE="${CF_ENV_FILE:-/root/.cloudflare.env}"
    if [ -f "$CF_ENV_FILE" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%$'\r'}"
            case "$line" in
                ''|\#*) continue ;;
                CF_EMAIL=*|CF_API_EMAIL=*|CLOUDFLARE_EMAIL=*) CF_EMAIL="${line#*=}" ;;
                CF_TOKEN=*|CF_API_KEY=*|CF_API_TOKEN=*|CLOUDFLARE_API_KEY=*) CF_TOKEN="${line#*=}" ;;
            esac
        done < "$CF_ENV_FILE"
    fi
    CF_EMAIL="${CF_EMAIL%\"}"; CF_EMAIL="${CF_EMAIL#\"}"
    CF_TOKEN="${CF_TOKEN%\"}"; CF_TOKEN="${CF_TOKEN#\"}"
}

f2b_first_existing() {
    local p
    for p in "$@"; do
        [ -e "$p" ] && { echo "$p"; return 0; }
    done
    return 1
}

f2b_detect() {
    PANEL_ROOT="${PANEL_ROOT:-/opt/1panel}"
    F2B_DIR="${F2B_DIR:-/etc/fail2ban}"
    OPENRESTY_DIR="${OPENRESTY_DIR:-}"
    NGINX_CONF="${NGINX_CONF:-}"
    SITE_LOG_GLOB="${SITE_LOG_GLOB:-}"
    OPENRESTY_LOG_GLOB="${OPENRESTY_LOG_GLOB:-}"
    SSH_PORT="${SSH_PORT:-}"
    AUTH_LOG="${AUTH_LOG:-}"
    IGNORE_IP="${IGNORE_IP:-127.0.0.1/8}"
    BAN_CHAIN="${BAN_CHAIN:-DOCKER-USER}"

    local cand
    if [ -z "$OPENRESTY_DIR" ]; then
        for cand in \
            "$PANEL_ROOT/apps/openresty/openresty" \
            "$PANEL_ROOT/apps/openresty" \
            /www/server/nginx \
            /etc/nginx
        do
            if [ -d "$cand" ]; then
                OPENRESTY_DIR="$cand"
                break
            fi
        done
    fi
    [ -n "${OPENRESTY_DIR:-}" ] || f2b_die "找不到 OpenResty/Nginx 目录，请设置 OPENRESTY_DIR"

    if [ -z "$NGINX_CONF" ]; then
        NGINX_CONF=$(f2b_first_existing \
            "$OPENRESTY_DIR/conf/nginx.conf" \
            "$OPENRESTY_DIR/nginx/conf/nginx.conf" \
            /etc/nginx/nginx.conf) || f2b_die "找不到 nginx.conf，请设置 NGINX_CONF"
    fi

    OPENRESTY_LOG_GLOB="${OPENRESTY_LOG_GLOB:-$OPENRESTY_DIR/log/*.log}"

    local v1_sites="$OPENRESTY_DIR/www/sites"
    local v2_sites="$PANEL_ROOT/www/sites"
    if [ -z "$SITE_LOG_GLOB" ]; then
        case "$PANEL_FLAVOR" in
            v2)
                if [ -d "$v2_sites" ]; then
                    SITE_LOG_GLOB="$v2_sites/*/log/*.log"
                elif [ -d "$v1_sites" ]; then
                    echo "未找到 v2 站点目录 $v2_sites，回退到 v1: $v1_sites"
                    SITE_LOG_GLOB="$v1_sites/*/log/*.log"
                    PANEL_FLAVOR=v1
                fi
                ;;
            *)
                if [ -d "$v1_sites" ]; then
                    SITE_LOG_GLOB="$v1_sites/*/log/*.log"
                    PANEL_FLAVOR=v1
                elif [ -d "$v2_sites" ]; then
                    echo "未找到 v1 站点目录 $v1_sites，改用 v2: $v2_sites"
                    SITE_LOG_GLOB="$v2_sites/*/log/*.log"
                    PANEL_FLAVOR=v2
                fi
                ;;
        esac
    fi
    [ -n "${SITE_LOG_GLOB:-}" ] || f2b_die "找不到站点日志目录，请设置 SITE_LOG_GLOB"

    if [ -z "$SSH_PORT" ]; then
        SSH_PORT=$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}') || true
        [ -n "${SSH_PORT:-}" ] || SSH_PORT=$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/{print $2; exit}' /etc/ssh/sshd_config 2>/dev/null) || true
        SSH_PORT="${SSH_PORT:-22}"
    fi
    if [ -z "$AUTH_LOG" ]; then
        AUTH_LOG=$(f2b_first_existing /var/log/auth.log /var/log/secure) || AUTH_LOG=/var/log/auth.log
    fi

    CF_ACTION_CONF="${CF_ACTION_CONF:-$F2B_DIR/action.d/cloudflare.conf}"
    FILTER_CONF="${FILTER_CONF:-$F2B_DIR/filter.d/nginx-cc.conf}"
    JAIL_LOCAL="${JAIL_LOCAL:-$F2B_DIR/jail.local}"
    REALIP_CONF="${REALIP_CONF:-$(dirname "$NGINX_CONF")/cloudflare-real-ip.conf}"
}

f2b_write_realip() {
    local tmp
    tmp=$(mktemp)
    {
        echo "# 由 f2b.sh 生成，勿手工重复插入 nginx.conf"
        echo "# 更新: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        if curl -fsS --max-time 15 https://www.cloudflare.com/ips-v4; then
            :
        else
            cat <<'CIDR'
173.245.48.0/20
103.21.244.0/22
103.22.200.0/22
103.31.4.0/22
141.101.64.0/18
108.162.192.0/18
190.93.240.0/20
188.114.96.0/20
197.234.240.0/22
198.41.128.0/17
162.158.0.0/15
104.16.0.0/13
104.24.0.0/14
172.64.0.0/13
131.0.72.0/22
CIDR
        fi
    } | awk '
        /^[0-9a-fA-F:.]+\/[0-9]+$/ { print "    set_real_ip_from " $0 ";" }
        /^#/ { print }
    ' > "$tmp"
    {
        if curl -fsS --max-time 15 https://www.cloudflare.com/ips-v6; then
            :
        else
            cat <<'CIDR'
2400:cb00::/32
2606:4700::/32
2803:f800::/32
2405:b500::/32
2405:8100::/32
2a06:98c0::/29
2c0f:f248::/32
CIDR
        fi
    } | awk '/^[0-9a-fA-F:]+\/[0-9]+$/ { print "    set_real_ip_from " $0 ";" }' >> "$tmp"
    echo "    real_ip_header CF-Connecting-IP;" >> "$tmp"
    echo "    real_ip_recursive on;" >> "$tmp"
    mv "$tmp" "$REALIP_CONF"
    echo "已写入 $REALIP_CONF"

    if grep -Eq 'include[[:space:]].*cloudflare-real-ip\.conf' "$NGINX_CONF"; then
        echo "nginx.conf 已包含 real_ip 配置"
        return 0
    fi
    if ! grep -Eq 'http[[:space:]]*\{' "$NGINX_CONF"; then
        f2b_die "$NGINX_CONF 中找不到 http { ，无法自动 include"
    fi
    local inc_name
    inc_name=$(basename "$REALIP_CONF")
    # 只在 http { 后插入一次
    awk -v inc="    include ${inc_name};" '
        BEGIN { done=0 }
        /http[[:space:]]*\{/ && !done { print; print inc; done=1; next }
        { print }
    ' "$NGINX_CONF" > "$NGINX_CONF.tmp"
    mv "$NGINX_CONF.tmp" "$NGINX_CONF"
    echo "已在 $NGINX_CONF 的 http{} 中加入 include $inc_name;"
}

f2b_write_cf_action() {
    local dest="$CF_ACTION_CONF"
    mkdir -p "$(dirname "$dest")"
    if [ ! -f "$dest" ] && [ -f /etc/fail2ban/action.d/cloudflare.conf ]; then
        cp /etc/fail2ban/action.d/cloudflare.conf "$dest"
    fi
    if [ ! -f "$dest" ]; then
        cat > "$dest" <<'EOF'
[Definition]
norestored = 1
cftarget = ip
cftarget_v6 = ipv6
cfuser =
cftoken =
actionban = curl -s -o /dev/null -X POST -H 'X-Auth-Email: <cfuser>' -H 'X-Auth-Key: <cftoken>' -H 'Content-Type: application/json' -d '{"mode":"block","configuration":{"target":"<cftarget>","value":"<ip>"},"notes":"fail2ban"}' https://api.cloudflare.com/client/v4/user/firewall/access_rules/rules
actionunban = curl -s -o /dev/null -X DELETE -H 'X-Auth-Email: <cfuser>' -H 'X-Auth-Key: <cftoken>' https://api.cloudflare.com/client/v4/user/firewall/access_rules/rules?mode=block&configuration_target=<cftarget>&configuration_value=<ip>
EOF
    fi

    grep -q '^cftarget =' "$dest" || echo "cftarget = ip" >> "$dest"
    grep -q '^cftarget_v6 =' "$dest" || echo "cftarget_v6 = ipv6" >> "$dest"
    if [ -n "${CF_EMAIL:-}" ]; then
        if grep -q '^cfuser =' "$dest"; then
            sed -i "s|^cfuser =.*|cfuser = ${CF_EMAIL}|" "$dest"
        else
            echo "cfuser = ${CF_EMAIL}" >> "$dest"
        fi
    fi
    if [ -n "${CF_TOKEN:-}" ]; then
        if grep -q '^cftoken =' "$dest"; then
            sed -i "s|^cftoken =.*|cftoken = ${CF_TOKEN}|" "$dest"
        else
            echo "cftoken = ${CF_TOKEN}" >> "$dest"
        fi
        echo "已更新 Cloudflare action（密钥不回显）"
        BAN_ACTION_LINE="action = cloudflare"
    else
        echo "未设置 CF_EMAIL/CF_TOKEN，jail 仅使用本机 iptables 封禁"
        BAN_ACTION_LINE="action = %(banaction)s"
    fi
}

f2b_write_filter() {
    mkdir -p "$(dirname "$FILTER_CONF")"
    cat > "$FILTER_CONF" <<'EOF'
[Definition]
failregex = ^<HOST> .* HTTP.* (403|429) .*$
ignoreregex = ^.*(\/(?:robots\.txt|favicon\.ico|.*\.(?:jpg|png|gif|jpeg|svg|webp|bmp|tiff|css|js|woff|woff2|eot|ttf|otf))$)
EOF
    echo "已写入 $FILTER_CONF"
}

f2b_write_jail() {
    mkdir -p "$(dirname "$JAIL_LOCAL")"
    touch "$JAIL_LOCAL"
    local block
    block=$(cat <<EOF
# F2B-PANEL-START
# 由 f2b.sh 管理。改环境变量后重新执行脚本即可更新这一段。
[DEFAULT]
bantime = 600
findtime = 300
maxretry = 5
banaction = iptables-allports
${BAN_ACTION_LINE}

[sshd]
ignoreip = ${IGNORE_IP}
enabled = true
filter = sshd
port = ${SSH_PORT}
maxretry = 5
findtime = 300
bantime = 600
banaction = iptables-allports
${BAN_ACTION_LINE}
logpath = ${AUTH_LOG}

[docker-nginx-cc]
enabled = true
chain = ${BAN_CHAIN}
filter = nginx-cc
port = http,https
banaction = iptables-allports
${BAN_ACTION_LINE}
logpath = ${OPENRESTY_LOG_GLOB}
          ${SITE_LOG_GLOB}
maxretry = 5
bantime = 3600
findtime = 600
ignoreip = ${IGNORE_IP}

[docker-nginx-badbots]
enabled = true
chain = ${BAN_CHAIN}
filter = apache-badbots
port = http,https
banaction = iptables-allports
${BAN_ACTION_LINE}
logpath = ${OPENRESTY_LOG_GLOB}
          ${SITE_LOG_GLOB}
maxretry = 2

[docker-nginx-botsearch]
enabled = true
chain = ${BAN_CHAIN}
filter = nginx-botsearch
port = http,https
banaction = iptables-allports
${BAN_ACTION_LINE}
logpath = ${OPENRESTY_LOG_GLOB}
          ${SITE_LOG_GLOB}

[docker-nginx-http-auth]
enabled = true
chain = ${BAN_CHAIN}
filter = nginx-http-auth
port = http,https
banaction = iptables-allports
${BAN_ACTION_LINE}
logpath = ${OPENRESTY_LOG_GLOB}
          ${SITE_LOG_GLOB}

[docker-nginx-limit-req]
enabled = true
chain = ${BAN_CHAIN}
filter = nginx-limit-req
port = http,https
banaction = iptables-allports
${BAN_ACTION_LINE}
logpath = ${OPENRESTY_LOG_GLOB}
          ${SITE_LOG_GLOB}

[docker-php-url-fopen]
enabled = true
chain = ${BAN_CHAIN}
filter = php-url-fopen
port = http,https
banaction = iptables-allports
${BAN_ACTION_LINE}
logpath = ${OPENRESTY_LOG_GLOB}
          ${SITE_LOG_GLOB}
# F2B-PANEL-END
EOF
)
    if grep -q '# F2B-PANEL-START' "$JAIL_LOCAL"; then
        awk -v block="$block" '
            BEGIN {p=1}
            /# F2B-PANEL-START/ {print block; p=0; next}
            /# F2B-PANEL-END/ {p=1; next}
            p {print}
        ' "$JAIL_LOCAL" > "$JAIL_LOCAL.tmp"
        mv "$JAIL_LOCAL.tmp" "$JAIL_LOCAL"
        echo "已更新 $JAIL_LOCAL 中的 F2B-PANEL 段"
    else
        printf '\n%s\n' "$block" >> "$JAIL_LOCAL"
        echo "已追加 F2B-PANEL 段到 $JAIL_LOCAL"
    fi
}

f2b_main() {
    [ "$(id -u)" -eq 0 ] || f2b_die "请使用 root 运行"
    command -v fail2ban-client >/dev/null 2>&1 || echo "提示: 未检测到 fail2ban-client，仍会写入配置"
    f2b_load_secrets
    f2b_detect
    echo "探测结果:"
    echo "  1Panel 版本倾向: $PANEL_FLAVOR"
    echo "  OpenResty: $OPENRESTY_DIR"
    echo "  nginx.conf: $NGINX_CONF"
    echo "  站点日志: $SITE_LOG_GLOB"
    echo "  OpenResty 日志: $OPENRESTY_LOG_GLOB"
    echo "  SSH 端口: $SSH_PORT"
    echo "  认证日志: $AUTH_LOG"
    echo "  fail2ban: $F2B_DIR"
    f2b_write_realip
    BAN_ACTION_LINE="action = %(banaction)s"
    f2b_write_cf_action
    f2b_write_filter
    f2b_write_jail
    if command -v fail2ban-client >/dev/null 2>&1; then
        fail2ban-client reload && echo "fail2ban 已 reload" || echo "请手动: systemctl restart fail2ban"
    else
        echo "未安装 fail2ban。安装后执行: systemctl enable --now fail2ban"
    fi
    echo "完成。Cloudflare 凭据请用 CF_EMAIL/CF_TOKEN 或 $CF_ENV_FILE，不要写进脚本。"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    f2b_main
fi
