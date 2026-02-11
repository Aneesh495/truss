# Truss Operator & Deployment Guide

## 1. System Requirements & Prerequisites

### 1.1 Operating Systems & Architecture
- **Linux:** Ubuntu 22.04 LTS / Debian 12 / RHEL 9 (x86_64, aarch64)
- **macOS:** Darwin 23.x / 24.x (Apple Silicon ARM64, Intel x86_64)

### 1.2 Toolchain Dependencies
- **Pony Compiler:** `ponyc` version 0.78.1 or later
- **C Compiler:** `clang` (LLVM 15+) or `gcc` (GCC 11+)
- **System Libraries:** OpenSSL 3.0.x (`libssl-dev`, `openssl`), GNU Make
- **Python Runtime:** Python 3.9+ (for CLI tooling and simulators)

---

## 2. Compilation and Binary Installation

To compile the native C fastpath acceleration library, UPF daemon binary, and test suite:

```bash
# Clone the repository
git clone https://github.com/Aneesh495/truss.git
cd truss

# Build all binaries
make all

# Verify build outputs
ls -lh bin/
# Expected: bin/truss, bin/test_suite, bin/c_fastpath_bench
```

---

## 3. Configuration Management

Truss can be run with command-line interface arguments or loaded with a structured configuration:

```bash
./bin/truss \
  --node-id 10.0.0.1 \
  --pfcp-ip 0.0.0.0 \
  --pfcp-port 8805 \
  --gtpu-ip 0.0.0.0 \
  --gtpu-port 2152 \
  --core-ip 10.100.0.1 \
  --admin-ip 127.0.0.1 \
  --admin-port 8080 \
  --log-level INFO
```

### 3.1 Network Interface Topology
In production cellular deployments, the UPF operates between two major network planes:
1. **N3 Interface (Access Plane):** Receives GTP-U encapsulated packets from gNodeB base stations over UDP port 2152.
2. **N4 Interface (Control Plane):** Receives 3GPP TS 29.244 PFCP session management instructions from the 5G Session Management Function (SMF) over UDP port 8805.
3. **N6 Interface (Data Network):** Routes decapsulated subscriber IP packets out to the external internet, intranet, or IMS network.

---

## 4. Telemetry & Monitoring Catalog

Truss exposes an OpenMetrics / Prometheus compatible telemetry endpoint at `http://<admin-ip>:<admin-port>/metrics`.

### 4.1 Datapath Metrics

| Metric Name | Type | Description |
| :--- | :--- | :--- |
| `truss_uptime_seconds` | Gauge | Elapsed time in seconds since UPF startup |
| `truss_active_sessions` | Gauge | Currently registered subscriber PDU sessions |
| `truss_rx_packets_total` | Counter | Total ingress packets received across all interfaces |
| `truss_rx_bytes_total` | Counter | Total ingress bytes received across all interfaces |
| `truss_tx_packets_total` | Counter | Total egress packets transmitted out of the UPF |
| `truss_tx_bytes_total` | Counter | Total egress bytes transmitted out of the UPF |

### 4.2 Drop & Error Counters

| Metric Name | Type | Description |
| :--- | :--- | :--- |
| `truss_drops_unknown_teid_total` | Counter | Packets dropped due to missing or unmapped TEID |
| `truss_drops_rate_limit_total` | Counter | Packets dropped due to QER trTCM token exhaustion |
| `truss_drops_gate_closed_total` | Counter | Packets dropped because session gate status is CLOSED |

### 4.3 Control Plane Metrics

| Metric Name | Type | Description |
| :--- | :--- | :--- |
| `truss_pfcp_requests_total` | Counter | Total PFCP requests received from SMF |
| `truss_pfcp_responses_total` | Counter | Total PFCP responses transmitted to SMF |

---

## 5. Administrative Control with `trussctl`

The repository includes `tools/trussctl`, an administrative CLI for inspecting running instances:

```bash
# Check daemon health status
./tools/trussctl --url http://127.0.0.1:8080 health

# Dump formatted node diagnostic status
./tools/trussctl --url http://127.0.0.1:8080 status

# Inspect Prometheus telemetry
./tools/trussctl --url http://127.0.0.1:8080 metrics

# List active subscriber PDU sessions
./tools/trussctl --url http://127.0.0.1:8080 sessions

# Launch live auto-refreshing terminal dashboard
./tools/trussctl --url http://127.0.0.1:8080 watch --interval 1.0
```

---

## 6. Troubleshooting Common Cellular Edge Issues

### 6.1 `truss_drops_unknown_teid_total` Increasing
- **Cause:** Ingress GTP-U packet arrives with a TEID that has not been established via PFCP, or whose session has expired.
- **Diagnostic:** Run `./tools/packet_inspector.py` to inspect the incoming TEID value. Run `./tools/trussctl sessions` to verify whether that TEID is bound to an active `SessionActor`.

### 6.2 `truss_drops_rate_limit_total` Increasing
- **Cause:** Subscriber traffic exceeds the Peak Information Rate (PIR) configured in the session's QER rule.
- **Diagnostic:** Query `/status` or `/metrics`. Review the configured PIR/PBS values sent in the PFCP Session Establishment Request.
