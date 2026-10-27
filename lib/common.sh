#!/usr/bin/env bash
# Base compartilhada: mensagens, caminhos DEV_*, configuração de projetos
# e rotinas de plataforma e download.

# ------------------------------------------------------------------ mensagens
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
  C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'
  C_BLUE=$'\e[34m'; C_CYAN=$'\e[36m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''
fi

ok()   { printf '  %s✔%s  %s\n'  "$C_GREEN"  "$C_RESET" "$*"; }
warn() { printf '  %s▲%s  %s\n'  "$C_YELLOW" "$C_RESET" "$*"; }
bad()  { printf '  %s✘%s  %s\n'  "$C_RED"    "$C_RESET" "$*" >&2; }
info() { printf '  %s•%s  %s\n'  "$C_CYAN"   "$C_RESET" "$*"; }
hint() { printf '  %s→  %s%s\n'  "$C_DIM"    "$*" "$C_RESET"; }
step() { printf '\n%s  %s%s\n'   "$C_BOLD"   "$*" "$C_RESET"; }
blank(){ printf '\n'; }

die() { bad "$*"; exit 1; }

has() { command -v "$1" >/dev/null 2>&1; }

require_command() {
  local cmd="$1" package="${2:-$1}"
  has "$cmd" || die "falta o comando \`$cmd\` — instale com: sudo apt install $package"
}

label() {
  local key="$1" value="$2" width="${3:-14}"
  local spaces=$(( width - ${#key} ))
  (( spaces < 1 )) && spaces=1
  printf '  %s%*s%s\n' "$key" "$spaces" "" "$value"
}

confirm() {
  local question="$1" default="${2:-n}" answer mark
  if [[ ! -t 0 ]]; then
    [[ "${DEV_YES:-}" == "1" ]] && return 0
    return 1
  fi
  if [[ "$default" == s ]]; then mark="[S/n]"; else mark="[s/N]"; fi
  read -r -p "  ?  $question $mark " answer
  [[ -z "$answer" ]] && answer="$default"
  [[ "$answer" =~ ^[SsYy]$ ]]
}

# ------------------------------------------------------------------- caminhos
DEV_HOME="${DEV_HOME:-$HOME/.dev}"
DEV_CACHE="${DEV_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/dev}"

DEV_RUNTIME="$DEV_HOME/runtime"      # php, nginx, mysql, node
DEV_ETC="$DEV_HOME/etc"              # vhosts, pool, my.cnf
DEV_DATA="$DEV_HOME/services/data"   # datadir mysql
DEV_LOG="$DEV_HOME/services/log"
DEV_RUN="$DEV_HOME/services/run"     # pids, sockets
DEV_CERTS="$DEV_HOME/certs"
DEV_SITES="$DEV_HOME/sites"          # sites ativos: nome -> caminho
DEV_SNAPSHOTS="$DEV_HOME/snapshots"
DEV_UP="$DEV_HOME/up"                # marcadores de sites no ar
DEV_QUIET="$DEV_HOME/quiet"          # supressão de erro na tela por site
DEV_CONFIG="$DEV_HOME/config"        # preferências globais da máquina
DEV_BIN="$DEV_HOME/bin"              # wrappers de CLI (composer, wp, etc)
DEV_PLUGINS="$DEV_HOME/plugins"      # plugins instalados

DEV="dev"
if [[ -n "${DEV_ROOT:-}" && "$(readlink -f "$(command -v dev 2>/dev/null)" 2>/dev/null)" != "$DEV_ROOT/dev" ]]; then
  DEV="${DEV_ROOT/#$HOME/\~}/dev"
fi

DEV_ADMIN_USER="dev"

sandbox_libs() {
  local dir
  for dir in "$DEV_RUNTIME"/mysql/*/lib-compat; do
    [[ -d "$dir" ]] && export LD_LIBRARY_PATH="$dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  done
  return 0
}
sandbox_libs

DEV_TMP="$(mktemp -d)"
trap 'rm -rf "$DEV_TMP"' EXIT

scratch() { mktemp -d -p "$DEV_TMP"; }

ensure_tree() {
  mkdir -p "$DEV_RUNTIME" "$DEV_ETC/nginx/sites" "$DEV_ETC/php" \
           "$DEV_DATA" "$DEV_LOG" "$DEV_RUN" "$DEV_CERTS" \
           "$DEV_SITES" "$DEV_SNAPSHOTS" "$DEV_CACHE" \
           "$DEV_UP" "$DEV_QUIET" "$DEV_BIN" \
           "$DEV_PLUGINS/installed"
}

# ------------------------------------------------------ caminhos dos runtimes
nginx_prefix() {
  local version
  version="$(config_get NGINX_VERSION)"
  [[ -n "$version" ]] || version="$(runtime_version nginx 2>/dev/null || echo "1.30.5")"
  printf '%s\n' "$DEV_RUNTIME/nginx/$version"
}
mysql_prefix() {
  local version
  version="$(config_get MYSQL_VERSION)"
  [[ -n "$version" ]] || version="${MYSQL_VERSION:-8.4.9}"
  printf '%s\n' "$DEV_RUNTIME/mysql/$version"
}

php_installed_version() {
  ls -1 "$DEV_RUNTIME/php" 2>/dev/null | sort -V | tail -1 || true
}

newest_patch() {
  local dir="$1" prefix="$2" candidate names=()
  for candidate in "$dir/$prefix".*; do
    [[ -d "$candidate" ]] && names+=("${candidate##*/}")
  done
  (( ${#names[@]} > 0 )) || return 0
  printf '%s\n' "${names[@]}" | sort -V | tail -1
}

php_version() {
  local wanted="${1:-}" found
  [[ -z "$wanted" ]] && wanted="$(config_get DEFAULT_PHP)"
  [[ -n "$wanted" ]] || wanted="$(php_installed_version)"
  [[ -d "$DEV_RUNTIME/php/$wanted" ]] && { printf '%s\n' "$wanted"; return 0; }
  found="$(newest_patch "$DEV_RUNTIME/php" "$wanted")"
  printf '%s\n' "${found:-$wanted}"
}

active_php_versions() {
  local versions=()
  local def
  def="$(php_version "")"
  [[ -n "$def" ]] && versions+=("$def")

  if [[ -d "${DEV_SITES:-}" ]]; then
    local sfile sdir proj_php ver
    for sfile in "$DEV_SITES"/*; do
      [[ -f "$sfile" ]] || continue
      sdir="$(cat "$sfile" 2>/dev/null || true)"
      if [[ -f "$sdir/dev.conf" ]]; then
        proj_php="$(grep -oP '^PHP="\K[^"]+' "$sdir/dev.conf" 2>/dev/null || true)"
        if [[ -n "$proj_php" ]]; then
          ver="$(php_version "$proj_php")"
          [[ -n "$ver" ]] && versions+=("$ver")
        fi
      fi
    done
  fi
  printf '%s\n' "${versions[@]}" | sort -u || true
}

php_prefix() { printf '%s\n' "$DEV_RUNTIME/php/$(php_version "${1:-}")"; }

fpm_socket() { printf '%s\n' "$DEV_RUN/php-$1.sock"; }

php_bin() {
  local version
  version="$(php_version "${1:-}")"
  [[ -n "$version" ]] || die "nenhum PHP instalado — rode \`$DEV install\`"
  [[ -x "$DEV_RUNTIME/php/$version/bin/php" ]] \
    || die "PHP $version não está instalado — rode \`$DEV install\`"
  printf '%s\n' "$DEV_RUNTIME/php/$version/bin/php"
}

node_bin() {
  local version="${1:-}"
  [[ -z "$version" ]] && version="$(config_get DEFAULT_NODE)"
  [[ -n "$version" ]] || return 1
  if [[ ! -d "$DEV_RUNTIME/node/$version" ]]; then
    local found
    found="$(newest_patch "$DEV_RUNTIME/node" "$version")"
    [[ -n "$found" ]] && version="$found"
  fi
  [[ -x "$DEV_RUNTIME/node/$version/bin/node" ]] || return 1
  printf '%s\n' "$DEV_RUNTIME/node/$version/bin/node"
}

mysql_cli() {
  MYSQL_PWD="$(config_get MYSQL_PASSWORD)" \
    "$(mysql_prefix)/bin/mysql" --socket="$DEV_RUN/mysql.sock" \
    -u "$(config_get MYSQL_USER)" "$@"
}

mysqldump_cli() {
  MYSQL_PWD="$(config_get MYSQL_PASSWORD)" \
    "$(mysql_prefix)/bin/mysqldump" --socket="$DEV_RUN/mysql.sock" \
    -u "$(config_get MYSQL_USER)" "$@"
}

CA_KEY="$DEV_CERTS/ca-key.pem"
CA_CRT="$DEV_CERTS/ca.pem"
LEAF_KEY="$DEV_CERTS/site-key.pem"
LEAF_CRT="$DEV_CERTS/site.pem"
CA_NAME="dev Local Development CA"

# ------------------------------------------------------------- plataforma
platform() {
  if [[ -n "${DEV_PLATFORM:-}" ]]; then
    printf '%s\n' "$DEV_PLATFORM"
  elif [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
    printf 'wsl\n'
  else
    printf 'linux\n'
  fi
}

is_wsl() { [[ "$(platform)" == wsl ]]; }

supported_system() {
  local os_release="$1" arch="$2" id="" id_like=""
  if [[ -f "$os_release" ]]; then
    id="$(grep -oP '^ID="?\K[^"]*' "$os_release" 2>/dev/null || true)"
    id_like="$(grep -oP '^ID_LIKE="?\K[^"]*' "$os_release" 2>/dev/null || true)"
  fi
  case " $id $id_like " in
    *" debian "*|*" ubuntu "*) ;;
    *) printf 'só Debian e Ubuntu são suportados — este sistema é "%s"\n' "${id:-desconhecido}"
       return 1 ;;
  esac
  case "$arch" in
    x86_64|amd64) ;;
    *) printf 'só x86_64 é suportado — esta máquina é %s\n' "$arch"
       return 1 ;;
  esac
}

no_windows() {
  local path="$1" reason="$2"
  is_wsl || return 0
  case "$(readlink -f "$path" 2>/dev/null || echo "$path")" in
    /mnt/c/*|/mnt/d/*|/mnt/[a-z]/*)
      die "$reason está no disco do Windows ($path).
     Mova para dentro do WSL, por exemplo ~/Code — no /mnt a leitura de
     arquivo é ordens de grandeza mais lenta." ;;
  esac
}

# ----------------------------------------------------------------- dev.conf
find_project() {
  local dir="${1:-$PWD}"
  dir="$(cd "$dir" 2>/dev/null && pwd)" || return 1
  while [[ "$dir" != "/" ]]; do
    [[ -f "$dir/dev.conf" ]] && { printf '%s\n' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}

load_project() {
  local dir
  dir="$(find_project "${1:-$PWD}")" || return 1
  PROJECT_DIR="$dir"
  PROJECT_NAME=""; PROJECT_APP=""; PROJECT_PHP=""; PROJECT_DOCROOT="."
  PROJECT_DATABASE=""; PROJECT_NODE=""
  local PHP="" NODE=""
  # shellcheck disable=SC1090
  source "$dir/dev.conf"
  PROJECT_NAME="${PROJECT:-$(basename "$dir")}"
  PROJECT_APP="${APP:-}"
  PROJECT_PHP="${PHP:-}"
  PROJECT_DOCROOT="${DOCROOT:-.}"
  PROJECT_DATABASE="${DATABASE:-}"
  PROJECT_NODE="${NODE:-}"
  export PROJECT_DIR PROJECT_NAME PROJECT_APP PROJECT_PHP PROJECT_DOCROOT \
         PROJECT_DATABASE PROJECT_NODE
}

looks_like_project() {
  local dir="$1" marker
  for marker in artisan wp-settings.php public/wp-settings.php \
                app/admin/cli/cron.php wp-load.php wp-config.php composer.json; do
    [[ -e "$dir/$marker" ]] && { printf '%s\n' "$marker"; return 0; }
  done
  return 1
}

require_project() {
  load_project && return 0

  bad "não há dev.conf aqui nem acima"
  blank

  local marker
  if marker="$(looks_like_project "$PWD")"; then
    info "mas aqui tem um ${marker} — este diretório parece um projeto"
    hint "adote:  $DEV init    escreve o dev.conf lendo a aplicação"
    hint "depois: $DEV up      põe no ar"
    blank
    exit 1
  fi

  local known=() file
  for file in "$DEV_SITES"/*; do [[ -f "$file" ]] && known+=("$(basename "$file")"); done

  if (( ${#known[@]} > 0 )); then
    hint "entre no diretório de um projeto:"
    for file in "${known[@]}"; do
      printf '     %scd %s%s\n' "$C_DIM" "$(sed "s|^$HOME|~|" "$DEV_SITES/$file" 2>/dev/null || true)" "$C_RESET"
    done
    blank
    hint "ou nomeie o projeto, nos comandos que aceitam:  ${DEV_COMMAND:-<comando>} <nome>"
  else
    hint "crie um:   $DEV new <app> <nome>"
    hint "ou adote:  $DEV init   (num diretório que já tem código)"
  fi
  blank
  exit 1
}

project_conf_set() {
  local file="$1" key="$2" value="$3"
  if grep -qE "^${key}=" "$file"; then
    sed -i -E "s|^${key}=.*|${key}=\"${value}\"|" "$file"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$file"
  fi
}

# --------------------------------------------------------- config da máquina
config_get() {
  [[ -f "$DEV_CONFIG" ]] || return 0
  # shellcheck disable=SC1090
  ( source "$DEV_CONFIG"; printf '%s\n' "${!1:-}" )
}

config_set() {
  local key="$1" value="$2" tmp
  mkdir -p "$(dirname "$DEV_CONFIG")"
  touch "$DEV_CONFIG"
  tmp="$(mktemp)"
  grep -v "^${key}=" "$DEV_CONFIG" > "$tmp" || true
  printf '%s=%q\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$DEV_CONFIG"
}

# ------------------------------------------------------- atalhos de comando
write_cli_shortcuts() {
  mkdir -p "$DEV_BIN"
  cat > "$DEV_BIN/composer" <<SH
#!/usr/bin/env bash
# Gerado pelo dev. O Composer do sandbox, com o PHP do projeto.
exec php "$DEV_RUNTIME/composer/composer.phar" "\$@"
SH
  if [[ -f "$DEV_RUNTIME/wp-cli/wp-cli.phar" ]]; then
    cat > "$DEV_BIN/wp" <<SH
#!/usr/bin/env bash
# Gerado pelo dev. O WP-CLI do sandbox, com o PHP do projeto.
exec php -d error_reporting="E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED" \\
  "$DEV_RUNTIME/wp-cli/wp-cli.phar" "\$@"
SH
    chmod +x "$DEV_BIN/wp"
  fi
  chmod +x "$DEV_BIN/composer"
}

project_path_prefix() {
  local php_dir node="" mysql_bin
  php_dir="$DEV_RUNTIME/php/$(php_version "$1")"
  node="$(node_bin "${2:-}" 2>/dev/null || node_bin 2>/dev/null || true)"
  [[ -n "$node" ]] && node="$(dirname "$node")"
  [[ -x "$DEV_BIN/composer" ]] || write_cli_shortcuts
  mysql_bin="$(mysql_prefix)/bin"
  [[ -x "$mysql_bin/mysql" ]] || mysql_bin=""
  printf '%s\n' "$php_dir/bin:$php_dir/sbin${node:+:$node}:$DEV_BIN${mysql_bin:+:$mysql_bin}"
}

project_env() {
  local php
  php="$(php_bin "$1")" || return 1
  PATH="$(project_path_prefix "$1" "${2:-}"):$PATH"
  PHP_INI_SCAN_DIR="$DEV_ETC/php/$(basename "$(dirname "$(dirname "$php")")")/conf.d"
  export PATH PHP_INI_SCAN_DIR
  export_node_env
}

export_node_env() {
  [[ -f "$CA_CRT" ]] && export NODE_EXTRA_CA_CERTS="$CA_CRT"
  return 0
}

# ------------------------------------------------------------------ download
download() {
  local url="$1" name="$2" sha="${3:-}" target="$DEV_CACHE/$2"
  mkdir -p "$DEV_CACHE"

  if [[ -f "$target" ]]; then
    if [[ -z "$sha" ]] || check_sha "$target" "$sha"; then
      printf '%s\n' "$target"; return 0
    fi
    warn "cache de $name não confere com o sha256 — baixando de novo" >&2
    rm -f "$target"
  fi

  info "baixando $name" >&2
  local bar=(--silent --show-error)
  [[ -t 1 ]] && bar=(--progress-bar)
  curl -fL -R "${bar[@]}" --retry 3 --retry-delay 2 \
       -o "$target.partial" "$url" >&2 || {
    rm -f "$target.partial"
    die "falhou baixar $url"
  }
  if [[ -n "$sha" ]] && ! check_sha "$target.partial" "$sha"; then
    rm -f "$target.partial"
    die "$name baixou com sha256 diferente do esperado"
  fi
  mv "$target.partial" "$target"
  printf '%s\n' "$target"
}

download_fresh() {
  local url="$1" name="$2" target="$DEV_CACHE/$2"
  [[ -f "$target" ]] || { download "$url" "$name"; return; }
  local bar=(--silent --show-error) code
  [[ -t 1 ]] && bar=(--progress-bar)
  code="$(curl -fL -R -z "$target" "${bar[@]}" --retry 2 --max-time 600 \
            -o "$target.partial" -w '%{http_code}' "$url" 2>/dev/null || echo 000)"
  case "$code" in
    200) if [[ -s "$target.partial" ]]; then
           mv "$target.partial" "$target"
           info "$name  versão nova baixada" >&2
         fi ;;
    304) ;;
    *)   warn "não consegui conferir se há versão nova de $name — usando a do cache" >&2 ;;
  esac
  rm -f "$target.partial"
  printf '%s\n' "$target"
}

check_sha() {
  local file="$1" expected="$2" actual
  actual="$(sha256sum "$file" | cut -d" " -f1 || true)"
  [[ "$actual" == "$expected" ]]
}

extract() {
  local tarball="$1" target="$2" strip="${3:-1}"
  mkdir -p "$target"
  tar -xf "$tarball" -C "$target" --strip-components="$strip"
}

build_jobs() {
  local n
  n="$(nproc 2>/dev/null || echo 2)"
  (( n > 2 )) && n=$(( n - 1 ))
  printf '%s\n' "$n"
}

# ------------------------------------------------------------- receitas e hooks
RECIPE_HOOKS=(
  recipe_title recipe_docroot recipe_php recipe_ask
  recipe_install recipe_restore recipe_next_steps
  recipe_change_password recipe_has_user recipe_identity
  recipe_gitignore recipe_schedule recipe_workers
)

unload_recipe() {
  local hook
  for hook in "${RECIPE_HOOKS[@]}"; do unset -f "$hook" 2>/dev/null || true; done
}

load_recipe() {
  local app="$1"
  unload_recipe
  if [[ -f "$DEV_PLUGINS/installed/$app/recipe.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_PLUGINS/installed/$app/recipe.sh"
    return 0
  fi
  if [[ -f "$DEV_ROOT/plugins/$app/recipe.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/plugins/$app/recipe.sh"
    return 0
  fi
  return 1
}

# ------------------------------------------------------------------ perguntas
ask() {
  local text="$1" default="${2:-}" answer
  [[ -t 0 ]] || return 1
  if [[ -n "$default" ]]; then
    read -r -p "  ?  $text [$default] " answer
    printf '%s\n' "${answer:-$default}"
  else
    read -r -p "  ?  $text " answer
    printf '%s\n' "$answer"
  fi
}

choose() {
  local text="$1"; shift
  local options=("$@") i answer lower found
  [[ -t 0 ]] || return 1
  printf '\n  %s?%s  %s\n' "$C_YELLOW" "$C_RESET" "$text" >&2
  for i in "${!options[@]}"; do
    printf '     %s%d%s  %s\n' "$C_BOLD" "$(( i + 1 ))" "$C_RESET" "${options[i]}" >&2
  done
  printf '\n' >&2

  while true; do
    read -r -p "  ?  1-${#options[@]}, ou o começo do nome: " answer
    answer="${answer#"${answer%%[![:space:]]*}"}"
    answer="${answer%"${answer##*[![:space:]]}"}"

    if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= ${#options[@]} )); then
      printf '%s\n' "${options[$(( answer - 1 ))]}"; return 0
    fi

    if [[ -n "$answer" ]]; then
      lower="${answer,,}"
      found=()
      for i in "${options[@]}"; do
        [[ "${i,,}" == "$lower"* ]] && found+=("$i")
      done
      if (( ${#found[@]} == 1 )); then
        printf '%s\n' "${found[0]}"; return 0
      elif (( ${#found[@]} > 1 )); then
        printf '     %s"%s" serve para %d opções — seja mais específico%s\n' \
          "$C_DIM" "$answer" "${#found[@]}" "$C_RESET" >&2
        continue
      fi
    fi
    printf '     %sescolha um número de 1 a %d, ou o começo do nome%s\n' \
      "$C_DIM" "${#options[@]}" "$C_RESET" >&2
  done
}

random_password() {
  local body digit symbol
  body="$(LC_ALL=C tr -dc 'a-km-zA-HJ-NP-Z' </dev/urandom 2>/dev/null | head -c 10 || true)"
  digit="$(LC_ALL=C tr -dc '2-9' </dev/urandom 2>/dev/null | head -c 1 || true)"
  symbol="$(LC_ALL=C tr -dc '!@#%*_-' </dev/urandom 2>/dev/null | head -c 1 || true)"
  printf 'Dev%s%s%s\n' "$body" "$digit" "$symbol"
}

with_progress() {
  local text="$1"; shift
  local log
  log="$(mktemp)"

  if [[ ! -t 1 ]]; then
    info "$text"
    local rc=0
    "$@" >"$log" 2>&1 || rc=$?
    if (( rc == 0 )); then rm -f "$log"; return 0; fi
    show_failure "$text" "$log"
    return "$rc"
  fi

  "$@" >"$log" 2>&1 &
  local pid=$! rc=0
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 start=$SECONDS
  local columns
  columns=$(( $(tput cols 2>/dev/null || echo 80) ))

  while kill -0 "$pid" 2>/dev/null; do
    local frame="${frames:$(( i % 10 )):1}"
    local elapsed=$(( SECONDS - start ))
    local last=""
    last="$(tail -20 "$log" 2>/dev/null \
      | grep -vE '^(PHP )?(Deprecated|Notice|Warning|Strict Standards):' \
      | tail -1 | tr -d '\r\n' | tr -cd '[:print:]' || true)"
    local room=$(( columns - ${#text} - 20 ))
    (( room < 0 )) && room=0
    printf '\r  %s%s%s  %s  %s%s%s %s%s%s\033[K' \
      "$C_CYAN" "$frame" "$C_RESET" "$text" \
      "$C_DIM" "$(clock "$elapsed")" "$C_RESET" \
      "$C_DIM" "${last:0:$room}" "$C_RESET"
    sleep 0.12
    i=$(( i + 1 ))
  done
  wait "$pid" || rc=$?
  printf '\r\033[K'

  if (( rc == 0 )); then
    printf '  %s✔%s  %s  %s%s%s\n' "$C_GREEN" "$C_RESET" "$text" \
      "$C_DIM" "$(clock $(( SECONDS - start )))" "$C_RESET"
    rm -f "$log"
    return 0
  fi
  show_failure "$text" "$log"
  return "$rc"
}

clock() {
  local seconds="$1"
  if (( seconds < 60 )); then printf '%ds\n' "$seconds"
  else printf '%dm%02ds\n' $(( seconds / 60 )) $(( seconds % 60 )); fi
}

show_failure() {
  local text="$1" log="$2" saved
  saved="$DEV_CACHE/failure-$(date +%s).log"
  bad "$text falhou"
  blank
  tail -20 "$log" 2>/dev/null | sed 's/^/     /' || true
  blank
  mkdir -p "$DEV_CACHE"
  mv "$log" "$saved" 2>/dev/null || true
  hint "saída completa em $saved"
}

announce_credentials() {
  local user="$1" password="$2"
  blank
  printf '  %s✔%s  conta criada: %s%s%s   senha %s%s%s\n' \
    "$C_GREEN" "$C_RESET" "$C_BOLD" "$user" "$C_RESET" "$C_BOLD" "$password" "$C_RESET"
  hint "não é guardada em lugar nenhum — se perder, $DEV passwd cria outra"
  blank
}
