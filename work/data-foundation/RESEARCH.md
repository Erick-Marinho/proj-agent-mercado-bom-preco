# Raw Data Research

Snapshot do que existe em `data/raw/` — o dump do PDV como o cliente enviou.
Descreve a realidade encontrada; não propõe tratamento.

**Base da snapshot** — arquivos lidos sem alteração, em 2026-08-13:

| arquivo | md5 | comprimido | descomprimido |
|---|---|---|---|
| `data/raw/produtos.csv.gz` | `8c2043e49ff39ae1bc03fba355be253a` | 21.208 B | 72.899 B |
| `data/raw/vendas.csv.gz` | `8187fb933f6029c95fc593d740a07bfc` | 6.528.637 B | 34.532.725 B |

**Convenção deste documento:** afirmações não marcadas são fatos medidos sobre
100% das linhas. Leituras não confirmadas pelos arquivos aparecem só em blocos
marcados **Hipótese**.

---

## Dataset overview

Dois CSVs comprimidos em gzip, gerados em 2026-08-02 (nomes internos
`produtos.csv` e `vendas.csv`).

| | produtos | vendas |
|---|---|---|
| Encoding | UTF-8 válido, sem BOM | UTF-8 válido, sem BOM |
| Quebra de linha | CRLF em 717/717 linhas | CRLF em 374.475/374.475 |
| Delimitador | `;` | `;` |
| Aspas / escape | nenhuma ocorrência de `"` | nenhuma ocorrência de `"` |
| Colunas | 9 | 10 |
| Linhas de dados | 716 | 374.474 |
| Grão | um produto do catálogo | um **item de cupom** |

Contagem de colunas íntegra em todas as linhas: 5.736 `;` ÷ 717 = exatamente 8
em produtos; 3.370.275 `;` ÷ 374.475 = exatamente 9 em vendas. Nenhum campo
contém o delimitador; nenhuma linha tem contagem de colunas quebrada.

`produtos` é o catálogo; `vendas` é uma junção desnormalizada cupom × item.

---

## Observed structure

**produtos**

```
codigo;descricao;categoria;marca;unidade;preco_venda;codigo_barras;fornecedor;data_cadastro
87305;ARROZ TIO JOAO 5KG;Grãos e cereais;Tio Joao;PCT;27,90;;Distribuidora Vale Verde;10/06/2020
```

- `codigo` — 716 valores únicos, numéricos, 4 ou 5 dígitos, faixa 1169–99945.
- `unidade` — 3 valores: `UN` 468, `PCT` 195, `KG` 53.
- `fornecedor` — 8 valores, nenhum vazio.
- `preco_venda` — R$ 2,49 a R$ 79,90 (mediana R$ 9,75). Nenhum zero ou negativo.
- `data_cadastro` — 2019-03-02 a 2025-03-04.

**vendas**

```
cupom;data_hora;caixa;codigo_produto;descricao_produto;quantidade;valor_unitario;valor_total_item;forma_pagamento;valor_total_cupom
C100001;01/01/2023 07:41:51;2;72234;PAO FRANCES KG;2,640;17,38;45,88;PIX;202,09
```

- `cupom` — 77.536 distintos, padrão `C######`, de `C100001` a `C177536`,
  **sequência contígua sem buracos**. Cresce monotonicamente linha a linha.
- 1 a 15 itens por cupom (moda 2).
- `caixa` — 4 valores (`1`–`4`), volume equilibrado (92.220 a 95.570 linhas).
- `forma_pagamento` — 5 valores: `DEBITO` 112.220, `CREDITO` 94.493,
  `DINHEIRO` 82.357, `PIX` 75.106, `VALE` 10.298.
- Colunas de cabeçalho de cupom (`data_hora`, `caixa`, `forma_pagamento`,
  `valor_total_cupom`) são consistentes dentro de cada cupom: **0 cupons com
  mais de um valor** em qualquer uma delas.
- **Zero linhas 100% duplicadas.**

**Ordenação de `vendas`:** ordenado por `cupom`; a data (dia) é não-decrescente,
mas **o horário dentro de um mesmo dia não é ordenado** — 37.802 pares fora de
ordem cronológica. Ex.: `C100005` (01/01/2023 20:36) precede `C100006`
(01/01/2023 10:41).

### Descontinuidade de formato em 2023-09-01

Os dois arquivos mudam de convenção no mesmo ponto do tempo, **sem sobreposição**:

| | formato de data | separador decimal | intervalo | n |
|---|---|---|---|---|
| vendas, bloco 1 | `dd/mm/aaaa HH:MM:SS` | vírgula | 2023-01-01 07:35:49 → **2023-08-31 21:23:58** | 95.749 |
| vendas, bloco 2 | `aaaa-mm-ddTHH:MM:SS` | ponto | **2023-09-01 07:37:48** → 2025-06-30 21:40:30 | 278.725 |
| produtos, bloco 1 | `dd/mm/aaaa` | vírgula | 2019-03-02 → **2023-08-27** | 536 |
| produtos, bloco 2 | `aaaa-mm-dd` | ponto | **2023-09-02** → 2025-03-04 | 180 |

- Correlação formato-de-data × separador-decimal: **100%** nos dois arquivos
  (tabela cruzada sem nenhuma célula fora da diagonal).
- Em `vendas` os dois blocos são **contíguos no arquivo** — exatamente 2 blocos,
  nenhuma intercalação.
- As 4 colunas numéricas de `vendas` trocam de separador juntas.
- `dd/mm/aaaa` é inequívoco: 333 datas de produtos têm dia > 12; **nenhuma** tem
  mês > 12.

---

## Quantitative findings

**Cobertura temporal de `vendas`:** 2023-01-01 07:35:49 a 2025-06-30 21:40:30.
912 dias distintos, **zero dias sem venda** no intervalo. Horários entre
07:00:00 e 21:59:58.

**Volume**

| ano | linhas | soma de `valor_total_item` |
|---|---|---|
| 2023 | 151.409 | R$ 3.606.866,89 |
| 2024 | 150.829 | R$ 3.609.524,18 |
| 2025 (até 30/06) | 72.236 | R$ 1.695.853,62 |
| **total** | **374.474** | **R$ 8.912.244,69** |

Cupons por dia: mínimo 16, mediana 80, máximo 207. Média mensal entre 66,0
(jan/2025) e 109,4 (dez/2024). Dezembro é o pico nos dois anos completos;
janeiro é o vale.

Distribuição por dia da semana (linhas): sáb 78.813 · sex 67.319 · qui 52.324 ·
qua 49.506 · seg 45.267 · ter 43.905 · dom 37.340.

**Faixas dos numéricos de `vendas`**

| coluna | mín | mediana | máx | negativos | zeros |
|---|---|---|---|---|---|
| `quantidade` | −6,000 | 1,000 | 6,000 | 5.195 | 0 |
| `valor_unitario` | 2,42 | 10,10 | 84,69 | 0 | 0 |
| `valor_total_item` | −357,60 | 14,68 | 376,62 | 5.195 | 0 |
| `valor_total_cupom` | −543,37 | 135,54 | 945,78 | 4.866 | 0 |

**Cardinalidade em `vendas`:** 714 `codigo_produto` distintos, 1.112
`descricao_produto` distintas, 13.225 `valor_unitario` distintos.

---

## Data quality findings

### Campos vazios

`produtos` — o vazio é string vazia, não `NULL` nem sentinela:

| coluna | vazios | % |
|---|---|---|
| `categoria` | 104 | 14,53% |
| `marca` | 104 | 14,53% |
| `codigo_barras` | 140 | 19,55% |
| outras 6 colunas | 0 | 0% |

`categoria` e `marca` vazias **não são as mesmas linhas**: 421 produtos têm os
três campos preenchidos, 2 têm os três vazios, e todas as 6 combinações
intermediárias ocorrem.

`vendas` — **zero campos vazios nas 10 colunas.**

### `categoria`: 43 rótulos para ~20 conceitos

Quatro estilos convivem — título acentuado, sem acento, caixa-alta e abreviação:

```
Laticínios 60 · LATICINIOS 7 · Laticinios 6
Grãos e cereais 60 · Graos e cereais 5 · GRAOS E CEREAIS 3
Padaria 44 · PAD 5 · PADARIA 2
BEBIDAS 4 · BEB 3 · Bebida 2 · bebidas 1
Casa 30 · Roupa 30 · LIMP 8 · LIMPEZA 6 · Limpeza roupa 4 · Limpeza casa 3
```

`marca` tem 168 valores não-vazios, sem acentuação consistente (`Uniao`,
`Perdigao`, `Ype`, `Nestle`), enquanto as descrições usam acento (`CAFÉ`,
`ELEGÊ`, `LIMÃO`).

### `codigo_barras` não é confiável

576 preenchidos: todos com 13 dígitos, todos com prefixo `789`, **nenhum
repetido** — mas apenas **64 (11,1%) passam no dígito verificador EAN-13**
(o acaso puro daria ~10%). Não serve como chave nem como validador.

### Duas grafias por produto em `vendas`

462 dos 714 códigos têm **exatamente 2** grafias de `descricao_produto`
(252 têm 1; nenhum tem 3+). A grafia minoritária responde por ~5% das linhas e
está **uniformemente distribuída** entre os 4 caixas (4,91% / 5,01% / 5,02% /
4,91%), entre os 3 anos e entre os dois blocos de formato.

282 dessas variantes minoritárias têm **exatamente 28 caracteres**, várias
terminando no meio de uma palavra:

```
cod=19031  maioria 'CAFE MELITTA TRAD 500G'          minoria 'CAFE MELITTA TRADICIONAL 500'
cod=69990  maioria 'QJO MUSS FAT 150G'               minoria 'QUEIJO MUSSARELA FATIADO 150'
cod=37129  maioria 'LEITE INT UHT ITALAC PACK 12UN'  minoria 'LEITE INTEGRAL UHT ITALAC PA'
cod=98995  maioria 'MAC ADRIA ESPAGUETE 500G'        minoria 'MACARRÃO ADRIA ESPAGUETE 500'
```

O limite de 28 **não vale para o arquivo todo**: 194 descrições distintas
passam de 28 caracteres (máximo 40).

713 dos 714 códigos têm ao menos uma grafia idêntica à do cadastro. A exceção é
`37600`: cadastro `'VINHO PEROLA TINTO SECO 750ML'` (29 chars), vendas sempre
`'VINHO PEROLA TINTO SECO 750M'` (28).

46 textos de descrição são usados por **mais de um** `codigo_produto` — ex.
`'ACHOC NESCAU 400G'` → `26130` e `44550`; `'BISCOITO CREAM CRACKER ADRIA'`
→ 4 códigos.

### 18 pares de códigos com descrição equivalente no catálogo

Equivalência = mesmo texto após remover acento, caixa, espaço e pontuação.
36 linhas envolvidas, todas com vendas próprias. Preços divergem muito em
alguns pares:

```
87216 'SHAMPOO SEDA 325ML'     R$14.90 cat='PERFUMARIA'      ean=sim    166 vendas
65918 'SHAMPOO SEDA 325ML'     R$27.39 cat='Higiene'         ean=sim    184 vendas   (1,84x)

63417 'PAP TOALHA NEVE 2UN'    R$ 9,90 cat='LIMPEZA'         ean=sim    199 vendas
72714 'PAP TOALHA NEVE 2UN'    R$15,31 cat=''                ean=não    212 vendas   (1,55x)

19031 'CAFE MELITTA TRAD 500G' R$17,50 cat='Graos e cereais' ean=sim  6.976 vendas
 4164 'CAFÉ MELITTA TRAD 500G' R$13,38 cat='Grãos e cereais' ean=não    371 vendas

26130 'ACHOC NESCAU 400G'      R$ 9.90 cat='Grãos e cereais' ean=sim  3.757 vendas
44550 'ACHOC NESCAU 400G'      R$ 8,67 cat='Grãos e cereais' ean=sim  3.753 vendas
```

Os pares não se comportam de um jeito só: alguns têm volume de vendas quase
idêntico nos dois códigos (Nescau: 3.757 / 3.753), outros têm volume muito
desigual (Melitta: 6.976 / 371).

### Quantidades negativas — 5.195 linhas (1,387%)

`valor_unitario` é positivo em 100% delas; o sinal está em `quantidade` e
`valor_total_item`. Valores observados: apenas −1, −2, −3, −4, −6. Distribuídas
por todos os anos (2.209 / 2.000 / 986) e todas as formas de pagamento.

Agrupam-se em 1.559 cupons de **duas naturezas distintas**:

- **1.013 cupons 100% negativos.** Todos com `valor_total_cupom` < 0.
  **994 (98,1%)** têm um cupom inteiramente positivo em outro ponto do arquivo
  com exatamente o mesmo conjunto `(produto, |quantidade|)`. Os outros 19 não.
- **546 cupons mistos** (linhas positivas e negativas juntas); 76 fecham com
  total negativo. Em **0 dos 546** o produto da linha negativa aparece também
  positivo no mesmo cupom.

Exemplo de misto (`C100024`, 01/01/2023, fecha em R$ 118,00 positivo): 7 itens
positivos e um único `MANTEIGA AVIACAO 200G` com quantidade `-2,000`.

> **Hipótese (não confirmada).** Cupons 100% negativos seriam devoluções ou
> estornos — o espelhamento de 98,1% sustenta a leitura. Mas o espelhamento é
> **inferido por coincidência de conjunto**: não há chave de estorno, cupom de
> origem nem código de operação nos arquivos. Já os cupons mistos contrariam a
> leitura mais natural (cancelar item recém-passado), justamente porque o
> produto negativo nunca aparece positivo no mesmo cupom.

### `quantidade × valor_unitario ≠ valor_total_item` — 11.129 linhas (2,972%)

A diferença é rigorosamente limitada e sempre no mesmo sentido:

- `|diferença| ≤ R$ 1,50` — **zero** casos acima disso;
- em linha positiva a diferença é **sempre negativa**; em linha negativa,
  **sempre positiva**. A operação sempre **reduz o valor absoluto**;
- módulo quase uniforme entre R$ 0,00 e R$ 1,50 (histograma de 0,10 em 0,10:
  853, 704, 737, 641, 761, 740, 727, 825, 726, 630, 847, 761, 780, 826, 345);
- **nunca zera nem inverte o item** (0 casos de total ≤ 0 em linha positiva);
- espalhada por 691 dos 714 produtos, taxa idêntica nos 4 caixas
  (2,93%–3,04%), presente em todos os meses dos dois blocos de formato.

Exemplo extremo (`C150849`): `CEBOLA KG`, quantidade `0.422`, unitário `5.34`,
total `0.88` — 0,422 × 5,34 = 2,25; diferença de −1,37, ou 61% do item.

> **Hipótese (não confirmada).** Desconto de caixa. Contra: um desconto
> comercial dificilmente seria uniforme entre R$ 0,00 e R$ 1,50
> **independentemente do valor do item** (61% numa cebola de R$ 2,25, ~1% num
> item de R$ 100). Arredondamento de balança, promoção por unidade e ruído de
> geração são igualmente compatíveis com a evidência.

**`valor_total_cupom` é internamente coerente:** igual à soma dos
`valor_total_item` do cupom em **77.536 de 77.536** cupons (tolerância
R$ 0,011). A diferença do item acima **não** reaparece no cabeçalho.

### Dispersão intradiária de `valor_unitario`

25,9% dos pares (produto, dia) — 55.992 de 216.060 — têm mais de um
`valor_unitario`. Ex.: `CAFE MELITTA TRAD 500G` em 01/01/2023 aparece a
17,12 / 17,17 / 17,25 / 17,42 / 17,75 / 17,76 / 18,47.

**Não é tendência de preço:** a mediana mensal do mesmo produto vai de 17,75
(jan/2023) a 17,79 (jun/2025) — estável ao longo de 30 meses.

`valor_unitario` máximo em vendas (84,69) **excede** o `preco_venda` máximo do
catálogo (79,90).

### Queda de volume de 12 a 18/08/2024

Cupons/dia na semana: 26, 36, 35, 22, 50, 41, 16 — contra média de 72,6 no mês
e ~85–90 nos meses vizinhos. Os dias existem no arquivo, com ~1/3 a 1/2 do
movimento. É o único período assim em 912 dias.

---

## Potential relationships

### Chave produto ↔ venda: `codigo` = `codigo_produto` (confirmado)

- **0 de 374.474** registros de venda têm `codigo_produto` ausente do catálogo.
  Integridade referencial perfeita nesse sentido.
- **714 dos 716** produtos aparecem em vendas. Os 2 ausentes:
  `16397` `REFRIG FANTA ZERO 2L` (cadastro 06/08/2022) e
  `45539` `CAFÉ TRES CORACOES TRAD 250G` (cadastro 2024-02-03).

### `unidade` explica a fração da quantidade (confirmado)

| `unidade` do catálogo | quantidade fracionária | quantidade inteira |
|---|---|---|
| `KG` | 38.997 | 27 |
| `PCT` | 0 | 105.825 |
| `UN` | 0 | 229.625 |

Nenhuma quantidade fracionária ocorre fora de `KG`.

### `preco_venda` acompanha o praticado (confirmado)

Razão mediana(`valor_unitario`) / `preco_venda`, sobre os 714 produtos vendidos:
mediana 1,015 · p10 1,012 · p90 1,018 · mín 0,971 · máx 1,049.

### `data_cadastro` não delimita o período de venda (confirmado)

**252 dos 714** produtos foram vendidos **antes** da própria `data_cadastro`:

```
cod=91289 CR DENTAL CLOSE UP 90G      1ª venda 2023-01-01  cadastro 2024-12-28
cod=89768 ÁGUA MINERAL CRYSTAL 1,5L   1ª venda 2023-01-01  cadastro 2024-11-04
cod=38024 DET YPE LIMÃO 500ML         1ª venda 2023-01-01  cadastro 2024-08-07
```

> **Hipóteses (não confirmadas) sobre a descontinuidade de 2023-09-01.**
> (a) Troca de sistema de PDV — explica a mudança simultânea nos dois arquivos.
> (b) Exportação em dois lotes com configurações regionais diferentes, sem
> troca de sistema. Nada nos arquivos nomeia sistema, versão ou origem; as duas
> leituras são igualmente compatíveis com a evidência. Se (a) for verdade, as
> `data_cadastro` reescritas na migração explicariam os 252 casos acima — mas
> isso é conjectura sobre conjectura.

> **Hipótese (não confirmada).** Os 18 pares de descrição equivalente seriam
> cadastro duplicado do mesmo produto. Contra: o par `SHAMPOO SEDA 325ML` a
> R$ 14,90 e R$ 27,39 é candidato mais forte a **produtos diferentes com
> descrição pobre** do que a duplicata.

---

## Open questions

Perguntas cujo significado **não é resolvível a partir dos arquivos**.

**Impacto direto em qualquer número de faturamento**

1. O que é um cupom 100% negativo — devolução, estorno, cancelamento fiscal?
   Ele **anula** um cupom positivo (os dois saem do faturamento) ou é
   lançamento independente? E os 19 sem par?
2. O que significa uma linha negativa dentro de um cupom que fecha positivo,
   sendo que o produto não aparece positivo no mesmo cupom?
3. O que é a diferença de até R$ 1,50 por item? "Vendemos R$ X de arroz" deve
   usar `valor_total_item` ou `quantidade × valor_unitario`? Os dois números
   divergem em ~R$ 8,5 mil no total.
4. Existe, no PDV de origem, campo de tipo de operação ou de cupom estornado
   que não veio nesta exportação?
5. `VALE` (10.298 linhas, 2,7%) é vale-alimentação, vale-funcionário,
   crediário? Conta como receita?

**Catálogo**

6. Os 18 pares de descrição equivalente são o mesmo produto com cadastro
   duplicado, ou produtos distintos? Precisa de decisão **caso a caso** — os
   pares se comportam de formas diferentes demais para uma regra única.
7. `categoria` vazia em 14,5% significa "sem categoria" ou "não informado na
   exportação"? `LIMP` / `LIMPEZA` / `Limpeza casa` / `Limpeza roupa` / `Casa`
   / `Roupa` são 6 categorias ou 2 conceitos escritos de 6 jeitos? Existe
   árvore de categorias oficial do mercado?
8. `data_cadastro` é entrada do produto no sistema atual ou no negócio?
9. `preco_venda` é o preço de tabela vigente hoje, ou o do momento do cadastro?
10. Por que 2 produtos cadastrados nunca venderam em 912 dias — descontinuados,
    ou cadastro que nunca entrou em operação?

**Origem e cobertura**

11. Houve troca de PDV em 2023-09-01, ou os dois blocos são dois lotes de
    exportação? Se houve troca: os `codigo` foram preservados, ou algum código
    foi reaproveitado para outro produto? Isso decide se a série de 2,5 anos é
    comparável ponta a ponta.
12. O que aconteceu entre 12 e 18/08/2024? Os arquivos não distinguem "vendeu
    pouco" de "registrou pouco".
13. Os dados terminam em 2025-06-30. Haverá carga incremental ou o histórico é
    fechado? Isso muda o significado de "semana passada" numa pergunta.
14. `caixa` 1–4 são terminais físicos fixos? Algum é autoatendimento ou balcão?
15. A dispersão intradiária de `valor_unitario` (25,9% dos produto-dia) é
    preço por cliente, promoção por horário, ou artefato da geração dos dados?
