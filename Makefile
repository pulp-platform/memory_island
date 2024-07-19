# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Michael Rogenmoser <michaero@iis.ee.ethz.ch>

BENDER ?= bender -d $(CURDIR)
PYTHON ?= python

IDMA_DIR := $(shell $(BENDER) path idma)

-include $(IDMA_DIR)/idma.mk

DMA_REG_HSJON := $(IDMA_RTL_DIR)/idma_reg32_3d.hjson
DMA_REG_DEPS  := $(IDMA_RTL_DIR)/idma_reg32_3d_reg_pkg.sv
DMA_REG_DEPS  += $(IDMA_RTL_DIR)/idma_reg32_3d_reg_top.sv
DMA_REG_DEPS  += $(IDMA_RTL_DIR)/idma_reg32_3d_top.sv
DMA_DEPS      := $(DMA_REG_DEPS)
DMA_DEPS      += $(IDMA_RTL_DIR)/idma_transport_layer_rw_obi.sv
DMA_DEPS      += $(IDMA_RTL_DIR)/idma_legalizer_rw_obi.sv
DMA_DEPS      += $(IDMA_RTL_DIR)/idma_backend_rw_obi.sv

src/dma/memory_island_dma_generated.sv: $(DMA_REG_HSJON) $(DMA_DEPS)
	$(CAT) $(filter-out $<,$^) > $@

.PHONY: dma-gen
dma-gen: src/dma/memory_island_dma_generated.sv

VSIM ?= vsim

scripts/compile.tcl: Bender.yml Bender.lock
	$(BENDER) script vsim -t test -t rtl --vlog-arg="-svinputport=compat" > $@
	echo "return 0" >> $@

.PHONY: test-vsim
test-vsim: scripts/compile.tcl
	$(VSIM) -64 -c -do "quit -code [source scripts/compile.tcl]"
	$(VSIM) -64 -do "vsim axi_memory_island_tb -voptargs=+acc; do scripts/debug_wave.do"
