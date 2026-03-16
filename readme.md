ReMu is a firmware architecture for data plane emualtion with containered nodes. 
## 1.Introduction to overall platform
hardware：FPGA NIC (Xilinx Alveo U250 )  

software：Python3.11, OVS2,DPDK22.11,docker
## 2.Components of data plane emulator 
Link emulator
Traffic manager
Switch emulator
## 3.Configurations of redircting software switch
DPDK accelerates the port connecting to FPGA card. 
## 4.Functions of orchestrator
ReMu Orchestrator takes charge of creating nodes managing OVS connections and sending configuration packets to data plane emulator. 



