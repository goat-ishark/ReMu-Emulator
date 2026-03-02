`timescale 1ns / 1ps
//1，5，3，3，2
//[15] tvalid
//[12:8] Bytes offset 0-255,0-111:11111
//[7:5] Byte_in_seg
//[4:2] val_index
//[1:0] val_type,01:2B;10:4B;11:8B
//将第一步取的128b数据进一步按容器类型提取，同时解析出该容器数据的序号。
module sub1_bit #(
	parameter SUB_PKTS_LEN = 8,
	parameter L_BIT_ACT_LEN = 4,
	parameter O_BIT_LEN = 1
)
(
	input				clk,
	input				aresetn,

	input						    i_bit_act_valid,
	input [L_BIT_ACT_LEN-1:0]	    i_bit_act,
	input [SUB_PKTS_LEN-1:0]	    i_bit_hdr,
	input                           i_bit_end,
	input                           i_bit_mask,

	output reg					    o_bit_out_valid,
	output reg 						o_bit_out,
	output reg                      o_bit_end,	
	output reg                      o_bit_mask
	// output reg 						o_bit_seg_valid
);

//雪潭定义字节高低位的顺序与我定义字节高低位的顺序不一样
always @(posedge clk) begin
	if(~aresetn) begin
		o_bit_out_valid <= 1'b0;
		o_bit_out <= 1'd0;
		o_bit_mask <= 1'b0;
		o_bit_end  <= 1'b0;
		// o_bit_seg_valid <= 1'd0;
	end
	else if (i_bit_end) begin
		o_bit_end <= 1'b1;
		o_bit_mask <= i_bit_mask; 
		if(i_bit_act_valid)
			o_bit_out_valid <= 1'b1;
		else
			o_bit_out_valid <= 1'b0;
		case({i_bit_act[3:0]})
			// 2B 在这里3c按0，1，2，3，4，5，6，7来算
			4'b0000: begin
				o_bit_out <= i_bit_hdr[7];
			end
			4'b0001: begin
				o_bit_out <= i_bit_hdr[6];
			end
			// 4B
			4'b0010: begin
				o_bit_out <= i_bit_hdr[5];
			end
			// 8B
			4'b0011: begin
				o_bit_out <= i_bit_hdr[4];
			end
			4'b0100: begin
				o_bit_out <= i_bit_hdr[3];
			end
			4'b0101: begin
				o_bit_out <= i_bit_hdr[2];
			end
			// 4B
			4'b0110: begin
				o_bit_out <= i_bit_hdr[1];
			end
			// 8B
			4'b0111: begin
				o_bit_out <= i_bit_hdr[0];
			end
			4'b1000: begin
				o_bit_out <= i_bit_hdr[15];
			end
			4'b1001: begin
				o_bit_out <= i_bit_hdr[14];
			end
			// 4B
			4'b1010: begin
				o_bit_out <= i_bit_hdr[13];
			end
			// 8B
			4'b1011: begin
				o_bit_out <= i_bit_hdr[12];
			end
			4'b1100: begin
				o_bit_out <= i_bit_hdr[11];
			end
			4'b1101: begin
				o_bit_out <= i_bit_hdr[10];
			end
			// 4B
			4'b1110: begin
				o_bit_out <= i_bit_hdr[9];
			end
			// 8B
			4'b1111: begin
				o_bit_out <= i_bit_hdr[8];
			end
		endcase
	end
	else begin
		o_bit_out_valid <= 1'b0;
		o_bit_out       <= 0;
		o_bit_end       <= 0;
		// o_bit_seg_valid <= 1'b0;
	end
end


endmodule
