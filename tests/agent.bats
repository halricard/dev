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
