/*
 * Truss 5G UPF & Packet Processing Fabric
 * 3GPP PFCP Node Manager Actor
 */

use "collections"
use "../truss_core"
use "../gtpu"
use "../pfcp"

actor NodeManager
  """
  Coordinates UPF node lifecycle, manages SMF associations, allocates
  local SEIDs and TEIDs, and handles PFCP control plane transactions.
  """
  let _config: UpfConfig
  let _logger: Logger
  let _metrics: MetricsCollector
  let _registry: SessionRegistry
  let _recovery_time: U32
  let _tx_tracker: PfcpTransactionTracker = PfcpTransactionTracker(512)

  var _next_seid: U64 = 1
  var _next_teid: U32

  let _associations: Map[String, AssociationState] = Map[String, AssociationState]

  new create(
    config': UpfConfig,
    logger': Logger,
    metrics': MetricsCollector,
    registry': SessionRegistry)
  =>
    _config = config'
    _logger = logger'
    _metrics = metrics'
    _registry = registry'
    _recovery_time = (MonotonicClock.seconds() + 2208988800).u32() /* NTP epoch offset */
    _next_teid = _config.teid_pool_start

  be handle_pfcp_message(
    raw_msg: Array[U8] val,
    from_ip: Ipv4Address,
    reply_sink: {(Array[U8] val)} val)
  =>
    _metrics.record_pfcp_request()

    try
      let hdr = PfcpHeader.decode(raw_msg)?

      /* Check transaction cache for retransmitted requests */
      match _tx_tracker.check_and_record(hdr.sequence_number, recover val Array[U8] end)
      | let cached: Array[U8] val =>
        if cached.size() > 0 then
          reply_sink(cached)
          return
        end
      end

      match hdr.message_type
      | PfcpMsgTypeHeartbeatRequest =>
        let resp = PfcpHeartbeatResp(hdr.sequence_number, _recovery_time)
        let resp_bytes = resp.encode()
        let _ = _tx_tracker.check_and_record(hdr.sequence_number, resp_bytes)
        reply_sink(resp_bytes)
        _metrics.record_pfcp_response()

      | PfcpMsgTypeAssociationSetupRequest =>
        _logger.info("NODE", "Received PFCP Association Setup Request from " + from_ip.string())
        _associations(from_ip.string()) = AssocStateEstablished

        let node_id = NodeIdIe.from_ipv4(_config.n3_ipv4)
        let resp = PfcpAssociationSetupResp(
          hdr.sequence_number,
          node_id,
          CauseRequestAccepted.code(),
          _recovery_time)
        let resp_bytes = resp.encode()
        let _ = _tx_tracker.check_and_record(hdr.sequence_number, resp_bytes)
        reply_sink(resp_bytes)
        _metrics.record_pfcp_response()

      | PfcpMsgTypeSessionEstablishmentRequest =>
        let local_seid = _next_seid
        _next_seid = _next_seid + 1

        let assigned_teid = _next_teid
        _next_teid = _next_teid + 1

        /* Parse IEs from payload */
        let payload_offset = hdr.header_size()
        let ies_data: Array[U8] val = recover val
          let slice = Array[U8]
          var i = payload_offset
          while i < raw_msg.size() do
            slice.push(raw_msg(i)?)
            i = i + 1
          end
          slice
        end

        var cp_seid_val: U64 = 0
        try
          let ies = PfcpIeCodec.parse_ie_stream(ies_data)?
          for ie in ies.values() do
            if ie.ie_type == IeTypeFSeid.code() then
              let fseid = PfcpIeCodec.decode_f_seid(ie)?
              cp_seid_val = fseid.seid
            end
          end
        end

        /* Instantiate subscriber session actor */
        let session = SessionActor(local_seid, cp_seid_val, _logger, _metrics)

        /* Default PDR for uplink N3 GTP-U */
        let pdr_ul = PdrRule(
          1,
          100,
          AccessInterface,
          assigned_teid,
          None,
          1,
          1,
          1)
        session.add_pdr(pdr_ul)

        /* Default FAR for uplink forwarding to CoreInterface */
        let far_ul = FarRule(1, ForwardingActionForw, CoreInterface)
        session.add_far(far_ul)

        /* Default QER: 1 Gbps PIR, 100 Mbps CIR */
        session.add_qer(1, GateOpen, 125_000_000, 10_000_000, 12_500_000, 2_000_000, 1)

        /* Default URR */
        session.add_urr(1, 100_000_000, 3600)

        /* Register in session registry */
        _registry.register_session(local_seid, session)
        _registry.bind_teid(assigned_teid, session)

        _logger.info("NODE", "Established PDU session, local SEID: " + local_seid.string() + ", assigned TEID: " + assigned_teid.string())

        /* Reply with Session Establishment Response */
        let up_fseid = FSeidIe(local_seid, _config.n3_ipv4)
        let resp = PfcpSessionEstablishmentResp(
          hdr.sequence_number,
          cp_seid_val,
          CauseRequestAccepted.code(),
          up_fseid)
        let resp_bytes = resp.encode()
        let _ = _tx_tracker.check_and_record(hdr.sequence_number, resp_bytes)
        reply_sink(resp_bytes)
        _metrics.record_pfcp_response()

      | PfcpMsgTypeSessionDeletionRequest =>
        let target_seid = hdr.seid
        _registry.remove_session(target_seid)

        let resp = PfcpSessionDeletionResp(
          hdr.sequence_number,
          target_seid,
          CauseRequestAccepted.code())
        let resp_bytes = resp.encode()
        let _ = _tx_tracker.check_and_record(hdr.sequence_number, resp_bytes)
        reply_sink(resp_bytes)
        _metrics.record_pfcp_response()
      end
    else
      _logger.err("NODE", "Failed to parse PFCP message from " + from_ip.string())
    end
