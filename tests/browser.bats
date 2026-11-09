#!/usr/bin/env bats
# Testes do navegador do dev: Chrome for Testing, chromedriver e Playwright MCP.

load helper

@test "o navegador e o MCP ficam no runtime do dev, nas versões fixadas" {
  run libraries '
    source "$DEV_ROOT/lib/browser.sh"
    chrome_bin; chromedriver_bin; playwright_mcp_cli
    url_for chrome; url_for chromedriver
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"$DEV_HOME/runtime/chrome/$CHROME_VERSION/chrome-linux64/chrome"* ]]
  [[ "$output" == *"chromedriver-linux64/chromedriver"* ]]
  [[ "$output" == *"playwright-mcp/$PLAYWRIGHT_MCP_VERSION/node_modules/@playwright/mcp/cli.js"* ]]
  [[ "$output" == *"chrome-for-testing-public/$CHROME_VERSION/linux64/chrome-linux64.zip"* ]]
  [[ "$output" == *"chrome-for-testing-public/$CHROME_VERSION/linux64/chromedriver-linux64.zip"* ]]
}

@test "o Chrome e o chromedriver têm sha256 fixado" {
  [[ "$CHROME_SHA256" =~ ^[0-9a-f]{64}$ ]]
  [[ "$CHROMEDRIVER_SHA256" =~ ^[0-9a-f]{64}$ ]]
}

@test "o MCP do agente só alcança o projeto, o endereço de teste e o Mailpit" {
  run libraries '
    source "$DEV_ROOT/lib/browser.sh"
    browser_mcp_args meu-site
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"--headless"* ]]
  [[ "$output" == *"--isolated"* ]]
  [[ "$output" == *"https://meu-site.localhost;https://test.meu-site.localhost;https://mail.localhost"* ]]
  [[ "$output" != *"--no-sandbox"* ]]
}

@test "BROWSER_NO_SANDBOX desliga o sandbox do Chrome no MCP e nos testes" {
  run libraries '
    source "$DEV_ROOT/lib/browser.sh"
    config_set BROWSER_NO_SANDBOX 1
    browser_mcp_args meu-site
    chrome_test_args
  '
  [ "$(grep -c -- '--no-sandbox' <<<"$output")" -eq 2 ]
}

@test "browser mcp não escreve nada na saída padrão quando falta o navegador" {
  mkdir -p "$DEV_HOME/sites"
  printf '%s\n' "$TEST_PROJECT" > "$DEV_HOME/sites/meu-site"
  run bash -c '"$1" browser mcp meu-site 2>/dev/null' _ "$ROOT/dev"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "as bibliotecas do Chrome preferem o nome t64 quando o apt o conhece" {
  printf '#!/bin/sh\ncase "$2" in libnss3|libgbm1) exit 0;; esac\nexit 1\n' > "$STUBS_BIN/dpkg"
  printf '#!/bin/sh\ncase "$2" in libasound2t64) exit 0;; esac\nexit 1\n' > "$STUBS_BIN/apt-cache"
  chmod +x "$STUBS_BIN/dpkg" "$STUBS_BIN/apt-cache"
  run libraries '
    source "$DEV_ROOT/lib/browser.sh"
    browser_apt_missing
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"libasound2t64"* ]]
  [[ "$output" != *"libnss3"* ]]
  [[ "$output" != *"libgbm1"* ]]
  [[ "$output" == *"libcups2"* ]]
}

@test "dev browser mostra o estado sem instalar nada" {
  run dev_cmd browser
  [ "$status" -eq 0 ]
  [[ "$output" == *"Chrome"*"$CHROME_VERSION"* ]]
  [[ "$output" == *"dev browser install"* || "$output" == *"browser install"* ]]
  [ ! -d "$DEV_HOME/runtime/chrome" ]
}

@test "o certificado e o vhost cobrem o endereço de teste do projeto" {
  mkdir -p "$DEV_HOME/sites"
  printf '%s\n' "$TEST_PROJECT" > "$DEV_HOME/sites/meu-site"
  run libraries '
    source "$DEV_ROOT/lib/certs.sh"
    served_hosts
  '
  [[ "$output" == *"meu-site.localhost"* ]]
  [[ "$output" == *"test.meu-site.localhost"* ]]
}
