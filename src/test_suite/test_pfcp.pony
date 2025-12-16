/*
 * Truss 5G UPF & Packet Processing Fabric
 * Test Suite: PFCP Protocol Codec and State Machine
 */

use "pony_test"
use "../truss_core"
use "../pfcp"

class iso _TestPfcpHeaderCodec is UnitTest
  fun name(): String => "pfcp/header_codec"

  fun apply(h: TestHelper) =>
    /* 1. Node-related message: Heartbeat Request (S=0, 8 bytes) */
    let node_hdr = PfcpHeader(PfcpMsgTypeHeartbeatRequest, 20, 1001)
    h.assert_false(node_hdr.has_seid)
    h.assert_eq[USize](8, node_hdr.header_size())

    let node_enc = node_hdr.encode()
    h.assert_eq[USize](8, node_enc.size())

    try
      let decoded_node = PfcpHeader.decode(node_enc)?
      h.assert_false(decoded_node.has_seid)
      h.assert_eq[U8](PfcpMsgTypeHeartbeatRequest.code(), decoded_node.message_type.code())
      h.assert_eq[U16](20, decoded_node.length)
      h.assert_eq[U32](1001, decoded_node.sequence_number)
    else
      h.fail("Failed to decode node-related PFCP header")
    end

    /* 2. Session-related message: Session Establishment Request (S=1, 16 bytes) */
    let session_hdr = PfcpHeader(PfcpMsgTypeSessionEstablishmentRequest, 80, 2002, 0x1122334455667788)
    h.assert_true(session_hdr.has_seid)
    h.assert_eq[USize](16, session_hdr.header_size())

    let session_enc = session_hdr.encode()
    h.assert_eq[USize](16, session_enc.size())

    try
      let decoded_sess = PfcpHeader.decode(session_enc)?
      h.assert_true(decoded_sess.has_seid)
      h.assert_eq[U8](PfcpMsgTypeSessionEstablishmentRequest.code(), decoded_sess.message_type.code())
      h.assert_eq[U16](80, decoded_sess.length)
      h.assert_eq[U32](2002, decoded_sess.sequence_number)
      h.assert_eq[U64](0x1122334455667788, decoded_sess.seid)
    else
      h.fail("Failed to decode session-related PFCP header")
    end

class iso _TestPfcpIeCodec is UnitTest
  fun name(): String => "pfcp/ie_codec"

  fun apply(h: TestHelper) =>
    /* Cause IE */
    let cause_ie = PfcpIeCodec.encode_cause(CauseRequestAccepted.code())
    try
      let decoded_cause = PfcpIeCodec.decode_cause(cause_ie)?
      h.assert_eq[U8](CauseRequestAccepted.code(), decoded_cause)
    else
      h.fail("Failed to decode Cause IE")
    end

    /* Recovery Time Stamp IE */
    let recovery_time: U32 = 0x87654321
    let rts_ie = PfcpIeCodec.encode_recovery_time_stamp(recovery_time)
    try
      let decoded_rts = PfcpIeCodec.decode_recovery_time_stamp(rts_ie)?
      h.assert_eq[U32](recovery_time, decoded_rts)
    else
      h.fail("Failed to decode Recovery Time Stamp IE")
    end

    /* Node ID IE (IPv4) */
    let node_ip = Ipv4Address.from_octets(10, 0, 0, 1)
    let node_id = NodeIdIe.from_ipv4(node_ip)
    let node_id_ie = PfcpIeCodec.encode_node_id(node_id)
    try
      let decoded_node_id = PfcpIeCodec.decode_node_id(node_id_ie)?
      match decoded_node_id.ipv4
      | let ip: Ipv4Address =>
        h.assert_eq[U32](node_ip.raw, ip.raw)
      else
        h.fail("Expected IPv4 Node ID")
      end
    else
      h.fail("Failed to decode Node ID IE")
    end

class iso _TestPfcpMessages is UnitTest
  fun name(): String => "pfcp/messages"

  fun apply(h: TestHelper) =>
    /* Heartbeat Request */
    let hb_req = PfcpHeartbeatReq(555, 1234567)
    let hb_bytes = hb_req.encode()

    /* Verify packet size: 8-byte PFCP header + 8-byte RecoveryTimeStamp IE = 16 bytes */
    h.assert_eq[USize](16, hb_bytes.size())

    try
      let hdr = PfcpHeader.decode(hb_bytes)?
      h.assert_eq[U8](PfcpMsgTypeHeartbeatRequest.code(), hdr.message_type.code())
      h.assert_eq[U32](555, hdr.sequence_number)
    else
      h.fail("Failed to decode Heartbeat Request header")
    end

    /* Heartbeat Response */
    let hb_resp = PfcpHeartbeatResp(555, 1234568)
    let resp_bytes = hb_resp.encode()
    h.assert_eq[USize](16, resp_bytes.size())

class iso _TestPfcpTransactionTracker is UnitTest
  fun name(): String => "pfcp/transaction_tracker"

  fun apply(h: TestHelper) =>
    let tracker = PfcpTransactionTracker(4)
    let dummy_response: Array[U8] val = [as U8: 0x20; 0x02; 0x00; 0x04; 0x00; 0x00; 0x01; 0x00]

    /* First time seeing seq 100: returns None and caches response */
    let res1 = tracker.check_and_record(100, dummy_response)
    h.assert_true(res1 is None)
    h.assert_true(tracker.contains(100))

    /* Duplicate request seq 100: returns cached response */
    let res2 = tracker.check_and_record(100, dummy_response)
    match res2
    | let cached: Array[U8] val =>
      h.assert_eq[USize](dummy_response.size(), cached.size())
    else
      h.fail("Expected cached response on duplicate transaction sequence")
    end
