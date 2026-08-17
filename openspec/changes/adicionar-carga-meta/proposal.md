## Why

O módulo `bom_preco.carga` ainda não existe, e sem ele o repositório não sai do lugar: o
passo 5 do `setup.sh` reprova, a checagem 17 do `verify.sh` reprova, e não há banco para o
agente consultar. Este change cobre a primeira metade do contrato da carga — **o rastro que
ela deixa**: a tabela `carga_meta`, o momento da marca de conclusão e o determinismo. O
esquema das tabelas de dados e as regras de limpeza ficam de fora, e entram em change próprio.

A parte do rastro vem primeiro porque é dela que o resto depende para ser verificável: sem
`carga_meta`, a única prova de que a carga terminou é a rolagem de tela de quem a rodou, e a
checagem 17 não tem contra o que comparar.

## What Changes

- Novo módulo `src/bom_preco/carga.py`, executável por `uv run python -m bom_preco.carga`,
  lendo `data/raw/*.csv.gz` e produzindo `data/bom_preco.db`.
- Nova tabela `carga_meta`, uma linha por arquivo de origem, com os contadores de linhas
  lidas, inseridas, corrigidas e descartadas, mais o instante de conclusão.
- Carga em transação única, com `concluida_em` gravado como último statement antes do commit.
- Relatório impresso ao final, com os mesmos números que vão para `carga_meta`.
- O banco passa a ser recriado do zero a cada execução: sem carga incremental, sem `UPDATE`
  sobre banco existente.

Fora de escopo, para um change posterior: esquema das tabelas `produtos` e `vendas`, regras
de limpeza (datas em dois formatos, números pt-BR, valores negativos, produtos duplicados,
categorias divergentes) e a coluna `origem_hash` — considerada e adiada, com o motivo em
`design.md`.

## Capabilities

### New Capabilities

- `carga`: o rastro que a carga deixa — a tabela `carga_meta`, o momento da marca de
  conclusão e a garantia de determinismo. Não cobre o esquema das tabelas de dados nem as
  regras de limpeza.

### Modified Capabilities

Nenhuma. As capabilities `ambiente-setup` e `ambiente-verificacao` já especificam o
comportamento delas contra esta carga — o passo 5 do setup e a checagem 17 do verify existem
e reprovam hoje justamente por ausência do módulo. Este change faz esses requisitos passarem
a ser satisfeitos, sem alterar o que eles exigem.

## Impact

- **Código novo**: `src/bom_preco/__init__.py`, `src/bom_preco/carga.py`.
- **`pyproject.toml`**: precisa declarar onde o pacote mora, senão o import falha — é o
  segundo desfecho previsto no passo 5 do `setup.sh`.
- **Dados**: `data/raw/*.csv.gz` é aberto somente para leitura, nunca escrito.
  `data/bom_preco.db` passa a existir; é derivado, descartável e não versionado.
- **Scripts**: `setup.sh` passa a concluir os cinco passos e sair com `0`; `verify.sh` passa
  a ter como aprovar a checagem 17.
