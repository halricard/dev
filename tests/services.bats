#!/usr/bin/env bats
# Testes da biblioteca lib/services.sh.

load helper

@test "pid_file devolve caminho sob DEV_RUN" {
  run libraries 'source "$DEV_ROOT/lib/services.sh" && pid_file mysql'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "$DEV_HOME/services/run/mysql.pid" ]]
}

@test "running identifica processo vivo e morto" {
  run libraries '
    source "$DEV_ROOT/lib/services.sh"
    mkdir -p "$DEV_RUN"
    echo 999999 > "$(pid_file teste)"
    running teste
  '
  [[ "$status" -ne 0 ]]

  run libraries '
    source "$DEV_ROOT/lib/services.sh"
    mkdir -p "$DEV_RUN"
    sleep 5 &
    pid=$!
    echo "$pid" > "$(pid_file sleep_test)"
    running sleep_test && kill "$pid"
  '
  [[ "$status" -eq 0 ]]
}

@test "stack_ports lista as cinco portas da pilha" {
  run libraries 'source "$DEV_ROOT/lib/services.sh" && stack_ports'
  [[ "$status" -eq 0 ]]
  local count
  count="$(printf '%s\n' "$output" | wc -l)"
  [[ "$count" -eq 5 ]]
}

@test "service_of_port mapeia portas aos serviços" {
  run libraries '
    source "$DEV_ROOT/lib/services.sh"
    printf "%s|%s|%s\n" \
      "$(service_of_port "$HTTP_PORT")" \
      "$(service_of_port "$MYSQL_PORT")" \
      "$(service_of_port "$SMTP_PORT")"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "nginx|mysql|mailpit" ]]
}
