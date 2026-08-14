# AGENTS.md

> Este arquivo é um **mapa**, não uma enciclopédia. Ele guarda só o que vale
> para **qualquer** tarefa neste repositório. O que importa apenas às vezes
> mora no arquivo do assunto — os ponteiros estão em "Onde procurar".

## O que é este projeto

Projeto que constrói incrementalmente uma solução para permitir que Seu Renato consulte e compreenda os dados históricos de produtos e vendas do seu mercado.

## Ambiente

Python **3.13** (fixado em `.python-version`), com **uv** cuidando de
interpretador, venv e dependências.

- Executar: `uv run python <arquivo>` — não é preciso ativar o `.venv`.
- Adicionar dependência: `uv add <pacote>` — atualiza `pyproject.toml` e `uv.lock` juntos.
- Configurar a máquina do zero: `./scripts/setup.sh` (guia — age).
- Conferir o estado do ambiente: `./scripts/verify.sh` (sensor — só observa).

O `verify.sh` lista **todas** as falhas de uma vez, cada uma com a linha
`corrigir:` pronta para copiar. Leia essa linha antes de inventar um conserto
próprio. Saída `1` significa ambiente não apto.

## Regras que valem sempre

1. **Deixe o `uv` gerenciar Python, venv e dependências.** Ele é a única via —
   inclusive para instalar o interpretador.
2. **Trate o `.env` como somente-leitura.** Para introduzir uma variável,
   adicione-a ao `.env.example`; cada pessoa atualiza o próprio `.env`.
   Sobrescrever o `.env` de alguém destrói configuração local de forma irreversível.
3. **Dependência de ambiente nova entra nos dois scripts:** o passo que resolve
   vai para o `setup.sh`, a verificação que detecta vai para o `verify.sh`.
   Um sem o outro apodrece — convenções em `docs/SCRIPTS.md`.
4. **Antes de dar uma tarefa por concluída, rode `./scripts/verify.sh`.**

## Onde procurar

- Como começar, dados brutos e Docker → `README.md`
- Escrever ou alterar um script → `docs/SCRIPTS.md`
- Contrato do ambiente (versões exigidas) → constantes no topo de `scripts/verify.sh`
- Variáveis de configuração disponíveis → `.env.example`

## Manutenção deste arquivo

Antes de acrescentar uma regra aqui, pergunte: **isso vale para toda tarefa?**
Se vale só às vezes, o lugar dela é o arquivo do assunto, não este.

Quando um erro se repetir, prefira melhorar a regra que já existe a empilhar
mais uma proibição. E prefira descrever o domínio ("o projeto tem o conceito
de X") a descrever a geografia do código ("X fica em `src/y/z.py`") — arquivos
mudam de lugar, e um caminho errado aqui vira instrução falsa com ar de verdade.
