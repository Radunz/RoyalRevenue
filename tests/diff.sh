#!/bin/bash
# Compara duas rodadas do run_all.sh ignorando tempos (" ms"), endereços de tabela e caminho do addon.
# Uso: ./diff.sh out_base out
cd "$(dirname "$0")"
A=${1:-out_base}; B=${2:-out}
norm() { grep -v " ms$" "$1" | sed -E 's/^lua(5\.1)?:/lua:/; s/0x[0-9a-f]+//g; s#[^ ]*/RoyalRevenue/#RoyalRevenue/#g; s/[0-9]{2}\/[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}/DD\/MM HH:MM:SS/g'; }
n=0
for f in "$A"/*.txt; do
  g="$B/$(basename "$f")"
  if ! diff -q <(norm "$f") <(norm "$g") >/dev/null 2>&1; then
    echo "== $(basename "$f")"; diff <(norm "$f") <(norm "$g") | head -12; n=$((n+1))
  fi
done
echo "arquivos diferentes: $n"
