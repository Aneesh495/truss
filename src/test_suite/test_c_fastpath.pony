/*
 * Truss 5G UPF & Packet Processing Fabric
 * Test Suite: C Fastpath Acceleration Layer
 */

use "pony_test"
use "../truss_core"

use @fastpath_gtpu_encapsulate[USize](
  out_buf: Pointer[U8] tag,
  out_capacity: USize,
  src_ip_be: U32,
  dst_ip_be: U32,
  src_port_be: U16,
  dst_port_be: U16,
  teid_be: U32,
  inner_payload: Pointer[U8] tag,
  inner_len: USize)

class iso _TestFastpathChecksum is UnitTest
  fun name(): String => "fastpath/checksum16"

  fun apply(h: TestHelper) =>
    /* RFC 1071 test vector */
    let data: Array[U8] val = [as U8: 0x45; 0x00; 0x00; 0x3c; 0x1c; 0x46; 0x40; 0x00
                                      0x40; 0x06; 0x00; 0x00; 0xac; 0x10; 0x0a; 0x63
                                      0xac; 0x10; 0x0a; 0x0c]
    let csum = FastpathFFI.checksum16(data)
    h.assert_true(csum != 0)

    /* Test incremental checksum update (RFC 1624) */
    let updated = FastpathFFI.checksum_update16(csum, 0x4000, 0x4001)
    h.assert_true(updated != csum)

class iso _TestFastpathCrc32c is UnitTest
  fun name(): String => "fastpath/crc32c"

  fun apply(h: TestHelper) =>
    let empty_arr = recover val Array[U8] end
    h.assert_eq[U32](0, FastpathFFI.crc32c(empty_arr))

    /* "123456789" CRC32c standard test vector is 0xE3069283 */
    let test_bytes: Array[U8] val = [as U8: 0x31; 0x32; 0x33; 0x34; 0x35; 0x36; 0x37; 0x38; 0x39]
    let crc = FastpathFFI.crc32c(test_bytes)
    h.assert_eq[U32](0xE3069283, crc)

class iso _TestFastpathLpmTrie is UnitTest
  fun name(): String => "fastpath/lpm_trie"

  fun apply(h: TestHelper) =>
    let trie = RoutingTrie

    /* Default route 0.0.0.0/0 -> nexthop 1 */
    h.assert_true(trie.insert(Ipv4Address.from_octets(0, 0, 0, 0), 0, 1))

    /* Subnet 192.168.0.0/16 -> nexthop 10 */
    h.assert_true(trie.insert(Ipv4Address.from_octets(192, 168, 0, 0), 16, 10))

    /* Specific subnet 192.168.1.0/24 -> nexthop 20 */
    h.assert_true(trie.insert(Ipv4Address.from_octets(192, 168, 1, 0), 24, 20))

    /* Host route 192.168.1.50/32 -> nexthop 30 */
    h.assert_true(trie.insert(Ipv4Address.from_octets(192, 168, 1, 50), 32, 30))

    /* Test LPM lookup: 8.8.8.8 matches default route /0 */
    h.assert_eq[U16](1, trie.lookup(Ipv4Address.from_octets(8, 8, 8, 8)))

    /* Test LPM lookup: 192.168.2.1 matches /16 */
    h.assert_eq[U16](10, trie.lookup(Ipv4Address.from_octets(192, 168, 2, 1)))

    /* Test LPM lookup: 192.168.1.10 matches /24 */
    h.assert_eq[U16](20, trie.lookup(Ipv4Address.from_octets(192, 168, 1, 10)))

    /* Test LPM lookup: 192.168.1.50 matches /32 exact host route */
    h.assert_eq[U16](30, trie.lookup(Ipv4Address.from_octets(192, 168, 1, 50)))

class iso _TestFastpathGtpuEncap is UnitTest
  fun name(): String => "fastpath/gtpu_encap"

  fun apply(h: TestHelper) =>
    let out_buf = recover iso Array[U8](128) end
    var i: USize = 0
    while i < 128 do
      out_buf.push(0)
      i = i + 1
    end
    let out_val: Array[U8] val = consume out_buf

    let payload: Array[U8] val = [as U8: 0xDE; 0xAD; 0xBE; 0xEF]
    let written = @fastpath_gtpu_encapsulate(
      out_val.cpointer(),
      out_val.size(),
      0x01010101,
      0x02020202,
      2152,
      2152,
      100,
      payload.cpointer(),
      payload.size())

    /* 20 IP + 8 UDP + 8 GTPU + 4 payload = 40 bytes */
    h.assert_eq[USize](40, written)
