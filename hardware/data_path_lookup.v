`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/12/30 10:39:55
// Design Name: 
// Module Name: data_path_lookup
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
//功能实现：1.1024b字段协议解析，生成查找parser_table的TCAM-index索引
//功能实现：2.将来自过滤器的数据报文原路转发到parser_wait_segs阶段
//功能实现：3.将该模块的配置匹配报文进行解析
//功能实现：4.与该模块无关的控制报文直接转发出去
//对任意进来的字段都做提取，无论有没有匹配上

module data_path_lookup #(
	parameter C_S_AXIS_TDATA_WIDTH= 512,
	parameter SEG_ADDR = 2,
	parameter CFG_ORDER_NUM = 128,//how to solve the 6
	parameter CFG_S_ORDER_WID = 16
)(
    input          									 axis_clk                ,
    input          									 aresetn                 ,
 
	input     [7:0]                                  i_offset_byte           ,//前一步提取了偏移地址，影响读出的字节数
	input                                            i_offset_byte_valid     ,
	input                                            i_offset_byte_end       ,
	//in s_axis_path_data
	input [C_S_AXIS_TDATA_WIDTH-1:0]		         i_dp_segs_tdata         ,
	input 								             i_dp_segs_valid         ,//一段2048b截取结束
	input 								             i_dp_segs_wea           ,//一段内有效的4拍数据
	input [SEG_ADDR-1:0]				             i_dp_segs_addra         ,//前面截取的512b的0-3地址

	// in control path
	input 	[CFG_ORDER_NUM*CFG_S_ORDER_WID-1:0]      i_cfg_bit_info  		,
	input 				                             i_cfg_bit_updata		,

    output     [CFG_ORDER_NUM-1:0]                   o_dp_bit               ,
	output                                           o_dp_bit_valid         ,
	output     [CFG_ORDER_NUM-1:0]                   o_dp_bit_mask          ,
	output                                           o_dp_bit_end           ,

	output     [C_S_AXIS_TDATA_WIDTH-1:0]            o_dp_segs_tdata        ,
	output                                           o_dp_segs_valid        ,
	output                                           o_dp_segs_wea          ,
	output     [SEG_ADDR-1:0]                        o_dp_segs_addra        ,

	input                                            i_pkt_fifo_rden     

);
localparam GROUP = (CFG_ORDER_NUM-1)/4+1;
localparam DP_END_IDLE = 0,DP1 = 1;
reg [GROUP*64-1:0]r_cfg_bit_info;
reg r_cfg_bit_updata;
always @(posedge axis_clk)begin
	if(~aresetn) begin
		r_cfg_bit_info <= 0;
		r_cfg_bit_updata <= 0;
	end
	else if(i_cfg_bit_updata)begin
		r_cfg_bit_info <= i_cfg_bit_info;//为了方便处理，扩展寄存器位宽是4的倍数
		r_cfg_bit_updata <= 1'b1;
	end
	else begin
		r_cfg_bit_info <= r_cfg_bit_info;
		r_cfg_bit_updata <= 0;
	end
end

//让这里的报文与sub处理完之后的结果同出，使报文可以与输出同步
// //=====================wait data===================================
wire     [C_S_AXIS_TDATA_WIDTH-1:0] tdata_fifo         ;
// wire                             tvalid_fifo        ;
wire     [SEG_ADDR-1:0]             taddr_fifo         ;
reg   pkt_fifo_rd_en                       ;
assign o_dp_segs_tdata = tdata_fifo        ;
assign o_dp_segs_addra = taddr_fifo        ;
assign o_dp_segs_valid = (taddr_fifo == 3 && pkt_fifo_rd_en )?1'b1:1'b0       ;
assign o_dp_segs_wea   = pkt_fifo_rd_en    ;

always @(posedge axis_clk)begin
	if(~aresetn)
     	pkt_fifo_rd_en <= 1'b0;
	else if(i_pkt_fifo_rden)//因为这个是离散的过来
		pkt_fifo_rd_en <= 1   ;
	else if(taddr_fifo == 3)
		pkt_fifo_rd_en <= 0   ;
	else
		pkt_fifo_rd_en <= pkt_fifo_rd_en   ;
end



reg     [1:0]   	                r_seg_addr       	;//写入256b的地址
reg 	[C_S_AXIS_TDATA_WIDTH-1:0] 	r_seg_tdata			;
reg 			 	                r_seg_wea			;
reg                                 r_wait_seg_end      ;
wire                                pkt_fifo_empty      ;

//获得进入第二级的sub的1024bit字段
always @(posedge axis_clk) begin
	if(!aresetn)begin
		r_seg_addr     <= 2'd0  ;
		r_seg_tdata    <= 512'd0;
		r_seg_wea      <= 1'b0  ;
	end
	else begin
		if(i_dp_segs_addra < 3'd4 )begin
			r_seg_addr   <= i_dp_segs_addra;
			r_seg_tdata  <= i_dp_segs_tdata;
			r_seg_wea    <= i_dp_segs_wea  ;
		end
		else begin
			r_seg_addr     <= 0   ;
			r_seg_tdata    <= 0   ;
			r_seg_wea      <= 0   ;
		end
	end
end

fallthrough_small_fifo #(
	.WIDTH(C_S_AXIS_TDATA_WIDTH + 2),
	.MAX_DEPTH_BITS(5)
)
dpl_wait_segs_fifo
(
	.din									({r_seg_tdata,r_seg_addr}     ),
	.wr_en									(r_seg_wea                    ),
	.rd_en									(pkt_fifo_rd_en               ),
	.dout									({tdata_fifo,taddr_fifo}      ),
	.full									(                             ),
	.prog_full								(                             ),
	.nearly_full							(pkt_fifo_nearly_full         ),
	.empty									(pkt_fifo_empty               ),
	.reset									(~aresetn                     ),
	.clk									(axis_clk                     )
);


reg dp_end_state;

always @(posedge axis_clk) begin
	if(!aresetn)begin
		r_wait_seg_end <= 1'd0  ;
		dp_end_state   <= DP_END_IDLE  ;
	end
	else begin
		case(dp_end_state)
			DP_END_IDLE:begin
				r_wait_seg_end <= 1'b0;
				if(i_dp_segs_addra == 3'd1) 
					dp_end_state <= DP1;
				else 
					dp_end_state <= DP_END_IDLE;
			end
			DP1:begin
				if(i_dp_segs_addra == 3'd3) begin
					r_wait_seg_end <= 1'b1;
					dp_end_state <= DP_END_IDLE;
				end
				else begin
					r_wait_seg_end <= 1'b0;
					dp_end_state   <= DP1 ;
				end
			end
		endcase
	end
end


/*==============================extract logic==================================*/
//将配置报文和数据报文取出来预处理，1.由上位机直接设置固定这些指令（优先），2.数据报文命中这些指令
reg [63:0] r_cfg_bit_info_group    [GROUP-1:0];//将128b的提取配置信息分4个一组，每组64位信息，分32组
   
wire [3:0] bit_act_low             [GROUP-1:0];
wire 	   bit_act_low_valid       [GROUP-1:0];
wire [15:0]bit_o                   [GROUP-1:0];
wire [3:0] bit_mask                [GROUP-1:0];
wire       bit_o_end               [GROUP-1:0];
    
reg [3:0]  r_bit_act_low           [GROUP-1:0];
reg 	   r_bit_act_low_valid     [GROUP-1:0];
reg [15:0] r_bit                   [GROUP-1:0];
reg [3:0]  r_bit_mask              [GROUP-1:0];
reg        r_bit_end               [GROUP-1:0];

wire [GROUP-1:0] w_bit_out_valid;
wire [GROUP-1:0] w_bit_out;
wire [GROUP-1:0] w_bit_end;
wire [GROUP-1:0] w_bit_out_mask;

// reg [127:0] bit_seg_out_valid;
generate
	genvar index;
	for(index=0;index < GROUP;index = index+1)begin://将128条指令分为32组，每组解析四个指令，因为下一组数据可以提取需要4个周期
	sub_op
	//将128X8b数据分为32X32组
	always @(posedge axis_clk) begin
		if(!aresetn) begin
			r_cfg_bit_info_group[index ] <= 0;
		end
		else begin
			if(r_cfg_bit_updata)
				r_cfg_bit_info_group[index] <= {r_cfg_bit_info[(3*GROUP+index+1)*16-1:(3*GROUP+index)*16],r_cfg_bit_info[(2*GROUP+index+1)*16-1:(2*GROUP+index)*16],r_cfg_bit_info[(1*GROUP+index+1)*16-1:(GROUP+index)*16],r_cfg_bit_info[(index+1)*16-1:index*16]};
			else 
				r_cfg_bit_info_group[index ] <= r_cfg_bit_info_group[index ];
		end
	end

	sub0_bit #(
		.BIT_WIDTH    (16),
		.BIT_GROUP_NUM(4 ),
		.C_S_AXIS_TDATA_WIDTH(C_S_AXIS_TDATA_WIDTH)							
	)
	sub0_bit(
		.axis_clk           (axis_clk					),
		.aresetn            (aresetn 					),
	//in  
		.i_bit_bram         (r_cfg_bit_info_group[index]),//each sub0_parser only solve 2 index

		.i_offset_byte      (i_offset_byte              ),
        .i_offset_byte_valid(i_offset_byte_valid        ),
		.i_offset_byte_end  (i_offset_byte_end          ),

		.i_seg_tdata        (i_dp_segs_tdata      		),
		.i_seg_wea          (i_dp_segs_wea        		),
		.i_seg_addra        (i_dp_segs_addra     		),
		.i_wait_segs_end    (i_dp_segs_valid            ),//只能保留一拍
	//out
		.o_bit_act_low      (bit_act_low[index]      	),
		.o_bit_act_low_valid(bit_act_low_valid[index]	),
		.o_bit_8            (bit_o[index]            	),//8 bits
		.o_bit_end          (bit_o_end[index]           ),
		.o_bit_mask         (bit_mask[index]            )

	);

always @(posedge axis_clk) begin
	if(!aresetn) begin
		r_bit_act_low[index]       	<= 1'b0						;     
		r_bit_act_low_valid[index] 	<= 1'b0						;
		r_bit[index]               	<= 8'd0						; 
		r_bit_end[index]            <= 1'd0                     ;
		r_bit_mask[index]           <= 4'd0                     ;   

	end	
	else begin	
		r_bit_act_low[index]       	<= bit_act_low[index]		;     
		r_bit_act_low_valid[index] 	<= bit_act_low_valid[index]	;
		r_bit[index]               	<= bit_o[index]				; 
		r_bit_end[index]            <= bit_o_end[index]			;   
		r_bit_mask[index]           <= bit_mask[index]          ;
	end
end

//we need the same clk of the parse_act and pkts_hdr
	sub1_bit #(
	.SUB_PKTS_LEN (16),//输入第二级提取的长度
	.L_BIT_ACT_LEN(4 ),//输入对应的选择地址
	.O_BIT_LEN    (1 ) //提取输出长度
	)
	sub1_bit (
		.clk				(axis_clk					),
		.aresetn			(aresetn 					),

		.i_bit_act_valid	(r_bit_act_low_valid[index]	),
		.i_bit_act			(r_bit_act_low[index]		),
		.i_bit_hdr			(r_bit[index]				),//8bits
		.i_bit_end          (r_bit_end[index]           ),
		.i_bit_mask         (r_bit_mask[index]          ),

		.o_bit_out_valid	(w_bit_out_valid[index]		),
		.o_bit_out			(w_bit_out[index]			),
		.o_bit_end          (w_bit_end[index]           ),//4拍连续出
		.o_bit_mask         (w_bit_out_mask[index]      )
		// .o_bit_seg_valid    (bit_seg_out_valid[index])//we can get the val in 5 clk ,and each clk 4 parser
	);
	end

endgenerate

//这里原本是数据命中后组和输出提取的有效数据的状态机
//把读取数据逻辑放在这里是为了读取数据和输出一起，但是实际需求是，数据不管有没有提取都要输出
//所以pkt_fifo_vld就不能在这里
//同时因为刷新ram的限制，不能太快也不能太慢，所以这里的r_pkt_fifo_rd_en信号要重新设计
//有效的报文一直有效，无效的报文一直无效
localparam BIT_IDLE = 0,
		   BIT_1    = 1,
		   BIT_2    = 2,
		   BIT_3    = 3,
		   BIT_END  = 4;

reg [3:0] bit_o_state;
reg [4*GROUP-1:0] r_dp_bit      ;
reg 			  r_dp_bit_valid;
reg               r_dp_end      ;
always @(posedge axis_clk) begin
	if(!aresetn) begin
		r_dp_bit <= 0;
		r_dp_bit_valid <= 1'd0;
		bit_o_state <= BIT_IDLE;
		r_dp_end <= 1'b0;
	end
	else begin 
		case(bit_o_state)
			BIT_IDLE :begin
				r_dp_end <= 1'b0;
				if(w_bit_end[0] == 1'b1)begin
					r_dp_bit[GROUP-1:0]  <= w_bit_out;
					r_dp_bit_valid <= 0;
					bit_o_state <= BIT_1  ;
				end
				else begin
					r_dp_bit       <= r_dp_bit;
					r_dp_bit_valid <= 1'd0    ;
					bit_o_state <= BIT_IDLE   ;
				end
			end
			BIT_1:begin
				r_dp_end <= 1'b0;
				r_dp_bit[2*GROUP-1:GROUP]  <= w_bit_out;
				r_dp_bit_valid <= 1'd0;
				bit_o_state <= BIT_2  ;
			end
			BIT_2:begin
				r_dp_end <= 1'b0;
				r_dp_bit[3*GROUP-1:2*GROUP]  <= w_bit_out;
				r_dp_bit_valid <= 1'd0;
				bit_o_state <= BIT_3  ;
			end
			BIT_3:begin
				r_dp_end    <= 1'b1         ;
				r_dp_bit[4*GROUP-1:3*GROUP]  <= w_bit_out;
				bit_o_state <= BIT_IDLE     ;
				if(w_bit_out_valid[0])
					r_dp_bit_valid <= 1'd1  ;
				else
					r_dp_bit_valid <= 1'b0  ;
			end
		endcase
	end
end

//这里的总线保持不知道综合实现时候是否能过
assign  o_dp_bit_end = r_dp_end;
assign  o_dp_bit = r_dp_bit;
assign  o_dp_bit_valid = r_dp_bit_valid;
// always @(posedge axis_clk) begin
// 	if(~aresetn) begin
// 		o_dp_bit <= 0;
// 		o_dp_bit_valid <= 0;
// 		o_dp_bit_end       <= 0;
// 	end
// 	else if(r_dp_end) begin
// 		o_dp_bit_end       <= 1'b1;
// 		if(r_dp_bit_valid)begin
// 			o_dp_bit <= r_dp_bit;
// 			o_dp_bit_valid <= r_dp_end;
// 		end
// 		else begin
// 			o_dp_bit <= o_dp_bit;
// 			o_dp_bit_valid <= 1'b0;
// 		end
// 	end
// 	else begin
// 		o_dp_bit_end   <= 0;
// 		o_dp_bit       <= o_dp_bit;
// 		o_dp_bit_valid <= 1'b0;
// 	end
// end


endmodule
