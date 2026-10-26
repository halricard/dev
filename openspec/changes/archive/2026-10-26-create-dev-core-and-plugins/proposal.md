# Proposal

## Why

Atualmente existem duas ferramentas irmãs no ecossistema pessoal de desenvolvimento: o `devsh` (que suporta WordPress, Moodle e Laravel, compilando runtimes do PHP e do nginx na máquina e misturando tudo no mesmo repositório monolítico) e o `wdev` (uma evolução arquitetural madura focada exclusivamente em WordPress, com runtimes pré-compilados/estáticos, gerenciamento robusto de portas e processos, rigor nos testes e regras estritas de convenção).

O objetivo deste projeto é criar o **`dev`**: uma nova ferramenta unificada de linha de comando (`dev`), adotando a engenharia de alta performance, portabilidade e convenções modernas do `wdev`, mas com um núcleo limpo focado exclusivamente nas linguagens e serviços básicos (PHP, Node.js/JavaScript, nginx, MySQL, Mailpit, Adminer, mkcert), enquanto o suporte a aplicações específicas (WordPress, Laravel, Moodle) é totalmente desacoplado e implementado através de uma arquitetura modular de plugins incrementais.

## What Changes

- **Novo utilitário CLI `dev`**: Despachante executável com convenção de código em inglês e interface/mensagens/documentação em português brasileiro (herdando a política do `wdev`).
- **Core de Ambiente e Serviços**:
  - Instalação e execução de runtimes e servidores sem Docker e sem compilação local durante o `install`.
  - Provedor de runtime pré-compilado/estático para PHP e nginx, binário minimal oficial do MySQL 8.4, Node.js LTS, Composer, Mailpit, Adminer e mkcert.
  - Sandbox isolado em `~/.dev` (cache em `~/.cache/dev`), com controle seguro de portas (`port_owner`: own, stack, user, alien, free) e sem dependência de systemd para execução dos processos de desenvolvimento.
  - Comandos de ambiente: `dev install`, `start`, `stop`, `restart`, `status`, `fix`, `doctor`, `versions`, `uninstall`.
- **Ciclo de Vida de Projetos**:
  - Gerenciamento unificado de sites via `dev.conf`: `dev up`, `down`, `init`, `destroy`, `sites`, `exec`, `shell`, `logs`, `errors`, `schedule`, `worker`, `track`, `untrack`, `clean`, `snapshot`, `restore`, `db query/export/import`, `open`, `autostart`.
  - Suporte nativo a projetos em PHP puro sem exigir nenhum plugin de aplicação.
- **Arquitetura de Plugins de Aplicações**:
  - Desacoplamento total de aplicações do core do `dev`. Ferramentas específicas (como WP-CLI ou instalador do Laravel) não são instaladas durante o core `dev install`.
  - Comandos de gerenciamento de plugins: `dev plugin list`, `dev plugin install <nome>`, `dev plugin remove <nome>`, `dev plugin status [nome]`.
  - Interface padronizada de receitas (`recipe hooks`) inspirada nas funções do `devsh` e portadas para os padrões do `wdev` (`recipe_title`, `recipe_docroot`, `recipe_php`, `recipe_ask`, `recipe_install`, `recipe_restore`, `recipe_next_steps`, `recipe_change_password`, `recipe_has_user`, `recipe_identity`, `recipe_gitignore`, `recipe_schedule`, `recipe_workers`).
  - Três plugins oficiais iniciais:
    - `wordpress`: Baixa WP-CLI sob demanda na instalação do plugin, instala e configura WordPress com wp-config seguro, `wp-cron` e suporte a banco MySQL.
    - `laravel`: Baixa `laravel-installer` sob demanda, suporte a MySQL e SQLite, migrações automáticas, workers de fila (`queue:listen`), Vite (`npm run dev`) e agendamento (`schedule:run`).
    - `moodle`: Suporta download e extração das versões/branches do Moodle, isolamento do diretório `data/` fora do docroot, instalação via CLI `admin/cli/install_database.php`, supressão de depreciações no PHP e agendamento de cron (`cron.php`).
- **Garantia de Qualidade e Governança**:
  - Portão rigoroso com `tools/check.sh` (sintaxe, variáveis locais auto-referenciadas, pipelines com guarda sob `pipefail`, identificadores proibidos, permissões de execução).
  - Testes automatizados via `bats-core` em `tests/` com isolamento completo de sandbox e variáveis temporárias.

## Capabilities

### New Capabilities
- `environment-core`: Núcleo do ambiente de desenvolvimento, provendo runtimes estáticos (PHP, nginx), serviços de infraestrutura (MySQL, Node.js, Composer, Mailpit, Adminer, mkcert), despacho de comandos CLI e supervisão de processos/portas no sandbox `~/.dev`.
- `project-lifecycle`: Gerenciamento do ciclo de vida de projetos individuais (`dev.conf`), orquestração de virtual hosts no nginx, execução de comandos isolados (`exec`/`shell`), agendador, supervisão de workers, snapshots e ferramentas de banco de dados.
- `application-plugins`: Mecanismo modular de plugins para aplicações, gerenciador do ciclo de vida dos plugins (`dev plugin ...`), contrato de hooks de receitas e catálogo oficial inicial (WordPress, Laravel e Moodle).

### Modified Capabilities
*(Nenhuma capacidade existente modificada; projeto greenfield)*

## Impact

- **Código**: Greenfield no diretório `/home/dell/Code/dev`. Estruturação inicial completa inspirada no layout de diretórios do `wdev` (`dev`, `versions.sh`, `lib/`, `plugins/`, `runtimes/`, `tests/`, `tools/`).
- **Compatibilidade de Máquina**: Compatível com WSL2 (Ubuntu/Debian x86_64) e Linux nativo.
- **Convivência de Portas**: Portas padrão idênticas aos projetos anteriores (HTTP 80, HTTPS 443, MySQL 13306, SMTP 11025, Mailpit UI 18025), com mecanismo inteligente de detecção de outra pilha e liberação com `take_over_ports` ou flag `-f`.
- **Independência**: O `wdev` e o `devsh` existentes permanecem intactos nos seus diretórios e sandboxes (`~/.wdev` e `~/.devsh`), sem qualquer interferência mútua.
