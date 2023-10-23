// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

module mem_req_multicut #(
  /// Address Width
  parameter int unsigned AddrWidth = 0,
  /// Data Width
  parameter int unsigned DataWidth = 0,
  /// Number of cuts
  parameter int unsigned NumCuts   = 0,
  // Derived, DO NOT OVERRIDE
  parameter int unsigned StrbWidth  = DataWidth/8
) (
  input  logic clk_i,
  input  logic rst_ni,

  // mem interface inputs
  input  logic                 req_i,
  output logic                 gnt_o,
  input  logic [AddrWidth-1:0] addr_i,
  input  logic                 we_i,
  input  logic [DataWidth-1:0] wdata_i,
  input  logic [StrbWidth-1:0] strb_i,

  // mem interface outputs
  output logic                 req_o,
  input  logic                 gnt_i,
  output logic [AddrWidth-1:0] addr_o,
  output logic                 we_o,
  output logic [DataWidth-1:0] wdata_o,
  output logic [StrbWidth-1:0] strb_o
);

  localparam int unsigned AggDataWidth  = 1+StrbWidth+AddrWidth+DataWidth;
  if (NumCuts == 0) begin
    assign req_o    = req_i;
    assign gnt_o    = gnt_i;
    assign addr_o   = addr_i;
    assign we_o     = we_i;
    assign wdata_o  = wdata_i;
    assign strb_o   = strb_i;
  end else begin
    logic [NumCuts:0][AggDataWidth-1:0]  data_agg;
    logic [NumCuts:0] req, gnt;

    assign data_agg[0]  = {we_i, strb_i, addr_i, wdata_i};
    assign req     [0]  = req_i;
    assign gnt_o        = gnt[0];
    assign gnt[NumCuts] = gnt_i;
    assign req_o        = req  [NumCuts];
    assign {we_o, strb_o, addr_o, wdata_o} = data_agg[NumCuts];

    for (genvar i = 0; i < NumCuts; i++) begin
      spill_register #(
        .T     (logic[AggDataWidth-1:0]),
        .Bypass(1'b0)
      ) i_cut (
        .clk_i,
        .rst_ni,
        .valid_i ( req     [i  ] ),
        .ready_o ( gnt     [i  ] ),
        .data_i  ( data_agg[i  ] ),
        .valid_o ( req     [i+1] ),
        .ready_i ( gnt     [i+1] ),
        .data_o  ( data_agg[i+1] )
      );
    end
  end

endmodule
