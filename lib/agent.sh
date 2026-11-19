#!/usr/bin/env bash
# Claude Code no projeto. O "dev agent add" gera só a skill "dev" em
# .claude/skills/dev; cada ferramenta entra por uma flag com o nome dela:
#
#   --playwright  navegador restrito ao projeto   servidor dev-playwright (dev browser mcp)
#   --context7    documentação atualizada         servidor dev-context7   (dev context7 mcp)
#   --figma       arquivos de design              servidor remoto figma (OAuth)
#   --penpot      arquivos de design (alternativa) servidor remoto penpot (dev agent key penpot)
#   --github      issues, branches e PRs          servidor github         (dev agent mcp github)
#   --impeccable  direção de UI                   skill, pelo instalador oficial
#   --tlc         método spec-driven              skill, pelo instalador oficial, e bloco no CLAUDE.md
#   --all         todas as ferramentas, com o Figma e o TLC como padrões
#
# Figma e Penpot são alternativos, como os métodos: um por projeto. Com --all,
# --penpot troca o Figma pelo Penpot.
#
# A skill descreve só as ferramentas que estão no projeto: o dev as detecta no
# .mcp.json e nas pastas de skill, então "dev agent update" acompanha o que
# foi instalado ou tirado depois.
#
# As chaves (Context7 e GitHub) ficam em ~/.dev/config, gravadas com
# "dev agent key <ferramenta>"; o dev as entrega aos servidores que inicia.

# shellcheck source=lib/browser.sh
source "$DEV_ROOT/lib/browser.sh"
# shellcheck source=lib/context7.sh
source "$DEV_ROOT/lib/context7.sh"

AGENT_MARKER="generated-by: dev agent"
AGENT_SKILL_DIR=".claude/skills/dev"
AGENT_TOOLS=(playwright context7 figma penpot github impeccable)
AGENT_DESIGN_TOOLS=(figma penpot)
AGENT_METHODS=(tlc)
AGENT_FIGMA_URL="https://mcp.figma.com/mcp"
AGENT_GITHUB_URL="https://api.githubcopilot.com/mcp/"
# O Penpot hospedado é o padrão; um Penpot próprio entra por PENPOT_URL. A
# chave vai na URL, então o .mcp.json guarda só as referências às variáveis.
AGENT_PENPOT_KEY_VAR="PENPOT_MCP_KEY"
AGENT_PENPOT_DEFAULT_URL="https://design.penpot.app"
# shellcheck disable=SC2016
AGENT_PENPOT_URL='${PENPOT_URL:-'"$AGENT_PENPOT_DEFAULT_URL"'}/mcp/stream?userToken=${'"$AGENT_PENPOT_KEY_VAR"':-}'
AGENT_CLAUDE_BEGIN="<!-- >>> dev agent -->"
AGENT_CLAUDE_END="<!-- <<< dev agent -->"

agent_usage() {
  printf 'uso: %s add [--playwright] [--context7] [--figma|--penpot] [--github] [--impeccable] [--tlc] [--all] | remove | update | list | key\n' \
    "${DEV_COMMAND:-$DEV agent}"
}

cmd_agent() {
  local subcmd="${1:-list}"; shift || true
  case "$subcmd" in
    add)             agent_add "$@" ;;
    remove|rm)       agent_remove "$@" ;;
    update)          agent_update "$@" ;;
    list)            agent_list "$@" ;;
    key)             cmd_key "$@" ;;
    mcp)             agent_mcp_serve "$@" ;;
    *)               die "$(agent_usage)" ;;
  esac
}

agent_skill_file() { printf '%s\n' "$PROJECT_DIR/$AGENT_SKILL_DIR/SKILL.md"; }

agent_installed() {
  local file
  file="$(agent_skill_file)"
  [[ -f "$file" ]] && grep -q "$AGENT_MARKER" "$file"
}

# ------------------------------------------------------ ferramentas e métodos
agent_tool_title() {
  case "$1" in
    playwright) printf 'Playwright\n' ;;
    context7)   printf 'Context7\n' ;;
    figma)      printf 'Figma\n' ;;
    penpot)     printf 'Penpot\n' ;;
    github)     printf 'GitHub\n' ;;
    impeccable) printf 'impeccable\n' ;;
    tlc)        printf 'TLC Spec-Driven\n' ;;
    *)          return 1 ;;
  esac
}

# Nome da skill que o instalador oficial grava em .claude/skills.
agent_skill_name() {
  case "$1" in
    impeccable) printf 'impeccable\n' ;;
    tlc)        printf 'tlc-spec-driven\n' ;;
    *)          return 1 ;;
  esac
}

# A skill pode estar no projeto ou na instalação global do Claude Code.
agent_skill_present() {
  local name
  name="$(agent_skill_name "$1")" || return 1
  [[ -f "$PROJECT_DIR/.claude/skills/$name/SKILL.md" || -f "$HOME/.claude/skills/$name/SKILL.md" ]]
}

agent_tool_enabled() {
  case "$1" in
    playwright|context7|figma|penpot|github) agent_mcp_installed "$1" ;;
    impeccable|tlc)                   agent_skill_present "$1" ;;
    *)                                return 1 ;;
  esac
}

# Método spec-driven presente no projeto, se houver.
agent_method() {
  local method
  for method in "${AGENT_METHODS[@]}"; do
    agent_skill_present "$method" && { printf '%s\n' "$method"; return 0; }
  done
  return 1
}

# Os instaladores oficiais trazem sempre a versão atual: o dev não a fixa.
# Rodam sem perguntas, no diretório dado e sem terminal.
agent_npx() {
  local dir="$1" node; shift
  node="$(node_bin)" || die "o Node do dev não está instalado — rode $DEV install"
  export_node_env
  env -C "$dir" PATH="$(dirname "$node"):$PATH" "$(dirname "$node")/npx" -y "$@" </dev/null
}

agent_install_tlc() {
  agent_npx "$1" @tech-leads-club/agent-skills install -s tlc-spec-driven -a claude-code
}

# Sem hooks: o detector de design do impeccable rodaria a cada edição, em
# qualquer arquivo; a skill do dev diz quando usar cada comando.
agent_install_impeccable() {
  agent_npx "$1" impeccable install -y --providers=claude --project --no-hooks
}

# Os instaladores procuram a raiz do projeto subindo até um .git; num projeto
# dentro de outro repositório (um ~/Code versionado, por exemplo), gravariam
# no repositório de fora, e também para outros agentes. Por isso rodam numa
# pasta temporária marcada como raiz, e só a skill e os subagentes que ela
# traz (.claude/agents) vêm para o projeto.
agent_install_skill() {
  local tool="$1" title name stage target agent
  title="$(agent_tool_title "$tool")"
  name="$(agent_skill_name "$tool")"
  if agent_skill_present "$tool"; then
    ok "$title  já instalado"
    return 0
  fi
  stage="$(mktemp -d -p "${DEV_TMP:-/tmp}")"
  mkdir -p "$stage/.git"
  if ! with_progress "instalando o $title (instalador oficial, versão atual, não fixada pelo dev)" \
      "agent_install_$tool" "$stage"; then
    rm -rf "$stage"
    warn "o instalador do $title falhou"
    return 0
  fi
  if [[ -f "$stage/.claude/skills/$name/SKILL.md" ]]; then
    target="$PROJECT_DIR/.claude/skills/$name"
    mkdir -p "$(dirname "$target")"
    rm -rf "$target"
    cp -R "$stage/.claude/skills/$name" "$target"
    ok "$title  .claude/skills/$name"
    for agent in "$stage"/.claude/agents/*.md; do
      [[ -f "$agent" ]] || continue
      mkdir -p "$PROJECT_DIR/.claude/agents"
      cp "$agent" "$PROJECT_DIR/.claude/agents/"
      ok "$title  .claude/agents/$(basename "$agent")"
    done
  else
    warn "o instalador do $title não gerou a skill $name — confira a instalação"
  fi
  rm -rf "$stage"
}

# ------------------------------------------------------------ geração da skill
agent_app_title() {
  local title=""
  if [[ -n "$PROJECT_APP" ]] && load_recipe "$PROJECT_APP"; then
    title="$(recipe_title 2>/dev/null || true)"
  fi
  printf '%s\n' "${title:-${PROJECT_APP:-PHP}}"
}

# Versão instalada da aplicação, lida dos arquivos do projeto pela receita.
agent_app_version() {
  local version=""
  if [[ -n "$PROJECT_APP" ]] && load_recipe "$PROJECT_APP" && declare -F recipe_version >/dev/null; then
    version="$(recipe_version "$PROJECT_DIR" 2>/dev/null || true)"
  fi
  if [[ -n "$version" ]]; then
    printf '`%s`\n' "$version"
  else
    printf 'not detected (check it in the code)\n'
  fi
}

agent_app_notes() {
  local file
  [[ -n "$PROJECT_APP" ]] || return 0
  for file in "$DEV_PLUGINS/installed/$PROJECT_APP/agent.md" "$DEV_ROOT/plugins/$PROJECT_APP/agent.md"; do
    [[ -f "$file" ]] && { cat "$file"; return 0; }
  done
  return 0
}

# Seção de trabalho em fases: o método e as ferramentas presentes no projeto.
agent_tools_section() {
  local method="" tool parts=()
  method="$(agent_method || true)"
  [[ -n "$method" ]] && parts+=("$(cat "$DEV_ROOT/lib/agent/methods/$method.md")")
  for tool in "${AGENT_TOOLS[@]}"; do
    agent_tool_enabled "$tool" && parts+=("$(cat "$DEV_ROOT/lib/agent/tools/$tool.md")")
  done
  (( ${#parts[@]} > 0 )) || return 0
  printf '## Feature work\n\n'
  printf 'Work on a feature in phases: context, specify, design, tasks, execute, verify and deliver. The tools below are set up for this project; use each one in the phases it names.\n\n'
  local part
  for part in "${parts[@]}"; do
    printf '%s\n\n' "$part"
  done
}

agent_render() {
  local text notes tools
  text="$(cat "$DEV_ROOT/lib/agent/skill.md")"
  notes="$(agent_app_notes)"
  tools="$(agent_tools_section)"
  [[ -n "$tools" ]] && tools+=$'\n\n'
  # As notas e as ferramentas entram primeiro: elas também usam os marcadores.
  text="${text//\{\{TOOLS\}\}/$tools}"
  text="${text//\{\{APP_NOTES\}\}/$notes}"
  text="${text//\{\{PROJECT\}\}/$PROJECT_NAME}"
  text="${text//\{\{APP_TITLE\}\}/$(agent_app_title)}"
  text="${text//\{\{APP_VERSION\}\}/$(agent_app_version)}"
  text="${text//\{\{PHP\}\}/${PROJECT_PHP:-$(config_get DEFAULT_PHP)}}"
  text="${text//\{\{DATABASE\}\}/${PROJECT_DATABASE:-none}}"
  text="${text//\{\{DOCROOT\}\}/$PROJECT_DOCROOT}"
  text="${text//\{\{URL\}\}/$(site_url "$PROJECT_NAME")}"
  text="${text//\{\{TEST_URL\}\}/https://$(test_host "$PROJECT_NAME")}"
  printf '%s\n' "$text"
}

agent_write() {
  local file
  file="$(agent_skill_file)"
  if [[ -f "$file" ]] && ! grep -q "$AGENT_MARKER" "$file"; then
    warn "já existe $AGENT_SKILL_DIR/SKILL.md que não foi gerado pelo dev — mantido"
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  agent_render > "$file"
  ok "skill  $AGENT_SKILL_DIR/SKILL.md"
}

# ----------------------------------------------------------- bloco no CLAUDE.md
# Com um método spec-driven, o CLAUDE.md do projeto ganha um bloco marcado que
# manda o Claude Code carregar a skill do dev antes de cada fase. O resto do
# arquivo é do usuário e nunca é alterado.
agent_claude_file() { printf '%s\n' "$PROJECT_DIR/CLAUDE.md"; }

agent_claude_block() {
  local method="$1"
  printf '%s\n' "$AGENT_CLAUDE_BEGIN"
  printf '## Feature workflow\n\n'
  printf 'Specify and build features with the %s skill (`%s`). Before each phase, load the `dev` skill: it says how to run, test and inspect this project and which tools to use in each phase.\n' \
    "$(agent_tool_title "$method")" "$(agent_skill_name "$method")"
  printf '%s\n' "$AGENT_CLAUDE_END"
}

agent_claude_installed() { grep -qxF "$AGENT_CLAUDE_BEGIN" "$(agent_claude_file)" 2>/dev/null; }

# Tira o bloco do dev. As linhas em branco que o precedem e as do fim do
# arquivo saem junto; se não sobrar nada, o arquivo é apagado.
agent_claude_strip() {
  local file tmp
  file="$(agent_claude_file)"
  [[ -f "$file" ]] || return 0
  tmp="$(mktemp)"
  awk -v begin="$AGENT_CLAUDE_BEGIN" -v end="$AGENT_CLAUDE_END" '
    skip { if ($0 == end) skip = 0; next }
    $0 == begin { skip = 1; blanks = ""; next }
    /^[[:space:]]*$/ { blanks = blanks $0 "\n"; next }
    { printf "%s", blanks; blanks = ""; print }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
  grep -q '[^[:space:]]' "$file" || rm -f "$file"
}

# Grava ou troca o bloco do método; sem método, tira o bloco.
agent_claude_sync() {
  local method file existed=0 tmp
  file="$(agent_claude_file)"
  if ! method="$(agent_method)"; then
    if agent_claude_installed; then
      agent_claude_strip
      ok "CLAUDE.md  bloco do dev removido (nenhum método instalado)"
    fi
    return 0
  fi
  if [[ -f "$file" ]]; then
    existed=1
    agent_claude_installed && existed=2
  fi
  tmp="$(mktemp)"
  agent_claude_block "$method" > "$tmp"
  if (( existed == 2 )); then
    # Troca no lugar, para o bloco não mudar de posição no arquivo.
    local out
    out="$(mktemp)"
    awk -v begin="$AGENT_CLAUDE_BEGIN" -v end="$AGENT_CLAUDE_END" -v block="$tmp" '
      skip { if ($0 == end) skip = 0; next }
      $0 == begin { while ((getline line < block) > 0) print line; close(block); skip = 1; next }
      { print }
    ' "$file" > "$out"
    cat "$out" > "$file"
    rm -f "$out"
  elif (( existed == 1 )); then
    { printf '\n'; cat "$tmp"; } >> "$file"
  else
    cat "$tmp" > "$file"
  fi
  rm -f "$tmp"
  ok "CLAUDE.md  bloco do $(agent_tool_title "$method")"
}

# ----------------------------------------------------------------- comandos
agent_add() {
  require_project
  local tool method="" design="" all=0 want=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --playwright|--context7|--github|--impeccable)
        want+=("${1#--}") ;;
      --figma|--penpot)
        [[ -z "$design" || "$design" == "${1#--}" ]] \
          || die "escolha uma ferramenta de design só: --figma ou --penpot"
        design="${1#--}" ;;
      --tlc)
        [[ -z "$method" || "$method" == tlc ]] || die "escolha um método só"
        method=tlc ;;
      --all)
        all=1 ;;
      *)
        die "opção desconhecida: $1 ($(agent_usage))" ;;
    esac
    shift
  done
  if (( all )); then
    for tool in "${AGENT_TOOLS[@]}"; do
      [[ " ${AGENT_DESIGN_TOOLS[*]} " == *" $tool "* ]] || want+=("$tool")
    done
    [[ -n "$design" ]] || design=figma
    [[ -n "$method" ]] || method=tlc
  fi
  [[ -n "$design" ]] && want+=("$design")
  if [[ -n "$method" ]]; then
    local other
    other="$(agent_method || true)"
    [[ -z "$other" || "$other" == "$method" ]] \
      || die "o projeto já usa o método $(agent_tool_title "$other"); tire-o antes de instalar outro"
  fi

  if (( ${#want[@]} > 0 )) || [[ -n "$method" ]]; then
    step "FERRAMENTAS DO CLAUDE CODE"
    for tool in "${AGENT_TOOLS[@]}"; do
      [[ " ${want[*]} " == *" $tool "* ]] || continue
      case "$tool" in
        playwright)
          install_browser
          browser_install_deps || true
          install_playwright_mcp || die "a instalação do Playwright MCP falhou"
          agent_mcp_write playwright ;;
        context7)
          ensure_context7
          agent_mcp_write context7 ;;
        figma|penpot)
          agent_design_switch "$tool"
          agent_mcp_write "$tool" ;;
        github)
          install_mcp_remote || die "a instalação do mcp-remote falhou"
          agent_mcp_write github ;;
        impeccable)
          agent_install_skill impeccable ;;
      esac
    done
    [[ -n "$method" ]] && agent_install_skill "$method"
  fi

  step "SKILL DO DEV PARA O CLAUDE CODE"
  agent_write
  agent_claude_sync
  agent_pending
  blank
  hint "a skill descreve este projeto ($PROJECT_NAME); regenere após mudar o dev.conf, atualizar a aplicação ou instalar ferramentas: $DEV agent update"
  hint "pode versionar os arquivos no git; para não versionar, adicione-os ao .gitignore"
  blank
}

# Uma ferramenta de design por projeto: instalar uma tira o servidor da outra.
agent_design_switch() {
  local chosen="$1" other
  for other in "${AGENT_DESIGN_TOOLS[@]}"; do
    [[ "$other" != "$chosen" ]] && agent_mcp_installed "$other" || continue
    agent_mcp_remove "$other"
    ok "$(agent_tool_title "$other")  .mcp.json  servidor $(agent_mcp_name "$other") removido (o projeto usa uma ferramenta de design só)"
  done
}

# Passos que dependem do usuário, para cada ferramenta presente no projeto.
agent_pending() {
  local opened=0

  if agent_tool_enabled context7 && [[ -z "$(key_value context7)" ]]; then
    (( opened++ )) || step "PARA TERMINAR A CONFIGURAÇÃO"
    info "Context7 (opcional): sem chave, a documentação vem com limites de uso menores"
    hint "crie uma chave em $CONTEXT7_KEYS_URL e grave com: $DEV agent key context7"
  fi
  if agent_tool_enabled figma; then
    (( opened++ )) || step "PARA TERMINAR A CONFIGURAÇÃO"
    info "Figma: entre na sua conta uma vez, dentro do Claude Code"
    hint "abra o Claude Code neste projeto e aprove os servidores do .mcp.json"
    hint "rode /mcp → figma → Authenticate e autorize no navegador"
  fi
  if agent_tool_enabled penpot; then
    (( opened++ )) || step "PARA TERMINAR A CONFIGURAÇÃO"
    local penpot_key
    penpot_key="$(key_value penpot)"
    if [[ -n "$penpot_key" ]]; then
      ok "Penpot: chave $(key_masked "$penpot_key") em $(key_source penpot)"
      [[ -n "${!AGENT_PENPOT_KEY_VAR:-}" ]] \
        || hint "abra um terminal novo (ou rode: source ~/.bashrc) antes de abrir o Claude Code"
    else
      warn "Penpot: falta a chave do servidor MCP"
      hint "gere em $PENPOT_KEYS_PLACE: ligue o Status e gere a chave (ela aparece uma vez só)"
      hint "grave com: $DEV agent key penpot"
      hint "num Penpot próprio, exporte também PENPOT_URL=https://<seu-penpot>   (o padrão é $AGENT_PENPOT_DEFAULT_URL)"
    fi
    info "Penpot: o servidor só funciona com o plugin conectado no navegador"
    hint "abra um arquivo de design no Penpot, use File → MCP Server → Connect e deixe a aba aberta"
  fi
  if agent_tool_enabled github; then
    (( opened++ )) || step "PARA TERMINAR A CONFIGURAÇÃO"
    local token
    token="$(key_value github)"
    if [[ -n "$token" ]]; then
      ok "GitHub: token $(key_masked "$token") em $(key_source github)"
    else
      warn "GitHub: falta o token"
      hint "crie um token fine-grained em $GITHUB_KEYS_URL"
      hint "  acesso aos repositórios do projeto; Contents, Issues e Pull requests em Read and write"
      hint "grave com: $DEV agent key github   (se o Claude Code já estiver aberto, reconecte em /mcp)"
    fi
  fi
  if agent_tool_enabled impeccable && [[ ! -f "$PROJECT_DIR/PRODUCT.md" ]]; then
    (( opened++ )) || step "PARA TERMINAR A CONFIGURAÇÃO"
    info "impeccable: na primeira tela, o Claude Code roda /impeccable init e pergunta sobre o produto"
    hint "para adiantar, rode /impeccable init no Claude Code (gera o PRODUCT.md)"
  fi
  if agent_tool_enabled playwright; then
    (( opened++ )) || step "PARA TERMINAR A CONFIGURAÇÃO"
    ok "Playwright: pronto; o navegador só alcança $(site_url "$PROJECT_NAME"), https://$(test_host "$PROJECT_NAME") e o Mailpit"
  fi
  return 0
}

agent_remove() {
  require_project
  [[ $# -eq 0 ]] || die "uso: ${DEV_COMMAND:-$DEV agent} remove"
  if ! agent_installed; then
    info "nenhuma skill do dev instalada neste projeto"
    return 0
  fi

  step "REMOVENDO SKILL DO DEV"
  local kind dir
  for kind in "${AGENT_MCP_KINDS[@]}"; do
    agent_mcp_remove "$kind"
  done
  agent_claude_strip
  dir="$PROJECT_DIR/$AGENT_SKILL_DIR"
  rm -f "$dir/SKILL.md"
  rmdir "$dir" 2>/dev/null || true
  rmdir "$(dirname "$dir")" 2>/dev/null || true
  rmdir "$(dirname "$(dirname "$dir")")" 2>/dev/null || true
  ok "skill, servidores MCP e bloco do CLAUDE.md gerados pelo dev removidos"
  local tool name
  for tool in impeccable "${AGENT_METHODS[@]}"; do
    name="$(agent_skill_name "$tool")"
    [[ -d "$PROJECT_DIR/.claude/skills/$name" ]] || continue
    if compgen -G "$PROJECT_DIR/.claude/agents/$name-*.md" >/dev/null; then
      hint "o $(agent_tool_title "$tool") veio do instalador oficial e continua em .claude/skills/$name e .claude/agents/$name-*.md; apague-os se não o quiser mais"
    else
      hint "o $(agent_tool_title "$tool") veio do instalador oficial e continua em .claude/skills/$name; apague a pasta se não o quiser mais"
    fi
  done
  blank
}

agent_update() {
  require_project
  step "ATUALIZANDO SKILL DO DEV"
  if ! agent_installed; then
    info "nenhuma skill do dev instalada — use: $DEV agent add"
    blank
    return 0
  fi
  # Servidores gravados no formato antigo (dev-browser, dev-docs, "dev docs
  # mcp", o github remoto com token em variável) passam para o atual.
  local kind
  for kind in "${AGENT_MCP_KINDS[@]}"; do
    agent_mcp_legacy "$kind" && agent_mcp_write "$kind"
  done
  agent_write
  agent_claude_sync
  blank
}

agent_list() {
  require_project
  step "CLAUDE CODE NESTE PROJETO"
  local tool
  agent_list_row "skill dev" "$AGENT_SKILL_DIR/SKILL.md" "$(agent_installed && echo 1)"
  for tool in "${AGENT_METHODS[@]}" "${AGENT_TOOLS[@]}"; do
    agent_list_row "$(agent_tool_title "$tool")" "$(agent_tool_where "$tool")" "$(agent_tool_enabled "$tool" && echo 1)"
  done
  blank
  hint "$(agent_usage)"
  blank
}

agent_list_row() {
  local label="$1" where="$2" on="$3" mark status_label
  if [[ -n "$on" ]]; then
    mark="${C_GREEN}✔${C_RESET}"; status_label="${C_GREEN}instalado${C_RESET}"
  else
    mark="${C_DIM}○${C_RESET}"; status_label="${C_DIM}disponível${C_RESET}"
  fi
  printf '  %b  %-16s %-34s %b\n' "$mark" "$label" "$where" "$status_label"
}

agent_tool_where() {
  case "$1" in
    playwright|context7|figma|penpot|github) printf '.mcp.json  %s\n' "$(agent_mcp_name "$1")" ;;
    *)                                printf '.claude/skills/%s\n' "$(agent_skill_name "$1")" ;;
  esac
}

# ------------------------------------------------- servidores MCP do Claude
# Playwright, Context7 e GitHub são iniciados pelo próprio comando dev; Figma e
# Penpot são remotos. Nenhum leva caminho da máquina nem segredo, então o
# .mcp.json pode ir para o git.

AGENT_MCP_KINDS=(playwright context7 figma penpot github)

agent_mcp_name() {
  case "$1" in
    playwright) printf 'dev-playwright\n' ;;
    context7)   printf 'dev-context7\n' ;;
    figma)      printf 'figma\n' ;;
    penpot)     printf 'penpot\n' ;;
    github)     printf 'github\n' ;;
    *)          return 1 ;;
  esac
}

# Nomes usados antes de as flags seguirem o nome das ferramentas.
agent_mcp_legacy_name() {
  case "$1" in
    playwright) printf 'dev-browser\n' ;;
    context7)   printf 'dev-docs\n' ;;
    *)          printf '\n' ;;
  esac
}

# Formatos antigos de uma entrada do dev, um por linha: "args <a> <b>" para
# os primeiros argumentos de um servidor stdio, "url <url>" para um remoto.
agent_mcp_legacy_forms() {
  case "$1" in
    context7) printf 'args docs mcp\n' ;;
    github)   printf 'url %s\n' "$AGENT_GITHUB_URL" ;;
  esac
  return 0
}

# Configuração do servidor, um campo por linha: "stdio", o comando e os
# argumentos; ou "http", a URL e, se houver, o cabeçalho Authorization.
agent_mcp_spec() {
  case "$1" in
    playwright) printf '%s\n' stdio "$(agent_dev_command)" browser mcp "$PROJECT_NAME" ;;
    context7)   printf '%s\n' stdio "$(agent_dev_command)" context7 mcp ;;
    figma)      printf '%s\n' http "$AGENT_FIGMA_URL" ;;
    penpot)     printf '%s\n' http "$AGENT_PENPOT_URL" ;;
    github)     printf '%s\n' stdio "$(agent_dev_command)" agent mcp github ;;
    *)          return 1 ;;
  esac
}

# O comando dev como o Claude Code o encontra: pelo nome, se estiver no PATH.
agent_dev_command() {
  if [[ "$(readlink -f "$(command -v dev 2>/dev/null)" 2>/dev/null || true)" == "$DEV_ROOT/dev" ]]; then
    printf 'dev\n'
  else
    printf '%s\n' "$DEV_ROOT/dev"
  fi
}

agent_node() {
  node_bin 2>/dev/null || command -v node 2>/dev/null || return 1
}

agent_mcp_json_file() { printf '%s\n' "$PROJECT_DIR/.mcp.json"; }

# Trecho para acrescentar à mão quando o dev não consegue editar o arquivo.
agent_mcp_snippet() {
  local spec=() name entry list="" arg
  mapfile -t spec < <(agent_mcp_spec "$1")
  name="$(agent_mcp_name "$1")"
  if [[ "${spec[0]}" == stdio ]]; then
    for arg in "${spec[@]:2}"; do list+="${list:+, }\"$arg\""; done
    entry="{ \"command\": \"${spec[1]}\", \"args\": [$list] }"
  elif [[ -n "${spec[2]:-}" ]]; then
    entry="{ \"type\": \"http\", \"url\": \"${spec[1]}\", \"headers\": { \"Authorization\": \"${spec[2]}\" } }"
  else
    entry="{ \"type\": \"http\", \"url\": \"${spec[1]}\" }"
  fi
  printf '{ "mcpServers": { "%s": %s } }\n' "$name" "$entry"
}

# Acrescenta, troca, confere ou tira a entrada do dev no .mcp.json,
# preservando as outras. JSON inválido não é tocado. A entrada é do dev quando
# os argumentos começam por "<comando do dev> mcp" (stdio) ou quando a URL é a
# do servidor (http). A entrada com o nome antigo sai quando a nova entra.
#   saída: 0 ok · 1 ausente (has) · 2 sem Node · 3 JSON inválido · 4 servidor alheio
agent_mcp_json() {
  local action="$1" kind="$2" file node spec=()
  file="$(agent_mcp_json_file)"
  node="$(agent_node)" || return 2
  mapfile -t spec < <(agent_mcp_spec "$kind")
  AGENT_MCP_LEGACY="$(agent_mcp_legacy_forms "$kind")" "$node" -e '
    const fs = require("fs");
    const [action, file, name, legacy, mode, ...rest] = process.argv.slice(1);
    let expected;
    if (mode === "stdio") {
      const [command, ...args] = rest;
      expected = { command, args };
    } else {
      const [url, auth] = rest;
      expected = { type: "http", url };
      if (auth) expected.headers = { Authorization: auth };
    }
    // "dev agent mcp <ferramenta>" identifica o servidor pelo terceiro argumento.
    const width = mode === "stdio" && expected.args[0] === "agent" ? 3 : 2;
    const current = (e) => !!e && (mode === "stdio"
      ? Array.isArray(e.args) && expected.args.slice(0, width).every((a, i) => e.args[i] === a)
      : e.url === expected.url);
    const forms = (process.env.AGENT_MCP_LEGACY || "").split("\n").filter(Boolean).map((l) => l.split(" "));
    const old = (e) => !!e && !current(e) && forms.some(([kind, ...v]) => kind === "url"
      ? e.url === v[0]
      : Array.isArray(e.args) && v.every((a, i) => e.args[i] === a));
    const ours = (e) => current(e) || old(e);
    let data = {};
    if (fs.existsSync(file)) {
      try { data = JSON.parse(fs.readFileSync(file, "utf8")); } catch (e) { process.exit(3); }
    }
    const servers = data.mcpServers || {};
    if (action === "has") process.exit(ours(servers[name]) || (legacy && ours(servers[legacy])) ? 0 : 1);
    if (action === "legacy") process.exit(old(servers[name]) || (legacy && ours(servers[legacy])) ? 0 : 1);
    let changed = false;
    if (legacy && ours(servers[legacy])) { delete servers[legacy]; changed = true; }
    if (action === "add") {
      if (servers[name] && !ours(servers[name])) process.exit(4);
      servers[name] = expected;
      changed = true;
    } else if (ours(servers[name])) {
      delete servers[name];
      changed = true;
    }
    if (!changed) process.exit(0);
    if (Object.keys(servers).length === 0) delete data.mcpServers; else data.mcpServers = servers;
    if (Object.keys(data).length === 0) { fs.unlinkSync(file); process.exit(0); }
    fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n");
  ' "$action" "$file" "$(agent_mcp_name "$kind")" "$(agent_mcp_legacy_name "$kind")" "${spec[@]}"
}

agent_mcp_installed() {
  [[ -f "$(agent_mcp_json_file)" ]] && agent_mcp_json has "$1" >/dev/null 2>&1
}

agent_mcp_legacy() {
  [[ -f "$(agent_mcp_json_file)" ]] && agent_mcp_json legacy "$1" >/dev/null 2>&1
}

# ------------------------------------------- servidores remotos pelo dev
# O GitHub é remoto, mas o Claude Code o alcança por "dev agent mcp github": o
# dev lê o token gravado e o repassa ao mcp-remote (versão fixada), que faz a
# ponte entre o stdio do Claude Code e o servidor HTTP. O token vai por
# variável de ambiente, nunca pela linha de comando.

mcp_remote_prefix()    { printf '%s\n' "$DEV_RUNTIME/mcp-remote/$MCP_REMOTE_VERSION"; }
mcp_remote_cli()       { printf '%s\n' "$(mcp_remote_prefix)/node_modules/mcp-remote/dist/proxy.js"; }
mcp_remote_installed() { [[ -f "$(mcp_remote_cli)" ]]; }

install_mcp_remote() {
  if mcp_remote_installed; then
    ok "mcp-remote $MCP_REMOTE_VERSION  já instalado"
    return 0
  fi
  local node prefix
  node="$(node_bin)" || die "o Node do dev não está instalado — rode $DEV install"
  prefix="$(mcp_remote_prefix)"
  mkdir -p "$prefix"
  # --ignore-scripts: nenhum script de instalação de terceiros roda na máquina.
  if ! with_progress "instalando o mcp-remote $MCP_REMOTE_VERSION" \
      env PATH="$(dirname "$node"):$PATH" \
      "$(dirname "$node")/npm" install --prefix "$prefix" --ignore-scripts \
      --no-audit --no-fund --save-exact "mcp-remote@$MCP_REMOTE_VERSION"; then
    rm -rf "$prefix"
    return 1
  fi
}

# Ponto de entrada do servidor, chamado pelo Claude Code. A saída padrão
# pertence ao protocolo MCP: nenhuma mensagem pode ir para ela.
agent_mcp_serve() {
  local tool="${1:-}" node token
  [[ "$tool" == github ]] || die "uso: ${DEV_COMMAND:-$DEV agent} mcp github"
  token="$(key_value github)"
  [[ -n "$token" ]] || die "sem token do GitHub — grave com: $DEV agent key github"
  mcp_remote_installed || die "o mcp-remote do dev não está instalado — rode: $DEV agent add --github"
  node="$(node_bin)" || die "o Node do dev não está instalado — rode $DEV install"
  export_node_env
  rm -rf "$DEV_TMP"
  mkdir -p "$DEV_HOME/mcp-remote"
  # shellcheck disable=SC2016
  exec env DEV_GITHUB_AUTHORIZATION="Bearer $token" MCP_REMOTE_CONFIG_DIR="$DEV_HOME/mcp-remote" \
    "$node" "$(mcp_remote_cli)" "$AGENT_GITHUB_URL" \
    --header 'Authorization:${DEV_GITHUB_AUTHORIZATION}' --transport http-only
}

agent_mcp_write() {
  local kind="$1" name rc=0
  name="$(agent_mcp_name "$kind")"
  agent_mcp_json add "$kind" || rc=$?
  case "$rc" in
    0) ok "$(agent_tool_title "$kind")  .mcp.json  servidor $name" ;;
    2) warn "sem Node para editar o .mcp.json — acrescente à mão:"
       agent_mcp_snippet "$kind" | sed 's/^/     /' ;;
    3) warn "o .mcp.json não é JSON válido — mantido; acrescente à mão:"
       agent_mcp_snippet "$kind" | sed 's/^/     /' ;;
    4) warn "o .mcp.json já tem um servidor $name que não é do dev — mantido" ;;
    *) warn "não consegui editar o .mcp.json" ;;
  esac
}

agent_mcp_remove() {
  [[ -f "$(agent_mcp_json_file)" ]] || return 0
  agent_mcp_json remove "$1" >/dev/null 2>&1 || true
}
