# ==============================================================================
# silicyOS Ultra-Fast Zsh Configuration (< 15ms Cold Startup, Zero Frameworks)
# ==============================================================================

[[ $- != *i* ]] && return

# --- History (In-RAM Optimized, Deduplicated) ---
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh_history"
[[ -d "${HISTFILE:h}" ]] || mkdir -p "${HISTFILE:h}"
HISTSIZE=4000
SAVEHIST=4000
setopt HIST_IGNORE_ALL_DUPS HIST_FIND_NO_DUPS HIST_REDUCE_BLANKS \
       INC_APPEND_HISTORY_TIME SHARE_HISTORY AUTO_CD INTERACTIVE_COMMENTS \
       PROMPT_SUBST NO_BEEP

# --- Fast Completion Caching (Rebuilds Once Per 24h) ---
autoload -Uz compinit
_zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
[[ -d "${_zcompdump:h}" ]] || mkdir -p "${_zcompdump:h}"
if [[ -n ${_zcompdump}(#qN.mh+24) ]]; then
    compinit -d "$_zcompdump"
else
    compinit -C -d "$_zcompdump"
fi
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# --- Minimal Native Git + Command Execution Timer Prompt ---
zmodload zsh/datetime

_silicy_preexec() {
    _cmd_start_time=$EPOCHREALTIME
}

_silicy_precmd() {
    local exit_code=$?
    _cmd_duration=""
    if (( $+_cmd_start_time )); then
        local elapsed=$(( (EPOCHREALTIME - _cmd_start_time) * 1000 ))
        unset _cmd_start_time
        if (( elapsed >= 1000 )); then
            _cmd_duration=$(printf " %%F{221}%.2fs%%f" $(( elapsed / 1000.0 )))
        elif (( elapsed >= 25 )); then
            _cmd_duration=$(printf " %%F{244}%.0fms%%f" $elapsed)
        fi
    fi

    _git_branch=""
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        local branch
        branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
        [[ -n "$branch" ]] && _git_branch=" %F{183}󰊢 ${branch}%f"
    fi
    return $exit_code
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _silicy_preexec
add-zsh-hook precmd _silicy_precmd

PROMPT='%F{117}%~%f${_git_branch}${_cmd_duration} %(?.%F{114}❯%f.%F{203}❯%f) '
RPROMPT=''

# --- Keybindings ---
bindkey -e
bindkey '^[[3~' delete-char
bindkey '^[[H'  beginning-of-line
bindkey '^[[F'  end-of-line

# --- Pacman & Btrfs zstd:3 Power Aliases ---
alias pacs='sudo pacman -Syu'
alias paci='sudo pacman -S --needed'
alias pacr='sudo pacman -Rns'
alias pacq='pacman -Ss'
alias pacc='sudo pacman -Scc --noconfirm && sudo paccache -rk1'
alias pacorph='sudo pacman -Rns $(pacman -Qtdq)'

alias btrfs-usage='sudo compsize -x /'
alias btrfs-df='sudo btrfs filesystem df / && sudo btrfs filesystem usage -h /'
alias btrfs-recomp='sudo btrfs filesystem defragment -r -v -czstd:3 /'
alias btrfs-sub='sudo btrfs subvolume list /'
alias btrfs-scrub='sudo btrfs scrub start / && sudo btrfs scrub status /'

alias ls='ls --color=auto -Fh'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'
alias ff='fastfetch'
alias power-watts='silicy-ctl telemetry --power'
alias center='silicy-center'
alias capsule='sudo silicy-capsule'
alias macos-mount='silicy-macos-bridge mount'
alias macos-umount='silicy-macos-bridge umount'
