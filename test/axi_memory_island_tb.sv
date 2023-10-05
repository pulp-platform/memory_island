// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

`include "axi/typedef.svh"

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
  parameter int unsigned WordsPerBank = 1024
) ();

  logic clk, rst_n;

  clk_rst_gen #(
    .RstClkCycles(3),
    .ClkPeriod   (10ps)
  ) i_clk_gen (
    .clk_o (clk),
    .rst_no(rst_n)
  );

  `AXI_TYPEDEF_ALL(narrow, logic[AddrWidth-1:0], logic[AxiIdWidth-1:0], logic[NarrowDataWidth-1:0], logic[NarrowDataWidth/8-1:0], logic[AxiUserWidth-1:0])
  `AXI_TYPEDEF_ALL(wide, logic[AddrWidth-1:0], logic[AxiIdWidth-1:0], logic[WideDataWidth-1:0], logic[WideDataWidth/8-1:0], logic[AxiUserWidth-1:0])

  narrow_req_t  [NumNarrowReq-1:0] axi_narrow_req;
  narrow_resp_t [NumNarrowReq-1:0] axi_narrow_rsp;
  wide_req_t    [  NumWideReq-1:0] axi_wide_req;
  wide_resp_t   [  NumWideReq-1:0] axi_wide_rsp;

  axi_memory_island_wrap #(
    .AddrWidth       ( AddrWidth       ),
    .NarrowDataWidth ( NarrowDataWidth ),
    .WideDataWidth   ( WideDataWidth   ),
    .AxiNarrowIdWidth( AxiIdWidth      ),
    .AxiWideIdWidth  ( AxiIdWidth      ),
    .axi_narrow_req_t( narrow_req_t    ),
    .axi_narrow_rsp_t( narrow_resp_t   ),
    .axi_wide_req_t  ( wide_req_t      ),
    .axi_wide_rsp_t  ( wide_resp_t     ),
    .NumNarrowReq    ( NumNarrowReq    ),
    .NumWideReq      ( NumWideReq      ),
    .NumWideBanks    ( NumWideBanks    ),
    .NarrowExtraBF   ( NarrowExtraBF   ),
    .WordsPerBank    ( WordsPerBank    )
  ) i_dut (
    .clk_i           (clk),
    .rst_ni          (rst_n),
    .axi_narrow_req_i(axi_narrow_req),
    .axi_narrow_rsp_o(axi_narrow_rsp),
    .axi_wide_req_i  (axi_wide_req),
    .axi_wide_rsp_o  (axi_wide_rsp)
  );

endmodule
