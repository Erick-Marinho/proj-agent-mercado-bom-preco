# Data Foundation — SPEC

Define **comportamento** da fundação de dados, não implementação.

Evidência que sustenta esta SPEC: [`work/data-foundation/RESEARCH.md`](../work/data-foundation/RESEARCH.md).
Toda contagem citada aqui vem de lá.

---

## Goal

Transformar o dump bruto do PDV numa base derivada consultável, **sem perder a
verdade sobre o que foi descartado ou alterado no caminho**.

O escopo é a fundação: ler o bruto, validar, carregar, e produzir evidência do
que aconteceu. Não é responder perguntas — é garantir que, quando as respostas
vierem, elas tenham procedência auditável.

A pesquisa mostrou que os arquivos contêm anomalias cujo **significado ainda não
é conhecido**: quantidades negativas, diferença de até R$ 1,50 por item, pares de
código com descrição equivalente. Esta SPEC não as resolve. Ela garante que
nenhuma delas seja resolvida por acidente.

---

## Behaviour

### B1 — O bruto é somente-leitura

Nenhuma execução escreve, move, renomeia ou recomprime arquivo em `data/raw/`.

*Verificável por:* hash dos arquivos brutos idêntico antes e depois de qualquer
execução.

### B2 — Nada entra sem validação explícita

Todo registro que chega à base derivada passou por uma validação declarada. Não
existe caminho em que um valor entre por ausência de checagem.

A validação cobre, no mínimo: contagem de colunas, encoding, campos
obrigatórios, e conversão de números e datas.

*Verificável por:* um registro inválido injetado em cópia do bruto não chega à
base derivada.

### B3 — Formato ambíguo falha; não se adivinha

Os dois formatos observados — `dd/mm/aaaa` com vírgula decimal e `aaaa-mm-dd`
com ponto decimal — são ambos aceitos, por regra explícita.

Um valor que não case com nenhum formato declarado é tratado como problema de
qualidade, **nunca** interpretado por heurística ou pelo locale do sistema.
`1.000` não vira 1000 ou 1,0 por inferência: ou a regra decide, ou a linha é
marcada.

*Verificável por:* as duas convenções carregam com o mesmo resultado semântico;
uma terceira convenção não passa silenciosamente.

### B4 — Toda linha tem destino declarado, e a soma fecha

Cada linha do bruto termina em exatamente uma categoria: **aceita**,
**corrigida** ou **rejeitada**.

```
linhas lidas = aceitas + corrigidas + rejeitadas
```

Esta igualdade é uma invariante da carga, não um relatório opcional.

*Verificável por:* a soma bate para os dois arquivos, em qualquer execução.

### B5 — Correção nunca é silenciosa

Toda linha corrigida registra o valor original, o valor resultante e a regra
aplicada. Toda linha rejeitada registra o motivo e a localização de origem
suficiente para encontrá-la no bruto.

Truncar, arredondar, preencher default ou normalizar texto **sem registro** é
violação desta SPEC.

*Verificável por:* para qualquer linha corrigida ou rejeitada, é possível
reconstruir o que ela era e por que mudou.

### B6 — Anomalia sem decisão é preservada e marcada

Quando o significado de um valor não foi decidido com o cliente, o comportamento
padrão é: **preservar o valor como está e sinalizá-lo**. Nunca descartar, nunca
normalizar por conta própria.

Vale hoje, no mínimo, para:

- quantidades negativas (5.195 registros);
- divergência entre `quantidade × valor_unitario` e `valor_total_item`
  (11.129 registros);
- produtos com descrição equivalente em códigos distintos (18 pares).

*Verificável por:* esses registros continuam recuperáveis na base derivada,
identificáveis como tal.

### B7 — Invariante observada vira verificação, não suposição

Propriedades medidas na pesquisa são **checadas na carga**, não assumidas. Se
uma delas deixar de valer, a carga reporta — não quebra em silêncio nem produz
número errado.

Mínimo:

- integridade referencial `vendas.codigo_produto` → `produtos.codigo`;
- `valor_total_cupom` igual à soma dos `valor_total_item` do cupom;
- consistência do cabeçalho (`data_hora`, `caixa`, `forma_pagamento`,
  `valor_total_cupom`) dentro de cada cupom.

*Verificável por:* violação injetada aparece no relatório.

### B8 — Cada execução produz evidência

A carga emite um relatório contendo, no mínimo:

- quantidades por destino (B4);
- contagem por motivo de rejeição e por regra de correção;
- contagem por sinalização de anomalia (B6);
- resultado de cada verificação de invariante (B7);
- intervalo temporal efetivamente carregado.

O relatório é o artefato que responde "o que aconteceu nesta carga" sem precisar
ler o código.

*Verificável por:* o relatório sozinho permite reconstruir os números de B4 e B7.

### B9 — A base derivada é reconstruível e descartável

Apagar a base e rodar a carga de novo, a partir do mesmo bruto, produz o mesmo
resultado — mesmos registros, mesmas contagens, mesmo relatório.

A base derivada não entra no controle de versão. O bruto é a única fonte.

*Verificável por:* duas execuções do zero produzem relatórios idênticos.

### B10 — Falha é alta e específica

Condição que impeça uma carga confiável — arquivo ausente, encoding inválido,
invariante estrutural quebrada — interrompe com mensagem que nomeia o problema.
Base parcial silenciosa não é resultado aceitável.

---

## Out of scope

Fora desta SPEC:

- o agente, LangGraph, linguagem natural, gráficos, Langfuse, evals;
- carga incremental — o escopo é o dump fechado (2023-01-01 a 2025-06-30);
- decidir se devoluções entram ou saem do faturamento;
- deduplicar os 18 pares de produto;
- normalizar a taxonomia de `categoria`;
- corrigir ou validar `codigo_barras`;
- reconciliar `data_cadastro` com a primeira venda;
- performance e otimização de consulta.

---

## Open decisions

### Precisam do cliente

Bloqueiam número de faturamento; **não** bloqueiam a carga. Enquanto sem
resposta, valem B6 e B7 — os dados ficam preservados e marcados.

1. O que é um cupom 100% negativo, e ele anula o cupom positivo espelhado?
2. O que é a linha negativa dentro de cupom que fecha positivo?
3. O que é a diferença de até R$ 1,50 por item — e qual coluna é a receita?
4. `VALE` conta como receita?

### Precisam de decisão técnica antes de implementar

5. A fronteira entre **corrigida** e **rejeitada**: uma data em formato
   desconhecido é linha rejeitada, ou campo nulo marcado?
6. Onde vive o relatório de B8 — stdout, arquivo versionável, tabela na própria
   base, ou mais de um?
7. Granularidade do rastro de B5: por linha, ou agregado por regra com amostra?
8. A carga é tudo-ou-nada, ou aceita resultado parcial declarado no relatório?
9. `verify.sh` deve checar algo sobre a base derivada, ou ela é ignorada por ser
   descartável? (AGENTS.md regra 3 se aplica a qualquer dependência nova que a
   carga introduzir.)

### Deliberadamente não decididas

Biblioteca ou driver SQLite, esquema da base, estrutura de módulos, nomes de
tipos e classes, formato de serialização do relatório.
