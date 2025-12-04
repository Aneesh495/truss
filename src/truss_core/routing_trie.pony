/*
 * Truss 5G UPF & Packet Processing Fabric
 * 24-8 Stride LPM Routing Table & Network Instance Mapping
 */

class RoutingTrie
  """
  High-performance Longest Prefix Match (LPM) routing table backed by the
  24-8 stride C fastpath. Guarantees line-rate IPv4 lookup with at most two
  memory accesses.
  """
  var _trie: Pointer[None]

  new iso create() =>
    _trie = @lpm_trie_create()

  fun ref insert(prefix: Ipv4Address, mask_len: U8, nexthop_id: U16): Bool =>
    if _trie.is_null() then return false end
    @lpm_trie_insert(_trie, prefix.raw, mask_len, nexthop_id)

  fun lookup(ip: Ipv4Address): U16 =>
    if _trie.is_null() then return 0xFFFF end
    @lpm_trie_lookup(_trie, ip.raw)

  fun _final() =>
    if not _trie.is_null() then
      @lpm_trie_destroy(_trie)
    end
