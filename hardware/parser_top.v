`timescale 1ns / 1ps


module parser_top #(
	parameter C_S_AXIS_TDATA_WIDTH = 512,
	parameter C_S_AXIS_TUSER_WIDTH = 256,
	parameter C_S_AXIS_TKEEP_WIDTH = 64,
	parameter PHV_LEN = (8+4+2)*8*8+100+256, 
	parameter PKTS_LEN = 2048,
	parameter PARSER_MOD_ID = 3'd1,
	parameter C_NUM_SEGS = 4,
	parameter C_VLANID_WIDTH = 12,
	parameter PARSER_NUM = 24,
	parameter PARSER_ACT_WIDTH = 16,
	parameter PKT_BYTE_LENGTH_W = 16,
	parameter INIT_FILE         = 1
)
(
	input									axis_clk,
	input									aresetn,

	// input slvae axi stream
	input [C_S_AXIS_TDATA_WIDTH-1 :0]	    s_axis_tdata ,
	input [C_S_AXIS_TUSER_WIDTH-1 :0]		s_axis_tuser ,
	input [C_S_AXIS_TKEEP_WIDTH-1 :0]		s_axis_tkeep ,
	input									s_axis_tvalid,
	input									s_axis_tlast ,
	output									s_axis_tready,
	
	// output
	output    								o_phv_valid,
	output     [PHV_LEN-1:0]			    o_phv_data ,
	output                                  o_phv_end  ,

	// back-pressure signals
	input									i_stg_ready,

	// output vlan
	output [C_VLANID_WIDTH-1:0]				out_vlan      ,
	output									out_vlan_valid,
	input									out_vlan_ready,


	output [C_S_AXIS_TDATA_WIDTH-1:0]		m_axis_tdata_0 ,
	output [C_S_AXIS_TUSER_WIDTH-1:0]		m_axis_tuser_0 ,
	output [C_S_AXIS_TKEEP_WIDTH-1:0]		m_axis_tkeep_0 ,
	output									m_axis_tlast_0 ,
	output									m_axis_tvalid_0,
	input									m_axis_tready_0,

	// ctrl path
	input [C_S_AXIS_TDATA_WIDTH-1:0]        ctrl_s_axis_tdata ,
	input [C_S_AXIS_TUSER_WIDTH-1:0]		ctrl_s_axis_tuser ,
	input [C_S_AXIS_TKEEP_WIDTH-1:0]		ctrl_s_axis_tkeep ,
	input									ctrl_s_axis_tvalid,
	input									ctrl_s_axis_tlast ,

	output [C_S_AXIS_TDATA_WIDTH-1:0]		ctrl_m_axis_tdata ,
	output [C_S_AXIS_TUSER_WIDTH-1:0]		ctrl_m_axis_tuser ,
	output [C_S_AXIS_TKEEP_WIDTH-1:0]		ctrl_m_axis_tkeep ,
	output									ctrl_m_axis_tvalid,
	output									ctrl_m_axis_tlast

);


localparam	DO_PARER_GROUP = 12;
localparam	DO_PARER_GROUP_NUM = 2;
localparam  PARSER_GROUP_WIDTH =  DO_PARER_GROUP_NUM*PARSER_ACT_WIDTH;
localparam  SUB_PKTS_LEN = 128;
localparam  L_PARSE_ACT_LEN = 8;
localparam  VAL_OUT_LEN = 64;
localparam  C_OFFBYTE_RAM_WIDTH = 16;
localparam  C_PARSER_RAM_WIDTH = 384;

localparam	IDLE=0,
			FLUSH_REST_PKTS=1;

reg  [31:0]                                 parser_bram_in       [DO_PARER_GROUP-1:0];
reg                                         parser_bram_in_valid [DO_PARER_GROUP-1:0];
reg                                         parser_bram_in_end   [DO_PARER_GROUP-1:0];
wire [7:0]                                  parser_act_low       [DO_PARER_GROUP-1:0];
wire [DO_PARER_GROUP-1:0]                   parser_act_low_valid                     ;    
wire [DO_PARER_GROUP-1:0]                   parser_act_low_end                       ; 
wire [63:0]                                 segs_8B_1            [DO_PARER_GROUP-1:0];
wire [63:0]                                 segs_8B_2            [DO_PARER_GROUP-1:0];
           
wire                                        val_out_valid        [DO_PARER_GROUP-1:0];
wire                                        val_out_end          [DO_PARER_GROUP-1:0];
wire [63:0]                                 val_out              [DO_PARER_GROUP-1:0];
wire [1 :0]                                 val_out_type         [DO_PARER_GROUP-1:0];
wire [2 :0]                                 val_out_seq          [DO_PARER_GROUP-1:0];

wire [C_S_AXIS_TDATA_WIDTH-1:0]	            w_segs_tdata                  ;
wire [C_S_AXIS_TUSER_WIDTH-1:0]				w_tuser_1st_out               ;
wire                                        w_tuser_1st_out_valid         ;
wire [383:0]								bram_out                      ;
wire                                        bram_out_valid                ;
wire [8:0]                                  bram_out_addrb                ;
wire                                        bram_out_end                  ;
    
wire										w_segs_end                    ;
            
reg [C_S_AXIS_TDATA_WIDTH-1:0]	            r_segs_tdata                  ;
reg [C_S_AXIS_TUSER_WIDTH-1:0]				r_tuser_1st_out               ;
reg                                         r_tuser_1st_out_valid         ;                                        
    
reg 										r_segs_end                    ;
reg [1:0]  									r_segs_addra                  ;
reg        									r_segs_wea                    ;
wire       									w_segs_wea                    ;
wire [1:0] 									w_segs_addra                  ;
wire [15 :0]                                w_lenth                       ;
wire                                        w_lenth_valid                 ;
reg  [15 :0]                                r_lenth                       ;
reg                                         r_lenth_valid                 ;

wire [C_S_AXIS_TDATA_WIDTH-1:0]             w_m_axis_tdata1               ;
wire [C_S_AXIS_TUSER_WIDTH-1:0]             w_m_axis_tuser1               ;
wire [C_S_AXIS_TKEEP_WIDTH-1:0]             w_m_axis_tkeep1               ;
wire                                        w_m_axis_tvalid1              ;
wire                                        w_m_axis_tlast1               ;
wire                                        w_m_axis_tready1              ;

reg [15:0] dbg_segs_end;
always @(posedge axis_clk) begin
	if(!aresetn)
		dbg_segs_end <=0;
	else if(o_phv_end)
		dbg_segs_end <= dbg_segs_end+1;
end
reg [15:0] dbg_s_tlast;
always @(posedge axis_clk) begin
	if(!aresetn)
		dbg_s_tlast <=0;
	else if(s_axis_tlast)
		dbg_s_tlast <= dbg_s_tlast+1;
end


parser_wait_segs #(
	.C_S_AXIS_TDATA_WIDTH (C_S_AXIS_TDATA_WIDTH),
	.C_S_AXIS_TUSER_WIDTH (C_S_AXIS_TUSER_WIDTH),
	.C_S_AXIS_TKEEP_WIDTH (C_S_AXIS_TKEEP_WIDTH),
	.C_NUM_SEGS           (C_NUM_SEGS          ),
	.PARSER_MOD_ID        (PARSER_MOD_ID       ),
	.PARSER_ACT_WIDTH     (PARSER_ACT_WIDTH    ),
	.PARSER_NUM           (PARSER_NUM          ),
	.PKT_BYTE_LENGTH_W    (PKT_BYTE_LENGTH_W   )
)
get_segs
(
	.axis_clk				(axis_clk             ),
	.aresetn				(aresetn              ),
        
	.s_axis_tdata			(s_axis_tdata         ),
	.s_axis_tuser			(s_axis_tuser         ),
	.s_axis_tkeep			(s_axis_tkeep         ),
	.s_axis_tvalid			(s_axis_tvalid        ),
	.s_axis_tlast			(s_axis_tlast         ),
	.s_axis_tready			(s_axis_tready        ),

	// output
	.o_seg_tdata			(w_segs_tdata         ),
	.o_seg_wea              (w_segs_wea           ),
	.o_seg_addra            (w_segs_addra         ),
	.o_seg_wait_end		    (w_segs_end           ),
      
	.o_tuser_1st			(w_tuser_1st_out      ),
	.o_tuser_1st_valid      (w_tuser_1st_out_valid),
	
	.o_lenth                (w_lenth              ),
	.o_lenth_valid          (w_lenth_valid        ),

	.o_m_axis_tdata         (w_m_axis_tdata1      ),
	.o_m_axis_tuser         (w_m_axis_tuser1      ),
	.o_m_axis_tkeep         (w_m_axis_tkeep1      ),
	.o_m_axis_tvalid        (w_m_axis_tvalid1     ),
	.o_m_axis_tlast         (w_m_axis_tlast1      ),
	.o_m_axis_tready        (1                    )
);

always @(posedge axis_clk) begin
	if (~aresetn) begin
		r_segs_tdata          <= 0;
		r_lenth               <= 0;
		r_lenth_valid         <= 0;
		r_tuser_1st_out       <= 0;
		r_tuser_1st_out_valid <= 0;
		r_segs_end            <= 0;
		r_segs_wea            <= 0;
		r_segs_addra          <= 0;
	end
	else begin
		r_segs_tdata          <= w_segs_tdata               ;
		r_lenth               <= w_lenth                    ;
		r_lenth_valid         <= w_lenth_valid              ;
		r_tuser_1st_out       <= w_tuser_1st_out            ;
		r_tuser_1st_out_valid <= w_tuser_1st_out_valid      ;
		r_segs_end            <= w_segs_end                 ;
		r_segs_wea            <= w_segs_wea                 ;
		r_segs_addra          <= w_segs_addra               ;
	end
end



wire [C_S_AXIS_TDATA_WIDTH-1:0] w_dp_segs_tdata1     ;
wire                            w_dp_segs_valid1     ;
wire                            w_dp_segs_wea1	     ;
wire [1:0]                      w_dp_segs_addra1     ;

reg [C_S_AXIS_TDATA_WIDTH-1:0] r_dp_segs_tdata1     ;
reg                            r_dp_segs_valid1     ;
reg                            r_dp_segs_wea1	     ;
reg [1:0]                      r_dp_segs_addra1     ;

always @(posedge axis_clk) begin
	if (~aresetn) begin
		r_dp_segs_tdata1  <= 0   ;
		r_dp_segs_valid1  <= 0   ;
		r_dp_segs_wea1	  <= 0   ;
		r_dp_segs_addra1  <= 0   ;
	end
	else begin
		r_dp_segs_tdata1  <= w_dp_segs_tdata1    ;
		r_dp_segs_valid1  <= w_dp_segs_valid1    ;
		r_dp_segs_wea1	  <= w_dp_segs_wea1	    ;
		r_dp_segs_addra1  <= w_dp_segs_addra1    ;
	end
end


data_path_top1  #(
	.C_S_AXIS_TDATA_WIDTH  (C_S_AXIS_TDATA_WIDTH   ),
	.C_S_AXIS_TUSER_WIDTH  (C_S_AXIS_TUSER_WIDTH   ),
	.C_S_AXIS_TKEEP_WIDTH  (C_S_AXIS_TKEEP_WIDTH   ),
	.C_RAM_WIDTH           (C_PARSER_RAM_WIDTH     ), 
	.C_RAM_DEPTH_WIDTH     ( 5                     ),
	.CFG_ORDER_NUM         ( 5                     ), 
	.CFG_S_ORDER_WID       ( 16                    ), 
	.CFG_TCAM_DEPTH        ( 32                    ), 
	.CFG_TCAM_MA_ADDR_WIDTH( 5                     ), 
	.CFG_BIT_MOD_ID        ( 15                    ),
	.CFG_TCAM_MOD_ID       ( 14                    ),
	.INIT_FILE             (1                      )

)
data_path_top1
(
	.axis_clk (axis_clk),
    .aresetn  (aresetn),
	
	.i_dp_segs_tdata		(r_segs_tdata		),
	.i_dp_segs_valid        (r_segs_end		    ),
	.i_dp_segs_wea			(r_segs_wea			),
	.i_dp_segs_addra		(r_segs_addra		),

	.i_offset_byte          (0                  ),
	.i_offset_byte_valid    (1                  ),
	.i_offset_byte_end      (1                  ),

	.ctrl_s_axis_tdata		(ctrl_s_axis_tdata  ),
	.ctrl_s_axis_tuser		(ctrl_s_axis_tuser  ),
	.ctrl_s_axis_tkeep		(ctrl_s_axis_tkeep  ),
	.ctrl_s_axis_tvalid		(ctrl_s_axis_tvalid ),
	.ctrl_s_axis_tlast		(ctrl_s_axis_tlast  ),

	.ctrl_m_axis_tdata		(ctrl_m_axis_tdata  ),
	.ctrl_m_axis_tuser		(ctrl_m_axis_tuser  ),
	.ctrl_m_axis_tkeep		(ctrl_m_axis_tkeep  ),
	.ctrl_m_axis_tvalid		(ctrl_m_axis_tvalid ),
	.ctrl_m_axis_tlast		(ctrl_m_axis_tlast  ),
	
	.o_bram			        (bram_out           ),
	.o_bram_valid           (bram_out_valid     ),
	.o_bram_addrb           (bram_out_addrb     ),
	.o_bram_end             (bram_out_end       ),

	.o_dp_segs_tdata	    (w_dp_segs_tdata1   ),
	.o_dp_segs_valid        (w_dp_segs_valid1   ),
	.o_dp_segs_wea	        (w_dp_segs_wea1	    ),
	.o_dp_segs_addra	    (w_dp_segs_addra1   )

);




generate
	genvar index;
	for(index=0;index < DO_PARER_GROUP;index = index+1)begin:
	sub_op
	always @(posedge axis_clk) begin
		if(!aresetn) begin
			parser_bram_in[index ]        <= 0   ;
			parser_bram_in_valid[index]   <= 1'b0;
			parser_bram_in_end[index]     <= 0   ;
		end
		else if(bram_out_end)begin
			parser_bram_in_end[index] <= 1'b1;
			parser_bram_in[index ] <= bram_out[PARSER_GROUP_WIDTH*(DO_PARER_GROUP-index)-1:PARSER_GROUP_WIDTH*(DO_PARER_GROUP-index-1)];
			if(bram_out_valid)
				parser_bram_in_valid[index]   <= 1'b1;
			else 
				parser_bram_in_valid[index]   <= 1'b0;
		end
		else begin
			parser_bram_in[index]       <= parser_bram_in[index];
			parser_bram_in_valid[index] <= 1'b0;
			parser_bram_in_end[index] <= 0;
		end
	end

	sub0_parser #(
		.PARSER_ACT_WIDTH    (PARSER_ACT_WIDTH    ),
		.DO_PARER_GROUP_NUM  (DO_PARER_GROUP_NUM  ),
		.C_S_AXIS_TDATA_WIDTH(C_S_AXIS_TDATA_WIDTH)
	)
	sub0_parser(
		.axis_clk             (axis_clk),
		.aresetn              (aresetn ),
	//in
		.i_parser_bram         (parser_bram_in[index]       ),
		.i_parser_bram_valid   (parser_bram_in_valid[index] ),
		.i_parser_bram_end     (parser_bram_in_end[index]   ),

		.i_seg_tdata           (r_dp_segs_tdata1            ),
		.i_seg_wea             (r_dp_segs_wea1              ),
		.i_seg_addra           (r_dp_segs_addra1            ),
		.i_wait_segs_end       (r_dp_segs_valid1            ),
	//out
		.o_parser_act_low      (parser_act_low[index]       ),
		.o_parser_act_low_valid(parser_act_low_valid[index] ),
		.o_parser_act_low_end  (parser_act_low_end[index]   ),
		.o_segs_8B_1           (segs_8B_1[index]            ),
		.o_segs_8B_2      	   (segs_8B_2[index]            )

	);


	sub1_parser #(
	.SUB_PKTS_LEN   (SUB_PKTS_LEN ),
	.L_PARSE_ACT_LEN(L_PARSE_ACT_LEN),
	.VAL_OUT_LEN    (VAL_OUT_LEN)
	)
	sub1_parser (
		.clk				(axis_clk),
		.aresetn			(aresetn),
		//in
		.parse_act_valid	(parser_act_low_valid[index]),
		// .parse_act			(sub_parse_act[index]),
		.parse_act			(parser_act_low[index]),
		.parse_act_end      (parser_act_low_end[index]),
		.pkts_hdr			({segs_8B_2[index],segs_8B_1[index]}),
		//out
		.val_out_end        (val_out_end[index]),
		.val_out_valid		(val_out_valid[index]),
		.val_out			(val_out[index]),
		.val_out_type		(val_out_type[index]),
		.val_out_seq		(val_out_seq[index])
	);
	end
endgenerate

	wire [DO_PARER_GROUP-1:0]           w_val_out_valid;
	wire [DO_PARER_GROUP-1:0]           w_val_out_end  ;
	wire [64*DO_PARER_GROUP-1:0]    	w_val_out      ;
	wire [2*DO_PARER_GROUP-1:0]    		w_val_out_type ;
	wire [3*DO_PARER_GROUP-1:0] 		w_val_out_seq  ;

	assign w_val_out_end = {
		val_out_end[0],val_out_end[1],val_out_end[ 2],val_out_end[ 3],
		val_out_end[4],val_out_end[5],val_out_end[ 6],val_out_end[ 7],
		val_out_end[8],val_out_end[9],val_out_end[10],val_out_end[11]};

	assign w_val_out_valid = {
		val_out_valid[0],val_out_valid[1],val_out_valid[2],val_out_valid[3],
		val_out_valid[4],val_out_valid[5],val_out_valid[6],val_out_valid[7],
		val_out_valid[8],val_out_valid[9],val_out_valid[10],val_out_valid[11]};
		
	assign w_val_out = {val_out[0],val_out[1],val_out[2],val_out[3],
						val_out[4],val_out[5],val_out[6],val_out[7],
						val_out[8],val_out[9],val_out[10],val_out[11]
					};
						
	assign w_val_out_type = {val_out_type[0 ],val_out_type[1 ],val_out_type[2 ],val_out_type[3 ],
							 val_out_type[4 ],val_out_type[5 ],val_out_type[6 ],val_out_type[7 ],
							 val_out_type[8 ],val_out_type[9 ],val_out_type[10],val_out_type[11]
							};

	assign w_val_out_seq = {val_out_seq[0 ],val_out_seq[1 ],val_out_seq[2 ],val_out_seq[3 ],
							val_out_seq[4 ],val_out_seq[5 ],val_out_seq[6 ],val_out_seq[7 ],
							val_out_seq[8 ],val_out_seq[9 ],val_out_seq[10],val_out_seq[11]
						};




	parser_do_parsing #(
		.C_S_AXIS_TDATA_WIDTH (C_S_AXIS_TDATA_WIDTH),
		.C_S_AXIS_TUSER_WIDTH (C_S_AXIS_TUSER_WIDTH),
		.PHV_LEN              (PHV_LEN             ),
		.PKTS_LEN             (PKTS_LEN            ),
		.PARSER_MOD_ID        (PARSER_MOD_ID       ),
		.C_NUM_SEGS           (C_NUM_SEGS          ),
		.C_VLANID_WIDTH       (C_VLANID_WIDTH      ),
		.DO_PARER_GROUP       (DO_PARER_GROUP      )
	)
	do_parsing
	(
		//in
		.axis_clk				(axis_clk       ),
		.aresetn				(aresetn        ),

		.sub_parse_val_valid    (w_val_out_valid), 
		.sub_parse_val_end      (w_val_out_end  ),
		.sub_parse_val          (w_val_out      ),     
		.sub_parse_val_type     (w_val_out_type ),
		.sub_parse_val_seq      (w_val_out_seq  ),

		.i_bram_parser_addrb    (bram_out_addrb ),
		.i_bram_parser_valid    (bram_out_valid ),
		.i_bram_parser_end      (bram_out_end   ),

		.i_lenth                (r_lenth              ),
		.i_lenth_valid          (r_lenth_valid        ),
		.i_tuser_1st		    (r_tuser_1st_out      ),
		.i_tuser_1st_valid      (r_tuser_1st_out_valid),

		//in
		.i_stg_ready			(i_stg_ready    ),
		//out  
		.o_phv_valid			(o_phv_valid    ),
		.o_phv			        (o_phv_data     ),
		.o_phv_end              (o_phv_end      ),
		//out
		.out_vlan				(out_vlan       ),
		.out_vlan_valid			(out_vlan_valid ),
		//in 
		.out_vlan_ready			(1'b1           )
	);




assign m_axis_tdata_0 = w_m_axis_tdata1; 
assign m_axis_tuser_0 = w_m_axis_tuser1;
assign m_axis_tkeep_0 = w_m_axis_tkeep1;
assign m_axis_tlast_0 = w_m_axis_tlast1;
assign m_axis_tvalid_0 = w_m_axis_tvalid1;


endmodule
