# Tasks

## 1. Fundação e Infraestrutura de Qualidade

- [x] 1.1 Criar estrutura inicial do repositório (`dev`, `versions.sh`, `CLAUDE.md`, `README.md`) e ferramentas de portão (`tools/check.sh`, `tools/test.sh`, `tools/banned-identifiers.txt`); verificar executando `./tools/check.sh`
- [x] 1.2 Configurar ambiente de testes BATS (`tests/helper.bash`, `tests/commands.bats`) cobrindo `usage()` e despacho inicial de subcomandos; verificar com `./tools/test.sh`
- [x] 1.3 Configurar catálogo de runtimes pré-compilados em `runtimes/` (`manifest.sh`, `SHA256SUMS`, arquivos estáticos de PHP e nginx derivados do `wdev`); verificar integridade com `tools/check.sh`

## 2. Core de Ambiente e Serviços

- [x] 2.1 Implementar `lib/common.sh` com caminhos `DEV_*`, utilitários de saída (`ok`, `warn`, `bad`, `die`), detecção de plataforma (WSL2/Linux) e parsing de `dev.conf`; verificar executando testes de biblioteca BATS
- [x] 2.2 Implementar `lib/releases.sh` e `lib/runtime.sh` para download em cache e validação de integridade dos componentes; verificar com teste unitário de resolução de URLs
- [x] 2.3 Implementar `lib/services.sh` com supervisão de processos sem systemd, detecção de donos de porta (`port_owner`: own, stack, user, alien, free) e encerramento gracioso (`take_over_ports`); verificar com testes BATS simulando ocupação de portas
- [x] 2.4 Implementar `lib/certs.sh` e `lib/config.sh` gerando autoridade local mkcert, certificados SSL, `nginx.conf`, pool PHP-FPM e configurações do MySQL/Adminer; verificar sintaxe dos arquivos de configuração gerados
- [x] 2.5 Implementar `lib/install.sh` (`dev install` com suporte a `--plan`, `dev uninstall`) e despachante em `dev` com comandos de ambiente (`start`, `stop`, `restart`, `status`, `fix`, `doctor`, `versions`); verificar executando `dev install --plan`

## 3. Gerenciamento do Ciclo de Vida de Projetos

- [x] 3.1 Implementar `lib/project.sh` e `lib/updown.sh` com `write_project_conf`, `detect_docroot`, `dev up`, `dev down`, `dev init`, `dev destroy`, e `dev sites`; verificar com teste BATS criando e desmontando projeto PHP puro
- [x] 3.2 Implementar `dev exec` e `dev shell` garantindo montagem de PATH isolado com PHP, Node e Composer do projeto; verificar executando comando via `dev exec` em sandbox simulado
- [x] 3.3 Implementar `lib/schedule.sh` e `lib/workers.sh` para supervisão de tarefas recorrentes (`dev.schedule`) e processos contínuos (`dev.workers`); verificar ciclo de execução e logs em teste BATS
- [x] 3.4 Implementar `lib/snapshot.sh` (`dev snapshot`, `dev restore`, `dev db query/export/import`), `lib/logs.sh`, `lib/errors.sh`, `lib/clean.sh`, `lib/track.sh`, `lib/passwd.sh`, e `lib/autostart.sh`; verificar subcomandos em testes BATS

## 4. Arquitetura e Gerenciador de Plugins

- [x] 4.1 Implementar `lib/plugins.sh` com subcomandos `dev plugin list`, `dev plugin install <name>`, `dev plugin remove <name>` e registro de estado em `~/.dev/plugins/installed/`; verificar com teste unitário BATS simulando instalação e remoção de plugin
- [x] 4.2 Definir a interface contratual de hooks de receitas (`recipe_*`), carregamento dinâmico e limpeza de funções (`unload_recipe`); verificar isolamento de funções em teste de troca de receita
- [x] 4.3 Integrar o comando `dev new <app> <site>` com o gerenciador de plugins, exigindo plugin ativo e repassando o scaffolding para a receita; verificar mensagem de bloqueio quando o plugin não está instalado

## 5. Implementação dos Plugins Oficiais (WordPress, Laravel, Moodle)

- [x] 5.1 Implementar plugin `plugins/wordpress` (`plugin.sh` para download de WP-CLI sob demanda e `recipe.sh` com scaffolding, salts, MySQL e `wp-cron`); verificar criação e restauração simuladas em teste BATS
- [x] 5.2 Implementar plugin `plugins/laravel` (`plugin.sh` com provisionamento do `laravel-installer` via Composer e `recipe.sh` com suporte MySQL/SQLite, `.env`, migrações, workers de fila, Vite e cron); verificar fluxo em teste BATS
- [x] 5.3 Implementar plugin `plugins/moodle` (`plugin.sh` com verificação de requisitos e `recipe.sh` com layout `app/` e `data/`, instalação via CLI Moodle, supressão de deprecations e cron); verificar integridade da receita em teste BATS

## 6. Verificação Final e Documentação

- [x] 6.1 Elaborar `USERGUIDE.html` e atualizar `README.md` documentando arquitetura, tabela de comandos práticos do dia a dia, fluxo rápido de cada aplicação (Moodle, Laravel e WordPress) e catálogo de plugins; verificar paridade com `usage()` via `tests/commands.bats`
- [x] 6.2 Executar suíte completa `./tools/check.sh` garantindo ausência de erros no shellcheck, respeito às armadilhas bash, conformidade de identificadores e todos os testes BATS verdes
