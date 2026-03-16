ReMu is a firmware architecture for data plane emualtion with containered nodes. 
## 1.Introduction to overall platform
Hardware：FPGA NIC (Xilinx Alveo U250 )  

Software：Python3.11, OVS2.2.1,DPDK22.11,docker
## 2.Components of data plane emulator 
Link Emulator：The Link Emulator in the ReMu system consists of the Geography Information Table (GIT), the Link Model Table (LMT), and Link Parameter Units (LPUs), all of which are derived from the Match and Action Table (MAT). While the former two stages utilize an extractor and a lookup engine, the LPU is augmented with an action engine.

Traffic manager: The Traffic Manager shapes traffic with virtual depareture time. Traffic manager reuse the calendar queues code CQ_deta.v for multi-level calendar queues structure.
Switch Emulator: The Switch Emulator consists of Switch Tables (STs) and a Connection Table (CT) to mimic L2/L3 operations on packets

## 3.Configurations of redircting software switch
The configuration of the redirecting software switch is primarily achieved by running a script before the emulation starts
## 4.Functions of orchestrator
ReMu Orchestrator takes charge of creating nodes managing OVS connections and sending configuration packets to data plane emulator. 


* [hardware/](./hardware/): Contains RTL source code.
    * [link_emulator/](./hardware/link_emulator/): Core emulation logic.
        * [`data_path_bit_cfg.v`](./hardware/link_emulator/data_path_bit_cfg.v):
