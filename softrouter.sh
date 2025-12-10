#!/bin/sh

BIN_PATH="/usr/bin/ech-workers"
CONF_FILE="/etc/ech-workers.conf"
INIT_FILE="/etc/init.d/ech-workers"
TMP_DIR="/tmp/ech-workers"

# 默认值（第一次生成配置用，可以之后在菜单里改）
DEFAULT_BEST_IP="cf.877771.xyz"
DEFAULT_SERVER_ADDR="echo.example.com:443"
DEFAULT_LISTEN_ADDR="0.0.0.0:30001"
DEFAULT_TOKEN=""
DEFAULT_DNS="https://dns.alidns.com/dns-query"
DEFAULT_ECH_DOMAIN="cloudflare-ech.com"

# 根据架构选择下载链接
get_latest_release_url() {
    echo "正在获取 GitHub 最新发布版本..."

    # 检查架构
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        DOWNLOAD_URL="https://github.com/byJoey/ech-wk/releases/download/latest/ECHWorkers-linux-amd64-softrouter.tar.gz"
    elif [ "$ARCH" = "aarch64" ]; then
        DOWNLOAD_URL="https://github.com/byJoey/ech-wk/releases/download/latest/ECHWorkers-linux-arm64-softrouter.tar.gz"
    else
        echo "不支持此架构：$ARCH"
        return 1
    fi

    echo "下载链接: $DOWNLOAD_URL"
    echo $DOWNLOAD_URL
}

ensure_binary() {
    if [ -x "$BIN_PATH" ]; then
        return 0
    fi

    echo "找不到二进制: $BIN_PATH"
    echo "自动下载最新版本..."

    DOWNLOAD_URL=$(get_latest_release_url)
    if [ $? -ne 0 ]; then
        echo "下载失败！"
        return 1
    fi

    echo "开始下载..."
    mkdir -p "$(dirname "$BIN_PATH")"
    mkdir -p "$TMP_DIR"

    # 使用 curl 下载压缩包
    curl -L -o "$TMP_DIR/ech-workers.tar.gz" "$DOWNLOAD_URL" || { echo "下载失败"; return 1; }

    echo "下载完成，开始解压..."
    # 解压下载的文件
    tar -zxvf "$TMP_DIR/ech-workers.tar.gz" -C "$TMP_DIR" || { echo "解压失败"; return 1; }

    # 假设解压后文件名是 ech-workers，请根据实际情况调整
    mv "$TMP_DIR/ech-workers" "$BIN_PATH" || { echo "移动文件失败"; return 1; }

    chmod +x "$BIN_PATH"
    echo "已下载并安装到 $BIN_PATH"
}

ensure_conf() {
    if [ -f "$CONF_FILE" ]; then
        return 0
    fi

    mkdir -p "$(dirname "$CONF_FILE")"
    cat >"$CONF_FILE" <<EOF
BEST_IP="$DEFAULT_BEST_IP"
SERVER_ADDR="$DEFAULT_SERVER_ADDR"
LISTEN_ADDR="$DEFAULT_LISTEN_ADDR"
TOKEN="$DEFAULT_TOKEN"
DNS="$DEFAULT_DNS"
ECH_DOMAIN="$DEFAULT_ECH_DOMAIN"
EOF
    echo "已生成默认配置: $CONF_FILE"
}

ensure_init() {
    if [ -f "$INIT_FILE" ]; then
        return 0
    fi

    cat >"$INIT_FILE" <<'EOF'
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=99
STOP=10

BIN="/usr/bin/ech-workers"
CONF="/etc/ech-workers.conf"

start_service() {
    [ -x "$BIN" ] || return 1
    [ -f "$CONF" ] && . "$CONF"

    # 给一些默认值，避免变量为空
    : "${DNS:=https://dns.alidns.com/dns-query}"
    : "${ECH_DOMAIN:=cloudflare-ech.com}"

    procd_open_instance
    procd_set_param command "$BIN" \
        -f "${SERVER_ADDR}" \
        -l "${LISTEN_ADDR}" \
        -token "${TOKEN}" \
        -ip "${BEST_IP}" \
        -dns "${DNS}" \
        -ech "${ECH_DOMAIN}"
    procd_set_param respawn
    procd_close_instance
}
EOF

    chmod +x "$INIT_FILE"
    /etc/init.d/ech-workers enable 2>/dev/null
    echo "已创建启动脚本: $INIT_FILE 并设置开机自启"
}

load_conf() {
    [ -f "$CONF_FILE" ] && . "$CONF_FILE"
}

save_conf() {
    mkdir -p "$(dirname "$CONF_FILE")"
    cat >"$CONF_FILE" <<EOF
BEST_IP="${BEST_IP}"
SERVER_ADDR="${SERVER_ADDR}"
LISTEN_ADDR="${LISTEN_ADDR}"
TOKEN="${TOKEN}"
DNS="${DNS}"
ECH_DOMAIN="${ECH_DOMAIN}"
EOF
}

show_menu() {
    while true; do
        clear
        ensure_conf
        load_conf

        echo "==========================="
        echo "----- 当前配置 ------------"
        echo "优选 IP      : ${BEST_IP}"
        echo "服务地址     : ${SERVER_ADDR}"
        echo "监听地址     : ${LISTEN_ADDR}"
        echo "TOKEN(身份令牌): ${TOKEN}"
        echo "DNS(可选)    : ${DNS}"
        echo "ECH 域名(可选): ${ECH_DOMAIN}"
        echo "---------------------------"
        echo "----- ech-workers 菜单 ----"
        echo "1) 修改优选 IP"
        echo "2) 修改服务地址"
        echo "3) 修改监听地址"
        echo "4) 修改 TOKEN(身份令牌)"
        echo "5) 启动 ech"
        echo "6) 关闭 ech"
        echo "7) 查看日志(最近50行)"
        echo "8) 退出"
        echo "==========================="
        printf "请选择 [1-8]: "
        read -r choice

        case "$choice" in
            1)
                printf "输入新的优选 IP: "
                read -r BEST_IP
                save_conf
                ;;
            2)
                printf "输入新的服务地址 (例如 example.com:443): "
                read -r SERVER_ADDR
                save_conf
                ;;
            3)
                printf "输入新的监听地址 (例如 0.0.0.0:30001): "
                read -r LISTEN_ADDR
                save_conf
                ;;
            4)
                printf "输入新的 TOKEN(身份令牌): "
                read -r TOKEN
                save_conf
                ;;
            5)
                ensure_binary || { echo "启动失败：二进制不存在"; sleep 2; continue; }
                ensure_init
                /etc/init.d/ech-workers restart
                echo "已启动 / 重启 ech-workers"
                sleep 2
                ;;
            6)
                if [ -x "$INIT_FILE" ]; then
                    /etc/init.d/ech-workers stop
                    echo "已停止 ech-workers"
                else
                    echo "找不到 $INIT_FILE"
                fi
                sleep 2
                ;;
            7)
                echo "日志输出 (logread -e ech-workers | tail -n 50):"
                echo "----------------------------------------------"
                if command -v logread >/dev/null 2>&1; then
                    logread -e ech-workers | tail -n 50
                else
                    echo "系统没有 logread，请手动查看日志。"
                fi
                echo "----------------------------------------------"
                printf "按回车返回菜单..."
                read dummy
                ;;
            8)
                exit 0
                ;;
            *)
                echo "无效选择"
                sleep 1
                ;;
        esac
    done
}

# 入口
ensure_conf
show_menu
