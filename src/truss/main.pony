/*
 * Truss 5G UPF & Packet Processing Fabric
 * Main Application Runtime and Daemon Supervisor
 */

use "net"
use "../truss_core"
use "../gtpu"
use "../pfcp"

actor Main
  """
  Primary runtime supervisor for the Truss 5G UPF data plane.
  Initializes actor pipelines, binds network sockets, and handles signal lifecycle.
  """
  new create(env: Env) =>
    let config = UpfConfig
    let logger = Logger(env.out, LogLevelInfo)
    let metrics = MetricsCollector

    logger.info("INIT", "=========================================================")
    logger.info("INIT", " Truss 5G UPF & Programmable Packet Routing Fabric")
    logger.info("INIT", " Capabilities-secure actor concurrency runtime")
    logger.info("INIT", " Node ID: " + config.node_id)
    logger.info("INIT", " PFCP Control Plane: " + config.pfcp_host + ":" + config.pfcp_port)
    logger.info("INIT", " GTP-U User Plane:   " + config.gtpu_host + ":" + config.gtpu_port)
    logger.info("INIT", " Admin HTTP Telemetry: " + config.admin_host + ":" + config.admin_port)
    logger.info("INIT", " N3 (Access) IP:     " + config.n3_ipv4.string())
    logger.info("INIT", " N6 (Core) IP:       " + config.n6_ipv4.string())
    logger.info("INIT", "=========================================================")

    /* 1. Initialize Longest Prefix Match Routing Table */
    let routing: RoutingTrie iso = RoutingTrie
    /* Seed default route 0.0.0.0/0 to nexthop ID 1 */
    routing.insert(Ipv4Address.from_octets(0, 0, 0, 0), 0, 1)
    /* Seed local subnet 10.200.0.0/16 to nexthop ID 2 */
    routing.insert(Ipv4Address.from_octets(10, 200, 0, 0), 16, 2)
    logger.info("ROUTING", "Seeded 24-8 stride LPM routing tables successfully")

    /* 2. Initialize Session Registry and Packet Pipeline */
    let registry = SessionRegistry(metrics)
    let pipeline = PacketPipeline(registry, consume routing, logger, metrics)
    let node_manager = NodeManager(config, logger, metrics, registry)

    /* 3. Bind Network Sockets */
    let udp_auth = UDPAuth(env.root)
    let pfcp_listener = PfcpUdpListener(
      udp_auth,
      config.pfcp_host,
      config.pfcp_port,
      node_manager,
      logger)

    let gtpu_listener = GtpuUdpListener(
      udp_auth,
      config.gtpu_host,
      config.gtpu_port,
      pipeline,
      logger)

    let tcp_listen_auth = TCPListenAuth(env.root)
    let admin_server = AdminServer(
      tcp_listen_auth,
      config.admin_host,
      config.admin_port,
      metrics,
      logger)

    logger.info("SUPERVISOR", "Truss 5G UPF initialized and listening for traffic")
