/*
 * Truss 5G UPF & Packet Processing Fabric
 * Test Suite: GTP-U Protocol Codec and Encapsulation
 */

use "pony_test"
use "../gtpu"

class iso _TestGtpuHeaderCodec is UnitTest
  fun name(): String => "gtpu/header_codec"

  fun apply(h: TestHelper) =>
    /* Standard 8-byte header without optional fields */
    let flags = GtpuFlags(1, true, false, false, false)
    let hdr = GtpuHeader(flags, GtpuTypeGPdu, 100, 0x12345678)
    h.assert_eq[USize](8, hdr.header_size())

    let enc = hdr.encode()
    h.assert_eq[USize](8, enc.size())

    /* Verify wire bytes */
    try
      /* Byte 0: Flags (Version 1 = 0x20, PT = 0x10 -> 0x30) */
      h.assert_eq[U8](0x30, enc(0)?)
      /* Byte 1: Message Type 255 (G-PDU) */
      h.assert_eq[U8](255, enc(1)?)
      /* Bytes 2-3: Length (100) */
      h.assert_eq[U8](0, enc(2)?)
      h.assert_eq[U8](100, enc(3)?)
      /* Bytes 4-7: TEID (0x12345678) */
      h.assert_eq[U8](0x12, enc(4)?)
      h.assert_eq[U8](0x34, enc(5)?)
      h.assert_eq[U8](0x56, enc(6)?)
      h.assert_eq[U8](0x78, enc(7)?)
    else
      h.fail("Array index out of bounds")
    end

class iso _TestGtpuExtensionCodec is UnitTest
  fun name(): String => "gtpu/extension_codec"

  fun apply(h: TestHelper) =>
    /* TS 38.415 PDU Session Container with QFI=9, RQI=true, Uplink=true */
    let psc = PduSessionContainer(9, true, true)
    h.assert_eq[U8](9, psc.qfi)
    h.assert_true(psc.rqi)
    h.assert_true(psc.is_uplink)

    let ext_hdr = psc.to_extension_header(0)
    h.assert_eq[U8](ExtTypePduSessionContainer.code(), ext_hdr.ext_type)
    h.assert_eq[U8](1, ext_hdr.length_units)

    let enc = ext_hdr.encode()
    /* 1 (length) + 2 (content) + 1 (next) = 4 bytes */
    h.assert_eq[USize](4, enc.size())

    /* Decode back */
    try
      let decoded_psc = PduSessionContainer.decode(ext_hdr)?
      h.assert_eq[U8](9, decoded_psc.qfi)
      h.assert_true(decoded_psc.rqi)
      h.assert_true(decoded_psc.is_uplink)
    else
      h.fail("Failed to decode PDU Session Container")
    end

class iso _TestGtpuPacketRoundtrip is UnitTest
  fun name(): String => "gtpu/packet_roundtrip"

  fun apply(h: TestHelper) =>
    let payload: Array[U8] val = [as U8: 0x45; 0x00; 0x00; 0x28; 0x00; 0x01; 0x00; 0x00
                                         0x40; 0x11; 0x00; 0x00; 0x0A; 0x00; 0x00; 0x01
                                         0x0A; 0x00; 0x00; 0x02]

    /* Create GTP-U packet with extension header (PDU Session Container, QFI 5) */
    let psc = PduSessionContainer(5, false, false)
    let ext = psc.to_extension_header(0)
    let exts = recover val [ext] end

    let flags = GtpuFlags(1, true, true, false, false)
    let hdr = GtpuHeader(flags, GtpuTypeGPdu, 0, 0xAABBCCDD, None, None, ExtTypePduSessionContainer.code())

    let packet = GtpuPacket(hdr, payload, exts)
    let wire = packet.encode()

    /* Decode wire bytes */
    try
      let decoded = GtpuPacket.decode(wire)?
      h.assert_eq[U32](0xAABBCCDD, decoded.header.teid)
      h.assert_eq[U8](GtpuTypeGPdu.code(), decoded.header.message_type.code())
      h.assert_eq[USize](1, decoded.extensions.size())

      let dec_ext = decoded.extensions(0)?
      h.assert_eq[U8](ExtTypePduSessionContainer.code(), dec_ext.ext_type)

      let dec_psc = PduSessionContainer.decode(dec_ext)?
      h.assert_eq[U8](5, dec_psc.qfi)
      h.assert_false(dec_psc.is_uplink)

      h.assert_eq[USize](payload.size(), decoded.payload.size())
      h.assert_eq[U8](0x45, decoded.payload(0)?)
    else
      h.fail("Failed to decode GTP-U packet wire representation")
    end
