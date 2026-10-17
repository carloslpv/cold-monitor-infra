# cold-monitor-infra

[English](#english) · [Português (Brasil)](#português-brasil)

---

## English

Runs the whole **cold-monitor** system, a cold-chain temperature monitoring system, around the clock with Docker
Compose: PostgreSQL, the [backend](https://github.com/carloslpv/cold-monitor-backend), the
[dashboard](https://github.com/carloslpv/cold-monitor-dashboard) and, optionally, the
[sensor simulator](https://github.com/carloslpv/cold-monitor-simulator).

### How it fits together

```
browser / sensors ──> dashboard (nginx, port 8090) ──/api──> backend (8080) ──> postgres (5432)
```

- Only the dashboard publishes a port. nginx serves the page and forwards `/api` (REST and the live stream) to the
  backend, so browsers and sensors use one address and CORS is not involved. PostgreSQL and the backend are reachable
  only inside the compose network.
- Every service has `restart: unless-stopped`: containers come back after a crash, a Docker restart or a reboot (as
  long as Docker itself starts), and stay down only if you stop them.
- The backend waits for a healthy database, and the dashboard for a healthy backend. Health checks use `pg_isready`,
  `/actuator/health` and nginx's `/healthz`.
- Data lives in the `cold-monitor_postgres-data` volume and survives `docker compose down` and image rebuilds.
- Logs are rotated (5 files of 10 MB per container).

### Requirements

- Docker with Compose v2.24 or later (Docker Desktop on Windows/macOS). On Docker Desktop, turn on *Start Docker
  Desktop when you sign in* so the stack comes back after a reboot.
- The backend, dashboard and simulator repositories cloned next to this one; the images are built from them:

```
cold-monitor-backend/
cold-monitor-dashboard/
cold-monitor-infra/      <- this repository
cold-monitor-simulator/  (only for --profile simulator)
```

Other locations can be set with `BACKEND_DIR`, `DASHBOARD_DIR` and `SIMULATOR_DIR`.

### Running

```bash
cp .env.example .env     # then set DB_PASSWORD and, for alerts, the Telegram settings
docker compose up -d --build
```

Open `http://localhost:8090` and log in with `ADMIN_USERNAME` / `ADMIN_PASSWORD` from `.env`. To also generate
readings with the simulator (it uses `DEVICE_API_KEY` on its own):

```bash
docker compose --profile simulator up -d --build
```

Useful commands:

| Command | What it does |
| --- | --- |
| `docker compose ps` | Status and health of each service |
| `docker compose logs -f backend` | Follow the backend log |
| `git -C ../cold-monitor-backend pull && docker compose up -d --build` | Update to the latest code (same for the other repositories) |
| `docker compose --profile simulator stop simulator` | Stop the simulator, keep the rest running |
| `docker compose down` | Stop everything (data is kept) |
| `docker compose down -v` | Stop everything and **delete the database** |

### Configuration

Settings go in `.env` next to `compose.yaml`. It is git-ignored; keep secrets there and never commit it.

| Variable | Default | Description |
| --- | --- | --- |
| `DB_PASSWORD` | (required) | PostgreSQL password, used by the database and the backend. It is applied when the volume is first created; changing it later needs `ALTER USER` inside PostgreSQL |
| `ADMIN_USERNAME` | `admin` | User who logs in to the dashboard |
| `ADMIN_PASSWORD` | (required) | Their password, at least 8 characters. Change it here and run `docker compose up -d` to apply |
| `DEVICE_API_KEY` | (required) | Key sensors send in the `X-API-Key` header, at least 16 characters (`openssl rand -hex 32`) |
| `DASHBOARD_PORT` | `8090` | Host port of the dashboard and the API |
| `DASHBOARD_BIND` | `0.0.0.0` | Host address the port listens on. `127.0.0.1` keeps it off the local network |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | (empty) | Telegram alerts (see the backend README) |
| `SIM_INTERVAL`, `SIM_EXCURSION_PROBABILITY` | `5s`, `0.02` | Simulator settings |
| `BACKEND_DIR`, `DASHBOARD_DIR`, `SIMULATOR_DIR` | `../cold-monitor-*` | Where each repository is checked out |

The whole `.env` is also passed to the backend, so any backend variable (`ALERT_OFFLINE_AFTER`, `ALERT_TIME_ZONE`, …)
can be set there. Database connection settings are fixed by the compose file.

Sensors on the local network send readings to `http://<this machine>:8090/api/v1/equipment/{id}/readings` with the
header `X-API-Key: <DEVICE_API_KEY>`. Logins are kept in the database, so rebuilding or restarting the backend does
not log anyone out.

### Backups

```bash
docker compose exec -T postgres pg_dump -U coldmonitor -Fc coldmonitor > coldmonitor.dump
docker compose exec -T postgres pg_restore -U coldmonitor -d coldmonitor --clean < coldmonitor.dump
```

### Continuous integration

GitHub Actions validates `compose.yaml` on every push. Each application repository builds, tests and builds its
Docker image in its own workflow.

---

## Português (Brasil)

Roda o sistema **cold-monitor** inteiro, um sistema de monitoramento de temperatura da cadeia fria, 24 horas por dia
com o Docker Compose: PostgreSQL, o [backend](https://github.com/carloslpv/cold-monitor-backend), o
[dashboard](https://github.com/carloslpv/cold-monitor-dashboard) e, se quiser, o
[simulador de sensores](https://github.com/carloslpv/cold-monitor-simulator).

### Como as partes se ligam

```
navegador / sensores ──> dashboard (nginx, porta 8090) ──/api──> backend (8080) ──> postgres (5432)
```

- Só o dashboard publica uma porta. O nginx serve a página e repassa `/api` (REST e o fluxo ao vivo) para o backend,
  então navegadores e sensores usam um único endereço e o CORS não entra em jogo. O PostgreSQL e o backend só são
  acessíveis dentro da rede do compose.
- Todos os serviços têm `restart: unless-stopped`: os containers voltam depois de uma falha, de um reinício do Docker
  ou do computador (desde que o próprio Docker suba), e só ficam parados se você os parar.
- O backend espera o banco ficar saudável, e o dashboard espera o backend. Os health checks usam `pg_isready`,
  `/actuator/health` e o `/healthz` do nginx.
- Os dados ficam no volume `cold-monitor_postgres-data` e sobrevivem a `docker compose down` e a rebuilds das imagens.
- Os logs são rotacionados (5 arquivos de 10 MB por container).

### Requisitos

- Docker com Compose v2.24 ou mais novo (Docker Desktop no Windows/macOS). No Docker Desktop, ligue *Start Docker
  Desktop when you sign in* para a stack voltar depois de reiniciar o computador.
- Os repositórios do backend, do dashboard e do simulador clonados ao lado deste; as imagens são geradas a partir
  deles:

```
cold-monitor-backend/
cold-monitor-dashboard/
cold-monitor-infra/      <- este repositório
cold-monitor-simulator/  (só para --profile simulator)
```

Outros caminhos podem ser definidos com `BACKEND_DIR`, `DASHBOARD_DIR` e `SIMULATOR_DIR`.

### Como rodar

```bash
cp .env.example .env     # depois defina DB_PASSWORD e, para os alertas, as configurações do Telegram
docker compose up -d --build
```

Abra `http://localhost:8090` e entre com o `ADMIN_USERNAME` / `ADMIN_PASSWORD` do `.env`. Para gerar leituras com o
simulador também (ele usa a `DEVICE_API_KEY` sozinho):

```bash
docker compose --profile simulator up -d --build
```

Comandos úteis:

| Comando | O que faz |
| --- | --- |
| `docker compose ps` | Status e saúde de cada serviço |
| `docker compose logs -f backend` | Acompanha o log do backend |
| `git -C ../cold-monitor-backend pull && docker compose up -d --build` | Atualiza para o código mais recente (o mesmo vale para os outros repositórios) |
| `docker compose --profile simulator stop simulator` | Para o simulador e mantém o resto rodando |
| `docker compose down` | Para tudo (os dados ficam) |
| `docker compose down -v` | Para tudo e **apaga o banco** |

### Configuração

As configurações ficam no `.env`, ao lado do `compose.yaml`. Ele está no `.gitignore`; guarde os segredos nele e nunca
faça commit dele.

| Variável | Padrão | Descrição |
| --- | --- | --- |
| `DB_PASSWORD` | (obrigatória) | Senha do PostgreSQL, usada pelo banco e pelo backend. Ela vale quando o volume é criado; para trocar depois, use `ALTER USER` dentro do PostgreSQL |
| `ADMIN_USERNAME` | `admin` | Usuário que entra no dashboard |
| `ADMIN_PASSWORD` | (obrigatória) | A senha dele, com pelo menos 8 caracteres. Mude aqui e rode `docker compose up -d` para aplicar |
| `DEVICE_API_KEY` | (obrigatória) | Chave que os sensores enviam no cabeçalho `X-API-Key`, com pelo menos 16 caracteres (`openssl rand -hex 32`) |
| `DASHBOARD_PORT` | `8090` | Porta do host para o dashboard e a API |
| `DASHBOARD_BIND` | `0.0.0.0` | Endereço do host em que a porta escuta. `127.0.0.1` deixa fora da rede local |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | (vazio) | Alertas no Telegram (veja o README do backend) |
| `SIM_INTERVAL`, `SIM_EXCURSION_PROBABILITY` | `5s`, `0.02` | Configurações do simulador |
| `BACKEND_DIR`, `DASHBOARD_DIR`, `SIMULATOR_DIR` | `../cold-monitor-*` | Onde cada repositório está clonado |

O `.env` inteiro também é passado ao backend, então qualquer variável do backend (`ALERT_OFFLINE_AFTER`,
`ALERT_TIME_ZONE`, …) pode ficar nele. A conexão com o banco é definida pelo próprio compose.

Sensores na rede local enviam leituras para `http://<esta máquina>:8090/api/v1/equipment/{id}/readings` com o
cabeçalho `X-API-Key: <DEVICE_API_KEY>`. Os logins ficam no banco, então refazer ou reiniciar o backend não desloga
ninguém.

### Backup

```bash
docker compose exec -T postgres pg_dump -U coldmonitor -Fc coldmonitor > coldmonitor.dump
docker compose exec -T postgres pg_restore -U coldmonitor -d coldmonitor --clean < coldmonitor.dump
```

### Integração contínua

O GitHub Actions valida o `compose.yaml` a cada push. Cada repositório de aplicação compila, testa e gera a imagem
Docker no próprio workflow.
