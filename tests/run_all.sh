#!/bin/bash
# Roda os testes t*.lua e grava a saída de cada um em out/<nome>.txt
# Uso: ./run_all.sh [pasta_do_addon] [pasta_de_saida] [--legacy]
#   padrão: ../  e  out/
# Os testes são de REGRESSÃO POR DIFF: compare a saída com a de antes da mudança
# (./run_all.sh ../baseline/ out_base  e depois  ./diff.sh out_base out).
#
# legacy/: 32 testes de funcionalidade que mudou depois deles e que terminam em erro desde então.
# Ficam fora da rodada normal (só inflavam a contagem e o ruído do diff); --legacy inclui de volta.
cd "$(dirname "$0")"
DIR=${1:-../}; OUT=${2:-out}
mkdir -p "$OUT"

ARQS=$(ls t*.lua 2>/dev/null)
for a in "$@"; do [ "$a" = "--legacy" ] && ARQS="$ARQS $(ls legacy/t*.lua 2>/dev/null)"; done

for f in $ARQS; do
  nome=$(basename "$f" .lua)
  timeout 120 lua5.1 -e "ADDON_DIR='$DIR'" "$f" > "$OUT/$nome.txt" 2>&1
  echo "exit $?" >> "$OUT/$nome.txt"
done
echo "ok: $(ls "$OUT" | wc -l) saídas em $OUT"
