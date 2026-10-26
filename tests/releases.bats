#!/usr/bin/env bats
# Testes da biblioteca lib/releases.sh e lib/runtime.sh.

load helper

@test "pinned_version devolve versões configuradas" {
  run libraries 'pinned_version node'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "$NODE_VERSION" ]]

  run libraries 'pinned_version mysql'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "$MYSQL_VERSION" ]]
}

@test "cache_name formata nomes com versões" {
  run libraries 'cache_name node 24.21.0'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "node-v24.21.0-linux-x64.tar.xz" ]]

  run libraries 'cache_name composer 2.10.3'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "composer-2.10.3.phar" ]]
}

@test "url_for gera URLs HTTPS válidas" {
  run libraries 'url_for node 24.21.0'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "https://nodejs.org/dist/v24.21.0/node-v24.21.0-linux-x64.tar.xz" ]]

  run libraries 'url_for composer 2.10.3'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "https://getcomposer.org/download/2.10.3/composer.phar" ]]
}

@test "runtime_version lê versão do manifesto" {
  run libraries 'runtime_version php'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "8.5.11" ]]

  run libraries 'runtime_version nginx'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "1.30.5" ]]
}
