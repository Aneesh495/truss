/*
 * Truss 5G UPF & Packet Processing Fabric
 * Foreign Function Interface (FFI) bindings to C fastpath
 */

use "path:../../build"
use "lib:fastpath"

use @fastpath_checksum16[U16](data: Pointer[U8] tag, len: USize)
use @fastpath_checksum_update16[U16](old_csum: U16, old_val: U16, new_val: U16)
use @fastpath_crc32c[U32](data: Pointer[U8] tag, len: USize)
use @lpm_trie_create[Pointer[None]]()
use @lpm_trie_destroy[None](trie: Pointer[None])
use @lpm_trie_insert[Bool](trie: Pointer[None], ip_be: U32, prefix_len: U8, nexthop_id: U16)
use @lpm_trie_lookup[U16](trie: Pointer[None], ip_be: U32)
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
use @fastpath_token_bucket_consume[Bool](
  current_tokens: Pointer[U64],
  last_refill_ns: Pointer[U64],
  now_ns: U64,
  rate_bytes_per_sec: U64,
  burst_bytes: U64,
  requested_bytes: U64)

primitive FastpathFFI
  """
  Safe wrapper around C fastpath primitives.
  """
  fun checksum16(data: Array[U8] box): U16 =>
    if data.size() == 0 then return 0 end
    @fastpath_checksum16(data.cpointer(), data.size())

  fun checksum_update16(old_csum: U16, old_val: U16, new_val: U16): U16 =>
    @fastpath_checksum_update16(old_csum, old_val, new_val)

  fun crc32c(data: Array[U8] box): U32 =>
    if data.size() == 0 then return 0 end
    @fastpath_crc32c(data.cpointer(), data.size())
