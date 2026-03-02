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
//加了path_lookup之后，数据报文会先到，bram_parser指令会后到，所以这里启动提取的逻辑有一些变化
//控制路径下发的指令随着数据有效信息触发才有效所以有效的逻辑布置，同步信息应该按触发后的逻辑来写
module sub0_parser #(
    parameter DO_PARER_GROUP_NUM = 2,
    parameter PARSER_ACT_WIDTH = 16,
    parameter C_S_AXIS_TDATA_WIDTH = 512
)(
    input axis_clk,
    input aresetn,

    input [DO_PARER_GROUP_NUM*PARSER_ACT_WIDTH-1:0]  i_parser_bram      ,
    input                                        i_parser_bram_valid,
    input                                        i_parser_bram_end  ,
    input [C_S_AXIS_TDATA_WIDTH-1:0]             i_seg_tdata        ,
    input                                        i_seg_wea          ,
    input  [1:0]                                 i_seg_addra        ,
    input                                        i_wait_segs_end    ,//数据平面和控制平面触发的信号要同步

    output reg [7:0]                             o_parser_act_low      ,//这个数据有时候有，有时候没有
    output reg                                   o_parser_act_low_valid,
    output reg                                   o_parser_act_low_end  ,
    output  [63:0]                               o_segs_8B_1           ,
    output  [63:0]                               o_segs_8B_2           ,
    output reg                                   o_segs_8B_valid
    );

reg [2:0] pre_seg_state;
reg [5:0] addrb;
reg [5:0] addrb1;
reg       enb;
reg [7:0] r_parser_act_low;
reg       r_parser_act_low_valid;
reg       r_parser_idle ;//解析假动作
reg       r_parser_act_low_end ;

wire [7:0] parse_action_l [DO_PARER_GROUP_NUM-1:0];
wire [7:0] parse_action_h [DO_PARER_GROUP_NUM-1:0];
wire [4:0] mem_addrb [DO_PARER_GROUP_NUM-1:0];
wire parser_en [DO_PARER_GROUP_NUM-1:0];

assign parse_action_l[0] = i_parser_bram[23:16];//81
assign parse_action_l[1] = i_parser_bram[7:0];

assign parse_action_h[0] = i_parser_bram[31:24];//80
assign parse_action_h[1] = i_parser_bram[15:8];

assign mem_addrb[0] = parse_action_h[0][4:0];
assign mem_addrb[1] = parse_action_h[1][4:0];

assign parser_en[0] = parse_action_h[0][7];
assign parser_en[1] = parse_action_h[1][7];

reg r_h_ram_addr;//因为写入和取出ram有冲突，所以分高地址8个ram和低地址8个ram
wire [2:0] w_seg_addra;
assign w_seg_addra = {r_h_ram_addr,i_seg_addra};

//----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
ram_d16_w256_d64_w64 O_8B_0 (
  .clka (axis_clk   ),    // input wire clka
  .ena  (1'b1       ),    // input wire ena
  .wea  (i_seg_wea  ),    // input wire [0 : 0] wea
  .addra(w_seg_addra),    // input wire [2 : 0] addra
  .dina (i_seg_tdata),    // input wire [255 : 0] dina
  .clkb (axis_clk   ),    // input wire clkb
  .enb  (enb        ),    // input wire enb
  .addrb(addrb      ),    // input wire [4 : 0] addrb
  .doutb(o_segs_8B_1)     // output wire [63 : 0] doutb
);
// INST_TAG_END ------ End INSTANTIATION Template ---------

//----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
ram_d16_w256_d64_w64 O_8B_1 (
  .clka (axis_clk   ),    // input wire clka
  .ena  (1'b1       ),    // input wire ena
  .wea  (i_seg_wea  ),    // input wire [0 : 0] wea
  .addra(w_seg_addra),    // input wire [2 : 0] addra
  .dina (i_seg_tdata),    // input wire [255 : 0] dina
  .clkb (axis_clk   ),    // input wire clkb
  .enb  (enb        ),    // input wire enb
  .addrb(addrb1     ),    // input wire [4 : 0] addrb
  .doutb(o_segs_8B_2)     // output wire [63 : 0] doutb
);
// INST_TAG_END ------ End INSTANTIATION Template ---------
localparam IDLE = 3'd0;
localparam O_1ST_PARSER = 3'd1;
localparam O_2ND_PARSER = 3'd2;
localparam O_3RD_PARSER = 3'd3;
localparam O_4TH_PARSER = 3'd4;
localparam O_5TH_PARSER = 3'd5;
localparam WAIT_RAM     = 3'd6;

//here is a state to get the segs_8B_1 and segs_8B_2
//由于24条指令分了两组进sub0_parser模块，但是ram一次只能读取一个地址的数据，
//所以这里的ram取数据逻辑按照parser指令分两拍
always @(posedge axis_clk) begin
	if(!aresetn)begin
        addrb <= 5'd0;
        addrb1 <= 5'd0;
        enb <= 0;
        pre_seg_state <= IDLE;
        r_parser_act_low <= 8'd0;
        r_parser_act_low_end <= 1'b0;
        r_parser_act_low_valid <= 0;
        o_segs_8B_valid <= 1'b0;
        r_parser_idle <= 1'b0;
	end
	else begin
		case(pre_seg_state)
            IDLE:begin
                r_parser_act_low_end <= 1'b0;
                r_parser_act_low_valid <= 1'b0;
                o_segs_8B_valid <= 1'b0;
                if(i_parser_bram_end)begin
                    pre_seg_state <= O_1ST_PARSER;
                    if(i_parser_bram_valid) 
                        r_parser_idle <= 1'b0;
                    else 
                        r_parser_idle <= 1'b1;
                end
                else begin
                    r_parser_idle   <= 0;
                    pre_seg_state <= IDLE;
                end
            end
			O_1ST_PARSER:begin 
                r_parser_act_low_end <= 1'b0;
                pre_seg_state <= O_2ND_PARSER;
                r_parser_idle <= r_parser_idle;
                if(parser_en[0]) begin
                    if(r_h_ram_addr) begin
                        addrb <= mem_addrb[0];
                        addrb1 <= mem_addrb[0]+1'b1;
                    end
                    else begin
                        addrb <= mem_addrb[0]+6'd32; //跳过低的位置取数据
                        addrb1 <= mem_addrb[0]+1'b1+6'd32;
                    end
                    enb <= 1'b1;
                end
                else begin
                    addrb <= 0;
                    addrb1 <= 0;
                    enb <= 0;
                end
			end
			O_2ND_PARSER:begin
                r_parser_act_low_end <= 1'b1;
                if(parser_en[1]) begin//如果parser指令有效，则数据输出
                    if(r_h_ram_addr) begin
                    addrb <= mem_addrb[1];
                    addrb1 <= mem_addrb[1]+1'b1;
                    end
                    else begin
                        addrb <= mem_addrb[1]+6'd32;
                        addrb1 <= mem_addrb[1]+1'b1+6'd32;
                    end
                    enb <= 1'b1;
                    pre_seg_state <= WAIT_RAM;
                    r_parser_act_low <= parse_action_l[0];
                    r_parser_act_low_valid <= 1'b1;
                    o_segs_8B_valid <= 1'b0;
                end
                else begin //如果parser指令无效，则无数据输出
                    pre_seg_state <= WAIT_RAM;
                    addrb <= 5'd0;
                    addrb1 <= 5'd0;
                    enb <= 0;
                    r_parser_act_low <= 8'd0;
                    r_parser_act_low_valid <= 0;
                    o_segs_8B_valid <= 1'b0;
                end
			end
            WAIT_RAM:begin
                if(r_parser_idle) begin
                    r_parser_act_low_valid <= 1'b0;
                    r_parser_act_low <= 0;
                    o_segs_8B_valid <= 1'b0;
                end
                else begin
                    r_parser_act_low_valid <= 1'b1;
                    r_parser_act_low <= parse_action_l[1];
                    o_segs_8B_valid <= 1'b1;
                end
                r_parser_act_low_end <= 1'b1;
                pre_seg_state <= IDLE;
            end
            default: begin
				pre_seg_state <= IDLE;
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
        if(i_wait_segs_end)
            r_h_ram_addr <= ~r_h_ram_addr;
        else
            r_h_ram_addr <= r_h_ram_addr;
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
        o_parser_act_low <= 8'b0;
        o_parser_act_low_valid <= 1'b0;
        o_parser_act_low_end <= 0;
    end
    else begin
        o_parser_act_low <= r_parser_act_low;
        o_parser_act_low_valid <= r_parser_act_low_valid;
        o_parser_act_low_end <= r_parser_act_low_end;
    end
end

endmodule
