#!/bin/bash
# Conferências rápidas antes de qualquer commit:
#   1. sintaxe Lua 5.1 (a do WoW) em todos os arquivos do addon;
#   2. tabelas de tradução (regra 3 do CLAUDE.md).
#
# O acumulado de 241 chaves sem EN foi zerado na v1.37.1, então a conferência de locale DERRUBA o
# check: chave nova sem tradução não passa mais. `--solto` volta ao modo relatório, se um dia for
# preciso commitar no meio de uma tradução.
# Uso: ./tools/check.sh          (sintaxe + locale, falha se faltar tradução)
#      ./tools/check.sh --solto  (só relata)
cd "$(dirname "$0")/.."
bad=0

for f in Brand.lua Shell.lua $(find Craft Livro -name '*.lua'); do luac5.1 -p "$f" || bad=1; done
[ $bad = 0 ] && echo "sintaxe ok"

if command -v python >/dev/null 2>&1; then
  if [ "$1" = "--solto" ]; then
    python -I tools/loccheck.py | grep -vE "^     " | tail -8
  else
    # o status tem de vir do python: num pipe o $? é o do último comando (era o do tail, que
    # sempre dá 0 — por isso o --strict não derrubava nada)
    saida=$(python -I tools/loccheck.py --strict); rc=$?
    printf '%s\n' "$saida" | grep -vE "^     \[" | tail -12
    [ "$rc" -ne 0 ] && bad=1
  fi
else
  echo "(python não encontrado: conferência de locale pulada)"
fi

exit $bad
