#!/usr/bin/env bats
# Testes de execução isolada: dev exec e dev shell.

load helper

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export DEV_HOME="$BATS_TEST_TMPDIR/sandbox"
  export DEV_CACHE="$BATS_TEST_TMPDIR/cache"
  export NO_COLOR=1
  unset DEV_YES
  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$HOME" "$DEV_HOME" "$TEST_PROJECT" "$DEV_HOME/etc"
  STUBS_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUBS_BIN"
  export PATH="$STUBS_BIN:$PATH"

  # Mock PHP runtime
  local php_bin_dir="$DEV_HOME/runtime/php/8.5.11/bin"
  mkdir -p "$php_bin_dir" "$DEV_HOME/runtime/php/8.5.11/sbin"
  cat > "$php_bin_dir/php" << 'EOF'
#!/bin/sh
echo "PHP 8.5.11 mock"
EOF
  chmod +x "$php_bin_dir/php"
  touch "$DEV_HOME/runtime/php/8.5.11/.installed"

  source "$ROOT/lib/common.sh"
  config_set DEFAULT_PHP "8.5.11"
}

@test "dev exec fora de projeto falha com aviso de dev.conf" {
  local outside="$BATS_TEST_TMPDIR/outside"
  mkdir -p "$outside"
  cd "$outside"
  run dev_cmd exec env
  cd "$BATS_TEST_TMPDIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"não há dev.conf aqui nem acima"* ]]
}

@test "dev exec sem comando informa uso correto" {
  cd "$TEST_PROJECT"
  project_conf PHP="8.5.11" DATABASE="testdb"
  run dev_cmd exec
  [ "$status" -ne 0 ]
  [[ "$output" == *"uso: dev exec <comando…>"* ]]
}

@test "dev exec injeta PATH isolado, DATABASE_URL e PHP_INI_SCAN_DIR no comando" {
  cd "$TEST_PROJECT"
  project_conf PHP="8.5.11" DATABASE="testdb"

  run dev_cmd exec env
  [ "$status" -eq 0 ]
  [[ "$output" == *"DATABASE_URL=mysql://"*"/testdb"* ]]
  [[ "$output" == *"PHP_INI_SCAN_DIR="*"/php/8.5.11/conf.d"* ]]
  [[ "$output" == *"PATH="*"/runtime/php/8.5.11/bin:"* ]]
  [ -x "$DEV_HOME/bin/composer" ]
}

@test "dev exec roda binário mock do PHP do projeto" {
  cd "$TEST_PROJECT"
  project_conf PHP="8.5.11" DATABASE="testdb"

  run dev_cmd exec php -v
  [ "$status" -eq 0 ]
  [[ "$output" == *"PHP 8.5.11 mock"* ]]
}

@test "dev shell executa SHELL com ambiente do projeto" {
  cd "$TEST_PROJECT"
  project_conf PHP="8.5.11" DATABASE="shelldb"

  run bash -c "export SHELL=/bin/sh; printf 'echo OK=\$DATABASE_URL\nexit\n' | \"$ROOT/dev\" shell"
  [ "$status" -eq 0 ]
  [[ "$output" == *"shell do projeto test-site"* ]]
  [[ "$output" == *"OK=mysql://"*"/shelldb"* ]]
}
