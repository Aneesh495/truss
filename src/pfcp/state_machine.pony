/*
 * Truss 5G UPF & Packet Processing Fabric
 * PFCP Association State Machine and Idempotent Transaction Cache
 */

use "collections"
use "../truss_core"

primitive AssocStateDown
  fun string(): String => "DOWN"

primitive AssocStateEstablished
  fun string(): String => "ESTABLISHED"

primitive AssocStateGracefulRelease
  fun string(): String => "GRACEFUL_RELEASE"

type AssociationState is
  ( AssocStateDown
  | AssocStateEstablished
  | AssocStateGracefulRelease )

class PfcpTransactionTracker
  """
  Maintains a ring cache of recent PFCP transactions by sequence number.
  Ensures idempotent response replay when peer SMF retransmits requests
  over lossy UDP networks.
  """
  let _capacity: USize
  let _seen_seqs: Map[U32, Array[U8] val]

  new create(capacity': USize = 256) =>
    _capacity = capacity'
    _seen_seqs = Map[U32, Array[U8] val](_capacity)

  fun ref check_and_record(seq: U32, response: Array[U8] val): (Array[U8] val | None) =>
    try
      /* Duplicate request detected: return cached response */
      _seen_seqs(seq)?
    else
      if _seen_seqs.size() >= _capacity then
        /* Simple eviction: clear oldest entries if capacity reached */
        _seen_seqs.clear()
      end
      _seen_seqs(seq) = response
      None
    end

  fun contains(seq: U32): Bool =>
    _seen_seqs.contains(seq)
