#!/usr/bin/env python3
"""
Truss End-to-End Latency Distribution Profiler
Measures control plane transaction roundtrips and user plane packet forwarding
latencies. Generates percentile distributions (p50, p90, p95, p99, p99.9) and
ASCII latency distribution histograms.
"""

import argparse
import math
import os
import statistics
import sys
import time
from typing import List, Tuple

# Add tools directory to module search path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from smf_simulator import SmfClient


def render_ascii_histogram(samples: List[float], buckets: int = 10, title: str = "Latency Distribution (us)") -> None:
    """Render terminal ASCII histogram of sampled values."""
    if not samples:
        return

    min_v = min(samples)
    max_v = max(samples)
    if min_v == max_v:
        max_v = min_v + 1.0

    bucket_width = (max_v - min_v) / buckets
    counts = [0] * buckets

    for s in samples:
        b_idx = min(buckets - 1, int((s - min_v) / bucket_width))
        counts[b_idx] += 1

    max_count = max(counts)
    scale = 40.0 / max_count if max_count > 0 else 1.0

    print("-----------------------------------------------------------------")
    print(f" {title}")
    print("-----------------------------------------------------------------")
    for i in range(buckets):
        b_low = min_v + (i * bucket_width)
        b_high = b_low + bucket_width
        bar = "#" * int(counts[i] * scale)
        pct = (counts[i] / len(samples)) * 100.0
        print(f" [{b_low:6.1f} - {b_high:6.1f} us] : {bar:<40} ({counts[i]:4d} | {pct:4.1f}%)")
    print("-----------------------------------------------------------------")


class LatencyProfiler:
    """Profiles PFCP and datapath latency percentiles."""
    def __init__(self, host: str = "127.0.0.1", port: int = 8805):
        self.host = host
        self.port = port
        self.client = SmfClient(host, port)

    def profile_heartbeat(self, iterations: int = 500) -> List[float]:
        """Collect roundtrip latency for Heartbeat requests."""
        print(f"[PROFILER] Collecting {iterations} PFCP Heartbeat roundtrip samples...")
        samples = []
        for _ in range(iterations):
            _, lat_us = self.client.heartbeat()
            samples.append(float(lat_us))
        return samples

    def profile_session_establishment(self, iterations: int = 500) -> List[float]:
        """Collect roundtrip latency for Session Establishment."""
        print(f"[PROFILER] Collecting {iterations} PFCP Session Establishment samples...")
        self.client.association_setup()
        samples = []
        for i in range(iterations):
            seid = 0x30000 + i
            teid = 15000 + i
            _, lat_us = self.client.establish_session(seid, seid, teid)
            samples.append(float(lat_us))
            # Clean up
            try:
                self.client.delete_session(seid)
            except Exception:
                pass
        return samples


def compute_percentiles(samples: List[float]) -> dict:
    """Compute standard statistical percentiles."""
    if not samples:
        return {}
    sorted_s = sorted(samples)
    n = len(sorted_s)

    def get_pct(p: float) -> float:
        idx = min(n - 1, int(n * (p / 100.0)))
        return sorted_s[idx]

    return {
        "count": n,
        "mean": statistics.mean(samples),
        "stdev": statistics.stdev(samples) if n > 1 else 0.0,
        "min": sorted_s[0],
        "p50": get_pct(50),
        "p90": get_pct(90),
        "p95": get_pct(95),
        "p99": get_pct(99),
        "p99_9": get_pct(99.9),
        "max": sorted_s[-1]
    }


def print_report(name: str, p: dict) -> None:
    """Format and print statistical latency summary."""
    print("=================================================================")
    print(f" LATENCY PROFILE: {name.upper()}")
    print("=================================================================")
    print(f" Sample Count:       {p['count']}")
    print(f" Arithmetic Mean:    {p['mean']:.2f} us")
    print(f" Standard Deviation: {p['stdev']:.2f} us")
    print("-----------------------------------------------------------------")
    print(f" Min Latency:        {p['min']:.2f} us")
    print(f" 50th Percentile:    {p['p50']:.2f} us  (Median)")
    print(f" 90th Percentile:    {p['p90']:.2f} us")
    print(f" 95th Percentile:    {p['p95']:.2f} us")
    print(f" 99th Percentile:    {p['p99']:.2f} us")
    print(f" 99.9th Percentile:  {p['p99_9']:.2f} us")
    print(f" Max Tail Latency:   {p['max']:.2f} us")
    print("=================================================================")


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="latency_profiler",
        description="Truss 5G UPF High-Resolution Latency Distribution Profiler"
    )
    parser.add_argument("--host", default="127.0.0.1", help="Target UPF host (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8805, help="UPF PFCP UDP port (default: 8805)")
    parser.add_argument("--iterations", type=int, default=300, help="Number of samples to collect (default: 300)")
    parser.add_argument(
        "--procedure",
        choices=["heartbeat", "session-establishment", "all"],
        default="heartbeat",
        help="Procedure to profile"
    )

    args = parser.parse_args()
    profiler = LatencyProfiler(args.host, args.port)

    if args.procedure in ("heartbeat", "all"):
        hb_samples = profiler.profile_heartbeat(args.iterations)
        hb_stats = compute_percentiles(hb_samples)
        print_report("PFCP Heartbeat Roundtrip", hb_stats)
        render_ascii_histogram(hb_samples, title="PFCP Heartbeat Latency Distribution (us)")

    if args.procedure in ("session-establishment", "all"):
        sess_samples = profiler.profile_session_establishment(min(100, args.iterations))
        sess_stats = compute_percentiles(sess_samples)
        print_report("PFCP Session Establishment", sess_stats)
        render_ascii_histogram(sess_samples, title="Session Establishment Latency Distribution (us)")


if __name__ == "__main__":
    main()
