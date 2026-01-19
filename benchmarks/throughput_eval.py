#!/usr/bin/env python3
"""
Truss Datapath Throughput and Scaling Evaluator
Measures packet-per-second (PPS) and megabit-per-second (Mbps) forwarding
performance across varying packet frame sizes and multi-session concurrency.
"""

import argparse
import os
import sys
import time
from typing import Dict, List

# Add tools directory to module search path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from ran_traffic_gen import RanTrafficGenerator


PACKET_SIZES = [64, 128, 256, 512, 1024, 1400]


class ThroughputEvaluator:
    """Evaluates UPF packet forwarding throughput under varying packet frame sizes."""
    def __init__(self, host: str = "127.0.0.1", port: int = 2152):
        self.host = host
        self.port = port
        self.gen = RanTrafficGenerator(host, port)

    def evaluate_frame_sizes(self, count_per_size: int = 5000, teid: int = 5001) -> List[Dict]:
        """Benchmark throughput across standard MTU sizes."""
        results = []
        for size in PACKET_SIZES:
            print(f"[THROUGHPUT] Evaluating frame size {size:4d} bytes ({count_per_size} packets)...")
            stats = self.gen.run_burst(
                teid=teid,
                count=count_per_size,
                packet_size=size,
                qfi=9,
                target_pps=0  # Line rate
            )
            results.append({
                "size_bytes": size,
                "wire_size": stats["packet_size"],
                "packets_sent": stats["packets_sent"],
                "total_bytes": stats["total_bytes"],
                "duration_sec": stats["duration_sec"],
                "pps": stats["actual_pps"],
                "mbps": stats["throughput_mbps"]
            })
            time.sleep(0.2)
        return results


def print_scaling_table(results: List[Dict]) -> None:
    """Display tabular breakdown of frame size throughput."""
    print("=================================================================")
    print("      TRUSS 5G UPF DATAPATH FRAME SIZE THROUGHPUT BENCHMARK      ")
    print("=================================================================")
    header = "{:<12} {:<12} {:<14} {:<16} {:<12}"
    print(header.format("FRAME SIZE", "WIRE SIZE", "PACKETS SENT", "RATE (PPS)", "THROUGHPUT"))
    print("-" * 68)
    for r in results:
        print(header.format(
            f"{r['size_bytes']} B",
            f"{r['wire_size']} B",
            f"{r['packets_sent']:,}",
            f"{r['pps']:,.0f} pps",
            f"{r['mbps']:,.2f} Mbps"
        ))
    print("=================================================================")


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="throughput_eval",
        description="Truss Datapath Throughput and Scaling Evaluator"
    )
    parser.add_argument("--host", default="127.0.0.1", help="Target UPF host (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=2152, help="UPF GTP-U UDP port (default: 2152)")
    parser.add_argument("--teid", type=int, default=5001, help="GTP-U TEID (default: 5001)")
    parser.add_argument("--count", type=int, default=3000, help="Packets per frame size (default: 3000)")

    args = parser.parse_args()
    evaluator = ThroughputEvaluator(args.host, args.port)
    results = evaluator.evaluate_frame_sizes(count_per_size=args.count, teid=args.teid)
    print_scaling_table(results)


if __name__ == "__main__":
    main()
