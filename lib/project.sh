#!/usr/bin/env bash
# Gerenciamento de projetos: ciclo de vida, vhosts, adoção e execução isolada.

valid_name() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]]; }

RESERVED_NAMES=(adminer db mailpit mail localhost plugin plugins)
reserved_name() { [[ " ${RESERVED_NAMES[*]} " == *" $1 "* ]]; }

site_exists() { [[ -f "$DEV_SITES/$1" ]]; }

site_url() { printf 'https://%s.localhost\n' "$1"; }

write_project_conf() {
  local dir="$1" name="$2" app="$3" docroot="$4" database="$5" php="${6:-}"
  cat > "$dir/dev.conf" <<CONF
# Configuração deste projeto, lida pelo dev.
#
# Após editar: dev up

PROJECT="$name"
APP="$app"           # wordpress, moodle, laravel — ou vazio para PHP puro
PHP="${php:-$(config_get DEFAULT_PHP)}"
NODE=""              # vazio = padrão da máquina
DOCROOT="$docroot"   # relativo à raiz do projeto
DATABASE="$database" # vazio = sem banco
CONF
}

detect_docroot() {
  local dir="$1" candidate
  for candidate in public web html app/public; do
    [[ -f "$dir/$candidate/index.php" ]] && { printf '%s\n' "$candidate"; return; }
  done
  printf '.\n'
}

write_gitignore() {
  local dir="$1"
  declare -F recipe_gitignore >/dev/null || return 0
  [[ -f "$dir/.gitignore" ]] && return 0
  recipe_gitignore > "$dir/.gitignore"
  hint ".gitignore escrito com regras de escada da aplicação"
}

detect_app() {
  local dir="$1" candidate
  [[ -f "$dir/artisan" ]] && { printf 'laravel\n'; return; }
  for candidate in . public wordpress public/wordpress; do
    [[ -f "$dir/$candidate/wp-settings.php" ]] && { printf 'wordpress\n'; return; }
  done
  for candidate in . app; do
    [[ -f "$dir/$candidate/version.php" && -f "$dir/$candidate/lib/setup.php" ]] && { printf 'moodle\n'; return; }
  done
  return 0
}

detect_database() {
  local dir="$1" app="$2" candidate value
  case "$app" in
    wordpress)
      for candidate in . public wordpress public/wordpress; do
        [[ -f "$dir/$candidate/wp-config.php" ]] || continue
        value="$(wp_config_value "$dir/$candidate" DB_NAME || true)"
        [[ -n "$value" ]] && { printf '%s\n' "$value"; return 0; }
      done
      env_value "$dir/.env" DB_NAME ;;
    laravel)
      value="$(env_value "$dir/.env" DB_DATABASE || true)"
      printf '%s\n' "$value" ;;
    moodle)
      for candidate in . app; do
        [[ -f "$dir/$candidate/config.php" ]] || continue
        value="$(grep -hoP "\$CFG->dbname\s*=\s*['\"]\K[^'\"]*" "$dir/$candidate/config.php" 2>/dev/null | head -1 || true)"
        [[ -n "$value" ]] && { printf '%s\n' "$value"; return 0; }
      done ;;
  esac
}

wp_config_value() {
  local dir="$1" key="$2" file value
  for file in "$dir/wp-config.php" "$dir"/wp-config*.php; do
    [[ -f "$file" ]] || continue
    [[ "$file" == *wp-config-sample.php ]] && continue
    value="$(grep -hoP "define\(\s*'${key}'\s*,\s*'\K[^']*" "$file" 2>/dev/null | head -1 || true)"
    [[ -n "$value" ]] && { printf '%s\n' "$value"; return 0; }
  done
  return 1
}

env_value() {
  [[ -f "$1" ]] || return 0
  grep -oP "^${2}=\K.*" "$1" 2>/dev/null | head -1 | tr -d "\"'" || true
}

detect_database_host() {
  local dir="$1" app="$2" candidate host="" port=""
  case "$app" in
    wordpress)
      for candidate in . public wordpress public/wordpress; do
        [[ -f "$dir/$candidate/wp-config.php" ]] || continue
        host="$(wp_config_value "$dir/$candidate" DB_HOST || true)"
        [[ -n "$host" ]] && break
      done
      if [[ "$host" == *:* ]]; then port="${host##*:}"; host="${host%%:*}"; fi
      if [[ -z "$host" ]]; then
        host="$(env_value "$dir/.env" DB_HOST)"
        port="$(env_value "$dir/.env" DB_PORT)"
      fi ;;
    laravel)
      host="$(env_value "$dir/.env" DB_HOST)"
      port="$(env_value "$dir/.env" DB_PORT)" ;;
    moodle)
      for candidate in . app; do
        [[ -f "$dir/$candidate/config.php" ]] || continue
        host="$(grep -hoP "\$CFG->dbhost\s*=\s*['\"]\K[^'\"]*" "$dir/$candidate/config.php" 2>/dev/null | head -1 || true)"
        port="$(grep -hoP "'dbport'\s*=>\s*\K[0-9]+" "$dir/$candidate/config.php" 2>/dev/null | head -1 || true)"
        [[ -n "$host" ]] && break
      done ;;
  esac
  [[ -n "$host" ]] || return 1
  printf '%s:%s\n' "$host" "${port:-3306}"
}

series_of() { printf '%s\n' "${1%.*}"; }

ensure_php() {
  local series="$1" title="$2" found installed installed_series
  found="$(php_version "$series")"
  if [[ -x "$DEV_RUNTIME/php/$found/bin/php" ]]; then
    return 0
  fi

  declare -F compile_runtime >/dev/null || source "$DEV_ROOT/lib/runtime.sh" 2>/dev/null || true

  # Se o tarball já estiver presente em runtimes/php/, apenas extrai
  local local_tarball=""
  if declare -F runtime_local_tarball >/dev/null; then
    local_tarball="$(runtime_local_tarball php "$series" 2>/dev/null || true)"
  fi
  if [[ -n "$local_tarball" && -f "$local_tarball" ]]; then
    info "instalando PHP $series a partir de runtimes/php/"
    if install_runtime php "$series"; then
      return 0
    fi
  fi

  installed="$(php_installed_version)"
  installed_series="$(series_of "$installed")"
  blank
  warn "o $title pede PHP $series, mas este dev ainda não tem esta versão"
  hint "PHP instalado: ${installed:-nenhum}"
  blank

  if confirm "Deseja compilar o PHP $series a partir do fonte oficial agora?" s; then
    blank
    step "COMPILAÇÃO SOB DEMANDA: PHP $series"
    if compile_runtime php "$series"; then
      ok "PHP $series instalado com sucesso"
      return 0
    else
      bad "falha ao compilar o PHP $series"
      return 1
    fi
  fi

  blank
  warn "criação cancelada: o $title requer PHP $series"
  if [[ -n "$installed_series" ]]; then
    hint "para usar a versão já instalada por sua conta e risco: use --php $installed_series"
  fi
  blank
  return 1
}

create_database() {
  local database="$1"
  [[ -n "$database" ]] || return 0
  mysql_cli -e "CREATE DATABASE IF NOT EXISTS \`$database\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
    || die "não consegui criar o banco $database"
  ok "banco $database"
}

database_credentials() {
  local database="$1"
  [[ -n "$database" ]] || return 0
  hint "banco $database em 127.0.0.1:$MYSQL_PORT   usuário: $(config_get MYSQL_USER) / senha: $(config_get MYSQL_PASSWORD)"
  hint "abra no navegador: $DEV open db   (entra direto pelo Adminer)"
}

cmd_new() {
  local app="" name="" php_chosen=""
  if [[ $# -ge 2 ]]; then
    app="$1"
    name="$2"
    shift 2
  elif [[ $# -eq 1 ]]; then
    name="$1"
    shift
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --php) php_chosen="${2:-}"; shift ;;
      -*)    die "opção desconhecida: $1" ;;
      *)     [[ -z "$name" ]] && name="$1" ;;
    esac
    shift
  done

  if [[ -z "$app" ]]; then
    local installed=()
    mapfile -t installed < <(find "$DEV_PLUGINS/installed" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null || true)
    if [[ ${#installed[@]} -eq 1 ]]; then
      app="${installed[0]}"
    else
      die "uso: ${DEV_COMMAND:-$DEV new} <app> <nome>  (ex: $DEV new wordpress meu-site)"
    fi
  fi

  if [[ ! -d "$DEV_PLUGINS/installed/$app" && ! -d "$DEV_ROOT/plugins/$app" ]]; then
    bad "aplicação ou plugin \"$app\" não existe"
    hint "veja plugins disponíveis com: $DEV plugin list"
    hint "instale o plugin com:        $DEV plugin install $app"
    return 1
  fi

  if [[ ! -d "$DEV_PLUGINS/installed/$app" ]]; then
    bad "o plugin \"$app\" ainda não está instalado"
    hint "instale antes com: $DEV plugin install $app"
    return 1
  fi

  while [[ -z "$name" ]] || ! valid_name "$name" || reserved_name "$name"; do
    if [[ -n "$name" ]] && reserved_name "$name"; then
      bad "\"$name\" é um nome reservado — escolha outro"
    elif [[ -n "$name" ]]; then
      bad "nome inválido: use apenas letras minúsculas, números e traço"
    fi
    name="$(ask "Nome do projeto:")" || die "uso: $DEV new <app> <nome>"
  done
  site_exists "$name" && die "já existe um projeto chamado \"$name\" — veja \`$DEV sites\`"

  local dir="$PWD/$name"
  if [[ -e "$dir" ]]; then
    rmdir "$dir" 2>/dev/null || die "o diretório $dir já existe e não está vazio"
  fi
  no_windows "$dir" "o diretório do projeto"

  source "$DEV_ROOT/lib/services.sh"
  cmd_start --if-needed
  running mysql || die "o MySQL não subiu — veja \`$DEV fix\`"

  step "CRIANDO PROJETO $name ($app)"
  load_recipe "$app" || die "não consegui carregar a receita do plugin $app"

  local project_php="$php_chosen"
  if [[ -z "$project_php" ]] && declare -F recipe_php >/dev/null; then
    project_php="$(recipe_php)"
  fi
  [[ -n "$project_php" ]] || project_php="$(series_of "$(config_get DEFAULT_PHP)")"
  ensure_php "$project_php" "$(recipe_title 2>/dev/null || echo "$app")" || return 1

  if declare -F recipe_ask >/dev/null; then
    recipe_ask || { info "cancelado pelo usuário"; return 0; }
  fi

  local database="${name//-/_}"
  mkdir -p "$dir"
  create_database "$database"
  recipe_install "$dir" "$name" "$database"

  local docroot="."
  if declare -F recipe_docroot >/dev/null; then
    docroot="$(recipe_docroot "$dir")"
  fi
  write_project_conf "$dir" "$name" "$app" "$docroot" "$database" "$project_php"
  write_gitignore "$dir"

  if declare -F recipe_schedule >/dev/null; then
    recipe_schedule > "$dir/dev.schedule"
  fi
  if declare -F recipe_workers >/dev/null; then
    recipe_workers > "$dir/dev.workers"
  fi

  mkdir -p "$DEV_UP"
  : > "$DEV_UP/$name"
  ( load_project "$dir" && cd "$dir" && serve_project "$dir" )

  blank
  ok "$(recipe_title 2>/dev/null || echo "$app") pronto em $(site_url "$name")"
  if declare -F recipe_next_steps >/dev/null; then
    recipe_next_steps "$dir" "$name"
  fi
  database_credentials "$database"
  blank
  cmd_open "$name" || true
}

cmd_init() {
  [[ -f "$PWD/dev.conf" ]] && die "já existe um dev.conf aqui"
  no_windows "$PWD" "o diretório do projeto"
  local name docroot app database
  name="$(basename "$PWD")"
  docroot="$(detect_docroot "$PWD")"
  app="$(detect_app "$PWD")"
  database="$(detect_database "$PWD" "$app")"

  write_project_conf "$PWD" "$name" "$app" "$docroot" "$database" \
    "$(series_of "$(config_get DEFAULT_PHP)")"

  ok "dev.conf escrito com sucesso"
  blank
  label "aplicação" "${app:-${C_DIM}PHP puro${C_RESET}}"
  label "docroot"   "$docroot"
  if [[ -n "$database" ]]; then
    label "banco" "$database  ${C_DIM}(detectado da aplicação)${C_RESET}"
  else
    label "banco" "${C_DIM}nenhum banco declarado${C_RESET}"
  fi
  blank
  hint "confira o dev.conf e suba com: $DEV up"
  blank
}

bring_up() {
  require_project
  no_windows "$PROJECT_DIR" "o diretório do projeto"
  source "$DEV_ROOT/lib/services.sh"
  source "$DEV_ROOT/lib/config.sh"

  ensure_php "${PROJECT_PHP:-$(series_of "$(config_get DEFAULT_PHP)")}" "$PROJECT_NAME" || return 1

  if [[ -n "$PROJECT_DATABASE" ]]; then
    running mysql || start_mysql \
      || die "o MySQL não subiu — $DEV fix mostra o que está no caminho"
    create_database "$PROJECT_DATABASE"
  fi

  if [[ -n "$PROJECT_APP" ]]; then
    if load_recipe "$PROJECT_APP" && declare -F recipe_restore >/dev/null; then
      recipe_restore "$PROJECT_DIR" "$PROJECT_NAME" "$PROJECT_DATABASE" || true
    fi
  fi

  write_gitignore "$PROJECT_DIR"
  serve_project "$PROJECT_DIR"
  blank
  ok "$PROJECT_NAME  servindo  $(site_url "$PROJECT_NAME")"
  hint "docroot $PROJECT_DIR/$PROJECT_DOCROOT · PHP $PROJECT_PHP"

  if [[ -n "$PROJECT_DATABASE" ]] && running mysql; then
    local tables host
    tables="$(mysql_cli -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$PROJECT_DATABASE';" 2>/dev/null || echo 0)"
    host="$(detect_database_host "$PROJECT_DIR" "$PROJECT_APP" 2>/dev/null || true)"

    if [[ -n "$host" && "$host" != "127.0.0.1:$MYSQL_PORT" && "$host" != "localhost:$MYSQL_PORT" ]]; then
      blank
      warn "a aplicação aponta para $host, fora do MySQL do dev"
      hint "seus dados continuam lá — o banco $PROJECT_DATABASE do dev está sem uso"
    elif (( tables == 0 )); then
      hint "o banco $PROJECT_DATABASE (127.0.0.1:$MYSQL_PORT) está vazio"
    fi
  fi
  blank
}

serve_project() {
  local dir="$1"
  source "$DEV_ROOT/lib/config.sh"
  source "$DEV_ROOT/lib/certs.sh"
  local docroot="$dir/${PROJECT_DOCROOT:-$(detect_docroot "$dir")}"
  [[ -d "$docroot" ]] || die "o docroot $docroot não existe"

  mkdir -p "$DEV_SITES"
  printf '%s\n' "$dir" > "$DEV_SITES/${PROJECT_NAME:-$(basename "$dir")}"
  write_vhost "${PROJECT_NAME:-$(basename "$dir")}" "$docroot" "${PROJECT_PHP:-$(config_get DEFAULT_PHP)}"

  source "$DEV_ROOT/lib/services.sh"
  if running nginx; then
    write_fpm_pools
    start_fpm
  fi

  if [[ -f "$DEV_ROOT/lib/schedule.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/schedule.sh"
    local site_now="${PROJECT_NAME:-$(basename "$dir")}"
    local php_now="${PROJECT_PHP:-$(config_get DEFAULT_PHP)}"
    stop_site_tasks "$site_now" 2>/dev/null || true
    start_site_tasks "$site_now" "$dir" "$php_now" schedule 2>/dev/null || true
    if [[ -f "$DEV_UP/$site_now" ]]; then
      start_site_tasks "$site_now" "$dir" "$php_now" worker 2>/dev/null || true
    fi
  fi

  reissue_leaf
  reload_nginx
}

reload_nginx() {
  source "$DEV_ROOT/lib/services.sh"
  source "$DEV_ROOT/lib/config.sh"
  running nginx || return 0
  write_nginx_files
  local prefix
  prefix="$(nginx_prefix)"
  "$prefix/sbin/nginx" -c "$DEV_ETC/nginx/nginx.conf" -p "$prefix" -t >/dev/null 2>&1 \
    || die "a configuração gerada do nginx é inválida"
  refresh_nginx
}

take_down() {
  local name="$1"
  if [[ -f "$DEV_ROOT/lib/schedule.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/schedule.sh"
    stop_site_tasks "$name" 2>/dev/null || true
  fi
  rm -f "$DEV_SITES/$name" "$DEV_ETC/nginx/sites/$name.conf" "$DEV_UP/$name"
  source "$DEV_ROOT/lib/certs.sh"
  reissue_leaf
  reload_nginx
}

cmd_destroy() {
  local name="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes|-f|--force) force=1 ;;
      *) name="$1" ;;
    esac
    shift
  done
  [[ -n "$name" ]] || die "uso: ${DEV_COMMAND:-$DEV destroy} <nome>"
  site_exists "$name" || die "não há projeto chamado \"$name\""
  local dir
  dir="$(cat "$DEV_SITES/$name")"

  local database=""
  if [[ -f "$dir/dev.conf" ]] && load_project "$dir" >/dev/null 2>&1; then
    database="$PROJECT_DATABASE"
  fi

  step "APAGAR $name"
  printf '  %s✘%s  Arquivos   %s\n' "$C_RED" "$C_RESET" "$dir"
  printf '  %s✘%s  Banco      %s\n' "$C_RED" "$C_RESET" "${database:-nenhum declarado}"
  [[ -d "$DEV_SNAPSHOTS/$name" ]] && printf '  %s✘%s  Snapshots  %s ponto(s)\n' "$C_RED" "$C_RESET" \
    "$(ls -1 "$DEV_SNAPSHOTS/$name" | wc -l || true)"
  printf '  %s✘%s  Vhost      %s\n' "$C_RED" "$C_RESET" "$DEV_ETC/nginx/sites/$name.conf"
  printf '  %s✘%s  No ar      sai do nginx e do certificado\n' "$C_RED" "$C_RESET"
  blank
  if (( ! force )); then
    local word
    read -r -p "  ?  Digite \"$name\" para confirmar a destruição: " word || true
    [[ "$word" == "$name" ]] || { info "cancelado; nada foi apagado"; return 0; }
  fi

  take_down "$name" >/dev/null 2>&1 || true
  source "$DEV_ROOT/lib/services.sh"
  if [[ -n "$database" ]] && running mysql; then
    mysql_cli -e "DROP DATABASE IF EXISTS \`$database\`;" 2>/dev/null || true
  fi
  rm -rf "${dir:?}" "$DEV_SNAPSHOTS/${name:?}" "$DEV_UP/${name:?}" "$DEV_QUIET/${name:?}"
  rm -f "$DEV_LOG/$name"-*.log "$DEV_LOG/schedule-$name"-*.log \
        "$DEV_LOG/worker-$name"-*.log "$DEV_RUN/schedule-$name"-*.runs \
        "$DEV_RUN/worker-$name"-*.runs
  ok "$name apagado com sucesso"
}

cmd_sites() {
  step "PROJETOS"
  local file name dir found=0
  for file in "$DEV_SITES"/*; do
    [[ -f "$file" ]] || continue
    found=1
    name="$(basename "$file")"
    dir="$(cat "$file")"
    local mark="$C_GREEN✔$C_RESET"
    [[ -d "$dir" ]] || mark="$C_YELLOW▲$C_RESET"
    printf '  %b  %-14s %s%-34s%s %s%s%s\n' "$mark" "$name" \
      "$C_BLUE" "$(site_url "$name")" "$C_RESET" "$C_DIM" "${dir/#$HOME/\~}" "$C_RESET"
  done
  (( found )) || hint "nenhum site registrado ainda — crie com \`$DEV new <app> <nome>\`"
  blank
}

project_environment() {
  require_project
  project_env "$PROJECT_PHP" "$PROJECT_NODE" || exit 1
  DATABASE_URL="mysql://$(config_get MYSQL_USER):$(config_get MYSQL_PASSWORD)@127.0.0.1:$MYSQL_PORT/$PROJECT_DATABASE"
  export DATABASE_URL
}

cmd_exec() {
  [[ $# -gt 0 ]] || die "uso: ${DEV_COMMAND:-$DEV exec} <comando…>"
  project_environment
  cd "$PROJECT_DIR" || exit 1
  exec "$@"
}

cmd_shell() {
  project_environment
  cd "$PROJECT_DIR" || exit 1
  info "shell do projeto $PROJECT_NAME — digite \`exit\` para sair"
  exec "${SHELL:-/bin/bash}"
}

cmd_open() {
  local name="${1:-}"
  [[ -z "$name" ]] && { load_project >/dev/null 2>&1 && name="$PROJECT_NAME"; }
  [[ -n "$name" ]] || die "uso: ${DEV_COMMAND:-$DEV open} <projeto|mail|db>"
  case "$name" in
    mail) name=mailpit ;;
    db)   name=adminer ;;
  esac
  local url
  url="$(site_url "$name")"
  if [[ "$name" == adminer ]]; then
    load_project >/dev/null 2>&1 || true
    if [[ -n "${PROJECT_DATABASE:-}" ]]; then
      url="$url/?db=$PROJECT_DATABASE"
    fi
  elif [[ "$name" == mailpit ]]; then
    url="https://mail.localhost"
  else
    site_exists "$name" || die "não há projeto chamado \"$name\" — veja \`$DEV sites\`"
  fi
  open_in_browser "$url"
}

EXPLORER_EXE="/mnt/c/Windows/explorer.exe"

open_in_browser() {
  local url="$1"
  if is_wsl && [[ -x "$EXPLORER_EXE" ]]; then
    "$EXPLORER_EXE" "$url" >/dev/null 2>&1 || true
    hint "abrindo $url"
  elif ! is_wsl && has xdg-open && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    xdg-open "$url" >/dev/null 2>&1 &
    hint "abrindo $url"
  else
    hint "abra $url no navegador"
  fi
}
