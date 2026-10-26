#!/usr/bin/env bash
# Testes do dev. O check.sh já os roda; este arquivo existe para rodar só
# eles, ou um arquivo específico: tools/test.sh tests/commands.bats
#
# bats-core puro, sem bibliotecas extras.
# Sem bats no PATH, baixa a versão fixada para o cache do dev (~/.cache/dev)
# conferindo o sha256. Nada é instalado no sistema.
#
# Código de saída 2 indica que não há bats e não foi possível baixá-lo.

set -uo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." || exit 1

BATS_VERSION="1.14.0"
BATS_SHA256="bb537b70b15b732f6d8827dd6578e3d8ce166636ce1f18ea9a074184fcce9177"

find_bats() {
  command -v bats 2>/dev/null && return 0
  local cache="${DEV_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/dev}/bats-core-$BATS_VERSION"
  if [[ ! -x "$cache/bin/bats" ]]; then
    local tmp
    tmp="$(mktemp -d)" || return 1
    curl -fsSL -o "$tmp/bats.tgz" \
      "https://github.com/bats-core/bats-core/archive/refs/tags/v$BATS_VERSION.tar.gz" \
      || { rm -rf "$tmp"; return 1; }
    if ! printf '%s  %s\n' "$BATS_SHA256" "$tmp/bats.tgz" | sha256sum -c --quiet - >/dev/null 2>&1; then
      echo "o bats baixado não confere com o sha256 fixado em tools/test.sh" >&2
      rm -rf "$tmp"; return 1
    fi
    mkdir -p "$cache" && tar -xzf "$tmp/bats.tgz" -C "$cache" --strip-components=1 \
      || { rm -rf "$tmp" "$cache"; return 1; }
    rm -rf "$tmp"
  fi
  printf '%s\n' "$cache/bin/bats"
}

bats_bin="$(find_bats)" || {
  echo "bats indisponível: instale (sudo apt install bats) ou deixe a rede baixá-lo" >&2
  exit 2
}

exec "$bats_bin" --print-output-on-failure "${@:-tests}"
