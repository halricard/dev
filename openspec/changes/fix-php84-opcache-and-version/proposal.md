# Proposal

## Why

Ao provisionar um novo projeto Moodle (`dev new moodle ead`), o sistema compila ou verifica o runtime do PHP 8.4 sob demanda, mas o processo aborta durante a verificação com o erro `"o PHP do runtime está sem o OPcache"`. Isso ocorre porque a compilação via `static-php-cli` não incluía a extensão `opcache` na lista de compilação. Além disso, o sistema estava forçando a versão defasada `8.4.6` no nome do pacote e nos mapeamentos do runtime, mesmo quando o `static-php-cli` baixava e compilava a versão oficial mais recente da série 8.4 (`8.4.27`).

## What Changes

- **Inclusão de OPcache na compilação do PHP**: Adiciona `opcache` à lista de extensões compiladas pelo `static-php-cli` em `tools/build-runtimes.sh`, garantindo que o binário estático do PHP contenha `Zend OPcache` ativo para satisfazer `lib/runtime.sh` e os requisitos do Moodle.
- **Atualização da resolução da versão do PHP 8.4**: Corrige o mapeamento da série 8.4 de `8.4.6` para `8.4.27` em `lib/runtime.sh` e `tools/build-runtimes.sh`, alinhando os nomes de artefatos (`php-8.4.27-linux-x86_64.tar.xz`), somas SHA-256 e testes associados.
- **Detecção dinâmica de versão compilada**: Ajusta o empacotador de runtimes para ler a versão real produzida pelo binário compilado (`php -r 'echo PHP_VERSION;'`) caso ela divirja da string de resolução preliminar.
- **Atualização dos testes BATS**: Atualiza os testes unitários e de integração que esperavam `8.4.6` para validar `8.4.27` e a presença do `Zend OPcache`.

## Capabilities

### New Capabilities
<!-- Nenhuma nova capacidade introduzida -->

### Modified Capabilities
- `environment-core`: Atualiza o requisito de compilação sob demanda do PHP para incluir obrigatoriamente `opcache` com verificação de `Zend OPcache`, e atualizar a resolução oficial da série 8.4 para a versão estável mais recente (`8.4.27`).

## Impact

- Afeta `tools/build-runtimes.sh`, `lib/runtime.sh`, `runtimes/SHA256SUMS`, `runtimes/php/` e testes BATS (`tests/build_runtimes.bats`, `tests/releases.bats`, `tests/common.bats`, `tests/services.bats`, `tests/recipes.bats`).
- Não quebra compatibilidade retroativa para projetos PHP 8.5; permite que `dev new moodle ead` execute a instalação do Moodle sem erros de OPcache e com o PHP 8.4.27 oficial.
