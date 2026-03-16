from remu_tools.rm_utils import *

class Remulator:
    def __init__(self, config_path):

        # 初始化仿真状态变量
        rm_args = rm_load_file(config_path)
        self.nodes = []
        self.links = []
        self.emulation_time = 0
        self.docker_service_name = 'uav-task'
        self.node_size = rm_args.node_size
        self.container_global_idx = 1
        self.login_message, self.transport =   rm_init_remote_machine(
            rm_args.remote_machine_IP, rm_args.remote_machine_username,
            rm_args.remote_machine_password)
        if self.login_message is None:
            print('Remote SSH login failure.')
            return
        if self.transport is None:
            print('Remote transport login failure.')
            return

        
        # 初始化远程连接 (如果需要)
        # self.remote_ssh = initialize_remote_connection(...)
        
        # 初始化其他核心模块，如数据生成器 (模仿 StarryNet 对 Observer 的调用)
        # self.observer = MyObserver(self.config)
        # print("2. 调用 Observer 生成仿真所需的物理数据...")
        # self.observer.generate_physical_data()

    def create_host_nodes(self):
        rm_thread = rm_HostNode_Init_Thread(self.login_message, self.docker_service_name,self.nodes,self.node_size,self.container_global_idx)
        rm_thread.start()
        rm_thread.join()
        print("3. 创建网络节点...")
        # 在这里实现创建节点（如 Docker 容器）的逻辑
        # 这部分可以调用一个工具函数，类似 sn_utils.py 中的 sn_Node_Init_Thread
        self.container_id_list = rm_get_container_info(self.login_message)
        print("Constellation initialization done. " +
              str(len(self.container_id_list)) + " have been created.")

    # def create_links(self):
    #     """
    #     定义创建节点间链路的方法。
    #     """
    #     print("4. 创建节点间的链路...")
    #     # 在这里实现创建链路（如 Docker network）并配置网络参数的逻辑
    #     # 类似 sn_utils.py 中的 sn_Link_Init_Thread
    #     pass
        
    # def start_emulation(self):
    #     """
    #     启动主仿真循环。
    #     """
    #     print("5. 开始仿真循环...")
    #     # 这里将是仿真的主循环，按时间步进，更新网络状态
    #     # 类似 sn_utils.py 中的 sn_Emulation_Start_Thread
    #     # for t in range(self.duration):
    #     #     print(f"  - 仿真时间: {t}s")
    #     #     # 更新链路延迟、处理拓扑变化等
    #     #     time.sleep(1)
    #     print("仿真结束。")

    # def stop_emulation(self):
    #     """
    #     清理和停止仿真环境。
    #     """
    #     print("6. 停止仿真，清理环境...")
    #     # 实现清理逻辑，如删除 Docker 容器和网络
    #     # 类似 sn_utils.py 中的 sn_Emulation_Stop_Thread
    #     pass

    # # 您可以添加更多自定义的API方法
    # def set_traffic(self, src_node, dst_node, start_time):
    #     """
    #     定义一个在特定时间注入流量的API。
    #     """
    #     print(f"计划在 {start_time}s 从节点 {src_node} 到 {dst_node} 发送流量。")
    #     pass
