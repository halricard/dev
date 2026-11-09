# dev

Ambiente de desenvolvimento PHP e Node.js para WSL2 e Linux, sem Docker, sem compilação demorada e com suporte modular a aplicações via plugins (WordPress, Laravel e Moodle).

---

## Características

- **Core Enxuto**: Instala PHP 8.5 estático, Node.js LTS, nginx 1.30 estático, MySQL 8.4 LTS minimal, Composer, Mailpit, Adminer e mkcert sem compilar nada do código-fonte.
- **Aplicações via Plugins**: Suporte modular sob demanda para WordPress, Laravel e Moodle (`dev plugin install <nome>`). Instale apenas o que usa.
- **Rápido e Idempotente**: Runtimes estáticos pré-compilados permitem provisionar o ambiente em minutos.
- **Sem Docker e sem systemd**: Processos leves com supervisão de portas (`port_owner`) e encerramento gracioso (`take_over_ports`).
- **HTTPS Local Automático**: Certificados SSL locais confiados no navegador via autoridade raiz própria gerada localmente.

---

## Primeiros Passos

```bash
# 1. Instalar a pilha base do core
./dev install

# 2. Instalar o plugin da aplicação desejada
dev plugin install wordpress    # ou moodle, ou laravel

# 3. Criar e iniciar um novo projeto
dev new wordpress meu-blog
```

O site estará disponível imediatamente em `https://meu-blog.localhost`.

---

## Fluxos Práticos do Dia a Dia

### Moodle

1. **Instalar plugin**: `dev plugin install moodle`
2. **Criar projeto**: `dev new moodle meu-ead` (cria layout seguro `app/` e `data/`, banco e cron)
3. **Trabalhar no dia a dia**:
   - `cd meu-ead`
   - `dev up` (garante MySQL, vhost e cron ativos)
   - `dev exec php admin/cli/cron.php` (executa tarefas manuais)
   - `dev logs` (visualiza erros PHP sem ruído de depreciações)
   - `dev down` (encerra ao fim do dia)

### Laravel

1. **Instalar plugin**: `dev plugin install laravel`
2. **Criar projeto**: `dev new laravel minha-api` (pergunta MySQL/SQLite, roda migrações e prepara ambiente)
3. **Trabalhar no dia a dia**:
   - `cd minha-api`
   - `dev up` (sobe banco, `queue:listen`, Vite e agendador)
   - `dev exec php artisan migrate` (executa comandos artisan)
   - `dev worker` (mostra o status da fila e do Vite)
   - `dev open mail` (abre o Mailpit para testar e-mails)

### WordPress

1. **Instalar plugin**: `dev plugin install wordpress` (baixa WP-CLI)
2. **Criar projeto**: `dev new wordpress meu-site` (banco, wp-config.php com salts e admin gerados)
3. **Trabalhar no dia a dia**:
   - `cd meu-site`
   - `dev up` (coloca site no ar e agenda wp-cron)
   - `dev exec wp plugin list` (executa comandos WP-CLI)
   - `dev snapshot checkpoint1` (salva estado completo do banco e arquivos)
   - `dev restore checkpoint1` (restaura se algo der errado)

### Testes e navegador do agente

Cada aplicação traz as suítes de teste oficiais dela, e `dev test` as roda com o PHP, o Node e o banco do projeto:

| Aplicação | Suítes | Navegador |
|---|---|---|
| Moodle | `phpunit`, `behat` | Chrome for Testing fixado pelo dev, com chromedriver (o Behat exige WebDriver) |
| Laravel | `pest` (ou `phpunit`), `browser` (Pest 4) | o do Playwright do projeto |
| WordPress | `phpunit` (plugin ou tema), `e2e` (Playwright) | o do Playwright do projeto |

Desde o Playwright 1.57, o navegador que ele baixa também é um Chrome for Testing; só muda quem fixa a versão. A primeira execução prepara a suíte: tabelas de teste com prefixo próprio, dataroot separado e dependências de desenvolvimento.

```bash
dev test                               # lista as suítes deste projeto
dev test behat --tags=@local_meuplugin # Moodle: Behat no Chrome, em https://test.<projeto>.localhost
dev test pest --filter=UserTest        # Laravel
dev test phpunit wp-content/plugins/meu-plugin   # WordPress
dev test user                          # conta temporária para testar no navegador
```

`dev test user` cria a conta `devtest` com senha nova a cada chamada; o `dev down` a apaga. A conta de administrador real nunca é usada nos testes.

Para dar ao agente de IA um navegador restrito ao projeto (Playwright MCP, headless, sem perfil em disco), use `dev agent add claude --browser`. A configuração gravada no `.mcp.json` só chama `dev browser mcp <projeto>`, sem segredo nem caminho da máquina.

### Documentação atualizada para o agente

Com `--docs`, o agente consulta a documentação atual da aplicação pelo [Context7](https://context7.com) em vez de confiar na memória:

```bash
dev docs key                            # grava a chave de API em ~/.dev/config (pede sem eco)
dev agent add claude --docs             # instala o Context7 MCP e registra o servidor dev-docs
```

A skill informa a versão instalada da aplicação (lida de `vendor/`, `wp-includes/version.php` ou `version.php`) e os IDs do Context7 de cada uma: `/laravel/docs/<major>.x` e `/pestphp/docs` no Laravel, as referências e os handbooks de developer.wordpress.org no WordPress, `/websites/moodledev_io` no Moodle. Rode `dev agent update` depois de atualizar a aplicação.

A configuração no projeto só chama `dev docs mcp`; a chave fica fora do projeto e do git e chega ao servidor por variável de ambiente. Com a chave gravada, `dev new --agent <alvo>` já inclui a documentação.

---

## Comandos

```text
dev install             instala a pilha base (--plan mostra e não instala)
dev start               sobe os serviços da máquina (-f libera porta ocupada)
dev stop                encerra os serviços da máquina
dev restart             stop e start — aplica conf.d/local.ini editado
dev status              o que está rodando
dev fix                 recupera a máquina meio de pé (-f encerra intrusos)
dev doctor              diagnostica o que costuma quebrar e instala as ferramentas de compilação
dev versions            o que está fixado vs. o que foi publicado
dev uninstall           remove o sandbox
dev plugin              gerenciador de plugins (list, install, update, remove)
dev new                 cria um projeto novo já instalado e no ar
dev up                  põe este projeto no ar: banco, vhost, agenda e workers
dev down                tira do ar; arquivos e banco ficam
dev init                escreve dev.conf num projeto existente
dev destroy             apaga projeto, banco e snapshots
dev sites               lista o que está sendo servido
dev exec                roda comando com php, node, composer do projeto
dev shell               abre shell com esses mesmos runtimes
dev logs                mostra erros da aplicação e do webserver
dev errors              se o erro aparece na tela deste projeto
dev schedule            o que roda de tempos em tempos
dev worker              processos de background contínuos
dev track               marca o que vai para o git
dev untrack             para de versionar
dev clean               lista lixo e arquivos temporários; clean trash remove
dev snapshot            salva arquivos e banco num ponto de volta
dev snapshots           lista os pontos salvos
dev restore             restaura um ponto salvo
dev db                  consulta (query), exporta ou importa banco
dev passwd              redefine a senha do admin
dev open                abre o site, mailpit ou adminer no navegador
dev autostart           sobe a pilha no início do sistema
dev test                suítes de teste da aplicação e usuário de teste temporário (test user)
dev browser             navegador do dev para testes e para o agente de IA (status, install, remove)
dev agent               gera a skill do dev para Claude, Codex ou Antigravity (add, remove, update, list; --browser, --docs)
dev docs                documentação atualizada para o agente via Context7 (status, key, install, remove)
```

---

## Documentação Completa

Abra `USERGUIDE.html` no seu navegador para ver o guia visual completo com tabelas práticas, fluxo de trabalho e resolução de problemas.
