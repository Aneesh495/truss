/*
 * Truss 5G UPF & Packet Processing Fabric
 * Subscriber PDU Session Actor
 */

use "collections"
use "../truss_core"
use "../gtpu"
use "../pfcp"

class val PdrRule
  let pdr_id: U16
  let precedence: U32
  let source_interface: NetworkInterface
  let local_teid: (U32 | None)
  let ue_ip: (Ipv4Address | None)
  let far_id: U32
  let qer_id: (U32 | None)
  let urr_id: (U32 | None)

  new val create(
    id': U16,
    prec: U32,
    src_if: NetworkInterface,
    teid': (U32 | None),
    ip': (Ipv4Address | None),
    fid: U32,
    qid: (U32 | None) = None,
    uid: (U32 | None) = None)
  =>
    pdr_id = id'
    precedence = prec
    source_interface = src_if
    local_teid = teid'
    ue_ip = ip'
    far_id = fid
    qer_id = qid
    urr_id = uid

class val FarRule
  let far_id: U32
  let action: ForwardingAction
  let destination_interface: NetworkInterface
  let outer_header: (OuterHeaderCreationIe | None)

  new val create(
    id': U32,
    act: ForwardingAction,
    dst_if: NetworkInterface,
    out_hdr: (OuterHeaderCreationIe | None) = None)
  =>
    far_id = id'
    action = act
    destination_interface = dst_if
    outer_header = out_hdr

actor SessionActor
  """
  Represents an active 5G PDU session. Owns all session rules (PDR, FAR,
  QER, URR) and processes traffic with zero concurrency locks.
  """
  let _local_seid: U64
  let _cp_seid: U64
  let _logger: Logger
  let _metrics: MetricsCollector

  let _pdrs: Map[U16, PdrRule] = Map[U16, PdrRule]
  let _fars: Map[U32, FarRule] = Map[U32, FarRule]
  let _qers: Map[U32, (GateStatus, TrtcmMeter, U8)] = Map[U32, (GateStatus, TrtcmMeter, U8)]
  let _urrs: Map[U32, UsageMeter] = Map[U32, UsageMeter]
  let _paging_buffer: ChunkRingBuffer = ChunkRingBuffer(64)

  new create(
    local_seid': U64,
    cp_seid': U64,
    logger': Logger,
    metrics': MetricsCollector)
  =>
    _local_seid = local_seid'
    _cp_seid = cp_seid'
    _logger = logger'
    _metrics = metrics'

  be add_pdr(rule: PdrRule) =>
    _pdrs(rule.pdr_id) = rule

  be add_far(rule: FarRule) =>
    _fars(rule.far_id) = rule

  be add_qer(qer_id: U32, gate: GateStatus, pir: U64, pbs: U64, cir: U64, cbs: U64, qfi: U8) =>
    let meter = TrtcmMeter(pir, pbs, cir, cbs)
    _qers(qer_id) = (gate, meter, qfi)

  be add_urr(urr_id: U32, vol_threshold: U64, time_threshold_sec: U64) =>
    _urrs(urr_id) = UsageMeter(urr_id, vol_threshold, time_threshold_sec)

  be process_uplink(payload: Array[U8] val, ingress_teid: U32, egress_sink: {(Array[U8] val)} val) =>
    let start_ns = MonotonicClock.nanos()
    let pkt_size = payload.size().u64()

    /* 1. Find matching PDR by precedence (lowest precedence integer wins) */
    var matched_pdr: (PdrRule | None) = None
    var lowest_precedence: U32 = 0xFFFFFFFF

    for pdr in _pdrs.values() do
      match pdr.source_interface
      | AccessInterface =>
        match pdr.local_teid
        | let t: U32 =>
          if (t == ingress_teid) and (pdr.precedence < lowest_precedence) then
            lowest_precedence = pdr.precedence
            matched_pdr = pdr
          end
        end
      end
    end

    match matched_pdr
    | let pdr: PdrRule =>
      /* 2. Check QER */
      match pdr.qer_id
      | let qid: U32 =>
        try
          (let gate, let meter, let qfi) = _qers(qid)?
          match gate
          | GateClosed =>
            _metrics.record_drop_gate_closed()
            return
          end
          let color = meter.mark(pkt_size, start_ns)
          match color
          | ColorRed =>
            _metrics.record_drop_rate_limit()
            return
          end
        end
      end

      /* 3. Record URR */
      match pdr.urr_id
      | let uid: U32 =>
        try
          let urr = _urrs(uid)?
          let rep = urr.record_uplink(pkt_size)
          match rep
          | let r: UsageReport =>
            _logger.info("SESSION", "URR threshold reached for SEID " + _local_seid.string())
          end
        end
      end

      /* 4. Apply FAR */
      try
        let far = _fars(pdr.far_id)?
        match far.action
        | ForwardingActionForw =>
          egress_sink(payload)
          _metrics.record_uplink(pkt_size, MonotonicClock.nanos() - start_ns)
        | ForwardingActionDrop =>
          _metrics.record_drop_gate_closed()
        | ForwardingActionBuff =>
          _paging_buffer.enqueue(payload, start_ns)
        end
      end
    else
      _metrics.record_drop_unknown_teid()
    end

  be process_downlink(ip_payload: Array[U8] val, ue_ip: Ipv4Address, egress_sink: {(U32, Ipv4Address, Array[U8] val)} val) =>
    let start_ns = MonotonicClock.nanos()
    let pkt_size = ip_payload.size().u64()

    /* 1. Find matching PDR for CoreInterface */
    var matched_pdr: (PdrRule | None) = None
    var lowest_precedence: U32 = 0xFFFFFFFF

    for pdr in _pdrs.values() do
      match pdr.source_interface
      | CoreInterface =>
        match pdr.ue_ip
        | let uip: Ipv4Address =>
          if (uip.raw == ue_ip.raw) and (pdr.precedence < lowest_precedence) then
            lowest_precedence = pdr.precedence
            matched_pdr = pdr
          end
        end
      end
    end

    match matched_pdr
    | let pdr: PdrRule =>
      /* 2. Check QER */
      match pdr.qer_id
      | let qid: U32 =>
        try
          (let gate, let meter, let qfi) = _qers(qid)?
          match gate
          | GateClosed =>
            _metrics.record_drop_gate_closed()
            return
          end
          let color = meter.mark(pkt_size, start_ns)
          match color
          | ColorRed =>
            _metrics.record_drop_rate_limit()
            return
          end
        end
      end

      /* 3. Record URR */
      match pdr.urr_id
      | let uid: U32 =>
        try
          let urr = _urrs(uid)?
          let _ = urr.record_downlink(pkt_size)
        end
      end

      /* 4. Apply FAR */
      try
        let far = _fars(pdr.far_id)?
        match far.action
        | ForwardingActionForw =>
          match far.outer_header
          | let oh: OuterHeaderCreationIe =>
            egress_sink(oh.teid, oh.ipv4, ip_payload)
            _metrics.record_downlink(pkt_size, MonotonicClock.nanos() - start_ns)
          end
        | ForwardingActionBuff =>
          _paging_buffer.enqueue(ip_payload, start_ns)
          _logger.info("SESSION", "Buffered DL packet for idle UE, SEID: " + _local_seid.string())
        | ForwardingActionDrop =>
          _metrics.record_drop_gate_closed()
        end
      end
    else
      _metrics.record_drop_unknown_teid()
    end

  be terminate(receiver: {(U64, Array[UsageReport] val)} val) =>
    let reports = recover iso Array[UsageReport] end
    for urr in _urrs.values() do
      reports.push(urr.generate_final_report())
    end
    receiver(_local_seid, consume reports)
