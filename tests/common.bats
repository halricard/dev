#!/usr/bin/env bats
# Testes da biblioteca lib/common.sh.

load helper

@test "plataforma responde wsl ou linux" {
  run libraries 'printf "%s\n" "$(platform)"'
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ ^(wsl|linux)$ ]]
}

@test "DEV_PLATFORM força a resposta de plataforma" {
  DEV_PLATFORM=linux run libraries 'printf "%s\n" "$(platform)"'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "linux" ]]

  DEV_PLATFORM=wsl run libraries 'printf "%s\n" "$(platform)"'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "wsl" ]]
}

@test "load_project lê dev.conf corretamente" {
  project_conf "PHP=8.5" "DATABASE=teste_db" "APP=wordpress"
  run in_project 'load_project && printf "%s|%s|%s|%s\n" "$PROJECT_NAME" "$PROJECT_APP" "$PROJECT_PHP" "$PROJECT_DATABASE"'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "test-site|wordpress|8.5|teste_db" ]]
}

@test "find_project acha dev.conf em subdiretórios" {
  project_conf "PHP=8.5"
  mkdir -p "$TEST_PROJECT/sub/dir"
  cd "$TEST_PROJECT/sub/dir"
  run libraries 'find_project'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "$TEST_PROJECT" ]]
}

@test "project_conf_set altera e acrescenta chaves" {
  project_conf "PHP=8.5"
  run in_project 'project_conf_set "$PWD/dev.conf" PHP "8.4" && project_conf_set "$PWD/dev.conf" DATABASE "novo_db" && cat dev.conf'
  [[ "$status" -eq 0 ]]
  [[ "$output" == *'PHP="8.4"'* ]]
  [[ "$output" == *'DATABASE="novo_db"'* ]]
}

@test "random_password gera senha com letra, digito e simbolo" {
  run libraries 'random_password'
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ [A-Z] ]]
  [[ "$output" =~ [a-z] ]]
  [[ "$output" =~ [0-9] ]]
  [[ "$output" =~ [!@#%*_-] ]]
}
