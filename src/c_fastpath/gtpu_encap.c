#include "fastpath.h"
#include <string.h>

#define IPV4_HEADER_LEN 20
#define UDP_HEADER_LEN 8
#define GTPU_HEADER_LEN 8
#define TOTAL_OUTER_HEADER_LEN (IPV4_HEADER_LEN + UDP_HEADER_LEN + GTPU_HEADER_LEN)

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
) {
    if (!out_buffer || !inner_payload) {
        return 0;
    }

    size_t total_len = TOTAL_OUTER_HEADER_LEN + inner_len;
    if (out_capacity < total_len || total_len > 65535) {
        return 0;
    }

    /* 1. Construct Outer IPv4 Header (20 bytes) */
    uint16_t ip_total_len = (uint16_t)total_len;
    out_buffer[0] = 0x45; /* Version 4, IHL 5 (20 bytes) */
    out_buffer[1] = 0x00; /* DSCP 0, ECN 0 */
    out_buffer[2] = (uint8_t)(ip_total_len >> 8);
    out_buffer[3] = (uint8_t)(ip_total_len & 0xFF);
    out_buffer[4] = 0x00; /* Identification */
    out_buffer[5] = 0x00;
    out_buffer[6] = 0x40; /* Flags: Don't Fragment (DF = 1) */
    out_buffer[7] = 0x00; /* Fragment Offset = 0 */
    out_buffer[8] = 64;   /* Time to Live (TTL) */
    out_buffer[9] = 17;   /* Protocol: UDP (17) */
    out_buffer[10] = 0x00; /* Checksum placeholder */
    out_buffer[11] = 0x00;
    memcpy(&out_buffer[12], &src_ip_be, 4);
    memcpy(&out_buffer[16], &dst_ip_be, 4);

    /* Compute IPv4 header checksum over the first 20 bytes */
    uint16_t ip_csum = fastpath_checksum16(out_buffer, IPV4_HEADER_LEN);
    out_buffer[10] = (uint8_t)(ip_csum & 0xFF);
    out_buffer[11] = (uint8_t)(ip_csum >> 8);

    /* 2. Construct Outer UDP Header (8 bytes) */
    uint16_t udp_len = (uint16_t)(UDP_HEADER_LEN + GTPU_HEADER_LEN + inner_len);
    memcpy(&out_buffer[20], &src_port_be, 2);
    memcpy(&out_buffer[22], &dst_port_be, 2);
    out_buffer[24] = (uint8_t)(udp_len >> 8);
    out_buffer[25] = (uint8_t)(udp_len & 0xFF);
    out_buffer[26] = 0x00; /* UDP checksum optional in IPv4 (set 0) */
    out_buffer[27] = 0x00;

    /* 3. Construct GTP-U Header (8 bytes) */
    /* Flags: Version=1 (001), Protocol Type=1 (1), Reserved=0, E=0, S=0, PN=0 -> 0x30 */
    out_buffer[28] = 0x30;
    out_buffer[29] = 255;  /* Message Type: 255 = G-PDU user data */
    uint16_t gtpu_payload_len = (uint16_t)inner_len;
    out_buffer[30] = (uint8_t)(gtpu_payload_len >> 8);
    out_buffer[31] = (uint8_t)(gtpu_payload_len & 0xFF);
    memcpy(&out_buffer[32], &teid_be, 4);

    /* 4. Copy Inner Payload */
    memcpy(&out_buffer[TOTAL_OUTER_HEADER_LEN], inner_payload, inner_len);

    return total_len;
}
