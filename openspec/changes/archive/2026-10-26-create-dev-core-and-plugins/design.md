# Design

## Context

O projeto `dev` unifica a robustez, velocidade e disciplina de engenharia do `wdev` com a flexibilidade de múltiplas aplicações do `devsh`. No `devsh`, a compilação do PHP a partir do código-fonte levava dezenas de minutos e acoplava WordPress, Laravel e Moodle no mesmo código. No `wdev`, os runtimes pré-compilados eliminaram a compilação local, reduzindo a instalação para minutos, com verificações rigorosas (`tools/check.sh`), testes automatizados (`bats-core`), gerenciamento inteligente de portas (`port_owner`) e contrato linguístico estrito (código em inglês, mensagens e documentação em português).

O `dev` nasce como um projeto greenfield em `/home/dell/Code/dev`, mantendo `~/.dev` como sandbox e `~/.cache/dev` como cache de downloads.

## Goals / Non-Goals

**Goals:**
- Construir o despachante executável `dev` e bibliotecas modulares em `lib/` seguindo as boas práticas consolidadas do `wdev`.
- Prover um **core enxuto** no `dev install` contendo apenas ferramentas essenciais para PHP e JavaScript/Node.js: runtimes estáticos (PHP, nginx), MySQL 8.4 LTS, Node.js LTS, Composer, Mailpit, Adminer e mkcert.
- Implementar uma **arquitetura de plugins de aplicação**:
  - Comandos: `dev plugin list`, `dev plugin install <name>`, `dev plugin remove <name>`, `dev plugin status [name]`.
  - Plugins embutidos no repositório em `plugins/<app>/`: `wordpress`, `laravel`, `moodle`.
  - Ferramentas específicas (WP-CLI, `laravel-installer`) são baixadas e configuradas sob demanda apenas na instalação do respectivo plugin.
- Portar e adaptar a receita do WordPress do `wdev` para o formato de plugin.
- Portar e adaptar as receitas do Laravel e do Moodle do `devsh` para o formato de plugin, respeitando o contrato de código em inglês e as melhorias de isolamento.
- Implementar todo o ciclo de vida do projeto (`up`, `down`, `init`, `destroy`, `exec`, `shell`, `schedule`, `worker`, `snapshot`, `db`, `logs`, `errors`, `clean`, `passwd`).
- Estabelecer a infraestrutura de qualidade: `tools/check.sh`, `tools/test.sh`, `tests/` com testes em bats e `tools/banned-identifiers.txt`.

**Non-Goals:**
- Compilação local de PHP ou MySQL no comando de instalação (uso de runtimes pré-compilados/estáticos).
- Suporte a Docker, containers ou orquestração via systemd.
- Instalação de ferramentas de aplicação no core base do `dev`.
- Suporte a sistemas fora do escopo Debian/Ubuntu x86_64 e WSL2.

## Decisions

### 1. Estrutura do Repositório e Separação de Responsabilidades

```
dev/
├── dev                         # Despachante executável principal
├── versions.sh                 # Versões fixadas dos binários oficiais e portas
├── runtimes/                   # Binários/tarballs pré-compilados de PHP e nginx
│   ├── manifest.sh             # Versões, URLs e sha256 de PHP e nginx
│   └── SHA256SUMS              # Checksums para validação no portão
├── lib/                        # Bibliotecas de lógica interna (uma por assunto)
│   ├── common.sh               # Utilitários, caminhos DEV_*, mensagens, parse de dev.conf
│   ├── install.sh              # Provisionamento do core base (PHP, Node, MySQL, etc.)
│   ├── plugins.sh              # Descoberta, instalação e gerenciamento de plugins
│   ├── project.sh              # Gerenciamento de projetos, dev.conf, vhosts, adoção
│   ├── updown.sh               # Orquestração do par up/down
│   ├── services.sh             # Supervisão de daemons, portas e processos sem systemd
│   ├── certs.sh                # Autoridade local mkcert e certificados SSL
│   ├── config.sh               # Geração de nginx.conf, php-fpm pool, my.cnf, Adminer
│   ├── runtime.sh              # Extração e conferência dos runtimes pré-compilados
│   ├── releases.sh             # Resolução de URLs e nomes de cache dos componentes
│   ├── schedule.sh             # Supervisão de tarefas recorrentes (dev.schedule)
│   ├── workers.sh              # Supervisão de processos de longa duração (dev.workers)
│   ├── snapshot.sh             # Snapshots de banco e arquivos e comandos db query/export/import
│   ├── doctor.sh               # Diagnósticos de saúde da máquina e do ambiente
│   ├── fix.sh                  # Recuperação de máquinas inconsistentes
│   ├── logs.sh                 # Inspeção de logs de erro agregados
│   ├── errors.sh               # Controle de exibição de erros no navegador
│   ├── clean.sh                # Limpeza de lixo e arquivos órfãos
│   ├── track.sh                # Gerenciamento do que vai para o git
│   ├── passwd.sh               # Redefinição de senha de usuários de projetos
│   └── autostart.sh            # Início automático no boot do WSL ou Linux
├── plugins/                    # Plugins de aplicação
│   ├── wordpress/
│   │   ├── plugin.sh           # Metadados e provisionamento de ferramentas (WP-CLI)
│   │   └── recipe.sh           # Receita WordPress (scaffolding, wp-config, cron)
│   ├── laravel/
│   │   ├── plugin.sh           # Provisionamento do laravel-installer via Composer
│   │   └── recipe.sh           # Receita Laravel (env, migrações, fila, Vite, cron)
│   └── moodle/
│       ├── plugin.sh           # Verificação de extensões e branches do Moodle
│       └── recipe.sh           # Receita Moodle (layout app/ + data/, CLI install, cron)
├── tests/                      # Suíte de testes em BATS
│   ├── helper.bash             # Mocks, isolamento de sandbox temporário
│   ├── commands.bats           # Validação de paridade entre usage(), case e docs
│   ├── plugins.bats            # Testes do gerenciador de plugins
│   └── updown.bats             # Testes de orquestração de projetos
├── tools/
│   ├── check.sh                # Portão de qualidade estático
│   ├── test.sh                 # Executor da suíte BATS
│   ├── build-runtimes.sh       # Script gerador de runtimes estáticos
│   └── banned-identifiers.txt  # Proibição de identificadores fora do padrão
├── README.md                   # Documentação inicial
└── USERGUIDE.html              # Guia completo visual para o desenvolvedor
```

*Alternativas consideradas:*
- *Manter receitas em `lib/recipes/` fixas:* Rejeitado porque viola o requisito de modularidade e desacoplamento em plugins com ferramentas instaláveis sob demanda.
- *Plugins como repositórios git remotos:* Rejeitado para o MVP, pois adicionaria complexidade de rede e versionamento; manter os plugins oficiais catalogados em `plugins/` e ativados/instalados sob demanda em `~/.dev/plugins` oferece experiência rápida, confiável e determinística.

### 2. Ciclo de Vida e Contrato do Sistema de Plugins

- **Catálogo de Plugins**: O diretório `plugins/` no repositório contém as definições oficiais dos plugins.
- **Estrutura de cada Plugin**:
  - `plugin.sh`: Deve implementar `plugin_info` (nome, título, descrição, ferramentas necessárias) e `plugin_install` / `plugin_uninstall` (responsáveis por baixar ou remover binários específicos, ex: WP-CLI ou `laravel-installer`).
  - `recipe.sh`: Implementa o contrato de hooks do projeto:
    - `recipe_title`: Título legível da aplicação.
    - `recipe_docroot`: Ponto de entrada web (`public`, `.`, `app/public`, etc.).
    - `recipe_php`: Versão/série de PHP recomendada.
    - `recipe_ask`: Perguntas interativas pré-instalação (ex: MySQL vs SQLite no Laravel).
    - `recipe_install`: Scaffolding e instalação automática via CLI.
    - `recipe_restore`: Reconstituição de dependências em projetos clonados (`composer install`, `npm ci`).
    - `recipe_next_steps`: Instruções e credenciais exibidas após a criação.
    - `recipe_change_password`: Troca de senha administrativa via CLI/tinker.
    - `recipe_has_user`: Verificação de existência de usuário.
    - `recipe_identity`: Identificador de login do usuário padrão.
    - `recipe_gitignore`: Template de `.gitignore` com lista branca e regra de escada.
    - `recipe_schedule`: Tarefas de cron padrão do projeto (`dev.schedule`).
    - `recipe_workers`: Processos de background padrão (`dev.workers`).
- **Estado no Sandbox**:
  - Plugins instalados são registrados em `~/.dev/plugins/installed/<name>`.
  - Ferramentas específicas residem em `~/.dev/runtime/<ferramenta>`.
  - `dev plugin list` inspeciona o catálogo em `plugins/` e cruza com os diretórios instalados em `~/.dev/plugins/installed/`.
- **Comando `dev new`**:
  - Sintaxe: `dev new <app> <site>` (ou `dev new <site>` caso apenas um plugin esteja instalado).
  - Valida se o plugin `<app>` está presente em `~/.dev/plugins/installed/`. Se não estiver, falha com instrução clara (`hint "instale o plugin com: dev plugin install <app>"`).

### 3. Convenção de Idioma e Identificadores

Seguindo a política estrita do `wdev`:
- **Em inglês**: Nomes de funções, variáveis, arquivos, diretórios, comandos, subcomandos, flags, chaves de configuração (`dev.conf`, `dev.schedule`, `dev.workers`, pool `[dev]`, `dev.service`).
- **Em português brasileiro**: Mensagens de saída para o usuário (`ok`, `warn`, `bad`, `info`, `hint`, `step`, `die`), texto de ajuda (`usage()`), comentários explicativos no código e documentação (`README.md`, `USERGUIDE.html`, `CLAUDE.md`).

### 4. Runtimes Pré-compilados e Compatibilidade

- **PHP**: Aproveitar a arquitetura do `wdev` com `spc` (PHP 8.5.11 estático, incluindo OPcache, mysqli, pdo_mysql, intl, mbstring, curl, etc.), garantindo que os avisos de depreciação do Moodle sejam suprimidos na raiz do `config.php` da aplicação, permitindo que uma única versão de alta performance atenda as três aplicações sem necessidade de compilar múltiplas versões de PHP.
- **Nginx**: 1.30.5 estático pré-compilado.
- **MySQL**: 8.4 LTS Minimal tarball oficial.
- **Node.js**: 24.x LTS binário oficial pré-compilado.

## Risks / Trade-offs

| Risco | Mitigação |
|---|---|
| **Conflito de portas com wdev ou devsh existentes** | O `dev` adota o algoritmo `port_owner` do `wdev`: detecta outros sandboxes e oferece encerramento gracioso via `-f` (`take_over_ports`), sem tocar em processos alheios ou do sistema (root). |
| **Depreciações no Moodle com PHP moderno** | Injetar no `config.php` gerado para o Moodle a diretiva `error_reporting(E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED)` e executar CLI do Moodle com essa flag antes de carregar o código. |
| **Instalador do Laravel com dependências de ambiente** | Injetar `DB_*` e `MAIL_*` diretamente no ambiente do processo filho (`ambiente_do_banco` portado para `db_environment`) para que o `php artisan migrate` fale exclusivamente com o sandbox do MySQL. |
| **Contaminação de namespace entre receitas** | Função `unload_recipe` zera todas as funções `recipe_*` antes de carregar uma nova receita. |
