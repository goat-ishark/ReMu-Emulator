`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/03/02 15:37:51
// Design Name: 
// Module Name: remu_link_emulator_top
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


module remu_link_emulator_top #(

	parameter C_S_AXIS_TDATA_WIDTH = 512,
	parameter C_S_AXIS_TUSER_WIDTH = 256,
	parameter C_S_AXIS_TKEEP_WIDTH = 64,
	parameter C_VLANID_WIDTH = 12,

	parameter INIT_FILE           = 1
	
)   


(
	input									    clk          ,	
	input									    aresetn      ,	
    //from pkt_filter
	input [C_S_AXIS_TDATA_WIDTH-1:0]		    s_axis_tdata1 ,
	input [C_S_AXIS_TKEEP_WIDTH-1:0]		    s_axis_tkeep1 ,
	input [C_S_AXIS_TUSER_WIDTH-1:0]			s_axis_tuser1 ,
	input										s_axis_tvalid1,
	output										s_axis_tready1,
	input										s_axis_tlast1 ,

    //from recirulator
	input [C_S_AXIS_TDATA_WIDTH-1:0]		    s_axis_tdata2 ,
	input [C_S_AXIS_TKEEP_WIDTH-1:0]		    s_axis_tkeep2 ,
	input [C_S_AXIS_TUSER_WIDTH-1:0]			s_axis_tuser2 ,
	input										s_axis_tvalid2,
	output										s_axis_tready2,
	input										s_axis_tlast2 ,

	input [C_S_AXIS_TDATA_WIDTH-1:0]            ctrl_s_axis_tdata_1,
    input [C_S_AXIS_TUSER_WIDTH-1:0]            ctrl_s_axis_tuser_1,
    input [C_S_AXIS_TKEEP_WIDTH-1:0]            ctrl_s_axis_tkeep_1,
    input                                       ctrl_s_axis_tvalid_1,
    input                                       ctrl_s_axis_tlast_1,
   // output                                      ctrl_s_axis_tready_1,

    output [C_S_AXIS_TDATA_WIDTH-1:0]           ctrl_m_axis_tdata,
    output [C_S_AXIS_TUSER_WIDTH-1:0]           ctrl_m_axis_tuser,
    output [C_S_AXIS_TKEEP_WIDTH-1:0]           ctrl_m_axis_tkeep,
    output                                      ctrl_m_axis_tvalid,
    output                                      ctrl_m_axis_tlast

	output     [C_S_AXIS_TDATA_WIDTH-1:0]		m_axis_tdata ,
	output     [C_S_AXIS_TKEEP_WIDTH-1:0]	    m_axis_tkeep ,
	output     [C_S_AXIS_TUSER_WIDTH-1:0]		m_axis_tuser ,
	output    									m_axis_tvalid,
	input										m_axis_tready,
	output  									m_axis_tlast,

    input                                       i_tuser_fifo_rd_en,
    output [C_S_AXIS_TUSER_WIDTH-1:0]           o_snd_half_fifo_tuser,
    output [C_S_AXIS_TKEEP_WIDTH-1:0]           o_snd_half_fifo_tkeep,
    output                                      o_snd_half_fifo_tlast,

    output                                      o_pkt_data_valid5,
    output [C_S_AXIS_TDATA_WIDTH/2-1:0]         o_pkt5_data0,
    output [C_S_AXIS_TDATA_WIDTH/2-1:0]         o_pkt5_data1,
    output [C_S_AXIS_TDATA_WIDTH/2-1:0]         o_pkt5_data2,
    output [C_S_AXIS_TDATA_WIDTH/2-1:0]         o_pkt5_data3,
    output [C_S_AXIS_TDATA_WIDTH/2-1:0]         o_pkt5_data4,
    output [C_S_AXIS_TDATA_WIDTH/2-1:0]         o_pkt5_data5,
    output [C_S_AXIS_TDATA_WIDTH/2-1:0]         o_pkt5_data6,
    output [C_S_AXIS_TDATA_WIDTH/2-1:0]         o_pkt5_data7,
    output [255:0]                              o_metadata,
    output                                      o_metadata_vld,

    output [C_S_AXIS_TDATA_WIDTH-1:0]           o_seg_fifo_tdata,
    output [C_S_AXIS_TUSER_WIDTH-1:0]           o_seg_fifo_tuser,
    output [C_S_AXIS_TKEEP_WIDTH-1:0]           o_seg_fifo_tkeep,
    output                                      o_seg_fifo_tlast,
    input                                       i_seg_fifo_rd_en,
    output                                      o_seg_fifo_empty,




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

wire [C_S_AXIS_TDATA_WIDTH-1:0]				s_axis_tdata_f;
wire [C_S_AXIS_TKEEP_WIDTH-1:0]		        s_axis_tkeep_f;
wire [C_S_AXIS_TUSER_WIDTH-1:0]				s_axis_tuser_f;
wire										s_axis_tvalid_f;
wire										s_axis_tready_f;
wire										s_axis_tlast_f;

reg [C_S_AXIS_TDATA_WIDTH-1:0]				s_axis_tdata_f_r;
reg [C_S_AXIS_TKEEP_WIDTH-1:0]			    s_axis_tkeep_f_r;
reg [C_S_AXIS_TUSER_WIDTH-1:0]				s_axis_tuser_f_r;
reg											s_axis_tvalid_f_r;
reg											s_axis_tready_f_r;
reg											s_axis_tlast_f_r;




reg [C_S_AXIS_TDATA_WIDTH-1:0] ctrl_s_axis_tdata_1_r,ctrl_s_axis_tdata_2_r,ctrl_s_axis_tdata_3_r,ctrl_s_axis_tdata_4_r,ctrl_s_axis_tdata_5_r, ctrl_s_axis_tdata_6_r;
reg [C_S_AXIS_TUSER_WIDTH-1:0] ctrl_s_axis_tuser_1_r,ctrl_s_axis_tuser_2_r,ctrl_s_axis_tuser_3_r,ctrl_s_axis_tuser_4_r,ctrl_s_axis_tuser_5_r, ctrl_s_axis_tuser_6_r;
reg [C_S_AXIS_TKEEP_WIDTH-1:0] ctrl_s_axis_tkeep_1_r,ctrl_s_axis_tkeep_2_r,ctrl_s_axis_tkeep_3_r,ctrl_s_axis_tkeep_4_r,ctrl_s_axis_tkeep_5_r, ctrl_s_axis_tkeep_6_r;
reg                            ctrl_s_axis_tlast_1_r,ctrl_s_axis_tlast_2_r,ctrl_s_axis_tlast_3_r,ctrl_s_axis_tlast_4_r,ctrl_s_axis_tlast_5_r, ctrl_s_axis_tlast_6_r;
reg                            ctrl_s_axis_tvalid_1_r,ctrl_s_axis_tvalid_2_r,ctrl_s_axis_tvalid_3_r,ctrl_s_axis_tvalid_4_r,ctrl_s_axis_tvalid_5_r, ctrl_s_axis_tvalid_6_r;

wire [C_S_AXIS_TDATA_WIDTH-1:0] ctrl_s_axis_tdata_2,ctrl_s_axis_tdata_3,ctrl_s_axis_tdata_4,ctrl_s_axis_tdata_5,ctrl_s_axis_tdata_6;
wire [C_S_AXIS_TUSER_WIDTH-1:0] ctrl_s_axis_tuser_2,ctrl_s_axis_tuser_3,ctrl_s_axis_tuser_4,ctrl_s_axis_tuser_5,ctrl_s_axis_tuser_6;
wire [C_S_AXIS_TKEEP_WIDTH-1:0] ctrl_s_axis_tkeep_2,ctrl_s_axis_tkeep_3,ctrl_s_axis_tkeep_4,ctrl_s_axis_tkeep_5,ctrl_s_axis_tkeep_6;
wire                            ctrl_s_axis_tlast_2,ctrl_s_axis_tlast_3,ctrl_s_axis_tlast_4,ctrl_s_axis_tlast_5,ctrl_s_axis_tlast_6;
wire                            ctrl_s_axis_tvalid_2,ctrl_s_axis_tvalid_3,ctrl_s_axis_tvalid_4,ctrl_s_axis_tvalid_5,ctrl_s_axis_tvalid_6;


wire                            stg0_phv_in_valid,stg0_phv_out_valid,stg1_phv_out_valid,stg2_phv_out_valid,stg3_phv_out_valid,stg4_phv_out_valid;
wire    [PHV_LEN-1:0]           stg0_phv_in, stg0_phv_out, stg1_phv_out, stg2_phv_out, stg3_phv_out, stg4_phv_out;
wire							stg0_phv_in_end;
reg                             stg0_phv_in_d1,stg0_phv_out_d1,stg1_phv_out_d1,stg2_phv_out_d1,stg3_phv_out_d1,stg4_phv_out_d1;
reg                             stg0_phv_out_valid_d1,stg1_phv_out_valid_d1,stg2_phv_out_valid_d1,stg3_phv_out_valid_d1,stg4_phv_out_valid_d1;
reg                             stg0_phv_in_end_d1;
// pkt fifo wires
wire [C_S_AXIS_TDATA_WIDTH-1:0]		pkt_fifo_tdata_out ;
wire [C_S_AXIS_TUSER_WIDTH-1:0]		pkt_fifo_tuser_out ;
wire [C_S_AXIS_TKEEP_WIDTH-1:0]	    pkt_fifo_tkeep_out ;
wire 								pkt_fifo_tlast_out ;




// output from parser
wire [C_S_AXIS_TDATA_WIDTH-1:0]		parser_m_axis_tdata ;
wire [C_S_AXIS_TUSER_WIDTH-1:0]		parser_m_axis_tuser ;
wire [C_S_AXIS_TKEEP_WIDTH-1:0]	    parser_m_axis_tkeep ;
wire 								parser_m_axis_tlast ;
wire 								parser_m_axis_tvalid;

wire 				pkt_fifo_rd_en;
wire     			pkt_fifo_nearly_full;
wire     			pkt_fifo_empty;

assign s_axis_tready_f = !pkt_fifo_nearly_full;

wire [PHV_LEN-1:0]		phv_fifo_out ;

wire							phv_fifo_rd_en ;
wire							phv_fifo_nearly_full ;
wire							phv_fifo_empty ;
wire                            phv_fifo2_nearly_full;

wire [625:0] high_phv_out ;
wire [625:0] low_phv_out  ;

link_parser_top #(
    .C_S_AXIS_TDATA_WIDTH(C_S_AXIS_TDATA_WIDTH), 
	.C_S_AXIS_TUSER_WIDTH(C_S_AXIS_TUSER_WIDTH),
	.C_S_AXIS_TKEEP_WIDTH(C_S_AXIS_TKEEP_WIDTH),
	.PHV_LEN             (PHV_LEN             ),
	.PKTS_LEN            (PKTS_LEN            ),
	.PARSER_MOD_ID       (PARSER_MOD_ID       ),
	.C_NUM_SEGS          (C_NUM_SEGS          ),
	.C_VLANID_WIDTH      (C_VLANID_WIDTH      ),
	.PARSER_NUM          (PARSER_NUM          ),
	.PARSER_ACT_WIDTH    (PARSER_ACT_WIDTH    ),
	.PKT_BYTE_LENGTH_W   (PKT_BYTE_LENGTH_W   ),
	.INIT_FILE           (INIT_FILE )
)
phv_parser
(
	.axis_clk		                (clk                   ),
	.aresetn		                (aresetn               ),
	// input slvae axi stream     
	.s_axis_tdata					(s_axis_tdata_f_r      ),
	.s_axis_tuser					(s_axis_tuser_f_r      ),
	.s_axis_tkeep					(s_axis_tkeep_f_r      ),
	.s_axis_tvalid	                (s_axis_tvalid_f_r     ),
	.o_phv_valid					(stg0_phv_in_valid     ),
	.o_phv_data						(stg0_phv_in           ),
	.o_phv_end                      (stg0_phv_in_end       ),
	.i_stg_ready					(stg0_ready),     
	//    

	// hit the parser rule 
	.m_axis_tdata_0					(parser_m_axis_tdata   ),
	.m_axis_tuser_0					(parser_m_axis_tuser   ),
	.m_axis_tkeep_0					(parser_m_axis_tkeep   ),
	.m_axis_tlast_0					(parser_m_axis_tlast   ),
	.m_axis_tvalid_0				(parser_m_axis_tvalid  ),
	.m_axis_tready_0				(~pkt_fifo_nearly_full ),
	// control path
    .ctrl_s_axis_tdata				(ctrl_s_axis_tdata_1_r ),
	.ctrl_s_axis_tuser				(ctrl_s_axis_tuser_1_r ),
	.ctrl_s_axis_tkeep				(ctrl_s_axis_tkeep_1_r ),
	.ctrl_s_axis_tlast				(ctrl_s_axis_tlast_1_r ),
	.ctrl_s_axis_tvalid				(ctrl_s_axis_tvalid_1_r),

    .ctrl_m_axis_tdata				(ctrl_s_axis_tdata_2   ),
	.ctrl_m_axis_tuser				(ctrl_s_axis_tuser_2   ),
	.ctrl_m_axis_tkeep				(ctrl_s_axis_tkeep_2   ),
	.ctrl_m_axis_tlast				(ctrl_s_axis_tlast_2   ),
	.ctrl_m_axis_tvalid				(ctrl_s_axis_tvalid_2  )
);






stage_GIT #( 
	.C_S_AXIS_TDATA_WIDTH   (C_S_AXIS_TDATA_WIDTH  ),
	.C_S_AXIS_TUSER_WIDTH   (C_S_AXIS_TUSER_WIDTH  ),
	.C_S_AXIS_TKEEP_WIDTH   (C_S_AXIS_TKEEP_WIDTH  ),
	.STAGE_ID               (0                     ),
	.PHV_LEN                (PHV_LEN               ),
	.KEY_LEN                (GIT_KEY_LEN           ),
	.KEY_OFF                (GIT_KEY_OFF	      ),
	.LKE_RAM_LEN            (GIT_RAM_LEN		   ),

	.C_VLANID_WIDTH         (C_VLANID_WIDTH        )
)
stage_GIT 
(
	.axis_clk				(clk                   ),
    .aresetn				(aresetn               ),
 
	// input 
    .phv_in					(stg0_phv_in_d1        ),
    .phv_in_valid			(stg0_phv_in_end_d1    ),


	// output 
    .phv_out				(stg0_phv_out          ),
    .phv_out_valid			(stg0_phv_out_valid    ),
	// back-pressure signals    
	.stage_ready_out		(stg0_ready            ),
	.stage_ready_in			(stg1_ready            ),
	// control path
    .c_s_axis_tdata         (ctrl_s_axis_tdata_2_r ),
	.c_s_axis_tuser         (ctrl_s_axis_tuser_2_r ),
	.c_s_axis_tkeep         (ctrl_s_axis_tkeep_2_r ),
	.c_s_axis_tlast         (ctrl_s_axis_tlast_2_r ),
	.c_s_axis_tvalid        (ctrl_s_axis_tvalid_2_r),

    .c_m_axis_tdata         (ctrl_s_axis_tdata_3   ),
	.c_m_axis_tuser         (ctrl_s_axis_tuser_3   ),
	.c_m_axis_tkeep         (ctrl_s_axis_tkeep_3   ),
	.c_m_axis_tlast         (ctrl_s_axis_tlast_3   ),
	.c_m_axis_tvalid        (ctrl_s_axis_tvalid_3  )
);


stage_LMT #(
	.C_S_AXIS_TDATA_WIDTH   (C_S_AXIS_TDATA_WIDTH  ),
	.C_S_AXIS_TUSER_WIDTH   (C_S_AXIS_TUSER_WIDTH  ),
	.C_S_AXIS_TKEEP_WIDTH   (C_S_AXIS_TKEEP_WIDTH  ),
	.STAGE_ID               (1                     ),
	.PHV_LEN                (PHV_LEN               ),
	.KEY_LEN                (LMT_KEY_LEN           ),
	.KEY_OFF                (LMT_KEY_OFF	      ),
	.LKE_RAM_LEN            (LMT_RAM_LEN		   ),
	.C_VLANID_WIDTH         (					   )
)
stage_LMT
(
	.axis_clk				(clk                   ),
    .aresetn				(aresetn               ),
 
	// input 
    .phv_in					(stg0_phv_out_d1      ),
    .phv_in_valid			(stg0_phv_out_valid_d1),
	// output 
    .phv_out				(stg1_phv_out          ),
    .phv_out_valid			(stg1_phv_out_valid    ),
	// back-pressure signals    
	.stage_ready_out		(stg1_ready            ),
	.stage_ready_in			(stg2_ready            ),
	// control path
    .c_s_axis_tdata         (ctrl_s_axis_tdata_3_r ),
	.c_s_axis_tuser         (ctrl_s_axis_tuser_3_r ),
	.c_s_axis_tkeep         (ctrl_s_axis_tkeep_3_r ),
	.c_s_axis_tlast         (ctrl_s_axis_tlast_3_r ),
	.c_s_axis_tvalid        (ctrl_s_axis_tvalid_3_r),

    .c_m_axis_tdata         (ctrl_s_axis_tdata_4   ),
	.c_m_axis_tuser         (ctrl_s_axis_tuser_4   ),
	.c_m_axis_tkeep         (ctrl_s_axis_tkeep_4  ),
	.c_m_axis_tlast         (ctrl_s_axis_tlast_4   ),
	.c_m_axis_tvalid        (ctrl_s_axis_tvalid_4  )
);

LPU_bw #(
	.C_S_AXIS_TDATA_WIDTH   (C_S_AXIS_TDATA_WIDTH  ),
	.C_S_AXIS_TUSER_WIDTH   (C_S_AXIS_TUSER_WIDTH  ),
	.C_S_AXIS_TKEEP_WIDTH   (C_S_AXIS_TKEEP_WIDTH  ),
	.STAGE_ID               (2                    ),
	.PHV_LEN                (PHV_LEN              ),
	.KEY_LEN                (BW_KEY_LEN                   ),
	.ACT_LEN                (BW_ACT_LEN                   )
)
LPU_bw
(
	.axis_clk				(clk                  ),
    .aresetn				(aresetn              ),

	// input
    .phv_in					(stg1_phv_out_d1      ),
    .phv_in_valid			(stg1_phv_out_valid_d1),

    .phv_out				(stg2_phv_out         ),
    .phv_out_valid			(stg2_phv_out_valid   ),
	// back-pressure signals
	.stage_ready_out		(stg2_ready           ),
	.stage_ready_in			(stg3_ready           ),

	// control path
    .c_s_axis_tdata        (ctrl_s_axis_tdata_4_r ),
	.c_s_axis_tuser        (ctrl_s_axis_tuser_4_r ),
	.c_s_axis_tkeep        (ctrl_s_axis_tkeep_4_r ),
	.c_s_axis_tlast        (ctrl_s_axis_tlast_4_r ),
	.c_s_axis_tvalid       (ctrl_s_axis_tvalid_4_r),

    .c_m_axis_tdata        (ctrl_s_axis_tdata_5   ),
	.c_m_axis_tuser        (ctrl_s_axis_tuser_5   ),
	.c_m_axis_tkeep        (ctrl_s_axis_tkeep_5   ),
	.c_m_axis_tlast        (ctrl_s_axis_tlast_5   ),
	.c_m_axis_tvalid       (ctrl_s_axis_tvalid_5  )
);

LPU_delay #(
	.C_S_AXIS_TDATA_WIDTH   (C_S_AXIS_TDATA_WIDTH  ),
	.C_S_AXIS_TUSER_WIDTH   (C_S_AXIS_TUSER_WIDTH  ),
	.C_S_AXIS_TKEEP_WIDTH   (C_S_AXIS_TKEEP_WIDTH  ),
	.STAGE_ID               (3                     ),
	.PHV_LEN                (PHV_LEN               ),
	.KEY_LEN                (DELAY_KEY_LEN                    ),
	.ACT_LEN                (DELAY_ACT_LEN                    )
)
LPU_delay
(
	.axis_clk				(clk                   ),
    .aresetn				(aresetn               ),
    
	// input       
    .phv_in					(stg2_phv_out_d1       ),
    .phv_in_valid			(stg2_phv_out_valid_d1 ),

    .phv_out				(stg3_phv_out          ),
    .phv_out_valid			(stg3_phv_out_valid    ),
	// back-pressure signals 
	.stage_ready_out		(stg3_ready            ),
	.stage_ready_in			(stg4_ready                 ),

	// control path
    .c_s_axis_tdata         (ctrl_s_axis_tdata_5_r ),
	.c_s_axis_tuser         (ctrl_s_axis_tuser_5_r ),
	.c_s_axis_tkeep         (ctrl_s_axis_tkeep_5_r ),
	.c_s_axis_tlast         (ctrl_s_axis_tlast_5_r ),
	.c_s_axis_tvalid        (ctrl_s_axis_tvalid_5_r),

    .c_m_axis_tdata         (ctrl_s_axis_tdata_6   ),
	.c_m_axis_tuser         (ctrl_s_axis_tuser_6   ),
	.c_m_axis_tkeep         (ctrl_s_axis_tkeep_6   ),
	.c_m_axis_tlast         (ctrl_s_axis_tlast_6   ),
	.c_m_axis_tvalid        (ctrl_s_axis_tvalid_6  )
);



LPU_loss #(
	.C_S_AXIS_TDATA_WIDTH   (C_S_AXIS_TDATA_WIDTH  ),
	.C_S_AXIS_TUSER_WIDTH   (C_S_AXIS_TUSER_WIDTH  ),
	.C_S_AXIS_TKEEP_WIDTH   (C_S_AXIS_TKEEP_WIDTH  ),
	.STAGE_ID               (4                     ),
	.PHV_LEN                (PHV_LEN               ),
	.KEY_LEN                (LOSS_KEY_LEN                   ),//link_id
	.ACT_LEN                (LOSS_ACT_LEN                   )//delay 16b
)
LPU_loss
(
	.axis_clk				(clk                   ),
    .aresetn				(aresetn               ),
    
	// input       
    .phv_in					(stg3_phv_out_d1       ),
    .phv_in_valid			(stg3_phv_out_valid_d1 ),

    .phv_out				(stg4_phv_out          ),
    .phv_out_valid			(stg4_phv_out_valid    ),
	// back-pressure signals 
	.stage_ready_out		(stg4_ready            ),
	.stage_ready_in			( !phv_fifo_nearly_full), // from PHV fifo to deparser

	// control path
    .c_s_axis_tdata         (ctrl_s_axis_tdata_6_r ),
	.c_s_axis_tuser         (ctrl_s_axis_tuser_6_r ),
	.c_s_axis_tkeep         (ctrl_s_axis_tkeep_6_r ),
	.c_s_axis_tlast         (ctrl_s_axis_tlast_6_r ),
	.c_s_axis_tvalid        (ctrl_s_axis_tvalid_6_r),

    .c_m_axis_tdata         (ctrl_s_axis_tdata_7   ),
	.c_m_axis_tuser         (ctrl_s_axis_tuser_7   ),
	.c_m_axis_tkeep         (ctrl_s_axis_tkeep_7   ),
	.c_m_axis_tlast         (ctrl_s_axis_tlast_7   ),
	.c_m_axis_tvalid        (ctrl_s_axis_tvalid_7  )
);



assign ctrl_m_axis_tdata = ctrl_s_axis_tdata_7;
assign ctrl_m_axis_tuser = ctrl_s_axis_tuser_7;
assign ctrl_m_axis_tkeep = ctrl_s_axis_tkeep_7;
assign ctrl_m_axis_tlast = ctrl_s_axis_tlast_7;
assign ctrl_m_axis_tvalid = ctrl_s_axis_tvalid_7;

fallthrough_small_fifo #(
	.WIDTH(C_S_AXIS_TDATA_WIDTH + C_S_AXIS_TUSER_WIDTH + C_S_AXIS_TKEEP_WIDTH + 1),
	.MAX_DEPTH_BITS(8)
)
parser_hit_fifo
(
	.wr_en									(parser_m_axis_tvalid   ),
	.din									(  {parser_m_axis_tdata,
												parser_m_axis_tuser,
												parser_m_axis_tkeep,
												parser_m_axis_tlast}),
	.rd_en									(pkt_fifo_rd_en         ),
	.dout									(  {pkt_fifo_tdata_out, 
												pkt_fifo_tuser_out, 
												pkt_fifo_tkeep_out, 
												pkt_fifo_tlast_out} ),
	.full									(                       ),
	.prog_full								(                       ),
	.nearly_full							(pkt_fifo_nearly_full   ),
	.empty									(pkt_fifo_empty         ),
	.reset									(~aresetn               ),
	.clk									(clk                    )
);

fallthrough_small_fifo #(
	.WIDTH          (626                 ),
	.MAX_DEPTH_BITS (6                   )
)
phv_fifo_1
(
	.din			(stg4_phv_out[625:0] ),
	.wr_en			(stg4_phv_out_valid  ),
	.rd_en			(phv_fifo_rd_en      ),
	.dout			(low_phv_out         ),
  
	.full			(                    ),
	.prog_full		(                    ),
	.nearly_full	(phv_fifo_nearly_full),
	.empty			(phv_fifo_empty      ),
	.reset			(~aresetn            ),
	.clk			(clk                 )
);

fallthrough_small_fifo #(
	.WIDTH          (626       ),
	.MAX_DEPTH_BITS (6         )
)
phv_fifo_2
(
	.din			(stg4_phv_out[1251:626]),
	.wr_en			(stg4_phv_out_valid    ),
	.rd_en			(phv_fifo_rd_en        ),
	.dout			(high_phv_out          ),
 
	.full			(                      ),
	.prog_full		(                      ),
	.nearly_full	( phv_fifo2_nearly_full       ), 
	.empty			(                      ),
	.reset			(~aresetn              ),
	.clk			(clk                   )
);

always @(posedge clk) begin
	if (~aresetn) begin
		s_axis_tdata_f_r <= 0;
		s_axis_tuser_f_r <= 0;
		s_axis_tkeep_f_r <= 0;
		s_axis_tlast_f_r <= 0;
		s_axis_tvalid_f_r <= 0;
	end
	else begin
		s_axis_tdata_f_r <= s_axis_tdata1;
		s_axis_tuser_f_r <= s_axis_tuser1;
		s_axis_tkeep_f_r <= s_axis_tkeep1;
		s_axis_tlast_f_r <= s_axis_tlast1;
		s_axis_tvalid_f_r <= s_axis_tvalid1;
	end
end


wire         phv_fifo_out_valid;

assign phv_fifo_out = {high_phv_out, low_phv_out};
assign phv_fifo_out_valid = stg4_phv_out_valid   ;



wire [C_S_AXIS_TDATA_WIDTH-1:0]			depar_out_tdata ;
wire [C_S_AXIS_TKEEP_WIDTH-1:0]	        depar_out_tkeep ;
wire [C_S_AXIS_TUSER_WIDTH-1:0]			depar_out_tuser ;
wire									depar_out_tvalid;
wire 									depar_out_tready;
wire 									depar_out_tlast ;

assign m_axis_tdata   =  depar_out_tdata       ;
assign m_axis_tkeep   =  depar_out_tkeep       ;
assign m_axis_tuser   =  depar_out_tuser       ;
assign m_axis_tvalid  =  depar_out_tvalid      ;
assign m_axis_tlast   =  depar_out_tlast       ;

wire                                   w_tuser_fifo_rd_en   ;
wire  [C_S_AXIS_TUSER_WIDTH-1:0]       w_snd_half_fifo_tuser;
wire  [C_S_AXIS_TKEEP_WIDTH-1:0]       w_snd_half_fifo_tkeep;
wire                                   w_snd_half_fifo_tlast; 
 
wire [C_S_AXIS_TDATA_WIDTH-1:0 ]	   w_seg_fifo_tdata_out   ;
wire [C_S_AXIS_TUSER_WIDTH-1:0 ]	   w_seg_fifo_tuser_out   ;
wire [C_S_AXIS_TKEEP_WIDTH-1:0 ]       w_seg_fifo_tkeep_out   ;
wire							       w_seg_fifo_tlast_out   ;
wire                              	   w_seg_fifo_rd_en       ;
wire                              	   w_seg_fifo_empty       ;

wire                                   o_reg_end            ;


deparser_top  #(
    .C_S_AXIS_TDATA_WIDTH    (C_S_AXIS_TDATA_WIDTH  ),
    .C_S_AXIS_TUSER_WIDTH    (C_S_AXIS_TUSER_WIDTH  ),
	.C_S_AXIS_TKEEP_WIDTH    (C_S_AXIS_TKEEP_WIDTH  ),
    .C_PKT_VEC_WIDTH         (PHV_LEN               ),
    .DEPARSER_MOD_ID         (5                     ),
    .C_VLANID_WIDTH          (12                    )
) deparser_top(   
    .axis_clk                (clk                   ),
    .aresetn                 (aresetn               ),
   
    .pkt_fifo_tdata          (pkt_fifo_tdata_out    ),
    .pkt_fifo_tkeep          (pkt_fifo_tkeep_out    ),
    .pkt_fifo_tuser          (pkt_fifo_tuser_out    ),
    .pkt_fifo_tlast          (pkt_fifo_tlast_out    ),
    .pkt_fifo_empty          (pkt_fifo_empty        ),
    .pkt_fifo_rd_en          (pkt_fifo_rd_en        ),
   
	.phv_fifo_out            (phv_fifo_out          ),
    .phv_fifo_empty          (phv_fifo_empty        ),
    .phv_fifo_rd_en          (phv_fifo_rd_en        ),
	.phv_fifo_in_valid       (phv_fifo_out_valid    ),

	.i_tuser_fifo_rd_en      (w_tuser_fifo_rd_en    ),
	.i_tuser_fifo_rd_en      (i_tuser_fifo_rd_en    ),
  
	.snd_half_fifo_tuser_out (w_snd_half_fifo_tuser ),
	.snd_half_fifo_tkeep_out (w_snd_half_fifo_tkeep ),
	.snd_half_fifo_tlast_out (w_snd_half_fifo_tlast ),
	.snd_half_fifo_tuser_out (o_snd_half_fifo_tuser ),
	.snd_half_fifo_tkeep_out (o_snd_half_fifo_tkeep ),
	.snd_half_fifo_tlast_out (o_snd_half_fifo_tlast ),

	.o_reg_end               (o_reg_end             ),
	.o_pkt_data_valid5       (w_pkt_data_valid5     ),
	.o_pkt5_data0            (w_pkt5_data0          ),   
	.o_pkt5_data1            (w_pkt5_data1          ),   
	.o_pkt5_data2            (w_pkt5_data2          ),   
	.o_pkt5_data3            (w_pkt5_data3          ),   
	.o_pkt5_data4            (w_pkt5_data4          ),   
	.o_pkt5_data5            (w_pkt5_data5          ),   
	.o_pkt5_data6            (w_pkt5_data6          ),   
	.o_pkt5_data7            (w_pkt5_data7          ), 
	.o_metadata              (w_metadata            ),
	.o_metadata_vld          (w_metadata_vld        ),


	.seg_fifo_tdata_out      (w_seg_fifo_tdata_out  ),
	.seg_fifo_tuser_out      (w_seg_fifo_tuser_out  ),
	.seg_fifo_tkeep_out      (w_seg_fifo_tkeep_out  ),
	.seg_fifo_tlast_out      (w_seg_fifo_tlast_out  ),
	.seg_fifo_rd_en          (w_seg_fifo_rd_en      ),
	.seg_fifo_empty          (w_seg_fifo_empty      ),

   
    .ctrl_s_axis_tdata       (ctrl_s_axis_tdata_2_r ),
    .ctrl_s_axis_tuser       (ctrl_s_axis_tuser_2_r ),
    .ctrl_s_axis_tkeep       (ctrl_s_axis_tkeep_2_r ),
    .ctrl_s_axis_tvalid      (ctrl_s_axis_tvalid_2_r),
    .ctrl_s_axis_tlast       (ctrl_s_axis_tlast_2_r )


);

always @(posedge clk) begin
	if (~aresetn) begin
		ctrl_s_axis_tdata_1_r <= 0;
		ctrl_s_axis_tuser_1_r <= 0;
		ctrl_s_axis_tkeep_1_r <= 0;
		ctrl_s_axis_tlast_1_r <= 0;
		ctrl_s_axis_tvalid_1_r <= 0;

		ctrl_s_axis_tdata_2_r <= 0;
		ctrl_s_axis_tuser_2_r <= 0;
		ctrl_s_axis_tkeep_2_r <= 0;
		ctrl_s_axis_tlast_2_r <= 0;
		ctrl_s_axis_tvalid_2_r <= 0;

		ctrl_s_axis_tdata_3_r <= 0;
		ctrl_s_axis_tuser_3_r <= 0;
		ctrl_s_axis_tkeep_3_r <= 0;
		ctrl_s_axis_tlast_3_r <= 0;
		ctrl_s_axis_tvalid_3_r <= 0;

		ctrl_s_axis_tdata_4_r <= 0;
		ctrl_s_axis_tuser_4_r <= 0;
		ctrl_s_axis_tkeep_4_r <= 0;
		ctrl_s_axis_tlast_4_r <= 0;
		ctrl_s_axis_tvalid_4_r <= 0;

		ctrl_s_axis_tdata_5_r <= 0;
		ctrl_s_axis_tuser_5_r <= 0;
		ctrl_s_axis_tkeep_5_r <= 0;
		ctrl_s_axis_tlast_5_r <= 0;
		ctrl_s_axis_tvalid_5_r <= 0;

		ctrl_s_axis_tdata_6_r <= 0;
		ctrl_s_axis_tuser_6_r <= 0;
		ctrl_s_axis_tkeep_6_r <= 0;
		ctrl_s_axis_tlast_6_r <= 0;
		ctrl_s_axis_tvalid_6_r <= 0;

	end
	else begin
		ctrl_s_axis_tdata_1_r <= ctrl_s_axis_tdata_1;
		ctrl_s_axis_tuser_1_r <= ctrl_s_axis_tuser_1;
		ctrl_s_axis_tkeep_1_r <= ctrl_s_axis_tkeep_1;
		ctrl_s_axis_tlast_1_r <= ctrl_s_axis_tlast_1;
		ctrl_s_axis_tvalid_1_r <= ctrl_s_axis_tvalid_1;

		ctrl_s_axis_tdata_2_r <= ctrl_s_axis_tdata_2;
		ctrl_s_axis_tuser_2_r <= ctrl_s_axis_tuser_2;
		ctrl_s_axis_tkeep_2_r <= ctrl_s_axis_tkeep_2;
		ctrl_s_axis_tlast_2_r <= ctrl_s_axis_tlast_2;
		ctrl_s_axis_tvalid_2_r <= ctrl_s_axis_tvalid_2;

		ctrl_s_axis_tdata_3_r <= ctrl_s_axis_tdata_3;
		ctrl_s_axis_tuser_3_r <= ctrl_s_axis_tuser_3;
		ctrl_s_axis_tkeep_3_r <= ctrl_s_axis_tkeep_3;
		ctrl_s_axis_tlast_3_r <= ctrl_s_axis_tlast_3;
		ctrl_s_axis_tvalid_3_r <= ctrl_s_axis_tvalid_3;

		ctrl_s_axis_tdata_4_r <= ctrl_s_axis_tdata_4;
		ctrl_s_axis_tuser_4_r <= ctrl_s_axis_tuser_4;
		ctrl_s_axis_tkeep_4_r <= ctrl_s_axis_tkeep_4;
		ctrl_s_axis_tlast_4_r <= ctrl_s_axis_tlast_4;
		ctrl_s_axis_tvalid_4_r <= ctrl_s_axis_tvalid_4;

		ctrl_s_axis_tdata_5_r <= ctrl_s_axis_tdata_5;
		ctrl_s_axis_tuser_5_r <= ctrl_s_axis_tuser_5;
		ctrl_s_axis_tkeep_5_r <= ctrl_s_axis_tkeep_5;
		ctrl_s_axis_tlast_5_r <= ctrl_s_axis_tlast_5;
		ctrl_s_axis_tvalid_5_r <= ctrl_s_axis_tvalid_5;

		ctrl_s_axis_tdata_6_r <= ctrl_s_axis_tdata_6;
		ctrl_s_axis_tuser_6_r <= ctrl_s_axis_tuser_6;
		ctrl_s_axis_tkeep_6_r <= ctrl_s_axis_tkeep_6;
		ctrl_s_axis_tlast_6_r <= ctrl_s_axis_tlast_6;
		ctrl_s_axis_tvalid_6_r <= ctrl_s_axis_tvalid_6;

	end
end

always @(posedge clk) begin
	if (~aresetn) begin
		stg0_phv_in_end_d1    <= 0;

		stg0_phv_out_valid_d1 <= 0;
		stg1_phv_out_valid_d1 <= 0;
		stg2_phv_out_valid_d1 <= 0;
		stg3_phv_out_valid_d1 <= 0;
		stg4_phv_out_valid_d1   <= 0;

		stg0_phv_in_d1  <= 0;
		stg0_phv_out_d1 <= 0;
		stg1_phv_out_d1 <= 0;
		stg2_phv_out_d1 <= 0;
		stg3_phv_out_d1 <= 0;
		stg4_phv_out_d1 <= 0;


	end
	else begin
        stg0_phv_in_end_d1    <= stg0_phv_in_end;
		stg0_phv_out_valid_d1 <= stg0_phv_out_valid;
		stg1_phv_out_valid_d1 <= stg1_phv_out_valid;
		stg2_phv_out_valid_d1 <= stg2_phv_out_valid;
		stg3_phv_out_valid_d1 <= stg3_phv_out_valid;
		stg4_phv_out_valid_d1 <= stg4_phv_out_valid;

		stg0_phv_in_d1  <= stg0_phv_in;
		stg0_phv_out_d1 <= stg0_phv_out;
		stg1_phv_out_d1 <= stg1_phv_out;
		stg2_phv_out_d1 <= stg2_phv_out;
		stg3_phv_out_d1 <= stg3_phv_out;	
		stg4_phv_out_d1 <= stg4_phv_out;


	end
end




endmodule
