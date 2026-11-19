#!/usr/bin/env bash
# Navegador gerenciado pelo dev: Chrome for Testing, chromedriver e o servidor
# MCP do Playwright. Atende as suítes de teste de navegador (Behat, Dusk) e dá
# ao Claude Code um navegador restrito aos endereços do projeto.
#
# Tudo é opcional e fica em ~/.dev/runtime; nada vai para o projeto.

# shellcheck source=lib/project.sh
source "$DEV_ROOT/lib/project.sh"

# Bibliotecas que o Chrome pede (lista do deb.deps do próprio Chrome for Testing,
# sem as que o core já instala).
BROWSER_APT_DEPS=(
  fonts-liberation libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0
  libcairo2 libcups2 libdbus-1-3 libgbm1 libglib2.0-0 libgtk-3-0 libnspr4
  libnss3 libpango-1.0-0 libxcomposite1 libxdamage1 libxkbcommon0 libxrandr2
)

cmd_browser() {
  local subcmd="${1:-status}"; shift || true
  case "$subcmd" in
    status)     browser_status ;;
    install)    browser_install_all ;;
    remove|rm)  browser_remove ;;
    mcp)        browser_mcp "$@" ;;
    *)          die "uso: ${DEV_COMMAND:-$DEV browser} [status|install|remove]" ;;
  esac
}

browser_prefix()        { printf '%s\n' "$DEV_RUNTIME/chrome/$CHROME_VERSION"; }
chrome_bin()            { printf '%s\n' "$(browser_prefix)/chrome-linux64/chrome"; }
chromedriver_bin()      { printf '%s\n' "$(browser_prefix)/chromedriver-linux64/chromedriver"; }
playwright_mcp_prefix() { printf '%s\n' "$DEV_RUNTIME/playwright-mcp/$PLAYWRIGHT_MCP_VERSION"; }
playwright_mcp_cli()    { printf '%s\n' "$(playwright_mcp_prefix)/node_modules/@playwright/mcp/cli.js"; }

browser_installed()        { [[ -x "$(chrome_bin)" && -x "$(chromedriver_bin)" ]]; }
playwright_mcp_installed() { [[ -f "$(playwright_mcp_cli)" ]]; }

# O sandbox do Chrome depende de namespaces de usuário. Onde o sistema os
# bloqueia, BROWSER_NO_SANDBOX=1 em ~/.dev/config desliga o sandbox.
browser_no_sandbox() { [[ "$(config_get BROWSER_NO_SANDBOX)" == "1" ]]; }

# Argumentos do Chrome nos testes, um por linha.
chrome_test_args() {
  printf '%s\n' --headless=new --disable-gpu --window-size=1366,900 --disable-dev-shm-usage
  browser_no_sandbox && printf '%s\n' --no-sandbox
  return 0
}

# ------------------------------------------------------------------ instalação
# Pacotes do apt que o Chrome pede e faltam. No Ubuntu 24.04 em diante várias
# bibliotecas ganharam o sufixo t64; qualquer uma das duas serve.
browser_apt_missing() {
  local package
  for package in "${BROWSER_APT_DEPS[@]}"; do
    dpkg -s "$package" >/dev/null 2>&1 && continue
    dpkg -s "${package}t64" >/dev/null 2>&1 && continue
    if apt-cache show "${package}t64" >/dev/null 2>&1; then
      printf '%s\n' "${package}t64"
    else
      printf '%s\n' "$package"
    fi
  done
}

browser_install_deps() {
  local missing=()
  mapfile -t missing < <(browser_apt_missing)
  if [[ ${#missing[@]} -eq 0 || -z "${missing[0]:-}" ]]; then
    ok "bibliotecas do navegador  já instaladas"
    return 0
  fi
  warn "o Chrome precisa de ${#missing[@]} pacote(s) do sistema"
  hint "sudo apt install ${missing[*]}"
  if ! confirm "instalar no sistema?" s; then
    warn "sem esses pacotes o Chrome não abre"
    return 1
  fi
  sudo apt-get update && sudo apt-get install -y "${missing[@]}"
}

install_browser() {
  if browser_installed; then
    ok "Chrome for Testing $CHROME_VERSION  já instalado"
    return 0
  fi
  require_command unzip
  local prefix component zip sha
  prefix="$(browser_prefix)"
  mkdir -p "$prefix"
  for component in chrome chromedriver; do
    sha="CHROME_SHA256"
    [[ "$component" == chromedriver ]] && sha="CHROMEDRIVER_SHA256"
    zip="$(download "$(url_for "$component")" "$(cache_name "$component")" "${!sha}")"
    if ! unzip -q -o "$zip" -d "$prefix"; then
      rm -rf "$prefix"
      die "não consegui extrair $component"
    fi
  done
  ok "Chrome for Testing $CHROME_VERSION  com chromedriver"
}

install_playwright_mcp() {
  if playwright_mcp_installed; then
    ok "Playwright MCP $PLAYWRIGHT_MCP_VERSION  já instalado"
    return 0
  fi
  local node prefix
  node="$(node_bin)" || die "o Node do dev não está instalado — rode $DEV install"
  prefix="$(playwright_mcp_prefix)"
  mkdir -p "$prefix"
  # --ignore-scripts: nenhum script de instalação de terceiros roda na máquina.
  # O Playwright também não baixa navegador próprio; usa o Chrome acima.
  if ! with_progress "instalando o Playwright MCP $PLAYWRIGHT_MCP_VERSION" \
      env PATH="$(dirname "$node"):$PATH" PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
      "$(dirname "$node")/npm" install --prefix "$prefix" --ignore-scripts \
      --no-audit --no-fund --save-exact "@playwright/mcp@$PLAYWRIGHT_MCP_VERSION"; then
    rm -rf "$prefix"
    return 1
  fi
}

# Garante o navegador antes de uma suíte de teste; pergunta antes de baixar.
ensure_browser() {
  browser_installed && return 0
  info "esta suíte usa o navegador do dev (Chrome for Testing $CHROME_VERSION, ~200 MB)"
  confirm "baixar e instalar agora?" s \
    || die "sem navegador não dá para rodar — instale com: $DEV browser install"
  install_browser
  browser_install_deps || die "faltam bibliotecas do sistema para o Chrome"
}

browser_install_all() {
  ensure_tree
  step "NAVEGADOR DO DEV"
  install_browser
  browser_install_deps || true
  install_playwright_mcp || die "a instalação do Playwright MCP falhou"
  blank
  hint "suítes de navegador: $DEV test      Claude Code com navegador: $DEV agent add --playwright"
  blank
}

browser_remove() {
  step "REMOVENDO O NAVEGADOR DO DEV"
  stop_chromedriver
  rm -rf "$DEV_RUNTIME/chrome" "$DEV_RUNTIME/playwright-mcp" "$DEV_CACHE/browser"
  ok "Chrome for Testing e Playwright MCP removidos"
  hint "as configurações de MCP nos projetos continuam; tire com: $DEV agent remove"
  blank
}

browser_status() {
  step "NAVEGADOR DO DEV"
  local mark
  if browser_installed; then mark="${C_GREEN}✔${C_RESET}"; else mark="${C_DIM}○${C_RESET}"; fi
  printf '  %b  %-16s %s\n' "$mark" "Chrome" "for Testing $CHROME_VERSION"
  printf '  %b  %-16s %s\n' "$mark" "chromedriver" "porta $CHROMEDRIVER_PORT, só durante os testes"
  if playwright_mcp_installed; then mark="${C_GREEN}✔${C_RESET}"; else mark="${C_DIM}○${C_RESET}"; fi
  printf '  %b  %-16s %s\n' "$mark" "Playwright MCP" "$PLAYWRIGHT_MCP_VERSION  navegador do Claude Code"
  blank
  if ! browser_installed || ! playwright_mcp_installed; then
    hint "instale com: $DEV browser install"
  else
    local missing=()
    mapfile -t missing < <(browser_apt_missing)
    if [[ ${#missing[@]} -gt 0 && -n "${missing[0]:-}" ]]; then
      warn "faltam bibliotecas do sistema: ${missing[*]}"
      hint "$DEV browser install   oferece instalar"
    fi
  fi
  blank
}

# ---------------------------------------------------------------- chromedriver
chromedriver_pid_file() { printf '%s\n' "$DEV_RUN/chromedriver.pid"; }

chromedriver_url() { printf 'http://127.0.0.1:%s\n' "$CHROMEDRIVER_PORT"; }

chromedriver_running() {
  local pid
  pid="$(cat "$(chromedriver_pid_file)" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

start_chromedriver() {
  chromedriver_running && return 0
  browser_installed || die "o navegador não está instalado — rode: $DEV browser install"
  mkdir -p "$DEV_RUN" "$DEV_LOG"
  nohup "$(chromedriver_bin)" --port="$CHROMEDRIVER_PORT" \
    >"$DEV_LOG/chromedriver.log" 2>&1 &
  echo $! > "$(chromedriver_pid_file)"
  local i=0
  while (( i < 100 )); do
    curl -fs --max-time 1 "$(chromedriver_url)/status" >/dev/null 2>&1 && return 0
    chromedriver_running || break
    sleep 0.1
    i=$(( i + 1 ))
  done
  stop_chromedriver
  die "o chromedriver não subiu na porta $CHROMEDRIVER_PORT — veja $DEV_LOG/chromedriver.log"
}

stop_chromedriver() {
  local file pid
  file="$(chromedriver_pid_file)"
  pid="$(cat "$file" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  rm -f "$file"
}

# ---------------------------------------------------------- MCP para o agente
# Origens que o navegador do agente pode visitar: o site, o endereço de teste e
# o Mailpit. Fora delas, o Playwright recusa as requisições.
browser_allowed_origins() {
  local name="$1"
  printf 'https://%s.localhost;https://%s;https://mail.localhost\n' "$name" "$(test_host "$name")"
}

# Argumentos do servidor MCP, um por linha. Sem estado em disco (--isolated),
# sem janela (--headless) e com o Chrome fixado pelo dev.
browser_mcp_args() {
  local name="$1"
  printf '%s\n' \
    --executable-path "$(chrome_bin)" \
    --headless \
    --isolated \
    --allowed-origins "$(browser_allowed_origins "$name")" \
    --output-dir "$DEV_CACHE/browser/$name" \
    --viewport-size 1366x900
  browser_no_sandbox && printf '%s\n' --no-sandbox
  return 0
}

# Ponto de entrada do servidor MCP, chamado pelo agente pelo comando
# "dev browser mcp <projeto>". A saída padrão pertence ao protocolo MCP:
# nenhuma mensagem pode ir para ela.
browser_mcp() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    load_project >/dev/null 2>&1 || die "uso: $DEV browser mcp <projeto>"
    name="$PROJECT_NAME"
  fi
  site_exists "$name" || die "não há projeto chamado \"$name\" — veja $DEV sites"
  browser_installed && playwright_mcp_installed \
    || die "o navegador do dev não está instalado — rode: $DEV browser install"
  local node args=()
  node="$(node_bin)" || die "o Node do dev não está instalado — rode $DEV install"
  mapfile -t args < <(browser_mcp_args "$name")
  mkdir -p "$DEV_CACHE/browser/$name"
  export_node_env
  rm -rf "$DEV_TMP"
  exec "$node" "$(playwright_mcp_cli)" "${args[@]}"
}
