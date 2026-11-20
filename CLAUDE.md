# CLAUDE.md

Guia para manutenção e desenvolvimento deste repositório.

## Idioma

O repositório adota **português brasileiro na prosa e inglês nos nomes**. Essa divisão é um contrato rigoroso:

| Em inglês | Em português |
|---|---|
| Comandos, subcomandos e flags (`install`, `start`, `plugin install`) | Comentários no código |
| Nomes de arquivo e diretório (`lib/plugins.sh`, `plugins/laravel/`) | `README.md`, `USERGUIDE.html`, `CLAUDE.md` |
| Nomes de função, variável e variável de ambiente (`start_mysql`, `DEV_HOME`) | Mensagens de saída (`ok`, `warn`, `bad`, `info`, `hint`, `step`, `die`) |
| Chaves e nomes de artefatos gerados (`dev.conf`, `dev.schedule`, `dev.workers`, pool `[dev]`, `dev.service`) | Telas de ajuda (`usage()`), dicas e mensagens de erro |

Funções novas devem se chamar, por exemplo, `load_project`, não `carregar_projeto`. Variáveis de configuração usam `DEFAULT_PHP`, não `PHP_PADRAO`.

## Verificação e Portão de Qualidade

O portão de entrada para qualquer alteração é o script `tools/check.sh`, que executa:
1. Validação de sintaxe (`bash -n`).
2. Detecção de variáveis locais auto-referenciadas.
3. Detecção de pipelines sem guarda sob `pipefail`.
4. Validação de ausência de crases na ajuda.
5. Permissões de bit de execução nos scripts.
6. Ausência de artefatos temporários no repositório.
7. Validação de identificadores proibidos (`tools/banned-identifiers.txt`).
8. Análise estática com `shellcheck`.
9. Bateria completa de testes automatizados com bats (`tools/test.sh`).

Para rodar as validações:
```bash
./tools/check.sh                     # Portão completo
./tools/test.sh                      # Apenas suíte de testes BATS
./tools/test.sh tests/commands.bats  # Teste de um arquivo específico
```

## Arquitetura

O comando principal se chama `dev`.
- `dev` é o despachante principal que carrega bibliotecas modulares em `lib/` e despacha subcomandos.
- `lib/common.sh`: base com caminhos `DEV_*`, utilitários de saída e leitura de `dev.conf`.
- `lib/plugins.sh`: gerenciador do catálogo e ciclo de vida de plugins em `plugins/`.
- `plugins/<app>/`: plugins de aplicação contendo `plugin.sh` (ferramentas e ciclo de vida), `recipe.sh` (scaffolding e hooks de projeto) e `agent.md` (notas em inglês da aplicação para a skill de agentes).
- `lib/agent.sh` e `lib/agent/skill.md`: `dev agent add` gera só a skill do Claude Code no projeto (`.claude/skills/dev/SKILL.md`); cada ferramenta entra por uma flag com o nome dela (`--playwright`, `--context7`, `--figma` ou `--penpot`, `--github`, `--impeccable`, `--tlc`, `--all`). Os servidores MCP vão para o `.mcp.json`, o TLC e o impeccable vêm dos instaladores oficiais, e o método spec-driven grava um bloco marcado no `CLAUDE.md` do projeto. A skill inclui só as ferramentas detectadas no projeto: os textos de cada uma ficam em `lib/agent/tools/` e os dos métodos em `lib/agent/methods/`. O dev atende só o Claude Code. O conteúdo da skill é em inglês, lido pelo Claude Code. O `.gitignore` leva para o git o que é do time (`.mcp.json`, `.claude/`, `CLAUDE.md`, `.specs/`) e deixa de fora o pessoal (`.claude/settings.local.json`, `CLAUDE.local.md`) e o binário do impeccable, que cada máquina baixa: as receitas já o escrevem assim, e o `agent_gitignore` completa um `.gitignore` antigo. Num clone, o `dev agent update` instala nesta máquina o que o `.mcp.json` pede (`agent_machine_install`) e o `dev up` avisa o que falta (`agent_machine_hint`).
- `lib/test.sh`: `dev test` lista, prepara e roda as suítes que cada receita declara (`recipe_test_suites`, `recipe_test_ready`, `recipe_test_init`, `recipe_test_run`) e cria o usuário de teste temporário (`recipe_test_user_create`, `recipe_test_user_remove`), apagado no `dev down`.
- `lib/browser.sh`: `dev browser` instala o Chrome for Testing com chromedriver (sha256 fixado em `versions.sh`) e o Playwright MCP; `dev browser mcp <projeto>` é o servidor MCP que o `dev agent add --playwright` configura (servidor `dev-playwright`), restrito a `https://<projeto>.localhost`, `https://test.<projeto>.localhost` e ao Mailpit.
- `lib/context7.sh`: `dev context7` instala o Context7 MCP (versão fixada em `versions.sh`); `dev context7 mcp` é o servidor que o `dev agent add --context7` configura (servidor `dev-context7`), com a chave só por variável de ambiente.
- `lib/keys.sh`: `dev agent key <ferramenta>` grava em `~/.dev/config` a chave do Context7 (`CONTEXT7_API_KEY`), o token do GitHub (`GITHUB_PAT`) e a chave do Penpot (`PENPOT_MCP_KEY`, que um bloco marcado no `~/.bashrc` lê a cada terminal, porque o Claude Code a usa direto na URL do servidor); `dev agent mcp github` leva o token ao servidor remoto do GitHub pelo `mcp-remote` (versão fixada em `versions.sh`). A receita informa a versão instalada da aplicação (`recipe_version`) e o `agent.md` lista os IDs do Context7.
- `lib/pin.sh`: `dev pin` grava no `dev.conf` a versão instalada da aplicação (`WORDPRESS_VERSION`, `MOODLE_VERSION` e, numa build semanal do Moodle, `MOODLE_COMMIT`), pelas funções `recipe_pin` e `recipe_pin_key` da receita; o `dev new` e o `dev up` gravam sozinhos quando falta. O `dev up` de um clone sem o núcleo baixa a versão fixada. O Laravel não tem chave: quem fixa é o `composer.lock`.
- Todo projeto responde também em `https://test.<projeto>.localhost`, o endereço das suítes que exigem um site separado (Behat).
- Estado em `~/.dev`, cache de download em `~/.cache/dev`.
