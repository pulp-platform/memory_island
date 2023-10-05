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
  parameter int unsigned AxiWideIdWidth = 0,

  parameter type axi_narrow_req_t = logic,
  parameter type axi_narrow_rsp_t = logic,

  parameter type axi_wide_req_t   = logic,
  parameter type axi_wide_rsp_t   = logic,

  /// Number of Narrow Ports
  parameter int unsigned NumNarrowReq    = 0,
  /// Number of Wide Ports
  parameter int unsigned NumWideReq      = 0,

  /// Banking Factor for the Wide Ports (power of 2)
  parameter int unsigned NumWideBanks    = (1<<$clog2(NumWideReq))*2*2,
  /// Extra multiplier for the Narrow banking factor (baseline is WideWidth/NarrowWidth) (power of 2)
  parameter int unsigned NarrowExtraBF   = 1,
  /// Words per memory bank. (Total number of banks is (WideWidth/NarrowWidth)*NumWideBanks)
  parameter int unsigned WordsPerBank    = 1024
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  axi_narrow_req_t [NumNarrowReq-1:0] axi_narrow_req_i,
  output axi_narrow_rsp_t [NumNarrowReq-1:0] axi_narrow_rsp_o,

  input  axi_wide_req_t   [NumWideReq-1:0]   axi_wide_req_i,
  output axi_wide_rsp_t   [NumWideReq-1:0]   axi_wide_rsp_o
);

  localparam NarrowStrbWidth = NarrowDataWidth/8;
  localparam WideStrbWidth   = WideDataWidth/8;

  logic [2*NumNarrowReq-1:0]                      narrow_req;
  logic [2*NumNarrowReq-1:0]                      narrow_gnt;
  logic [2*NumNarrowReq-1:0][      AddrWidth-1:0] narrow_addr;
  logic [2*NumNarrowReq-1:0][NarrowDataWidth-1:0] narrow_wdata;
  logic [2*NumNarrowReq-1:0][NarrowStrbWidth-1:0] narrow_strb;
  logic [2*NumNarrowReq-1:0]                      narrow_we;
  logic [2*NumNarrowReq-1:0]                      narrow_rvalid;
  logic [2*NumNarrowReq-1:0][NarrowDataWidth-1:0] narrow_rdata;

  logic [2*NumWideReq-1:0]                    wide_req;
  logic [2*NumWideReq-1:0]                    wide_gnt;
  logic [2*NumWideReq-1:0][    AddrWidth-1:0] wide_addr;
  logic [2*NumWideReq-1:0][WideDataWidth-1:0] wide_wdata;
  logic [2*NumWideReq-1:0][WideStrbWidth-1:0] wide_strb;
  logic [2*NumWideReq-1:0]                    wide_we;
  logic [2*NumWideReq-1:0]                    wide_rvalid;
  logic [2*NumWideReq-1:0][WideDataWidth-1:0] wide_rdata;


  for (genvar i = 0; i < NumNarrowReq; i++) begin : gen_narrow_conv
    axi_to_mem_split #(
      .axi_req_t   ( axi_narrow_req_t ),
      .axi_resp_t  ( axi_narrow_rsp_t ),
      .AddrWidth   ( AddrWidth ),
      .AxiDataWidth( NarrowDataWidth ),
      .IdWidth     ( AxiNarrowIdWidth ),
      .MemDataWidth( NarrowDataWidth ),
      .BufDepth    (),
      .HideStrb    (1'b0),
      .OutFifoDepth()
    ) i_narrow_conv (
      .clk_i,
      .rst_ni,
      .test_i      ( '0 ),
      .busy_o      (),
      .axi_req_i   ( axi_narrow_req_i[i] ),
      .axi_resp_o  ( axi_narrow_rsp_o[i] ),
      .mem_req_o   ( narrow_req      [2*i+:2] ),
      .mem_gnt_i   ( narrow_gnt      [2*i+:2] ),
      .mem_addr_o  ( narrow_addr     [2*i+:2] ),
      .mem_wdata_o ( narrow_wdata    [2*i+:2] ),
      .mem_strb_o  ( narrow_strb     [2*i+:2] ),
      .mem_atop_o  (),
      .mem_we_o    ( narrow_we       [2*i+:2] ),
      .mem_rvalid_i( narrow_rvalid   [2*i+:2] ),
      .mem_rdata_i ( narrow_rdata    [2*i+:2] )
    );
  end

  for (genvar i = 0; i < NumWideReq; i++) begin : gen_wide_conv
    axi_to_mem_split #(
      .axi_req_t   ( axi_wide_req_t ),
      .axi_resp_t  ( axi_wide_rsp_t ),
      .AddrWidth   ( AddrWidth ),
      .AxiDataWidth( WideDataWidth ),
      .IdWidth     ( AxiWideIdWidth ),
      .MemDataWidth( WideDataWidth ),
      .BufDepth    (),
      .HideStrb    (1'b0),
      .OutFifoDepth()
    ) i_wide_conv (
      .clk_i,
      .rst_ni,
      .test_i      ( '0 ),
      .busy_o      (),
      .axi_req_i   ( axi_wide_req_i[i]),
      .axi_resp_o  ( axi_wide_rsp_o[i]),
      .mem_req_o   ( wide_req      [2*i+:2] ),
      .mem_gnt_i   ( wide_gnt      [2*i+:2] ),
      .mem_addr_o  ( wide_addr     [2*i+:2] ),
      .mem_wdata_o ( wide_wdata    [2*i+:2] ),
      .mem_strb_o  ( wide_strb     [2*i+:2] ),
      .mem_atop_o  (),
      .mem_we_o    ( wide_we       [2*i+:2] ),
      .mem_rvalid_i( wide_rvalid   [2*i+:2] ),
      .mem_rdata_i ( wide_rdata    [2*i+:2] )
    );
  end


  memory_island_core #(
    .AddrWidth      ( AddrWidth ),
    .NarrowDataWidth( NarrowDataWidth ),
    .WideDataWidth  ( WideDataWidth ),
    .NumNarrowReq   ( 2*NumNarrowReq ),
    .NumWideReq     ( 2*NumWideReq ),
    .NumWideBanks   ( NumWideBanks ),
    .NarrowExtraBF  ( NarrowExtraBF ),
    .WordsPerBank   ( WordsPerBank )
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
