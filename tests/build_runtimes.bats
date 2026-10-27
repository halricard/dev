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

@test "lib/runtime.sh exporta APT_BUILD_DEPS com 13 ferramentas oficiais" {
  run bash -c "source '$ROOT/lib/runtime.sh' && printf '%s\n' \"\${#APT_BUILD_DEPS[@]}\""
  [ "$status" -eq 0 ]
  [ "$output" -ge 13 ]

  run bash -c "source '$ROOT/lib/runtime.sh' && printf '%s ' \"\${APT_BUILD_DEPS[@]}\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"gcc "* ]]
  [[ "$output" == *"g++ "* ]]
  [[ "$output" == *"make "* ]]
  [[ "$output" == *"autoconf "* ]]
  [[ "$output" == *"bison "* ]]
  [[ "$output" == *"re2c "* ]]
  [[ "$output" == *"flex "* ]]
}

@test "missing_build_deps identifica ferramentas ausentes" {
  run bash -c "source '$ROOT/lib/runtime.sh'
    APT_BUILD_DEPS=(ferramenta_inexistente_1234 gcc)
    missing=\$(missing_build_deps)
    printf '%s\n' \"\$missing\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"ferramenta_inexistente_1234"* ]]
}

@test "check_build_deps aborta em modo nao-interativo quando faltam ferramentas" {
  run bash -c "
    DEV_ROOT='$ROOT'
    source '$ROOT/lib/common.sh'
    source '$ROOT/tools/build-runtimes.sh'
    missing_build_deps() { echo 'gcc'; }
    check_build_deps
  " </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"faltam 1 ferramentas de compilação no sistema"* ]]
  [[ "$output" == *"sudo apt update && sudo apt install -y gcc"* ]]
}

@test "check_build_deps instala ferramentas com confirmacao positiva do usuario" {
  run bash -c "
    DEV_ROOT='$ROOT'
    source '$ROOT/lib/common.sh'
    source '$ROOT/tools/build-runtimes.sh'
    missing_count=1
    missing_build_deps() {
      if (( missing_count > 0 )); then echo 'gcc'; return 0; fi
      return 0
    }
    confirm() { return 0; }
    sudo() {
      if [[ \"\$1\" == \"apt-get\" ]]; then
        missing_count=0
        return 0
      fi
      return 1
    }
    check_build_deps
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"instalando ferramentas de compilação..."* ]]
  [[ "$output" == *"ferramentas de compilação instaladas com sucesso"* ]]
}

