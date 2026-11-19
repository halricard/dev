#!/usr/bin/env bats
# Testes do dev agent: skill do dev e ferramentas opcionais para o Claude Code.

load helper

# Instalações simuladas: os testes só conferem os arquivos gravados no projeto.
install_stubs='
  install_browser() { :; }
  browser_install_deps() { :; }
  install_playwright_mcp() { :; }
  install_context7_mcp() { :; }
  install_mcp_remote() { :; }
  agent_install_tlc() { mkdir -p "$1/.claude/skills/tlc-spec-driven" && echo tlc > "$1/.claude/skills/tlc-spec-driven/SKILL.md"; }
  agent_install_impeccable() { mkdir -p "$1/.claude/skills/impeccable" && echo ui > "$1/.claude/skills/impeccable/SKILL.md"; }
'

agent() { in_project 'source "$DEV_ROOT/lib/agent.sh"; '"$install_stubs"' '"$1"; }

skill() { printf '%s\n' "$TEST_PROJECT/.claude/skills/dev/SKILL.md"; }

# ------------------------------------------------------------------ skill dev
@test "agent add gera a skill com os dados do projeto" {
  project_conf APP=wordpress DATABASE=test_site
  run agent 'cmd_agent add'
  [ "$status" -eq 0 ]
  local file; file="$(skill)"
  [ -f "$file" ]
  grep -q '^name: dev$' "$file"
  grep -q 'generated-by: dev agent' "$file"
  grep -q 'test-site' "$file"
  grep -q 'test_site' "$file"
  grep -q 'https://test-site.localhost' "$file"
  grep -q 'dev exec wp' "$file"
  ! grep -q '{{' "$file"
}

@test "agent add sem flags grava só a skill, sem ferramentas nem método" {
  project_conf APP=laravel DATABASE=test_site
  run agent 'cmd_agent add'
  [ "$status" -eq 0 ]
  grep -q 'php artisan' "$(skill)"
  ! grep -q '## Feature work' "$(skill)"
  [ ! -e "$TEST_PROJECT/.mcp.json" ]
  [ ! -e "$TEST_PROJECT/CLAUDE.md" ]
  [ "$(ls "$TEST_PROJECT/.claude/skills")" = "dev" ]
}

@test "agent add moodle inclui as notas e a UI do Moodle" {
  project_conf APP=moodle DATABASE=test_site
  run agent 'cmd_agent add'
  [ "$status" -eq 0 ]
  grep -q 'purge_caches' "$(skill)"
  grep -q '### Moodle UI' "$(skill)"
}

@test "agent add não grava credenciais do banco" {
  project_conf APP=wordpress DATABASE=test_site
  run agent 'config_set MYSQL_PASSWORD "segredo-unico-123"; cmd_agent add --all'
  [ "$status" -eq 0 ]
  ! grep -rq 'segredo-unico-123' "$TEST_PROJECT"
}

@test "agent add rejeita flag desconhecida e as antigas com o uso" {
  project_conf APP=wordpress
  local flag
  for flag in codex --browser --docs; do
    run agent "cmd_agent add $flag"
    [ "$status" -ne 0 ]
    [[ "$output" == *"opção desconhecida: $flag"* ]]
    [[ "$output" == *"--playwright"* ]]
  done
  [ ! -d "$TEST_PROJECT/.claude" ]
}

@test "agent remove não aceita alvo" {
  project_conf APP=wordpress
  run agent 'cmd_agent add; cmd_agent remove claude'
  [ "$status" -ne 0 ]
  [[ "$output" == *"uso:"* ]]
  [ -f "$(skill)" ]
}

@test "agent add preserva arquivo que o dev não gerou" {
  project_conf APP=wordpress
  mkdir -p "$TEST_PROJECT/.claude/skills/dev"
  echo "minha skill" > "$(skill)"
  run agent 'cmd_agent add'
  [ "$status" -eq 0 ]
  [[ "$output" == *"mantido"* ]]
  [ "$(cat "$(skill)")" = "minha skill" ]
}

@test "agent add é idempotente" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=wordpress
  run agent 'cmd_agent add --all'
  local before mcp claude
  before="$(cat "$(skill)")"; mcp="$(cat "$TEST_PROJECT/.mcp.json")"; claude="$(cat "$TEST_PROJECT/CLAUDE.md")"
  run agent 'cmd_agent add --all'
  [ "$status" -eq 0 ]
  [ "$(cat "$(skill)")" = "$before" ]
  [ "$(cat "$TEST_PROJECT/.mcp.json")" = "$mcp" ]
  [ "$(cat "$TEST_PROJECT/CLAUDE.md")" = "$claude" ]
}

@test "agent update regenera a skill instalada" {
  project_conf APP=wordpress DATABASE=old_db
  run agent 'cmd_agent add'
  project_conf APP=wordpress DATABASE=new_db
  run agent 'cmd_agent update'
  [ "$status" -eq 0 ]
  grep -q 'new_db' "$(skill)"
}

@test "agent update sem skill instalada não cria nada" {
  project_conf APP=wordpress
  run agent 'cmd_agent update'
  [ "$status" -eq 0 ]
  [[ "$output" == *"nenhuma skill do dev instalada"* ]]
  [ ! -e "$TEST_PROJECT/.claude" ]
}

@test "agent remove apaga só o gerado e limpa diretórios vazios" {
  project_conf APP=wordpress
  run agent 'cmd_agent add'
  mkdir -p "$TEST_PROJECT/.claude/skills/outra"
  run agent 'cmd_agent remove'
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_PROJECT/.claude/skills/dev" ]
  [ -d "$TEST_PROJECT/.claude/skills/outra" ]

  rmdir "$TEST_PROJECT/.claude/skills/outra"
  run agent 'cmd_agent add; cmd_agent remove'
  [ ! -e "$TEST_PROJECT/.claude" ]
}

@test "agent list mostra a skill e cada ferramenta" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=wordpress
  run agent 'cmd_agent list'
  [ "$status" -eq 0 ]
  [[ "$output" == *"skill dev"*"disponível"* ]]
  run agent 'cmd_agent add --figma; cmd_agent list'
  [[ "$output" == *"skill dev"*"instalado"* ]]
  [[ "$output" == *"Figma"*".mcp.json  figma"*"instalado"* ]]
  [[ "$output" == *"GitHub"*"disponível"* ]]
  [[ "$output" == *"TLC Spec-Driven"*"disponível"* ]]
}

@test "agent fora de um projeto falha" {
  run libraries 'source "$DEV_ROOT/lib/agent.sh"; cd "$BATS_TEST_TMPDIR" && cmd_agent add'
  [ "$status" -ne 0 ]
}

@test "dev help lista os comandos e as flags de agent" {
  run dev_cmd help
  [[ "$output" == *"agent add"* ]]
  local flag
  for flag in --playwright --context7 --figma --penpot --github --impeccable --tlc --all; do
    [[ "$output" == *"$flag"* ]]
  done
}

@test "dev new não aceita mais --agent" {
  run dev_cmd new wordpress meu-site --agent
  [ "$status" -ne 0 ]
  [[ "$output" == *"opção desconhecida: --agent"* ]]
}

# --------------------------------------------------------- servidores MCP
@test "agent add --playwright grava o servidor sem segredo nem caminho da máquina" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=wordpress DATABASE=test_site
  run agent 'config_set MYSQL_PASSWORD "segredo-unico-123"; cmd_agent add --playwright'
  [ "$status" -eq 0 ]
  local file="$TEST_PROJECT/.mcp.json"
  grep -q '"dev-playwright"' "$file"
  grep -q '"browser"' "$file"
  grep -q '"test-site"' "$file"
  ! grep -q 'segredo-unico-123' "$file"
  ! grep -q "$HOME" "$file"
  grep -q '### Browser: Playwright (`dev-playwright`)' "$(skill)"
  ! grep -q '### Documentation: Context7' "$(skill)"
}

@test "agent add --playwright preserva outros servidores e o remove tira só o do dev" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=wordpress
  printf '{"mcpServers":{"outro":{"command":"x"}},"extra":1}\n' > "$TEST_PROJECT/.mcp.json"
  run agent 'cmd_agent add --playwright'
  [ "$status" -eq 0 ]
  grep -q '"outro"' "$TEST_PROJECT/.mcp.json"
  grep -q '"dev-playwright"' "$TEST_PROJECT/.mcp.json"
  run agent 'cmd_agent remove'
  [ "$status" -eq 0 ]
  grep -q '"outro"' "$TEST_PROJECT/.mcp.json"
  grep -q '"extra"' "$TEST_PROJECT/.mcp.json"
  ! grep -q '"dev-playwright"' "$TEST_PROJECT/.mcp.json"
}

@test "agent add não mexe em .mcp.json inválido nem em servidor alheio" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=wordpress
  printf '{ quebrado' > "$TEST_PROJECT/.mcp.json"
  run agent 'cmd_agent add --playwright'
  [ "$status" -eq 0 ]
  [[ "$output" == *"não é JSON válido"* ]]
  [ "$(cat "$TEST_PROJECT/.mcp.json")" = "{ quebrado" ]

  printf '{"mcpServers":{"figma":{"type":"http","url":"https://outro.example/mcp"}}}\n' > "$TEST_PROJECT/.mcp.json"
  run agent 'cmd_agent add --figma'
  [[ "$output" == *"não é do dev"* ]]
  grep -q 'outro.example' "$TEST_PROJECT/.mcp.json"
  run agent 'cmd_agent remove'
  grep -q 'outro.example' "$TEST_PROJECT/.mcp.json"
}

@test "agent add --context7 grava o servidor sem a chave de API" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=laravel DATABASE=test_site
  run agent 'config_set CONTEXT7_API_KEY "ctx7sk-chave-unica-123"; cmd_agent add --context7'
  [ "$status" -eq 0 ]
  local file="$TEST_PROJECT/.mcp.json"
  grep -q '"dev-context7"' "$file"
  grep -q '"context7",' "$file"
  ! grep -q '"docs"' "$file"
  ! grep -rq 'ctx7sk-chave-unica-123' "$TEST_PROJECT"
  ! grep -q "$HOME" "$file"
  grep -q '### Documentation: Context7 (`dev-context7`)' "$(skill)"
}

@test "agent add --figma grava o servidor remoto e pede a autenticação" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=laravel
  run agent 'cmd_agent add --figma'
  [ "$status" -eq 0 ]
  grep -q '"url": "https://mcp.figma.com/mcp"' "$TEST_PROJECT/.mcp.json"
  grep -q '"type": "http"' "$TEST_PROJECT/.mcp.json"
  [[ "$output" == *"/mcp → figma → Authenticate"* ]]
  grep -q '### Design files: Figma (`figma`)' "$(skill)"
  grep -q '### Laravel UI' "$(skill)"
}

@test "agent add --github grava o servidor do dev, sem o token, e avisa quando falta" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=wordpress
  run agent 'unset GITHUB_PAT; cmd_agent add --github'
  [ "$status" -eq 0 ]
  local file="$TEST_PROJECT/.mcp.json"
  grep -q '"github"' "$file"
  grep -q '"agent",' "$file"
  grep -q '"mcp",' "$file"
  ! grep -q 'githubcopilot' "$file"
  [[ "$output" == *"GitHub: falta o token"*"dev agent key github"* ]]
  [[ "$output" == *"github.com/settings/personal-access-tokens"* ]]
  grep -q '### Repository: GitHub (`github`)' "$(skill)"
  grep -q 'dev agent key github' "$(skill)"

  run agent 'config_set GITHUB_PAT ghp-token-unico-123456; cmd_agent add --github'
  [ "$status" -eq 0 ]
  [[ "$output" != *"falta o token"* ]]
  [[ "$output" == *"GitHub: token ghp-tok…3456 em"* ]]
  [[ "$output" != *"ghp-token-unico-123456"* ]]
  ! grep -rq 'ghp-token-unico-123456' "$TEST_PROJECT"
}

@test "agent mcp github entrega o token por variável de ambiente, não por argumento" {
  local cli="$DEV_HOME/runtime/mcp-remote/$MCP_REMOTE_VERSION/node_modules/mcp-remote/dist/proxy.js"
  mkdir -p "$(dirname "$cli")" "$BATS_TEST_TMPDIR/node"
  touch "$cli"
  printf '#!/bin/sh\necho "args=$*"\necho "auth=$DEV_GITHUB_AUTHORIZATION"\n' > "$BATS_TEST_TMPDIR/node/node"
  chmod +x "$BATS_TEST_TMPDIR/node/node"
  run libraries '
    source "$DEV_ROOT/lib/agent.sh"
    config_set GITHUB_PAT ghp-segredo-123456
    node_bin() { printf "%s\n" "$BATS_TEST_TMPDIR/node/node"; }
    cmd_agent mcp github
  '
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "args=$cli https://api.githubcopilot.com/mcp/ --header Authorization:\${DEV_GITHUB_AUTHORIZATION} --transport http-only" ]]
  [[ "${lines[0]}" != *"ghp-segredo"* ]]
  [ "${lines[1]}" = "auth=Bearer ghp-segredo-123456" ]
}

@test "agent mcp github sem token não escreve nada na saída padrão" {
  local cli="$DEV_HOME/runtime/mcp-remote/$MCP_REMOTE_VERSION/node_modules/mcp-remote/dist/proxy.js"
  mkdir -p "$(dirname "$cli")"
  touch "$cli"
  run bash -c 'unset GITHUB_PAT; "$1" agent mcp github 2>/dev/null' _ "$ROOT/dev"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  run bash -c 'unset GITHUB_PAT; "$1" agent mcp github 2>&1 >/dev/null' _ "$ROOT/dev"
  [[ "$output" == *"dev agent key github"* ]]
}

@test "agent update migra os servidores no formato antigo" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=wordpress
  run agent 'cmd_agent add'
  printf '{"mcpServers":{"dev-browser":{"command":"dev","args":["browser","mcp","test-site"]},"dev-docs":{"command":"dev","args":["docs","mcp"]},"github":{"type":"http","url":"https://api.githubcopilot.com/mcp/","headers":{"Authorization":"Bearer ${GITHUB_PAT:-}"}},"outro":{"command":"x"}}}\n' \
    > "$TEST_PROJECT/.mcp.json"
  run agent 'cmd_agent update'
  [ "$status" -eq 0 ]
  local file="$TEST_PROJECT/.mcp.json"
  grep -q '"dev-playwright"' "$file"
  grep -q '"dev-context7"' "$file"
  ! grep -q '"dev-browser"' "$file"
  ! grep -q '"dev-docs"' "$file"
  ! grep -q '"docs"' "$file"
  ! grep -q 'githubcopilot' "$file"
  grep -q '"github"' "$file"
  grep -q '"agent",' "$file"
  grep -q '"outro"' "$file"
  grep -q 'dev-playwright' "$(skill)"
  grep -q 'Repository: GitHub' "$(skill)"
}

@test "agent add --penpot guarda só as referências à chave e ao endereço" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=moodle
  run agent 'unset PENPOT_MCP_KEY; cmd_agent add --penpot'
  [ "$status" -eq 0 ]
  local file="$TEST_PROJECT/.mcp.json"
  grep -qF '"url": "${PENPOT_URL:-https://design.penpot.app}/mcp/stream?userToken=${PENPOT_MCP_KEY:-}"' "$file"
  grep -q '"type": "http"' "$file"
  [[ "$output" == *"Penpot: falta a chave do servidor MCP"*"dev agent key penpot"* ]]
  [[ "$output" == *"File → MCP Server → Connect"* ]]
  grep -q '### Design files: Penpot (`penpot`)' "$(skill)"
  ! grep -q '### Design files: Figma' "$(skill)"

  run agent 'unset PENPOT_MCP_KEY; config_set PENPOT_MCP_KEY pp-chave-unica-123; cmd_agent add --penpot'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Penpot: chave pp-chav…-123 em"* ]]
  [[ "$output" == *"abra um terminal novo"* ]]
  ! grep -rq 'pp-chave-unica-123' "$TEST_PROJECT"
}

@test "Figma e Penpot são alternativos" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=wordpress
  run agent 'cmd_agent add --figma --penpot'
  [ "$status" -ne 0 ]
  [[ "$output" == *"escolha uma ferramenta de design só"* ]]

  run agent 'cmd_agent add --figma; cmd_agent add --penpot'
  [ "$status" -eq 0 ]
  [[ "$output" == *"servidor figma removido"* ]]
  grep -q '"penpot"' "$TEST_PROJECT/.mcp.json"
  ! grep -q '"figma"' "$TEST_PROJECT/.mcp.json"
  ! grep -q 'Design files: Figma' "$(skill)"
}

@test "agent add --all --penpot troca o Figma pelo Penpot" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=laravel
  run agent 'cmd_agent add --all --penpot'
  [ "$status" -eq 0 ]
  local file="$TEST_PROJECT/.mcp.json" name
  for name in dev-playwright dev-context7 penpot github; do
    grep -q "\"$name\"" "$file"
  done
  ! grep -q '"figma"' "$file"
  grep -q '### Design files: Penpot' "$(skill)"
  [ -f "$TEST_PROJECT/.claude/skills/tlc-spec-driven/SKILL.md" ]
}

# ------------------------------------------------- impeccable, TLC e --all
@test "agent add --impeccable usa o instalador oficial e liga as regras de UI" {
  project_conf APP=moodle
  run agent 'cmd_agent add --impeccable'
  [ "$status" -eq 0 ]
  [[ "$output" == *"versão atual, não fixada pelo dev"* ]]
  [ -f "$TEST_PROJECT/.claude/skills/impeccable/SKILL.md" ]
  grep -q '### UI direction: impeccable' "$(skill)"
  [[ "$output" == *"/impeccable init"* ]]
  [ ! -e "$TEST_PROJECT/CLAUDE.md" ]
}

@test "agent add avisa quando o instalador oficial não deixa a skill no lugar" {
  project_conf APP=wordpress
  run agent 'agent_install_tlc() { :; }; cmd_agent add --tlc'
  [ "$status" -eq 0 ]
  [[ "$output" == *"não gerou a skill tlc-spec-driven"* ]]
  [ ! -e "$TEST_PROJECT/CLAUDE.md" ]
}

@test "os instaladores oficiais rodam fora do projeto e só a skill vem para ele" {
  project_conf APP=wordpress
  # O projeto fica dentro de outro repositório, como um ~/Code versionado.
  mkdir -p "$BATS_TEST_TMPDIR/.git"
  run agent '
    agent_install_impeccable() {
      [[ "$1" != "$PROJECT_DIR" && -d "$1/.git" ]] || return 1
      mkdir -p "$1/.claude/skills/impeccable/scripts" "$1/.claude/agents" "$1/.agents" "$1/.cursor"
      echo ui > "$1/.claude/skills/impeccable/SKILL.md"
      echo sub > "$1/.claude/agents/impeccable-documenter.md"
      echo x > "$1/.claude/skills/impeccable/scripts/impeccable"
      echo "{}" > "$1/.claude/settings.local.json"
      echo "{}" > "$1/.agents/.skill-lock.json"
    }
    cmd_agent add --impeccable'
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT/.claude/skills/impeccable/SKILL.md" ]
  [ -f "$TEST_PROJECT/.claude/skills/impeccable/scripts/impeccable" ]
  [ -f "$TEST_PROJECT/.claude/agents/impeccable-documenter.md" ]
  [ ! -e "$TEST_PROJECT/.claude/settings.local.json" ]
  [ ! -e "$TEST_PROJECT/.agents" ]
  [ ! -e "$TEST_PROJECT/.cursor" ]
  [ ! -e "$BATS_TEST_TMPDIR/.claude" ]
  [ ! -e "$BATS_TEST_TMPDIR/.agents" ]
}

@test "agent add --tlc instala o método e grava o bloco no CLAUDE.md" {
  project_conf APP=wordpress
  run agent 'cmd_agent add --tlc'
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT/.claude/skills/tlc-spec-driven/SKILL.md" ]
  grep -q '### Spec-driven method: TLC' "$(skill)"
  local claude="$TEST_PROJECT/CLAUDE.md"
  grep -qxF '<!-- >>> dev agent -->' "$claude"
  grep -q 'tlc-spec-driven' "$claude"
  grep -q 'load the `dev` skill' "$claude"
}

@test "o bloco do CLAUDE.md preserva o texto do usuário e o remove tira só o bloco" {
  project_conf APP=wordpress
  printf '# Meu projeto\n\nRegras minhas.\n' > "$TEST_PROJECT/CLAUDE.md"
  run agent 'cmd_agent add --tlc; cmd_agent update; cmd_agent add --tlc'
  [ "$status" -eq 0 ]
  local claude="$TEST_PROJECT/CLAUDE.md"
  grep -q 'Regras minhas.' "$claude"
  [ "$(grep -c '>>> dev agent' "$claude")" -eq 1 ]
  run agent 'cmd_agent remove'
  [ "$status" -eq 0 ]
  [ "$(cat "$claude")" = "$(printf '# Meu projeto\n\nRegras minhas.')" ]
  [[ "$output" == *"continua em .claude/skills/tlc-spec-driven"* ]]
  [ -d "$TEST_PROJECT/.claude/skills/tlc-spec-driven" ]
}

@test "o CLAUDE.md criado só para o bloco some no remove" {
  project_conf APP=wordpress
  run agent 'cmd_agent add --tlc; cmd_agent remove'
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_PROJECT/CLAUDE.md" ]
}

@test "agent update tira o bloco quando o método sai do projeto" {
  project_conf APP=wordpress
  run agent 'cmd_agent add --tlc'
  rm -rf "$TEST_PROJECT/.claude/skills/tlc-spec-driven"
  run agent 'cmd_agent update'
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_PROJECT/CLAUDE.md" ]
  ! grep -q 'Spec-driven method' "$(skill)"
}

@test "agent add --all liga todas as ferramentas e o TLC" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=moodle
  run agent 'unset GITHUB_PAT; cmd_agent add --all'
  [ "$status" -eq 0 ]
  local file="$TEST_PROJECT/.mcp.json" name
  for name in dev-playwright dev-context7 figma github; do
    grep -q "\"$name\"" "$file"
  done
  [ -f "$TEST_PROJECT/.claude/skills/impeccable/SKILL.md" ]
  [ -f "$TEST_PROJECT/.claude/skills/tlc-spec-driven/SKILL.md" ]
  grep -q '>>> dev agent' "$TEST_PROJECT/CLAUDE.md"
  local section
  for section in 'Spec-driven method: TLC' 'Documentation: Context7' 'Browser: Playwright' \
                 'Design files: Figma' 'Repository: GitHub' 'UI direction: impeccable'; do
    grep -q "### $section" "$(skill)"
  done
  ! grep -q '{{' "$(skill)"
  run agent 'cmd_agent remove'
  [ ! -e "$file" ]
  [ ! -e "$TEST_PROJECT/CLAUDE.md" ]
}

@test "agent add termina com os passos que dependem do usuário" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=wordpress
  run agent 'unset GITHUB_PAT CONTEXT7_API_KEY; cmd_agent add --all'
  [ "$status" -eq 0 ]
  [[ "$output" == *"PARA TERMINAR A CONFIGURAÇÃO"* ]]
  [[ "$output" == *"Context7 (opcional)"*"dev agent key context7"* ]]
  [[ "$output" == *"Figma: entre na sua conta"*"/mcp → figma → Authenticate"* ]]
  [[ "$output" == *"GitHub: falta o token"*"dev agent key github"* ]]
  [[ "$output" == *"impeccable: na primeira tela"* ]]
  [[ "$output" == *"Playwright: pronto"* ]]
}

@test "agent add sem ferramentas não mostra passos pendentes" {
  project_conf APP=wordpress
  run agent 'cmd_agent add'
  [ "$status" -eq 0 ]
  [[ "$output" != *"PARA TERMINAR A CONFIGURAÇÃO"* ]]
}

# ------------------------------------------------------- versão e notas
@test "a skill traz testes, usuário de teste e endereço de teste nas notas do Moodle" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=moodle DATABASE=test_site
  run agent 'cmd_agent add --playwright'
  local file; file="$(skill)"
  grep -q 'dev test user' "$file"
  grep -q 'dev test behat' "$file"
  grep -q 'https://test.test-site.localhost' "$file"
  grep -q 'Never use, read or reset the real administrator account' "$file"
  ! grep -q '{{' "$file"
}

@test "a skill traz a versão da aplicação e os IDs do Context7" {
  command -v node >/dev/null || skip "sem node"
  project_conf APP=laravel DATABASE=test_site
  local app="$TEST_PROJECT/vendor/laravel/framework/src/Illuminate/Foundation"
  mkdir -p "$app"
  printf "<?php\nclass Application {\n    const VERSION = '12.38.1';\n}\n" > "$app/Application.php"
  run agent 'cmd_agent add --context7'
  local file; file="$(skill)"
  grep -q 'Version: `12.38.1`' "$file"
  grep -q 'dev-context7' "$file"
  grep -q '/laravel/docs/<major>.x' "$file"
  ! grep -q '{{' "$file"
}

@test "a skill sem versão detectada pede para conferir no código" {
  project_conf APP=wordpress
  run agent 'cmd_agent add'
  local file; file="$(skill)"
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
