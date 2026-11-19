#!/usr/bin/env bats
# Testes do dev context7 (servidor MCP do Context7) e do dev agent key (chaves
# das ferramentas do Claude Code).

load helper

curl_stub() {
  printf '#!/bin/sh\ncat > "%s/header"\nprintf %s\n%s\n' "$BATS_TEST_TMPDIR" "$1" "${2:-}" > "$STUBS_BIN/curl"
  chmod +x "$STUBS_BIN/curl"
}

@test "o Context7 MCP fica no runtime do dev, na versão fixada" {
  run libraries '
    source "$DEV_ROOT/lib/context7.sh"
    context7_mcp_cli
  '
  [ "$status" -eq 0 ]
  [[ "$output" == "$DEV_HOME/runtime/context7-mcp/$CONTEXT7_MCP_VERSION/node_modules/@upstash/context7-mcp/dist/index.js" ]]
  [[ "$CONTEXT7_MCP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "agent key context7 grava a chave aceita só para o dono e mascara na saída" {
  curl_stub 200
  run bash -c 'printf "ctx7sk-abcdef-123456-wxyz\n" | "$1" agent key context7' _ "$ROOT/dev"
  [ "$status" -eq 0 ]
  [[ "$output" == *"aceita"* ]]
  [[ "$output" != *"ctx7sk-abcdef-123456-wxyz"* ]]
  [[ "$output" == *"ctx7sk-…wxyz"* ]]
  grep -q '^CONTEXT7_API_KEY=ctx7sk-abcdef-123456-wxyz$' "$DEV_HOME/config"
  [ "$(stat -c %a "$DEV_HOME/config")" = "600" ]
  grep -q 'Authorization: Bearer ctx7sk-abcdef-123456-wxyz' "$BATS_TEST_TMPDIR/header"
}

@test "agent key recusa a chave que o serviço rejeita e não grava nada" {
  curl_stub 401
  run bash -c 'printf "ctx7sk-errada-000000\n" | "$1" agent key context7' _ "$ROOT/dev"
  [ "$status" -ne 0 ]
  [[ "$output" == *"recusou"* ]]
  ! grep -q 'CONTEXT7_API_KEY' "$DEV_HOME/config" 2>/dev/null
}

@test "agent key grava mesmo sem conseguir falar com o serviço" {
  curl_stub 000 'exit 6'
  run bash -c 'printf "ctx7sk-offline-123456\n" | "$1" agent key context7' _ "$ROOT/dev"
  [ "$status" -eq 0 ]
  [[ "$output" == *"não consegui falar"* ]]
  grep -q 'CONTEXT7_API_KEY=ctx7sk-offline-123456' "$DEV_HOME/config"
}

@test "agent key github confere o token na API do GitHub e o grava" {
  curl_stub 200
  run bash -c 'printf "github_pat_abcdef123456_wxyz\n" | "$1" agent key github' _ "$ROOT/dev"
  [ "$status" -eq 0 ]
  [[ "$output" == *"aceita pelo GitHub"* ]]
  [[ "$output" != *"github_pat_abcdef123456_wxyz"* ]]
  grep -q '^GITHUB_PAT=github_pat_abcdef123456_wxyz$' "$DEV_HOME/config"
  grep -q 'Authorization: Bearer github_pat_abcdef123456_wxyz' "$BATS_TEST_TMPDIR/header"
}

@test "agent key --remove apaga só a chave da ferramenta" {
  run libraries '
    source "$DEV_ROOT/lib/keys.sh"
    config_set DEFAULT_PHP 8.4
    config_set CONTEXT7_API_KEY ctx7sk-xyz
    config_set GITHUB_PAT ghp-xyz
    cmd_key context7 --remove
  '
  [ "$status" -eq 0 ]
  ! grep -q CONTEXT7_API_KEY "$DEV_HOME/config"
  grep -q GITHUB_PAT "$DEV_HOME/config"
  grep -q DEFAULT_PHP "$DEV_HOME/config"
}

@test "agent key sem ferramenta mostra o estado das chaves, mascaradas" {
  run libraries '
    source "$DEV_ROOT/lib/keys.sh"
    config_set GITHUB_PAT github_pat_abcdef123456_wxyz
    cmd_key
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"context7"*"não gravada"* ]]
  [[ "$output" == *"github"*"github_…wxyz"* ]]
  [[ "$output" != *"github_pat_abcdef123456_wxyz"* ]]
}

@test "agent key recusa ferramenta sem chave" {
  run dev_cmd agent key figma
  [ "$status" -ne 0 ]
  [[ "$output" == *"ferramenta sem chave: figma"* ]]
}

@test "agent key penpot grava a chave e o ~/.bashrc só a lê de ~/.dev/config" {
  printf '# meu bashrc\nalias ll="ls -l"\n' > "$HOME/.bashrc"
  run bash -c 'printf "pp-chave-unica-123456\n" | "$1" agent key penpot' _ "$ROOT/dev"
  [ "$status" -eq 0 ]
  [[ "$output" == *"não tem como conferir"* ]]
  [[ "$output" == *"abra um terminal novo"* ]]
  grep -q '^PENPOT_MCP_KEY=pp-chave-unica-123456$' "$DEV_HOME/config"
  grep -q '^alias ll="ls -l"$' "$HOME/.bashrc"
  grep -qxF '# >>> dev agent key >>>' "$HOME/.bashrc"
  ! grep -q 'pp-chave-unica-123456' "$HOME/.bashrc"
  # Um terminal novo recebe a chave.
  run bash -c 'unset PENPOT_MCP_KEY; source "$1"; printf "%s" "$PENPOT_MCP_KEY"' _ "$HOME/.bashrc"
  [ "$output" = "pp-chave-unica-123456" ]

  run bash -c 'printf "pp-chave-nova-654321\n" | "$1" agent key penpot' _ "$ROOT/dev"
  [ "$(grep -c '>>> dev agent key' "$HOME/.bashrc")" -eq 1 ]

  run dev_cmd agent key penpot --remove
  [ "$status" -eq 0 ]
  ! grep -q 'dev agent key' "$HOME/.bashrc"
  [ "$(cat "$HOME/.bashrc")" = "$(printf '# meu bashrc\nalias ll="ls -l"')" ]
  ! grep -q PENPOT_MCP_KEY "$DEV_HOME/config"
}

@test "as chaves do Context7 e do GitHub não mexem no ~/.bashrc" {
  printf '# meu bashrc\n' > "$HOME/.bashrc"
  curl_stub 200
  run bash -c 'printf "github_pat_abcdef123456_wxyz\n" | "$1" agent key github' _ "$ROOT/dev"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.bashrc")" = "# meu bashrc" ]
}

@test "a variável de ambiente vence a chave gravada" {
  run libraries '
    source "$DEV_ROOT/lib/keys.sh"
    config_set CONTEXT7_API_KEY gravada
    key_value context7
    CONTEXT7_API_KEY=do-ambiente key_value context7
  '
  [ "${lines[0]}" = "gravada" ]
  [ "${lines[1]}" = "do-ambiente" ]
}

@test "context7 mcp não escreve nada na saída padrão quando falta o servidor" {
  run bash -c '"$1" context7 mcp 2>/dev/null' _ "$ROOT/dev"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "context7 mcp passa a chave por variável de ambiente, não por argumento" {
  local cli="$DEV_HOME/runtime/context7-mcp/$CONTEXT7_MCP_VERSION/node_modules/@upstash/context7-mcp/dist/index.js"
  mkdir -p "$(dirname "$cli")" "$DEV_HOME/runtime/node/24.0.0/bin"
  touch "$cli"
  printf '#!/bin/sh\necho "args=$*"\necho "key=$CONTEXT7_API_KEY"\necho "otel=$OTEL_SDK_DISABLED"\n' \
    > "$DEV_HOME/runtime/node/24.0.0/bin/node"
  chmod +x "$DEV_HOME/runtime/node/24.0.0/bin/node"
  run libraries '
    source "$DEV_ROOT/lib/context7.sh"
    config_set CONTEXT7_API_KEY ctx7sk-segredo
    node_bin() { printf "%s\n" "$DEV_HOME/runtime/node/24.0.0/bin/node"; }
    context7_mcp
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"args=$cli --transport stdio"* ]]
  [[ "${lines[0]}" == "args="* && "${lines[0]}" != *"ctx7sk-segredo"* ]]
  [[ "$output" == *"key=ctx7sk-segredo"* ]]
  [[ "$output" == *"otel=true"* ]]
}

@test "dev context7 mostra o estado sem instalar nada" {
  run dev_cmd context7
  [ "$status" -eq 0 ]
  [[ "$output" == *"Context7 MCP"*"$CONTEXT7_MCP_VERSION"* ]]
  [[ "$output" == *"agent key context7"* ]]
  [ ! -d "$DEV_HOME/runtime/context7-mcp" ]
}

@test "dev docs não existe mais" {
  run dev_cmd docs
  [ "$status" -ne 0 ]
}

@test "dev help lista os comandos de context7 e de chaves" {
  run dev_cmd help
  [[ "$output" == *"context7 install"* ]]
  [[ "$output" == *"agent key"* ]]
  [[ "$output" == *"--context7"* ]]
  [[ "$output" != *"docs key"* ]]
}
