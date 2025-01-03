// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Lorenzo Leone <lleone@iis.ee.ethz.ch>

// This is a wrapper to instantiate the memory bank.
// The wrapper has been introduced for power managemnet reasons:
// when PMU strategies must be applied in a deisgn with the memory island,
// the memory banks can be switched on/off using some control signals.
// A memory bank can be made of internal cuts which can be turned on/off
// independently.
// When the memory is interleaved, cut inside the same logic bank are not
// contiguous and therefore a proper swicthing strategy must be applied.
//
// This wrapper instantiates:
//   - `tc_sram` if no power management is necessary
//   - `mem_multibank_pwrgate` if we want to apply power strategies to the bank. In this case
//     powerr management signals (deepsleep and powergate) are driven from the UPF file.

module mem_bank_wrapper #(
    parameter int unsigned NumWords = 1024,  // Number of Words in data array
    parameter int unsigned DataWidth = 0,  // Data signal width
    parameter int unsigned ByteWidth = 8,  // Width of a data byte
    parameter int unsigned NumPorts = 1,  // Number of read and write ports
    parameter int unsigned Latency = 1,  // Latency when the read data is available
    parameter int unsigned NumLogicBanks = 1,  // Logic bank for Power Management
    parameter SimInit = "none",  // Simulation initialization
    // DEPENDENT PARAMETERS, DO NOT OVERWRITE!
    parameter int unsigned AddrWidth = (NumWords > 32'd1) ? $clog2(NumWords) : 32'd1,
    parameter int unsigned BeWidth = (DataWidth + ByteWidth - 32'd1) / ByteWidth,  // ceil_div
    parameter type addr_t = logic [AddrWidth-1:0],
    parameter type data_t = logic [DataWidth-1:0],
    parameter type be_t = logic [BeWidth-1:0]
) (
    input  logic                 clk_i,
    input  logic                 rst_ni,
    // input ports
    input  logic  [NumPorts-1:0] req_i,    // request
    input  logic  [NumPorts-1:0] we_i,     // write enable
    input  addr_t [NumPorts-1:0] addr_i,   // request address
    input  data_t [NumPorts-1:0] wdata_i,  // write data
    input  be_t   [NumPorts-1:0] be_i,     // write byte enable
    // output ports
    output data_t [NumPorts-1:0] rdata_o   // read data
);

`ifdef UPF
   // Drive deepsleep and powergate signals directly from the UPF file
   mem_multibank_pwrgate #(
       .NumWords     (NumWords),
       .DataWidth    (DataWidth),
       .ByteWidth    (ByteWidth),
       .NumPorts     (NumPorts),
       .Latency      (Latency),
       .NumLogicBanks(NumLogicBanks),
       .SimInit      (SimInit)
   ) i_bank (
       .clk_i,
       .rst_ni,
       .req_i,
       .we_i,
       .addr_i,
       .wdata_i,
       .be_i,
       .rdata_o
   );
`else
   tc_sram #(
       .NumWords (NumWords),
       .DataWidth(DataWidth),
       .ByteWidth(ByteWidth),
       .NumPorts (NumPorts),
       .Latency  (Latency),
       .SimInit  (SimInit)
   ) i_bank (
       .clk_i,
       .rst_ni,
       .req_i,
       .we_i,
       .addr_i,
       .wdata_i,
       .be_i,
       .rdata_o
   );
`endif

endmodule
