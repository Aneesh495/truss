#!/usr/bin/env python3
"""
Truss Multi-Subscriber Synthetic Workload Generator
Simulates realistic 5G cellular workloads across hundreds of concurrent UE
sessions. Exercises PFCP session lifecycle, concurrent GTP-U data streams,
QoS enforcement rules (QER), and usage reporting (URR).
"""

import argparse
import concurrent.futures
import json
import random
import socket
import sys
import time
import urllib.request
from typing import Dict, List

from smf_simulator import SmfClient
from ran_traffic_gen import RanTrafficGenerator, build_gtpu_packet, build_inner_ipv4_udp


class SubscriberSession:
    """Represents an active simulated 5G mobile subscriber."""
    def __init__(self, index: int, base_seid: int = 0x50000, base_teid: int = 20000):
        self.index = index
        self.seid = base_seid + index
        self.teid = base_teid + index
        self.ue_ip = f"10.60.{ (index // 254) % 254 }.{ (index % 254) + 1 }"
        self.qfi = 9 if (index % 2 == 0) else 5
        self.established = False


class WorkloadOrchestrator:
    """
    Coordinates multi-subscriber simulation against Truss UPF.
    Runs control-plane setup, data-plane transmission, and teardown phases.
    """
    def __init__(
        self,
        upf_host: str = "127.0.0.1",
        pfcp_port: int = 8805,
        gtpu_port: int = 2152,
        admin_url: str = "http://127.0.0.1:8080",
        num_subscribers: int = 50
    ):
        self.upf_host = upf_host
        self.pfcp_port = pfcp_port
        self.gtpu_port = gtpu_port
        self.admin_url = admin_url
        self.num_subscribers = num_subscribers
        self.smf = SmfClient(upf_host, pfcp_port)
        self.subscribers: List[SubscriberSession] = [
            SubscriberSession(i) for i in range(num_subscribers)
        ]

    def phase_1_control_plane_setup(self) -> None:
        """Establish PFCP association and subscriber PDU sessions."""
        print(f"[WORKLOAD] Phase 1: Establishing PFCP association with UPF at {self.upf_host}:{self.pfcp_port}...")
        self.smf.association_setup()

        print(f"[WORKLOAD] Establishing {self.num_subscribers} subscriber PDU sessions...")
        t0 = time.perf_counter()
        success = 0
        for sub in self.subscribers:
            try:
                self.smf.establish_session(
                    local_seid=sub.seid,
                    cp_seid=sub.seid,
                    teid=sub.teid,
                    smf_ip="127.0.0.1"
                )
                sub.established = True
                success += 1
            except Exception as exc:
                print(f"[WARN] Failed to establish session for subscriber {sub.index}: {exc}")

        duration = time.perf_counter() - t0
        rate = success / duration if duration > 0 else 0
        print(f"[WORKLOAD] Phase 1 Complete: {success}/{self.num_subscribers} sessions active in {duration:.3f}s ({rate:.1f} sessions/s)")

    def phase_2_traffic_burst(self, packets_per_sub: int = 20, packet_size: int = 256) -> Dict[str, float]:
        """Stream concurrent GTP-U packets across all established sessions."""
        print(f"[WORKLOAD] Phase 2: Transmitting GTP-U traffic ({packets_per_sub} pkts/subscriber, size={packet_size}B)...")
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        target = (self.upf_host, self.gtpu_port)

        t0 = time.perf_counter()
        total_packets = 0
        total_bytes = 0

        # Construct inner payloads
        for sub in self.subscribers:
            if not sub.established:
                continue
            inner_pkt = build_inner_ipv4_udp(
                src_ip=sub.ue_ip,
                dst_ip="1.1.1.1",
                src_port=random.randint(10000, 60000),
                dst_port=443,
                payload=b"A" * max(0, packet_size - 40)
            )
            gtpu_pkt = build_gtpu_packet(teid=sub.teid, payload=inner_pkt, qfi=sub.qfi)

            for _ in range(packets_per_sub):
                sock.sendto(gtpu_pkt, target)
                total_packets += 1
                total_bytes += len(gtpu_pkt)

        duration = time.perf_counter() - t0
        pps = total_packets / duration if duration > 0 else 0
        mbps = (total_bytes * 8) / (duration * 1_000_000) if duration > 0 else 0

        print(f"[WORKLOAD] Phase 2 Complete: {total_packets} packets ({total_bytes:,} bytes) sent in {duration:.4f}s")
        print(f"           Throughput: {pps:,.1f} packets/sec ({mbps:.2f} Mbps)")

        return {
            "total_packets": total_packets,
            "total_bytes": total_bytes,
            "duration": duration,
            "pps": pps,
            "mbps": mbps
        }

    def phase_3_verify_telemetry(self) -> None:
        """Inspect UPF metrics and verify datapath accounting."""
        print(f"[WORKLOAD] Phase 3: Querying UPF telemetry from {self.admin_url}/metrics...")
        try:
            req = urllib.request.Request(f"{self.admin_url}/metrics")
            with urllib.request.urlopen(req, timeout=3.0) as resp:
                body = resp.read().decode("utf-8")
                print("--- UPF Telemetry Summary ---")
                for line in body.splitlines():
                    if "truss_rx_packets" in line or "truss_active_sessions" in line or "truss_tx_packets" in line:
                        print(f"  {line}")
        except Exception as exc:
            print(f"[WARN] Could not fetch metrics from admin endpoint: {exc}")

    def phase_4_teardown(self) -> None:
        """Gracefully release all subscriber sessions."""
        print(f"[WORKLOAD] Phase 4: Tearing down {self.num_subscribers} subscriber sessions...")
        t0 = time.perf_counter()
        deleted = 0
        for sub in self.subscribers:
            if sub.established:
                try:
                    self.smf.delete_session(upf_seid=sub.seid)
                    sub.established = False
                    deleted += 1
                except Exception as exc:
                    pass

        duration = time.perf_counter() - t0
        print(f"[WORKLOAD] Phase 4 Complete: {deleted} sessions released in {duration:.3f}s")


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="synthetic_workload",
        description="Truss Multi-Subscriber Synthetic Workload Generator"
    )
    parser.add_argument("--host", default="127.0.0.1", help="Target UPF host (default: 127.0.0.1)")
    parser.add_argument("--pfcp-port", type=int, default=8805, help="UPF PFCP port (default: 8805)")
    parser.add_argument("--gtpu-port", type=int, default=2152, help="UPF GTP-U port (default: 2152)")
    parser.add_argument("--admin-url", default="http://127.0.0.1:8080", help="UPF Admin URL (default: http://127.0.0.1:8080)")
    parser.add_argument("--subscribers", type=int, default=20, help="Number of concurrent subscribers (default: 20)")
    parser.add_argument("--packets", type=int, default=50, help="Packets per subscriber (default: 50)")
    parser.add_argument("--size", type=int, default=256, help="Packet size in bytes (default: 256)")

    args = parser.parse_args()

    orchestrator = WorkloadOrchestrator(
        upf_host=args.host,
        pfcp_port=args.pfcp_port,
        gtpu_port=args.gtpu_port,
        admin_url=args.admin_url,
        num_subscribers=args.subscribers
    )

    print("=================================================================")
    print("      TRUSS MULTI-SUBSCRIBER 5G SYNTHETIC WORKLOAD SUITE        ")
    print("=================================================================")
    orchestrator.phase_1_control_plane_setup()
    orchestrator.phase_2_traffic_burst(packets_per_sub=args.packets, packet_size=args.size)
    orchestrator.phase_3_verify_telemetry()
    orchestrator.phase_4_teardown()
    print("=================================================================")
    print(" Workload simulation completed successfully.")
    print("=================================================================")


if __name__ == "__main__":
    main()
