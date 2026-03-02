`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/01/10 09:30:03
// Design Name: 
// Module Name: data_path_tcam_cfg
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
//该模块提取配置到tcam模块里的数据,单个TCAM配置的最大深度是256/16，以16b为宽度做配置，最大允许配置2048b的数据
//三拍，来的及
module data_path_tcam_cfg#(
    parameter C_S_AXIS_TDATA_WIDTH = 512 ,
    parameter C_S_AXIS_TUSER_WIDTH = 256 ,
	parameter C_S_AXIS_TKEEP_WIDTH = 64  ,
    parameter FEATURE_BIT_WIDTH    = 128 ,
    parameter TCAM_MATCH_ADDR      = 5   ,
	parameter TCAM_DEPTH           = 32  ,
	parameter CFG_TCAM_MOD_ID      = 8   ,
	parameter INIT_FILE            = 1
)(
    input                 axis_clk,
    input                 aresetn ,

    input [C_S_AXIS_TDATA_WIDTH-1:0]            ctrl_s_axis_tdata      ,
    input [C_S_AXIS_TUSER_WIDTH-1:0]            ctrl_s_axis_tuser      ,
    input [C_S_AXIS_TKEEP_WIDTH-1:0]            ctrl_s_axis_tkeep      ,
    input                                       ctrl_s_axis_tvalid     ,
    input                                       ctrl_s_axis_tlast      ,
        
    output reg [C_S_AXIS_TDATA_WIDTH-1:0  ]       ctrl_m_axis_tdata      ,
    output reg [C_S_AXIS_TUSER_WIDTH-1:0 ]       ctrl_m_axis_tuser      ,
    output reg [C_S_AXIS_TKEEP_WIDTH-1:0]       ctrl_m_axis_tkeep      ,
    output reg                                 ctrl_m_axis_tvalid     ,
    output reg                                 ctrl_m_axis_tlast      ,

    input [FEATURE_BIT_WIDTH-1:0]              i_dp_bit               ,             
    input                                      i_dp_bit_valid         ,   
	input [FEATURE_BIT_WIDTH-1:0]              i_dp_bit_mask          ,
	input                                      i_dp_bit_end           ,
// out      
    output  reg                                o_dp_tcam_match        ,
    output  reg    [TCAM_MATCH_ADDR-1:0]       o_dp_tcam_match_addr   ,
	output  reg                                o_dp_tcam_match_end    , //指示匹配结束
	
	output reg                                 o_pkt_rden            
);

//=====================Data Path====================================
localparam TCAM_BIT_WIDTH = (FEATURE_BIT_WIDTH-1)/16+1 ; //tcam的宽度设置以16为基本
reg [TCAM_BIT_WIDTH*16-1:0]  r_path_bit    ;             //按16的整数倍设置
reg                          r_path_bit_vld;
reg                          match_sample     ;  //对匹配结果进行采样
reg [1:0]                    cmp_state        ;
reg                          idle_match       ; //如果输入信号是无效的，那么就是空匹配状态

always @(posedge axis_clk) begin
    if(!aresetn) begin
        r_path_bit		<= 0         ;
        r_path_bit_vld  <= 1'd0      ;
		cmp_state       <= 3'd0      ;
		idle_match      <= 0         ;
    end  
    else begin
		case(cmp_state)
			0: begin //传入数据给tcam匹配
				o_pkt_rden          <= 0; 
				o_dp_tcam_match_end <= 1'b0;
				match_sample <= 0;
				if(i_dp_bit_end) begin //在有数据输入时启动匹配
					if(i_dp_bit_valid)begin  
						r_path_bit		<= i_dp_bit  ;
        				r_path_bit_vld  <= 1'd1      ;
						cmp_state       <= 2'd1      ;//有有效数据进行匹配时对数据匹配结果进行采样
						idle_match      <= 0         ;
    				end
					else begin
						cmp_state       <= 2'd1      ;//无有效数据进行匹配时，不对采样结果进行采样
						r_path_bit		<= 128'hffffffffffffff  ;
        				r_path_bit_vld  <= 1'd0      ;
						idle_match      <= 1         ;
					end
				end
    			else begin
        			r_path_bit		<= 128'hffffffffffffffff;//如果非进行tcam查找的数据，让数据输出错误
        			r_path_bit_vld  <= 1'd0      ;
					cmp_state       <= 2'd0      ;
					idle_match      <= 0         ;
    			end
			end
			1:begin //匹配中
				o_dp_tcam_match_end <= 1'b0;
				cmp_state <= 2'd2;
				r_path_bit_vld  <= 1'd0      ;
				r_path_bit		<= 128'hffffffffffffffff;
				o_pkt_rden      <= 1'b1      ;
				if(idle_match)
					match_sample       <= 1'b0;
				else 
					match_sample       <= 1'b1;
			end
			2:begin //匹配结果输出
				idle_match          <= 0;
				o_pkt_rden          <= 0;
				o_dp_tcam_match_end <= 1'b1;
				match_sample <= 1'b0;
				cmp_state <= 2'd3;
				r_path_bit_vld  <= 1'd0      ;
				r_path_bit		<= 128'hffffffffffffffff;
			end
			3:begin
				o_pkt_rden          <= 0;
				idle_match          <= 0;
				o_dp_tcam_match_end <= 1'b0;
				match_sample <= 1'b0;
				if(o_dp_tcam_match) begin
					r_path_bit		<= 128'hffffffffffffffff;//如果非进行tcam查找的数据，让数据输出错误
        			r_path_bit_vld  <= 1'd0      ;
					cmp_state       <= 2'd0      ;
				end
				else begin
					cmp_state       <= 2'd0      ;//如果一次匹配之后没有匹配上
				end
			end
		endcase
	
	end
end

/*================Control Path====================*/
//接收控制报文1536b，12X128条指令
    //=================ctrl path cfg tcam ===============================
//配置32条，128b的tcam及掩码，再加上地址信息8位(有效取5位，可扩展至8位，还是自己加1作为索引？)
//120b由上位机决定的掩码，8b可以由上位机决定tcam的地址在哪里，低位一定是要做提取比对的位，所以就设为常数
//数据报文一会大端，一会小端的不好，所以进行统一之后好一些
//写状态机的话，会写32个，1024个字节，足够用
//32的设置看一个环境内有多少种协议路径，每种协议路径有多少中掩码组合？
//设置两个TCAM,将256b数据拆分，查找出的地址最高位作为区分

wire [C_S_AXIS_TDATA_WIDTH-1:0]	ctrl_s_axis_tdata_swapped;
//控制报文需要一次性倒换，倒完之后再按单条指令的位置做截取，一般按顺序算的话，倒完之后优先取高位作为指令的第一条
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
										ctrl_s_axis_tdata[248+:8],
										ctrl_s_axis_tdata[256+:8],      
										ctrl_s_axis_tdata[264+:8],		
										ctrl_s_axis_tdata[272+:8],		
										ctrl_s_axis_tdata[280+:8],		
										ctrl_s_axis_tdata[288+:8],		
										ctrl_s_axis_tdata[296+:8],		
										ctrl_s_axis_tdata[304+:8],		
										ctrl_s_axis_tdata[312+:8],		
										ctrl_s_axis_tdata[320+:8],		
										ctrl_s_axis_tdata[328+:8],		
										ctrl_s_axis_tdata[336+:8],		
										ctrl_s_axis_tdata[344+:8],		
										ctrl_s_axis_tdata[352+:8],		
										ctrl_s_axis_tdata[360+:8],		
										ctrl_s_axis_tdata[368+:8],		
										ctrl_s_axis_tdata[376+:8],		
										ctrl_s_axis_tdata[384+:8],		
										ctrl_s_axis_tdata[392+:8],		
										ctrl_s_axis_tdata[400+:8],		
										ctrl_s_axis_tdata[408+:8],		
										ctrl_s_axis_tdata[416+:8],		
										ctrl_s_axis_tdata[424+:8],		
										ctrl_s_axis_tdata[432+:8],		
										ctrl_s_axis_tdata[440+:8],		
										ctrl_s_axis_tdata[448+:8],		
										ctrl_s_axis_tdata[456+:8],		
										ctrl_s_axis_tdata[464+:8],		
										ctrl_s_axis_tdata[472+:8],		
										ctrl_s_axis_tdata[480+:8],		
										ctrl_s_axis_tdata[488+:8],		
										ctrl_s_axis_tdata[496+:8],		
										ctrl_s_axis_tdata[504+:8]       
									};		

//方案拟定：1.256b进,在没有缓冲的情况下，两个TCAM各载入128b,深度减半
//        2.第一拍数据载入mask掩码，后面的数据载入din端
reg [TCAM_BIT_WIDTH*16-1:0] r_cam_mask ;

wire [3:0] data_path_tcam_id;

assign data_path_tcam_id = ctrl_s_axis_tdata[368+:4];

reg 	r_tcam_data_vld;
always @(posedge axis_clk) begin
	if(!aresetn) begin
		r_tcam_data_vld <= 1'b0; 
	end
	else if(data_path_tcam_id == CFG_TCAM_MOD_ID)
		r_tcam_data_vld <= 1'b1;
	else if(ctrl_s_axis_tlast)
		r_tcam_data_vld <= 1'b0;
	else 
		r_tcam_data_vld <= r_tcam_data_vld;
end
reg [4  :0] ctrl_fifo_state;
localparam TCAM_FIFO_IDLE= 0 ;
localparam BUFFER_MASK   = 1 ;
localparam BUFFER_TCAM   = 2 ;
localparam FLUSH_REST_C  = 3 ;

reg [C_S_AXIS_TDATA_WIDTH-1:0] r_fifo_tdata     ;
reg         				r_fifo_tvalid    ;
reg         				r_fifo_tlast     ;
reg [3:0]   				r_fifo_tcam_addr ;
//因为不明确TCAM的busy信号是什么时候拉高，
//所以这里对ctrl信号做一个fifo缓存，当busy有效时候，从fifo读取控制报文
//判别有效数据进入FIFO
always @(posedge axis_clk) begin
	if(!aresetn) begin
		r_fifo_tdata    <= 512'd0;
		r_fifo_tvalid   <= 1'b0  ;
		r_fifo_tlast    <= 1'b0  ;
		ctrl_fifo_state <= TCAM_FIFO_IDLE;
		r_cam_mask      <= 128'd0	;
	end
	else begin
		case(ctrl_fifo_state)
			TCAM_FIFO_IDLE:begin
				r_fifo_tdata  		<= 512'd0;
				r_fifo_tvalid 		<= 1'b0;
				r_fifo_tlast  		<= 1'b0;
				r_fifo_tcam_addr    <= 4'd0;
				if(ctrl_s_axis_tvalid) begin
					if(data_path_tcam_id == CFG_TCAM_MOD_ID) begin//找到配置数据路径提取报文的关键字，启动计数
						ctrl_fifo_state <= BUFFER_MASK;
					end
					else begin//1.没有启动时候配置值为0，启动之后配置值保持，等待二次配置
						ctrl_fifo_state <= TCAM_FIFO_IDLE;
					end
				end
				else begin //报文没进来过，2.报文返回了一次但是没配置下一次
					ctrl_fifo_state <= TCAM_FIFO_IDLE;
					r_cam_mask <= 128'd0		;
				end
			end
			BUFFER_MASK:begin
				if(ctrl_s_axis_tvalid) begin
					r_cam_mask       <= ctrl_s_axis_tdata_swapped[0+:TCAM_BIT_WIDTH*16];//从控制报文下发掩码
					ctrl_fifo_state  <= BUFFER_TCAM;
					r_fifo_tdata     <= 512'd0;
					r_fifo_tvalid    <= 1'b0;
					r_fifo_tlast     <= 1'b0;
					r_fifo_tcam_addr <= 4'd0;
				end
				else begin
					r_fifo_tdata     <= 512'd0;
					r_fifo_tvalid    <= 1'b0;
					r_fifo_tlast     <= 1'b0;
					r_fifo_tcam_addr <= 4'd0;
					ctrl_fifo_state <= BUFFER_MASK;
				end
			end
			BUFFER_TCAM:begin //由上位机下发只有该固定格式的配置报文,这里要不要判别预设深度和配置报文不一致的情况
				if(ctrl_s_axis_tvalid) begin
					r_fifo_tdata  <= ctrl_s_axis_tdata_swapped[511:0];
					r_fifo_tvalid <= 1'b1;
					r_fifo_tcam_addr <= r_fifo_tcam_addr+1'b1;
					if(ctrl_s_axis_tlast) begin
						ctrl_fifo_state <= TCAM_FIFO_IDLE;
						r_fifo_tlast  <= 1'b1;
					end
					else begin
						ctrl_fifo_state <= BUFFER_TCAM;
						r_fifo_tlast  <= 1'b0;
					end
				end
				else begin 
					r_fifo_tcam_addr <= r_fifo_tcam_addr;
					r_fifo_tdata  <= 512'd0;
					r_fifo_tvalid <= 1'b0;
					r_fifo_tlast  <= 1'b0;
					ctrl_fifo_state <= TCAM_FIFO_IDLE;
				end
			end
			FLUSH_REST_C:begin
				r_fifo_tdata  <= 512'd0;
				r_fifo_tvalid <= 1'b0;
				r_fifo_tlast  <= 1'b0;//配置报文数据格式不对，寄存器处理清零
				if(ctrl_s_axis_tlast)
					ctrl_fifo_state <= TCAM_FIFO_IDLE;
				else
					ctrl_fifo_state <= FLUSH_REST_C;
			end
		endcase
	end
end
wire [3:0] w_fifo_tcam_addr;
assign w_fifo_tcam_addr = (r_fifo_tcam_addr > 0)? r_fifo_tcam_addr-1:0;
wire [C_S_AXIS_TDATA_WIDTH-1:0]     c_data_tcam                ;

wire 					         c_axis_tlast               ;
wire [3:0]                       c_axis_tcam_addr           ;

wire                             c_data_fifo_nearly_full    ;
wire                             c_data_fifo_empty          ;
reg r_dp_tcam_busy;//从仿真看，这个信号没有按时序逻辑出，所以在输出时候最好进行寄存
fallthrough_small_fifo #(
	.WIDTH(517),
	.MAX_DEPTH_BITS(5)
)
data_path_tcam_cfg_fifo
(
	.din									({r_fifo_tdata,r_fifo_tlast,w_fifo_tcam_addr}),
	.wr_en									(r_fifo_tvalid ),
	.rd_en									(r_dp_tcam_busy),//在tcam忙的时候切换下一个信号
	.dout									({c_data_tcam,c_axis_tlast,c_axis_tcam_addr}),
	.full									(),
	.prog_full								(),
	.nearly_full							(),
	.empty									(c_data_fifo_empty),
	.reset									(~aresetn)         ,
	.clk									(axis_clk)
);

assign c_wr_en_cam =  !c_data_fifo_empty;//fifo有数据时候写入
 
wire [TCAM_BIT_WIDTH*16-1:0]     c_tcam_data          [16/TCAM_BIT_WIDTH-1:0];
//we use mode Block RAM-Based which need one cycle delay xapp1151 write operation
//tcam会延迟几拍出
//允许写入读出同时操作时，会出现边写进边匹配上数据，造成match拉高，而一旦match拉高，造成一系列逻辑问题
        // tcam1 for lookup
generate
	if(INIT_FILE == 0) begin
		wire [16/TCAM_BIT_WIDTH-1:0]		        w_dp_tcam_busy                                 ;
		wire [16/TCAM_BIT_WIDTH-1:0]		        w_dp_tcam_match                                ;
		wire [TCAM_MATCH_ADDR-1  :0] 	            w_dp_tcam_match_addr    [16/TCAM_BIT_WIDTH-1:0];
		genvar index;
		for(index=0;index<16/TCAM_BIT_WIDTH;index = index+1)begin://将256b按16位为基准得到cam配置的组
		cam_op
			assign c_tcam_data[index] = c_data_tcam[(C_S_AXIS_TDATA_WIDTH-16*TCAM_BIT_WIDTH*index)-1:C_S_AXIS_TDATA_WIDTH-16*TCAM_BIT_WIDTH*(index+1)];

    	    cam_top # ( 
    	        .C_DEPTH			(TCAM_DEPTH                  ),//TCAM_DEPTH/(256/C_WIDTH)
    	        .C_WIDTH			(TCAM_BIT_WIDTH*16           ),
    	        .C_MEM_INIT			(0	                         ),//不使用初始文件
    	        .C_MEM_INIT_FILE	("./init1.mif"               )
				//.C_ELABORATION_DIR  ("/home/tsh/Desktop/link_emulator_05171005/link_emulator_512_sim.xpr/link_emulator_sim/link_emulator_sim.srcs/sources_1/new/tcam")
    	    )		   
			//TODO remember to change it back.
    	    cam_datapath_lookup1
    	    (
    	        .CLK				(axis_clk				     ),
    	        .CMP_DIN			(r_path_bit				     ),//来自数据提取的128b有效字段
    	        .CMP_DATA_MASK		(            			     ),//来自数据提取的128b实际有效位
    	        .BUSY				(w_dp_tcam_busy[index]		 ),
    	        .MATCH				(w_dp_tcam_match[index]		 ),
    	        .MATCH_ADDR			(w_dp_tcam_match_addr[index] ),
	
    	        .WE                 (c_wr_en_cam                 ),//控制报文算好的128b数据
    	        .WR_ADDR            (c_axis_tcam_addr[3:0]       ),//由控制报文下发的5b的查找地址
    	        .DATA_MASK          (r_cam_mask			         ),//TODO do we need ternary matching?
    	        .DIN                (c_tcam_data[index]          ),//由控制报文下发的128b数据匹配路径
				.EN					(1'b1					     )
    	    );	

		end
		
		always @(posedge axis_clk) begin
			if(!aresetn) 
				r_dp_tcam_busy <= 1'b0;
			else
				r_dp_tcam_busy <= &w_dp_tcam_busy;
		end

		//把match给一个固定的位宽的寄存器
		//这里需要进行时序优化
		wire [15:0] w_match_switch;
		assign w_match_switch = (w_dp_tcam_match != 0)?w_dp_tcam_match:16'h00;//绝对不同的路径字段匹配
		//要写一个case语句判断哪个数据出，16选1
		always @(posedge axis_clk) begin
			if(!aresetn) begin
				o_dp_tcam_match_addr <= 5'h1f;
			end
			else if(match_sample) begin
				case (w_match_switch[15:0])
					16'h0001  : o_dp_tcam_match_addr <= w_dp_tcam_match_addr[0 ]*16/TCAM_BIT_WIDTH+0 ;
					16'h0002  : o_dp_tcam_match_addr <= w_dp_tcam_match_addr[1 ]*16/TCAM_BIT_WIDTH+1 ;
					16'h0004  : o_dp_tcam_match_addr <= w_dp_tcam_match_addr[2 ]*16/TCAM_BIT_WIDTH+2 ;
					16'h0008  : o_dp_tcam_match_addr <= w_dp_tcam_match_addr[3 ]*16/TCAM_BIT_WIDTH+3 ;
					16'h0010  : o_dp_tcam_match_addr <= w_dp_tcam_match_addr[4 ]*16/TCAM_BIT_WIDTH+4 ;
					16'h0020  : o_dp_tcam_match_addr <= w_dp_tcam_match_addr[5 ]*16/TCAM_BIT_WIDTH+5 ;
					16'h0040  : o_dp_tcam_match_addr <= w_dp_tcam_match_addr[6 ]*16/TCAM_BIT_WIDTH+6 ;
					16'h0080  : o_dp_tcam_match_addr <= w_dp_tcam_match_addr[7 ]*16/TCAM_BIT_WIDTH+7 ;
					16'h0100  : o_dp_tcam_match_addr <= w_dp_tcam_match_addr[8 ]*16/TCAM_BIT_WIDTH+8 ;
					16'h0200  : o_dp_tcam_match_addr <= w_dp_tcam_match_addr[9 ]*16/TCAM_BIT_WIDTH+9 ;
					16'h0400  : o_dp_tcam_match_addr <= w_dp_tcam_match_addr[10]*16/TCAM_BIT_WIDTH+10;
					16'h0800  : o_dp_tcam_match_addr <= w_dp_tcam_match_addr[11]*16/TCAM_BIT_WIDTH+11;
					16'h1000  : o_dp_tcam_match_addr <= w_dp_tcam_match_addr[12]*16/TCAM_BIT_WIDTH+12;
					16'h2000  : o_dp_tcam_match_addr <= w_dp_tcam_match_addr[13]*16/TCAM_BIT_WIDTH+13;
					16'h4000  : o_dp_tcam_match_addr <= w_dp_tcam_match_addr[14]*16/TCAM_BIT_WIDTH+14;
					16'h8000  : o_dp_tcam_match_addr <= w_dp_tcam_match_addr[15]*16/TCAM_BIT_WIDTH+15;
					default   : begin
						o_dp_tcam_match_addr <= 5'h1f;
					end
				endcase
			end
			else 
				o_dp_tcam_match_addr <= o_dp_tcam_match_addr;
		end


		always @(posedge axis_clk) begin
			if(!aresetn) 
				o_dp_tcam_match <= 1'b0;
			else if(match_sample && w_match_switch != 16'h00)
				o_dp_tcam_match <= 1'b1;
			else
				o_dp_tcam_match <= 1'b0;
		end
	end
	else begin
		wire                        		        w_dp_tcam_busy                                 ;
		wire                      		            w_dp_tcam_match                                ;
		wire [3:0] 	                                w_dp_tcam_match_addr                           ;
		 cam_top # ( 
    	        .C_DEPTH			(16                          ),//TCAM_DEPTH/(256/C_WIDTH)
    	        .C_WIDTH			(16                          ),
    	        .C_MEM_INIT			(1	                         ),//不使用初始文件
    	        .C_MEM_INIT_FILE	("./init1.mif"               )
				//.C_ELABORATION_DIR  ("/home/tsh/Desktop/link_emulator_05171005/link_emulator_512_sim.xpr/link_emulator_sim/link_emulator_sim.srcs/sources_1/new/tcam")
    	    )		   
			//TODO remember to change it back.
    	    cam_datapath_lookup1
    	    (
    	        .CLK				(axis_clk				     ),
    	        .CMP_DIN			(r_path_bit				     ),//来自数据提取的128b有效字段
    	        .CMP_DATA_MASK		(            			     ),//来自数据提取的128b实际有效位
    	        .BUSY				(w_dp_tcam_busy      		 ),
    	        .MATCH				(w_dp_tcam_match 		     ),
    	        .MATCH_ADDR			(w_dp_tcam_match_addr        ),
	
    	        .WE                 (   1'b0                     ),//控制报文算好的128b数据
    	        .WR_ADDR            (                            ),//由控制报文下发的5b的查找地址
    	        .DATA_MASK          (			                 ),//TODO do we need ternary matching?
    	        .DIN                (                            ),//由控制报文下发的128b数据匹配路径
				.EN					(1'b1					     )
    	    );	

			always @(posedge axis_clk) begin
				if(!aresetn) begin
					o_dp_tcam_match <= 1'b0;
					o_dp_tcam_match_addr <= 0;
				end
				else if(match_sample) begin
					o_dp_tcam_match <= w_dp_tcam_match;
					o_dp_tcam_match_addr <= w_dp_tcam_match_addr;
				end
				else begin
					o_dp_tcam_match <= 1'b0;
					o_dp_tcam_match_addr <= o_dp_tcam_match_addr;
				end
			end

	end
endgenerate 



//====================该段工程将非本配置模块的控制信号输出=======================
//将控制报文寄存一拍，用于判别第二拍数据里
// reg [C_S_AXIS_TDATA_WIDTH-1:0]              r1_ctrl_s_axis_tdata      ;
// reg [C_S_AXIS_TUSER_WIDTH-1:0]             r1_ctrl_s_axis_tuser      ;
// reg [C_S_AXIS_TKEEP_WIDTH-1:0]            r1_ctrl_s_axis_tkeep      ;
// reg                                      r1_ctrl_s_axis_tvalid     ;
// reg                                      r1_ctrl_s_axis_tlast      ;
// always @(posedge axis_clk) begin
//     if(!aresetn) begin
//         r1_ctrl_s_axis_tdata  <= 0 ;
//         r1_ctrl_s_axis_tuser  <= 0 ;
//         r1_ctrl_s_axis_tkeep  <= 0 ;
//         r1_ctrl_s_axis_tvalid <= 0 ;
//         r1_ctrl_s_axis_tlast  <= 0 ;
//     end
//     else begin
//         r1_ctrl_s_axis_tdata  <= ctrl_s_axis_tdata  ;
//         r1_ctrl_s_axis_tuser  <= ctrl_s_axis_tuser  ;
//         r1_ctrl_s_axis_tkeep  <= ctrl_s_axis_tkeep  ;
//         r1_ctrl_s_axis_tvalid <= ctrl_s_axis_tvalid ;
//         r1_ctrl_s_axis_tlast  <= ctrl_s_axis_tlast  ;
//     end
// end

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
					if( data_path_tcam_id == CFG_TCAM_MOD_ID) begin //如果是该模块的配置报文，则不输出
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
					ctrl_data_o_state  <= CTRL_O_JUDGE      ;
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
					ctrl_data_o_state  <= CTRL_O_JUDGE   ;
				end   
				else begin   
					ctrl_data_o_state  <= CTRL_O_FLUSH   ;
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

endmodule




