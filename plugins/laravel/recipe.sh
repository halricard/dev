#!/usr/bin/env bash
# Laravel: scaffolding, .env, migrações, workers de fila, Vite e cron.

recipe_title() { printf 'Laravel\n'; }

recipe_docroot() { printf 'public\n'; }

setup_database_env() {
  local database="$1"
  [[ -n "$database" ]] || return 0
  export DB_CONNECTION=mysql
  export DB_HOST=127.0.0.1
  export DB_PORT="$MYSQL_PORT"
  export DB_DATABASE="$database"
  DB_USERNAME="$(config_get MYSQL_USER)"
  DB_PASSWORD="$(config_get MYSQL_PASSWORD)"
  export DB_USERNAME DB_PASSWORD
}

recipe_ask() {
  local choice
  choice="$(choose "Qual banco para este projeto?" \
    "MySQL — servidor do dev, na porta $MYSQL_PORT" \
    "SQLite — um arquivo dentro do projeto")" || return 1
  case "$choice" in
    MySQL*)  LARAVEL_DB="mysql" ;;
    SQLite*) LARAVEL_DB="sqlite" ;;
  esac
}

recipe_install() {
  local dir="$1" name="$2" database="$3"
  local php
  php="$(php_bin "${PROJECT_PHP:-$(config_get DEFAULT_PHP)}")"
  local laravel="$DEV_RUNTIME/laravel-installer/bin/laravel"

  setup_database_env "$database"

  blank
  info "criando projeto Laravel..."
  blank
  rmdir "$dir" 2>/dev/null || true

  ( project_env "${PROJECT_PHP:-$(config_get DEFAULT_PHP)}" "" || exit 1
    cd "$(dirname "$dir")" && composer create-project --no-interaction laravel/laravel "$name" ) \
    || die "a instalação do Laravel falhou"

  write_env "$dir" "$name" "$database"
  ( cd "$dir" && "$php" artisan key:generate --force >/dev/null 2>&1 ) || true

  if [[ -n "$database" && "${LARAVEL_DB:-mysql}" == "mysql" ]]; then
    info "rodando migrações"
    ( cd "$dir" && "$php" artisan migrate --force >/dev/null 2>&1 ) \
      || warn "as migrações não rodaram; tente com \`$DEV exec php artisan migrate\`"
  fi

  ok "Laravel instalado"

  LARAVEL_ADMIN_USER="admin"
  LARAVEL_ADMIN_PASS="$(random_password)"
  LARAVEL_ADMIN_EMAIL="admin@$name.localhost"

  if recipe_change_password "$dir" "$LARAVEL_ADMIN_USER" "$LARAVEL_ADMIN_PASS" >/dev/null 2>&1; then
    announce_credentials "$LARAVEL_ADMIN_EMAIL" "$LARAVEL_ADMIN_PASS"
  fi
}

write_env() {
  local dir="$1" name="$2" database="$3"
  local env="$dir/.env"
  [[ -f "$env" ]] || cp "$dir/.env.example" "$env" 2>/dev/null || touch "$env"
  adjust_env "$env" APP_NAME    "$name"
  adjust_env "$env" APP_URL     "https://$name.localhost"

  if [[ -n "$database" && "${LARAVEL_DB:-mysql}" == "mysql" ]]; then
    adjust_env "$env" DB_CONNECTION mysql
    adjust_env "$env" DB_HOST     127.0.0.1
    adjust_env "$env" DB_PORT     "$MYSQL_PORT"
    adjust_env "$env" DB_DATABASE "$database"
    adjust_env "$env" DB_USERNAME "$(config_get MYSQL_USER)"
    adjust_env "$env" DB_PASSWORD "$(config_get MYSQL_PASSWORD)"
  fi

  adjust_env "$env" MAIL_MAILER smtp
  adjust_env "$env" MAIL_HOST   127.0.0.1
  adjust_env "$env" MAIL_PORT   "$SMTP_PORT"
}

adjust_env() {
  local file="$1" key="$2" value="$3"
  if grep -qE "^#?\s*${key}=" "$file"; then
    sed -i -E "s|^#?\s*${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

recipe_restore() {
  local dir="$1" name="$2" database="$3"
  setup_database_env "$database"
  local php
  php="$(php_bin "${PROJECT_PHP:-$(config_get DEFAULT_PHP)}")"
  local path
  path="$(project_path_prefix "${PROJECT_PHP:-$(config_get DEFAULT_PHP)}" "${PROJECT_NODE:-}")"

  if [[ ! -f "$dir/vendor/autoload.php" ]]; then
    info "repondo dependências (composer install)"
    ( cd "$dir" && export PATH="$path:$PATH" \
        && COMPOSER_NO_INTERACTION=1 "$php" "$DEV_RUNTIME/composer/composer.phar" \
             install --no-interaction >/dev/null 2>&1 ) || die "o composer install falhou"
  fi

  [[ -f "$dir/.env" ]] || write_env "$dir" "$name" "$database"
  grep -qE '^APP_KEY=.+' "$dir/.env" 2>/dev/null \
    || ( cd "$dir" && "$php" artisan key:generate --force >/dev/null 2>&1 ) || true

  mkdir -p "$dir"/storage/framework/{cache,sessions,views} "$dir/bootstrap/cache"
}

recipe_next_steps() {
  local dir="$1" name="$2"
  hint "artisan, queue:listen e Vite prontos para uso"
  hint "veja workers ativos com: $DEV worker"
  hint "veja agendamentos com:   $DEV schedule"
}

DEFAULT_ADMIN="admin"

recipe_change_password() {
  local dir="$1" user="$2" password="$3"
  local php
  php="$(php_bin "${PROJECT_PHP:-$(config_get DEFAULT_PHP)}")"
  local email="$user@${PROJECT_NAME:-localhost}.localhost"
  local output
  output="$( cd "$dir" && "$php" artisan tinker --execute="
    \$u = \\App\\Models\\User::updateOrCreate(
      ['email' => '$email'],
      ['name' => '$user', 'password' => bcrypt('$password')]
    );
    echo 'ok';
  " 2>&1 )" || true
  [[ "$output" == *ok* ]] && return 0
  return 1
}

recipe_has_user() {
  local dir="$1" user="$2"
  mysql_cli -N -B "$PROJECT_DATABASE" \
    -e "SELECT 1 FROM users WHERE email='$user@${PROJECT_NAME}.localhost' LIMIT 1;" \
    2>/dev/null | grep -q 1
}

recipe_identity() { printf '%s@%s.localhost\n' "$1" "${PROJECT_NAME:-app}"; }

recipe_workers() {
  cat <<'WORKERS'
# Processos contínuos deste projeto, supervisionados pelo dev.
php artisan queue:listen --tries=1 --timeout=0
npm run dev
WORKERS
}

recipe_schedule() {
  cat <<'AGENDA'
# Agenda do Laravel, lida pelo dev.
# Formato:  <intervalo em segundos>  <comando>
60 php artisan schedule:run
AGENDA
}
