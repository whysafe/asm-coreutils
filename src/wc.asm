; wc [-lwc] [file...]: count lines, words and bytes like GNU wc in the C locale.
; Column width follows GNU: the digits of the summed size of regular files,
; at least 7 if any input is not a regular file, and 1 for a single count
; of a single input.

default rel
%include "io.inc"

global _start
global prog_name

section .rodata
prog_name:  db "wc", 0
dash:       db "-", 0
total_str:  db "total", 0
align 8
stdin_list: dq dash

section .data
bad_opt:    db "wc: invalid option -- 'x'", 10
            db "usage: wc [-lwc] [file...]", 10, 0
%define BAD_OPT_CHAR 23

section .bss
opt_l:      resb 1
opt_w:      resb 1
opt_c:      resb 1
no_name:    resb 1
need_sep:   resb 1
alignb 8
num_width:  resq 1
cur:        resq 3              ; lines, words, bytes of the current file
tot:        resq 3
stat_buf:   resb STAT_SIZE

section .text
_start:
    mov rcx, [rsp]
    dec rcx                     ; arguments after argv[0]
    lea rsi, [rsp+16]           ; read cursor
    mov r12, rsi                ; file names are compacted in place
    mov rdi, rsi                ; write cursor
    xor r8d, r8d                ; set after "--"
.args:
    test rcx, rcx
    jz .args_done
    mov rax, [rsi]
    add rsi, 8
    dec rcx
    test r8d, r8d
    jnz .file
    cmp byte [rax], '-'
    jne .file
    cmp byte [rax+1], 0
    je .file
    cmp word [rax+1], '-'       ; "--"
    jne .opts
    mov r8d, 1
    jmp .args
.opts:
    inc rax
.opt:
    mov dl, [rax]
    test dl, dl
    jz .args
    cmp dl, 'l'
    jne .not_l
    mov byte [opt_l], 1
    jmp .opt_next
.not_l:
    cmp dl, 'w'
    jne .not_w
    mov byte [opt_w], 1
    jmp .opt_next
.not_w:
    cmp dl, 'c'
    jne .bad_option
    mov byte [opt_c], 1
.opt_next:
    inc rax
    jmp .opt
.bad_option:
    mov [bad_opt+BAD_OPT_CHAR], dl
    lea rdi, [bad_opt]
    call err_str
    mov edi, 1
    call exit_program
.file:
    mov [rdi], rax
    add rdi, 8
    jmp .args

.args_done:
    mov r13, rdi
    sub r13, r12
    shr r13, 3                  ; number of files
    jnz .count_flags
    lea r12, [stdin_list]
    mov r13d, 1
    mov byte [no_name], 1

.count_flags:
    movzx eax, byte [opt_l]
    movzx ecx, byte [opt_w]
    add eax, ecx
    movzx ecx, byte [opt_c]
    add eax, ecx
    jnz .width
    mov byte [opt_l], 1
    mov byte [opt_w], 1
    mov byte [opt_c], 1
    mov eax, 3

.width:
    mov qword [num_width], 1
    cmp r13, 1
    jne .measure
    cmp eax, 1
    je .process
.measure:
    xor r14d, r14d              ; summed size of regular files
    mov r15d, 1                 ; minimum width
    xor ebx, ebx
.stat_loop:
    cmp rbx, r13
    je .stat_done
    mov rdi, [r12+rbx*8]
    call stat_path
    test rax, rax
    js .stat_next
    mov eax, [stat_buf+ST_MODE]
    and eax, S_IFMT
    cmp eax, S_IFREG
    jne .not_regular
    add r14, [stat_buf+ST_SIZE]
    jmp .stat_next
.not_regular:
    mov r15d, 7
.stat_next:
    inc rbx
    jmp .stat_loop
.stat_done:
    mov ecx, 1
    mov rax, r14
    mov r8d, 10
.digits:
    cmp rax, 10
    jb .digits_done
    xor edx, edx
    div r8
    inc ecx
    jmp .digits
.digits_done:
    cmp rcx, r15
    cmovb rcx, r15
    mov [num_width], rcx

.process:
    xor ebx, ebx
.file_loop:
    cmp rbx, r13
    je .files_done
    mov rdi, [r12+rbx*8]
    call wc_file
    inc rbx
    jmp .file_loop
.files_done:
    cmp r13, 1
    jbe .finish
    lea rdi, [tot]
    lea rsi, [total_str]
    call print_counts
.finish:
    mov edi, [exit_status]
    call exit_program

; stat_path(rdi name) -> rax 0 or -errno, fills stat_buf; "-" is stdin
stat_path:
    lea rsi, [stat_buf]
    cmp byte [rdi], '-'
    jne .by_path
    cmp byte [rdi+1], 0
    jne .by_path
    mov edi, STDIN
    mov eax, SYS_FSTAT
    syscall
    ret
.by_path:
    mov eax, SYS_STAT
    syscall
    ret

; wc_file(rdi name): counts one input, prints its line, adds to totals
wc_file:
    push rbx
    push r14
    push r15
    mov r14, rdi
    call open_input
    test rax, rax
    js .open_error
    mov r15, rax
    mov rdi, rax
    call count_fd
    mov rbx, rax
    mov rdi, r15
    call close_input
    test rbx, rbx
    jns .add
    mov rdi, r14
    mov rsi, rbx
    call report_error
.add:
    mov rax, [cur]
    add [tot], rax
    mov rax, [cur+8]
    add [tot+8], rax
    mov rax, [cur+16]
    add [tot+16], rax
    lea rdi, [cur]
    mov rsi, r14
    cmp byte [no_name], 0
    je .print
    xor esi, esi
.print:
    call print_counts
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

; count_fd(rdi fd) -> rax 0 or -errno; stores the counts in cur
; A word is a maximal run of bytes other than ' ', '\t', '\n', '\v', '\f', '\r'.
count_fd:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r15, rdi
    xor r12d, r12d              ; lines
    xor r13d, r13d              ; words
    xor r14d, r14d              ; bytes
    xor ebx, ebx                ; inside a word
.read:
    mov rdi, r15
    lea rsi, [in_buf]
    mov edx, BUF_SIZE
    call io_read
    test rax, rax
    jz .done
    js .done
    add r14, rax
    lea rsi, [in_buf]
    lea rdi, [rsi+rax]
.scan:
    cmp rsi, rdi
    je .read
    movzx eax, byte [rsi]
    inc rsi
    cmp eax, 10
    jne .not_newline
    inc r12
    jmp .space
.not_newline:
    cmp eax, ' '
    je .space
    sub eax, 9
    cmp eax, 4                  ; 9..13
    jbe .space
    test ebx, ebx
    jnz .scan
    mov ebx, 1
    inc r13
    jmp .scan
.space:
    xor ebx, ebx
    jmp .scan
.done:
    mov [cur], r12
    mov [cur+8], r13
    mov [cur+16], r14
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; print_counts(rdi counts[3], rsi name or 0)
print_counts:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov byte [need_sep], 0
    cmp byte [opt_l], 0
    je .words
    mov rdi, [rbx]
    call put_number
.words:
    cmp byte [opt_w], 0
    je .bytes
    mov rdi, [rbx+8]
    call put_number
.bytes:
    cmp byte [opt_c], 0
    je .name
    mov rdi, [rbx+16]
    call put_number
.name:
    test r12, r12
    jz .eol
    mov edi, ' '
    call out_byte
    mov rdi, r12
    call out_str
.eol:
    mov edi, 10
    call out_byte
    pop r12
    pop rbx
    ret

; put_number(rdi value): one column, separated from the previous by a space
put_number:
    push rdi
    cmp byte [need_sep], 0
    je .first
    mov edi, ' '
    call out_byte
.first:
    mov byte [need_sep], 1
    pop rdi
    mov rsi, [num_width]
    jmp out_dec
