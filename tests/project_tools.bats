#!/usr/bin/env bats
# Testes dos comandos de suporte: errors, clean, track, snapshot, db e autostart.

load helper

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export DEV_HOME="$BATS_TEST_TMPDIR/sandbox"
  export DEV_CACHE="$BATS_TEST_TMPDIR/cache"
  export NO_COLOR=1
  unset DEV_YES
  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$HOME" "$DEV_HOME" "$TEST_PROJECT" "$DEV_HOME/sites" "$DEV_HOME/services/run" "$DEV_HOME/run" "$DEV_HOME/snapshots"
  STUBS_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUBS_BIN"
  export PATH="$STUBS_BIN:$PATH"

  source "$ROOT/lib/common.sh"
  config_set DEFAULT_PHP "8.5.11"
}

@test "errors on e off gerenciam estado de exibição de erros" {
  cd "$TEST_PROJECT"
  project_conf APP="" PHP="8.5.11" DOCROOT="." DATABASE=""

  run in_project '
    source "$DEV_ROOT/lib/errors.sh"
    write_vhost() { :; }
    reload_nginx() { :; }
    cmd_errors off
    [ -f "$DEV_QUIET/$PROJECT_NAME" ]
    cmd_errors on
    [ ! -f "$DEV_QUIET/$PROJECT_NAME" ]
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"ERROS NA TELA"* ]]
}

@test "clean lista arquivos de lixo e clean trash --plan simula remoção" {
  cd "$TEST_PROJECT"
  project_conf APP="" PHP="8.5.11" DOCROOT="." DATABASE=""

  touch "$TEST_PROJECT/Thumbs.db"
  touch "$TEST_PROJECT/desktop.ini"
  touch "$TEST_PROJECT/.DS_Store"

  run in_project '
    source "$DEV_ROOT/lib/clean.sh"
    cmd_clean
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"trash"* ]]
  [[ "$output" == *"3 arquivo(s)"* ]]

  run in_project '
    source "$DEV_ROOT/lib/clean.sh"
    cmd_clean trash --plan
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"seriam apagados"* ]]
  [ -f "$TEST_PROJECT/Thumbs.db" ]
}

@test "track e untrack manipulam .gitignore com escada de diretórios" {
  cd "$TEST_PROJECT"
  project_conf APP="wordpress" PHP="8.5.11" DOCROOT="." DATABASE=""

  cat > "$TEST_PROJECT/.gitignore" << 'EOF'
/*
!/dev.conf
!/wp-content/
/wp-content/*
EOF

  mkdir -p "$TEST_PROJECT/wp-content/plugins/meu-plugin"
  touch "$TEST_PROJECT/wp-content/plugins/meu-plugin/meu-plugin.php"

  run in_project '
    source "$DEV_ROOT/lib/track.sh"
    cmd_track wp-content/plugins/meu-plugin
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"passa a ser versionado"* ]]
  grep -qxF '!/wp-content/plugins/meu-plugin/' "$TEST_PROJECT/.gitignore"

  run in_project '
    source "$DEV_ROOT/lib/track.sh"
    cmd_untrack wp-content/plugins/meu-plugin
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"deixa de ser versionado"* ]]
  ! grep -qxF '!/wp-content/plugins/meu-plugin/' "$TEST_PROJECT/.gitignore"
}

@test "snapshot, snapshots e restore criam e recuperam backups de arquivos" {
  cd "$TEST_PROJECT"
  project_conf APP="" PHP="8.5.11" DOCROOT="." DATABASE=""

  echo "versao 1" > "$TEST_PROJECT/app.txt"

  run in_project '
    source "$DEV_ROOT/lib/snapshot.sh"
    running() { return 1; } # Sem mysql no teste
    cmd_snapshot ponto1
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"snapshot \"ponto1\""* ]]
  [ -d "$DEV_SNAPSHOTS/test-site/ponto1" ]
  [ -f "$DEV_SNAPSHOTS/test-site/ponto1/files.tar.gz" ]

  run in_project '
    source "$DEV_ROOT/lib/snapshot.sh"
    cmd_snapshots
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-site/ponto1"* ]]

  # Modifica arquivo e restaura
  echo "versao 2" > "$TEST_PROJECT/app.txt"
  [ "$(cat "$TEST_PROJECT/app.txt")" = "versao 2" ]

  run in_project '
    source "$DEV_ROOT/lib/snapshot.sh"
    running() { return 1; }
    cmd_restore -y ponto1
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"voltou para \"ponto1\""* ]]
  [ "$(cat "$TEST_PROJECT/app.txt")" = "versao 1" ]
}

@test "autostart status reporta estado desativado por padrão" {
  run libraries '
    source "$DEV_ROOT/lib/autostart.sh"
    has_systemd() { return 1; }
    cmd_autostart status
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"INÍCIO AUTOMÁTICO"* ]]
  [[ "$output" == *"desativado"* ]]
}
