# Proposal

## Why

Durante a execução de `./dev install`, após subir o MySQL, o instalador falha com a mensagem:
`✘ o MySQL não aceita a senha do config nem a senha vazia`.

A causa raiz não é uma recusa de credenciais pelo servidor MySQL, mas sim a falha de carregamento de biblioteca dinâmica do binário cliente `mysql` (`error while loading shared libraries: libncurses.so.6: cannot open shared object file: No such file or directory`, código 127). Atualmente, a função `compatibilize_libs` inspeciona apenas o binário do servidor `mysqld` (que exigia `libaio.so.1`), ignorando os utilitários cliente (`mysql`, `mysqldump`, `mysqladmin`) que exigem `libncurses.so.6`. Como as mensagens de erro do cliente são descartadas para `/dev/null` durante o teste de conexão em `set_mysql_root_password`, o instalador diagnostica incorretamente a falha como rejeição de senha.

## What Changes

- Adiciona `libncurses6` à lista de dependências mínimas do sistema (`APT_MIN`) em `lib/install.sh`.
- Atualiza `compatibilize_libs` para inspecionar todos os executáveis do MySQL (`$prefix/bin/*` ou `mysqld`, `mysql`, `mysqldump`, `mysqladmin`) e criar compatibilidade caso bibliotecas dinâmicas faltem no sistema (incluindo mapeamento de fallback para `libncursesw.so.6` quando presente).
- Garante que `compatibilize_libs` e `sandbox_libs` sejam executados mesmo quando o MySQL já estiver previamente descompactado, garantindo compatibilidade em re-execuções do `dev install`.
- Assegura que `sandbox_libs` seja chamado em `set_mysql_root_password` e `mysql_password_applied` para garantir o `LD_LIBRARY_PATH` com `lib-compat`.
- Aprimora o tratamento de erro em `set_mysql_root_password` para diferenciar erro de execução/biblioteca/socket do erro real de autenticação do MySQL.
- Adiciona verificação no `dev doctor` e autocura no `dev fix` para a operacionalidade dos binários cliente do MySQL.

## Capabilities

### Modified Capabilities

- `environment-core`: Exige `libncurses6` nas dependências do sistema e garante compatibilização e execução funcional tanto do daemon `mysqld` quanto dos utilitários cliente do MySQL (`mysql`), prevenindo falhas de inicialização e diagnóstico incorreto de credenciais no banco de dados.

## Impact

- `lib/install.sh`: Expansão de `APT_MIN` com `libncurses6` e aprimoramento de `compatibilize_libs` para cobrir todos os binários do MySQL e rodar mesmo quando já instalado.
- `lib/config.sh`: Chamada de `sandbox_libs` e diferenciação precisa de erro no teste de credenciais em `set_mysql_root_password`.
- `lib/doctor.sh`: Verificação da execução funcional de `mysql` além de `mysqld`.
- `lib/fix.sh`: Reaplicação de `compatibilize_libs` quando binários do MySQL apresentarem bibliotecas pendentes.
- Suíte de testes: Novos testes automatizados com bats cobrindo a compatibilização de bibliotecas cliente e diagnóstico de banco.
