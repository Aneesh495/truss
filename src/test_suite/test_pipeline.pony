/*
 * Truss 5G UPF & Packet Processing Fabric
 * Test Suite: Datapath Pipeline and Session Rules
 */

use "pony_test"
use "../truss_core"
use "../pfcp"
use "../truss"

class iso _TestSessionRegistry is UnitTest
  fun name(): String => "pipeline/session_registry"

  fun apply(h: TestHelper) =>
    h.long_test(5_000_000_000)
    let metrics = MetricsCollector
    let reg = SessionRegistry(metrics)
    let logger = Logger(h.env.out, LogLevelInfo)
    let sess = SessionActor(1001, 2002, logger, metrics)

    reg.register_session(1001, sess)
    reg.bind_teid(500, sess)

    reg.lookup_by_teid(500, {(found: (SessionActor | None))(h) =>
      match found
      | let s: SessionActor =>
        h.complete(true)
      else
        h.fail("Failed to find session by TEID")
        h.complete(false)
      end
    })

class iso _TestSessionActorRules is UnitTest
  fun name(): String => "pipeline/session_actor_rules"

  fun apply(h: TestHelper) =>
    let ue_ip = Ipv4Address.from_octets(10, 60, 0, 1)
    let pdr = PdrRule(1, 10, AccessInterface, 500, ue_ip, 1, 1, 1)
    let far = FarRule(1, ForwardingActionForw, CoreInterface)

    h.assert_eq[U16](1, pdr.pdr_id)
    h.assert_eq[U32](10, pdr.precedence)
    h.assert_eq[U32](1, far.far_id)

    match pdr.source_interface
    | AccessInterface => h.assert_true(true)
    else
      h.fail("Expected AccessInterface")
    end

    match far.destination_interface
    | CoreInterface => h.assert_true(true)
    else
      h.fail("Expected CoreInterface")
    end
