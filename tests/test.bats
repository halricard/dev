#!/usr/bin/env bats
# Testes do dev test: suítes por aplicação, execução e usuário de teste temporário.

load helper

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export DEV_HOME="$BATS_TEST_TMPDIR/sandbox"
  export DEV_CACHE="$BATS_TEST_TMPDIR/cache"
  export NO_COLOR=1
  unset DEV_YES
  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$HOME" "$DEV_HOME/etc" "$TEST_PROJECT"
  STUBS_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUBS_BIN"
  export PATH="$STUBS_BIN:$PATH"

  local php_dir="$DEV_HOME/runtime/php/8.5.11"
  mkdir -p "$php_dir/bin" "$php_dir/sbin"
  printf '#!/bin/sh\necho "PHP mock $*"\n' > "$php_dir/bin/php"
  chmod +x "$php_dir/bin/php"
  source "$ROOT/lib/common.sh"
  config_set DEFAULT_PHP "8.5.11"
}

# Um plugin de mentira, instalado no sandbox, com usuário de teste.
fake_app() {
  local dir="$DEV_HOME/plugins/installed/fakeapp"
  mkdir -p "$dir"
  cat > "$dir/recipe.sh" <<'RECIPE'
recipe_title() { printf 'Fake\n'; }
recipe_test_suites() { printf '%s\n' "unit|testes de mentira"; }
recipe_test_ready() { [[ -f "$PROJECT_DIR/.ready" ]]; }
recipe_test_init() { touch "$PROJECT_DIR/.ready"; printf 'init %s\n' "$1" >> "$PROJECT_DIR/calls"; }
recipe_test_run() { printf 'run %s\n' "$*" >> "$PROJECT_DIR/calls"; return "${FAKE_RC:-0}"; }
recipe_has_user() { [[ -f "$PROJECT_DIR/existing-user" ]]; }
recipe_test_user_create() { printf 'create %s %s\n' "$2" "$4" >> "$PROJECT_DIR/calls"; printf 'papel de mentira\n'; }
recipe_test_user_remove() { printf 'remove %s\n' "$2" >> "$PROJECT_DIR/calls"; }
RECIPE
}

@test "dev test fora de um projeto falha" {
  cd "$BATS_TEST_TMPDIR"
  run dev_cmd test
  [ "$status" -ne 0 ]
  [[ "$output" == *"não há dev.conf"* ]]
}

@test "dev test help mostra o uso sem exigir projeto" {
  cd "$BATS_TEST_TMPDIR"
  run dev_cmd test help
  [ "$status" -eq 0 ]
  [[ "$output" == *"test user --remove"* ]]
}

@test "dev test lista phpunit e behat no Moodle com o endereço de teste" {
  project_conf APP=moodle PHP=8.5.11
  cd "$TEST_PROJECT"
  run dev_cmd test
  [ "$status" -eq 0 ]
  [[ "$output" == *"phpunit"* ]]
  [[ "$output" == *"behat"*"https://test.test-site.localhost"* ]]
}

@test "dev test lista pest no Laravel com Pest e phpunit sem ele" {
  project_conf APP=laravel PHP=8.5.11
  cd "$TEST_PROJECT"
  run dev_cmd test
  [[ "$output" == *"phpunit"* ]]
  [[ "$output" != *"pest  "* ]]
  [[ "$output" == *"browser"* ]]
  mkdir -p vendor/bin && printf '#!/bin/sh\n' > vendor/bin/pest && chmod +x vendor/bin/pest
  run dev_cmd test
  [[ "$output" == *"pest"*"Pest"* ]]
  [[ "$output" != *"phpunit "* ]]
}

@test "dev test lista phpunit e e2e no WordPress" {
  project_conf APP=wordpress PHP=8.5.11 DATABASE=blog
  cd "$TEST_PROJECT"
  run dev_cmd test
  [ "$status" -eq 0 ]
  [[ "$output" == *"phpunit"*"blog_tests"* ]]
  [[ "$output" == *"e2e"*"Playwright"* ]]
}

@test "dev test com suíte desconhecida falha e mostra as conhecidas" {
  project_conf APP=moodle PHP=8.5.11
  cd "$TEST_PROJECT"
  run dev_cmd test cypress
  [ "$status" -ne 0 ]
  [[ "$output" == *"suíte desconhecida: cypress"* ]]
  [[ "$output" == *"behat"* ]]
}

@test "projeto sem aplicação roda o PHPUnit do projeto com os argumentos" {
  project_conf PHP=8.5.11
  mkdir -p "$TEST_PROJECT/vendor/bin"
  printf '#!/bin/sh\necho "phpunit chamado com: $*"\n' > "$TEST_PROJECT/vendor/bin/phpunit"
  chmod +x "$TEST_PROJECT/vendor/bin/phpunit"
  cd "$TEST_PROJECT"
  run dev_cmd test phpunit --filter=Foo
  [ "$status" -eq 0 ]
  [[ "$output" == *"phpunit chamado com: --filter=Foo"* ]]
  [[ "$output" == *"phpunit passou"* ]]
}

@test "dev test prepara a suíte só na primeira vez e repassa o código de saída" {
  fake_app
  project_conf APP=fakeapp PHP=8.5.11
  cd "$TEST_PROJECT"
  run dev_cmd test unit a b
  [ "$status" -eq 0 ]
  [[ "$output" == *"PREPARANDO  unit"* ]]
  FAKE_RC=3 run dev_cmd test unit
  [ "$status" -eq 3 ]
  [[ "$output" != *"PREPARANDO"* ]]
  [[ "$output" == *"terminou com código 3"* ]]
  [ "$(grep -c '^init unit' calls)" -eq 1 ]
  grep -q '^run unit a b' calls
}

@test "dev test user cria a conta temporária, marca e remove" {
  fake_app
  project_conf APP=fakeapp PHP=8.5.11
  cd "$TEST_PROJECT"
  run dev_cmd test user
  [ "$status" -eq 0 ]
  [[ "$output" == *"login"*"devtest"* ]]
  [[ "$output" == *"senha"*"Dev"* ]]
  [[ "$output" == *"papel de mentira"* ]]
  grep -q '^create devtest 1' calls
  [ -f "$DEV_HOME/test-users/test-site" ]

  run dev_cmd test user --no-admin
  grep -q '^create devtest 0' calls

  run dev_cmd test user --remove
  [ "$status" -eq 0 ]
  grep -q '^remove devtest' calls
  [ ! -f "$DEV_HOME/test-users/test-site" ]
}

@test "dev test user não toma conta de um usuário que o dev não criou" {
  fake_app
  project_conf APP=fakeapp PHP=8.5.11
  touch "$TEST_PROJECT/existing-user"
  cd "$TEST_PROJECT"
  run dev_cmd test user
  [ "$status" -ne 0 ]
  [[ "$output" == *"não foi criado pelo dev"* ]]
  [ ! -f "$TEST_PROJECT/calls" ]
}

@test "dev test user recusa aplicação sem contas" {
  project_conf PHP=8.5.11
  cd "$TEST_PROJECT"
  run dev_cmd test user
  [ "$status" -ne 0 ]
  [[ "$output" == *"não tem contas de usuário"* ]]
}

@test "dev down apaga o usuário de teste do site" {
  fake_app
  project_conf APP=fakeapp PHP=8.5.11
  mkdir -p "$DEV_HOME/sites" "$DEV_HOME/test-users"
  printf '%s\n' "$TEST_PROJECT" > "$DEV_HOME/sites/test-site"
  date +%s > "$DEV_HOME/test-users/test-site"
  run libraries '
    source "$DEV_ROOT/lib/updown.sh"
    take_down() { rm -f "$DEV_SITES/$1"; }
    cmd_down test-site
  '
  [ "$status" -eq 0 ]
  grep -q '^remove devtest' "$TEST_PROJECT/calls"
  [ ! -f "$DEV_HOME/test-users/test-site" ]
}

@test "o bloco de testes do Moodle entra antes do setup.php e é reescrito sem duplicar" {
  mkdir -p "$TEST_PROJECT/app"
  cat > "$TEST_PROJECT/app/config.php" <<'PHP'
<?php
// Gerado pelo dev.
$CFG->wwwroot = 'https://test-site.localhost';

require_once(__DIR__ . '/lib/setup.php');
PHP
  run libraries '
    source "$DEV_ROOT/lib/browser.sh"
    load_recipe moodle
    moodle_write_test_config "'"$TEST_PROJECT"'" test-site
    moodle_write_test_config "'"$TEST_PROJECT"'" test-site
  '
  [ "$status" -eq 0 ]
  local config="$TEST_PROJECT/app/config.php"
  [ "$(grep -c '>>> dev test' "$config")" -eq 1 ]
  grep -q "behat_wwwroot    = 'https://test.test-site.localhost'" "$config"
  grep -q "phpunit_prefix   = 'phpu_'" "$config"
  grep -q "'wd_host' => 'http://127.0.0.1:$CHROMEDRIVER_PORT'" "$config"
  grep -q "'--headless=new'" "$config"
  local block_line setup_line
  block_line="$(grep -n '<<< dev test' "$config" | cut -d: -f1)"
  setup_line="$(grep -n "lib/setup.php" "$config" | cut -d: -f1)"
  [ "$block_line" -lt "$setup_line" ]
  [ -d "$TEST_PROJECT/data-behat" ]
  [ -d "$TEST_PROJECT/data-phpunit" ]
}

@test "config.php do Moodle desconhecido fica intocado e o bloco vai para a tela" {
  mkdir -p "$TEST_PROJECT/app"
  printf '<?php\n// meu config\n' > "$TEST_PROJECT/app/config.php"
  run libraries '
    source "$DEV_ROOT/lib/browser.sh"
    load_recipe moodle
    moodle_write_test_config "'"$TEST_PROJECT"'" test-site
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"behat_wwwroot"* ]]
  [ "$(cat "$TEST_PROJECT/app/config.php")" = "$(printf '<?php\n// meu config')" ]
}

@test "WordPress acha o plugin a testar e a versão do núcleo" {
  mkdir -p "$TEST_PROJECT/wp-includes" "$TEST_PROJECT/wp-content/plugins/meu"
  touch "$TEST_PROJECT/wp-settings.php" "$TEST_PROJECT/wp-content/plugins/meu/phpunit.xml.dist"
  printf "<?php\n\$wp_version = '6.8.3';\n" > "$TEST_PROJECT/wp-includes/version.php"
  run libraries '
    load_recipe wordpress
    PROJECT_DIR="'"$TEST_PROJECT"'"; TEST_CALLER_DIR="'"$TEST_PROJECT"'"
    wp_installed_version "$PROJECT_DIR"
    wp_test_target wp-content/plugins/meu
    wp_test_target --filter=x || echo "não é alvo"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"6.8.3"* ]]
  [[ "$output" == *"$TEST_PROJECT/wp-content/plugins/meu"* ]]
  [[ "$output" == *"não é alvo"* ]]
}

@test "dev help lista os comandos de teste" {
  run dev_cmd help
  [[ "$output" == *"test user"* ]]
  [[ "$output" == *"browser install"* ]]
}
