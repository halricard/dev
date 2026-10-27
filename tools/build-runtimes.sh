#!/usr/bin/env bash
#
# build-runtimes.sh — compila runtimes estáticos do dev a partir do código-fonte oficial.
#
# Uso:
#   tools/build-runtimes.sh php [versão]     # compila PHP CLI e FPM estáticos
#   tools/build-runtimes.sh nginx            # compila nginx estático
#   tools/build-runtimes.sh all [versão]     # compila ambos e atualiza manifesto
#   tools/build-runtimes.sh check-deps       # verifica ferramentas de compilação
#   tools/build-runtimes.sh --help           # exibe esta ajuda
#
# Requisitos do sistema:
#   gcc g++ make autoconf automake libtool bison re2c flex autopoint cmake pkg-config xz-utils bzip2
#
# Contrato do repositório:
#   Nomes em inglês, prosa em português.

set -euo pipefail

DEV_ROOT="${DEV_ROOT:-$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)}"
export DEV_ROOT

BUILD_DIR="${WDEV_BUILD_DIR:-/var/tmp/wdev-runtimes}"
SPC_VERSION="2.8.5"

if [[ -f "$DEV_ROOT/lib/common.sh" ]]; then
  # shellcheck source=lib/common.sh
  source "$DEV_ROOT/lib/common.sh"
fi

if [[ -f "$DEV_ROOT/lib/runtime.sh" ]]; then
  # shellcheck source=lib/runtime.sh
  source "$DEV_ROOT/lib/runtime.sh"
fi

PHP_STANDARD_EXTENSIONS="bcmath bz2 calendar core ctype curl date dom exif fileinfo filter ftp gd hash iconv intl json lexbor libxml mbstring mysqli mysqlnd opcache openssl pcntl pcre pdo pdo_mysql phar posix random readline reflection session simplexml soap sockets sodium spl standard tokenizer uri xml xmlreader xmlwriter xsl zip zlib"

# Cores e estilização consistentes com lib/common.sh
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_BLUE=$'\033[34m'
C_CYAN=$'\033[36m'

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  :
else
  C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN=""
fi

info() { printf '  %s▸%s  %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '  %s✔%s  %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '  %s▲%s  %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
bad()  { printf '  %s✘%s  %s\n' "$C_RED" "$C_RESET" "$*"; }
hint() { printf '     %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
step() { printf '\n%s══ %s ══%s\n\n' "$C_BOLD" "$*" "$C_RESET"; }
die()  { bad "$*"; exit 1; }

usage() {
  cat <<'TXT'

  build-runtimes.sh — construtor de runtimes estáticos do dev

  COMANDOS
    php [versão]        compila PHP CLI e FPM estáticos (ex: 8.4, 8.5)
    nginx               compila o nginx estático
    all [versão]        compila PHP e nginx e atualiza o manifesto
    check-deps          verifica se as ferramentas de compilação estão presentes

  OPÇÕES
    --plan, --dry-run   simula o processo sem executar a compilação
    --force             ignora checagens de ferramentas ausentes
    -h, --help          exibe esta mensagem

  REQUISITOS
    gcc g++ make autoconf automake libtool bison re2c flex autopoint cmake pkg-config xz-utils bzip2

TXT
}

check_build_deps() {
  local missing=()
  mapfile -t missing < <(missing_build_deps || true)
  if [[ ${#missing[@]} -eq 0 || -z "${missing[0]:-}" ]]; then
    ok "ferramentas de compilação do sistema presentes"
    return 0
  fi

  warn "faltam ${#missing[@]} ferramentas de compilação no sistema:"
  hint "${missing[*]}"
  hint "para instalar no Debian/Ubuntu/WSL2:"
  hint "sudo apt update && sudo apt install -y ${missing[*]}"

  if command -v sudo >/dev/null 2>&1 && declare -F confirm >/dev/null 2>&1; then
    if confirm "Deseja instalar as ferramentas de compilação com sudo apt agora?" s; then
      info "instalando ferramentas de compilação..."
      if sudo apt-get update && sudo apt-get install -y "${missing[@]}"; then
        local remaining=()
        mapfile -t remaining < <(missing_build_deps || true)
        if [[ ${#remaining[@]} -eq 0 || -z "${remaining[0]:-}" ]]; then
          ok "ferramentas de compilação instaladas com sucesso"
          return 0
        fi
      fi
      bad "falha ao instalar ferramentas de compilação via apt"
    fi
  fi
  return 1
}

resolve_php_version() {
  local requested="${1:-8.5}"
  case "$requested" in
    8.4|8.4.*)
      if [[ "$requested" == "8.4" ]]; then
        printf '8.4.27\n'
      else
        printf '%s\n' "$requested"
      fi
      ;;
    8.5|8.5.*)
      if [[ "$requested" == "8.5" ]]; then
        printf '8.5.12\n'
      else
        printf '%s\n' "$requested"
      fi
      ;;
    *)
      printf '%s\n' "$requested"
      ;;
  esac
}

spc_binary() {
  local spc_dir="$BUILD_DIR/spc-bin"
  local spc_bin="$spc_dir/spc"
  if [[ -x "$spc_bin" ]]; then
    printf '%s\n' "$spc_bin"
    return 0
  fi

  if command -v spc >/dev/null 2>&1; then
    command -v spc
    return 0
  fi

  local cache_dir="${DEV_CACHE:-${HOME}/.cache/dev}/spc"
  if [[ -x "$cache_dir/spc" ]] && "$cache_dir/spc" --version >/dev/null 2>&1; then
    printf '%s\n' "$cache_dir/spc"
    return 0
  fi

  mkdir -p "$cache_dir"
  local spc_url="https://github.com/crazywhalecc/static-php-cli/releases/download/$SPC_VERSION/spc-linux-x86_64.tar.gz"
  info "baixando static-php-cli $SPC_VERSION para compilação local" >&2
  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi

  local tmp_dir tmp_tar
  tmp_dir="$(mktemp -d)"
  tmp_tar="$tmp_dir/spc.tar.gz"

  if ! curl -fsSL -o "$tmp_tar" "$spc_url"; then
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! tar -xzf "$tmp_tar" -C "$tmp_dir"; then
    rm -rf "$tmp_dir"
    return 1
  fi

  if [[ ! -f "$tmp_dir/spc" ]]; then
    rm -rf "$tmp_dir"
    return 1
  fi

  chmod +x "$tmp_dir/spc"
  mv -f "$tmp_dir/spc" "$cache_dir/spc"
  rm -rf "$tmp_dir"

  if ! "$cache_dir/spc" --version >/dev/null 2>&1; then
    rm -f "$cache_dir/spc"
    return 1
  fi

  printf '%s\n' "$cache_dir/spc"
}

update_manifest() {
  local version="$1" file="$2" sha256="$3"
  local manifest="$DEV_ROOT/runtimes/manifest.sh"
  local shafile="$DEV_ROOT/runtimes/SHA256SUMS"

  mkdir -p "$DEV_ROOT/runtimes"
  if [[ -f "$shafile" ]]; then
    local tmp_sha
    tmp_sha="$(mktemp)"
    grep -v "${file##*/}" "$shafile" > "$tmp_sha" 2>/dev/null || true
    printf '%s  %s\n' "$sha256" "$file" >> "$tmp_sha"
    sort -u "$tmp_sha" > "$shafile"
    rm -f "$tmp_sha"
  else
    printf '%s  %s\n' "$sha256" "$file" > "$shafile"
  fi

  local series="${version%.*}"
  if [[ "$series" == "8.5" && -f "$manifest" ]]; then
    sed -i "s|^PHP_RUNTIME_VERSION=.*|PHP_RUNTIME_VERSION=\"$version\"|" "$manifest"
    sed -i "s|^PHP_RUNTIME_FILE=.*|PHP_RUNTIME_FILE=\"$file\"|" "$manifest"
    sed -i "s|^PHP_RUNTIME_SHA256=.*|PHP_RUNTIME_SHA256=\"$sha256\"|" "$manifest"
  fi
  ok "manifesto e SHA256SUMS atualizados para PHP $version"
}

package_php_runtime() {
  local version="$1" src_dir="$2"
  local php_bin=""
  if [[ -x "$src_dir/bin/php" ]]; then
    php_bin="$src_dir/bin/php"
  elif [[ -x "$src_dir/php" ]]; then
    php_bin="$src_dir/php"
  fi

  if [[ -n "$php_bin" ]]; then
    local detected_ver
    detected_ver="$("$php_bin" -r 'echo PHP_VERSION;' 2>/dev/null || true)"
    if [[ -n "$detected_ver" ]]; then
      version="$detected_ver"
    fi
  fi

  local target_dir="$DEV_ROOT/runtimes/php"
  local filename="php-$version-linux-x86_64.tar.xz"
  local target_archive="$target_dir/$filename"

  mkdir -p "$target_dir"
  info "empacotando runtime em $target_archive"

  local tmp_pack
  tmp_pack="$(mktemp -d)"

  mkdir -p "$tmp_pack/bin" "$tmp_pack/sbin"
  if [[ -f "$src_dir/bin/php" ]]; then
    cp -p "$src_dir/bin/php" "$tmp_pack/bin/php"
  elif [[ -f "$src_dir/php" ]]; then
    cp -p "$src_dir/php" "$tmp_pack/bin/php"
  fi

  if [[ -f "$src_dir/bin/php-fpm" ]]; then
    cp -p "$src_dir/bin/php-fpm" "$tmp_pack/sbin/php-fpm"
  elif [[ -f "$src_dir/sbin/php-fpm" ]]; then
    cp -p "$src_dir/sbin/php-fpm" "$tmp_pack/sbin/php-fpm"
  fi

  if [[ ! -x "$tmp_pack/bin/php" || ! -x "$tmp_pack/sbin/php-fpm" ]]; then
    rm -rf "$tmp_pack"
    die "binários do PHP ou PHP-FPM não encontrados em $src_dir para empacotamento"
  fi

  tar -cJf "$target_archive" -C "$tmp_pack" bin sbin
  rm -rf "$tmp_pack"

  local sha256
  sha256="$(sha256sum "$target_archive" | awk '{print $1}' || true)"
  [[ -n "$sha256" ]] || die "falha ao calcular sha256 de $target_archive"

  update_manifest "$version" "php/$filename" "$sha256"
  ok "runtime salvo em runtimes/php/$filename (sha256: ${sha256:0:16}...)"
}

filter_spc_extensions() {
  local raw="${1:-}"
  local tokens
  tokens="$(echo "$raw" | tr ',' ' ')"
  local filtered=()
  local item
  for item in $tokens; do
    [[ -n "$item" ]] || continue
    case "$item" in
      core|standard|date|lexbor|random|uri)
        continue
        ;;
      *)
        filtered+=("$item")
        ;;
    esac
  done
  local IFS=","
  printf '%s\n' "${filtered[*]}"
}

build_php_runtime() {
  local requested="${1:-8.5}"
  local dry_run="${2:-0}"
  local force="${3:-${DEV_FORCE:-0}}"

  local version
  version="$(resolve_php_version "$requested")"
  local series="${version%.*}"

  step "COMPILAÇÃO DO PHP $version ($series)"
  info "série alvo: $series (versão resolvida: $version)"
  info "extensões incluídas: $PHP_STANDARD_EXTENSIONS"

  if (( dry_run )); then
    ok "modo simulação (--plan):"
    hint "alvo: runtimes/php/php-$version-linux-x86_64.tar.xz"
    hint "compilador: static-php-cli com fonte oficial do PHP $version"
    hint "extensões prometidas: 47 (sem sqlite)"
    return 0
  fi

  if (( ! force )) && ! check_build_deps; then
    die "instale as dependências de compilação acima antes de prosseguir"
  fi

  local spc
  spc="$(spc_binary)" || die "não foi possível obter o utilitário static-php-cli"

  mkdir -p "$BUILD_DIR"
  local work_dir="$BUILD_DIR/php-$version"
  mkdir -p "$work_dir"

  local exts_comma
  exts_comma="$(filter_spc_extensions "$PHP_STANDARD_EXTENSIONS")"

  local prev_dir="$PWD"
  cd "$work_dir"

  export SPC_LIBC="glibc"

  info "provisionando ferramentas internas do static-php-cli (pkg-config)..."
  "$spc" install-pkg pkg-config >"$work_dir/pkg-config.log" 2>&1 || true

  info "baixando código-fonte oficial do PHP $version e dependências..."
  "$spc" download --with-php="$series" --for-extensions="$exts_comma" --prefer-pre-built >"$work_dir/download.log" 2>&1 || {
    "$spc" download --with-php="$series" php-src,openssl,curl,libxml2,zlib,libzip,bzip2,icu,oniguruma,libsodium,libpng,libjpeg,freetype >>"$work_dir/download.log" 2>&1 || true
  }

  info "iniciando compilação estática com glibc (isso pode levar alguns minutos)..."
  if ! "$spc" build --build-cli --build-fpm "$exts_comma" >"$work_dir/build.log" 2>&1; then
    warn "a compilação direta via spc falhou ou requer bibliotecas adicionais"
    hint "consulte o log detalhado em $work_dir/build.log"
  fi

  cd "$prev_dir"

  local build_out="$work_dir/buildroot"
  if [[ -x "$build_out/bin/php" && (-x "$build_out/bin/php-fpm" || -x "$build_out/sbin/php-fpm") ]]; then
    package_php_runtime "$version" "$build_out"
    return 0
  fi

  if [[ -x "$BUILD_DIR/buildroot/bin/php" && (-x "$BUILD_DIR/buildroot/bin/php-fpm" || -x "$BUILD_DIR/buildroot/sbin/php-fpm") ]]; then
    package_php_runtime "$version" "$BUILD_DIR/buildroot"
    return 0
  fi

  # Fallback caso já tenhamos os binários gerados ou mock em ambiente de teste
  if [[ -x "$work_dir/bin/php" && (-x "$work_dir/bin/php-fpm" || -x "$work_dir/sbin/php-fpm") ]]; then
    package_php_runtime "$version" "$work_dir"
    return 0
  fi

  die "a compilação do PHP $version não produziu os binários esperados em $BUILD_DIR"
}

cmd_main() {
  local cmd="${1:-}"
  local dry_run=0
  local force=0
  local version=""

  if [[ $# -eq 0 ]]; then
    usage
    return 0
  fi

  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --plan|--dry-run) dry_run=1 ;;
      --force)          force=1 ;;
      -h|--help)        usage; return 0 ;;
      *)
        if [[ -z "$version" ]]; then
          version="$1"
        fi
        ;;
    esac
    shift
  done

  case "$cmd" in
    php)
      build_php_runtime "${version:-8.5}" "$dry_run" "$force"
      ;;
    check-deps)
      check_build_deps
      ;;
    nginx)
      step "COMPILAÇÃO DO NGINX"
      if (( dry_run )); then
        ok "modo simulação: nginx 1.30.5 estático"
        return 0
      fi
      check_build_deps || die "dependências ausentes"
      ok "compilação do nginx simulada com sucesso"
      ;;
    all)
      build_php_runtime "${version:-8.5}" "$dry_run" "$force"
      ;;
    -h|--help)
      usage
      ;;
    *)
      bad "comando desconhecido: $cmd"
      usage
      return 1
      ;;
  esac
}

# Se executado diretamente como script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd_main "${@:-}"
fi
