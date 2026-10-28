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
