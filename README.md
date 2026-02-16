# Truss

```
  _______ _____  _    _  _____ _____ 
 |__   __|  __ \| |  | |/ ____/ ____|
    | |  | |__) | |  | | (___| (___  
    | |  |  _  /| |  | |\___ \\___ \ 
    | |  | | \ \| |__| |____) |___) |
    |_|  |_|  \_\\____/|_____/_____/ 
```

**High-Performance 3GPP 5G User Plane Function (UPF) and Zero-Contention Packet Routing Fabric**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Pony: 0.78.1](https://img.shields.io/badge/Pony-0.78.1-green.svg)](https://www.ponylang.io)
[![3GPP TS 29.244](https://img.shields.io/badge/3GPP-TS%2029.244%20(PFCP)-orange.svg)](docs/3GPP_SPEC_MAPPING.md)
[![3GPP TS 29.281](https://img.shields.io/badge/3GPP-TS%2029.281%20(GTP--U)-purple.svg)](docs/3GPP_SPEC_MAPPING.md)
[![Tests: 100% Passing](https://img.shields.io/badge/Tests-100%25%20Passing-brightgreen.svg)](docs/VERIFICATION_PASS.md)

---

## Overview

Truss is a modern, carrier-grade 3GPP 5G Core User Plane Function (UPF) engineered for line-rate packet forwarding, deterministic microsecond tail latencies, and zero lock contention. 

Telecom datapath architectures frequently suffer from thread synchronization bottlenecks, mutex contention on subscriber session registries, and uncoordinated garbage collection pauses that violate 5G Ultra-Reliable Low-Latency Communication (URLLC) Service Level Agreements. Truss addresses these fundamental architectural challenges by implementing the core datapath in **Pony**, harnessing its actor-model concurrency, mathematically verified reference capabilities (`iso`, `val`, `ref`, `tag`), and actor-local garbage collection to eliminate data races and synchronization locks at compile time.

Computationally intensive packet primitives (such as Internet checksum verification, CRC32c Castagnoli computation, DIR-24-8 longest-prefix routing lookups, and GTP-U header encapsulation) are offloaded to an AVX2/NEON vector-accelerated C fastpath layer seamlessly integrated via Pony Foreign Function Interface (FFI).

---

## Key Architectural Highlights

- **Zero-Lock Actor Concurrency:** Eliminates mutexes, spinlocks, and global read-write locks across subscriber lookup tables and packet queues. Each subscriber session is modeled as an independent actor (`SessionActor`).
- **Data-Race Freedom via Reference Capabilities:** Pony enforces strict memory isolation at compile time. Packet payloads are passed across actors as immutable `Array[U8] val` buffers with zero memory copying and zero race conditions.
- **Microsecond Control Plane:** Full implementation of 3GPP TS 29.244 Packet Forwarding Control Protocol (PFCP v17.0.0). Handles Association Setup, Heartbeats, and Session Establishment in under 300 microseconds.
- **Hardware-Accelerated DIR-24-8 LPM Trie:** Line-rate IPv4 longest prefix match lookups executing in 8.19 nanoseconds per packet (122+ Million lookups/sec).
- **RFC 2698 Two-Rate Three-Color Marker (trTCM):** Nanosecond-accurate token bucket metering for 5G QoS Flow Enforcement Rules (QER), classifying traffic into Green, Yellow, and Red streams.
- **Embedded Telemetry & Control API:** Built-in HTTP REST server exposing live JSON state dumps and OpenMetrics / Prometheus telemetry on `/metrics`.
- **Rich Operator Tooling Ecosystem:** Includes a standalone Python administrative CLI (`tools/trussctl`), synthetic 5G SMF protocol emulator (`tools/smf_simulator.py`), high-throughput gNodeB traffic generator (`tools/ran_traffic_gen.py`), protocol dissector (`tools/packet_inspector.py`), and specification conformance test suite (`tools/conformance_suite.py`).

---

## System Architecture

```
                      +---------------------------------------+
                      |         Supervisor Actor (Main)       |
                      +-------------------+-------------------+
                                          |
         +--------------------------------+-------------------------------+
         |                                |                               |
+--------v---------+             +--------v---------+            +--------v---------+
|   NodeManager    |             | PacketPipeline   |            |   AdminServer    |
| (PFCP Port 8805) |             | (GTP-U Port 2152)|            | (HTTP Port 8080) |
+--------+---------+             +--------+---------+            +--------+---------+
         |                                |                               |
         | (PFCP Session Rules)           | (O(1) Route & Dispatch)       | (Metrics)
         v                                v                               v
+------------------+             +------------------+            +------------------+
| SessionRegistry  |<------------|  RoutingTrie     |            | MetricsCollector |
| (Concurrent Map) |             |  (DIR-24-8 C)    |            | (Histograms/Counters)
+--------+---------+             +------------------+            +------------------+
         |
         | (1:1 Actor Mapping)
         v
+---------------------------------------------------+
|               SessionActor Pool                   |
|   Session 1         Session 2       Session N     |
| [PDR/FAR/QER/URR] [PDR/FAR/QER/URR] [PDR/FAR/QER] |
+---------------------------------------------------+
```

For detailed architectural specifications, capability matrices, and memory lifecycles, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Empirical Benchmark Highlights

Micro-benchmarks evaluated on bare-metal ARM64 hardware (Apple Silicon NEON vector extensions, Clang `-O3`, Ponyc 0.78.1). For methodology and full percentile logs, see [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

```
+-------------------------------------------------------------------------------+
| Fastpath Subsystem         | Workload / Frame | Throughput    | Mean Latency  |
+----------------------------+------------------+---------------+---------------+
| RFC 1071 Internet Checksum | 1400B IPv4 Frame | 488.33 Gbps   | 22.94 ns      |
| DIR-24-8 LPM Route Lookup  | Random IPv4 /32  | 122.13 Mpps   | 8.19 ns       |
| GTP-U Encap (N3 Pipeline)  | 128B Inner PDU   | 106.24 Mpps   | 9.41 ns       |
| PFCP Heartbeat Roundtrip   | TS 29.244 (UDP)  | 7,027 tx/sec  | 128.00 us     |
| PFCP Session Establishment | PDR + FAR Rules  | 3,846 tx/sec  | 260.00 us     |
+-------------------------------------------------------------------------------+
```

---

## Repository Structure

```
.
|-- Makefile                      # Root build configuration and targets
|-- corral.json                   # Pony package manager manifest
|-- LICENSE                       # MIT open source license
|-- README.md                     # Master documentation
|-- benchmarks/                   # Benchmark harnesses and profiling suites
|   |-- c_fastpath_bench.c        # Native C fastpath micro-benchmark binary
|   |-- bench_runner.py           # Master benchmark runner and report compiler
|   |-- latency_profiler.py       # High-resolution percentile latency profiler
|   `-- throughput_eval.py        # Frame-size scaling and throughput evaluator
|-- docs/                         # In-depth technical documentation
|   |-- ARCHITECTURE.md           # Deep architectural specification
|   |-- 3GPP_SPEC_MAPPING.md      # Specification clause mapping matrix
|   |-- PROTOCOL_MANUAL.md        # Wire formats and bit-level diagrams
|   |-- BENCHMARKS.md             # Empirical performance evaluation
|   |-- OPERATOR_GUIDE.md         # Deployment and observability manual
|   `-- VERIFICATION_PASS.md      # QA matrix and bug resolution logs
|-- src/                          # Pony and C source code
|   |-- c_fastpath/               # C99 fastpath acceleration layer
|   |   |-- fastpath.h            # Fastpath header declarations
|   |   |-- checksum.c            # RFC 1071 / RFC 1624 checksum engine
|   |   |-- lpm_trie.c            # DIR-24-8 longest prefix match trie
|   |   |-- gtpu_encap.c          # Optimized GTP-U header encapsulation
|   |   `-- token_bucket.c        # High-speed token bucket policer
|   |-- truss_core/               # Core Pony networking primitives
|   |   |-- types.pony            # IPv4 address, 5-tuple, and network types
|   |   |-- ffi.pony              # Foreign Function Interface bindings
|   |   |-- routing_trie.pony     # Safe Pony wrapper around C LPM trie
|   |   |-- token_bucket.pony     # Nanosecond token bucket rate limiter
|   |   |-- trtcm.pony            # RFC 2698 Two-Rate Three-Color Marker
|   |   |-- usage_meter.pony      # TS 29.244 URR volume and time accounting
|   |   |-- buffer_pool.pony      # Ring buffer for paging and jitter buffering
|   |   |-- monotonic_clock.pony  # Nanosecond monotonic timing primitives
|   |   `-- logger.pony           # Asynchronous actor logger
|   |-- gtpu/                     # 3GPP TS 29.281 GTP-U Protocol Package
|   |   |-- header.pony           # GTP-U header codecs and flag bitmasks
|   |   |-- extension.pony        # TS 38.415 PDU session container codec
|   |   |-- packet.pony           # Full GTP-U packet parser and serializer
|   |   `-- tunnel_endpoint.pony  # Decapsulation actor
|   |-- pfcp/                     # 3GPP TS 29.244 PFCP Protocol Package
|   |   |-- header.pony           # Node vs Session binary header codecs
|   |   |-- ie_types.pony         # Information Element definitions
|   |   |-- ie_codec.pony         # Binary TLV encoder and decoder
|   |   |-- messages.pony         # Heartbeat, Association, Session messages
|   |   `-- state_machine.pony    # Association FSM and transaction cache
|   |-- truss/                    # Main UPF Daemon & Datapath Assembly
|   |   |-- main.pony             # Root supervisor and runtime entrypoint
|   |   |-- config.pony           # Configuration loader and parser
|   |   |-- session_actor.pony    # Subscriber PDU session actor
|   |   |-- session_registry.pony # O(1) TEID/IP session dispatcher
|   |   |-- node_manager.pony     # PFCP control plane coordinator
|   |   |-- packet_pipeline.pony  # User plane packet routing engine
|   |   |-- socket.pony           # UDP socket actors for N3 and N4
|   |   |-- admin.pony            # Embedded HTTP REST telemetry server
|   |   `-- metrics.pony          # OpenMetrics histogram and counter collector
|   `-- test_suite/               # Comprehensive Unit Test Suite
|       |-- main.pony             # Test suite runner
|       |-- test_c_fastpath.pony  # C fastpath unit tests
|       |-- test_core.pony        # Core primitives unit tests
|       |-- test_gtpu.pony        # GTP-U protocol unit tests
|       |-- test_pfcp.pony        # PFCP protocol unit tests
|       `-- test_pipeline.pony    # Pipeline and session actor unit tests
`-- tools/                        # Control plane and testing tooling
    |-- trussctl                  # Administrative CLI for status and telemetry
    |-- smf_simulator.py          # 3GPP TS 29.244 PFCP SMF emulator
    |-- ran_traffic_gen.py        # 3GPP TS 29.281 GTP-U traffic generator
    |-- packet_inspector.py       # Bit-level protocol dissector
    |-- synthetic_workload.py     # Multi-subscriber workload orchestrator
    `-- conformance_suite.py      # Automated 3GPP conformance test runner
```

---

## Quickstart Guide

### 1. Prerequisites
Ensure `ponyc` (0.78.1+), `clang`, `openssl`, and `make` are installed:
```bash
# macOS (via Homebrew)
brew install ponyc corral openssl@3

# Linux (Ubuntu / Debian)
sudo apt-get install clang libssl-dev make
```

### 2. Compilation
Compile all native libraries, executables, and test suites:
```bash
make all
```

### 3. Run Unit Tests
Execute the Pony unit test suite verifying fastpath, codecs, and actors:
```bash
make test
```

### 4. Run C Micro-Benchmarks
Execute high-resolution fastpath micro-benchmarks:
```bash
make bench-c
```

### 5. Launch UPF Daemon
Run the Truss UPF daemon on standard cellular interfaces:
```bash
./bin/truss \
  --node-id 10.0.0.1 \
  --pfcp-port 8805 \
  --gtpu-port 2152 \
  --admin-port 8080
```

### 6. Inspect Telemetry with `trussctl`
In a separate terminal, use `trussctl` to query the live UPF:
```bash
# Check health
./tools/trussctl health

# View diagnostic status
./tools/trussctl status

# Dump Prometheus metrics
./tools/trussctl metrics

# Launch live auto-refreshing monitor
./tools/trussctl watch
```

---

## Testing & Conformance Verification

Truss includes a complete test ecosystem spanning unit tests, protocol dissection, and 3GPP specification conformance:

```bash
# 1. Run unit test suite (20 tests covering all actors and codecs)
./bin/test_suite

# 2. Run 3GPP conformance suite against running UPF
./tools/conformance_suite.py

# 3. Simulate multi-subscriber traffic workload (20 UEs, 50 pkts/UE)
./tools/synthetic_workload.py --subscribers 20 --packets 50

# 4. Dissect raw GTP-U packet hex stream
./tools/packet_inspector.py 30ff0014aabbccdd4500001400010000401100000a0000010a000002
```

For defect analysis, regression test cases, and quality assurance logs, see [docs/VERIFICATION_PASS.md](docs/VERIFICATION_PASS.md).

---

## 3GPP Specification Compliance Matrix

Truss adheres strictly to the normative requirements of 3GPP cellular standards:

- **3GPP TS 29.244 (Release 17):** Interface between the Control Plane and the User Plane nodes (PFCP).
- **3GPP TS 29.281 (Release 17):** General Packet Radio System (GPRS) Tunnelling Protocol User Plane (GTPv1-U).
- **3GPP TS 38.415 (Release 17):** NG-RAN; PDU Session User Plane Protocol.
- **IETF RFC 2698:** A Two Rate Three Color Marker.
- **IETF RFC 1071 / RFC 1624:** Computation and Incremental Update of the Internet Checksum.

For complete clause-by-clause mapping, consult [docs/3GPP_SPEC_MAPPING.md](docs/3GPP_SPEC_MAPPING.md).

---

## License

Truss is open-source software licensed under the [MIT License](LICENSE).
