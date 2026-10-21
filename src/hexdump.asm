; hexdump [-C] [file...]: canonical hex+ASCII dump, same output as `hexdump -C`.
; Inputs are dumped as one stream; repeated 16-byte lines collapse into "*".

default rel
%include "io.inc"

global _start
global prog_name

section .rodata
prog_name:  db "hexdump", 0
dash:       db "-", 0
opt_c:      db "-C", 0
star_line:  db "*", 10, 0
blank_byte: db "   "

section .bss
alignb 8
line:       resb 16             ; bytes of the line being collected
prev:       resb 16             ; last printed full line
fill:       resq 1              ; bytes in `line`
offset:     resq 1              ; stream offset of `line`
file_count: resq 1
have_prev:  resb 1
in_dup:     resb 1              ; "*" already printed for the current run

section .text
_start:
    mov r12, [rsp]
    lea r13, [rsp+16]
    dec r12
.args:
    test r12, r12
    jz .args_done
    mov rdi, [r13]
    lea rsi, [opt_c]
    call streq
    test eax, eax
    jnz .next_arg               ; -C is the only (and default) format
    inc qword [file_count]
    mov rdi, [r13]
    call dump_file
.next_arg:
    add r13, 8
    dec r12
    jmp .args
.args_done:
    cmp qword [file_count], 0
    jne .tail
    lea rdi, [dash]
    call dump_file
.tail:
    mov rbx, [fill]
    test rbx, rbx
    jz .final_offset
    mov rdi, rbx
    call print_line
    add [offset], rbx
.final_offset:
    mov rdi, [offset]
    test rdi, rdi
    jz .finish
    mov esi, 8
    call out_hex
    mov edi, 10
    call out_byte
.finish:
    mov edi, [exit_status]
    call exit_program

; dump_file(rdi name)
dump_file:
    push rbx
    push r14
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
    lea rdi, [in_buf]
    mov rsi, rax
    call feed
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
    pop r14
    pop rbx
    ret

; feed(rdi buf, rsi len): appends bytes to `line`, emitting every full line
feed:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
.loop:
    test r12, r12
    jz .done
    mov rax, [fill]
    lea rcx, [line]
    mov dl, [rbx]
    mov [rcx+rax], dl
    inc rax
    mov [fill], rax
    inc rbx
    dec r12
    cmp rax, 16
    jne .loop
    call full_line
    jmp .loop
.done:
    pop r12
    pop rbx
    ret

; full_line(): prints `line`, or "*" once for a run of repeated lines
full_line:
    mov qword [fill], 0
    cmp byte [have_prev], 0
    je .show
    mov rax, [line]
    cmp rax, [prev]
    jne .show
    mov rax, [line+8]
    cmp rax, [prev+8]
    jne .show
    cmp byte [in_dup], 0
    jne .skip
    mov byte [in_dup], 1
    lea rdi, [star_line]
    call out_str
.skip:
    add qword [offset], 16
    ret
.show:
    mov edi, 16
    call print_line
    mov rax, [line]
    mov [prev], rax
    mov rax, [line+8]
    mov [prev+8], rax
    mov byte [have_prev], 1
    mov byte [in_dup], 0
    add qword [offset], 16
    ret

; print_line(rdi count): "oooooooo  xx xx ... xx  xx ... xx  |ascii|"
print_line:
    push rbx
    push r12
    mov r12, rdi
    mov rdi, [offset]
    mov esi, 8
    call out_hex
    mov edi, ' '
    call out_byte
    mov edi, ' '
    call out_byte
    xor ebx, ebx
.hex:
    cmp ebx, 16
    je .ascii
    cmp ebx, 8
    jne .no_gap
    mov edi, ' '
    call out_byte
.no_gap:
    cmp rbx, r12
    jae .blank
    lea rax, [line]
    movzx edi, byte [rax+rbx]
    mov esi, 2
    call out_hex
    mov edi, ' '
    call out_byte
    jmp .hex_next
.blank:
    lea rdi, [blank_byte]
    mov esi, 3
    call out_bytes
.hex_next:
    inc ebx
    jmp .hex
.ascii:
    mov edi, ' '
    call out_byte
    mov edi, '|'
    call out_byte
    xor ebx, ebx
.ascii_loop:
    cmp rbx, r12
    je .end
    lea rax, [line]
    movzx edi, byte [rax+rbx]
    cmp edi, 0x20
    jb .dot
    cmp edi, 0x7e
    jbe .put
.dot:
    mov edi, '.'
.put:
    call out_byte
    inc ebx
    jmp .ascii_loop
.end:
    mov edi, '|'
    call out_byte
    mov edi, 10
    call out_byte
    pop r12
    pop rbx
    ret
