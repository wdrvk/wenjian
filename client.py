# 导入需要的库
import psutil        # 用于获取系统信息
import socket        # 用于网络通信
import json         # 用于数据序列化
import time         # 用于时间相关操作
import netifaces    # 用于获取网络接口信息
import getpass      # 用于获取用户名
from threading import Thread, Lock  # 用于多线程操作
from datetime import datetime      # 用于处理日期时间

class MonitorClient:
    def __init__(self, server_host='hjghkwu.serv00.net', server_port=12870):
        # 初始化监控客户端
        self.server_host = server_host      # 服务器地址
        self.server_port = server_port      # 服务器端口
        self.running = False                # 运行状态标志
        self.lock = Lock()                  # 线程锁，用于保护共享数据
        self.last_net_io = None            # 上次网络IO数据
        self.last_net_time = None          # 上次网络IO时间
        self.retry_interval = 5            # 重试间隔（秒）
        self.max_retries = 3               # 最大重试次数
        
    def get_network_speed(self):
        """计算网络速度，避免阻塞数据收集"""
        # 获取当前网络IO计数
        current_net_io = psutil.net_io_counters()
        current_time = time.time()
        
        with self.lock:  # 使用线程锁保护共享数据
            # 如果是首次获取数据，初始化基准值
            if self.last_net_io is None or self.last_net_time is None:
                self.last_net_io = current_net_io
                self.last_net_time = current_time
                return {'upload': 0, 'download': 0}
            
            # 计算时间差，避免除以很小的数
            time_delta = current_time - self.last_net_time
            if time_delta < 0.1:
                return {'upload': 0, 'download': 0}
            
            # 计算上传和下载速度
            upload_speed = (current_net_io.bytes_sent - self.last_net_io.bytes_sent) / time_delta
            download_speed = (current_net_io.bytes_recv - self.last_net_io.bytes_recv) / time_delta
            
            # 更新基准值
            self.last_net_io = current_net_io
            self.last_net_time = current_time
            
            # 返回计算结果
            return {
                'upload': int(upload_speed),
                'download': int(download_speed)
            }
        
    def get_system_metrics(self):
        """收集系统指标数据"""
        try:
            # 获取CPU使用率（非阻塞方式）
            cpu_percent = psutil.cpu_percent(interval=None)
            
            # 获取内存使用情况
            memory = psutil.virtual_memory()
            memory_percent = memory.percent
            
            # 获取网络速度
            network_speed = self.get_network_speed()
            
            # 获取IP地址（排除回环地址）
            ip_addresses = []
            for interface in netifaces.interfaces():
                try:
                    addrs = netifaces.ifaddresses(interface)
                    if netifaces.AF_INET in addrs:
                        for addr in addrs[netifaces.AF_INET]:
                            if addr['addr'] != '127.0.0.1':
                                ip_addresses.append(addr['addr'])
                except Exception as e:
                    print(f"获取网络接口 {interface} 的IP地址时出错: {e}")
            
            # 获取当前用户名
            username = getpass.getuser()
            
            # 返回收集的所有数据
            return {
                'cpu_percent': cpu_percent,
                'memory_percent': memory_percent,
                'network_speed': network_speed,
                'ip_addresses': ip_addresses,
                'hostname': socket.gethostname(),
                'username': username,
                'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            }
        except Exception as e:
            print(f"获取系统信息时出错: {e}")
            return None
    
    def send_metrics(self):
        """发送指标数据到服务器，包含重试逻辑"""
        consecutive_failures = 0  # 连续失败次数
        
        while self.running:
            try:
                # 获取系统指标数据
                metrics = self.get_system_metrics()
                if metrics is None:
                    raise Exception("无法获取系统数据")
                
                # 尝试发送数据，最多重试max_retries次
                for attempt in range(self.max_retries):
                    try:
                        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                            sock.settimeout(5)  # 设置5秒超时
                            sock.connect((self.server_host, self.server_port))
                            sock.send(json.dumps(metrics).encode())
                            consecutive_failures = 0  # 发送成功，重置失败计数
                            break
                    except socket.error as e:
                        # 处理不同类型的网络错误
                        if e.errno == 61:
                            print("服务器未运行")
                        elif e.errno == 60:
                            print("连接服务器超时")
                        elif e.errno == 8:
                            print("无法解析服务器地址")
                        else:
                            print(f"网络连接错误: {e}")
                        
                        if attempt == self.max_retries - 1:
                            raise
                        time.sleep(1)
                
            except Exception as e:
                # 处理连续失败的情况
                consecutive_failures += 1
                if consecutive_failures >= 3:
                    print("连续多次连接失败，增加重试间隔...")
                    time.sleep(self.retry_interval * 2)
                else:
                    time.sleep(self.retry_interval)
                continue
            
            time.sleep(self.retry_interval)
    
    def start(self):
        """启动监控客户端"""
        print(f"正在启动监控客户端... 连接到 {self.server_host}:{self.server_port}")
        self.running = True
        Thread(target=self.send_metrics, daemon=True).start()
    
    def stop(self):
        """停止监控客户端"""
        print("正在停止监控客户端...")
        self.running = False

def main():
    """主函数"""
    import argparse
    
    # 创建命令行参数解析器
    parser = argparse.ArgumentParser(description='系统监控客户端')
    parser.add_argument('--host', default='hjghkwu.serv00.net',
                      help='监控服务器地址')
    parser.add_argument('--port', type=int, default=12870,
                      help='监控服务器端口')
    parser.add_argument('--interval', type=int, default=5,
                      help='数据发送间隔（秒）')
    
    # 解析命令行参数
    args = parser.parse_args()
    
    # 创建并配置客户端实例
    client = MonitorClient(server_host=args.host, server_port=args.port)
    client.retry_interval = args.interval
    
    try:
        # 启动客户端
        client.start()
        print("按 Ctrl+C 停止客户端...")
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        # 处理键盘中断
        client.stop()
        print("\n客户端已停止.")
    except Exception as e:
        # 处理其他异常
        print(f"发生意外错误: {e}")
        client.stop()

# 程序入口点
if __name__ == '__main__':
    main()