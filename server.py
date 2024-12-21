from flask import Flask, send_from_directory, jsonify
import socket
import json
import threading
import time
from datetime import datetime

app = Flask(__name__)

class MonitorServer:
    def __init__(self, host='0.0.0.0', port=12870):
        self.host = host  # 监听地址
        self.data_port = port  # 数据端口
        self.clients = {}  # 使用用户名作为键保存客户端数据
        self.running = False  # 服务器运行状态标志
        self.lock = threading.Lock()  # 线程锁，用于保护共享数据

    def start_data_server(self):
        # 创建数据服务器套接字
        server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            server_socket.bind((self.host, self.data_port))  # 绑定地址和端口
            server_socket.listen(5)  # 设置监听队列大小
            server_socket.settimeout(1)  # 设置超时时间为1秒

            print(f"监控服务器正在监听 {self.host}:{self.data_port}")

            while self.running:
                try:
                    # 接受客户端连接
                    client_socket, addr = server_socket.accept()
                    # 为每个客户端启动一个线程处理数据
                    threading.Thread(target=self.handle_client, 
                                      args=(client_socket, addr),
                                      daemon=True).start()
                except socket.timeout:
                    continue  # 如果超时，继续等待新连接
                except Exception as e:
                    print(f"接受客户端时出错: {e}")
                    if not self.running:
                        break
        except Exception as e:
            print(f"启动数据服务器时出错: {e}")
        finally:
            server_socket.close()  # 关闭服务器套接字

    def handle_client(self, client_socket, addr):
        try:
            # 接收客户端数据
            data = client_socket.recv(4096).decode()
            if data:
                metrics = json.loads(data)  # 解析JSON数据
                username = metrics['username']  # 获取用户名

                with self.lock:
                    # 更新或添加客户端数据
                    self.clients[username] = {
                        'metrics': metrics,  # 保存客户端指标
                        'last_update': time.time(),  # 保存最近更新时间
                        'status': '在线'  # 默认状态为在线
                    }
                print(f"收到来自 {username} 的数据")
        except json.JSONDecodeError as e:
            print(f"来自客户端 {addr} 的无效JSON数据: {e}")
        except Exception as e:
            print(f"处理客户端 {addr} 时出错: {e}")
        finally:
            client_socket.close()  # 关闭客户端连接

    def clean_inactive_clients(self):
        """清理长时间未更新的客户端"""
        while self.running:
            time.sleep(60)  # 每分钟检查一次
            current_time = time.time()
            with self.lock:
                # 标记10分钟未更新的客户端为离线并移除
                for username, data in list(self.clients.items()):
                    if current_time - data['last_update'] > 600:  # 10分钟超时
                        print(f"移除长时间未响应的客户端: {username}")
                        del self.clients[username]

    def start(self):
        self.running = True  # 设置服务器运行状态
        # 启动数据服务器线程
        threading.Thread(target=self.start_data_server, daemon=True).start()
        # 启动清理线程
        threading.Thread(target=self.clean_inactive_clients, daemon=True).start()
        print("监控服务器已启动")

    def get_clients_data(self):
        current_time = time.time()
        with self.lock:
            result = []
            for username, data in self.clients.items():
                # 如果30秒内无更新，标记为离线
                if current_time - data['last_update'] > 30:
                    data['status'] = '离线'
                else:
                    data['status'] = '在线'

                client_data = {
                    'ip': data['metrics'].get('ip_addresses')[0],  # 显示第一个IP地址
                    'hostname': data['metrics'].get('hostname', '未知'),  # 主机名
                    'username': data['metrics'].get('username', '未知'),  # 用户名
                    'cpu_percent': data['metrics'].get('cpu_percent', 0),  # CPU使用率
                    'memory_percent': data['metrics'].get('memory_percent', 0),  # 内存使用率
                    'network_speed': data['metrics'].get('network_speed', {'upload': 0, 'download': 0}),  # 网络速度
                    'status': data['status'],  # 状态
                    'last_update': datetime.fromtimestamp(data['last_update']).strftime('%Y-%m-%d %H:%M:%S')  # 最近更新时间
                }
                result.append(client_data)
            return result

# 创建服务器实例
monitor_server = MonitorServer()

@app.route('/')
def index():
    return send_from_directory('static', 'index.html')  # 返回前端静态页面

@app.route('/api/clients')
def get_clients():
    return jsonify(monitor_server.get_clients_data())  # 返回客户端数据的JSON响应

if __name__ == '__main__':
    try:
        monitor_server.start()  # 启动监控服务器
        app.run(host='0.0.0.0', port=37200, debug=False)  # 启动Flask服务
    except Exception as e:
        print(f"服务器运行时出错: {e}")
