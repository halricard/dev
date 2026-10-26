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
- `plugins/<app>/`: plugins de aplicação contendo `plugin.sh` (ferramentas e ciclo de vida) e `recipe.sh` (scaffolding e hooks de projeto).
- Estado em `~/.dev`, cache de download em `~/.cache/dev`.
