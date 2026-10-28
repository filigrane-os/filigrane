#!/bin/bash
# Status line Claude Code: modèle, effort, dossier, branche git, usage du contexte.
# Entrée: JSON sur stdin, transmis aussi au module IA de la fili-bar (contexte, coût, limites du forfait).
input=$(cat)
[ -x "$HOME/.local/bin/fili-ai-session" ] && "$HOME/.local/bin/fili-ai-session" status <<<"$input" >/dev/null 2>&1

model=$(jq -r '.model.display_name // "?"' <<<"$input")
effort=$(jq -r '.effort.level // empty' <<<"$input")
dir=$(jq -r '.workspace.current_dir // .cwd // "."' <<<"$input")
size=$(jq -r '.context_window.context_window_size // 200000' <<<"$input")
pct=$(jq -r '.context_window.used_percentage // empty' <<<"$input")

if [ -z "$pct" ]; then
    pct=0
fi
pct=${pct%.*}
used=$((size * pct / 100))

branch=$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null \
    || git -C "$dir" rev-parse --short HEAD 2>/dev/null)

# Couleur selon remplissage
if   [ "$pct" -ge 80 ]; then c=31
elif [ "$pct" -ge 50 ]; then c=33
else c=32; fi

# Barre de 10 cases
filled=$((pct / 10)); [ "$filled" -gt 10 ] && filled=10
bar=""
for i in 0 1 2 3 4 5 6 7 8 9; do
    if [ "$i" -lt "$filled" ]; then bar+="█"; else bar+="░"; fi
done

fmt() { awk -v n="$1" 'BEGIN{ if (n>=1000) printf "%.0fk", n/1000; else printf "%d", n }'; }

out="\033[36m${model}\033[0m"
[ -n "$effort" ] && out+=" \033[33m${effort}\033[0m"
out+=" \033[90m│\033[0m \033[34m${dir/#$HOME/\~}\033[0m"
[ -n "$branch" ] && out+=" \033[90m│\033[0m \033[35m ${branch}\033[0m"
out+=" \033[90m│\033[0m \033[${c}m${bar} ${pct}%\033[0m \033[90m($(fmt "$used")/$(fmt "$size"))\033[0m"
printf '%b' "$out"
