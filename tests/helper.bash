#!/usr/bin/env bash
# Carregado por todos os arquivos de teste BATS.
#
# Cada teste roda num sandbox hermético: HOME, DEV_HOME e DEV_CACHE dentro do
# diretório temporário do bats, apagado ao final. Nada toca o ~/.dev da máquina.

ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

# shellcheck source=../versions.sh
source "$ROOT/versions.sh"

PHP_VERSION_SERIES="8.5"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export DEV_HOME="$BATS_TEST_TMPDIR/sandbox"
  export DEV_CACHE="$BATS_TEST_TMPDIR/cache"
  export NO_COLOR=1
  unset DEV_YES
  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$HOME" "$DEV_HOME" "$TEST_PROJECT"
  STUBS_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUBS_BIN"
  export PATH="$STUBS_BIN:$PATH"
}

stub() {
  cat > "$STUBS_BIN/$1" <<STUB
#!/usr/bin/env bash
printf '%s %s\n' "$1" "\$*" >> "$BATS_TEST_TMPDIR/calls"
STUB
  chmod +x "$STUBS_BIN/$1"
}

# Os testes nunca enxergam as portas reais da máquina: as portas do dev (80,
# 443, 13306, 11025) são as mesmas dentro e fora do sandbox, e um "dev fix -f"
# ou "dev start" de teste encerraria o MySQL e o Mailpit de verdade. Este ss
# falso responde que nada escuta; quem testa portas define a própria função ss.
guard_ports() {
  local dir="$BATS_TEST_TMPDIR/guard"
  if [[ ! -x "$dir/ss" ]]; then
    mkdir -p "$dir"
    printf '#!/bin/sh\necho "State Recv-Q Send-Q Local Address:Port Peer Address:Port Process"\n' > "$dir/ss"
    chmod +x "$dir/ss"
  fi
  printf '%s\n' "$dir"
}

dev_cmd() {
  PATH="$(guard_ports):$PATH" "$ROOT/dev" "$@" </dev/null
}

libraries() {
  bash -c '
    set -euo pipefail
    DEV_ROOT="$1"; export DEV_ROOT
    source "$DEV_ROOT/versions.sh"
    [[ -f "$DEV_ROOT/runtimes/manifest.sh" ]] && source "$DEV_ROOT/runtimes/manifest.sh"
    [[ -f "$DEV_ROOT/lib/common.sh" ]] && source "$DEV_ROOT/lib/common.sh"
    [[ -f "$DEV_ROOT/lib/releases.sh" ]] && source "$DEV_ROOT/lib/releases.sh"
    [[ -f "$DEV_ROOT/lib/runtime.sh" ]] && source "$DEV_ROOT/lib/runtime.sh"
    [[ -f "$DEV_ROOT/lib/plugins.sh" ]] && source "$DEV_ROOT/lib/plugins.sh"
    source() {
      case " ${IGNORE:-} " in *" ${1##*/} "*) return 0 ;; esac
      builtin source "$@"
    }
    eval "$2"
  ' _ "$ROOT" "$1" </dev/null
}

# Toda chamada de libraries passa pelo guarda de portas.
eval "unguarded_$(declare -f libraries)"
libraries() { PATH="$(guard_ports):$PATH" unguarded_libraries "$@"; }

in_project() { cd "$TEST_PROJECT" && libraries "$1"; }

project_conf() {
  local php="$PHP_VERSION_SERIES" database="" app="" line
  for line in "$@"; do
    case "$line" in
      PHP=*)      php="${line#PHP=}" ;;
      DATABASE=*) database="${line#DATABASE=}" ;;
      APP=*)      app="${line#APP=}" ;;
    esac
  done
  cat > "$TEST_PROJECT/dev.conf" <<CONF
PROJECT="test-site"
APP="$app"
PHP="$php"
NODE=""
DOCROOT="."
DATABASE="$database"
CONF
}
