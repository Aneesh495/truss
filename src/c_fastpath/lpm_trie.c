#include "fastpath.h"
#include <stdlib.h>
#include <string.h>

lpm_trie_t* lpm_trie_create(void) {
    lpm_trie_t *trie = (lpm_trie_t *)malloc(sizeof(lpm_trie_t));
    if (!trie) {
        return NULL;
    }

    trie->tbl24 = (uint16_t *)malloc(LPM_TBL24_SIZE * sizeof(uint16_t));
    if (!trie->tbl24) {
        free(trie);
        return NULL;
    }

    trie->max_tbl8_groups = LPM_MAX_TBL8_GROUPS;
    trie->tbl8 = (uint16_t *)malloc(trie->max_tbl8_groups * LPM_TBL8_GROUP_SIZE * sizeof(uint16_t));
    if (!trie->tbl8) {
        free(trie->tbl24);
        free(trie);
        return NULL;
    }

    /* Initialize all tbl24 entries to invalid nexthop */
    for (size_t i = 0; i < LPM_TBL24_SIZE; i++) {
        trie->tbl24[i] = LPM_INVALID_NEXTHOP;
    }

    /* Initialize tbl8 entries */
    for (size_t i = 0; i < (size_t)trie->max_tbl8_groups * LPM_TBL8_GROUP_SIZE; i++) {
        trie->tbl8[i] = LPM_INVALID_NEXTHOP;
    }

    trie->tbl8_groups_used = 0;
    return trie;
}

void lpm_trie_destroy(lpm_trie_t *trie) {
    if (!trie) {
        return;
    }
    if (trie->tbl24) {
        free(trie->tbl24);
        trie->tbl24 = NULL;
    }
    if (trie->tbl8) {
        free(trie->tbl8);
        trie->tbl8 = NULL;
    }
    free(trie);
}

bool lpm_trie_insert(lpm_trie_t *trie, uint32_t ip_be, uint8_t prefix_len, uint16_t nexthop_id) {
    if (!trie || prefix_len > 32 || nexthop_id == LPM_INVALID_NEXTHOP) {
        return false;
    }

    /* IPv4 integer is already structured with MSB = high octet */
    uint32_t ip_h = ip_be;

    if (prefix_len <= 24) {
        /* Route fits in tbl24 */
        uint32_t base_idx = (ip_h >> 8) & 0x00FFFFFF;
        uint32_t count = 1 << (24 - prefix_len);

        for (uint32_t i = 0; i < count; i++) {
            uint32_t idx = base_idx + i;
            if (idx < LPM_TBL24_SIZE) {
                /* If existing entry is a tbl8 pointer, propagate covering route to tbl8 slots */
                uint16_t current = trie->tbl24[idx];
                if (current != LPM_INVALID_NEXTHOP && (current & LPM_FLAG_TBL8) != 0) {
                    uint32_t group_idx = (current & ~LPM_FLAG_TBL8);
                    uint16_t *group = &trie->tbl8[group_idx * LPM_TBL8_GROUP_SIZE];
                    for (uint32_t k = 0; k < LPM_TBL8_GROUP_SIZE; k++) {
                        if (group[k] == LPM_INVALID_NEXTHOP) {
                            group[k] = nexthop_id;
                        }
                    }
                } else {
                    trie->tbl24[idx] = nexthop_id;
                }
            }
        }
        return true;
    } else {
        /* Route requires tbl8 block (prefix_len > 24) */
        uint32_t tbl24_idx = (ip_h >> 8) & 0x00FFFFFF;
        uint16_t current = trie->tbl24[tbl24_idx];
        uint32_t group_idx = 0;

        if (current == LPM_INVALID_NEXTHOP || (current & LPM_FLAG_TBL8) == 0) {
            /* Allocate new tbl8 group */
            if (trie->tbl8_groups_used >= trie->max_tbl8_groups) {
                /* Exceeded max tbl8 capacity */
                return false;
            }
            group_idx = trie->tbl8_groups_used++;
            uint16_t prev_nexthop = current;
            uint16_t *group = &trie->tbl8[group_idx * LPM_TBL8_GROUP_SIZE];

            /* Initialize new group with previous covering route or invalid */
            for (uint32_t k = 0; k < LPM_TBL8_GROUP_SIZE; k++) {
                group[k] = prev_nexthop;
            }

            /* Point tbl24 entry to this new group with tbl8 flag */
            trie->tbl24[tbl24_idx] = (uint16_t)(group_idx | LPM_FLAG_TBL8);
        } else {
            group_idx = (current & ~LPM_FLAG_TBL8);
        }

        /* Fill appropriate slots in tbl8 group */
        uint32_t sub_base = ip_h & 0xFF;
        uint32_t sub_count = 1 << (32 - prefix_len);
        uint16_t *group = &trie->tbl8[group_idx * LPM_TBL8_GROUP_SIZE];

        for (uint32_t i = 0; i < sub_count; i++) {
            uint32_t slot = sub_base + i;
            if (slot < LPM_TBL8_GROUP_SIZE) {
                group[slot] = nexthop_id;
            }
        }
        return true;
    }
}

uint16_t lpm_trie_lookup(const lpm_trie_t *trie, uint32_t ip_be) {
    if (!trie) {
        return LPM_INVALID_NEXTHOP;
    }

    uint32_t ip_h = ip_be;
    uint32_t tbl24_idx = (ip_h >> 8) & 0x00FFFFFF;
    uint16_t val = trie->tbl24[tbl24_idx];

    if (val == LPM_INVALID_NEXTHOP) {
        return LPM_INVALID_NEXTHOP;
    }

    if ((val & LPM_FLAG_TBL8) == 0) {
        return val;
    }

    /* Traversed to tbl8 secondary block */
    uint32_t group_idx = (val & ~LPM_FLAG_TBL8);
    uint32_t tbl8_idx = (group_idx * LPM_TBL8_GROUP_SIZE) + (ip_h & 0xFF);
    return trie->tbl8[tbl8_idx];
}
