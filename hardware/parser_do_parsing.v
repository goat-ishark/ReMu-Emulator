
`timescale 1ns / 1ps

`define DEF_MAC_ADDR	48
`define DEF_VLAN		32
`define DEF_ETHTYPE		16

`define TYPE_IPV4		16'h0008
`define TYPE_ARP		16'h0608

`define PROT_ICMP		8'h01
`define PROT_TCP		8'h06
`define PROT_UDP		8'h11

`define SUB_PARSE(idx) \
	case(sub_parse_val_out_type[idx]) \
		2'b01: val_2B_nxt[sub_parse_val_out_seq[idx]] = sub_parse_val_out[idx][15:0]; \
		2'b10: val_4B_nxt[sub_parse_val_out_seq[idx]] = sub_parse_val_out[idx][31:0]; \
		2'b11: val_8B_nxt[sub_parse_val_out_seq[idx]] = sub_parse_val_out[idx][63:0]; \
	endcase \
 
// `define SWAP_BYTE_ORDER \
// 	assign val_8B_swapped = {	val_8B[0+:8], \
// 									val_8B[8+:8], \
// 									val_8B[16+:8], \
// 									val_8B[24+:8], \
// 									val_8B[32+:8], \
// 									val_8B[40+:8], \
// 									val_8B[48+:8], \
// 									val_8B[56+:8]}; \
// 	assign val_4B_swapped = {	val_4B[0+:8], \
// 									val_4B[8+:8], \
// 									val_4B[16+:8], \
// 									val_4B[24+:8]}; \
// 	assign val_2B_swapped = {	val_2B[0+:8], \
// 									val_2B[8+:8]}; \
//how about get a conflict when the parser action is used in the same val
//由于24条指令及对应的容器要组合成一个phv，所以该模块将前步骤提取的所有有效数据输入，最终输出phv
module parser_do_parsing #(
	parameter C_S_AXIS_TDATA_WIDTH = 512,
	parameter C_S_AXIS_TUSER_WIDTH = 256,
	parameter PHV_LEN = (8+4+2)*8*8+100+256,
	parameter PKTS_LEN = 2048,
	parameter PARSER_MOD_ID = 3'd1,
	parameter C_NUM_SEGS = 4,
	parameter C_VLANID_WIDTH = 12,
	parameter DO_PARER_GROUP = 12

)
(
	input											axis_clk,
	input											aresetn,

	input [DO_PARER_GROUP-1:0] 						sub_parse_val_valid,//parser进来的数据由效
	input [DO_PARER_GROUP-1:0]                      sub_parse_val_end  ,
	input [64*DO_PARER_GROUP-1:0] 					sub_parse_val      ,//以64字节为组分的子容器字段
	input [2*DO_PARER_GROUP-1:0] 					sub_parse_val_type , 
	input [3*DO_PARER_GROUP-1:0]                    sub_parse_val_seq  ,
	//in parser bram addrb_out
	input [8:0] 									i_bram_parser_addrb,//存下parser指令的地址，同时代替vlan做后级指令存放的地址
	input 											i_bram_parser_valid,
	input                                           i_bram_parser_end  ,
	//
	input [15:0]                                    i_lenth            ,
	input                                           i_lenth_valid      ,
	//
	input [C_S_AXIS_TUSER_WIDTH-1:0]			    i_tuser_1st        ,
	input                                           i_tuser_1st_valid  ,
	// input [C_VLANID_WIDTH-1 :0]                     i_vlan,
	// input                                           i_vlan_valid,
	// input [C_NUM_SEGS*C_AXIS_DATA_WIDTH-1:0]		tdata_segs,

	// input [1*DO_PARER_GROUP-1:0] 					i_sub_seg_valid   ,//启动提取
	// input [319:0]									bram_out,
	input											i_stg_ready       ,
    
	// phv output    
	output 		     								o_phv_valid       ,
	output     [PHV_LEN-1:0]					    o_phv             ,
	output                                          o_phv_end         ,
    
	output     [C_VLANID_WIDTH-1:0]			        out_vlan          ,
	output    									    out_vlan_valid    ,
	input											out_vlan_ready

);

localparam			PARSE_ACT_LEN   =5'd16;
localparam			VAL_OUT_LEN     =7'd64;

localparam			IDLE            =0    ,
					SUB_PARSE_1     =1    ,
					SUB_PARSE_2     =2    ,
					SUB_PARSE_3     =3    ,
					SUB_PARSE_4     =4    ,
					SUB_PARSE_5     =5    ,
					GET_PHV_OUTPUT  =6    ,
					OUTPUT          =7    ,
					SUB_PARSE_ST    =8    ,
					IDLE_PARSE_1    =9    ,
					IDLE_PARSE_2    =10   ;
					

reg [3:0] state, state_next;
reg bram_addr_rd;
wire [8:0] bram_parser_addrb;
assign out_vlan       = bram_parser_addrb;
assign out_vlan_valid = bram_addr_rd     ;
// // parsing actions
// wire [15:0] parse_action [0:19];		// we have 10 parse action
// reg [3:0] sub_parse_act_valid;
reg [DO_PARER_GROUP-1:0] sub_parse_act_valid;
reg [63:0] sub_parse_val_out [0:DO_PARER_GROUP-1];
reg  sub_parse_val_out_valid [0:DO_PARER_GROUP-1];
reg [1:0] sub_parse_val_out_type [0:DO_PARER_GROUP-1];
reg [2:0] sub_parse_val_out_seq [0:DO_PARER_GROUP-1];


reg                         o_phv_valid_next;
reg                         o_phv_end_next  ;
reg [PHV_LEN-1:0]           o_phv_next      ;
reg                         idle_parser,idle_parser_nxt     ;
always @(posedge axis_clk) begin
	if(~aresetn)begin
		sub_parse_val_out_seq[0 ] <= 3'd0;
		sub_parse_val_out_seq[1 ] <= 3'd0;
		sub_parse_val_out_seq[2 ] <= 3'd0;
		sub_parse_val_out_seq[3 ] <= 3'd0;
		sub_parse_val_out_seq[4 ] <= 3'd0;
		sub_parse_val_out_seq[5 ] <= 3'd0;
		sub_parse_val_out_seq[6 ] <= 3'd0;
		sub_parse_val_out_seq[7 ] <= 3'd0;
		sub_parse_val_out_seq[8 ] <= 3'd0;
		sub_parse_val_out_seq[9 ] <= 3'd0;
		sub_parse_val_out_seq[10] <= 3'd0;
		sub_parse_val_out_seq[11] <= 3'd0;
	end
	else begin 
    	sub_parse_val_out_seq[0 ] <= sub_parse_val_seq[35:33];
    	sub_parse_val_out_seq[1 ] <= sub_parse_val_seq[32:30];
    	sub_parse_val_out_seq[2 ] <= sub_parse_val_seq[29:27];
    	sub_parse_val_out_seq[3 ] <= sub_parse_val_seq[26:24];
    	sub_parse_val_out_seq[4 ] <= sub_parse_val_seq[23:21];
    	sub_parse_val_out_seq[5 ] <= sub_parse_val_seq[20:18];
    	sub_parse_val_out_seq[6 ] <= sub_parse_val_seq[17:15];
    	sub_parse_val_out_seq[7 ] <= sub_parse_val_seq[14:12];
    	sub_parse_val_out_seq[8 ] <= sub_parse_val_seq[11:9 ];
    	sub_parse_val_out_seq[9 ] <= sub_parse_val_seq[8 :6 ];
    	sub_parse_val_out_seq[10] <= sub_parse_val_seq[5 :3 ];
    	sub_parse_val_out_seq[11] <= sub_parse_val_seq[2 :0 ];
	end
end

always @(posedge axis_clk) begin
	if(~aresetn) begin
		sub_parse_val_out[0 ] <= 64'd0;
		sub_parse_val_out[1 ] <= 64'd0;
		sub_parse_val_out[2 ] <= 64'd0;
		sub_parse_val_out[3 ] <= 64'd0;
		sub_parse_val_out[4 ] <= 64'd0;
		sub_parse_val_out[5 ] <= 64'd0;
		sub_parse_val_out[6 ] <= 64'd0;
		sub_parse_val_out[7 ] <= 64'd0;
		sub_parse_val_out[8 ] <= 64'd0;
		sub_parse_val_out[9 ] <= 64'd0;
		sub_parse_val_out[10] <= 64'd0;
		sub_parse_val_out[11] <= 64'd0;	
	end
	else begin
		sub_parse_val_out[0 ] <= sub_parse_val[767:704];
		sub_parse_val_out[1 ] <= sub_parse_val[703:640];
		sub_parse_val_out[2 ] <= sub_parse_val[639:576];
		sub_parse_val_out[3 ] <= sub_parse_val[575:512];
		sub_parse_val_out[4 ] <= sub_parse_val[511:448];
		sub_parse_val_out[5 ] <= sub_parse_val[447:384];
		sub_parse_val_out[6 ] <= sub_parse_val[383:320];
		sub_parse_val_out[7 ] <= sub_parse_val[319:256];
		sub_parse_val_out[8 ] <= sub_parse_val[255:192];
		sub_parse_val_out[9 ] <= sub_parse_val[191:128];
		sub_parse_val_out[10] <= sub_parse_val[127:64 ];
		sub_parse_val_out[11] <= sub_parse_val[63 :0  ];
	end
end

always @(posedge axis_clk) begin
	if(~aresetn) begin
		sub_parse_val_out_valid[0 ] <= 1'b0;
		sub_parse_val_out_valid[1 ] <= 1'b0;
		sub_parse_val_out_valid[2 ] <= 1'b0;
		sub_parse_val_out_valid[3 ] <= 1'b0;
		sub_parse_val_out_valid[4 ] <= 1'b0;
		sub_parse_val_out_valid[5 ] <= 1'b0;
		sub_parse_val_out_valid[6 ] <= 1'b0;
		sub_parse_val_out_valid[7 ] <= 1'b0;
		sub_parse_val_out_valid[8 ] <= 1'b0;
		sub_parse_val_out_valid[9 ] <= 1'b0;
		sub_parse_val_out_valid[10] <= 1'b0;
		sub_parse_val_out_valid[11] <= 1'b0;
	end
	else begin
		sub_parse_val_out_valid[0 ] <= sub_parse_val_valid[11];
		sub_parse_val_out_valid[1 ] <= sub_parse_val_valid[10];
		sub_parse_val_out_valid[2 ] <= sub_parse_val_valid[9 ];
		sub_parse_val_out_valid[3 ] <= sub_parse_val_valid[8 ];
		sub_parse_val_out_valid[4 ] <= sub_parse_val_valid[7 ];
		sub_parse_val_out_valid[5 ] <= sub_parse_val_valid[6 ];
		sub_parse_val_out_valid[6 ] <= sub_parse_val_valid[5 ];
		sub_parse_val_out_valid[7 ] <= sub_parse_val_valid[4 ];
		sub_parse_val_out_valid[8 ] <= sub_parse_val_valid[3 ];
		sub_parse_val_out_valid[9 ] <= sub_parse_val_valid[2 ];
		sub_parse_val_out_valid[10] <= sub_parse_val_valid[1 ];
		sub_parse_val_out_valid[11] <= sub_parse_val_valid[0 ];
	end
end

always @(posedge axis_clk) begin
	if(~aresetn) begin
		sub_parse_val_out_type[0 ] <= 2'd0;
		sub_parse_val_out_type[1 ] <= 2'd0;
		sub_parse_val_out_type[2 ] <= 2'd0;
		sub_parse_val_out_type[3 ] <= 2'd0;
		sub_parse_val_out_type[4 ] <= 2'd0;
		sub_parse_val_out_type[5 ] <= 2'd0;
		sub_parse_val_out_type[6 ] <= 2'd0;
		sub_parse_val_out_type[7 ] <= 2'd0;
		sub_parse_val_out_type[8 ] <= 2'd0;
		sub_parse_val_out_type[9 ] <= 2'd0;
		sub_parse_val_out_type[10] <= 2'd0;
		sub_parse_val_out_type[11] <= 2'd0;
	end
	else begin
		sub_parse_val_out_type[0 ] <= sub_parse_val_type[23:22];
		sub_parse_val_out_type[1 ] <= sub_parse_val_type[21:20];
		sub_parse_val_out_type[2 ] <= sub_parse_val_type[19:18];
		sub_parse_val_out_type[3 ] <= sub_parse_val_type[17:16];
		sub_parse_val_out_type[4 ] <= sub_parse_val_type[15:14];
		sub_parse_val_out_type[5 ] <= sub_parse_val_type[13:12];
		sub_parse_val_out_type[6 ] <= sub_parse_val_type[11:10];
		sub_parse_val_out_type[7 ] <= sub_parse_val_type[9 :8 ];
		sub_parse_val_out_type[8 ] <= sub_parse_val_type[7 :6 ];
		sub_parse_val_out_type[9 ] <= sub_parse_val_type[5 :4 ];
		sub_parse_val_out_type[10] <= sub_parse_val_type[3 :2 ];
		sub_parse_val_out_type[11] <= sub_parse_val_type[1 :0 ];
	end
end

reg [63:0] val_8B [0:7];
reg [31:0] val_4B [0:7];
reg [15:0] val_2B [0:7];
reg [63:0] val_8B_nxt [0:7];
reg [31:0] val_4B_nxt [0:7];
reg [15:0] val_2B_nxt [0:7];

// wire [63:0] val_8B_swapped [0:7];
// wire [31:0] val_4B_swapped [0:7];
// wire [15:0] val_2B_swapped [0:7];
wire [15:0]  lenth_fifo       ;
wire         lenth_empty      ;
wire [127:0] tuser_1st_fifo   ;
// `SWAP_BYTE_ORDER
//metadata define add value here
wire [7  :0] phv_dst                    ;//31-24
wire [31 :0] phv_intime_stamp           ;//127-96
wire [15 :0] phv_lenth                  ;//128-143
wire [15 :0] phv_delay                  ;//144-159
wire [3  :0] phv_loss_theta             ;//160-163
wire [3  :0] phv_link_model             ;//164-167
wire [7  :0] phv_flow_id                ;//168-175
wire [23 :0] phv_band_width             ;//176-199
wire [155:0] phv_reserv                 ;//200-355
//val 896+
assign phv_dst          = 8'h04              ;
assign phv_intime_stamp = tuser_1st_fifo[127:96];
assign phv_lenth        = lenth_fifo         ;
assign phv_delay        = 0                  ;
assign phv_loss_theta   = ((!o_phv_valid_next) &  o_phv_end_next) ;
assign phv_link_model = 4'd0;
assign phv_flow_id = 0;
assign phv_band_width = 0;
assign phv_reserv = 0;
reg [PHV_LEN-1:0]   r_phv      ;
reg                 r_phv_valid;
reg                 r_phv_end  ;
always @(*) begin
	state_next = state;
	//
	o_phv_valid_next = 0;
	o_phv_next       = r_phv;
	o_phv_end_next   = 0;
	bram_addr_rd        = 0;
	//
	val_2B_nxt[0] = val_2B[0];
	val_2B_nxt[1] = val_2B[1];
	val_2B_nxt[2] = val_2B[2];
	val_2B_nxt[3] = val_2B[3];
	val_2B_nxt[4] = val_2B[4];
	val_2B_nxt[5] = val_2B[5];
	val_2B_nxt[6] = val_2B[6];
	val_2B_nxt[7] = val_2B[7];
	val_4B_nxt[0] = val_4B[0];
	val_4B_nxt[1] = val_4B[1];
	val_4B_nxt[2] = val_4B[2];
	val_4B_nxt[3] = val_4B[3];
	val_4B_nxt[4] = val_4B[4];
	val_4B_nxt[5] = val_4B[5];
	val_4B_nxt[6] = val_4B[6];
	val_4B_nxt[7] = val_4B[7];
	val_8B_nxt[0] = val_8B[0];
	val_8B_nxt[1] = val_8B[1];
	val_8B_nxt[2] = val_8B[2];
	val_8B_nxt[3] = val_8B[3];
	val_8B_nxt[4] = val_8B[4];
	val_8B_nxt[5] = val_8B[5];
	val_8B_nxt[6] = val_8B[6];
	val_8B_nxt[7] = val_8B[7];
	//
	sub_parse_act_valid = 12'd0;
	idle_parser_nxt = idle_parser;
	case (state)
		IDLE: begin
			if (sub_parse_val_end == 12'hfff) //信号到了
				if(sub_parse_val_valid)
					state_next = SUB_PARSE_1;
				else
					state_next = IDLE_PARSE_1;
			else 
				state_next = IDLE;
		end
		IDLE_PARSE_1:begin
			sub_parse_act_valid = 12'h000;
			state_next = IDLE_PARSE_2;
			bram_addr_rd = 0;
			idle_parser_nxt = 1;
		end
		IDLE_PARSE_2:begin
			sub_parse_act_valid = 12'h000;
			state_next = GET_PHV_OUTPUT;
			bram_addr_rd = 0;
			idle_parser_nxt = 1;
		end
		SUB_PARSE_1: begin
			`SUB_PARSE(0 )
			`SUB_PARSE(1 )
			`SUB_PARSE(2 )
			`SUB_PARSE(3 )
			`SUB_PARSE(4 )
			`SUB_PARSE(5 )
			`SUB_PARSE(6 )
			`SUB_PARSE(7 )
			`SUB_PARSE(8 )
			`SUB_PARSE(9 )
			`SUB_PARSE(10)
			`SUB_PARSE(11)
			sub_parse_act_valid = 12'hfff;
			state_next = SUB_PARSE_2;
			bram_addr_rd = 1;
			idle_parser_nxt = 0;
		end

		SUB_PARSE_2: begin
			state_next = GET_PHV_OUTPUT;

			`SUB_PARSE(0 )
			`SUB_PARSE(1 )
			`SUB_PARSE(2 )
			`SUB_PARSE(3 )
			`SUB_PARSE(4 )
			`SUB_PARSE(5 )
			`SUB_PARSE(6 )
			`SUB_PARSE(7 )
			`SUB_PARSE(8 )
			`SUB_PARSE(9 )
			`SUB_PARSE(10)
			`SUB_PARSE(11)
			sub_parse_act_valid = 12'hfff;
			idle_parser_nxt = 0;
		end

		GET_PHV_OUTPUT: begin
			if(i_stg_ready) begin
				o_phv_end_next = 1;
				state_next = IDLE;
				if(idle_parser) begin
					o_phv_valid_next = 1'b0;
					o_phv_next = {1092'd0,phv_link_model,phv_loss_theta,phv_delay,phv_lenth,phv_intime_stamp,tuser_1st_fifo[95:32],phv_dst,tuser_1st_fifo[23:0]};
				end
				else begin
					o_phv_valid_next = 1'b1;
					o_phv_next ={val_8B[7], val_8B[6], val_8B[5], val_8B[4], val_8B[3], val_8B[2], val_8B[1], val_8B[0],
							 val_4B[7], val_4B[6], val_4B[5], val_4B[4], val_4B[3], val_4B[2], val_4B[1], val_4B[0],
							 val_2B[7], val_2B[6], val_2B[5], val_2B[4], val_2B[3], val_2B[2], val_2B[1], val_2B[0],
								// Tao: manually set output port to 1 for eazy test
								// {115{1'b0}}, vlan_id, 1'b0, i_tuser_1st[127:32], 8'h04, i_tuser_1st[23:0]};
							phv_reserv,phv_band_width,phv_flow_id,phv_link_model,phv_loss_theta,phv_delay,phv_lenth,phv_intime_stamp,tuser_1st_fifo[95:32],phv_dst,tuser_1st_fifo[23:0]};
				end
				// zero out
				val_2B_nxt[0]=0;
				val_2B_nxt[1]=0;
				val_2B_nxt[2]=0;
				val_2B_nxt[3]=0;
				val_2B_nxt[4]=0;
				val_2B_nxt[5]=0;
				val_2B_nxt[6]=0;
				val_2B_nxt[7]=0;
				val_4B_nxt[0]=0;
				val_4B_nxt[1]=0;
				val_4B_nxt[2]=0;
				val_4B_nxt[3]=0;
				val_4B_nxt[4]=0;
				val_4B_nxt[5]=0;
				val_4B_nxt[6]=0;
				val_4B_nxt[7]=0;
				val_8B_nxt[0]=0;
				val_8B_nxt[1]=0;
				val_8B_nxt[2]=0;
				val_8B_nxt[3]=0;
				val_8B_nxt[4]=0;
				val_8B_nxt[5]=0;
				val_8B_nxt[6]=0;
				val_8B_nxt[7]=0;
			end
			else begin
				state_next = GET_PHV_OUTPUT;
			end
		end
	endcase
end

always @(posedge axis_clk) begin
	if (~aresetn) begin
		state <= IDLE;
		//
		r_phv_end <= 0;
		r_phv <= 0;
		r_phv_valid <= 0;
		//
		// out_vlan <= 0;
		// out_vlan_valid <= 0;
		//
		val_2B[0] <= 0;
		val_2B[1] <= 0;
		val_2B[2] <= 0;
		val_2B[3] <= 0;
		val_2B[4] <= 0;
		val_2B[5] <= 0;
		val_2B[6] <= 0;
		val_2B[7] <= 0;
		val_4B[0] <= 0;
		val_4B[1] <= 0;
		val_4B[2] <= 0;
		val_4B[3] <= 0;
		val_4B[4] <= 0;
		val_4B[5] <= 0;
		val_4B[6] <= 0;
		val_4B[7] <= 0;
		val_8B[0] <= 0;
		val_8B[1] <= 0;
		val_8B[2] <= 0;
		val_8B[3] <= 0;
		val_8B[4] <= 0;
		val_8B[5] <= 0;
		val_8B[6] <= 0;
		val_8B[7] <= 0;
		idle_parser <= 0;
	end
	else begin
		state <= state_next;
		//
		r_phv_end <= o_phv_end_next;
		r_phv <= o_phv_next;
		r_phv_valid <= o_phv_valid_next;
		//
		val_2B[0] <= val_2B_nxt[0];
		val_2B[1] <= val_2B_nxt[1];
		val_2B[2] <= val_2B_nxt[2];
		val_2B[3] <= val_2B_nxt[3];
		val_2B[4] <= val_2B_nxt[4];
		val_2B[5] <= val_2B_nxt[5];
		val_2B[6] <= val_2B_nxt[6];
		val_2B[7] <= val_2B_nxt[7];
		val_4B[0] <= val_4B_nxt[0];
		val_4B[1] <= val_4B_nxt[1];
		val_4B[2] <= val_4B_nxt[2];
		val_4B[3] <= val_4B_nxt[3];
		val_4B[4] <= val_4B_nxt[4];
		val_4B[5] <= val_4B_nxt[5];
		val_4B[6] <= val_4B_nxt[6];
		val_4B[7] <= val_4B_nxt[7];
		val_8B[0] <= val_8B_nxt[0];
		val_8B[1] <= val_8B_nxt[1];
		val_8B[2] <= val_8B_nxt[2];
		val_8B[3] <= val_8B_nxt[3];
		val_8B[4] <= val_8B_nxt[4];
		val_8B[5] <= val_8B_nxt[5];
		val_8B[6] <= val_8B_nxt[6];
		val_8B[7] <= val_8B_nxt[7];
		idle_parser <= idle_parser_nxt;
	end
end
// assign o_phv = {r_phv[1251:356],100'd0,118'd0,bram_parser_addrb,r_phv[127:0]};
assign o_phv = {r_phv[1251:356],100'd0,r_phv[255:41],bram_parser_addrb,r_phv[31:0]};
assign o_phv_valid = r_phv_valid;
assign o_phv_end   = r_phv_end  ;

fallthrough_small_fifo #(
	.WIDTH(9),
	.MAX_DEPTH_BITS(5)
)
parser_addrb_fifo
(
	.din									(i_bram_parser_addrb ),
	.wr_en									(i_bram_parser_valid ),
	.rd_en									(bram_addr_rd        ),
	.dout									(bram_parser_addrb   ),
	.full									(                    ),
	.prog_full								(                    ),
	.nearly_full							(pkt_fifo_nearly_full),
	.empty									(pkt_fifo_empty      ),
	.reset									(~aresetn            ),
	.clk									(axis_clk            )
);



fallthrough_small_fifo #(
	.WIDTH         (16 ),
	.MAX_DEPTH_BITS(16)
)
lenth_buffer_fifo
(
	.din									(i_lenth         ),
	.wr_en									(i_lenth_valid   ),
	.rd_en									(o_phv_end_next  ),
	.dout									(lenth_fifo      ),
	.full									(                ),
	.prog_full								(                ),
	.nearly_full							(                ),
	.empty									(lenth_empty     ),
	.reset									(~aresetn        ),
	.clk									(axis_clk        )
);
fallthrough_small_fifo #(
	.WIDTH         (128),
	.MAX_DEPTH_BITS(16 )
)
tuser_buffer_fifo
(
	.din									(i_tuser_1st      ),
	.wr_en									(i_tuser_1st_valid),
	.rd_en									(o_phv_end_next   ),
	.dout									(tuser_1st_fifo   ),
	.full									(                 ),
	.prog_full								(                 ),
	.nearly_full							(                 ),
	.empty									(                 ),
	.reset									(~aresetn         ),
	.clk									(axis_clk         )
);
endmodule
