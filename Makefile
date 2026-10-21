NASM      ?= nasm
LD        ?= ld
NASMFLAGS := -f elf64 -g -I lib/
BIN       := bin
PROGS     := cat wc hexdump rev

all: $(addprefix $(BIN)/,$(PROGS))

$(BIN):
	mkdir -p $@

$(BIN)/io.o: lib/io.asm lib/io.inc | $(BIN)
	$(NASM) $(NASMFLAGS) -o $@ $<

$(BIN)/%.o: src/%.asm lib/io.inc | $(BIN)
	$(NASM) $(NASMFLAGS) -o $@ $<

$(BIN)/%: $(BIN)/%.o $(BIN)/io.o
	$(LD) -o $@ $^

test: all
	bash tests/run.sh

clean:
	rm -rf $(BIN)

.SECONDARY:
.PHONY: all test clean
