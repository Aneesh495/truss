#include "fastpath.h"

bool fastpath_token_bucket_consume(
    uint64_t *current_tokens,
    uint64_t *last_refill_ns,
    uint64_t now_ns,
    uint64_t rate_bytes_per_sec,
    uint64_t burst_bytes,
    uint64_t requested_bytes
) {
    if (!current_tokens || !last_refill_ns) {
        return false;
    }

    /* Refill calculation */
    if (now_ns > *last_refill_ns) {
        uint64_t elapsed_ns = now_ns - *last_refill_ns;
        /* Calculate tokens to add: elapsed_ns * rate / 1e9 */
        uint64_t tokens_to_add = (uint64_t)(((double)elapsed_ns * (double)rate_bytes_per_sec) / 1000000000.0);
        if (tokens_to_add > 0) {
            uint64_t updated = *current_tokens + tokens_to_add;
            if (updated > burst_bytes) {
                updated = burst_bytes;
            }
            *current_tokens = updated;
            *last_refill_ns = now_ns;
        }
    }

    /* Check consumption */
    if (*current_tokens >= requested_bytes) {
        *current_tokens -= requested_bytes;
        return true;
    }

    return false;
}
