#!/usr/bin/env bats
# O despachante e as faces da documentação: a ajuda e os comandos.

load helper

commands_from_usage() {
  local list
  list="$(dev_cmd help | awk '/^    [a-z]/ { print $1 }' | sort -u)"
  [[ -n "$list" ]] || { echo "a ajuda não listou comando nenhum" >&2; return 1; }
  printf '%s\n' "$list"
}

commands_from_case() {
  sed -n '/^case "\$subcommand" in/,/^esac/p' "$ROOT/dev" \
    | grep -oE '^  [a-z|]+\)' | tr -d ' )' | tr '|' '\n' \
    | grep -vxE 'help' | sort -u
}

@test "help roda num sandbox vazio" {
  run dev_cmd help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"PROJETO"* ]]
  [[ "$output" == *"PLUGINS"* ]]
}

@test "--version roda num sandbox vazio" {
  run dev_cmd --version
  [[ "$status" -eq 0 ]]
  [[ "$output" == dev* ]]
}

@test "comando desconhecido diz como ver a lista" {
  run dev_cmd nao-existe
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"comando desconhecido: nao-existe"* ]]
  [[ "$output" == *"dev help"* ]]
}

@test "todo comando da ajuda existe no despachante" {
  local help missing
  help="$(commands_from_usage)"
  missing="$(comm -23 <(printf '%s\n' "$help") <(commands_from_case))"
  [[ -z "$missing" ]] || { echo "na ajuda, sem entrada no case: $missing"; false; }
}

@test "todo comando do despachante aparece na ajuda" {
  local help missing
  help="$(commands_from_usage)"
  missing="$(comm -13 <(printf '%s\n' "$help") <(commands_from_case))"
  [[ -z "$missing" ]] || { echo "no case, sem linha no usage(): $missing"; false; }
}

@test "todo comando da ajuda aparece no README" {
  local block c missing=""
  block="$(awk '/^## Comandos/ { section = 1; next }
                section && /^```/ { if (inside) exit; inside = 1; next }
                inside' "$ROOT/README.md")"
  [[ -n "$block" ]] || { echo "não achei o bloco de \"## Comandos\" no README"; false; }
  local help
  help="$(commands_from_usage)"
  for c in $help; do
    grep -qw -- "$c" <<<"$block" || missing+=" $c"
  done
  [[ -z "$missing" ]] || { echo "sem linha no README:$missing"; false; }
}

@test "todo comando da ajuda aparece no guia" {
  local help c missing=""
  help="$(commands_from_usage)"
  for c in $help; do
    grep -qE "<code>(dev )?$c[ <]|dev $c\b" "$ROOT/USERGUIDE.html" || missing+=" $c"
  done
  [[ -z "$missing" ]] || { echo "sem menção no USERGUIDE.html:$missing"; false; }
}

@test "a ajuda não tem crase nem variável solta" {
  run dev_cmd help
  [[ "$output" != *"command not found"* ]]
  [[ "$output" != *"unbound variable"* ]]
}

@test "o terminal do guia preserva as quebras de linha" {
  grep -q 'white-space:\s*pre-wrap' "$ROOT/USERGUIDE.html" \
    || { echo "o bloco .term perdeu o white-space:pre-wrap"; false; }
  grep -q 'class="in"' "$ROOT/USERGUIDE.html" \
    || { echo "as linhas digitadas perderam a classe .in"; false; }
}
