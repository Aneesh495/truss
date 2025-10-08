/*
 * Truss 5G UPF & Packet Processing Fabric
 * GTP-U Packet Parser, Encoder, and Validator
 */

use "buffered"

class val GtpuPacket
  """
  Represents a complete GTP-U packet with header, optional extensions,
  and user plane payload.
  """
  let header: GtpuHeader
  let extensions: Array[GtpuExtensionHeader] val
  let payload: Array[U8] val

  new val create(
    hdr': GtpuHeader,
    payload': Array[U8] val,
    exts': Array[GtpuExtensionHeader] val = recover Array[GtpuExtensionHeader] end)
  =>
    header = hdr'
    payload = payload'
    extensions = exts'

  fun encode(): Array[U8] val =>
    let wb = Writer

    /* Compute total payload length for header */
    var ext_bytes: USize = 0
    if header.flags.has_optional_fields() then
      /* 4 octets for seq/npdu/next_ext */
      ext_bytes = ext_bytes + 4
      for ext in extensions.values() do
        ext_bytes = ext_bytes + (ext.length_units.usize() * 4)
      end
    end

    let total_gtpu_len: U16 = (ext_bytes + payload.size()).u16()

    /* Encode header */
    wb.u8(header.flags.raw)
    wb.u8(header.message_type.code())
    wb.u16_be(total_gtpu_len)
    wb.u32_be(header.teid)

    if header.flags.has_optional_fields() then
      let s = match header.sequence_number | let sn: U16 => sn else 0 end
      let p = match header.npdu_number | let pn: U8 => pn else 0 end
      let first_ext_type = if extensions.size() > 0 then
        try extensions(0)?.ext_type else 0 end
      else
        match header.next_extension_type | let ne: U8 => ne else 0 end
      end

      wb.u16_be(s)
      wb.u8(p)
      wb.u8(first_ext_type)

      /* Encode extension headers */
      var i: USize = 0
      while i < extensions.size() do
        try
          let ext = extensions(i)?
          let next_t: U8 = if (i + 1) < extensions.size() then
            extensions(i + 1)?.ext_type
          else
            0
          end
          wb.u8(ext.length_units)
          wb.write(ext.content)
          wb.u8(next_t)
        end
        i = i + 1
      end
    end

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

  new val decode(data: Array[U8] val)? =>
    if data.size() < 8 then error end

    let rb = Reader
    rb.append(data)

    let flags_raw = rb.u8()?
    let flags = GtpuFlags.from_raw(flags_raw)
    if flags.version() != 1 then error end

    let msg_type_code = rb.u8()?
    let msg_type = GtpuMessageTypeCodec.from_code(msg_type_code)?
    let len_field = rb.u16_be()?
    let teid = rb.u32_be()?

    var seq: (U16 | None) = None
    var npdu: (U8 | None) = None
    var next_ext: (U8 | None) = None
    let exts = recover iso Array[GtpuExtensionHeader] end

    var bytes_read_after_teid: USize = 0

    if flags.has_optional_fields() then
      if rb.size() < 4 then error end
      seq = rb.u16_be()?
      npdu = rb.u8()?
      let first_ext = rb.u8()?
      next_ext = first_ext
      bytes_read_after_teid = 4

      var current_ext_type = first_ext
      while (current_ext_type != 0) and (rb.size() >= 4) do
        let len_units = rb.u8()?
        let total_ext_bytes = len_units.usize() * 4
        if total_ext_bytes < 4 then error end
        if rb.size() < (total_ext_bytes - 1) then error end

        let content_len = total_ext_bytes - 2
        let content_bytes: Array[U8] val = recover val rb.block(content_len)? end
        let next_type = rb.u8()?

        exts.push(GtpuExtensionHeader(current_ext_type, len_units, content_bytes, next_type))
        bytes_read_after_teid = bytes_read_after_teid + total_ext_bytes
        current_ext_type = next_type
      end
    end

    let expected_payload_len = len_field.usize() - bytes_read_after_teid
    if rb.size() < expected_payload_len then error end
    let payload_bytes: Array[U8] val = recover val rb.block(expected_payload_len)? end

    header = GtpuHeader(flags, msg_type, len_field, teid, seq, npdu, next_ext)
    extensions = consume exts
    payload = payload_bytes
