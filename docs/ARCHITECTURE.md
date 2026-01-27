# Truss Architecture & System Design

## 1. Executive Architectural Overview

Truss is a high-performance 3GPP 5G Core User Plane Function (UPF) designed for carrier-grade throughput, ultra-reliable low-latency communication (URLLC), and zero lock-contention packet routing. The core processing engine is implemented in Pony, utilizing its actor-model concurrency, type-safe reference capabilities, and causal message ordering to eliminate data races and thread synchronization locks. Low-level, computationally intensive operations (Internet checksum calculation, CRC32c Castagnoli hashing, DIR-24-8 LPM routing lookups, and GTP-U header encapsulation) are offloaded to an AVX2/NEON-accelerated C fastpath layer linked directly via Pony Foreign Function Interface (FFI).

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
         | (Session Rules)                | (O(1) Route & Dispatch)       | (Metrics)
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

---

## 2. Actor Model & Concurrency Paradigm

### 2.1 The Problem with Multi-Threaded Locking
Traditional telecom packet processing engines rely on lock-based synchronization (mutexes, rwlocks, spinlocks) or complex lock-free data structures to coordinate session state between control plane threads and datapath worker cores. Under multi-gigabit traffic and high subscriber connection churn, thread contention on shared hash maps degrades cache efficiency and introduces latency spikes that violate URLLC latency budgets.

### 2.2 Pony Actor Concurrency
Truss eliminates all synchronization primitives by modeling each concurrent component as an isolated, asynchronous actor:

1. **Isolation by Default:** Actors do not share mutable memory. Each actor owns its private heap space and manages its internal state independently.
2. **Asynchronous Message Passing:** Inter-actor communication occurs strictly through asynchronous behaviors (`be`). Behaviors are queued in lock-free, per-actor FIFO message queues and scheduled onto work-stealing runtime worker threads.
3. **No Garbage Collection Pauses:** Pony employs a concurrent, actor-local garbage collection mechanism. When an actor collects memory, only its private heap is examined; no other actors or worker threads are halted.

---

## 3. Reference Capability Ownership (`iso`, `val`, `ref`, `tag`)

Pony guarantees data race freedom at compile time through its mathematically sound reference capability type system. Truss leverages these guarantees across the datapath:

```
+-----------------------------------------------------------------------------+
| Capability | Mutability | Sendable Across Actors | Datapath Usage            |
+------------+------------+------------------------+--------------------------+
| val        | Immutable  | Yes                    | Packet buffers, IP addrs,|
|            |            |                        | rule structs, metrics    |
+------------+------------+------------------------+--------------------------+
| iso        | Mutable    | Yes (via consume)      | Pipeline transfer, raw C |
|            |            |                        | output buffers, tries    |
+------------+------------+------------------------+--------------------------+
| ref        | Mutable    | No (Actor-Local)       | Internal session rules,  |
|            |            |                        | ring buffers, meters     |
+------------+------------+------------------------+--------------------------+
| tag        | Opaque     | Yes                    | Actor handles, sinks,    |
|            |            |                        | listeners, logger tags   |
+-----------------------------------------------------------------------------+
```

### 3.1 Zero-Copy Packet Buffer Handoff
When an ingress packet arrives on the UDP socket actor, it is packaged into an immutable `Array[U8] val` buffer. Because the buffer is marked `val`, it can be passed across the supervisor, pipeline, and session actors without deep-copying memory, while guaranteeing that no actor can concurrently mutate the buffer in flight.

---

## 4. Datapath Routing & Pipeline Architecture

### 4.1 Ingress N3 / RAN Processing Flow (Uplink)

```
[gNodeB Radio Access Network]
            |
            | (GTP-U / UDP 2152)
            v
+-------------------------------+
|    GtpuSocket Actor           | -> Receives raw UDP datagram
+---------------+---------------+
                |
                v
+-------------------------------+
|    PacketPipeline Actor       | -> Parses TS 29.281 GTP-U header
+---------------+---------------+ -> Extracts TEID (e.g., 0x00001389)
                |
                v
+-------------------------------+
|    SessionRegistry            | -> O(1) concurrent lookup: TEID -> SessionActor
+---------------+---------------+
                |
                v
+-------------------------------+
|    SessionActor (Subscriber)  | -> Evaluates PDRs by precedence
|   1. QER Token Bucket Check   | -> trTCM enforces CIR/CBS and PIR/PBS limits
|   2. URR Volume Accounting    | -> Accumulates byte and packet counters
|   3. FAR Forwarding Rule      | -> Determines forward, drop, or buffer action
+---------------+---------------+
                |
                v
+-------------------------------+
|    RoutingTrie (DIR-24-8)     | -> Line-rate IPv4 LPM route lookup (C fastpath)
+---------------+---------------+ -> Resolves egress next-hop and interface
                |
                v
+-------------------------------+
|    CoreSocket Actor (N6)      | -> Transmits raw IP packet to Data Network
+-------------------------------+
```

### 4.2 Ingress N6 / DN Processing Flow (Downlink)

```
[External Data Network (Internet)]
            |
            | (Raw IPv4 Packet)
            v
+-------------------------------+
|    CoreSocket Actor (N6)      | -> Receives downlink IPv4 packet
+---------------+---------------+
                |
                v
+-------------------------------+
|    PacketPipeline Actor       | -> Extracts destination UE IPv4 address
+---------------+---------------+
                |
                v
+-------------------------------+
|    SessionRegistry            | -> O(1) lookup: UE IP -> SessionActor
+---------------+---------------+
                |
                v
+-------------------------------+
|    SessionActor (Subscriber)  | -> Evaluates Downlink PDRs
|   1. QER Downlink Metering    | -> Rate shapes downlink traffic
|   2. URR Downlink Accounting  | -> Increments downlink counters
|   3. FAR Outer Header Encap   | -> Appends GTP-U header with gNodeB TEID
+---------------+---------------+
                |
                v
+-------------------------------+
|    GtpuSocket Actor (N3)      | -> Transmits GTP-U encapsulated packet to RAN
+-------------------------------+
```

---

## 5. C Fastpath Acceleration (DIR-24-8 LPM Trie)

IPv4 longest-prefix match (LPM) routing lookups are accelerated using the DIR-24-8 stride algorithm implemented in pure C99:

1. **Table 24 (TBL24):** A direct-indexed array of 16,777,216 entries (32 MB memory footprint) covering all IPv4 prefixes between /0 and /24. The first 24 bits of the IPv4 address directly index TBL24 in a single memory access.
2. **Table 8 (TBL8):** A secondary pool of 256-entry blocks allocated dynamically for prefixes more specific than /24 (/25 to /32). If bit 15 (`LPM_FLAG_TBL8`) is set in the TBL24 entry, the remaining 8 bits of the IPv4 address index the secondary TBL8 group.
3. **Lookup Latency:**
   - Prefixes <= /24: Exactly 1 memory access (~7 ns).
   - Prefixes > /24: Exactly 2 memory accesses (~14 ns).

---

## 6. Failure Isolation and Supervision Strategy

Truss adheres to the Erlang/Pony supervisor pattern:

1. **Hierarchical Supervision:** The root `Main` actor oversees subsystems (`NodeManager`, `PacketPipeline`, `AdminServer`, `MetricsCollector`).
2. **Actor Lifecycle Management:** If an individual subscriber's `SessionActor` encounters an unhandled exception or malformed payload, only that specific session actor is terminated. The `SessionRegistry` unbinds its TEID and UE IP mappings without impacting other subscribers.
3. **Control Plane Resiliency:** The `PfcpTransactionTracker` caches recent responses in an idempotent ring buffer. If the peer SMF retransmits requests over a lossy network, Truss returns the cached response without re-executing state transitions.
