import docker
import subprocess
import threading
import time
from scapy.all import Ether, Dot1Q, IP, UDP, Packet, BitField, ByteField, IntField, StrFixedLenField, sendp

# ==========================================
# 3. FPGA 报文定义 (基于 Scapy)
# ==========================================
class FPGAConfigHeader(Packet):
    name = "FPGAConfigHeader"
    fields_desc = [
        BitField("resource_id", 0, 12),     # 12 bits Resource ID
        BitField("reserved", 0, 4),         # 4 bits reserved
        ByteField("index", 0),              # 8 bits (1 Byte) index
        IntField("cookie", 0),              # 4 Bytes cookie
        StrFixedLenField("padding", b'\x00'*11, 11) # 11 Bytes padding
    ]

class FPGAManager:
    def __init__(self, iface):
        self.iface = iface
        self.running = False

    def send_config(self, res_id, index, cookie, payload=b''):
        # 构造报文: Eth / VLAN / IP / UDP / FPGAHeader / Payload
        pkt = Ether() / Dot1Q(vlan=100) / IP(dst="192.168.1.100") / UDP(sport=1234, dport=5678) \
              / FPGAConfigHeader(resource_id=res_id, reserved=0, index=index, cookie=cookie) \
              / payload
        sendp(pkt, iface=self.iface, verbose=False)
        print(f"[FPGA Manager] 发送配置报文: Resource={res_id}, Index={index}")

    def run_periodic_config(self):
        self.running = True
        idx = 0
        while self.running:
            self.send_config(res_id=1, index=idx % 255, cookie=0xABCD1234, payload=b'init')
            idx += 1
            time.sleep(5) # 模拟周期性发送配置

# ==========================================
# 1. 容器管理模块
# ==========================================
class ContainerManager:
    def __init__(self):
        self.client = docker.from_env()
        self.containers = {}

    def create_and_run(self, name, image="ubuntu:latest"):
        print(f"[Container Manager] 创建并启动容器: {name}")
        # 实际环境中需要挂载 vhost-user sockets 目录
        cont = self.client.containers.run(image, name=name, detach=True, tty=True)
        self.containers[name] = cont
        return cont

    def pause_container(self, name):
        if name in self.containers:
            print(f"[Container Manager] 暂停容器: {name}")
            self.containers[name].pause()

    def collect_stats(self):
        while True:
            for name, cont in self.containers.items():
                try:
                    stats = cont.stats(stream=False)
                    # 此处可提取所需的 CPU/Mem/Net 状态数据
                    print(f"[Container Manager] 容器 {name} 状态: CPU使用率收集中...")
                except Exception as e:
                    pass
            time.sleep(10)

# ==========================================
# 2. OVS-DPDK 管理模块
# ==========================================
class OVSDPDKManager:
    def __init__(self, bridge="br-dpdk"):
        self.bridge = bridge

    def run_cmd(self, cmd):
        subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def configure_flows(self, container_ports, fpga_port):
        print("[OVS-DPDK Manager] 开始配置 DPDK 轮询与流表...")
        # 1. 清空现有流表
        self.run_cmd(f"ovs-ofctl del-flows {self.bridge}")
        
        # 2. 容器 -> FPGA 重定向
        for port in container_ports:
            self.run_cmd(f"ovs-ofctl add-flow {self.bridge} \"in_port={port}, actions=output:{fpga_port}\"")
            
        # 3. FPGA -> 容器 路由回传 (假设已知各容器的 MAC)
        # 示例：将目的 MAC 匹配的流量送回对应容器
        # self.run_cmd(f"ovs-ofctl add-flow {self.bridge} \"in_port={fpga_port}, dl_dst=<CONT_MAC>, actions=output:{port}\"")
        print("[OVS-DPDK Manager] 流表配置完成。")

# ==========================================
# 主控调度 (并发运行)
# ==========================================
def main():
    print("=== 启动网络仿真器管理器 ===")
    
    # 初始化模块
    cm = ContainerManager()
    ovsm = OVSDPDKManager(bridge="br-dpdk")
    fpgam = FPGAManager(iface="eth1") # 假设直连 FPGA 的管理口是 eth1

    # 1. 启动容器
    cm.create_and_run("node1")
    cm.create_and_run("node2")

    # 2. 配置 OVS-DPDK 流表 (假设 node1 port 为 1, node2 port 为 2, FPGA port 为 3)
    ovsm.configure_flows(container_ports=[1, 2], fpga_port=3)

    # 3. 并发运行常驻任务
    threads = []
    
    # 线程A：容器状态采集
    t_stats = threading.Thread(target=cm.collect_stats, daemon=True)
    threads.append(t_stats)
    
    # 线程B：FPGA 配置报文发送任务
    t_fpga = threading.Thread(target=fpgam.run_periodic_config, daemon=True)
    threads.append(t_fpga)

    for t in threads:
        t.start()

    try:
        while True:
            time.sleep(1) # 保持主进程运行，这里可以接入 CLI 交互
    except KeyboardInterrupt:
        print("\n=== 关闭网络仿真器管理器 ===")
        fpgam.running = False

if __name__ == "__main__":
    main()