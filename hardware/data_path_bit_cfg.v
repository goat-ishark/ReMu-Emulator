`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/01/10 09:33:28
// Design Name: 
// Module Name: data_path_bit_cfg
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
//原module写法问题：配置报文必须定长，且提取数据寄存器不能受参数可控，维护这两个部分

module data_path_bit_cfg #(
    parameter C_S_AXIS_TDATA_WIDTH  = 512 ,
    parameter C_S_AXIS_TUSER_WIDTH = 256 ,
    parameter CFG_ORDER_NUMBER   = 128 ,//由于后面的处理，这里设置为4的倍数
    parameter CFG_ORDER_WIDTH    = 16  ,
	parameter CFG_BIT_MOD_ID     = 15  ,
	parameter INIT_FILE          = 1
)(
    input axis_clk                                                    ,
    input aresetn                                                     ,

    input [C_S_AXIS_TDATA_WIDTH-1:0  ]            ctrl_s_axis_tdata      ,
    input [C_S_AXIS_TUSER_WIDTH-1:0 ]             ctrl_s_axis_tuser      ,
    input [C_S_AXIS_TDATA_WIDTH/8-1:0]            ctrl_s_axis_tkeep      ,
    input                                         ctrl_s_axis_tvalid     ,
    input                                         ctrl_s_axis_tlast      ,
        
    output reg [C_S_AXIS_TDATA_WIDTH-1:0  ]       ctrl_m_axis_tdata      ,
    output reg [C_S_AXIS_TUSER_WIDTH-1:0 ]        ctrl_m_axis_tuser      ,
    output reg [C_S_AXIS_TDATA_WIDTH/8-1:0]       ctrl_m_axis_tkeep      ,
    output reg                                    ctrl_m_axis_tvalid     ,
    output reg                                    ctrl_m_axis_tlast      ,

    output reg [CFG_ORDER_NUMBER*CFG_ORDER_WIDTH-1:0]   o_cfg_bit_info    ,
    output reg                                          o_cfg_bit_updata       

    );
// o_cfg_bit_info 0 1 0
// o_cfg_bit_updata 806080648080808480a3
generate 
	if(INIT_FILE) begin
		always @(posedge axis_clk)begin
			if(!aresetn) begin
				o_cfg_bit_info <= 0;
				o_cfg_bit_updata <= 0;
			end
			else begin
				o_cfg_bit_info <= 80'h806080648080808480a3;
				o_cfg_bit_updata <= 1;
			end
		end
		always @(posedge axis_clk) begin
			if(!aresetn) begin
				ctrl_m_axis_tdata  <= 0; 
				ctrl_m_axis_tuser  <= 0;
				ctrl_m_axis_tkeep  <= 0;
				ctrl_m_axis_tvalid <= 0;
				ctrl_m_axis_tlast  <= 0;
			end
			else begin
				ctrl_m_axis_tdata  <= ctrl_s_axis_tdata ;
				ctrl_m_axis_tuser  <= ctrl_s_axis_tuser ;
				ctrl_m_axis_tkeep  <= ctrl_s_axis_tkeep ;
				ctrl_m_axis_tvalid <= ctrl_s_axis_tvalid;
				ctrl_m_axis_tlast  <= ctrl_s_axis_tlast ;
			end
		end
	end
	else begin
		//根据设计的参数，得到应该提取的指令条数，知道提取状态机走几拍
		reg [4:0] pkt_seg;
		always @(posedge axis_clk)begin
			if(!aresetn)begin
				pkt_seg <= 5'd0;
			end
			else begin
				if(CFG_ORDER_NUMBER <= 16)
					pkt_seg <= 5'd1;
				else if((CFG_ORDER_NUMBER > 16)&&(CFG_ORDER_NUMBER <=32))
					pkt_seg <= 5'd2;
				else if((CFG_ORDER_NUMBER > 32)&&(CFG_ORDER_NUMBER <= 48))
					pkt_seg <= 5'd3;
				else if((CFG_ORDER_NUMBER > 48)&&(CFG_ORDER_NUMBER <= 64))
					pkt_seg <= 5'd4;
				else if((CFG_ORDER_NUMBER > 64)&&(CFG_ORDER_NUMBER <= 80))
					pkt_seg <= 5'd5;
				else if((CFG_ORDER_NUMBER > 80)&&(CFG_ORDER_NUMBER <= 96))
					pkt_seg <= 5'd6;
				else if((CFG_ORDER_NUMBER > 96)&&(CFG_ORDER_NUMBER <= 112))
					pkt_seg <= 5'd7;
				else if((CFG_ORDER_NUMBER > 112)&&(CFG_ORDER_NUMBER <= 128))
					pkt_seg <= 5'd8;
				else 
					pkt_seg <= 5'd0;
			end
		end

		    /*================Control Path====================*/
		//接收控制报文2048b，16X128条指令

		wire [C_S_AXIS_TDATA_WIDTH-1:0]	ctrl_s_axis_tdata_swapped;
		//控制报文需要一次性倒换，倒完之后再按单条指令的位置做截取，一般按顺序算的话，倒完之后优先取高位作为指令的第一条
		// assign ctrl_s_axis_tdata_swapped = {	ctrl_s_axis_tdata[0  +:8],      //[255:248]
		// 										ctrl_s_axis_tdata[8  +:8],		//[247:240]
		// 										ctrl_s_axis_tdata[16 +:8],		//[239:232]
		// 										ctrl_s_axis_tdata[24 +:8],		//[231:224]
		// 										ctrl_s_axis_tdata[32 +:8],		//[223:216]
		// 										ctrl_s_axis_tdata[40 +:8],		//[215:208]
		// 										ctrl_s_axis_tdata[48 +:8],		//[207:200]
		// 										ctrl_s_axis_tdata[56 +:8],		//[199:192]
		// 										ctrl_s_axis_tdata[64 +:8],		//[191:184]
		// 										ctrl_s_axis_tdata[72 +:8],		//[183:176]
		// 										ctrl_s_axis_tdata[80 +:8],		//[175:168]
		// 										ctrl_s_axis_tdata[88 +:8],		//[167:160]
		// 										ctrl_s_axis_tdata[96 +:8],		//[159:152]
		// 										ctrl_s_axis_tdata[104+:8],		//[151:144]
		// 										ctrl_s_axis_tdata[112+:8],		//[143:136]
		// 										ctrl_s_axis_tdata[120+:8],		//[135:128]
		// 										ctrl_s_axis_tdata[128+:8],		//[127:120]
		// 										ctrl_s_axis_tdata[136+:8],		//[119:112]
		// 										ctrl_s_axis_tdata[144+:8],		//[111:104]
		// 										ctrl_s_axis_tdata[152+:8],		//[103:96 ]
		// 										ctrl_s_axis_tdata[160+:8],		//[95 :88 ]
		// 										ctrl_s_axis_tdata[168+:8],		//[87 :80 ]
		// 										ctrl_s_axis_tdata[176+:8],		//[79 :72 ]
		// 										ctrl_s_axis_tdata[184+:8],		//[71 :64 ]
		// 										ctrl_s_axis_tdata[192+:8],		//[63 :56 ]
		// 										ctrl_s_axis_tdata[200+:8],		//[55 :48 ]
		// 										ctrl_s_axis_tdata[208+:8],		//[47 :40 ]
		// 										ctrl_s_axis_tdata[216+:8],		//[39 :32 ]
		// 										ctrl_s_axis_tdata[224+:8],		//[31 :24 ]
		// 										ctrl_s_axis_tdata[232+:8],		//[23 :16 ]
		// 										ctrl_s_axis_tdata[240+:8],		//[15 :08 ]
		// 										ctrl_s_axis_tdata[248+:8]};		//[07 :00 ]

		//因为这里按字节倒数据，所以这样
		assign ctrl_s_axis_tdata_swapped ={
										   ctrl_s_axis_tdata[247:240],
										   ctrl_s_axis_tdata[255:248],
										   ctrl_s_axis_tdata[231:224],
										   ctrl_s_axis_tdata[239:232],
										   ctrl_s_axis_tdata[215:208],
										   ctrl_s_axis_tdata[223:216],
										   ctrl_s_axis_tdata[199:192],
										   ctrl_s_axis_tdata[207:200],
										   ctrl_s_axis_tdata[183:176],
										   ctrl_s_axis_tdata[191:184],
										   ctrl_s_axis_tdata[167:160],
										   ctrl_s_axis_tdata[175:168],
										   ctrl_s_axis_tdata[151:144],
										   ctrl_s_axis_tdata[159:152], 
										   ctrl_s_axis_tdata[135:128],
										   ctrl_s_axis_tdata[143:136],
										   ctrl_s_axis_tdata[119:112],
										   ctrl_s_axis_tdata[127:120],
										   ctrl_s_axis_tdata[103:96 ],
										   ctrl_s_axis_tdata[111:104],
										   ctrl_s_axis_tdata[87 :80 ],
										   ctrl_s_axis_tdata[95 :88 ],
										   ctrl_s_axis_tdata[71 :64 ],
										   ctrl_s_axis_tdata[79 :72 ],
										   ctrl_s_axis_tdata[55 :48 ],
										   ctrl_s_axis_tdata[63 :56 ],
										   ctrl_s_axis_tdata[39 :32 ],
										   ctrl_s_axis_tdata[47 :40 ],
										   ctrl_s_axis_tdata[23 :16 ],
										   ctrl_s_axis_tdata[31 :24 ],
										   ctrl_s_axis_tdata[7  : 0 ],
										   ctrl_s_axis_tdata[15 : 8 ]
										};


		wire [3:0] data_path_lk_id;//标识的是一整段报文
		reg [2047:0] r_cfg_bit_info; //12x128,加一个数据有效指示，作为TCAM查找的掩码
		reg 		 r_cfg_bit_updata;//配置更新

		always @(posedge axis_clk)begin
			if(!aresetn) begin
				o_cfg_bit_info <= 0;
				o_cfg_bit_updata <= 0;
			end
			else begin
				case(pkt_seg)
					5'd1: 
						o_cfg_bit_info <= r_cfg_bit_info;//只有一段报文，最后一个状态
					5'd2:
						o_cfg_bit_info <= r_cfg_bit_info;
					5'd3:
						o_cfg_bit_info <= r_cfg_bit_info;
					5'd4:
						o_cfg_bit_info <= r_cfg_bit_info;
					5'd5:
						o_cfg_bit_info <= r_cfg_bit_info;
					5'd6:
						o_cfg_bit_info <= r_cfg_bit_info;
					5'd7:
						o_cfg_bit_info <= r_cfg_bit_info;
					5'd8:
						o_cfg_bit_info <= r_cfg_bit_info;
					default:
						o_cfg_bit_info <= 0;//超出解析提取范围的报文，不做处理了
				endcase
				o_cfg_bit_updata <= r_cfg_bit_updata;
			end
		end

		//256位第二段的112+4,在512位是什么位置
		assign data_path_lk_id = ctrl_s_axis_tdata[368+:4];//查找数据路径提取配置报文
		reg [3:0] ctrl_state;
		localparam HEADER_PKT1    = 0,
		           HEADER_PKT2    = 1,
		           BUFFER_FI_PKT  = 2,
		           BUFFER_SE_PKT  = 3,
		           BUFFER_TH_PKT  = 4, 
		           BUFFER_FO_PKT  = 5,
		           BUFFER_FRI_PKT = 6,
				   BUFFER_SIX_PKT = 7,
				   BUFFER_SEV_PKT = 8,
				   BUFFER_EIG_PKT = 9,
		           FLUSH_REST_C   = 10;

		always @(posedge axis_clk) begin
			if(!aresetn) begin
				r_cfg_bit_info <= 2048'd0;
		        r_cfg_bit_updata <= 1'b0;
				ctrl_state <= HEADER_PKT1;
			end
			else begin
				case(ctrl_state)
					HEADER_PKT1:begin
						r_cfg_bit_updata <= 1'b0;
						if(ctrl_s_axis_tvalid) begin
							if(data_path_lk_id == CFG_BIT_MOD_ID) begin//找到配置数据路径提取报文的关键字，启动计数
								r_cfg_bit_info <= 2048'd0;
								ctrl_state <= BUFFER_FI_PKT;
							end
							else begin//1.没有启动时候配置值为0，启动之后配置值保持，等待二次配置
								ctrl_state <= FLUSH_REST_C;
								r_cfg_bit_info <= r_cfg_bit_info;
							end
						end
						else begin //报文没进来过，2.报文返回了一次但是没配置下一次
							ctrl_state <= HEADER_PKT1;
							r_cfg_bit_info <= r_cfg_bit_info;
						end
					end
					BUFFER_FI_PKT:begin
						if(ctrl_s_axis_tvalid) begin
							r_cfg_bit_info[255:0] <= ctrl_s_axis_tdata_swapped;//0-15
							if(pkt_seg == 1) begin //在预估只有一段报文的条件下
								if(ctrl_s_axis_tlast) begin//结束，报文正确
									r_cfg_bit_updata <= 1'b1 ;
									ctrl_state <= HEADER_PKT1;
								end
								else begin//没有结束，报文错误
									ctrl_state <= FLUSH_REST_C;//校验失败，报文错误
									r_cfg_bit_updata <= 1'b0  ;
								end
							end
							else begin //继续接下一段报文
								ctrl_state <= BUFFER_SE_PKT;
								r_cfg_bit_updata <= 1'b0   ;
							end
						end
						else begin //报文还没有来
							r_cfg_bit_updata <= 1'b0 ;
							r_cfg_bit_info <= r_cfg_bit_info;
							ctrl_state <= BUFFER_FI_PKT;
						end
					end
					BUFFER_SE_PKT:begin
						if(ctrl_s_axis_tvalid) begin
							r_cfg_bit_info[511:256] <= ctrl_s_axis_tdata_swapped;//0-15
							if(pkt_seg == 2) begin //在预估只有一段报文的条件下
								if(ctrl_s_axis_tlast) begin//结束，报文正确
									r_cfg_bit_updata <= 1'b1 ;
									ctrl_state <= HEADER_PKT1;
								end
								else begin//没有结束，报文错误
									ctrl_state <= FLUSH_REST_C;//校验失败，报文错误
									r_cfg_bit_updata <= 1'b0  ;
								end
							end
							else begin //继续接下一段报文
								ctrl_state <= BUFFER_TH_PKT;
								r_cfg_bit_updata <= 1'b0   ;
							end
						end
						else begin //报文还没有来
							r_cfg_bit_updata <= 1'b0 ;
							r_cfg_bit_info <= r_cfg_bit_info;
							ctrl_state <= BUFFER_SE_PKT;
						end
					end
					BUFFER_TH_PKT:begin
						if(ctrl_s_axis_tvalid) begin
							r_cfg_bit_info[767:512] <= ctrl_s_axis_tdata_swapped;//0-15
							if(pkt_seg == 3) begin //在预估只有一段报文的条件下
								if(ctrl_s_axis_tlast) begin//结束，报文正确
									r_cfg_bit_updata <= 1'b1 ;
									ctrl_state <= HEADER_PKT1;
								end
								else begin//没有结束，报文错误
									ctrl_state <= FLUSH_REST_C;//校验失败，报文错误
									r_cfg_bit_updata <= 1'b0  ;
								end
							end
							else begin //继续接下一段报文
								ctrl_state <= BUFFER_FO_PKT;
								r_cfg_bit_updata <= 1'b0   ;
							end
						end
						else begin //报文还没有来
							r_cfg_bit_updata <= 1'b0 ;
							r_cfg_bit_info <= r_cfg_bit_info;
							ctrl_state <= BUFFER_SE_PKT;
						end
					end
					BUFFER_FO_PKT:begin
						if(ctrl_s_axis_tvalid) begin
							r_cfg_bit_info[1023:768] <= ctrl_s_axis_tdata_swapped;//0-15
							if(pkt_seg == 4) begin //在预估只有一段报文的条件下
								if(ctrl_s_axis_tlast) begin//结束，报文正确
									r_cfg_bit_updata <= 1'b1 ;
									ctrl_state <= HEADER_PKT1;
								end
								else begin//没有结束，报文错误
									ctrl_state <= FLUSH_REST_C;//校验失败，报文错误
									r_cfg_bit_updata <= 1'b0  ;
								end
							end
							else begin //继续接下一段报文
								ctrl_state <= BUFFER_FRI_PKT;
								r_cfg_bit_updata <= 1'b0   ;
							end
						end
						else begin //报文还没有来
							r_cfg_bit_updata <= 1'b0 ;
							r_cfg_bit_info <= r_cfg_bit_info;
							ctrl_state <= BUFFER_FO_PKT;
						end
					end
					BUFFER_FRI_PKT:begin //由上位机下发只有该固定格式的配置报文
						if(ctrl_s_axis_tvalid) begin
							r_cfg_bit_info[1279:1024] <= ctrl_s_axis_tdata_swapped;//0-15
							if(pkt_seg == 5) begin //在预估只有一段报文的条件下
								if(ctrl_s_axis_tlast) begin//结束，报文正确
									r_cfg_bit_updata <= 1'b1 ;
									ctrl_state <= HEADER_PKT1;
								end
								else begin//没有结束，报文错误
									ctrl_state <= FLUSH_REST_C;//校验失败，报文错误
									r_cfg_bit_updata <= 1'b0  ;
								end
							end
							else begin //继续接下一段报文
								ctrl_state <= BUFFER_SIX_PKT;
								r_cfg_bit_updata <= 1'b0   ;
							end
						end
						else begin //报文还没有来
							r_cfg_bit_updata <= 1'b0 ;
							r_cfg_bit_info <= r_cfg_bit_info;
							ctrl_state <= BUFFER_FRI_PKT;
						end
					end
					BUFFER_SIX_PKT:begin
						if(ctrl_s_axis_tvalid) begin
							r_cfg_bit_info[1535:1280] <= ctrl_s_axis_tdata_swapped;//0-15
							if(pkt_seg == 6) begin //在预估只有一段报文的条件下
								if(ctrl_s_axis_tlast) begin//结束，报文正确
									r_cfg_bit_updata <= 1'b1 ;
									ctrl_state <= HEADER_PKT1;
								end
								else begin//没有结束，报文错误
									ctrl_state <= FLUSH_REST_C;//校验失败，报文错误
									r_cfg_bit_updata <= 1'b0  ;
								end
							end
							else begin //继续接下一段报文
								ctrl_state <= BUFFER_SEV_PKT;
								r_cfg_bit_updata <= 1'b0   ;
							end
						end
						else begin //报文还没有来
							r_cfg_bit_updata <= 1'b0 ;
							r_cfg_bit_info <= r_cfg_bit_info;
							ctrl_state <= BUFFER_SIX_PKT;
						end
					end
					BUFFER_SEV_PKT:begin //由上位机下发只有该固定格式的配置报文
						if(ctrl_s_axis_tvalid) begin
							r_cfg_bit_info[1791:1536] <= ctrl_s_axis_tdata_swapped;//0-15
							if(pkt_seg == 7) begin //在预估只有一段报文的条件下
								if(ctrl_s_axis_tlast) begin//结束，报文正确
									r_cfg_bit_updata <= 1'b1 ;
									ctrl_state <= HEADER_PKT1;
								end
								else begin//没有结束，报文错误
									ctrl_state <= FLUSH_REST_C;//校验失败，报文错误
									r_cfg_bit_updata <= 1'b0  ;
								end
							end
							else begin //继续接下一段报文
								ctrl_state <= BUFFER_EIG_PKT;
								r_cfg_bit_updata <= 1'b0   ;
							end
						end
						else begin //报文还没有来
							r_cfg_bit_updata <= 1'b0 ;
							r_cfg_bit_info <= r_cfg_bit_info;
							ctrl_state <= BUFFER_SEV_PKT;
						end
					end
					BUFFER_EIG_PKT:begin //由上位机下发只有该固定格式的配置报文
						if(ctrl_s_axis_tvalid) begin
							r_cfg_bit_info[2047:1792] <= ctrl_s_axis_tdata_swapped;//0-15
							if(pkt_seg == 8) begin //在预估只有一段报文的条件下
								if(ctrl_s_axis_tlast) begin//结束，报文正确
									r_cfg_bit_updata <= 1'b1 ;
									ctrl_state <= HEADER_PKT1;
								end
								else begin//没有结束，报文错误
									ctrl_state <= FLUSH_REST_C;//校验失败，报文错误
									r_cfg_bit_updata <= 1'b0  ;
								end
							end
							else begin //继续接下一段报文
								ctrl_state <= FLUSH_REST_C ;//不是8段以内的数据也是错的
								r_cfg_bit_updata <= 1'b0   ;
							end
						end
						else begin //报文还没有来
							r_cfg_bit_updata <= 1'b0 ;
							r_cfg_bit_info <= r_cfg_bit_info;
							ctrl_state <= BUFFER_EIG_PKT;
						end
					end
					FLUSH_REST_C:begin
						r_cfg_bit_info <= r_cfg_bit_info;//配置报文数据格式不对，寄存器处理清零
						r_cfg_bit_updata <= 0;
						if(ctrl_s_axis_tlast)
							ctrl_state <= HEADER_PKT1;
						else
							ctrl_state <= FLUSH_REST_C;
					end
				endcase
			end
		end
		//这个状态机的写法可以优化，状态重复判别

		reg [2:0] ctrl_data_o_state;
		localparam CTRL_O_IDLE  = 0,//512位不用缓存等一拍做判别
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
							if(data_path_lk_id == CFG_BIT_MOD_ID) begin //如果是该模块的配置报文，则不输出
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
								ctrl_data_o_state  <= CTRL_O_FLUSH       ;
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
	end
endgenerate

endmodule
