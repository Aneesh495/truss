# Truss Protocol Wire Formats & Codec Manual

## 1. 3GPP TS 29.244 PFCP Header Formats

PFCP packets are transmitted over UDP port 8805. The protocol specifies two distinct header formats depending on whether the message is Node-related (S bit = 0) or Session-related (S bit = 1).

### 1.1 Node-Related Header (8 Octets, S = 0)
Used for Heartbeat and Association management procedures.

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|Version| Spare |S|   Msg Type  |        Message Length         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                 Sequence Number (24-bit)      |     Spare     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- **Version (3 bits):** Protocol version, must be set to `1` (binary `001`).
- **Spare (4 bits):** Reserved for future extensions, transmitted as `0000`.
- **S (1 bit):** SEID present flag. Set to `0` for Node-related messages.
- **Message Type (8 bits):** 1 for Heartbeat Request, 2 for Heartbeat Response, 5 for Association Setup Request, 6 for Association Setup Response.
- **Message Length (16 bits):** Total length in octets of the payload following the 4-octet header prefix.
- **Sequence Number (24 bits):** Transaction identifier in network byte order.
- **Spare (8 bits):** Reserved padding octet, transmitted as `0x00`.

### 1.2 Session-Related Header (16 Octets, S = 1)
Used for subscriber PDU Session Establishment, Modification, Deletion, and Reporting.

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|Version| Spare |S|   Msg Type  |        Message Length         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
+                   Session Endpoint Identifier (SEID)          +
|                           (64-bit Big-Endian)                 |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                 Sequence Number (24-bit)      |     Spare     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- **S (1 bit):** Set to `1` indicating 8-octet SEID field is present.
- **SEID (64 bits):** Destination session identifier assigned by the receiver.

---

## 2. PFCP Type-Length-Value (TLV) Encoding

Information Elements (IEs) are serialized using 4-octet TLV headers:

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|            IE Type (16-bit)   |          Length (16-bit)      |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                         IE Value / Payload                    |
|                              ...                              |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### 2.1 Grouped IEs
Complex rules (Create PDR, Create FAR, Create QER, Create URR) encapsulate child TLVs inside their value field. Truss parses child TLVs recursively without dynamic memory allocations.

---

## 3. 3GPP TS 29.281 GTP-U Wire Format

GTP-U datagrams are carried over UDP port 2152.

### 3.1 Standard 8-Octet Header (No Optional Fields)
Used when sequence numbers, N-PDU numbers, and extension headers are absent (E=0, S=0, PN=0).

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|Version|PT |*|E|S|PN|   Msg Type |        Payload Length         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                  Tunnel Endpoint Identifier (TEID)            |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- **Version (3 bits):** Must be `1` (binary `001`).
- **PT (1 bit):** Protocol Type. Set to `1` for GTP (TS 29.281).
- **E (1 bit):** Extension header present.
- **S (1 bit):** Sequence number present.
- **PN (1 bit):** N-PDU number present.
- **Message Type (8 bits):** `255` (`0xFF`) for G-PDU user plane payload.
- **TEID (32 bits):** Tunnel identifier identifying the subscriber flow.

### 3.2 Extended 12-Octet Header (E=1 or S=1 or PN=1)

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|Version|PT |*|1|0|0 |  Msg Type  |        Payload Length         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                  Tunnel Endpoint Identifier (TEID)            |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|      Sequence Number (16-bit) |  N-PDU Number | Next Ext Type |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- **Next Extension Type (8 bits):** Identifies the first extension header (e.g., `0x85` for PDU Session Container).

---

## 4. 3GPP TS 38.415 PDU Session Container Format

Transmitted as a GTP-U extension header to transport 5G Quality of Service (QoS) parameters across the N3 interface.

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  Length (4-octet units: 1)    |PDU Typ| Spare |S|RQI|  QFI    |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
| Next Ext Header Type (0x00)   |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- **Length (8 bits):** Total extension header length divided by 4 octets (`1` for standard 4-octet container).
- **PDU Type (4 bits):** `0` for Downlink User Location Information, `1` for Uplink.
- **RQI (1 bit):** Reflective QoS Indicator.
- **QFI (6 bits):** QoS Flow Identifier (values 1 to 63).
- **Next Extension Header Type (8 bits):** `0x00` if no additional extensions follow.

---

## 5. RFC 2698 Two-Rate Three-Color Marker (trTCM) Algorithm

The Two-Rate Three-Color Marker meters IP packet traffic according to four configuration parameters:
- **PIR (Peak Information Rate):** Peak permitted bandwidth in bytes/second.
- **PBS (Peak Burst Size):** Peak token capacity in bytes.
- **CIR (Committed Information Rate):** Guaranteed bandwidth in bytes/second.
- **CBS (Committed Burst Size):** Committed token capacity in bytes.

### 5.1 Token Replenishment Model
Two token buckets ($T_p$ for peak and $T_c$ for committed) are replenished simultaneously at rates PIR and CIR:

$$T_p(t) = \min(PBS, T_p(t_{last}) + (t - t_{last}) \times PIR)$$
$$T_c(t) = \min(CBS, T_c(t_{last}) + (t - t_{last}) \times CIR)$$

### 5.2 Packet Marking Logic
For a packet of length $B$ arriving at time $t$:

```
                  +---------------------------+
                  | Packet arrives (Length B) |
                  +-------------+-------------+
                                |
                                v
                       /-----------------\
                      /   Is B > T_p ?    \
                      \                   /
                       \-----------------/
                         |             |
                   YES   |             | NO
                         v             v
                    +---------+  /-----------------\
                    |   RED   | /   Is B > T_c ?    \
                    | (Drop)  | \                   /
                    +---------+  \-----------------/
                                   |             |
                             YES   |             | NO
                                   v             v
                             +----------+  +-----------+
                             |  YELLOW  |  |   GREEN   |
                             | (T_p-=B) |  |(T_p,T_c-=B|
                             +----------+  +-----------+
```
