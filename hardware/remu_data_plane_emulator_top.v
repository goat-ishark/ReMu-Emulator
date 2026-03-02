`timescale 1ns / 1ps

//* +------------+     +--------+     +-----+     +-----+     +------+     +----------+
//* | pkt_filter |---->| parser |---->| GIT |---->| LMT |---->| LPUs |---->| deparser |
//* +------------+  ^  +--------+     +-----+     +-----+     +------+     +----------+
//				 * |                                                             |
//				 * |                                                             v
//				 * |                                                          +----+
//				 * |                                                          | TM |
//				 * |                                                          +----+
//				 * |                                                             |
// * +----------+    |+----------+     +--------+     +----+     +----+     +-----v-+       
// * | Egress/  |<--| recirculator |<----|deparser|<----| CT |<----| ST |<----| parser |
// * ||---------+     +----------+     +----------+   +----+     +----+     +--------+  

module data_plane_emulator_top #(

	parameter C_S_AXIS_TDATA_WIDTH = 512,
	parameter C_S_AXIS_TUSER_WIDTH = 256,
	parameter C_S_AXIS_TKEEP_WIDTH = 64,
	parameter C_VLANID_WIDTH = 12,
	parameter LINK_PARSER_INIT_FILE             = 1,
	parameter SWITCH_PARSER_INIT_FILE           = 1
	
)
(


	// input Slave AXI Stream
	input [C_S_AXIS_TDATA_WIDTH-1:0]		    s_axis_tdata ,
	input [C_S_AXIS_TKEEP_WIDTH-1:0]		    s_axis_tkeep ,
	input [C_S_AXIS_TUSER_WIDTH-1:0]			s_axis_tuser ,
	input										s_axis_tvalid,
	output										s_axis_tready,
	input										s_axis_tlast ,
	// output Master AXI Stream
	output     [C_S_AXIS_TDATA_WIDTH-1:0]		m_axis_tdata ,
	output     [C_S_AXIS_TKEEP_WIDTH-1:0]	    m_axis_tkeep ,
	output     [C_S_AXIS_TUSER_WIDTH-1:0]		m_axis_tuser ,
	output    									m_axis_tvalid,
	input										m_axis_tready,
	output  									m_axis_tlast,

	//DDR interface
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

    input  wire                                c0_ddr4_aresetn,
    input  wire                                sys_rst

	
);




localparam PHV_LEN = (8+4+2)*8*8+100+256;//1252 bits
localparam PARSER_MOD_ID = 3'd1;
localparam C_NUM_SEGS = 4;
localparam PKTS_LEN = 2048;
localparam PARSER_NUM = 24;
localparam PARSER_ACT_WIDTH = 16;
localparam DEPARSER_MOD_ID  = 3'd5;
localparam PKT_BYTE_LENGTH_W     = 16;

localparam GIT_KEY_LEN = 96;
localparam GIT_KEY_OFF = 38;
localparam GIT_RAM_LEN = 11;

localparam LMT_KEY_LEN = 96;
localparam LMT_KEY_OFF = 38;
localparam LMT_RAM_LEN = 11;

localparam BW_KEY_LEN = 24;
localparam BW_ACT_LEN = 16;

localparam DELAY_KEY_LEN = 24;
localparam DELAY_ACT_LEN = 16;

localparam LOSS_KEY_LEN = 24;
localparam LOSS_ACT_LEN = 16;

wire                                c0_ddr4_ui_clk;
wire                                c0_ddr4_ui_clk_sync_rst;

wire                                 clk = c0_ddr4_ui_clk;
wire                                 aresetn = ~c0_ddr4_ui_clk_sync_rst;

// stage-related
wire [PHV_LEN-1:0]				    stg0_phv_in;
wire								stg0_phv_in_valid;
wire								stg0_phv_in_end;
	
wire [PHV_LEN-1:0]				    stg0_phv_out;
wire								stg0_phv_out_valid;

wire [PHV_LEN-1:0]				    stg1_phv_out;
wire								stg1_phv_out_valid;

wire [PHV_LEN-1:0]				    stg2_phv_out;
wire								stg2_phv_out_valid;

wire [PHV_LEN-1:0]				    stg3_phv_out;
wire								stg3_phv_out_valid;

wire [PHV_LEN-1:0]				    stg4_phv_out;
wire								stg4_phv_out_valid;

wire [PHV_LEN-1:0]				    stg5_phv_out;
wire								stg5_phv_out_valid;

reg [PHV_LEN-1:0]					stg0_phv_in_d1;
reg [PHV_LEN-1:0]					stg0_phv_out_d1;
reg [PHV_LEN-1:0]					stg1_phv_out_d1;
reg [PHV_LEN-1:0]					stg2_phv_out_d1;
reg [PHV_LEN-1:0]					stg3_phv_out_d1;
reg [PHV_LEN-1:0]					stg4_phv_out_d1;
reg [PHV_LEN-1:0]					stg5_phv_out_d1;


reg									stg0_phv_in_valid_d1;
reg									stg0_phv_out_valid_d1;
reg									stg1_phv_out_valid_d1;
reg									stg2_phv_out_valid_d1;
reg									stg3_phv_out_valid_d1;
reg									stg4_phv_out_valid_d1;
reg									stg5_phv_out_valid_d1;


reg									stg0_phv_in_end_d1;
// back pressure signals
wire 								s_axis_tready_p;
wire 								stg0_ready;
wire 								stg1_ready;
wire 								stg2_ready;
wire 								stg3_ready;
wire 								stg4_ready;
wire 								stg5_ready;




	wire                                       pkt_data_valid5;
	wire [C_S_AXIS_TDATA_WIDTH/2-1:0]          pkt5_data0;
	wire [C_S_AXIS_TDATA_WIDTH/2-1:0]          pkt5_data1;
	wire [C_S_AXIS_TDATA_WIDTH/2-1:0]          pkt5_data2;
	wire [C_S_AXIS_TDATA_WIDTH/2-1:0]          pkt5_data3;
	wire [C_S_AXIS_TDATA_WIDTH/2-1:0]          pkt5_data4;
	wire [C_S_AXIS_TDATA_WIDTH/2-1:0]          pkt5_data5;
	wire [C_S_AXIS_TDATA_WIDTH/2-1:0]          pkt5_data6;
	wire [C_S_AXIS_TDATA_WIDTH/2-1:0]          pkt5_data7;
	wire [255:0]                               metadata;
	wire                                       metadata_vld;

wire [C_S_AXIS_TDATA_WIDTH-1:0] depar_out_tdata;
wire [C_S_AXIS_TKEEP_WIDTH-1:0] depar_out_tkeep;
wire [C_S_AXIS_TUSER_WIDTH-1:0] depar_out_tuser;
wire depar_out_tvalid;
wire depar_out_tlast;
wire depar_out_tready;

reg [C_S_AXIS_TDATA_WIDTH-1:0] depar_out_tdata_r;
reg [C_S_AXIS_TKEEP_WIDTH-1:0] depar_out_tkeep_r;
reg [C_S_AXIS_TUSER_WIDTH-1:0] depar_out_tuser_r;
reg depar_out_tvalid_r;
reg depar_out_tlast_r;
reg depar_out_tready_r;

wire tuser_fifo_rd_en;
wire [C_S_AXIS_TUSER_WIDTH-1:0] snd_half_fifo_tuser;
wire [C_S_AXIS_TKEEP_WIDTH-1:0] snd_half_fifo_tkeep;
wire snd_half_fifo_tlast;

wire [C_S_AXIS_TDATA_WIDTH-1:0] seg_fifo_tdata_out;
wire [C_S_AXIS_TUSER_WIDTH-1:0] seg_fifo_tuser_out;
wire [C_S_AXIS_TKEEP_WIDTH-1:0] seg_fifo_tkeep_out;
wire seg_fifo_tlast_out;
wire seg_fifo_rd_en;
wire seg_fifo_empty;

wire [C_S_AXIS_TDATA_WIDTH-1:0] s_axis_tdata_f;
wire [C_S_AXIS_TKEEP_WIDTH-1:0] s_axis_tkeep_f;
wire [C_S_AXIS_TUSER_WIDTH-1:0] s_axis_tuser_f;
wire                           s_axis_tvalid_f;
wire                           s_axis_tready_f;
wire                           s_axis_tlast_f;

//NOTE: filter control packets from data packets.
wire [C_S_AXIS_TDATA_WIDTH-1:0]				ctrl_s_axis_tdata_1;
wire [C_S_AXIS_TKEEP_WIDTH-1:0]		        ctrl_s_axis_tkeep_1;
wire [C_S_AXIS_TUSER_WIDTH-1:0]				ctrl_s_axis_tuser_1;
wire										ctrl_s_axis_tvalid_1;
wire										ctrl_s_axis_tlast_1;

reg  [C_S_AXIS_TDATA_WIDTH-1:0]				ctrl_s_axis_tdata_1_r;
reg  [C_S_AXIS_TKEEP_WIDTH-1:0]		        ctrl_s_axis_tkeep_1_r;
reg  [C_S_AXIS_TUSER_WIDTH-1:0]				ctrl_s_axis_tuser_1_r;
reg 										ctrl_s_axis_tvalid_1_r;
reg 										ctrl_s_axis_tlast_1_r;

wire [C_S_AXIS_TDATA_WIDTH-1:0]				ctrl_s_axis_tdata_2;
wire [C_S_AXIS_TKEEP_WIDTH-1:0]		        ctrl_s_axis_tkeep_2;
wire [C_S_AXIS_TUSER_WIDTH-1:0]				ctrl_s_axis_tuser_2;
wire 										ctrl_s_axis_tvalid_2;
wire 										ctrl_s_axis_tlast_2;

reg  [C_S_AXIS_TDATA_WIDTH-1:0]				ctrl_s_axis_tdata_2_r;
reg  [C_S_AXIS_TKEEP_WIDTH-1:0]		        ctrl_s_axis_tkeep_2_r;
reg  [C_S_AXIS_TUSER_WIDTH-1:0]				ctrl_s_axis_tuser_2_r;
reg 										ctrl_s_axis_tvalid_2_r;
reg 										ctrl_s_axis_tlast_2_r;

reg  [C_S_AXIS_TDATA_WIDTH-1:0]             m_axis_tdata2_r;
reg  [C_S_AXIS_TKEEP_WIDTH-1:0]             m_axis_tkeep2_r;
reg   [C_S_AXIS_TUSER_WIDTH-1:0]             m_axis_tuser2_r;
reg                                         m_axis_tvalid2_r;
reg                                         m_axis_tready2_r;
reg                                         m_axis_tlast2_r;

wire [C_S_AXIS_TDATA_WIDTH-1:0]             m_axis_tdata2;
wire [C_S_AXIS_TKEEP_WIDTH-1:0]             m_axis_tkeep2;
wire [C_S_AXIS_TUSER_WIDTH-1:0]             m_axis_tuser2;
wire                                         m_axis_tvalid2;
wire                                         m_axis_tready2;
wire                                         m_axis_tlast2;



reg [63:0] glb_time;
always @(posedge clk) begin
    if(!aresetn) begin
        glb_time <= 0;
    end
    else begin
        glb_time <= glb_time+1;
    end
end


pkt_filter #(
	.C_S_AXIS_TDATA_WIDTH(C_S_AXIS_TDATA_WIDTH ),
	.C_S_AXIS_TUSER_WIDTH(C_S_AXIS_TUSER_WIDTH ),
	.C_S_AXIS_TKEEP_WIDTH(C_S_AXIS_TKEEP_WIDTH )
)pkt_filter
(
	.clk(clk),
	.aresetn(aresetn),

	// input Slave AXI Stream
	.s_axis_tdata (s_axis_tdata ),
	.s_axis_tkeep (s_axis_tkeep ),
	.s_axis_tuser (s_axis_tuser ),
	.s_axis_tvalid(s_axis_tvalid),
	.s_axis_tready(s_axis_tready),
	.s_axis_tlast (s_axis_tlast ),

	// output Master AXI Stream
	.m_axis_tdata (s_axis_tdata_f),
	.m_axis_tkeep (s_axis_tkeep_f),
	.m_axis_tuser (s_axis_tuser_f),
	.m_axis_tvalid(s_axis_tvalid_f),
	.m_axis_tready(s_axis_tready_f),
	.m_axis_tlast (s_axis_tlast_f),

	.ctrl_m_axis_tdata  (ctrl_s_axis_tdata_1 ),
	.ctrl_m_axis_tuser  (ctrl_s_axis_tuser_1 ),
	.ctrl_m_axis_tkeep  (ctrl_s_axis_tkeep_1 ),
	.ctrl_m_axis_tlast  (ctrl_s_axis_tlast_1 ),
	.ctrl_m_axis_tvalid (ctrl_s_axis_tvalid_1)
);

remu_link_emulator_top #(
	.C_S_AXIS_TDATA_WIDTH(C_S_AXIS_TDATA_WIDTH), 
	.C_S_AXIS_TUSER_WIDTH(C_S_AXIS_TUSER_WIDTH),
	.C_S_AXIS_TKEEP_WIDTH(C_S_AXIS_TKEEP_WIDTH),
	.INIT_FILE           (LINK_PARSER_INIT_FILE)
)
remu_link_emulator
(
	.clk				    (clk                   ),
    .aresetn				(aresetn               ),
    //from pkt_filter

	.s_axis_tdata1					(  s_axis_tdata_f    ),

	.s_axis_tkeep1					(  s_axis_tkeep_f ),
	.s_axis_tuser1					(  s_axis_tuser_f    ),
	.s_axis_tvalid1	                (  s_axis_tvalid_f   ),
	.s_axis_tlast1					(  s_axis_tlast_f   ),				     
	.s_axis_tready1					(  s_axis_tready_f   ),

	.s_axis_tdata2                  (m_axis_tdata2_r),
	.s_axis_tkeep2                  (m_axis_tkeep2_r),
	.s_axis_tuser2                  (m_axis_tuser2_r),
	.s_axis_tvalid2                 (m_axis_tvalid2_r),
	.s_axis_tready2                 (m_axis_tready2),
	.s_axis_tlast2                  (m_axis_tlast2_r),

	.ctrl_s_axis_tdata  (ctrl_s_axis_tdata_1_r),
	.ctrl_s_axis_tuser  (ctrl_s_axis_tuser_1_r),
	.ctrl_s_axis_tkeep  (ctrl_s_axis_tkeep_1_r),
	.ctrl_s_axis_tvalid (ctrl_s_axis_tvalid_1_r),
	.ctrl_s_axis_tlast  (ctrl_s_axis_tlast_1_r),

    // to remu switch emulator
	.ctrl_m_axis_tdata  ( ctrl_s_axis_tdata_2),
	.ctrl_m_axis_tuser  ( ctrl_s_axis_tuser_2),
	.ctrl_m_axis_tkeep  ( ctrl_s_axis_tkeep_2),
	.ctrl_m_axis_tlast  ( ctrl_s_axis_tlast_2),
	.ctrl_m_axis_tvalid ( ctrl_s_axis_tvalid_2),

    // output to TM
    .i_tuser_fifo_rd_en     (tuser_fifo_rd_en      ),
    .o_snd_half_fifo_tuser  (snd_half_fifo_tuser   ),
    .o_snd_half_fifo_tkeep  (snd_half_fifo_tkeep   ),
    .o_snd_half_fifo_tlast  (snd_half_fifo_tlast   ),

	.o_pkt_data_valid5      (pkt_data_valid5       ),
	.o_pkt5_data0           (pkt5_data0            ),
	.o_pkt5_data1           (pkt5_data1            ),
	.o_pkt5_data2           (pkt5_data2            ),
	.o_pkt5_data3           (pkt5_data3            ),
	.o_pkt5_data4           (pkt5_data4            ),
	.o_pkt5_data5           (pkt5_data5            ),
	.o_pkt5_data6           (pkt5_data6            ),
	.o_pkt5_data7           (pkt5_data7            ),
	.o_metadata             (metadata              ),
	.o_metadata_vld         (metadata_vld          ),

    .o_seg_fifo_tdata       (seg_fifo_tdata_out    ),
    .o_seg_fifo_tuser       (seg_fifo_tuser_out    ),
    .o_seg_fifo_tkeep       (seg_fifo_tkeep_out    ),
    .o_seg_fifo_tlast       (seg_fifo_tlast_out    ),
    .i_seg_fifo_rd_en       (seg_fifo_rd_en        ),
    .o_seg_fifo_empty       (seg_fifo_empty        )

	);



// TM
tm_top_dq tm_top_beta_uut_s (    


        .global_time(global_time),
        .i_pkt_data_valid5(pkt_data_valid5),
        .i_pkt5_data0(pkt5_data0),
        .i_pkt5_data1(pkt5_data1),
        .i_pkt5_data2(pkt5_data2),
        .i_pkt5_data3(pkt5_data3),
        .i_pkt5_data4(pkt5_data4),
        .i_pkt5_data5(pkt5_data5),
        .i_pkt5_data6(pkt5_data6),
        .i_pkt5_data7(pkt5_data7),
        .i_metadata(metadata),
        .i_metadata_vld(metadata_vld),

        .o_tuser_fifo_rd_en(tuser_fifo_rd_en),
        .i_snd_half_fifo_tuser(snd_half_fifo_tuser),
        .i_snd_half_fifo_tkeep(snd_half_fifo_tkeep),
        .i_snd_half_fifo_tlast(snd_half_fifo_tlast),

        .i_seg_fifo_tdata_out(seg_fifo_tdata_out),
        .i_seg_fifo_tuser_out(seg_fifo_tuser_out),
        .i_seg_fifo_tkeep_out(seg_fifo_tkeep_out),
        .i_seg_fifo_tlast_out(seg_fifo_tlast_out),
        .o_seg_fifo_rd_en(seg_fifo_rd_en),
        .i_seg_fifo_empty(seg_fifo_empty),

        .depar_out_tdata(depar_out_tdata),
        .depar_out_tkeep(depar_out_tkeep),
        .depar_out_tuser(depar_out_tuser),
        .depar_out_tvalid(depar_out_tvalid),
        .depar_out_tlast(depar_out_tlast),
        .depar_out_tready(depar_out_tready_r),

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
        .sys_rst(sys_rst)
    );


remu_switch_emulator_top #(
	.C_S_AXIS_TDATA_WIDTH(C_S_AXIS_TDATA_WIDTH), 
	.C_S_AXIS_TUSER_WIDTH(C_S_AXIS_TUSER_WIDTH),
	.C_S_AXIS_TKEEP_WIDTH(C_S_AXIS_TKEEP_WIDTH)
)
remu_switch_emulator
(
	.clk				    (clk                   ),
    .aresetn				(aresetn               ),

	.s_axis_tdata					( depar_out_tdata_r     ),
	.s_axis_tuser					( depar_out_tuser_r     ),
	.s_axis_tkeep					( depar_out_tkeep_r     ),
	.s_axis_tvalid	                ( depar_out_tvalid_r    ),
	.s_axis_tlast					( depar_out_tlast_r     ),				     
	.s_axis_tready					( depar_out_tready    ),

    // egress
	.m_axis_tdata1 (m_axis_tdata1),
	.m_axis_tkeep1 (m_axis_tkeep1),
	.m_axis_tuser1 (m_axis_tuser1),
	.m_axis_tvalid(m_axis_tvalid1),
	.m_axis_tready(m_axis_tready1),
	.m_axis_tlast (m_axis_tlast1),

    // recirculation
	.m_axis_tdata2 (m_axis_tdata2),
	.m_axis_tkeep2 (m_axis_tkeep2),
	.m_axis_tuser2 (m_axis_tuser2),
	.m_axis_tvalid(m_axis_tvalid2),
	.m_axis_tready(m_axis_tready2_r),
	.m_axis_tlast (m_axis_tlast2),




	.ctrl_s_axis_tdata  ( ctrl_s_axis_tdata_2_r),
	.ctrl_s_axis_tuser  ( ctrl_s_axis_tuser_2_r),
	.ctrl_s_axis_tkeep  ( ctrl_s_axis_tkeep_2_r),
	.ctrl_s_axis_tlast  ( ctrl_s_axis_tlast_2_r),
	.ctrl_s_axis_tvalid (ctrl_s_axis_tvalid_2_r)

	);





always @(posedge clk) begin
	if (~aresetn) begin
	ctrl_s_axis_tdata_1_r <= 0;
	ctrl_s_axis_tkeep_1_r <= 0;
	ctrl_s_axis_tuser_1_r <= 0;
	ctrl_s_axis_tvalid_1_r <= 0;
	ctrl_s_axis_tlast_1_r <= 0;
	
    ctrl_s_axis_tdata_2_r <= 0;
	ctrl_s_axis_tkeep_2_r <= 0;
	ctrl_s_axis_tuser_2_r <= 0;
	ctrl_s_axis_tvalid_2_r <= 0;
	ctrl_s_axis_tlast_2_r <= 0;

	depar_out_tdata_r <= 0;
	depar_out_tkeep_r <= 0;
	depar_out_tuser_r <= 0;
	depar_out_tvalid_r <= 0;
	depar_out_tlast_r <= 0;

	depar_out_tready_r <= 0;

	m_axis_tdata2_r <= 0;
	m_axis_tkeep2_r <= 0;
	m_axis_tuser2_r <= 0;		
	m_axis_tvalid2_r <= 0;
	m_axis_tready2_r <= 0;
	m_axis_tlast2_r <= 0;



	



	end
	else begin
		ctrl_s_axis_tdata_1_r <= ctrl_s_axis_tdata_1;
		ctrl_s_axis_tkeep_1_r <= ctrl_s_axis_tkeep_1;
		ctrl_s_axis_tuser_1_r <= ctrl_s_axis_tuser_1;
		ctrl_s_axis_tvalid_1_r <= ctrl_s_axis_tvalid_1;
		ctrl_s_axis_tlast_1_r <= ctrl_s_axis_tlast_1;

		ctrl_s_axis_tdata_2_r <= ctrl_s_axis_tdata_2;
		ctrl_s_axis_tkeep_2_r <= ctrl_s_axis_tkeep_2;
		ctrl_s_axis_tuser_2_r <= ctrl_s_axis_tuser_2;
		ctrl_s_axis_tvalid_2_r <= ctrl_s_axis_tvalid_2;
		ctrl_s_axis_tlast_2_r <= ctrl_s_axis_tlast_2;
		
		depar_out_tdata_r <= depar_out_tdata;
		depar_out_tkeep_r <= depar_out_tkeep;
		depar_out_tuser_r <= depar_out_tuser;
		depar_out_tvalid_r <= depar_out_tvalid;
		depar_out_tlast_r <= depar_out_tlast;
		depar_out_tready_r <= depar_out_tready;

		m_axis_tdata2_r <= m_axis_tdata2;
		m_axis_tkeep2_r <= m_axis_tkeep2;
		m_axis_tuser2_r <= m_axis_tuser2;
		m_axis_tvalid2_r <= m_axis_tvalid2;
		m_axis_tready2_r <= m_axis_tready2;
		m_axis_tlast2_r <= m_axis_tlast2;

	end

end





endmodule
