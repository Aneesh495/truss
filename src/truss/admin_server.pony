/*
 * Truss 5G UPF & Packet Processing Fabric
 * Admin HTTP REST Server Actor
 */

use "net"
use "../truss_core"

actor AdminServer is TCPListenerActor
  var _tcp_listener: TCPListener = TCPListener.none()
  let _server_auth: TCPServerAuth
  let _metrics: MetricsCollector
  let _logger: Logger

  new create(
    listen_auth: TCPListenAuth,
    host: String,
    port: String,
    metrics: MetricsCollector,
    logger: Logger)
  =>
    _server_auth = TCPServerAuth(listen_auth)
    _metrics = metrics
    _logger = logger
    _tcp_listener = TCPListener(listen_auth, host, port, this)

  fun ref _listener(): TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): AdminConnection =>
    AdminConnection(_server_auth, fd, _metrics, _logger)

  fun ref _on_listening() =>
    _logger.info("ADMIN", "Admin HTTP REST server listening")

  fun ref _on_listen_failure() =>
    _logger.fatal("ADMIN", "Failed to bind Admin HTTP REST server")

  fun ref _on_closed() =>
    _logger.info("ADMIN", "Admin HTTP REST server closed")
