; BFH is a scuffed hexdump written in x86_64 asm
; It takes data from stdin and spits it out to stdout
; usage ./bfh < targetfile

%define BUFFLEN 16 ; files are read in 16 byte chunks for convenience's sake for now

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
    and al, 00Fh             ; working with 8 bits, 0 the most significant nybble 
    mov dl, al               ; moving into dl because who knows what's in the rest of rax 
    mov dl, byte [rbx + rdx] ; setting dl to DIGITS[dl] 
    mov byte [r11 + rcx], dl ; writing dl to numstr[rcx]
    dec rcx                  ; rcx--

    mov rax, r10             ; original counter back to rax
    shr al, 4                ; move most significant nybble least significant
    and al, 00Fh             ; 0 the now most significant nybble
    mov dl, al               
    mov dl, byte [rbx + rdx]
    mov byte [r11 + rcx], dl
    
    dec rcx
    jz CONTINUE             ; if we have written into all 8 fields we'll have to live with it
    
    cmp r10, 100h           ; here we check if the overall counter is more than 1 byte, if not we have handled it fully
    jb CONTINUE 
    shr r10, 8              ; shift right 1 byte
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
    shr al, 4                ; most significant nybble in the least significant into al
    and cl, 00Fh             ; 0 most significant nybble in cl 
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

    xor rax, rax            ; 0 rax because now we are going to use it to cleanup our strings
    mov r9, chrstr          ; I originally wanted to subtract 15 from r9, but then realised that the syscall may have affected it
CLEANCHARSTR:
    mov byte [r9+rax], 2Eh  ; reset to '.'
    inc rax                  
    cmp rax, r15            ; have we handled all 16 chars? (r15 seems unaffected by write syscall, but maybe this can cause undefined behaviour)
    jne CLEANCHARSTR
    
    xor rax, rax            ; 0 again, now we are handling chrstr cleanup
    mov r11, numstr         ; r11 is definitely affected by syscalls
CLEANNUMSTR:
    mov byte [r11+rax], 30h ; write 0 into all 8 fields
    inc rax
    cmp rax, 8
    jne CLEANNUMSTR         ; there's probably a clever way to do both cleanups at the same time
    
    pop r10                 ; retrieve r10 from the stack
    add r10, r15            ; increase it with the operations performed
    jmp READ                ; back to the top!

QUIT:
    mov rax, 60             ; x64 exit syscall, rax 60, rbx 0 (exit with 0 code)
    mov rbx, 0
    syscall

QUIT_WITH_ERROR:
    mov rbx, rax            ; error exit code will be negative (whatever read syscall has spat back)
    mov rax, 60
    syscall
