/*
 * Truss 5G UPF & Packet Processing Fabric
 * 3GPP TS 29.281 and TS 38.415 GTP-U Extension Headers
 */

use "buffered"

primitive ExtTypeNone
  fun code(): U8 => 0x00
  fun string(): String => "No More Extension Headers"

primitive ExtTypePduSessionContainer
  fun code(): U8 => 0x85
  fun string(): String => "PDU Session Container (TS 38.415)"

primitive ExtTypePdcpPdu
  fun code(): U8 => 0x40
  fun string(): String => "Selected PDCP PDU"

class val GtpuExtensionHeader
  """
  Generic GTP-U extension header container.
  Length is represented in 4-octet units.
  """
  let ext_type: U8
  let length_units: U8
  let content: Array[U8] val
  let next_ext_type: U8

  new val create(
    type': U8,
    len_units': U8,
    content': Array[U8] val,
    next_type': U8 = 0)
  =>
    ext_type = type'
    length_units = len_units'
    content = content'
    next_ext_type = next_type'

  fun encode(): Array[U8] val =>
    let wb = Writer
    wb.u8(length_units)
    wb.write(content)
    wb.u8(next_ext_type)

    let chunks = wb.done()
    let out = recover iso Array[U8] end
    for chunk in (consume chunks).values() do
      match chunk
      | let s: String => out.append(s)
      | let a: Array[U8] val => out.append(a)
      end
    end
    consume out

class val PduSessionContainer
  """
  PDU Session Container according to 3GPP TS 38.415.
  Carries 6-bit QoS Flow Identifier (QFI) and Reflective QoS Indicator (RQI).
  """
  let is_uplink: Bool
  let qfi: U8
  let rqi: Bool

  new val create(qfi': U8, is_ul': Bool = false, rqi': Bool = false) =>
    qfi = qfi' and 0x3F
    is_uplink = is_ul'
    rqi = rqi'

  fun to_extension_header(next_type: U8 = 0): GtpuExtensionHeader =>
    /*
     * PDU Session Container length is 1 unit (4 octets):
     * [0]: Length = 1 unit (4 octets)
     * [1]: PDU Type (4-bit) | Spare (4-bit)
     * [2]: Spare (1-bit) | RQI (1-bit) | QFI (6-bit)
     * [3]: Next Extension Header Type
     */
    let wb = Writer
    let b1: U8 = if is_uplink then 0x10 else 0x00 end
    var b2: U8 = qfi and 0x3F
    if rqi then b2 = b2 or 0x40 end
    wb.u8(b1)
    wb.u8(b2)

    let chunks = wb.done()
    let content = recover iso Array[U8] end
    for chunk in (consume chunks).values() do
      match chunk
      | let s: String => content.append(s)
      | let a: Array[U8] val => content.append(a)
      end
    end

    GtpuExtensionHeader(ExtTypePduSessionContainer.code(), 1, consume content, next_type)

  new val decode(ext: GtpuExtensionHeader)? =>
    if ext.ext_type != ExtTypePduSessionContainer.code() then error end
    if ext.content.size() < 2 then error end
    let b1 = ext.content(0)?
    let b2 = ext.content(1)?
    is_uplink = ((b1 >> 4) and 0x0F) == 1
    rqi = (b2 and 0x40) != 0
    qfi = b2 and 0x3F
