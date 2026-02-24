`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/10 13:44:09
// Design Name: 
// Module Name: tm_top_beta
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tm_top_beta

#(
    parameter	 C_S_AXIS_TDATA_WIDTH = 512,
    parameter	 C_S_AXIS_TUSER_WIDTH = 256,
    parameter    C_S_AXIS_TKEEP_WIDTH = 32,

    parameter   DDR4_AXIS_DATA_WIDTH = 512,
    parameter   DDR4_AXIS_STRB_WIDTH = DDR4_AXIS_DATA_WIDTH/8, //512/8=64

    parameter   RAM_AXIS_DATA_WIDTH = 512,
    parameter   RAM_AXIS_STRB_WIDTH = RAM_AXIS_DATA_WIDTH/8, 

    parameter   PKT_LEN_WIDTH = 16,  // the width for pkt length  1518 needs 11bits
    parameter   TIME_SCALE_WIDTH = 32// the width for virtual time


)



(
    input                                   i_pkt_data_valid5     ,
    input  [C_S_AXIS_TDATA_WIDTH/2-1    :0]    i_pkt5_data0          ,
    input  [C_S_AXIS_TDATA_WIDTH/2-1    :0]    i_pkt5_data1          ,
    input  [C_S_AXIS_TDATA_WIDTH/2-1    :0]    i_pkt5_data2          ,
    input  [C_S_AXIS_TDATA_WIDTH/2-1    :0]    i_pkt5_data3          ,
    input  [C_S_AXIS_TDATA_WIDTH/2-1    :0]    i_pkt5_data4          ,
    input  [C_S_AXIS_TDATA_WIDTH/2-1    :0]    i_pkt5_data5          ,
    input  [C_S_AXIS_TDATA_WIDTH/2-1    :0]    i_pkt5_data6          ,
    input  [C_S_AXIS_TDATA_WIDTH/2-1    :0]    i_pkt5_data7          ,
    input  [255                      :0]       i_metadata            , 
    input                                      i_metadata_vld        ,

    output                                  o_tuser_fifo_rd_en     ,
	input  [C_S_AXIS_TUSER_WIDTH-1 :0]      i_snd_half_fifo_tuser  ,
	input  [C_S_AXIS_TKEEP_WIDTH-1 :0]      i_snd_half_fifo_tkeep  ,
	input                                   i_snd_half_fifo_tlast  ,

	input [C_S_AXIS_TDATA_WIDTH-1:0]	    i_seg_fifo_tdata_out   ,
	input [C_S_AXIS_TUSER_WIDTH-1:0]	    i_seg_fifo_tuser_out   ,
	input [C_S_AXIS_TKEEP_WIDTH-1:0]	  	i_seg_fifo_tkeep_out   ,
	input							                	  i_seg_fifo_tlast_out   ,
	output                               	o_seg_fifo_rd_en       ,
	input                              	    i_seg_fifo_empty       ,
   
    output wire    [C_S_AXIS_TDATA_WIDTH-1:0]   depar_out_tdata     ,
    output wire    [C_S_AXIS_TKEEP_WIDTH-1:0]   depar_out_tkeep     ,
    output wire    [C_S_AXIS_TUSER_WIDTH-1:0]   depar_out_tuser     ,
    output wire                                 depar_out_tvalid    ,
    output wire                                 depar_out_tlast     ,
	input                                      depar_out_tready     ,


    //DDR4 interface

    output wire                                c0_init_calib_complete, // output wire c0_init_calib_complete
    output wire                                dbg_clk, // output wire dbg_clk
    input wire                                 c0_sys_clk_p, // input wire c0_sys_clk_p
    input wire                                 c0_sys_clk_n, // input wire c0_sys_clk_n
    output wire [511 : 0]                      dbg_bus, // output wire [511 : 0] dbg_bus
    output wire [16 : 0]                       c0_ddr4_adr, // output wire [16 : 0] c0_ddr4_adr
    output wire [1 : 0]                        c0_ddr4_ba, // output wire [1 : 0] c0_ddr4_ba
    output wire [0 : 0]                        c0_ddr4_cke, // output wire [0 : 0] c0_ddr4_cke
    output wire [0 : 0]                        c0_ddr4_cs_n, // output wire [0 : 0] c0_ddr4_cs_n
    inout wire [7 : 0]                         c0_ddr4_dm_dbi_n, // inout wire [7 : 0] c0_ddr4_dm_dbi_n
    inout wire [63 : 0]                        c0_ddr4_dq, // inout wire [63 : 0] c0_ddr4_dq
    inout wire [7 : 0]                         c0_ddr4_dqs_c, // inout wire [7 : 0] c0_ddr4_dqs_c
    inout wire [7 : 0]                         c0_ddr4_dqs_t, // inout wire [7 : 0] c0_ddr4_dqs_t
    output wire [0 : 0]                        c0_ddr4_odt, // output wire [0 : 0] c0_ddr4_odt
    output wire [1 : 0]                        c0_ddr4_bg, // output wire [1 : 0] c0_ddr4_bg
    output wire                                c0_ddr4_reset_n, // output wire c0_ddr4_reset_n
    output wire                                c0_ddr4_act_n, // output wire c0_ddr4_act_n
    output wire [0 : 0]                        c0_ddr4_ck_c, // output wire [0 : 0] c0_ddr4_ck_c
    output wire [0 : 0]                        c0_ddr4_ck_t, // output wire [0 : 0] c0_ddr4_ck_t
    output wire                                c0_ddr4_ui_clk, // output wire c0_ddr4_ui_clk
    output wire                                c0_ddr4_ui_clk_sync_rst,   // output wire c0_ddr4_ui_clk_sync_rst
    input  wire                                c0_ddr4_aresetn,
    input  wire                                sys_rst
    );

    wire [TIME_SCALE_WIDTH-1:0]         virtual_time ;
    wire                               ddr_clk;
    assign                             ddr_clk = c0_ddr4_ui_clk;

    // Add these wire declarations in tm_top_beta
    wire                                                 c_chooser_coarse_cq_ddr4_data_en;
    wire  [PKT_LEN_WIDTH+TIME_SCALE_WIDTH-1:0]           c_chooser_coarse_cq_ddr4_descripter;
    wire  [C_S_AXIS_TDATA_WIDTH-1:0]                     c_chooser_coarse_cq_ddr4_axis_tdata;
    wire  [C_S_AXIS_TDATA_WIDTH/8-1:0]                   c_chooser_coarse_cq_ddr4_axis_tstrb;
    wire                                                 c_chooser_coarse_cq_ddr4_axis_tlast;
    wire                                                 c_chooser_coarse_cq_ddr4_axis_tvalid;
    wire                                                 c_chooser_coarse_cq_ddr4_axis_tready;

    wire                                                 c_chooser_switch_data_en;
   wire [PKT_LEN_WIDTH+TIME_SCALE_WIDTH-1:0]            c_chooser_switch_descripter;
   wire [C_S_AXIS_TDATA_WIDTH-1:0]                      c_chooser_switch_axis_wdata;
   wire [C_S_AXIS_TDATA_WIDTH/8-1:0]                    c_chooser_switch_axis_wstrb;
   wire                                                 c_chooser_switch_axis_wlast   ; 
   wire                                                 c_chooser_switch_axis_wvalid  ;
   wire                                                 c_chooser_switch_axis_wready  ;

    wire                                                 c_coarse_cq_switch_data_en;
    wire [PKT_LEN_WIDTH+TIME_SCALE_WIDTH-1:0]            c_coarse_cq_switch_descripter;
    wire [C_S_AXIS_TDATA_WIDTH-1:0]                     c_coarse_cq_switch_axis_wdata;
    wire [C_S_AXIS_TDATA_WIDTH/8-1:0]                    c_coarse_cq_switch_axis_wstrb;
    wire                                                 c_coarse_cq_switch_axis_wlast;
    wire                                                 c_coarse_cq_switch_axis_wvalid;
    wire                                                 c_coarse_cq_switch_axis_wready;

    wire                                                 c_switch_fine_cq_data_en;
   wire [PKT_LEN_WIDTH+TIME_SCALE_WIDTH-1:0]            c_switch_fine_cq_descripter;
   wire [C_S_AXIS_TDATA_WIDTH-1:0]                      c_switch_fine_cq_axis_wdata;
   wire [C_S_AXIS_TDATA_WIDTH/8-1:0]                    c_switch_fine_cq_axis_wstrb;
   wire                                                 c_switch_fine_cq_axis_wlast;    
   wire                                                 c_switch_fine_cq_axis_wvalid; 
   wire                                                 c_switch_fine_cq_axis_wready;

    wire [31:0]    c0_ddr4_s_axi_awaddr;
    wire [7:0]     c0_ddr4_s_axi_awlen;
    wire [2:0]     c0_ddr4_s_axi_awsize;
    wire [1:0]     c0_ddr4_s_axi_awburst;
    wire [3:0]     c0_ddr4_s_axi_awcache;
    wire [2:0]     c0_ddr4_s_axi_awprot;
    wire           c0_ddr4_s_axi_awvalid;
    wire           c0_ddr4_s_axi_awready;

    wire [511:0]   c0_ddr4_s_axi_wdata;
    wire [63:0]    c0_ddr4_s_axi_wstrb;
    wire           c0_ddr4_s_axi_wlast;
    wire           c0_ddr4_s_axi_wvalid;
    wire           c0_ddr4_s_axi_wready;

    wire           c0_ddr4_s_axi_bready;
    wire [1:0]     c0_ddr4_s_axi_bresp;
    wire           c0_ddr4_s_axi_bvalid;

    wire [31:0]    c0_ddr4_s_axi_araddr;
    wire [7:0]     c0_ddr4_s_axi_arlen;
    wire [2:0]     c0_ddr4_s_axi_arsize;
    wire [1:0]     c0_ddr4_s_axi_arburst;
    wire [3:0]     c0_ddr4_s_axi_arcache;
    wire [2:0]     c0_ddr4_s_axi_arprot;
    wire           c0_ddr4_s_axi_arvalid;
    wire           c0_ddr4_s_axi_arready;

    wire           c0_ddr4_s_axi_rready;
    wire [511:0]   c0_ddr4_s_axi_rdata;
    wire [1:0]     c0_ddr4_s_axi_rresp;
    wire           c0_ddr4_s_axi_rlast;
    wire           c0_ddr4_s_axi_rvalid;

        wire [31 : 0] s_axi_awaddr;
    wire [7 : 0] s_axi_awlen;
    wire [2 : 0] s_axi_awsize;
    wire [1 : 0] s_axi_awburst;
    wire [3 : 0] s_axi_awcache;
    wire [2 : 0] s_axi_awprot;

    wire s_axi_awvalid;
    wire s_axi_awready;
    wire [511 : 0] s_axi_wdata;
    wire [63 : 0] s_axi_wstrb;
    wire s_axi_wlast;
    wire s_axi_wvalid;
    wire s_axi_wready;
    wire [1 : 0] s_axi_bresp;
    wire s_axi_bvalid;
    wire s_axi_bready;
    wire [21 : 0] s_axi_araddr;
    wire [7 : 0] s_axi_arlen;
    wire [2 : 0] s_axi_arsize;
    wire [1 : 0] s_axi_arburst;

    wire [3 : 0] s_axi_arcache;
    wire [2 : 0] s_axi_arprot;
    wire s_axi_arvalid;
    wire s_axi_arready;
    wire [511 : 0] s_axi_rdata;
    wire [1 : 0] s_axi_rresp;
    wire s_axi_rlast;
    wire s_axi_rvalid;
    wire s_axi_rready;



    virtual_time virtual_time_inst
    (
        .clk       (ddr_clk),
        .rst_n     (c0_ddr4_aresetn),
        .virtual_time (virtual_time)
    );


    mem_chooser mem_chooser_inst
    (
        //input 

       .clk                         (ddr_clk),
       .aresetn                     (c0_ddr4_aresetn),
       .virtual_time                (virtual_time),
       .i_pkt_data_valid5           (i_pkt_data_valid5 ),
       .i_pkt5_data0                (i_pkt5_data0),
       .i_pkt5_data1                (i_pkt5_data1),
       .i_pkt5_data2                (i_pkt5_data2),
       .i_pkt5_data3                (i_pkt5_data3),
       .i_pkt5_data4                (i_pkt5_data4),
       .i_pkt5_data5                (i_pkt5_data5),
       .i_pkt5_data6                (i_pkt5_data6),
       .i_pkt5_data7                (i_pkt5_data7),
       .i_metadata                  (i_metadata),
       .i_metadata_vld              (i_metadata_vld),

       .pkt_fifo_tdata        (i_seg_fifo_tdata_out),
       .pkt_fifo_tuser        (i_seg_fifo_tuser_out),
       .pkt_fifo_tkeep        (i_seg_fifo_tkeep_out),
       .pkt_fifo_tlast        (i_seg_fifo_tlast_out),
       .pkt_fifo_rd_en            (o_seg_fifo_rd_en),  
       .pkt_fifo_empty            (i_seg_fifo_empty),
       
       //converting into axis to ddr4_addr_manager
       .o_ddr4_data_en               (c_chooser_coarse_cq_ddr4_data_en),   
       .o_ddr4_descripter            (c_chooser_coarse_cq_ddr4_descripter),
       .o_ddr4_axis_wdata            (c_chooser_coarse_cq_ddr4_axis_tdata),
       .o_ddr4_axis_wstrb            (c_chooser_coarse_cq_ddr4_axis_tstrb),
       .o_ddr4_axis_wlast            (c_chooser_coarse_cq_ddr4_axis_tlast),
       .o_ddr4_axis_wvalid           (c_chooser_coarse_cq_ddr4_axis_tvalid),
       .i_ddr4_axis_wready           (c_chooser_coarse_cq_ddr4_axis_tready),
       //converting into axis_switch
        .o_switch_data_en            (c_chooser_switch_data_en),
        .o_switch_descripter         (c_chooser_switch_descripter),
        .o_switch_axis_wdata         (c_chooser_switch_axis_wdata),
        .o_switch_axis_wstrb         (c_chooser_switch_axis_wstrb),
        .o_switch_axis_wlast         (c_chooser_switch_axis_wlast),
        .o_switch_axis_wvalid        (c_chooser_switch_axis_wvalid),
        .i_switch_axis_wready        (c_chooser_switch_axis_wready)

    );

    CQ_deta    #(
        .FIFO_NUMBER (160),  //160
        .TOTAL_TIME (128)  //128
    ) coarse_CQ 

    (
        .clk(ddr_clk),
        .aresetn(c0_ddr4_aresetn),
        .virtual_time(virtual_time),

        .i_data_en(c_chooser_coarse_cq_ddr4_data_en),
        .i_pkt_descripter(c_chooser_coarse_cq_ddr4_descripter),

        .i_axis_tdata(c_chooser_coarse_cq_ddr4_axis_tdata),
        .i_axis_tstrb(c_chooser_coarse_cq_ddr4_axis_tstrb),
        .i_axis_tlast(c_chooser_coarse_cq_ddr4_axis_tlast),
        .i_axis_tvalid(c_chooser_coarse_cq_ddr4_axis_tvalid),
        .o_axis_tready(c_chooser_coarse_cq_ddr4_axis_tready),

        .o_data_en(c_coarse_cq_switch_data_en),
        .o_pkt_descripter(c_coarse_cq_switch_descripter),
        .m_axis_tdata(c_coarse_cq_switch_axis_wdata),
        .m_axis_tstrb(c_coarse_cq_switch_axis_wstrb),
        .m_axis_tlast(c_coarse_cq_switch_axis_wlast),
        .m_axis_tvalid(c_coarse_cq_switch_axis_wvalid),
        .m_axis_tready(1'b1),

        .s_axi_awaddr(c0_ddr4_s_axi_awaddr),
        .s_axi_awlen(c0_ddr4_s_axi_awlen),
        .s_axi_awsize(c0_ddr4_s_axi_awsize),
        .s_axi_awburst(c0_ddr4_s_axi_awburst),
        .s_axi_awcache(c0_ddr4_s_axi_awcache),
        .s_axi_awprot(c0_ddr4_s_axi_awprot),
        .s_axi_awuser(),
        .s_axi_awvalid(c0_ddr4_s_axi_awvalid),
        .s_axi_awready(c0_ddr4_s_axi_awready),

        .s_axi_wdata(c0_ddr4_s_axi_wdata),
        .s_axi_wstrb(c0_ddr4_s_axi_wstrb),
        .s_axi_wlast(c0_ddr4_s_axi_wlast),
        .s_axi_wvalid(c0_ddr4_s_axi_wvalid),
        .s_axi_wready(c0_ddr4_s_axi_wready),

        .s_axi_bresp(c0_ddr4_s_axi_bresp),
        .s_axi_bvalid(c0_ddr4_s_axi_bvalid),
        .s_axi_bready(c0_ddr4_s_axi_bready),

        .s_axi_araddr(c0_ddr4_s_axi_araddr),
        .s_axi_arlen(c0_ddr4_s_axi_arlen),
        .s_axi_arsize(c0_ddr4_s_axi_arsize),
        .s_axi_arburst(c0_ddr4_s_axi_arburst),
        .s_axi_arcache(c0_ddr4_s_axi_arcache),
        .s_axi_arprot(c0_ddr4_s_axi_arprot),
        .s_axi_aruser(),
        .s_axi_arvalid(c0_ddr4_s_axi_arvalid),
        .s_axi_arready(c0_ddr4_s_axi_arready),

        .s_axi_rdata(c0_ddr4_s_axi_rdata),
        .s_axi_rresp(c0_ddr4_s_axi_rresp),
        .s_axi_rlast(c0_ddr4_s_axi_rlast),
        .s_axi_rvalid(c0_ddr4_s_axi_rvalid),
        .s_axi_rready(c0_ddr4_s_axi_rready)
    );

    axis_switch axis_switch_ins
    (
        .clk                        (ddr_clk),
        .aresetn                    (c0_ddr4_aresetn),
        // input from mem_chooser
        .i_switch_data_en           (c_chooser_switch_data_en),
        .i_switch_descripter        (c_chooser_switch_descripter),
        .i_switch_axis_wdata         (c_chooser_switch_axis_wdata),
        .i_switch_axis_wstrb         (c_chooser_switch_axis_wstrb),
        .i_switch_axis_wlast         (c_chooser_switch_axis_wlast),
        .i_switch_axis_wvalid        (c_chooser_switch_axis_wvalid),
        .o_switch_axis_wready        (c_chooser_switch_axis_wready),

        //input from coarse-grained calendar queues
        .i_ddr4_data_en             (c_coarse_cq_switch_data_en),
        .i_ddr4_descripter          (c_coarse_cq_switch_descripter),
        .i_ddr4_axis_wdata           (c_coarse_cq_switch_axis_wdata),
        .i_ddr4_axis_wstrb           (c_coarse_cq_switch_axis_wstrb),
        .i_ddr4_axis_wlast           (c_coarse_cq_switch_axis_wlast),
        .i_ddr4_axis_wvalid          (c_coarse_cq_switch_axis_wvalid),
        .o_ddr4_axis_wready          (c_coarse_cq_switch_axis_wready),
        //output to fine-grained calendar queues                                                       
        .o_ram_data_en              (c_switch_fine_cq_data_en),
        .o_ram_descripter           (c_switch_fine_cq_descripter),
        .o_ram_axis_wdata           (c_switch_fine_cq_axis_wdata),
        .o_ram_axis_wstrb           (c_switch_fine_cq_axis_wstrb),
        .o_ram_axis_wlast           (c_switch_fine_cq_axis_wlast),
        .o_ram_axis_wvalid          (c_switch_fine_cq_axis_wvalid),
        .i_ram_axis_wready          (c_switch_fine_cq_axis_wready)

    );

    CQ_deta   #(
        .FIFO_NUMBER (160),
        .TOTAL_TIME (0.8)
    )fine_CQ 
    (
        .clk(c0_ddr4_ui_clk),
        .aresetn(c0_ddr4_aresetn),
        .virtual_time(virtual_time),
        .i_data_en(c_switch_fine_cq_data_en),
        .i_pkt_descripter(c_switch_fine_cq_descripter),

        .i_axis_tdata(c_switch_fine_cq_axis_wdata),
        .i_axis_tstrb(c_switch_fine_cq_axis_wstrb),
        .i_axis_tlast(c_switch_fine_cq_axis_wlast),
        .i_axis_tvalid(c_switch_fine_cq_axis_wvalid),
        .o_axis_tready(c_switch_fine_cq_axis_wready),

        .o_data_en(),
        .o_pkt_descripter(),
        .m_axis_tdata(depar_out_tdata),
        .m_axis_tstrb(depar_out_tkeep),
        .m_axis_tlast(depar_out_tlast),
        .m_axis_tvalid(depar_out_tvalid),
        .m_axis_tready(depar_out_tready),


        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awlen(s_axi_awlen),
        .s_axi_awsize(s_axi_awsize),
        .s_axi_awburst(s_axi_awburst),
        .s_axi_awcache(s_axi_awcache),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awuser(),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),

        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wlast(s_axi_wlast),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),

        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),

        .s_axi_araddr(s_axi_araddr),
        .s_axi_arlen(s_axi_arlen),
        .s_axi_arsize(s_axi_arsize),
        .s_axi_arburst(s_axi_arburst),
        .s_axi_arcache(s_axi_arcache),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_aruser(),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),

        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rlast(s_axi_rlast),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready)
        

    );

    ddr4_0 ddr4_ins (
        .c0_init_calib_complete(c0_init_calib_complete),
        .dbg_clk(dbg_clk),
        .c0_sys_clk_p(c0_sys_clk_p),
        .c0_sys_clk_n(c0_sys_clk_n),
        .dbg_bus(dbg_bus),
        .c0_ddr4_adr(c0_ddr4_adr),
        .c0_ddr4_ba(c0_ddr4_ba),
        .c0_ddr4_cke(c0_ddr4_cke),
        .c0_ddr4_cs_n(c0_ddr4_cs_n),
        .c0_ddr4_dm_dbi_n(c0_ddr4_dm_dbi_n),
        .c0_ddr4_dq(c0_ddr4_dq),
        .c0_ddr4_dqs_c(c0_ddr4_dqs_c),
        .c0_ddr4_dqs_t(c0_ddr4_dqs_t),
        .c0_ddr4_odt(c0_ddr4_odt),
        .c0_ddr4_bg(c0_ddr4_bg),
        .c0_ddr4_reset_n(c0_ddr4_reset_n),
        .c0_ddr4_act_n(c0_ddr4_act_n),
        .c0_ddr4_ck_c(c0_ddr4_ck_c),
        .c0_ddr4_ck_t(c0_ddr4_ck_t),
        .c0_ddr4_ui_clk(c0_ddr4_ui_clk),
        .c0_ddr4_ui_clk_sync_rst(c0_ddr4_ui_clk_sync_rst),
        .c0_ddr4_aresetn(c0_ddr4_aresetn),
        .c0_ddr4_s_axi_awid(1'b0),            // input wire [0 : 0] c0_ddr4_s_axi_awid
        .c0_ddr4_s_axi_awaddr(c0_ddr4_s_axi_awaddr),        // input wire [31 : 0] c0_ddr4_s_axi_awaddr
        .c0_ddr4_s_axi_awlen(c0_ddr4_s_axi_awlen),          // input wire [7 : 0] c0_ddr4_s_axi_awlen
        .c0_ddr4_s_axi_awsize(c0_ddr4_s_axi_awsize),        // input wire [2 : 0] c0_ddr4_s_axi_awsize
        .c0_ddr4_s_axi_awburst(c0_ddr4_s_axi_awburst),      // input wire [1 : 0] c0_ddr4_s_axi_awburst
        .c0_ddr4_s_axi_awlock(1'b0),        // input wire [0 : 0] c0_ddr4_s_axi_awlock
        .c0_ddr4_s_axi_awcache(c0_ddr4_s_axi_awcache),      // input wire [3 : 0] c0_ddr4_s_axi_awcache
        .c0_ddr4_s_axi_awprot(c0_ddr4_s_axi_awprot),        // input wire [2 : 0] c0_ddr4_s_axi_awprot
        .c0_ddr4_s_axi_awqos(4'b0),          // input wire [3 : 0] c0_ddr4_s_axi_awqos
        .c0_ddr4_s_axi_awvalid(c0_ddr4_s_axi_awvalid),      // input wire c0_ddr4_s_axi_awvalid
        .c0_ddr4_s_axi_awready(c0_ddr4_s_axi_awready),      // output wire c0_ddr4_s_axi_awready
        .c0_ddr4_s_axi_wdata(c0_ddr4_s_axi_wdata),          // input wire [511 : 0] c0_ddr4_s_axi_wdata
        .c0_ddr4_s_axi_wstrb(c0_ddr4_s_axi_wstrb),          // input wire [63 : 0] c0_ddr4_s_axi_wstrb
        .c0_ddr4_s_axi_wlast(c0_ddr4_s_axi_wlast),          // input wire c0_ddr4_s_axi_wlast
        .c0_ddr4_s_axi_wvalid(c0_ddr4_s_axi_wvalid),        // input wire c0_ddr4_s_axi_wvalid
        .c0_ddr4_s_axi_wready(c0_ddr4_s_axi_wready),        // output wire c0_ddr4_s_axi_wready
        .c0_ddr4_s_axi_bready(c0_ddr4_s_axi_bready),        // input wire c0_ddr4_s_axi_bready
        .c0_ddr4_s_axi_bid(c0_ddr4_s_axi_bid),              // output wire [0 : 0] c0_ddr4_s_axi_bid
        .c0_ddr4_s_axi_bresp(c0_ddr4_s_axi_bresp),          // output wire [1 : 0] c0_ddr4_s_axi_bresp
        .c0_ddr4_s_axi_bvalid(c0_ddr4_s_axi_bvalid),        // output wire c0_ddr4_s_axi_bvalid
        .c0_ddr4_s_axi_arid(1'b0),            // input wire [0 : 0] c0_ddr4_s_axi_arid
        .c0_ddr4_s_axi_araddr(c0_ddr4_s_axi_araddr),        // input wire [31 : 0] c0_ddr4_s_axi_araddr
        .c0_ddr4_s_axi_arlen(c0_ddr4_s_axi_arlen),          // input wire [7 : 0] c0_ddr4_s_axi_arlen
        .c0_ddr4_s_axi_arsize(c0_ddr4_s_axi_arsize),        // input wire [2 : 0] c0_ddr4_s_axi_arsize
        .c0_ddr4_s_axi_arburst(c0_ddr4_s_axi_arburst),      // input wire [1 : 0] c0_ddr4_s_axi_arburst
        .c0_ddr4_s_axi_arlock(1'b0),        // input wire [0 : 0] c0_ddr4_s_axi_arlock
        .c0_ddr4_s_axi_arcache(c0_ddr4_s_axi_arcache),      // input wire [3 : 0] c0_ddr4_s_axi_arcache
        .c0_ddr4_s_axi_arprot(c0_ddr4_s_axi_arprot),        // input wire [2 : 0] c0_ddr4_s_axi_arprot
        .c0_ddr4_s_axi_arqos(4'b0),          // input wire [3 : 0] c0_ddr4_s_axi_arqos
        .c0_ddr4_s_axi_arvalid(c0_ddr4_s_axi_arvalid),      // input wire c0_ddr4_s_axi_arvalid
        .c0_ddr4_s_axi_arready(c0_ddr4_s_axi_arready),      // output wire c0_ddr4_s_axi_arready
        .c0_ddr4_s_axi_rready(c0_ddr4_s_axi_rready),        // input wire c0_ddr4_s_axi_rready
        .c0_ddr4_s_axi_rlast(c0_ddr4_s_axi_rlast),          // output wire c0_ddr4_s_axi_rlast
        .c0_ddr4_s_axi_rvalid(c0_ddr4_s_axi_rvalid),        // output wire c0_ddr4_s_axi_rvalid
        .c0_ddr4_s_axi_rresp(c0_ddr4_s_axi_rresp),          // output wire [1 : 0] c0_ddr4_s_axi_rresp
        .c0_ddr4_s_axi_rid(c0_ddr4_s_axi_rid),              // output wire [0 : 0] c0_ddr4_s_axi_rid
        .c0_ddr4_s_axi_rdata(c0_ddr4_s_axi_rdata),          // output wire [511 : 0] c0_ddr4_s_axi_rdata
        .sys_rst(sys_rst)

    );

    axi_bram bram_ins (
        .s_axi_aclk(c0_ddr4_ui_clk),        // input wire s_axi_aclk
        .s_axi_aresetn(!c0_ddr4_ui_clk_sync_rst),  // input wire s_axi_aresetn
        .s_axi_awaddr(s_axi_awaddr[21:0]),    // input wire [21 : 0] s_axi_awaddr
        .s_axi_awlen(s_axi_awlen),      // input wire [7 : 0] s_axi_awlen
        .s_axi_awsize(s_axi_awsize),    // input wire [2 : 0] s_axi_awsize
        .s_axi_awburst(s_axi_awburst),  // input wire [1 : 0] s_axi_awburst
        .s_axi_awlock(),    // input wire s_axi_awlock
        .s_axi_awcache(s_axi_awcache),  // input wire [3 : 0] s_axi_awcache
        .s_axi_awprot(s_axi_awprot),    // input wire [2 : 0] s_axi_awprot
        .s_axi_awvalid(s_axi_awvalid),  // input wire s_axi_awvalid
        .s_axi_awready(s_axi_awready),  // output wire s_axi_awready
        .s_axi_wdata(s_axi_wdata),      // input wire [511 : 0] s_axi_wdata
        .s_axi_wstrb(s_axi_wstrb),      // input wire [63 : 0] s_axi_wstrb
        .s_axi_wlast(s_axi_wlast),      // input wire s_axi_wlast
        .s_axi_wvalid(s_axi_wvalid),    // input wire s_axi_wvalid
        .s_axi_wready(s_axi_wready),    // output wire s_axi_wready
        .s_axi_bresp(s_axi_bresp),      // output wire [1 : 0] s_axi_bresp
        .s_axi_bvalid(s_axi_bvalid),    // output wire s_axi_bvalid
        .s_axi_bready(s_axi_bready),    // input wire s_axi_bready
        .s_axi_araddr(s_axi_araddr[21:0]),    // input wire [21 : 0] s_axi_araddr
        .s_axi_arlen(s_axi_arlen),      // input wire [7 : 0] s_axi_arlen
        .s_axi_arsize(s_axi_arsize),    // input wire [2 : 0] s_axi_arsize
        .s_axi_arburst(s_axi_arburst),  // input wire [1 : 0] s_axi_arburst
        .s_axi_arlock(),    // input wire s_axi_arlock
        .s_axi_arcache(s_axi_arcache),  // input wire [3 : 0] s_axi_arcache
        .s_axi_arprot(s_axi_arprot),    // input wire [2 : 0] s_axi_arprot
        .s_axi_arvalid(s_axi_arvalid),  // input wire s_axi_arvalid
        .s_axi_arready(s_axi_arready),  // output wire s_axi_arready
        .s_axi_rdata(s_axi_rdata),      // output wire [511 : 0] s_axi_rdata
        .s_axi_rresp(s_axi_rresp),      // output wire [1 : 0] s_axi_rresp
        .s_axi_rlast(s_axi_rlast),      // output wire s_axi_rlast
        .s_axi_rvalid(s_axi_rvalid),    // output wire s_axi_rvalid
        .s_axi_rready(s_axi_rready)    // input wire s_axi_rready
    );



endmodule
