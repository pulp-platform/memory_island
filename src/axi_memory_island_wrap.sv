// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

module axi_memory_island_wrap #(
  /// Address Width
  parameter int unsigned AddrWidth       = 0,
  /// Data Width for the Narrow Ports
  parameter int unsigned NarrowDataWidth = 0,
  /// Data Width for the Wide Ports
  parameter int unsigned WideDataWidth   = 0,

  parameter int unsigned AxiNarrowIdWidth = 0,
  parameter int unsigned AxiWideIdWidth   = 0,

  parameter type axi_narrow_req_t = logic,
  parameter type axi_narrow_rsp_t = logic,

  parameter type axi_wide_req_t = logic,
  parameter type axi_wide_rsp_t = logic,

  /// Number of Narrow Ports
  parameter int unsigned NumNarrowReq = 0,
  /// Number of Wide Ports
  parameter int unsigned NumWideReq   = 0,

  /// Indicates corresponding narrow requestor supports read/write (0 for read-only/write-only)
  parameter bit [NumNarrowReq-1:0] NarrowRW = '1,
  /// Indicates corresponding narrow requestor supports read/write (0 for read-only/write-only)
  parameter bit [  NumWideReq-1:0] WideRW   = '1,

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

  /// Relinquish narrow priority after x cycles, 0 for never. Requires SpillNarrowReqRouted==0.
  parameter int unsigned WidePriorityWait = 1,

  /// Banking Factor for the Wide Ports (power of 2)
  parameter int unsigned NumWideBanks  = (1 << $clog2(NumWideReq)) * 2 * 2,
  /// Extra multiplier for the Narrow banking factor (baseline is WideWidth/NarrowWidth) (power of 2)
  parameter int unsigned NarrowExtraBF = 1,
  /// Words per memory bank. (Total number of banks is (WideWidth/NarrowWidth)*NumWideBanks)
  parameter int unsigned WordsPerBank  = 1024,
  // verilog_lint: waive explicit-parameter-storage-type
  parameter              MemorySimInit = "none"
) (
  input logic clk_i,
  input logic rst_ni,

  input  axi_narrow_req_t [NumNarrowReq-1:0] axi_narrow_req_i,
  output axi_narrow_rsp_t [NumNarrowReq-1:0] axi_narrow_rsp_o,

  input  axi_wide_req_t [NumWideReq-1:0] axi_wide_req_i,
  output axi_wide_rsp_t [NumWideReq-1:0] axi_wide_rsp_o
);

  localparam int unsigned NarrowStrbWidth = NarrowDataWidth / 8;
  localparam int unsigned WideStrbWidth = WideDataWidth / 8;

  localparam int unsigned InternalNumNarrow = NumNarrowReq + $countones(NarrowRW);
  localparam int unsigned InternalNumWide = NumWideReq + $countones(WideRW);

  localparam int unsigned NarrowMemRspLatency = SpillNarrowReqEntry +
                                                SpillNarrowReqRouted +
                                                SpillReqBank +
                                                SpillRspBank +
                                                SpillNarrowRspRouted +
                                                SpillNarrowRspEntry +
                                                1;
  localparam int unsigned  WideMemRspLatency = SpillWideReqEntry +
                                               SpillWideReqRouted +
                                               SpillWideReqSplit +
                                               SpillReqBank +
                                               SpillRspBank +
                                               SpillWideRspSplit +
                                               SpillWideRspRouted +
                                               SpillWideRspEntry +
                                               1;

  logic [InternalNumNarrow-1:0]                      narrow_req;
  logic [InternalNumNarrow-1:0]                      narrow_gnt;
  logic [InternalNumNarrow-1:0][      AddrWidth-1:0] narrow_addr;
  logic [InternalNumNarrow-1:0][NarrowDataWidth-1:0] narrow_wdata;
  logic [InternalNumNarrow-1:0][NarrowStrbWidth-1:0] narrow_strb;
  logic [InternalNumNarrow-1:0]                      narrow_we;
  logic [InternalNumNarrow-1:0]                      narrow_rvalid;
  logic [InternalNumNarrow-1:0][NarrowDataWidth-1:0] narrow_rdata;

  logic [  InternalNumWide-1:0]                      wide_req;
  logic [  InternalNumWide-1:0]                      wide_gnt;
  logic [  InternalNumWide-1:0][      AddrWidth-1:0] wide_addr;
  logic [  InternalNumWide-1:0][  WideDataWidth-1:0] wide_wdata;
  logic [  InternalNumWide-1:0][  WideStrbWidth-1:0] wide_strb;
  logic [  InternalNumWide-1:0]                      wide_we;
  logic [  InternalNumWide-1:0]                      wide_rvalid;
  logic [  InternalNumWide-1:0][  WideDataWidth-1:0] wide_rdata;


  for (genvar i = 0; i < NumNarrowReq; i++) begin : gen_narrow_conv
    localparam int unsigned Id = i + $countones(NarrowRW[i:0]);
    if (NarrowRW[i]) begin : gen_split_conv
      axi_to_mem_split #(
        .axi_req_t   (axi_narrow_req_t),
        .axi_resp_t  (axi_narrow_rsp_t),
        .AddrWidth   (AddrWidth),
        .AxiDataWidth(NarrowDataWidth),
        .IdWidth     (AxiNarrowIdWidth),
        .MemDataWidth(NarrowDataWidth),
        .BufDepth    (1 + NarrowMemRspLatency),
        .HideStrb    (1'b0),
        .OutFifoDepth(1)
      ) i_narrow_conv (
        .clk_i,
        .rst_ni,
        .test_i      ('0),
        .busy_o      (),
        .axi_req_i   (axi_narrow_req_i[i]),
        .axi_resp_o  (axi_narrow_rsp_o[i]),
        .mem_req_o   (narrow_req[Id-:2]),
        .mem_gnt_i   (narrow_gnt[Id-:2]),
        .mem_addr_o  (narrow_addr[Id-:2]),
        .mem_wdata_o (narrow_wdata[Id-:2]),
        .mem_strb_o  (narrow_strb[Id-:2]),
        .mem_atop_o  (),
        .mem_we_o    (narrow_we[Id-:2]),
        .mem_rvalid_i(narrow_rvalid[Id-:2]),
        .mem_rdata_i (narrow_rdata[Id-:2])
      );
    end else begin : gen_single_conv
      axi_to_mem #(
        .axi_req_t   (axi_narrow_req_t),
        .axi_resp_t  (axi_narrow_rsp_t),
        .AddrWidth   (AddrWidth),
        .AxiDataWidth(NarrowDataWidth),
        .IdWidth     (AxiNarrowIdWidth),
        .NumBanks    (1),
        .BufDepth    (1 + NarrowMemRspLatency),
        .HideStrb    (1'b0),
        .OutFifoDepth(1)
      ) i_narrow_conv (
        .clk_i,
        .rst_ni,
        .busy_o      (),
        .axi_req_i   (axi_narrow_req_i[i]),
        .axi_resp_o  (axi_narrow_rsp_o[i]),
        .mem_req_o   (narrow_req[Id]),
        .mem_gnt_i   (narrow_gnt[Id]),
        .mem_addr_o  (narrow_addr[Id]),
        .mem_wdata_o (narrow_wdata[Id]),
        .mem_strb_o  (narrow_strb[Id]),
        .mem_atop_o  (),
        .mem_we_o    (narrow_we[Id]),
        .mem_rvalid_i(narrow_rvalid[Id]),
        .mem_rdata_i (narrow_rdata[Id])
      );
    end
  end

  for (genvar i = 0; i < NumWideReq; i++) begin : gen_wide_conv
    localparam int unsigned Id = i + $countones(WideRW[i:0]);
    if (WideRW[i]) begin : gen_split_conv
      axi_to_mem_split #(
        .axi_req_t   (axi_wide_req_t),
        .axi_resp_t  (axi_wide_rsp_t),
        .AddrWidth   (AddrWidth),
        .AxiDataWidth(WideDataWidth),
        .IdWidth     (AxiWideIdWidth),
        .MemDataWidth(WideDataWidth),
        .BufDepth    (1 + WideMemRspLatency),
        .HideStrb    (1'b0),
        .OutFifoDepth(1)
      ) i_wide_conv (
        .clk_i,
        .rst_ni,
        .test_i      ('0),
        .busy_o      (),
        .axi_req_i   (axi_wide_req_i[i]),
        .axi_resp_o  (axi_wide_rsp_o[i]),
        .mem_req_o   (wide_req[Id-:2]),
        .mem_gnt_i   (wide_gnt[Id-:2]),
        .mem_addr_o  (wide_addr[Id-:2]),
        .mem_wdata_o (wide_wdata[Id-:2]),
        .mem_strb_o  (wide_strb[Id-:2]),
        .mem_atop_o  (),
        .mem_we_o    (wide_we[Id-:2]),
        .mem_rvalid_i(wide_rvalid[Id-:2]),
        .mem_rdata_i (wide_rdata[Id-:2])
      );
    end else begin : gen_single_conv
      axi_to_mem #(
        .axi_req_t   (axi_wide_req_t),
        .axi_resp_t  (axi_wide_rsp_t),
        .AddrWidth   (AddrWidth),
        .AxiDataWidth(WideDataWidth),
        .IdWidth     (AxiWideIdWidth),
        .NumBanks    (1),
        .BufDepth    (1 + WideMemRspLatency),
        .HideStrb    (1'b0),
        .OutFifoDepth(1)
      ) i_wide_conv (
        .clk_i,
        .rst_ni,
        .busy_o      (),
        .axi_req_i   (axi_wide_req_i[i]),
        .axi_resp_o  (axi_wide_rsp_o[i]),
        .mem_req_o   (wide_req[Id]),
        .mem_gnt_i   (wide_gnt[Id]),
        .mem_addr_o  (wide_addr[Id]),
        .mem_wdata_o (wide_wdata[Id]),
        .mem_strb_o  (wide_strb[Id]),
        .mem_atop_o  (),
        .mem_we_o    (wide_we[Id]),
        .mem_rvalid_i(wide_rvalid[Id]),
        .mem_rdata_i (wide_rdata[Id])
      );
    end
  end


  memory_island_core #(
    .AddrWidth           (AddrWidth),
    .NarrowDataWidth     (NarrowDataWidth),
    .WideDataWidth       (WideDataWidth),
    .NumNarrowReq        (2 * NumNarrowReq),
    .NumWideReq          (2 * NumWideReq),
    .NumWideBanks        (NumWideBanks),
    .NarrowExtraBF       (NarrowExtraBF),
    .WordsPerBank        (WordsPerBank),
    .SpillNarrowReqEntry (SpillNarrowReqEntry),
    .SpillNarrowRspEntry (SpillNarrowRspEntry),
    .SpillNarrowReqRouted(SpillNarrowReqRouted),
    .SpillNarrowRspRouted(SpillNarrowRspRouted),
    .SpillWideReqEntry   (SpillWideReqEntry),
    .SpillWideRspEntry   (SpillWideRspEntry),
    .SpillWideReqRouted  (SpillWideReqRouted),
    .SpillWideRspRouted  (SpillWideRspRouted),
    .SpillWideReqSplit   (SpillWideReqSplit),
    .SpillWideRspSplit   (SpillWideRspSplit),
    .SpillReqBank        (SpillReqBank),
    .SpillRspBank        (SpillRspBank),
    .WidePriorityWait    (WidePriorityWait),
    .MemorySimInit       (MemorySimInit)
  ) i_memory_island (
    .clk_i,
    .rst_ni,

    .narrow_req_i   (narrow_req),
    .narrow_gnt_o   (narrow_gnt),
    .narrow_addr_i  (narrow_addr),
    .narrow_we_i    (narrow_we),
    .narrow_wdata_i (narrow_wdata),
    .narrow_strb_i  (narrow_strb),
    .narrow_rvalid_o(narrow_rvalid),
    .narrow_rdata_o (narrow_rdata),
    .wide_req_i     (wide_req),
    .wide_gnt_o     (wide_gnt),
    .wide_addr_i    (wide_addr),
    .wide_we_i      (wide_we),
    .wide_wdata_i   (wide_wdata),
    .wide_strb_i    (wide_strb),
    .wide_rvalid_o  (wide_rvalid),
    .wide_rdata_o   (wide_rdata)
  );

endmodule
