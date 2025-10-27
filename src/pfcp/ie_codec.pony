/*
 * Truss 5G UPF & Packet Processing Fabric
 * 3GPP TS 29.244 Information Element (IE) TLV Codec
 */

use "buffered"
use "../truss_core"

class val PfcpRawIe
  """
  Raw Type-Length-Value container for PFCP Information Elements.
  Type: 16-bit big-endian.
  Length: 16-bit big-endian.
  Value: Array[U8] val.
  """
  let ie_type: U16
  let payload: Array[U8] val

  new val create(type': U16, payload': Array[U8] val) =>
    ie_type = type'
    payload = payload'

  fun encode(): Array[U8] val =>
    let wb = Writer
    wb.u16_be(ie_type)
    wb.u16_be(payload.size().u16())
    wb.write(payload)

    let chunks = wb.done()
    let out = recover iso Array[U8] end
    for chunk in (consume chunks).values() do
      match chunk
      | let s: String => out.append(s)
      | let a: Array[U8] val => out.append(a)
      end
    end
    consume out

primitive PfcpIeCodec
  """
  Encoders and decoders for standard 3GPP TS 29.244 Information Elements.
  """

  /* Cause IE (Type 19) */
  fun encode_cause(cause_code: U8): PfcpRawIe =>
    let arr = recover val [as U8: cause_code] end
    PfcpRawIe(IeTypeCause.code(), arr)

  fun decode_cause(ie: PfcpRawIe): U8 ? =>
    if (ie.ie_type != IeTypeCause.code()) or (ie.payload.size() < 1) then error end
    ie.payload(0)?

  /* Recovery Time Stamp IE (Type 96) */
  fun encode_recovery_time_stamp(ntp_sec: U32): PfcpRawIe =>
    let wb = Writer
    wb.u32_be(ntp_sec)
    let chunks = wb.done()
    let out = recover iso Array[U8] end
    for chunk in (consume chunks).values() do
      match chunk
      | let s: String => out.append(s)
      | let a: Array[U8] val => out.append(a)
      end
    end
    PfcpRawIe(IeTypeRecoveryTimeStamp.code(), consume out)

  fun decode_recovery_time_stamp(ie: PfcpRawIe): U32 ? =>
    if (ie.ie_type != IeTypeRecoveryTimeStamp.code()) or (ie.payload.size() < 4) then error end
    let rb = Reader
    rb.append(ie.payload)
    rb.u32_be()?

  /* Node ID IE (Type 60) */
  fun encode_node_id(node_id: NodeIdIe): PfcpRawIe =>
    let wb = Writer
    match node_id.ipv4
    | let ip: Ipv4Address =>
      wb.u8(0) /* IPv4 type */
      wb.u32_be(ip.raw)
    else
      wb.u8(2) /* FQDN type */
      wb.write(node_id.fqdn)
    end
    let chunks = wb.done()
    let out = recover iso Array[U8] end
    for chunk in (consume chunks).values() do
      match chunk
      | let s: String => out.append(s)
      | let a: Array[U8] val => out.append(a)
      end
    end
    PfcpRawIe(IeTypeNodeId.code(), consume out)

  fun decode_node_id(ie: PfcpRawIe): NodeIdIe ? =>
    if (ie.ie_type != IeTypeNodeId.code()) or (ie.payload.size() < 1) then error end
    let rb = Reader
    rb.append(ie.payload)
    let n_type = rb.u8()?
    if n_type == 0 then
      if rb.size() < 4 then error end
      let raw_ip = rb.u32_be()?
      NodeIdIe.from_ipv4(Ipv4Address(raw_ip))
    elseif n_type == 2 then
      let fqdn_bytes = rb.block(rb.size())?
      NodeIdIe.from_fqdn(String.from_iso_array(consume fqdn_bytes))
    else
      error
    end

  /* F-SEID IE (Type 57) */
  fun encode_f_seid(fseid: FSeidIe): PfcpRawIe =>
    let wb = Writer
    wb.u8(0x02) /* Flags: V4 = 1, V6 = 0 */
    wb.u64_be(fseid.seid)
    wb.u32_be(fseid.ipv4.raw)
    let chunks = wb.done()
    let out = recover iso Array[U8] end
    for chunk in (consume chunks).values() do
      match chunk
      | let s: String => out.append(s)
      | let a: Array[U8] val => out.append(a)
      end
    end
    PfcpRawIe(IeTypeFSeid.code(), consume out)

  fun decode_f_seid(ie: PfcpRawIe): FSeidIe ? =>
    if (ie.ie_type != IeTypeFSeid.code()) or (ie.payload.size() < 13) then error end
    let rb = Reader
    rb.append(ie.payload)
    let flags = rb.u8()?
    if (flags and 0x02) == 0 then error end /* Must have IPv4 */
    let seid = rb.u64_be()?
    let ip = rb.u32_be()?
    FSeidIe(seid, Ipv4Address(ip))

  /* F-TEID IE (Type 21) */
  fun encode_f_teid(fteid: FTeidIe): PfcpRawIe =>
    let wb = Writer
    var flags: U8 = 0
    if fteid.choose_id then
      flags = flags or 0x04 /* CH = 1 */
      wb.u8(flags)
    else
      flags = flags or 0x01 /* V4 = 1 */
      wb.u8(flags)
      wb.u32_be(fteid.teid)
      wb.u32_be(fteid.ipv4.raw)
    end
    let chunks = wb.done()
    let out = recover iso Array[U8] end
    for chunk in (consume chunks).values() do
      match chunk
      | let s: String => out.append(s)
      | let a: Array[U8] val => out.append(a)
      end
    end
    PfcpRawIe(IeTypeFTeid.code(), consume out)

  fun decode_f_teid(ie: PfcpRawIe): FTeidIe ? =>
    if (ie.ie_type != IeTypeFTeid.code()) or (ie.payload.size() < 1) then error end
    let rb = Reader
    rb.append(ie.payload)
    let flags = rb.u8()?
    if (flags and 0x04) != 0 then
      FTeidIe(0, Ipv4Address(0), true)
    else
      if rb.size() < 8 then error end
      let teid = rb.u32_be()?
      let ip = rb.u32_be()?
      FTeidIe(teid, Ipv4Address(ip), false)
    end

  /* Gate Status IE (Type 25) */
  fun encode_gate_status(gate: GateStatusIe): PfcpRawIe =>
    var raw: U8 = 0
    if not gate.ul_open then raw = raw or 0x04 end
    if not gate.dl_open then raw = raw or 0x01 end
    let arr = recover val [as U8: raw] end
    PfcpRawIe(IeTypeGateStatus.code(), arr)

  fun decode_gate_status(ie: PfcpRawIe): GateStatusIe ? =>
    if (ie.ie_type != IeTypeGateStatus.code()) or (ie.payload.size() < 1) then error end
    let raw = ie.payload(0)?
    let ul_open = (raw and 0x04) == 0
    let dl_open = (raw and 0x01) == 0
    GateStatusIe(ul_open, dl_open)

  /* Parse a sequence of TLVs from a raw byte buffer */
  fun parse_ie_stream(data: Array[U8] val): Array[PfcpRawIe] val ? =>
    let rb = Reader
    rb.append(data)
    let result = recover iso Array[PfcpRawIe] end

    while rb.size() >= 4 do
      let ie_t = rb.u16_be()?
      let ie_l = rb.u16_be()?
      if rb.size() < ie_l.usize() then error end
      let ie_val: Array[U8] val = recover val rb.block(ie_l.usize())? end
      result.push(PfcpRawIe(ie_t, ie_val))
    end

    consume result
