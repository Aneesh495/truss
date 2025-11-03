/*
 * Truss 5G UPF & Packet Processing Fabric
 * High-Performance Telemetry & Metrics Collector Actor
 */

use "format"
use "../truss_core"

actor MetricsCollector
  """
  Maintains system-wide telemetry counters, packet drop reasons,
  and latency histograms for the UPF datapath.
  """
  var _uplink_packets: U64 = 0
  var _uplink_bytes: U64 = 0
  var _downlink_packets: U64 = 0
  var _downlink_bytes: U64 = 0
  var _dropped_unknown_teid: U64 = 0
  var _dropped_gate_closed: U64 = 0
  var _dropped_rate_limit: U64 = 0
  var _active_sessions: USize = 0
  var _pfcp_requests: U64 = 0
  var _pfcp_responses: U64 = 0

  /* Simple log2 latency histogram buckets (in microseconds): <1us, <2us, <4us, <8us, ... */
  let _latency_buckets: Array[U64] = Array[U64](16)

  new create() =>
    var i: USize = 0
    while i < 16 do
      _latency_buckets.push(0)
      i = i + 1
    end

  be record_uplink(bytes: U64, latency_ns: U64 = 0) =>
    _uplink_packets = _uplink_packets + 1
    _uplink_bytes = _uplink_bytes + bytes
    _record_latency(latency_ns)

  be record_downlink(bytes: U64, latency_ns: U64 = 0) =>
    _downlink_packets = _downlink_packets + 1
    _downlink_bytes = _downlink_bytes + bytes
    _record_latency(latency_ns)

  be record_drop_unknown_teid() =>
    _dropped_unknown_teid = _dropped_unknown_teid + 1

  be record_drop_gate_closed() =>
    _dropped_gate_closed = _dropped_gate_closed + 1

  be record_drop_rate_limit() =>
    _dropped_rate_limit = _dropped_rate_limit + 1

  be set_active_sessions(count: USize) =>
    _active_sessions = count

  be record_pfcp_request() =>
    _pfcp_requests = _pfcp_requests + 1

  be record_pfcp_response() =>
    _pfcp_responses = _pfcp_responses + 1

  fun ref _record_latency(latency_ns: U64) =>
    if latency_ns == 0 then return end
    let us = latency_ns / 1_000
    var bucket: USize = 0
    var threshold: U64 = 1
    while (bucket < 15) and (us >= threshold) do
      threshold = threshold * 2
      bucket = bucket + 1
    end
    try
      _latency_buckets(bucket)? = _latency_buckets(bucket)? + 1
    end

  be export_json(receiver: {(String)} val) =>
    let json = "{"
      + "\"uplink_packets\":" + _uplink_packets.string() + ","
      + "\"uplink_bytes\":" + _uplink_bytes.string() + ","
      + "\"downlink_packets\":" + _downlink_packets.string() + ","
      + "\"downlink_bytes\":" + _downlink_bytes.string() + ","
      + "\"dropped_unknown_teid\":" + _dropped_unknown_teid.string() + ","
      + "\"dropped_gate_closed\":" + _dropped_gate_closed.string() + ","
      + "\"dropped_rate_limit\":" + _dropped_rate_limit.string() + ","
      + "\"active_sessions\":" + _active_sessions.string() + ","
      + "\"pfcp_requests\":" + _pfcp_requests.string() + ","
      + "\"pfcp_responses\":" + _pfcp_responses.string() + "}"
    receiver(consume json)
