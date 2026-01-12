/*
 * Truss 5G UPF & Packet Processing Fabric
 * C Fastpath Micro-Benchmark Suite
 * Measures raw throughput and cycle efficiency of fastpath primitives.
 */

#define _POSIX_C_SOURCE 199309L
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <time.h>
#include "../src/c_fastpath/fastpath.h"

static inline uint64_t get_nanos(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static void bench_checksum16(void) {
    const size_t pkt_size = 1400;
    const uint64_t iterations = 2000000ULL;
    uint8_t *buf = (uint8_t *)malloc(pkt_size);
    for (size_t i = 0; i < pkt_size; i++) {
        buf[i] = (uint8_t)(i & 0xFF);
    }

    uint64_t t0 = get_nanos();
    volatile uint16_t csum = 0;
    for (uint64_t i = 0; i < iterations; i++) {
        csum = fastpath_checksum16(buf, pkt_size);
    }
    (void)csum;
    uint64_t t1 = get_nanos();

    double sec = (double)(t1 - t0) / 1e9;
    double gb = (double)(iterations * pkt_size) / 1e9;
    double gbps = (gb * 8.0) / sec;
    double ns_per_op = (double)(t1 - t0) / (double)iterations;

    printf("[FASTPATH-BENCH] Checksum16 (RFC 1071, 1400B):\n");
    printf("  Iterations:   %llu in %.4f s\n", (unsigned long long)iterations, sec);
    printf("  Throughput:   %.2f Gbps (%.2f GB/s)\n", gbps, gb / sec);
    printf("  Latency:      %.2f ns/packet\n\n", ns_per_op);

    free(buf);
}

static void bench_crc32c(void) {
    const size_t pkt_size = 1400;
    const uint64_t iterations = 2000000ULL;
    uint8_t *buf = (uint8_t *)malloc(pkt_size);
    for (size_t i = 0; i < pkt_size; i++) {
        buf[i] = (uint8_t)((i * 31) & 0xFF);
    }

    uint64_t t0 = get_nanos();
    volatile uint32_t crc = 0;
    for (uint64_t i = 0; i < iterations; i++) {
        crc = fastpath_crc32c(buf, pkt_size);
    }
    (void)crc;
    uint64_t t1 = get_nanos();

    double sec = (double)(t1 - t0) / 1e9;
    double gb = (double)(iterations * pkt_size) / 1e9;
    double gbps = (gb * 8.0) / sec;
    double ns_per_op = (double)(t1 - t0) / (double)iterations;

    printf("[FASTPATH-BENCH] CRC32c Castagnoli (1400B):\n");
    printf("  Iterations:   %llu in %.4f s\n", (unsigned long long)iterations, sec);
    printf("  Throughput:   %.2f Gbps (%.2f GB/s)\n", gbps, gb / sec);
    printf("  Latency:      %.2f ns/packet\n\n", ns_per_op);

    free(buf);
}

static void bench_lpm_trie(void) {
    lpm_trie_t *trie = lpm_trie_create();
    if (!trie) {
        fprintf(stderr, "Failed to create LPM trie\n");
        return;
    }

    /* Seed routing table with realistic routing distribution */
    lpm_trie_insert(trie, 0x00000000, 0, 1);    /* 0.0.0.0/0 default */
    lpm_trie_insert(trie, 0x0A000000, 8, 10);   /* 10.0.0.0/8 */
    lpm_trie_insert(trie, 0x0A3C0000, 16, 20);  /* 10.60.0.0/16 */
    lpm_trie_insert(trie, 0xAC100000, 12, 30);  /* 172.16.0.0/12 */
    lpm_trie_insert(trie, 0xC0A80000, 16, 40);  /* 192.168.0.0/16 */
    lpm_trie_insert(trie, 0xC0A80100, 24, 50);  /* 192.168.1.0/24 */
    lpm_trie_insert(trie, 0xC0A80132, 32, 60);  /* 192.168.1.50/32 */

    const uint64_t iterations = 20000000ULL;
    uint32_t test_ip = 0xC0A80132;

    uint64_t t0 = get_nanos();
    volatile uint16_t nh = 0;
    for (uint64_t i = 0; i < iterations; i++) {
        /* Pseudo-random IPv4 lookup pattern */
        test_ip = test_ip * 1664525ULL + 1013904223ULL;
        nh = lpm_trie_lookup(trie, test_ip);
    }
    (void)nh;
    uint64_t t1 = get_nanos();

    double sec = (double)(t1 - t0) / 1e9;
    double m_lookups_sec = ((double)iterations / 1e6) / sec;
    double ns_per_lookup = (double)(t1 - t0) / (double)iterations;

    printf("[FASTPATH-BENCH] 24-8 LPM Trie Lookups:\n");
    printf("  Iterations:   %llu in %.4f s\n", (unsigned long long)iterations, sec);
    printf("  Rate:         %.2f Million lookups/sec (Mpps)\n", m_lookups_sec);
    printf("  Latency:      %.2f ns/lookup\n\n", ns_per_lookup);

    lpm_trie_destroy(trie);
}

static void bench_gtpu_encap(void) {
    const size_t payload_len = 128;
    const size_t out_cap = 256;
    const uint64_t iterations = 5000000ULL;

    uint8_t *payload = (uint8_t *)malloc(payload_len);
    uint8_t *out_buf = (uint8_t *)malloc(out_cap);
    memset(payload, 0xAA, payload_len);

    uint64_t t0 = get_nanos();
    volatile size_t written = 0;
    for (uint64_t i = 0; i < iterations; i++) {
        written = fastpath_gtpu_encapsulate(
            out_buf,
            out_cap,
            0x0A000001,
            0x0A000002,
            2152,
            2152,
            0x12345678,
            payload,
            payload_len
        );
    }
    (void)written;
    uint64_t t1 = get_nanos();

    double sec = (double)(t1 - t0) / 1e9;
    double m_pkts_sec = ((double)iterations / 1e6) / sec;
    double ns_per_encap = (double)(t1 - t0) / (double)iterations;

    printf("[FASTPATH-BENCH] GTP-U Encapsulation Pipeline (128B inner PDU):\n");
    printf("  Iterations:   %llu in %.4f s\n", (unsigned long long)iterations, sec);
    printf("  Rate:         %.2f Million encapsulations/sec (Mpps)\n", m_pkts_sec);
    printf("  Latency:      %.2f ns/encap\n\n", ns_per_encap);

    free(payload);
    free(out_buf);
}

int main(void) {
    printf("=================================================================\n");
    printf("         TRUSS C FASTPATH ACCELERATION MICRO-BENCHMARKS          \n");
    printf("=================================================================\n\n");

    bench_checksum16();
    bench_crc32c();
    bench_lpm_trie();
    bench_gtpu_encap();

    printf("=================================================================\n");
    printf(" Benchmark execution finished.\n");
    printf("=================================================================\n");
    return 0;
}
