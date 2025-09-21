/*
 * Truss 5G UPF & Packet Processing Fabric
 * High-Resolution Monotonic Clock Primitives
 */

use "time"

primitive MonotonicClock
  """
  Monotonic nanosecond timestamp source for packet processing,
  QoS token replenishment, and latency profiling.
  """
  fun nanos(): U64 =>
    Time.nanos()

  fun millis(): U64 =>
    Time.nanos() / 1_000_000

  fun seconds(): U64 =>
    Time.nanos() / 1_000_000_000
