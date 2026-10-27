#!/usr/bin/env bats
# Testes do gerador e construtor de runtimes: tools/build-runtimes.sh.

load helper

@test "build-runtimes.sh exibe ajuda estruturada sem crases" {
  run "$ROOT/tools/build-runtimes.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"construtor de runtimes estáticos do dev"* ]]
  [[ "$output" == *"php [versão]"* ]]
  [[ "$output" != *"\`"* ]]
}

@test "build-runtimes.sh php 8.4 --plan simula compilação sem tocar no disco" {
  run "$ROOT/tools/build-runtimes.sh" php 8.4 --plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"COMPILAÇÃO DO PHP 8.4.6 (8.4)"* ]]
  [[ "$output" == *"modo simulação (--plan)"* ]]
  [[ "$output" == *"runtimes/php/php-8.4.6-linux-x86_64.tar.xz"* ]]
}

@test "build-runtimes.sh check-deps detecta ferramentas ausentes" {
  run "$ROOT/tools/build-runtimes.sh" check-deps
  # Se ferramentas faltarem, o código é 1 com diagnóstico
  if [[ "$status" -ne 0 ]]; then
    [[ "$output" == *"faltam"* ]]
    [[ "$output" == *"sudo apt install"* ]]
  else
    [[ "$output" == *"ferramentas de compilação do sistema presentes"* ]]
  fi
}

@test "build-runtimes.sh rejeita comando desconhecido" {
  run "$ROOT/tools/build-runtimes.sh" comando-invalido
  [ "$status" -ne 0 ]
  [[ "$output" == *"comando desconhecido"* ]]
}
