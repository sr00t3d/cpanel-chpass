[🇺🇸 English](README.md) | 🇧🇷 **Português (BR)** | [🇪🇸 Español](README-es.md)

# cpanel-chpass — Alterador e Rotacionador Seguro de Senhas cPanel/WHM

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.0.0-brightgreen.svg)](https://github.com/sr00t3d/cpanel-chpass/releases)
[![Bash](https://img.shields.io/badge/Linux-Bash%204.0%2B-4EAA25?logo=gnu-bash&logoColor=white)](chpass.sh)

O **`chpass.sh`** é uma CLI em Bash para alterar e rotacionar senhas de contas cPanel/WHM (com sincronização automática do MySQL) usando a API oficial **`whmapi1 passwd`** (com fallback para `/scripts/chpass`), geração criptográfica de senhas fortes (`/dev/urandom`), bloqueio estrito contra `root` e usuários de sistema (`UID < 500`), rotação em lote/revenda, `--dry-run`, salvamento em `chmod 600` e saídas `table`, `json` e `csv`.

> **Inspiração Histórica:** Reimplementação limpa em Bash inspirada no `chpass` (`ecpp_2.pl`, 2012, **Michael Karr** / HostGator Toolbox). Substitui a chamada interna legada `Cpanel::ChangePasswd` e o gerador `rand()` fraco por `whmapi1`, senhas CSPRNG, dry-run e rotação em lote para resposta a incidentes.

---

## Execução Direta (Linux / cPanel)

```bash
# Simulação dry-run sem clonar o repositório
bash <(curl -fsSL https://raw.githubusercontent.com/sr00t3d/cpanel-chpass/main/chpass.sh) alice --dry-run
```

---

## Instalação e Uso

```bash
git clone https://github.com/sr00t3d/cpanel-chpass.git
cd cpanel-chpass
chmod +x chpass.sh

# Gerar senha forte de 16 caracteres automaticamente (sincroniza MySQL)
sudo ./chpass.sh alice

# Definir senha específica sem alterar o MySQL
sudo ./chpass.sh alice 'Str0ng#Pass2026!' --no-mysql

# Simular rotação em massa de uma revenda em JSON
sudo ./chpass.sh -r minharevenda --dry-run -o json

# Resposta a incidentes: rotacionar lista de contas salvando em arquivo chmod 600
sudo ./chpass.sh -f comprometidas.txt --save /root/credenciais-rotacionadas.txt
```

---

## Exemplo Real de Saída

```text
USERNAME           PASSWORD             STATUS     MESSAGE
------------------ -------------------- ---------- ------------------------------
demoacct           k9#Lm2@pQ7xR4^vN     dry_run    Simulated via whmapi1 (mysql_sync=1, digest=0)

Summary: 1 processed | 1 ok | 0 failed
```

---

## Autor & Licença

Desenvolvido por **Percio Castelo** ([perciocastelo.com.br](https://perciocastelo.com.br)).
Inspirado no `chpass` (`ecpp_2.pl`, 2012, **Michael Karr** / HostGator Toolbox).

Licenciado sob a [Apache License 2.0](LICENSE).
