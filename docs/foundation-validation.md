# Fundação — registro de preparação e validação

**Status desta execução: PREPARADO, NÃO VALIDADO.**
Os arquivos do skeleton foram montados e revisados, mas **nada foi executado em Docker**: nenhuma imagem construída, nenhuma dependência instalada, nenhuma migration aplicada, nenhum teste rodado. A validação real acontece no primeiro `./scripts/setup.sh` na máquina Linux de destino. Preencha a seção "Validação na máquina de destino" nesse momento.

## Ambiente desta preparação (24/09/2026)

| Item | Valor |
|---|---|
| Destino dos arquivos | `C:\Users\Lucas Patrão\Desktop\capivara-ultimate-games\bottleneck-playground` (Windows, só armazenamento) |
| Onde os arquivos foram montados | Container Linux (Ubuntu 24.04) da sessão do Claude |
| Docker | Daemon disponível, mas o egress bloqueia Docker Hub → sem imagens |
| Packagist / npm registry | Bloqueados pelo egress → sem `composer install` / `npm install` |
| GitHub | Acessível → clones do starter, do Sail e do `official-images` |

Por isso **não existem ainda `composer.lock` nem `package-lock.json`**: eles serão gerados no primeiro setup e devem ser versionados em seguida.

## Revisões upstream usadas

| Item | Referência | Verificação |
|---|---|---|
| Vue Starter Kit | `d282e817c6c2fa1bd475f7c42ea785ccfc67d0ab` (21/09/2026, "Make the email-verification feature implement MustVerifyEmail…") | commit existe; é a base do histórico deste repositório |
| Laravel Sail (código de referência) | `a7174a143ca3ffa986c847bcf6a76725fcf66924` (22/09/2026) | difere da tag `v1.68.0` apenas no CHANGELOG |
| Laravel Sail (Composer / bootstrap) | `1.68.0` = tag `v1.68.0` → `2bc304083d515065b03944e425e62cb3c526c33e` | `composer.json` fixa `"laravel/sail": "1.68.0"` |
| laravel-vite-plugin (leitura de código) | `891d2742` (3.2.0) | comportamento automático com `LARAVEL_SAIL` confirmado |
| docker-library/official-images | `13dfdd8d898cc8a341a6decf85e7482dec9aef41` (23/09/2026) | tags de postgres/redis abaixo listadas ali |

Git local: branch `chore/skeleton-setup`; remote `upstream` → `https://github.com/laravel/vue-starter-kit.git` com **push desabilitado**. Não há remote pessoal (a definir).

## Versões: faixas declaradas × resolvidas

| Componente | Faixa nos manifests / config | Resolvido |
|---|---|---|
| PHP (runtime) | Sail runtime `8.5` (starter aceita `^8.3`) | a registrar: `sail php -v` |
| Laravel | `laravel/framework ^13.17` | a registrar: `composer.lock` |
| Inertia (server) | `inertiajs/inertia-laravel ^3.0` | a registrar |
| Sail | `1.68.0` (exato) | 1.68.0 |
| Composer | instalado pelo Dockerfile do Sail (último estável) | a registrar: `sail composer -V` |
| Node | Sail runtime `NODE_VERSION=24` | a registrar: `sail node -v` |
| Vue | `^3.5.13` | a registrar: `package-lock.json` |
| @inertiajs/vue3 | `^3.0.0` | a registrar |
| Vite / Vite Plus | `vite ^8.0.0`, `vite-plus 0.3.0` | a registrar |
| PostgreSQL | `postgres:18.6-alpine` (antes: `18-alpine`) | digest a registrar: `docker image inspect postgres:18.6-alpine --format '{{index .RepoDigests 0}}'` |
| Redis | `redis:8.10.2-alpine` (antes: `alpine` flutuante) | digest a registrar |

Nenhum digest foi inventado: não foi possível consultar o registry.

## O que foi feito

1. Clone do starter na revisão indicada; branch `chore/skeleton-setup`; `origin` renomeado para `upstream` com push bloqueado.
2. `composer.json`: `laravel/sail` de `^1.53` para `1.68.0` (equivalente a `composer require --dev laravel/sail:1.68.0 --no-update`).
3. `compose.yaml`: reproduz o resultado de `artisan sail:install --with=pgsql,redis --php=8.5` (lógica do `InteractsWithDockerComposeServices` do Sail em `a7174a1`, aplicada à mão porque não havia `vendor/`), com ajustes permitidos:
   - `name: bottleneck-playground`; imagem da app `bottleneck-playground/app:php8.5`;
   - todas as portas publicadas em `127.0.0.1`; app em `8000` → `80` do container;
   - `depends_on` com `condition: service_healthy`; healthchecks do Sail preservados;
   - tags concretas para PostgreSQL e Redis; volumes nomeados `sail-pgsql`/`sail-redis`.
4. `phpunit.xml`: mesma transformação do `sail:install` (remove `DB_CONNECTION=sqlite`, troca `:memory:` por `testing`).
5. `.env.example`: identidade, PostgreSQL, Redis (cache e fila), `COMPOSE_PROJECT_NAME`, portas, `WWWUSER`/`WWWGROUP`, `SAIL_XDEBUG_MODE=off`, `PHP_CLI_SERVER_WORKERS=4` (como o `sail:install` faz). `APP_KEY` vazia. Sem chaves duplicadas.
6. `vite.config.ts`: **não alterado**. O `laravel-vite-plugin` já usa `0.0.0.0`, `VITE_PORT`, `strictPort` e HMR em `localhost` quando `LARAVEL_SAIL` está definido. Definir `server.host` manualmente quebraria o endereço de HMR.
7. `.gitignore`: logs, dumps SQL, temporários e variações de `.env` (exceto `.env.example`).
8. `scripts/setup.sh`: bootstrap completo e idempotente. Checado com `bash -n`, e o fluxo e a idempotência do `.env` foram exercitados com `docker`/`sail` falsos. **Não executado contra Docker real.**
9. `docker compose config --quiet` com `.env.example`: **OK** (sintaxe e interpolação).
10. README, este documento e `docs/next-steps.md`.

`install:features` **não** foi executado: ele exige `vendor/` e `node_modules/`. O `setup.sh` o executa com as opções padrão se `chisel.php` ainda existir. Ele modifica arquivos, gera recursos Wayfinder e compila. Versione essas mudanças depois do primeiro setup.

## Validação na máquina de destino (a preencher)

Depois de `./scripts/setup.sh`, registre:

```bash
uname -a; docker version --format '{{.Server.Version}}'; docker compose version
git rev-parse HEAD
docker compose ps
./vendor/bin/sail php -v | head -1
./vendor/bin/sail composer -V
./vendor/bin/sail node -v; ./vendor/bin/sail npm -v
./vendor/bin/sail artisan about --only=environment,drivers
./vendor/bin/sail composer show laravel/framework laravel/sail inertiajs/inertia-laravel | grep -E '^(name|versions)'
./vendor/bin/sail npm ls vue vite vite-plus @inertiajs/vue3 --depth=0
docker image inspect postgres:18.6-alpine redis:8.10.2-alpine --format '{{.RepoTags}} {{index .RepoDigests 0}} {{.Architecture}}'
```

Checklist:

- [ ] Docker daemon acessível e `docker compose config` válido
- [ ] `laravel.test`, `pgsql` (healthy), `redis` (healthy) rodando
- [ ] Composer e npm funcionando dentro do container
- [ ] APP_KEY gerada; migrations aplicadas (`sail artisan migrate:status`)
- [ ] SQL `select 1` e cache `bottleneck:smoke` = `ok` via tinker
- [ ] `sail npm run build` OK; <http://localhost:8000> abre a página padrão sem erros no console
- [ ] `sail artisan test` verde no banco `testing`; `sail composer ci:check` verde
- [ ] HMR: com `sail npm run dev`, editar temporariamente um texto em `resources/js/pages/Welcome.vue`, ver a atualização sem reload e **reverter**
- [ ] Persistência: `sail stop && sail up -d --wait` e `migrate:status` continua igual
- [ ] `composer.lock`, `package-lock.json` e as mudanças do `install:features` versionados

## Pendências conhecidas

- Lockfiles ainda não existem (ver acima).
- `.github/workflows/tests.yml` do starter roda os testes sem PostgreSQL. Depois da troca do `phpunit.xml` para `testing`/pgsql, esse workflow vai falhar até receber um serviço PostgreSQL. Isso ficou registrado em `docs/next-steps.md` e não foi alterado nesta etapa.
- `.npmrc` do starter tem `ignore-scripts=true` (mantido). Se algum pacote nativo exigir postinstall, isso aparecerá no primeiro `npm install`.
