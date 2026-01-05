#!/usr/bin/env python3
"""
Truss Protocol Packet Inspector & Dissector
Dissects 3GPP TS 29.281 GTP-U and TS 29.244 PFCP protocol streams,
displaying structured protocol trees with bit-level field decoding.
"""

import argparse
import binascii
import socket
import struct
import sys
from typing import Any, Dict, List, Optional, Tuple


# GTP-U Message Types (TS 29.281 Table 6.1-1)
GTPU_MSG_TYPES = {
    1: "Echo Request",
    2: "Echo Response",
    26: "Error Indication",
    254: "End Marker",
    255: "G-PDU (User Data)"
}

# PFCP Message Types (TS 29.244 Table 6.1-1)
PFCP_MSG_TYPES = {
    1: "Heartbeat Request",
    2: "Heartbeat Response",
    5: "Association Setup Request",
    6: "Association Setup Response",
    9: "Association Release Request",
    10: "Association Release Response",
    50: "Session Establishment Request",
    51: "Session Establishment Response",
    52: "Session Modification Request",
    53: "Session Modification Response",
    54: "Session Deletion Request",
    55: "Session Deletion Response",
    56: "Session Report Request",
    57: "Session Report Response"
}

# PFCP Information Element Names (TS 29.244 Table 8.1.1-1)
PFCP_IE_NAMES = {
    1: "Create PDR",
    2: "PDI (Packet Detection Information)",
    3: "Create FAR",
    4: "Forwarding Parameters",
    6: "Create URR",
    7: "Create QER",
    9: "Update PDR",
    10: "Update FAR",
    13: "Update URR",
    14: "Update QER",
    19: "Cause",
    20: "Source Interface",
    21: "F-TEID",
    22: "Network Instance",
    25: "Gate Status",
    26: "MBR (Maximum Bitrate)",
    27: "GBR (Guaranteed Bitrate)",
    29: "Precedence",
    42: "Destination Interface",
    44: "Apply Action",
    56: "PDR ID",
    57: "F-SEID",
    60: "Node ID",
    64: "Volume Threshold",
    66: "Volume Measurement",
    67: "Duration Measurement",
    78: "Usage Report",
    84: "Outer Header Creation",
    89: "QFI",
    95: "Outer Header Removal",
    96: "Recovery Time Stamp",
    108: "FAR ID",
    109: "QER ID",
    110: "URR ID"
}


def dissect_gtpu(data: bytes, indent: int = 0) -> None:
    """Dissect GTP-U packet according to 3GPP TS 29.281."""
    pfx = " " * indent
    if len(data) < 8:
        print(f"{pfx}[MALFORMED] Packet too short for GTP-U header ({len(data)} bytes)")
        return

    flags, msg_type, length, teid = struct.unpack("!BBHI", data[:8])
    version = (flags >> 5) & 0x07
    pt = bool(flags & 0x10)
    has_ext = bool(flags & 0x04)
    has_seq = bool(flags & 0x02)
    has_npdu = bool(flags & 0x01)

    type_name = GTPU_MSG_TYPES.get(msg_type, f"Unknown ({msg_type})")

    print(f"{pfx}\033[1;34m[GTP-U Header (TS 29.281)]\033[0m")
    print(f"{pfx}  Version:           {version}")
    print(f"{pfx}  Protocol Type:     {'GTP' if pt else 'GTP Prime'}")
    print(f"{pfx}  Extension Flag:    {has_ext}")
    print(f"{pfx}  Sequence Flag:     {has_seq}")
    print(f"{pfx}  N-PDU Flag:        {has_npdu}")
    print(f"{pfx}  Message Type:      {type_name} (0x{msg_type:02X})")
    print(f"{pfx}  Length:            {length} octets")
    print(f"{pfx}  TEID:              0x{teid:08X} ({teid})")

    offset = 8
    next_ext_type = 0
    if has_ext or has_seq or has_npdu:
        if len(data) < 12:
            print(f"{pfx}  [MALFORMED] Truncated optional header")
            return
        seq_num, npdu_num, next_ext_type = struct.unpack("!HBB", data[8:12])
        print(f"{pfx}  Sequence Number:   {seq_num}")
        print(f"{pfx}  N-PDU Number:      {npdu_num}")
        print(f"{pfx}  Next Ext Type:     0x{next_ext_type:02X}")
        offset = 12

    # Parse Extension Headers
    while next_ext_type != 0 and offset < len(data):
        if offset >= len(data):
            break
        ext_len_units = data[offset]
        total_ext_len = ext_len_units * 4
        if total_ext_len < 4 or (offset + total_ext_len) > len(data):
            print(f"{pfx}  [MALFORMED] Invalid extension header length")
            break

        ext_payload = data[offset + 1:offset + total_ext_len - 1]
        next_ext = data[offset + total_ext_len - 1]

        if next_ext_type == 0x85:
            # TS 38.415 PDU Session Container
            pdu_type = (ext_payload[0] >> 4) & 0x0F
            rqi = bool(ext_payload[1] & 0x40)
            qfi = ext_payload[1] & 0x3F
            print(f"{pfx}  \033[1;35m[Extension: TS 38.415 PDU Session Container]\033[0m")
            print(f"{pfx}    PDU Type:        {'Uplink' if pdu_type == 1 else 'Downlink'}")
            print(f"{pfx}    RQI:             {rqi}")
            print(f"{pfx}    QFI:             {qfi}")
        else:
            print(f"{pfx}  [Extension Header: Type 0x{next_ext_type:02X}, Length {total_ext_len} bytes]")

        offset += total_ext_len
        next_ext_type = next_ext

    # Inner Payload
    payload = data[offset:]
    if payload:
        print(f"{pfx}  \033[1;32m[Encapsulated PDU Payload ({len(payload)} bytes)]\033[0m")
        if len(payload) >= 20 and ((payload[0] >> 4) == 4):
            # IPv4 Dissection
            src_ip = socket.inet_ntoa(payload[12:16])
            dst_ip = socket.inet_ntoa(payload[16:20])
            proto = payload[9]
            proto_name = {6: "TCP", 17: "UDP", 1: "ICMP"}.get(proto, f"Proto-{proto}")
            print(f"{pfx}    IPv4: {src_ip} -> {dst_ip} ({proto_name})")
            if proto == 17 and len(payload) >= 28:
                sport, dport = struct.unpack("!HH", payload[20:24])
                print(f"{pfx}    UDP:  Port {sport} -> Port {dport}")
        else:
            hex_dump = binascii.hexlify(payload[:32]).decode("ascii")
            print(f"{pfx}    Data: {hex_dump}...")


def dissect_pfcp(data: bytes, indent: int = 0) -> None:
    """Dissect PFCP packet according to 3GPP TS 29.244."""
    pfx = " " * indent
    if len(data) < 8:
        print(f"{pfx}[MALFORMED] Packet too short for PFCP header ({len(data)} bytes)")
        return

    flags, msg_type, length = struct.unpack("!BBH", data[:4])
    version = (flags >> 5) & 0x07
    has_seid = bool(flags & 0x01)
    type_name = PFCP_MSG_TYPES.get(msg_type, f"Unknown ({msg_type})")

    print(f"{pfx}\033[1;36m[PFCP Header (TS 29.244)]\033[0m")
    print(f"{pfx}  Version:           {version}")
    print(f"{pfx}  SEID Flag:         {has_seid}")
    print(f"{pfx}  Message Type:      {type_name} (0x{msg_type:02X})")
    print(f"{pfx}  Length:            {length} octets")

    offset = 4
    if has_seid:
        if len(data) < 16:
            print(f"{pfx}  [MALFORMED] Truncated session header")
            return
        seid, s2, s1, s0 = struct.unpack("!QBBB", data[4:15])
        seq = (s2 << 16) | (s1 << 8) | s0
        print(f"{pfx}  SEID:              0x{seid:016X}")
        print(f"{pfx}  Sequence Number:   {seq}")
        offset = 16
    else:
        s2, s1, s0 = struct.unpack("!BBB", data[4:7])
        seq = (s2 << 16) | (s1 << 8) | s0
        print(f"{pfx}  Sequence Number:   {seq}")
        offset = 8

    # Parse Information Elements (TLVs)
    print(f"{pfx}  \033[1;33m[Information Elements]\033[0m")
    ie_end = min(len(data), 4 + length)
    dissect_pfcp_ies(data[offset:ie_end], indent + 4)


def dissect_pfcp_ies(data: bytes, indent: int) -> None:
    """Recursively parse PFCP Information Elements."""
    pfx = " " * indent
    offset = 0
    while offset + 4 <= len(data):
        ie_type, ie_len = struct.unpack("!HH", data[offset:offset + 4])
        ie_val = data[offset + 4:offset + 4 + ie_len]
        name = PFCP_IE_NAMES.get(ie_type, f"IE-{ie_type}")

        print(f"{pfx}\033[33m- {name}\033[0m (Type {ie_type}, Length {ie_len})")

        # Specific decoders
        if ie_type == 19 and len(ie_val) >= 1:
            cause_code = ie_val[0]
            cause_desc = {1: "Request Accepted", 64: "Request Rejected"}.get(cause_code, f"Code {cause_code}")
            print(f"{pfx}    Cause: {cause_desc} ({cause_code})")
        elif ie_type == 96 and len(ie_val) >= 4:
            ntp_ts = struct.unpack("!I", ie_val[:4])[0]
            print(f"{pfx}    Recovery Timestamp: {ntp_ts}")
        elif ie_type == 60 and len(ie_val) >= 5:
            node_type = ie_val[0]
            if node_type == 0:
                ip = socket.inet_ntoa(ie_val[1:5])
                print(f"{pfx}    Node IPv4: {ip}")
        elif ie_type in (1, 2, 3, 4, 6, 7):
            # Grouped IEs: parse recursively
            dissect_pfcp_ies(ie_val, indent + 4)

        offset += 4 + ie_len


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="packet_inspector",
        description="3GPP TS 29.281 GTP-U & TS 29.244 PFCP Protocol Dissector"
    )
    parser.add_argument("hex_data", nargs="?", help="Hex-encoded packet byte stream to inspect")
    parser.add_argument("--proto", choices=["gtpu", "pfcp", "auto"], default="auto", help="Protocol format")
    args = parser.parse_args()

    if not args.hex_data:
        print("Enter hex stream (or Ctrl+D to exit):")
        try:
            raw_input = sys.stdin.read().strip()
        except KeyboardInterrupt:
            return
    else:
        raw_input = args.hex_data

    cleaned_hex = "".join(raw_input.split()).replace("0x", "")
    try:
        packet_bytes = binascii.unhexlify(cleaned_hex)
    except binascii.Error as exc:
        print(f"[ERROR] Invalid hex string: {exc}", file=sys.stderr)
        sys.exit(1)

    print("=================================================================")
    print(f" TRUSS PACKET INSPECTOR DISSECTION ({len(packet_bytes)} bytes)")
    print("=================================================================")

    proto = args.proto
    if proto == "auto":
        # Heuristic detection:
        # GTP-U version is in bits 7-5 of first byte: (b >> 5) == 1
        # PFCP version is also in bits 7-5: (b >> 5) == 1
        # GTP-U standard ports: 2152, PFCP standard: 8805
        # Message type in byte 1: GTP-U 255 is GPDU, PFCP 1/2/5/50 are PFCP
        if len(packet_bytes) >= 2:
            msg_type = packet_bytes[1]
            if msg_type in PFCP_MSG_TYPES:
                proto = "pfcp"
            elif msg_type in GTPU_MSG_TYPES:
                proto = "gtpu"
            else:
                proto = "gtpu"

    if proto == "gtpu":
        dissect_gtpu(packet_bytes)
    elif proto == "pfcp":
        dissect_pfcp(packet_bytes)
    print("=================================================================")


if __name__ == "__main__":
    main()
