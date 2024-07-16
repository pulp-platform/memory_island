onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /axi_memory_island_tb/clk
add wave -noupdate /axi_memory_island_tb/errors
add wave -noupdate -expand /axi_memory_island_tb/mismatch
add wave -noupdate -group top_tb /axi_memory_island_tb/rst_n
add wave -noupdate -group top_tb /axi_memory_island_tb/random_mem_filled
add wave -noupdate -group top_tb /axi_memory_island_tb/end_of_sim
add wave -noupdate -group top_tb /axi_memory_island_tb/axi_narrow_req
add wave -noupdate -group top_tb /axi_memory_island_tb/axi_narrow_rsp
add wave -noupdate -group top_tb /axi_memory_island_tb/axi_wide_req
add wave -noupdate -group top_tb /axi_memory_island_tb/axi_wide_rsp
add wave -noupdate -group top_tb /axi_memory_island_tb/filtered_narrow_req
add wave -noupdate -group top_tb /axi_memory_island_tb/filtered_narrow_rsp
add wave -noupdate -group top_tb /axi_memory_island_tb/filtered_wide_req
add wave -noupdate -group top_tb /axi_memory_island_tb/filtered_wide_rsp
add wave -noupdate -group top_tb /axi_memory_island_tb/filtered_narrow_req_cut
add wave -noupdate -group top_tb /axi_memory_island_tb/filtered_narrow_rsp_cut
add wave -noupdate -group top_tb /axi_memory_island_tb/filtered_wide_req_cut
add wave -noupdate -group top_tb /axi_memory_island_tb/filtered_wide_rsp_cut
add wave -noupdate -group top_tb /axi_memory_island_tb/dut_narrow_req
add wave -noupdate -group top_tb /axi_memory_island_tb/dut_narrow_rsp
add wave -noupdate -group top_tb /axi_memory_island_tb/dut_wide_req
add wave -noupdate -group top_tb /axi_memory_island_tb/dut_wide_rsp
add wave -noupdate -group top_tb /axi_memory_island_tb/golden_narrow_req
add wave -noupdate -group top_tb /axi_memory_island_tb/golden_narrow_rsp
add wave -noupdate -group top_tb /axi_memory_island_tb/golden_wide_req
add wave -noupdate -group top_tb /axi_memory_island_tb/golden_wide_rsp
add wave -noupdate -group top_tb /axi_memory_island_tb/blocking_write
add wave -noupdate -group top_tb /axi_memory_island_tb/blocking_read
add wave -noupdate -group top_tb /axi_memory_island_tb/tmp_read
add wave -noupdate -group top_tb /axi_memory_island_tb/tmp_write
add wave -noupdate -group top_tb /axi_memory_island_tb/write_range
add wave -noupdate -group top_tb /axi_memory_island_tb/read_range
add wave -noupdate -group top_tb /axi_memory_island_tb/aw_hs
add wave -noupdate -group top_tb /axi_memory_island_tb/ar_hs
add wave -noupdate -group top_tb /axi_memory_island_tb/write_len
add wave -noupdate -group top_tb /axi_memory_island_tb/read_len
add wave -noupdate -group top_tb /axi_memory_island_tb/write_overlapping_write
add wave -noupdate -group top_tb /axi_memory_island_tb/write_overlapping_read
add wave -noupdate -group top_tb /axi_memory_island_tb/read_overlapping_write
add wave -noupdate -group top_tb /axi_memory_island_tb/live_write_overlapping_write
add wave -noupdate -group top_tb /axi_memory_island_tb/live_write_overlapping_read
add wave -noupdate -group top_tb /axi_memory_island_tb/live_read_overlapping_write
add wave -noupdate -group top_tb /axi_memory_island_tb/golden_all_req
add wave -noupdate -group top_tb /axi_memory_island_tb/golden_all_rsp
add wave -noupdate -group compare0 {/axi_memory_island_tb/gen_narrow_stim[0]/i_narrow_compare/i_axi_bus_compare/*}
add wave -noupdate -group compare1 {/axi_memory_island_tb/gen_narrow_stim[1]/i_narrow_compare/i_axi_bus_compare/*}
add wave -noupdate -group compare2 {/axi_memory_island_tb/gen_narrow_stim[2]/i_narrow_compare/i_axi_bus_compare/*}
add wave -noupdate -group compare3 {/axi_memory_island_tb/gen_narrow_stim[3]/i_narrow_compare/i_axi_bus_compare/*}
add wave -noupdate -group compare4_w {/axi_memory_island_tb/gen_wide_stim[0]/i_wide_compare/i_axi_bus_compare/*}
add wave -noupdate -group compare5_w {/axi_memory_island_tb/gen_wide_stim[1]/i_wide_compare/i_axi_bus_compare/*}
add wave -noupdate -group memory_island /axi_memory_island_tb/i_dut/i_memory_island/*
