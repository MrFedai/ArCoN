#!/usr/bin/env bash
# ArCoN v3.0 -- modules/shell.sh
# v2.5 "Sector 8 / Step B: Shell (zsh/fish/bash) + themes" and the Nerd Font step.
#
# v2.5 → v3.0
#   * oh-my-zsh installed with `sh -c "$(curl ...)"`      → git clone + upstream .zshrc template
#   * starship installed with `curl | sh`                 → distro package, else GitHub release
#                                                            verified with the upstream .sha256 file
#   * starship preset "pastel" is not a valid preset      → pastel-powerline (verified against
#                                                            starship v1.26.0 presets)
#   * `sed -i` on .zshrc with no backup                   → journaled backup, idempotent edit
#   * chsh without checking /etc/shells                   → shell registered check + confirmation
#   * fonts: Arch only, others just printed a notice      → catalog entry for Arch/macOS/Windows,
#                                                            clear manual note elsewhere

ARCON_MODULE=shell
ZSH_THEMES=("agnoster" "robbyrussell" "bira" "powerlevel10k")
# verified against starship v1.26.0 docs/public/presets/toml
STARSHIP_PRESETS=("default" "pastel-powerline" "tokyo-night" "pure-preset" "gruvbox-rainbow")
STARSHIP_VERSION_FALLBACK=v1.26.0

mod_shell_wizard() {
    local cur choice; cur="$(basename "${SHELL:-bash}")"
    ui_say "  ${DIM}(Current shell: $cur)${NC}"
    ui_choose choice "$(cfg SHELL_TARGET skip)" "=== PREFERRED SHELL & THEME CONFIG ===" \
        "zsh:Zsh (themes: agnoster, robbyrussell, bira, powerlevel10k)" \
        "fish:Fish (Starship presets)" "bash:Bash (Starship presets)" "skip:Skip"
    cfg_set SHELL_TARGET "$choice" wizard
    case "$choice" in
        zsh)
            local opts=() t
            for t in "${ZSH_THEMES[@]}"; do opts+=("$t:$t"); done
            ui_choose t "$(cfg SHELL_ZSH_THEME agnoster)" "=== ZSH THEME ===" "${opts[@]}"
            cfg_set SHELL_ZSH_THEME "$t" wizard ;;
        fish|bash)
            local opts=() p
            for p in "${STARSHIP_PRESETS[@]}"; do opts+=("$p:$p"); done
            ui_choose p "$(cfg SHELL_STARSHIP_PRESET default)" "=== STARSHIP PRESET ===" "${opts[@]}"
            cfg_set SHELL_STARSHIP_PRESET "$p" wizard ;;
    esac
    if [[ "$choice" != skip ]]; then ui_confirm_set SHELL_CHSH y "Set $choice as your default login shell"; fi
    return 0
}

mod_shell_plan() {
    local t; t="$(cfg SHELL_TARGET skip)"
    [[ "$t" == skip ]] && { cfg_bool SHELL_FONT yes && task_add shell.font low "Install JetBrainsMono Nerd Font" shell_font; return 0; }
    case "$t" in
        zsh)
            task_add shell.zsh_pkg low "Install zsh" shell_zsh_pkg
            task_add shell.omz low "Install Oh-My-Zsh + plugins (git clone)" shell_omz
            task_add shell.zsh_theme low "Configure .zshrc (theme $(cfg SHELL_ZSH_THEME), plugins)" shell_zsh_theme ;;
        fish)
            task_add shell.fish_pkg low "Install fish" shell_fish_pkg
            task_add shell.starship low "Install starship" shell_starship
            task_add shell.fish_cfg low "Configure fish + starship preset $(cfg SHELL_STARSHIP_PRESET)" shell_fish_cfg ;;
        bash)
            task_add shell.starship low "Install starship" shell_starship
            task_add shell.bash_cfg low "Configure .bashrc + starship preset $(cfg SHELL_STARSHIP_PRESET)" shell_bash_cfg ;;
    esac
    cfg_bool SHELL_FONT yes && task_add shell.font low "Install JetBrainsMono Nerd Font" shell_font
    cfg_bool SHELL_CHSH yes && task_add shell.chsh medium "Set $t as the default login shell" shell_chsh
    return 0
}

shell_zsh_pkg()  { pkg_install_ids zsh git curl; }
shell_fish_pkg() { pkg_install_ids fish; }

shell_omz() {
    local omz="$ARCON_HOME/.oh-my-zsh" custom="${ZSH_CUSTOM:-$ARCON_HOME/.oh-my-zsh/custom}"
    if [[ -d "$omz/.git" ]]; then log_info "oh-my-zsh already installed"
    elif [[ -e "$omz" ]]; then log_warn "$omz exists but is not a git checkout — left untouched"
    else
        x_user COMMAND "clone oh-my-zsh" -- git clone --depth 1 "$(cfg OHMYZSH_REPO)" "$omz" || return 1
        rb_add FILE "$omz" ABSENT user
    fi
    # pairs of "<subdir under $custom>" "<repo url>" (no ':' splitting: URLs contain ':')
    local -a plugins=(
        "plugins/zsh-autosuggestions"      "$(cfg ZSH_AUTOSUGGESTIONS_REPO)"
        "plugins/zsh-syntax-highlighting"  "$(cfg ZSH_SYNTAX_REPO)"
    )
    local i dir url
    for (( i = 0; i < ${#plugins[@]}; i += 2 )); do
        dir="$custom/${plugins[i]}"; url="${plugins[i+1]}"
        if [[ -d "$dir/.git" ]]; then log_debug "present: $dir"; continue; fi
        x_user COMMAND "clone $(basename "$dir")" -- git clone --depth 1 "$url" "$dir" || return 1
        rb_add FILE "$dir" ABSENT user
    done
    local dir2
    if [[ "$(cfg SHELL_ZSH_THEME)" == powerlevel10k ]]; then
        dir2="$custom/themes/powerlevel10k"
        if [[ ! -d "$dir2/.git" ]]; then
            x_user COMMAND "clone powerlevel10k" -- git clone --depth 1 "$(cfg POWERLEVEL10K_REPO)" "$dir2" || return 1
            rb_add FILE "$dir2" ABSENT user
        fi
    fi
}

shell_zsh_theme() {
    local theme; theme="$(cfg SHELL_ZSH_THEME agnoster)"
    local val="$theme"; [[ "$theme" == powerlevel10k ]] && val="powerlevel10k/powerlevel10k"
    local zshrc="$ARCON_HOME/.zshrc" tpl="$ARCON_HOME/.oh-my-zsh/templates/zshrc.zsh-template"
    if [[ ! -f "$zshrc" ]]; then
        if [[ -f "$tpl" ]]; then fs_install_file "$tpl" "$zshrc" || return 1
        elif ! is_dry_run; then log_error "no .zshrc and no oh-my-zsh template found"; return 1; fi
    fi
    fs_set_kv "$zshrc" '^ZSH_THEME=' "ZSH_THEME=\"$val\"" || return 1
    fs_set_kv "$zshrc" '^plugins=\(' 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' || return 1
    is_dry_run || log_result "zsh theme" PASS "$val"
}

shell_starship() {
    if command -v starship >/dev/null 2>&1; then log_info "starship already installed"; return 0; fi
    if pkg_available starship; then pkg_install starship && return 0; fi
    log_warn "starship is not packaged for $OS_ID $OS_VERSION — installing the official release binary (checksum verified)"
    local target ver tag tgz sum_url dest="$ARCON_TMP/starship.tar.gz"
    case "$OS_FAMILY:$HW_ARCH" in
        linux:x86_64)  target=x86_64-unknown-linux-gnu ;;
        linux:aarch64) target=aarch64-unknown-linux-musl ;;
        macos:arm64)   target=aarch64-apple-darwin ;;
        macos:x86_64)  target=x86_64-apple-darwin ;;
        *) log_error "no starship release for $OS_FAMILY/$HW_ARCH"; return 1 ;;
    esac
    tag="$(curl -fsSL --max-time 20 https://api.github.com/repos/starship/starship/releases/latest 2>/dev/null |
           grep -m1 '"tag_name"' | cut -d'"' -f4)"
    [[ -n "$tag" ]] || tag="$STARSHIP_VERSION_FALLBACK"
    tgz="https://github.com/starship/starship/releases/download/$tag/starship-$target.tar.gz"
    sum_url="$tgz.sha256"
    if is_dry_run; then
        plan_record PKG_INSTALL "starship $tag from $tgz (sha256 from $sum_url) into /usr/local/bin"
        return 0
    fi
    local want; want="$(curl -fsSL --max-time 20 "$sum_url" | awk '{print $1}')"
    [[ "$want" =~ ^[0-9a-f]{64}$ ]] || { log_error "could not fetch the upstream sha256 for starship — aborting"; return 1; }
    fetch_to "$tgz" "$dest" "$want" || return 1
    local work; work="$(mktemp -d)"
    tar -xzf "$dest" -C "$work" || { rm -rf "$work"; return 1; }
    x_root FILE "install starship $tag to /usr/local/bin" -- install -m 0755 "$work/starship" /usr/local/bin/starship
    local rc=$?; rm -rf "$work"
    (( rc == 0 )) && rb_add FILE /usr/local/bin/starship ABSENT root
    return $rc
}

shell_starship_preset() {
    local preset; preset="$(cfg SHELL_STARSHIP_PRESET default)"
    [[ "$preset" == default ]] && { log_info "using the default starship prompt"; return 0; }
    local valid=0 p
    for p in "${STARSHIP_PRESETS[@]}"; do [[ "$p" == "$preset" ]] && valid=1; done
    (( valid )) || { log_error "unknown starship preset '$preset' (valid: ${STARSHIP_PRESETS[*]})"; return 1; }
    if is_dry_run; then plan_record FILE "$ARCON_HOME/.config/starship.toml <- starship preset $preset"; return 0; fi
    local tmp="$ARCON_TMP/starship.toml"
    starship preset "$preset" -o "$tmp" || { log_error "starship preset $preset failed"; return 1; }
    fs_install_file "$tmp" "$ARCON_HOME/.config/starship.toml"
}

shell_fish_cfg() {
    fs_append_once "$ARCON_HOME/.config/fish/config.fish" "starship init fish | source" || return 1
    shell_starship_preset
}

shell_bash_cfg() {
    # shellcheck disable=SC2016  # the line is written literally into ~/.bashrc
    fs_append_once "$ARCON_HOME/.bashrc" 'eval "$(starship init bash)"' || return 1
    shell_starship_preset
}

shell_font() {
    if catalog_field font-jetbrains-nerd "$(platform_catalog_column)" | grep -qv '^-$'; then
        pkg_install_ids font-jetbrains-nerd && return 0
    fi
    if command -v fc-list >/dev/null 2>&1 && fc-list 2>/dev/null | grep -q "JetBrainsMono Nerd Font"; then
        log_result "JetBrainsMono Nerd Font" PASS "already installed"; return 0
    fi
    log_warn "JetBrainsMono Nerd Font is not packaged for $OS_ID — install it manually from https://github.com/ryanoasis/nerd-fonts/releases (needed for prompt icons)"
    rb_add NOTE "Nerd Font not installed automatically on $OS_ID (documented manual step)"
    return "$TASK_SKIP"
}

shell_chsh() {
    local t path cur
    t="$(cfg SHELL_TARGET)"
    path="$(command -v "$t" 2>/dev/null)"
    if [[ -z "$path" ]]; then
        if is_dry_run; then path="/usr/bin/$t"   # not installed yet: plan with the usual path
        else log_error "$t not found in PATH after installation"; return 1; fi
    fi
    cur="$(getent passwd "$ARCON_USER" 2>/dev/null | cut -d: -f7)"
    [[ -n "$cur" ]] || cur="$(dscl . -read "/Users/$ARCON_USER" UserShell 2>/dev/null | awk '{print $2}')"
    if [[ "$cur" == "$path" ]]; then log_info "$ARCON_USER already uses $path"; return 0; fi
    if ! is_dry_run && ! grep -qx "$path" /etc/shells 2>/dev/null; then
        log_warn "$path is not listed in /etc/shells; adding it (required by chsh)"
        fs_append_once /etc/shells "$path" root || return 1
    fi
    rb_add SHELL "$ARCON_USER" "$cur"
    x_root SETTING "change login shell of $ARCON_USER to $path (was $cur)" -- chsh -s "$path" "$ARCON_USER" || return 1
    log_warn "log out and back in for the new shell to take effect"
}
