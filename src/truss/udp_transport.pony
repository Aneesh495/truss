/*
 * Truss 5G UPF & Packet Processing Fabric
 * UDP Transport Actors for PFCP (Port 8805) and GTP-U (Port 2152)
 */

use "net"
use "../truss_core"

actor PfcpUdpListener is (UDPSocketActor & UDPLifecycleEventReceiver)
  var _udp: UDPSocket = UDPSocket.none()
  let _node_manager: NodeManager
  let _logger: Logger

  new create(
    auth: UDPAuth,
    host: String,
    port: String,
    node_manager: NodeManager,
    logger: Logger)
  =>
    _node_manager = node_manager
    _logger = logger
    _udp = UDPSocket(auth, host, port, this, this)

  fun ref _socket(): UDPSocket => _udp

  fun ref _on_bound() =>
    _logger.info("NET", "PFCP UDP listener bound successfully")

  fun ref _on_bind_failure() =>
    _logger.fatal("NET", "Failed to bind PFCP UDP listener")

  fun ref _on_received(data: Array[U8] iso, from: NetAddress val): ReadAction =>
    let payload: Array[U8] val = consume data
    try
      (let ip_str, let port_str) = from.name()?
      let from_ip = Ipv4Address.parse(ip_str)?

      _node_manager.handle_pfcp_message(payload, from_ip, {(resp: Array[U8] val) =>
        None
      })
    end
    KeepReading

  fun ref _on_closed() =>
    _logger.info("NET", "PFCP UDP listener closed")

actor GtpuUdpListener is (UDPSocketActor & UDPLifecycleEventReceiver)
  var _udp: UDPSocket = UDPSocket.none()
  let _pipeline: PacketPipeline
  let _logger: Logger

  new create(
    auth: UDPAuth,
    host: String,
    port: String,
    pipeline: PacketPipeline,
    logger: Logger)
  =>
    _pipeline = pipeline
    _logger = logger
    _udp = UDPSocket(auth, host, port, this, this)

  fun ref _socket(): UDPSocket => _udp

  fun ref _on_bound() =>
    _logger.info("NET", "GTP-U UDP listener bound successfully")

  fun ref _on_bind_failure() =>
    _logger.fatal("NET", "Failed to bind GTP-U UDP listener")

  fun ref _on_received(data: Array[U8] iso, from: NetAddress val): ReadAction =>
    let payload: Array[U8] val = consume data
    try
      (let ip_str, let port_str) = from.name()?
      let from_ip = Ipv4Address.parse(ip_str)?

      _pipeline.process_n3_datagram(payload, from_ip, {(egress_data: Array[U8] val) =>
        None
      })
    end
    KeepReading

  fun ref _on_closed() =>
    _logger.info("NET", "GTP-U UDP listener closed")
