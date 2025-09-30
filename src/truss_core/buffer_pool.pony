/*
 * Truss 5G UPF & Packet Processing Fabric
 * Chunk Ring Buffer & Memory Pool for Paging / Jitter Buffering
 */

use "collections"

class BufferedPacket
  let data: Array[U8] val
  let timestamp_ns: U64

  new create(d: Array[U8] val, ts: U64) =>
    data = d
    timestamp_ns = ts

class ChunkRingBuffer
  """
  Fixed-capacity ring buffer holding packets for an idle or paging UE session.
  Avoids unbounded memory growth by discarding oldest packets on overflow.
  """
  let _capacity: USize
  let _slots: Array[(BufferedPacket | None)]
  var _head: USize = 0
  var _tail: USize = 0
  var _count: USize = 0
  var _dropped_overflow: U64 = 0

  new create(capacity': USize = 64) =>
    _capacity = capacity'.max(4)
    _slots = Array[(BufferedPacket | None)](_capacity)
    var i: USize = 0
    while i < _capacity do
      _slots.push(None)
      i = i + 1
    end

  fun ref enqueue(packet_data: Array[U8] val, now_ns: U64): Bool =>
    let pkt = BufferedPacket(packet_data, now_ns)
    if _count == _capacity then
      /* Ring buffer is full: overwrite oldest packet at tail */
      _tail = (_tail + 1) % _capacity
      _dropped_overflow = _dropped_overflow + 1
      _count = _count - 1
    end

    try
      _slots(_head)? = pkt
      _head = (_head + 1) % _capacity
      _count = _count + 1
      true
    else
      false
    end

  fun ref dequeue(): (BufferedPacket | None) =>
    if _count == 0 then
      return None
    end

    try
      let item = _slots(_tail)?
      _slots(_tail)? = None
      _tail = (_tail + 1) % _capacity
      _count = _count - 1
      item
    else
      None
    end

  fun ref drain(): Array[Array[U8] val] iso^ =>
    let result = recover iso Array[Array[U8] val](_count) end
    while _count > 0 do
      match dequeue()
      | let p: BufferedPacket => result.push(p.data)
      end
    end
    consume result

  fun count(): USize => _count
  fun capacity(): USize => _capacity
  fun dropped_overflow(): U64 => _dropped_overflow
  fun is_empty(): Bool => _count == 0
