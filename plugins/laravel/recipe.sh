#!/usr/bin/env bash
# Laravel: scaffolding, .env, migrações, workers de fila, Vite e cron.

recipe_title() { printf 'Laravel\n'; }

recipe_docroot() { printf 'public\n'; }

# Versão do framework instalado, lida do vendor (sem rodar PHP).
recipe_version() {
  local file="$1/vendor/laravel/framework/src/Illuminate/Foundation/Application.php"
  [[ -f "$file" ]] || return 1
  sed -n "/const VERSION = '/{s/.*const VERSION = '\([^']*\)'.*/\1/p;q;}" "$file"
}

# O Laravel não ganha chave no dev.conf: quem fixa a versão é o composer.lock,
# que o composer install do dev up respeita.
recipe_pin() {
  if [[ -f "$1/composer.lock" ]]; then
    info "o Laravel é fixado pelo composer.lock — mantenha-o no git" >&2
  else
    warn "não há composer.lock: sem ele, cada composer install pode trazer versões diferentes" >&2
    hint "o $DEV exec composer install o gera; depois faça commit dele" >&2
  fi
}

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

# ------------------------------------------------------------------- testes
# pest (ou phpunit): a suíte do projeto pelo "php artisan test".
# browser: testes de navegador do Pest 4 (pestphp/pest-plugin-browser), que
#          serve a aplicação em processo e abre o navegador do Playwright do
#          projeto (Chrome for Testing desde o Playwright 1.57).

laravel_uses_pest() {
  [[ -x vendor/bin/pest ]] || grep -q '"pestphp/pest"' composer.json 2>/dev/null
}

recipe_test_suites() {
  if laravel_uses_pest; then
    printf '%s\n' "pest|testes do projeto com Pest (php artisan test)"
  else
    printf '%s\n' "phpunit|testes do projeto com PHPUnit (php artisan test)"
  fi
  printf '%s\n' "browser|testes de navegador do Pest 4 (pest-plugin-browser, com o Playwright do projeto)"
}

recipe_test_ready() {
  case "$1" in
    pest|phpunit) [[ -x vendor/bin/phpunit || -x vendor/bin/pest ]] ;;
    browser)      [[ -d vendor/pestphp/pest-plugin-browser && -x node_modules/.bin/playwright ]] ;;
  esac
}

recipe_test_init() {
  case "$1" in
    pest|phpunit)
      with_progress "instalando as dependências de desenvolvimento (composer install)" \
        env COMPOSER_NO_INTERACTION=1 composer install --no-interaction ;;
    browser)
      laravel_uses_pest || die "os testes de navegador do Pest pedem o Pest no projeto — veja pestphp.com"
      if [[ ! -d vendor/pestphp/pest-plugin-browser ]]; then
        info "o plugin de navegador do Pest não está no projeto — entra como dependência de desenvolvimento"
        confirm "rodar composer require --dev pestphp/pest-plugin-browser?" s \
          || die "sem o plugin não há o que rodar"
        with_progress "instalando o pest-plugin-browser" \
          env COMPOSER_NO_INTERACTION=1 composer require --dev pestphp/pest-plugin-browser --no-interaction \
          || return 1
      fi
      if [[ ! -x node_modules/.bin/playwright ]]; then
        info "o pacote npm playwright não está no projeto"
        confirm "rodar npm install --save-dev playwright?" s \
          || die "sem o Playwright o Pest não abre o navegador"
        with_progress "instalando o Playwright (npm)" \
          npm install --save-dev --no-audit --no-fund playwright || return 1
      fi
      browser_install_deps || return 1 ;;
  esac
}

recipe_test_run() {
  local suite="$1"; shift
  case "$suite" in
    pest|phpunit)
      php artisan test "$@" ;;
    browser)
      playwright_chromium || return 1
      if [[ $# -eq 0 && -d tests/Browser ]]; then
        set -- tests/Browser
      fi
      PLAYWRIGHT_BROWSERS_PATH="$(playwright_browsers_path)" php artisan test "$@" ;;
  esac
}

# ---------------------------------------------------------- usuário de teste
# O Laravel não tem papel de administrador padrão: a conta é um usuário comum,
# com e-mail verificado.
recipe_test_user_create() {
  local dir="$1" user="$2" password="$3" output
  output="$( cd "$dir" && php artisan tinker --execute="
    \$u = \\App\\Models\\User::updateOrCreate(
      ['email' => '$(recipe_identity "$user")'],
      ['name' => 'Dev Teste', 'password' => bcrypt('$password')]
    );
    \$u->forceFill(['email_verified_at' => now()])->save();
    echo 'ok';
  " 2>&1 )" || true
  [[ "$output" == *ok* ]] || { printf '%s\n' "$output" >&2; return 1; }
  printf 'usuário comum (o Laravel não tem papel de administrador padrão)\n'
}

recipe_test_user_remove() {
  local dir="$1" user="$2" output
  output="$( cd "$dir" && php artisan tinker --execute="
    \\App\\Models\\User::where('email', '$(recipe_identity "$user")')->delete();
    echo 'ok';
  " 2>&1 )" || true
  [[ "$output" == *ok* ]]
}
