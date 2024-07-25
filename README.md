# Interleaved Memory Island

The Interleaved Memory Island is designed as a high-throughput low-contention L2 scratchpad memory for use in large System-on-Chip designs. It offers multiple ports for narrow low-latency accesses and wide high-throughput access.

The Memory Island is developed as part of the [PULP project](https://pulp-platform.org/), a joint effort between ETH Zurich and the University of Bologna.

## Architecture

The core part of the memory island supports multiple independent request ports of two data widths, called narrow and wide. The narrow requestors are generally assumed to have a data width of 32 or 64 bits (in line with processor cores) and are designed to have limited latency, while the wide requestors are assumed to have larger data widths (256, 512, 1024 bits) for high throughput, but tolerating some latency. All requestors access the same memory region, but due to the interleaved layout of the memory island, contention in accessing the individual banks is kept to a minimum.

## Top-level Modules

Various modules support different protocols for integration.

| Module Name | Protocol | Description |
|---|---|---|
| `memory_island_core` | OBI/TCDM | The core memory island module |
| `axi_memory_island_wrap` | AXI | AXI-compatible wrapper for the memory island |

### Testbenches

`axi_memory_island_tb`: Random AXI Masters with additional logic to avoid writes overlapping each-other or reads, with bus comparators comparing the AXI requests to the `axi_memory_island_wrap` and an AXI simulation memory, here used as the golden reference.

## Quickstart

To run a simulation with QuestaSim, use the `make test-vsim` target, which will compile the sourcecode and start the `axi_memory_island_tb` testbench with appropriate waves.

## License

Unless specified otherwise in the respective file headers, all code checked into this repository is made available under a permissive license. All hardware sources and tool scripts are licensed under the Solderpad Hardware License 0.51 (see [`LICENSE`](LICENSE)).
