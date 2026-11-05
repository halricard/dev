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
          8.4|8.4.*) printf '8.4.27\n' ;;
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

# A glibc que o binário realmente pede, lida da sua tabela de símbolos. O
# manifesto declara uma exigência única; esta é a de cada tarball.
binary_required_glibc() {
  grep -aoE 'GLIBC_[0-9]+\.[0-9]+' "$1" 2>/dev/null | sed 's/^GLIBC_//' | sort -V | tail -1 || true
}

runtime_expected_extensions() {
  local ver="${1:-}"
  local exts="${PHP_RUNTIME_EXTENSIONS:-}"
  case "$ver" in
    8.4|8.4.*)
      printf '%s\n' "$exts" | tr ' ' '\n' | grep -vE '^(lexbor|uri)$' | tr '\n' ' '
      printf '\n'
      ;;
    *)
      printf '%s\n' "$exts"
      ;;
  esac
}

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
  local php="$1" ver="${2:-}" expected loaded missing="" found
  if [[ -z "$ver" && -x "$php" ]]; then
    ver="$("$php" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)"
  fi
  expected="$(runtime_expected_extensions "$ver")"
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
      local required_glibc expected_version actual_version fpm_banner
      required_glibc="$(binary_required_glibc "$php")"
      [[ -n "$required_glibc" ]] || required_glibc="$(runtime_glibc)"
      if [[ -n "$required_glibc" ]] && glibc_too_old "$required_glibc"; then
        die "este runtime do PHP exige glibc $required_glibc ou superior — regenere com tools/build-runtimes.sh nesta máquina"
      fi
      "$php" -v >/dev/null 2>&1 || die "o PHP do runtime não executa nesta máquina"
      # O nome do tarball não prova nada: é a versão do binário que decide se a
      # correção de segurança prometida pelo manifesto está mesmo lá dentro.
      expected_version="$(runtime_version php "$ver")"
      actual_version="$("$php" -n -r 'echo PHP_VERSION;' 2>/dev/null || true)"
      [[ "$actual_version" == "$expected_version" ]] \
        || die "o tarball do PHP $expected_version traz o binário ${actual_version:-desconhecido} — regenere com tools/build-runtimes.sh php ${expected_version%.*}"
      "$php" -v 2>/dev/null | grep -q 'Zend OPcache' || die "o PHP do runtime está sem o OPcache"
      runtime_check_extensions "$php" "$ver"
      [[ -x "$dir/sbin/php-fpm" ]] || die "o tarball do PHP não tem sbin/php-fpm"
      fpm_banner="$("$dir/sbin/php-fpm" -n -v 2>/dev/null || true)"
      [[ "$fpm_banner" == "PHP $expected_version "* ]] \
        || die "o php-fpm do tarball não é o PHP $expected_version"
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

compile_runtime() {
  local component="$1" version="${2:-}"
  case "$component" in
    php)
      info "iniciando compilação do PHP $version a partir do código-fonte oficial..."
      "$DEV_ROOT/tools/build-runtimes.sh" php "$version" || return 1
      # O build reescreve o manifesto: o sha lido no início deste processo já não vale.
      if [[ -f "$DEV_ROOT/runtimes/manifest.sh" ]]; then
        # shellcheck source=runtimes/manifest.sh
        source "$DEV_ROOT/runtimes/manifest.sh"
      fi
      install_runtime php "$version"
      ;;
    *)
      die "compilação sob demanda não suportada para $component"
      ;;
  esac
}

# O php-fpm no ar segue com o binário antigo em memória mesmo depois da troca do
# diretório. Encerrado aqui, o próximo start já sobe o novo.
stop_replaced_fpm() {
  local version="$1" pidfile="$DEV_RUN/php-fpm-$1.pid"
  [[ -f "$pidfile" ]] || return 0
  kill -QUIT "$(cat "$pidfile" 2>/dev/null || true)" 2>/dev/null || true
  rm -f "$pidfile" "$DEV_RUN/php-$version.sock"
  info "php-fpm $version encerrado: o próximo start usa o binário novo"
}

install_runtime() {
  local component="$1" ver="${2:-}"
  local version dir tarball previous
  version="$(runtime_version "$component" "$ver")"
  [[ -n "$version" ]] || die "o runtime de $component ainda não está fixado no manifesto"

  if runtime_installed "$component" "$ver"; then
    ok "$component $version  já instalado"
    return 0
  fi

  tarball="$(runtime_fetch "$component" "$ver")" || return 1
  dir="$(runtime_dir "$component" "$ver")"
  # O diretório atual só sai depois que o novo passa na verificação: tarball ruim
  # não pode deixar a máquina sem o runtime que já funcionava. O ponto inicial no
  # nome o esconde de quem lista as versões instaladas.
  previous="$(dirname "$dir")/.previous-$version"
  info "extraindo $component $version"
  rm -rf "$previous"
  [[ ! -d "$dir" ]] || mv "$dir" "$previous"
  mkdir -p "$dir"
  if ! tar -xf "$tarball" -C "$dir" || ! ( runtime_verify "$component" "$ver" ); then
    rm -rf "$dir"
    [[ ! -d "$previous" ]] || mv "$previous" "$dir"
    bad "$component $version recusado; o que estava instalado continua no lugar"
    return 1
  fi
  rm -rf "$previous"
  [[ "$component" != php ]] || stop_replaced_fpm "$version"
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
