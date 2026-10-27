#!/usr/bin/env bash
# Runtimes pré-compilados do repositório (PHP e nginx).

DEV_RUNTIMES_DIR="${DEV_RUNTIMES_DIR:-$DEV_ROOT/runtimes}"

runtime_version() {
  local comp="$1" ver="${2:-}"
  case "$comp" in
    php)
      if [[ -n "$ver" ]]; then
        local found="" candidate candidates=()
        for candidate in "$DEV_RUNTIMES_DIR"/php/php-"$ver"*-linux-x86_64.tar.xz; do
          if [[ -f "$candidate" ]]; then
            local fname="${candidate##*/}"
            fname="${fname#php-}"
            fname="${fname%-linux-x86_64.tar.xz}"
            candidates+=("$fname")
          fi
        done
        if (( ${#candidates[@]} > 0 )); then
          printf '%s\n' "${candidates[@]}" | sort -V | tail -1
          return 0
        fi
        if declare -F php_runtime_known_version >/dev/null 2>&1; then
          php_runtime_known_version "$ver"
          return 0
        fi
        case "$ver" in
          8.4|8.4.*) printf '8.4.6\n' ;;
          8.5|8.5.*) printf '%s\n' "${PHP_RUNTIME_VERSION:-8.5.12}" ;;
          *)         printf '%s\n' "$ver" ;;
        esac
      else
        printf '%s\n' "${PHP_RUNTIME_VERSION:-}"
      fi
      ;;
    nginx) printf '%s\n' "${NGINX_RUNTIME_VERSION:-}" ;;
  esac
}

runtime_file() {
  local comp="$1" ver="${2:-}"
  case "$comp" in
    php)
      local version
      version="$(runtime_version php "$ver")"
      if [[ -n "$ver" && "$version" != "${PHP_RUNTIME_VERSION:-}" ]]; then
        printf 'php/php-%s-linux-x86_64.tar.xz\n' "$version"
      else
        printf '%s\n' "${PHP_RUNTIME_FILE:-}"
      fi
      ;;
    nginx) printf '%s\n' "${NGINX_RUNTIME_FILE:-}" ;;
  esac
}

runtime_sha256() {
  local comp="$1" ver="${2:-}"
  case "$comp" in
    php)
      local file
      file="$(runtime_file php "$ver")"
      if [[ "$file" == "${PHP_RUNTIME_FILE:-}" ]]; then
        printf '%s\n' "${PHP_RUNTIME_SHA256:-}"
        return 0
      fi
      if [[ -f "$DEV_RUNTIMES_DIR/SHA256SUMS" ]]; then
        local sha
        sha="$(awk -v f="$file" '$2==f {print $1; exit}' "$DEV_RUNTIMES_DIR/SHA256SUMS" 2>/dev/null || true)"
        if [[ -n "$sha" ]]; then
          printf '%s\n' "$sha"
          return 0
        fi
      fi
      local full_path="$DEV_RUNTIMES_DIR/$file"
      if [[ -f "$full_path" ]]; then
        sha256sum "$full_path" 2>/dev/null | awk '{print $1}' || true
      fi
      ;;
    nginx) printf '%s\n' "${NGINX_RUNTIME_SHA256:-}" ;;
  esac
}

runtime_url() {
  local comp="$1" ver="${2:-}"
  case "$comp" in
    php)
      if [[ -z "$ver" || "$ver" == "${PHP_RUNTIME_VERSION:-}" ]]; then
        printf '%s\n' "${PHP_RUNTIME_URL:-}"
      else
        printf '\n'
      fi
      ;;
    nginx) printf '%s\n' "${NGINX_RUNTIME_URL:-}" ;;
  esac
}

runtime_glibc() { printf '%s\n' "${PHP_RUNTIME_GLIBC:-}"; }

glibc_too_old() {
  local required="$1" have
  have="$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+$' || true)"
  [[ -n "$have" ]] || return 1
  [[ "$(printf '%s\n%s\n' "$required" "$have" | sort -V | head -1 || true)" != "$required" ]]
}

runtime_expected_extensions() { printf '%s\n' "${PHP_RUNTIME_EXTENSIONS:-}"; }

runtime_dir() {
  local comp="$1" ver="${2:-}"
  printf '%s\n' "$DEV_RUNTIME/$comp/$(runtime_version "$comp" "$ver")"
}

runtime_binary() {
  local comp="$1" ver="${2:-}"
  local dir
  dir="$(runtime_dir "$comp" "$ver")"
  case "$comp" in
    php)   printf '%s\n' "$dir/bin/php" ;;
    nginx) printf '%s\n' "$dir/sbin/nginx" ;;
  esac
}

runtime_installed() {
  local comp="$1" ver="${2:-}"
  local dir marker expected
  dir="$(runtime_dir "$comp" "$ver")"
  marker="$dir/.installed"
  [[ -f "$marker" ]] || return 1
  expected="$(runtime_sha256 "$comp" "$ver")"
  [[ -n "$expected" ]] || return 0
  [[ "$(cat "$marker" 2>/dev/null || true)" == "$expected" ]]
}

runtime_local_tarball() {
  local comp="$1" ver="${2:-}"
  local file
  file="$(runtime_file "$comp" "$ver")"
  [[ -n "$file" ]] || return 1
  printf '%s\n' "$DEV_RUNTIMES_DIR/$file"
}

runtime_fetch() {
  local component="$1" ver="${2:-}" local_tarball="" sha url file
  sha="$(runtime_sha256 "$component" "$ver")"
  file="$(runtime_file "$component" "$ver")"
  [[ -n "$file" ]] || die "o manifesto de $component não diz o nome do arquivo"

  if local_tarball="$(runtime_local_tarball "$component" "$ver")" && [[ -f "$local_tarball" ]]; then
    if [[ -n "$sha" ]] && ! check_sha "$local_tarball" "$sha"; then
      die "o tarball de $component em runtimes/ não confere com o sha256 do manifesto"
    fi
    printf '%s\n' "$local_tarball"
    return 0
  fi

  url="$(runtime_url "$component" "$ver")"
  [[ -n "$url" ]] || die "não há runtime de $component em runtimes/ nem URL no manifesto"
  download "$url" "$(basename "$file")" "$sha"
}

runtime_check_extensions() {
  local php="$1" expected loaded missing="" found
  expected="$(runtime_expected_extensions)"
  [[ -n "$expected" ]] || return 0
  loaded="$("$php" -m 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
  for found in $expected; do
    grep -qx -- "$found" <<<"$loaded" || missing+=" $found"
  done
  [[ -z "$missing" ]] || die "o runtime do PHP não traz as extensões esperadas:$missing"
}

runtime_verify() {
  local component="$1" ver="${2:-}" dir php
  dir="$(runtime_dir "$component" "$ver")"
  case "$component" in
    nginx)
      [[ -x "$dir/sbin/nginx" ]] || die "o tarball do nginx não tem sbin/nginx"
      "$dir/sbin/nginx" -v >/dev/null 2>&1 \
        || die "o nginx do runtime não executa nesta máquina"
      ;;
    php)
      php="$dir/bin/php"
      [[ -x "$php" ]] || die "o tarball do PHP não tem bin/php"
      local required_glibc
      required_glibc="$(runtime_glibc)"
      if [[ -n "$required_glibc" ]] && glibc_too_old "$required_glibc"; then
        die "este runtime do PHP exige glibc $required_glibc ou superior"
      fi
      "$php" -v >/dev/null 2>&1 || die "o PHP do runtime não executa nesta máquina"
      "$php" -v 2>/dev/null | grep -q 'Zend OPcache' || die "o PHP do runtime está sem o OPcache"
      runtime_check_extensions "$php"
      [[ -x "$dir/sbin/php-fpm" ]] || die "o tarball do PHP não tem sbin/php-fpm"
      ;;
  esac
}

APT_BUILD_DEPS=(
  gcc
  g++
  make
  autoconf
  automake
  libtool
  bison
  re2c
  flex
  autopoint
  cmake
  pkg-config
  xz-utils
  bzip2
)

missing_build_deps() {
  local missing=()
  local tool
  for tool in "${APT_BUILD_DEPS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      if command -v dpkg-query >/dev/null 2>&1; then
        if ! dpkg-query -s "$tool" >/dev/null 2>&1; then
          missing+=("$tool")
        fi
      else
        missing+=("$tool")
      fi
    fi
  done
  printf '%s\n' "${missing[@]}"
}

compile_runtime() {
  local component="$1" version="${2:-}"
  case "$component" in
    php)
      info "iniciando compilação do PHP $version a partir do código-fonte oficial..."
      "$DEV_ROOT/tools/build-runtimes.sh" php "$version" || return 1
      install_runtime php "$version"
      ;;
    *)
      die "compilação sob demanda não suportada para $component"
      ;;
  esac
}

install_runtime() {
  local component="$1" ver="${2:-}"
  local version dir tarball
  version="$(runtime_version "$component" "$ver")"
  [[ -n "$version" ]] || die "o runtime de $component ainda não está fixado no manifesto"

  if runtime_installed "$component" "$ver"; then
    ok "$component $version  já instalado"
    return 0
  fi

  tarball="$(runtime_fetch "$component" "$ver")" || return 1
  dir="$(runtime_dir "$component" "$ver")"
  info "extraindo $component $version"
  rm -rf "$dir"
  mkdir -p "$dir"
  tar -xf "$tarball" -C "$dir" || die "não consegui extrair $tarball"
  runtime_verify "$component" "$ver"
  runtime_sha256 "$component" "$ver" > "$dir/.installed"
  ok "$component $version"
}

# Verificação e concessão de capability para portas privilegiadas no nginx.
has_net_bind_capability() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    target="$(runtime_binary nginx 2>/dev/null || true)"
    if [[ ! -f "$target" && -n "$(nginx_prefix 2>/dev/null || true)" ]]; then
      target="$(nginx_prefix)/sbin/nginx"
    fi
  fi
  [[ -n "$target" && -f "$target" ]] || return 1
  command -v getcap >/dev/null 2>&1 || return 1
  local caps
  caps="$(getcap "$target" 2>/dev/null || true)"
  [[ "$caps" == *"cap_net_bind_service"* ]]
}

grant_net_bind_capability() {
  local target="${1:-}"
  local interactive=0
  if [[ "$target" == "-i" || "$target" == "--interactive" ]]; then
    interactive=1
    target=""
  elif [[ "${2:-}" == "-i" || "${2:-}" == "--interactive" ]]; then
    interactive=1
  fi

  if [[ -z "$target" ]]; then
    target="$(runtime_binary nginx 2>/dev/null || true)"
    if [[ ! -f "$target" && -n "$(nginx_prefix 2>/dev/null || true)" ]]; then
      target="$(nginx_prefix)/sbin/nginx"
    fi
  fi
  [[ -n "$target" && -f "$target" ]] || return 1
  has_net_bind_capability "$target" && return 0

  if command -v setcap >/dev/null 2>&1; then
    if sudo -n setcap 'cap_net_bind_service=+ep' "$target" 2>/dev/null; then
      return 0
    fi
    if (( interactive )); then
      if sudo setcap 'cap_net_bind_service=+ep' "$target" 2>/dev/null; then
        return 0
      fi
    fi
  fi

  if declare -p PENDING >/dev/null 2>&1; then
    PENDING+=("sudo setcap 'cap_net_bind_service=+ep' $target")
  fi
  return 1
}
