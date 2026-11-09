#!/usr/bin/env bash
# Moodle: scaffolding com layout app/ e data/, supressão de deprecations e cron.

recipe_title() { printf 'Moodle\n'; }

recipe_php() { printf '8.4\n'; }

recipe_docroot() {
  [[ -f "$1/app/public/index.php" ]] && { printf 'app/public\n'; return; }
  printf 'app\n'
}

# Versão do Moodle instalado, lida do $release de version.php (sem rodar PHP).
recipe_version() {
  local file
  for file in "$1/app/version.php" "$1/app/public/version.php"; do
    [[ -f "$file" ]] || continue
    sed -n "/^\$release *= *'/{s/^\$release *= *'\([^ ']*\).*/\1/p;q;}" "$file"
    return 0
  done
  return 1
}

branch_for_moodle() {
  printf '%s\n' "${MOODLE_BRANCH:-503}"
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
  info "extraindo Moodle ${version:-(branch ${branch:-503})}"
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

  local php_series="${PROJECT_PHP:-$(recipe_php 2>/dev/null || config_get DEFAULT_PHP || true)}"
  local php_ver; php_ver="$(php_version "$php_series")"
  if ! declare -F write_php_ini >/dev/null && [[ -f "$DEV_ROOT/lib/config.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/config.sh"
  fi
  declare -F write_php_ini >/dev/null && write_php_ini "$php_ver" 2>/dev/null || true

  local php; php="$(php_bin "$php_ver")"
  local php_ini="$DEV_ETC/php/$php_ver/php.ini"
  local php_cli=(
    env PHPRC="$DEV_ETC/php/$php_ver" PHP_INI_SCAN_DIR="$DEV_ETC/php/$php_ver/conf.d"
    "$php" -c "$php_ini" -d max_input_vars=5000 -d error_reporting="E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED"
  )

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
  local php_series="${PROJECT_PHP:-$(recipe_php 2>/dev/null || config_get DEFAULT_PHP || true)}"
  local php_ver; php_ver="$(php_version "$php_series")"
  local php_ini="$DEV_ETC/php/$php_ver/php.ini"
  ( cd "$root" && env PHPRC="$DEV_ETC/php/$php_ver" PHP_INI_SCAN_DIR="$DEV_ETC/php/$php_ver/conf.d" \
      "$(php_bin "$php_ver")" -c "$php_ini" -d max_input_vars=5000 "$DEV_RUNTIME/composer/composer.phar" \
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
  local php_series="${PROJECT_PHP:-$(recipe_php 2>/dev/null || config_get DEFAULT_PHP || true)}"
  local php_ver; php_ver="$(php_version "$php_series")"
  local php_ini="$DEV_ETC/php/$php_ver/php.ini"
  ( cd "$root" && env PHPRC="$DEV_ETC/php/$php_ver" PHP_INI_SCAN_DIR="$DEV_ETC/php/$php_ver/conf.d" \
      "$(php_bin "$php_ver")" -c "$php_ini" \
      -d max_input_vars=5000 \
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

# ------------------------------------------------------------------- testes
# PHPUnit e Behat, as duas suítes oficiais do Moodle. Cada uma usa tabelas
# próprias no mesmo banco (prefixos phpu_ e bht_) e um dataroot próprio ao lado
# de data/. O Behat abre o site em https://test.<projeto>.localhost pelo Chrome
# do dev.

moodle_root() {
  if [[ -d "$1/app" ]]; then printf '%s\n' "$1/app"; else printf '%s\n' "$1"; fi
}

# Moodle 5.1+ guarda as ferramentas em public/; as versões anteriores, na raiz.
moodle_tool() {
  local root candidate
  root="$(moodle_root "$1")"
  for candidate in "public/admin/tool/$2" "admin/tool/$2"; do
    [[ -d "$root/$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

MOODLE_TEST_BEGIN="// >>> dev test"
MOODLE_TEST_END="// <<< dev test"

moodle_test_config_block() {
  local dir="$1" name="$2" arg args=""
  while IFS= read -r arg; do
    args+="'$arg', "
  done < <(chrome_test_args)
  cat <<PHP
$MOODLE_TEST_BEGIN — escrito pelo dev test e reescrito a cada preparo; não edite
\$CFG->phpunit_prefix   = 'phpu_';
\$CFG->phpunit_dataroot = '$dir/data-phpunit';
\$CFG->behat_prefix     = 'bht_';
\$CFG->behat_dataroot   = '$dir/data-behat';
\$CFG->behat_wwwroot    = 'https://$(test_host "$name")';
\$CFG->behat_profiles   = [
    'default' => [
        'browser' => 'chrome',
        'wd_host' => '$(chromedriver_url)',
        'capabilities' => [
            'extra_capabilities' => [
                'goog:chromeOptions' => [
                    'binary' => '$(chrome_bin)',
                    'args' => [${args%, }],
                ],
            ],
        ],
    ],
];
$MOODLE_TEST_END
PHP
}

# Põe o bloco de testes no config.php, logo antes do require do setup.php.
# Um config.php que o dev não reconhece fica intocado; o bloco vai para a tela.
moodle_write_test_config() {
  local dir="$1" name="$2" config block tmp
  config="$(moodle_root "$dir")/config.php"
  block="$(moodle_test_config_block "$dir" "$name")"
  if [[ ! -f "$config" ]] || ! grep -q "^require_once(__DIR__ . '/lib/setup.php');" "$config"; then
    bad "não reconheci o config.php — acrescente antes do require_once do setup.php:"
    printf '%s\n' "$block" | sed 's/^/     /'
    return 1
  fi
  tmp="$(mktemp)"
  awk -v begin="$MOODLE_TEST_BEGIN" -v end="$MOODLE_TEST_END" -v block="$block" '
    index($0, begin) == 1 { skip = 1; next }
    skip && index($0, end) == 1 { skip = 0; next }
    skip { next }
    /^require_once\(__DIR__ \. .\/lib\/setup\.php.\);/ { print block; print "" }
    { print }
  ' "$config" > "$tmp"
  cat "$tmp" > "$config"
  rm -f "$tmp"
  mkdir -p "$dir/data-phpunit" "$dir/data-behat"
  chmod 0750 "$dir/data-phpunit" "$dir/data-behat"
}

# As suítes precisam das dependências de desenvolvimento do Composer, que a
# criação do projeto deixa de fora. O composer.phar do dev fica ao lado para o
# init do Moodle não baixar outro da internet.
moodle_test_dependencies() {
  local root
  root="$(moodle_root "$1")"
  [[ -e "$root/composer.phar" ]] || ln -s "$DEV_RUNTIME/composer/composer.phar" "$root/composer.phar"
  [[ -x "$root/vendor/bin/phpunit" && -x "$root/vendor/bin/behat" ]] && return 0
  with_progress "instalando as dependências de teste (composer install)" \
    env -C "$root" COMPOSER_NO_INTERACTION=1 composer install --no-interaction
}

recipe_test_suites() {
  printf '%s\n' \
    "phpunit|testes unitários e de integração (PHPUnit; tabelas phpu_, dados em data-phpunit/)" \
    "behat|testes de aceitação no navegador (Behat + Chrome em https://$(test_host "$PROJECT_NAME"))"
}

recipe_test_ready() {
  local suite="$1" root tool
  root="$(moodle_root "$PROJECT_DIR")"
  grep -q "$MOODLE_TEST_BEGIN" "$root/config.php" 2>/dev/null || return 1
  tool="$(moodle_tool "$PROJECT_DIR" "$suite")" || return 1
  ( cd "$root" && php "$tool/cli/util.php" --diag >/dev/null 2>&1 )
}

recipe_test_init() {
  local suite="$1" root tool
  root="$(moodle_root "$PROJECT_DIR")"
  tool="$(moodle_tool "$PROJECT_DIR" "$suite")" || die "esta versão do Moodle não traz admin/tool/$suite"
  moodle_write_test_config "$PROJECT_DIR" "$PROJECT_NAME" || return 1
  moodle_test_dependencies "$PROJECT_DIR" || return 1
  if [[ "$suite" == behat ]]; then
    test_require_served
  fi
  with_progress "preparando o $suite do Moodle (instala as tabelas de teste)" \
    env -C "$root" php "$tool/cli/init.php" --disable-composer
}

recipe_test_run() {
  local suite="$1"; shift
  local root
  root="$(moodle_root "$PROJECT_DIR")"
  cd "$root" || return 1
  case "$suite" in
    phpunit)
      vendor/bin/phpunit "$@" ;;
    behat)
      test_require_served
      test_browser
      vendor/bin/behat --config "$PROJECT_DIR/data-behat/behatrun/behat/behat.yml" "$@" ;;
  esac
}

# ---------------------------------------------------------- usuário de teste
moodle_cli_php() {
  local dir="$1" script="$2"; shift 2
  local root file
  root="$(moodle_root "$dir")"
  file="$(mktemp --suffix=.php -p "${DEV_TMP:-/tmp}")"
  printf '%s\n' "$script" > "$file"
  ( cd "$root" && php -d error_reporting="E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED" \
      "$file" "$root/config.php" "$@" )
  local rc=$?
  rm -f "$file"
  return "$rc"
}

recipe_test_user_create() {
  local dir="$1" user="$2" password="$3" admin="$4" output
  output="$(moodle_cli_php "$dir" '<?php
define("CLI_SCRIPT", true);
require($argv[1]);
require_once($CFG->dirroot . "/user/lib.php");
[$username, $password, $admin] = [$argv[2], $argv[3], $argv[4] === "1"];
$user = $DB->get_record("user", ["username" => $username, "mnethostid" => $CFG->mnet_localhost_id, "deleted" => 0]);
if (!$user) {
    $id = user_create_user((object) [
        "username" => $username, "password" => $password, "auth" => "manual",
        "firstname" => "Dev", "lastname" => "Teste", "confirmed" => 1, "policyagreed" => 1,
        "email" => $username . "@" . parse_url($CFG->wwwroot, PHP_URL_HOST),
        "mnethostid" => $CFG->mnet_localhost_id,
    ], true, false);
    $user = $DB->get_record("user", ["id" => $id]);
} else {
    update_internal_user_password($user, $password);
    $DB->set_field("user", "suspended", 0, ["id" => $user->id]);
}
$admins = array_diff(array_filter(explode(",", $CFG->siteadmins)), [$user->id]);
if ($admin) {
    $admins[] = $user->id;
}
set_config("siteadmins", implode(",", $admins));
echo "ok\n";
' "$user" "$password" "$admin" 2>&1)" || true
  [[ "$output" == *ok* ]] || { printf '%s\n' "$output" >&2; return 1; }
  if [[ "$admin" == 1 ]]; then
    printf 'administrador do site\n'
  else
    printf 'usuário autenticado, sem papel em curso\n'
  fi
}

recipe_test_user_remove() {
  local dir="$1" user="$2" output
  output="$(moodle_cli_php "$dir" '<?php
define("CLI_SCRIPT", true);
require($argv[1]);
$user = $DB->get_record("user", ["username" => $argv[2], "mnethostid" => $CFG->mnet_localhost_id, "deleted" => 0]);
if ($user) {
    set_config("siteadmins", implode(",", array_diff(explode(",", $CFG->siteadmins), [$user->id])));
    delete_user($user);
}
echo "ok\n";
' "$user" 2>&1)" || true
  [[ "$output" == *ok* ]]
}
