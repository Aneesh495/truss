/*
 * Truss 5G UPF & Packet Processing Fabric
 * Concurrent Session Registry Actor
 */

use "collections"
use "../truss_core"

actor SessionRegistry
  """
  Thread-safe index mapping TEIDs, UE IPs, and local SEIDs to SessionActors.
  Enables O(1) packet dispatching without cross-thread lock contention.
  """
  let _by_local_seid: Map[U64, SessionActor] = Map[U64, SessionActor]
  let _by_ingress_teid: Map[U32, SessionActor] = Map[U32, SessionActor]
  let _by_ue_ip: Map[U32, SessionActor] = Map[U32, SessionActor]
  let _metrics: MetricsCollector

  new create(metrics: MetricsCollector) =>
    _metrics = metrics

  be register_session(local_seid: U64, session: SessionActor) =>
    _by_local_seid(local_seid) = session
    _metrics.set_active_sessions(_by_local_seid.size())

  be bind_teid(teid: U32, session: SessionActor) =>
    _by_ingress_teid(teid) = session

  be bind_ue_ip(ue_ip: Ipv4Address, session: SessionActor) =>
    _by_ue_ip(ue_ip.raw) = session

  be lookup_by_teid(teid: U32, callback: {((SessionActor | None))} val) =>
    try
      callback(_by_ingress_teid(teid)?)
    else
      callback(None)
    end

  be lookup_by_ue_ip(ue_ip: Ipv4Address, callback: {((SessionActor | None))} val) =>
    try
      callback(_by_ue_ip(ue_ip.raw)?)
    else
      callback(None)
    end

  be remove_session(local_seid: U64, teid: (U32 | None) = None, ue_ip: (Ipv4Address | None) = None) =>
    try _by_local_seid.remove(local_seid)? end
    match teid
    | let t: U32 => try _by_ingress_teid.remove(t)? end
    end
    match ue_ip
    | let ip: Ipv4Address => try _by_ue_ip.remove(ip.raw)? end
    end
    _metrics.set_active_sessions(_by_local_seid.size())

  be session_count(callback: {(USize)} val) =>
    callback(_by_local_seid.size())
