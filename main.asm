; BFH is a scuffed hexdump written in x86_64 asm
; It takes data from stdin and spits it out to stdout
; usage ./bfh < targetfile

%define BUFFLEN 16

section .bss
    buffer: resb BUFFLEN  ; reserves a buffer for read syscall
               ;012345678

section .data
    numstr: db "00000000:"                                          ; line number
    hexstr: db " 0000 0000 0000 0000 0000 0000 0000 0000 ", 20h     ; hex  string
    chrstr: db "................", 0Ah                              ; ascii chars from hex + \n
    HEXLEN: equ $-numstr                                            ; len of the numstr+hexstr+chrstr for write syscall

    DIGITS: db "0123456789ABCDEF"                                   ; string of chars for substitution

section .text

global _start

_start:
    mov rbp, rsp        ; needed for gdb happiness
    
    xor r10, r10        ; r10 is the overall counter for numstr

READ:
    push r10            ; push r10 to the stack because write syscall can change it
    xor rax, rax        ; x64 linux syscall rax 0, rdi 0, rsi char * buffer, rdx # of chars to read
    xor rdi, rdi        
    mov rsi, buffer
    mov rdx, BUFFLEN
    syscall

    cmp rax, 1          ; if rax > 0 we have read at least one char, if rax == 0 EOF, if rax < 0 error 
    je QUIT             ; if we are at EOF or we get an error we quit
    jb QUIT_WITH_ERROR

    mov r15, rax        ; len of read chars
    xor rdx, rdx        ; we will use dl and rdx to store the values at DIGITS[n] to write into numstr
    mov rsi, hexstr
    inc rsi

    mov rcx, 7               ; writing right to left
LINENUM:                     ; there's probably way better ways to do this
    mov rax, r10             ; overall counter into rax
    and al, 00Fh             ; working with 8 bits, 0 the most significant nibble 
    mov dl, al               ; moving into dl because who knows what's in the rest of rax 
    mov dl, byte [DIGITS + rdx] ; setting dl to DIGITS[dl] 
    mov byte [numstr + rcx], dl ; writing dl to numstr[rcx]
    dec rcx                  ; rcx--
    cmp rcx, 0               ; check if we have finished the space in LINENUM
    jb CONTINUE              
    cmp r10, 0Fh             ; check if we have handled all of r10
    jb CONTINUE
    shr r10, 4               ; if not shift a nibble to right
    jmp LINENUM
    
    
CONTINUE:
    xor rax, rax            ; putting 0 in these registers to avoid any undefined behaviour
    xor rbx, rbx
    xor rcx, rcx
    xor rdx, rdx

SCAN:
    mov al, byte [buffer + rcx]      ; buffer[n] into rax
    cmp al, 20h             ; we check if its value is meaningful as a char in ascii between the range of ' '
    jb HEXDUMP              
    cmp al, 7Eh             ; and '~'
    ja HEXDUMP
    mov byte [chrstr + rcx], al       ; if it is we write the char in chrstr[n] 
    
HEXDUMP:
    mov bl, al                  ; buffer[n] into cl as well (I assume this is faster than mov al, byte [rsi] twice, or push)
    shr al, 4                                           ; most significant nibble in the least significant into al
    and bl, 00Fh                                        ; 0 most significant nibble in cl 
    mov dl, byte [DIGITS + rax]                         ; dl with DIGITS[al] 
    mov byte [rsi], dl                             ; hexstr[n* 3 + 1] = dl 
    inc rsi
    mov dl, byte [DIGITS + rbx]                         ; dl with DIGITS[cl]
    mov byte [rsi], dl                             ; hexstr[n*3 + 2] = dl
    inc rsi
    inc rcx
    mov dl, byte[rsi] 
    cmp dl, 020h
    jne .L1
    inc rsi
    .L1:

    cmp rcx, r15             ; have we handled all 16 chars?
    jne SCAN
    cmp r15, 16
    jb CLEANHEXSTR          
    
    mov rax, 1              ; x64 write syscall to stdout, rax 1, rdi 1, rsi *string, rdx len of str
    mov rdi, rax
    mov rsi, numstr
    mov rdx, HEXLEN
    syscall

    cmp rax, 0
    jb QUIT_WITH_ERROR        ; negative values indicate syscall write error


    xor rax, rax
CLEANNUMSTR:
    mov byte [numstr + rax], 30h ; reset to '0'
CLEANCHARSTR:
    mov byte [chrstr + rax], 2Eh  ; reset to '.'
    inc rax
    cmp rax, 8                ; len(numstr) = 8
    jl CLEANNUMSTR
    cmp rax, 16               ; len(charstr) = 16
    jl CLEANCHARSTR
    
    pop r10                ; retrieve r10 from the stack
    add r10, 16            ; increase it with the operations performed

    jmp READ                ; back to the top!

CLEANHEXSTR:                ; jumped to when the final chunk to print has less than 16 bytes
    lea rcx, [rcx * 2 + rcx]
    mov rax, hexstr
    add rax, rcx
    mov rbx, chrstr
    sub rbx, 2
    .L1:
    mov byte [rax], 20h
    inc rax
    cmp rax, rbx
    jb .L1
    
    mov rax, 1              ; x64 write syscall to stdout, rax 1, rdi 1, rsi *string, rdx len of str
    mov rdi, rax
    mov rsi, numstr
    mov rdx, HEXLEN
    syscall

QUIT:
    mov rax, 60             ; x64 exit syscall, rax 60, rdi 0 (exit with 0 code)
    mov rdi, 0
    syscall

QUIT_WITH_ERROR:
    mov rdi, rax            ; error exit code will be negative (whatever read syscall has spat back)
    mov rax, 60
    syscall
