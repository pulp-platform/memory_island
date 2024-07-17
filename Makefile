# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Michael Rogenmoser <michaero@iis.ee.ethz.ch>

BENDER ?= bender -d $(CURDIR)
PYTHON ?= python

IDMA_DIR := $(shell $(BENDER) path idma)
# ifneq ($(wildcard .bender),)
-include $(IDMA_DIR)/idma.mk

# endif
src/dma/memory_island_dma.sv: $(IDMA_RTL_DIR)/idma_transport_layer_rw_obi.sv $(IDMA_RTL_DIR)/idma_legalizer_rw_obi.sv $(IDMA_RTL_DIR)/idma_backend_rw_obi.sv
	$(CAT) $^ > $@

# 	python $(IDMA_DIR)/util/gen_idma.py --help
# 	python $(IDMA_DIR)/util/gen_idma.py --entity backend --tpl $(IDMA_ROOT)/src/backend/tpl/idma_backend.sv.tpl --ids obi rw obi rw


VSIM ?= vsim

scripts/compile.tcl: Bender.yml Bender.lock
	$(BENDER) script vsim -t test --vlog-arg="-svinputport=compat" > $@
	echo "return 0" >> $@

.PHONY: test-vsim
test-vsim: scripts/compile.tcl
	$(VSIM) -64 -c -do "quit -code [source scripts/compile.tcl]"
	$(VSIM) -64 -do "vsim axi_memory_island_tb -voptargs=+acc; do scripts/debug_wave.do"
