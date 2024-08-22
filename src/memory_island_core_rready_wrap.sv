// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

module memory_island_core_rready_wrap #(
  /// Address Width
  parameter int unsigned AddrWidth            = 0,
  /// Data Width for the Narrow Ports
  parameter int unsigned NarrowDataWidth      = 0,
  /// Data Width for the Wide Ports
  parameter int unsigned WideDataWidth        = 0,

  /// Number of Narrow Ports
  parameter int unsigned NumNarrowReq         = 0,
  /// Number of Wide Ports
  parameter int unsigned NumWideReq           = 0,

  /// Banking Factor for the Wide Ports (power of 2)
  parameter int unsigned NumWideBanks         = (1<<$clog2(NumWideReq))*2,
  /// Extra multiplier for the Narrow banking factor (baseline is WideWidth/NarrowWidth) (power of 2)
  parameter int unsigned NarrowExtraBF        = 1,
  /// Words per memory bank. (Total number of banks is (WideWidth/NarrowWidth)*NumWideBanks)
  parameter int unsigned WordsPerBank         = 1024,

  /// Spill Narrow
  parameter int unsigned SpillNarrowReqEntry  = 0,
  parameter int unsigned SpillNarrowRspEntry  = 0,
  parameter int unsigned SpillNarrowReqRouted = 0,
  parameter int unsigned SpillNarrowRspRouted = 0,
  /// Spill Wide
  parameter int unsigned SpillWideReqEntry    = 0,
  parameter int unsigned SpillWideRspEntry    = 0,
  parameter int unsigned SpillWideReqRouted   = 0,
  parameter int unsigned SpillWideRspRouted   = 0,
  parameter int unsigned SpillWideReqSplit    = 0,
  parameter int unsigned SpillWideRspSplit    = 0,
  /// Spill at Bank
  parameter int unsigned SpillReqBank         = 0,
  parameter int unsigned SpillRspBank         = 0,

  parameter bit          CombRspReq           = 1'b1,

  parameter              MemorySimInit        = "none",

  /// Relinquish narrow priority after x cycles, 0 for never. Requires SpillNarrowReqRouted==0.
  parameter int unsigned WidePriorityWait     = 1,

  // Derived, DO NOT OVERRIDE
  parameter int unsigned NarrowStrbWidth      = NarrowDataWidth/8,
  parameter int unsigned WideStrbWidth        = WideDataWidth/8,
  parameter int unsigned NWDivisor            = WideDataWidth/NarrowDataWidth
) (
  input  logic clk_i,
  input  logic rst_ni,

  // Narrow inputs
  input  logic [NumNarrowReq-1:0]                      narrow_req_i,
  output logic [NumNarrowReq-1:0]                      narrow_gnt_o,
  input  logic [NumNarrowReq-1:0][      AddrWidth-1:0] narrow_addr_i,
  input  logic [NumNarrowReq-1:0]                      narrow_we_i,
  input  logic [NumNarrowReq-1:0][NarrowDataWidth-1:0] narrow_wdata_i,
  input  logic [NumNarrowReq-1:0][NarrowStrbWidth-1:0] narrow_strb_i,
  output logic [NumNarrowReq-1:0]                      narrow_rvalid_o,
  input  logic [NumNarrowReq-1:0]                      narrow_rready_i,
  output logic [NumNarrowReq-1:0][NarrowDataWidth-1:0] narrow_rdata_o,

  // Wide inputs
  input  logic [  NumWideReq-1:0]                      wide_req_i,
  output logic [  NumWideReq-1:0]                      wide_gnt_o,
  input  logic [  NumWideReq-1:0][      AddrWidth-1:0] wide_addr_i,
  input  logic [  NumWideReq-1:0]                      wide_we_i,
  input  logic [  NumWideReq-1:0][  WideDataWidth-1:0] wide_wdata_i,
  input  logic [  NumWideReq-1:0][  WideStrbWidth-1:0] wide_strb_i,
  output logic [  NumWideReq-1:0]                      wide_rvalid_o,
  input  logic [  NumWideReq-1:0]                      wide_rready_i,
  output logic [  NumWideReq-1:0][  WideDataWidth-1:0] wide_rdata_o
);

  localparam NarrowDepth = ;
  localparam WideDepth   = ;

  logic [NumNarrowReq-1:0]                      narrow_req;
  logic [NumNarrowReq-1:0]                      narrow_gnt;
  logic [NumNarrowReq-1:0]                      narrow_rvalid;
  logic [NumNarrowReq-1:0][NarrowDataWidth-1:0] narrow_rdata;
  logic [NumNarrowReq-1:0]                      narrow_fifo_ready;
  logic [NumNarrowReq-1:0]                      narrow_credit_left;


  logic [  NumWideReq-1:0]                      wide_req;
  logic [  NumWideReq-1:0]                      wide_gnt;
  logic [  NumWideReq-1:0]                      wide_rvalid;
  logic [  NumWideReq-1:0][  WideDataWidth-1:0] wide_rdata;
  logic [  NumWideReq-1:0]                      wide_fifo_ready;
  logic [  NumWideReq-1:0]                      wide_credit_left;

  for (genvar i = 0; i < NumNarrowReq; i++) begin : gen_narrow_r_fifo
    stream_fifo #(
      .FALL_THROUGH ( 1'b1 ),
      .DATA_WIDTH   ( NarrowDataWidth ),
      .DEPTH        ()
    ) i_rdata_fifo (
      .clk_i,
      .rst_ni,
      .flush_i   ('0),
      .testmode_i('0),
      .usage_o   (),
      .data_i    ( narrow_rdata     [i] ),
      .valid_i   ( narrow_rvalid    [i] ),
      .ready_o   ( narrow_fifo_ready[i] ),
      .data_o    ( narrow_rdata_o   [i] ),
      .valid_o   ( narrow_rvalid_o  [i] ),
      .ready_i   ( narrow_rready_i  [i] ),
    );

    credit_counter #(
      .NumCredits     (  ),
      .InitCreditEmpty( 1'b0 )
    ) i_rdata_credit (
      .clk_i,
      .rst_ni,
      .credit_o     (),
      .credit_give_i( narrow_rvalid_o[i] & narrow_rready_i[i] ),
      .credit_take_i( narrow_req     [i] & narrow_gnt     [i] ),
      .credit_init_i( '0 ),
      .credit_left_o( narrow_credit_left                  [i] ),
      .credit_crit_o(),
      .credit_full_o()
    );

    // Only transmit request if we have credits or a space frees up
    assign narrow_req  [i] = narrow_req_i[i] & (narrow_credit_left[i] | (CombRspReq & narrow_rready_i[i] & narrow_rvalid_o[i]));
    // Only grant    request if we have credits or a space frees up
    assign narrow_gnt_o[i] = narrow_gnt  [i] & (narrow_credit_left[i] | (CombRspReq & narrow_rready_i[i] & narrow_rvalid_o[i]));
  end

  for (genvar i = 0; i < NumWideReq; i++) begin : gen_wide_r_fifo
    stream_fifo #(
      .FALL_THROUGH ( 1'b1 ),
      .DATA_WIDTH   ( WideDataWidth ),
      .DEPTH        ()
    ) i_rdata_fifo (
      .clk_i,
      .rst_ni,
      .flush_i   ('0),
      .testmode_i('0),
      .usage_o   (),
      .data_i    ( wide_rdata     [i] ),
      .valid_i   ( wide_rvalid    [i] ),
      .ready_o   ( wide_fifo_ready[i] ),
      .data_o    ( wide_rdata_o   [i] ),
      .valid_o   ( wide_rvalid_o  [i] ),
      .ready_i   ( wide_rready_i  [i] ),
    );

    credit_counter #(
      .NumCredits     (  ),
      .InitCreditEmpty( 1'b0 )
    ) i_rdata_credit (
      .clk_i,
      .rst_ni,
      .credit_o     (),
      .credit_give_i( wide_rvalid_o[i] & wide_rready_i[i] ),
      .credit_take_i( wide_req     [i] & wide_gnt     [i] ),
      .credit_init_i( '0 ),
      .credit_left_o( wide_credit_left                [i] ),
      .credit_crit_o(),
      .credit_full_o()
    );

    // Only transmit request if we have credits or a space frees up
    assign wide_req  [i] = wide_req_i[i] & (wide_credit_left[i] | (CombRspReq & wide_rready_i[i] & wide_rvalid_o[i]));
    // Only grant    request if we have credits or a space frees up
    assign wide_gnt_o[i] = wide_gnt  [i] & (wide_credit_left[i] | (CombRspReq & wide_rready_i[i] & wide_rvalid_o[i]));
  end

  memory_island_core #(
    .AddrWidth            ( AddrWidth            ),
    .NarrowDataWidth      ( NarrowDataWidth      ),
    .WideDataWidth        ( WideDataWidth        ),
    .NumNarrowReq         ( NumNarrowReq         ),
    .NumWideReq           ( NumWideReq           ),
    .NumWideBanks         ( NumWideBanks         ),
    .NarrowExtraBF        ( NarrowExtraBF        ),
    .WordsPerBank         ( WordsPerBank         ),
    .SpillNarrowReqEntry  ( SpillNarrowReqEntry  ),
    .SpillNarrowRspEntry  ( SpillNarrowRspEntry  ),
    .SpillNarrowReqRouted ( SpillNarrowReqRouted ),
    .SpillNarrowRspRouted ( SpillNarrowRspRouted ),
    .SpillWideReqEntry    ( SpillWideReqEntry    ),
    .SpillWideRspEntry    ( SpillWideRspEntry    ),
    .SpillWideReqRouted   ( SpillWideReqRouted   ),
    .SpillWideRspRouted   ( SpillWideRspRouted   ),
    .SpillWideReqSplit    ( SpillWideReqSplit    ),
    .SpillWideRspSplit    ( SpillWideRspSplit    ),
    .SpillReqBank         ( SpillReqBank         ),
    .SpillRspBank         ( SpillRspBank         ),
    .WidePriorityWait     ( WidePriorityWait     ),
    .MemorySimInit        ( MemorySimInit        )
  ) i_memory_island (
    .clk_i,
    .rst_ni,

    .narrow_req_i    ( narrow_req    ),
    .narrow_gnt_o    ( narrow_gnt    ),
    .narrow_addr_i,
    .narrow_we_i,
    .narrow_wdata_i,
    .narrow_strb_i,
    .narrow_rvalid_o ( narrow_rvalid ),
    .narrow_rdata_o  ( narrow_rdata  ),
    .wide_req_i      ( wide_req      ),
    .wide_gnt_o      ( wide_gnt      ),
    .wide_addr_i,
    .wide_we_i,
    .wide_wdata_i,
    .wide_strb_i,
    .wide_rvalid_o   ( wide_rvalid   ),
    .wide_rdata_o    ( wide_rdata    )
  );

endmodule
