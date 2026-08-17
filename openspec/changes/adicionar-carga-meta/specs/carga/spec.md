## Purpose

O rastro que a carga deixa ao transformar os dumps de `data/raw/` em `data/bom_preco.db`: a
tabela `carga_meta`, o momento da marca de conclusão e a garantia de determinismo. O esquema
das tabelas de dados e as regras de limpeza ficam fora desta capability.

## ADDED Requirements

### Requirement: Origem somente para leitura

A carga DEVE abrir `data/raw/produtos.csv.gz` e `data/raw/vendas.csv.gz` somente para
leitura. Ela NUNCA DEVE escrever em `data/raw/`.

#### Scenario: Execução completa da carga

- **WHEN** a carga termina, com sucesso ou com erro
- **THEN** `data/raw/` permanece byte a byte como estava
- **AND** `git status` não reporta modificação em `data/raw/`

### Requirement: O banco é recriado do zero

A carga DEVE ser a dona exclusiva de `data/bom_preco.db` e recriá-lo integralmente a cada
execução. NÃO DEVE existir carga incremental nem `UPDATE` sobre banco existente. A saída
contém as tabelas `produtos`, `vendas` e `carga_meta`.

#### Scenario: Banco já existe

- **WHEN** a carga roda e `data/bom_preco.db` já existe
- **THEN** o conteúdo anterior é integralmente substituído pelo resultado desta execução

#### Scenario: Banco ausente

- **WHEN** a carga roda e `data/bom_preco.db` não existe
- **THEN** a carga cria o arquivo e conclui normalmente, sem exigir passo prévio

### Requirement: Determinismo

Rodar a carga duas vezes sobre o mesmo dump DEVE produzir o mesmo banco — os mesmos dados e
os mesmos contadores de `carga_meta`. `concluida_em` é a única coluna que pode variar entre
execuções, por ser um relógio.

#### Scenario: Duas execuções sobre o mesmo dump

- **WHEN** a carga roda duas vezes sobre `data/raw/` inalterado
- **THEN** as tabelas de dados têm o mesmo conteúdo nas duas execuções
- **AND** todos os contadores de `carga_meta` são idênticos
- **AND** somente `concluida_em` difere

### Requirement: Tabela `carga_meta`

A carga DEVE gravar em `carga_meta` uma linha por arquivo de origem, com `origem` (TEXT,
chave primária) contendo o nome do arquivo em `data/raw/`, como `vendas.csv.gz`;
`linhas_lidas`, `linhas_inseridas`, `linhas_corrigidas` e `linhas_descartadas` (INTEGER); e
`concluida_em` (TEXT) com o instante do fim da carga em ISO-8601 UTC.

#### Scenario: Contagem por arquivo de origem

- **WHEN** a carga consome `produtos.csv.gz` e `vendas.csv.gz`
- **THEN** `carga_meta` tem exatamente uma linha para cada um, identificada pelo nome do arquivo

#### Scenario: Significado dos contadores

- **WHEN** a carga preenche os contadores de uma origem
- **THEN** `linhas_lidas` conta as linhas de dados lidas, sem o cabeçalho
- **AND** `linhas_inseridas` conta as que viraram registro na tabela de dados
- **AND** `linhas_corrigidas` conta quantas das inseridas passaram por normalização
- **AND** `linhas_descartadas` conta as lidas que não viraram registro

### Requirement: Invariantes dos contadores

Os contadores DEVEM satisfazer `linhas_lidas == linhas_inseridas + linhas_descartadas` e
`linhas_corrigidas <= linhas_inseridas`. Corrigida é subconjunto de inserida, não uma
terceira categoria: somar corrigidas ao total é erro de leitura.

#### Scenario: Fechamento do total

- **WHEN** os contadores de qualquer origem são lidos
- **THEN** inseridas mais descartadas somam exatamente as lidas

#### Scenario: Linha normalizada e inserida

- **WHEN** uma data é reescrita de `dd/mm/aaaa` para ISO e a linha vira registro
- **THEN** ela conta em `linhas_inseridas` e também em `linhas_corrigidas`

### Requirement: Relatório impresso

A carga DEVE imprimir ao terminar um relatório de linhas lidas, inseridas, corrigidas e
descartadas, com os mesmos números gravados em `carga_meta`. A tabela existe para que esse
relatório sobreviva ao terminal.

#### Scenario: Fim da carga

- **WHEN** a carga conclui
- **THEN** imprime os contadores por origem
- **AND** os números impressos são iguais aos gravados em `carga_meta`

### Requirement: Momento da marca de conclusão

A carga DEVE rodar em transação única e gravar `concluida_em` como último statement antes do
commit. NUNCA DEVE existir banco com dados e sem marca, nem marca sem os dados que ela declara.

#### Scenario: Carga interrompida

- **WHEN** a execução é interrompida em qualquer ponto — Ctrl-C, queda do processo ou erro
  de parsing no meio do arquivo
- **THEN** a transação é desfeita por inteiro
- **AND** não resta banco com dados parciais nem linha em `carga_meta`

#### Scenario: Carga concluída

- **WHEN** a carga chega ao fim sem erro
- **THEN** `concluida_em` está preenchido para cada origem
- **AND** o preenchimento significa carga inteira, que é o que a checagem 17 do `verify.sh`
  usa para distinguir banco carregado de banco pela metade
