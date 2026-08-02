# Mercado Bom Preço — Assistente de Análise de Vendas

Assistente que responde perguntas sobre as vendas de um mercado em linguagem natural e devolve o dado e um gráfico.

```
Pergunta: "Quantas vendas de papel higiênico tivemos semana passada?"
Resposta: "340 unidades, R$ 2.180,00" + gráfico por marca
```

> **Projeto-laboratório.** O Mercado Bom Preço, o Seu Renato e todos os dados
> deste repositório são fictícios.

---

## Stack

| Camada | Ferramenta |
|---|---|
| Linguagem | Python |
| Contratos e validação | Pydantic |
| Orquestração do agente | LangGraph |
| Observabilidade | Langfuse (self-hosted) |
| Dados | SQLite |
| Ambiente | uv |
| Especificação | OpenSpec |

## Rodando localmente

**Pré-requisitos:** Python 3.11+, [uv](https://docs.astral.sh/uv/), Docker e Docker Compose.

```bash
git clone git@github.com:Erick-Marinho/proj-agent-mercado-bom-preco.git
cd proj-agent-mercado-bom-preco
./scripts/setup.sh
```

O `setup.sh` monta o ambiente. O `verify.sh` confere que ele está utilizável:

```bash
./scripts/verify.sh
```

> Documentação ensina, script obriga. Um README pode ser lido pela metade,
> seguido fora de ordem ou ignorado. Um script que roda do começo ao fim e falha
> alto quando algo está errado não permite nada disso.

### Credenciais

```bash
cp .env.example .env
```

Preencha o `.env`. Nenhum segredo entra no controle de versão.

> Validar credencial não é verificar se a variável existe — é fazer a chamada
> real e confirmar que ela responde. Chave revogada falha igual a variável vazia,
> só que mais tarde e de forma mais confusa. É isso que o `verify.sh` faz.

### Carga dos dados

O repositório traz o dump do PDV como o cliente enviou, comprimido e intocado.
O banco é **derivado**: gerado pela carga, não versionado.

```bash
uv run python -m bom_preco.carga
```

A carga é determinística — apagar o `.db` e rodar de novo produz o mesmo
resultado. Ela emite um relatório de quantas linhas entraram, quantas foram
corrigidas e quantas ficaram de fora.

### Executando

```bash
uv run python -m bom_preco
```

## Estrutura

```
.
├── scripts/               # o harness: setup.sh, verify.sh
├── openspec/              # especificações e mudanças propostas
├── data/
│   ├── raw/               # dump original comprimido — nunca se edita
│   │   ├── produtos.csv.gz
│   │   └── vendas.csv.gz
│   └── bom_preco.db       # gerado pela carga, não versionado
├── src/
│   └── bom_preco/
├── evals/                 # conjunto de avaliação
└── docs/
    ├── decisoes/          # registro das decisões de arquitetura
    └── problemas-conhecidos.md
```

## Como trabalhamos

**A especificação vem antes.** Nenhuma mudança é implementada sem estar descrita
e acordada em `openspec/`. A especificação é a fonte de verdade; o código a segue.

**O harness impõe o caminho.** Tudo que precisa ser feito na ordem certa vira
script em `scripts/`. Combinado que depende de memória é combinado que se quebra.

**O dado bruto é imutável.** `data/raw/` guarda o que o cliente enviou, com toda
a sujeira. Limpeza acontece na carga, e o resultado é descartável e reconstruível.

**As decisões ficam registradas.** Cada escolha de arquitetura relevante vira um
documento em `docs/decisoes/`: qual era o problema, quais opções existiam, o que
foi escolhido e por quê. É o registro do raciocínio — a parte que se perde quando
só o código sobrevive.

## Licença

Uso educacional. Dados e cliente fictícios.