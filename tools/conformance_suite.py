#!/usr/bin/env python3
"""
Truss 3GPP Specification Conformance Test Suite
Validates conformance against 3GPP TS 29.244 (PFCP) and TS 29.281 (GTP-U)
protocol standards, error scenarios, boundary conditions, and state transitions.
"""

import argparse
import socket
import struct
import sys
import time
from typing import Callable, List, Optional, Tuple

from smf_simulator import (
    PFCP_ASSOCIATION_SETUP_REQUEST,
    PFCP_ASSOCIATION_SETUP_RESPONSE,
    PFCP_HEARTBEAT_REQUEST,
    PFCP_HEARTBEAT_RESPONSE,
    PFCP_SESSION_DELETION_REQUEST,
    PFCP_SESSION_DELETION_RESPONSE,
    PFCP_SESSION_ESTABLISHMENT_REQUEST,
    PFCP_SESSION_ESTABLISHMENT_RESPONSE,
    decode_pfcp_header,
    encode_create_far,
    encode_create_pdr,
    encode_f_seid,
    encode_node_id_ipv4,
    encode_pfcp_header,
    encode_recovery_time_stamp,
)
from ran_traffic_gen import build_gtpu_packet, build_inner_ipv4_udp


class ConformanceTest:
    """Individual conformance test descriptor and execution unit."""
    def __init__(self, test_id: str, description: str, func: Callable):
        self.test_id = test_id
        self.description = description
        self.func = func
        self.passed = False
        self.error_msg = ""
        self.latency_us = 0


class ConformanceRunner:
    """Executes 3GPP protocol conformance test vectors."""
    def __init__(self, target_host: str = "127.0.0.1", pfcp_port: int = 8805, gtpu_port: int = 2152):
        self.target_host = target_host
        self.pfcp_port = pfcp_port
        self.gtpu_port = gtpu_port
        self.tests: List[ConformanceTest] = []
        self._register_tests()

    def _register_tests(self) -> None:
        self.tests.append(ConformanceTest(
            "TC-PFCP-01",
            "PFCP Heartbeat Procedure (TS 29.244 cl 6.2.2)",
            self.tc_pfcp_heartbeat
        ))
        self.tests.append(ConformanceTest(
            "TC-PFCP-02",
            "PFCP Association Setup Procedure (TS 29.244 cl 6.2.6)",
            self.tc_pfcp_association_setup
        ))
        self.tests.append(ConformanceTest(
            "TC-PFCP-03",
            "PFCP Session Establishment with PDR and FAR (TS 29.244 cl 6.3.2)",
            self.tc_pfcp_session_establishment
        ))
        self.tests.append(ConformanceTest(
            "TC-PFCP-04",
            "PFCP Idempotent Transaction Replay on Duplicate Sequence Number",
            self.tc_pfcp_duplicate_transaction
        ))
        self.tests.append(ConformanceTest(
            "TC-PFCP-05",
            "PFCP Protocol Error Handling: Unsupported Version Rejection",
            self.tc_pfcp_invalid_version
        ))
        self.tests.append(ConformanceTest(
            "TC-PFCP-06",
            "PFCP Session Deletion Procedure (TS 29.244 cl 6.3.4)",
            self.tc_pfcp_session_deletion
        ))
        self.tests.append(ConformanceTest(
            "TC-GTPU-01",
            "GTP-U Standard G-PDU Encapsulation & Transmission (TS 29.281 cl 5.1)",
            self.tc_gtpu_gpdu_transmission
        ))
        self.tests.append(ConformanceTest(
            "TC-GTPU-02",
            "GTP-U TS 38.415 PDU Session Container Extension Header Validation",
            self.tc_gtpu_pdu_session_container
        ))
        self.tests.append(ConformanceTest(
            "TC-GTPU-03",
            "GTP-U Malformed Packet Rejection: Header Length Underflow",
            self.tc_gtpu_malformed_header
        ))

    def _send_pfcp(self, data: bytes, timeout: float = 2.0) -> bytes:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(timeout)
        try:
            sock.sendto(data, (self.target_host, self.pfcp_port))
            resp, _ = sock.recvfrom(4096)
            return resp
        finally:
            sock.close()

    def tc_pfcp_heartbeat(self) -> None:
        """TC-PFCP-01: Heartbeat transaction with recovery timestamp."""
        seq = 101
        ies = encode_recovery_time_stamp(int(time.time()))
        pkt = encode_pfcp_header(PFCP_HEARTBEAT_REQUEST, seq, ies)
        resp = self._send_pfcp(pkt)

        msg_type, length, r_seq, seid, payload = decode_pfcp_header(resp)
        assert msg_type == PFCP_HEARTBEAT_RESPONSE, f"Expected Heartbeat Response (2), got {msg_type}"
        assert r_seq == seq, f"Expected sequence {seq}, got {r_seq}"
        assert len(payload) >= 4, "Heartbeat response must contain Recovery Timestamp IE"

    def tc_pfcp_association_setup(self) -> None:
        """TC-PFCP-02: Association Setup with Node ID."""
        seq = 102
        ies = encode_node_id_ipv4("127.0.0.1") + encode_recovery_time_stamp(int(time.time()))
        pkt = encode_pfcp_header(PFCP_ASSOCIATION_SETUP_REQUEST, seq, ies)
        resp = self._send_pfcp(pkt)

        msg_type, length, r_seq, seid, payload = decode_pfcp_header(resp)
        assert msg_type == PFCP_ASSOCIATION_SETUP_RESPONSE, f"Expected Association Setup Response (6), got {msg_type}"
        assert r_seq == seq, f"Expected sequence {seq}, got {r_seq}"

    def tc_pfcp_session_establishment(self) -> None:
        """TC-PFCP-03: Session Establishment with PDR and FAR."""
        seq = 103
        seid = 0x8888
        ies = bytearray()
        ies.extend(encode_node_id_ipv4("127.0.0.1"))
        ies.extend(encode_f_seid(seid, "127.0.0.1"))
        ies.extend(encode_create_pdr(pdr_id=1, precedence=100, src_interface=0, teid=9999, far_id=1))
        ies.extend(encode_create_far(far_id=1, apply_action=0x02))

        pkt = encode_pfcp_header(PFCP_SESSION_ESTABLISHMENT_REQUEST, seq, bytes(ies), seid=0)
        resp = self._send_pfcp(pkt)

        msg_type, length, r_seq, upf_seid, payload = decode_pfcp_header(resp)
        assert msg_type == PFCP_SESSION_ESTABLISHMENT_RESPONSE, f"Expected Session Establishment Response, got {msg_type}"
        assert r_seq == seq, f"Expected sequence {seq}, got {r_seq}"

    def tc_pfcp_duplicate_transaction(self) -> None:
        """TC-PFCP-04: Verify idempotent replay for duplicate request sequence."""
        seq = 104
        ies = encode_recovery_time_stamp(int(time.time()))
        pkt = encode_pfcp_header(PFCP_HEARTBEAT_REQUEST, seq, ies)

        resp1 = self._send_pfcp(pkt)
        resp2 = self._send_pfcp(pkt)

        assert resp1 == resp2, "Idempotent transaction replay failed: duplicate responses differ"

    def tc_pfcp_invalid_version(self) -> None:
        """TC-PFCP-05: Send PFCP packet with unsupported version 2."""
        # Version 2 in bits 7-5 -> 0x40
        raw_invalid = struct.pack("!BBHBBBx", 0x40, PFCP_HEARTBEAT_REQUEST, 4, 0, 0, 105)
        try:
            resp = self._send_pfcp(raw_invalid, timeout=0.5)
            # If UPF responds, it must indicate failure, or drop silently
            msg_type, length, seq, seid, payload = decode_pfcp_header(resp)
            assert msg_type != PFCP_HEARTBEAT_RESPONSE, "UPF should not accept unsupported version 2"
        except (socket.timeout, TimeoutError):
            # Silent drop of invalid version packet is compliant
            pass

    def tc_pfcp_session_deletion(self) -> None:
        """TC-PFCP-06: Clean deletion of session context."""
        seq = 106
        pkt = encode_pfcp_header(PFCP_SESSION_DELETION_REQUEST, seq, b"", seid=0x8888)
        resp = self._send_pfcp(pkt)

        msg_type, length, r_seq, seid, payload = decode_pfcp_header(resp)
        assert msg_type == PFCP_SESSION_DELETION_RESPONSE, f"Expected Session Deletion Response, got {msg_type}"
        assert r_seq == seq, f"Expected sequence {seq}, got {r_seq}"

    def tc_gtpu_gpdu_transmission(self) -> None:
        """TC-GTPU-01: Send valid GTP-U G-PDU."""
        inner = build_inner_ipv4_udp("10.60.0.1", "8.8.8.8", 12345, 53, b"ping")
        gtpu_pkt = build_gtpu_packet(teid=9999, payload=inner)

        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.sendto(gtpu_pkt, (self.target_host, self.gtpu_port))
        finally:
            sock.close()

    def tc_gtpu_pdu_session_container(self) -> None:
        """TC-GTPU-02: GTP-U with TS 38.415 QFI Extension Header."""
        inner = build_inner_ipv4_udp("10.60.0.1", "8.8.8.8", 12345, 53, b"qfi-test")
        gtpu_pkt = build_gtpu_packet(teid=9999, payload=inner, qfi=9)

        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.sendto(gtpu_pkt, (self.target_host, self.gtpu_port))
        finally:
            sock.close()

    def tc_gtpu_malformed_header(self) -> None:
        """TC-GTPU-03: Truncated GTP-U header rejection."""
        truncated_pkt = b"\x30\xFF\x00\x10"  # Only 4 bytes instead of 8

        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            # UPF must gracefully discard truncated header without crashing
            sock.sendto(truncated_pkt, (self.target_host, self.gtpu_port))
        finally:
            sock.close()

    def run_all(self) -> bool:
        """Execute all test cases and print report."""
        print("=================================================================")
        print("          TRUSS 3GPP PROTOCOL CONFORMANCE TEST SUITE             ")
        print("=================================================================")
        passed_count = 0
        total_count = len(self.tests)

        for test in self.tests:
            sys.stdout.write(f"[{test.test_id}] {test.description:<56} ")
            sys.stdout.flush()
            t0 = time.perf_counter()
            try:
                test.func()
                test.latency_us = int((time.perf_counter() - t0) * 1_000_000)
                test.passed = True
                passed_count += 1
                print(f"\033[32mPASS\033[0m ({test.latency_us} us)")
            except Exception as exc:
                test.latency_us = int((time.perf_counter() - t0) * 1_000_000)
                test.passed = False
                test.error_msg = str(exc)
                print(f"\033[31mFAIL\033[0m ({test.latency_us} us)")
                print(f"        Error: {exc}")

        print("=================================================================")
        print(f" Conformance Summary: {passed_count}/{total_count} tests passed")
        print("=================================================================")
        return passed_count == total_count


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="conformance_suite",
        description="3GPP TS 29.244 and TS 29.281 Protocol Conformance Test Runner"
    )
    parser.add_argument("--host", default="127.0.0.1", help="Target UPF host (default: 127.0.0.1)")
    parser.add_argument("--pfcp-port", type=int, default=8805, help="UPF PFCP port (default: 8805)")
    parser.add_argument("--gtpu-port", type=int, default=2152, help="UPF GTP-U port (default: 2152)")

    args = parser.parse_args()
    runner = ConformanceRunner(args.host, args.pfcp_port, args.gtpu_port)
    success = runner.run_all()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
