#!/usr/bin/env bats
# Testes do instalador e comandos de ambiente.

load helper

@test "dev install --plan executa com sucesso sem tocar no disco" {
  run dev_cmd install --plan
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"PLANO DO CORE"* ]]
  [[ "$output" == *"PHP"* ]]
  [[ "$output" == *"MySQL"* ]]
  [[ "$output" == *"apenas simulação (--plan)"* ]]
}

@test "dev versions lista componentes fixados" {
  run dev_cmd versions
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"VERSÕES FIXADAS"* ]]
  [[ "$output" == *"mysql"* ]]
  [[ "$output" == *"node"* ]]
}
