// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Performance testbench for memory_island_core: drives the mem-level narrow/wide ports with
// closed-loop synthetic traffic and reports per-port grant/stall statistics. Narrow stall cycles
// are attributed to their cause by probing the core's internal bank arbitration:
//   true   another narrow port won the same pseudo bank for the same physical bank
//   false  another narrow port won the same pseudo bank for a different physical bank
//   hol    own bank open, but the pseudo bank is held by a request stuck at another bank
//   wide   own bank has been promoted to wide priority (WidePriorityWait)
//   rmw    own bank's ECC SRAM holds gnt low for a read-modify-write
//   (false and hol only exist when a pseudo bank covers several wide banks, NarrowExtraBF=1)
//
// Plusargs:
//   +SCENARIO=S1|S2|S3|S4  traffic scenario (default S1)
//   +INJ=<0..100>          narrow injection rate in percent (S1-S3, default 100)
//   +OFFSET=<bytes>        S4 DmaW-DmaR base offset modulo 64 B (default 32)
//   +CYCLES=<n>            measured cycles (default 20000)
//
// Seed the traffic with vsim -sv_seed.
//
// Scenarios:
//   S1  4 narrow uniform random, wide idle
//   S2  4 narrow with the same addr[4:2], ports 0/2 on wide bank 0, ports 1/3 on wide bank 1
//   S3  4 narrow uniform random, wide streaming 16-beat bursts (alternating read/write)
//   S4  dora-like: port 0 host (20%, random, 30% of writes sub-word), port 1 DmaR sequential
//       read, port 2 DmaW sequential write, port 3 sensor sequential write (10%), wide streaming

module memory_island_core_perf_tb #(
  parameter int unsigned NarrowExtraBF     = 1,
  parameter int unsigned NumWideBanks      = 2,
  parameter int unsigned WordsPerBank      = 16384,
  parameter int unsigned BankAccessLatency = 1,
  parameter int unsigned WidePriorityWait  = 3,
  parameter time         CyclTime          = 10ns
) ();

  localparam int unsigned AddrWidth       = 32;
  localparam int unsigned NarrowDataWidth = 32;
  localparam int unsigned WideDataWidth   = 256;
  localparam int unsigned NumNarrowReq    = 4;
  localparam int unsigned NumWideReq      = 1;

  localparam int unsigned NWDivisor       = WideDataWidth / NarrowDataWidth;
  localparam int unsigned NarrowStrbWidth = NarrowDataWidth / 8;
  localparam int unsigned WideStrbWidth   = WideDataWidth / 8;
  localparam int unsigned NarrowWordBit   = $clog2(NarrowStrbWidth);
  localparam int unsigned WideWordBit     = $clog2(WideStrbWidth);
  localparam int unsigned PseudoBankBits  = $clog2(NWDivisor * NarrowExtraBF);
  localparam int unsigned MemBytes        = NumWideBanks * WordsPerBank * WideStrbWidth;
  localparam int unsigned WideBurstLen    = 16;

  // Region bases for sequential streams (S4)
  localparam int unsigned DmaSrcBase    = 32'h0001_0000;
  localparam int unsigned DmaDstBase    = 32'h0004_0000;
  localparam int unsigned SensorBase    = 32'h000C_0000;
  localparam int unsigned WideBase      = 32'h0008_0000;

  logic clk, rst_n;

  clk_rst_gen #(
    .RstClkCycles(5),
    .ClkPeriod   (CyclTime)
  ) i_clk_gen (
    .clk_o (clk),
    .rst_no(rst_n)
  );

  logic [NumNarrowReq-1:0]                      narrow_req, narrow_gnt, narrow_we, narrow_rvalid;
  logic [NumNarrowReq-1:0][AddrWidth-1:0]       narrow_addr;
  logic [NumNarrowReq-1:0][NarrowDataWidth-1:0] narrow_wdata, narrow_rdata;
  logic [NumNarrowReq-1:0][NarrowStrbWidth-1:0] narrow_strb;

  logic [NumWideReq-1:0]                    wide_req, wide_gnt, wide_we, wide_rvalid;
  logic [NumWideReq-1:0][AddrWidth-1:0]     wide_addr;
  logic [NumWideReq-1:0][WideDataWidth-1:0] wide_wdata, wide_rdata;
  logic [NumWideReq-1:0][WideStrbWidth-1:0] wide_strb;

  memory_island_core #(
    .AddrWidth           (AddrWidth),
    .NarrowDataWidth     (NarrowDataWidth),
    .WideDataWidth       (WideDataWidth),
    .NumNarrowReq        (NumNarrowReq),
    .NumWideReq          (NumWideReq),
    .NumWideBanks        (NumWideBanks),
    .NarrowExtraBF       (NarrowExtraBF),
    .WordsPerBank        (WordsPerBank),
    .SpillNarrowReqEntry (0),
    .SpillNarrowRspEntry (0),
    .SpillNarrowReqRouted(0),
    .SpillNarrowRspRouted(0),
    .SpillWideReqEntry   (0),
    .SpillWideRspEntry   (0),
    .SpillWideReqRouted  (0),
    .SpillWideRspRouted  (0),
    .SpillWideReqSplit   (0),
    .SpillWideRspSplit   (0),
    .SpillReqBank        (0),
    .SpillRspBank        (0),
    .MemorySimInit       ("zeros"),
    .WidePriorityWait    (WidePriorityWait),
    .BankAccessLatency   (BankAccessLatency)
  ) i_dut (
    .clk_i          (clk),
    .rst_ni         (rst_n),
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

  ////////////////
  // Plusargs   //
  ////////////////

  string       scenario = "S1";
  int unsigned inj      = 100;
  int unsigned offset   = 32;
  int unsigned cycles   = 20000;
  logic        wide_on;

  initial begin
    void'($value$plusargs("SCENARIO=%s", scenario));
    void'($value$plusargs("INJ=%d", inj));
    void'($value$plusargs("OFFSET=%d", offset));
    void'($value$plusargs("CYCLES=%d", cycles));
    wide_on = (scenario == "S3") || (scenario == "S4");
  end

  ////////////////////////
  // Traffic generation //
  ////////////////////////

  // Measurement window
  logic measure, draining;

  function automatic logic [AddrWidth-1:0] rand_word_addr();
    return AddrWidth'($urandom_range(MemBytes / NarrowStrbWidth - 1, 0)) << NarrowWordBit;
  endfunction

  // Per-port injection rate and next-request generator
  int unsigned seq_idx[NumNarrowReq];

  function automatic int unsigned port_inj(int unsigned p);
    if (scenario == "S4") begin
      case (p)
        0: return 20;
        3: return 10;
        default: return 100;
      endcase
    end
    return inj;
  endfunction

  task automatic next_narrow(input int unsigned p, output logic [AddrWidth-1:0] addr,
                             output logic we, output logic [NarrowStrbWidth-1:0] strb);
    strb = '1;
    we   = $urandom_range(1, 0);
    case (scenario)
      "S2": begin
        // Same sub-bank (addr[4:2] = 3); ports 0/2 -> wide bank 0, ports 1/3 -> wide bank 1
        addr = rand_word_addr();
        addr[WideWordBit-1:NarrowWordBit] = 3;
        addr[WideWordBit] = p[0];
      end
      "S4": begin
        case (p)
          0: begin
            addr = rand_word_addr();
            if (we && ($urandom_range(99, 0) < 30)) begin
              // sb or sh
              if ($urandom_range(1, 0)) strb = 4'b0001 << $urandom_range(3, 0);
              else strb = 4'b0011 << (2 * $urandom_range(1, 0));
            end
          end
          1: begin
            addr = DmaSrcBase + (seq_idx[p] << NarrowWordBit);
            we   = 1'b0;
          end
          2: begin
            addr = DmaDstBase + offset + (seq_idx[p] << NarrowWordBit);
            we   = 1'b1;
          end
          default: begin
            addr = SensorBase + (seq_idx[p] << NarrowWordBit);
            we   = 1'b1;
          end
        endcase
        seq_idx[p]++;
      end
      default: addr = rand_word_addr();  // S1, S3
    endcase
  endtask

  // Per-port statistics
  longint unsigned n_gnt[NumNarrowReq], n_stall[NumNarrowReq];
  longint unsigned n_rvalid[NumNarrowReq], wait_sum[NumNarrowReq];
  longint unsigned st_true[NumNarrowReq], st_false[NumNarrowReq], st_hol[NumNarrowReq];
  longint unsigned st_wide[NumNarrowReq], st_rmw[NumNarrowReq], st_other[NumNarrowReq];
  int unsigned     cur_wait[NumNarrowReq], max_wait[NumNarrowReq];

  for (genvar p = 0; p < NumNarrowReq; p++) begin : gen_narrow_gen
    always @(posedge clk or negedge rst_n) begin
      logic [AddrWidth-1:0]       a;
      logic                       w;
      logic [NarrowStrbWidth-1:0] s;
      if (!rst_n) begin
        narrow_req[p]   <= 1'b0;
        narrow_addr[p]  <= '0;
        narrow_we[p]    <= 1'b0;
        narrow_wdata[p] <= '0;
        narrow_strb[p]  <= '0;
        seq_idx[p]      = 0;
      end else begin
        // Issue a new request when idle or right after a handshake
        if ((!narrow_req[p] || narrow_gnt[p]) && !draining) begin
          if ($urandom_range(99, 0) < port_inj(p)) begin
            next_narrow(p, a, w, s);
            narrow_req[p]   <= 1'b1;
            narrow_addr[p]  <= a;
            narrow_we[p]    <= w;
            narrow_wdata[p] <= $urandom();
            narrow_strb[p]  <= s;
          end else begin
            narrow_req[p] <= 1'b0;
          end
        end else if (narrow_gnt[p]) begin
          narrow_req[p] <= 1'b0;
        end
      end
    end
  end

  // Wide stream: WideBurstLen beats per burst, bursts alternate read/write, sequential addresses
  int unsigned wide_beat;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wide_req   <= '0;
      wide_addr  <= '0;
      wide_we    <= '0;
      wide_wdata <= '0;
      wide_strb  <= '0;
      wide_beat  = 0;
    end else if (wide_on) begin
      if ((!wide_req[0] || wide_gnt[0]) && !draining) begin
        wide_req[0]   <= 1'b1;
        wide_addr[0]  <= WideBase + ((wide_beat << WideWordBit) % (MemBytes / 2));
        wide_we[0]    <= (wide_beat / WideBurstLen) % 2;
        wide_wdata[0] <= {WideDataWidth / 32{$urandom()}};
        wide_strb[0]  <= '1;
        wide_beat++;
      end else if (wide_gnt[0]) begin
        wide_req[0] <= 1'b0;
      end
    end
  end

  //////////////////////
  // Stall attribution //
  //////////////////////

  // Physical bank of a narrow address
  function automatic int unsigned wide_bank_of(logic [AddrWidth-1:0] addr);
    return (addr >> WideWordBit) % NumWideBanks;
  endfunction
  function automatic int unsigned sub_bank_of(logic [AddrWidth-1:0] addr);
    return (addr >> NarrowWordBit) % NWDivisor;
  endfunction
  function automatic int unsigned pseudo_bank_of(logic [AddrWidth-1:0] addr);
    return (addr >> NarrowWordBit) % (1 << PseudoBankBits);
  endfunction

  // A physical bank is closed to narrow when wide holds priority or the ECC SRAM stalls for RMW
  function automatic logic bank_wide_prio(int unsigned wb, int unsigned sb);
    if (WidePriorityWait == 0) return 1'b0;
    return i_dut.wide_priority_q[wb][sb] == WidePriorityWait;
  endfunction
  function automatic logic bank_rmw(int unsigned wb, int unsigned sb);
    return !i_dut.gnt_bank[wb][sb];
  endfunction

  longint unsigned w_gnt, w_stall, w_rvalid, cyc;

  always @(posedge clk) begin
    if (measure) begin
      cyc++;
      for (int p = 0; p < NumNarrowReq; p++) begin
        if (narrow_req[p] && narrow_gnt[p]) begin
          n_gnt[p]++;
          wait_sum[p] += cur_wait[p];
          if (cur_wait[p] > max_wait[p]) max_wait[p] = cur_wait[p];
          cur_wait[p] = 0;
        end else if (narrow_req[p]) begin
          automatic int unsigned pb = pseudo_bank_of(narrow_addr[p]);
          automatic int unsigned wb = wide_bank_of(narrow_addr[p]);
          automatic int unsigned sb = sub_bank_of(narrow_addr[p]);
          automatic logic winner_found = 1'b0;
          automatic logic winner_same_bank = 1'b0;
          n_stall[p]++;
          cur_wait[p]++;
          // Did another narrow port win this pseudo bank this cycle?
          for (int q = 0; q < NumNarrowReq; q++) begin
            if (q != p && narrow_req[q] && narrow_gnt[q] &&
                pseudo_bank_of(narrow_addr[q]) == pb) begin
              winner_found = 1'b1;
              winner_same_bank = (wide_bank_of(narrow_addr[q]) == wb);
            end
          end
          if (winner_found) begin
            if (winner_same_bank) st_true[p]++;
            else st_false[p]++;
          end else if (bank_wide_prio(wb, sb)) begin
            st_wide[p]++;
          end else if (bank_rmw(wb, sb)) begin
            st_rmw[p]++;
          end else begin
            // Own bank is open but the pseudo bank is locked on a request stuck at another bank
            automatic logic blocked_elsewhere = 1'b0;
            for (int q = 0; q < NumNarrowReq; q++) begin
              if (q != p && narrow_req[q] && pseudo_bank_of(narrow_addr[q]) == pb &&
                  wide_bank_of(narrow_addr[q]) != wb) blocked_elsewhere = 1'b1;
            end
            if (blocked_elsewhere) st_hol[p]++;
            else st_other[p]++;
          end
        end
      end
      if (wide_req[0] && wide_gnt[0]) begin
        w_gnt++;
      end else if (wide_req[0]) begin
        w_stall++;
      end
    end
    // Every request (read or write) gets an rvalid; count them in and after the window
    if (measure || draining) begin
      for (int p = 0; p < NumNarrowReq; p++) if (narrow_rvalid[p]) n_rvalid[p]++;
      if (wide_rvalid[0]) w_rvalid++;
    end
  end

  ///////////////
  // Sequencer //
  ///////////////

  initial begin
    measure  = 1'b0;
    draining = 1'b0;
    cyc      = 0;
    w_gnt    = 0;
    w_stall  = 0;
    w_rvalid = 0;
    for (int p = 0; p < NumNarrowReq; p++) begin
      n_gnt[p]    = 0;
      n_stall[p]  = 0;
      n_rvalid[p] = 0;
      wait_sum[p] = 0;
      st_true[p]  = 0;
      st_false[p] = 0;
      st_hol[p]   = 0;
      st_wide[p]  = 0;
      st_rmw[p]   = 0;
      st_other[p] = 0;
      cur_wait[p] = 0;
      max_wait[p] = 0;
    end
    @(posedge rst_n);
    @(posedge clk);
    #1ps;
    measure = 1'b1;
    repeat (cycles) @(posedge clk);
    // Stop issuing; let outstanding requests complete, then drain responses
    #1ps;
    measure  = 1'b0;
    draining = 1'b1;
    wait (!(|narrow_req) && !(|wide_req));
    repeat (50) @(posedge clk);
    report();
    $finish;
  end

  // Requests granted after the window closes still produce responses; account for them
  longint unsigned n_gnt_drain[NumNarrowReq], w_gnt_drain;
  initial begin
    w_gnt_drain = 0;
    for (int p = 0; p < NumNarrowReq; p++) n_gnt_drain[p] = 0;
  end
  always @(posedge clk) begin
    if (draining) begin
      for (int p = 0; p < NumNarrowReq; p++) if (narrow_req[p] && narrow_gnt[p]) n_gnt_drain[p]++;
      if (wide_req[0] && wide_gnt[0]) w_gnt_drain++;
    end
  end

  function automatic void report();
    int errors = 0;
    for (int p = 0; p < NumNarrowReq; p++) begin
      $display("RESULT kind=narrow scen=%s bf=%0d inj=%0d off=%0d port=%0d cycles=%0d gnt=%0d ",
               scenario, NarrowExtraBF, inj, offset, p, cyc, n_gnt[p],
               "stall=%0d true=%0d false=%0d hol=%0d wide=%0d rmw=%0d other=%0d wait_sum=%0d max_wait=%0d",
               n_stall[p], st_true[p], st_false[p], st_hol[p], st_wide[p], st_rmw[p], st_other[p],
               wait_sum[p], max_wait[p]);
      if (n_rvalid[p] != n_gnt[p] + n_gnt_drain[p]) begin
        $error("port %0d: %0d rvalid vs %0d grants", p, n_rvalid[p], n_gnt[p] + n_gnt_drain[p]);
        errors++;
      end
      if (st_true[p] + st_false[p] + st_hol[p] + st_wide[p] + st_rmw[p] + st_other[p] !=
          n_stall[p]) begin
        $error("port %0d: stall attribution does not add up", p);
        errors++;
      end
    end
    $display("RESULT kind=wide scen=%s bf=%0d inj=%0d off=%0d port=0 cycles=%0d gnt=%0d stall=%0d",
             scenario, NarrowExtraBF, inj, offset, cyc, w_gnt, w_stall);
    if (w_rvalid != w_gnt + w_gnt_drain) begin
      $error("wide: %0d rvalid vs %0d grants", w_rvalid, w_gnt + w_gnt_drain);
      errors++;
    end
    $display("SANITY %s", errors == 0 ? "PASS" : "FAIL");
  endfunction

endmodule
