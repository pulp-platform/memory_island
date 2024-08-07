// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

module geared_memory_island #(
  /// Address Width
  parameter int unsigned AddrWidth       = 0,
  /// Data Width for the Narrow Ports
  parameter int unsigned NarrowDataWidth = 0,
  /// Data Width for the Wide Ports
  parameter int unsigned WideDataWidth   = 0,

  /// Number of Narrow Ports
  parameter int unsigned NumNarrowReq    = 0,
  /// Number of Wide Ports
  parameter int unsigned NumWideReq      = 0,

  /// Banking Factor for the Wide Ports (power of 2)
  parameter int unsigned NumWideBanks    = (1<<$clog2(NumWideReq))*2,
  /// Extra multiplier for the Narrow banking factor (baseline is WideWidth/NarrowWidth) (power of 2)
  parameter int unsigned NarrowExtraBF   = 1,
  /// Words per memory bank. (Total number of banks is (WideWidth/NarrowWidth)*NumWideBanks)
  parameter int unsigned WordsPerBank    = 1024,

  parameter int unsigned GearRatio       = 1,

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

  parameter bit          InternalCombRspReq   = 1'b1,

  parameter              MemorySimInit        = "none",

  // Derived, DO NOT OVERRIDE
  parameter int unsigned NarrowStrbWidth = NarrowDataWidth/8,
  parameter int unsigned WideStrbWidth   = WideDataWidth/8,
  parameter int unsigned NWDivisor       = WideDataWidth/NarrowDataWidth
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
  output logic [NumNarrowReq-1:0][NarrowDataWidth-1:0] narrow_rdata_o,

  // Wide inputs
  input  logic [  NumWideReq-1:0]                      wide_req_i,
  output logic [  NumWideReq-1:0]                      wide_gnt_o,
  input  logic [  NumWideReq-1:0][      AddrWidth-1:0] wide_addr_i,
  input  logic [  NumWideReq-1:0]                      wide_we_i,
  input  logic [  NumWideReq-1:0][  WideDataWidth-1:0] wide_wdata_i,
  input  logic [  NumWideReq-1:0][  WideStrbWidth-1:0] wide_strb_i,
  output logic [  NumWideReq-1:0]                      wide_rvalid_o,
  output logic [  NumWideReq-1:0][  WideDataWidth-1:0] wide_rdata_o
);

  typedef struct packed {
    logic [      AddrWidth-1:0] addr;
    logic                       we;
    logic [NarrowDataWidth-1:0] wdata;
    logic [NarrowStrbWidth-1:0] strb;
  } narrow_mem_req_t;

  typedef struct packed {
    logic [   AddrWidth-1:0] addr;
    logic                    we;
    logic [WideDataWidth-1:0] wdata;
    logic [WideStrbWidth-1:0] strb;
  } wide_mem_req_t;

  logic geared_clk;

  narrow_mem_req_t [NumNarrowReq-1:0] narrow_mem_req;
  narrow_mem_req_t [NumNarrowReq-1:0][GearRatio-1:0] narrow_mem_req_geared;
  logic [NumNarrowReq-1:0][GearRatio-1:0] narrow_req_geared;
  logic [NumNarrowReq-1:0][GearRatio-1:0] narrow_gnt_geared;
  logic [NumNarrowReq-1:0][GearRatio-1:0] narrow_rvalid_geared;
  logic [NumNarrowReq-1:0][GearRatio-1:0] narrow_rready_geared;
  logic [NumNarrowReq-1:0][GearRatio-1:0][NarrowDataWidth-1:0] narrow_rdata_geared;

  logic [NumNarrowReq-1:0][GearRatio-1:0] narrow_selected;
  logic [NumNarrowReq-1:0][cf_math_pkg::idx_width(GearRatio)-1:0] narrow_selected_bin;
  logic [NumNarrowReq-1:0][cf_math_pkg::idx_width(GearRatio)-1:0] narrow_selected_out;

  logic [GearRatio*NumNarrowReq-1:0]                      narrow_req_entry_geared;
  logic [GearRatio*NumNarrowReq-1:0]                      narrow_gnt_entry_geared;
  logic [GearRatio*NumNarrowReq-1:0][      AddrWidth-1:0] narrow_addr_entry_geared;
  logic [GearRatio*NumNarrowReq-1:0]                      narrow_we_entry_geared;
  logic [GearRatio*NumNarrowReq-1:0][NarrowDataWidth-1:0] narrow_wdata_entry_geared;
  logic [GearRatio*NumNarrowReq-1:0][NarrowStrbWidth-1:0] narrow_strb_entry_geared;
  logic [GearRatio*NumNarrowReq-1:0]                      narrow_rvalid_entry_geared;
  logic [GearRatio*NumNarrowReq-1:0]                      narrow_rready_entry_geared;
  logic [GearRatio*NumNarrowReq-1:0][NarrowDataWidth-1:0] narrow_rdata_entry_geared;

  wide_mem_req_t [NumWideReq-1:0] wide_mem_req;
  wide_mem_req_t [NumWideReq-1:0][GearRatio-1:0] wide_mem_req_geared;
  logic [NumWideReq-1:0][GearRatio-1:0] wide_req_geared;
  logic [NumWideReq-1:0][GearRatio-1:0] wide_gnt_geared;
  logic [NumWideReq-1:0][GearRatio-1:0] wide_rvalid_geared;
  logic [NumWideReq-1:0][GearRatio-1:0] wide_rready_geared;
  logic [NumWideReq-1:0][GearRatio-1:0][WideDataWidth-1:0] wide_rdata_geared;

  logic [GearRatio*  NumWideReq-1:0]                      wide_req_entry_geared;
  logic [GearRatio*  NumWideReq-1:0]                      wide_gnt_entry_geared;
  logic [GearRatio*  NumWideReq-1:0][      AddrWidth-1:0] wide_addr_entry_geared;
  logic [GearRatio*  NumWideReq-1:0]                      wide_we_entry_geared;
  logic [GearRatio*  NumWideReq-1:0][  WideDataWidth-1:0] wide_wdata_entry_geared;
  logic [GearRatio*  NumWideReq-1:0][  WideStrbWidth-1:0] wide_strb_entry_geared;
  logic [GearRatio*  NumWideReq-1:0]                      wide_rvalid_entry_geared;
  logic [GearRatio*  NumWideReq-1:0]                      wide_rready_entry_geared;
  logic [GearRatio*  NumWideReq-1:0][  WideDataWidth-1:0] wide_rdata_entry_geared;

  clk_int_div #(
    .DIV_VALUE_WIDTH       ( $clog2(GearRatio) ),
    .DEFAULT_DIV_VALUE     ( GearRatio         ),
    .ENABLE_CLOCK_IN_RESET ( 1'b1              )
  ) i_gear_clk_div (
    .clk_i,
    .rst_ni,
    .en_i           ( 1'b1       ),
    .test_mode_en_i ( 1'b0       ),
    .div_i          ( GearRatio  ),
    .div_valid_i    ( 1'b0       ),
    .div_ready_o    (),
    .clk_o          ( geared_clk ),
    .cycl_count_o   ()
  );

  for (genvar i = 0; i < NumNarrowReq; i++) begin : gen_narrow_gearing
    assign narrow_mem_req[i] = '{
      addr:  narrow_addr_i  [i],
      we:    narrow_we_i    [i],
      wdata: narrow_wdata_i [i],
      strb:  narrow_strb_i  [i]
    };

    geared_stream_split #(
      .GearRatio ( GearRatio        ),
      .T         ( narrow_mem_req_t )
    ) i_gear_split (
      .clk_i,
      .geared_clk_i   ( geared_clk               ),
      .rst_ni,
      .clr_i          ( '0                       ),

      .valid_i        ( narrow_req_i         [i] ),
      .ready_o        ( narrow_gnt_o         [i] ),
      .data_i         ( narrow_mem_req       [i] ),
      .selected_reg_o ( narrow_selected      [i] ),

      .valid_o        ( narrow_req_geared    [i] ),
      .ready_i        ( narrow_gnt_geared    [i] ),
      .data_o         ( narrow_mem_req_geared[i] )
    );

    for (genvar j = 0; j < GearRatio; j++) begin
      localparam id = i*GearRatio + j;
      assign narrow_req_entry_geared   [id]   = narrow_req_geared         [i][j];
      assign narrow_gnt_geared         [i][j] = narrow_gnt_entry_geared   [id];
      assign narrow_addr_entry_geared  [id]   = narrow_mem_req_geared     [i][j].addr;
      assign narrow_we_entry_geared    [id]   = narrow_mem_req_geared     [i][j].we;
      assign narrow_wdata_entry_geared [id]   = narrow_mem_req_geared     [i][j].wdata;
      assign narrow_strb_entry_geared  [id]   = narrow_mem_req_geared     [i][j].strb;
      assign narrow_rvalid_geared      [i][j] = narrow_rvalid_entry_geared[id];
      assign narrow_rready_entry_geared[id]   = narrow_rready_geared      [i][j];
      assign narrow_rdata_geared       [i][j] = narrow_rdata_entry_geared [id];
    end

    onehot_to_bin #(
      .ONEHOT_WIDTH ( GearRatio )
    ) i_gear_to_bin (
      .onehot ( narrow_selected    [i] ),
      .bin    ( narrow_selected_bin[i] )
    );

    fifo_v3 #(
      .FALL_THROUGH(1'b0),
      .DATA_WIDTH  ($clog2(GearRatio)),
      .DEPTH       () // TODO: NumOutstanding * GearRatio
    ) i_selection_fifo (
      .clk_i,
      .rst_ni,
      .flush_i   ('0),
      .testmode_i('0),
      .full_o    (),
      .empty_o   (),
      .usage_o   (),
      .data_i    (  narrow_selected_bin[i] ),
      .push_i    ( |narrow_selected    [i] ),
      .data_o    (  narrow_selected_out[i] ),
      .pop_i     (  narrow_rvalid_o    [i] )
    );

    geared_stream_collect #(
      .GearRatio ( GearRatio ),
      .T         ( logic [NarrowDataWidth-1:0] )
    ) i_gear_collect (
      .clk_i,
      .geared_clk_i  ( geared_clk ),
      .rst_ni,
      .clr_i         ('0),

      .valid_i       ( narrow_rvalid_geared  [i] ),
      .ready_o       ( narrow_rready_geared  [i] ),
      .data_i        ( narrow_rdata_geared   [i] ),

      .valid_o       ( narrow_rvalid_o       [i] ),
      .ready_i       ( 1'b1                      ),
      .data_o        ( narrow_rdata_o        [i] ),
      .selected_reg_i( 1<<narrow_selected_out[i] ),
    );
  end

  for (genvar i = 0; i < NumWideReq; i++) begin : gen_wide_gearing
    assign wide_mem_req[i] = '{
      addr:  wide_addr_i  [i],
      we:    wide_we_i    [i],
      wdata: wide_wdata_i [i],
      strb:  wide_strb_i  [i]
    };

    geared_stream_split #(
      .GearRatio ( GearRatio        ),
      .T         ( wide_mem_req_t )
    ) i_gear_split (
      .clk_i,
      .geared_clk_i   ( geared_clk             ),
      .rst_ni,
      .clr_i          ( '0                     ),

      .valid_i        ( wide_req_i         [i] ),
      .ready_o        ( wide_gnt_o         [i] ),
      .data_i         ( wide_mem_req       [i] ),
      .selected_reg_o ( wide_selected      [i] ),

      .valid_o        ( wide_req_geared    [i] ),
      .ready_i        ( wide_gnt_geared    [i] ),
      .data_o         ( wide_mem_req_geared[i] )
    );

    for (genvar j = 0; j < GearRatio; j++) begin
      localparam id = i*GearRatio + j;
      assign wide_req_entry_geared   [id]   = wide_req_geared         [i][j];
      assign wide_gnt_geared         [i][j] = wide_gnt_entry_geared   [id];
      assign wide_addr_entry_geared  [id]   = wide_mem_req_geared     [i][j].addr;
      assign wide_we_entry_geared    [id]   = wide_mem_req_geared     [i][j].we;
      assign wide_wdata_entry_geared [id]   = wide_mem_req_geared     [i][j].wdata;
      assign wide_strb_entry_geared  [id]   = wide_mem_req_geared     [i][j].strb;
      assign wide_rvalid_geared      [i][j] = wide_rvalid_entry_geared[id];
      assign wide_rready_entry_geared[id]   = wide_rready_geared      [i][j];
      assign wide_rdata_geared       [i][j] = wide_rdata_entry_geared [id];
    end

    onehot_to_bin #(
      .ONEHOT_WIDTH ( GearRatio )
    ) i_gear_to_bin (
      .onehot ( wide_selected    [i] ),
      .bin    ( wide_selected_bin[i] )
    );

    fifo_v3 #(
      .FALL_THROUGH(1'b0),
      .DATA_WIDTH  ($clog2(GearRatio)),
      .DEPTH       () // TODO: NumOutstanding * GearRatio
    ) i_selection_fifo (
      .clk_i,
      .rst_ni,
      .flush_i   ('0),
      .testmode_i('0),
      .full_o    (),
      .empty_o   (),
      .usage_o   (),
      .data_i    (  wide_selected_bin[i] ),
      .push_i    ( |wide_selected    [i] ),
      .data_o    (  wide_selected_out[i] ),
      .pop_i     (  wide_rvalid_o    [i] )
    );

    geared_stream_collect #(
      .GearRatio ( GearRatio ),
      .T         ( logic [WideDataWidth-1:0] )
    ) i_gear_collect (
      .clk_i,
      .geared_clk_i  ( geared_clk              ),
      .rst_ni,
      .clr_i         ('0),

      .valid_i       ( wide_rvalid_geared  [i] ),
      .ready_o       ( wide_rready_geared  [i] ),
      .data_i        ( wide_rdata_geared   [i] ),

      .valid_o       ( wide_rvalid_o       [i] ),
      .ready_i       ( 1'b1                    ),
      .data_o        ( wide_rdata_o        [i] ),
      .selected_reg_i( 1<<wide_selected_out[i] ),
    );
  end


  memory_island_core_rready_wrap #(
    .AddrWidth            ( AddrWidth              ),
    .NarrowDataWidth      ( NarrowDataWidth        ),
    .WideDataWidth        ( WideDataWidth          ),

    .NumNarrowReq         ( NumNarrowReq*GearRatio ),
    .NumWideReq           ( NumWideReq*GearRatio   ),

    .NumWideBanks         ( NumWideBanks           ),
    .NarrowExtraBF        ( NarrowExtraBF          ),
    .WordsPerBank         ( WordsPerBank           ),

    .SpillNarrowReqEntry  ( SpillNarrowReqEntry    ),
    .SpillNarrowRspEntry  ( SpillNarrowRspEntry    ),
    .SpillNarrowReqRouted ( SpillNarrowReqRouted   ),
    .SpillNarrowRspRouted ( SpillNarrowRspRouted   ),
    .SpillWideReqEntry    ( SpillWideReqEntry      ),
    .SpillWideRspEntry    ( SpillWideRspEntry      ),
    .SpillWideReqRouted   ( SpillWideReqRouted     ),
    .SpillWideRspRouted   ( SpillWideRspRouted     ),
    .SpillWideReqSplit    ( SpillWideReqSplit      ),
    .SpillWideRspSplit    ( SpillWideRspSplit      ),
    .SpillReqBank         ( SpillReqBank           ),
    .SpillRspBank         ( SpillRspBank           ),

    .CombRspReq           ( InternalCombRspReq     ),

    .MemorySimInit        ( MemorySimInit          )
  ) i_memory_island_core (
    .clk_i           ( geared_clk                 ),
    .rst_ni,
    .narrow_req_i    ( narrow_req_entry_geared    ),
    .narrow_gnt_o    ( narrow_gnt_entry_geared    ),
    .narrow_addr_i   ( narrow_addr_entry_geared   ),
    .narrow_we_i     ( narrow_we_entry_geared     ),
    .narrow_wdata_i  ( narrow_wdata_entry_geared  ),
    .narrow_strb_i   ( narrow_strb_entry_geared   ),
    .narrow_rvalid_o ( narrow_rvalid_entry_geared ),
    .narrow_rready_i ( narrow_rready_entry_geared ),
    .narrow_rdata_o  ( narrow_rdata_entry_geared  ),
    .wide_req_i      ( wide_req_entry_geared      ),
    .wide_gnt_o      ( wide_gnt_entry_geared      ),
    .wide_addr_i     ( wide_addr_entry_geared     ),
    .wide_we_i       ( wide_we_entry_geared       ),
    .wide_wdata_i    ( wide_wdata_entry_geared    ),
    .wide_strb_i     ( wide_strb_entry_geared     ),
    .wide_rvalid_o   ( wide_rvalid_entry_geared   ),
    .wide_rready_i   ( wide_rready_entry_geared   ),
    .wide_rdata_o    ( wide_rdata_entry_geared    )
  );

endmodule
