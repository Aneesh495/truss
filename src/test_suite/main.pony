/*
 * Truss 5G UPF & Packet Processing Fabric
 * Main Test Runner and Test Suite Registry
 */

use "pony_test"

actor Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  new make() =>
    None

  fun tag tests(test: PonyTest) =>
    /* 1. C Fastpath tests */
    test(_TestFastpathChecksum)
    test(_TestFastpathCrc32c)
    test(_TestFastpathLpmTrie)
    test(_TestFastpathGtpuEncap)

    /* 2. Core Primitives tests */
    test(_TestIpv4Address)
    test(_TestFlow5Tuple)
    test(_TestMonotonicClock)
    test(_TestTokenBucket)
    test(_TestTrtcmMeter)
    test(_TestUsageMeter)
    test(_TestChunkRingBuffer)

    /* 3. GTP-U Protocol tests */
    test(_TestGtpuHeaderCodec)
    test(_TestGtpuExtensionCodec)
    test(_TestGtpuPacketRoundtrip)

    /* 4. PFCP Protocol tests */
    test(_TestPfcpHeaderCodec)
    test(_TestPfcpIeCodec)
    test(_TestPfcpMessages)
    test(_TestPfcpTransactionTracker)

    /* 5. Datapath & State Machine tests */
    test(_TestSessionRegistry)
    test(_TestSessionActorRules)
