extern printf
extern strcmp
extern getenv
extern system
extern access
extern fopen
extern fclose
extern fputs
extern snprintf

section .data
    usage_msg db "Usage: fowo [-d] install <link>", 10, 0
    install_cmd db "install", 0
    flag_d db "-d", 0
    
    config_prod db "/etc/fowo", 0
    build_prod db "/tmp/fowo_build", 0
    
    config_dbg db "/tmp/fowo_config", 0
    build_dbg db "/tmp/fowo_build_debug", 0
    
    editor_env db "EDITOR", 0
    editor_def db "nano", 0
    
    open_mode db "a+", 0
    cfg_init_msg db "# ==========================================", 10, "# Fowo Package Manager Configuration", 10, "# ==========================================", 10, "# Instructions:", 10, "# 1. Add required system dependencies below.", 10, "# 2. Add custom build flags using FLAGS=...", 10, "# 3. Save and exit to continue.", 10, "# ==========================================", 10, "# Detected Dependencies:", 10, 0
    err_cfg db "Failed to open config file %s. Are you root?", 10, 0
    
    cmd_fmt db "%s %s", 0
    clone_fmt db "rm -rf %s && git clone --recursive %s %s", 0
    clone_msg db "Cloning %s to %s...", 10, 0
    
    makefile_fmt db "%s/Makefile", 0
    cmakelist_fmt db "%s/CMakeLists.txt", 0
    meson_fmt db "%s/meson.build", 0
    
    msg_makefile db "Found Makefile. Building...", 10, 0
    make_cmd db "cd %s && make", 0
    
    msg_cmake db "Found CMakeLists.txt. Building...", 10, 0
    cmake_cmd db "cd %s && cmake -B build && cmake --build build", 0
    
    msg_meson db "Found meson.build. Building...", 10, 0
    meson_cmd db "cd %s && meson setup build && meson compile -C build", 0
    
    cargo_fmt db "%s/Cargo.toml", 0
    msg_cargo db "Found Cargo.toml. Building...", 10, 0
    cargo_cmd db "cd %s && cargo build --release", 0
    
    msg_unsupported db "Unsupported build system or no build file found.", 10, 0
    
    scan_msg db "Scanning dependencies...", 10, 0
    cmake_grep db "grep -hE 'find_package|pkg_check_modules' %s/CMakeLists.txt 2>/dev/null | sed 's/^/# /' >> %s", 0
    meson_grep db "grep -h 'dependency(' %s/meson.build 2>/dev/null | sed 's/^/# /' >> %s", 0
    cargo_grep db "grep -hA 15 '\[dependencies\]' %s/Cargo.toml 2>/dev/null | sed 's/^/# /' >> %s", 0

section .bss
    cmd_buf resb 1024
    file_buf resb 512

section .text
    global main

main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    
    ; r12 = argc
    ; r13 = argv
    mov r12, rdi
    mov r13, rsi
    mov r14, 0 ; debug_mode
    
    cmp r12, 2
    jl .usage
    
    ; check argv[1] == "-d"
    mov rdi, [r13+8]
    mov rsi, flag_d
    call strcmp
    cmp eax, 0
    jne .no_debug
    
    mov r14, 1 ; debug_mode = 1
    cmp r12, 4
    jl .usage
    
    ; check argv[2] == "install"
    mov rdi, [r13+16]
    mov rsi, install_cmd
    call strcmp
    cmp eax, 0
    jne .usage
    
    mov r15, [r13+24] ; r15 = link
    jmp .setup_paths

.no_debug:
    cmp r12, 3
    jl .usage
    
    mov rdi, [r13+8]
    mov rsi, install_cmd
    call strcmp
    cmp eax, 0
    jne .usage
    
    mov r15, [r13+16] ; r15 = link

.setup_paths:
    cmp r14, 1
    je .is_debug
    
    mov r12, config_prod ; r12 = config_path
    mov r13, build_prod  ; r13 = build_dir
    jmp .open_config

.is_debug:
    mov r12, config_dbg
    mov r13, build_dbg

.open_config:
    mov rdi, r12
    mov rsi, 0 ; F_OK
    call access
    cmp eax, 0
    je .clone
    
    mov rdi, r12
    mov rsi, open_mode
    call fopen
    cmp rax, 0
    je .cfg_error
    
    mov rbx, rax
    mov rdi, cfg_init_msg
    mov rsi, rbx
    call fputs
    
    mov rdi, rbx
    call fclose
    jmp .clone

.cfg_error:
    mov rdi, err_cfg
    mov rsi, r12
    xor eax, eax
    call printf

.clone:
    mov rdi, clone_msg
    mov rsi, r15
    mov rdx, r13
    xor eax, eax
    call printf

    mov rdi, cmd_buf
    mov rsi, 1024
    mov rdx, clone_fmt
    mov rcx, r13
    mov r8, r15
    mov r9, r13
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf
    call system

.scan_deps:
    mov rdi, scan_msg
    xor eax, eax
    call printf

    mov rdi, cmd_buf
    mov rsi, 1024
    mov rdx, cmake_grep
    mov rcx, r13
    mov r8, r12
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    
    mov rdi, cmd_buf
    mov rsi, 1024
    mov rdx, meson_grep
    mov rcx, r13
    mov r8, r12
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    
    mov rdi, cmd_buf
    mov rsi, 1024
    mov rdx, cargo_grep
    mov rcx, r13
    mov r8, r12
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system

.editor:
    mov rdi, editor_env
    call getenv
    cmp rax, 0
    jne .got_editor
    mov rax, editor_def
.got_editor:
    mov rdi, cmd_buf
    mov rsi, 1024
    mov rdx, cmd_fmt
    mov rcx, rax
    mov r8, r12
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf
    call system

.check_meson:
    mov rdi, file_buf
    mov rsi, 512
    mov rdx, meson_fmt
    mov rcx, r13
    xor eax, eax
    call snprintf
    
    mov rdi, file_buf
    mov rsi, 0
    call access
    cmp eax, 0
    je .do_meson

.check_cmake:
    mov rdi, file_buf
    mov rsi, 512
    mov rdx, cmakelist_fmt
    mov rcx, r13
    xor eax, eax
    call snprintf
    
    mov rdi, file_buf
    mov rsi, 0
    call access
    cmp eax, 0
    je .do_cmake
    
.check_cargo:
    mov rdi, file_buf
    mov rsi, 512
    mov rdx, cargo_fmt
    mov rcx, r13
    xor eax, eax
    call snprintf
    
    mov rdi, file_buf
    mov rsi, 0
    call access
    cmp eax, 0
    je .do_cargo
    
.check_makefile:
    mov rdi, file_buf
    mov rsi, 512
    mov rdx, makefile_fmt
    mov rcx, r13
    xor eax, eax
    call snprintf
    
    mov rdi, file_buf
    mov rsi, 0 ; F_OK
    call access
    cmp eax, 0
    je .do_make
    
    jmp .unsupported

.do_make:
    mov rdi, msg_makefile
    xor eax, eax
    call printf
    
    mov rdi, cmd_buf
    mov rsi, 1024
    mov rdx, make_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf
    call system
    jmp .done

.do_cmake:
    mov rdi, msg_cmake
    xor eax, eax
    call printf
    
    mov rdi, cmd_buf
    mov rsi, 1024
    mov rdx, cmake_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf
    call system
    jmp .done

.do_meson:
    mov rdi, msg_meson
    xor eax, eax
    call printf
    
    mov rdi, cmd_buf
    mov rsi, 1024
    mov rdx, meson_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf
    call system
    jmp .done

.do_cargo:
    mov rdi, msg_cargo
    xor eax, eax
    call printf
    
    mov rdi, cmd_buf
    mov rsi, 1024
    mov rdx, cargo_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf
    call system
    jmp .done

.unsupported:
    mov rdi, msg_unsupported
    xor eax, eax
    call printf
    jmp .done

.usage:
    mov rdi, usage_msg
    xor eax, eax
    call printf
    mov eax, 1
    jmp .exit

.done:
    xor eax, eax
.exit:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
