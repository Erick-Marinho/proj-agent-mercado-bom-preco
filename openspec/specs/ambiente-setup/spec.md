# ambiente-setup Specification

## Purpose

Montar o ambiente do zero, num comando só. O `scripts/setup.sh` muta e prepara; não julga o
resultado. É o par mutante da capability `ambiente-verificacao`: **o setup produz exatamente
o que o verify confere**, e quem responde "está utilizável?" é o verify. O raciocínio por
trás das escolhas está em `docs/decisoes/`.

## Requirements

### Requirement: Execução a partir de qualquer diretório

O setup DEVE se reposicionar na raiz do repositório antes de qualquer passo.

#### Scenario: Chamado de um subdiretório

- **WHEN** o script é invocado com o diretório de trabalho em qualquer ponto do repositório
- **THEN** ele se reposiciona na raiz e roda igual

### Requirement: Os cinco passos do ambiente

O setup DEVE executar cinco passos nesta ordem, cada um dependendo do anterior: instalar
`uv` (1), disponibilizar a versão de `.python-version` (2), convergir `.venv` para o
`pyproject.toml` via `uv sync` (3), criar o `.env` a partir do `.env.example` com
`chmod 600` (4) e gerar `data/bom_preco.db` via `uv run python -m bom_preco.carga` (5). O
pin de Python DEVE ser lido de `.python-version` em tempo de execução, sem aparecer escrito
no script.

#### Scenario: Ambiente ainda inexistente

- **WHEN** nenhum dos artefatos existe
- **THEN** os cinco passos produzem `uv` no PATH, a versão pinada, o `.venv` convergido, o
  `.env` e o banco

#### Scenario: `uv` e Python já presentes

- **WHEN** o passo 1 encontra `uv` instalado
- **THEN** mantém a instalação e imprime a versão
- **AND** o passo 2 mantém a versão de Python já disponível

#### Scenario: Banco já existente

- **WHEN** o passo 5 encontra `data/bom_preco.db`
- **THEN** recria o banco do zero, porque a carga é determinística e nada feito à mão mora
  no banco derivado

### Requirement: Idempotência

Rodar o setup duas vezes seguidas NÃO DEVE quebrar nem desfazer nada.

#### Scenario: Segunda execução consecutiva

- **WHEN** o setup roda de novo sobre um ambiente que ele mesmo montou
- **THEN** os passos 1, 2 e 3 convergem, o passo 4 preserva o `.env` e o passo 5 recria o banco
- **AND** nada do que existia é perdido

### Requirement: O setup não verifica

O setup NÃO DEVE conferir credencial nem emitir diagnóstico. Um setup que também verifica
duplica a lógica do verify, e as duas cópias divergem.

#### Scenario: Fim de uma execução bem-sucedida

- **WHEN** os cinco passos concluem
- **THEN** a última linha da saída aponta para `./scripts/verify.sh`

### Requirement: Preservação do `.env`

O setup NÃO DEVE sobrescrever um `.env` existente, mesmo incompleto ou desatualizado, nem
preencher segredo. Chave faltante é problema da checagem 6 do verify.

#### Scenario: `.env` já existe

- **WHEN** o passo 4 encontra um `.env`
- **THEN** mantém o arquivo exatamente como está

#### Scenario: `.env` criado agora

- **WHEN** o passo 4 copia o `.env.example`
- **THEN** o `.env` sai com os valores vazios
- **AND** a saída diz que `OPENAI_API_KEY` precisa ser preenchida à mão, e segue

#### Scenario: `chmod 600` indisponível

- **WHEN** o `chmod 600` sobre o `.env` falha
- **THEN** o passo não aborta, porque sistema de arquivos sem permissão POSIX não reprova o
  ambiente inteiro

### Requirement: Fronteiras do que o setup não toca

O setup NÃO DEVE escrever em `data/raw/`, que é imutável por contrato, nem subir Docker ou
Langfuse, que só passam a ser necessários a partir da semana 6 e já são reportados como
aviso pelo verify.

#### Scenario: Dados brutos durante a execução

- **WHEN** qualquer passo roda
- **THEN** `data/raw/` permanece intocado, e a limpeza fica por conta da carga

#### Scenario: Observabilidade durante a execução

- **WHEN** o setup conclui
- **THEN** nenhum container foi iniciado

### Requirement: Falha explícita, sem rollback

Toda falha DEVE abortar na hora, com bloco de mensagem que nomeia a causa e o comando de
correção, e sair com `1`. Os passos já concluídos permanecem. O script NÃO DEVE usar
`set -e`: cada passo trata o próprio erro.

#### Scenario: Falha no meio da sequência

- **WHEN** um passo falha
- **THEN** o script aborta imprimindo causa e correção, e sai com `1`
- **AND** os passos anteriores já concluídos permanecem, sem rollback

#### Scenario: Erro sem mensagem

- **WHEN** um comando interno retorna erro
- **THEN** o passo trata o próprio erro e informa o usuário, em vez de o script morrer em silêncio

### Requirement: Falhas do passo 1 — `uv`

O passo 1 DEVE distinguir `curl` ausente, instalador que falhou e instalação que não
apareceu no PATH, e tentar recarregar o PATH antes de desistir.

#### Scenario: `curl` ausente

- **WHEN** o passo 1 não encontra `curl`
- **THEN** a mensagem manda instalar o `curl` e rodar de novo, porque sem ele não há como
  instalar o `uv`

#### Scenario: Instalador falhou

- **WHEN** o instalador oficial retorna erro
- **THEN** a mensagem manda conferir conexão ou instalar à mão pela doc do `uv`

#### Scenario: Instalou, mas `uv` não aparece

- **WHEN** a instalação conclui e `uv` não está no PATH da sessão em curso
- **THEN** o script recarrega `~/.local/bin/env` e `~/.cargo/env` e reinsere os diretórios no PATH
- **AND** persistindo, a mensagem manda reabrir o terminal ou rodar
  `export PATH="$HOME/.local/bin:$PATH"`

### Requirement: Falhas dos passos 2, 3 e 4

Cada situação DEVE apontar o comando que revela o erro completo ou o arquivo a restaurar.

#### Scenario: `.python-version` ausente ou vazio

- **WHEN** o passo 2 não lê o pin
- **THEN** falha com a correção `git checkout -- .python-version`, dizendo que o projeto não
  declara sua versão

#### Scenario: `uv python install` falhou

- **WHEN** o passo 2 não consegue instalar a versão pinada
- **THEN** a mensagem manda rodar `uv python install <pin>` à mão para ver o erro completo

#### Scenario: `uv sync` falhou

- **WHEN** o passo 3 não converge o ambiente
- **THEN** a mensagem manda rodar `uv sync` à mão para ver o erro completo

#### Scenario: `.env.example` ausente

- **WHEN** o passo 4 não encontra o modelo
- **THEN** falha com a correção `git checkout -- .env.example`, dizendo que não há de onde
  criar o `.env`

#### Scenario: Cópia do `.env` falhou

- **WHEN** o `cp` retorna erro de escrita
- **THEN** a mensagem nomeia o passo

### Requirement: Falhas do passo 5 — carga

O passo 5 DEVE distinguir três desfechos, porque cada um manda o usuário para um lugar
diferente, e DEVE capturar e reimprimir a saída da carga em qualquer desfecho, sucesso ou
falha, porque erro de carga sem a saída dela é indepurável.

#### Scenario: Módulo ainda não escrito

- **WHEN** `src/bom_preco/` não existe
- **THEN** a mensagem diz que não é erro de instalação, e sim código que ainda não foi escrito
- **AND** aponta para a capability `carga` e avisa que o verify vai reprovar na checagem 17 até lá

#### Scenario: Import falha

- **WHEN** `src/bom_preco/` existe e a execução falha com `No module named`
- **THEN** a mensagem aponta para o `pyproject.toml`, que precisa declarar onde o pacote mora
- **AND** afirma que `uv` e Python estão bem, porque os dois passos anteriores terminaram

#### Scenario: Carga falhou por outro motivo

- **WHEN** a carga retorna erro que não é ausência de módulo
- **THEN** a mensagem imprime a saída da carga e o comando para repeti-la isoladamente

### Requirement: Exit code

O setup DEVE sair com `0` somente quando os cinco passos concluírem, e com `1` quando algum
falhar. O contrato do exit code é "o ambiente ficou pronto", e sem banco ele não ficou.

#### Scenario: Ambiente montado

- **WHEN** os cinco passos concluem
- **THEN** o exit code é `0`

#### Scenario: Quatro passos concluídos e a carga impossível

- **WHEN** os passos 1 a 4 concluem e o passo 5 reprova porque `src/bom_preco/` não existe
- **THEN** o exit code é `1`
- **AND** `setup.sh && verify.sh` para no primeiro comando, em vez de passar ali e reprovar
  no segundo

### Requirement: Formato de saída

A saída DEVE trazer um bloco por passo, numerado `[n/5]`, com `✓` para o que foi criado, `·`
para o que já existia e foi mantido, e nota indentada em cinza para o que o usuário ainda
precisa fazer à mão. Falha vira `✗` seguido do bloco de correção.

#### Scenario: Saída não é um terminal

- **WHEN** a saída é redirecionada, ou `NO_COLOR` está definida
- **THEN** a cor sai automaticamente

### Requirement: Restrições de implementação

O script DEVE rodar em Bash 3.2, que é o que o macOS traz — sem `declare -A`, sem `mapfile`,
sem `readarray`. A mesma restrição vale para o `verify.sh`.

#### Scenario: Execução no Bash que o macOS traz

- **WHEN** o script roda sob Bash 3.2
- **THEN** nenhuma construção posterior ao Bash 3.2 é usada
