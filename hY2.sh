#!/bin/sh

# 获取当前用户名
USER=$(whoami)
USER_HOME=$(readlink -f /home/$USER)
HYSTERIA_WORKDIR="$USER_HOME/.hysteria"

# 创建工作目录
mkdir -p "$HYSTERIA_WORKDIR"

# 随机生成密码函数
generate_password() {
    PASSWORD=$(openssl rand -base64 12)
}

# 设置服务器端口函数
set_server_port() {
    printf "请输入 hysteria2 端口 (面板开放的UDP端口,默认 20026）: "
    read input_port
    if [ -z "$input_port" ]; then
        SERVER_PORT="20026"
    else
        SERVER_PORT="$input_port"
    fi
}

# 下载依赖文件函数
download_dependencies() {
    ARCH=$(uname -m)
    if [ "$ARCH" = "arm" ] || [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
        DOWNLOAD_URL="https://download.hysteria.network/app/latest/hysteria-freebsd-arm64"
    elif [ "$ARCH" = "amd64" ] || [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "x86" ]; then
        DOWNLOAD_URL="https://download.hysteria.network/app/latest/hysteria-freebsd-amd64"
    else
        printf "不支持的架构: %s\n" "$ARCH"
        exit 1
    fi

    if [ ! -e "$HYSTERIA_WORKDIR/web" ]; then
        printf "正在下载 Hysteria...\n"
        if ! fetch -o "$HYSTERIA_WORKDIR/web" "$DOWNLOAD_URL"; then
            printf "下载失败\n"
            exit 1
        fi
    fi
    chmod +x "$HYSTERIA_WORKDIR/web"
}

# 生成证书函数
generate_cert() {
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "$HYSTERIA_WORKDIR/server.key" -out "$HYSTERIA_WORKDIR/server.crt" -subj "/CN=bing.com" -days 36500
}

# 生成配置文件函数
generate_config() {
    cat > "$HYSTERIA_WORKDIR/config.yaml" << EOF
listen: :$SERVER_PORT

tls:
  cert: $HYSTERIA_WORKDIR/server.crt
  key: $HYSTERIA_WORKDIR/server.key

auth:
  type: password
  password: "$PASSWORD"

fastOpen: true

masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true

transport:
  udp:
    hopInterval: 30s
EOF
}

# 运行下载的文件函数
run_files() {
    if [ -e "$HYSTERIA_WORKDIR/web" ]; then
        nohup "$HYSTERIA_WORKDIR/web" server "$HYSTERIA_WORKDIR/config.yaml" > /dev/null 2>&1 &
        sleep 1
        if pgrep web > /dev/null; then
            printf "web 正在运行\n"
        else
            printf "web 启动失败\n"
            exit 1
        fi
    fi
}

# 测试IP是否可访问谷歌函数
test_google_access() {
    ip="$1"
    type="$2"
    if fetch -T 3 -o /dev/null "https://www.google.com/generate_204" > /dev/null 2>&1; then
        printf "%s IP: %s (√ 可访问谷歌)\n" "$type" "$ip"
        return 0
    else
        printf "%s IP: %s (× 无法访问谷歌)\n" "$type" "$ip"
        return 1
    fi
}

# 获取IP函数
get_ip() {
    printf "正在检测服务器IP和连通性...\n\n"
    
    # 尝试获取IPv4地址
    IPV4=$(ifconfig | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | head -n 1)
    if [ -n "$IPV4" ]; then
        if test_google_access "$IPV4" "IPv4"; then
            HOST_IP="$IPV4"
            return
        fi
    fi
    
    # 尝试获取IPv6地址
    IPV6=$(ifconfig | grep "inet6 " | grep -v "::1" | grep -v "fe80" | awk '{print $2}' | head -n 1)
    if [ -n "$IPV6" ]; then
        if test_google_access "$IPV6" "IPv6"; then
            HOST_IP="$IPV6"
            return
        fi
    fi
    
    # 如果没有可访问谷歌的IP，使用第一个可用的IP
    if [ -n "$IPV4" ]; then
        HOST_IP="$IPV4"
        printf "\n未发现可访问谷歌的IP，使用IPv4: %s\n" "$IPV4"
    elif [ -n "$IPV6" ]; then
        HOST_IP="$IPV6"
        printf "\n未发现可访问谷歌的IP，使用IPv6: %s\n" "$IPV6"
    else
        printf "\n错误：未能找到任何可用IP\n"
        exit 1
    fi
}

# 获取网络信息函数
get_ipinfo() {
    ISP=$(fetch -qo - "https://speed.cloudflare.com/meta" | sed 's/.*"asOrganization":"\([^"]*\).*"city":"\([^"]*\).*/\2-\1/' | tr ' ' '_')
}

# 输出配置函数
print_config() {
    printf "\nHysteria2 安装成功\n\n"
    printf "V2rayN或Nekobox 配置：\n"
    printf "hysteria2://%s@%s:%s/?sni=www.bing.com&alpn=h3&insecure=1#%s\n\n" "$PASSWORD" "$HOST_IP" "$SERVER_PORT" "$ISP"
    printf "Surge 配置：\n"
    printf "%s = hysteria2, %s, %s, password = %s, skip-cert-verify=true, sni=www.bing.com\n\n" "$ISP" "$HOST_IP" "$SERVER_PORT" "$PASSWORD"
    printf "Clash 配置：\n"
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
printf "开始安装 Hysteria2...\n\n"
generate_password
set_server_port
download_dependencies
generate_cert
generate_config
run_files
get_ip
get_ipinfo
print_config
