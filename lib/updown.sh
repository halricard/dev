#!/usr/bin/env bash
# up e down: orquestração do projeto no ar e fora dele.

# shellcheck source=lib/project.sh
source "$DEV_ROOT/lib/project.sh"

up_marker() { printf '%s\n' "$DEV_UP/$1"; }

cmd_up() {
  require_project
  source "$DEV_ROOT/lib/services.sh"
  source "$DEV_ROOT/lib/config.sh"
  if [[ -f "$DEV_ROOT/lib/schedule.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/schedule.sh"
  fi

  mkdir -p "$DEV_UP"
  : > "$(up_marker "$PROJECT_NAME")"

  cmd_start --if-needed

  step "UP  $PROJECT_NAME"
  bring_up

  if [[ -f "$DEV_ROOT/lib/workers.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/workers.sh"
    local raised
    raised="$(start_site_tasks "$PROJECT_NAME" "$PROJECT_DIR" "$PROJECT_PHP" worker 2>/dev/null || true)"
    if [[ -n "$raised" && "$raised" -gt 0 ]] 2>/dev/null; then
      ok "$raised worker(s) de pé"
      hint "$DEV worker   mostra o estado dos workers"
    fi
  fi
  hint "$DEV down     tira do ar — arquivos e banco continuam"
  blank
}

cmd_down() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    require_project
    name="$PROJECT_NAME"
  fi
  if ! site_exists "$name"; then
    rm -f "$(up_marker "$name")"
    info "$name não está no ar"
    return 0
  fi

  step "DOWN  $name"
  take_down "$name"
  ok "$name fora do ar — site, agenda e workers parados"
  hint "arquivos e banco continuam; $DEV up põe de volta"
  hint "para apagar tudo: $DEV destroy $name"
  blank
}
