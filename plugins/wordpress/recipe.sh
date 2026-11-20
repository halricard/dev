#!/usr/bin/env bash
# WordPress: receita de scaffolding, salts, MySQL e WP-Cron.

recipe_title() { printf 'WordPress\n'; }

recipe_docroot() { printf '.\n'; }

wp_core_dir() {
  local dir="$1" candidate doc="${PROJECT_DOCROOT:-.}"
  for candidate in "$doc/wordpress" "$doc" public/wordpress public wordpress .; do
    [[ -f "$dir/${candidate#./}/wp-settings.php" ]] && { printf '%s\n' "${candidate#./}"; return 0; }
  done
  return 1
}

# Versão do núcleo instalado, lida de wp-includes/version.php (sem rodar PHP).
recipe_version() {
  local dir="$1" core
  core="$(wp_core_dir "$dir")" || return 1
  sed -n "/^\$wp_version *= *'/{s/^\$wp_version *= *'\([^']*\)'.*/\1/p;q;}" "$dir/$core/wp-includes/version.php"
}

# Toda versão publicada do WordPress tem pacote próprio em wordpress.org, que
# nunca muda; a nightly (6.9-alpha-…) não tem, e por isso não se fixa.
recipe_pin_key() { printf 'WORDPRESS_VERSION\n'; }

recipe_pin() {
  local version
  version="$(recipe_version "$1" 2>/dev/null || true)"
  [[ -n "$version" ]] || { bad "não achei o núcleo do WordPress (wp-includes/version.php)" >&2; return 1; }
  if [[ "$version" == *alpha* || "$version" == *-src ]]; then
    bad "o WordPress $version é uma nightly, sem pacote para baixar de novo" >&2
    hint "atualize para uma versão publicada: $DEV exec wp core update --version=<versão> --force" >&2
    return 1
  fi
  printf 'WORDPRESS_VERSION=%s\n' "$version"
}

wp_config_file() {
  local dir="$1" candidate
  for candidate in wp-config.php "${PROJECT_DOCROOT:-.}/wp-config.php" public/wp-config.php \
           ../wp-config.php; do
    [[ -f "$dir/${candidate#./}" ]] || continue
    grep -q "wp-settings\.php" "$dir/${candidate#./}" 2>/dev/null || continue
    printf '%s\n' "$dir/${candidate#./}"
    return 0
  done
  return 1
}

wp() {
  local root="$1" dir="$1"
  shift
  local rel
  rel="$(wp_core_dir "$root" || true)"
  [[ -n "$rel" && "$rel" != "." ]] && dir="$root/$rel"
  local conf
  conf="$(wp_config_file "$root" || true)"
  local pre=()
  [[ -n "$conf" ]] && pre=(env "WP_CONFIG_PATH=$conf")

  local php_series="${PROJECT_PHP:-$(config_get DEFAULT_PHP)}"
  local php_ver; php_ver="$(php_version "$php_series")"
  local php_ini="$DEV_ETC/php/$php_ver/php.ini"

  "${pre[@]}" env PHPRC="$DEV_ETC/php/$php_ver" PHP_INI_SCAN_DIR="$DEV_ETC/php/$php_ver/conf.d" \
    "$(php_bin "$php_series")" \
    -c "$php_ini" \
    -d error_reporting="E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED" \
    "$DEV_RUNTIME/wp-cli/wp-cli.phar" --path="$dir" --allow-root "$@" \
    2> >(grep -vE '^(PHP )?(Deprecated|Warning|Notice):.*wp-cli\.phar' >&2)
}

recipe_install() {
  local dir="$1" name="$2" database="$3" tarball
  local version="${WORDPRESS_VERSION:-}"
  if [[ -n "$version" ]]; then
    tarball="$(download "$(url_for wordpress "$version")" "$(cache_name wordpress "$version")")"
  else
    tarball="$(download_fresh "$(url_for wordpress)" "$(cache_name wordpress)")"
  fi
  info "extraindo WordPress${version:+ $version}"
  tar -xf "$tarball" -C "$dir" --strip-components=1 --skip-old-files

  if [[ -f "$dir/wp-config.php" ]]; then
    info "wp-config.php já existe — mantido como está"
  else
    cat > "$dir/wp-config.php" <<CONF
<?php
// Gerado pelo dev.
define( 'DB_NAME', '$database' );
define( 'DB_USER', '$(config_get MYSQL_USER)' );
define( 'DB_PASSWORD', '$(config_get MYSQL_PASSWORD)' );
define( 'DB_HOST', '127.0.0.1:$MYSQL_PORT' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

$(wp_salts)

\$table_prefix = 'wp_';

define( 'WP_DEBUG', ! ( defined( 'WP_CLI' ) && WP_CLI ) );
define( 'WP_DEBUG_DISPLAY', true );
define( 'WP_DEBUG_LOG', '$DEV_LOG/$name-php.log' );

if ( ! defined( 'ABSPATH' ) ) define( 'ABSPATH', __DIR__ . '/' );
require_once ABSPATH . 'wp-settings.php';
CONF
  fi

  WP_ADMIN_USER="admin"
  WP_ADMIN_PASS="$(random_password)"
  WP_ADMIN_EMAIL="admin@$name.localhost"
  info "instalando o WordPress"
  wp "$dir" core install \
    --url="https://$name.localhost" \
    --title="$name" \
    --admin_user="$WP_ADMIN_USER" \
    --admin_password="$WP_ADMIN_PASS" \
    --admin_email="$WP_ADMIN_EMAIL" \
    --skip-email >/dev/null || die "o \`wp core install\` falhou"
  ok "WordPress instalado"
  announce_credentials "$WP_ADMIN_USER" "$WP_ADMIN_PASS"
}

wp_salts() {
  local output
  output="$(curl -s --max-time 10 https://api.wordpress.org/secret-key/1.1/salt/ || true)"
  if [[ "$output" == *"AUTH_KEY"* ]]; then printf '%s\n' "$output"; return; fi
  local key value
  for key in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY \
             AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
    value="$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%^&*()_+=-' </dev/urandom 2>/dev/null | head -c 64 || true)"
    printf "define( '%s', '%s' );\n" "$key" "$value"
  done
}

recipe_restore() {
  local dir="$1" name="$2" database="$3"
  wp_core_dir "$dir" >/dev/null && return 0
  info "o núcleo do WordPress não está aqui — baixando"
  recipe_install "$dir" "$name" "$database"
}

recipe_next_steps() {
  local dir="$1" name="$2"
  hint "entre como ${C_BOLD}${WP_ADMIN_USER:-admin}${C_RESET}   senha ${C_BOLD}${WP_ADMIN_PASS:-—}${C_RESET}"
  hint "painel em https://$name.localhost/wp-admin/"
  hint "perdeu a senha?  $DEV passwd"
}

DEFAULT_ADMIN="admin"

recipe_change_password() {
  local dir="$1" user="$2" password="$3"
  if wp "$dir" user get "$user" >/dev/null 2>&1; then
    wp "$dir" user update "$user" --user_pass="$password" >/dev/null
  else
    wp "$dir" user create "$user" "$user@${PROJECT_NAME}.localhost" \
      --role=administrator --user_pass="$password" >/dev/null
  fi
}

recipe_has_user() {
  wp "$1" user get "$2" --field=ID >/dev/null 2>&1
}

recipe_identity() { printf '%s\n' "$1"; }

recipe_gitignore() {
  cat <<'GITIGNORE'
# Escrito pelo dev na criação do projeto.
/*
!/.gitignore
!/dev.conf
!/dev.schedule
!/dev.workers
!/.mcp.json
!/.claude/
/.claude/settings.local.json
!/CLAUDE.md
/CLAUDE.local.md
/.claude/skills/impeccable/scripts/bin/
!/.specs/

*:Zone.Identifier
Thumbs.db
desktop.ini
.DS_Store

!/wp-content/
/wp-content/*
!/wp-content/plugins/
/wp-content/plugins/*
!/wp-content/themes/
/wp-content/themes/*
GITIGNORE
}

recipe_schedule() {
  local dir="${1:-$PWD}" core target="wp-cron.php"
  core="$(wp_core_dir "$dir" 2>/dev/null || true)"
  [[ -n "$core" && "$core" != "." ]] && target="$core/wp-cron.php"
  cat <<AGENDA
# Agenda deste projeto, lida pelo dev.
# Formato:  <intervalo em segundos>  <comando>
60 php $target
AGENDA
}

# ------------------------------------------------------------------- testes
# phpunit: testes de integração de um plugin ou tema com a biblioteca de testes
#          oficial do WordPress, num banco separado (<banco>_tests).
# e2e:     testes de ponta a ponta com o @playwright/test do projeto, logados
#          com um usuário temporário criado só para a execução.

recipe_test_suites() {
  printf '%s\n' \
    "phpunit|testes de integração de um plugin ou tema (biblioteca de testes do WordPress, banco ${PROJECT_DATABASE:-do projeto}_tests)" \
    "e2e|testes de ponta a ponta com o Playwright do projeto (@playwright/test)"
}

wp_installed_version() {
  local core
  core="$(wp_core_dir "$1")" || return 1
  grep -oP "^\\\$wp_version\s*=\s*'\K[^']+" "$1/${core#./}/wp-includes/version.php" 2>/dev/null || true
}

wp_tests_dir() { printf '%s\n' "$DEV_HOME/wordpress-tests/$PROJECT_NAME"; }

wp_tests_database() { printf '%s_tests\n' "$PROJECT_DATABASE"; }

# Um diretório com phpunit.xml ou playwright.config, relativo a quem chamou.
wp_test_target() {
  local candidate="$1"
  [[ -n "$candidate" ]] || return 1
  [[ "$candidate" == /* ]] || candidate="${TEST_CALLER_DIR:-$PROJECT_DIR}/$candidate"
  [[ -d "$candidate" ]] || return 1
  candidate="$(cd "$candidate" && pwd)"
  [[ -f "$candidate/phpunit.xml" || -f "$candidate/phpunit.xml.dist" \
     || -f "$candidate/playwright.config.ts" || -f "$candidate/playwright.config.js" ]] || return 1
  printf '%s\n' "$candidate"
}

recipe_test_ready() {
  case "$1" in
    phpunit)
      [[ -f "$(wp_tests_dir)/includes/functions.php" && -f "$(wp_tests_dir)/wp-tests-config.php" ]] \
        && grep -q "$(wp_installed_version "$PROJECT_DIR")" "$(wp_tests_dir)/.version" 2>/dev/null ;;
    e2e)
      [[ -x node_modules/.bin/playwright || -x "$PROJECT_DIR/node_modules/.bin/playwright" ]] ;;
  esac
}

recipe_test_init() {
  case "$1" in
    phpunit) wp_init_phpunit ;;
    e2e)
      [[ -x node_modules/.bin/playwright ]] \
        || die "o @playwright/test não está no projeto — instale com: $DEV exec npm install"
      browser_install_deps ;;
  esac
}

wp_init_phpunit() {
  [[ -n "$PROJECT_DATABASE" ]] || die "o projeto não declara banco no dev.conf"
  local version tarball dir core
  version="$(wp_installed_version "$PROJECT_DIR")"
  [[ -n "$version" ]] || die "não achei a versão do WordPress em wp-includes/version.php"
  core="$(wp_core_dir "$PROJECT_DIR")"
  dir="$(wp_tests_dir)"
  tarball="$(download "$(url_for wpdevelop "$version")" "$(cache_name wpdevelop "$version")")"
  rm -rf "$dir"
  mkdir -p "$dir"
  tar -xzf "$tarball" -C "$dir" --strip-components=3 --wildcards \
    '*/tests/phpunit/includes/*' '*/tests/phpunit/data/*' \
    || die "não consegui extrair a biblioteca de testes do WordPress $version"
  cat > "$dir/wp-tests-config.php" <<PHP
<?php
// Gerado pelo dev test. Banco separado: a instalação de teste o apaga e recria.
define( 'ABSPATH', '$PROJECT_DIR/${core#./}/' );
define( 'WP_DEFAULT_THEME', 'default' );
define( 'WP_DEBUG', true );
define( 'DB_NAME', '$(wp_tests_database)' );
define( 'DB_USER', '$(config_get MYSQL_USER)' );
define( 'DB_PASSWORD', '$(config_get MYSQL_PASSWORD)' );
define( 'DB_HOST', '127.0.0.1:$MYSQL_PORT' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );
\$table_prefix = 'wptests_';
define( 'WP_TESTS_DOMAIN', 'example.org' );
define( 'WP_TESTS_EMAIL', 'admin@example.org' );
define( 'WP_TESTS_TITLE', 'Test Blog' );
define( 'WP_PHP_BINARY', 'php' );
define( 'WPLANG', '' );
PHP
  chmod 600 "$dir/wp-tests-config.php"
  printf '%s\n' "$version" > "$dir/.version"
  create_database "$(wp_tests_database)"
  ok "biblioteca de testes do WordPress $version  banco $(wp_tests_database)"
}

recipe_test_run() {
  local suite="$1"; shift
  # O alvo é o primeiro argumento, se for um diretório de testes; senão, o
  # diretório de onde o comando foi chamado.
  local target=""
  if [[ $# -gt 0 ]] && target="$(wp_test_target "$1")"; then
    shift
  else
    target="$(wp_test_target "${TEST_CALLER_DIR:-}" || true)"
  fi
  case "$suite" in
    phpunit) wp_run_phpunit "$target" "$@" ;;
    e2e)     wp_run_e2e "${target:-$PROJECT_DIR}" "$@" ;;
  esac
}

wp_run_phpunit() {
  local target="$1"; shift
  if [[ -z "$target" ]]; then
    bad "diga qual plugin ou tema testar (o diretório com phpunit.xml):"
    hint "$DEV test phpunit wp-content/plugins/meu-plugin [argumentos do phpunit]"
    return 1
  fi
  cd "$target" || return 1
  local phpunit=vendor/bin/phpunit
  [[ -x "$phpunit" ]] || phpunit="$PROJECT_DIR/vendor/bin/phpunit"
  if [[ ! -x "$phpunit" ]]; then
    bad "o PHPUnit não está instalado em ${target#"$PROJECT_DIR"/}"
    hint "$DEV exec composer require --dev phpunit/phpunit yoast/phpunit-polyfills   (dentro do plugin)"
    return 1
  fi
  local polyfills=""
  [[ -d vendor/yoast/phpunit-polyfills ]] && polyfills="$PWD/vendor/yoast/phpunit-polyfills"
  WP_TESTS_DIR="$(wp_tests_dir)" WP_CORE_DIR="$PROJECT_DIR/$(wp_core_dir "$PROJECT_DIR")" \
    WP_TESTS_PHPUNIT_POLYFILLS_PATH="$polyfills" \
    "$phpunit" "$@"
}

WP_E2E_USER="devtest-e2e"

wp_e2e_cleanup() { recipe_test_user_remove "$PROJECT_DIR" "$WP_E2E_USER" >/dev/null 2>&1 || true; }

wp_run_e2e() {
  local target="$1"; shift
  cd "$target" || return 1
  [[ -x node_modules/.bin/playwright ]] \
    || die "o @playwright/test não está em ${target#"$PROJECT_DIR"/} — instale com: $DEV exec npm install"
  test_require_served
  playwright_chromium || return 1
  local password
  password="$(random_password)"
  if recipe_has_user "$PROJECT_DIR" "$WP_E2E_USER"; then
    die "já existe um usuário \"$WP_E2E_USER\" — o dev usa esse nome só durante o e2e"
  fi
  recipe_test_user_create "$PROJECT_DIR" "$WP_E2E_USER" "$password" 1 >/dev/null \
    || die "não consegui criar o usuário temporário do e2e"
  test_on_exit wp_e2e_cleanup
  info "usuário temporário $WP_E2E_USER criado para esta execução"
  WP_BASE_URL="$(site_url "$PROJECT_NAME")" WP_USERNAME="$WP_E2E_USER" WP_PASSWORD="$password" \
    PLAYWRIGHT_BROWSERS_PATH="$(playwright_browsers_path)" \
    node_modules/.bin/playwright test "$@"
}

# ---------------------------------------------------------- usuário de teste
recipe_test_user_create() {
  local dir="$1" user="$2" password="$3" admin="$4" role=subscriber
  [[ "$admin" == 1 ]] && role=administrator
  if wp "$dir" user get "$user" >/dev/null 2>&1; then
    wp "$dir" user update "$user" --user_pass="$password" --role="$role" >/dev/null || return 1
  else
    wp "$dir" user create "$user" "$user@${PROJECT_NAME}.localhost" \
      --role="$role" --user_pass="$password" >/dev/null || return 1
  fi
  if [[ "$role" == administrator ]]; then
    printf 'administrador\n'
  else
    printf 'assinante (subscriber)\n'
  fi
}

recipe_test_user_remove() {
  local dir="$1" user="$2"
  wp "$dir" user get "$user" >/dev/null 2>&1 || return 0
  wp "$dir" user delete "$user" --yes >/dev/null
}
