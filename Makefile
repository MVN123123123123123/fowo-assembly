CC = gcc
NASM = nasm
NASM_FLAGS = -f elf64 -g
LDFLAGS = -no-pie

all: build/fowo

build/fowo: build/fowo.o
	$(CC) $(LDFLAGS) build/fowo.o -o build/fowo

build/fowo.o: src/fowo.asm
	$(NASM) $(NASM_FLAGS) src/fowo.asm -o build/fowo.o

clean:
	rm -rf build/*
