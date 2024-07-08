# Interleaved Memory Island

The Interleaved Memory Island is designed as a high-throughput low-contention L2 scratchpad memory for use in large System-on-Chip designs. It offers multiple ports for narrow low-latency accesses and wide high-throughput access.

The Memory Island is developed as part of the [PULP project](https://pulp-platform.org/), a joint effort between ETH Zurich and the University of Bologna.

## Top-level Modules

Various modules support different protocols for integration.

| Module Name | Protocol | Description |
|---|---|---|
| `memory_island_core` | OBI/TCDM | The core memory island module |
| `axi_memory_island_wrap` | AXI | AXI-compatible wrapper for the memory island |

### Testbenches


## License

Unless specified otherwise in the respective file headers, all code checked into this repository is made available under a permissive license. All hardware sources and tool scripts are licensed under the Solderpad Hardware License 0.51 (see [`LICENSE`](LICENSE)).
