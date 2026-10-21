; io.asm: raw syscall wrappers, buffered stdout, number formatting, errors.
; Every program links this object and defines a global `prog_name` string.

default rel

%define IO_IMPL
%include "io.inc"

global io_read
global io_write_all
global io_open
global io_close
global open_input
global close_input
global out_byte
global out_bytes
global out_str
global out_dec
global out_hex
global out_flush
global err_str
global report_error
global strlen
global streq
global exit_program
global exit_status
global in_buf

extern prog_name

section .rodata
hex_digits:     db "0123456789abcdef"
colon_space:    db ": ", 0
newline:        db 10, 0

e_perm:         db "Operation not permitted", 0
e_noent:        db "No such file or directory", 0
e_io:           db "Input/output error", 0
e_acces:        db "Permission denied", 0
e_notdir:       db "Not a directory", 0
e_isdir:        db "Is a directory", 0
e_mfile:        db "Too many open files", 0
e_pipe:         db "Broken pipe", 0
e_unknown:      db "Unknown error", 0

section .data
align 8
; pairs of (errno, message); errno 0 terminates the table
errtab:
    dq 1,  e_perm
    dq 2,  e_noent
    dq 5,  e_io
    dq 13, e_acces
    dq 20, e_notdir
    dq 21, e_isdir
    dq 24, e_mfile
    dq 32, e_pipe
    dq 0,  e_unknown

exit_status:    dd 0

section .bss
alignb 16
in_buf:         resb BUF_SIZE
out_buf:        resb BUF_SIZE
out_len:        resq 1

section .text

; io_read(rdi fd, rsi buf, rdx len) -> rax bytes read, 0 on EOF, -errno
io_read:
.again:
    mov eax, SYS_READ
    syscall
    cmp rax, -EINTR
    je .again
    ret

; io_write_all(rdi fd, rsi buf, rdx len) -> rax 0 or -errno
io_write_all:
.loop:
    test rdx, rdx
    jz .done
    mov eax, SYS_WRITE
    syscall
    cmp rax, -EINTR
    je .loop
    test rax, rax
    js .fail
    add rsi, rax
    sub rdx, rax
    jmp .loop
.done:
    xor eax, eax
.fail:
    ret

; io_open(rdi path) -> rax fd or -errno
io_open:
    mov esi, O_RDONLY
    xor edx, edx
    mov eax, SYS_OPEN
    syscall
    ret

; io_close(rdi fd)
io_close:
    mov eax, SYS_CLOSE
    syscall
    ret

; open_input(rdi path) -> rax fd or -errno; "-" means stdin
open_input:
    cmp byte [rdi], '-'
    jne io_open
    cmp byte [rdi+1], 0
    jne io_open
    xor eax, eax
    ret

; close_input(rdi fd): closes everything except stdin
close_input:
    test edi, edi
    jnz io_close
    ret

; out_flush(): writes the stdout buffer; exits with status 1 on write error
out_flush:
    mov rdx, [out_len]
    test rdx, rdx
    jz .ret
    mov edi, STDOUT
    lea rsi, [out_buf]
    call io_write_all
    mov qword [out_len], 0
    test rax, rax
    jns .ret
    mov edi, 1
    mov eax, SYS_EXIT
    syscall
.ret:
    ret

; out_byte(dil byte)
out_byte:
    mov rax, [out_len]
    cmp rax, BUF_SIZE
    jb .put
    push rdi
    call out_flush
    pop rdi
    xor eax, eax
.put:
    lea rcx, [out_buf]
    mov [rcx+rax], dil
    inc rax
    mov [out_len], rax
    ret

; out_bytes(rdi ptr, rsi len)
out_bytes:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
.loop:
    test r12, r12
    jz .done
    mov rax, [out_len]
    mov ecx, BUF_SIZE
    sub rcx, rax                ; free space in the buffer
    jnz .copy
    call out_flush
    jmp .loop
.copy:
    cmp rcx, r12
    cmova rcx, r12              ; chunk = min(free, remaining)
    lea rdi, [out_buf]
    add rdi, rax
    mov rsi, rbx
    add rbx, rcx
    sub r12, rcx
    add rax, rcx
    mov [out_len], rax
    rep movsb
    jmp .loop
.done:
    pop r12
    pop rbx
    ret

; out_str(rdi cstr)
out_str:
    push rdi
    call strlen
    pop rdi
    mov rsi, rax
    jmp out_bytes

; out_dec(rdi value, rsi width): unsigned decimal, right-aligned with spaces
out_dec:
    push rbx
    push r12
    sub rsp, 32
    mov r12, rsi
    lea rbx, [rsp+32]           ; digits are written backwards from here
    mov rax, rdi
    mov ecx, 10
.conv:
    xor edx, edx
    div rcx
    add dl, '0'
    dec rbx
    mov [rbx], dl
    test rax, rax
    jnz .conv
    lea rax, [rsp+32]
    sub rax, rbx                ; number of digits
    sub r12, rax                ; padding needed
    jle .digits
.pad:
    mov edi, ' '
    call out_byte
    dec r12
    jnz .pad
.digits:
    mov rdi, rbx
    lea rsi, [rsp+32]
    sub rsi, rbx
    call out_bytes
    add rsp, 32
    pop r12
    pop rbx
    ret

; out_hex(rdi value, rsi min_digits): lowercase hex, zero-padded
out_hex:
    push rbx
    push r12
    sub rsp, 32
    mov r12, rsi
    lea rbx, [rsp+32]
    mov rax, rdi
    lea rcx, [hex_digits]
.conv:
    mov edx, eax
    and edx, 15
    mov dl, [rcx+rdx]
    dec rbx
    mov [rbx], dl
    shr rax, 4
    jnz .conv
    lea rax, [rsp+32]
    sub rax, rbx
    sub r12, rax
    jle .digits
.pad:
    mov edi, '0'
    call out_byte
    dec r12
    jnz .pad
.digits:
    mov rdi, rbx
    lea rsi, [rsp+32]
    sub rsi, rbx
    call out_bytes
    add rsp, 32
    pop r12
    pop rbx
    ret

; err_str(rdi cstr): unbuffered write to stderr
err_str:
    push rdi
    call strlen
    pop rsi
    mov rdx, rax
    mov edi, STDERR
    jmp io_write_all

; report_error(rdi name, rsi -errno): prints "prog: name: message" and
; makes the final exit status 1
report_error:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    call out_flush              ; keep stdout/stderr order on a terminal
    lea rdi, [prog_name]
    call err_str
    lea rdi, [colon_space]
    call err_str
    mov rdi, rbx
    call err_str
    lea rdi, [colon_space]
    call err_str
    mov rax, r12
    neg rax
    lea rdx, [errtab]
.find:
    mov rcx, [rdx]
    test rcx, rcx
    jz .found
    cmp rcx, rax
    je .found
    add rdx, 16
    jmp .find
.found:
    mov rdi, [rdx+8]
    call err_str
    lea rdi, [newline]
    call err_str
    mov dword [exit_status], 1
    pop r12
    pop rbx
    ret

; strlen(rdi cstr) -> rax
strlen:
    xor eax, eax
.loop:
    cmp byte [rdi+rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; streq(rdi a, rsi b) -> eax 1 if equal, else 0
streq:
    xor ecx, ecx
.loop:
    mov al, [rdi+rcx]
    cmp al, [rsi+rcx]
    jne .differ
    inc rcx
    test al, al
    jnz .loop
    mov eax, 1
    ret
.differ:
    xor eax, eax
    ret

; exit_program(edi status): flushes stdout and terminates
exit_program:
    push rdi
    call out_flush
    pop rdi
    mov eax, SYS_EXIT
    syscall
