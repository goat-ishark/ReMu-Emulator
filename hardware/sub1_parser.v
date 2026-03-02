`timescale 1ns / 1ps
//1，5，3，3，2
//[15] tvalid
//[12:8] Bytes offset 0-255,0-111:11111
//[7:5] Byte_in_seg
//[4:2] val_index
//[1:0] val_type,01:2B;10:4B;11:8B
//将第一步取的128b数据进一步按容器类型提取，同时解析出该容器数据的序号。
module sub1_parser #(
	parameter SUB_PKTS_LEN = 128,
	parameter L_PARSE_ACT_LEN = 8,
	parameter VAL_OUT_LEN = 64
)
(
	input				clk,
	input				aresetn,

	input						    parse_act_valid,
	input [L_PARSE_ACT_LEN-1:0]	    parse_act,
	input                           parse_act_end,

	input [SUB_PKTS_LEN-1:0]	    pkts_hdr,

	output reg					    val_out_valid,
	output reg					    val_out_end,
	output reg [VAL_OUT_LEN-1:0]	val_out,

	output reg [1:0]			    val_out_type,
	output reg [2:0]			    val_out_seq   //val_seq
);

always @(posedge clk) begin
	if(~aresetn) begin
		val_out_valid <= 1'b0;
		val_out_type <= 2'b00;
		val_out <= 64'd0;
		val_out_seq <= 3'd0;
		val_out_end <= 1'b0;
	end
	else if(parse_act_end) begin
		val_out_end <= 1'b1;
		if (parse_act_valid) begin
			val_out_seq <= parse_act[4:2];
			case({parse_act[1:0]})
				// 2B
				3'b01: begin
					val_out_valid <= 1'b1;
					val_out_type <= 2'b01;
					val_out[15:0] <= pkts_hdr[(parse_act[7:5])*8 +: 16];
				end
				// 4B
				3'b10: begin
					val_out_valid <= 1'b1;
					val_out_type <= 2'b10;
					val_out[31:0] <= pkts_hdr[(parse_act[7:5])*8 +: 32];
				end
				// 8B
				3'b11: begin
					val_out_valid <= 1'b1;
					val_out_type <= 2'b11;
					val_out[63:0] <= pkts_hdr[(parse_act[7:5])*8 +: 64];
				end
				default: begin
					val_out_valid <= 1'b0;
					val_out_type <= 2'b00;
					val_out <= 0;
				end
			endcase
		end
		else begin
			val_out_valid <= 1'b0;
		end
	end
	else begin
		val_out_end <= 1'b0;
		val_out_valid <= 1'b0;
	end
end


endmodule
