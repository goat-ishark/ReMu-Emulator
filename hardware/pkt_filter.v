
`timescale 1ns / 1ps
`define ETH_TYPE_IPV4   16'h0008 //0800
`define IPPROT_UDP      8'h11
`define CONTROL_PORT    16'hf2f1
// `define ETH_TYPE_IPV6	16'hdd86 //86dd
`define TPID            16'h0081

module pkt_filter #(
	parameter C_S_AXIS_TDATA_WIDTH = 512,
	parameter C_S_AXIS_TUSER_WIDTH = 256,
	parameter C_S_AXIS_TKEEP_WIDTH = 64
)(
    input  wire                                 clk,
    input  wire                                 aresetn,

// input Slave AXI Stream
    input  wire [C_S_AXIS_TDATA_WIDTH-1:0]      s_axis_tdata,
    input  wire [C_S_AXIS_TKEEP_WIDTH-1:0]      s_axis_tkeep,
    input  wire [C_S_AXIS_TUSER_WIDTH-1:0]      s_axis_tuser,
    input  wire                                 s_axis_tvalid,
    input  wire                                 s_axis_tlast,
    output wire                                 s_axis_tready,
    
// output Master AXI Stream(data)
    output reg [C_S_AXIS_TDATA_WIDTH-1:0]       m_axis_tdata,
    output reg [C_S_AXIS_TKEEP_WIDTH-1:0]       m_axis_tkeep,
    output reg [C_S_AXIS_TUSER_WIDTH-1:0]       m_axis_tuser,
    output reg                                  m_axis_tvalid,
    output reg                                  m_axis_tlast,
    input  wire                                 m_axis_tready,	
// output Master AXI Stream(control)
    output reg [C_S_AXIS_TDATA_WIDTH-1:0]       ctrl_m_axis_tdata,
    output reg [C_S_AXIS_TKEEP_WIDTH-1:0]       ctrl_m_axis_tkeep,
    output reg [C_S_AXIS_TUSER_WIDTH-1:0]       ctrl_m_axis_tuser,
    output reg                                  ctrl_m_axis_tvalid,
    output reg                                  ctrl_m_axis_tlast
);

localparam  WAIT_FIRST_PKT  = 3'b000,
            WAIT_SECOND_PKT = 3'b001,
			BUFFER_DATA1    = 3'b010,
            BUFFER_DATA     = 3'b011,
			BUFFER_CTRL     = 3'b100,
            THROW_PKT       = 3'b101;

// localparam  FIL_OUT_IDLE    = 3'b000,//起始状�?�机跳转
// 			FIL_OUT_SWITCH  = 3'b001,//�?包数据后状�?�机跳转
//             FLUSH_CTL       = 3'b010,
//             FLUSH_DATA      = 3'b011;

reg         rd_state,rd_state_next;
localparam  RD_IDLE    = 3'b000,//起始状�?�机跳转
			CTRL_RD    = 3'b001;//�?包数据后状�?�机跳转


reg [15:0] dbg_fil_s_tlast;
reg [15:0] dbg_fil_m_tlast;
always @(posedge clk) begin
	if(!aresetn)begin
		dbg_fil_s_tlast <= 0;
	end
	else if(s_axis_tlast)begin
		dbg_fil_s_tlast <= dbg_fil_s_tlast+1'b1;
	end
end
always @(posedge clk) begin
	if(!aresetn)begin
		dbg_fil_m_tlast <= 0;
	end
	else if(m_axis_tlast)begin
		dbg_fil_m_tlast <= dbg_fil_m_tlast+1'b1;
	end
end
// reg  [3:0] vlan_id;
// wire [11:0] w_vlan_id;
// assign  w_vlan_id = tdata_fifo[116+:12];

wire [C_S_AXIS_TDATA_WIDTH-1:0]		tdata_fifo;
wire [C_S_AXIS_TUSER_WIDTH-1:0]		tuser_fifo;
wire [C_S_AXIS_TDATA_WIDTH/8-1:0]	tkeep_fifo;
wire								tlast_fifo;

reg                                 pkt_fifo_wr_en   ;
reg                                 pkt_fifo_rd_en   ;//不读的时候，�?3拍出tdata的报文在数据总线�?
reg [C_S_AXIS_TDATA_WIDTH-1:0]      r_s_axis_tdata_0 ;
reg [C_S_AXIS_TKEEP_WIDTH-1:0]      r_s_axis_tkeep_0 ;
reg [C_S_AXIS_TUSER_WIDTH-1:0]      r_s_axis_tuser_0 ;
reg                                 r_s_axis_tvalid_0;
reg                                 r_s_axis_tlast_0 ;

wire pkt_fifo_almost_empty,pkt_fifo_nearly_full;
wire rd_valid;
wire prog_full;
wire full;

wire ctrl_or_data_fifo;



assign s_axis_tready = (m_axis_tready &&!pkt_fifo_nearly_full);

//�?始是来的数据有效就新进fifo，现在是判别fifo是否能整包写入，�?以会写入判别延迟�?�?
always @(posedge clk) begin
	if(!aresetn)begin
		r_s_axis_tdata_0  <= 0;
		r_s_axis_tkeep_0  <= 0;
		r_s_axis_tvalid_0 <= 0;
		r_s_axis_tlast_0  <= 0;
	end
	else if(s_axis_tvalid)begin
        r_s_axis_tdata_0  <= s_axis_tdata ;
        r_s_axis_tkeep_0  <= s_axis_tkeep ;
        r_s_axis_tvalid_0 <= s_axis_tvalid;
        r_s_axis_tlast_0  <= s_axis_tlast ;  
	end
	else begin
		r_s_axis_tdata_0  <= 0;
        r_s_axis_tkeep_0  <= 0;
        r_s_axis_tvalid_0 <= 0;
        r_s_axis_tlast_0  <= 0; 
	end
end

// 对报文类型的判别，同时写入报文到fifo,在fifo满时候，丢弃要进入的报文
reg [2:0] fil_in_state    ;
reg       ctrl_or_data    ;
reg       tuser_fifo_wr_en;

//输入时隙,将数据报文进入时隙写到第�?拍的tuser�?
reg [31:0] r_intime_stamp ; //输入时隙
always @(posedge clk) begin
	if(!aresetn) begin
		r_intime_stamp <= 0;
	end
	else if(r_intime_stamp == 4095)//进入时隙�?0-4095
		r_intime_stamp <= 0;
	else begin
		r_intime_stamp <= r_intime_stamp+1'b1;
	end
end

reg in_time_valid;
integer wr_init_intimestamp;
initial begin
	wr_init_intimestamp = $fopen("/home/tsh/Desktop/link_emulator_05171005/init_intimestamp.txt","w");
end
always @(posedge clk) begin
	if(in_time_valid) begin
		$fwrite(wr_init_intimestamp,"%h\n",r_intime_stamp);
	end
end
initial begin
	#120000000;
	$fclose(wr_init_intimestamp);
end

always @(posedge clk) begin
	 if(!aresetn)begin
		tuser_fifo_wr_en <= 1'b0;
		pkt_fifo_wr_en <= 1'b0;
		ctrl_or_data   <= 1'b0;
		fil_in_state <= WAIT_FIRST_PKT;
		r_s_axis_tuser_0 <= 0;
		in_time_valid <= 0;
	 end
	 else begin
		case(fil_in_state)
			WAIT_FIRST_PKT:begin
				if(prog_full) begin//如果fifo不能接收�?包最大的数据32，则这整包数据不写入fifo
					pkt_fifo_wr_en <= 1'b0;
					fil_in_state   <= THROW_PKT;
					r_s_axis_tuser_0 <= 0;
					tuser_fifo_wr_en <= 1'b0;
					in_time_valid <= 0;
				end
				else begin //在fifo没有编程满的情况下，数据有效，可以写入fifo
					if(s_axis_tvalid && s_axis_tready)begin
						tuser_fifo_wr_en <= 1'b1;
						r_s_axis_tuser_0 <= {r_intime_stamp,s_axis_tuser[95:0]};
						in_time_valid <= 1'b1;
						pkt_fifo_wr_en <= 1'b1;
						if((s_axis_tdata[143:128]==`ETH_TYPE_IPV4)&&(s_axis_tdata[223:216]==`IPPROT_UDP)&&(s_axis_tdata[111:96]==`TPID)&&(s_axis_tdata[335:320]==`CONTROL_PORT)) begin
							fil_in_state <= BUFFER_CTRL;
							ctrl_or_data <= 1'b0;//当是ipv4报文是时候要判别是控制报文还是数据报�?
						end
						else begin//默认系统除了控制报文其它的均是数据报�?
							fil_in_state <= BUFFER_DATA;
							ctrl_or_data <= 1'b1;
						end
					end
					else begin
						tuser_fifo_wr_en <= 1'b0;
						pkt_fifo_wr_en <= 1'b0;
						fil_in_state <= WAIT_FIRST_PKT;
						in_time_valid <= 0;
					end
				end
			end

			BUFFER_CTRL:begin //第二拍控制报�?
				r_s_axis_tuser_0 <= s_axis_tuser;
				ctrl_or_data     <= 1'b0;
				in_time_valid <= 0;
				if(s_axis_tvalid && s_axis_tready) begin
					pkt_fifo_wr_en <= 1'b1;
					tuser_fifo_wr_en <= 1'b1;
					if(s_axis_tlast)
						fil_in_state <= WAIT_FIRST_PKT;
					else
						fil_in_state <= BUFFER_CTRL;
				end
				else begin
					tuser_fifo_wr_en <= 1'b0;
					pkt_fifo_wr_en <= 1'b0;
					fil_in_state <= BUFFER_CTRL;
				end
			end

			BUFFER_DATA:begin //第二拍数据报�?
				r_s_axis_tuser_0 <= s_axis_tuser;
				ctrl_or_data <= 1'b1;
				in_time_valid <= 0;
				if(s_axis_tvalid && s_axis_tready) begin
					pkt_fifo_wr_en <= 1'b1;
					tuser_fifo_wr_en <= 1'b1;
					if(s_axis_tlast)
						fil_in_state <= WAIT_FIRST_PKT;
					else
						fil_in_state <= BUFFER_DATA;
				end
				else begin
					tuser_fifo_wr_en <= 1'b0;
					pkt_fifo_wr_en <= 1'b0;
					fil_in_state   <= BUFFER_DATA;
				end
			end

			THROW_PKT:begin
				in_time_valid <= 0;
				r_s_axis_tuser_0 <= s_axis_tuser;
				tuser_fifo_wr_en <= 1'b0;
				ctrl_or_data   <= 1'd0;
				pkt_fifo_wr_en <= 1'd0;
				if(s_axis_tlast && s_axis_tready) 
					fil_in_state <= WAIT_FIRST_PKT;
				else 
					fil_in_state <= THROW_PKT;
			end
		endcase
	 end
end

//----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
//512+64+1+256+1 = 577+256+1= 834
fifo_generator_00 filter_tdata_fifo (
  .clk         (clk                  ),  // input wire clk
  .rst        (!aresetn             ),  // input wire srst
  .din         ({r_s_axis_tdata_0,r_s_axis_tkeep_0,r_s_axis_tlast_0,r_s_axis_tuser_0,ctrl_or_data}),  // input wire [255 : 0] din
  .wr_en       (pkt_fifo_wr_en       ),  // input wire wr_en
  .rd_en       (pkt_fifo_rd_en       ),  // input wire rd_en
  .dout        ({tdata_fifo,tkeep_fifo,tlast_fifo,tuser_fifo,ctrl_or_data_fifo}),  // output wire [255 : 0] dout
  .full        (full                 ),  // output wire full
  .almost_full (pkt_fifo_nearly_full ),  // output wire almost_full
  .empty       (pkt_fifo_empty       ),  // output wire empty
  .almost_empty(pkt_fifo_almost_empty),  // output wire almost_empty
  .valid       (rd_valid             ),  // output wire valid
  .prog_full   (prog_full            )   // output wire prog_full
);
// INST_TAG_END ------ End INSTANTIATION Template ---------

//控制读出信号
//在读出信号发出下�?拍才出数�?

always @(*) begin
	if(!aresetn) begin
		pkt_fifo_rd_en = 1'b0;
		rd_state_next    = RD_IDLE;
	end
	else begin 
		// rd_state_next = rd_state;
		case(rd_state)
			RD_IDLE:begin
				if(m_axis_tready) begin
					if(!pkt_fifo_empty) begin//已经判别了报文控制或者数据类型的情况�?
						pkt_fifo_rd_en   = 1'b1   ;
						rd_state_next    = CTRL_RD;
					end
					else begin
						pkt_fifo_rd_en   = 1'b0;
						rd_state_next = RD_IDLE;
					end
				end
				else begin
					pkt_fifo_rd_en   = 1'b0;
					rd_state_next = RD_IDLE;
				end
			end

			CTRL_RD:begin
				if(m_axis_tready) begin
					if(tlast_fifo) begin
						pkt_fifo_rd_en = 1'b1;
						rd_state_next = RD_IDLE;
					end
					else begin
						rd_state_next = CTRL_RD;
						if(!pkt_fifo_empty)
							pkt_fifo_rd_en = 1'b1;//上一拍因为空了没有读
						else 
							pkt_fifo_rd_en = 1'b0;
					end
				end
				else begin
					rd_state_next = CTRL_RD;
					pkt_fifo_rd_en = 1'b0;
				end
			end
		endcase
	end
end

always @(posedge clk) begin
	if(!aresetn) 
		rd_state <= RD_IDLE;
	else
		rd_state <= rd_state_next ;
end

//读出数据赋�??,这里要写两段，因为写入的tuser是第二段�?
//中间的m_tready不用标准的axis_tream
always @(posedge clk) begin
	if(!aresetn)begin
		ctrl_m_axis_tdata  <= 0;
		ctrl_m_axis_tkeep  <= 0;
		ctrl_m_axis_tuser  <= 0;
		ctrl_m_axis_tvalid <= 0;
		ctrl_m_axis_tlast  <= 0;
		m_axis_tdata  <= 0;
		m_axis_tkeep  <= 0;
		m_axis_tuser  <= 0;
		m_axis_tvalid <= 0;
		m_axis_tlast  <= 0;
	end
	else begin
		if(rd_valid) begin
			if(ctrl_or_data_fifo) begin
				m_axis_tdata   <= tdata_fifo       ;
				m_axis_tkeep   <= tkeep_fifo       ;
				m_axis_tuser   <= tuser_fifo       ;
				m_axis_tvalid  <= 1'b1             ;
				m_axis_tlast   <= tlast_fifo       ;
			end
			else begin
				ctrl_m_axis_tdata  <= tdata_fifo   ;
				ctrl_m_axis_tkeep  <= tkeep_fifo   ;
				ctrl_m_axis_tuser  <= tuser_fifo   ;
				ctrl_m_axis_tvalid <= 1'b1         ;
				ctrl_m_axis_tlast  <= tlast_fifo   ;
			end
		end
		else begin
			ctrl_m_axis_tdata  <= 0;
			ctrl_m_axis_tkeep  <= 0;
			ctrl_m_axis_tuser  <= 0;
			ctrl_m_axis_tvalid <= 0;
			ctrl_m_axis_tlast  <= 0;
			m_axis_tdata       <= 0;
			m_axis_tkeep       <= 0;
			m_axis_tuser       <= 0;
			m_axis_tvalid      <= 0;
			m_axis_tlast       <= 0;
		end
	end
end


// integer wr1_file,wr2_file;
// initial begin
// 	wr1_file = $fopen("/home/tsh/Desktop/link_emulator_05171005/filter_s_axis_data.txt","w");
// 	wr2_file = $fopen("/home/tsh/Desktop/link_emulator_05171005/filter_m_axis_data.txt","w");
// end
// //将输入和输出数据打印到txt文本中进行比�?

// always @(posedge clk) begin
//     if(s_axis_tvalid == 1'b1)
//     	$fwrite(wr1_file,"%h\n",s_axis_tdata);
// end
// always @(posedge clk) begin
// 	if(m_axis_tvalid == 1'b1)
//     	$fwrite(wr2_file,"%h\n",m_axis_tdata);
// end

// initial begin
// 	#12000000;
// 	$fclose(wr1_file);
// 	$fclose(wr2_file);
// end

// integer wr3_file;
// initial begin
// 	wr3_file = $fopen("/home/tsh/Desktop/link_emulator_05171005/init_intime_stamp.txt","w");
// end
// // //将输入和输出数据打印到txt文本中进行比�?

// always @(posedge clk) begin
//     if((fil_in_state == WAIT_FIRST_PKT)&&(s_axis_tvalid))
//     	$fwrite(wr3_file,"%h\n",r_s_axis_tuser_0[127-:32]);
// end

// initial begin
// 	#12000000;
// 	$fclose(wr3_file);
// end

endmodule
