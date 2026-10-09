#!/bin/bash
# Gera dist/RoyalRevenue-v<versão>.zip com a pasta RoyalRevenue/ (versão lida do .toc)
cd "$(dirname "$0")/.."
./tools/check.sh || exit 1
V=$(grep -m1 '^## Version:' RoyalRevenue.toc | sed 's/.*: *//; s/\r//')
mkdir -p dist
rm -f "dist/RoyalRevenue-v$V.zip"
tmp=$(mktemp -d)
mkdir "$tmp/RoyalRevenue"
cp -r Brand.lua Shell.lua Craft Livro Media RoyalRevenue.toc "$tmp/RoyalRevenue/"
(cd "$tmp" && zip -qr "RoyalRevenue-v$V.zip" RoyalRevenue -x '*.orig')
mv "$tmp/RoyalRevenue-v$V.zip" dist/
rm -rf "$tmp"
echo "dist/RoyalRevenue-v$V.zip"
