/*
 * Truss 5G UPF & Packet Processing Fabric
 * GTP-U Tunnel Endpoint Manager Actor
 */

use "../truss_core"

actor TunnelEndpoint
  """
  Manages GTP-U tunnel endpoints, decapsulates ingress packets,
  and encapsulates egress packets towards the Radio Access Network.
  """
  let _logger: Logger
  var _active_tunnels: USize = 0
  var _packets_processed: U64 = 0
  var _bytes_processed: U64 = 0

  new create(logger: Logger) =>
    _logger = logger

  be decapsulate(raw_datagram: Array[U8] val, from_ip: Ipv4Address) =>
    _packets_processed = _packets_processed + 1
    _bytes_processed = _bytes_processed + raw_datagram.size().u64()

    try
      let pkt = GtpuPacket.decode(raw_datagram)?
      match pkt.header.message_type
      | GtpuTypeGPdu =>
        /* G-PDU user plane payload ready for session pipeline */
        None
      | GtpuTypeEchoRequest =>
        _logger.debug("GTPU", "Received GTP-U Echo Request from " + from_ip.string())
      | GtpuTypeEchoResponse =>
        _logger.debug("GTPU", "Received GTP-U Echo Response from " + from_ip.string())
      | GtpuTypeErrorIndication =>
        _logger.warn("GTPU", "Received GTP-U Error Indication for TEID " + pkt.header.teid.string())
      | GtpuTypeEndMarker =>
        _logger.info("GTPU", "Received GTP-U End Marker for TEID " + pkt.header.teid.string())
      end
    else
      _logger.err("GTPU", "Failed to decode malformed GTP-U datagram of size " + raw_datagram.size().string())
    end

  be stats(receiver: {(U64, U64, USize)} val) =>
    receiver(_packets_processed, _bytes_processed, _active_tunnels)
