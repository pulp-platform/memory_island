// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

module memory_island_core #(
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

  parameter              MemorySimInit        = "none",

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

  localparam int unsigned NarrowIntcBankLat = 1+SpillNarrowReqRouted+SpillNarrowRspRouted+SpillReqBank+SpillRspBank;

  logic [   NumNarrowReq-1:0]                                        narrow_req_entry_spill;
  logic [   NumNarrowReq-1:0]                                        narrow_gnt_entry_spill;
  logic [   NumNarrowReq-1:0]               [         AddrWidth-1:0] narrow_addr_entry_spill;
  logic [   NumNarrowReq-1:0]                                        narrow_we_entry_spill;
  logic [   NumNarrowReq-1:0]               [   NarrowDataWidth-1:0] narrow_wdata_entry_spill;
  logic [   NumNarrowReq-1:0]               [   NarrowStrbWidth-1:0] narrow_strb_entry_spill;
  logic [   NumNarrowReq-1:0]                                        narrow_rvalid_entry_spill;
  logic [   NumNarrowReq-1:0]               [   NarrowDataWidth-1:0] narrow_rdata_entry_spill;

  logic [     NumWideReq-1:0]                                        wide_req_entry_spill;
  logic [     NumWideReq-1:0]                                        wide_gnt_entry_spill;
  logic [     NumWideReq-1:0]               [         AddrWidth-1:0] wide_addr_entry_spill;
  logic [     NumWideReq-1:0]                                        wide_we_entry_spill;
  logic [     NumWideReq-1:0]               [     WideDataWidth-1:0] wide_wdata_entry_spill;
  logic [     NumWideReq-1:0]               [     WideStrbWidth-1:0] wide_strb_entry_spill;
  logic [     NumWideReq-1:0]                                        wide_rvalid_entry_spill;
  logic [     NumWideReq-1:0]               [     WideDataWidth-1:0] wide_rdata_entry_spill;

  logic [WidePseudoBanks-1:0]                                        narrow_req_routed;
  logic [WidePseudoBanks-1:0]                                        narrow_gnt_routed;
  logic [WidePseudoBanks-1:0]               [NarrowAddrMemWidth-1:0] narrow_addr_routed;
  logic [WidePseudoBanks-1:0]                                        narrow_we_routed;
  logic [WidePseudoBanks-1:0]               [   NarrowDataWidth-1:0] narrow_wdata_routed;
  logic [WidePseudoBanks-1:0]               [   NarrowStrbWidth-1:0] narrow_strb_routed;
  logic [WidePseudoBanks-1:0]                                        narrow_rvalid_routed;
  logic [WidePseudoBanks-1:0]               [   NarrowDataWidth-1:0] narrow_rdata_routed;

  logic [WidePseudoBanks-1:0]                                        narrow_req_routed_spill;
  logic [WidePseudoBanks-1:0]                                        narrow_gnt_routed_spill;
  logic [WidePseudoBanks-1:0]               [NarrowAddrMemWidth-1:0] narrow_addr_routed_spill;
  logic [WidePseudoBanks-1:0]                                        narrow_we_routed_spill;
  logic [WidePseudoBanks-1:0]               [   NarrowDataWidth-1:0] narrow_wdata_routed_spill;
  logic [WidePseudoBanks-1:0]               [   NarrowStrbWidth-1:0] narrow_strb_routed_spill;
  logic [WidePseudoBanks-1:0]                                        narrow_rvalid_routed_spill;
  logic [WidePseudoBanks-1:0]               [   NarrowDataWidth-1:0] narrow_rdata_routed_spill;

  logic [   NumWideBanks-1:0]                                        wide_req_routed;
  logic [   NumWideBanks-1:0]                                        wide_gnt_routed;
  logic [   NumWideBanks-1:0]               [  BankAddrMemWidth-1:0] wide_addr_routed;
  logic [   NumWideBanks-1:0]                                        wide_we_routed;
  logic [   NumWideBanks-1:0]               [     WideDataWidth-1:0] wide_wdata_routed;
  logic [   NumWideBanks-1:0]               [     WideStrbWidth-1:0] wide_strb_routed;
  logic [   NumWideBanks-1:0]                                        wide_rvalid_routed;
  logic [   NumWideBanks-1:0]                                        wide_rready_routed;
  logic [   NumWideBanks-1:0]               [     WideDataWidth-1:0] wide_rdata_routed;

  logic [   NumWideBanks-1:0]                                        wide_req_routed_spill;
  logic [   NumWideBanks-1:0]                                        wide_gnt_routed_spill;
  logic [   NumWideBanks-1:0]               [  BankAddrMemWidth-1:0] wide_addr_routed_spill;
  logic [   NumWideBanks-1:0]                                        wide_we_routed_spill;
  logic [   NumWideBanks-1:0]               [     WideDataWidth-1:0] wide_wdata_routed_spill;
  logic [   NumWideBanks-1:0]               [     WideStrbWidth-1:0] wide_strb_routed_spill;
  logic [   NumWideBanks-1:0]                                        wide_rvalid_routed_spill;
  logic [   NumWideBanks-1:0]                                        wide_rready_routed_spill;
  logic [   NumWideBanks-1:0]               [     WideDataWidth-1:0] wide_rdata_routed_spill;

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

  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         wide_req_bank_spill;
  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         wide_gnt_bank_spill;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][  BankAddrMemWidth-1:0] wide_addr_bank_spill;
  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         wide_we_bank_spill;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowDataWidth-1:0] wide_wdata_bank_spill;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowStrbWidth-1:0] wide_strb_bank_spill;
  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         wide_rvalid_bank_spill;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowDataWidth-1:0] wide_rdata_bank_spill;

  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         req_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][  BankAddrMemWidth-1:0] addr_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         we_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowDataWidth-1:0] wdata_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowStrbWidth-1:0] strb_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         rvalid_bank;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowDataWidth-1:0] rdata_bank;

  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         req_bank_spill;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][  BankAddrMemWidth-1:0] addr_bank_spill;
  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         we_bank_spill;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowDataWidth-1:0] wdata_bank_spill;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowStrbWidth-1:0] strb_bank_spill;
  logic [   NumWideBanks-1:0][NWDivisor-1:0]                         rvalid_bank_spill;
  logic [   NumWideBanks-1:0][NWDivisor-1:0][   NarrowDataWidth-1:0] rdata_bank_spill;

  for (genvar i = 0; i < NumNarrowReq; i++) begin
    mem_req_multicut #(
      .DataWidth ( NarrowDataWidth     ),
      .AddrWidth ( AddrWidth           ),
      .NumCuts   ( SpillNarrowReqEntry )
    ) i_spill_narrow_req_entry (
      .clk_i,
      .rst_ni,

      .req_i   ( narrow_req_i            [i] ),
      .gnt_o   ( narrow_gnt_o            [i] ),
      .addr_i  ( narrow_addr_i           [i] ),
      .we_i    ( narrow_we_i             [i] ),
      .wdata_i ( narrow_wdata_i          [i] ),
      .strb_i  ( narrow_strb_i           [i] ),

      .req_o   ( narrow_req_entry_spill  [i] ),
      .gnt_i   ( narrow_gnt_entry_spill  [i] ),
      .addr_o  ( narrow_addr_entry_spill [i] ),
      .we_o    ( narrow_we_entry_spill   [i] ),
      .wdata_o ( narrow_wdata_entry_spill[i] ),
      .strb_o  ( narrow_strb_entry_spill [i] )
    );
    mem_rsp_multicut #(
      .DataWidth ( NarrowDataWidth     ),
      .NumCuts   ( SpillNarrowRspEntry )
    ) i_spill_narrow_rsp_entry (
      .clk_i,
      .rst_ni,

      .rvalid_i ( narrow_rvalid_entry_spill[i] ),
      .rready_o (),
      .rdata_i  ( narrow_rdata_entry_spill [i] ),

      .rvalid_o ( narrow_rvalid_o          [i] ),
      .rready_i ( 1'b1                         ),
      .rdata_o  ( narrow_rdata_o           [i] )
    );
  end

  for (genvar i = 0; i < NumWideReq; i++) begin
    mem_req_multicut #(
      .DataWidth ( WideDataWidth     ),
      .AddrWidth ( AddrWidth         ),
      .NumCuts   ( SpillWideReqEntry )
    ) i_spill_wide_req_entry (
      .clk_i,
      .rst_ni,

      .req_i   ( wide_req_i            [i] ),
      .gnt_o   ( wide_gnt_o            [i] ),
      .addr_i  ( wide_addr_i           [i] ),
      .we_i    ( wide_we_i             [i] ),
      .wdata_i ( wide_wdata_i          [i] ),
      .strb_i  ( wide_strb_i           [i] ),

      .req_o   ( wide_req_entry_spill  [i] ),
      .gnt_i   ( wide_gnt_entry_spill  [i] ),
      .addr_o  ( wide_addr_entry_spill [i] ),
      .we_o    ( wide_we_entry_spill   [i] ),
      .wdata_o ( wide_wdata_entry_spill[i] ),
      .strb_o  ( wide_strb_entry_spill [i] )
    );
    mem_rsp_multicut #(
      .DataWidth ( WideDataWidth     ),
      .NumCuts   ( SpillWideRspEntry )
    ) i_spill_wide_rsp_entry (
      .clk_i,
      .rst_ni,

      .rvalid_i ( wide_rvalid_entry_spill[i] ),
      .rready_o (),
      .rdata_i  ( wide_rdata_entry_spill [i] ),

      .rvalid_o ( wide_rvalid_o          [i] ),
      .rready_i ( 1'b1                       ),
      .rdata_o  ( wide_rdata_o           [i] )
    );
  end

  // Narrow interconnect
  // Fixed latency as higher priority for narrow accesses
  tcdm_interconnect #(
    .NumIn        ( NumNarrowReq               ),
    .NumOut       ( WidePseudoBanks            ),
    .AddrWidth    ( AddrWidth                  ),
    .DataWidth    ( NarrowDataWidth            ),
    .BeWidth      ( NarrowStrbWidth            ),
    .AddrMemWidth ( NarrowAddrMemWidth         ),
    .WriteRespOn  ( 1                          ),
    .RespLat      ( NarrowIntcBankLat          ),
    .Topology     ( tcdm_interconnect_pkg::LIC )
  ) i_narrow_interco (
    .clk_i,
    .rst_ni,

    .req_i   ( narrow_req_entry_spill    ),
    .add_i   ( narrow_addr_entry_spill   ),
    .wen_i   ( narrow_we_entry_spill     ),
    .wdata_i ( narrow_wdata_entry_spill  ),
    .be_i    ( narrow_strb_entry_spill   ),
    .gnt_o   ( narrow_gnt_entry_spill    ),
    .vld_o   ( narrow_rvalid_entry_spill ),
    .rdata_o ( narrow_rdata_entry_spill  ),

    .req_o   ( narrow_req_routed         ),
    .gnt_i   ( narrow_gnt_routed         ),
    .add_o   ( narrow_addr_routed        ),
    .wen_o   ( narrow_we_routed          ),
    .wdata_o ( narrow_wdata_routed       ),
    .be_o    ( narrow_strb_routed        ),
    .rdata_i ( narrow_rdata_routed       )
  );

  for (genvar i = 0; i < WidePseudoBanks; i++) begin : gen_spill_narrow_routed
    mem_req_multicut #(
      .AddrWidth ( NarrowAddrMemWidth   ),
      .DataWidth ( NarrowDataWidth      ),
      .NumCuts   ( SpillNarrowReqRouted )
    ) i_spill_narrow_req_routed (
      .clk_i,
      .rst_ni,

      .req_i   ( narrow_req_routed        [i] ),
      .gnt_o   ( narrow_gnt_routed        [i] ),
      .addr_i  ( narrow_addr_routed       [i] ),
      .we_i    ( narrow_we_routed         [i] ),
      .wdata_i ( narrow_wdata_routed      [i] ),
      .strb_i  ( narrow_strb_routed       [i] ),

      .req_o   ( narrow_req_routed_spill  [i] ),
      .gnt_i   ( narrow_gnt_routed_spill  [i] ),
      .addr_o  ( narrow_addr_routed_spill [i] ),
      .we_o    ( narrow_we_routed_spill   [i] ),
      .wdata_o ( narrow_wdata_routed_spill[i] ),
      .strb_o  ( narrow_strb_routed_spill [i] )
    );

    mem_rsp_multicut #(
      .DataWidth ( NarrowDataWidth      ),
      .NumCuts   ( SpillNarrowRspRouted )
    ) i_spill_narrow_rsq_routed (
      .clk_i,
      .rst_ni,

      .rvalid_i ( 1'b1                         ), // Static latency, signal not used
      .rready_o (),
      .rdata_i  ( narrow_rdata_routed_spill[i] ),

      .rvalid_o (),
      .rready_i ( 1'b1                         ),
      .rdata_o  ( narrow_rdata_routed      [i] )
    );
  end

  // narrow gnt always set
  assign narrow_gnt_routed_spill = '1;

  localparam int unsigned NarrowWideBankSelWidth = AddrWideBankBit-AddrNarrowWideBit;

  for (genvar i = 0; i < TotalBanks/WidePseudoBanks; i++) begin : gen_narrow_routed_bank_l1
    for (genvar j = 0; j < NarrowExtraBF; j++) begin : gen_narrow_routed_bank_l2
      for (genvar k = 0; k < NWDivisor; k++) begin : gen_narrow_routed_bank_l3
        assign narrow_req_bank  [(i*NarrowExtraBF)+j][k] = narrow_req_routed_spill  [(j*NWDivisor) + k] &
                                                          (narrow_addr_routed_spill [(j*NWDivisor) + k][NarrowWideBankSelWidth-1:0] == i);
        assign narrow_addr_bank [(i*NarrowExtraBF)+j][k] = narrow_addr_routed_spill [(j*NWDivisor) + k][AddrTopBit-AddrNarrowWideBit-1:NarrowWideBankSelWidth];
        assign narrow_we_bank   [(i*NarrowExtraBF)+j][k] = narrow_we_routed_spill   [(j*NWDivisor) + k];
        assign narrow_wdata_bank[(i*NarrowExtraBF)+j][k] = narrow_wdata_routed_spill[(j*NWDivisor) + k];
        assign narrow_strb_bank [(i*NarrowExtraBF)+j][k] = narrow_strb_routed_spill [(j*NWDivisor) + k];
      end
    end
  end

  for (genvar j = 0; j < NarrowExtraBF; j++) begin : gen_narrow_routed_bank_rdata_l1
    for (genvar k = 0; k < NWDivisor; k++) begin : gen_narrow_routed_bank_rdata_l2
      logic [NarrowWideBankSelWidth-1:0] narrow_rdata_sel;
      shift_reg #(
        .dtype ( logic [NarrowWideBankSelWidth-1:0] ),
        .Depth ( NarrowIntcBankLat                  )
      ) i_narrow_rdata_sel (
        .clk_i,
        .rst_ni,
        .d_i   ( narrow_addr_routed_spill [(j*NWDivisor) + k][NarrowWideBankSelWidth-1:0] ),
        .d_o   ( narrow_rdata_sel                                                         )
      );
      assign narrow_rdata_routed_spill[(j*NWDivisor) + k] = narrow_rdata_bank[(narrow_rdata_sel*NarrowExtraBF) + j][k];
    end
  end

  // Wide interconnect
  varlat_inorder_interco #(
    .NumIn          ( NumWideReq                 ),
    .NumOut         ( NumWideBanks               ),
    .AddrWidth      ( AddrWidth                  ),
    .DataWidth      ( WideDataWidth              ),
    .BeWidth        ( WideStrbWidth              ),
    .AddrMemWidth   ( BankAddrMemWidth           ),
    .WriteRespOn    ( 1                          ),
    .NumOutstanding ( 3                          ),
    .Topology       ( tcdm_interconnect_pkg::LIC )
  ) i_wide_interco (
    .clk_i,
    .rst_ni,

    .req_i    ( wide_req_entry_spill    ),
    .add_i    ( wide_addr_entry_spill   ),
    .we_i     ( wide_we_entry_spill     ),
    .wdata_i  ( wide_wdata_entry_spill  ),
    .be_i     ( wide_strb_entry_spill   ),
    .gnt_o    ( wide_gnt_entry_spill    ),
    .vld_o    ( wide_rvalid_entry_spill ),
    .rdata_o  ( wide_rdata_entry_spill  ),

    .req_o    ( wide_req_routed         ),
    .gnt_i    ( wide_gnt_routed         ),
    .add_o    ( wide_addr_routed        ),
    .we_o     ( wide_we_routed          ),
    .wdata_o  ( wide_wdata_routed       ),
    .be_o     ( wide_strb_routed        ),
    .rvalid_i ( wide_rvalid_routed      ),
    .rready_o ( wide_rready_routed      ),
    .rdata_i  ( wide_rdata_routed       )
  );

  for (genvar i = 0; i < NumWideBanks; i++) begin : gen_wide_banks
    mem_req_multicut #(
      .DataWidth ( WideDataWidth      ),
      .AddrWidth ( BankAddrMemWidth   ),
      .NumCuts   ( SpillWideReqRouted )
    ) i_spill_wide_req_routed (
      .clk_i,
      .rst_ni,

      .req_i   ( wide_req_routed        [i] ),
      .gnt_o   ( wide_gnt_routed        [i] ),
      .addr_i  ( wide_addr_routed       [i] ),
      .we_i    ( wide_we_routed         [i] ),
      .wdata_i ( wide_wdata_routed      [i] ),
      .strb_i  ( wide_strb_routed       [i] ),

      .req_o   ( wide_req_routed_spill  [i] ),
      .gnt_i   ( wide_gnt_routed_spill  [i] ),
      .addr_o  ( wide_addr_routed_spill [i] ),
      .we_o    ( wide_we_routed_spill   [i] ),
      .wdata_o ( wide_wdata_routed_spill[i] ),
      .strb_o  ( wide_strb_routed_spill [i] )
    );
    mem_rsp_multicut #(
      .DataWidth ( WideDataWidth      ),
      .NumCuts   ( SpillWideRspRouted )
    ) i_spill_wide_rsp_routed (
      .clk_i,
      .rst_ni,

      .rvalid_i ( wide_rvalid_routed_spill[i] ),
      .rready_o ( wide_rready_routed_spill[i] ),
      .rdata_i  ( wide_rdata_routed_spill [i] ),

      .rvalid_o ( wide_rvalid_routed      [i] ),
      .rready_i ( wide_rready_routed      [i] ),
      .rdata_o  ( wide_rdata_routed       [i] )
    );

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

      .req_i         ( wide_req_routed_spill   [i]                           ),
      .gnt_o         ( wide_gnt_routed_spill   [i]                           ),
      .addr_i        ( {wide_addr_routed_spill [i], {AddrWideWordBit{1'b0}}} ),
      .wdata_i       ( wide_wdata_routed_spill [i]                           ),
      .strb_i        ( wide_strb_routed_spill  [i]                           ),
      .wuser_i       ( '0                                                    ),
      .we_i          ( wide_we_routed_spill    [i]                           ),
      .rvalid_o      ( wide_rvalid_routed_spill[i]                           ),
      .rready_i      ( wide_rready_routed_spill[i]                           ),
      .ruser_o       (),
      .rdata_o       ( wide_rdata_routed_spill [i]                           ),

      .bank_req_o    ( wide_req_bank   [i]                                   ),
      .bank_gnt_i    ( wide_gnt_bank   [i]                                   ),
      .bank_addr_o   ( bank_addr_tmp                                         ),
      .bank_wdata_o  ( wide_wdata_bank [i]                                   ),
      .bank_strb_o   ( wide_strb_bank  [i]                                   ),
      .bank_wuser_o  (),
      .bank_we_o     ( wide_we_bank    [i]                                   ),
      .bank_rvalid_i ( wide_rvalid_bank[i]                                   ),
      .bank_rdata_i  ( wide_rdata_bank [i]                                   ),
      .bank_ruser_i  ( '0                                                    )
    );
    for (genvar j = 0; j < NWDivisor; j++) begin : gen_narrow_banks
      mem_req_multicut #(
        .DataWidth ( NarrowDataWidth   ),
        .AddrWidth ( BankAddrMemWidth  ),
        .NumCuts   ( SpillWideReqSplit )
      ) i_spill_wide_req_split (
        .clk_i,
        .rst_ni,

        .req_i   ( wide_req_bank        [i][j] ),
        .gnt_o   ( wide_gnt_bank        [i][j] ),
        .addr_i  ( wide_addr_bank       [i][j] ),
        .we_i    ( wide_we_bank         [i][j] ),
        .wdata_i ( wide_wdata_bank      [i][j] ),
        .strb_i  ( wide_strb_bank       [i][j] ),

        .req_o   ( wide_req_bank_spill  [i][j] ),
        .gnt_i   ( wide_gnt_bank_spill  [i][j] ),
        .addr_o  ( wide_addr_bank_spill [i][j] ),
        .we_o    ( wide_we_bank_spill   [i][j] ),
        .wdata_o ( wide_wdata_bank_spill[i][j] ),
        .strb_o  ( wide_strb_bank_spill [i][j] )
      );

      mem_rsp_multicut #(
        .DataWidth ( NarrowDataWidth   ),
        .NumCuts   ( SpillWideRspSplit )
      ) i_spill_wide_rsp_split (
        .clk_i,
        .rst_ni,

        .rvalid_i ( wide_rvalid_bank_spill[i][j] ),
        .rready_o (),
        .rdata_i  ( wide_rdata_bank_spill [i][j] ),

        .rvalid_o ( wide_rvalid_bank      [i][j] ),
        .rready_i ( 1'b1                         ),
        .rdata_o  ( wide_rdata_bank       [i][j] )
      );


      // narrow/wide arbitration, narrow always has priority
      assign req_bank             [i][j] =  narrow_req_bank[i][j] | wide_req_bank_spill[i][j];
      assign wide_gnt_bank_spill  [i][j] = ~narrow_req_bank[i][j];
      assign we_bank              [i][j] =  narrow_req_bank[i][j] ? narrow_we_bank   [i][j] : wide_we_bank_spill   [i][j];
      assign addr_bank            [i][j] =  narrow_req_bank[i][j] ? narrow_addr_bank [i][j] : wide_addr_bank_spill [i][j];
      assign wdata_bank           [i][j] =  narrow_req_bank[i][j] ? narrow_wdata_bank[i][j] : wide_wdata_bank_spill[i][j];
      assign strb_bank            [i][j] =  narrow_req_bank[i][j] ? narrow_strb_bank [i][j] : wide_strb_bank_spill [i][j];
      assign narrow_rdata_bank    [i][j] =  rdata_bank     [i][j];
      assign wide_rdata_bank_spill[i][j] =  rdata_bank     [i][j];

      mem_req_multicut #(
        .DataWidth ( NarrowDataWidth  ),
        .AddrWidth ( BankAddrMemWidth ),
        .NumCuts   ( SpillReqBank     )
      ) i_spill_req_bank (
        .clk_i,
        .rst_ni,

        .req_i   ( req_bank        [i][j] ),
        .gnt_o   (),
        .addr_i  ( addr_bank       [i][j] ),
        .we_i    ( we_bank         [i][j] ),
        .wdata_i ( wdata_bank      [i][j] ),
        .strb_i  ( strb_bank       [i][j] ),

        .req_o   ( req_bank_spill  [i][j] ),
        .gnt_i   ( 1'b1                   ),
        .addr_o  ( addr_bank_spill [i][j] ),
        .we_o    ( we_bank_spill   [i][j] ),
        .wdata_o ( wdata_bank_spill[i][j] ),
        .strb_o  ( strb_bank_spill [i][j] )
      );

      mem_rsp_multicut #(
        .DataWidth ( NarrowDataWidth ),
        .NumCuts   ( SpillRspBank    )
      ) i_spill_rsp_bank (
        .clk_i,
        .rst_ni,

        .rvalid_i ( 1'b1                   ),
        .rready_o (),
        .rdata_i  ( rdata_bank_spill[i][j] ),

        .rvalid_o (),
        .rready_i ( 1'b1                   ),
        .rdata_o  ( rdata_bank      [i][j] )
      );

      // Memory bank
      tc_sram #(
        .NumWords  ( WordsPerBank    ),
        .DataWidth ( NarrowDataWidth ),
        .ByteWidth ( 8               ),
        .NumPorts  ( 1               ),
        .Latency   ( 1               ),
        .SimInit   ( MemorySimInit   )
      ) i_bank (
        .clk_i,
        .rst_ni,
        .req_i   ( req_bank_spill  [i][j] ),
        .we_i    ( we_bank_spill   [i][j] ),
        .addr_i  ( addr_bank_spill [i][j] ),
        .wdata_i ( wdata_bank_spill[i][j] ),
        .be_i    ( strb_bank_spill [i][j] ),
        .rdata_o ( rdata_bank_spill[i][j] )
      );

      // Shift reg for wide rvalid
      logic [SpillReqBank+SpillRspBank:0] shift_rvalid_d, shift_rvalid_q;
      for (genvar k = 0; k < SpillReqBank+SpillRspBank+1; k++) begin
        if (k == 0) begin: gen_shift_in
          assign shift_rvalid_d[k] = req_bank[i][j] & wide_gnt_bank[i][j];
        end else begin: gen_shift
          assign shift_rvalid_d[k] = shift_rvalid_q[k-1];
        end
      end
      assign wide_rvalid_bank_spill[i][j] = shift_rvalid_q[SpillReqBank+SpillRspBank];

      always_ff @(posedge clk_i or negedge rst_ni) begin : proc_wide_bank_rvalid
        if(~rst_ni) begin
          shift_rvalid_q <= '0;
        end else begin
          shift_rvalid_q <= shift_rvalid_d;
        end
      end
    end
  end

endmodule
