#!/bin/bash
# Sintaxe Lua 5.1 (a do WoW) em todos os arquivos do addon
cd "$(dirname "$0")/.."
bad=0
for f in Brand.lua Shell.lua $(find Craft Livro -name '*.lua'); do luac5.1 -p "$f" || bad=1; done
[ $bad = 0 ] && echo "sintaxe ok"
exit $bad
