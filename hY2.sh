
#!/bin/bash
# 获取当前用户名
USER=$(whoami)
USER_HOME=$(eval echo ~$USER)
HYSTERIA_WORKDIR="$USER_HOME/.hysteria"

# 检查系统环境
check_system() {
    # 检查CPU架构
    case $(uname -m) in
        x86_64|amd64)   ARCH="amd64" ;;
        arm64|aarch64)  ARCH="arm64" ;;
        *)
            echo "不支持的架构: $(uname -m)"
            exit 1
            ;;
    esac
}

# 创建必要的目录
init_directory() {
    if [ ! -d "$HYSTERIA_WORKDIR" ]; then
        mkdir -p "$HYSTERIA_WORKDIR" || {
            echo "创建目录失败: $HYSTERIA_WORKDIR"
            exit 1
        }
    fi
}

# 随机生成密码函数
generate_password() {
    export PASSWORD=${PASSWORD:-$(openssl rand -base64 12)}
}

# 设置服务器端口函数
set_server_port() {
    read -p "请输入 hysteria2 端口 (面板开放的UDP端口,默认 20026）: " input_port
    export SERVER_PORT="${input_port:-20026}"
}

# 下载依赖文件函数
download_dependencies() {
    local BINARY_URL="https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-$ARCH"
    local BINARY_PATH="$HYSTERIA_WORKDIR/web"

    echo "准备下载 Hysteria2..."
    echo "下载地址: $BINARY_URL"
    
    if curl -L -o "$BINARY_PATH" "$BINARY_URL"; then
        chmod +x "$BINARY_PATH"
        echo -e "\e[1;32m下载完成\e[0m"
    else
        echo "下载失败!"
        exit 1
    fi
}

# 生成证书函数
generate_cert() {
    local CERT="$HYSTERIA_WORKDIR/server.crt"
    local KEY="$HYSTERIA_WORKDIR/server.key"
    
    if [ -f "$CERT" ] && [ -f "$KEY" ]; then
        echo "证书文件已存在，跳过生成"
        return
    fi

    echo "生成自签名证书..."
    if ! openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "$KEY" -out "$CERT" \
        -subj "/CN=bing.com" -days 36500 2>/dev/null; then
        echo "证书生成失败!"
        exit 1
    fi
    chmod 644 "$CERT" "$KEY"
    echo "证书生成成功"
}

# 生成配置文件函数
generate_config() {
    cat << EOF > "$HYSTERIA_WORKDIR/config.yaml"
listen: :$SERVER_PORT

tls:
  cert: $HYSTERIA_WORKDIR/server.crt
  key: $HYSTERIA_WORKDIR/server.key

auth:
  type: password
  password: "$PASSWORD"

masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true

transport:
  udp:
    hopInterval: 30s
EOF
    chmod 644 "$HYSTERIA_WORKDIR/config.yaml"
}

# 运行服务函数
run_service() {
    if [ ! -f "$HYSTERIA_WORKDIR/web" ]; then
        echo "错误: hysteria2 程序文件不存在"
        exit 1
    fi

    # 先停止已有实例
    pkill -f "web server"
    sleep 2

    # 启动新实例并保存日志
    cd "$HYSTERIA_WORKDIR"
    nohup ./web server config.yaml > hysteria.log 2>&1 &
    
    # 等待服务启动
    sleep 3
    
    # 检查服务状态
    if pgrep -f "web server" >/dev/null; then
        echo -e "\e[1;32mHysteria2 服务启动成功\e[0m"
    else
        echo -e "\e[1;31mHysteria2 服务启动失败\e[0m"
        echo "查看错误日志:"
        tail -n 20 "$HYSTERIA_WORKDIR/hysteria.log"
        exit 1
    fi
}

# 获取IP地址函数
get_ip() {
    # 先尝试获取IPv4
    HOST_IP=$(curl -s4 ip.sb || curl -s4 ifconfig.me || curl -s4 ipinfo.io/ip)
    if [ -z "$HOST_IP" ]; then
        # 如果IPv4失败，尝试IPv6
        HOST_IP=$(curl -s6 ip.sb || curl -s6 ifconfig.me || curl -s6 ipinfo.io/ip)
    fi
    
    if [ -z "$HOST_IP" ]; then
        echo -e "\e[1;31m无法获取IP地址\e[0m"
        exit 1
    fi
    
    echo -e "\e[1;32m本机IP: $HOST_IP\e[0m"
}

# 获取网络信息函数
get_ipinfo() {
    ISP=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')
    if [ -z "$ISP" ]; then
        ISP="Unknown"
    fi
}

# 添加守护进程函数
add_crontab_task() {
    # 备份现有的crontab
    crontab -l > /tmp/crontab.bak 2>/dev/null
    
    # 添加新的定时任务
    echo "*/1 * * * * cd $HYSTERIA_WORKDIR && if ! pgrep -f 'web server' >/dev/null; then ./web server config.yaml > hysteria.log 2>&1 & fi" >> /tmp/crontab.bak
    
    # 应用新的crontab
    crontab /tmp/crontab.bak
    rm -f /tmp/crontab.bak
    
    echo -e "\e[1;32m守护进程配置完成\e[0m"
}

# 输出配置函数
print_config() {
    if [ ! -f "$HYSTERIA_WORKDIR/config.yaml" ]; then
        echo "配置文件不存在！"
        exit 1
    fi
    
    echo -e "\e[1;32mHysteria2 安装成功\033[0m"
    echo ""
    echo -e "\e[1;33mV2rayN或Nekobox 配置\033[0m"
    echo -e "\e[1;32mhysteria2://$PASSWORD@$HOST_IP:$SERVER_PORT/?sni=www.bing.com&alpn=h3&insecure=1#$ISP\033[0m"
    echo ""
    echo -e "\e[1;33mSurge 配置\033[0m"
    echo -e "\e[1;32m$ISP = hysteria2, $HOST_IP, $SERVER_PORT, password = $PASSWORD, skip-cert-verify=true, sni=www.bing.com\033[0m"
    echo ""
    echo -e "\e[1;33mClash 配置\033[0m"
    cat << EOF
- name: $ISP
  type: hysteria2
  server: $HOST_IP
  port: $SERVER_PORT
  password: $PASSWORD
  alpn:
    - h3
  sni: www.bing.com
  skip-cert-verify: true
  fast-open: true
EOF
}

# 主程序
main() {
    echo "开始安装 Hysteria2..."
    check_system
    init_directory
    generate_password
    set_server_port
    download_dependencies
    generate_cert
    generate_config
    run_service
    get_ip
    get_ipinfo
    print_config
    add_crontab_task
    echo -e "\e[1;32m安装完成！服务已启动并已配置守护进程。\e[0m"
}

main