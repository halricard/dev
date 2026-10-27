# Tasks

## 1. Dependências do Sistema e Compatibilização de Bibliotecas MySQL

- [x] 1.1 Incluir `libncurses6` na lista `APT_MIN` em `lib/install.sh` e validar que `apt_missing` identifica o pacote se ausente.
- [x] 1.2 Atualizar `compatibilize_libs` em `lib/install.sh` para inspecionar todos os executáveis do MySQL (`mysqld`, `mysql`, `mysqldump`, `mysqladmin`) e incluir fallback de symlink de `libncursesw.so.6` para `libncurses.so.6`.
- [x] 1.3 Assegurar que `install_mysql` em `lib/install.sh` execute `compatibilize_libs` e `sandbox_libs` mesmo quando o diretório do MySQL já estiver presente.

## 2. Configuração de Credenciais e Tratamento Preciso de Erros

- [x] 2.1 Invocar `sandbox_libs` em `set_mysql_root_password` e `mysql_password_applied` ([`lib/config.sh`](file:///home/dell/Code/dev/lib/config.sh)), capturando stderr do comando `mysql` para diferenciar erros de carregamento de biblioteca/socket de erro de autenticação.
- [x] 2.2 Adicionar verificação de execução do utilitário `mysql` em `cmd_doctor` ([`lib/doctor.sh`](file:///home/dell/Code/dev/lib/doctor.sh)) e autocura de `lib-compat` em `cmd_fix` ([`lib/fix.sh`](file:///home/dell/Code/dev/lib/fix.sh)).

## 3. Testes Automatizados e Portão de Qualidade

- [x] 3.1 Adicionar testes BATS para a compatibilização de bibliotecas cliente do MySQL, detecção de erros em `set_mysql_root_password` e diagnósticos no `doctor`/`fix`.
- [x] 3.2 Executar `./tools/check.sh` e garantir que o repositório passe com sucesso em todas as validações (sintaxe, identificadores banidos e suíte de testes).
