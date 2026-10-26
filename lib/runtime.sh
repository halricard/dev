#!/usr/bin/env bash
# Runtimes pré-compilados do repositório (PHP e nginx).

DEV_RUNTIMES_DIR="${DEV_RUNTIMES_DIR:-$DEV_ROOT/runtimes}"

runtime_version() {
  case "$1" in
    php)   printf '%s\n' "${PHP_RUNTIME_VERSION:-}" ;;
    nginx) printf '%s\n' "${NGINX_RUNTIME_VERSION:-}" ;;
  esac
}

runtime_file() {
  case "$1" in
    php)   printf '%s\n' "${PHP_RUNTIME_FILE:-}" ;;
    nginx) printf '%s\n' "${NGINX_RUNTIME_FILE:-}" ;;
  esac
}

runtime_sha256() {
  case "$1" in
    php)   printf '%s\n' "${PHP_RUNTIME_SHA256:-}" ;;
    nginx) printf '%s\n' "${NGINX_RUNTIME_SHA256:-}" ;;
  esac
}

runtime_url() {
  case "$1" in
    php)   printf '%s\n' "${PHP_RUNTIME_URL:-}" ;;
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

runtime_dir() { printf '%s\n' "$DEV_RUNTIME/$1/$(runtime_version "$1")"; }

runtime_binary() {
  local dir
  dir="$(runtime_dir "$1")"
  case "$1" in
    php)   printf '%s\n' "$dir/bin/php" ;;
    nginx) printf '%s\n' "$dir/sbin/nginx" ;;
  esac
}

runtime_installed() {
  local dir marker expected
  dir="$(runtime_dir "$1")"
  marker="$dir/.installed"
  [[ -f "$marker" ]] || return 1
  expected="$(runtime_sha256 "$1")"
  [[ -n "$expected" ]] || return 0
  [[ "$(cat "$marker" 2>/dev/null || true)" == "$expected" ]]
}

runtime_local_tarball() {
  local file
  file="$(runtime_file "$1")"
  [[ -n "$file" ]] || return 1
  printf '%s\n' "$DEV_RUNTIMES_DIR/$file"
}

runtime_fetch() {
  local component="$1" local_tarball="" sha url file
  sha="$(runtime_sha256 "$component")"
  file="$(runtime_file "$component")"
  [[ -n "$file" ]] || die "o manifesto de $component não diz o nome do arquivo"

  if local_tarball="$(runtime_local_tarball "$component")" && [[ -f "$local_tarball" ]]; then
    if [[ -n "$sha" ]] && ! check_sha "$local_tarball" "$sha"; then
      die "o tarball de $component em runtimes/ não confere com o sha256 do manifesto"
    fi
    printf '%s\n' "$local_tarball"
    return 0
  fi

  url="$(runtime_url "$component")"
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
  local component="$1" dir php
  dir="$(runtime_dir "$component")"
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

install_runtime() {
  local component="$1" version dir tarball
  version="$(runtime_version "$component")"
  [[ -n "$version" ]] || die "o runtime de $component ainda não está fixado no manifesto"

  if runtime_installed "$component"; then
    ok "$component $version  já instalado"
    return 0
  fi

  tarball="$(runtime_fetch "$component")" || return 1
  dir="$(runtime_dir "$component")"
  info "extraindo $component $version"
  rm -rf "$dir"
  mkdir -p "$dir"
  tar -xf "$tarball" -C "$dir" || die "não consegui extrair $tarball"
  runtime_verify "$component"
  runtime_sha256 "$component" > "$dir/.installed"
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
