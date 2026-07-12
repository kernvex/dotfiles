set -gx XDG_CONFIG_HOME $HOME/.config
set -gx EDITOR nvim
set -gx GIT_EDITOR nvim
# Pin the locale so Python/Perl/etc. don't emit "setlocale" warnings when the
# terminal forwards an unset or exotic LC_*.
set -gx LANG en_US.UTF-8
set -gx DOTFILES $HOME/6eniu5/dotfiles
set -q CU_OWNER; or set -gx CU_OWNER $USER
set -gx PNPM_HOME $HOME/Library/pnpm

test -d $HOME/.local/bin; and fish_add_path $HOME/.local/bin
test -d $HOME/.local/scripts; and fish_add_path $HOME/.local/scripts
test -d $HOME/.cargo/bin; and fish_add_path $HOME/.cargo/bin
test -d $HOME/.bun/bin; and fish_add_path $HOME/.bun/bin
test -d $PNPM_HOME; and fish_add_path $PNPM_HOME
test -d $HOME/go/bin; and fish_add_path $HOME/go/bin
# proxy.golang.org intermittently 403s on some module zips, and Go only falls
# back to the next proxy on 404/410 (not 403), so add goproxy.io as a backstop.
set -gx GOPROXY https://proxy.golang.org,https://goproxy.io,direct

if test -x /opt/homebrew/bin/brew
  eval (/opt/homebrew/bin/brew shellenv)
else if test -x /usr/local/bin/brew
  eval (/usr/local/bin/brew shellenv)
end

# $HOMEBREW_PREFIX is exported by `brew shellenv` above — reuse it instead of
# spawning a `brew --prefix` subprocess on every shell startup.
set -l brew_prefix $HOMEBREW_PREFIX
if test -n "$brew_prefix" -a -d "$brew_prefix/opt/gnu-sed/libexec/gnubin"
  fish_add_path --prepend "$brew_prefix/opt/gnu-sed/libexec/gnubin"
end

if test -z "$JAVA_HOME" -a -x /usr/libexec/java_home
  set -gx JAVA_HOME (/usr/libexec/java_home -v 21 2>/dev/null)
  test -n "$JAVA_HOME"; and fish_add_path "$JAVA_HOME/bin"
end

fish_vi_key_bindings

function fish_greeting
end

# Prefer Homebrew CLI tools from setup.sh. Use `command cat`, `command ls`, `command grep`, `command find`, etc. for originals.
command -v nvim >/dev/null; and alias vim nvim
command -v eza >/dev/null; and alias ls eza
command -v bat >/dev/null; and alias cat 'bat --paging=never'
command -v rg >/dev/null; and alias grep rg
command -v rg >/dev/null; and alias egrep rg
command -v rg >/dev/null; and alias fgrep 'rg -F'
# fd is installed as `fd`; it is not a POSIX find replacement (different flags). Use `command find` for find(1) syntax.
command -v lazygit >/dev/null; and alias lg lazygit

# bash-style history recall: !! = previous command, !$ = its last argument
function _last_history_item
  echo $history[1]
end
function _last_history_arg
  set -l tokens (string split --no-empty -- ' ' $history[1])
  echo $tokens[-1]
end
abbr -a '!!' --position anywhere --function _last_history_item
abbr -a '!$' --position anywhere --function _last_history_arg

test -z "$MANPAGER"; and command -v bat >/dev/null; and set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"

function la --wraps=ls --wraps=eza --description 'List contents of directory using eza grid'
  eza --grid --icons -a --long --header --accessed --group-directories-first $argv
end

function ll --wraps=ls --wraps=eza --description 'List contents of directory using eza tree'
  eza --tree --level=2 -a --long --header --accessed --git $argv
end

function lla --wraps=ls --wraps=eza --description 'List contents of directory using eza tree'
  eza --tree --level=1 -a --long --header --accessed --group-directories-first $argv
end

function lll --wraps=ls --wraps=eza --description 'List contents of directory using eza tree'
  eza --tree --level=2 -a --long --header --accessed --group-directories-first $argv
end

function llll --wraps=ls --wraps=eza --description 'List contents of directory using eza tree'
  eza --tree --level=3 -a --long --header --accessed --group-directories-first $argv
end

bind \cf 'tmux-sessionizer; commandline -f repaint'
bind -M insert \cf 'tmux-sessionizer; commandline -f repaint'

bind \eh 'tmux-sessionizer -s 0; commandline -f repaint'
bind -M insert \eh 'tmux-sessionizer -s 0; commandline -f repaint'
bind \et 'tmux-sessionizer -s 1; commandline -f repaint'
bind -M insert \et 'tmux-sessionizer -s 1; commandline -f repaint'
bind \en 'tmux-sessionizer -s 2; commandline -f repaint'
bind -M insert \en 'tmux-sessionizer -s 2; commandline -f repaint'
bind \es 'tmux-sessionizer -s 3; commandline -f repaint'
bind -M insert \es 'tmux-sessionizer -s 3; commandline -f repaint'

test -f "$HOME/.cargo/env.fish"; and source "$HOME/.cargo/env.fish"

# fnm and mise both manage Node; activating both lets mise (loaded second) shadow
# fnm's shims. Prefer fnm (what esetup installs); fall back to mise only if fnm is absent.
if command -v fnm >/dev/null 2>&1
  fnm env --use-on-cd --shell fish | source
else if command -v mise >/dev/null 2>&1
  mise activate fish | source
end
# fzf shell integration (Ctrl-T files, Alt-C cd). Loaded before atuin so atuin keeps Ctrl-R.
command -v fzf >/dev/null 2>&1; and fzf --fish | source
command -v atuin >/dev/null 2>&1; and atuin init fish | source
command -v zoxide >/dev/null 2>&1; and zoxide init fish | source
command -v starship >/dev/null 2>&1; and starship init fish | source

if test -f /opt/homebrew/Caskroom/miniconda/base/etc/fish/conf.d/conda.fish
  source /opt/homebrew/Caskroom/miniconda/base/etc/fish/conf.d/conda.fish
else if test -f /usr/local/Caskroom/miniconda/base/etc/fish/conf.d/conda.fish
  source /usr/local/Caskroom/miniconda/base/etc/fish/conf.d/conda.fish
end

if test -d $HOME/.sdkman
  set -gx SDKMAN_DIR $HOME/.sdkman
end

alias refresh_gh_token 'set -gx GITHUB_TOKEN (gh auth token)'
