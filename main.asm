%define BUFFLEN 16

section .bss
    buffer: resb BUFFLEN

section .data
    hexstr: db "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00", 10
    HEXLEN: equ $-hexstr

    DIGITS: db "0123456789ABCDEF"

section .text

global _start

_start:
    mov rbp, rsp

READ:
    xor rax, rax
    xor rdi, rdi
    mov rsi, buffer
    mov rdx, BUFFLEN
    syscall
    
    cmp rax, 1
    jb QUIT

    mov r15, rax        ; len of read chars
    mov rsi, buffer     ; *buffer[0]
    mov rdi, hexstr     ; *hexstr[0]
    xor r8, r8
    mov rbx, DIGITS 
    xor rcx, rcx
    xor rax, rax

SCAN:
    mov al, byte [rsi]
    mov cl, al
    shr al, 4 
    shl cl, 4
    shr cl, 4
    add rbx, rax
    mov dl, byte [rbx]
    mov byte [rdi], dl 
    inc rdi
    sub rbx, rax
    add rbx, rcx
    mov dl, byte [rbx]
    mov byte [rdi], dl
    sub rbx, rcx
    inc rdi
    inc rdi
    inc rsi

   ; sub rbx, rax
   ; add rbx, rcx

   inc r8
   cmp r8, r15
   jne SCAN
    
   mov rax, 1
   mov rdi, rax
   mov rsi, hexstr
   mov rdx, HEXLEN
   syscall
    
   jmp READ

QUIT:
    mov rax, 60
    mov rbx, 0
    syscall
