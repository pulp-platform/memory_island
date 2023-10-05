# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Michael Rogenmoser <michaero@iis.ee.ethz.ch>

BENDER ?= bender

scripts/compile.tcl:
	$(BENDER) script vsim -t test --vlog-arg="-svinputport=compat" > scripts/compile.tcl
