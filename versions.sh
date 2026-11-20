#!/usr/bin/env bash
# Versões fixadas. Este arquivo vai para o git e garante que todo o time
# execute exatamente o mesmo ambiente.
#
# O PHP e o nginx vêm pré-compilados de runtimes/manifest.sh com sha256 fixado.
# Este arquivo fixa os binários oficiais baixados e portas padrão.

DEV_VERSION="0.1.0-dev"

# Binários oficiais e ferramentas utilitárias
MYSQL_VERSION="8.4.9"        # LTS; https://dev.mysql.com/downloads/mysql/
NODE_VERSION="24.22.1"       # linha LTS; https://nodejs.org/dist/
COMPOSER_VERSION="2.10.3"    # https://getcomposer.org/download/
MAILPIT_VERSION="1.31.3"     # https://github.com/axllent/mailpit/releases
ADMINER_VERSION="6.1.1"      # https://github.com/vrana/adminer/releases
MKCERT_VERSION="1.4.4"       # https://github.com/FiloSottile/mkcert/releases

# Versões de ferramentas e instaladores usados pelos plugins
WPCLI_VERSION="2.12.0"       # Plugin WordPress; https://github.com/wp-cli/wp-cli/releases
# A versão do WordPress e a do Moodle são de cada projeto: o dev new e o dev up
# as gravam no dev.conf (WORDPRESS_VERSION, MOODLE_VERSION e MOODLE_COMMIT).
MOODLE_BRANCH="503"          # Branch dos projetos Moodle novos (Moodle 5.3)
LARAVEL_INSTALLER="5.32.0"   # Plugin Laravel; instalador oficial via Composer

# Navegador de testes e do Claude Code, instalado sob demanda (dev browser install).
# O Chrome for Testing não publica sha256; os valores abaixo foram conferidos no download.
CHROME_VERSION="157.0.8103.38"   # https://googlechromelabs.github.io/chrome-for-testing/
CHROME_SHA256="8cdeb344e9b2cefe59f4aea8d1d93d5d93054c03cde217665c16fc1f62e72a66"
CHROMEDRIVER_SHA256="329525fa0bf02be19794de1e9475772ef64695e0456f142888bd70df3147dc1e"
PLAYWRIGHT_MCP_VERSION="0.0.83"  # https://www.npmjs.com/package/@playwright/mcp

# Servidores MCP do Claude Code, instalados sob demanda (dev context7 install, dev agent add).
CONTEXT7_MCP_VERSION="4.4.4"     # https://www.npmjs.com/package/@upstash/context7-mcp
MCP_REMOTE_VERSION="0.16.6"      # https://www.npmjs.com/package/mcp-remote (ponte para o GitHub MCP)

# Portas padrão.
# Portas altas para serviços auxiliares evitam colisão com instâncias do sistema.
HTTP_PORT="80"
HTTPS_PORT="443"
MYSQL_PORT="13306"
SMTP_PORT="11025"
MAILPIT_UI_PORT="18025"
CHROMEDRIVER_PORT="14444"
