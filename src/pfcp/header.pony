/*
 * Truss 5G UPF & Packet Processing Fabric
 * 3GPP TS 29.244 PFCP Header Definitions and Codec
 */

use "buffered"

primitive PfcpMsgTypeHeartbeatRequest
  fun code(): U8 => 1
  fun is_session_type(): Bool => false
  fun string(): String => "Heartbeat Request"

primitive PfcpMsgTypeHeartbeatResponse
  fun code(): U8 => 2
  fun is_session_type(): Bool => false
  fun string(): String => "Heartbeat Response"

primitive PfcpMsgTypeAssociationSetupRequest
  fun code(): U8 => 5
  fun is_session_type(): Bool => false
  fun string(): String => "Association Setup Request"

primitive PfcpMsgTypeAssociationSetupResponse
  fun code(): U8 => 6
  fun is_session_type(): Bool => false
  fun string(): String => "Association Setup Response"

primitive PfcpMsgTypeAssociationReleaseRequest
  fun code(): U8 => 9
  fun is_session_type(): Bool => false
  fun string(): String => "Association Release Request"

primitive PfcpMsgTypeAssociationReleaseResponse
  fun code(): U8 => 10
  fun is_session_type(): Bool => false
  fun string(): String => "Association Release Response"

primitive PfcpMsgTypeSessionEstablishmentRequest
  fun code(): U8 => 50
  fun is_session_type(): Bool => true
  fun string(): String => "Session Establishment Request"

primitive PfcpMsgTypeSessionEstablishmentResponse
  fun code(): U8 => 51
  fun is_session_type(): Bool => true
  fun string(): String => "Session Establishment Response"

primitive PfcpMsgTypeSessionModificationRequest
  fun code(): U8 => 52
  fun is_session_type(): Bool => true
  fun string(): String => "Session Modification Request"

primitive PfcpMsgTypeSessionModificationResponse
  fun code(): U8 => 53
  fun is_session_type(): Bool => true
  fun string(): String => "Session Modification Response"

primitive PfcpMsgTypeSessionDeletionRequest
  fun code(): U8 => 54
  fun is_session_type(): Bool => true
  fun string(): String => "Session Deletion Request"

primitive PfcpMsgTypeSessionDeletionResponse
  fun code(): U8 => 55
  fun is_session_type(): Bool => true
  fun string(): String => "Session Deletion Response"

primitive PfcpMsgTypeSessionReportRequest
  fun code(): U8 => 56
  fun is_session_type(): Bool => true
  fun string(): String => "Session Report Request"

primitive PfcpMsgTypeSessionReportResponse
  fun code(): U8 => 57
  fun is_session_type(): Bool => true
  fun string(): String => "Session Report Response"

type PfcpMessageType is
  ( PfcpMsgTypeHeartbeatRequest
  | PfcpMsgTypeHeartbeatResponse
  | PfcpMsgTypeAssociationSetupRequest
  | PfcpMsgTypeAssociationSetupResponse
  | PfcpMsgTypeAssociationReleaseRequest
  | PfcpMsgTypeAssociationReleaseResponse
  | PfcpMsgTypeSessionEstablishmentRequest
  | PfcpMsgTypeSessionEstablishmentResponse
  | PfcpMsgTypeSessionModificationRequest
  | PfcpMsgTypeSessionModificationResponse
  | PfcpMsgTypeSessionDeletionRequest
  | PfcpMsgTypeSessionDeletionResponse
  | PfcpMsgTypeSessionReportRequest
  | PfcpMsgTypeSessionReportResponse )

primitive PfcpMessageTypeCodec
  fun from_code(code': U8): PfcpMessageType? =>
    match code'
    | 1 => PfcpMsgTypeHeartbeatRequest
    | 2 => PfcpMsgTypeHeartbeatResponse
    | 5 => PfcpMsgTypeAssociationSetupRequest
    | 6 => PfcpMsgTypeAssociationSetupResponse
    | 9 => PfcpMsgTypeAssociationReleaseRequest
    | 10 => PfcpMsgTypeAssociationReleaseResponse
    | 50 => PfcpMsgTypeSessionEstablishmentRequest
    | 51 => PfcpMsgTypeSessionEstablishmentResponse
    | 52 => PfcpMsgTypeSessionModificationRequest
    | 53 => PfcpMsgTypeSessionModificationResponse
    | 54 => PfcpMsgTypeSessionDeletionRequest
    | 55 => PfcpMsgTypeSessionDeletionResponse
    | 56 => PfcpMsgTypeSessionReportRequest
    | 57 => PfcpMsgTypeSessionReportResponse
    else
      error
    end

class val PfcpHeader
  """
  PFCP binary header according to 3GPP TS 29.244 clause 7.2.2.
  8 octets for Node-related messages (S=0).
  16 octets for Session-related messages (S=1).
  """
  let version: U8
  let has_seid: Bool
  let message_type: PfcpMessageType
  let length: U16
  let seid: U64
  let sequence_number: U32

  new val create(
    msg_type': PfcpMessageType,
    len': U16,
    seq': U32,
    seid': U64 = 0,
    has_seid': (Bool | None) = None)
  =>
    version = 1
    has_seid = match has_seid'
    | let b: Bool => b
    else
      msg_type'.is_session_type()
    end
    message_type = msg_type'
    length = len'
    sequence_number = seq' and 0x00FFFFFF
    seid = seid'

  fun header_size(): USize =>
    if has_seid then 16 else 8 end

  fun encode(): Array[U8] val =>
    let wb = Writer
    var flags: U8 = (version and 0x07) << 5
    if has_seid then flags = flags or 0x01 end

    wb.u8(flags)
    wb.u8(message_type.code())
    wb.u16_be(length)

    if has_seid then
      wb.u64_be(seid)
    end

    /* 24-bit sequence number (3 bytes) */
    let s2 = ((sequence_number >> 16) and 0xFF).u8()
    let s1 = ((sequence_number >> 8) and 0xFF).u8()
    let s0 = (sequence_number and 0xFF).u8()
    wb.u8(s2)
    wb.u8(s1)
    wb.u8(s0)

    /* Spare octet */
    wb.u8(0)

    let chunks = wb.done()
    let out = recover iso Array[U8] end
    for chunk in (consume chunks).values() do
      match chunk
      | let s: String => out.append(s)
      | let a: Array[U8] val => out.append(a)
      end
    end
    consume out

  new val decode(data: Array[U8] val)? =>
    if data.size() < 8 then error end
    let rb = Reader
    rb.append(data)

    let flags = rb.u8()?
    version = (flags >> 5) and 0x07
    if version != 1 then error end

    has_seid = (flags and 0x01) != 0
    let msg_code = rb.u8()?
    message_type = PfcpMessageTypeCodec.from_code(msg_code)?
    length = rb.u16_be()?

    if has_seid then
      if rb.size() < 12 then error end
      seid = rb.u64_be()?
    else
      seid = 0
    end

    if rb.size() < 4 then error end
    let s2 = rb.u8()?.u32()
    let s1 = rb.u8()?.u32()
    let s0 = rb.u8()?.u32()
    sequence_number = (s2 << 16) or (s1 << 8) or s0
    let _ = rb.u8()? /* Spare */
