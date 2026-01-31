# 3GPP Specification Compliance & Clause Mapping Matrix

This document provides a comprehensive cross-reference mapping between official 3GPP technical specifications and the concrete implementation classes, actors, and functions within Truss.

---

## 1. 3GPP TS 29.244 (PFCP v17.0.0)

| Clause | Specification Title | Truss Implementation | File Reference |
| :--- | :--- | :--- | :--- |
| **6.2.2** | Heartbeat Procedure | `PfcpHeartbeatReq`, `PfcpHeartbeatResp` | `src/pfcp/messages.pony` |
| **6.2.6** | Association Setup Procedure | `PfcpAssociationSetupReq`, `PfcpAssociationSetupResp` | `src/pfcp/messages.pony` |
| **6.2.7** | Association Update Procedure | `AssociationState`, `AssocStateEstablished` | `src/pfcp/state_machine.pony` |
| **6.2.8** | Association Release Procedure | `PfcpMsgTypeAssociationReleaseRequest` | `src/pfcp/header.pony` |
| **6.3.2** | Session Establishment Procedure | `SessionActor`, `SessionRegistry` | `src/truss/session_actor.pony` |
| **6.3.3** | Session Modification Procedure | `PfcpMsgTypeSessionModificationRequest` | `src/pfcp/header.pony` |
| **6.3.4** | Session Deletion Procedure | `remove_session`, `generate_final_report` | `src/truss/session_registry.pony` |
| **7.2.2** | Message Header Formats | `PfcpHeader` (Node vs Session format) | `src/pfcp/header.pony` |
| **7.2.2.4** | Sequence Number and Retransmission | `PfcpTransactionTracker` | `src/pfcp/state_machine.pony` |
| **7.5.2** | Information Elements Catalog | `PfcpIeCodec`, `PfcpRawIe` | `src/pfcp/ie_codec.pony` |
| **8.2.1** | Cause Information Element | `CauseRequestAccepted`, `CauseRequestRejected` | `src/truss_core/types.pony` |
| **8.2.2** | Source Interface IE | `AccessInterface`, `CoreInterface`, `SgiInterface` | `src/truss_core/types.pony` |
| **8.2.3** | F-TEID Information Element | `FTeidIe` | `src/pfcp/ie_types.pony` |
| **8.2.4** | Network Instance IE | `NetworkInstanceIe` | `src/pfcp/ie_types.pony` |
| **8.2.7** | Gate Status IE | `GateOpen`, `GateClosed` | `src/truss_core/types.pony` |
| **8.2.8** | Maximum Bitrate (MBR) IE | `MbrIe` | `src/pfcp/ie_types.pony` |
| **8.2.9** | Guaranteed Bitrate (GBR) IE | `GbrIe` | `src/pfcp/ie_types.pony` |
| **8.2.26** | Apply Action IE | `ForwardingActionForw`, `ForwardingActionDrop` | `src/truss_core/types.pony` |
| **8.2.38** | Node ID Information Element | `NodeIdIe` (IPv4 and FQDN modes) | `src/pfcp/ie_types.pony` |
| **8.2.39** | F-SEID Information Element | `FSeidIe` | `src/pfcp/ie_types.pony` |
| **8.2.48** | Recovery Time Stamp IE | `encode_recovery_time_stamp` | `src/pfcp/ie_codec.pony` |
| **8.2.56** | Outer Header Creation IE | `OuterHeaderCreationIe`, `OuterHeaderGtpUUdpIpv4` | `src/truss_core/types.pony` |
| **8.2.64** | Volume Measurement IE | `VolumeMeasurement` | `src/truss_core/usage_meter.pony` |
| **8.2.65** | Duration Measurement IE | `UsageReport` | `src/truss_core/usage_meter.pony` |
| **8.2.66** | Usage Report Information Element | `UsageMeter`, `trigger_report` | `src/truss_core/usage_meter.pony` |

---

## 2. 3GPP TS 29.281 (GTP-U v17.0.0)

| Clause | Specification Title | Truss Implementation | File Reference |
| :--- | :--- | :--- | :--- |
| **5.1** | GTP-U Header Format & Flags | `GtpuHeader`, `GtpuFlags` | `src/gtpu/header.pony` |
| **5.1.1** | Version & Protocol Type Fields | `version == 1`, `pt == true` validation | `src/gtpu/header.pony` |
| **5.1.2** | Tunnel Endpoint Identifier (TEID) | 32-bit TEID dispatch in pipeline | `src/gtpu/header.pony` |
| **5.2.1** | Extension Header Mechanism | `GtpuExtensionHeader` codec | `src/gtpu/extension.pony` |
| **6.1** | GTP-U Message Types | `GtpuMessageType`, `GtpuTypeGPdu` | `src/gtpu/header.pony` |
| **7.1** | User Plane Packet Processing | `GtpuPacket.decode`, `fastpath_gtpu_encapsulate` | `src/gtpu/packet.pony` |
| **7.2** | Error Indication Handling | `GtpuTypeErrorIndication` | `src/gtpu/header.pony` |
| **7.3** | End Marker Processing | `GtpuTypeEndMarker` | `src/gtpu/header.pony` |

---

## 3. 3GPP TS 38.415 (PDU Session User Plane Protocol)

| Clause | Specification Title | Truss Implementation | File Reference |
| :--- | :--- | :--- | :--- |
| **5.5.2** | PDU Session Container Format | `PduSessionContainer` | `src/gtpu/extension.pony` |
| **5.5.2.1** | QoS Flow Identifier (QFI) | 6-bit QFI extraction and tag matching | `src/gtpu/extension.pony` |
| **5.5.2.2** | Reflective QoS Indicator (RQI) | RQI flag parsing | `src/gtpu/extension.pony` |
| **5.5.2.3** | PDU Type (DL / UL Direction) | Uplink / Downlink container layout | `src/gtpu/extension.pony` |

---

## 4. IETF RFC Standards

| RFC | Title | Truss Implementation | File Reference |
| :--- | :--- | :--- | :--- |
| **RFC 791** | Internet Protocol (IPv4) | `Ipv4Address`, checksum validation | `src/truss_core/types.pony` |
| **RFC 768** | User Datagram Protocol (UDP) | UDP header parse and length validation | `src/truss/socket.pony` |
| **RFC 1071** | Computing the Internet Checksum | `fastpath_checksum16` (AVX2/NEON) | `src/c_fastpath/checksum.c` |
| **RFC 1624** | Incremental Internet Checksum Update | `fastpath_checksum_update16` | `src/c_fastpath/checksum.c` |
| **RFC 2698** | Two-Rate Three-Color Marker (trTCM) | `TrtcmMeter` (CIR/CBS and PIR/PBS policing)| `src/truss_core/trtcm.pony` |
