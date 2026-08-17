# 0002 — `setup.sh` muta, `verify.sh` diagnostica

## Problema

Os dois scripts conhecem a mesma lista de coisas que o ambiente precisa ter: `uv`, a versão
de Python pinada, o `.venv`, o `.env`, o banco. A tentação é juntar — um script só que monta
e confere, ou um setup que valida o que acabou de fazer.

## Opções

1. **Um script só**, com flag `--check`. Menos arquivo, uma lista só.
2. **Setup que confere ao final** o que produziu.
3. **Dois scripts com papéis disjuntos**: o setup muta e não julga; o verify julga e não muta.

## Escolha

Opção 3. O `setup.sh` não faz nenhuma checagem de credencial nem emite diagnóstico, e a
última linha da sua saída de sucesso aponta para `./scripts/verify.sh`. O `verify.sh` não
instala, não sincroniza, não copia `.env` e não gera banco.

Do lado do setup, a regra tem uma consequência que parece inconsistência e não é: ele
**não sobrescreve o `.env`**. Existindo, é mantido como está, inclusive incompleto ou
desatualizado. Chave que faltar é a checagem 6 do verify, não problema do setup.

## Porquê

**Contra a opção 1 e 2:** a lógica de checagem duplicada diverge. Não em teoria — a lista
muda toda vez que entra uma dependência ou uma chave nova, e a cópia que ninguém lembrou de
atualizar passa a aprovar ambiente quebrado. Com papéis disjuntos existe uma lista só, e ela
mora no verify.

**Sobre o `.env`:** um `cp` descuidado apaga credencial que ninguém tem cópia. É a única
coisa no repositório que o usuário digitou à mão e não pode recuperar de lugar nenhum — nem
do git, nem regerando. Preservar o arquivo desatualizado e deixar o verify reclamar custa
uma linha de relatório; sobrescrever custa uma chave.

A relação entre os dois é o que dá sentido ao par: **o setup produz exatamente o que o
verify confere.** Checagem nova no verify implica passo correspondente no setup, e vice-versa.
Está especificado nas capabilities `ambiente-setup` e `ambiente-verificacao`.
