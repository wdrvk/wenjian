#!/bin/bash
# 介绍信息
{
    echo -e "\e[92m" 
    echo "通往电脑的路不止一条"
    echo -e "\e[0m"  
}

# 获取当前用户名
USER=$(whoami)
USER_HOME=$(readlink -f /home/$USER)
HYSTERIA_WORKDIR="$USER_HOME/.hysteria"

# 创建必要的目录，如果不存在
[ ! -d "$HYSTERIA_WORKDIR" ] && mkdir -p "$HYSTERIA_WORKDIR"

###################################################

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
    FILE_INFO=("https://download.hysteria.network/app/latest/hysteria-freebsd-arm64 web")
  elif [[ "$ARCH" == "amd64" || "$ARCH" == "x86_64" || "$ARCH" == "x86" ]]; then
    FILE_INFO=("https://download.hysteria.network/app/latest/hysteria-freebsd-amd64 web")
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

# 获取IP地址函数
get_all_ips() {
    local ips=()
    
    # 使用 netstat 替代 ifconfig，因为它通常不需要 root 权限
    local local_ips=$(netstat -in | awk '/^[a-z]/ { if($4 != "0.0.0.0") print $4 }')
    
    # 获取本地IP
    for ip in $local_ips; do
        if ! is_private_ip "$ip"; then
            ips+=("$ip")
        fi
    done
    
    # 从多个外部服务获取IP
    local ext_services=(
        "https://4.ipw.cn"
        "https://ipv4.icanhazip.com"
        "https://api4.ipify.org"
        "https://v4.ident.me"
    )
    
    for service in "${ext_services[@]}"; do
        local ext_ip=$(fetch -qo - "$service" 2>/dev/null)
        if [[ -n "$ext_ip" ]] && ! is_private_ip "$ext_ip"; then
            ips+=("$ext_ip")
        fi
    done
    
    # IPv6 检测
    local ext_ipv6_services=(
        "https://6.ipw.cn"
        "https://ipv6.icanhazip.com"
        "https://api6.ipify.org"
    )
    
    for service in "${ext_ipv6_services[@]}"; do
        local ext_ipv6=$(fetch -qo - "$service" 2>/dev/null)
        if [[ -n "$ext_ipv6" ]] && [[ $ext_ipv6 != fe80:* ]]; then
            ips+=("$ext_ipv6")
        fi
    done
    
    # 删除重复项并返回结果
    printf '%s\n' "${ips[@]}" | sort -u
}

# 检查是否是内网IP
is_private_ip() {
    local ip=$1
    local ip_parts
    IFS='.' read -ra ip_parts <<< "$ip"
    
    # 检查IP格式是否正确
    [[ ${#ip_parts[@]} -ne 4 ]] && return 1
    
    # 检查是否是私有IP范围
    if [[ ${ip_parts[0]} -eq 10 ]] || \
       [[ ${ip_parts[0]} -eq 172 && ${ip_parts[1]} -ge 16 && ${ip_parts[1]} -le 31 ]] || \
       [[ ${ip_parts[0]} -eq 192 && ${ip_parts[1]} -eq 168 ]]; then
        return 0
    fi
    return 1
}

# 测试IP可用性
test_ip_connectivity() {
    local ip=$1
    local test_domains=("www.google.com" "www.cloudflare.com" "www.github.com")
    local success=0
    
    # 设置较短的超时时间
    for domain in "${test_domains[@]}"; do
        if fetch -T 3 -o /dev/null "https://${domain}" >/dev/null 2>&1; then
            ((success++))
        fi
    done
    
    # 如果至少有2个测试站点可访问，则认为IP可用
    [[ $success -ge 2 ]]
    return $?
}

# 主要的IP检测和选择函数
get_best_ip() {
    echo -e "\e[1;34m正在检测可用的IP地址...\e[0m"
    local available_ips=()
    local selected_ip=""
    
    # 获取所有外网IP
    while IFS= read -r ip; do
        echo -e "\e[1;37m检测IP: $ip\e[0m"
        if test_ip_connectivity "$ip"; then
            echo -e "\e[1;32m✓ IP $ip 可用\e[0m"
            available_ips+=("$ip")
        else
            echo -e "\e[1;31m✗ IP $ip 不可用\e[0m"
        fi
    done < <(get_all_ips)
    
    # 如果有可用IP，选择第一个
    if [[ ${#available_ips[@]} -gt 0 ]]; then
        selected_ip="${available_ips[0]}"
        echo -e "\e[1;32m选择可用IP: $selected_ip\e[0m"
        HOST_IP="$selected_ip"
    else
        echo -e "\e[1;31m未找到可用的IP地址\e[0m"
        exit 1
    fi
}

# 替换原有的get_ip函数
get_ip() {
    get_best_ip
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

# 添加 crontab 守护进程任务
add_crontab_task() {
  crontab -l > /tmp/crontab.bak
  echo "*/12 * * * * if ! pgrep -x web; then nohup $HYSTERIA_WORKDIR/web server $HYSTERIA_WORKDIR/config.yaml >/dev/null 2>&1 & fi" >> /tmp/crontab.bak
  crontab /tmp/crontab.bak
  rm /tmp/crontab.bak
  echo -e "\e[1;32mCrontab 任务添加完成\e[0m"
}

# 主程序
read -p "是否安装 Hysteria？(Y/N 回车N)" install_hysteria_answer
install_hysteria_answer=${install_hysteria_answer^^}

if [[ "$install_hysteria_answer" == "Y" ]]; then
  install_hysteria
fi

read -p "是否添加 crontab 任务来守护进程？(Y/N 回车N)" add_crontab_answer
add_crontab_answer=${add_crontab_answer^^}

if [[ "$add_crontab_answer" == "Y" ]]; then
  add_crontab_task
fi