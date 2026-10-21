; cat [-n] [file...]: concatenate files to stdout ("-" or no files = stdin).
; -n numbers all output lines like GNU cat ("%6d\t"), counting across files.

default rel
%include "io.inc"

global _start
global prog_name

section .rodata
prog_name:  db "cat", 0
dash:       db "-", 0
opt_n:      db "-n", 0

section .data
at_bol:     db 1                ; next byte starts a new line

section .bss
alignb 8
line_no:    resq 1
numbering:  resb 1

section .text
_start:
    mov r12, [rsp]              ; argc
    lea r13, [rsp+16]           ; argv[1]
    dec r12
    jz .stdin_only
    mov rdi, [r13]
    lea rsi, [opt_n]
    call streq
    test eax, eax
    jz .files
    mov byte [numbering], 1
    add r13, 8
    dec r12
    jz .stdin_only
.files:
    mov rdi, [r13]
    call cat_file
    add r13, 8
    dec r12
    jnz .files
    jmp .finish
.stdin_only:
    lea rdi, [dash]
    call cat_file
.finish:
    mov edi, [exit_status]
    call exit_program

; cat_file(rdi name)
cat_file:
    push rbx
    push r14
    push r15
    mov r14, rdi
    call open_input
    test rax, rax
    js .open_error
    mov rbx, rax
.read:
    mov rdi, rbx
    lea rsi, [in_buf]
    mov edx, BUF_SIZE
    call io_read
    test rax, rax
    jz .close
    js .read_error
    mov r15, rax
    lea rdi, [in_buf]
    mov rsi, r15
    cmp byte [numbering], 0
    jne .numbered
    call out_bytes
    jmp .flush
.numbered:
    call number_chunk
.flush:
    call out_flush              ; do not hold back interactive input
    jmp .read
.read_error:
    mov rdi, r14
    mov rsi, rax
    call report_error
.close:
    mov rdi, rbx
    call close_input
    jmp .ret
.open_error:
    mov rdi, r14
    mov rsi, rax
    call report_error
.ret:
    pop r15
    pop r14
    pop rbx
    ret

; number_chunk(rdi buf, rsi len): copies bytes, prefixing each line start
number_chunk:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
.loop:
    test r12, r12
    jz .done
    cmp byte [at_bol], 0
    je .byte
    mov byte [at_bol], 0
    inc qword [line_no]
    mov rdi, [line_no]
    mov esi, 6
    call out_dec
    mov edi, 9
    call out_byte
.byte:
    movzx edi, byte [rbx]
    cmp edi, 10
    jne .put
    mov byte [at_bol], 1
.put:
    call out_byte
    inc rbx
    dec r12
    jmp .loop
.done:
    pop r12
    pop rbx
    ret
