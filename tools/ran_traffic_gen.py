#!/usr/bin/env python3
"""
Truss 5G Radio Access Network (gNodeB) Traffic Generator
Transmits synthetic GTP-U encapsulated traffic (3GPP TS 29.281) over UDP port 2152
with 5G QoS Flow Identifier (QFI) PDU session container headers (3GPP TS 38.415).
"""

import argparse
import socket
import struct
import sys
import time
from typing import Optional


GTPU_PORT = 2152
GTPU_MSG_TYPE_GPDU = 255
EXT_TYPE_PDU_SESSION_CONTAINER = 0x85


def build_inner_ipv4_udp(
    src_ip: str,
    dst_ip: str,
    src_port: int,
    dst_port: int,
    payload: bytes
) -> bytes:
    """Construct standard inner IPv4 UDP datagram with checksums."""
    # IPv4 Header (20 bytes)
    version_ihl = (4 << 4) | 5
    tos = 0
    total_len = 20 + 8 + len(payload)
    ident = 0x1234
    flags_frag = 0x4000  # Don't fragment
    ttl = 64
    proto = 17  # UDP
    csum = 0  # Initial checksum

    s_ip = socket.inet_aton(src_ip)
    d_ip = socket.inet_aton(dst_ip)

    ip_hdr_no_csum = struct.pack(
        "!BBHHHBBH4s4s",
        version_ihl, tos, total_len, ident, flags_frag, ttl, proto, 0, s_ip, d_ip
    )

    # Compute IPv4 header checksum (RFC 1071)
    acc = 0
    for i in range(0, len(ip_hdr_no_csum), 2):
        acc += (ip_hdr_no_csum[i] << 8) + ip_hdr_no_csum[i + 1]
    while (acc >> 16) > 0:
        acc = (acc & 0xFFFF) + (acc >> 16)
    ip_csum = (~acc) & 0xFFFF

    ip_hdr = struct.pack(
        "!BBHHHBBH4s4s",
        version_ihl, tos, total_len, ident, flags_frag, ttl, proto, ip_csum, s_ip, d_ip
    )

    # UDP Header (8 bytes)
    udp_len = 8 + len(payload)
    udp_hdr = struct.pack("!HHHH", src_port, dst_port, udp_len, 0)

    return ip_hdr + udp_hdr + payload


def build_gtpu_packet(
    teid: int,
    payload: bytes,
    qfi: Optional[int] = None,
    seq_num: Optional[int] = None
) -> bytes:
    """
    Construct 3GPP TS 29.281 GTP-U encapsulated packet.
    Optionally appends TS 38.415 PDU Session Container carrying QFI.
    """
    has_ext = (qfi is not None)
    has_seq = (seq_num is not None)

    flags = 0x30  # Version 1 (0x20) | Protocol Type GTP (0x10)
    if has_ext:
        flags |= 0x04
    if has_seq:
        flags |= 0x02

    ext_bytes = bytearray()
    if has_ext:
        # TS 38.415 PDU Session Container:
        # Length in 4-octet units: 1
        # PDU Type (4-bit): 0 (DL) / 1 (UL) | Spare (4-bit)
        # Spare (1-bit) | RQI (1-bit) | QFI (6-bit)
        # Next Extension Header Type: 0 (None)
        qfi_val = qfi & 0x3F
        ext_bytes.extend(struct.pack("!BBB", 1, 0x10, qfi_val))  # Uplink = 1, QFI
        ext_bytes.append(0x00)  # No next extension header

    optional_hdr = bytearray()
    if has_ext or has_seq:
        s = seq_num if seq_num is not None else 0
        npdu = 0
        next_ext = EXT_TYPE_PDU_SESSION_CONTAINER if has_ext else 0
        optional_hdr.extend(struct.pack("!HBB", s, npdu, next_ext))

    # Length field indicates bytes following mandatory 8-byte header
    gtpu_len = len(optional_hdr) + len(ext_bytes) + len(payload)
    mandatory_hdr = struct.pack("!BBHI", flags, GTPU_MSG_TYPE_GPDU, gtpu_len, teid)

    return mandatory_hdr + bytes(optional_hdr) + bytes(ext_bytes) + payload


class RanTrafficGenerator:
    """
    High-performance GTP-U traffic generator.
    Sends bursts of GTP-U encapsulated packets to evaluate UPF forwarding performance.
    """
    def __init__(self, target_host: str = "127.0.0.1", target_port: int = GTPU_PORT):
        self.target = (target_host, target_port)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # Enlarge socket send buffer for burst transmission
        try:
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4 * 1024 * 1024)
        except OSError:
            pass

    def run_burst(
        self,
        teid: int,
        count: int = 1000,
        packet_size: int = 128,
        qfi: int = 9,
        target_pps: int = 0
    ) -> dict:
        """Execute packet burst and record performance statistics."""
        # Generate dummy inner payload
        inner_payload = b"X" * max(0, packet_size - 40)
        inner_pkt = build_inner_ipv4_udp(
            src_ip="10.60.0.1",
            dst_ip="1.1.1.1",
            src_port=12345,
            dst_port=80,
            payload=inner_payload
        )
        gtpu_pkt = build_gtpu_packet(teid=teid, payload=inner_pkt, qfi=qfi)

        total_bytes = len(gtpu_pkt) * count
        interval = (1.0 / target_pps) if target_pps > 0 else 0.0

        print(f"[RAN-GEN] Sending {count} GTP-U packets (TEID={teid}, QFI={qfi}, wire_len={len(gtpu_pkt)} bytes)...")
        t0 = time.perf_counter()

        sent = 0
        for i in range(count):
            self.sock.sendto(gtpu_pkt, self.target)
            sent += 1
            if interval > 0:
                time.sleep(interval)

        duration = time.perf_counter() - t0
        actual_pps = sent / duration if duration > 0 else 0.0
        mbps = (total_bytes * 8) / (duration * 1_000_000) if duration > 0 else 0.0

        return {
            "packets_sent": sent,
            "total_bytes": total_bytes,
            "duration_sec": duration,
            "actual_pps": actual_pps,
            "throughput_mbps": mbps,
            "packet_size": len(gtpu_pkt)
        }


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="ran_traffic_gen",
        description="3GPP TS 29.281 GTP-U Radio Access Network Traffic Generator"
    )
    parser.add_argument("--host", default="127.0.0.1", help="Target UPF N3/RAN IP (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=GTPU_PORT, help="Target UPF GTP-U UDP port (default: 2152)")
    parser.add_argument("--teid", type=int, default=5001, help="GTP-U Tunnel Endpoint Identifier (default: 5001)")
    parser.add_argument("--qfi", type=int, default=9, help="QoS Flow Identifier 1-63 (default: 9)")
    parser.add_argument("--count", type=int, default=5000, help="Number of packets to send (default: 5000)")
    parser.add_argument("--size", type=int, default=256, help="Inner packet size in bytes (default: 256)")
    parser.add_argument("--rate", type=int, default=0, help="Target rate in packets per second (0 for max line rate)")

    args = parser.parse_args()
    gen = RanTrafficGenerator(args.host, args.port)
    stats = gen.run_burst(
        teid=args.teid,
        count=args.count,
        packet_size=args.size,
        qfi=args.qfi,
        target_pps=args.rate
    )

    print("=================================================================")
    print("                RAN TRAFFIC GENERATOR BURST REPORT               ")
    print("=================================================================")
    print(f"Packets Sent:     {stats['packets_sent']}")
    print(f"Total Bytes:      {stats['total_bytes']:,} bytes")
    print(f"Elapsed Time:     {stats['duration_sec']:.4f} seconds")
    print(f"Achieved Rate:    {stats['actual_pps']:,.1f} packets/sec")
    print(f"Throughput:       {stats['throughput_mbps']:.2f} Mbps")
    print(f"Wire Packet Size: {stats['packet_size']} bytes")
    print("=================================================================")


if __name__ == "__main__":
    main()
