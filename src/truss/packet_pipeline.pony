/*
 * Truss 5G UPF & Packet Processing Fabric
 * Zero-Copy Packet Pipeline Worker Actor
 */

use "../truss_core"
use "../gtpu"

actor PacketPipeline
  """
  Dispatches packets between physical network interfaces and session actors.
  Performs O(1) TEID classification and invokes session state machines.
  """
  let _registry: SessionRegistry
  let _routing: RoutingTrie
  let _logger: Logger
  let _metrics: MetricsCollector

  new create(
    registry: SessionRegistry,
    routing: RoutingTrie iso,
    logger: Logger,
    metrics: MetricsCollector)
  =>
    _registry = registry
    _routing = consume routing
    _logger = logger
    _metrics = metrics

  be process_n3_datagram(
    raw_packet: Array[U8] val,
    from_ip: Ipv4Address,
    egress_n6_sink: {(Array[U8] val)} val)
  =>
    try
      let gtpu = GtpuPacket.decode(raw_packet)?
      let teid = gtpu.header.teid
      let payload = gtpu.payload

      _registry.lookup_by_teid(teid, {(session: (SessionActor | None)) =>
        match session
        | let s: SessionActor =>
          s.process_uplink(payload, teid, egress_n6_sink)
        | None =>
          None
        end
      })
    else
      _metrics.record_drop_unknown_teid()
    end

  be process_n6_datagram(
    ip_packet: Array[U8] val,
    egress_n3_sink: {(U32, Ipv4Address, Array[U8] val)} val)
  =>
    /* Extract destination IPv4 address from IP header (bytes 16-19) */
    if ip_packet.size() < 20 then return end
    try
      let o1 = ip_packet(16)?
      let o2 = ip_packet(17)?
      let o3 = ip_packet(18)?
      let o4 = ip_packet(19)?
      let dst_ip = Ipv4Address.from_octets(o1, o2, o3, o4)

      _registry.lookup_by_ue_ip(dst_ip, {(session: (SessionActor | None)) =>
        match session
        | let s: SessionActor =>
          s.process_downlink(ip_packet, dst_ip, egress_n3_sink)
        | None =>
          None
        end
      })
    end
