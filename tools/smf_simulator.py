#!/usr/bin/env python3
"""
Truss 5G Session Management Function (SMF) Simulator
Emulates 3GPP TS 29.244 PFCP control plane procedures over UDP port 8805.
Supports Association Setup, Heartbeats, and Session Establishment with
PDR, FAR, QER, and URR policy rules.
"""

import argparse
import socket
import struct
import sys
import time
from typing import Optional, Tuple


# PFCP Message Types (TS 29.244 Table 6.1-1)
PFCP_HEARTBEAT_REQUEST = 1
PFCP_HEARTBEAT_RESPONSE = 2
PFCP_ASSOCIATION_SETUP_REQUEST = 5
PFCP_ASSOCIATION_SETUP_RESPONSE = 6
PFCP_SESSION_ESTABLISHMENT_REQUEST = 50
PFCP_SESSION_ESTABLISHMENT_RESPONSE = 51
PFCP_SESSION_MODIFICATION_REQUEST = 52
PFCP_SESSION_MODIFICATION_RESPONSE = 53
PFCP_SESSION_DELETION_REQUEST = 54
PFCP_SESSION_DELETION_RESPONSE = 55

# PFCP Information Element Types (TS 29.244 Table 8.1.1-1)
IE_CREATE_PDR = 1
IE_PDI = 2
IE_CREATE_FAR = 3
IE_FORWARDING_PARAMETERS = 4
IE_CREATE_URR = 6
IE_CREATE_QER = 7
IE_CAUSE = 19
IE_SOURCE_INTERFACE = 20
IE_F_TEID = 21
IE_GATE_STATUS = 25
IE_MBR = 26
IE_GBR = 27
IE_APPLY_ACTION = 44
IE_DESTINATION_INTERFACE = 42
IE_F_SEID = 57
IE_NODE_ID = 60
IE_VOLUME_THRESHOLD = 64
IE_OUTER_HEADER_CREATION = 84
IE_QFI = 89
IE_RECOVERY_TIME_STAMP = 96


def encode_pfcp_header(
    msg_type: int,
    seq: int,
    payload: bytes,
    seid: Optional[int] = None
) -> bytes:
    """
    Encode 3GPP TS 29.244 binary PFCP header.
    Node messages: 8 bytes (S=0).
    Session messages: 16 bytes (S=1, 8-byte SEID).
    """
    version = 1
    has_seid = (seid is not None)
    flags = (version & 0x07) << 5
    if has_seid:
        flags |= 0x01

    length = len(payload)
    if has_seid:
        length += 12  # SEID (8) + Seq (3) + Spare (1)
    else:
        length += 4   # Seq (3) + Spare (1)

    s2 = (seq >> 16) & 0xFF
    s1 = (seq >> 8) & 0xFF
    s0 = seq & 0xFF

    if has_seid:
        return struct.pack("!BBHQBBBx", flags, msg_type, length, seid, s2, s1, s0) + payload
    else:
        return struct.pack("!BBHBBBx", flags, msg_type, length, s2, s1, s0) + payload


def decode_pfcp_header(data: bytes) -> Tuple[int, int, int, Optional[int], bytes]:
    """
    Decode 3GPP TS 29.244 binary PFCP header.
    Returns (msg_type, length, seq, seid, payload).
    """
    if len(data) < 8:
        raise ValueError(f"Packet too short for PFCP header: {len(data)} bytes")

    flags, msg_type, length = struct.unpack("!BBH", data[:4])
    version = (flags >> 5) & 0x07
    has_seid = bool(flags & 0x01)

    if version != 1:
        raise ValueError(f"Unsupported PFCP version: {version}")

    if has_seid:
        if len(data) < 16:
            raise ValueError(f"Packet too short for session PFCP header: {len(data)} bytes")
        seid, s2, s1, s0 = struct.unpack("!QBBB", data[4:15])
        seq = (s2 << 16) | (s1 << 8) | s0
        payload = data[16:4 + length]
        return msg_type, length, seq, seid, payload
    else:
        s2, s1, s0 = struct.unpack("!BBB", data[4:7])
        seq = (s2 << 16) | (s1 << 8) | s0
        payload = data[8:4 + length]
        return msg_type, length, seq, None, payload


def encode_tlv(ie_type: int, value: bytes) -> bytes:
    """Encode standard PFCP TLV Information Element."""
    return struct.pack("!HH", ie_type, len(value)) + value


def encode_node_id_ipv4(ip_str: str) -> bytes:
    """Encode Node ID IE containing IPv4 address."""
    packed_ip = socket.inet_aton(ip_str)
    return encode_tlv(IE_NODE_ID, b"\x00" + packed_ip)


def encode_recovery_time_stamp(ntp_sec: int) -> bytes:
    """Encode Recovery Time Stamp IE."""
    return encode_tlv(IE_RECOVERY_TIME_STAMP, struct.pack("!I", ntp_sec))


def encode_f_seid(seid: int, ip_str: str) -> bytes:
    """Encode Fully Qualified SEID (F-SEID) IE (IPv4 flag = 0x02)."""
    packed_ip = socket.inet_aton(ip_str)
    return encode_tlv(IE_F_SEID, struct.pack("!BQI", 0x02, seid, struct.unpack("!I", packed_ip)[0]))


def encode_create_pdr(
    pdr_id: int,
    precedence: int,
    src_interface: int,
    teid: Optional[int] = None,
    ue_ip_str: Optional[str] = None,
    far_id: int = 1,
    qer_id: Optional[int] = None,
    urr_id: Optional[int] = None
) -> bytes:
    """
    Encode Grouped Create PDR Information Element.
    Contains PDR ID, Precedence, PDI, FAR ID, and optional QER/URR IDs.
    """
    # Build inner PDI
    pdi_ies = bytearray()
    pdi_ies.extend(encode_tlv(IE_SOURCE_INTERFACE, struct.pack("!B", src_interface)))

    if teid is not None:
        # F-TEID (V4 flag = 0x01)
        dummy_ip = socket.inet_aton("127.0.0.1")
        f_teid_val = struct.pack("!BII", 0x01, teid, struct.unpack("!I", dummy_ip)[0])
        pdi_ies.extend(encode_tlv(IE_F_TEID, f_teid_val))

    pdr_ies = bytearray()
    pdr_ies.extend(encode_tlv(1, struct.pack("!H", pdr_id)))  # PDR ID (Type 56/1)
    pdr_ies.extend(encode_tlv(29, struct.pack("!I", precedence)))  # Precedence
    pdr_ies.extend(encode_tlv(IE_PDI, bytes(pdi_ies)))
    pdr_ies.extend(encode_tlv(108, struct.pack("!I", far_id)))  # FAR ID

    if qer_id is not None:
        pdr_ies.extend(encode_tlv(109, struct.pack("!I", qer_id)))  # QER ID
    if urr_id is not None:
        pdr_ies.extend(encode_tlv(110, struct.pack("!I", urr_id)))  # URR ID

    return encode_tlv(IE_CREATE_PDR, bytes(pdr_ies))


def encode_create_far(far_id: int, apply_action: int = 0x02) -> bytes:
    """
    Encode Grouped Create FAR Information Element.
    Apply action 0x02 = FORW (Forward).
    """
    far_ies = bytearray()
    far_ies.extend(encode_tlv(108, struct.pack("!I", far_id)))  # FAR ID
    far_ies.extend(encode_tlv(IE_APPLY_ACTION, struct.pack("!B", apply_action)))
    return encode_tlv(IE_CREATE_FAR, bytes(far_ies))


class SmfClient:
    """
    Lightweight SMF client socket manager.
    Sends PFCP control messages and awaits responses with retry handling.
    """
    def __init__(self, target_host: str = "127.0.0.1", target_port: int = 8805, timeout: float = 2.0):
        self.target = (target_host, target_port)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.settimeout(timeout)
        self.seq = 1

    def _next_seq(self) -> int:
        s = self.seq
        self.seq = (self.seq + 1) & 0x00FFFFFF
        return s

    def send_and_receive(self, payload: bytes) -> bytes:
        """Send raw PFCP datagram and receive reply."""
        self.sock.sendto(payload, self.target)
        resp, addr = self.sock.recvfrom(4096)
        return resp

    def heartbeat(self) -> Tuple[int, int]:
        """Execute PFCP Heartbeat transaction."""
        seq = self._next_seq()
        ts = int(time.time())
        ies = encode_recovery_time_stamp(ts)
        pkt = encode_pfcp_header(PFCP_HEARTBEAT_REQUEST, seq, ies)

        t0 = time.perf_counter()
        resp = self.send_and_receive(pkt)
        latency_us = int((time.perf_counter() - t0) * 1_000_000)

        msg_type, length, r_seq, seid, payload = decode_pfcp_header(resp)
        if msg_type != PFCP_HEARTBEAT_RESPONSE:
            raise RuntimeError(f"Unexpected response message type: {msg_type}")
        if r_seq != seq:
            raise RuntimeError(f"Sequence mismatch: expected {seq}, got {r_seq}")

        return r_seq, latency_us

    def association_setup(self, smf_ip: str = "127.0.0.1") -> Tuple[int, int]:
        """Execute PFCP Association Setup transaction."""
        seq = self._next_seq()
        ts = int(time.time())
        ies = encode_node_id_ipv4(smf_ip) + encode_recovery_time_stamp(ts)
        pkt = encode_pfcp_header(PFCP_ASSOCIATION_SETUP_REQUEST, seq, ies)

        t0 = time.perf_counter()
        resp = self.send_and_receive(pkt)
        latency_us = int((time.perf_counter() - t0) * 1_000_000)

        msg_type, length, r_seq, seid, payload = decode_pfcp_header(resp)
        if msg_type != PFCP_ASSOCIATION_SETUP_RESPONSE:
            raise RuntimeError(f"Unexpected response message type: {msg_type}")
        return r_seq, latency_us

    def establish_session(
        self,
        local_seid: int,
        cp_seid: int,
        teid: int,
        smf_ip: str = "127.0.0.1"
    ) -> Tuple[int, int]:
        """Execute PFCP Session Establishment transaction."""
        seq = self._next_seq()
        ies = bytearray()
        ies.extend(encode_node_id_ipv4(smf_ip))
        ies.extend(encode_f_seid(cp_seid, smf_ip))

        # Create Uplink PDR (Access interface, TEID)
        ies.extend(encode_create_pdr(
            pdr_id=1,
            precedence=10,
            src_interface=0,  # Access
            teid=teid,
            far_id=1
        ))

        # Create Uplink FAR (Forward)
        ies.extend(encode_create_far(far_id=1, apply_action=0x02))

        # Encode Session-related header (SEID = 0 on establishment request)
        pkt = encode_pfcp_header(PFCP_SESSION_ESTABLISHMENT_REQUEST, seq, bytes(ies), seid=0)

        t0 = time.perf_counter()
        resp = self.send_and_receive(pkt)
        latency_us = int((time.perf_counter() - t0) * 1_000_000)

        msg_type, length, r_seq, upf_seid, payload = decode_pfcp_header(resp)
        if msg_type != PFCP_SESSION_ESTABLISHMENT_RESPONSE:
            raise RuntimeError(f"Unexpected response message type: {msg_type}")

        return r_seq, latency_us

    def delete_session(self, upf_seid: int) -> Tuple[int, int]:
        """Execute PFCP Session Deletion transaction."""
        seq = self._next_seq()
        pkt = encode_pfcp_header(PFCP_SESSION_DELETION_REQUEST, seq, b"", seid=upf_seid)

        t0 = time.perf_counter()
        resp = self.send_and_receive(pkt)
        latency_us = int((time.perf_counter() - t0) * 1_000_000)

        msg_type, length, r_seq, seid, payload = decode_pfcp_header(resp)
        if msg_type != PFCP_SESSION_DELETION_RESPONSE:
            raise RuntimeError(f"Unexpected response message type: {msg_type}")

        return r_seq, latency_us


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="smf_simulator",
        description="3GPP TS 29.244 PFCP Session Management Function Simulator"
    )
    parser.add_argument("--host", default="127.0.0.1", help="Target UPF PFCP IP (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8805, help="Target UPF PFCP UDP port (default: 8805)")
    parser.add_argument(
        "action",
        choices=["heartbeat", "associate", "session-lifecycle", "benchmark"],
        help="PFCP control procedure to execute"
    )
    parser.add_argument("--sessions", type=int, default=100, help="Number of iterations for benchmark")

    args = parser.parse_args()
    client = SmfClient(args.host, args.port)

    print(f"[SMF] Initialized PFCP client targeting {args.host}:{args.port}")

    if args.action == "heartbeat":
        seq, lat = client.heartbeat()
        print(f"[SMF] Heartbeat transaction successful: seq={seq}, latency={lat} us")

    elif args.action == "associate":
        seq, lat = client.association_setup()
        print(f"[SMF] Association Setup successful: seq={seq}, latency={lat} us")

    elif args.action == "session-lifecycle":
        print("[SMF] 1. Associating with UPF...")
        client.association_setup()
        print("[SMF] 2. Establishing PDU Session (CP SEID=0x1000, TEID=5001)...")
        seq, lat = client.establish_session(local_seid=0x1000, cp_seid=0x1000, teid=5001)
        print(f"[SMF] Session established: seq={seq}, latency={lat} us")
        time.sleep(0.5)
        print("[SMF] 3. Deleting PDU Session...")
        d_seq, d_lat = client.delete_session(upf_seid=0x1000)
        print(f"[SMF] Session deleted: seq={d_seq}, latency={d_lat} us")

    elif args.action == "benchmark":
        print(f"[SMF] Benchmarking {args.sessions} consecutive session establishments...")
        client.association_setup()
        latencies = []
        t_start = time.perf_counter()

        for i in range(args.sessions):
            teid = 10000 + i
            seid = 0x20000 + i
            seq, lat = client.establish_session(local_seid=seid, cp_seid=seid, teid=teid)
            latencies.append(lat)

        total_time = time.perf_counter() - t_start
        latencies.sort()
        p50 = latencies[len(latencies) // 2]
        p99 = latencies[int(len(latencies) * 0.99)]
        ops = args.sessions / total_time

        print(f"[SMF] Benchmark complete: {args.sessions} sessions in {total_time:.3f}s ({ops:.1f} sessions/sec)")
        print(f"      Latency: p50={p50} us, p99={p99} us, min={latencies[0]} us, max={latencies[-1]} us")


if __name__ == "__main__":
    main()
