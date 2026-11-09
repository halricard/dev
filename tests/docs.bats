#!/usr/bin/env bats
# Testes do dev docs: servidor MCP do Context7 e chave de API.

load helper

@test "o Context7 MCP fica no runtime do dev, na versão fixada" {
  run libraries '
    source "$DEV_ROOT/lib/docs.sh"
    context7_mcp_cli
  '
  [ "$status" -eq 0 ]
  [[ "$output" == "$DEV_HOME/runtime/context7-mcp/$CONTEXT7_MCP_VERSION/node_modules/@upstash/context7-mcp/dist/index.js" ]]
  [[ "$CONTEXT7_MCP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "docs key grava a chave aceita só para o dono e mascara na saída" {
  printf '#!/bin/sh\ncat > "%s/header"\nprintf 200\n' "$BATS_TEST_TMPDIR" > "$STUBS_BIN/curl"
  chmod +x "$STUBS_BIN/curl"
  run bash -c 'printf "ctx7sk-abcdef-123456-wxyz\n" | "$1" docs key' _ "$ROOT/dev"
  [ "$status" -eq 0 ]
  [[ "$output" == *"aceita"* ]]
  [[ "$output" != *"ctx7sk-abcdef-123456-wxyz"* ]]
  [[ "$output" == *"ctx7sk-…wxyz"* ]]
  grep -q '^CONTEXT7_API_KEY=ctx7sk-abcdef-123456-wxyz$' "$DEV_HOME/config"
  [ "$(stat -c %a "$DEV_HOME/config")" = "600" ]
  grep -q 'Authorization: Bearer ctx7sk-abcdef-123456-wxyz' "$BATS_TEST_TMPDIR/header"
}

@test "docs key recusa a chave que o Context7 rejeita e não grava nada" {
  printf '#!/bin/sh\ncat >/dev/null\nprintf 401\n' > "$STUBS_BIN/curl"
  chmod +x "$STUBS_BIN/curl"
  run bash -c 'printf "ctx7sk-errada-000000\n" | "$1" docs key' _ "$ROOT/dev"
  [ "$status" -ne 0 ]
  [[ "$output" == *"recusou"* ]]
  ! grep -q 'CONTEXT7_API_KEY' "$DEV_HOME/config" 2>/dev/null
}

@test "docs key grava mesmo sem conseguir falar com o Context7" {
  printf '#!/bin/sh\ncat >/dev/null\nprintf 000\nexit 6\n' > "$STUBS_BIN/curl"
  chmod +x "$STUBS_BIN/curl"
  run bash -c 'printf "ctx7sk-offline-123456\n" | "$1" docs key' _ "$ROOT/dev"
  [ "$status" -eq 0 ]
  [[ "$output" == *"não consegui falar"* ]]
  grep -q 'CONTEXT7_API_KEY=ctx7sk-offline-123456' "$DEV_HOME/config"
}

@test "docs key --remove apaga só a chave" {
  run libraries '
    source "$DEV_ROOT/lib/docs.sh"
    config_set DEFAULT_PHP 8.4
    config_set CONTEXT7_API_KEY ctx7sk-xyz
    docs_key --remove
  '
  [ "$status" -eq 0 ]
  ! grep -q CONTEXT7_API_KEY "$DEV_HOME/config"
  grep -q DEFAULT_PHP "$DEV_HOME/config"
}

@test "a variável CONTEXT7_API_KEY vence a chave gravada" {
  run libraries '
    source "$DEV_ROOT/lib/docs.sh"
    config_set CONTEXT7_API_KEY gravada
    docs_api_key
    CONTEXT7_API_KEY=do-ambiente docs_api_key
  '
  [ "${lines[0]}" = "gravada" ]
  [ "${lines[1]}" = "do-ambiente" ]
}

@test "docs mcp não escreve nada na saída padrão quando falta o servidor" {
  run bash -c '"$1" docs mcp 2>/dev/null' _ "$ROOT/dev"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "docs mcp passa a chave por variável de ambiente, não por argumento" {
  local cli="$DEV_HOME/runtime/context7-mcp/$CONTEXT7_MCP_VERSION/node_modules/@upstash/context7-mcp/dist/index.js"
  mkdir -p "$(dirname "$cli")" "$DEV_HOME/runtime/node/24.0.0/bin"
  touch "$cli"
  printf '#!/bin/sh\necho "args=$*"\necho "key=$CONTEXT7_API_KEY"\necho "otel=$OTEL_SDK_DISABLED"\n' \
    > "$DEV_HOME/runtime/node/24.0.0/bin/node"
  chmod +x "$DEV_HOME/runtime/node/24.0.0/bin/node"
  run libraries '
    source "$DEV_ROOT/lib/docs.sh"
    config_set DEFAULT_NODE 24.0.0
    config_set CONTEXT7_API_KEY ctx7sk-segredo
    node_bin() { printf "%s\n" "$DEV_HOME/runtime/node/24.0.0/bin/node"; }
    docs_mcp
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"args=$cli --transport stdio"* ]]
  [[ "${lines[0]}" == "args="* && "${lines[0]}" != *"ctx7sk-segredo"* ]]
  [[ "$output" == *"key=ctx7sk-segredo"* ]]
  [[ "$output" == *"otel=true"* ]]
}

@test "dev docs mostra o estado sem instalar nada" {
  run dev_cmd docs
  [ "$status" -eq 0 ]
  [[ "$output" == *"Context7 MCP"*"$CONTEXT7_MCP_VERSION"* ]]
  [[ "$output" == *"docs key"* ]]
  [ ! -d "$DEV_HOME/runtime/context7-mcp" ]
}

@test "dev help lista os comandos de docs" {
  run dev_cmd help
  [[ "$output" == *"docs key"* ]]
  [[ "$output" == *"--docs"* ]]
}
