#!/bin/bash
# Gera dist/RoyalRevenue-v<versão>.zip com a pasta RoyalRevenue/ (versão lida do .toc)
cd "$(dirname "$0")/.."
./tools/check.sh || exit 1
V=$(grep -m1 '^## Version:' RoyalRevenue/RoyalRevenue.toc | sed 's/.*: *//; s/\r//')
mkdir -p dist
rm -f "dist/RoyalRevenue-v$V.zip"
zip -qr "dist/RoyalRevenue-v$V.zip" RoyalRevenue -x '*.orig' && echo "dist/RoyalRevenue-v$V.zip"
