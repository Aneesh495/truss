/*
 * Truss 5G UPF & Packet Processing Fabric
 * Configuration Parser & Runtime Parameters
 */

use "../truss_core"

class val UpfConfig
  """
  Immutable runtime configuration for the Truss 5G UPF engine.
  """
  let node_id: String
  let pfcp_host: String
  let pfcp_port: String
  let gtpu_host: String
  let gtpu_port: String
  let admin_host: String
  let admin_port: String
  let n3_ipv4: Ipv4Address
  let n6_ipv4: Ipv4Address
  let teid_pool_start: U32
  let teid_pool_end: U32
  let worker_count: USize

  new val create(
    node': String = "upf.5g.local",
    pfcp_h: String = "0.0.0.0",
    pfcp_p: String = "8805",
    gtpu_h: String = "0.0.0.0",
    gtpu_p: String = "2152",
    admin_h: String = "0.0.0.0",
    admin_p: String = "8080",
    n3_ip: Ipv4Address = Ipv4Address.from_octets(10, 200, 1, 1),
    n6_ip: Ipv4Address = Ipv4Address.from_octets(10, 200, 2, 1),
    teid_start: U32 = 1000,
    teid_end: U32 = 1000000,
    workers: USize = 4)
  =>
    node_id = node'
    pfcp_host = pfcp_h
    pfcp_port = pfcp_p
    gtpu_host = gtpu_h
    gtpu_port = gtpu_p
    admin_host = admin_h
    admin_port = admin_p
    n3_ipv4 = n3_ip
    n6_ipv4 = n6_ip
    teid_pool_start = teid_start
    teid_pool_end = teid_end
    worker_count = workers
