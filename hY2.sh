#!/bin/bash
# 介绍信息
{
    echo -e "\e[92m" 
    echo "通往电脑的路不止一条，所有的信息都应该是免费的，打破电脑特权，在电脑上创造艺术和美，计算机将使生活更美好。"
    echo "    ______                   _____               _____         "
    echo "    ___  /_ _____  ____________  /______ ___________(_)______ _"
    echo "    __  __ \\__  / / /__  ___/_  __/_  _ \\__  ___/__  / _  __ \`/"
    echo "    _  / / /_  /_/ / _(__  ) / /_  /  __/_  /    _  /  / /_/ / "
    echo "    /_/ /_/ _\\__, /  /____/  \\__/  \\___/ /_/     /_/   \\__,_/  "
    echo "            /____/                                              "
    echo "                          ______          __________          "
    echo "    ______________ __________  /_____________  ____/         "
    echo "    __  ___/_  __ \\_  ___/__  //_/__  ___/______ \\           "
    echo "    _(__  ) / /_/ // /__  _  ,<   _(__  )  ____/ /        不要直连"
    echo "    /____/  \\____/ \\___/  /_/|_|  /____/  /_____/         没有售后"
    echo "缝合怪：天诚 原作者们：cmliu RealNeoMan、k0baya、eooce"
    echo "交流群:https://t.me/cncomorg"
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

# 获取IP地址函数
get_ip() {
  ipv4=$(curl -s 4.ipw.cn)
  if [[ -n "$ipv4" ]]; then
    HOST_IP="$ipv4"
  else
    ipv6=$(curl -s --max-time 1 6.ipw.cn)
    if [[ -n "$ipv6" ]]; then
      HOST_IP="$ipv6"
    else
      echo -e "\e[1;35m无法获取IPv4或IPv6地址\033[0m"
      exit 1
    fi
  fi
  echo -e "\e[1;32m本机IP: $HOST_IP\033[0m"
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