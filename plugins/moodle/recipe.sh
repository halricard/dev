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

# ------------------------------------------------------------ versão fixada
# O dev.conf guarda MOODLE_VERSION e, para quem não está numa release,
# MOODLE_COMMIT: o commit do github.com/moodle/moodle com o mesmo código.

MOODLE_GITHUB_API="https://api.github.com/repos/moodle/moodle"
MOODLE_GITHUB_RAW="https://raw.githubusercontent.com/moodle/moodle"

recipe_pin_key() { printf 'MOODLE_VERSION\n'; }

# O version.php do núcleo, relativo a app/: na raiz até o 5.0, em public/ desde o 5.1.
moodle_version_path() {
  local root candidate
  root="$(moodle_root "$1")"
  for candidate in version.php public/version.php; do
    [[ -f "$root/$candidate" && -f "$root/${candidate%version.php}lib/setup.php" ]] \
      && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

# Um campo do version.php: version (2026100501.01), release ('5.3.1+ (Build: …)') ou branch ('503').
moodle_field() {
  grep -oP "^\\\$$2\s*=\s*'?\K[^';]*[^';\s]" "$1" 2>/dev/null | head -1 || true
}

# Os commits que mexeram no version.php da ref, entre duas datas, do mais novo
# ao mais antigo. Saída: 0 ok · 1 sem rede · 2 limite de consultas · 3 ref inexistente.
moodle_commits() {
  local ref="$1" path="$2" since="$3" until="$4" body code
  body="$(mktemp -p "$DEV_TMP")"
  code="$(curl -sS -L --max-time 30 -H 'Accept: application/vnd.github+json' -o "$body" -w '%{http_code}' \
    "$MOODLE_GITHUB_API/commits?sha=$ref&path=$path&since=$since&until=$until&per_page=100" 2>/dev/null || echo 000)"
  case "$code" in
    200)         json_array_field sha < "$body"; rm -f "$body"; return 0 ;;
    403|429)     rm -f "$body"; return 2 ;;
    404|409|422) rm -f "$body"; return 3 ;;
    *)           rm -f "$body"; return 1 ;;
  esac
}

# O commit cujo version.php tem exatamente o version e o release instalados.
# Cada build semanal sobe o version, então só um commit casa com os dois. A
# busca fica nas semanas em torno da data do build, numa consulta só à API.
moodle_find_commit() {
  local path="$1" version="$2" release="$3" branch="$4"
  local build since until ref sha list file rc=0
  build="$(grep -oP 'Build: \K[0-9]{8}' <<<"$release" || true)"
  [[ -n "$build" ]] || { bad "o release \"$release\" não traz a data do build" >&2; return 1; }
  since="$(date -u -d "$build -21 days" +%Y-%m-%dT00:00:00Z)"
  until="$(date -u -d "$build +8 days" +%Y-%m-%dT00:00:00Z)"
  list="$(mktemp -p "$DEV_TMP")"
  file="$(mktemp -p "$DEV_TMP")"
  # A branch estável primeiro; a versão em desenvolvimento só existe na main.
  for ref in "MOODLE_${branch}_STABLE" main; do
    rc=0
    moodle_commits "$ref" "$path" "$since" "$until" > "$list" || rc=$?
    (( rc == 3 )) && continue
    (( rc == 0 )) || break
    while IFS= read -r sha; do
      [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || continue
      curl -fsSL --max-time 30 -o "$file" "$MOODLE_GITHUB_RAW/$sha/$path" 2>/dev/null || continue
      if [[ "$(moodle_field "$file" version)" == "$version" && "$(moodle_field "$file" release)" == "$release" ]]; then
        rm -f "$list" "$file"
        printf '%s\n' "$sha"
        return 0
      fi
    done < "$list"
    break
  done
  rm -f "$list" "$file"
  case "$rc" in
    2) bad "o GitHub recusou a consulta: limite de 60 por hora sem login — tente de novo mais tarde" >&2 ;;
    1) bad "não consegui consultar o GitHub (sem rede?)" >&2 ;;
  esac
  return 1
}

# Imprime as chaves do dev.conf para a versão instalada em <dir>.
recipe_pin() {
  local dir="$1" root path version release branch short commit
  root="$(moodle_root "$dir")"
  path="$(moodle_version_path "$dir")" || {
    bad "não achei o núcleo do Moodle em ${root#"$dir"/}/ (version.php)" >&2
    return 1
  }
  release="$(moodle_field "$root/$path" release)"
  version="$(moodle_field "$root/$path" version)"
  branch="$(moodle_field "$root/$path" branch)"
  short="${release%% *}"
  [[ -n "$short" && -n "$version" ]] || { bad "não consegui ler a versão em $root/$path" >&2; return 1; }

  if moodle_is_release "$short"; then
    printf 'MOODLE_VERSION=%s\nMOODLE_COMMIT=\n' "$short"
    return 0
  fi

  [[ -n "$branch" ]] || { bad "o version.php não informa a branch do Moodle" >&2; return 1; }
  info "Moodle $release é uma build fora de release — procurando o commit no GitHub" >&2
  commit="$(moodle_find_commit "$path" "$version" "$release" "$branch")" || {
    bad "não achei no GitHub o commit do Moodle $release (version $version)" >&2
    hint "um núcleo com alterações locais não tem commit igual; fixe uma release, ex: MOODLE_VERSION=\"${short%%[!0-9.]*}\"" >&2
    return 1
  }
  printf 'MOODLE_VERSION=%s\nMOODLE_COMMIT=%s\n' "$short" "$commit"
}

branch_for_moodle() {
  printf '%s\n' "${MOODLE_BRANCH:-503}"
}

# Release é o número sem sufixo (5.3, 5.3.1): o pacote dela nunca muda. Build
# semanal (5.3.1+) e versão em desenvolvimento (5.4dev) só se reproduzem pelo
# commit do git, em MOODLE_COMMIT.
moodle_is_release() { [[ "$1" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; }

# O pacote do Moodle: o commit fixado, a release fixada ou, sem nada no
# dev.conf, a build mais recente da branch padrão.
moodle_tarball() {
  local version="${MOODLE_VERSION:-}" commit="${MOODLE_COMMIT:-}" branch
  if [[ -n "$commit" ]]; then
    [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die "MOODLE_COMMIT no dev.conf não é um commit do git: $commit"
    download "$(url_for moodlegit "$commit")" "$(cache_name moodlegit "$commit")"
  elif [[ -n "$version" ]]; then
    moodle_is_release "$version" || die "MOODLE_VERSION=\"$version\" não é uma release e o dev.conf não traz o MOODLE_COMMIT dela
     rode $DEV pin onde este Moodle está instalado, ou fixe uma release (ex: 5.3.1)"
    download "$(url_for moodle "$version")" "$(cache_name moodle "$version")"
  else
    branch="$(branch_for_moodle)"
    download_fresh "$(url_for moodle "latest-$branch")" "$(cache_name moodle "latest-$branch")"
  fi
}

recipe_install() {
  local dir="$1" name="$2" database="$3" tarball
  # O motivo já foi dito por moodle_tarball; o dev para aqui, como no die.
  tarball="$(moodle_tarball)" || exit 1

  mkdir -p "$dir/app" "$dir/data"
  chmod 0750 "$dir/data"
  if [[ -n "${MOODLE_COMMIT:-}" ]]; then
    info "extraindo Moodle ${MOODLE_VERSION:-} (commit ${MOODLE_COMMIT:0:12})"
  else
    info "extraindo Moodle ${MOODLE_VERSION:-(branch $(branch_for_moodle))}"
  fi
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
