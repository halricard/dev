#!/usr/bin/env bash
# Provisionamento do core do dev dentro de $DEV_HOME.
#
# Runtimes pré-compilados e binários oficiais. Não compila nada do fonte.

APT_MIN=(
  ca-certificates curl openssl
  iproute2 procps
  tar xz-utils unzip
  zstd
  libnss3-tools
  libcap2-bin
)

apt_missing() {
  local missing=() package
  for package in "${APT_MIN[@]}"; do
    dpkg -s "$package" >/dev/null 2>&1 || missing+=("$package")
  done
  if ! dpkg -s libaio1t64 >/dev/null 2>&1 && ! dpkg -s libaio1 >/dev/null 2>&1; then
    apt-cache show libaio1t64 >/dev/null 2>&1 && missing+=(libaio1t64) || missing+=(libaio1)
  fi
  dpkg -s libnuma1 >/dev/null 2>&1 || missing+=(libnuma1)
  printf '%s\n' "${missing[@]}"
}

install_apt() {
  local missing
  mapfile -t missing < <(apt_missing)
  [[ ${#missing[@]} -eq 0 || -z "${missing[0]}" ]] && { ok "dependências do sistema  já instaladas"; return 0; }

  warn "faltam ${#missing[@]} pacotes do sistema"
  hint "sudo apt install ${missing[*]}"
  blank
  confirm "instalar no sistema?" s || die "sem os pacotes não dá para seguir"
  sudo apt-get update
  sudo apt-get install -y "${missing[@]}"
}

compatibilize_libs() {
  local prefix="$1" compat="$1/lib-compat" real
  mkdir -p "$compat"
  local missing
  while IFS= read -r missing; do
    [[ -n "$missing" ]] || continue
    real="$(ls /usr/lib/x86_64-linux-gnu/"${missing}"* 2>/dev/null | head -1 || true)"
    [[ -n "$real" ]] || continue
    ln -sf "$real" "$compat/$missing"
    info "$missing → $(basename "$real")"
  done < <(ldd "$prefix/bin/mysqld" 2>/dev/null | grep 'not found' | awk '{print $1}' || true)
}

install_mysql() {
  local version="${1:-$MYSQL_VERSION}"
  local prefix="$DEV_RUNTIME/mysql/$version"
  sandbox_libs
  [[ -x "$prefix/bin/mysqld" ]] && { ok "MySQL $version  já instalado"; return 0; }

  local tarball
  tarball="$(download "$(url_for mysql "$version")" "$(cache_name mysql "$version")")"

  info "instalando MySQL $version"
  mkdir -p "$prefix"
  extract "$tarball" "$prefix" 1

  local compressed
  while IFS= read -r compressed; do
    [[ -n "$compressed" ]] || continue
    zstd -dq --rm "$compressed" || die "falhou descomprimir $compressed"
  done < <(find "$prefix/bin" -name "*.zst" 2>/dev/null)
  chmod +x "$prefix"/bin/* 2>/dev/null || true

  compatibilize_libs "$prefix"
  sandbox_libs

  if ! LD_LIBRARY_PATH="$prefix/lib-compat" "$prefix/bin/mysqld" --version >/dev/null 2>&1; then
    local missing
    missing="$(ldd "$prefix/bin/mysqld" 2>/dev/null | grep 'not found' | awk '{print $1}' | tr '\n' ' ' || true)"
    die "o mysqld não executa; faltam bibliotecas do sistema: ${missing:-desconhecidas}
     tente:  sudo apt install libaio1t64 libnuma1"
  fi

  config_set MYSQL_VERSION "$version"
  ok "MySQL $version"
}

install_node() {
  local version="${1:-$NODE_VERSION}"
  local prefix="$DEV_RUNTIME/node/$version"
  [[ -x "$prefix/bin/node" ]] && { ok "Node $version  já instalado"; return 0; }
  local tarball
  tarball="$(download "$(url_for node "$version")" "$(cache_name node "$version")")"
  mkdir -p "$prefix"
  extract "$tarball" "$prefix" 1
  config_set DEFAULT_NODE "$version"
  ok "Node $version"
}

install_composer() {
  local version="${1:-$COMPOSER_VERSION}"
  local target="$DEV_RUNTIME/composer/composer.phar"
  [[ -f "$target" ]] && { ok "Composer  já instalado"; return 0; }
  local phar
  phar="$(download "$(url_for composer "$version")" "$(cache_name composer "$version")")"
  mkdir -p "$(dirname "$target")"
  cp "$phar" "$target"
  chmod +x "$target"
  ok "Composer $version"
}

install_mkcert() {
  local version="${1:-$MKCERT_VERSION}"
  local prefix="$DEV_RUNTIME/mkcert"
  [[ -x "$prefix/bin/mkcert" ]] && { ok "mkcert  já instalado"; return 0; }
  local binary
  binary="$(download "$(url_for mkcert "$version")" "$(cache_name mkcert "$version")")"
  mkdir -p "$prefix/bin"
  install -m 0755 "$binary" "$prefix/bin/mkcert"
  ok "mkcert $version"
}

install_mailpit() {
  local version="${1:-$MAILPIT_VERSION}"
  local prefix="$DEV_RUNTIME/mailpit"
  [[ -x "$prefix/bin/mailpit" ]] && { ok "Mailpit  já instalado"; return 0; }
  local tarball tmp
  tarball="$(download "$(url_for mailpit "$version")" "$(cache_name mailpit "$version")")"
  tmp="$(scratch)"
  tar -xf "$tarball" -C "$tmp"
  mkdir -p "$prefix/bin"
  install -m 0755 "$tmp/mailpit" "$prefix/bin/mailpit"
  ok "Mailpit $version"
}

install_adminer() {
  local version="${1:-$ADMINER_VERSION}"
  local target="$DEV_HOME/adminer/adminer.php"
  [[ -f "$target" ]] && { ok "Adminer  já instalado"; return 0; }
  local file
  file="$(download "$(url_for adminer "$version")" "$(cache_name adminer "$version")")"
  mkdir -p "$(dirname "$target")"
  cp "$file" "$target"
  ok "Adminer $version"
}

install_own_runtime() {
  local php_version nginx_version
  install_runtime php || return 1
  install_runtime nginx || return 1
  grant_net_bind_capability || true
  php_version="$(runtime_version php)"
  nginx_version="$(runtime_version nginx)"
  config_set DEFAULT_PHP "$php_version"
  config_set NGINX_VERSION "$nginx_version"
}

COMMAND_DIRS=("$HOME/.local/bin" "$HOME/bin" /usr/local/bin)

in_path() { [[ ":$PATH:" == *":$1:"* ]]; }

install_command() {
  local target="$DEV_ROOT/dev" current="" dir=""
  chmod +x "$target" 2>/dev/null || true

  current="$(command -v dev 2>/dev/null || true)"
  if [[ -n "$current" && "$(readlink -f "$current")" == "$target" ]]; then
    ok "comando dev  já no PATH"
    return 0
  fi

  if [[ -n "$current" ]]; then
    if [[ -L "$current" && "$(basename "$(readlink -f "$current")")" == dev ]]; then
      dir="$(dirname "$current")"
    else
      warn "já existe outro comando dev em $current — mantido"
      hint "o deste repositório continua em $target"
      return 0
    fi
  fi

  if [[ -z "$dir" ]]; then
    local candidate
    for candidate in "${COMMAND_DIRS[@]}"; do
      in_path "$candidate" && { dir="$candidate"; break; }
    done
  fi
  [[ -n "$dir" ]] || dir=/usr/local/bin
  [[ "$dir" == "$HOME"/* ]] && mkdir -p "$dir"

  if [[ -w "$dir" ]]; then
    ln -sfn "$target" "$dir/dev"
  elif ! sudo -n ln -sfn "$target" "$dir/dev" 2>/dev/null; then
    PENDING+=("sudo ln -sfn $target $dir/dev")
    return 0
  fi
  ok "comando dev  em $dir"
  DEV="dev"
}

remove_command() {
  local dir dirs=("${COMMAND_DIRS[@]}")
  dir="$(command -v dev 2>/dev/null || true)"
  [[ -n "$dir" ]] && dirs+=("$(dirname "$dir")")
  for dir in "${dirs[@]}"; do
    [[ -L "$dir/dev" && "$(readlink -f "$dir/dev")" == "$DEV_ROOT/dev" ]] || continue
    rm -f "$dir/dev" 2>/dev/null || sudo rm -f "$dir/dev" || true
  done
}

PENDING=()

warm_sudo() {
  [[ -t 0 ]] || return 1
  sudo -n true 2>/dev/null && return 0
  info "alguns passos podem precisar de sudo (pacotes do apt, autoridade no sistema, link do dev)"
  sudo -v
}

cmd_install() {
  local plan_only=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --plan|-n|--dry-run) plan_only=1 ;;
      *) die "opção desconhecida: $1" ;;
    esac
    shift
  done

  local reason
  reason="$(supported_system /etc/os-release "$(uname -m)")" || die "$reason"
  is_wsl || warn "Linux nativo: suporte experimental — WSL2 é o ambiente padrão"
  no_windows "$DEV_HOME" "o diretório do dev"

  step "PLANO DO CORE"
  printf "  %-10s %-10s ${C_DIM}%s${C_RESET}\n" \
    "PHP"      "$(runtime_version php)"   "pré-compilado, estático (spc)" \
    "nginx"    "$(runtime_version nginx)" "pré-compilado, estático" \
    "MySQL"    "$MYSQL_VERSION"           "binário oficial minimal" \
    "Node"     "$NODE_VERSION"            "binário oficial LTS" \
    "Mailpit"  "$MAILPIT_VERSION"         "captura todo e-mail localmente" \
    "Adminer"  "$ADMINER_VERSION"         "cliente de banco no navegador" \
    "Composer" "$COMPOSER_VERSION"        "gerenciador de dependências PHP" \
    "mkcert"   "$MKCERT_VERSION"          "confere autoridade HTTPS local"
  blank
  hint "aplicações específicas (moodle, laravel, wordpress) são instaladas via plugins"
  hint "após o install: dev plugin list"
  blank

  step "CONFERINDO DOWNLOADS"
  if ! verify_urls; then
    blank
    bad "há downloads indisponíveis — instalação abortada"
    return 1
  fi

  if (( plan_only )); then
    blank
    info "apenas simulação (--plan); nenhum arquivo modificado"
    return 0
  fi
  blank

  ensure_tree
  warm_sudo || true
  step "DEPENDÊNCIAS DO SISTEMA"; install_apt
  step "RUNTIME PRÉ-COMPILADO"; install_own_runtime
  step "BINÁRIOS BASE"
  install_mysql
  install_node
  install_composer
  install_mailpit
  install_adminer
  install_mkcert

  step "CONFIGURAÇÃO"
  source "$DEV_ROOT/lib/certs.sh";  generate_ca
  source "$DEV_ROOT/lib/config.sh"; write_configs; init_datadir
  install_command

  blank
  if (( ${#PENDING[@]} > 0 )); then
    warn "${#PENDING[@]} passo(s) dependem de sudo e ficaram pendentes:"
    local step_cmd
    for step_cmd in "${PENDING[@]}"; do printf '     %s%s%s\n' "$C_BOLD" "$step_cmd" "$C_RESET"; done
    blank
    return 1
  fi
  ok "core instalado com sucesso"
  blank

  source "$DEV_ROOT/lib/services.sh"
  take_over_ports || true
  cmd_start --if-needed
  ensure_mysql_password
  hint "$DEV plugin list   mostra aplicações disponíveis para instalar"
  hint "$DEV new           cria novos projetos"
  blank
}

cmd_uninstall() {
  step "REMOVER O DEV"
  local size
  size="$(du -sh "$DEV_HOME" 2>/dev/null | cut -f1 || echo "?")"
  printf '  %s✘%s  Sandbox        %s   %s\n' "$C_RED" "$C_RESET" "$DEV_HOME" "$size"
  printf '  %s✘%s  Bancos         arquivos dos projetos ficam, os bancos são removidos\n' "$C_RED" "$C_RESET"
  printf '  %s✘%s  Autoridade     sai das lojas do Windows e Linux\n' "$C_RED" "$C_RESET"
  printf '  %s✘%s  Comando        link dev no PATH\n' "$C_RED" "$C_RESET"
  blank
  local word
  read -r -p "  ?  Digite \"remover\" para confirmar: " word
  [[ "$word" == "remover" ]] || { blank; info "nada foi removido"; return 0; }

  source "$DEV_ROOT/lib/services.sh"; cmd_stop >/dev/null 2>&1 || true
  source "$DEV_ROOT/lib/certs.sh"
  remove_ca_from_windows || true
  remove_ca_from_linux || true
  remove_command
  rm -rf "$DEV_HOME"
  blank
  ok "sandbox do dev removido"
}
