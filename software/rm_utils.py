import os
import threading
import json
import copy
import argparse
import os
from time import sleep
import time
#import numpy
import random
try:
    import threading
except ImportError:
    os.system("pip3 install threading")
    import threading

try:
    import paramiko
except ImportError:
    os.system("pip3 install paramiko")
    import paramiko

try:
    import requests
except ImportError:
    os.system("pip3 install requests")
    import requests


class rm_HostNode_Init_Thread(threading.Thread):
    def __init__(self,login_message, docker_service_name, nodes,node_size,container_global_idx):
        threading.Thread.__init__(self)
        self.login_message = login_message  
        self.docker_service_name = docker_service_name
        self.nodes = nodes
        self.node_size = node_size
        self.container_global_idx = container_global_idx

    def run(self):
        rm_reset_docker_env(self.login_message, self.docker_service_name, self.node_size)

        self.container_id_list = rm_get_container_info(self.login_message)
        # Rename all containers with the global idx
        rm_rename_all_container(self.login_message, self.container_id_list,
                                self.container_global_idx)
        


def rm_reset_docker_env(login_message, docker_service_name, node_size):
    print("Reset docker environment for  emulation ...")
    print("Remove legacy containers.")
    print(rm_remote_cmd(login_message,
                        "docker service rm " + docker_service_name))
    print(rm_remote_cmd(login_message, "docker rm -f $(docker ps -a -q)"))

    # rm_delete_remote_network_bridge(login_message)
    print("Creating new containers...")
    #Creating new containers...

    ##Todo:modify the docker image 
    rm_remote_cmd(
        login_message, "docker service create --replicas " + str(node_size) +
        " --name " + str(docker_service_name) +
        " --cap-add ALL swr.cn-north-4.myhuaweicloud.com/ddn-k8s/ghcr.io/linuxserver/baseimage-ubuntu:jammy ping www.baidu.com")
def rm_remote_cmd(login_message, cmd):
    stdin, stdout, stderr = login_message.exec_command(cmd, get_pty=True)
    lines = stdout.readlines()
    return lines


            # rm_args.remote_machine_IP, rm_args.remote_machine_username,
            # rm_args.remote_machine_password)
def rm_load_file(config_path):
    f = open("./config.json", "r", encoding='utf8')
    table = json.load(f)
    data = {}
    data["node_size"] = table["node_size"]
    data['remote_machine_IP'] = table['remote_machine_IP']
    data['remote_machine_username'] = table['remote_machine_username']
    data['remote_machine_password'] = table['remote_machine_password']
    parser = argparse.ArgumentParser(description='manual to this script')
    parser.add_argument('--node_size', type=int, default=data['node_size'])
    parser.add_argument('--remote_machine_IP',
                        type=str,
                        default=data['remote_machine_IP'])
    parser.add_argument('--remote_machine_username',
                        type=str,
                        default=data['remote_machine_username'])
    parser.add_argument('--remote_machine_password',
                        type=str,
                        default=data['remote_machine_password'])
    rm_args = parser.parse_args()

    return rm_args

def rm_init_remote_machine(host, username, password):
    # transport = paramiko.Transport((host, 22))
    # transport.connect(username=username, password=password)
    login_message = paramiko.SSHClient()
    # remote_machine_ssh._transport = transport
    login_message.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    login_message.connect(hostname=host,
                          port=22,
                               username=username,
                               password=password)
    transport = paramiko.Transport((host, 22))
    transport.connect(username=username, password=password)
    return login_message, transport
    # transport.close()

def rm_get_container_info(login_message):
    #  Read all container information in all_container_info
    all_container_info = rm_remote_cmd(login_message, "docker ps")
    n_container = len(all_container_info) - 1
    container_id_list = []
    for container_idx in range(1, n_container + 1):
        container_id_list.append(all_container_info[container_idx].split()[0])

    return container_id_list


def rm_rename_all_container(login_message, container_id_list, new_idx):
    print("Rename all containers ...")
    # new_idx = 1  # 删除此行，否则外部传入的 container_global_idx 会被忽略
    for container_id in container_id_list:
        rm_remote_cmd(
            login_message, "docker rename " + str(container_id) +
            " ovs_container_" + str(new_idx))
        new_idx = new_idx + 1
