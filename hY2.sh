#!/bin/bash
# 介绍信息
{
    echo -e "\e[92m" 
    echo "通往电脑的路不止一条"
    echo -e "\e[0m"  
}

# 获取当前用户名和路径
USER=$(whoami)
USER_HOME=$(eval echo "~$USER")
HYSTERIA_WORKDIR="$USER_HOME/.hysteria"

# 创建必要的目录
[ ! -d "$HYSTERIA_WORKDIR" ] && mkdir -p "$HYSTERIA_WORKDIR"

###################################################

# 检查基础工具安装
check_dependencies() {
    local missing_deps=()
    
    # 检查基本命令
    for cmd in fetch openssl; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing_deps+=($cmd)
        fi
    done
    
    # 如果有缺失的依赖，尝试安装
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "\e[1;33m检测到缺少必要组件，正在安装: ${missing_deps[*]}\033[0m"
        env ASSUME_ALWAYS_YES=YES pkg bootstrap
        pkg update
        pkg install -y ${missing_deps[*]}
    fi
}

# 获取IP地址函数
get_ip() {
    # 创建临时文件存储IP
    local ip_file=$(mktemp)
    local valid_ips=()
    local selected_ip=""
    
    echo -e "\e[1;33m正在检测所有可用IP...\033[0m"
    
    # 使用多个IP检测服务获取外网IP
    local external_ip=""
    
    # 尝试ipw.cn
    external_ip=$(fetch -qo - http://4.ipw.cn 2>/dev/null)
    if [ -z "$external_ip" ]; then
        # 备用：尝试使用ipinfo.io
        external_ip=$(fetch -qo - http://ipinfo.io/ip 2>/dev/null)
    fi
    
    if [ -z "$external_ip" ]; then
        # 再次备用：使用ifconfig.me
        external_ip=$(fetch -qo - http://ifconfig.me 2>/dev/null)
    fi
    
    if [ -n "$external_ip" ]; then
        echo "$external_ip" >> "$ip_file"
        
        # 尝试获取IPv6地址
        local ipv6=$(fetch -qo - http://6.ipw.cn 2>/dev/null)
        if [ -n "$ipv6" ]; then
            echo "$ipv6" >> "$ip_file"
        fi
    fi
    
    # 如果没有找到任何IP地址
    if [[ ! -s "$ip_file" ]]; then
        echo -e "\e[1;31m未检测到任何外网IP地址\033[0m"
        rm -f "$ip_file"
        exit 1
    fi
    
    echo -e "\e[1;32m检测到的所有IP地址：\033[0m"
    cat "$ip_file" | nl
    
    echo -e "\e[1;33m正在检测IP可用性...\033[0m"
    
    # 检查每个IP的连通性
    while IFS= read -r ip; do
        if fetch -qo /dev/null "https://www.google.com/generate_204" 2>/dev/null; then
            echo -e "\e[1;32mIP: $ip 可以访问Google\033[0m"
            valid_ips+=("$ip")
        else
            echo -e "\e[1;31mIP: $ip 无法访问Google\033[0m"
        fi
    done < "$ip_file"
    
    # 删除临时文件
    rm -f "$ip_file"
    
    # 如果有可用IP，让用户选择
    if [[ ${#valid_ips[@]} -gt 0 ]]; then
        echo -e "\e[1;32m可用IP列表：\033[0m"
        for i in "${!valid_ips[@]}"; do
            echo "$((i+1)). ${valid_ips[i]}"
        done
        
        while true; do
            read -p "请选择要使用的IP序号 (1-${#valid_ips[@]}, 默认1): " choice
            choice=${choice:-1}
            
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#valid_ips[@]}" ]; then
                selected_ip="${valid_ips[$((choice-1))]}"
                break
            else
                echo -e "\e[1;31m无效的选择，请重试\033[0m"
            fi
        done
        
        HOST_IP="$selected_ip"
        echo -e "\e[1;32m已选择IP: $HOST_IP\033[0m"
        return 0
    else
        echo -e "\e[1;31m未找到可用的IP地址\033[0m"
        exit 1
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
    ARCH=$(uname -m)
    DOWNLOAD_DIR="$HYSTERIA_WORKDIR"
    mkdir -p "$DOWNLOAD_DIR"
    
    # FreeBSD特定架构检测
    case "$ARCH" in
        "amd64"|"x86_64")
            DOWNLOAD_URL="https://download.hysteria.network/app/latest/hysteria-freebsd-amd64"
            ;;
        "arm64"|"aarch64")
            DOWNLOAD_URL="https://download.hysteria.network/app/latest/hysteria-freebsd-arm64"
            ;;
        *)
            echo -e "\e[1;31m不支持的架构: $ARCH\033[0m"
            exit 1
            ;;
    esac
    
    if [[ -e "$DOWNLOAD_DIR/web" ]]; then
        echo -e "\e[1;32m程序已存在，跳过下载\e[0m"
    else
        echo -e "\e[1;32m正在下载程序...\e[0m"
        if ! fetch -o "$DOWNLOAD_DIR/web" "$DOWNLOAD_URL"; then
            echo -e "\e[1;31m下载失败\033[0m"
            exit 1
        fi
        chmod +x "$DOWNLOAD_DIR/web"
    fi
}

# 生成证书函数
generate_cert() {
    if [[ ! -f "$HYSTERIA_WORKDIR/server.key" ]] || [[ ! -f "$HYSTERIA_WORKDIR/server.crt" ]]; then
        echo -e "\e[1;32m生成证书...\e[0m"
        openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
            -keyout "$HYSTERIA_WORKDIR/server.key" \
            -out "$HYSTERIA_WORKDIR/server.crt" \
            -subj "/CN=bing.com" -days 36500
    else
        echo -e "\e[1;32m证书已存在，跳过生成\e[0m"
    fi
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
    if [[ -e "$HYSTERIA_WORKDIR/web" ]]; then
        # 先终止已存在的进程
        pkill -f "$HYSTERIA_WORKDIR/web" >/dev/null 2>&1
        sleep 1
        
        nohup "$HYSTERIA_WORKDIR/web" server "$HYSTERIA_WORKDIR/config.yaml" >/dev/null 2>&1 &
        sleep 2
        
        if pgrep -f "$HYSTERIA_WORKDIR/web" >/dev/null; then
            echo -e "\e[1;32m服务启动成功\e[0m"
        else
            echo -e "\e[1;31m服务启动失败\e[0m"
            exit 1
        fi
    fi
}

# 获取网络信息函数
get_ipinfo() {
    if command -v fetch >/dev/null 2>&1; then
        ISP=$(fetch -qo - https://speed.cloudflare.com/meta 2>/dev/null | sed 's/.*"asn":{"name":"\([^"]*\)".*"city":"\([^"]*\)".*/\2-\1/' | sed 's/ /_/g')
        if [ -z "$ISP" ]; then
            ISP="Unknown"
        fi
    else
        ISP="Unknown"
    fi
}

# 输出配置函数
print_config() {
    # 处理IPv6地址
    local display_ip="$HOST_IP"
    if [[ $HOST_IP == *":"* ]]; then
        display_ip="[$HOST_IP]"
    fi
    
    echo -e "\e[1;32mHysteria2 安装成功\033[0m"
    echo ""
    echo -e "\e[1;33mV2rayN或Nekobox 配置\033[0m"
    echo -e "\e[1;32mhysteria2://$PASSWORD@$display_ip:$SERVER_PORT/?sni=www.bing.com&alpn=h3&insecure=1#$ISP\033[0m"
    echo ""
    echo -e "\e[1;33mSurge 配置\033[0m"
    echo -e "\e[1;32m$ISP = hysteria2, $display_ip, $SERVER_PORT, password = $PASSWORD, skip-cert-verify=true, sni=www.bing.com\033[0m"
    echo ""
    echo -e "\e[1;33mClash 配置\033[0m"
    cat << EOF
- name: $ISP
  type: hysteria2
  server: $display_ip
  port: $SERVER_PORT
  password: $PASSWORD
  alpn:
    - h3
  sni: www.bing.com
  skip-cert-verify: true
  fast-open: true
EOF
}

# 添加开机自启动服务
add_service() {
    cat << EOF > /usr/local/etc/rc.d/hysteria
#!/bin/sh

# PROVIDE: hysteria
# REQUIRE: NETWORKING
# KEYWORD: shutdown

. /etc/rc.subr

name="hysteria"
rcvar="hysteria_enable"

load_rc_config \$name

: \${hysteria_enable:="NO"}
: \${hysteria_user:="$USER"}

command="$HYSTERIA_WORKDIR/web"
command_args="server $HYSTERIA_WORKDIR/config.yaml"
pidfile="/var/run/\${name}.pid"

start_cmd="\${name}_start"
stop_cmd="\${name}_stop"

hysteria_start() {
    echo "Starting \${name}."
    /usr/sbin/daemon -P \${pidfile} -r -f -u \${hysteria_user} \${command} \${command_args}
}

hysteria_stop() {
    if [ -f \${pidfile} ]; then
        kill \`cat \${pidfile}\`
        rm \${pidfile}
    fi
}

run_rc_command "\$1"
EOF

    chmod 555 /usr/local/etc/rc.d/hysteria
    sysrc hysteria_enable=YES
    service hysteria start
}

# 安装 Hysteria
install_hysteria() {
    check_dependencies
    get_ip
    generate_password
    set_server_port
    download_dependencies
    generate_cert
    generate_config
    run_files
    get_ipinfo
    print_config
}

# 主程序
echo -e "\e[1;32m开始安装 Hysteria2...\e[0m"
install_hysteria

# 询问是否添加开机自启动
echo -e "\e[1;33m是否添加开机自启动？(Y/N 默认N): \e[0m"
read -p "" add_service_answer
add_service_answer=${add_service_answer:-N}
add_service_answer=${add_service_answer^^}

if [[ "$add_service_answer" == "Y" ]]; then
    if [ "$(id -u)" -eq 0 ]; then
        add_service
        echo -e "\e[1;32m已添加开机自启动\e[0m"
    else
        echo -e "\e[1;31m添加开机自启动需要root权限，请使用root用户运行\e[0m"
    fi
fi

echo -e "\e[1;32m安装完成！\e[0m"