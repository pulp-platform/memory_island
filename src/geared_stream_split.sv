// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

module geared_stream_split #(
  parameter int unsigned GearRatio = 1,
  parameter type         T         = logic  // Vivado requires a default value for type parameters.
) (
  input  logic                 clk_i,          // Clock
  input  logic                 geared_clk_i,   // Geared Clock
  input  logic                 rst_ni,         // Asynchronous active-low reset
  input  logic                 clr_i,          // Synchronous clear
  // Input port
  input  logic                 valid_i,
  output logic                 ready_o,
  input  T                     data_i,
  output logic [GearRatio-1:0] selected_reg_o,
  // Output port
  output logic [GearRatio-1:0] valid_o,
  input  logic [GearRatio-1:0] ready_i,
  output T     [GearRatio-1:0] data_o
);

  if (GearRatio < 1) begin
    $fatal(1, "Gear Ratio < 1 not supported!");
  end else if (GearRatio == 1) begin
    assign valid_o = valid_i;
    assign ready_o = ready_i;
    assign data_o = data_i;
    assign selected_reg_o = 1'b1;
  end else begin
    logic [GearRatio-1:0] reg_active_d, reg_active;
    logic [GearRatio-1:0] ready_out;
    logic [GearRatio-1:0] reg_ena;

    // reg_active is high for one cycle for each position during a full geared_clk cycle
    assign reg_active_d[GearRatio-1:1] = reg_active[GearRatio-2:0];
    assign reg_active_d[0] = reg_active[GearRatio-1];

    `FF(reg_active, reg_active_d, {{(GearRatio-1){1'b0}}, 1'b1}, clk_i, rst_ni)

    assign selected_reg_o = reg_active;

    assign ready_o = |ready_out;

    for (genvar i = 0; i < GearRatio; i++) begin

      assign ready_out[i] = (ready_i[i] | ~valid_o[i]) & reg_active[i];
      assign reg_ena[i] = valid_i & ready_out[i];

      // only active once during each geared_clk cycle
      `FFLARNC(valid_o[i], valid_i, ready_out[i], clr_i, 1'b0, clk_i, rst_ni)
      `FFLARNC(data_o[i], data_i, reg_ena[i], clr_i, '0, clk_i, rst_ni)
    end
  end

endmodule
