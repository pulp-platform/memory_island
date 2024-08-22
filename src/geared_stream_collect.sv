// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

module geared_stream_collect #(
  parameter int unsigned GearRatio = 1,
  parameter type         T         = logic  // Vivado requires a default value for type parameters.
) (
  input  logic                 clk_i,          // Clock
  input  logic                 geared_clk_i,   // Geared Clock
  input  logic                 rst_ni,         // Asynchronous active-low reset
  input  logic                 clr_i,          // Synchronous clear
  // Input port
  input  logic [GearRatio-1:0] valid_i,
  output logic [GearRatio-1:0] ready_o,
  input  T     [GearRatio-1:0] data_i,
  // Output port
  output logic                 valid_o,
  input  logic                 ready_i,
  output T                     data_o,
  input  logic [GearRatio-1:0] selected_reg_i
);

  if (GearRatio < 1) begin
    $fatal(1, "Gear Ratio < 1 not supported!");
  end else if (GearRatio == 1) begin
    assign valid_o = valid_i;
    assign ready_o = ready_i;
    assign data_o = data_i;
  end else begin
    logic last_cycle_in_gear;

    logic [GearRatio-1:0] valid_in_d, valid_in_q;
    logic [GearRatio-1:0] ready_out_d, ready_out_q, ready_out_tmp;

    T [GearRatio-1:0] data_out;
    logic [$clog2(GearRatio)-1:0] sel_reg;

    assign valid_o = |(valid_in_q & selected_reg_i);

    onehot_to_bin #(
      .ONEHOT_WIDTH(GearRatio)
    ) i_selected_reg (
      .onehot ( selected_reg_i ),
      .bin    ( sel_reg )
    );
    assign data_o = data_out[sel_reg];

    assign ready_o = ready_out_q | ready_out_tmp;

    for (genvar i = 0; i < GearRatio; i++) begin

      assign valid_in_d[i] = last_cycle_in_gear ? valid_i[i] : 1'b0;
      assign ready_out_d[i] = last_cycle_in_gear ? 1'b0 : (ready_out_tmp | ready_out_q);
      assign ready_out_tmp[i] = selected_reg_i == i ? ready_i : 1'b0;

      `FFLARNC(ready_out_q[i], ready_out_d[i], 1'b1, clr_i, 1'b0, clk_i, rst_ni)
      `FFLARNC(valid_in_q[i], valid_in_d[i], last_cycle_in_gear || (selected_reg_i[i] && ready_i), clr_i, 1'b0, clk_i, rst_ni)
      `FFLARNC(data_out[i], data_i[i], last_cycle_in_gear & valid_i[i] & ready_o[i], clr_i, '0, clk_i, rst_ni)
    end
  end

endmodule
