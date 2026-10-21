; rev [file...]: reverse the bytes of every line ("-" or no files = stdin).
; Lines of any length are kept in a heap buffer grown with brk(2).

default rel
%include "io.inc"

%define GROW_STEP 65536

global _start
global prog_name

section .rodata
prog_name:  db "rev", 0
dash:       db "-", 0
oom_msg:    db "rev: out of memory", 10, 0

section .bss
alignb 8
line_base:  resq 1
line_cap:   resq 1
line_len:   resq 1

section .text
_start:
    xor edi, edi
    mov eax, SYS_BRK            ; brk(0) returns the current program break
    syscall
    mov [line_base], rax

    mov r12, [rsp]
    lea r13, [rsp+16]
    dec r12
    jz .stdin_only
.files:
    mov rdi, [r13]
    call rev_file
    add r13, 8
    dec r12
    jnz .files
    jmp .finish
.stdin_only:
    lea rdi, [dash]
    call rev_file
.finish:
    mov edi, [exit_status]
    call exit_program

; rev_file(rdi name)
rev_file:
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
    jz .eof
    js .read_error
    lea r15, [in_buf]
    add rax, r15
    push rax                    ; end of the chunk
.scan:
    cmp r15, [rsp]
    je .chunk_done
    movzx eax, byte [r15]
    inc r15
    cmp eax, 10
    je .newline
    mov edi, eax
    call append_byte
    jmp .scan
.newline:
    call emit_line
    mov edi, 10
    call out_byte
    jmp .scan
.chunk_done:
    pop rax
    jmp .read
.read_error:
    mov rdi, r14
    mov rsi, rax
    call report_error
.eof:
    call emit_line              ; last line without '\n' stays without it
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

; append_byte(dil byte): pushes a byte to the line buffer, growing it if full
append_byte:
    mov rax, [line_len]
    cmp rax, [line_cap]
    jb .store
    push rdi
    mov rdi, [line_base]
    add rdi, [line_cap]
    add rdi, GROW_STEP
    push rdi
    mov eax, SYS_BRK
    syscall
    pop rdi
    cmp rax, rdi
    jne .oom
    add qword [line_cap], GROW_STEP
    pop rdi
    mov rax, [line_len]
.store:
    mov rcx, [line_base]
    mov [rcx+rax], dil
    inc rax
    mov [line_len], rax
    ret
.oom:
    lea rdi, [oom_msg]
    call err_str
    mov edi, 1
    call exit_program

; emit_line(): writes the buffered line backwards and empties the buffer
emit_line:
    push rbx
    mov rbx, [line_len]
.loop:
    test rbx, rbx
    jz .done
    dec rbx
    mov rax, [line_base]
    movzx edi, byte [rax+rbx]
    call out_byte
    jmp .loop
.done:
    mov qword [line_len], 0
    pop rbx
    ret
