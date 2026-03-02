`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/10/02 15:02:26
// Design Name: 
// Module Name: pre_get_segs
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
//1，5，3，3，2
//[15] tvalid
//[12:8] Bytes offset 0-255,0-111:11111
//[7:5] Byte_in_seg
//[4:2] val_index
//[1:0] val_type,01:2B;10:4B;11:8B
//简单双端口ram可以一边写入一边读出吗？
//整个设计已经决定了提取指令和对应存放位置关系，所以对进入sub_bit的指令看作整体一次判别就可以

module sub0_bit #(
    parameter BIT_GROUP_NUM = 4,
    parameter BIT_WIDTH = 16,
    parameter C_S_AXIS_TDATA_WIDTH = 512
)(
    input axis_clk,
    input aresetn,

    input [BIT_GROUP_NUM*BIT_WIDTH-1:0]  i_bit_bram,
    input [7:0]                          i_offset_byte,//直接当前解析无效时候，输出偏移字节0就可以
    input                                i_offset_byte_valid,//上一级没有匹配上怎么给
    input                                i_offset_byte_end  ,
    
    input [C_S_AXIS_TDATA_WIDTH-1:0]     i_seg_tdata    ,
    input                                i_seg_wea      ,
    input  [1:0]                         i_seg_addra    ,
    input                                i_wait_segs_end,
    
    output reg [3:0]                     o_bit_act_low  ,//没处理完的指令也输出一下
    output reg                           o_bit_act_low_valid,
    output  [15:0]                       o_bit_8,         //2个字节的数据输出
    output  reg                          o_bit_end,
    output  [3:0]                        o_bit_mask
);


//如果把ram给大一点呢？
reg [3:0] pre_seg_state      ;
reg [7:0] addrb              ;
reg [3:0] r_bit_act_low      ;
reg       r_bit_act_low_valid;
reg       r_bit_act_end      ;

wire [BIT_WIDTH-1:0] bit_order [BIT_GROUP_NUM-1:0];

wire [7:0] mem_addrb [BIT_GROUP_NUM-1:0];
wire  [BIT_GROUP_NUM-1:0] bit_en;
assign o_bit_mask = bit_en;
assign bit_order[3] = i_bit_bram[BIT_WIDTH*4-1:BIT_WIDTH*3];//81
assign bit_order[2] = i_bit_bram[BIT_WIDTH*3-1:BIT_WIDTH*2];
assign bit_order[1] = i_bit_bram[BIT_WIDTH*2-1:BIT_WIDTH*1];//81
assign bit_order[0] = i_bit_bram[BIT_WIDTH*1-1:0];

assign mem_addrb[0] = bit_order[0][11:4];
assign mem_addrb[1] = bit_order[1][11:4];
assign mem_addrb[2] = bit_order[2][11:4];
assign mem_addrb[3] = bit_order[3][11:4];

wire [3:0]mem_addr_low [3:0];
assign mem_addr_low[0] = bit_order[0][3:0];
assign mem_addr_low[1] = bit_order[1][3:0];
assign mem_addr_low[2] = bit_order[2][3:0];
assign mem_addr_low[3] = bit_order[3][3:0];

assign bit_en[0] = bit_order[0][15];
assign bit_en[1] = bit_order[1][15];
assign bit_en[2] = bit_order[2][15];
assign bit_en[3] = bit_order[3][15];

reg r_h_ram_addr;//因为写入和取出ram有冲突，所以分高地址8个ram和低地址8个ram
wire [2:0] w_seg_addra;
assign w_seg_addra = {r_h_ram_addr,i_seg_addra};//存入ram的高位地址或着存入低位地址

//----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
//256b，深度8进，8b出
ram_d8_w256_d256_w8 O_2B_0 (
  .clka (axis_clk   ),    // input wire clka
  .ena  (1'b1       ),    // input wire ena
  .wea  (i_seg_wea  ),    // input wire [0 : 0] wea
  .addra(w_seg_addra),    // input wire [2 : 0] addra
  .dina (i_seg_tdata),    // input wire [255 : 0] dina
  .clkb (axis_clk   ),    // input wire clkb
  .enb  (1          ),    // input wire enb
  .addrb(addrb      ),    // input wire [4 : 0] addrb
  .doutb(o_bit_8    )     // output wire [63 : 0] doutb
);

// INST_TAG_END ------ End INSTANTIATION Template ---------

// INST_TAG_END ------ End INSTANTIATION Template ---------
localparam IDLE         = 4'd0;
localparam O_1ST_PARSER = 4'd1;//第一个parser指令解析
localparam O_2ND_PARSER = 4'd2;//第二个parser指令解析
localparam O_3RD_PARSER = 4'd3;//第三个parser指令解析
localparam O_4TH_PARSER = 4'd4;//第四个parser指令解析
localparam O_5TH_PARSER = 4'd5;
localparam WAIT_RAM     = 4'd6;
localparam WAIT_OFF_BYTE= 4'd7;//等待偏移字节
localparam ACT_IDLE     = 4'd8;
//here is a state to get the segs_8B_1 and segs_8B_2
//由于24条指令分了两组进sub0_parser模块，但是ram一次只能读取一个地址的数据，
//所以这里的ram取数据逻辑按照parser指令分两拍
//写两个状态机
reg r_offset_byte_valid;
reg r_ram_out_end;
always @(posedge axis_clk) begin
	if(!aresetn)begin
        addrb <= 8'd0;
        pre_seg_state <= O_1ST_PARSER;
        r_ram_out_end <= 0;
        r_offset_byte_valid <= 0;
	end
	else begin
		case(pre_seg_state)
            O_1ST_PARSER:begin
                if(i_wait_segs_end && i_offset_byte_end) begin//因为这里其实会有两拍中断，所以逻辑上还是等一下报文会比较好
                    r_ram_out_end <= 1'b1;
                    pre_seg_state <= O_2ND_PARSER;
                    r_offset_byte_valid <= i_offset_byte_valid;
                    if(bit_en[0]) begin //解析指令
                        if(w_h_ram_addrb) begin
                            addrb <= mem_addrb[0]+i_offset_byte;//往高位传输，取低位数据
                        end
                        else begin
                            addrb <= mem_addrb[0]+8'd128+i_offset_byte; //跳过读出低的位置取数据
                        end
                    end
                    else begin
                        addrb <= 8'd0;
                    end
                end
                else begin
                    r_ram_out_end       <= 1'b0;
                    r_offset_byte_valid <= 0;
                    addrb               <= 8'd0;
                    pre_seg_state       <= O_1ST_PARSER;
                end
            end

            O_2ND_PARSER:begin 
                pre_seg_state <= O_3RD_PARSER;
                r_ram_out_end <= 1'b0;
                r_offset_byte_valid <= r_offset_byte_valid;
                if(bit_en[1]) begin
                    if(w_h_ram_addrb) begin
                        addrb <= mem_addrb[1]+i_offset_byte;
                    end
                    else begin
                        addrb <= mem_addrb[1]+8'd128+i_offset_byte; //跳过低的位置取数据
                    end
                end
                else begin
                    addrb <= 8'd0;
                end
			end
            O_3RD_PARSER:begin 
                r_ram_out_end <= 1'b0;
                pre_seg_state <= O_4TH_PARSER;
                r_offset_byte_valid <= r_offset_byte_valid;
                if(bit_en[2]) begin
                    if(w_h_ram_addrb) begin
                        addrb <= mem_addrb[2]+i_offset_byte;
                    end
                    else begin
                        addrb <= mem_addrb[2]+8'd128+i_offset_byte; //跳过低的位置取数据
                    end
                end
                else begin
                    addrb <= 8'd0;
                end
			end
			O_4TH_PARSER:begin
                r_ram_out_end <= 1'b0;
                pre_seg_state <= O_1ST_PARSER;
                r_offset_byte_valid <= r_offset_byte_valid;
                if(bit_en[3]) begin//如果parser指令有效，则数据输出
                    if(w_h_ram_addrb) begin
                        addrb <= mem_addrb[3]+i_offset_byte;
                    end
                    else begin
                        addrb <= mem_addrb[3]+8'd128+i_offset_byte;
                    end
                end
                else begin //如果parser指令无效，则无数据输出
                    addrb <= 8'd0;
                end
			end
            default: begin
				pre_seg_state <= IDLE;
			end
		endcase
	end
end

reg [2:0] ram_o_state;
localparam O_RAM1 = 0;
localparam O_RAM2 = 1;
localparam O_RAM3 = 2;
localparam O_RAM4 = 3;
always @(posedge axis_clk) begin
	if(!aresetn)begin
        ram_o_state <= O_RAM1;
        r_bit_act_low <= 4'd0;
        r_bit_act_low_valid <= 0;
        r_bit_act_end <= 0;
	end
	else begin
		case(ram_o_state)
            O_RAM1:begin
                if(r_ram_out_end)begin
                    ram_o_state <= O_RAM2;
                    if(r_offset_byte_valid) begin//因为这里其实会有两拍中断，所以逻辑上还是等一下报文会比较好
                        r_bit_act_low <= mem_addr_low[0];
                        r_bit_act_low_valid <= 1;
                    end
                    else begin
                        r_bit_act_low <= 0;
                        r_bit_act_low_valid <= 1'b0;
                    end
                    r_bit_act_end <= 1;
                end
                else begin
                    r_bit_act_low <= 0;
                    r_bit_act_low_valid <= 1'b0;
                    r_bit_act_end <= 0;
                    ram_o_state <= O_RAM1;
                end
            end
            O_RAM2:begin 
                ram_o_state <= O_RAM3;
                r_bit_act_end <= 1;
                r_bit_act_low <= mem_addr_low[1];
                r_bit_act_low_valid <= r_bit_act_low_valid;
			end
            O_RAM3:begin 
                ram_o_state <= O_RAM4;
                r_bit_act_end <= 1;
                r_bit_act_low <= mem_addr_low[2];
                r_bit_act_low_valid <= r_bit_act_low_valid;
			end
			O_RAM4:begin
                r_bit_act_low <= mem_addr_low[3];
                r_bit_act_low_valid <= r_bit_act_low_valid;
                ram_o_state <= O_RAM1;
                r_bit_act_end <= 1;
			end
            default: begin
				ram_o_state <= O_RAM1;
			end
		endcase
	end
end

//每次数据写入完之后存向不同的地址
always @(posedge axis_clk) begin
    if(!aresetn)begin
       r_h_ram_addr <= 1'b0;
	end
    else begin
        if(i_wait_segs_end)//传完4拍数据，接着往哪个位置传输
            r_h_ram_addr <= ~r_h_ram_addr;
        else
            r_h_ram_addr <= r_h_ram_addr;
    end
end

reg w_h_ram_addrb ;//对于读的数据，它要随i_wait_segs_end变化
always @(*) begin
    if(!aresetn)begin
       w_h_ram_addrb <= 1'b0;
	end
    else begin
        if(i_wait_segs_end)//传完4拍数据，接着往哪个位置传输
            w_h_ram_addrb = ~r_h_ram_addr;
        else
            w_h_ram_addrb = w_h_ram_addrb;
    end
end

// ila_2 parser_top (
// 	.clk(axis_clk), // input wire clk
//   //catch the data to dma
// 	.probe0 (pre_seg_state  ), // input wire [2:0]  probe0  
// 	.probe1 (addrb ), // input wire [4:0]  probe1 
// 	.probe2 (addrb1  ), // input wire [4:0]  probe2
//     .probe3 (enb      ), // input wire [0:0]  probe3
 
//     .probe4 (o_segs_8B_1      ), // input wire [63:0]    probe7
//     .probe5 (o_segs_8B_2      ) // input wire [63:0]    probe8
// );

always @(posedge axis_clk)begin
    if(!aresetn) begin
        o_bit_act_low       <= 8'b0;
        o_bit_act_low_valid <= 1'b0;
        o_bit_end           <= 1'b0;
    end
    else begin
        o_bit_act_low       <= r_bit_act_low;
        o_bit_act_low_valid <= r_bit_act_low_valid;
        o_bit_end           <= r_bit_act_end;
    end
end

endmodule