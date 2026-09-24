# Bottleneck Playground

> An open-source playground for learning performance and scalability with Laravel, Vue 3, Python, PostgreSQL, MySQL, Redis, and Docker. Tackle hands-on challenges: diagnose slow queries, debug queues, handle concurrency, and measure improvements in realistic applications.

A descrição acima é a **visão do produto**. No futuro a plataforma ficará online para outras pessoas praticarem. **Este repositório, hoje, contém apenas a fundação local**:

- Laravel 13 + [Vue Starter Kit oficial](https://github.com/laravel/vue-starter-kit) (Vue 3, Inertia, TypeScript, Tailwind, Vite).
- Desenvolvimento local com Docker Compose + [Laravel Sail](https://laravel.com/docs/sail) (PHP 8.5).
- PostgreSQL 18 e Redis 8.

Não há ainda domínio de negócio, atividades, dashboard próprio, MySQL, RabbitMQ, Python, Horizon ou deploy. Veja [`docs/next-steps.md`](docs/next-steps.md).

> ⚠️ Ambiente **somente para desenvolvimento local**: não está preparado para exposição pública nem para executar código não confiável de terceiros.

## Pré-requisitos

- Linux (Ubuntu/Debian/Fedora…) **ou** Windows com **WSL2** (use o terminal do WSL, nunca PowerShell).
- Docker Engine (Linux) ou Docker Desktop com integração WSL2 habilitada.
- Docker Compose v2 (`docker compose version`).
- `git`, `curl`, ~6 GB livres em disco e ~4 GB de RAM para os containers.
- Seu usuário precisa usar o Docker sem `sudo` (grupo `docker`). Não rode o setup como root.

**Não é preciso** PHP, Composer, Node ou npm no host: tudo roda dentro dos containers.

Portas usadas no host (todas em `127.0.0.1`): `8000` (app), `5173` (Vite), `5432` (PostgreSQL), `6379` (Redis).

## Instalação em uma máquina nova

```bash
# 1. Clonar (no WSL, mantenha o projeto no filesystem Linux, ex.: ~/projects)
mkdir -p ~/projects && cd ~/projects
git clone <URL-DO-SEU-REPOSITORIO> bottleneck-playground   # placeholder: repositório pessoal ainda não definido
cd bottleneck-playground

# 2. Setup completo (cria .env, instala dependências em container, sobe serviços, migra, compila e testa)
./scripts/setup.sh
```

O script é idempotente: preserva `.env` e `APP_KEY` existentes e não apaga volumes. Use `./scripts/setup.sh --skip-tests` para pular a suíte de testes.

<details>
<summary>Passo a passo manual (equivalente ao script)</summary>

```bash
cp -n .env.example .env
sed -i "s/^WWWUSER=.*/WWWUSER=$(id -u)/; s/^WWWGROUP=.*/WWWGROUP=$(id -g)/" .env

# Dependências PHP sem PHP no host: runtime oficial do Sail v1.68.0
git clone --depth 1 --branch v1.68.0 https://github.com/laravel/sail.git /tmp/bottleneck-sail-bootstrap
docker build --build-arg WWWGROUP="$(id -g)" -t bottleneck-bootstrap:php8.5 /tmp/bottleneck-sail-bootstrap/runtimes/8.5
docker run --rm -e WWWUSER="$(id -u)" -e COMPOSER_HOME=/tmp/composer \
  -v "$PWD:/var/www/html" -w /var/www/html bottleneck-bootstrap:php8.5 \
  composer install --no-interaction --prefer-dist --no-scripts
docker run --rm -e WWWUSER="$(id -u)" -e COMPOSER_HOME=/tmp/composer \
  -v "$PWD:/var/www/html" -w /var/www/html bottleneck-bootstrap:php8.5 \
  composer dump-autoload --no-interaction

docker compose up -d --build --wait
./vendor/bin/sail artisan key:generate          # só se APP_KEY estiver vazia
./vendor/bin/sail artisan migrate
./vendor/bin/sail npm ci                         # ou `npm install` se não houver package-lock.json
./vendor/bin/sail artisan install:features \
  --answers='{"auth_features":["email-verification","registration","2fa","passkeys","password-confirmation"]}'   # só se chisel.php existir
./vendor/bin/sail npm run build
./vendor/bin/sail artisan test
```
</details>

**Lockfiles:** se o clone ainda não tiver `composer.lock` e `package-lock.json`, o primeiro setup vai gerá-los. Versione-os logo em seguida (`git add composer.lock package-lock.json`) para que as próximas máquinas instalem exatamente as mesmas versões.

Banco, volumes Docker e `.env` **não** vão pelo Git: cada máquina tem os seus.

## Uso diário

| Ação | Comando |
|---|---|
| Subir serviços | `./vendor/bin/sail up -d --wait` |
| Vite com HMR (terminal separado) | `./vendor/bin/sail npm run dev` |
| Parar preservando dados | `./vendor/bin/sail stop` (ou `sail down`, **sem** `-v`) |
| Status | `docker compose ps` |
| Logs | `./vendor/bin/sail logs -f` · `./vendor/bin/sail logs -f pgsql` |
| Artisan / Composer / npm | `./vendor/bin/sail artisan …` · `sail composer …` · `sail npm …` |
| Testes | `./vendor/bin/sail artisan test` · checagem completa: `sail composer ci:check` |
| Shell no container | `./vendor/bin/sail shell` |
| psql | `./vendor/bin/sail psql` |
| redis-cli | `./vendor/bin/sail redis` |

Dica: `alias sail='sh $([ -f sail ] && echo sail || echo vendor/bin/sail)'`.

URLs:

- Aplicação: <http://localhost:8000>
- Healthcheck do framework: <http://localhost:8000/up> (não valida banco nem Redis)
- Vite dev server: <http://localhost:5173> (servido via app; não abra diretamente)

O plugin `laravel-vite-plugin` detecta o Sail (`LARAVEL_SAIL=1`) e já faz o Vite escutar em `0.0.0.0:${VITE_PORT}` com HMR apontando para `localhost`, por isso o `vite.config.ts` do starter não foi alterado.

## Banco de testes

`phpunit.xml` usa a conexão PostgreSQL do `.env` com o banco **`testing`**, isolado do banco de desenvolvimento `bottleneck_playground`. O PostgreSQL cria `testing` automaticamente no primeiro boot de um volume novo; o `scripts/setup.sh` também o cria se faltar.

## Troubleshooting

- **Porta ocupada** (`address already in use`): descubra quem usa (`ss -ltnp | grep 8000`) e altere no `.env` `APP_PORT` (+ `APP_URL`), `VITE_PORT`, `FORWARD_DB_PORT` ou `FORWARD_REDIS_PORT`. Depois `sail up -d --wait`. Não derrube containers de outros projetos.
- **`./scripts/setup.sh: Permission denied`** (arquivos copiados de um disco Windows perdem o bit de execução): `chmod +x scripts/setup.sh` ou `bash scripts/setup.sh`.
- **`docker info` falha**: Docker Desktop fechado, integração WSL desativada ou usuário fora do grupo `docker`.
- **Permissão negada em `storage/` ou `vendor/`**: confira `WWWUSER`/`WWWGROUP` no `.env` (= `id -u`/`id -g`) e reconstrua: `sail build --no-cache && sail up -d`.
- **Lento no Windows**: o projeto está em `/mnt/c/...`. Mova para `~/projects` dentro do WSL.
- **`Vite manifest not found`**: rode `sail npm run build` ou deixe `sail npm run dev` aberto.
- **HMR não atualiza**: confira que `sail npm run dev` está rodando e que `public/hot` existe; porta `VITE_PORT` precisa estar livre.
- **Banco `testing` ausente** (volume antigo): `docker compose exec pgsql createdb -U sail testing`.
- **Recomeçar do zero** apagando dados locais (destrutivo, consciente): `sail down -v`.

## Documentação do projeto

- [`docs/foundation-validation.md`](docs/foundation-validation.md) — revisões, versões, o que foi feito e o que falta validar.
- [`docs/next-steps.md`](docs/next-steps.md) — gaps conhecidos para as próximas etapas.

## Créditos e licença

Baseado no [Laravel + Vue Starter Kit](https://github.com/laravel/vue-starter-kit) e no [Laravel Sail](https://github.com/laravel/sail), ambos software livre sob licença MIT, © Taylor Otwell / Laravel. Este projeto é distribuído sob a mesma licença MIT (ver `composer.json`).
