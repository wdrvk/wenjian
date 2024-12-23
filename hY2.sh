
#!/bin/bash
# 介绍信息
{
    echo -e "\e[92m" 
    echo "一键安装Hysteria2脚本"
    echo -e "\e[0m"  
}

# 获取当前用户名
USER=$(whoami)
USER_HOME=$(readlink -f /home/$USER) # 获取标准化的用户主目录
HYSTERIA_WORKDIR="$USER_HOME/.hysteria"

# 创建必要的目录，如果不存在
[ ! -d "$HYSTERIA_WORKDIR" ] && mkdir -p "$HYSTERIA_WORKDIR"

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
  FILE_INFO=()

  if [[ "$ARCH" == "arm" || "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    FILE_INFO=("https://download.hysteria.network/app/latest/hysteria-freebsd-arm64 web" "https://github.com/eooce/test/releases/download/ARM/swith npm")
  elif [[ "$ARCH" == "amd64" || "$ARCH" == "x86_64" || "$ARCH" == "x86" ]]; then
    FILE_INFO=("https://download.hysteria.network/app/latest/hysteria-freebsd-amd64 web" "https://github.com/eooce/test/releases/download/freebsd/swith npm")
  else
    echo "不支持的架构: $ARCH"
    exit 1
  fi

  for entry in "${FILE_INFO[@]}"; do
    URL=$(echo "$entry" | cut -d ' ' -f 1)
    NEW_FILENAME=$(echo "$entry" | cut -d ' ' -f 2)
    FILENAME="$DOWNLOAD_DIR/$NEW_FILENAME"
    if [[ -e "$FILENAME" ]]; then
      echo -e "\e[1;32m$FILENAME 已存在，跳过下载\e[0m"
    else
      curl -L -sS -o "$FILENAME" "$URL"
      echo -e "\e[1;32m下载 $FILENAME\e[0m"
    fi
    chmod +x "$FILENAME"
  done
  wait
}

# 生成证书函数
generate_cert() {
  openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "$HYSTERIA_WORKDIR/server.key" -out "$HYSTERIA_WORKDIR/server.crt" -subj "/CN=bing.com" -days 36500
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
    nohup "$HYSTERIA_WORKDIR/web" server "$HYSTERIA_WORKDIR/config.yaml" >/dev/null 2>&1 &
    sleep 1
    echo -e "\e[1;32mweb 正在运行\e[0m"
  fi
}

# 测试IP是否可访问谷歌函数
test_google_access() {
    local ip=$1
    local type=$2
    local timeout=3

    # 使用curl测试连接性，设置较短的超时时间
    if curl --interface "$ip" -s --max-time $timeout "https://www.google.com/generate_204" -o /dev/null; then
        echo -e "\e[1;32m$type IP: $ip (√ 可访问谷歌)\e[0m"
        return 0
    else
        echo -e "\e[1;31m$type IP: $ip (× 无法访问谷歌)\e[0m"
        return 1
    fi
}

# 获取所有IP并测试函数
get_ip() {
    # 存储可用的IP
    declare -a VALID_IPS
    
    echo -e "\e[1;33m正在检测服务器IP和连通性...\e[0m"
    
    # 获取IPv4地址
    IPV4S=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1")
    
    # 获取IPv6地址
    IPV6S=$(ip -6 addr show | grep -oP '(?<=inet6\s)[0-9a-fA-F:]+' | grep -v "::1" | grep -v "fe80")
    
    echo -e "\n\e[1;36m发现以下IP地址：\e[0m"
    
    # 测试IPv4地址
    if [ -n "$IPV4S" ]; then
        while IFS= read -r ip; do
            if test_google_access "$ip" "IPv4"; then
                VALID_IPS+=("$ip")
            fi
        done <<< "$IPV4S"
    else
        echo -e "\e[1;33m未发现IPv4地址\e[0m"
    fi
    
    # 测试IPv6地址
    if [ -n "$IPV6S" ]; then
        while IFS= read -r ip; do
            if test_google_access "$ip" "IPv6"; then
                VALID_IPS+=("$ip")
            fi
        done <<< "$IPV6S"
    else
        echo -e "\e[1;33m未发现IPv6地址\e[0m"
    fi
    
    # 如果找到可用IP，选择第一个可用的
    if [ ${#VALID_IPS[@]} -gt 0 ]; then
        HOST_IP="${VALID_IPS[0]}"
        echo -e "\n\e[1;32m已选择可用IP: $HOST_IP\e[0m"
    else
        # 如果没有可以访问谷歌的IP，使用第一个发现的IP
        FIRST_IP=$(ip -o addr show | grep -v " lo " | grep -oP '(?<=inet6?\s)[0-9a-fA-F:.]+' | grep -v "::1" | grep -v "fe80" | head -n1)
        if [ -n "$FIRST_IP" ]; then
            HOST_IP="$FIRST_IP"
            echo -e "\n\e[1;33m未发现可访问谷歌的IP，使用第一个可用IP: $HOST_IP\e[0m"
        else
            echo -e "\n\e[1;31m错误：未能找到任何可用IP\e[0m"
            exit 1
        fi
    fi
}

# 获取网络信息函数
get_ipinfo() {
  ISP=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')
}

# 输出配置函数
print_config() {
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

# 删除临时文件函数
cleanup() {
  rm -rf "$HYSTERIA_WORKDIR/web" "$HYSTERIA_WORKDIR/config.yaml"
}

# 安装 Hysteria
install_hysteria() {
  generate_password
  set_server_port
  download_dependencies
  generate_cert
  generate_config
  run_files
  get_ip
  get_ipinfo
  print_config
}

# 主程序
install_hysteria
