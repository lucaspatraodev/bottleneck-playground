#!/usr/bin/env bash
#
# Bottleneck Playground — bootstrap do ambiente local (Linux / WSL2 + Docker).
#
# Uso (na raiz do repositório):
#   ./scripts/setup.sh                # instala, sobe containers, migra e valida
#   ./scripts/setup.sh --skip-tests   # idem, sem rodar a suíte de testes
#
# O que ele faz, na ordem:
#   1. Confere git, Docker daemon e Docker Compose v2.
#   2. Cria .env a partir de .env.example (NUNCA sobrescreve um .env existente)
#      e ajusta WWWUSER/WWWGROUP para o seu usuário.
#   3. Se vendor/ não existir: constrói a imagem runtime oficial do Sail
#      (laravel/sail v1.68.0, PHP 8.5) e roda `composer install` DENTRO dela.
#      Nenhum PHP/Composer/Node é necessário no host.
#   4. docker compose up (laravel.test + pgsql + redis) aguardando healthchecks.
#   5. Gera APP_KEY só se estiver vazia, migra, instala dependências npm,
#      finaliza o starter (install:features) se ainda não foi aplicado e compila.
#   6. Smoke checks (SQL, Redis, cache) e testes existentes no banco `testing`.
#
# Não usa `down -v`, `migrate:fresh`, `docker system prune` nem apaga volumes.
set -Eeuo pipefail

SAIL_VERSION="v1.68.0"          # tag oficial; commit 2bc304083d515065b03944e425e62cb3c526c33e
PHP_RUNTIME="8.5"
BOOTSTRAP_IMAGE="bottleneck-bootstrap:php${PHP_RUNTIME}"
RUN_TESTS=1

for arg in "$@"; do
    case "$arg" in
        --skip-tests) RUN_TESTS=0 ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "Argumento desconhecido: $arg" >&2; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[aviso] %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m[erro] %s\033[0m\n' "$*" >&2; exit 1; }
trap 'die "falhou na linha $LINENO: $BASH_COMMAND"' ERR

# ---------------------------------------------------------------- 1. pré-requisitos
log "Verificando pré-requisitos"
case "$(uname -s)" in
    Linux) ;;
    Darwin) warn "macOS não é o alvo validado deste script; seguindo mesmo assim." ;;
    *) die "Rode este script em Linux ou dentro do WSL2 (não no PowerShell/Git Bash)." ;;
esac
if [[ "$ROOT" == /mnt/[a-z]/* ]]; then
    warn "O projeto está no filesystem do Windows ($ROOT). Prefira ~/projects/bottleneck-playground dentro do WSL (muito mais rápido e sem problemas de permissão)."
fi
[[ "$(id -u)" != 0 ]] || die "Não rode como root: o Sail mapeia o usuário do container para o seu UID. Use seu usuário normal (no grupo docker)."
command -v git    >/dev/null || die "git não encontrado."
command -v docker >/dev/null || die "docker CLI não encontrado."
docker info >/dev/null 2>&1   || die "Sem acesso ao Docker daemon (docker info falhou). Verifique Docker Desktop/Engine, o context ativo e se seu usuário pode usar o Docker."
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 não encontrado (docker compose version)."
echo "docker context: $(docker context show 2>/dev/null || echo '?')"
docker compose version

# ---------------------------------------------------------------- 2. .env
log "Preparando .env"
if [[ -f .env ]]; then
    echo ".env já existe — preservado."
else
    cp .env.example .env
    echo ".env criado a partir de .env.example."
fi

set_env() { # set_env CHAVE VALOR  (idempotente, sem duplicar chaves)
    local key="$1" value="$2"
    if grep -qE "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >> .env
    fi
}
set_env WWWUSER  "$(id -u)"
set_env WWWGROUP "$(id -g)"
echo "WWWUSER=$(id -u) WWWGROUP=$(id -g)"

env_value() { grep -E "^$1=" .env | tail -n1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }

# ---------------------------------------------------------------- 3. dependências PHP
if [[ ! -x vendor/bin/sail ]]; then
    log "vendor/ ausente — construindo runtime oficial do Sail ${SAIL_VERSION} (PHP ${PHP_RUNTIME})"
    TMP_SAIL="$(mktemp -d "${TMPDIR:-/tmp}/bottleneck-sail-bootstrap.XXXXXX")"
    git clone --quiet --depth 1 --branch "$SAIL_VERSION" https://github.com/laravel/sail.git "$TMP_SAIL"
    docker build --build-arg WWWGROUP="$(id -g)" -t "$BOOTSTRAP_IMAGE" "$TMP_SAIL/runtimes/${PHP_RUNTIME}"
    rm -rf "$TMP_SAIL"

    bootstrap() {
        docker run --rm \
            -e WWWUSER="$(id -u)" \
            -e COMPOSER_HOME=/tmp/composer \
            -e NPM_CONFIG_CACHE=/tmp/npm \
            -v "$ROOT:/var/www/html" \
            -w /var/www/html \
            "$BOOTSTRAP_IMAGE" "$@"
    }

    if [[ -f composer.lock ]]; then
        log "composer install (respeitando composer.lock)"
    else
        warn "composer.lock ausente: o Composer vai resolver as dependências agora. Versione o composer.lock gerado."
        log "composer install (resolução inicial)"
    fi
    # --no-scripts evita o instalador interativo do starter antes do ambiente estar pronto.
    bootstrap composer install --no-interaction --prefer-dist --no-scripts
    bootstrap composer dump-autoload --no-interaction
fi

SAIL=./vendor/bin/sail

# ---------------------------------------------------------------- 4. containers
log "Validando e subindo containers"
docker compose config --quiet
docker compose up -d --build --wait --wait-timeout 300
docker compose ps

# ---------------------------------------------------------------- 5. aplicação
if [[ -z "$(env_value APP_KEY)" ]]; then
    log "APP_KEY vazia — gerando"
    $SAIL artisan key:generate --no-interaction
else
    echo "APP_KEY já configurada — preservada."
fi

$SAIL artisan config:clear
$SAIL composer check-platform-reqs

log "Garantindo banco de testes 'testing' (criado automaticamente só em volume novo)"
if ! docker compose exec -T pgsql psql -U "$(env_value DB_USERNAME)" -d postgres -tAc \
        "SELECT 1 FROM pg_database WHERE datname='testing'" | grep -q 1; then
    docker compose exec -T pgsql createdb -U "$(env_value DB_USERNAME)" testing
    echo "Banco 'testing' criado."
fi

log "Migrations"
$SAIL artisan migrate --no-interaction

log "Dependências npm"
if [[ -f package-lock.json ]]; then
    $SAIL npm ci
else
    warn "package-lock.json ausente: usando npm install. Versione o package-lock.json gerado."
    $SAIL npm install
fi

if [[ -f chisel.php ]]; then
    log "Finalizando o starter (install:features com as opções padrão)"
    $SAIL artisan install:features --no-interaction \
        --answers='{"auth_features":["email-verification","registration","2fa","passkeys","password-confirmation"]}'
else
    echo "install:features já aplicado (chisel.php ausente) — pulando."
fi

log "Build frontend"
$SAIL npm run build

# ---------------------------------------------------------------- 6. verificação
log "Smoke checks"
docker compose exec -T pgsql pg_isready -U "$(env_value DB_USERNAME)" -d "$(env_value DB_DATABASE)"
docker compose exec -T redis redis-cli ping
$SAIL artisan tinker --execute='dump(DB::select("select 1 as ok"));'
$SAIL artisan tinker --execute='dump(Illuminate\Support\Facades\Redis::connection()->ping());'
$SAIL artisan tinker --execute='cache()->put("bottleneck:smoke", "ok", 60); dump(cache()->get("bottleneck:smoke")); cache()->forget("bottleneck:smoke");'
$SAIL artisan migrate:status
APP_PORT_VALUE="$(env_value APP_PORT)"
curl -fsS "http://localhost:${APP_PORT_VALUE:-8000}/up" >/dev/null && echo "GET /up OK"

if [[ "$RUN_TESTS" == 1 ]]; then
    log "Testes existentes (banco 'testing')"
    $SAIL artisan test
fi

log "Pronto"
cat <<EOF
Aplicação:  http://localhost:${APP_PORT_VALUE:-8000}
Vite (HMR): ./vendor/bin/sail npm run dev      (em outro terminal)
Parar:      ./vendor/bin/sail stop             (preserva dados)
Retomar:    ./vendor/bin/sail up -d --wait

Se este foi o primeiro setup, versione os lockfiles gerados:
  git add composer.lock package-lock.json && git commit -m "chore: lock dependencies"
EOF
