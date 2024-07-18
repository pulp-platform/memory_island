# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Michael Rogenmoser <michaero@iis.ee.ethz.ch>

BENDER ?= bender -d $(CURDIR)

VSIM ?= vsim

scripts/compile.tcl: Bender.yml Bender.lock
	$(BENDER) script vsim -t test --vlog-arg="-svinputport=compat" > $@
	echo "return 0" >> $@

.PHONY: test-vsim
test-vsim: scripts/compile.tcl
	$(VSIM) -64 -c -do "quit -code [source scripts/compile.tcl]"
	$(VSIM) -64 -do "vsim axi_memory_island_tb -voptargs=+acc; do scripts/debug_wave.do"
