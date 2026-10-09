#!/bin/bash
# Roda todos os testes t*.lua e grava a saída de cada um em out/<nome>.txt
# Uso: ./run_all.sh [pasta_do_addon] [pasta_de_saida]
#   padrão: ../  e  out/
# Os testes são de REGRESSÃO POR DIFF: compare a saída com a de antes da mudança
# (./run_all.sh ../baseline/ out_base  e depois  ./diff.sh out_base out).
cd "$(dirname "$0")"
DIR=${1:-../}; OUT=${2:-out}
mkdir -p "$OUT"
for f in t*.lua; do
  timeout 120 lua5.1 -e "ADDON_DIR='$DIR'" "$f" > "$OUT/${f%.lua}.txt" 2>&1
  echo "exit $?" >> "$OUT/${f%.lua}.txt"
done
echo "ok: $(ls "$OUT" | wc -l) saídas em $OUT"
