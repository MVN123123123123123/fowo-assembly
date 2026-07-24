default rel

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
    usage_msg db "Usage: fowo [-d] install [--tcz] <link>", 10, 0
    install_cmd db "install", 0
    flag_d db "-d", 0
    flag_tcz db "--tcz", 0
    
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
    
    ; TCZ packaging strings
    tcz_stage_clean db "rm -rf /tmp/fowo_tcz_stage && mkdir -p /tmp/fowo_tcz_stage", 0
    make_install_cmd db "cd %s && make DESTDIR=/tmp/fowo_tcz_stage install", 0
    cmake_install_cmd db "cd %s && DESTDIR=/tmp/fowo_tcz_stage cmake --install build", 0
    meson_install_cmd db "cd %s && DESTDIR=/tmp/fowo_tcz_stage meson install -C build", 0
    cargo_install_cmd db "mkdir -p /tmp/fowo_tcz_stage/usr/local/bin && for f in %s/target/release/*; do test -f $f && test -x $f && cp $f /tmp/fowo_tcz_stage/usr/local/bin/; done", 0
    tcz_mksquashfs db "mksquashfs /tmp/fowo_tcz_stage /tmp/$(basename %s .git).tcz -b 4096 -noappend", 0
    tcz_md5 db "cd /tmp && md5sum $(basename %s .git).tcz > $(basename %s .git).tcz.md5.txt", 0
    tcz_move db "mv /tmp/$(basename %s .git).tcz* /etc/sysconfig/tcedir/optional/", 0
    msg_tcz_staging db "Installing to staging directory...", 10, 0
    msg_tcz_packaging db "Creating TCZ package...", 10, 0
    msg_tcz_moving db "Moving to TCE directory...", 10, 0
    msg_tcz_done db "TCZ package built and installed.", 10, 0

section .bss
    cmd_buf resb 1024
    file_buf resb 512
    tcz_mode   resb 1
    build_type resb 1

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
    mov byte [tcz_mode], 0
    mov byte [build_type], 0
    
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
    
    ; check argv[3] == "--tcz"
    mov rdi, [r13+24]
    mov rsi, flag_tcz
    call strcmp
    cmp eax, 0
    jne .no_tcz_debug
    
    mov byte [tcz_mode], 1
    cmp r12, 5
    jl .usage
    mov r15, [r13+32] ; r15 = link (argv[4])
    jmp .setup_paths

.no_tcz_debug:
    mov r15, [r13+24] ; r15 = link (argv[3])
    jmp .setup_paths

.no_debug:
    cmp r12, 3
    jl .usage
    
    mov rdi, [r13+8]
    mov rsi, install_cmd
    call strcmp
    cmp eax, 0
    jne .usage
    
    ; check argv[2] == "--tcz"
    mov rdi, [r13+16]
    mov rsi, flag_tcz
    call strcmp
    cmp eax, 0
    jne .no_tcz
    
    mov byte [tcz_mode], 1
    cmp r12, 4
    jl .usage
    mov r15, [r13+24] ; r15 = link (argv[3])
    jmp .setup_paths

.no_tcz:
    mov r15, [r13+16] ; r15 = link (argv[2])

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
    mov byte [build_type], 1
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
    jmp .post_build

.do_cmake:
    mov byte [build_type], 2
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
    jmp .post_build

.do_meson:
    mov byte [build_type], 3
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
    jmp .post_build

.do_cargo:
    mov byte [build_type], 4
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
    jmp .post_build

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

.post_build:
    cmp byte [tcz_mode], 1
    jne .done
    
    ; --- TCZ Packaging Pipeline ---
    
    ; Print staging message
    mov rdi, msg_tcz_staging
    xor eax, eax
    call printf
    
    ; Clean and create staging directory
    mov rdi, tcz_stage_clean
    call system
    
    ; Dispatch install based on build_type
    cmp byte [build_type], 1
    je .tcz_install_make
    cmp byte [build_type], 2
    je .tcz_install_cmake
    cmp byte [build_type], 3
    je .tcz_install_meson
    cmp byte [build_type], 4
    je .tcz_install_cargo
    jmp .done

.tcz_install_make:
    mov rdi, cmd_buf
    mov rsi, 1024
    mov rdx, make_install_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    jmp .tcz_squash

.tcz_install_cmake:
    mov rdi, cmd_buf
    mov rsi, 1024
    mov rdx, cmake_install_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    jmp .tcz_squash

.tcz_install_meson:
    mov rdi, cmd_buf
    mov rsi, 1024
    mov rdx, meson_install_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    jmp .tcz_squash

.tcz_install_cargo:
    mov rdi, cmd_buf
    mov rsi, 1024
    mov rdx, cargo_install_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    jmp .tcz_squash

.tcz_squash:
    ; Print packaging message
    mov rdi, msg_tcz_packaging
    xor eax, eax
    call printf
    
    ; Create .tcz with mksquashfs
    mov rdi, cmd_buf
    mov rsi, 1024
    mov rdx, tcz_mksquashfs
    mov rcx, r15
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    
    ; Generate md5sum
    mov rdi, cmd_buf
    mov rsi, 1024
    mov rdx, tcz_md5
    mov rcx, r15
    mov r8, r15
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    
    ; Print moving message
    mov rdi, msg_tcz_moving
    xor eax, eax
    call printf
    
    ; Move to TCE directory
    mov rdi, cmd_buf
    mov rsi, 1024
    mov rdx, tcz_move
    mov rcx, r15
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    
    ; Print done message
    mov rdi, msg_tcz_done
    xor eax, eax
    call printf
    jmp .done

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
