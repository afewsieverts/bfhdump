; BFH is a scuffed hexdump written in x86_64 asm
; It takes data from stdin and spits it out to stdout
; usage ./bfh < targetfile

%define BUFFLEN 16

section .bss
    buffer: resb BUFFLEN  ; reserves a buffer for read syscall

section .data
    numstr: db "00000000:"                                            ; line number
    hexstr: db " 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00   "  ; hex  string
    chrstr: db "................", 10                                 ; ascii chars from hex + \n
    HEXLEN: equ $-numstr                                              ; len of the numstr+hexstr+chrstr for write syscall

    DIGITS: db "0123456789ABCDEF"                                     ; string of chars for substitution

section .text

global _start

_start:
    mov rbp, rsp        ; needed for gdb happiness
    
    xor r10, r10        ; r10 is the overall counter for numstr

READ:
    push r10            ; push r10 to the stack because read and write syscall can change it
    xor rax, rax        ; x64 linux syscall rax 0, rdi 0, rsi char * buffer, rdx # of chars to read
    xor rdi, rdi        
    mov rsi, buffer
    mov rdx, BUFFLEN
    syscall

    cmp rax, 1          ; if rax > 0 we have read at least one char, if rax == 0 EOF, if rax < 0 error 
    je QUIT             ; if we are at EOF or we get an error we quit
    jb QUIT_WITH_ERROR

    mov r15, rax        ; len of read chars
    mov rsi, buffer     ; *buffer
    mov rdi, hexstr     ; *hexstr
    inc rdi             ; buffer[1] as [0] is ' ' for readability
    xor r8, r8          ; 0 in r8 as we use it as a counter for buffer
    mov rbx, DIGITS     ; *DIGITS
    mov r9, chrstr      ; *chrstr
    mov r11, numstr     ; *numstr
    xor rcx, rcx        ; rcx as a counter for numstr, at the moment we handle a max of 0xFFFFFFFF lines
    xor rdx, rdx        ; we will use dl and rdx to store the values at DIGITS[n] to write into numstr
   
    mov rcx, 7               ; writing left to right
LINENUM:                     ; there's probably way better ways to do this
    mov rax, r10             ; overall counter into rax
    and al, 00Fh             ; working with 8 bits, 0 the most significant nibble 
    mov dl, al               ; moving into dl because who knows what's in the rest of rax 
    mov dl, byte [rbx + rdx] ; setting dl to DIGITS[dl] 
    mov byte [r11 + rcx], dl ; writing dl to numstr[rcx]
    dec rcx                  ; rcx--
    cmp rcx, 0               ; check if we have finished the space in LINENUM
    jb CONTINUE              
    cmp r10, 0Fh             ; check if we have handled all of r10
    jb CONTINUE
    shr r10, 4               ; if not shift a nibble to right
    jmp LINENUM
    
    
CONTINUE:
    xor rax, rax            ; putting 0 in these registers to avoid any undefined behaviour
    xor rdx, rdx
    xor rcx, rcx

SCAN:
    mov al, byte [rsi]      ; buffer[n] into rax
    cmp al, 20h             ; we check if its value is meaningful as a char in ascii between the range of ' '
    jb HEXDUMP              
    cmp al, 7Eh             ; and '~'
    ja HEXDUMP
    mov byte [r9], al       ; if it is we write the char in chrstr[n] 
    
HEXDUMP:
    mov cl, al               ; buffer[n] copied into cl as well (I assume this is faster than mov al, byte [rsi] twice, or push)
    shr al, 4                ; most significant nibble in the least significant into al
    and cl, 00Fh             ; 0 most significant nibble in cl 
    mov dl, byte [rbx + rax] ; dl with DIGITS[al] 
    mov byte [rdi], dl       ; hexstr[n] = dl 
    inc rdi                  ; n + 1
    mov dl, byte [rbx + rcx] ; dl with DIGITS[cl]
    mov byte [rdi], dl       ; hexstr[n] = dl
    inc rdi                  
    inc rdi ; HEXSTR[rdi+2]  skipping the space
    inc r9  ; CHRSTR[r9+1]   aligning the chrstr
    inc rsi ; BUFFER[rsi+1]  moving to the next read

    inc r8                  
    cmp r8, r15             ; have we handled all 16 chars?
    jne SCAN
    
    mov rax, 1              ; x64 write syscall to stdout, rax 1, rdi 1, rsi *string, rdx len of str
    mov rdi, rax
    mov rsi, numstr
    mov rdx, HEXLEN
    syscall

    cmp rax, 0
    jb QUIT_WITH_ERROR        ; negative values indicate syscall write error


    xor rax, rax
    mov r9, chrstr           ; reassign as syscalls may have changed regs
    mov r11, numstr
CLEANNUMSTR:
    mov byte [r11 + rax], 30h ; reset to '0'
CLEANCHARSTR:
    mov byte [r9 + rax], 2Eh  ; reset to '.'
    inc rax
    cmp rax, 8                ; len(numstr) = 8
    jl CLEANNUMSTR
    cmp rax, 16               ; len(charstr) = 16
    jl CLEANCHARSTR
    
    pop r10                ; retrieve r10 from the stack
    add r10, 16            ; increase it with the operations performed

    jmp READ                ; back to the top!

QUIT:
    mov rax, 60             ; x64 exit syscall, rax 60, rbx 0 (exit with 0 code)
    mov rbx, 0
    syscall

QUIT_WITH_ERROR:
    mov rbx, rax            ; error exit code will be negative (whatever read syscall has spat back)
    mov rax, 60
    syscall
