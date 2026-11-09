# .bashrc

# Claude Code and user binaries (also for non-interactive shells, e.g. ssh)
export PATH="$HOME/.local/bin:$PATH"

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
PS1='[\u@\h \W]\$ '
