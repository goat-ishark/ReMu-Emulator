ReMu is a firmware architecture for data plane emualtion with containered nodes. 
## 1.Introduction to overall platform
Hardware：FPGA NIC (Xilinx Alveo U250 )  

Software：Python3.11, OVS2.2.1,DPDK20.11,docker
## 2.Components of data plane emulator 
Link Emulator：The Link Emulator in the ReMu system consists of the Geography Information Table (GIT), the Link Model Table (LMT), and Link Parameter Units (LPUs), all of which are derived from the Match and Action Table (MAT). While the former two stages utilize an extractor and a lookup engine, the LPU is augmented with an action engine.

Traffic manager: The Traffic Manager shapes traffic with virtual depareture time. Traffic manager reuse the calendar queues code CQ_deta.v for multi-level calendar queues structure.

Switch Emulator: The Switch Emulator consists of Switch Tables (STs) and a Connection Table (CT) to mimic L2/L3 operations on packets

PHV Format： The metadata of PHV traverse through stages follows the format like:
255       240 239   232 231                    88 87         64 63         49 48      33 32                 1 0
+-----------+---------+-------------------------+-------------+-------------+----------+--------------------+---+
|           |         |                         |             |             |          |                    | l |
|  flow_id  |  link_  |        Reserved         |  port_info  |  Reserved   | pkt_len  |  scheduling_time   | o |
|           |  model  |                         |             |             |          |                    | s |
|           |         |                         |             |             |          |                    | s |
+-----------+---------+-------------------------+-------------+-------------+----------+--------------------+---+
   16 bit      8 bit           144 bit              24 bit        15 bit       16 bit          32 bit       1b 
     2B         1B               18B                  3B                         2B              4B

## 3.Configurations of redircting software switch
The configuration of the redirecting software switch is primarily achieved by running a script before the emulation starts.

## 4.Functions of orchestrator
ReMu Orchestrator takes charge of creating nodes managing OVS connections and sending configuration packets to data plane emulator. 

## 5.Running ReMu
Users can define network topologies and link models via JSON configuration files. A  Python script then initializes the emulation environment and generates  performance reports.
