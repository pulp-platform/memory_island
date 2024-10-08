# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Michael Rogenmoser <michaero@iis.ee.ethz.ch>

MEMORY_ISLAND_ROOT := $(CURDIR)

BENDER ?= bender -d $(MEMORY_ISLAND_ROOT)

VSIM ?= vsim

scripts/compile.tcl: Bender.yml Bender.lock
	$(BENDER) script vsim -t test --vlog-arg="-svinputport=compat" > $@
	echo "return 0" >> $@

.PHONY: test-vsim
test-vsim: scripts/compile.tcl
	$(VSIM) -64 -c -do "quit -code [source scripts/compile.tcl]"
	$(VSIM) -64 -do "vsim axi_memory_island_tb -voptargs=+acc; do scripts/debug_wave.do"

test-vsim-bare: scripts/compile.tcl
	$(VSIM) -64 -c -do "quit -code [source scripts/compile.tcl]"
	$(VSIM) -64 -c -do "vsim axi_memory_island_tb; run -all"

## Internal CI
NONFREE_REMOTE ?= git@iis-git.ee.ethz.ch:pulp-restricted/memory_island_nonfree.git
NONFREE_COMMIT ?= master

nonfree-init:
	git clone $(NONFREE_REMOTE) $(MEMORY_ISLAND_ROOT)/nonfree
	cd nonfree && git checkout $(NONFREE_COMMIT)

-include $(MEMORY_ISLAND_ROOT)/nonfree/nonfree.mk
