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
uv sync
cp .env.example .env
```

Preencha o `.env`. Nenhum segredo entra no controle de versão.

> Validar credencial não é verificar se a variável existe — é fazer uma chamada
> real e confirmar que ela responde. Chave revogada falha igual a variável vazia,
> só que mais tarde e de forma mais confusa.

```bash
uv run python -m bom_preco
```

## Estrutura

```
.
├── openspec/         # especificações e mudanças propostas
├── data/
│   ├── raw/          # dump original, com a sujeira preservada
│   └── bom_preco.db  # banco gerado (não versionado)
├── src/
│   └── bom_preco/
├── evals/            # conjunto de avaliação
└── docs/
    └── decisoes/     # registro das decisões de arquitetura
```

## Como trabalhamos

O desenvolvimento é orientado a especificação: antes de implementar, a mudança é
descrita e acordada em `openspec/`. A especificação é a fonte de verdade — o
código a segue, não o contrário.

Cada decisão de arquitetura relevante fica registrada em `docs/decisoes/`: qual
era o problema, quais opções existiam, o que foi escolhido e por quê. É o
registro do raciocínio, que é a parte que se perde quando só o código sobrevive.

## Licença

Uso educacional. Dados e cliente fictícios.