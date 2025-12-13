/*
 * Truss 5G UPF & Packet Processing Fabric
 * Test Suite: Core Networking Primitives & Metering
 */

use "pony_test"
use "../truss_core"

class iso _TestIpv4Address is UnitTest
  fun name(): String => "core/ipv4_address"

  fun apply(h: TestHelper) =>
    /* Octet construction and stringification */
    let ip = Ipv4Address.from_octets(192, 168, 1, 100)
    h.assert_eq[U8](192, ip.octet1())
    h.assert_eq[U8](168, ip.octet2())
    h.assert_eq[U8](1, ip.octet3())
    h.assert_eq[U8](100, ip.octet4())
    h.assert_eq[String]("192.168.1.100", ip.string())

    /* Parsing string */
    try
      let parsed = Ipv4Address.parse("10.20.30.40")?
      h.assert_eq[U8](10, parsed.octet1())
      h.assert_eq[U8](20, parsed.octet2())
      h.assert_eq[U8](30, parsed.octet3())
      h.assert_eq[U8](40, parsed.octet4())
    else
      h.fail("Failed to parse valid IPv4 string")
    end

    /* Prefix matching */
    let prefix = Ipv4Address.from_octets(10, 0, 0, 0)
    let candidate1 = Ipv4Address.from_octets(10, 24, 100, 1)
    let candidate2 = Ipv4Address.from_octets(11, 0, 0, 1)
    h.assert_true(candidate1.matches_prefix(prefix, 8))
    h.assert_false(candidate2.matches_prefix(prefix, 8))

class iso _TestFlow5Tuple is UnitTest
  fun name(): String => "core/flow_5tuple"

  fun apply(h: TestHelper) =>
    let src_ip = Ipv4Address.from_octets(10, 0, 0, 1)
    let dst_ip = Ipv4Address.from_octets(10, 0, 0, 2)
    let flow = Flow5Tuple(6, src_ip, dst_ip, 1024, 5000, 80, 80)

    /* Positive match within port and IP ranges */
    h.assert_true(flow.matches(6, src_ip, dst_ip, 2048, 80))

    /* Mismatched protocol */
    h.assert_false(flow.matches(17, src_ip, dst_ip, 2048, 80))

    /* Mismatched port */
    h.assert_false(flow.matches(6, src_ip, dst_ip, 999, 80))

    /* Wildcard flow */
    let any_ip = Ipv4Address.from_octets(0, 0, 0, 0)
    let wildcard_flow = Flow5Tuple(0, any_ip, any_ip)
    h.assert_true(wildcard_flow.matches(17, src_ip, dst_ip, 53, 53))

class iso _TestMonotonicClock is UnitTest
  fun name(): String => "core/monotonic_clock"

  fun apply(h: TestHelper) =>
    let t1 = MonotonicClock.nanos()
    h.assert_true(t1 > 0)
    let t2 = MonotonicClock.nanos()
    h.assert_true(t2 >= t1)

    let m1 = MonotonicClock.millis()
    h.assert_true(m1 > 0)

    let s1 = MonotonicClock.seconds()
    h.assert_true(s1 > 0)

class iso _TestTokenBucket is UnitTest
  fun name(): String => "core/token_bucket"

  fun apply(h: TestHelper) =>
    /* 10 MB/s = 10,000,000 bytes/sec, burst 10,000 bytes */
    let rate_bps: U64 = 10_000_000
    let burst_bytes: U64 = 10_000
    let t0: U64 = 1_000_000_000

    let bucket = TokenBucket(rate_bps, burst_bytes, t0)
    h.assert_eq[U64](burst_bytes, bucket.available_tokens())

    /* Consume 4,000 bytes */
    h.assert_true(bucket.try_consume(4000, t0))
    h.assert_eq[U64](6000, bucket.available_tokens())

    /* Consume 6,000 bytes */
    h.assert_true(bucket.try_consume(6000, t0))
    h.assert_eq[U64](0, bucket.available_tokens())

    /* Attempt to consume 1 byte without advance in time should fail */
    h.assert_false(bucket.try_consume(1, t0))

    /* Advance time by 1 ms (1_000_000 ns). At 10 MB/s, 1 ms generates 10,000 tokens */
    let t1 = t0 + 1_000_000
    h.assert_true(bucket.try_consume(5000, t1))

class iso _TestTrtcmMeter is UnitTest
  fun name(): String => "core/trtcm_meter"

  fun apply(h: TestHelper) =>
    /* PIR = 20 MB/s, PBS = 10,000 bytes, CIR = 10 MB/s, CBS = 5,000 bytes */
    let pir: U64 = 20_000_000
    let pbs: U64 = 10_000
    let cir: U64 = 10_000_000
    let cbs: U64 = 5_000
    let t0: U64 = 1_000_000_000

    let meter = TrtcmMeter(pir, pbs, cir, cbs)

    /* Small packet within CBS should be GREEN */
    let c1 = meter.mark(1500, t0)
    match c1
    | ColorGreen => h.assert_true(true)
    else
      h.fail("Expected ColorGreen")
    end

    /* Another 1500 bytes -> 3000 bytes consumed, still <= CBS (5000), GREEN */
    let c2 = meter.mark(1500, t0)
    match c2
    | ColorGreen => h.assert_true(true)
    else
      h.fail("Expected ColorGreen")
    end

    /* 3000 bytes more -> total 6000 > CBS (5000), but <= PBS (10000), YELLOW */
    let c3 = meter.mark(3000, t0)
    match c3
    | ColorYellow => h.assert_true(true)
    else
      h.fail("Expected ColorYellow")
    end

    /* 5000 bytes more -> total 11000 > PBS (10000), RED */
    let c4 = meter.mark(5000, t0)
    match c4
    | ColorRed => h.assert_true(true)
    else
      h.fail("Expected ColorRed")
    end

class iso _TestUsageMeter is UnitTest
  fun name(): String => "core/usage_meter"

  fun apply(h: TestHelper) =>
    let urr_id: U32 = 42
    let vol_thresh: U64 = 5000
    let time_thresh_sec: U64 = 60

    let meter = UsageMeter(urr_id, vol_thresh, time_thresh_sec)

    /* Record 2000 bytes uplink -> threshold not reached (returns None) */
    let trig1 = meter.record_uplink(2000)
    h.assert_true(trig1 is None)

    /* Record 3500 bytes uplink -> reaches 5500 >= 5000 bytes threshold */
    let trig2 = meter.record_uplink(3500)
    match trig2
    | let rep: UsageReport =>
      h.assert_eq[U32](urr_id, rep.urr_id)
      h.assert_eq[U64](5500, rep.volume.total_bytes)
      h.assert_eq[U64](5500, rep.volume.uplink_bytes)
      h.assert_eq[U64](0, rep.volume.downlink_bytes)
    else
      h.fail("Expected UsageReport trigger")
    end

    /* Next packet under threshold returns None again */
    let trig3 = meter.record_downlink(1000)
    h.assert_true(trig3 is None)

    /* Final report */
    let final_rep = meter.generate_final_report()
    h.assert_eq[U64](6500, final_rep.volume.total_bytes)
    h.assert_eq[U64](5500, final_rep.volume.uplink_bytes)
    h.assert_eq[U64](1000, final_rep.volume.downlink_bytes)

class iso _TestChunkRingBuffer is UnitTest
  fun name(): String => "core/chunk_ring_buffer"

  fun apply(h: TestHelper) =>
    let ring = ChunkRingBuffer(4)
    h.assert_true(ring.is_empty())
    h.assert_eq[USize](0, ring.count())

    let chunk1: Array[U8] val = [as U8: 1; 2; 3]
    let chunk2: Array[U8] val = [as U8: 4; 5; 6]
    let chunk3: Array[U8] val = [as U8: 7; 8; 9]
    let chunk4: Array[U8] val = [as U8: 10; 11; 12]

    h.assert_true(ring.enqueue(chunk1, 100))
    h.assert_true(ring.enqueue(chunk2, 200))
    h.assert_true(ring.enqueue(chunk3, 300))
    h.assert_true(ring.enqueue(chunk4, 400))

    h.assert_eq[USize](4, ring.count())

    /* Enqueue when full will drop oldest (chunk1) and keep capacity 4 */
    let chunk5: Array[U8] val = [as U8: 13; 14; 15]
    h.assert_true(ring.enqueue(chunk5, 500))
    h.assert_eq[USize](4, ring.count())
    h.assert_eq[U64](1, ring.dropped_overflow())

    /* Dequeue FIFO: first out should now be chunk2 because chunk1 was evicted */
    match ring.dequeue()
    | let p: BufferedPacket =>
      try
        h.assert_eq[U8](4, p.data(0)?)
      else
        h.fail("Array indexing failed")
      end
    else
      h.fail("Expected dequeued packet")
    end
