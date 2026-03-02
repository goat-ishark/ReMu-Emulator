`timescale 1ns / 1ps
//主要功能：对数据报文进行截断
//【1】取8段2048b的数据报文，少于2048b的数据报文则补充0字段输出，
//【2】拆分数据报文中待处理的报文头和除报文头外的其余字段。
//可选功能
//【3】根据需要输出数据报文的vlan，
//【4】获取报文的长度信息（按字节）
// 几个输出信号之间的关联
module parser_wait_segs #(
	parameter C_S_AXIS_TDATA_WIDTH = 512,
	parameter C_S_AXIS_TUSER_WIDTH = 256,
	parameter C_S_AXIS_TKEEP_WIDTH = 64,
	parameter C_NUM_SEGS = 4,
	parameter PARSER_MOD_ID = 3'd1,
	parameter PARSER_ACT_WIDTH = 16,
	parameter PARSER_NUM = 24,
	parameter PKT_BYTE_LENGTH_W = 16
)
(
	input											axis_clk     ,
	input											aresetn      ,
	// 
	input [C_S_AXIS_TDATA_WIDTH-1:0]			    s_axis_tdata ,
	input [C_S_AXIS_TUSER_WIDTH-1:0]				s_axis_tuser ,
	input [C_S_AXIS_TKEEP_WIDTH-1:0]			    s_axis_tkeep ,
	input											s_axis_tvalid,
	input											s_axis_tlast ,
	output reg										s_axis_tready,
	//
	output reg [C_S_AXIS_TDATA_WIDTH-1:0]	        o_seg_tdata   ,//just use the ram to out
	output reg  									o_seg_wea     ,
	output reg [2:0] 								o_seg_addra   ,
	output reg										o_seg_wait_end,//only set high once clk if 8 segs get
	// output reg dina,
	output reg[C_S_AXIS_TUSER_WIDTH-1:0]		    o_tuser_1st      ,
	output reg                                      o_tuser_1st_valid, 
	// output lenth
	output reg [PKT_BYTE_LENGTH_W-1:0]              o_lenth          ,//需要对报文的长度进行统计
	output reg                                      o_lenth_valid    ,

	output reg [C_S_AXIS_TDATA_WIDTH-1:0]           o_m_axis_tdata   ,
	output reg [C_S_AXIS_TUSER_WIDTH-1:0]           o_m_axis_tuser   ,
	output reg [C_S_AXIS_TKEEP_WIDTH-1:0]           o_m_axis_tkeep   ,
	output reg                                      o_m_axis_tvalid  ,
	output reg                                      o_m_axis_tlast   ,
	input                                           o_m_axis_tready

);

reg [C_S_AXIS_TDATA_WIDTH-1:0]			    r_s_axis_tdata ;
reg [C_S_AXIS_TUSER_WIDTH-1:0]				r_s_axis_tuser ;
reg [C_S_AXIS_TKEEP_WIDTH-1:0]				r_s_axis_tkeep ;
reg 										r_s_axis_tvalid;
reg 										r_s_axis_tlast ;

always @(posedge axis_clk) begin
	if(~aresetn)begin
		r_s_axis_tdata  <= 0;
		r_s_axis_tuser  <= 0;
		r_s_axis_tkeep  <= 0;
		r_s_axis_tvalid <= 0;
		r_s_axis_tlast  <= 0;

	end
	else begin
		r_s_axis_tdata <= s_axis_tdata ;
		r_s_axis_tuser <= s_axis_tuser ;
		r_s_axis_tkeep <= s_axis_tkeep ;
		r_s_axis_tvalid<= s_axis_tvalid;
		r_s_axis_tlast <= s_axis_tlast ;

	end
end

localparam	WAIT_1ST_SEG  =0,
			WAIT_2ND_SEG  =1,
			WAIT_3RD_SEG  =2,
			WAIT_4TH_SEG  =3,
			EMPTY_1CYCLE  =4,
			EMPTY_2CYCLE  =5,
			EMPTY_3CYCLE  =6,
			WAIT_TILL_LAST=7;

reg [C_S_AXIS_TDATA_WIDTH-1:0 ] r_segs_tdata_next      ;
reg [C_S_AXIS_TUSER_WIDTH-1:0]  r_tuser_1st_next       ;
reg                             r_tuser_1st_valid_next ;
reg 						    r_segs_valid_next      ;
reg         				    r_seg_wea_next         ;
reg [1:0]   				    r_seg_addra_next       ;
reg 						    s_axis_tready_next     ;
reg [4:0]                       state,state_next       ;

wire [C_S_AXIS_TDATA_WIDTH-1:0]		tdata_fifo;
wire [C_S_AXIS_TUSER_WIDTH-1:0]		tuser_fifo;
wire [C_S_AXIS_TKEEP_WIDTH-1:0]	    tkeep_fifo;
wire								tlast_fifo;


wire [11:0] vlan_id;
assign vlan_id = {s_axis_tdata[115:112],s_axis_tdata[127:120]};


reg        pkt_fifo_rd_en  ;
wire       pkt_fifo_empty  ;
fallthrough_small_fifo #(
	.WIDTH(C_S_AXIS_TDATA_WIDTH + C_S_AXIS_TUSER_WIDTH + C_S_AXIS_TKEEP_WIDTH + 1),
	.MAX_DEPTH_BITS(5)
)
parser_wait_segs_fifo
(
	.din									({r_s_axis_tdata,r_s_axis_tuser,r_s_axis_tkeep,r_s_axis_tlast}),
	.wr_en									(r_s_axis_tvalid),
	.rd_en									(pkt_fifo_rd_en),
	.dout									({tdata_fifo, tuser_fifo, tkeep_fifo, tlast_fifo}),
	.full									(),
	.prog_full								(),
	.nearly_full							(pkt_fifo_nearly_full),
	.empty									(pkt_fifo_empty),
	.reset									(~aresetn),
	.clk									(axis_clk)
);
//经过过滤器之后的数据报文和控制报文一定是可以进行rmt处理的有效报文，区别在不知道该报文的长度，
//是否满足进行2048b的查找
//在进入的时候记录报文长度信息
//第一个tuser位置
reg [PKT_BYTE_LENGTH_W-1:0] pkt_byte_cnt;
reg [PKT_BYTE_LENGTH_W-1:0] byte_length_cnt;
always @(*) begin
	if(~aresetn)
		pkt_byte_cnt = 0;
	else begin
		case(s_axis_tkeep)
			64'hffffffffffffffff: pkt_byte_cnt = 64 ;
			64'h7fffffffffffffff: pkt_byte_cnt = 63 ;
			64'h3fffffffffffffff: pkt_byte_cnt = 62 ;
			64'h1fffffffffffffff: pkt_byte_cnt = 61 ;
			64'h0fffffffffffffff: pkt_byte_cnt = 60 ;
			64'h07ffffffffffffff: pkt_byte_cnt = 59 ;
			64'h03ffffffffffffff: pkt_byte_cnt = 58 ;
			64'h01ffffffffffffff: pkt_byte_cnt = 57 ;
			64'h00ffffffffffffff: pkt_byte_cnt = 56 ;
			64'h007fffffffffffff: pkt_byte_cnt = 55 ;
			64'h003fffffffffffff: pkt_byte_cnt = 54 ;
			64'h001fffffffffffff: pkt_byte_cnt = 53 ;
			64'h000fffffffffffff: pkt_byte_cnt = 52 ;
			64'h0007ffffffffffff: pkt_byte_cnt = 51 ;
			64'h0003ffffffffffff: pkt_byte_cnt = 50 ;
			64'h0001ffffffffffff: pkt_byte_cnt = 49 ;
			64'h0000ffffffffffff: pkt_byte_cnt = 48 ;
			64'h00007fffffffffff: pkt_byte_cnt = 47 ;
			64'h00003fffffffffff: pkt_byte_cnt = 46 ;
			64'h00001fffffffffff: pkt_byte_cnt = 45 ;
			64'h00000fffffffffff: pkt_byte_cnt = 44 ;
			64'h000007ffffffffff: pkt_byte_cnt = 43 ;
			64'h000003ffffffffff: pkt_byte_cnt = 42 ;
			64'h000001ffffffffff: pkt_byte_cnt = 41 ;
			64'h000000ffffffffff: pkt_byte_cnt = 40 ;
			64'h0000007fffffffff: pkt_byte_cnt = 39 ;
			64'h0000003fffffffff: pkt_byte_cnt = 38 ;
			64'h0000001fffffffff: pkt_byte_cnt = 37 ;
			64'h0000000fffffffff: pkt_byte_cnt = 36 ;
			64'h00000007ffffffff: pkt_byte_cnt = 35 ;
			64'h00000003ffffffff: pkt_byte_cnt = 34 ;
			64'h00000001ffffffff: pkt_byte_cnt = 33 ;
			64'h00000000ffffffff: pkt_byte_cnt = 32 ;
			64'h000000007fffffff: pkt_byte_cnt = 31 ;
			64'h000000003fffffff: pkt_byte_cnt = 30 ;
			64'h000000001fffffff: pkt_byte_cnt = 29 ;
			64'h000000000fffffff: pkt_byte_cnt = 28 ;
			64'h0000000007ffffff: pkt_byte_cnt = 27 ;
			64'h0000000003ffffff: pkt_byte_cnt = 26 ;
			64'h0000000001ffffff: pkt_byte_cnt = 25 ;
			64'h0000000000ffffff: pkt_byte_cnt = 24 ;
			64'h00000000007fffff: pkt_byte_cnt = 23 ;
			64'h00000000003fffff: pkt_byte_cnt = 22 ;
			64'h00000000001fffff: pkt_byte_cnt = 21 ;
			64'h00000000000fffff: pkt_byte_cnt = 20 ;
			64'h000000000007ffff: pkt_byte_cnt = 19 ;
			64'h000000000003ffff: pkt_byte_cnt = 18 ;
			64'h000000000001ffff: pkt_byte_cnt = 17 ;
			64'h000000000000ffff: pkt_byte_cnt = 16 ;
			64'h0000000000007fff: pkt_byte_cnt = 15 ;
			64'h0000000000003fff: pkt_byte_cnt = 14 ;
			64'h0000000000001fff: pkt_byte_cnt = 13 ;
			64'h0000000000000fff: pkt_byte_cnt = 12 ;
			64'h00000000000007ff: pkt_byte_cnt = 11 ;
			64'h00000000000003ff: pkt_byte_cnt = 10 ;
			64'h00000000000001ff: pkt_byte_cnt = 9  ;
			64'h00000000000000ff: pkt_byte_cnt = 8  ;
			64'h000000000000007f: pkt_byte_cnt = 7  ;
			64'h000000000000003f: pkt_byte_cnt = 6  ;
			64'h000000000000001f: pkt_byte_cnt = 5  ;
			64'h000000000000000f: pkt_byte_cnt = 4  ;
			64'h0000000000000007: pkt_byte_cnt = 3  ;
			64'h0000000000000003: pkt_byte_cnt = 2  ;
			64'h0000000000000001: pkt_byte_cnt = 1  ;
			default     : pkt_byte_cnt = 0  ;
		endcase
	end
end

always @(posedge axis_clk) begin
	if(~aresetn) begin
		byte_length_cnt <= 0;
	end
	else begin
		if(s_axis_tvalid )
			if(s_axis_tlast)
				byte_length_cnt <= 0;
			else 
				byte_length_cnt <= pkt_byte_cnt + byte_length_cnt;
		else 
			byte_length_cnt <= byte_length_cnt;
	end
end

always @(posedge axis_clk) begin
	if(~aresetn)begin
		o_lenth <= 16'd0;
		o_lenth_valid <= 1'd0;
	end
	else if(s_axis_tvalid && s_axis_tlast)begin
		o_lenth <= byte_length_cnt + pkt_byte_cnt;
		o_lenth_valid <= 1'b1;
	end
	else begin
		o_lenth       <= o_lenth;
		o_lenth_valid <= 1'd0;
	end
end

//这里的报文是出给ram
always @(*) begin
	state_next = state;
	
	r_segs_tdata_next  = o_seg_tdata  ;
	r_segs_valid_next  = 0            ;
	r_seg_addra_next   = 3'd0         ;
	r_seg_wea_next     = 1'b0         ;
    
	r_tuser_1st_next   = o_tuser_1st  ;
	r_tuser_1st_valid_next = 1'b0     ;
	s_axis_tready_next = s_axis_tready;

    pkt_fifo_rd_en     = 1'b0         ;

	case (state)
		// at least 2 segs
		WAIT_1ST_SEG: begin
			if (!pkt_fifo_empty) begin
				r_seg_wea_next     = 1'b1            ;
				r_seg_addra_next   = 3'd0            ;
				r_segs_tdata_next  = tdata_fifo      ;
				r_tuser_1st_next   = tuser_fifo      ;
				r_tuser_1st_valid_next = 1'b1        ;
				if(tlast_fifo) begin    
					pkt_fifo_rd_en    = 1'b1         ;
					state_next = EMPTY_1CYCLE        ;
					s_axis_tready_next = 0           ;
				end
				else begin
					s_axis_tready_next = 1           ;
					state_next         = WAIT_2ND_SEG;
					pkt_fifo_rd_en     = 1'b1        ; 
				end
			end
			else begin
				s_axis_tready_next = 1               ;//当前fifo空的时候，允许读入报文
                state_next         = WAIT_1ST_SEG    ;
				pkt_fifo_rd_en     = 1'b0            ;
				r_tuser_1st_valid_next = 1'd0        ;
			end
		end
		WAIT_2ND_SEG: begin
			if (!pkt_fifo_empty) begin
				r_segs_tdata_next = tdata_fifo  ;
				r_seg_addra_next  = 3'd1        ;
				r_seg_wea_next    = 1'b1        ;
				if (tlast_fifo) begin //数据报文一定不会小于64B，所以在两段这里判别是否是最后一段 
					pkt_fifo_rd_en    = 1'b1    ;
					state_next = EMPTY_2CYCLE   ;
					s_axis_tready_next = 0; //如果第2段数据报文就少于2048b，这里补充完整2048b的数据，不再向过滤器阶段取数据
				end
				else begin
					s_axis_tready_next = 1      ;
					pkt_fifo_rd_en    = 1'b1    ;
					state_next = WAIT_3RD_SEG   ;
				end
			end
			else begin
				state_next = WAIT_2ND_SEG       ;
				pkt_fifo_rd_en    = 1'b0        ;
			end
		end
		WAIT_3RD_SEG: begin
			if (!pkt_fifo_empty) begin
				r_segs_tdata_next = tdata_fifo;
				r_seg_addra_next  = 3'd2;
				r_seg_wea_next    = 1'b1;
				if (tlast_fifo) begin
					pkt_fifo_rd_en    = 1'b1    ;
					s_axis_tready_next = 0      ;
					state_next = EMPTY_3CYCLE   ;
				end
				else begin
					s_axis_tready_next = 1      ;
					pkt_fifo_rd_en    = 1'b1    ;
					state_next = WAIT_4TH_SEG   ;
				end
			end
			else begin
				state_next = WAIT_3RD_SEG       ;
				pkt_fifo_rd_en    = 1'b0        ;
			end
		end
		WAIT_4TH_SEG: begin
			if (!pkt_fifo_empty) begin
				r_segs_tdata_next = tdata_fifo;
				r_segs_valid_next = 1'b1;
				r_seg_addra_next = 3'd3;
				r_seg_wea_next = 1'b1  ;
				if (tlast_fifo) begin
					s_axis_tready_next = 1      ;
					pkt_fifo_rd_en    = 1'b1    ;
					state_next = WAIT_1ST_SEG   ;//第四拍是最后一拍，正好2048b数据
				end
				else begin
					s_axis_tready_next = 1      ;
					pkt_fifo_rd_en    = 1'b1    ;
					state_next = WAIT_TILL_LAST ;//超过四拍2048b的数据
				end
			end
			else begin
				state_next = WAIT_4TH_SEG       ;
				pkt_fifo_rd_en    = 1'b0        ;
			end
		end

		EMPTY_1CYCLE: begin
			pkt_fifo_rd_en     = 1'b0;//第二拍
			r_segs_tdata_next  = 0   ;
			r_seg_addra_next   = 3'd1;
			r_seg_wea_next     = 1'b1;
			s_axis_tready_next = 0   ;  //少于8拍的报文在这里其实只要rden不再读数据就行，没必要
			state_next = EMPTY_2CYCLE;
		end
		
		EMPTY_2CYCLE: begin
			pkt_fifo_rd_en     = 1'b0;
			r_segs_tdata_next  = 0   ;
			r_seg_addra_next   = 3'd2;
			r_seg_wea_next     = 1'b1;
			s_axis_tready_next = 0   ;
			state_next = EMPTY_3CYCLE;
		end

		EMPTY_3CYCLE: begin
			r_segs_valid_next  = 1'b1;
			pkt_fifo_rd_en     = 1'b0;
			r_segs_tdata_next  = 0   ;
			r_seg_addra_next   = 3'd3;
			r_seg_wea_next     = 1'b1;
			s_axis_tready_next = 0   ;
			state_next = WAIT_1ST_SEG;
		end

		WAIT_TILL_LAST: begin //等待一个报文的结束，这里一个报文只提取2048b
			r_segs_tdata_next  = 1'b0;
			r_seg_addra_next   = 1'b0;
			r_seg_wea_next     = 1'b0;
			s_axis_tready_next = 1'b1;
			if (tlast_fifo)  begin//当前fifo缓存是空还是满，都不影响读到tlast才跳转
				state_next = WAIT_1ST_SEG;
				pkt_fifo_rd_en     = 1'b1;
			end
			else begin
				state_next = WAIT_TILL_LAST ;
				if(!pkt_fifo_empty) //留在当前状态，fifo不空继续读，直到tlast_fifo出来
					pkt_fifo_rd_en     = 1'b1;
				else 
					pkt_fifo_rd_en     = 1'b0;//fifo空了，则暂时不读，等fifo不空
			end
		end
	endcase
end

always @(posedge axis_clk) begin
	if (~aresetn) begin
		state             <= WAIT_1ST_SEG       ;
		o_seg_tdata       <= 512'd0             ;
		o_seg_wait_end    <= 1'd0               ;
		o_seg_wea         <= 1'd0               ;
		o_seg_addra       <= 1'd0               ;
		o_tuser_1st       <= 128'd0             ;
		o_tuser_1st_valid <= 1'd0               ;
		s_axis_tready     <= 1'd1               ;
		// o_vlan            <= 1'd0               ;
		// o_vlan_valid      <= 1'd0               ;
	end
	else begin
		state             <= state_next            ;
		o_seg_wea         <= r_seg_wea_next        ;
		o_seg_addra       <= r_seg_addra_next      ;
		o_seg_tdata       <= r_segs_tdata_next     ;
		o_tuser_1st       <= r_tuser_1st_next      ;
		o_tuser_1st_valid <= r_tuser_1st_valid_next;
		o_seg_wait_end    <= r_segs_valid_next     ;
		s_axis_tready     <= s_axis_tready_next    ;
		// o_vlan            <= vlan_id_next          ;
		// o_vlan_valid      <= vlan_valid_next       ;
	end
end

//data_path_top1不会影响这个模块数据的输出，因为这里的数据处理大于data_path_top1
always @(posedge axis_clk) begin
	if(~aresetn) begin
		o_m_axis_tdata  <= 0;
		o_m_axis_tuser  <= 0;
		o_m_axis_tkeep  <= 0;
		o_m_axis_tvalid <= 0;
		o_m_axis_tlast  <= 0;
	end
	else if(pkt_fifo_rd_en) begin
		o_m_axis_tdata  <= tdata_fifo;
		o_m_axis_tuser  <= tuser_fifo;
		o_m_axis_tkeep  <= tkeep_fifo;
		o_m_axis_tvalid <= 1;
		o_m_axis_tlast  <= tlast_fifo;
	end
	else begin
		o_m_axis_tdata  <= 0;
		o_m_axis_tuser  <= 0;
		o_m_axis_tkeep  <= 0;
		o_m_axis_tvalid <= 0;
		o_m_axis_tlast  <= 0;
	end
end


// integer wr1_file,wr2_file;
// initial begin
// 	wr1_file = $fopen("/home/tsh/Desktop/link_emulator_05171005/psegs_s_axis_data.txt","w");
// 	wr2_file = $fopen("/home/tsh/Desktop/link_emulator_05171005/psegs_m_axis_data.txt","w");
// end
// //将输入和输出数据打印到txt文本中进行比较
// //看取的是否是报文的前8段内容，同时少于8段的补0
// always @(posedge axis_clk) begin
//     if(s_axis_tvalid == 1'b1)
//     	$fwrite(wr1_file,"%h\n",s_axis_tdata);
// end
// always @(posedge axis_clk) begin
// 	if(o_seg_wea == 1'b1)
//     	$fwrite(wr2_file,"%h\n",o_seg_tdata);
// end

// initial begin
// 	#12000000;
// 	$fclose(wr1_file);
// 	$fclose(wr2_file);
// end

endmodule
