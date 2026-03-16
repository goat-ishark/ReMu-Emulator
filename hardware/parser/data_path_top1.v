`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/01/10 09:19:05
// Design Name: 
// Module Name: data_path_top
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


module data_path_top1 #(
    parameter C_S_AXIS_TDATA_WIDTH   = 512,
    parameter C_S_AXIS_TUSER_WIDTH   = 256,
    parameter C_S_AXIS_TKEEP_WIDTH   = 64 ,
    parameter C_RAM_WIDTH            = 16 ,
    parameter C_RAM_DEPTH_WIDTH      = 5  ,
    parameter CFG_ORDER_NUM          = 5  ,//提取bit指令数量
    parameter CFG_S_ORDER_WID        = 16 ,
    parameter CFG_TCAM_DEPTH         = 32 ,
    parameter CFG_TCAM_MA_ADDR_WIDTH = 5  ,
    parameter CFG_BIT_MOD_ID         = 15 ,
    parameter CFG_TCAM_MOD_ID        = 14 ,
    parameter INIT_FILE              = 1   //使用初始文件级加载配置

)(
    input axis_clk                                              , 
    input aresetn                                               , 
    
	input [C_S_AXIS_TDATA_WIDTH-1:0]       i_dp_segs_tdata	    ,	
	input                                  i_dp_segs_valid      ,       
	input                                  i_dp_segs_wea	    ,		
	input [1:0]                            i_dp_segs_addra	    ,
   
    input [7:0]                            i_offset_byte        ,
    input                                  i_offset_byte_valid  ,
    input                                  i_offset_byte_end    ,
   
	input [C_S_AXIS_TDATA_WIDTH-1:0]       ctrl_s_axis_tdata	,	
	input [C_S_AXIS_TUSER_WIDTH-1:0]       ctrl_s_axis_tuser	,	
	input [C_S_AXIS_TKEEP_WIDTH-1:0]       ctrl_s_axis_tkeep	,	
	input                                  ctrl_s_axis_tvalid	,	
	input                                  ctrl_s_axis_tlast	,	
   
	output [C_S_AXIS_TDATA_WIDTH-1:0]      ctrl_m_axis_tdata	,	
	output [C_S_AXIS_TUSER_WIDTH-1:0]      ctrl_m_axis_tuser	,	
	output [C_S_AXIS_TKEEP_WIDTH-1:0]      ctrl_m_axis_tkeep	,	
	output                                 ctrl_m_axis_tvalid	,	
	output                                 ctrl_m_axis_tlast	,	
   
	output  reg [C_RAM_WIDTH-1:0]          o_bram               ,
    output  reg                            o_bram_valid         ,
    output  reg [8:0]                      o_bram_addrb         ,
    output  reg                            o_bram_end           ,

    output reg [C_S_AXIS_TDATA_WIDTH-1:0]  o_dp_segs_tdata	    ,	
	output reg                             o_dp_segs_valid      ,       
	output reg                             o_dp_segs_wea	    ,		
	output reg [1:0]                       o_dp_segs_addra	
    );


wire [CFG_ORDER_NUM*CFG_S_ORDER_WID-1:0] w_cfg_bit_info  ;
wire                                     w_cfg_bit_updata;

//几个需要控制报文的模块串行配置
//数据报文路径解析关键bit位配置模块，输入配置报文，用寄存器的方式输出128X12b的数据
wire [C_S_AXIS_TDATA_WIDTH-1:0]      w_ctrl_m_axis_tdata1   ;
wire [C_S_AXIS_TUSER_WIDTH-1:0]      w_ctrl_m_axis_tuser1   ;
wire [C_S_AXIS_TKEEP_WIDTH-1:0]      w_ctrl_m_axis_tkeep1   ;
wire                                 w_ctrl_m_axis_tvalid1  ;
wire                                 w_ctrl_m_axis_tlast1   ;
reg [C_S_AXIS_TDATA_WIDTH-1:0]       r_ctrl_m_axis_tdata1   ;
reg [C_S_AXIS_TUSER_WIDTH-1:0]       r_ctrl_m_axis_tuser1   ;
reg [C_S_AXIS_TKEEP_WIDTH-1:0]       r_ctrl_m_axis_tkeep1   ;
reg                                  r_ctrl_m_axis_tvalid1  ;
reg                                  r_ctrl_m_axis_tlast1   ;

//控制报文配置TCAM，128b数据提取出的关键字查找TCAM，输出匹配地址
//128bX32的TCAM数据，加128bX1的掩码
wire [C_S_AXIS_TDATA_WIDTH-1:0  ]    w_ctrl_m_axis_tdata2   ;
wire [C_S_AXIS_TUSER_WIDTH-1:0 ]     w_ctrl_m_axis_tuser2   ;
wire [C_S_AXIS_TKEEP_WIDTH-1:0]      w_ctrl_m_axis_tkeep2   ;
wire                                 w_ctrl_m_axis_tvalid2  ;
wire                                 w_ctrl_m_axis_tlast2   ;
reg [C_S_AXIS_TDATA_WIDTH-1:0  ]     r_ctrl_m_axis_tdata2   ;
reg [C_S_AXIS_TUSER_WIDTH-1:0 ]      r_ctrl_m_axis_tuser2   ;
reg [C_S_AXIS_TKEEP_WIDTH-1:0]       r_ctrl_m_axis_tkeep2   ;
reg                                  r_ctrl_m_axis_tvalid2  ;
reg                                  r_ctrl_m_axis_tlast2   ;

wire [CFG_ORDER_NUM-1:0]             w_dp_bit               ;
wire                                 w_dp_bit_valid         ;
wire [CFG_ORDER_NUM-1:0]             w_dp_bit_mask          ;
wire                                 w_dp_bit_end           ;

wire                                 w_dp_tcam_match        ;
wire [CFG_TCAM_MA_ADDR_WIDTH-1:0]    w_dp_tcam_match_addr   ;
wire                                 w_dp_tcam_match_end    ;
wire                                 w_pkt_rden             ;

//输入1024b待提取报文头，输入提取指令，输出128b提取字段
wire [C_S_AXIS_TDATA_WIDTH-1:0] w_dp_segs_tdata;
wire                            w_dp_segs_valid;
wire                            w_dp_segs_wea  ;
wire [1  :0]                    w_dp_segs_addra;


wire [C_RAM_WIDTH-1:0]          w_bram         ;
wire                            w_bram_valid   ;
wire [8:0]                      w_bram_addrb   ;
wire                            w_bram_end     ;


data_path_bit_cfg #(
    .C_S_AXIS_TDATA_WIDTH   (C_S_AXIS_TDATA_WIDTH   ),
    .C_S_AXIS_TUSER_WIDTH   (C_S_AXIS_TUSER_WIDTH   ),
    .CFG_ORDER_NUMBER       (CFG_ORDER_NUM          ),
    .CFG_ORDER_WIDTH        (CFG_S_ORDER_WID        ),
    .CFG_BIT_MOD_ID         (CFG_BIT_MOD_ID         ),
    .INIT_FILE              (INIT_FILE              )
)
data_path_bit_cfg(
    .axis_clk               (axis_clk               ),
    .aresetn                (aresetn                ),
   
    .ctrl_s_axis_tdata      (ctrl_s_axis_tdata      ),
    .ctrl_s_axis_tuser      (ctrl_s_axis_tuser      ),
    .ctrl_s_axis_tkeep      (ctrl_s_axis_tkeep      ),
    .ctrl_s_axis_tvalid     (ctrl_s_axis_tvalid     ),
    .ctrl_s_axis_tlast      (ctrl_s_axis_tlast      ),

    .ctrl_m_axis_tdata      (w_ctrl_m_axis_tdata1   ),
    .ctrl_m_axis_tuser      (w_ctrl_m_axis_tuser1   ),
    .ctrl_m_axis_tkeep      (w_ctrl_m_axis_tkeep1   ),
    .ctrl_m_axis_tvalid     (w_ctrl_m_axis_tvalid1  ),
    .ctrl_m_axis_tlast      (w_ctrl_m_axis_tlast1   ),

    .o_cfg_bit_info         (w_cfg_bit_info         ),//CFG_ORDER_NUM*CFG_S_ORDER_WID
    .o_cfg_bit_updata       (w_cfg_bit_updata       )
);

always @(posedge axis_clk)begin
    if(!aresetn) begin
        r_ctrl_m_axis_tdata1  <=   0;
        r_ctrl_m_axis_tuser1  <=   0;
        r_ctrl_m_axis_tkeep1  <=   0;
        r_ctrl_m_axis_tvalid1 <=   0;
        r_ctrl_m_axis_tlast1  <=   0;
    end
    else begin
        r_ctrl_m_axis_tdata1  <=   w_ctrl_m_axis_tdata1 ;
        r_ctrl_m_axis_tuser1  <=   w_ctrl_m_axis_tuser1 ;
        r_ctrl_m_axis_tkeep1  <=   w_ctrl_m_axis_tkeep1 ;
        r_ctrl_m_axis_tvalid1 <=   w_ctrl_m_axis_tvalid1;
        r_ctrl_m_axis_tlast1  <=   w_ctrl_m_axis_tlast1 ;
    end
end



data_path_lookup#(
    .C_S_AXIS_TDATA_WIDTH  (C_S_AXIS_TDATA_WIDTH),
    .SEG_ADDR              (2                   ),
    .CFG_ORDER_NUM         (CFG_ORDER_NUM       ),
    .CFG_S_ORDER_WID       (CFG_S_ORDER_WID     )
)
data_path_lookup1(
    .axis_clk              (axis_clk            ),
    .aresetn               (aresetn             ),
    
    .i_offset_byte         (i_offset_byte       ),//前一级的输入偏移字节
    .i_offset_byte_valid   (i_offset_byte_valid ),
    .i_offset_byte_end     (i_offset_byte_end   ),

    .i_dp_segs_tdata       (i_dp_segs_tdata     ),
    .i_dp_segs_valid       (i_dp_segs_valid     ),
    .i_dp_segs_wea         (i_dp_segs_wea       ),
    .i_dp_segs_addra       (i_dp_segs_addra     ),
  
    .i_cfg_bit_info        (w_cfg_bit_info      ),
    .i_cfg_bit_updata      (w_cfg_bit_updata    ),
  
    .o_dp_bit              (w_dp_bit            ),//提取128b关键协议数据
    .o_dp_bit_valid        (w_dp_bit_valid      ),
    .o_dp_bit_mask         (w_dp_bit_mask       ),
    .o_dp_bit_end          (w_dp_bit_end        ),
     
    .o_dp_segs_tdata  	   (w_dp_segs_tdata     ),
    .o_dp_segs_valid  	   (w_dp_segs_valid     ),
    .o_dp_segs_wea    	   (w_dp_segs_wea       ),
    .o_dp_segs_addra  	   (w_dp_segs_addra     ),

    .i_pkt_fifo_rden       (w_pkt_rden          )	
);

data_path_tcam_cfg #(
    .C_S_AXIS_TDATA_WIDTH   (C_S_AXIS_TDATA_WIDTH   ),
    .C_S_AXIS_TUSER_WIDTH   (C_S_AXIS_TUSER_WIDTH   ),
    .C_S_AXIS_TKEEP_WIDTH   (C_S_AXIS_TKEEP_WIDTH   ),
    .FEATURE_BIT_WIDTH      (CFG_ORDER_NUM          ),//提取特征bit位
    .TCAM_MATCH_ADDR        (CFG_TCAM_MA_ADDR_WIDTH ),
    .TCAM_DEPTH             (CFG_TCAM_DEPTH         ),
    .CFG_TCAM_MOD_ID        (CFG_TCAM_MOD_ID        ),
    .INIT_FILE              (INIT_FILE              )
) data_path_tcam_cfg(
    .axis_clk               (axis_clk               ),
    .aresetn                (aresetn                ),
// in
    .ctrl_s_axis_tdata      (r_ctrl_m_axis_tdata1   ),
    .ctrl_s_axis_tuser      (r_ctrl_m_axis_tuser1   ),
    .ctrl_s_axis_tkeep      (r_ctrl_m_axis_tkeep1   ),
    .ctrl_s_axis_tvalid     (r_ctrl_m_axis_tvalid1  ),
    .ctrl_s_axis_tlast      (r_ctrl_m_axis_tlast1   ),

    .ctrl_m_axis_tdata      (w_ctrl_m_axis_tdata2   ),
    .ctrl_m_axis_tuser      (w_ctrl_m_axis_tuser2   ),
    .ctrl_m_axis_tkeep      (w_ctrl_m_axis_tkeep2   ),
    .ctrl_m_axis_tvalid     (w_ctrl_m_axis_tvalid2  ),
    .ctrl_m_axis_tlast      (w_ctrl_m_axis_tlast2   ),
//  
    .i_dp_bit               (w_dp_bit               ),
    .i_dp_bit_valid         (w_dp_bit_valid         ),
    .i_dp_bit_mask          (w_dp_bit_mask          ),
    .i_dp_bit_end           (w_dp_bit_end           ),
// out     
    .o_dp_tcam_match        (w_dp_tcam_match        ),
    .o_dp_tcam_match_addr   (w_dp_tcam_match_addr   ),
    .o_dp_tcam_match_end    (w_dp_tcam_match_end    ),

    .o_pkt_rden             (w_pkt_rden             )
);

always @(posedge axis_clk)begin
    if(!aresetn) begin
        r_ctrl_m_axis_tdata2  <=   0;
        r_ctrl_m_axis_tuser2  <=   0;
        r_ctrl_m_axis_tkeep2  <=   0;
        r_ctrl_m_axis_tvalid2 <=   0;
        r_ctrl_m_axis_tlast2  <=   0;
    end
    else begin
        r_ctrl_m_axis_tdata2  <=   w_ctrl_m_axis_tdata2 ;
        r_ctrl_m_axis_tuser2  <=   w_ctrl_m_axis_tuser2 ;
        r_ctrl_m_axis_tkeep2  <=   w_ctrl_m_axis_tkeep2 ;
        r_ctrl_m_axis_tvalid2 <=   w_ctrl_m_axis_tvalid2;
        r_ctrl_m_axis_tlast2  <=   w_ctrl_m_axis_tlast2 ;
    end
end



always @(posedge axis_clk) begin
    if(!aresetn) begin
        o_dp_segs_tdata <= 0;
        o_dp_segs_valid <= 0;
        o_dp_segs_wea   <= 0;
        o_dp_segs_addra <= 0;
        o_bram          <= 0;
        o_bram_valid    <= 0;
        o_bram_addrb    <= 0;
        o_bram_end      <= 0;
    end
    else begin
        o_dp_segs_tdata <= w_dp_segs_tdata ;
        o_dp_segs_valid <= w_dp_segs_valid ;
        o_dp_segs_wea   <= w_dp_segs_wea   ;
        o_dp_segs_addra <= w_dp_segs_addra ;
        o_bram          <= w_bram          ;
        o_bram_valid    <= w_bram_valid    ;
        o_bram_addrb    <= w_bram_addrb    ;
        o_bram_end      <= w_bram_end      ;
    end
end




parser_bram_cfg#(
    .C_S_AXIS_TDATA_WIDTH   (C_S_AXIS_TDATA_WIDTH   ),
    .C_S_AXIS_TUSER_WIDTH   (C_S_AXIS_TUSER_WIDTH   ),
    .C_S_AXIS_TKEEP_WIDTH   (C_S_AXIS_TKEEP_WIDTH   ),
    .TCAM_MATCH_ADDR        (5                      ),
    .VLAN_ID_WIDTH          (12                     ),
    .C_PARSER_RAM_WIDTH     (16*24                  ),
    .PARSER_MOD_ID          (1                      )
) parser_bram_cfg(
    .axis_clk               (axis_clk               ),
    .aresetn                (aresetn                ),

    .ctrl_s_axis_tdata      (r_ctrl_m_axis_tdata2   ),
    .ctrl_s_axis_tuser      (r_ctrl_m_axis_tuser2   ),
    .ctrl_s_axis_tkeep      (r_ctrl_m_axis_tkeep2   ),
    .ctrl_s_axis_tvalid     (r_ctrl_m_axis_tvalid2  ),
    .ctrl_s_axis_tlast      (r_ctrl_m_axis_tlast2   ),

    .ctrl_m_axis_tdata      (ctrl_m_axis_tdata      ),
    .ctrl_m_axis_tuser      (ctrl_m_axis_tuser      ),
    .ctrl_m_axis_tkeep      (ctrl_m_axis_tkeep      ),
    .ctrl_m_axis_tvalid     (ctrl_m_axis_tvalid     ),
    .ctrl_m_axis_tlast      (ctrl_m_axis_tlast      ),
   
    .i_dp_tcam_match        (w_dp_tcam_match        ),
    .i_dp_tcam_match_addr   (w_dp_tcam_match_addr   ),
    .i_dp_tcam_match_end    (w_dp_tcam_match_end    ),

    .o_bram_parser          (w_bram                 ),
    .o_bram_parser_valid    (w_bram_valid           ),
    .o_bram_parser_addrb    (w_bram_addrb           ),
    .o_bram_parser_end      (w_bram_end             )

);

endmodule
