# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

O repositório é escrito em português (README, commits, docs, nomes de módulo). Mantenha esse idioma em código novo, documentação e mensagens de commit.

## Estado atual

O projeto está no bootstrap: existe o esqueleto de diretórios, o `pyproject.toml`
e o dump bruto do PDV. **Ainda não existem** `src/bom_preco/`, `scripts/setup.sh`,
`scripts/verify.sh` nem specs em `openspec/` — o README descreve o alvo, não o
que já está no disco. Verifique antes de assumir que um caminho citado no README existe.

## Comandos

```bash
./scripts/setup.sh                    # monta o ambiente (a criar)
./scripts/verify.sh                   # confere que o ambiente está utilizável (a criar)
uv run python -m bom_preco.carga      # carga: data/raw/*.csv.gz -> data/bom_preco.db
uv run python -m bom_preco            # executa o agente
```

Toda execução Python passa por `uv run` — não há ativação manual de virtualenv.
Dependências entram via `uv add`, nunca editando `pyproject.toml` na mão.

Python está pinado em **3.13** (`.python-version` e `requires-python`); o README
ainda diz 3.11+, o pin vale mais.

## Convenções de trabalho (do README, e elas mandam)

**A especificação vem antes.** Nenhuma mudança é implementada sem estar descrita e
acordada em `openspec/`. Diante de um pedido de implementação sem spec correspondente,
escreva/atualize a spec primeiro ou aponte a lacuna.

**O harness impõe o caminho.** Qualquer passo que precise acontecer numa ordem certa
vira script em `scripts/`, não instrução de README. `verify.sh` valida credencial
fazendo a chamada real ao provedor — checar se a variável de ambiente existe não conta.

**O dado bruto é imutável.** `data/raw/*.csv.gz` é o que o cliente enviou, com toda a
sujeira. Nunca edite, descomprima no lugar nem "corrija" esses arquivos. Limpeza
acontece na carga.

**O banco é derivado.** `data/bom_preco.db` não é versionado. A carga tem que ser
determinística: apagar o `.db` e rodar de novo produz o mesmo resultado, e ela emite
relatório de linhas inseridas / corrigidas / descartadas.

**As decisões ficam registradas.** Escolha de arquitetura relevante vira documento em
`docs/decisoes/`: problema, opções, escolha, porquê.

## Os dados brutos

Dois CSVs gzipados, separador `;`, cabeçalho na primeira linha:

- `produtos.csv` (~716 linhas) — `codigo;descricao;categoria;marca;unidade;preco_venda;codigo_barras;fornecedor;data_cadastro`
- `vendas.csv` (~374k linhas) — `cupom;data_hora;caixa;codigo_produto;descricao_produto;quantidade;valor_unitario;valor_total_item;forma_pagamento;valor_total_cupom`

Sujeira já mapeada, que a carga precisa tratar:

- **Datas em dois formatos** em `vendas.data_hora`: `yyyy-mm-dd hh:mm:ss` (~279k linhas)
  e `dd/mm/yyyy hh:mm:ss` (~96k). `produtos.data_cadastro` é `dd/mm/yyyy`.
- **Números em pt-BR**: vírgula decimal (`27,90`, `2,640`), sem separador de milhar.
- **~5,2k linhas de venda com valores negativos** — provável devolução/estorno; decidir
  e registrar o tratamento em `docs/decisoes/`.
- **Produto duplicado**: o mesmo item aparece com códigos diferentes e descrições
  divergentes (`ARROZ TIO JOAO 5KG` vs `Arroz Tio Joao 5 kg`) — ~17 grupos por
  descrição normalizada. Caixa e espaçamento são inconsistentes.
- **Categoria bagunçada**: 104 produtos sem categoria, e o mesmo conceito com rótulos
  distintos (`Grãos e cereais` vs `MERCEARIA`, `Laticínios` vs `LATICINIOS`,
  `LIMP` vs `LIMPEZA`, `Higiene` vs `Higiene pessoal`).
- **`codigo_barras` frequentemente vazio.**
- `valor_total_cupom` é denormalizado — repetido em cada item do cupom.
- Integridade referencial está ok: todo `vendas.codigo_produto` existe em `produtos.codigo`.

`forma_pagamento` ∈ {DEBITO, CREDITO, DINHEIRO, PIX, VALE}. Período coberto: 2023 em diante.

## Stack alvo

Pydantic para contratos e validação, LangGraph para orquestração do agente, Langfuse
self-hosted para observabilidade, SQLite para os dados, uv para ambiente, OpenSpec para
especificação. Segredos em `.env` (modelo em `.env.example`): `OPENAI_API_KEY`,
`LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_HOST`.

## Commits

Prefixo de tipo em português no imperativo/substantivo curto, como no histórico:
`chore: bootstrap do projeto Python`, `data: dump inicial do PDV enviado pelo cliente`,
`docs: README e gitignore iniciais`.
