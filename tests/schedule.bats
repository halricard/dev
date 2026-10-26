#!/usr/bin/env bats
# Testes de tarefas agendadas (dev.schedule) e workers contínuos (dev.workers).

load helper

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export DEV_HOME="$BATS_TEST_TMPDIR/sandbox"
  export DEV_CACHE="$BATS_TEST_TMPDIR/cache"
  export NO_COLOR=1
  unset DEV_YES
  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$HOME" "$DEV_HOME" "$TEST_PROJECT" "$DEV_HOME/sites" "$DEV_HOME/services/run" "$DEV_HOME/run"
  STUBS_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUBS_BIN"
  export PATH="$STUBS_BIN:$PATH"

  source "$ROOT/lib/common.sh"
  config_set DEFAULT_PHP "8.5.11"
}

@test "cadence formata segundos, minutos e horas" {
  libraries '
    source "$DEV_ROOT/lib/schedule.sh"
    [ "$(cadence 15)" = "15s" ]
    [ "$(cadence 60)" = "1min" ]
    [ "$(cadence 120)" = "2min" ]
    [ "$(cadence 3600)" = "1h" ]
    [ "$(cadence 7200)" = "2h" ]
  '
}

@test "lines_of_kind ignora linhas vazias e comentários em dev.schedule e dev.workers" {
  cat > "$TEST_PROJECT/dev.schedule" << 'EOF'
# Comentário
60 echo oi

  # Outro comentário
300 php worker.php
EOF

  cat > "$TEST_PROJECT/dev.workers" << 'EOF'
# Worker
queue:work
EOF

  libraries '
    source "$DEV_ROOT/lib/schedule.sh"
    schedule_lines="$(lines_of_kind "'"$TEST_PROJECT"'" schedule | wc -l)"
    [ "$schedule_lines" -eq 2 ]

    worker_lines="$(lines_of_kind "'"$TEST_PROJECT"'" worker | wc -l)"
    [ "$worker_lines" -eq 1 ]
  '
}

@test "start_site_tasks e stop_site_tasks gerenciam ciclo de vida de tarefas" {
  cat > "$TEST_PROJECT/dev.schedule" << 'EOF'
1 echo "tick"
EOF

  project_conf APP="" PHP="8.5.11" DOCROOT="." DATABASE=""

  libraries '
    source "$DEV_ROOT/lib/schedule.sh"
    count="$(start_site_tasks "site-teste" "'"$TEST_PROJECT"'" "8.5.11" schedule)"
    [ "$count" -eq 1 ]
    [ -f "$DEV_RUN/schedule-site-teste-1.pid" ]
    pid="$(cat "$DEV_RUN/schedule-site-teste-1.pid")"
    kill -0 "$pid"

    # Espera a tarefa rodar e gravar em .runs
    sleep 1.2
    [ -f "$DEV_RUN/schedule-site-teste-1.runs" ]

    stop_site_tasks "site-teste" schedule
    [ ! -f "$DEV_RUN/schedule-site-teste-1.pid" ]
  '
}

@test "cmd_schedule e cmd_worker listam tarefas configuradas do projeto" {
  printf '%s\n' "$TEST_PROJECT" > "$DEV_HOME/sites/meu-app"
  cat > "$TEST_PROJECT/dev.schedule" << 'EOF'
60 echo teste
EOF
  cat > "$TEST_PROJECT/dev.workers" << 'EOF'
echo worker-loop
EOF

  run libraries '
    source "$DEV_ROOT/lib/schedule.sh"
    cmd_schedule meu-app
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"AGENDAMENTOS · meu-app"* ]]
  [[ "$output" == *"meu-app · echo teste"* ]]
  [[ "$output" == *"a cada 1min"* ]]

  run libraries '
    source "$DEV_ROOT/lib/workers.sh"
    cmd_worker meu-app
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"WORKERS · meu-app"* ]]
  [[ "$output" == *"meu-app · echo worker-loop"* ]]
}
