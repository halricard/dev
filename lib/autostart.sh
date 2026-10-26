#!/usr/bin/env bash
# Sobe a pilha de serviços do dev no boot do sistema ou no shell interativo.

UNIT_NAME="dev.service"
UNIT_FILE="$HOME/.config/systemd/user/$UNIT_NAME"
PROFILE_FILE="$HOME/.bashrc"
PROFILE_START="# >>> dev autostart >>>"
PROFILE_END="# <<< dev autostart <<<"

has_systemd() {
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl --user is-system-running >/dev/null 2>&1
}

has_linger() {
  [[ "$(loginctl show-user "$USER" --property=Linger 2>/dev/null)" == "Linger=yes" ]]
}

write_unit() {
  mkdir -p "$(dirname "$UNIT_FILE")"
  cat > "$UNIT_FILE" <<UNIT
# Gerado por dev autostart. Remova com: dev autostart off

[Unit]
Description=dev — ambiente de desenvolvimento PHP e Node.js
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$DEV_ROOT/dev start
ExecStop=$DEV_ROOT/dev stop

[Install]
WantedBy=default.target
UNIT
}

write_profile_line() {
  remove_profile_line
  cat >> "$PROFILE_FILE" <<PROFILE
$PROFILE_START
[[ \$- == *i* ]] && "$DEV_ROOT/dev" start --if-needed
$PROFILE_END
PROFILE
}

remove_profile_line() {
  [[ -f "$PROFILE_FILE" ]] || return 0
  grep -qF "$PROFILE_START" "$PROFILE_FILE" || return 0
  local tmp="$DEV_TMP/profile"
  mkdir -p "$DEV_TMP"
  awk -v a="$PROFILE_START" -v b="$PROFILE_END" '
    $0 == a { inside = 1; next }
    $0 == b { inside = 0; next }
    !inside' "$PROFILE_FILE" > "$tmp"
  cat "$tmp" > "$PROFILE_FILE"
  rm -f "$tmp"
}

profile_active() {
  [[ -f "$PROFILE_FILE" ]] && grep -qF "$PROFILE_START" "$PROFILE_FILE"
}

unit_active() {
  [[ -f "$UNIT_FILE" ]] && [[ "$(systemctl --user is-enabled "$UNIT_NAME" 2>/dev/null)" == "enabled" ]]
}

cmd_autostart() {
  case "${1:-status}" in
    on)     autostart_on ;;
    off)    autostart_off ;;
    status) autostart_status ;;
    *)      die "use: ${DEV_COMMAND:-$DEV autostart} on | off | status" ;;
  esac
}

autostart_on() {
  [[ -d "$DEV_RUNTIME" ]] || die "nada instalado ainda — rode $DEV install"
  step "INÍCIO AUTOMÁTICO"

  if has_systemd; then
    write_unit
    systemctl --user daemon-reload
    systemctl --user enable "$UNIT_NAME" >/dev/null 2>&1 \
      || die "o systemd recusou a unit — veja: systemctl --user status $UNIT_NAME"
    ok "ativado pelo systemd"
    info "$UNIT_FILE"
    if has_linger; then
      ok "sobe no boot, sem precisar abrir terminal"
    else
      warn "sobe quando você abrir o primeiro terminal, não no boot"
      hint "sudo loginctl enable-linger $USER   corrige isso"
    fi
  else
    write_profile_line
    ok "ativado pelo $PROFILE_FILE"
    info "sobe no primeiro terminal que você abrir"
    is_wsl && hint "systemd=true em /etc/wsl.conf faz subir no boot; depois rode isto de novo"
  fi
  blank
}

autostart_off() {
  step "INÍCIO AUTOMÁTICO"
  local touched=0

  if [[ -f "$UNIT_FILE" ]]; then
    has_systemd && systemctl --user disable "$UNIT_NAME" >/dev/null 2>&1 || true
    rm -f "$UNIT_FILE"
    has_systemd && systemctl --user daemon-reload || true
    ok "unit do systemd removida"; touched=1
  fi
  if profile_active; then
    remove_profile_line
    ok "linha removida do $PROFILE_FILE"; touched=1
  fi

  (( touched )) || info "já estava desativado"
  hint "o que está no ar continua no ar — $DEV stop derruba"
  blank
}

autostart_status() {
  step "INÍCIO AUTOMÁTICO"
  if unit_active; then
    ok "ativado pelo systemd"
    info "$UNIT_FILE"
    has_linger && ok "sobe no boot" || warn "sobe no primeiro terminal — falta o linger"
    has_linger || hint "sudo loginctl enable-linger $USER"
  elif [[ -f "$UNIT_FILE" ]]; then
    warn "a unit existe mas não está habilitada"
    hint "$DEV autostart on"
  elif profile_active; then
    ok "ativado pelo $PROFILE_FILE"
    info "sobe no primeiro terminal que você abrir"
  else
    info "desativado"
    hint "$DEV autostart on"
  fi
  blank
}
