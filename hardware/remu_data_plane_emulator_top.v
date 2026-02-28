`timescale 1ns / 1ps

   +------------+     +--------+     +-----+     +-----+     +------+     +----------+
 * | pkt_filter |---->| parser |---->| GIT |---->| LMT |---->| LPUs |---->| deparser |
 * +------------+  ^  +--------+     +-----+     +-----+     +------+     +----------+
				 * |                                                             |
				 * |                                                             v
				 * |                                                          +----+
				 * |                                                          | TM |
				 * |                                                          +----+
				 * |                                                             |
 * +----------+    |+----------+     +--------+     +----+     +----+     +-----v-+       
 * | Egress/  |<--| recirculator |<----|deparser|<----| CT |<----| ST |<----| parser |
 * ||---------+     +----------+     +----------+   +----+     +----+     +--------+  

module data_plane_emulator_top #(

	parameter C_S_AXIS_TDATA_WIDTH = 512,
	parameter C_S_AXIS_TUSER_WIDTH = 256,
	parameter C_S_AXIS_TKEEP_WIDTH = 64,
	parameter C_VLANID_WIDTH = 12,
	parameter INIT_FILE             = 1 
	
)
(
	input									    clk          ,		// axis clk
	input									    aresetn      ,	

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
	output  									m_axis_tlast
	
);


localparam PHV_LEN = (8+4+2)*8*8+100+256;//1252 bits
localparam PARSER_MOD_ID = 3'd1;
localparam C_NUM_SEGS = 4;
localparam PKTS_LEN = 2048;
localparam PARSER_NUM = 24;
localparam PARSER_ACT_WIDTH = 16;
localparam DEPARSER_MOD_ID  = 3'd5;
localparam PKT_BYTE_LENGTH_W     = 16;
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


reg [PHV_LEN-1:0]					stg0_phv_in_d1;
reg [PHV_LEN-1:0]					stg0_phv_out_d1;
reg [PHV_LEN-1:0]					stg1_phv_out_d1;
reg [PHV_LEN-1:0]					stg2_phv_out_d1;

reg									stg0_phv_in_valid_d1;
reg									stg0_phv_out_valid_d1;
reg									stg1_phv_out_valid_d1;
reg									stg2_phv_out_valid_d1;

reg									stg0_phv_in_end_d1;
// back pressure signals
wire 								s_axis_tready_p;
wire 								stg0_ready;
wire 								stg1_ready;
wire 								stg2_ready;
wire 								stg3_ready;

//NOTE: to filter out packets other than UDP/IP.
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

wire [C_S_AXIS_TDATA_WIDTH-1:0]				ctrl_s_axis_tdata_3;
wire [C_S_AXIS_TKEEP_WIDTH-1:0]		        ctrl_s_axis_tkeep_3;
wire [C_S_AXIS_TUSER_WIDTH-1:0]				ctrl_s_axis_tuser_3;
wire 										ctrl_s_axis_tvalid_3;
wire 										ctrl_s_axis_tlast_3;

reg  [C_S_AXIS_TDATA_WIDTH-1:0]				ctrl_s_axis_tdata_3_r;
reg  [C_S_AXIS_TKEEP_WIDTH-1:0]		        ctrl_s_axis_tkeep_3_r;
reg  [C_S_AXIS_TUSER_WIDTH-1:0]				ctrl_s_axis_tuser_3_r;
reg  										ctrl_s_axis_tvalid_3_r;
reg  										ctrl_s_axis_tlast_3_r;

wire [C_S_AXIS_TDATA_WIDTH-1:0]				ctrl_s_axis_tdata_4;
wire [C_S_AXIS_TKEEP_WIDTH-1:0]		        ctrl_s_axis_tkeep_4;
wire [C_S_AXIS_TUSER_WIDTH-1:0]				ctrl_s_axis_tuser_4;
wire 										ctrl_s_axis_tvalid_4;
wire 										ctrl_s_axis_tlast_4;

reg  [C_S_AXIS_TDATA_WIDTH-1:0]				ctrl_s_axis_tdata_4_r;
reg  [C_S_AXIS_TKEEP_WIDTH-1:0]		        ctrl_s_axis_tkeep_4_r;
reg  [C_S_AXIS_TUSER_WIDTH-1:0]				ctrl_s_axis_tuser_4_r;
reg 										ctrl_s_axis_tvalid_4_r;
reg 										ctrl_s_axis_tlast_4_r;

wire [C_S_AXIS_TDATA_WIDTH-1:0]				ctrl_s_axis_tdata_5;
wire [C_S_AXIS_TKEEP_WIDTH-1:0]		        ctrl_s_axis_tkeep_5;
wire [C_S_AXIS_TUSER_WIDTH-1:0]				ctrl_s_axis_tuser_5;
wire 										ctrl_s_axis_tvalid_5;
wire 										ctrl_s_axis_tlast_5;

reg  [C_S_AXIS_TDATA_WIDTH-1:0]				ctrl_s_axis_tdata_5_r;
reg  [C_S_AXIS_TKEEP_WIDTH-1:0]		        ctrl_s_axis_tkeep_5_r;
reg  [C_S_AXIS_TUSER_WIDTH-1:0]				ctrl_s_axis_tuser_5_r;
reg 										ctrl_s_axis_tvalid_5_r;
reg 										ctrl_s_axis_tlast_5_r;

reg [63:0] glb_time;
always @(posedge clk) begin
    if(!aresetn) begin
        glb_time <= 0;
    end
    else begin
        glb_time <= glb_time+1;
    end
end
reg [63:0] in_time;
reg [63:0] out_time;
// reg [63:0] real_delay;
// reg [63:0] real_delay_nxt         ;
reg [15:0] dbg_axi_s_tlast_i;
reg [15:0] dbg_axi_m_tlast_o;
reg r_s_axis_tlast;
reg r_m_axis_tlast;
reg write_delay_enable;
// reg rd_en_in_time;
// reg rd_en_out_time;
reg [3:0] s_delay_id;
reg [3:0] m_delay_id;


always @(posedge clk) begin
	if(!aresetn)begin
		dbg_axi_s_tlast_i <=0;
		in_time <= 0;
		r_s_axis_tlast <= 0;
		s_delay_id <= 0;
	end
	else if(s_axis_tlast)begin
		dbg_axi_s_tlast_i <= dbg_axi_s_tlast_i+1;
		in_time <= glb_time;
		r_s_axis_tlast <= 1;
		s_delay_id <= s_axis_tdata[3:0];
	end
	else begin
		dbg_axi_s_tlast_i <= dbg_axi_s_tlast_i;
		in_time <= in_time;
		r_s_axis_tlast <= 0;
		s_delay_id <= s_delay_id;
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
	.m_axis_tready(s_axis_tready_f && s_axis_tready_p),
	.m_axis_tlast (s_axis_tlast_f),

	.ctrl_m_axis_tdata  (ctrl_s_axis_tdata_1 ),
	.ctrl_m_axis_tuser  (ctrl_s_axis_tuser_1 ),
	.ctrl_m_axis_tkeep  (ctrl_s_axis_tkeep_1 ),
	.ctrl_m_axis_tlast  (ctrl_s_axis_tlast_1 ),
	.ctrl_m_axis_tvalid (ctrl_s_axis_tvalid_1)
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
		s_axis_tdata_f_r <= s_axis_tdata_f;
		s_axis_tuser_f_r <= s_axis_tuser_f;
		s_axis_tkeep_f_r <= s_axis_tkeep_f;
		s_axis_tlast_f_r <= s_axis_tlast_f;
		s_axis_tvalid_f_r <= s_axis_tvalid_f;
	end
end

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

wire [625:0] high_phv_out ;
wire [625:0] low_phv_out  ;
wire         phv_fifo_out_valid;

assign phv_fifo_out = {high_phv_out, low_phv_out};
assign phv_fifo_out_valid = stg2_phv_out_valid   ;

//经过过滤器的报文进入parser模块
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
	.INIT_FILE           (INIT_FILE           )
)
phv_parser
(
	.axis_clk		                (clk                   ),
	.aresetn		                (aresetn               ),
	// input slvae axi stream     
	.s_axis_tdata					(s_axis_tdata_f_r      ),
	.s_axis_tuser					(s_axis_tuser_f_r      ),
	.s_axis_tkeep					(s_axis_tkeep_f_r      ),
	.s_axis_tvalid	                (s_axis_tvalid_f_r & s_axis_tready_f),//从过滤器过来的报文能进parser后的fifo
	.s_axis_tlast					(s_axis_tlast_f_r      ),				     
	.s_axis_tready					(s_axis_tready_p       ),//get_segs

	// output to stage0
	.o_phv_valid					(stg0_phv_in_valid     ),
	.o_phv_data						(stg0_phv_in           ),//here is the most important dignal
	.o_phv_end                      (stg0_phv_in_end       ),
	// .i_stg_ready					(stg0_ready),     
	.i_stg_ready					(1'b1                  ),
	//    
	.out_vlan						(stg0_vlan_in          ),
	.out_vlan_valid					(stg0_vlan_valid_in    ),
	.out_vlan_ready                 (stg0_vlan_ready       ),
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

//这里加stage
//从parser出的phv直接进stage
stage0 #(
	.C_S_AXIS_TDATA_WIDTH   (C_S_AXIS_TDATA_WIDTH  ),
	.C_S_AXIS_TUSER_WIDTH   (C_S_AXIS_TUSER_WIDTH  ),
	.C_S_AXIS_TKEEP_WIDTH   (C_S_AXIS_TKEEP_WIDTH  ),
	.STAGE_ID               (0                     ),
	.PHV_LEN                (PHV_LEN               ),
	.KEY_LEN                (96  				   ),
	.KEY_OFF                (38					   ),//实际在底层写了这么长为宽的截取，�?以是定长的设计了
	.LKE_RAM_LEN            (11					   ),//查找表匹配地�?读取ram的宽度：link_model+link_id
	.C_VLANID_WIDTH         (					   )
)
stage0
(
	.axis_clk				(clk                   ),
    .aresetn				(aresetn               ),
 
	// input 
    .phv_in					(stg0_phv_in_d1        ),
    .phv_in_valid			(stg0_phv_in_end_d1    ),
	.vlan_in				(stg0_vlan_in_r        ),//vlan可�?�项
	.vlan_valid_in			(stg0_vlan_valid_in_r  ),
	.vlan_ready_out			(stg0_vlan_ready       ),//这里建议给高
	// output  
	.vlan_out				(stg0_vlan_out         ),
	.vlan_valid_out			(stg0_vlan_valid_out   ),
	.vlan_out_ready			(stg1_vlan_ready       ),
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

stage1 #(
	.C_S_AXIS_TDATA_WIDTH   (C_S_AXIS_TDATA_WIDTH  ),
	.C_S_AXIS_TUSER_WIDTH   (C_S_AXIS_TUSER_WIDTH  ),
	.C_S_AXIS_TKEEP_WIDTH   (C_S_AXIS_TKEEP_WIDTH  ),
	.STAGE_ID               (1                    ),
	.PHV_LEN                (PHV_LEN              ),
	.KEY_LEN                (24                   ),//link_model+pkt_length 4+16
	.ACT_LEN                (24                   )//1/bandwidth
)
stage1
(
	.axis_clk				(clk                  ),
    .aresetn				(aresetn              ),

	// input
    .phv_in					(stg0_phv_out_d1      ),
    .phv_in_valid			(stg0_phv_out_valid_d1),
	.vlan_in				(stg0_vlan_out_r      ),
	.vlan_valid_in			(stg0_vlan_valid_out_r),
	.vlan_ready_out			(stg1_vlan_ready      ),
	// output
	.vlan_out				(stg1_vlan_out        ),
	.vlan_valid_out			(stg1_vlan_valid_out  ),
	.vlan_out_ready			(stg2_vlan_ready      ),
	// output
    .phv_out				(stg1_phv_out         ),
    .phv_out_valid			(stg1_phv_out_valid   ),
	// back-pressure signals
	.stage_ready_out		(stg1_ready           ),
	.stage_ready_in			(stg2_ready           ),

	// control path
    .c_s_axis_tdata        (ctrl_s_axis_tdata_3_r ),
	.c_s_axis_tuser        (ctrl_s_axis_tuser_3_r ),
	.c_s_axis_tkeep        (ctrl_s_axis_tkeep_3_r ),
	.c_s_axis_tlast        (ctrl_s_axis_tlast_3_r ),
	.c_s_axis_tvalid       (ctrl_s_axis_tvalid_3_r),

    .c_m_axis_tdata        (ctrl_s_axis_tdata_4   ),
	.c_m_axis_tuser        (ctrl_s_axis_tuser_4   ),
	.c_m_axis_tkeep        (ctrl_s_axis_tkeep_4   ),
	.c_m_axis_tlast        (ctrl_s_axis_tlast_4   ),
	.c_m_axis_tvalid       (ctrl_s_axis_tvalid_4  )
);

stage2 #(
	.C_S_AXIS_TDATA_WIDTH   (C_S_AXIS_TDATA_WIDTH  ),
	.C_S_AXIS_TUSER_WIDTH   (C_S_AXIS_TUSER_WIDTH  ),
	.C_S_AXIS_TKEEP_WIDTH   (C_S_AXIS_TKEEP_WIDTH  ),
	.STAGE_ID               (2                     ),
	.PHV_LEN                (PHV_LEN               ),
	.KEY_LEN                (24                    ),//link_id
	.ACT_LEN                (16                    )//delay 16b
)
stage2
(
	.axis_clk				(clk                   ),
    .aresetn				(aresetn               ),
    
	// input       
    .phv_in					(stg1_phv_out_d1       ),
    .phv_in_valid			(stg1_phv_out_valid_d1 ),
	.vlan_in				(stg1_vlan_out_r       ),
	.vlan_valid_in			(stg1_vlan_valid_out_r ),
	.vlan_ready_out			(stg2_vlan_ready       ),
	// output 
	.vlan_out				(stg2_vlan_out         ),
	.vlan_valid_out			(stg2_vlan_valid_out   ),
	.vlan_out_ready			(stg3_vlan_ready       ),
	// output 
    .phv_out				(stg2_phv_out          ),
    .phv_out_valid			(stg2_phv_out_valid    ),
	// back-pressure signals 
	.stage_ready_out		(stg2_ready            ),
	.stage_ready_in			(1'b1                  ),

	// control path
    .c_s_axis_tdata         (ctrl_s_axis_tdata_4_r ),
	.c_s_axis_tuser         (ctrl_s_axis_tuser_4_r ),
	.c_s_axis_tkeep         (ctrl_s_axis_tkeep_4_r ),
	.c_s_axis_tlast         (ctrl_s_axis_tlast_4_r ),
	.c_s_axis_tvalid        (ctrl_s_axis_tvalid_4_r),

    .c_m_axis_tdata         (ctrl_s_axis_tdata_5   ),
	.c_m_axis_tuser         (ctrl_s_axis_tuser_5   ),
	.c_m_axis_tkeep         (ctrl_s_axis_tkeep_5   ),
	.c_m_axis_tlast         (ctrl_s_axis_tlast_5   ),
	.c_m_axis_tvalid        (ctrl_s_axis_tvalid_5  )
);

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
	.din			(stg2_phv_out[625:0] ),
	.wr_en			(stg2_phv_out_valid  ),
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
	.din			(stg2_phv_out[1251:626]),
	.wr_en			(stg2_phv_out_valid    ),//we just hold it in one clk
	.rd_en			(phv_fifo_rd_en        ),
	.dout			(high_phv_out          ),
 
	.full			(                      ),
	.prog_full		(                      ),
	.nearly_full	(                      ),
	.empty			(                      ),
	.reset			(~aresetn              ),
	.clk			(clk                   )
);

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

wire                                   w_reg_end            ;
wire                                   w_pkt_data_valid5    ;
wire [C_S_AXIS_TDATA_WIDTH/2-1:0]      w_pkt5_data0         ;  
wire [C_S_AXIS_TDATA_WIDTH/2-1:0]      w_pkt5_data1         ;  
wire [C_S_AXIS_TDATA_WIDTH/2-1:0]      w_pkt5_data2         ;  
wire [C_S_AXIS_TDATA_WIDTH/2-1:0]      w_pkt5_data3         ;  
wire [C_S_AXIS_TDATA_WIDTH/2-1:0]      w_pkt5_data4         ;  
wire [C_S_AXIS_TDATA_WIDTH/2-1:0]      w_pkt5_data5         ;  
wire [C_S_AXIS_TDATA_WIDTH/2-1:0]      w_pkt5_data6         ;  
wire [C_S_AXIS_TDATA_WIDTH/2-1:0]      w_pkt5_data7         ;  
wire [255                  :0]         w_metadata           ;
wire                                   w_metadata_vld       ;  

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
    .pkt_fifo_empty          (pkt_fifo_empty        ),//when we use empty
    .pkt_fifo_rd_en          (pkt_fifo_rd_en        ),//when we use rd_en
   
	.phv_fifo_out            (phv_fifo_out          ),
    .phv_fifo_empty          (phv_fifo_empty        ),//when we use empty
    .phv_fifo_rd_en          (phv_fifo_rd_en        ),//when we use rd_en
	.phv_fifo_in_valid       (stg2_phv_out_valid    ),

	.i_tuser_fifo_rd_en      (w_tuser_fifo_rd_en    ),
  
	.snd_half_fifo_tuser_out (w_snd_half_fifo_tuser ),
	.snd_half_fifo_tkeep_out (w_snd_half_fifo_tkeep ),
	.snd_half_fifo_tlast_out (w_snd_half_fifo_tlast ),

	.o_reg_end               (w_reg_end             ),//ram放回结束
	.o_pkt_data_valid5       (w_pkt_data_valid5     ),//pkt5的数据有效输�?
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
//// �?8段外余下的数�?
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
        .i_seg_fifo_tlast_out(ieg_fifo_tlast_out),
        .o_seg_fifo_rd_en(seg_fifo_rd_en),
        .i_seg_fifo_empty(seg_fifo_empty),

        .depar_out_tdata(depar_out_tdata),
        .depar_out_tkeep(depar_out_tkeep),
        .depar_out_tuser(depar_out_tuser),
        .depar_out_tvalid(depar_out_tvalid),
        .depar_out_tlast(depar_out_tlast),
        .depar_out_tready(depar_out_tready),

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


//parser
switch_parser_top #(
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
	.INIT_FILE           (INIT_FILE           )
)
phv_parser
(
	.axis_clk		                (clk                   ),
	.aresetn		                (aresetn               ),
	// input slvae axi stream     
	.s_axis_tdata					(      ),
	.s_axis_tuser					(      ),
	.s_axis_tkeep					(      ),
	.s_axis_tvalid	                (      ),
	.s_axis_tlast					(      ),				     
	.s_axis_tready					(      ),//get_segs

	// output to stage0
	.o_phv_valid					(  ),
	.o_phv_data						(           ),//here is the most important dignal
	.o_phv_end                      (       ),
	// .i_stg_ready					(),     
	.i_stg_ready					(        ),
	//    
	.out_vlan						(          ),
	.out_vlan_valid					(    ),
	.out_vlan_ready                 (       ),
	// hit the parser rule 
	.m_axis_tdata_0					(   ),
	.m_axis_tuser_0					(   ),
	.m_axis_tkeep_0					(   ),
	.m_axis_tlast_0					(   ),
	.m_axis_tvalid_0				(  ),
	.m_axis_tready_0				(),
	// control path
    .ctrl_s_axis_tdata				( ),
	.ctrl_s_axis_tuser				( ),
	.ctrl_s_axis_tkeep				( ),
	.ctrl_s_axis_tlast				( ),
	.ctrl_s_axis_tvalid				(),

    .ctrl_m_axis_tdata				(   ),
	.ctrl_m_axis_tuser				(   ),
	.ctrl_m_axis_tkeep				(   ),
	.ctrl_m_axis_tlast				(   ),
	.ctrl_m_axis_tvalid				(  )
);
// STs
stage1 #(
	.C_S_AXIS_TDATA_WIDTH   (C_S_AXIS_TDATA_WIDTH  ),
	.C_S_AXIS_TUSER_WIDTH   (C_S_AXIS_TUSER_WIDTH  ),
	.C_S_AXIS_TKEEP_WIDTH   (C_S_AXIS_TKEEP_WIDTH  ),
	.STAGE_ID               (1                    ),
	.PHV_LEN                (PHV_LEN              ),
	.KEY_LEN                (24                   ),//link_model+pkt_length 4+16
	.ACT_LEN                (24                   )//1/bandwidth
)
stage1
(
	.axis_clk				(clk                  ),
    .aresetn				(aresetn              ),

	// input
    .phv_in					(stg0_phv_out_d1      ),
    .phv_in_valid			(stg0_phv_out_valid_d1),
	.vlan_in				(stg0_vlan_out_r      ),
	.vlan_valid_in			(stg0_vlan_valid_out_r),
	.vlan_ready_out			(stg1_vlan_ready      ),
	// output
	.vlan_out				(stg1_vlan_out        ),
	.vlan_valid_out			(stg1_vlan_valid_out  ),
	.vlan_out_ready			(stg2_vlan_ready      ),
	// output
    .phv_out				(stg1_phv_out         ),
    .phv_out_valid			(stg1_phv_out_valid   ),
	// back-pressure signals
	.stage_ready_out		(stg1_ready           ),
	.stage_ready_in			(stg2_ready           ),

	// control path
    .c_s_axis_tdata        (ctrl_s_axis_tdata_3_r ),
	.c_s_axis_tuser        (ctrl_s_axis_tuser_3_r ),
	.c_s_axis_tkeep        (ctrl_s_axis_tkeep_3_r ),
	.c_s_axis_tlast        (ctrl_s_axis_tlast_3_r ),
	.c_s_axis_tvalid       (ctrl_s_axis_tvalid_3_r),

    .c_m_axis_tdata        (ctrl_s_axis_tdata_4   ),
	.c_m_axis_tuser        (ctrl_s_axis_tuser_4   ),
	.c_m_axis_tkeep        (ctrl_s_axis_tkeep_4   ),
	.c_m_axis_tlast        (ctrl_s_axis_tlast_4   ),
	.c_m_axis_tvalid       (ctrl_s_axis_tvalid_4  )
);
// CTs
stage1 #(
	.C_S_AXIS_TDATA_WIDTH   (C_S_AXIS_TDATA_WIDTH  ),
	.C_S_AXIS_TUSER_WIDTH   (C_S_AXIS_TUSER_WIDTH  ),
	.C_S_AXIS_TKEEP_WIDTH   (C_S_AXIS_TKEEP_WIDTH  ),
	.STAGE_ID               (1                    ),
	.PHV_LEN                (PHV_LEN              ),
	.KEY_LEN                (24                   ),//link_model+pkt_length 4+16
	.ACT_LEN                (24                   )//1/bandwidth
)
stage1
(
	.axis_clk				(clk                  ),
    .aresetn				(aresetn              ),

	// input
    .phv_in					(stg0_phv_out_d1      ),
    .phv_in_valid			(stg0_phv_out_valid_d1),
	.vlan_in				(stg0_vlan_out_r      ),
	.vlan_valid_in			(stg0_vlan_valid_out_r),
	.vlan_ready_out			(stg1_vlan_ready      ),
	// output
	.vlan_out				(stg1_vlan_out        ),
	.vlan_valid_out			(stg1_vlan_valid_out  ),
	.vlan_out_ready			(stg2_vlan_ready      ),
	// output
    .phv_out				(stg1_phv_out         ),
    .phv_out_valid			(stg1_phv_out_valid   ),
	// back-pressure signals
	.stage_ready_out		(stg1_ready           ),
	.stage_ready_in			(stg2_ready           ),

	// control path
    .c_s_axis_tdata        (ctrl_s_axis_tdata_3_r ),
	.c_s_axis_tuser        (ctrl_s_axis_tuser_3_r ),
	.c_s_axis_tkeep        (ctrl_s_axis_tkeep_3_r ),
	.c_s_axis_tlast        (ctrl_s_axis_tlast_3_r ),
	.c_s_axis_tvalid       (ctrl_s_axis_tvalid_3_r),

    .c_m_axis_tdata        (ctrl_s_axis_tdata_4   ),
	.c_m_axis_tuser        (ctrl_s_axis_tuser_4   ),
	.c_m_axis_tkeep        (ctrl_s_axis_tkeep_4   ),
	.c_m_axis_tlast        (ctrl_s_axis_tlast_4   ),
	.c_m_axis_tvalid       (ctrl_s_axis_tvalid_4  )
);

//deparser


always @(posedge clk) begin
	if (~aresetn) begin
		stg0_phv_in_end_d1  <= 0;
		stg0_phv_in_valid_d1  <= 0;
		stg0_phv_out_valid_d1 <= 0;
		stg1_phv_out_valid_d1 <= 0;
		stg2_phv_out_valid_d1 <= 0;

		stg0_phv_in_d1  <= 0;
		stg0_phv_out_d1 <= 0;
		stg1_phv_out_d1 <= 0;
		stg2_phv_out_d1 <= 0;
		//
		stg0_vlan_in_r <= 0;
		stg0_vlan_valid_in_r <= 0;
		stg0_vlan_out_r <= 0;
		stg0_vlan_valid_out_r <= 0;
		stg1_vlan_out_r <= 0;
		stg1_vlan_valid_out_r <= 0;
		stg2_vlan_out_r <= 0;
		stg2_vlan_valid_out_r <= 0;
		stg3_vlan_out_r <= 0;
		stg3_vlan_valid_out_r <= 0;
	end
	else begin
		stg0_phv_in_end_d1    <= stg0_phv_in_end;

		stg0_phv_in_valid_d1  <= stg0_phv_in_valid;
		stg0_phv_out_valid_d1 <= stg0_phv_out_valid;
		stg1_phv_out_valid_d1 <= stg1_phv_out_valid;
		stg2_phv_out_valid_d1 <= stg2_phv_out_valid;

		stg0_phv_in_d1  <= stg0_phv_in;
		stg0_phv_out_d1 <= stg0_phv_out;
		stg1_phv_out_d1 <= stg1_phv_out;
		stg2_phv_out_d1 <= stg2_phv_out;
		//
		stg0_vlan_in_r <= stg0_vlan_in;
		stg0_vlan_valid_in_r <= stg0_vlan_valid_in;
		stg0_vlan_out_r <= stg0_vlan_out;
		stg0_vlan_valid_out_r <= stg0_vlan_valid_out;
		stg1_vlan_out_r <= stg1_vlan_out;
		stg1_vlan_valid_out_r <= stg1_vlan_valid_out;
		stg2_vlan_out_r <= stg2_vlan_out;
		stg2_vlan_valid_out_r <= stg2_vlan_valid_out;
		stg3_vlan_out_r <= stg3_vlan_out;
		stg3_vlan_valid_out_r <= stg3_vlan_valid_out;
	end
end

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

	end
end



endmodule
