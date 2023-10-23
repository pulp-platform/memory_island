// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

module memory_island_core #(
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

  /// Spill Narrow
  parameter int unsigned SpillNarrowReqEntry = 0,
  parameter int unsigned SpillNarrowRspEntry = 0,
  parameter int unsigned SpillNarrowReqRouted = 0,
  parameter int unsigned SpillNarrowRspRouted = 0,

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
  input  logic [NumWideReq-1:0]                    wide_req_i,
  output logic [NumWideReq-1:0]                    wide_gnt_o,
  input  logic [NumWideReq-1:0][    AddrWidth-1:0] wide_addr_i,
  input  logic [NumWideReq-1:0]                    wide_we_i,
  input  logic [NumWideReq-1:0][WideDataWidth-1:0] wide_wdata_i,
  input  logic [NumWideReq-1:0][WideStrbWidth-1:0] wide_strb_i,
  output logic [NumWideReq-1:0]                    wide_rvalid_o,
  output logic [NumWideReq-1:0][WideDataWidth-1:0] wide_rdata_o
);

  localparam int unsigned WidePseudoBanks = NWDivisor * NarrowExtraBF;
  localparam int unsigned TotalBanks = NWDivisor * NumWideBanks;

  // Addr: GlobalBits _ InBankAddr _ WideBankSel _ NarrowBankSel _ Strb
  localparam int unsigned AddrNarrowWordBit = $clog2(NarrowDataWidth/8);
  localparam int unsigned AddrWideWordBit   = $clog2(WideDataWidth/8);
  localparam int unsigned AddrNarrowWideBit = AddrWideWordBit + $clog2(NarrowExtraBF);
  localparam int unsigned AddrWideBankBit   = AddrWideWordBit + $clog2(NumWideBanks);
  localparam int unsigned AddrTopBit        = AddrWideBankBit + $clog2(WordsPerBank);

  localparam int unsigned NarrowAddrMemWidth = AddrTopBit-AddrNarrowWideBit;
  localparam int unsigned BankAddrMemWidth   = $clog2(WordsPerBank);

  localparam int unsigned NarrowIntcBankLat = 1+SpillNarrowReqRouted+SpillNarrowRspRouted;

  logic [   NumNarrowReq-1:0]                                        narrow_req_cut;
  logic [   NumNarrowReq-1:0]                                        narrow_gnt_cut;
  logic [   NumNarrowReq-1:0]               [         AddrWidth-1:0] narrow_addr_cut;
  logic [   NumNarrowReq-1:0]                                        narrow_we_cut;
  logic [   NumNarrowReq-1:0]               [   NarrowDataWidth-1:0] narrow_wdata_cut;
  logic [   NumNarrowReq-1:0]               [   NarrowStrbWidth-1:0] narrow_strb_cut;
  logic [   NumNarrowReq-1:0]                                        narrow_rvalid_cut;
  logic [   NumNarrowReq-1:0]               [   NarrowDataWidth-1:0] narrow_rdata_cut;

  logic [     NumWideReq-1:0]                                        wide_req_cut;
  logic [     NumWideReq-1:0]                                        wide_gnt_cut;
  logic [     NumWideReq-1:0]               [         AddrWidth-1:0] wide_addr_cut;
  logic [     NumWideReq-1:0]                                        wide_we_cut;
  logic [     NumWideReq-1:0]               [     WideDataWidth-1:0] wide_wdata_cut;
  logic [     NumWideReq-1:0]               [     WideStrbWidth-1:0] wide_strb_cut;
  logic [     NumWideReq-1:0]                                        wide_rvalid_cut;
  logic [     NumWideReq-1:0]               [     WideDataWidth-1:0] wide_rdata_cut;

  logic [WidePseudoBanks-1:0]                                        narrow_req_intc;
  logic [WidePseudoBanks-1:0]                                        narrow_gnt_intc;
  logic [WidePseudoBanks-1:0]               [NarrowAddrMemWidth-1:0] narrow_addr_intc;
  logic [WidePseudoBanks-1:0]                                        narrow_we_intc;
  logic [WidePseudoBanks-1:0]               [   NarrowDataWidth-1:0] narrow_wdata_intc;
  logic [WidePseudoBanks-1:0]               [   NarrowStrbWidth-1:0] narrow_strb_intc;
  logic [WidePseudoBanks-1:0]                                        narrow_rvalid_intc;
  logic [WidePseudoBanks-1:0]               [   NarrowDataWidth-1:0] narrow_rdata_intc;

  logic [WidePseudoBanks-1:0]                                        narrow_req_intc_cut;
  logic [WidePseudoBanks-1:0]                                        narrow_gnt_intc_cut;
  logic [WidePseudoBanks-1:0]               [NarrowAddrMemWidth-1:0] narrow_addr_intc_cut;
  logic [WidePseudoBanks-1:0]                                        narrow_we_intc_cut;
  logic [WidePseudoBanks-1:0]               [   NarrowDataWidth-1:0] narrow_wdata_intc_cut;
  logic [WidePseudoBanks-1:0]               [   NarrowStrbWidth-1:0] narrow_strb_intc_cut;
  logic [WidePseudoBanks-1:0]                                        narrow_rvalid_intc_cut;
  logic [WidePseudoBanks-1:0]               [   NarrowDataWidth-1:0] narrow_rdata_intc_cut;

  logic [   NumWideBanks-1:0]                                        wide_req_intc;
  logic [   NumWideBanks-1:0]                                        wide_gnt_intc;
  logic [   NumWideBanks-1:0]               [  BankAddrMemWidth-1:0] wide_addr_intc;
  logic [   NumWideBanks-1:0]                                        wide_we_intc;
  logic [   NumWideBanks-1:0]               [     WideDataWidth-1:0] wide_wdata_intc;
  logic [   NumWideBanks-1:0]               [     WideStrbWidth-1:0] wide_strb_intc;
  logic [   NumWideBanks-1:0]                                        wide_rvalid_intc;
  logic [   NumWideBanks-1:0]                                        wide_rready_intc;
  logic [   NumWideBanks-1:0]               [     WideDataWidth-1:0] wide_rdata_intc;

  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         narrow_req_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][  BankAddrMemWidth-1:0] narrow_addr_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         narrow_we_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowDataWidth-1:0] narrow_wdata_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowStrbWidth-1:0] narrow_strb_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowDataWidth-1:0] narrow_rdata_bank;

  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         wide_req_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         wide_gnt_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][  BankAddrMemWidth-1:0] wide_addr_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         wide_we_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowDataWidth-1:0] wide_wdata_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowStrbWidth-1:0] wide_strb_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         wide_rvalid_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowDataWidth-1:0] wide_rdata_bank;

  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         req_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][  BankAddrMemWidth-1:0] addr_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         we_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowDataWidth-1:0] wdata_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowStrbWidth-1:0] strb_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         rvalid_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowDataWidth-1:0] rdata_bank;

  for (genvar i = 0; i < NumNarrowReq; i++) begin
    mem_req_multicut #(
      .DataWidth( NarrowDataWidth ),
      .AddrWidth( AddrWidth       ),
      .NumCuts  ( SpillNarrowReqEntry )
    ) i_cut_narrow_req_entry (
      .clk_i,
      .rst_ni,

      .req_i   ( narrow_req_i    [i] ),
      .gnt_o   ( narrow_gnt_o    [i] ),
      .addr_i  ( narrow_addr_i   [i] ),
      .we_i    ( narrow_we_i     [i] ),
      .wdata_i ( narrow_wdata_i  [i] ),
      .strb_i  ( narrow_strb_i   [i] ),

      .req_o   ( narrow_req_cut  [i] ),
      .gnt_i   ( narrow_gnt_cut  [i] ),
      .addr_o  ( narrow_addr_cut [i] ),
      .we_o    ( narrow_we_cut   [i] ),
      .wdata_o ( narrow_wdata_cut[i] ),
      .strb_o  ( narrow_strb_cut [i] )
    );
    mem_rsp_multicut #(
      .DataWidth ( NarrowDataWidth     ),
      .NumCuts   ( SpillNarrowRspEntry )
    ) i_cut_narrow_rsp_entry (
      .clk_i,
      .rst_ni,

      .rvalid_i ( narrow_rvalid_cut[i] ),
      .rready_o (),
      .rdata_i  ( narrow_rdata_cut [i] ),

      .rvalid_o ( narrow_rvalid_o  [i] ),
      .rready_i ( 1'b1                 ),
      .rdata_o  ( narrow_rdata_o   [i] )
    );
  end

  assign wide_req_cut   = wide_req_i;
  assign wide_gnt_o     = wide_gnt_cut;
  assign wide_addr_cut  = wide_addr_i;
  assign wide_we_cut    = wide_we_i;
  assign wide_wdata_cut = wide_wdata_i;
  assign wide_strb_cut  = wide_strb_i;
  assign wide_rvalid_o  = wide_rvalid_cut;
  assign wide_rdata_o   = wide_rdata_cut;


  // Narrow interconnect
  // Fixed latency as higher priority for narrow accesses
  tcdm_interconnect #(
    .NumIn       ( NumNarrowReq               ),
    .NumOut      ( WidePseudoBanks            ),
    .AddrWidth   ( AddrWidth                  ),
    .DataWidth   ( NarrowDataWidth            ),
    .BeWidth     ( NarrowStrbWidth            ),
    .AddrMemWidth( NarrowAddrMemWidth         ),
    .WriteRespOn ( 1                          ),
    .RespLat     ( NarrowIntcBankLat          ),
    .Topology    ( tcdm_interconnect_pkg::LIC )
  ) i_narrow_interco (
    .clk_i,
    .rst_ni,

    .req_i  ( narrow_req_cut    ),
    .add_i  ( narrow_addr_cut   ),
    .wen_i  ( narrow_we_cut     ),
    .wdata_i( narrow_wdata_cut  ),
    .be_i   ( narrow_strb_cut   ),
    .gnt_o  ( narrow_gnt_cut    ),
    .vld_o  ( narrow_rvalid_cut ),
    .rdata_o( narrow_rdata_cut  ),

    .req_o  ( narrow_req_intc   ),
    .gnt_i  ( narrow_gnt_intc   ),
    .add_o  ( narrow_addr_intc  ),
    .wen_o  ( narrow_we_intc    ),
    .wdata_o( narrow_wdata_intc ),
    .be_o   ( narrow_strb_intc  ),
    .rdata_i( narrow_rdata_intc )
  );

  for (genvar i = 0; i < WidePseudoBanks; i++) begin : gen_spill_narrow_routed
    mem_req_multicut #(
      .AddrWidth ( NarrowAddrMemWidth   ),
      .DataWidth ( NarrowDataWidth      ),
      .NumCuts   ( SpillNarrowReqRouted )
    ) i_narrow_routed_req_cut (
      .clk_i,
      .rst_ni,

      .req_i  ( narrow_req_intc      [i] ),
      .gnt_o  ( narrow_gnt_intc      [i] ),
      .addr_i ( narrow_addr_intc     [i] ),
      .we_i   ( narrow_we_intc       [i] ),
      .wdata_i( narrow_wdata_intc    [i] ),
      .strb_i ( narrow_strb_intc     [i] ),

      .req_o  ( narrow_req_intc_cut  [i] ),
      .gnt_i  ( narrow_gnt_intc_cut  [i] ),
      .addr_o ( narrow_addr_intc_cut [i] ),
      .we_o   ( narrow_we_intc_cut   [i] ),
      .wdata_o( narrow_wdata_intc_cut[i] ),
      .strb_o ( narrow_strb_intc_cut [i] )
    );

    mem_rsp_multicut #(
      .DataWidth ( NarrowDataWidth      ),
      .NumCuts   ( SpillNarrowRspRouted )
    ) i_narrow_routed_rsp_cut (
      .clk_i,
      .rst_ni,

      .rvalid_i( narrow_rvalid_intc_cut[i] ),
      .rready_o(),
      .rdata_i ( narrow_rdata_intc_cut [i] ),

      .rvalid_o( narrow_rvalid_intc    [i] ),
      .rready_i( 1'b1 ),
      .rdata_o ( narrow_rdata_intc     [i] )
    );
  end

  // narrow gnt always set
  assign narrow_gnt_intc_cut = '1;

  localparam int unsigned NarrowWideBankSelWidth = AddrWideBankBit-AddrNarrowWideBit;

  for (genvar i = 0; i < TotalBanks/WidePseudoBanks; i++) begin : gen_narrow_intc_bank_l1
    for (genvar j = 0; j < NarrowExtraBF; j++) begin : gen_narrow_intc_bank_l2
      for (genvar k = 0; k < NWDivisor; k++) begin : gen_narrow_intc_bank_l3
        assign narrow_req_bank  [(i*NarrowExtraBF)+j][k] = narrow_req_intc_cut  [(j*NWDivisor) + k] &
                                                          (narrow_addr_intc_cut [(j*NWDivisor) + k][NarrowWideBankSelWidth-1:0] == i);
        assign narrow_addr_bank [(i*NarrowExtraBF)+j][k] = narrow_addr_intc_cut [(j*NWDivisor) + k][AddrTopBit-AddrNarrowWideBit-1:NarrowWideBankSelWidth];
        assign narrow_we_bank   [(i*NarrowExtraBF)+j][k] = narrow_we_intc_cut   [(j*NWDivisor) + k];
        assign narrow_wdata_bank[(i*NarrowExtraBF)+j][k] = narrow_wdata_intc_cut[(j*NWDivisor) + k];
        assign narrow_strb_bank [(i*NarrowExtraBF)+j][k] = narrow_strb_intc_cut [(j*NWDivisor) + k];
      end
    end
  end

  for (genvar j = 0; j < NarrowExtraBF; j++) begin : gen_narrow_intc_bank_rdata_l1
    for (genvar k = 0; k < NWDivisor; k++) begin : gen_narrow_intc_bank_rdata_l2
      logic [NarrowWideBankSelWidth-1:0] narrow_rdata_sel;
      shift_reg #(
        .dtype ( logic [NarrowWideBankSelWidth-1:0] ),
        .Depth ( NarrowIntcBankLat                  )
      ) i_narrow_rdata_sel (
        .clk_i,
        .rst_ni,
        .d_i   ( narrow_addr_intc_cut [(j*NWDivisor) + k][NarrowWideBankSelWidth-1:0] ),
        .d_o   ( narrow_rdata_sel                                                     )
      );
      assign narrow_rdata_intc_cut[(j*NWDivisor) + k] = narrow_rdata_bank[(narrow_rdata_sel*NarrowExtraBF) + j][k];
    end
  end

  // Wide interconnect
  varlat_inorder_interco #(
    .NumIn              ( NumWideReq                 ),
    .NumOut             ( NumWideBanks               ),
    .AddrWidth          ( AddrWidth                  ),
    .DataWidth          ( WideDataWidth              ),
    .BeWidth            ( WideStrbWidth              ),
    .AddrMemWidth       ( BankAddrMemWidth           ),
    .WriteRespOn        ( 1                          ),
    .NumOutstanding     ( 3                          ),
    .Topology           ( tcdm_interconnect_pkg::LIC )
  ) i_wide_interco (
    .clk_i,
    .rst_ni,

    .req_i   ( wide_req_cut    ),
    .add_i   ( wide_addr_cut   ),
    .we_i    ( wide_we_cut     ),
    .wdata_i ( wide_wdata_cut  ),
    .be_i    ( wide_strb_cut   ),
    .gnt_o   ( wide_gnt_cut    ),
    .vld_o   ( wide_rvalid_cut ),
    .rdata_o ( wide_rdata_cut  ),

    .req_o   ( wide_req_intc    ),
    .gnt_i   ( wide_gnt_intc    ),
    .add_o   ( wide_addr_intc   ),
    .we_o    ( wide_we_intc     ),
    .wdata_o ( wide_wdata_intc  ),
    .be_o    ( wide_strb_intc   ),
    .rvalid_i( wide_rvalid_intc ),
    .rready_o( wide_rready_intc ),
    .rdata_i ( wide_rdata_intc  )
  );

  for (genvar i = 0; i < NumWideBanks; i++) begin : gen_wide_banks
    logic [NWDivisor-1:0][BankAddrMemWidth + AddrWideWordBit-1:0] bank_addr_tmp;
    for (genvar j = 0; j < NWDivisor; j++) begin
      assign wide_addr_bank[i][j] = bank_addr_tmp [j][AddrWideWordBit+:BankAddrMemWidth];
    end
    // Split wide requests to banks
    stream_mem_to_banks_det #(
      .AddrWidth  ( BankAddrMemWidth + AddrWideWordBit ),
      .DataWidth  ( WideDataWidth                      ),
      .WUserWidth ( 1                                  ),
      .RUserWidth ( 1                                  ),
      .NumBanks   ( NWDivisor                          ),
      .HideStrb   ( 1'b1                               ),
      .MaxTrans   ( 2                                  ), // TODO tune?
      .FifoDepth  ( 3                                  )  // TODO tune?
    ) i_wide_to_banks (
      .clk_i,
      .rst_ni,

      .req_i        ( wide_req_intc   [i]                           ),
      .gnt_o        ( wide_gnt_intc   [i]                           ),
      .addr_i       ( {wide_addr_intc [i], {AddrWideWordBit{1'b0}}} ),
      .wdata_i      ( wide_wdata_intc [i]                           ),
      .strb_i       ( wide_strb_intc  [i]                           ),
      .wuser_i      ( '0 ),
      .we_i         ( wide_we_intc    [i]                           ),
      .rvalid_o     ( wide_rvalid_intc[i]                           ),
      .rready_i     ( wide_rready_intc[i]                           ),
      .ruser_o      (),
      .rdata_o      ( wide_rdata_intc [i]                           ),
      .bank_req_o   ( wide_req_bank   [i]                           ),
      .bank_gnt_i   ( wide_gnt_bank   [i]                           ),
      .bank_addr_o  ( bank_addr_tmp                                 ),
      .bank_wdata_o ( wide_wdata_bank [i]                           ),
      .bank_strb_o  ( wide_strb_bank  [i]                           ),
      .bank_wuser_o (),
      .bank_we_o    ( wide_we_bank    [i]                           ),
      .bank_rvalid_i( wide_rvalid_bank[i]                           ),
      .bank_rdata_i ( wide_rdata_bank [i]                           ),
      .bank_ruser_i ( '0                                            )
    );
    for (genvar j = 0; j < NWDivisor; j++) begin : gen_narrow_banks
      // narrow/wide arbitration, narrow always has priority
      assign req_bank         [i][j] =  narrow_req_bank[i][j] | wide_req_bank[i][j];
      assign wide_gnt_bank    [i][j] = ~narrow_req_bank[i][j];
      assign we_bank          [i][j] =  narrow_req_bank[i][j] ? narrow_we_bank   [i][j] : wide_we_bank   [i][j];
      assign addr_bank        [i][j] =  narrow_req_bank[i][j] ? narrow_addr_bank [i][j] : wide_addr_bank [i][j];
      assign wdata_bank       [i][j] =  narrow_req_bank[i][j] ? narrow_wdata_bank[i][j] : wide_wdata_bank[i][j];
      assign strb_bank        [i][j] =  narrow_req_bank[i][j] ? narrow_strb_bank [i][j] : wide_strb_bank [i][j];
      assign narrow_rdata_bank[i][j] =  rdata_bank     [i][j];
      assign wide_rdata_bank  [i][j] =  rdata_bank     [i][j];

      // Memory bank
      tc_sram #(
        .NumWords  ( WordsPerBank    ),
        .DataWidth ( NarrowDataWidth ),
        .ByteWidth ( 8               ),
        .NumPorts  ( 1               ),
        .Latency   ( 1               )
      ) i_bank (
        .clk_i,
        .rst_ni,
        .req_i   ( req_bank  [i][j] ),
        .we_i    ( we_bank   [i][j] ),
        .addr_i  ( addr_bank [i][j] ),
        .wdata_i ( wdata_bank[i][j] ),
        .be_i    ( strb_bank [i][j] ),
        .rdata_o ( rdata_bank[i][j] )
      );

      always_ff @(posedge clk_i or negedge rst_ni) begin : proc_wide_bank_rvalid
        if(~rst_ni) begin
          wide_rvalid_bank[i][j] <= 0;
        end else begin
          wide_rvalid_bank[i][j] <= req_bank[i][j] & wide_gnt_bank[i][j];
        end
      end
    end
  end

endmodule
