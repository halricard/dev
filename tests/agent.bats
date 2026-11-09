#!/usr/bin/env bats
# Testes do dev agent: skill do dev para Claude, Codex e Antigravity.

load helper

@test "agent add claude gera a skill com os dados do projeto" {
  project_conf APP=wordpress DATABASE=test_site
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent add claude'
  [ "$status" -eq 0 ]
  local file="$TEST_PROJECT/.claude/skills/dev/SKILL.md"
  [ -f "$file" ]
  grep -q '^name: dev$' "$file"
  grep -q 'generated-by: dev agent' "$file"
  grep -q 'test-site' "$file"
  grep -q 'test_site' "$file"
  grep -q 'https://test-site.localhost' "$file"
  grep -q 'dev exec wp' "$file"
  ! grep -q '{{' "$file"
}

@test "agent add usa o diretório de cada agente" {
  project_conf APP=laravel DATABASE=test_site
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent add all'
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT/.claude/skills/dev/SKILL.md" ]
  [ -f "$TEST_PROJECT/.agents/skills/dev/SKILL.md" ]
  [ -f "$TEST_PROJECT/.agent/skills/dev/SKILL.md" ]
  grep -q 'php artisan' "$TEST_PROJECT/.agents/skills/dev/SKILL.md"
}

@test "agent add moodle inclui notas do Moodle" {
  project_conf APP=moodle DATABASE=test_site
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent add codex'
  [ "$status" -eq 0 ]
  grep -q 'purge_caches' "$TEST_PROJECT/.agents/skills/dev/SKILL.md"
}

@test "agent add não grava credenciais do banco" {
  project_conf APP=wordpress DATABASE=test_site
  run in_project '
    source "$DEV_ROOT/lib/agent.sh"
    config_set MYSQL_PASSWORD "segredo-unico-123"
    cmd_agent add claude
  '
  [ "$status" -eq 0 ]
  ! grep -rq 'segredo-unico-123' "$TEST_PROJECT/.claude"
}

@test "agent add sem alvo e sem terminal falha com o uso" {
  project_conf APP=wordpress
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent add'
  [ "$status" -ne 0 ]
  [[ "$output" == *"uso:"* ]]
  [ ! -d "$TEST_PROJECT/.claude" ]
}

@test "agent add rejeita agente desconhecido" {
  project_conf APP=wordpress
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent add cursor'
  [ "$status" -ne 0 ]
  [[ "$output" == *"agente desconhecido"* ]]
}

@test "agent add preserva arquivo que o dev não gerou" {
  project_conf APP=wordpress
  mkdir -p "$TEST_PROJECT/.claude/skills/dev"
  echo "minha skill" > "$TEST_PROJECT/.claude/skills/dev/SKILL.md"
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent add claude'
  [ "$status" -eq 0 ]
  [[ "$output" == *"mantido"* ]]
  [ "$(cat "$TEST_PROJECT/.claude/skills/dev/SKILL.md")" = "minha skill" ]
}

@test "agent add é idempotente" {
  project_conf APP=wordpress
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent add claude'
  local before; before="$(cat "$TEST_PROJECT/.claude/skills/dev/SKILL.md")"
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent add claude'
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_PROJECT/.claude/skills/dev/SKILL.md")" = "$before" ]
}

@test "agent update regenera só o que está instalado" {
  project_conf APP=wordpress DATABASE=old_db
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent add claude'
  project_conf APP=wordpress DATABASE=new_db
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent update'
  [ "$status" -eq 0 ]
  grep -q 'new_db' "$TEST_PROJECT/.claude/skills/dev/SKILL.md"
  [ ! -d "$TEST_PROJECT/.agents" ]
}

@test "agent remove apaga só o gerado e limpa diretórios vazios" {
  project_conf APP=wordpress
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent add all'
  mkdir -p "$TEST_PROJECT/.claude/skills/outra"
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent remove all'
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_PROJECT/.claude/skills/dev" ]
  [ -d "$TEST_PROJECT/.claude/skills/outra" ]
  [ ! -e "$TEST_PROJECT/.agents" ]
  [ ! -e "$TEST_PROJECT/.agent" ]
}

@test "agent list mostra o estado de cada agente" {
  project_conf APP=wordpress
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent add codex; cmd_agent list'
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex"*"instalado"* ]]
  [[ "$output" == *"claude"*"disponível"* ]]
}

@test "agent fora de um projeto falha" {
  run libraries 'source "$DEV_ROOT/lib/agent.sh"; cd "$BATS_TEST_TMPDIR" && cmd_agent add claude'
  [ "$status" -ne 0 ]
}

@test "dev help lista os comandos de agent" {
  run dev_cmd help
  [[ "$output" == *"agent add"* ]]
}

# Instalação do navegador simulada: o teste só confere os arquivos de MCP.
browser_stubs='
  install_browser() { :; }
  browser_install_deps() { :; }
  install_playwright_mcp() { :; }
'

@test "agent add --browser grava o MCP do Claude sem segredo nem caminho da máquina" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=wordpress DATABASE=test_site
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; '"$browser_stubs"'
    config_set MYSQL_PASSWORD "segredo-unico-123"
    cmd_agent add claude --browser'
  [ "$status" -eq 0 ]
  local file="$TEST_PROJECT/.mcp.json"
  [ -f "$file" ]
  grep -q '"dev-browser"' "$file"
  grep -q '"browser"' "$file"
  grep -q '"test-site"' "$file"
  ! grep -q 'segredo-unico-123' "$file"
  ! grep -q "$HOME" "$file"
}

@test "agent add --browser preserva outros servidores e o remove tira só o do dev" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=wordpress
  printf '{"mcpServers":{"outro":{"command":"x"}},"extra":1}\n' > "$TEST_PROJECT/.mcp.json"
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; '"$browser_stubs"' cmd_agent add claude --browser'
  [ "$status" -eq 0 ]
  grep -q '"outro"' "$TEST_PROJECT/.mcp.json"
  grep -q '"dev-browser"' "$TEST_PROJECT/.mcp.json"
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent list'
  [[ "$output" == *"claude"*"navegador"* ]]
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent remove claude'
  [ "$status" -eq 0 ]
  grep -q '"outro"' "$TEST_PROJECT/.mcp.json"
  ! grep -q '"dev-browser"' "$TEST_PROJECT/.mcp.json"
}

@test "agent add --browser não mexe em .mcp.json inválido nem em servidor alheio" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=wordpress
  printf '{ quebrado' > "$TEST_PROJECT/.mcp.json"
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; '"$browser_stubs"' cmd_agent add claude --browser'
  [ "$status" -eq 0 ]
  [[ "$output" == *"não é JSON válido"* ]]
  [ "$(cat "$TEST_PROJECT/.mcp.json")" = "{ quebrado" ]

  printf '{"mcpServers":{"dev-browser":{"command":"meu"}}}\n' > "$TEST_PROJECT/.mcp.json"
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; '"$browser_stubs"' cmd_agent add claude --browser'
  [[ "$output" == *"não é do dev"* ]]
  grep -q '"meu"' "$TEST_PROJECT/.mcp.json"
}

@test "agent add --browser grava e o remove tira o bloco do Codex" {
  project_conf APP=wordpress
  mkdir -p "$TEST_PROJECT/.codex"
  printf 'model = "x"\n' > "$TEST_PROJECT/.codex/config.toml"
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; '"$browser_stubs"' cmd_agent add codex --browser; cmd_agent add codex --browser'
  [ "$status" -eq 0 ]
  local file="$TEST_PROJECT/.codex/config.toml"
  [ "$(grep -c '^\[mcp_servers.dev-browser\]' "$file")" -eq 1 ]
  grep -q 'args = \["browser", "mcp", "test-site"\]' "$file"
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent remove codex'
  [ "$(cat "$file")" = 'model = "x"' ]
}

@test "agent add --browser para o Antigravity só mostra a configuração" {
  project_conf APP=wordpress
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; '"$browser_stubs"' cmd_agent add antigravity --browser'
  [ "$status" -eq 0 ]
  [[ "$output" == *"configuração global"* ]]
  [[ "$output" == *'"dev-browser"'* ]]
}

@test "a skill traz testes, usuário de teste e endereço de teste nas notas do Moodle" {
  project_conf APP=moodle DATABASE=test_site
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent add claude'
  local file="$TEST_PROJECT/.claude/skills/dev/SKILL.md"
  grep -q 'dev test user' "$file"
  grep -q 'dev test behat' "$file"
  grep -q 'https://test.test-site.localhost' "$file"
  grep -q 'Never use, read or reset the real administrator account' "$file"
  ! grep -q '{{' "$file"
}

# Instalação do Context7 MCP simulada: o teste só confere os arquivos de MCP.
docs_stubs='
  install_context7_mcp() { :; }
'

@test "agent add --docs grava o MCP do Context7 sem a chave de API" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=laravel DATABASE=test_site
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; '"$docs_stubs"'
    config_set CONTEXT7_API_KEY "ctx7sk-chave-unica-123"
    cmd_agent add all --docs'
  [ "$status" -eq 0 ]
  local file="$TEST_PROJECT/.mcp.json"
  grep -q '"dev-docs"' "$file"
  grep -q '"docs"' "$file"
  grep -q 'args = \["docs", "mcp"\]' "$TEST_PROJECT/.codex/config.toml"
  [[ "$output" == *'"dev-docs"'* ]]
  ! grep -rq 'ctx7sk-chave-unica-123' "$TEST_PROJECT"
  ! grep -q "$HOME" "$file"
}

@test "agent add --browser --docs convive no mesmo projeto e o remove tira os dois" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=wordpress
  mkdir -p "$TEST_PROJECT/.codex"
  printf 'model = "x"\n' > "$TEST_PROJECT/.codex/config.toml"
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; '"$browser_stubs$docs_stubs"'
    cmd_agent add claude --browser --docs
    cmd_agent add codex --browser --docs; cmd_agent add codex --docs'
  [ "$status" -eq 0 ]
  grep -q '"dev-browser"' "$TEST_PROJECT/.mcp.json"
  grep -q '"dev-docs"' "$TEST_PROJECT/.mcp.json"
  local toml="$TEST_PROJECT/.codex/config.toml"
  [ "$(grep -c '^\[mcp_servers.dev-docs\]' "$toml")" -eq 1 ]
  [ "$(grep -c '^\[mcp_servers.dev-browser\]' "$toml")" -eq 1 ]
  [ "$(grep -c '^$' "$toml")" -eq 2 ]
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent list'
  [[ "$output" == *"claude"*"navegador"*"documentação"* ]]
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent remove all'
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_PROJECT/.mcp.json" ]
  [ "$(cat "$toml")" = 'model = "x"' ]
}

@test "agent add sem --docs sugere a documentação" {
  project_conf APP=wordpress
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent add claude'
  [[ "$output" == *"--docs"* ]]
  [ ! -e "$TEST_PROJECT/.mcp.json" ]
}

@test "a skill traz a versão da aplicação e os IDs do Context7" {
  project_conf APP=laravel DATABASE=test_site
  local app="$TEST_PROJECT/vendor/laravel/framework/src/Illuminate/Foundation"
  mkdir -p "$app"
  printf "<?php\nclass Application {\n    const VERSION = '12.38.1';\n}\n" > "$app/Application.php"
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent add claude'
  local file="$TEST_PROJECT/.claude/skills/dev/SKILL.md"
  grep -q 'Version: `12.38.1`' "$file"
  grep -q 'dev-docs' "$file"
  grep -q '/laravel/docs/<major>.x' "$file"
  ! grep -q '{{' "$file"
}

@test "a skill sem versão detectada pede para conferir no código" {
  project_conf APP=wordpress
  run in_project 'source "$DEV_ROOT/lib/agent.sh"; cmd_agent add claude'
  local file="$TEST_PROJECT/.claude/skills/dev/SKILL.md"
  grep -q 'Version: not detected' "$file"
  grep -q '/websites/developer_wordpress_reference_hooks' "$file"
}

@test "as receitas leem a versão instalada sem rodar PHP" {
  mkdir -p "$TEST_PROJECT/wp/wp-includes" "$TEST_PROJECT/moodle/app"
  touch "$TEST_PROJECT/wp/wp-settings.php"
  printf "<?php\n\$wp_version = '6.8.3';\n" > "$TEST_PROJECT/wp/wp-includes/version.php"
  printf "<?php\n\$version  = 2025100600.00;\n\$release  = '5.1.1+ (Build: 20251212)';\n" > "$TEST_PROJECT/moodle/app/version.php"
  run libraries '
    load_recipe wordpress; recipe_version "'"$TEST_PROJECT/wp"'"
    load_recipe moodle; recipe_version "'"$TEST_PROJECT/moodle"'"
  '
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "6.8.3" ]
  [ "${lines[1]}" = "5.1.1+" ]
}
