bfh: main.o
	ld -o exe main.o

main.o: main.asm
	nasm -f elf64 -g -F dwarf main.asm
