# Makefile for Truss 5G UPF & Packet Processing Fabric

CC ?= clang
CFLAGS ?= -O3 -Wall -Wextra -pedantic -fPIC -std=c11
AR ?= ar
PONYC ?= ponyc
PONYC_FLAGS ?= --pic -p build -Dopenssl_3.0.x

SRC_DIR := src
BUILD_DIR := build
BIN_DIR := bin

C_SRCS := $(wildcard $(SRC_DIR)/c_fastpath/*.c)
C_OBJS := $(patsubst $(SRC_DIR)/c_fastpath/%.c,$(BUILD_DIR)/c_fastpath/%.o,$(C_SRCS))
FASTPATH_LIB := $(BUILD_DIR)/libfastpath.a

.PHONY: all clean test bench run dirs c_fastpath

all: dirs c_fastpath $(BIN_DIR)/truss $(BIN_DIR)/test_suite

dirs:
	@mkdir -p $(BUILD_DIR)/c_fastpath $(BIN_DIR)

c_fastpath: dirs $(FASTPATH_LIB)

$(BUILD_DIR)/c_fastpath/%.o: $(SRC_DIR)/c_fastpath/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -I$(SRC_DIR)/c_fastpath -c $< -o $@

$(FASTPATH_LIB): $(C_OBJS)
	$(AR) rcs $@ $^

$(BIN_DIR)/truss: c_fastpath $(wildcard $(SRC_DIR)/truss/*.pony) $(wildcard $(SRC_DIR)/truss_core/*.pony) $(wildcard $(SRC_DIR)/gtpu/*.pony) $(wildcard $(SRC_DIR)/pfcp/*.pony)
	@mkdir -p $(BIN_DIR)
	$(PONYC) $(PONYC_FLAGS) -o $(BIN_DIR) $(SRC_DIR)/truss

$(BIN_DIR)/test_suite: c_fastpath $(wildcard $(SRC_DIR)/test_suite/*.pony) $(wildcard $(SRC_DIR)/truss_core/*.pony) $(wildcard $(SRC_DIR)/gtpu/*.pony) $(wildcard $(SRC_DIR)/pfcp/*.pony)
	@mkdir -p $(BIN_DIR)
	$(PONYC) $(PONYC_FLAGS) -o $(BIN_DIR) $(SRC_DIR)/test_suite

test: $(BIN_DIR)/test_suite
	./$(BIN_DIR)/test_suite

$(BIN_DIR)/c_fastpath_bench: c_fastpath benchmarks/c_fastpath_bench.c
	@mkdir -p $(BIN_DIR)
	$(CC) $(CFLAGS) -I$(SRC_DIR)/c_fastpath benchmarks/c_fastpath_bench.c $(FASTPATH_LIB) -o $@

bench-c: $(BIN_DIR)/c_fastpath_bench
	./$(BIN_DIR)/c_fastpath_bench

bench: c_fastpath bench-c
	python3 benchmarks/bench_runner.py

clean:
	rm -rf $(BUILD_DIR) $(BIN_DIR) *.o *.a *.bc
