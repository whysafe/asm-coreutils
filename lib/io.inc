; io.inc: shared constants and declarations of the I/O library (lib/io.asm).
;
; Calling convention (System V AMD64 subset):
;   arguments in rdi, rsi, rdx; result in rax;
;   rbx, rbp, r12-r15 are preserved, everything else may be clobbered.

%ifndef IO_INC
%define IO_INC

%define SYS_READ    0
%define SYS_WRITE   1
%define SYS_OPEN    2
%define SYS_CLOSE   3
%define SYS_STAT    4
%define SYS_FSTAT   5
%define SYS_BRK     12
%define SYS_EXIT    60

%define STDIN       0
%define STDOUT      1
%define STDERR      2

%define O_RDONLY    0
%define EINTR       4

%define BUF_SIZE    65536

; struct stat (x86-64)
%define ST_MODE     24
%define ST_SIZE     48
%define STAT_SIZE   144
%define S_IFMT      0xF000
%define S_IFREG     0x8000

%ifndef IO_IMPL
extern io_read
extern io_write_all
extern io_open
extern io_close
extern open_input
extern close_input
extern out_byte
extern out_bytes
extern out_str
extern out_dec
extern out_hex
extern out_flush
extern err_str
extern report_error
extern strlen
extern streq
extern exit_program
extern exit_status
extern in_buf
%endif

section .note.GNU-stack noalloc noexec nowrite progbits

%endif
