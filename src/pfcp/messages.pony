/*
 * Truss 5G UPF & Packet Processing Fabric
 * 3GPP TS 29.244 PFCP Message Structures and Packet Codec
 */

use "buffered"
use "../truss_core"

class val PfcpHeartbeatReq
  let seq: U32
  let recovery_time: U32

  new val create(seq': U32, recovery_time': U32) =>
    seq = seq'
    recovery_time = recovery_time'

  fun encode(): Array[U8] val =>
    let ie = PfcpIeCodec.encode_recovery_time_stamp(recovery_time)
    let ie_bytes = ie.encode()
    let hdr = PfcpHeader(PfcpMsgTypeHeartbeatRequest, ie_bytes.size().u16(), seq)
    let hdr_bytes = hdr.encode()

    let out = recover iso Array[U8] end
    out.append(hdr_bytes)
    out.append(ie_bytes)
    consume out

class val PfcpHeartbeatResp
  let seq: U32
  let recovery_time: U32

  new val create(seq': U32, recovery_time': U32) =>
    seq = seq'
    recovery_time = recovery_time'

  fun encode(): Array[U8] val =>
    let ie = PfcpIeCodec.encode_recovery_time_stamp(recovery_time)
    let ie_bytes = ie.encode()
    let hdr = PfcpHeader(PfcpMsgTypeHeartbeatResponse, ie_bytes.size().u16(), seq)
    let hdr_bytes = hdr.encode()

    let out = recover iso Array[U8] end
    out.append(hdr_bytes)
    out.append(ie_bytes)
    consume out

class val PfcpAssociationSetupReq
  let seq: U32
  let node_id: NodeIdIe
  let recovery_time: U32

  new val create(seq': U32, node: NodeIdIe, recovery_time': U32) =>
    seq = seq'
    node_id = node
    recovery_time = recovery_time'

  fun encode(): Array[U8] val =>
    let ie1 = PfcpIeCodec.encode_node_id(node_id)
    let ie2 = PfcpIeCodec.encode_recovery_time_stamp(recovery_time)

    let out = recover iso Array[U8] end
    let b1 = ie1.encode()
    let b2 = ie2.encode()
    let total_len = (b1.size() + b2.size()).u16()

    let hdr = PfcpHeader(PfcpMsgTypeAssociationSetupRequest, total_len, seq)
    out.append(hdr.encode())
    out.append(b1)
    out.append(b2)
    consume out

class val PfcpAssociationSetupResp
  let seq: U32
  let node_id: NodeIdIe
  let cause: U8
  let recovery_time: U32

  new val create(seq': U32, node: NodeIdIe, cause': U8, recovery_time': U32) =>
    seq = seq'
    node_id = node
    cause = cause'
    recovery_time = recovery_time'

  fun encode(): Array[U8] val =>
    let ie_node = PfcpIeCodec.encode_node_id(node_id)
    let ie_cause = PfcpIeCodec.encode_cause(cause)
    let ie_ts = PfcpIeCodec.encode_recovery_time_stamp(recovery_time)

    let b_node = ie_node.encode()
    let b_cause = ie_cause.encode()
    let b_ts = ie_ts.encode()
    let total_len = (b_node.size() + b_cause.size() + b_ts.size()).u16()

    let hdr = PfcpHeader(PfcpMsgTypeAssociationSetupResponse, total_len, seq)
    let out = recover iso Array[U8] end
    out.append(hdr.encode())
    out.append(b_node)
    out.append(b_cause)
    out.append(b_ts)
    consume out

class val PfcpSessionEstablishmentReq
  let seq: U32
  let cp_fseid: FSeidIe
  let pdr_id: U16
  let precedence: U32
  let far_id: U32
  let local_teid: U32

  new val create(
    seq': U32,
    fseid: FSeidIe,
    pdr_id': U16,
    precedence': U32,
    far_id': U32,
    local_teid': U32)
  =>
    seq = seq'
    cp_fseid = fseid
    pdr_id = pdr_id'
    precedence = precedence'
    far_id = far_id'
    local_teid = local_teid'

  fun encode(): Array[U8] val =>
    let ie_node = PfcpIeCodec.encode_node_id(NodeIdIe.from_ipv4(cp_fseid.ipv4))
    let ie_fseid = PfcpIeCodec.encode_f_seid(cp_fseid)

    let out = recover iso Array[U8] end
    let b_node = ie_node.encode()
    let b_fseid = ie_fseid.encode()
    let total_len = (b_node.size() + b_fseid.size()).u16()

    let hdr = PfcpHeader(PfcpMsgTypeSessionEstablishmentRequest, total_len, seq, 0, true)
    out.append(hdr.encode())
    out.append(b_node)
    out.append(b_fseid)
    consume out

class val PfcpSessionEstablishmentResp
  let seq: U32
  let seid: U64
  let cause: U8
  let up_fseid: FSeidIe

  new val create(seq': U32, seid': U64, cause': U8, up_fseid': FSeidIe) =>
    seq = seq'
    seid = seid'
    cause = cause'
    up_fseid = up_fseid'

  fun encode(): Array[U8] val =>
    let ie_node = PfcpIeCodec.encode_node_id(NodeIdIe.from_ipv4(up_fseid.ipv4))
    let ie_cause = PfcpIeCodec.encode_cause(cause)
    let ie_fseid = PfcpIeCodec.encode_f_seid(up_fseid)

    let b_node = ie_node.encode()
    let b_cause = ie_cause.encode()
    let b_fseid = ie_fseid.encode()
    let total_len = (b_node.size() + b_cause.size() + b_fseid.size()).u16()

    let hdr = PfcpHeader(PfcpMsgTypeSessionEstablishmentResponse, total_len, seq, seid, true)
    let out = recover iso Array[U8] end
    out.append(hdr.encode())
    out.append(b_node)
    out.append(b_cause)
    out.append(b_fseid)
    consume out

class val PfcpSessionDeletionReq
  let seq: U32
  let seid: U64

  new val create(seq': U32, seid': U64) =>
    seq = seq'
    seid = seid'

  fun encode(): Array[U8] val =>
    let hdr = PfcpHeader(PfcpMsgTypeSessionDeletionRequest, 0, seq, seid, true)
    hdr.encode()

class val PfcpSessionDeletionResp
  let seq: U32
  let seid: U64
  let cause: U8
  let report: (UsageReport | None)

  new val create(seq': U32, seid': U64, cause': U8, rep: (UsageReport | None) = None) =>
    seq = seq'
    seid = seid'
    cause = cause'
    report = rep

  fun encode(): Array[U8] val =>
    let ie_cause = PfcpIeCodec.encode_cause(cause)
    let b_cause = ie_cause.encode()
    let total_len = b_cause.size().u16()

    let hdr = PfcpHeader(PfcpMsgTypeSessionDeletionResponse, total_len, seq, seid, true)
    let out = recover iso Array[U8] end
    out.append(hdr.encode())
    out.append(b_cause)
    consume out
