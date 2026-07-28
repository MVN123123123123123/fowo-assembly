default rel

extern printf
extern strcmp
extern getenv
extern system
extern access
extern fopen
extern fclose
extern fputs
extern fprintf
extern fgets
extern snprintf
extern exit
extern popen
extern pclose
extern opendir
extern readdir
extern closedir
extern strlen
extern strncmp
extern time

section .data
    usage_msg db "Usage: fowo [-d] install [--tcz] [--no-edit] <link>", 10, \
                 "       fowo [-d] update", 10, \
                 "       fowo [-d] update <package>", 10, 0
    install_cmd db "install", 0
    update_cmd db "update", 0
    uninstall_cmd db "uninstall", 0
    remove_cmd db "remove", 0
    list_cmd db "list", 0
    
    uninstall_msg db "Uninstalling package: %s...", 10, 0
    uninstall_sh_fmt db "DB=%s/%s; sudo xargs -a $DB.files rm -f 2>/dev/null; sudo rm -f $DB.files $DB.db", 0
    
    list_sh_fmt db "echo 'Installed packages:'; for f in %s/*.db; do [ -e ", 34, "$f", 34, " ] || continue; pkg=$(basename $f .db); url=$(awk -F= '/^URL=/{print $2}' $f); date_ts=$(awk -F= '/^DATE=/{print $2}' $f); if [ -n ", 34, "$date_ts", 34, " ]; then date_str=$(date -d @$date_ts 2>/dev/null || echo $date_ts); else date_str='Unknown'; fi; echo ' - '$pkg; echo '   URL:  '$url; echo '   Date: '$date_str; done", 0
    
    flag_d db "-d", 0
    flag_tcz db "--tcz", 0
    flag_no_edit db "--no-edit", 0
    
    config_prod db "/etc/fowo", 0
    build_prod db "/tmp/fowo_build", 0
    
    config_dbg db "/tmp/fowo_config", 0
    build_dbg db "/tmp/fowo_build_debug", 0
    
    editor_env db "EDITOR", 0
    editor_def db "nano", 0
    
    open_mode db "a+", 0
    read_mode db "r", 0
    write_mode db "w", 0
    cfg_init_msg db "# ==========================================", 10, \
                    "# Fowo Package Manager Configuration", 10, \
                    "# ==========================================", 10, \
                    "# Instructions:", 10, \
                    "# 1. Map dependencies using: ALIAS system_pkg = dep1, dep2", 10, \
                    "# 2. Use system PM for specific deps: SYS [pm] pkg (e.g. SYS dnf openssl-devel)", 10, \
                    "# 3. Add custom build flags using FLAGS=...", 10, \
                    "# 4. Save and exit to continue.", 10, \
                    "# ==========================================", 10, \
                    "# Detected Dependencies:", 10, 0
    err_cfg db "Failed to open config file %s. Are you root?", 10, 0
    
    cmd_fmt db "%s %s", 0
    clone_fmt db "D='%s'; if [ ! -d $D/.git ]; then rm -rf $D && git clone --recursive %s $D; else echo 'Pulling latest...'; cd $D && git pull; fi", 0
    build_dir_fmt db "%s/%s", 0
    clone_msg db "Cloning %s to %s...", 10, 0
    
    makefile_fmt db "%s/Makefile", 0
    cmakelist_fmt db "%s/CMakeLists.txt", 0
    meson_fmt db "%s/meson.build", 0
    
    makefile_name db "Makefile", 0
    cmakelist_name db "CMakeLists.txt", 0
    meson_name db "meson.build", 0
    cargo_name db "Cargo.toml", 0
    
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
    msg_build_fail db "Build failed. Aborting.", 10, 0
    msg_clone_fail db "Git clone/pull failed. Aborting.", 10, 0
    
    scan_msg db "Scanning dependencies...", 10, 0
    makefile_grep db "grep -hE 'pkg-config' %s/Makefile 2>/dev/null | sed -n -E ", 34, "s/.*pkg-config[[:space:]]+(--cflags|--libs|--cflags --libs)[[:space:]]+([a-zA-Z0-9_.-]+).*/# Detected: \2/p", 34, " >> %s", 0
    cmake_grep db "grep -hE 'find_package|pkg_check_modules' %s/CMakeLists.txt 2>/dev/null | sed -n -E ", 34, "s/.*(find_package|pkg_check_modules)[[:space:]]*\([[:space:]]*([a-zA-Z0-9_.-]+).*/# Detected: \2/p", 34, " >> %s", 0
    meson_grep db "grep -h 'dependency(' %s/meson.build 2>/dev/null | sed -n -E ", 34, "s/.*dependency[[:space:]]*\([[:space:]]*'([^']+)'.*/# Detected: \1/p", 34, " >> %s", 0
    cargo_grep db "grep -hA 15 '\[dependencies\]' %s/Cargo.toml 2>/dev/null | grep -v '\[dependencies\]' | sed -n -E ", 34, "s/^([a-zA-Z0-9_.-]+)[[:space:]]*=.*/# Detected: \1/p", 34, " >> %s", 0
    install_deps_cmd db "awk '/^ALIAS / { pkg=$2; for(i=4;i<=NF;i++){ val=$i; sub(/,$/,", 34, 34, ",val); map[val]=pkg } } /^SYS / { sys_map[$3]=$2 } /^# Detected:/ { dep=$3; detected[dep]=1 } END { for(dep in detected) { if(map[dep]!=", 34, 34, ") dep=map[dep]; to_install[dep]=1 } for(pkg in to_install) { if(system(", 34, "test -f /var/lib/fowo/packages/", 34, " pkg ", 34, ".db || test -f /tmp/fowo_packages/", 34, " pkg ", 34, ".db", 34, ")==0) continue; if(sys_map[pkg]!=", 34, 34, ") { pm=sys_map[pkg]; if(pm==", 34, "dnf", 34, ") cmd=", 34, "sudo dnf install -y ", 34, " pkg; else if(pm==", 34, "apt", 34, ") cmd=", 34, "sudo apt-get install -y ", 34, " pkg; else if(pm==", 34, "tce-load", 34, ") cmd=", 34, "tce-load -wi ", 34, " pkg; else cmd=pm ", 34, " install ", 34, " pkg; system(cmd); } else { system(", 34, "if command -v tce-load >/dev/null 2>&1; then tce-load -wi ", 34, " pkg ", 34, "; else %s install ", 34, " pkg ", 34, "; fi", 34, "); } } }' %s", 0
    
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
    
    msg_normal_install db "Installing to system (Normal Linux)...", 10, 0
    norm_make_install_cmd db "rm -rf /tmp/fowo_dest_stage && mkdir -p /tmp/fowo_dest_stage && cd %s && sudo make DESTDIR=/tmp/fowo_dest_stage install", 0
    norm_cmake_install_cmd db "rm -rf /tmp/fowo_dest_stage && mkdir -p /tmp/fowo_dest_stage && cd %s && sudo DESTDIR=/tmp/fowo_dest_stage cmake --install build", 0
    norm_meson_install_cmd db "rm -rf /tmp/fowo_dest_stage && mkdir -p /tmp/fowo_dest_stage && cd %s && sudo DESTDIR=/tmp/fowo_dest_stage meson install -C build", 0
    norm_cargo_install_cmd db "rm -rf /tmp/fowo_dest_stage && mkdir -p /tmp/fowo_dest_stage/usr/local/bin && for f in %s/target/release/*; do test -f $f && test -x $f && cp $f /tmp/fowo_dest_stage/usr/local/bin/; done", 0
    track_files_fmt db "cd /tmp/fowo_dest_stage && find . -type f | sed 's|^\./|/|' | sudo tee %s/%s.files >/dev/null && sudo cp -a /tmp/fowo_dest_stage/* / 2>/dev/null || true && sudo rm -rf /tmp/fowo_dest_stage", 0
    
    ; -----------------------------------------------
    ; Topology database strings
    ; -----------------------------------------------
    pkg_db_prod db "/var/lib/fowo/packages", 0
    pkg_db_dbg db "/tmp/fowo_packages", 0
    mkdir_fmt db "mkdir -p %s", 0
    db_file_fmt db "%s/%s.db", 0
    
    ; DB write format: one line per field
    db_write_url db "URL=%s", 10, 0
    db_write_commit db "COMMIT=%s", 10, 0
    db_write_date db "DATE=%ld", 10, 0
    db_write_btype db "BUILD_TYPE=%d", 10, 0
    db_write_bconf db "BUILD_CONF=%s", 10, 0
    db_write_tcz db "TCZ_MODE=%d", 10, 0
    
    ; DB read prefixes
    db_pfx_url db "URL=", 0
    db_pfx_commit db "COMMIT=", 0
    db_pfx_date db "DATE=", 0
    db_pfx_btype db "BUILD_TYPE=", 0
    db_pfx_bconf db "BUILD_CONF=", 0
    db_pfx_tcz db "TCZ_MODE=", 0
    
    ; Git commands for updater
    ls_remote_fmt db "git ls-remote %s HEAD 2>/dev/null | head -1 | cut -f1", 0
    rev_parse_fmt db "cd %s && git rev-parse HEAD 2>/dev/null", 0
    git_diff_fmt db "cd %s && git fetch origin 2>/dev/null && git diff --name-only %s origin/HEAD -- %s 2>/dev/null | head -1", 0
    
    ; Update messages
    msg_update_all db "Scanning all installed packages for updates...", 10, 0
    msg_checking db "Checking %s...", 10, 0
    msg_up_to_date db "  %s is up to date.", 10, 0
    msg_update_found db "  Update available for %s", 10, 0
    msg_conf_changed db "  Build config changed. Running full install...", 10, 0
    msg_conf_same db "  Build config unchanged. Rebuilding silently...", 10, 0
    msg_update_done db "Update check complete.", 10, 0
    msg_pkg_not_found db "Package '%s' not found in database.", 10, 0
    msg_saving_topo db "Saving package topology for %s...", 10, 0
    
    fowo_pkg_name db "fowo", 0
    fowo_default_repo db "https://github.com/MVN123123123123123/fowo-assembly", 0
    msg_fowo_updating db "  Downloading latest fowo binary...", 10, 0
    msg_fowo_updated db "  fowo updated successfully to %s", 10, 0
    fowo_update_cmd db "curl -sL %s/releases/download/latest/fowo -o /tmp/fowo_new && chmod +x /tmp/fowo_new && sudo mv /tmp/fowo_new %s", 0
    fowo_db_fmt1 db "echo 'URL=%s' > %s/fowo.db", 0
    fowo_db_fmt2 db "echo 'COMMIT=%s' >> %s/fowo.db", 0
    fowo_db_fmt3 db "echo 'DATE='$(date +%%s) >> %s/fowo.db && echo 'BUILD_TYPE=0' >> %s/fowo.db && echo 'TCZ_MODE=0' >> %s/fowo.db", 0

    ; Self-invocation format strings
    self_invoke_noedit db "%s -d install --no-edit %s", 0
    self_invoke_edit db "%s -d install %s", 0
    self_invoke_noedit_prod db "%s install --no-edit %s", 0
    self_invoke_edit_prod db "%s install %s", 0
    
    self_invoke_tcz_noedit db "%s -d install --tcz --no-edit %s", 0
    self_invoke_tcz_edit db "%s -d install --tcz %s", 0
    self_invoke_tcz_noedit_prod db "%s install --tcz --no-edit %s", 0
    self_invoke_tcz_edit_prod db "%s install --tcz %s", 0
    
    ; Misc
    db_ext db ".db", 0
    newline_char db 10, 0
    popen_read db "r", 0

section .bss
    cmd_buf resb 4096
    cmd_buf2 resb 4096
    file_buf resb 512
    actual_build_dir resb 4096
    tcz_mode   resb 1
    build_type resb 1
    no_edit_mode resb 1
    debug_mode_g resb 1
    
    ; Topology database buffers
    db_path_buf resb 512
    pkg_db_path resb 512
    remote_commit resb 128
    local_commit resb 128
    stored_url resb 512
    stored_commit resb 128
    stored_bconf resb 256
    stored_btype resb 4
    stored_tcz resb 1
    stored_date resb 32
    line_buf resb 4096
    pkg_name_buf resb 256
    self_path_buf resb 512
    
    ; For update iteration
    dir_entry_name resb 256
    timestamp_buf resb 32

section .text
    global _start
    global main

_start:
    mov rdi, [rsp]        ; argc
    lea rsi, [rsp + 8]    ; argv
    call main
    mov rdi, rax
    call exit

; =========================================================================
; main(argc, argv)
; =========================================================================
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
    mov byte [no_edit_mode], 0
    mov byte [debug_mode_g], 0
    
    ; Save argv[0] for self-invocation
    mov rax, [r13]
    mov rdi, self_path_buf
    mov rsi, rax
.copy_self:
    lodsb
    stosb
    test al, al
    jnz .copy_self
    
    cmp r12, 2
    jl .usage
    
    ; -------------------------------------------------------
    ; Check argv[1] == "-d"
    ; -------------------------------------------------------
    mov rdi, [r13+8]
    mov rsi, flag_d
    call strcmp
    cmp eax, 0
    jne .no_debug
    
    mov r14, 1
    mov byte [debug_mode_g], 1
    cmp r12, 3
    jl .usage
    
    ; -------------------------------------------------------
    ; Debug mode: check argv[2] for command
    ; -------------------------------------------------------
    ; Check "update"
    mov rdi, [r13+16]
    mov rsi, update_cmd
    call strcmp
    cmp eax, 0
    je .parse_update_debug
    
    ; Check "install"
    mov rdi, [r13+16]
    mov rsi, install_cmd
    call strcmp
    cmp eax, 0
    je .parse_install_debug

    ; Check "uninstall"
    mov rdi, [r13+16]
    mov rsi, uninstall_cmd
    call strcmp
    cmp eax, 0
    je .parse_uninstall_debug
    mov rdi, [r13+16]
    mov rsi, remove_cmd
    call strcmp
    cmp eax, 0
    je .parse_uninstall_debug

    ; Check "list"
    mov rdi, [r13+16]
    mov rsi, list_cmd
    call strcmp
    cmp eax, 0
    je .do_list_packages

    jmp .usage

.parse_install_debug:
    ; --- Debug install: parse flags from argv[3] onward ---
    cmp r12, 4
    jl .usage
    
    mov rbx, 3              ; arg index
.dbg_parse_flags:
    cmp rbx, r12
    jge .usage              ; no link found
    
    mov rax, rbx
    shl rax, 3
    mov rdi, [r13 + rax]
    
    ; Check --tcz
    mov rsi, flag_tcz
    call strcmp
    cmp eax, 0
    jne .dbg_not_tcz
    mov byte [tcz_mode], 1
    inc rbx
    jmp .dbg_parse_flags
    
.dbg_not_tcz:
    mov rax, rbx
    shl rax, 3
    mov rdi, [r13 + rax]
    mov rsi, flag_no_edit
    call strcmp
    cmp eax, 0
    jne .dbg_not_noedit
    mov byte [no_edit_mode], 1
    inc rbx
    jmp .dbg_parse_flags
    
.dbg_not_noedit:
    ; This arg is the link
    mov rax, rbx
    shl rax, 3
    mov r15, [r13 + rax]
    jmp .setup_paths
    
    ; -------------------------------------------------------
    ; Debug update: fowo -d update [<pkg>]
    ; -------------------------------------------------------
.parse_update_debug:
    cmp r12, 4
    jl .do_update_all
    mov r15, [r13+24]       ; r15 = package name
    jmp .do_update_one
    
.parse_uninstall_debug:
    cmp r12, 4
    jl .usage
    mov r15, [r13+24]
    jmp .uninstall

    ; -------------------------------------------------------
    ; No debug: check argv[1] for command
    ; -------------------------------------------------------
.no_debug:
    ; Check "update"
    mov rdi, [r13+8]
    mov rsi, update_cmd
    call strcmp
    cmp eax, 0
    je .parse_update_nodebug
    
    ; Check "install"
    mov rdi, [r13+8]
    mov rsi, install_cmd
    call strcmp
    cmp eax, 0
    je .parse_install_nodebug

    ; Check "uninstall"
    mov rdi, [r13+8]
    mov rsi, uninstall_cmd
    call strcmp
    cmp eax, 0
    je .parse_uninstall_nodebug
    mov rdi, [r13+8]
    mov rsi, remove_cmd
    call strcmp
    cmp eax, 0
    je .parse_uninstall_nodebug

    ; Check "list"
    mov rdi, [r13+8]
    mov rsi, list_cmd
    call strcmp
    cmp eax, 0
    je .do_list_packages

    jmp .usage

.parse_install_nodebug:
    ; --- Non-debug install: parse flags from argv[2] onward ---
    cmp r12, 3
    jl .usage
    
    mov rbx, 2
.nodebug_parse_flags:
    cmp rbx, r12
    jge .usage
    
    mov rax, rbx
    shl rax, 3
    mov rdi, [r13 + rax]
    
    mov rsi, flag_tcz
    call strcmp
    cmp eax, 0
    jne .nodebug_not_tcz
    mov byte [tcz_mode], 1
    inc rbx
    jmp .nodebug_parse_flags
    
.nodebug_not_tcz:
    mov rax, rbx
    shl rax, 3
    mov rdi, [r13 + rax]
    mov rsi, flag_no_edit
    call strcmp
    cmp eax, 0
    jne .nodebug_not_noedit
    mov byte [no_edit_mode], 1
    inc rbx
    jmp .nodebug_parse_flags
    
.nodebug_not_noedit:
    mov rax, rbx
    shl rax, 3
    mov r15, [r13 + rax]
    jmp .setup_paths
    
    ; -------------------------------------------------------
    ; Non-debug update: fowo update [<pkg>]
    ; -------------------------------------------------------
.parse_update_nodebug:
    cmp r12, 3
    jl .do_update_all
    mov r15, [r13+16]
    jmp .do_update_one

.parse_uninstall_nodebug:
    cmp r12, 3
    jl .usage
    mov r15, [r13+16]
    jmp .uninstall

; =========================================================================
; Setup paths (install flow)
; NOTE: r12 and r13 are repurposed here. After this point:
;   r12 = config path (was argc)
;   r13 = build dir path (was argv)
;   r14 = debug mode flag,  r15 = URL / git link
; =========================================================================
.setup_paths:
    cmp r14, 1
    je .is_debug
    
    mov r12, config_prod
    mov r13, build_prod
    jmp .open_config

.is_debug:
    mov r12, config_dbg
    mov r13, build_dbg

.open_config:
    ; Skip config creation in no-edit mode if file already exists
    cmp byte [no_edit_mode], 1
    je .clone
    
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
    mov eax, 1
    jmp .exit

.clone:
    ; --- Extract basename from URL ---
    mov rbx, r15
    mov rcx, r15
.find_slash:
    cmp byte [rcx], 0
    je .found_end
    cmp byte [rcx], '/'
    jne .not_slash
    ; Only update basename if next char is a real path component
    cmp byte [rcx + 1], 0
    je .not_slash
    cmp byte [rcx + 1], '/'
    je .not_slash
    lea rbx, [rcx + 1]
.not_slash:
    inc rcx
    jmp .find_slash
.found_end:

    mov rsi, rbx
    mov rdi, file_buf
.copy_name:
    lodsb
    stosb
    test al, al
    jnz .copy_name
    
    ; Calculate string length and strip trailing '/' characters
    lea rax, [file_buf]
    mov rcx, rdi
    sub rcx, rax
    dec rcx                             ; rcx = strlen(file_buf)
.strip_trailing_slash:
    test rcx, rcx
    jz .no_git
    cmp byte [file_buf + rcx - 1], '/'
    jne .check_dot_git
    dec rcx
    mov byte [file_buf + rcx], 0
    lea rdi, [file_buf + rcx + 1]       ; adjust rdi past new null
    jmp .strip_trailing_slash
.check_dot_git:
    cmp rcx, 4
    jl .no_git
    cmp dword [rdi - 5], 0x7469672e     ; ".git" in little-endian
    jne .no_git
    mov byte [rdi - 5], 0
.no_git:

    ; Also copy pkg name to pkg_name_buf for topology save
    mov rsi, file_buf
    mov rdi, pkg_name_buf
.copy_pkg_name:
    lodsb
    stosb
    test al, al
    jnz .copy_pkg_name

    mov rdi, actual_build_dir
    mov rsi, 4096
    mov rdx, build_dir_fmt
    mov rcx, r13
    mov r8, file_buf
    xor eax, eax
    call snprintf
    
    mov r13, actual_build_dir

    mov rdi, clone_msg
    mov rsi, r15
    mov rdx, r13
    xor eax, eax
    call printf

    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, clone_fmt
    mov rcx, r13
    mov r8, r15
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf
    call system
    test eax, eax
    jnz .clone_fail

    ; --- Skip scan_deps and editor if --no-edit ---
    cmp byte [no_edit_mode], 1
    je .run_deps

.scan_deps:
    mov rdi, scan_msg
    xor eax, eax
    call printf

    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, makefile_grep
    mov rcx, r13
    mov r8, r12
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system

    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, cmake_grep
    mov rcx, r13
    mov r8, r12
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, meson_grep
    mov rcx, r13
    mov r8, r12
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    
    mov rdi, cmd_buf
    mov rsi, 4096
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
    mov rsi, 4096
    mov rdx, cmd_fmt
    mov rcx, rax
    mov r8, r12
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf
    call system

.run_deps:
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, install_deps_cmd
    mov rcx, self_path_buf
    mov r8, r12
    xor eax, eax
    call snprintf

    mov rdi, cmd_buf
    call system

; =========================================================================
; Build system detection
; =========================================================================
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
    mov rsi, 4096
    mov rdx, make_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf
    call system
    test eax, eax
    jnz .build_fail
    jmp .post_build

.do_cmake:
    mov byte [build_type], 2
    mov rdi, msg_cmake
    xor eax, eax
    call printf
    
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, cmake_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf
    call system
    test eax, eax
    jnz .build_fail
    jmp .post_build

.do_meson:
    mov byte [build_type], 3
    mov rdi, msg_meson
    xor eax, eax
    call printf
    
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, meson_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf
    call system
    test eax, eax
    jnz .build_fail
    jmp .post_build

.do_cargo:
    mov byte [build_type], 4
    mov rdi, msg_cargo
    xor eax, eax
    call printf
    
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, cargo_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf
    call system
    test eax, eax
    jnz .build_fail
    jmp .post_build

.unsupported:
    mov rdi, msg_unsupported
    xor eax, eax
    call printf
    jmp .done

.build_fail:
    mov rdi, msg_build_fail
    xor eax, eax
    call printf
    mov eax, 1
    jmp .exit

.clone_fail:
    mov rdi, msg_clone_fail
    xor eax, eax
    call printf
    mov eax, 1
    jmp .exit

.usage:
    mov rdi, usage_msg
    xor eax, eax
    call printf
    mov eax, 1
    jmp .exit

; =========================================================================
; Post-build: save topology, then optionally package TCZ
; =========================================================================
.post_build:
    ; --- Save topology database entry ---
    call save_topology
    
    cmp byte [tcz_mode], 1
    je .tcz_pipeline
    
    ; --- Normal Linux Installation ---
    mov rdi, msg_normal_install
    xor eax, eax
    call printf
    
    cmp byte [build_type], 1
    je .norm_install_make
    cmp byte [build_type], 2
    je .norm_install_cmake
    cmp byte [build_type], 3
    je .norm_install_meson
    cmp byte [build_type], 4
    je .norm_install_cargo
    jmp .done

.norm_install_make:
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, norm_make_install_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    jmp .track_files

.norm_install_cmake:
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, norm_cmake_install_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    jmp .track_files

.norm_install_meson:
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, norm_meson_install_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    jmp .track_files

.norm_install_cargo:
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, norm_cargo_install_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    jmp .track_files

.track_files:
    cmp byte [debug_mode_g], 1
    je .tf_debug
    lea rbx, [pkg_db_prod]
    jmp .tf_run
.tf_debug:
    lea rbx, [pkg_db_dbg]
.tf_run:
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, track_files_fmt
    mov rcx, rbx
    mov r8, pkg_name_buf
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf
    call system
    jmp .done

.tcz_pipeline:
    ; --- TCZ Packaging Pipeline ---
    mov rdi, msg_tcz_staging
    xor eax, eax
    call printf
    
    mov rdi, tcz_stage_clean
    call system
    
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
    mov rsi, 4096
    mov rdx, make_install_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    jmp .tcz_squash

.tcz_install_cmake:
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, cmake_install_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    jmp .tcz_squash

.tcz_install_meson:
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, meson_install_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    jmp .tcz_squash

.tcz_install_cargo:
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, cargo_install_cmd
    mov rcx, r13
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    jmp .tcz_squash

.tcz_squash:
    mov rdi, msg_tcz_packaging
    xor eax, eax
    call printf
    
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, tcz_mksquashfs
    mov rcx, r15
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, tcz_md5
    mov rcx, r15
    mov r8, r15
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    
    mov rdi, msg_tcz_moving
    xor eax, eax
    call printf
    
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, tcz_move
    mov rcx, r15
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf
    call system
    
    mov rdi, msg_tcz_done
    xor eax, eax
    call printf
    jmp .done

; =========================================================================
; UPDATE: full system scan
; =========================================================================
.do_update_all:
    cmp r14, 1
    je .ua_debug
    mov r12, config_prod
    mov r13, build_prod
    lea rbx, [pkg_db_prod]
    jmp .ua_start
.ua_debug:
    mov r12, config_dbg
    mov r13, build_dbg
    lea rbx, [pkg_db_dbg]

.ua_start:
    mov rdi, msg_update_all
    xor eax, eax
    call printf
    
    mov rdi, rbx
    call opendir
    test rax, rax
    jz .ua_done
    mov r15, rax

.ua_loop:
    mov rdi, r15
    call readdir
    test rax, rax
    jz .ua_close
    
    lea rsi, [rax + 19]        ; d_name offset in struct dirent (Linux x86_64 glibc)
    mov rdi, dir_entry_name
.ua_copy_name:
    lodsb
    stosb
    test al, al
    jnz .ua_copy_name
    
    mov rdi, dir_entry_name
    call strlen
    cmp rax, 3
    jl .ua_loop
    
    lea rdi, [dir_entry_name + rax - 3]
    mov rsi, db_ext
    call strcmp
    cmp eax, 0
    jne .ua_loop
    
    mov rdi, dir_entry_name
    call strlen
    sub rax, 3
    mov byte [dir_entry_name + rax], 0
    
    mov rsi, dir_entry_name
    mov rdi, pkg_name_buf
.ua_copy_pkg:
    lodsb
    stosb
    test al, al
    jnz .ua_copy_pkg
    
    push rax                ; alignment padding
    push r15
    push rbx
    push r14
    push r13
    push r12
    
    call update_single_pkg
    
    pop r12
    pop r13
    pop r14
    pop rbx
    pop r15
    pop rax                 ; alignment padding
    
    jmp .ua_loop

.ua_close:
    mov rdi, r15
    call closedir
    
.ua_done:
    mov rdi, msg_update_done
    xor eax, eax
    call printf
    xor eax, eax
    jmp .exit

; =========================================================================
; UPDATE: specific package
; =========================================================================
.do_update_one:
    cmp r14, 1
    je .uo_debug
    mov r12, config_prod
    mov r13, build_prod
    lea rbx, [pkg_db_prod]
    jmp .uo_start
.uo_debug:
    mov r12, config_dbg
    mov r13, build_dbg
    lea rbx, [pkg_db_dbg]

.uo_start:
    mov rsi, r15
    mov rdi, pkg_name_buf
.uo_copy:
    lodsb
    stosb
    test al, al
    jnz .uo_copy
    
    mov rdi, db_path_buf
    mov rsi, 512
    mov rdx, db_file_fmt
    mov rcx, rbx
    mov r8, pkg_name_buf
    xor eax, eax
    call snprintf
    
    mov rdi, db_path_buf
    mov rsi, 0
    call access
    cmp eax, 0
    jne .uo_not_found
    
    call update_single_pkg
    
    mov rdi, msg_update_done
    xor eax, eax
    call printf
    xor eax, eax
    jmp .exit

.uo_not_found:
    mov rdi, msg_pkg_not_found
    mov rsi, pkg_name_buf
    xor eax, eax
    call printf
    mov eax, 1
    jmp .exit

; =========================================================================
; Common exit points for main
; =========================================================================

; =========================================================================
; UNINSTALL: remove package
; =========================================================================
.uninstall:
    mov rdi, uninstall_msg
    mov rsi, r15
    xor eax, eax
    call printf
    
    cmp byte [debug_mode_g], 1
    je .un_debug
    lea rbx, [pkg_db_prod]
    jmp .un_run
.un_debug:
    lea rbx, [pkg_db_dbg]
.un_run:
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, uninstall_sh_fmt
    mov rcx, rbx
    mov r8, r15
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf
    call system
    jmp .done

; =========================================================================
; LIST: list installed packages
; =========================================================================
.do_list_packages:
    cmp byte [debug_mode_g], 1
    je .list_debug
    lea rbx, [pkg_db_prod]
    jmp .list_run
.list_debug:
    lea rbx, [pkg_db_dbg]
.list_run:
    mov rdi, cmd_buf
    mov rsi, 4096
    mov rdx, list_sh_fmt
    mov rcx, rbx
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf
    call system
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

; =========================================================================
; save_topology - Save package metadata to db file
;   Uses globals: r13 (build_dir), r15 (URL), pkg_name_buf, build_type,
;                 debug_mode_g
; =========================================================================
save_topology:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    
    ; Preserve r13 and r15 from caller via stack frame (they're already pushed)
    mov r14, r13            ; r14 = build_dir
    mov r12, r15            ; r12 = URL
    
    ; Print saving message
    mov rdi, msg_saving_topo
    mov rsi, pkg_name_buf
    xor eax, eax
    call printf
    
    ; Determine db directory
    cmp byte [debug_mode_g], 1
    je .st_debug
    lea rbx, [pkg_db_prod]
    jmp .st_mkdir
.st_debug:
    lea rbx, [pkg_db_dbg]

.st_mkdir:
    ; mkdir -p <db_dir>
    mov rdi, cmd_buf2
    mov rsi, 4096
    mov rdx, mkdir_fmt
    mov rcx, rbx
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf2
    call system
    
    ; Format db file path: <db_dir>/<pkg_name>.db
    mov rdi, db_path_buf
    mov rsi, 512
    mov rdx, db_file_fmt
    mov rcx, rbx
    mov r8, pkg_name_buf
    xor eax, eax
    call snprintf
    
    ; Get current commit via popen
    mov rdi, cmd_buf2
    mov rsi, 4096
    mov rdx, rev_parse_fmt
    mov rcx, r14
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf2
    mov rsi, popen_read
    call popen
    test rax, rax
    jz .st_no_commit
    mov rbx, rax
    
    mov rdi, local_commit
    mov rsi, 128
    mov rdx, rbx
    call fgets
    
    mov rdi, rbx
    call pclose
    
    ; Strip trailing newline from local_commit
    mov rdi, local_commit
    call strlen
    test rax, rax
    jz .st_no_commit
    lea rcx, [local_commit + rax - 1]
    cmp byte [rcx], 10
    jne .st_write_db
    mov byte [rcx], 0
    jmp .st_write_db
    
.st_no_commit:
    mov byte [local_commit], '?'
    mov byte [local_commit + 1], 0

.st_write_db:
    ; Open db file for writing
    mov rdi, db_path_buf
    mov rsi, write_mode
    call fopen
    test rax, rax
    jz .st_done
    mov rbx, rax
    
    ; Write URL
    mov rdi, rbx
    mov rsi, db_write_url
    mov rdx, r12
    xor eax, eax
    call fprintf
    
    ; Write COMMIT
    mov rdi, rbx
    mov rsi, db_write_commit
    mov rdx, local_commit
    xor eax, eax
    call fprintf
    
    ; Write DATE (unix timestamp)
    xor edi, edi
    call time
    mov r15, rax            ; r15 = timestamp
    mov rdi, rbx
    mov rsi, db_write_date
    mov rdx, r15
    xor eax, eax
    call fprintf
    
    ; Write BUILD_TYPE
    movzx edx, byte [build_type]
    mov rdi, rbx
    mov rsi, db_write_btype
    xor eax, eax
    call fprintf
    
    ; Write BUILD_CONF (determine from build_type)
    mov rdi, rbx
    mov rsi, db_write_bconf
    
    cmp byte [build_type], 1
    je .st_conf_make
    cmp byte [build_type], 2
    je .st_conf_cmake
    cmp byte [build_type], 3
    je .st_conf_meson
    cmp byte [build_type], 4
    je .st_conf_cargo
    mov rdx, makefile_name  ; fallback
    jmp .st_conf_write
.st_conf_make:
    mov rdx, makefile_name
    jmp .st_conf_write
.st_conf_cmake:
    mov rdx, cmakelist_name
    jmp .st_conf_write
.st_conf_meson:
    mov rdx, meson_name
    jmp .st_conf_write
.st_conf_cargo:
    mov rdx, cargo_name
.st_conf_write:
    xor eax, eax
    call fprintf
    
    ; Write TCZ_MODE
    movzx edx, byte [tcz_mode]
    mov rdi, rbx
    mov rsi, db_write_tcz
    xor eax, eax
    call fprintf
    
    mov rdi, rbx
    call fclose
    
.st_done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; =========================================================================
; update_single_pkg - Check and update a single package
;   Reads: pkg_name_buf, rbx (db dir ptr), debug_mode_g
;   Uses:  stored_url, stored_commit, stored_bconf, remote_commit
; =========================================================================
update_single_pkg:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    
    ; r14 = db dir (from rbx)
    mov r14, rbx
    
    ; Clear stored buffers
    mov byte [stored_url], 0
    mov byte [stored_commit], 0
    mov byte [stored_bconf], 0
    mov byte [stored_btype], 0
    mov byte [stored_tcz], 0

    mov rdi, pkg_name_buf
    mov rsi, fowo_pkg_name
    call strcmp
    cmp eax, 0
    jne .skip_fowo_def

    mov rdi, stored_url
    mov rsi, fowo_default_repo
.copy_f_def:
    lodsb
    stosb
    test al, al
    jnz .copy_f_def
.skip_fowo_def:

    ; Print "Checking <pkg>..."
    mov rdi, msg_checking
    mov rsi, pkg_name_buf
    xor eax, eax
    call printf
    
    ; Construct db file path
    mov rdi, db_path_buf
    mov rsi, 512
    mov rdx, db_file_fmt
    mov rcx, r14
    mov r8, pkg_name_buf
    xor eax, eax
    call snprintf
    
    ; Read the db file
    mov rdi, db_path_buf
    mov rsi, read_mode
    call fopen
    test rax, rax
    jnz .usp_has_db
    cmp byte [stored_url], 0
    je .usp_done
    jmp .usp_check_remote
.usp_has_db:
    mov r12, rax            ; r12 = FILE*

.usp_read_loop:
    mov rdi, line_buf
    mov rsi, 4096
    mov rdx, r12
    call fgets
    test rax, rax
    jz .usp_read_done
    
    ; Strip trailing newline
    mov rdi, line_buf
    call strlen
    test rax, rax
    jz .usp_read_loop
    lea rcx, [line_buf + rax - 1]
    cmp byte [rcx], 10
    jne .usp_check_url
    mov byte [rcx], 0
    
.usp_check_url:
    mov rdi, line_buf
    mov rsi, db_pfx_url
    mov rdx, 4              ; strlen("URL=")
    call strncmp
    cmp eax, 0
    jne .usp_check_commit
    lea rsi, [line_buf + 4]
    mov rdi, stored_url
.usp_copy_url:
    lodsb
    stosb
    test al, al
    jnz .usp_copy_url
    jmp .usp_read_loop

.usp_check_commit:
    mov rdi, line_buf
    mov rsi, db_pfx_commit
    mov rdx, 7              ; strlen("COMMIT=")
    call strncmp
    cmp eax, 0
    jne .usp_check_bconf
    lea rsi, [line_buf + 7]
    mov rdi, stored_commit
.usp_copy_commit:
    lodsb
    stosb
    test al, al
    jnz .usp_copy_commit
    jmp .usp_read_loop

.usp_check_bconf:
    mov rdi, line_buf
    mov rsi, db_pfx_bconf
    mov rdx, 11             ; strlen("BUILD_CONF=")
    call strncmp
    cmp eax, 0
    jne .usp_check_btype
    lea rsi, [line_buf + 11]
    mov rdi, stored_bconf
.usp_copy_bconf:
    lodsb
    stosb
    test al, al
    jnz .usp_copy_bconf
    jmp .usp_read_loop

.usp_check_btype:
    mov rdi, line_buf
    mov rsi, db_pfx_btype
    mov rdx, 11             ; strlen("BUILD_TYPE=")
    call strncmp
    cmp eax, 0
    jne .usp_check_tcz
    mov al, [line_buf + 11]
    sub al, '0'                ; convert ASCII digit to integer
    mov [stored_btype], al
    jmp .usp_read_loop

.usp_check_tcz:
    mov rdi, line_buf
    mov rsi, db_pfx_tcz
    mov rdx, 9              ; strlen("TCZ_MODE=")
    call strncmp
    cmp eax, 0
    jne .usp_read_loop
    mov al, [line_buf + 9]
    sub al, 48              ; char to int
    mov [stored_tcz], al
    jmp .usp_read_loop

.usp_read_done:
    mov rdi, r12
    call fclose
    
.usp_check_remote:
    ; Check that we have a URL
    cmp byte [stored_url], 0
    je .usp_done
    
    ; --- Query remote HEAD via git ls-remote (no API hit) ---
    mov rdi, cmd_buf2
    mov rsi, 4096
    mov rdx, ls_remote_fmt
    mov rcx, stored_url
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf2
    mov rsi, popen_read
    call popen
    test rax, rax
    jz .usp_done
    mov r12, rax
    
    mov rdi, remote_commit
    mov rsi, 128
    mov rdx, r12
    call fgets
    
    mov rdi, r12
    call pclose
    
    ; Strip trailing newline from remote_commit
    mov rdi, remote_commit
    call strlen
    test rax, rax
    jz .usp_done
    lea rcx, [remote_commit + rax - 1]
    cmp byte [rcx], 10
    jne .usp_compare
    mov byte [rcx], 0

.usp_compare:
    ; Compare stored_commit vs remote_commit
    mov rdi, stored_commit
    mov rsi, remote_commit
    call strcmp
    cmp eax, 0
    je .usp_up_to_date
    
    ; --- Update available! ---
    mov rdi, msg_update_found
    mov rsi, pkg_name_buf
    xor eax, eax
    call printf
    
    mov rdi, pkg_name_buf
    mov rsi, fowo_pkg_name
    call strcmp
    cmp eax, 0
    je .do_fowo_binary_update
    
    ; Construct build dir path for this package
    cmp byte [debug_mode_g], 1
    je .usp_build_dbg
    mov rcx, build_prod
    jmp .usp_build_set
.usp_build_dbg:
    mov rcx, build_dbg
.usp_build_set:
    mov rdi, actual_build_dir
    mov rsi, 4096
    mov rdx, build_dir_fmt
    mov r8, pkg_name_buf
    xor eax, eax
    call snprintf
    
    ; Check if the build config file changed using git diff
    cmp byte [stored_bconf], 0
    je .usp_full_install

    mov rdi, cmd_buf2
    mov rsi, 4096
    mov rdx, git_diff_fmt
    mov rcx, actual_build_dir
    mov r8, stored_commit
    mov r9, stored_bconf
    xor eax, eax
    call snprintf
    
    mov rdi, cmd_buf2
    mov rsi, popen_read
    call popen
    test rax, rax
    jz .usp_full_install
    mov r12, rax
    
    mov rdi, line_buf
    mov rsi, 4096
    mov rdx, r12
    call fgets
    mov r13, rax
    
    mov rdi, r12
    call pclose
    
    ; If fgets returned NULL or empty, config did NOT change
    test r13, r13
    jz .usp_silent_rebuild
    cmp byte [line_buf], 0
    je .usp_silent_rebuild
    cmp byte [line_buf], 10
    je .usp_silent_rebuild
    
    ; Build config DID change
    jmp .usp_full_install

.usp_silent_rebuild:
    mov rdi, msg_conf_same
    xor eax, eax
    call printf
    
    cmp byte [stored_tcz], 1
    je .usp_silent_tcz
    
    cmp byte [debug_mode_g], 1
    je .usp_silent_dbg
    mov rdx, self_invoke_noedit_prod
    jmp .usp_silent_format
.usp_silent_dbg:
    mov rdx, self_invoke_noedit
    jmp .usp_silent_format
    
.usp_silent_tcz:
    cmp byte [debug_mode_g], 1
    je .usp_silent_tcz_dbg
    mov rdx, self_invoke_tcz_noedit_prod
    jmp .usp_silent_format
.usp_silent_tcz_dbg:
    mov rdx, self_invoke_tcz_noedit
    
.usp_silent_format:
    mov rdi, cmd_buf2
    mov rsi, 4096
    mov rcx, self_path_buf
    mov r8, stored_url
    xor eax, eax
    call snprintf
    jmp .usp_run_self

.usp_full_install:
    mov rdi, msg_conf_changed
    xor eax, eax
    call printf
    
    cmp byte [stored_tcz], 1
    je .usp_full_tcz
    
    cmp byte [debug_mode_g], 1
    je .usp_full_dbg
    mov rdx, self_invoke_edit_prod
    jmp .usp_full_format
.usp_full_dbg:
    mov rdx, self_invoke_edit
    jmp .usp_full_format
    
.usp_full_tcz:
    cmp byte [debug_mode_g], 1
    je .usp_full_tcz_dbg
    mov rdx, self_invoke_tcz_edit_prod
    jmp .usp_full_format
.usp_full_tcz_dbg:
    mov rdx, self_invoke_tcz_edit

.usp_full_format:
    mov rdi, cmd_buf2
    mov rsi, 4096
    mov rcx, self_path_buf
    mov r8, stored_url
    xor eax, eax
    call snprintf

.usp_run_self:
    mov rdi, cmd_buf2
    call system
    jmp .usp_done

.do_fowo_binary_update:
    mov rdi, msg_fowo_updating
    xor eax, eax
    call printf

    mov rdi, cmd_buf2
    mov rsi, 4096
    mov rdx, fowo_update_cmd
    mov rcx, stored_url
    mov r8, self_path_buf
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf2
    call system

    mov rdi, cmd_buf2
    mov rsi, 4096
    mov rdx, fowo_db_fmt1
    mov rcx, stored_url
    mov r8, r14
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf2
    call system

    mov rdi, cmd_buf2
    mov rsi, 4096
    mov rdx, fowo_db_fmt2
    mov rcx, remote_commit
    mov r8, r14
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf2
    call system

    mov rdi, cmd_buf2
    mov rsi, 4096
    mov rdx, fowo_db_fmt3
    mov rcx, r14
    mov r8, r14
    mov r9, r14
    xor eax, eax
    call snprintf
    mov rdi, cmd_buf2
    call system

    mov rdi, msg_fowo_updated
    mov rsi, remote_commit
    xor eax, eax
    call printf
    jmp .usp_done

.usp_up_to_date:
    mov rdi, msg_up_to_date
    mov rsi, pkg_name_buf
    xor eax, eax
    call printf

.usp_done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
