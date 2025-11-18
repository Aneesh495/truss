/*
 * Truss 5G UPF & Packet Processing Fabric
 * Admin HTTP REST Connection Actor
 */

use "net"
use "../truss_core"

actor AdminConnection is (TCPConnectionActor & ServerLifecycleEventReceiver)
  var _tcp_connection: TCPConnection = TCPConnection.none()
  let _metrics: MetricsCollector
  let _logger: Logger

  new create(
    auth: TCPServerAuth,
    fd: U32,
    metrics: MetricsCollector,
    logger: Logger)
  =>
    _metrics = metrics
    _logger = logger
    _tcp_connection = TCPConnection.server(auth, fd, this, this)

  fun ref _connection(): TCPConnection =>
    _tcp_connection

  fun ref _on_start_failure(reason: StartFailureReason) =>
    None

  fun ref _on_received(data: Array[U8] iso): ReadAction =>
    let req_str = String.from_iso_array(consume data)

    if req_str.contains("GET /healthz") then
      _send_http(200, "OK", "text/plain", "OK\n")
    elseif req_str.contains("GET /api/v1/info") then
      let info_json = "{\"name\":\"truss\",\"description\":\"3GPP 5G UPF in Pony\",\"version\":\"0.1.0\"}\n"
      _send_http(200, "OK", "application/json", info_json)
    elseif req_str.contains("GET /metrics") then
      let fallback_metrics = "{\"status\":\"healthy\",\"engine\":\"truss-5g-upf\"}\n"
      _send_http(200, "OK", "application/json", fallback_metrics)
    else
      _send_http(404, "Not Found", "text/plain", "Not Found\n")
    end

    YieldReading

  fun ref _send_http(status_code: U32, status_text: String, content_type: String, body: String) =>
    let resp = "HTTP/1.1 " + status_code.string() + " " + status_text + "\r\n"
      + "Content-Type: " + content_type + "\r\n"
      + "Content-Length: " + body.size().string() + "\r\n"
      + "Connection: close\r\n\r\n"
      + body

    _tcp_connection.send(consume resp)
    _tcp_connection.close()

  fun ref _on_closed() =>
    None
