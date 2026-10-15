#!/bin/bash
# Conferências rápidas antes de qualquer commit:
#   1. sintaxe Lua 5.1 (a do WoW) em todos os arquivos do addon;
#   2. tabelas de tradução (regra 3 do CLAUDE.md).
#
# A conferência de locale não derruba o check por causa do acumulado de chaves sem EN que já
# existia quando ela foi criada. Com o acumulado zerado, trocar por --strict faz o check falhar
# em qualquer chave nova sem tradução, que é o objetivo.
# Uso: ./tools/check.sh          (sintaxe + relatório de locale)
#      ./tools/check.sh --strict (falha também se faltar tradução)
cd "$(dirname "$0")/.."
bad=0

for f in Brand.lua Shell.lua $(find Craft Livro -name '*.lua'); do luac5.1 -p "$f" || bad=1; done
[ $bad = 0 ] && echo "sintaxe ok"

if command -v python >/dev/null 2>&1; then
  if [ "$1" = "--strict" ]; then
    python -I tools/loccheck.py --strict | tail -20 || bad=1
  else
    python -I tools/loccheck.py | grep -vE "^     " | tail -8
  fi
else
  echo "(python não encontrado: conferência de locale pulada)"
fi

exit $bad
