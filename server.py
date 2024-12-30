from flask import Flask, send_from_directory, jsonify
import socket
import json
import threading
import time
from datetime import datetime
import requests
import pytz

# wxpusher 配置
WX_PUSHER_APP_TOKEN = "AT_oTcuJlivNzoQgwbR8IIVUC1sLYaENLGc"
WX_PUSHER_TOPIC_ID = "36159"

def send_wxpusher_message(title, content):
    """使用 wxpusher 主题推送功能发送消息"""
    url = "https://wxpusher.zjiecode.com/api/send/message"

    data = {
        "appToken": WX_PUSHER_APP_TOKEN,
        "content": content,
        "summary": title,
        "contentType": 1,
        "topicIds": [WX_PUSHER_TOPIC_ID],
    }

    try:
        response = requests.post(url, json=data, headers={'Content-Type': 'application/json'})
        response_data = response.json()
        if response_data.get("code") == 1000:
            print("有主机掉线，发送微信通知")
        else:
            print(f"[{datetime.now(pytz.timezone('Asia/Shanghai'))}] 微信推送失败：{response_data}")
    except Exception as e:
        print(f"[{datetime.now(pytz.timezone('Asia/Shanghai'))}] 微信推送请求失败：{e}")

app = Flask(__name__)

class MonitorServer:
    def __init__(self, host='0.0.0.0', port=12870):
        self.host = host
        self.data_port = port
        self.clients = {}
        self.running = False
        self.lock = threading.Lock()

    def start_data_server(self):
        server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            server_socket.bind((self.host, self.data_port))
            server_socket.listen(5)
            server_socket.settimeout(1)

            print(f"Monitor server listening on {self.host}:{self.data_port}")

            while self.running:
                try:
                    client_socket, addr = server_socket.accept()
                    threading.Thread(target=self.handle_client, 
                                  args=(client_socket, addr),
                                  daemon=True).start()
                except socket.timeout:
                    continue
                except Exception as e:
                    print(f"Error accepting client: {e}")
                    if not self.running:
                        break
        except Exception as e:
            print(f"Error starting data server: {e}")
        finally:
            server_socket.close()

    def handle_client(self, client_socket, addr):
        try:
            data = client_socket.recv(4096).decode()
            if data:
                metrics = json.loads(data)
                username = metrics['username']

                with self.lock:
                    if username not in self.clients:
                        self.clients[username] = {
                            'metrics': metrics,
                            'last_update': time.time(),
                            'status': 'Online',
                            'notified_offline': False
                        }
                    else:
                        self.clients[username]['metrics'] = metrics
                        self.clients[username]['last_update'] = time.time()
                        self.clients[username]['status'] = 'Online'
                        self.clients[username]['notified_offline'] = False

                print(f"Received data from {username}")
        except json.JSONDecodeError as e:
            print(f"Invalid JSON from client {addr}: {e}")
        except Exception as e:
            print(f"Error handling client {addr}: {e}")
        finally:
            client_socket.close()

    def monitor_clients(self):
        while self.running:
            time.sleep(30)
            current_time = time.time()
            with self.lock:
                for username, data in self.clients.items():
                    if current_time - data['last_update'] > 30:
                        if not data['notified_offline']:
                            print(f"Client {username} offline, sending notification.")
                            send_wxpusher_message("serv00掉线通知", f"客户端 {username} 掉线")
                            self.clients[username]['notified_offline'] = True
                        self.clients[username]['status'] = 'Offline'

    def get_clients_data(self):
        with self.lock:
            beijing_tz = pytz.timezone('Asia/Shanghai')
            result = []
            for username, data in self.clients.items():
                beijing_time = datetime.fromtimestamp(data['last_update']).astimezone(beijing_tz)
                
                client_data = {
                    'ip': data['metrics'].get('ip_addresses', ['Unknown'])[0],
                    'hostname': data['metrics'].get('hostname', 'Unknown').split('.')[0], 
                    'username': data['metrics'].get('username', 'Unknown'),  
                    'cpu_percent': data['metrics'].get('cpu_percent', 0),
                    'memory_percent': data['metrics'].get('memory_percent', 0),
                    'network_speed': data['metrics'].get('network_speed', {'upload': 0, 'download': 0}),
                    'status': data['status'],
                    'last_update': beijing_time.strftime('%Y-%m-%d %H:%M:%S')
                }
                result.append(client_data)
            return result

    def start(self):
        self.running = True
        threading.Thread(target=self.start_data_server, daemon=True).start()
        threading.Thread(target=self.monitor_clients, daemon=True).start()
        print("Monitor server started")

# 创建服务器实例
monitor_server = MonitorServer()

@app.route('/')
def index():
    return send_from_directory('static', 'index.html')

@app.route('/api/clients')
def get_clients():
    return jsonify(monitor_server.get_clients_data())

if __name__ == '__main__':
    try:
        monitor_server.start()
        app.run(host='0.0.0.0', port=37200, debug=False)
    except Exception as e:
        print(f"Server error: {e}")