#ifndef TRUSS_FASTPATH_H
#define TRUSS_FASTPATH_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Internet Checksum (RFC 1071)
 * Computes standard 16-bit one's complement checksum over packet buffers.
 */
uint16_t fastpath_checksum16(const uint8_t *data, size_t len);

/*
 * Incremental Checksum Update (RFC 1624)
 * Updates checksum when 16-bit field changes from old_val to new_val.
 */
uint16_t fastpath_checksum_update16(uint16_t old_csum, uint16_t old_val, uint16_t new_val);

/*
 * CRC32c (Castagnoli) Cyclic Redundancy Check
 * Uses polynomial 0x82F63B78 for packet integrity and flow hashing.
 */
uint32_t fastpath_crc32c(const uint8_t *data, size_t len);

/*
 * 24-8 Stride LPM Routing Trie Structure (DIR-24-8 Algorithm)
 * Enables line-rate longest-prefix-match lookup for IPv4 destinations.
 */
#define LPM_TBL24_SIZE (1 << 24)
#define LPM_TBL8_GROUP_SIZE 256
#define LPM_MAX_TBL8_GROUPS 256
#define LPM_INVALID_NEXTHOP 0xFFFF
#define LPM_FLAG_TBL8 0x8000

typedef struct {
    uint16_t *tbl24;
    uint16_t *tbl8;
    uint32_t tbl8_groups_used;
    uint32_t max_tbl8_groups;
} lpm_trie_t;

/*
 * Allocate and initialize a 24-8 LPM routing table.
 */
lpm_trie_t* lpm_trie_create(void);

/*
 * Free all memory associated with the LPM trie.
 */
void lpm_trie_destroy(lpm_trie_t *trie);

/*
 * Insert an IPv4 prefix route (address and netmask prefix length 0-32).
 * Returns true on success, false if capacity exceeded or invalid arguments.
 */
bool lpm_trie_insert(lpm_trie_t *trie, uint32_t ip_be, uint8_t prefix_len, uint16_t nexthop_id);

/*
 * Lookup next-hop ID for an IPv4 address (big-endian).
 * Returns matching nexthop_id or LPM_INVALID_NEXTHOP if no match.
 */
uint16_t lpm_trie_lookup(const lpm_trie_t *trie, uint32_t ip_be);

/*
 * Fast GTP-U / UDP / IPv4 Encapsulation Helper
 * Writes outer IPv4 header (20 bytes), outer UDP header (8 bytes), and
 * outer GTP-U header (8 bytes) into out_buffer (at least 36 bytes),
 * followed by copying the payload.
 * Returns total written length in bytes, or 0 on buffer underflow.
 */
size_t fastpath_gtpu_encapsulate(
    uint8_t *out_buffer,
    size_t out_capacity,
    uint32_t src_ip_be,
    uint32_t dst_ip_be,
    uint16_t src_port_be,
    uint16_t dst_port_be,
    uint32_t teid_be,
    const uint8_t *inner_payload,
    size_t inner_len
);

/*
 * Fast Token Bucket Limiter Helper
 * Refills tokens based on elapsed nanoseconds and consumes if tokens available.
 * Returns true if permitted, false if rate limited.
 */
bool fastpath_token_bucket_consume(
    uint64_t *current_tokens,
    uint64_t *last_refill_ns,
    uint64_t now_ns,
    uint64_t rate_bytes_per_sec,
    uint64_t burst_bytes,
    uint64_t requested_bytes
);

#ifdef __cplusplus
}
#endif

#endif /* TRUSS_FASTPATH_H */
