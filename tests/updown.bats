#!/usr/bin/env bats
# Testes do gerenciamento de projetos e comandos up/down/init/destroy/sites.

load helper

@test "detect_docroot identifica caminhos padrão" {
  libraries '
    source "$DEV_ROOT/lib/project.sh"
    test_dir="$(scratch)"
    mkdir -p "$test_dir/public"
    touch "$test_dir/public/index.php"
    [ "$(detect_docroot "$test_dir")" = "public" ]

    rm -rf "$test_dir"
    test_dir="$(scratch)"
    mkdir -p "$test_dir/web"
    touch "$test_dir/web/index.php"
    [ "$(detect_docroot "$test_dir")" = "web" ]

    rm -rf "$test_dir"
    test_dir="$(scratch)"
    mkdir -p "$test_dir"
    touch "$test_dir/index.php"
    [ "$(detect_docroot "$test_dir")" = "." ]
    rm -rf "$test_dir"
  '
}

@test "write_project_conf gera dev.conf legível por load_project" {
  libraries '
    source "$DEV_ROOT/lib/project.sh"
    site_dir="$(scratch)"
    write_project_conf "$site_dir" "meusite" "" "public" "" "8.5"
    [ -f "$site_dir/dev.conf" ]

    load_project "$site_dir"
    [ "$PROJECT_NAME" = "meusite" ]
    [ "$PROJECT_APP" = "" ]
    [ "$PROJECT_DOCROOT" = "public" ]
    [ "$PROJECT_PHP" = "8.5" ]
    rm -rf "$site_dir"
  '
}

@test "cmd_init cria dev.conf em diretório de projeto existente e recusa se já existir" {
  mkdir -p "$TEST_PROJECT/public"
  echo "<?php echo 'oi';" > "$TEST_PROJECT/public/index.php"

  run in_project '
    source "$DEV_ROOT/lib/project.sh"
    cmd_init
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"dev.conf escrito com sucesso"* ]]
  [ -f "$TEST_PROJECT/dev.conf" ]

  # dev init repetido deve falhar
  run in_project '
    source "$DEV_ROOT/lib/project.sh"
    cmd_init
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"já existe um dev.conf aqui"* ]]
}

@test "cmd_up marca projeto como UP e chama bring_up" {
  project_conf APP="" PHP="8.5" DOCROOT="." DATABASE=""

  IGNORE="services.sh config.sh schedule.sh" run in_project '
    source "$DEV_ROOT/lib/updown.sh"
    cmd_start() { :; }
    start_site_tasks() { echo 0; }
    bring_up() {
      [[ -f "$DEV_UP/$PROJECT_NAME" ]] && echo "marcador antes de ligar"
    }
    cmd_up
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"marcador antes de ligar"* ]]
  [[ "$output" == *"UP  test-site"* ]]
}

@test "cmd_sites lista os projetos registrados" {
  mkdir -p "$DEV_HOME/sites"
  printf '%s\n' "$TEST_PROJECT" > "$DEV_HOME/sites/meu-site"

  run libraries '
    source "$DEV_ROOT/lib/project.sh"
    cmd_sites
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"meu-site"* ]]
  [[ "$output" == *"https://meu-site.localhost"* ]]
}

@test "cmd_down desliga projeto e remove do ar" {
  mkdir -p "$DEV_HOME/sites" "$DEV_HOME/up"
  printf '%s\n' "$TEST_PROJECT" > "$DEV_HOME/sites/site-down"
  touch "$DEV_HOME/up/site-down"

  run libraries '
    source "$DEV_ROOT/lib/updown.sh"
    take_down() {
      rm -f "$DEV_SITES/$1" "$DEV_UP/$1"
    }
    cmd_down site-down
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"DOWN  site-down"* ]]
  [[ "$output" == *"fora do ar"* ]]
  [ ! -f "$DEV_HOME/sites/site-down" ]
  [ ! -f "$DEV_HOME/up/site-down" ]
}

@test "cmd_destroy remove vhost, banco, snapshots e arquivos com confirmação" {
  local dir="$TEST_PROJECT/projeto-destroy"
  mkdir -p "$dir" "$DEV_HOME/sites"
  printf 'PROJECT="projeto-destroy"\nAPP=""\nPHP="8.5"\nDOCROOT="."\nDATABASE="destroy_db"\n' > "$dir/dev.conf"
  printf '%s\n' "$dir" > "$DEV_HOME/sites/projeto-destroy"

  IGNORE="services.sh" run in_project '
    source "$DEV_ROOT/lib/project.sh"
    take_down() {
      rm -f "$DEV_SITES/$1" "$DEV_UP/$1"
    }
    running() { [[ "$1" == mysql ]]; }
    mysql_cli() { printf "%s\n" "$*" >> "$BATS_TEST_TMPDIR/calls"; }
    cmd_destroy -y projeto-destroy
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"destroy_db"* ]]
  [[ "$output" == *"projeto-destroy apagado com sucesso"* ]]
  [ ! -d "$dir" ]
  [ ! -f "$DEV_HOME/sites/projeto-destroy" ]
  grep -q 'DROP DATABASE IF EXISTS `destroy_db`' "$BATS_TEST_TMPDIR/calls"
}

@test "ensure_php aceita versao quando binario ja esta instalado" {
  run libraries '
    source "$DEV_ROOT/lib/project.sh"
    mkdir -p "$DEV_RUNTIME/php/8.4.27/bin"
    touch "$DEV_RUNTIME/php/8.4.27/bin/php"
    chmod +x "$DEV_RUNTIME/php/8.4.27/bin/php"
    ensure_php "8.4" "Moodle"
  '
  [ "$status" -eq 0 ]
}

@test "ensure_php com confirmacao do usuario aciona compile_runtime" {
  run libraries '
    source "$DEV_ROOT/lib/project.sh"
    runtime_local_tarball() { return 1; }
    confirm() { return 0; }
    compile_runtime() { return 0; }
    ensure_php "8.4" "Moodle"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"COMPILAÇÃO SOB DEMANDA"* ]]
  [[ "$output" == *"instalado com sucesso"* ]]
}

@test "ensure_php com recusa do usuario cancela sem prosseguir" {
  run libraries '
    source "$DEV_ROOT/lib/project.sh"
    runtime_local_tarball() { return 1; }
    confirm() { return 1; }
    ensure_php "8.4" "Moodle"
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"criação cancelada: o Moodle requer PHP 8.4"* ]]
}

