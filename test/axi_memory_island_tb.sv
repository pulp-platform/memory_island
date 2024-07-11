// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

`include "axi/typedef.svh"
`include "axi/assign.svh"

module axi_memory_island_tb #(
  parameter int unsigned AddrWidth = 32,
  parameter int unsigned NarrowDataWidth = 32,
  parameter int unsigned WideDataWidth   = 512,
  parameter int unsigned AxiIdWidth = 2,
  parameter int unsigned AxiUserWidth = 1,
  parameter int unsigned NumNarrowReq = 4,
  parameter int unsigned NumWideReq = 2,
  parameter int unsigned NumWideBanks = 8,
  parameter int unsigned NarrowExtraBF = 2,
  parameter int unsigned WordsPerBank = 512*NumNarrowReq*NumWideReq,
  parameter int unsigned TbNumReads = 200,
  parameter int unsigned TbNumWrites = 200
) ();

  parameter time CyclTime = 10ns;
  parameter time ApplTime = 2ns;
  parameter time TestTime = 8ns;

  localparam int unsigned TotalBytes = WordsPerBank*NumWideBanks*WideDataWidth/8;
  localparam int unsigned UsableAddrWidth= $clog2(TotalBytes);

  localparam int unsigned TotalReq = NumNarrowReq+NumWideReq;

  localparam int unsigned BytesPerReq = TotalBytes/TotalReq;

  logic clk, rst_n;

  logic [TotalReq-1:0] end_of_sim;
  logic [TotalReq-1:0] mismatch;

  clk_rst_gen #(
    .RstClkCycles(3),
    .ClkPeriod   (CyclTime)
  ) i_clk_gen (
    .clk_o (clk),
    .rst_no(rst_n)
  );

  `AXI_TYPEDEF_ALL(narrow, logic[AddrWidth-1:0], logic[AxiIdWidth-1:0], logic[NarrowDataWidth-1:0], logic[NarrowDataWidth/8-1:0], logic[AxiUserWidth-1:0])
  `AXI_TYPEDEF_ALL(wide, logic[AddrWidth-1:0], logic[AxiIdWidth-1:0], logic[WideDataWidth-1:0], logic[WideDataWidth/8-1:0], logic[AxiUserWidth-1:0])

  typedef axi_test::axi_rand_master #(
    .AW ( AddrWidth        ),
    .DW ( NarrowDataWidth  ),
    .IW ( AxiIdWidth       ),
    .UW ( AxiUserWidth     ),
    // Stimuli application and test time
    .TA ( ApplTime         ),
    .TT ( TestTime         ),
    // Maximum number of read and write transactions in flight
    .MAX_READ_TXNS  ( 20   ),
    .MAX_WRITE_TXNS ( 20   ),

    .SIZE_ALIGN        ( 0 ),
    .AXI_MAX_BURST_LEN ( 0 ), // max
    .TRAFFIC_SHAPING   ( 0 ),
    .AXI_EXCLS         ( 1'b0 ),
    .AXI_ATOPS         ( 1'b0 ),
    .AXI_BURST_FIXED   ( 1'b0 ),
    .AXI_BURST_INCR    ( 1'b1 ),
    .AXI_BURST_WRAP    ( 1'b0 ),
    .UNIQUE_IDS        ( 1'b0 )
  ) narrow_axi_rand_master_t;

  typedef axi_test::axi_rand_master #(
    .AW ( AddrWidth      ),
    .DW ( WideDataWidth  ),
    .IW ( AxiIdWidth     ),
    .UW ( AxiUserWidth   ),
    // Stimuli application and test time
    .TA ( ApplTime       ),
    .TT ( TestTime       ),
    // Maximum number of read and write transactions in flight
    .MAX_READ_TXNS  ( 20      ),
    .MAX_WRITE_TXNS ( 20      ),

    .SIZE_ALIGN        ( 0 ),
    .AXI_MAX_BURST_LEN ( 0 ), // max
    .TRAFFIC_SHAPING   ( 0 ),
    .AXI_EXCLS         ( 1'b0 ),
    .AXI_ATOPS         ( 1'b0 ),
    .AXI_BURST_FIXED   ( 1'b0 ),
    .AXI_BURST_INCR    ( 1'b1 ),
    .AXI_BURST_WRAP    ( 1'b0 ),
    .UNIQUE_IDS        ( 1'b0 )
  ) wide_axi_rand_master_t;

  narrow_req_t  [NumNarrowReq-1:0] axi_narrow_req;
  narrow_resp_t [NumNarrowReq-1:0] axi_narrow_rsp;
  wide_req_t    [  NumWideReq-1:0] axi_wide_req;
  wide_resp_t   [  NumWideReq-1:0] axi_wide_rsp;

  AXI_BUS_DV #(
    .AXI_ADDR_WIDTH ( AddrWidth       ),
    .AXI_DATA_WIDTH ( NarrowDataWidth ),
    .AXI_ID_WIDTH   ( AxiIdWidth      ),
    .AXI_USER_WIDTH ( AxiUserWidth    )
  ) axi_narrow_dv [NumNarrowReq-1:0] (clk);

  AXI_BUS_DV #(
    .AXI_ADDR_WIDTH ( AddrWidth     ),
    .AXI_DATA_WIDTH ( WideDataWidth ),
    .AXI_ID_WIDTH   ( AxiIdWidth    ),
    .AXI_USER_WIDTH ( AxiUserWidth  )
  ) axi_wide_dv [NumWideReq-1:0] (clk);

  narrow_axi_rand_master_t narrow_rand_master [NumNarrowReq];
  wide_axi_rand_master_t   wide_rand_master [NumWideReq];

  narrow_req_t  [NumNarrowReq-1:0] dut_narrow_req;
  narrow_resp_t [NumNarrowReq-1:0] dut_narrow_rsp;
  wide_req_t    [  NumWideReq-1:0] dut_wide_req;
  wide_resp_t   [  NumWideReq-1:0] dut_wide_rsp;

  narrow_req_t  [NumNarrowReq-1:0] golden_narrow_req;
  narrow_resp_t [NumNarrowReq-1:0] golden_narrow_rsp;
  wide_req_t    [  NumWideReq-1:0] golden_wide_req;
  wide_resp_t   [  NumWideReq-1:0] golden_wide_rsp;


  for (genvar i = 0; i < NumNarrowReq; i++) begin : gen_narrow_stim
    `AXI_ASSIGN_TO_REQ(axi_narrow_req[i], axi_narrow_dv[i])
    `AXI_ASSIGN_FROM_RESP(axi_narrow_dv[i], axi_narrow_rsp[i])
  
    // Stimuli Generation
    initial begin
      narrow_rand_master[i] = new( axi_narrow_dv[i] );
      end_of_sim[i] <= 1'b0;
      narrow_rand_master[i].add_memory_region(i*BytesPerReq,
                                              (i+1)*BytesPerReq,
                                              axi_pkg::DEVICE_NONBUFFERABLE);
      narrow_rand_master[i].reset();
      @(posedge rst_n);
      narrow_rand_master[i].run(TbNumReads, TbNumWrites);
      end_of_sim[i] <= 1'b1;
    end

    // Test
    axi_slave_compare #(
      .AxiIdWidth   ( AxiIdWidth       ),
      .FifoDepth    ( 32               ),
      .UseSize      ( 1'b1             ),
      .DataWidth    ( NarrowDataWidth  ),
      .axi_aw_chan_t( narrow_aw_chan_t ),
      .axi_w_chan_t ( narrow_w_chan_t  ),
      .axi_b_chan_t ( narrow_b_chan_t  ),
      .axi_ar_chan_t( narrow_ar_chan_t ),
      .axi_r_chan_t ( narrow_r_chan_t  ),
      .axi_req_t    ( narrow_req_t     ),
      .axi_rsp_t    ( narrow_resp_t    )
    ) i_narrow_compare (
      .clk_i         ( clk ),
      .rst_ni        (rst_n),
      .testmode_i    ('0 ),
      .axi_mst_req_i ( axi_narrow_req   [i] ),
      .axi_mst_rsp_o ( axi_narrow_rsp   [i] ),
      .axi_ref_req_o ( golden_narrow_req[i] ),
      .axi_ref_rsp_i ( golden_narrow_rsp[i] ),
      .axi_test_req_o( dut_narrow_req   [i] ),
      .axi_test_rsp_i( dut_narrow_rsp   [i] ),
      .aw_mismatch_o (),
      .w_mismatch_o  (),
      .b_mismatch_o  (),
      .ar_mismatch_o (),
      .r_mismatch_o  (),
      .mismatch_o    (mismatch[i]),
      .busy_o        ()
    );
  end

  for (genvar i = 0; i < NumWideReq; i++) begin : gen_wide_stim
    `AXI_ASSIGN_TO_REQ(axi_wide_req[i], axi_wide_dv[i])
    `AXI_ASSIGN_FROM_RESP(axi_wide_dv[i], axi_wide_rsp[i])

    // Stimuli Generation
    initial begin
      wide_rand_master[i] = new( axi_wide_dv[i] );
      end_of_sim[NumNarrowReq+i] <= 1'b0;
      wide_rand_master[i].add_memory_region((NumNarrowReq+i)*BytesPerReq,
                                            (NumNarrowReq+i+1)*BytesPerReq,
                                            axi_pkg::DEVICE_NONBUFFERABLE);
      wide_rand_master[i].reset();
      @(posedge rst_n);
      wide_rand_master[i].run(TbNumReads, TbNumWrites);
      end_of_sim[NumNarrowReq+i] <= 1'b1;
    end

    // Test
    axi_slave_compare #(
      .AxiIdWidth   ( AxiIdWidth     ),
      .FifoDepth    ( 32             ),
      .UseSize      ( 1'b1           ),
      .DataWidth    ( WideDataWidth  ),
      .axi_aw_chan_t( wide_aw_chan_t ),
      .axi_w_chan_t ( wide_w_chan_t  ),
      .axi_b_chan_t ( wide_b_chan_t  ),
      .axi_ar_chan_t( wide_ar_chan_t ),
      .axi_r_chan_t ( wide_r_chan_t  ),
      .axi_req_t    ( wide_req_t     ),
      .axi_rsp_t    ( wide_resp_t    )
    ) i_wide_compare (
      .clk_i         ( clk ),
      .rst_ni        (rst_n),
      .testmode_i    ('0 ),
      .axi_mst_req_i ( axi_wide_req   [i] ),
      .axi_mst_rsp_o ( axi_wide_rsp   [i] ),
      .axi_ref_req_o ( golden_wide_req[i] ),
      .axi_ref_rsp_i ( golden_wide_rsp[i] ),
      .axi_test_req_o( dut_wide_req   [i] ),
      .axi_test_rsp_i( dut_wide_rsp   [i] ),
      .aw_mismatch_o (),
      .w_mismatch_o  (),
      .b_mismatch_o  (),
      .ar_mismatch_o (),
      .r_mismatch_o  (),
      .mismatch_o    (mismatch[NumNarrowReq+i]),
      .busy_o        ()
    );
  end

  // DUT
  axi_memory_island_wrap #(
    .AddrWidth            ( AddrWidth       ),
    .NarrowDataWidth      ( NarrowDataWidth ),
    .WideDataWidth        ( WideDataWidth   ),
    .AxiNarrowIdWidth     ( AxiIdWidth      ),
    .AxiWideIdWidth       ( AxiIdWidth      ),
    .axi_narrow_req_t     ( narrow_req_t    ),
    .axi_narrow_rsp_t     ( narrow_resp_t   ),
    .axi_wide_req_t       ( wide_req_t      ),
    .axi_wide_rsp_t       ( wide_resp_t     ),
    .NumNarrowReq         ( NumNarrowReq    ),
    .NumWideReq           ( NumWideReq      ),

    .SpillNarrowReqEntry  ( 0               ),
    .SpillNarrowRspEntry  ( 0               ),
    .SpillNarrowReqRouted ( 0               ),
    .SpillNarrowRspRouted ( 0               ),

    .SpillWideReqEntry    ( 0               ),
    .SpillWideRspEntry    ( 0               ),
    .SpillWideReqRouted   ( 0               ),
    .SpillWideRspRouted   ( 0               ),
    .SpillWideReqSplit    ( 0               ),
    .SpillWideRspSplit    ( 0               ),

    .SpillReqBank         ( 0               ),
    .SpillRspBank         ( 0               ),

    .NumWideBanks         ( NumWideBanks    ),
    .NarrowExtraBF        ( NarrowExtraBF   ),
    .WordsPerBank         ( WordsPerBank    ),
    .MemorySimInit        ( "zeros"         )
  ) i_dut (
    .clk_i            ( clk            ),
    .rst_ni           ( rst_n          ),
    .axi_narrow_req_i ( dut_narrow_req ),
    .axi_narrow_rsp_o ( dut_narrow_rsp ),
    .axi_wide_req_i   ( dut_wide_req   ),
    .axi_wide_rsp_o   ( dut_wide_rsp   ),
    .dma_reg_req_i    ( '0             ),
    .dma_reg_rsp_o    ()
  );

  // Golden model
  for (genvar i = 0; i < NumNarrowReq; i++) begin : gen_narrow_golden
    axi_sim_mem #(
      .AddrWidth         ( AddrWidth       ),
      .DataWidth         ( NarrowDataWidth ),
      .IdWidth           ( AxiIdWidth      ),
      .UserWidth         ( AxiUserWidth    ),
      .axi_req_t         ( narrow_req_t    ),
      .axi_rsp_t         ( narrow_resp_t   ),
      .WarnUninitialized ( 1'b0            ),
      .UninitializedData ( "zeros"         ),
      .ClearErrOnAccess  ( 1'b0            ),
      .ApplDelay         ( ApplTime        ),
      .AcqDelay          ( TestTime        )
    ) i_narrow_sim_mem (
      .clk_i             ( clk ),
      .rst_ni            ( rst_n ),
      .axi_req_i         ( golden_narrow_req[i] ),
      .axi_rsp_o         ( golden_narrow_rsp[i] ),
      .mon_w_valid_o     (),
      .mon_w_addr_o      (),
      .mon_w_data_o      (),
      .mon_w_id_o        (),
      .mon_w_user_o      (),
      .mon_w_beat_count_o(),
      .mon_w_last_o      (),
      .mon_r_valid_o     (),
      .mon_r_addr_o      (),
      .mon_r_data_o      (),
      .mon_r_id_o        (),
      .mon_r_user_o      (),
      .mon_r_beat_count_o(),
      .mon_r_last_o      ()
    );
  end
  for (genvar i = 0; i < NumWideReq; i++) begin : gen_wide_golden
    axi_sim_mem #(
      .AddrWidth         ( AddrWidth     ),
      .DataWidth         ( WideDataWidth ),
      .IdWidth           ( AxiIdWidth    ),
      .UserWidth         ( AxiUserWidth  ),
      .axi_req_t         ( wide_req_t    ),
      .axi_rsp_t         ( wide_resp_t   ),
      .WarnUninitialized ( 1'b0          ),
      .UninitializedData ( "zeros"       ),
      .ClearErrOnAccess  ( 1'b0          ),
      .ApplDelay         ( ApplTime      ),
      .AcqDelay          ( TestTime      )
    ) i_narrow_sim_mem (
      .clk_i             ( clk ),
      .rst_ni            ( rst_n ),
      .axi_req_i         ( golden_wide_req[i] ),
      .axi_rsp_o         ( golden_wide_rsp[i] ),
      .mon_w_valid_o     (),
      .mon_w_addr_o      (),
      .mon_w_data_o      (),
      .mon_w_id_o        (),
      .mon_w_user_o      (),
      .mon_w_beat_count_o(),
      .mon_w_last_o      (),
      .mon_r_valid_o     (),
      .mon_r_addr_o      (),
      .mon_r_data_o      (),
      .mon_r_id_o        (),
      .mon_r_user_o      (),
      .mon_r_beat_count_o(),
      .mon_r_last_o      ()
    );
  end

  int unsigned errors;

  // TB ctrl
  initial begin
    errors = 0;
    do begin
      #TestTime;
      errors += $countones(mismatch);
      if (end_of_sim == '1) begin
        $display("Counted %d errors.", errors);
        $stop();
      end
      @(posedge clk);
    end while (1'b1);
  end

endmodule
