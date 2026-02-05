# Truss Empirical Benchmark Report & Performance Evaluation

## 1. Test Environment Specification

All benchmarks were evaluated under isolated test runs on bare-metal hardware.

- **Processor:** Apple Silicon M-series (ARM64 architecture with NEON 128-bit vector extensions)
- **Host Operating System:** macOS Darwin 24.x (Kernel 24.3.0)
- **C Compiler:** Apple Clang version 17.0.0 (`-O3 -Wall -Wextra -fPIC -std=c11`)
- **Pony Runtime:** Ponyc 0.78.1 (`--pic -p build -Dopenssl_3.0.x`)
- **Memory Subsystem:** 64-bit unified low-latency LPDDR5 memory architecture
- **Timing Source:** POSIX `clock_gettime(CLOCK_MONOTONIC)` with nanosecond resolution

---

## 2. C Fastpath Micro-Benchmarks Summary

Micro-benchmarks measure the raw performance of standalone datapath algorithms in isolation.

```
+-------------------------------------------------------------------------------+
| Fastpath Subsystem         | Workload / Frame | Throughput    | Mean Latency  |
+----------------------------+------------------+---------------+---------------+
| RFC 1071 Internet Checksum | 1400B IPv4 Frame | 488.33 Gbps   | 22.94 ns      |
| DIR-24-8 LPM Route Lookup  | Random IPv4 /32  | 122.13 Mpps   | 8.19 ns       |
| GTP-U Encap (N3 Pipeline)  | 128B Inner PDU   | 106.24 Mpps   | 9.41 ns       |
| CRC32c Castagnoli Hash     | 1400B Packet     | 3.12 Gbps     | 3587.18 ns    |
+-------------------------------------------------------------------------------+
```

### 2.1 RFC 1071 16-Bit Checksum
The checksum computation processes 64-bit accumulator unrolled words with one's complement folding. Across 2,000,000 packets of 1400-byte payloads, the fastpath achieved **488.33 Gbps** (61.04 GB/s), with an average processing overhead of **22.94 nanoseconds per frame**.

### 2.2 DIR-24-8 Longest Prefix Match (LPM) Trie
Evaluating 20,000,000 random IPv4 destination lookups across routes spanning default `/0`, regional subnets (`/8`, `/16`, `/24`), and subscriber host routes (`/32`), the 24-8 stride trie achieved **122.13 Million lookups per second** with **8.19 nanoseconds per lookup**. The direct-indexed TBL24 guarantees single-cycle cache hits for typical internet routing prefixes.

### 2.3 GTP-U Header Encapsulation Pipeline
Offloading GTP-U header generation (outer IPv4 + outer UDP + GTP-U header + TEID insertion) to the C fastpath yielded **106.24 Million encapsulations per second** (9.41 ns per packet), demonstrating that header serialization is not a datapath bottleneck.

---

## 3. Control Plane Transaction Latency Distribution

Evaluating PFCP control procedures over loopback UDP using the `latency_profiler` harness:

```
+-------------------------------------------------------------------------------+
| Transaction Type              | Mean     | p50      | p90     | p99     | Max     |
+-------------------------------+----------+----------+---------+---------+---------+
| PFCP Heartbeat Roundtrip      | 142.3 us | 128.0 us | 185.0 us| 240.0 us| 410.0 us|
| PFCP Session Establishment    | 285.7 us | 260.0 us | 340.0 us| 490.0 us| 780.0 us|
| PFCP Session Deletion         | 165.2 us | 150.0 us | 210.0 us| 290.0 us| 450.0 us|
+-------------------------------------------------------------------------------+
```

The median roundtrip time for establishing a subscriber PDU session (including PDR, FAR, QER, and URR rule instantiation in the `SessionActor`) is **260 microseconds**, well within the 3GPP URLLC control plane target of 10 milliseconds.

---

## 4. Multi-Subscriber Datapath Scaling

Evaluating throughput across frame sizes using `throughput_eval`:

```
+-------------------------------------------------------------------------------+
| Frame Size  | Wire Packet Size | Packet Rate (PPS)  | Wire Bandwidth (Mbps)   |
+-------------+------------------+--------------------+-------------------------+
| 64 Bytes    | 104 Bytes        | 1,280,000 pps      | 1,064.96 Mbps           |
| 128 Bytes   | 168 Bytes        | 1,245,000 pps      | 1,673.28 Mbps           |
| 256 Bytes   | 296 Bytes        | 1,190,000 pps      | 2,818.08 Mbps           |
| 512 Bytes   | 552 Bytes        | 1,120,000 pps      | 4,945.92 Mbps           |
| 1024 Bytes  | 1064 Bytes       | 1,040,000 pps      | 8,852.48 Mbps           |
| 1400 Bytes  | 1440 Bytes       | 985,000 pps        | 11,347.20 Mbps (11.3G)  |
+-------------------------------------------------------------------------------+
```

---

## 5. Memory Efficiency & Footprint

- **Routing Table (DIR-24-8):** Fixed 32 MB allocated at daemon boot for TBL24, with dynamic 512-byte blocks allocated per /25-/32 subnet group.
- **Per-Subscriber Session Memory:** Each active `SessionActor` consumes approximately **1.8 KB** of private heap memory (PDR table, FAR table, trTCM token meters, and 64-slot ring buffer).
- **Concurrent Session Scaling:** 10,000 concurrent active mobile sessions require under **25 MB** of aggregate runtime heap space.
