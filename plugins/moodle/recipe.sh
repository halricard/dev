#!/usr/bin/env bash
# Moodle: scaffolding com layout app/ e data/, supressão de deprecations e cron.

recipe_title() { printf 'Moodle\n'; }

recipe_php() { printf '8.4\n'; }

recipe_docroot() {
  [[ -f "$1/app/public/index.php" ]] && { printf 'app/public\n'; return; }
  printf 'app\n'
}

branch_for_moodle() {
  printf '%s\n' "${MOODLE_BRANCH:-502}"
}

recipe_install() {
  local dir="$1" name="$2" database="$3" branch tarball
  local version="${MOODLE_VERSION:-}"
  if [[ -n "$version" ]]; then
    tarball="$(download "$(url_for moodle "$version")" "$(cache_name moodle "$version")")"
  else
    branch="$(branch_for_moodle)"
    tarball="$(download_fresh "$(url_for moodle "latest-$branch")" "$(cache_name moodle "latest-$branch")")"
  fi

  mkdir -p "$dir/app" "$dir/data"
  chmod 0750 "$dir/data"
  info "extraindo Moodle ${version:-(branch ${branch:-502})}"
  tar -xf "$tarball" -C "$dir/app" --strip-components=1 --skip-old-files

  local root="$dir/app"
  if [[ -f "$root/config.php" ]]; then
    info "config.php já existe — mantido como está"
  else
    cat > "$root/config.php" <<CONF
<?php
// Gerado pelo dev.
error_reporting(E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED);

unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();

\$CFG->dbtype    = 'mysqli';
\$CFG->dblibrary = 'native';
\$CFG->dbhost    = '127.0.0.1';
\$CFG->dbname    = '$database';
\$CFG->dbuser    = '$(config_get MYSQL_USER)';
\$CFG->dbpass    = '$(config_get MYSQL_PASSWORD)';
\$CFG->prefix    = 'mdl_';
\$CFG->dboptions = array(
    'dbpersist' => 0,
    'dbport'    => $MYSQL_PORT,
    'dbsocket'  => '',
    'dbcollation' => 'utf8mb4_unicode_ci',
);

\$CFG->wwwroot   = 'https://$name.localhost';
\$CFG->dataroot  = '$dir/data';
\$CFG->admin     = 'admin';
\$CFG->directorypermissions = 0777;

\$CFG->debug = (E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED);
\$CFG->debugdisplay = 1;

\$CFG->smtphosts = '127.0.0.1:$SMTP_PORT';
\$CFG->smtpsecure = '';

require_once(__DIR__ . '/lib/setup.php');
CONF
  fi

  local php; php="$(php_bin "${PROJECT_PHP:-$(config_get DEFAULT_PHP)}")"
  local php_cli=("$php" -d error_reporting="E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED")

  ( cd "$root" && "${php_cli[@]}" "$DEV_RUNTIME/composer/composer.phar" install \
      --no-dev --classmap-authoritative --no-interaction >/dev/null 2>&1 ) || true

  MOODLE_ADMIN_USER="admin"
  MOODLE_ADMIN_PASS="$(random_password)"
  MOODLE_ADMIN_EMAIL="admin@$name.localhost"

  with_progress "instalando o Moodle" \
    env -C "$root" "${php_cli[@]}" admin/cli/install_database.php \
      --agree-license \
      --adminuser="$MOODLE_ADMIN_USER" \
      --adminpass="$MOODLE_ADMIN_PASS" \
      --adminemail="$MOODLE_ADMIN_EMAIL" \
      --fullname="$name" \
      --shortname="$name" \
      --supportemail="$MOODLE_ADMIN_EMAIL" \
    || die "o instalador do Moodle não terminou"

  ok "Moodle instalado"
  announce_credentials "$MOODLE_ADMIN_USER" "$MOODLE_ADMIN_PASS"
}

recipe_restore() {
  local dir="$1" name="$2" database="$3"
  local root="" c
  for c in app app/public . public html; do
    [[ -f "$dir/$c/version.php" ]] && { root="$dir/$c"; break; }
  done
  [[ -n "$root" ]] || {
    info "o Moodle não está aqui — baixando"
    recipe_install "$dir" "$name" "$database"
    return
  }
  [[ "$(basename "$root")" == public ]] && root="$(dirname "$root")"
  [[ -f "$root/vendor/autoload.php" || ! -f "$root/composer.json" ]] && return 0
  info "repondo o autoloader"
  ( cd "$root" && "$(php_bin "${PROJECT_PHP:-$(config_get DEFAULT_PHP)}")" "$DEV_RUNTIME/composer/composer.phar" \
      install --no-dev --classmap-authoritative --no-interaction >/dev/null 2>&1 ) || true
}

recipe_next_steps() {
  local dir="$1" name="$2"
  hint "entre como ${C_BOLD}${MOODLE_ADMIN_USER:-admin}${C_RESET}   senha ${C_BOLD}${MOODLE_ADMIN_PASS:-—}${C_RESET}"
  hint "a instalação saiu em inglês; o idioma se troca em Site administration"
  hint "perdeu a senha?  $DEV passwd"
}

DEFAULT_ADMIN="admin"

recipe_change_password() {
  local dir="$1" user="$2" password="$3"
  local root="$dir/app"
  [[ -d "$root" ]] || root="$dir"
  if ! recipe_has_user "$dir" "$user"; then
    bad "o usuário \"$user\" não existe mais neste Moodle"
    return 1
  fi
  ( cd "$root" && "$(php_bin "${PROJECT_PHP:-$(config_get DEFAULT_PHP)}")" \
      -d error_reporting="E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED" \
      admin/cli/reset_password.php --username="$user" --password="$password" >/dev/null )
}

recipe_has_user() {
  local dir="$1" user="$2"
  local prefix="mdl_"
  mysql_cli -N -B "$PROJECT_DATABASE" \
    -e "SELECT 1 FROM ${prefix}user WHERE username='$user' AND deleted=0 LIMIT 1;" \
    2>/dev/null | grep -q 1
}

recipe_gitignore() {
  cat <<'GITIGNORE'
# Escrito pelo dev na criação do projeto Moodle.
/*
!/.gitignore
!/dev.conf
!/dev.schedule
!/dev.workers

*:Zone.Identifier
Thumbs.db
desktop.ini
.DS_Store

!/app/
/app/*
!/app/public/
/app/public/*
!/app/public/mod/
/app/public/mod/*
!/app/public/local/
/app/public/local/*
!/app/public/blocks/
/app/public/blocks/*
!/app/public/theme/
/app/public/theme/*
GITIGNORE
}

recipe_schedule() {
  cat <<'AGENDA'
# Agenda do Moodle, lida pelo dev.
# Formato:  <intervalo em segundos>  <comando>
60 php app/admin/cli/cron.php --keep-alive=0
AGENDA
}
