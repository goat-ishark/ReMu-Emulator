`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/01/10 16:23:48
// Design Name: 
// Module Name: cfg_parser_bram
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


module parser_bram_cfg #(
	parameter C_S_AXIS_TDATA_WIDTH  = 512 ,
	parameter C_S_AXIS_TUSER_WIDTH = 256  ,
	parameter C_S_AXIS_TKEEP_WIDTH = 64   ,
	parameter TCAM_MATCH_ADDR    = 5      ,
	parameter VLAN_ID_WIDTH      = 12     ,
	parameter C_PARSER_RAM_WIDTH = 16*24  ,
	parameter PARSER_MOD_ID      = 1
)(
    input 									   axis_clk               ,
    input 									   aresetn                ,

    input      [C_S_AXIS_TDATA_WIDTH-1:0]       ctrl_s_axis_tdata      ,
    input      [C_S_AXIS_TUSER_WIDTH-1:0]       ctrl_s_axis_tuser      ,
    input      [C_S_AXIS_TKEEP_WIDTH-1:0]       ctrl_s_axis_tkeep      ,
    input                                       ctrl_s_axis_tvalid     ,
    input                                       ctrl_s_axis_tlast      ,
        
    output reg [C_S_AXIS_TDATA_WIDTH-1:0]       ctrl_m_axis_tdata      ,
    output reg [C_S_AXIS_TUSER_WIDTH-1:0]       ctrl_m_axis_tuser      ,
    output reg [C_S_AXIS_TKEEP_WIDTH-1:0]       ctrl_m_axis_tkeep      ,
    output reg                                  ctrl_m_axis_tvalid     ,
    output reg                                  ctrl_m_axis_tlast      ,
   
    input 									    i_dp_tcam_match        ,
    input [TCAM_MATCH_ADDR-1:0] 			    i_dp_tcam_match_addr   ,
	input                                       i_dp_tcam_match_end    ,
 
    output 		reg	 [C_PARSER_RAM_WIDTH-1:0]   o_bram_parser          ,
	output      reg                             o_bram_parser_valid    ,
	output      reg [8:0]                       o_bram_parser_addrb    , //在parser部分提取的指令地址直接给到deparser
    output      reg                             o_bram_parser_end                        
	);



    /*================Control Path====================*/

wire [C_PARSER_RAM_WIDTH-1:0]   bram_parser;
wire [C_S_AXIS_TDATA_WIDTH-1:0]	ctrl_s_axis_tdata_swapped;

reg [15:0] dbg_bram_parser_end;
always @(posedge axis_clk) begin
	if(~aresetn)begin
		dbg_bram_parser_end <= 0;
	end
	else if(o_bram_parser_end)
		dbg_bram_parser_end <= dbg_bram_parser_end+1'b1;
	else 
		dbg_bram_parser_end <= dbg_bram_parser_end;
end

reg [15:0] dbg_bram_parser_valid;
always @(posedge axis_clk) begin
	if(~aresetn)begin
		dbg_bram_parser_valid <= 0;
	end
	else if(o_bram_parser_valid)
		dbg_bram_parser_valid <= dbg_bram_parser_valid+1'b1;
	else 
		dbg_bram_parser_valid <= dbg_bram_parser_valid;
end

assign ctrl_s_axis_tdata_swapped = {	ctrl_s_axis_tdata[0 +:8],      	//[255:248]
										ctrl_s_axis_tdata[8 +:8],		//[247:240]
										ctrl_s_axis_tdata[16+:8],		//[239:232]
										ctrl_s_axis_tdata[24+:8],		//[231:224]
										ctrl_s_axis_tdata[32+:8],		//[223:216]
										ctrl_s_axis_tdata[40+:8],		//[215:208]
										ctrl_s_axis_tdata[48+:8],		//[207:200]
										ctrl_s_axis_tdata[56+:8],		//[199:192]
										ctrl_s_axis_tdata[64+:8],		//[191:184]
										ctrl_s_axis_tdata[72+:8],		//[183:176]
										ctrl_s_axis_tdata[80+:8],		//[175:168]
										ctrl_s_axis_tdata[88+:8],		//[167:160]
										ctrl_s_axis_tdata[96+:8],		//[159:152]
										ctrl_s_axis_tdata[104+:8],		//[151:144]
										ctrl_s_axis_tdata[112+:8],		//[143:136]
										ctrl_s_axis_tdata[120+:8],		//[135:128]
										ctrl_s_axis_tdata[128+:8],		//[127:120]
										ctrl_s_axis_tdata[136+:8],		//[119:112]
										ctrl_s_axis_tdata[144+:8],		//[111:104]
										ctrl_s_axis_tdata[152+:8],		//[103:96 ]
										ctrl_s_axis_tdata[160+:8],		//[95 :88 ]
										ctrl_s_axis_tdata[168+:8],		//[87 :80 ]
										ctrl_s_axis_tdata[176+:8],		//[79 :72 ]
										ctrl_s_axis_tdata[184+:8],		//[71 :64 ]
										ctrl_s_axis_tdata[192+:8],		//[63 :56 ]
										ctrl_s_axis_tdata[200+:8],		//[55 :48 ]
										ctrl_s_axis_tdata[208+:8],		//[47 :40 ]
										ctrl_s_axis_tdata[216+:8],		//[39 :32 ]
										ctrl_s_axis_tdata[224+:8],		//[31 :24 ]
										ctrl_s_axis_tdata[232+:8],		//[23 :16 ]
										ctrl_s_axis_tdata[240+:8],		//[15 :08 ]
										ctrl_s_axis_tdata[248+:8]};		//[07 :00 ]


reg [8:0]						ctrl_wr_ram_addr;//0-512
reg	[C_PARSER_RAM_WIDTH-1:0]	ctrl_wr_ram_data;
reg								ctrl_wr_ram_en;

wire [3:0] parser_mod_id;
assign parser_mod_id = ctrl_s_axis_tdata[368+:4];

localparam	WAIT_FIRST_PKT = 0,
			WAIT_SECOND_PKT = 1,
			WAIT_THIRD_PKT = 2,
			WAIT_FOURTH_PKT = 3,
			WRITE_RAM = 4,
			FLUSH_REST_C = 5;

reg [3:0] ctrl_ram_state;

always @(posedge axis_clk) begin
	if(!aresetn) begin
		ctrl_wr_ram_addr <= 0;
		ctrl_wr_ram_data <= 0;
		ctrl_wr_ram_en   <= 0;
		ctrl_ram_state   <= WAIT_FIRST_PKT;
	end
	else begin
		case (ctrl_ram_state)
			WAIT_FIRST_PKT: begin
				if (ctrl_s_axis_tvalid) begin
					if (parser_mod_id == PARSER_MOD_ID) begin
						ctrl_ram_state <= WAIT_THIRD_PKT;
					end
					else begin
						ctrl_ram_state <= FLUSH_REST_C;
					end
				end
				else begin
					ctrl_ram_state <= WAIT_FIRST_PKT;
				end
			end
			WAIT_THIRD_PKT: begin // first half of ctrl_wr_ram_data
				ctrl_wr_ram_en <= 1'b0;
				if (ctrl_s_axis_tvalid) begin
					ctrl_wr_ram_data[383-:256] <= ctrl_s_axis_tdata_swapped[255-:256];//16条指令
					if(ctrl_s_axis_tlast) begin
						ctrl_ram_state <= WRITE_RAM;
					end
					else begin
						ctrl_ram_state <= WAIT_FOURTH_PKT;
					end
				end
				else begin
					ctrl_ram_state <= WAIT_THIRD_PKT;
					ctrl_wr_ram_data <= ctrl_wr_ram_data;
				end
			end
			WAIT_FOURTH_PKT: begin // first half of ctrl_wr_ram_data
				if (ctrl_s_axis_tvalid) begin
					ctrl_wr_ram_data[127-:128] <= ctrl_s_axis_tdata_swapped[239-:128];//8条指令
					ctrl_wr_ram_addr <= ctrl_s_axis_tdata_swapped[248-:9];
					ctrl_wr_ram_en <= 1'b1;
					if(ctrl_s_axis_tlast) begin //如果是最后一拍数据，则写入ram，否则跳回接收数据的一拍
						ctrl_ram_state <= WRITE_RAM;
					end
					else begin
						ctrl_ram_state <= WAIT_THIRD_PKT;
					end
				end
				else begin
					ctrl_ram_state <= WAIT_FOURTH_PKT;
					ctrl_wr_ram_data <= ctrl_wr_ram_data;
				end
			end
			WRITE_RAM: begin // second half of ctrl_wr_ram_data
				// if (ctrl_s_axis_tvalid) begin
					ctrl_wr_ram_en <= 1'b0;
					ctrl_ram_state <= WAIT_FIRST_PKT;
					// if (ctrl_s_axis_tlast) 
					// 	ctrl_ram_state <= WAIT_FIRST_PKT;
					// else
					// 	ctrl_ram_state <= FLUSH_REST_C;
				// end
			end
			FLUSH_REST_C: begin
				ctrl_wr_ram_en <= 1'b0;
				if (ctrl_s_axis_tvalid && ctrl_s_axis_tlast) begin
					ctrl_ram_state <= WAIT_FIRST_PKT;
				end
				else 
					ctrl_ram_state <= FLUSH_REST_C;

			end
		endcase
	end
end

//====================该段工程将非本配置模块的控制信号输出=======================
//该输出跳转状态机没有考虑控制报文连续发出的问题，这个问题暂时不考虑
reg [2:0] ctrl_data_o_state;
localparam CTRL_O_IDLE  = 0,
		   CTRL_O_JUDGE = 1,
		   CTRL_O_FLUSH = 2,
		   CTRL_O_STAY  = 3;
always @(posedge axis_clk) begin
    if(!aresetn) begin
        ctrl_m_axis_tdata  <= 0 ;
        ctrl_m_axis_tuser  <= 0 ;
        ctrl_m_axis_tkeep  <= 0 ;
        ctrl_m_axis_tvalid <= 0 ;
        ctrl_m_axis_tlast  <= 0 ;
		ctrl_data_o_state  <= CTRL_O_JUDGE;
    end
    else begin
		case(ctrl_data_o_state)
			CTRL_O_JUDGE:begin
				if(ctrl_s_axis_tvalid) begin
					if( parser_mod_id == PARSER_MOD_ID) begin //如果是该模块的配置报文，则不输出
        			    ctrl_m_axis_tdata  <= 0 ;
        			    ctrl_m_axis_tuser  <= 0 ;
        			    ctrl_m_axis_tkeep  <= 0 ;
        			    ctrl_m_axis_tvalid <= 0 ;
        			    ctrl_m_axis_tlast  <= 0 ;
						ctrl_data_o_state  <= CTRL_O_STAY ;
        			end
        			else begin
        			    ctrl_m_axis_tdata  <= ctrl_s_axis_tdata  ; //如果不是该模块的配置报文，则输出
        			    ctrl_m_axis_tuser  <= ctrl_s_axis_tuser  ;
        			    ctrl_m_axis_tkeep  <= ctrl_s_axis_tkeep  ;
        			    ctrl_m_axis_tvalid <= ctrl_s_axis_tvalid ;
        			    ctrl_m_axis_tlast  <= ctrl_s_axis_tlast  ;
						ctrl_data_o_state <= CTRL_O_FLUSH;
        			end
				end
				else begin
					ctrl_data_o_state  <= CTRL_O_JUDGE ;
					ctrl_m_axis_tdata  <= ctrl_m_axis_tdata ;
					ctrl_m_axis_tuser  <= ctrl_m_axis_tuser ;
					ctrl_m_axis_tkeep  <= ctrl_m_axis_tkeep ;
					ctrl_m_axis_tvalid <= 0                 ;
					ctrl_m_axis_tlast  <= ctrl_m_axis_tlast ;
				end
			end
			CTRL_O_FLUSH:begin
				ctrl_m_axis_tdata  <= ctrl_s_axis_tdata  ; //如果不是该模块的配置报文，则输出
        		ctrl_m_axis_tuser  <= ctrl_s_axis_tuser  ;
        		ctrl_m_axis_tkeep  <= ctrl_s_axis_tkeep  ;
        		ctrl_m_axis_tvalid <= ctrl_s_axis_tvalid ;
        		ctrl_m_axis_tlast  <= ctrl_s_axis_tlast  ;
				if(ctrl_s_axis_tlast)begin
					ctrl_data_o_state  <= CTRL_O_JUDGE;
				end
				else begin
					ctrl_data_o_state  <= CTRL_O_FLUSH;
				end
			end
			CTRL_O_STAY:begin
				ctrl_m_axis_tdata  <= 0 ;
        		ctrl_m_axis_tuser  <= 0 ;
        		ctrl_m_axis_tkeep  <= 0 ;
        		ctrl_m_axis_tvalid <= 0 ;
        		ctrl_m_axis_tlast  <= 0 ;
				if(ctrl_s_axis_tlast)begin
					ctrl_data_o_state  <= CTRL_O_JUDGE;
				end
				else begin
					ctrl_data_o_state  <= CTRL_O_STAY;
				end
			end
		endcase
    end
end


// =============================================================== //
reg [8:0] r1_bram_parser_addrb ;
reg [8:0] r2_bram_parser_addrb ;
wire [8:0] addrb;
assign addrb = i_dp_tcam_match?{i_dp_tcam_match_addr}:9'h1ff;
always @(posedge axis_clk) begin
	if(!aresetn) begin
		r1_bram_parser_addrb <= 9'h0;
	end
	else begin
		if(i_dp_tcam_match)
			r1_bram_parser_addrb <= addrb;
		else
			r1_bram_parser_addrb <= r1_bram_parser_addrb;
	end
end

always @(posedge axis_clk) begin
	if(!aresetn) begin
		r2_bram_parser_addrb <= 9'h0;
		o_bram_parser_addrb  <= 9'h0;
	end
	else begin
		r2_bram_parser_addrb <= r1_bram_parser_addrb;
		o_bram_parser_addrb  <= r2_bram_parser_addrb;
	end
end
parse_act_ram_ip
parse_act_ram
(
	// write port
	.clka		(axis_clk),
	.addra		(ctrl_wr_ram_addr[8:0]),
	.dina		(ctrl_wr_ram_data),
	.ena		(1'b1),
	.wea		(ctrl_wr_ram_en),

	//
	.clkb		(axis_clk),
	.addrb		(addrb), // [NOTICE:] note that we may change due to little or big endian
	.doutb		(bram_parser),
	.enb		(1'b1) // always set to 1
);

reg r1_dp_tcam_match;
reg r2_dp_tcam_match;
always @(posedge axis_clk) begin
	if(!aresetn) begin
		r1_dp_tcam_match <= 0;
		r2_dp_tcam_match <= 0;
	end
	else begin
		r1_dp_tcam_match <= i_dp_tcam_match ;
		r2_dp_tcam_match <= r1_dp_tcam_match;
	end
end

reg r1_dp_tcam_match_end;
reg r2_dp_tcam_match_end;
always @(posedge axis_clk) begin
	if(!aresetn) begin
		r1_dp_tcam_match_end <= 0;
		r2_dp_tcam_match_end <= 0;
	end
	else begin
		r1_dp_tcam_match_end <= i_dp_tcam_match_end ;
		r2_dp_tcam_match_end <= r1_dp_tcam_match_end;
	end
end

always @(posedge axis_clk) begin
	if(!aresetn) begin
		o_bram_parser <= 0;
		o_bram_parser_valid <= 1'b0;
		o_bram_parser_end   <= 1'b0;
	end
	else if(r2_dp_tcam_match_end)begin//匹配之后，该信号会一直有效
		o_bram_parser <= bram_parser;
		o_bram_parser_valid <= r2_dp_tcam_match;
		o_bram_parser_end   <= 1'b1;
	end
	else begin
		o_bram_parser       <= o_bram_parser;
		o_bram_parser_valid <= 1'b0;
		o_bram_parser_end   <= 1'b0;
	end
end

//ila_4 ila_parser_bram_cfg(
//    .clk   (axis_clk        ),
    
//    .probe0(ctrl_ram_state  ),
//    .probe1(ctrl_wr_ram_data),
//    .probe2(ctrl_wr_ram_addr),
//    .probe3(parser_mod_id   )
    
//);

endmodule

