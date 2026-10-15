#!/bin/bash
# Compara duas rodadas do run_all.sh mostrando só o que é diferença de verdade.
#
# O ruído que sobrava a cada rodada e precisava ser filtrado à mão:
#   - endereço de tabela do Lua ("table: 013A0998"), que muda a cada execução;
#   - o caminho do addon, que na rodada base vem de ../../baseline/RoyalRevenue/ e na nova de ../ ;
#   - o caminho do interpretador no erro ("C:\Program Files (x86)\Lua\5.1\lua.exe:");
#   - tempos e datas.
# Uso: ./diff.sh out_base out        (ou: ./diff.sh out_base out -v  para o diff completo)
cd "$(dirname "$0")"
A=${1:-out_base}; B=${2:-out}
LINHAS=12
[ "$3" = "-v" ] && LINHAS=100000

norm() {
  grep -v " ms$" "$1" | sed -E '
    s/^[^ ]*lua(5\.1)?(\.exe)?:/lua:/;
    s#[A-Za-z]:\\[^:]*lua(5\.1)?\.exe:#lua:#;
    s/0x[0-9a-fA-F]+/ADDR/g;
    s/(table|function|userdata): [0-9A-Fa-f]+/\1: ADDR/g;
    s#[^[:space:]]*[/\\]baseline[/\\]RoyalRevenue[/\\]#ADDON/#g;
    s#[^[:space:]]*/RoyalRevenue/#ADDON/#g;
    s#(^|[[:space:]])\.\./#\1ADDON/#g;
    s/[0-9]{2}\/[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}/DD\/MM HH:MM:SS/g'
}

n=0
for f in "$A"/*.txt; do
  g="$B/$(basename "$f")"
  if [ ! -f "$g" ]; then echo "== $(basename "$f")  (só na base)"; n=$((n+1)); continue; fi
  if ! diff -q <(norm "$f") <(norm "$g") >/dev/null 2>&1; then
    echo "== $(basename "$f")"; diff <(norm "$f") <(norm "$g") | head -$LINHAS; n=$((n+1))
  fi
done
for g in "$B"/*.txt; do
  [ -f "$A/$(basename "$g")" ] || { echo "== $(basename "$g")  (teste novo)"; n=$((n+1)); }
done
echo "arquivos diferentes: $n"
