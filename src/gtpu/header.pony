/*
 * Truss 5G UPF & Packet Processing Fabric
 * 3GPP TS 29.281 GTP-U Header Definitions and Encoding
 */

use "buffered"

primitive GtpuTypeEchoRequest
  fun code(): U8 => 1
  fun string(): String => "Echo Request"

primitive GtpuTypeEchoResponse
  fun code(): U8 => 2
  fun string(): String => "Echo Response"

primitive GtpuTypeErrorIndication
  fun code(): U8 => 26
  fun string(): String => "Error Indication"

primitive GtpuTypeEndMarker
  fun code(): U8 => 254
  fun string(): String => "End Marker"

primitive GtpuTypeGPdu
  fun code(): U8 => 255
  fun string(): String => "G-PDU User Data"

type GtpuMessageType is
  ( GtpuTypeEchoRequest
  | GtpuTypeEchoResponse
  | GtpuTypeErrorIndication
  | GtpuTypeEndMarker
  | GtpuTypeGPdu )

primitive GtpuMessageTypeCodec
  fun from_code(code': U8): GtpuMessageType? =>
    match code'
    | 1 => GtpuTypeEchoRequest
    | 2 => GtpuTypeEchoResponse
    | 26 => GtpuTypeErrorIndication
    | 254 => GtpuTypeEndMarker
    | 255 => GtpuTypeGPdu
    else
      error
    end

class val GtpuFlags
  """
  Represents 8-bit flags field in GTP-U header.
  Version must be 1 (001 in upper 3 bits).
  PT: 1 for GTP.
  E: Extension header flag.
  S: Sequence number flag.
  PN: N-PDU number flag.
  """
  let raw: U8

  new val create(
    version': U8 = 1,
    pt': Bool = true,
    has_ext': Bool = false,
    has_seq': Bool = false,
    has_npdu': Bool = false)
  =>
    var f: U8 = (version' and 0x07) << 5
    if pt' then f = f or 0x10 end
    if has_ext' then f = f or 0x04 end
    if has_seq' then f = f or 0x02 end
    if has_npdu' then f = f or 0x01 end
    raw = f

  new val from_raw(raw': U8) =>
    raw = raw'

  fun version(): U8 => (raw >> 5) and 0x07
  fun is_gtp(): Bool => (raw and 0x10) != 0
  fun has_extension(): Bool => (raw and 0x04) != 0
  fun has_sequence(): Bool => (raw and 0x02) != 0
  fun has_npdu(): Bool => (raw and 0x01) != 0
  fun has_optional_fields(): Bool => (raw and 0x07) != 0

class val GtpuHeader
  """
  Mandatory 8-byte GTP-U header with optional 4-byte extension fields.
  """
  let flags: GtpuFlags
  let message_type: GtpuMessageType
  let length: U16
  let teid: U32
  let sequence_number: (U16 | None)
  let npdu_number: (U8 | None)
  let next_extension_type: (U8 | None)

  new val create(
    flags': GtpuFlags,
    msg_type': GtpuMessageType,
    len': U16,
    teid': U32,
    seq': (U16 | None) = None,
    npdu': (U8 | None) = None,
    next_ext': (U8 | None) = None)
  =>
    flags = flags'
    message_type = msg_type'
    length = len'
    teid = teid'
    sequence_number = seq'
    npdu_number = npdu'
    next_extension_type = next_ext'

  fun header_size(): USize =>
    if flags.has_optional_fields() then 12 else 8 end

  fun encode(): Array[U8] val =>
    let wb = Writer
    wb.u8(flags.raw)
    wb.u8(message_type.code())
    wb.u16_be(length)
    wb.u32_be(teid)

    if flags.has_optional_fields() then
      let s = match sequence_number | let sn: U16 => sn else 0 end
      let p = match npdu_number | let pn: U8 => pn else 0 end
      let e = match next_extension_type | let ne: U8 => ne else 0 end
      wb.u16_be(s)
      wb.u8(p)
      wb.u8(e)
    end

    let chunks = wb.done()
    let out = recover iso Array[U8] end
    for chunk in (consume chunks).values() do
      match chunk
      | let s: String => out.append(s)
      | let a: Array[U8] val => out.append(a)
      end
    end
    consume out
