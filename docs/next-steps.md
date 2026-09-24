# Próximas etapas (não implementadas)

Gaps conhecidos da fundação. Nada abaixo existe ainda no repositório. Cada item entra só quando houver um exercício ou uma necessidade concreta.

## Imediato (fechar a fundação)

- Rodar `./scripts/setup.sh` numa máquina Linux/WSL2 e preencher `docs/foundation-validation.md`.
- Versionar `composer.lock`, `package-lock.json` e as mudanças geradas pelo `install:features`.
- Registrar os digests reais de `postgres:18.6-alpine` e `redis:8.10.2-alpine` (e, se quiser, fixá-los no `compose.yaml` como `imagem:tag@sha256:…`).
- Ajustar `.github/workflows/tests.yml` com um serviço PostgreSQL (banco `testing`), porque o `phpunit.xml` não usa mais SQLite em memória.
- Criar o repositório pessoal no GitHub, adicionar como `origin` e publicar a branch. Isso é uma decisão do dono, fora desta etapa.

## Antes de qualquer benchmark HTTP

- **Nginx + PHP-FPM** no lugar do `artisan serve` do Sail. O servidor de desenvolvimento não representa um ambiente real de produção e distorce medições.
- Perfis de ambiente separados: dev (Sail) × bench (FPM, OPcache, `APP_DEBUG=false`, config/route/view cache).

## Filas e processamento assíncrono

- Workers dedicados (`queue:work`) como serviços próprios.
- Scheduler dedicado.
- Laravel Horizon para observar filas Redis.

## Bancos e mensageria

- MySQL, para exercícios comparando PostgreSQL e MySQL.
- RabbitMQ e um serviço Python, somente quando existirem exercícios que os usem.

## Observabilidade e medição

- Logs estruturados, métricas e tracing.
- Profiling (ex.: Xdebug profiler/SPX) e análise de queries (`EXPLAIN ANALYZE`, `pg_stat_statements`).
- Testes de carga com k6.

## Plataforma online (arquitetura própria, futura)

- Deploy público, TLS, autenticação da plataforma.
- Isolamento forte para executar código/exercícios de usuários (sandbox por usuário, limites de recursos, rede).
- O ambiente local atual **não** é seguro para código não confiável nem para exposição pública.

## Produto

- Domínio educacional (ex.: e-commerce fictício), as 30 atividades, enunciados, correção e progresso. Fora do escopo da fundação.
