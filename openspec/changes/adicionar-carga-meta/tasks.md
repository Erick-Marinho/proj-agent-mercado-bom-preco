## 1. Estrutura do pacote

- [ ] 1.1 Criar `src/bom_preco/__init__.py`
- [ ] 1.2 Declarar no `pyproject.toml` onde o pacote mora, de modo que
      `uv run python -m bom_preco.carga` resolva o import
- [ ] 1.3 Confirmar que o segundo desfecho previsto no passo 5 do `setup.sh`
      (`No module named`) deixou de ocorrer

## 2. Leitura da origem

- [ ] 2.1 Abrir `data/raw/produtos.csv.gz` e `data/raw/vendas.csv.gz` em modo somente
      leitura, separador `;`, cabeçalho na primeira linha
- [ ] 2.2 Contar linhas de dados por origem, sem o cabeçalho, alimentando `linhas_lidas`
- [ ] 2.3 Garantir que nenhum caminho de código escreve em `data/raw/`

## 3. Escrita do banco

- [ ] 3.1 Recriar `data/bom_preco.db` do zero a cada execução, sem `UPDATE` sobre banco existente
- [ ] 3.2 Criar as tabelas `produtos` e `vendas` num esquema mínimo que sustente os
      contadores — o esquema definitivo e as regras de limpeza são do change seguinte
- [ ] 3.3 Criar a tabela `carga_meta` com as seis colunas especificadas, `origem` como chave primária
- [ ] 3.4 Envolver toda a execução numa transação única

## 4. Contadores e marca

- [ ] 4.1 Acumular `linhas_inseridas`, `linhas_corrigidas` e `linhas_descartadas` por origem
- [ ] 4.2 Tratar corrigida como subconjunto de inserida — linha normalizada que vira registro
      conta nas duas
- [ ] 4.3 Gravar `concluida_em` em ISO-8601 UTC como último statement antes do commit
- [ ] 4.4 Verificar `linhas_lidas == linhas_inseridas + linhas_descartadas` e
      `linhas_corrigidas <= linhas_inseridas` antes de fechar a transação

## 5. Relatório

- [ ] 5.1 Imprimir ao final os contadores por origem
- [ ] 5.2 Conferir que os números impressos são exatamente os gravados em `carga_meta`

## 6. Verificação

- [ ] 6.1 Rodar a carga duas vezes seguidas e confirmar que dados e contadores são idênticos,
      variando apenas `concluida_em`
- [ ] 6.2 Interromper a carga no meio (Ctrl-C) e confirmar que não resta banco com dados
      parciais nem linha em `carga_meta`
- [ ] 6.3 Rodar `./scripts/verify.sh` e confirmar que a checagem 17 passa
- [ ] 6.4 Rodar `./scripts/setup.sh` num ambiente limpo e confirmar que os cinco passos
      concluem e o exit code é `0`
