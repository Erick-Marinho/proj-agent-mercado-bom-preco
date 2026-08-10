# Contrato do módulo `bom_preco.carga`

## Propósito

Ler os dumps de `data/raw/` e produzir `data/bom_preco.db`. Executada por
`uv run python -m bom_preco.carga`.

Este contrato cobre o **rastro que a carga deixa** — a tabela `carga_meta`, o momento da
marca de conclusão e o determinismo. O esquema das tabelas de dados e as regras de limpeza
ficam fora do escopo, e entram em contrato próprio.

## Entrada e saída

Entrada: `data/raw/produtos.csv.gz` e `data/raw/vendas.csv.gz`, abertos somente para
leitura. A carga nunca escreve em `data/raw/`.

Saída: `data/bom_preco.db`, com as tabelas `produtos`, `vendas` e `carga_meta`. O banco é
derivado, descartável e não versionado. A carga é dona exclusiva do arquivo e o recria do
zero a cada execução — não há carga incremental nem `UPDATE` sobre banco existente. O
`rm -f` que aparece na correção da checagem 17 do `verify.sh` não é obrigatório para a carga
funcionar; ele cobre o caso do arquivo corrompido, que não abre para ser recriado.

## Determinismo

Rodar a carga duas vezes sobre o mesmo dump produz o mesmo banco. "O mesmo" vale para os
dados e para os contadores de `carga_meta`. `concluida_em` é a única coluna que muda entre
execuções, por ser um relógio.

## `carga_meta`

Uma linha por arquivo de origem.

| Coluna | Tipo | Guarda |
|---|---|---|
| `origem` | TEXT, chave primária | nome do arquivo em `data/raw/`, como `vendas.csv.gz` |
| `linhas_lidas` | INTEGER | linhas de dados lidas da origem, sem contar o cabeçalho |
| `linhas_inseridas` | INTEGER | linhas que viraram registro na tabela de dados |
| `linhas_corrigidas` | INTEGER | quantas das inseridas passaram por normalização |
| `linhas_descartadas` | INTEGER | linhas lidas que não viraram registro |
| `concluida_em` | TEXT | instante do fim da carga, ISO-8601 em UTC |

Invariantes:

- `linhas_lidas == linhas_inseridas + linhas_descartadas`;
- `linhas_corrigidas <= linhas_inseridas` — **corrigida é subconjunto de inserida, não uma
  terceira categoria.** Uma data reescrita de `dd/mm/aaaa` para ISO conta nas duas colunas.
  Somar corrigidas ao total é erro de leitura.

São os mesmos números do relatório que a carga imprime ao terminar. A tabela existe para que
esse relatório sobreviva ao terminal: sem ela, a única prova de que a carga terminou é a
rolagem de tela de quem a rodou.

## Momento da marca

A carga roda em transação única e grava `concluida_em` como último statement antes do
commit.

A consequência é o que dá valor à marca: interrupção em qualquer ponto — Ctrl-C, queda,
erro de parsing na linha 300 mil — desfaz tudo. Nunca existe banco com dados e sem marca,
nem marca sem os dados que ela declara. `concluida_em` preenchido significa carga inteira, e
é exatamente isso que a checagem 17 de [`verify-sh.md`](verify-sh.md) usa para distinguir
banco carregado de banco pela metade.

## Decisão adiada: hash da origem

Registrado como **considerado e adiado**, não como esquecimento: uma coluna `origem_hash`
guardando o hash de cada arquivo de `data/raw/` consumido, para o `verify.sh` recomputar e
detectar banco velho — carga completa, porém feita antes de o dump mudar.

Adiado porque hoje o dump não muda: veio do cliente uma vez e está versionado, e a checagem
12 do `verify.sh` reprova qualquer modificação local nele. Enquanto isso valer, comparar
`linhas_lidas` com a contagem do arquivo cobre a maior parte do risco — falha só quando a
alteração preserva o número de linhas.

Reabrir quando o dump passar a ser reenviado ou atualizado.
