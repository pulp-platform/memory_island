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
$(MEMORY_ISLAND_ROOT)/build/compile-vcs: $(MEMORY_ISLAND_ROOT)/build
	$(BENDER) script vcs -t test --vlog-arg="$(VLOGAN_ARGS)" > $@
	chmod +x $@

-include $(MEMORY_ISLAND_ROOT)/nonfree/nonfree.mk

BENDER_FILES := $(shell $(BENDER) script flist -n -t test -t memory_island_standalone_synth)

.PHONY: format
format:
	verible-verilog-format $(BENDER_FILES) --inplace --flagfile .verilog_format


VCS_FLAGS ?= -full64 -nc -ignore initializer_driver_checks -assert disable_cover -kdb -Mlib=$(VCS_BUILDDIR)
VLOGAN_ARGS += -full64 -q -ntb_opts uvm -kdb -nc -assert svaext +v2k -timescale=1ps/1ps -incr_vlogan $(TRACE_FLAGS_VCS)

$(MEMORY_ISLAND_ROOT)/build:
	mkdir -p $@

$(MEMORY_ISLAND_ROOT)/build/vcs.bin: $(MEMORY_ISLAND_ROOT)/build/compile-vcs
	cd $(MEMORY_ISLAND_ROOT)/build && \
	sh $< && \
	vcs -top axi_memory_island_tb $(VCS_FLAGS) -o $@

.PHONY: test-vcs test-vcs-clean
test-vcs: $(MEMORY_ISLAND_ROOT)/build/vcs.bin
	cd $(MEMORY_ISLAND_ROOT)/build && \
	$<

test-vcs-clean:
	rm -rf $(MEMORY_ISLAND_ROOT)/build
