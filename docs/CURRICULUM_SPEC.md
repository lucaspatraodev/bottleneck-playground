# Bottleneck Playground — Curriculum Spec

| Campo | Valor |
|---|---|
| Projeto | `bottleneck-playground` |
| Documento | Especificação do laboratório (design, **não** implementação) |
| Versão | 1.0 — 24/09/2026 |
| Destino final no repositório | `docs/CURRICULUM_SPEC.md` (hoje em `Tasks/Lessons/`) |
| Implementador previsto | Codex (ou outro agente), a partir do skeleton já existente |
| Base técnica | Laravel 13, Vue 3 + Inertia + TypeScript, Laravel Sail (PHP 8.5), PostgreSQL 18, Redis 8 |

> **Este documento não contém soluções.** Ele descreve o laboratório, o domínio, as ferramentas de medição e as 30 tasks do ponto de vista do aluno, mais os requisitos de implementação. O desenho dos defeitos plantados e as soluções de referência ficam num documento selado, fora das pastas de documentação do aluno (ver §8 e §13.2). Quem vai **estudar** não deve abri-lo.

---

## Sumário

1. [Propósito](#1-propósito)
2. [Arquitetura](#2-arquitetura)
3. [Containers](#3-containers)
4. [Domínio](#4-domínio)
5. [Dataset](#5-dataset)
6. [Modelo de tasks](#6-modelo-de-tasks)
7. [Mecanismo de reset / check / benchmark](#7-mecanismo-de-reset--check--benchmark)
8. [Regras anti-spoiler](#8-regras-anti-spoiler)
9. [As 30 tasks](#9-as-30-tasks)
10. [Matriz conceito × task](#10-matriz-conceito--task)
11. [Ordem recomendada](#11-ordem-recomendada)
12. [Estimativa de dificuldade](#12-estimativa-de-dificuldade)
13. [Requisitos de implementação para o Codex](#13-requisitos-de-implementação-para-o-codex)
14. [Definition of Done do projeto](#14-definition-of-done-do-projeto)

---

## 1. Propósito

### 1.1 O que é

O Bottleneck Playground é um laboratório de engenharia de backend e full stack montado sobre um e-commerce fictício, a **Bottleneck Store**, com volume de dados suficiente para expor problemas que não aparecem num CRUD pequeno. O aluno recebe **tickets de engenharia**, não perguntas teóricas. Cada ticket descreve um sintoma de produção. O aluno investiga, mede, corrige e prova a melhora com números.

### 1.2 Para quem

Para quem é Full Stack com experiência prática em Laravel, Vue, SQL, APIs, webhooks e Docker, e quer ganhar profundidade de nível Pleno/Sênior em:

- performance de banco (EXPLAIN, índices, planos, paginação, agregações em milhões de linhas);
- Eloquent em escala (N+1, memória, processamento em lote);
- Redis, cache e rate limiting;
- filas, jobs e workers (Redis Queue, Horizon, RabbitMQ);
- concorrência, idempotência, locks e transações;
- integrações resilientes e segurança de webhooks;
- observabilidade orientada a investigação;
- performance de front-end com Vue.

As competências foram escolhidas para cobrir uma vaga Full Stack Pleno que pede PHP/Laravel, Vue, Python, MySQL, PostgreSQL, Redis, Git, cloud, segurança, async, workers e observabilidade.

### 1.3 Princípios de design

1. **Investigar antes de saber.** O enunciado descreve o sintoma e o contexto de negócio, nunca a causa. A causa precisa ser encontrada com as ferramentas certas.
2. **Determinismo.** Os critérios de aceite são medidos com métricas que não dependem da velocidade da máquina: número de queries, forma do plano de execução, blocos lidos, linhas examinadas, chamadas externas, memória de pico, invariantes de dados e checksums de resultado. Latência e throughput são sempre medidos e reportados, mas **nunca** decidem aprovação sozinhos.
3. **Concorrência reproduzível.** Condições de corrida são reproduzidas com checkpoints controlados por um harness (§7.6), não com `sleep` nem com sorte.
4. **Antes e depois.** Toda task tem medição de baseline e de resultado com o mesmo instrumento e o mesmo dataset.
5. **Realismo.** O código com defeito parece código de produção plausível. Nada de `// BUG AQUI`.
6. **Anti-spoiler.** As soluções existem, mas ficam deliberadamente isoladas (§8).
7. **Uma máquina.** Tudo roda localmente com Docker Compose num Linux/WSL2 comum. Não há dependência de cloud.
8. **Isolamento entre tasks.** Fazer, refazer ou resetar uma task não destrói o trabalho das outras.

### 1.4 Fora do escopo

- Curso teórico ou apostila. A teoria entra só como referência curta em `docs/concepts/`.
- Infraestrutura de produção, deploy público, Kubernetes ou multi-tenant.
- Executar código de terceiros na plataforma pública futura (exige arquitetura própria de isolamento).
- Metas de latência absolutas ("responder em 200 ms").

### 1.5 O que significa "concluir" uma task

Uma task está concluída quando `make lab-check TASK=XX` retorna todos os critérios obrigatórios como **PASS** no dataset recomendado, e o aluno registrou em `docs/lab-notes/XX.md` a investigação (evidências de antes e depois e decisões). Ler a solução do vault depois disso é opcional e intencional.

---

## 2. Arquitetura

### 2.1 Visão geral

```
                          ┌──────────────────────────── Docker Compose (bottleneck-playground) ─────────────────────────────┐
 navegador ── Vite HMR ──▶│ laravel.test (Sail: artisan serve + Vite)          [dev]                                        │
 k6 ─────────────────────▶│ nginx ─▶ app-fpm (PHP-FPM + OPcache)               [bench]                                      │
                          │      │                                                                                          │
                          │      ├──▶ pgsql (PostgreSQL 18: pg_stat_statements, auto_explain)                               │
                          │      ├──▶ mysql (MySQL 8.4 LTS: catálogo legado)            [mysql]                             │
                          │      ├──▶ redis (cache, locks, rate limit, filas, Horizon)                                      │
                          │      ├──▶ rabbitmq (eventos de domínio)                     [rabbit]                            │
                          │      └──▶ partners-mock (Python/FastAPI: gateway, ERP, marketplace + control plane)             │
                          │                                                                                                 │
                          │ horizon / workers / scheduler                               [queue]                             │
                          │ analytics-consumer (Python, consome RabbitMQ)               [rabbit]                            │
                          │ otel-collector, jaeger, prometheus, grafana, exporters      [obs]                               │
                          │ k6 (execução sob demanda)                                   [tools]                             │
                          └─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Estrutura de diretórios

Tudo abaixo é **alvo de implementação**. O skeleton atual tem apenas a base do starter kit.

```
app/
  Models/                       Eloquent (Customer, Order, Payment, ...)
  Http/Controllers/
    Storefront/                 API de clientes (/api/me/*, /api/catalog/*, /api/checkout)
    Admin/                      API do backoffice (/api/admin/*)
    Webhooks/                   /api/webhooks/{gateway,marketplace}
    Legacy/                     /api/legacy-catalog/* (conexão MySQL)
  Http/Resources/               API Resources
  Services/<Contexto>/          regras de negócio (Checkout, Inventory, Coupons, Reports...)
  Jobs/<Contexto>/              jobs de fila
  Integrations/{Gateway,Erp,Marketplace}/   clientes HTTP dos parceiros
  Events/ Listeners/
  Console/Commands/<Contexto>/  comandos de negócio (import, recalculate, reconcile...)
  Lab/                          ferramentas do laboratório (não é domínio)
    Probes/                     QueryCounter, PlanInspector, MemoryProbe, CacheProbe, ExternalCallProbe
    Checkpoints/                Lab::checkpoint(), políticas, eventos
    Race/                       orquestrador de concorrência
    Tasks/                      registro de tasks, checkers (um diretório por task)
    Support/                    golden checksums, ledger client, relatórios
config/lab.php
database/
  migrations/                   schema baseline do domínio
  lab/generator/                SQL e comandos do gerador determinístico
lab/
  tasks/XX/                     manifesto, cenário, scripts k6, cenários de corrida, contratos
  k6/                           bibliotecas compartilhadas de carga
  golden/                       checksums de resultados esperados (sem conteúdo de solução)
services/
  partners-mock/                Python (FastAPI) — gateway, ERP, marketplace, control plane
  analytics-consumer/           Python — consumidor RabbitMQ (T21)
docker/                         configs de pgsql, mysql, redis, rabbitmq, nginx, php-fpm, obs
docs/
  tasks/XX-slug/                enunciado do aluno (README.md) + hints.md
  concepts/                     referências conceituais genéricas
  partners/                     "documentação pública" dos parceiros simulados
  lab-notes/                    anotações do aluno (uma por task)
  CURRICULUM_SPEC.md            este documento
vault/
  DO_NOT_OPEN_SOLUTIONS/        soluções (ver §8)
Makefile                        interface do laboratório (atalhos para artisan lab:*)
```

### 2.3 Modos de execução

| Modo | Como sobe | Uso |
|---|---|---|
| **dev** | `sail up -d` (perfil padrão) | Desenvolvimento, HMR, investigação manual. Servidor `artisan serve`. |
| **bench** | `--profile bench` | Benchmarks HTTP (k6): Nginx + PHP-FPM, OPcache, `APP_DEBUG=false`, config/route/view cache. |
| **lab** | `LAB_ENABLED=true` | Ativa probes, checkpoints, headers de laboratório e relógio fixo. **Nunca** em produção: o provider do lab se recusa a registrar se `APP_ENV=production`. |

### 2.4 Autenticação

- **Staff/admin:** usuários do starter (`users`, Fortify) para as páginas Inertia do backoffice; tokens Sanctum com ability `admin` para a API `/api/admin/*`.
- **Clientes:** tokens Sanctum emitidos para `customers` (model tokenable) para `/api/me/*` e `/api/checkout`.
- `make lab-info` imprime tokens determinísticos dos usuários e clientes de referência, para uso em k6 e curl. Os tokens são recriados a cada `lab-start`/`lab-reset`.

### 2.5 Relógio e sementes

- `LAB_CLOCK=2026-06-30T23:59:59-03:00`: com o lab ativo, `now()` é congelado nesse instante (Carbon test now), exceto nos cenários que avançam o relógio explicitamente pelo harness.
- `LAB_SEED=20260630`: semente global do gerador e dos cenários. Mesma semente e mesmo dataset produzem dados idênticos bit a bit, em qualquer máquina.
- Fuso de negócio: `America/Sao_Paulo`. Timestamps armazenados em `timestamptz` (PG) e em UTC (MySQL).

### 2.6 Modelo de isolamento entre tasks

| Recurso | Estratégia |
|---|---|
| **Código** | Um branch Git por task: `lab/task-XX`, criado a partir da tag `lab-baseline` (ou de outro branch indicado com `FROM=`). A solução de uma task nunca contamina outra. |
| **Banco PostgreSQL** | Um database por task (`bp_tXX`), clonado de um database-template por dataset (`bp_tpl_small`, `bp_tpl_medium`, `bp_tpl_large`) com `CREATE DATABASE ... TEMPLATE ... STRATEGY FILE_COPY`. Reset = recriar a partir do template e reaplicar o cenário. |
| **Banco MySQL** | Um schema por task (`bp_tXX`), carregado dos CSVs determinísticos do dataset (só nas tasks que usam MySQL). |
| **Redis** | Prefixo por task em cache, locks, rate limiter, filas e Horizon (`bp:tXX:`). Reset apaga só as chaves do prefixo (SCAN + UNLINK), nunca `FLUSHALL`. |
| **Filas** | Nomes de fila qualificados pela task. `failed_jobs` fica no database da task. |
| **RabbitMQ** | vhost por task (`/bp-tXX`). |
| **Parceiros (mock)** | Namespace do ledger e dos cenários por task (`X-Lab-Task`). |
| **Resultados** | `storage/lab/runs/TXX/` e `storage/lab/benchmarks/TXX/` (gitignored). |

A conexão de banco, os prefixos e os namespaces da task ativa são aplicados por um `LabServiceProvider`, que lê `storage/lab/state.json` (escrito por `lab:start`). O `.env` não é alterado.

---

## 3. Containers

Todas as portas são publicadas apenas em `127.0.0.1`. As versões exatas das imagens são fixadas pelo Codex na implementação e registradas em `docs/lab-versions.md`. As faixas abaixo são a intenção.

| Serviço | Imagem / base | Perfil | Função | Porta host |
|---|---|---|---|---|
| `laravel.test` | Sail runtime PHP 8.5 (já existe) | padrão | App em dev, Vite, Artisan, Composer, npm, Playwright | 8000, 5173 |
| `pgsql` | `postgres:18.x-alpine` | padrão | Banco principal | 5432 |
| `redis` | `redis:8.x-alpine` | padrão | Cache, locks, rate limit, filas, Horizon | 6379 |
| `partners-mock` | Python 3.13 + FastAPI/uvicorn | padrão | Gateway de pagamento, ERP, marketplace e notificações simulados | 8090 |
| `mysql` | `mysql:8.4` (LTS) | `mysql` | Catálogo legado (T09) e comparações | 3306 |
| `horizon` | mesma imagem da app | `queue` | Supervisores de fila (Redis) | — |
| `scheduler` | mesma imagem da app | `queue` | `schedule:work` | — |
| `rabbitmq` | `rabbitmq:4.x-management` | `rabbit` | Broker de eventos (T21) | 5672, 15672 |
| `analytics-consumer` | Python 3.13 | `rabbit` | Consumidor de eventos (T21) | — |
| `app-fpm` | Sail runtime + PHP-FPM + OPcache | `bench` | App para benchmarks | — |
| `nginx` | `nginx:1.x-alpine` | `bench` | Proxy para o FPM | 8080 |
| `otel-collector` | `otel/opentelemetry-collector-contrib` | `obs` | Recebe OTLP | — |
| `jaeger` | `jaegertracing/jaeger` (v2) | `obs` | Traces | 16686 |
| `prometheus` | `prom/prometheus` | `obs` | Métricas | 9090 |
| `grafana` | `grafana/grafana` | `obs` | Dashboards | 3000 |
| `postgres-exporter`, `redis-exporter` | exporters oficiais | `obs` | Métricas de infraestrutura | — |
| `k6` | `grafana/k6` | `tools` | Carga sob demanda (`docker compose run --rm k6 ...`) | — |

**Configurações obrigatórias:**

- **PostgreSQL** (`docker/pgsql/postgresql.conf`): `shared_preload_libraries='pg_stat_statements,auto_explain'`, `pg_stat_statements.track=all`, `track_io_timing=on`, `auto_explain.log_min_duration=500ms`, `auto_explain.log_analyze=on`, `auto_explain.log_buffers=on`, `log_lock_waits=on`, `deadlock_timeout=1s`, `log_min_duration_statement=1000`, `max_connections=200`. Memória modesta e documentada (`shared_buffers` em ~25% do limite do container). Extensões disponíveis: `pg_stat_statements`, `pg_trgm`, `citext`. No PostgreSQL 18, `EXPLAIN ANALYZE` já inclui `BUFFERS` por padrão.
- **MySQL:** `slow_query_log=ON`, `long_query_time=0.5`, `performance_schema=ON`, `innodb_print_all_deadlocks=ON`, `innodb_buffer_pool_size` modesto e documentado.
- **Redis:** `maxmemory` definido, com política documentada. A escolha de política quando cache e filas dividem a mesma instância é assunto discutido em `docs/concepts/`.
- **RabbitMQ:** topologia declarada em `docker/rabbitmq/definitions.json`, carregada no boot.
- **PHP-FPM (bench):** `pm=static` com número de processos documentado, OPcache ligado, `opcache.validate_timestamps=0`.

**Orçamento de recursos (referência):** perfil padrão ≈ 2,5 GB de RAM; com `queue` + `obs` + `bench` ≈ 5–6 GB; `mysql` + `rabbit` ≈ +1,5 GB. Máquina recomendada: 16 GB de RAM e SSD. Disco conforme o dataset (§5.5).

---

## 4. Domínio

### 4.1 Contextos

| Contexto | Responsabilidade |
|---|---|
| Customers | Clientes, endereços, segmentos, LTV |
| Catalog | Categorias, produtos, variantes, preços, avaliações |
| Inventory | Estoque por variante e armazém, reservas |
| Orders | Pedidos, itens, histórico de status, cupons |
| Payments | Pagamentos, eventos do gateway |
| Integrations | Webhooks recebidos, sincronização com marketplace, exportação para ERP |
| Reporting | Relatórios e agregados |
| Platform | Jobs, auditoria, chaves de idempotência |

### 4.2 Tabelas

A lista dá as colunas principais e o significado de cada tabela. **Índices e constraints do baseline não são listados aqui de propósito:** descobrir o estado real do schema (`\d+ tabela`, `SHOW INDEX`) faz parte das tasks. A definição exata do baseline está no documento selado (§13.2).

| Tabela | Colunas principais | Observações |
|---|---|---|
| `customers` | id, uuid, email, name, phone, document_hash, segment (`retail`, `vip`, `wholesale`), status (`active`, `blocked`), marketing_opt_in, lifetime_value_cents, ltv_calculated_at, last_order_at, created_at, updated_at, deleted_at | Dados legados com caixa mista em e-mails |
| `addresses` | id, customer_id, type (`shipping`, `billing`), street, number, district, city, state (UF), zip, is_default, created_at | Clientes podem ter vários endereços |
| `categories` | id, parent_id, name, slug, position | Árvore de 3 níveis |
| `products` | id, category_id, name, slug, brand, description, status (`active`, `draft`, `archived`), base_price_cents, created_at, updated_at, deleted_at | |
| `product_variants` | id, product_id, sku, attributes (jsonb), price_cents, compare_at_price_cents, weight_grams, is_active, created_at, updated_at | |
| `product_reviews` | id, product_id, customer_id, rating (1–5), title, body, status (`pending`, `approved`, `rejected`), created_at | |
| `warehouses` | id, code, name, state | |
| `inventory` | id, variant_id, warehouse_id, on_hand, reserved, version, updated_at | Uma linha por variante × armazém |
| `inventory_reservations` | id, order_id, variant_id, warehouse_id, quantity, status (`active`, `consumed`, `released`), expires_at, created_at | |
| `coupons` | id, code, discount_type (`percent`, `fixed`), value, usage_limit, per_customer_limit, used_count, starts_at, ends_at | |
| `coupon_redemptions` | id, coupon_id, order_id, customer_id, created_at | |
| `orders` | id, uuid, number, customer_id (nulo em compra de convidado), status, channel (`web`, `app`, `marketplace`), warehouse_id, currency, subtotal_cents, discount_cents, shipping_cents, total_cents, coupon_id, shipping_address_id, marketplace_order_ref, placed_at, paid_at, fulfillment_started_at, canceled_at, created_at, updated_at | Status: `pending_payment`, `paid`, `picking`, `shipped`, `delivered`, `canceled`, `refunded` |
| `order_items` | id, order_id, product_id, variant_id, quantity, unit_price_cents, total_cents, created_at | |
| `order_status_history` | id, order_id, from_status, to_status, actor, changed_at | |
| `payments` | id, order_id, provider, provider_payment_id, method (`pix`, `card`, `boleto`), status (`pending`, `processing`, `authorized`, `captured`, `failed`, `refunded`), amount_cents, attempts, captured_at, failure_reason, created_at, updated_at | |
| `payment_events` | id, payment_id, provider_event_id, type, payload (jsonb), occurred_at, created_at | |
| `webhook_events` | id, provider (`gateway`, `marketplace`, `erp`), external_id, event_type, signature_valid, headers (jsonb), payload (jsonb), status (`received`, `processed`, `failed`, `ignored`), attempts, error, received_at, processed_at | |
| `marketplace_listings` | id, variant_id, marketplace, external_listing_id, last_synced_stock, last_synced_price_cents, last_synced_at, status | |
| `marketplace_syncs` | id, listing_id, kind (`stock`, `price`), payload (jsonb), status (`queued`, `sent`, `acked`, `failed`), attempts, last_error, requested_at, sent_at | |
| `erp_exports` | id, order_id, status, attempts, erp_reference, last_error, exported_at | |
| `analytics_daily_sales` | day, channel, orders_count, revenue_cents, updated_at | Alimentada pelo consumidor Python (T21) |
| `legacy_catalog_items` | *(somente MySQL)* id, category_id, product_id, variant_sku, title, brand, price_cents, stock, is_active, attributes (json), created_at, updated_at | Catálogo B2B legado, desnormalizado (T09) |
| `flash_sales`, `flash_sale_items`, `flash_sale_claims` | (introduzidas na release da T30) | Descritas na própria T30 |
| `audit_logs` | id, actor_type, actor_id, action, subject_type, subject_id, changes (jsonb), request_id, created_at | Tabela grande e só de inserção |
| `idempotency_keys` | id, scope, key, request_hash, response_code, response_body, locked_until, created_at | Existe no baseline, usada só por algumas rotas |
| `jobs`, `job_batches`, `failed_jobs` | padrão Laravel | Driver `database`, usado só onde explicitado |
| `users`, `sessions`, `personal_access_tokens`, `cache`, `cache_locks` | padrão starter/Sanctum | |

### 4.3 Máquinas de estado

- **Pedido:** `pending_payment → paid → picking → shipped → delivered`. `pending_payment → canceled`. `paid|picking → canceled` (com estorno). `delivered → refunded`.
- **Pagamento:** `pending → processing → authorized → captured`. `processing → failed`. `captured → refunded`. Eventos do gateway podem chegar fora de ordem.
- **Reserva:** `active → consumed | released`. Reservas expiram em 15 minutos no relógio do lab.

### 4.4 Superfície da aplicação

| Tipo | Identificador | Tasks |
|---|---|---|
| GET | `/api/me/orders` | T01 |
| GET | `/api/admin/customers/search?email=` · POST `/api/admin/customers` | T02 |
| GET | `/api/admin/fulfillment/queue?warehouse=&since=` | T03 |
| Comando | `marketplace:import-orders --file=` | T04 |
| GET | `/api/admin/reports/customer-spend` | T05 |
| GET | `/api/admin/reports/revenue-by-category?month=` | T06 |
| GET | `/api/admin/orders?page=&per_page=` · comando `orders:export` | T07 |
| Comando | `campaigns:build-reengagement --days=` | T08 |
| GET | `/api/legacy-catalog/categories/{id}/products?sort=&page=` (MySQL) | T09 |
| GET | `/api/admin/orders/recent?limit=` | T10 |
| GET | `/api/catalog/products?category=&in_stock=&sort=&page=` | T11 |
| Comando | `customers:recalculate-ltv` | T12 |
| POST | `/api/checkout` | T13, T24, T25 |
| GET | `/api/catalog/products/{slug}` | T14, T15 |
| PATCH | `/api/admin/variants/{id}/price` · GET `/api/catalog/variants/{sku}/availability` | T15 |
| GET | `/api/storefront/home` | T16 |
| POST | `/api/coupons/validate` · GET `/api/catalog/search?q=` | T17 |
| Job | `Erp\ExportOrderToErp` · comando `erp:enqueue-backlog` | T18 |
| Job | `Payments\CapturePayment` | T19 |
| Job | `Orders\FulfillPaidOrder` | T20 |
| Evento/consumidor | exchange `commerce.events` · `services/analytics-consumer` | T21 |
| POST | `/api/webhooks/gateway` | T22 |
| POST | `/api/orders/{uuid}/apply-coupon` | T23 |
| Job | `Marketplace\ImportMarketplaceOrder` | T24 |
| Comando | `inventory:rebalance` | T25 |
| Job | `Marketplace\SyncListingToMarketplace` · comando `marketplace:reconcile` | T26 |
| POST | `/api/webhooks/marketplace` | T27 |
| GET | `/api/me/orders/{uuid}` (+ checkout) | T28 |
| Página Inertia | `/admin/orders` (Vue) · GET `/api/admin/orders/search` | T29 |
| Release Flash Sale | `/api/flash-sales/*`, job `SettleFlashSaleClaim`, widget Vue | T30 |

Endpoints de tasks diferentes são independentes de propósito. Como cada task parte do baseline no próprio branch, os defeitos de uma não mascaram as medições de outra.

### 4.5 Parceiros simulados (`partners-mock`)

Serviço em Python (FastAPI) com quatro "parceiros" e um plano de controle. A documentação "pública" de cada parceiro, como um parceiro real forneceria, fica em `docs/partners/*.md` e faz parte do material do aluno.

**Gateway de pagamento (`/gateway/v1`):**
- `POST /payments` (aceita o header `Idempotency-Key`), `POST /payments/{id}/capture`, `POST /payments/{id}/refund`, `GET /payments/{id}`.
- Envia webhooks para `POST {APP_URL}/api/webhooks/gateway` com assinatura `X-BP-Signature: t=<unix>,v1=<hex hmac_sha256(secret, t + "." + raw_body)>`. Pode reenviar, duplicar, enviar em paralelo ou fora de ordem.

**ERP (`/erp/v1`):**
- `POST /orders`, `POST /orders:batch` (até 100 pedidos por chamada), `GET /orders/{ref}`.

**Marketplace (`/mkt/v1`):**
- `PUT /listings/{id}/stock` e `PUT /listings/{id}/price` (aceitam `Idempotency-Key` e `If-Match: <version>`), `POST /listings:batch`, `GET /listings/{id}`, `GET /orders/{ref}`, `POST /orders/{ref}/reject` (recusa um pedido, ex.: sem estoque).
- Limite de 10 requisições/s por token (token bucket). Acima disso responde `429` com `Retry-After`.
- Envia webhooks `order.created` e `order.canceled` assinados.

**Notificações (`/notify/v1`):**
- `POST /messages` (e-mail/push transacional; aceita `Idempotency-Key` opcional). Simula o provedor de e-mail usado por checkout, pagamentos e logística.

**Comportamentos programáveis por cenário** (determinísticos, consumidos em ordem por rota e chave):

| Resposta | Descrição |
|---|---|
| `200`, `201`, `202` | Sucesso |
| `400` | Payload inválido |
| `401` | Credencial inválida |
| `409` | Conflito (versão desatualizada / duplicidade) |
| `429` | Limite excedido, com `Retry-After` |
| `500`, `503` | Erro / indisponibilidade temporária |
| `slow` | Responde após `delay_ms` |
| `timeout` | Segura a conexão por `hang_ms` (padrão 120 s) sem responder |
| `down` | Recusa conexões durante uma janela |

**Plano de controle** (usado pelo harness e pelo checker; o aluno também pode usar):
- `POST /__control/scenarios` — carrega uma sequência, por exemplo `{"partner":"gateway","route":"capture","sequence":[{"status":500},{"status":500},{"status":200}],"repeat":false}`.
- `POST /__control/webhooks/emit` — dispara webhooks (`duplicate`, `parallel`, `out_of_order`, `bad_signature`, `replay_of`).
- `GET /__control/ledger?task=&route=&correlation_id=` — registro de todas as chamadas recebidas, com timestamp, headers selecionados, corpo resumido e chave de idempotência.
- `GET /__control/state/{partner}` — estado interno (ex.: estoque de cada listing no marketplace).
- `POST /__control/reset?task=` — limpa o namespace da task.

O ledger é a fonte de verdade para critérios como "no máximo uma captura por pagamento" e "no máximo N chamadas externas durante a requisição".

### 4.6 Eventos de domínio

`OrderPlaced`, `OrderPaid`, `OrderCanceled`, `OrderRefunded`, `PaymentCaptured`, `PaymentFailed`, `InventoryChanged`, `PriceChanged`. Os eventos `order.*` e `payment.*` também são publicados no RabbitMQ (exchange `commerce.events`, tipo topic) quando o perfil `rabbit` está ativo.

---

## 5. Dataset

### 5.1 Perfis e volumes

| Entidade | SMALL | MEDIUM | LARGE |
|---|---:|---:|---:|
| customers | 2.000 | 200.000 | 1.500.000 |
| addresses | 3.200 | 320.000 | 2.400.000 |
| categories | 60 | 300 | 600 |
| products | 1.000 | 20.000 | 100.000 |
| product_variants | 3.000 | 80.000 | 400.000 |
| product_reviews | 5.000 | 500.000 | 4.000.000 |
| warehouses | 3 | 5 | 8 |
| inventory | 9.000 | 400.000 | 3.200.000 |
| coupons / redemptions | 50 / 1.000 | 2.000 / 150.000 | 10.000 / 1.200.000 |
| **orders** | **10.000** | **1.000.000** | **8.000.000** |
| order_items | ~25.000 | ~2.500.000 | ~20.000.000 |
| order_status_history | ~30.000 | ~3.000.000 | ~24.000.000 |
| payments | ~11.000 | ~1.100.000 | ~8.800.000 |
| payment_events | ~30.000 | ~3.000.000 | ~24.000.000 |
| webhook_events | ~20.000 | ~2.000.000 | ~16.000.000 |
| marketplace_listings / syncs | 2.000 / 10.000 | 60.000 / 1.000.000 | 300.000 / 8.000.000 |
| audit_logs | ~20.000 | ~2.000.000 | ~16.000.000 |
| legacy_catalog_items (MySQL) | 50.000 | 2.000.000 | 10.000.000 |

SMALL serve para iterar rápido e para os checks de corretude com golden. MEDIUM é o padrão da maioria das tasks. LARGE é opcional e existe para sentir a escala real ("8 milhões de pedidos").

### 5.2 Distribuições (realismo pedagógico)

- **Tempo:** 36 meses de histórico terminando em `LAB_CLOCK`, crescimento de ~3% ao mês, sazonalidade semanal e picos de Black Friday e Natal.
- **Status de pedidos:** fortemente enviesado (a grande maioria entregue; poucos pendentes). Distribuição exata no documento selado.
- **Clientes:** distribuição de cauda longa (Zipf). Há clientes com zero pedidos, um pequeno grupo "whale" (atacado) com dezenas de milhares de pedidos e compras de convidado (sem cliente).
- **Produtos:** popularidade Zipf (itens "quentes"), variantes por tamanho e cor, parte do catálogo arquivada ou excluída logicamente.
- **E-mails e textos:** caixa mista e acentuação, como em dados legados reais.
- **Endereços:** parte dos clientes tem mais de um endereço.
- **Canais:** web, app e marketplace.
- **Pagamentos:** mais de uma tentativa em parte dos pedidos (falha → sucesso).
- **Sujeira histórica:** três anos de produção deixam marcas. Os dados podem conter situações que uma regra nova precisa tratar antes de ser aplicada.
- **Âncoras:** entidades de referência com IDs estáveis (clientes, SKUs, cupons, armazéns), usadas pelos cenários e pelos checkers. `make lab-info TASK=XX` mostra as âncoras relevantes para a task.

### 5.3 Determinismo

- Aleatoriedade por **hash**, não por estado: `lab_rand(seed, stream, n) = ('x' || substr(md5(seed || ':' || stream || ':' || n), 1, 12))::bit(48)::bigint / 2^48`. Isso funciona de forma idêntica em execução paralela.
- Nenhum `random()` ou `now()` no gerador. Datas derivadas de `LAB_CLOCK`.
- O dataset gera um `manifest.json` com contagens e checksums por tabela (`md5` de `string_agg` ordenado por `id`, em amostras de blocos fixos para LARGE). Datasets com o mesmo manifesto são intercambiáveis.

### 5.4 Pipeline de geração

1. `make lab-dataset DATASET=medium` executa `php artisan lab:dataset medium`.
2. Cria o database `bp_tpl_medium`, aplica as migrations do baseline **sem índices secundários**, gera os dados por SQL set-based (`INSERT ... SELECT` sobre `generate_series`, em etapas por tabela e em lotes de 1 M linhas), cria os índices do baseline, roda `VACUUM (ANALYZE)` e grava o `manifest.json`.
3. Para MySQL: exporta as tabelas necessárias com `COPY ... TO STDOUT (FORMAT csv)` para `storage/lab/datasets/<dataset>/mysql/*.csv` e carrega com `LOAD DATA LOCAL INFILE` quando uma task precisar.
4. SMALL também pode ser gerado via factories (`DatabaseSeeder` com `LAB_DATASET=small`) para o aluno estudar factories. O caminho oficial dos checkers é o gerador SQL.
5. O template fica somente leitura (`ALTER DATABASE ... WITH ALLOW_CONNECTIONS false`) e é clonado por `lab:start`.

### 5.5 Tempo e disco (estimativas a confirmar na implementação)

| Dataset | Geração (SSD comum) | Disco do template | Disco por task ativa |
|---|---|---|---|
| SMALL | < 1 min | ~100 MB | ~100 MB |
| MEDIUM | ~5–15 min | ~5–7 GB | ~5–7 GB |
| LARGE | ~40–120 min | ~40–55 GB | ~40–55 GB |

`LAB_KEEP_DBS` (padrão 2; recomendado 1 para LARGE) limita quantos databases de task ficam guardados. Os mais antigos são removidos e podem ser recriados do template a qualquer momento. Isso não destrói trabalho, porque o trabalho do aluno está no branch.

### 5.6 Versionamento

- **Nenhum dump é versionado.** `storage/lab/datasets/` fica no `.gitignore`.
- São versionados: o gerador, os manifestos esperados (`lab/datasets/<dataset>.manifest.json`), as fixtures pequenas de cenário (ex.: o arquivo de importação da T04 é **gerado**, e só o gerador é versionado) e os checksums golden.

---

## 6. Modelo de tasks

### 6.1 Anatomia de uma task

| Campo | Conteúdo |
|---|---|
| ID | `T01`…`T30`, com ticket fictício `BP-xxx` |
| Título | Frase curta no estilo de ticket |
| Nível | 1 (Fundamentos) a 5 (Sênior) |
| Cenário empresarial | Contexto de negócio, quem reclamou e por que importa |
| Sintoma | O que se observa, com números |
| Informações disponíveis | O que o "time" já sabe: logs, reclamações, dashboards, histórico |
| Objetivo | O resultado de negócio esperado (não a técnica) |
| Conceitos envolvidos | Temas a dominar, com leituras em `docs/concepts/` |
| Preparar o cenário | Comando `make` |
| Endpoint / tabela / job | Pontos de entrada |
| Dataset recomendado | SMALL, MEDIUM ou LARGE |
| Critérios de aceite | Numerados (`AC1`…), mensuráveis, verificados por `lab-check` |
| Medir o antes / o depois | Comandos e o que observar |
| Testes automatizados possíveis | O que o aluno pode, ou deve, escrever |
| Perguntas de reflexão | Para registrar em `docs/lab-notes/XX.md` |
| Hints | No máximo 3, graduais, em `docs/tasks/XX/hints.md` e via `make lab-hint` |

### 6.2 Arquivos de uma task

```
docs/tasks/07-deep-pagination/README.md     enunciado (visível)
docs/tasks/07-deep-pagination/hints.md      hints em <details>, um por bloco
lab/tasks/07/task.yaml                      manifesto (abaixo)
lab/tasks/07/scenario.sql | scenario.php    preparação específica da task
lab/tasks/07/bench.k6.js                    carga (opcional)
lab/tasks/07/race/*.yaml                    cenários de concorrência (opcional)
lab/tasks/07/baseline.<dataset>.json        números de referência do baseline (só métricas)
app/Lab/Tasks/T07/Checks/*.php              verificações (sem código de solução)
tests/Lab/T07/AcceptanceTest.php            testes AC1..ACn (nomes neutros)
vault/DO_NOT_OPEN_SOLUTIONS/T07/            solução (ver §8)
```

**Manifesto (`task.yaml`), exemplo de formato:**

```yaml
id: T07
ticket: BP-189
title: "Backoffice: página 40.000 leva 20s e itens se repetem"
level: 3
datasets: { default: medium, allowed: [small, medium, large] }
profiles: []                     # perfis Compose extras (queue, obs, rabbit, mysql, bench)
owned_paths:                     # arquivos que o aluno deve alterar; usados por lab-reset CODE=1
  - app/Http/Controllers/Admin/OrderIndexController.php
  - app/Console/Commands/Orders/ExportOrdersCommand.php
  - database/migrations/
scenario: lab/tasks/07/scenario.sql
anchors: [orders.deep_position, customers.reference_set]
checks:
  - { id: AC1, type: plan_cost_ratio, mandatory: true }
  - { id: AC2, type: race_consistency, scenario: lab/tasks/07/race/insert-while-paging.yaml, mandatory: true }
  - { id: AC3, type: contract, mandatory: true }
  - { id: AC4, type: plan_no_full_scan, mandatory: true }
benchmark: { deterministic: [qpr, blk, plan], load: lab/tasks/07/bench.k6.js }
notes_required: true
```

### 6.3 Níveis

| Nível | Rótulo | Expectativa |
|---|---|---|
| 1 | Fundamentos | Uma causa, ferramentas básicas (EXPLAIN, contagem de queries) |
| 2 | Intermediário | Uma causa principal com um desvio ou trade-off |
| 3 | Pleno | Mais de uma causa ou exigência de corretude + performance |
| 4 | Pleno+ | Concorrência, falhas parciais ou sistemas distribuídos |
| 5 | Sênior | Incidente com múltiplas causas, priorização e comunicação |

### 6.4 Métricas determinísticas (kit de medição)

| Sigla | Métrica | Como é medida |
|---|---|---|
| **QPR** | Queries por requisição/job/comando | `DB::listen` no `QueryCounter`. Header `X-Lab-Queries` em modo lab. |
| **BLK** | Blocos acessados (shared hit + read) | `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` das queries capturadas. A soma hit+read é estável entre execuções com o mesmo plano e os mesmos dados. |
| **PLAN** | Forma do plano | Tipos de nó por relação (Seq Scan, Index Scan, Sort, Hash Join...), linhas por nó |
| **ROWSREAD** | Linhas lidas das tabelas base (PostgreSQL) | Soma, nos nós de leitura do plano, de (linhas retornadas + removidas por filtro) × loops. Complementa o BLK quando buffers em cache distorcem a comparação. |
| **ROWS** | Linhas examinadas (MySQL) | `performance_schema.events_statements_history.ROWS_EXAMINED` e `Handler_read_*` |
| **MEM** | Pico de memória PHP | `memory_get_peak_usage(true)` do processo |
| **WAL** | Bytes de WAL gerados | `pg_wal_lsn_diff` antes e depois de uma operação de escrita fixa |
| **EXT** | Chamadas externas | Ledger do `partners-mock`, por correlation id, rota e chave |
| **CACHE** | Hits, misses e recomputações | Eventos `CacheHit`/`CacheMissed` e contador de recomputação no ponto de cálculo |
| **INV** | Invariantes de dados | Consultas de verificação ao fim de um cenário (ex.: `reserved <= on_hand`) |
| **GOLD** | Checksum de resultado | SHA-256 do resultado canônico (linhas ordenadas e serializadas), comparado com `lab/golden/` |
| **PW** | Métricas de navegador | Playwright: nº de requisições, bytes, nós de DOM, chunks carregados |
| **LAT** | Latência / throughput | k6 e logs de acesso. **Informativo:** gera WARN, nunca FAIL |

### 6.5 Anotações e respostas do aluno

- `docs/lab-notes/XX.md`: investigação, evidências (planos, contagens, prints), decisões e reflexões. Algumas tasks exigem seções específicas; o checker verifica só a presença das seções, não o conteúdo.
- `storage/lab/answers/XX.json`: nas tasks de diagnóstico (T28, T30), respostas curtas e normalizadas (ex.: dimensão ou dependência causadora), comparadas por hash com `lab/golden/answers/XX.json`. O hash não revela a resposta.

---

## 7. Mecanismo de reset / check / benchmark

### 7.1 Interface

O `Makefile` é uma fachada fina para `./vendor/bin/sail artisan lab:*`. Os mesmos comandos podem ser chamados via Artisan.

| Comando | Efeito |
|---|---|
| `make lab-list` | Lista as tasks com status (não iniciada / em andamento / PASS), dataset e último check |
| `make lab-dataset DATASET=medium [FORCE=1]` | Gera ou valida o template do dataset (idempotente, confere o manifesto) |
| `make lab-start TASK=07 [DATASET=medium] [FROM=<branch>] [PROFILES=queue,obs]` | Prepara e ativa a task (§7.2) |
| `make lab-reset TASK=07 [CODE=1]` | Recria o estado da task (§7.3) |
| `make lab-check TASK=07` | Executa os critérios de aceite (§7.4) |
| `make lab-benchmark TASK=07 LABEL=before\|after [LOAD=10\|100\|300]` | Mede e grava (§7.5) |
| `make lab-compare TASK=07` | Compara o último `before` com o último `after` |
| `make lab-race TASK=07 SCENARIO=<nome>` | Roda um cenário de concorrência isolado e mostra a linha do tempo de eventos |
| `make lab-drain TASK=07` | Processa as filas da task até esvaziar (`--stop-when-empty`) |
| `make lab-scenario TASK=06 STEP=<nome>` | Executa um passo extra do cenário da task (ex.: inserir vendas novas) |
| `make lab-workload TASK=04 [VERIFY=1]` | Executa o workload de leitura de referência da task; com `VERIFY=1`, compara os planos com o baseline |
| `make lab-load TASK=28` | Gera o tráfego de fundo da task |
| `make lab-status` | Task ativa, branch, dataset, database, perfis e serviços |
| `make lab-info TASK=07` | Endpoints, âncoras, tokens e comandos úteis |
| `make lab-hint TASK=07` | Mostra o **próximo** hint não visto (um por vez) e registra o uso |
| `make lab-psql` / `lab-mysql` / `lab-redis` / `lab-logs` | Atalhos de investigação já apontados para a task ativa |
| `make reveal TASK=07` | Informa **apenas o caminho** da solução, após confirmação explícita (§8) |
| `make lab-verify-solutions [TASK=07]` | **Mantenedores/CI:** prova que o baseline falha e a solução passa (§13.6) |

### 7.2 `lab-start`

1. Verifica os pré-requisitos (Docker, serviços, versão do lab) e se o working tree está limpo. Se não estiver, para com uma mensagem clara e nunca faz stash automático.
2. Cria `lab/task-XX` a partir de `lab-baseline` (ou de `FROM`) se ainda não existir, e faz checkout.
3. Garante o template do dataset (gera se faltar, após confirmação, porque pode demorar).
4. Se o database `bp_tXX` não existir, clona do template, aplica o cenário da task e roda `migrate` (aplicando as migrations que o aluno já criou no branch).
5. Configura os prefixos Redis, o vhost RabbitMQ e o namespace do mock. Sobe os perfis necessários. Reinicia os workers da task.
6. Grava `storage/lab/state.json`.
7. Imprime o caminho do enunciado, as âncoras e os próximos passos (`make lab-benchmark TASK=XX LABEL=before`).

### 7.3 `lab-reset`

- **Estado (padrão):** recria `bp_tXX` do template, reaplica o cenário, roda as migrations do branch, limpa as chaves Redis do prefixo da task, filas, vhost e namespace do mock, e reinicia os workers.
- **Código (`CODE=1`):** pede a confirmação digitada `RESET 07`, lista os arquivos que serão restaurados e executa `git restore --source=lab-baseline -- <owned_paths>`. Nunca apaga branches, nunca faz `reset --hard`, nunca mexe em arquivos fora de `owned_paths` nem em `docs/lab-notes/`.

### 7.4 `lab-check`

1. **Pré-condições:** branch correto, database da task ativo, nenhuma migration pendente, serviços dos perfis saudáveis, checkpoints obrigatórios presentes. Se falhar, o resultado é `INCONCLUSIVE` com instrução objetiva.
2. Executa cada `ACn` em ordem, com dados de uma cópia descartável quando o check altera estado (`bp_tXX_check`, clonada do database da task).
3. Imprime uma tabela e grava `storage/lab/runs/TXX/check-<timestamp>.json`.

Exemplo de saída:

```
T07 — Backoffice: página 40.000 leva 20s e itens se repetem        dataset=medium  branch=lab/task-07
┌─────┬──────────────────────────────────────────────────────────┬────────┬───────────────┬───────────────┐
│ AC  │ Critério                                                 │ Status │ Medido        │ Limite        │
├─────┼──────────────────────────────────────────────────────────┼────────┼───────────────┼───────────────┤
│ AC1 │ Custo da página profunda ≤ 3× custo da primeira página   │ FAIL   │ 1 412×        │ ≤ 3×          │
│ AC2 │ Percurso completo sem repetidos/ausentes sob inserções   │ FAIL   │ 37 repetidos  │ 0             │
│ AC3 │ Contrato de paginação válido                             │ PASS   │ —             │ —             │
│ AC4 │ Nenhuma query lê a tabela inteira                        │ FAIL   │ 2 queries     │ 0             │
│ LAT │ p95 (k6, 10 VUs) — informativo                           │ INFO   │ 18,2 s        │ —             │
└─────┴──────────────────────────────────────────────────────────┴────────┴───────────────┴───────────────┘
Resultado: FAIL (3 de 4 obrigatórios falharam). Registro: storage/lab/runs/T07/check-20260924T141200.json
```

Regras de mensagem: mostrar critério, valor medido e limite. **Nunca** sugerir a correção, citar nomes de índices, colunas "certas" ou qualquer caminho do vault.

**Status possíveis:** `PASS`, `FAIL`, `WARN` (métrica informativa fora do esperado), `INCONCLUSIVE` (pré-condição não atendida ou cenário não exercitado), `ERROR` (falha de ambiente).
**Exit codes:** 0 = todos os obrigatórios PASS; 1 = algum FAIL; 2 = INCONCLUSIVE; 3 = ERROR.

**Formato do JSON de resultado:**

```json
{
  "task": "T07", "dataset": "medium", "branch": "lab/task-07", "commit": "abc1234",
  "lab_version": "1.0.0", "started_at": "...", "finished_at": "...",
  "results": [
    {"id": "AC1", "status": "FAIL", "metric": "blk_ratio", "measured": 1412.0, "limit": 3.0, "details": {"first_page_blk": 41, "deep_page_blk": 57902}}
  ],
  "summary": {"mandatory": 4, "passed": 1, "failed": 3, "warn": 0}
}
```

### 7.5 `lab-benchmark` e `lab-compare`

- **Parte determinística** (sempre): executa as operações de referência da task (requisições com âncoras fixas, comando, job) e registra QPR, BLK, PLAN, ROWS, MEM, WAL, EXT e CACHE.
- **Parte de carga** (quando a task define `bench.k6.js`): roda no modo **bench** (Nginx + FPM) com orçamento fixo de iterações, para que a quantidade de trabalho seja igual antes e depois:
  - `LOAD=10`: 10 VUs, 200 iterações por VU;
  - `LOAD=100`: 100 VUs, 50 iterações por VU;
  - `LOAD=300`: rampa 0→300 VUs, 30 iterações por VU.
  - Registra RPS, p50, p95, p99, taxa de erro e checks do k6.
- Grava em `storage/lab/benchmarks/TXX/<label>-<timestamp>.json`, incluindo a descrição da máquina (CPU, RAM, versão do Docker) para contextualizar.
- `lab-compare` mostra as variações relativas (`after/before`). Comparações entre máquinas diferentes vêm marcadas como não comparáveis.

### 7.6 Checkpoints e harness de concorrência

**API na aplicação:**

```php
Lab::checkpoint(string $name, array $context = []): void
```

- No-op quando `LAB_ENABLED=false` ou quando não há política para o participante atual.
- O participante é identificado por `LAB_PARTICIPANT` (CLI/worker) ou pelo header `X-Lab-Participant` (HTTP). O header só é aceito com o lab ativo e com o token de harness `X-Lab-Harness` válido.
- As políticas ficam em Redis (`bp:tXX:lab:policy:<participant>:<checkpoint>`):
  - `pass`: segue;
  - `record`: registra o evento e segue;
  - `pause`: bloqueia até receber um sinal (`until: signal:<nome>`), com `timeout_ms` de segurança;
  - `crash`: `posix_kill(getmypid(), SIGKILL)`;
  - `throw`: lança a exceção configurada.
- Todo checkpoint atingido é registrado num Redis Stream `bp:tXX:lab:events` (participante, checkpoint, timestamp monotônico, contexto).
- **Pseudo-checkpoint `db.before_commit`:** o lab escuta o evento de pré-commit de transação do Laravel (ou envolve o gerenciador de transações, se o evento não existir na versão instalada). Assim, um participante pode ser pausado imediatamente antes do commit mesmo que a lógica tenha sido reescrita.
- Em modo lab, cada conexão PostgreSQL executa `SET application_name = 'bp:tXX:<participant>'`. Isso permite ao harness detectar, via `pg_stat_activity` (`wait_event_type = 'Lock'`), que um participante está bloqueado esperando lock, **sem depender de tempo**.

**Cenários de corrida (`lab/tasks/XX/race/*.yaml`), exemplo de formato:**

```yaml
name: last-item-two-channels
participants:
  A: { kind: http, request: "POST /api/checkout", body_fixture: checkout-last-item.json }
  B: { kind: job,  job: "Marketplace\\ImportMarketplaceOrder", payload_fixture: mkt-order-last-item.json }
policies:
  A: { "inventory.reserve.2": { action: pause, until: "signal:release-A", timeout_ms: 15000 } }
steps:
  - start: A
  - wait_event: { participant: A, checkpoint: "inventory.reserve.2" }
  - start: B
  - wait_any:
      - { finished: B }
      - { blocked_on_lock: B }          # via pg_stat_activity
      - { timeout_ms: 5000 }            # liveness only; never decides the result
  - signal: release-A
  - wait: { finished: [A, B], timeout_ms: 30000 }
assert: invariants:inventory            # invariantes definidos no checker da task
```

**Regras do harness:**

1. Tempo existe só como limite de liveness, nunca como critério de resultado.
2. O cenário precisa demonstrar a falha no baseline de forma **100% reprodutível**. O Codex prova isso com 20 execuções seguidas (§13.6).
3. Se o código do aluno não passa pelo checkpoint esperado, o harness tenta o pseudo-checkpoint `db.before_commit`. Se nenhum for atingido, o cenário roda sem pausa e o resultado vem acompanhado de `INFO: janela de corrida não exercitada`. Nessas tasks há sempre um segundo check de **stress** com semente fixa (N participantes simultâneos em alta contenção), para que uma solução incorreta não passe só por ter "fugido" do checkpoint.
4. Os checkpoints que o baseline declara como contrato do lab estão listados no enunciado de cada task ("não remova as chamadas `Lab::checkpoint()` destes pontos"). Para não virarem pista, o baseline coloca checkpoints em **vários** pontos neutros de cada fluxo instrumentado (entrada, depois de cada passo de I/O, antes do commit), sempre com nomes neutros no formato `<área>.<operação>.<n>` (ex.: `inventory.reserve.2`). Nunca há um checkpoint só na janela de corrida.

### 7.7 Captura de queries e planos

- O `QueryCounter` grava, por requisição ou processo, o SQL, os bindings, a conexão, o tempo e o chamador (arquivo:linha) em `storage/lab/captures/<run>.ndjson`.
- O `PlanInspector` reexecuta cada `SELECT` capturado com `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` dentro de uma transação que é desfeita. Para DML, usa `EXPLAIN` sem `ANALYZE` ou executa em transação desfeita, conforme o check. No MySQL, usa `EXPLAIN ANALYZE` / `EXPLAIN FORMAT=JSON` e os deltas de `Handler_read_*`.
- Os checks de plano são independentes de como o aluno escreveu a query. Olham todas as queries capturadas daquela operação e avaliam propriedades como "nenhum Seq Scan sobre `orders`" ou "BLK ≤ X% do baseline".

---

## 8. Regras anti-spoiler

1. **Separação física:**
   - `docs/tasks/`: enunciados, hints e contratos (visíveis);
   - `docs/concepts/`: referências conceituais **genéricas**, sem mencionar tasks, arquivos, tabelas ou soluções do projeto;
   - `vault/DO_NOT_OPEN_SOLUTIONS/`: tudo que é solução.
2. **Conteúdo do vault, por task (`vault/DO_NOT_OPEN_SOLUTIONS/TXX/`):** `README.md` (solução completa e explicação), `investigation.md` (caminho de investigação esperado, com comandos e leituras), `solution.patch` (diff contra `lab-baseline`), `queries.sql` (queries corrigidas, quando houver), `results.md` (resultados esperados antes/depois nos três datasets) e `tradeoffs.md` (alternativas aceitas, rejeitadas e por quê).
3. **Nenhum link** para o vault em READMEs, enunciados, conceitos, hints, mensagens do checker, comentários de código ou templates de PR. O README principal diz apenas: *"Solutions exist in a deliberately isolated vault. Do not open it until you choose to review a task."*
4. **Nenhum snippet de solução** em enunciados, hints, conceitos, testes, checkers, mensagens de erro, nomes de arquivos ou nomes de testes. Testes se chamam `AcceptanceTest::test_ac1()` etc. e o texto do critério é o mesmo do enunciado.
5. **Checkers verificam comportamento e métricas, não implementação:** nada de "existe o índice `orders_customer_id_index`". Sim a "nenhum Seq Scan em `orders`" e "BLK ≤ 2% do baseline".
6. **Golden por hash:** resultados esperados são checksums. Quando o check falha, mostra no máximo três exemplos de divergência como dado (ex.: "cliente âncora C-0042: obtido 10, esperado 5"), nunca a query correta.
7. **Falha não revela nada:** o checker jamais mostra, sugere ou abre soluções após uma falha. Não existe modo "mostrar resposta".
8. **`make reveal TASK=07`:**
   - pede que o aluno digite exatamente `REVEAL 07`;
   - avisa se a task nunca passou no check (sem bloquear);
   - imprime **somente** o caminho `vault/DO_NOT_OPEN_SOLUTIONS/T07/README.md`, sem conteúdo;
   - registra a revelação em `storage/lab/reveals.log`.
9. **Busca acidental:** o repositório inclui `.ignore` e `.rgignore` com `vault/` (ripgrep e editores que respeitam esses arquivos), e `docs/lab-notes/README.md` recomenda adicionar `vault/**` a `search.exclude` e `files.exclude` do editor. A pasta **não** é versionada criptografada, por simplicidade.
10. **Hints graduais:** no máximo 3 por task, do mais geral ao mais específico. Nenhum hint contém código ou nome de artefato da solução. `make lab-hint` mostra um por vez. Os hints também ficam em `docs/tasks/XX/hints.md`, cada um dentro de `<details>`.
11. **Histórico Git neutro:** commits que criam o baseline têm mensagens neutras ("feat(orders): admin listing"). É proibido "plant bug", "missing index for T01" e similares. Commits do vault só tocam `vault/`.
12. **Código do baseline sem pistas:** sem comentários como `TODO: add index`, `FIXME: race`, `// slow`. Nomes de variáveis e métodos plausíveis de produção.
13. **Este documento:** descreve tasks sem soluções. O desenho dos defeitos fica no documento selado citado em §13.2, que segue as mesmas regras do vault.

---

## 9. As 30 tasks

### Distribuição

| Bloco | Tasks | Tema |
|---|---|---|
| A | T01–T09 | Banco de dados: planos, índices, agregações, paginação, subqueries, MySQL × PostgreSQL |
| B | T10–T13 | Laravel/Eloquent e processamento de dados |
| C | T14–T17 | Redis e cache |
| D | T18–T21 | Filas, jobs e workers (Redis Queue, Horizon, RabbitMQ + Python) |
| E | T22–T25 | Concorrência, idempotência, transações, locks e deadlocks |
| F | T26–T27 | Integrações, resiliência e segurança |
| G | T28 | Observabilidade |
| H | T29 | Performance de front-end / full stack |
| I | T30 | Incidente final integrando tudo |

**Ajuste em relação à sugestão original:** o bloco de banco tem 9 tasks em vez de 8, com uma dedicada ao MySQL (T09). O bloco Eloquent fica com 4. Transações, locks, isolamento e deadlocks, também assuntos de banco, estão no bloco E (T22–T25). Com isso, **13 das 30 tasks** têm o banco como eixo principal.

Convenções usadas abaixo:
- "Preparar" sempre inclui `make lab-start TASK=XX`. O dataset padrão é o recomendado.
- "Antes"/"Depois" sempre incluem `make lab-benchmark TASK=XX LABEL=before|after` e `make lab-compare TASK=XX`. Os itens listados são o que observar além disso.
- `BLK`, `QPR`, `EXT` etc. são as métricas da §6.4.
- As notas vão em `docs/lab-notes/XX.md`.

---

### T01 — "Meus pedidos" leva 6 segundos

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-101 | 1 — Fundamentos | Banco / PostgreSQL | MEDIUM (SMALL para iterar; LARGE opcional) |

**Cenário empresarial.** O app da Bottleneck Store migrou de MySQL para PostgreSQL no último trimestre. O schema foi convertido 1:1 por uma ferramenta. Desde então, o atendimento recebe reclamações de que a tela "Meus pedidos" demora, principalmente em horário de pico.

**Sintoma.** `GET /api/me/orders` (20 pedidos por página, do mais recente para o mais antigo) tem p95 de 5–7 s no MEDIUM. A CPU do banco sobe junto com o tráfego da tela.

**Informações disponíveis.**
- Top 5 do `pg_stat_statements` (via `make lab-psql`): a consulta da tela lidera em tempo total.
- Log de acesso com a rota e as durações.
- Diagrama do domínio (§4.2) e o fato de o schema ter sido convertido automaticamente.

**Objetivo.** Fazer a listagem paginada do cliente ler só os dados de que precisa, sem mudar a resposta.

**Conceitos envolvidos.** `EXPLAIN`, `EXPLAIN ANALYZE`, `BUFFERS`; Seq Scan × Index Scan × Bitmap Heap Scan; B-tree; custo estimado × real; linhas estimadas × reais; foreign keys e índices no PostgreSQL × MySQL.

**Preparar.** `make lab-start TASK=01`

**Endpoint / tabela.** `GET /api/me/orders?page=1` · `orders`

**Critérios de aceite.**
- **AC1** — Nenhuma query capturada da requisição faz leitura sequencial de `orders`, para os três clientes âncora (comum, VIP e atacado).
- **AC2** — BLK da query principal ≤ 2% do baseline, para os três clientes âncora.
- **AC3** — A resposta é idêntica à do baseline (GOLD) para os três clientes âncora, nas páginas 1 e 3.
- **AC4** — Toda mudança de schema é uma migration reversível (o check executa `down` e `up` numa cópia).

**Medir o antes.** Na query capturada (`X-Lab-Queries`, ou `storage/lab/captures`), rode `EXPLAIN (ANALYZE, BUFFERS)`. Observe o tipo de nó sobre `orders`, as linhas estimadas × reais e os blocos lidos.

**Medir o depois.** O mesmo `EXPLAIN` e a comparação de BLK e do plano. Opcional: `LOAD=10` para ver a latência.

**Testes automatizados possíveis.** Teste de feature que valida a paginação e a ordenação da resposta. Teste da migration (up/down). Opcional: teste que usa o `PlanInspector` para travar o plano.

**Perguntas de reflexão.**
1. Por que a mesma tabela no MySQL/InnoDB provavelmente não teria esse sintoma?
2. Quanto essa mudança custa em escrita e em disco? Como você mediria?
3. Por que as linhas estimadas e as reais diferem no plano antes da mudança?
4. O que mudaria se a tela ordenasse por valor total em vez de data?

**Hints.**
1. No plano, procure qual tabela é lida por inteiro e compare as linhas lidas com as linhas retornadas.
2. Liste os índices que realmente existem em `orders` (`\d orders`) e compare com as colunas do `WHERE`.
3. A consulta filtra **e** ordena. Uma única estrutura pode servir aos dois.

---

### T02 — Busca de cliente por e-mail: lenta desde a "correção"

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-114 | 1 — Fundamentos | Banco / PostgreSQL | MEDIUM |

**Cenário empresarial.** O atendimento busca clientes por e-mail o dia inteiro. Há duas sprints, a busca "não encontrava" clientes que existiam, e um dev corrigiu. Desde então, cada busca leva ~4 s. Além disso, o CRM reclama de clientes duplicados que diferem só em maiúsculas/minúsculas no e-mail.

**Sintoma.** `GET /api/admin/customers/search?email=Maria.Silva@Example.com` leva 3–5 s no MEDIUM. `POST /api/admin/customers` aceita `maria.silva@example.com` mesmo já existindo `Maria.Silva@example.com`.

**Informações disponíveis.**
- O PR da "correção" (no histórico do branch baseline, com mensagem neutra).
- Uma planilha do CRM com exemplos de duplicados (`storage/lab/fixtures/t02/crm-duplicates.csv`, gerada no `lab-start`).
- Top do `pg_stat_statements`.

**Objetivo.** Busca por e-mail rápida e sem diferenciar caixa, **e** impossibilidade de cadastrar dois clientes com o mesmo e-mail em caixas diferentes, com uma regra garantida pelo banco.

**Conceitos envolvidos.** Sargability; índices sobre expressões; collation e sensibilidade a caixa (PostgreSQL determinístico, `citext`, collations ICU não determinísticas; MySQL com `utf8mb4_0900_ai_ci`); unicidade garantida pelo banco × validação na aplicação; dados legados antes de uma nova restrição.

**Preparar.** `make lab-start TASK=02`

**Endpoint / tabela.** `GET /api/admin/customers/search?email=` · `POST /api/admin/customers` · `customers`

**Critérios de aceite.**
- **AC1** — A busca não faz leitura sequencial de `customers` para os 20 e-mails do conjunto de teste, em qualquer combinação de caixa.
- **AC2** — Os 20 e-mails do conjunto de teste são encontrados independentemente da caixa digitada (GOLD).
- **AC3** — Cadastrar um e-mail que difere de um existente só pela caixa retorna `422` com mensagem de negócio, mesmo com duas requisições simultâneas (harness). Nunca `500` e nunca dois registros.
- **AC4** — A regra do AC3 é garantida pelo banco: um `INSERT` direto via SQL com o e-mail em outra caixa é rejeitado.
- **AC5** — Nenhum cliente existente é apagado sem trilha. A decisão sobre os conflitos já existentes está documentada nas notas, e a contagem de clientes + registros arquivados ou mesclados é igual à original.

**Medir o antes.** `EXPLAIN (ANALYZE, BUFFERS)` da busca. Tente criar o mesmo e-mail com caixa diferente. Conte os conflitos existentes no dataset.

**Medir o depois.** Os mesmos passos. `lab-check`.

**Testes automatizados possíveis.** Teste de feature de busca com variações de caixa. Teste de cadastro duplicado. Teste de migration com dados conflitantes.

**Perguntas de reflexão.**
1. Por que a "correção" anterior deixou a busca lenta?
2. Normalizar na escrita ou tratar na leitura: quais os trade-offs?
3. Como o MySQL resolveria o mesmo problema por padrão, e que surpresas isso traz (acentos, `ß`, emojis)?
4. O que fazer com os dados que já violam a regra nova?

**Hints.**
1. Compare o que está indexado com a expressão que aparece no `WHERE`.
2. Índices não precisam ser só sobre colunas cruas.
3. Antes de criar uma restrição, pergunte o que os três anos de dados já contêm.

---

### T03 — Fila de separação do armazém lenta mesmo "com índice"

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-131 | 2 — Intermediário | Banco / PostgreSQL | MEDIUM (LARGE recomendado para sentir a escala) |

**Cenário empresarial.** A expedição de cada armazém abre a "fila de separação": pedidos pagos daquele armazém desde uma data, dos mais antigos para os mais novos, 100 por vez. "Já existe índice em `status` e em `placed_at`", diz o DBA anterior. Mesmo assim, no fim do mês a tela passa de 3 s.

**Sintoma.** `GET /api/admin/fulfillment/queue?warehouse=SP1&since=2026-06-01` tem p95 ~3 s no MEDIUM e ~15 s no LARGE, e piora quanto mais antigo o `since`.

**Informações disponíveis.** A lista de índices atuais de `orders` (descubra-a). As estatísticas de colunas em `pg_stats`. Um comentário no ticket: "adicionamos mais um índice ano passado e não mudou nada".

**Objetivo.** A fila de separação responde com custo proporcional ao que retorna, para qualquer armazém e janela.

**Conceitos envolvidos.** Índice composto; ordem das colunas (igualdade, intervalo, ordenação); seletividade e cardinalidade (`pg_stats`: `n_distinct`, `most_common_vals`, `most_common_freqs`); índice parcial; Bitmap AND; `ANALYZE` e estatísticas; índices inúteis de baixa cardinalidade.

**Preparar.** `make lab-start TASK=03`

**Endpoint / tabela.** `GET /api/admin/fulfillment/queue` · `orders`

**Critérios de aceite.**
- **AC1** — BLK ≤ 1% do baseline em três combinações de parâmetros (armazém grande/pequeno × janela curta/longa).
- **AC2** — O plano não ordena mais linhas do que as que retorna (nenhum nó Sort com entrada acima de 1.000 linhas).
- **AC3** — Nenhum índice novo é redundante com um existente (nenhum índice é prefixo de outro sobre `orders` depois da mudança).
- **AC4** — As notas justificam as escolhas com números de `pg_stats` (seções "Seletividade" e "Decisão").
- **AC5** — GOLD da resposta para as três combinações.

**Medir o antes.** `EXPLAIN (ANALYZE, BUFFERS)` nas três combinações. Consulte `pg_stats` para `status`, `warehouse_id` e `placed_at`. Veja o uso dos índices em `pg_stat_user_indexes`.

**Medir o depois.** Os mesmos planos. Tamanho dos índices (`pg_relation_size`). `lab-compare`.

**Testes automatizados possíveis.** Teste de feature de ordenação e filtros. Teste de plano via `PlanInspector` para a combinação mais pesada.

**Perguntas de reflexão.**
1. Por que um índice só em `status` quase nunca ajuda nesse dataset?
2. O que acontece com o plano se a mesma informação for indexada em outra ordem de colunas?
3. Quando um índice parcial é melhor, e quando vira armadilha (mudanças de regra, planos genéricos com parâmetros)?
4. Como o MySQL resolveria (index merge, ordenação por índice)?

**Hints.**
1. Descubra quantas linhas cada filtro elimina sozinho.
2. Um índice composto pode filtrar e entregar ordenado ao mesmo tempo, dependendo da ordem das colunas.
3. Colunas comparadas por igualdade e por intervalo não são intercambiáveis dentro de um índice.

---

### T04 — Importação do marketplace ficou 4× mais lenta e o disco cresceu 60%

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-147 | 2 — Intermediário | Banco / PostgreSQL | MEDIUM |

**Cenário empresarial.** Todo dia, o comando `marketplace:import-orders` importa um arquivo com os pedidos do marketplace (100 mil no MEDIUM). No último ano, vários times criaram índices "para acelerar relatórios". A importação, que levava 6 minutos, agora leva 25, e o banco cresceu 60%.

**Sintoma.** A importação de referência gera muito mais escrita (WAL) do que o volume de dados justificaria. As tabelas de pedidos têm índices demais.

**Informações disponíveis.**
- Arquivo de importação determinístico (gerado em `storage/lab/fixtures/t04/`).
- `make lab-workload TASK=04`: executa o **workload de leitura de referência** (as consultas reais dos relatórios e telas) para popular as estatísticas de uso.
- `pg_stat_user_indexes`, `pg_stat_statements`, `pg_relation_size`.

**Objetivo.** Reduzir o custo de escrita da importação sem piorar nenhuma consulta do workload de leitura.

**Conceitos envolvidos.** Custo de escrita de índices; WAL; índices duplicados, redundantes (prefixo) e não utilizados; HOT updates e fillfactor; bloat; trade-off leitura × escrita; representatividade do período observado; índices que garantem regras (UNIQUE) e índices que servem a FKs.

**Preparar.** `make lab-start TASK=04` (roda o workload uma vez para popular as estatísticas)

**Comando / tabelas.** `marketplace:import-orders --file=...` · `orders`, `order_items`, `payment_events`, `order_status_history`

**Critérios de aceite.**
- **AC1** — O WAL gerado pela importação de referência é ≤ 60% do baseline.
- **AC2** — Nenhuma regressão de leitura: todas as consultas do workload mantêm BLK ≤ 110% do baseline e nenhuma passa a fazer leitura sequencial de tabela com mais de 100 mil linhas.
- **AC3** — O resultado da importação é idêntico ao baseline (contagens e GOLD).
- **AC4** — Nenhuma regra de integridade é perdida (os testes de unicidade e FK do domínio continuam passando).
- **AC5** — As notas trazem uma tabela com índice, evidência (uso, redundância, tamanho) e decisão.

**Medir o antes.** `lab-benchmark` registra WAL, tamanho dos índices e duração (informativa). Consulte `pg_stat_user_indexes` depois do workload.

**Medir o depois.** Os mesmos números. `make lab-workload TASK=04 VERIFY=1` compara os planos do workload.

**Testes automatizados possíveis.** Teste da migration (up/down). Teste de integridade (unicidade e FKs) com dados mínimos.

**Perguntas de reflexão.**
1. `idx_scan = 0` prova que um índice é inútil? Que armadilhas existem (reset de estatísticas, réplicas, relatório mensal)?
2. Quem mais "usa" um índice além dos `SELECT`s?
3. Como o custo de índices secundários difere no InnoDB (PK dentro do índice secundário, change buffer)?
4. Como você faria essa limpeza num banco de produção de verdade, sem janela de manutenção?

**Hints.**
1. O PostgreSQL mantém estatísticas de uso por índice, mas o período observado importa.
2. Um índice cujas colunas iniciais repetem as de outro raramente se paga.
3. Nem todo índice "sem uso" pode ser removido: alguns existem para garantir regras.

---

### T05 — Relatório de clientes: números errados (e lentos)

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-158 | 2 — Intermediário | Banco / SQL | SMALL (corretude) + MEDIUM (custo) |

**Cenário empresarial.** O relatório "Clientes e gasto total", usado pelo CRM e pelo financeiro, tem dois problemas. O gasto de alguns clientes aparece **dobrado** em relação ao sistema financeiro, e clientes que nunca compraram "sumiram" do relatório. O marketing precisa deles para campanhas de primeira compra.

**Sintoma.** `GET /api/admin/reports/customer-spend?segment=&from=&to=` retorna totais divergentes para parte dos clientes e omite outros. No MEDIUM, leva vários segundos.

**Informações disponíveis.**
- Três clientes âncora com os valores "oficiais" do financeiro (`make lab-info TASK=05`).
- O contrato do relatório: uma linha por cliente do segmento, com `orders_count`, `spent_cents` (pedidos pagos no período) e `last_order_at`.

**Objetivo.** Relatório correto pelo contrato e com custo razoável no MEDIUM.

**Conceitos envolvidos.** `JOIN` × `LEFT JOIN`; cardinalidade de joins (fan-out); agregar antes ou depois de juntar; `COUNT(*)` × `COUNT(col)` × `COUNT(DISTINCT ...)`; `GROUP BY`; `HAVING` × `WHERE`; filtro na cláusula `ON` × no `WHERE` com `LEFT JOIN`; CTEs e subqueries.

**Preparar.** `make lab-start TASK=05 DATASET=small` (e depois `DATASET=medium`)

**Endpoint / tabelas.** `GET /api/admin/reports/customer-spend` · `customers`, `addresses`, `orders`, `payments`

**Critérios de aceite.**
- **AC1** — GOLD no SMALL para três combinações de parâmetros.
- **AC2** — GOLD no MEDIUM para uma combinação.
- **AC3** — Clientes do segmento sem pedidos no período aparecem com `orders_count = 0` e `spent_cents = 0`.
- **AC4** — No MEDIUM, a requisição executa no máximo 2 queries e o BLK não passa de 100% do baseline (a corretude não pode custar mais).
- **AC5** — Existe um teste de feature do aluno que falharia com a versão original (o check roda os testes em `tests/Feature/Reports/` contra o baseline numa worktree temporária e espera falha).

**Medir o antes.** Compare os três clientes âncora com os valores do financeiro. Conte as linhas por cliente em cada etapa da query (antes do `GROUP BY`).

**Medir o depois.** `lab-check` e `lab-compare`.

**Testes automatizados possíveis.** Um cenário mínimo com factories: cliente com dois endereços, cliente sem pedidos, pedido com duas tentativas de pagamento. Esse é o teste exigido no AC5.

**Perguntas de reflexão.**
1. Por que o total dobrou para alguns clientes e não para outros?
2. Por que uma condição no `WHERE` "desfez" o `LEFT JOIN`?
3. Quando é melhor agregar numa subquery antes de juntar?
4. Como você validaria um relatório financeiro antes de mandá-lo para produção?

**Hints.**
1. Conte quantas linhas existem por cliente depois de cada `JOIN`, antes de agrupar.
2. Uma condição no `WHERE` pode transformar um `LEFT JOIN` em `INNER JOIN`.
3. Agregar antes de juntar muda a cardinalidade.

---

### T06 — Faturamento mensal por categoria varre 8 milhões de pedidos

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-173 | 3 — Pleno | Banco / PostgreSQL | MEDIUM (LARGE recomendado) |

**Cenário empresarial.** No fechamento do mês, o financeiro abre o painel "Faturamento por categoria". No LARGE, a consulta passa de 25 s e estoura o timeout do proxy. Além disso, o valor de maio não bate com o do ERP em alguns milhares de reais.

**Sintoma.** `GET /api/admin/reports/revenue-by-category?month=2026-05` lê praticamente as tabelas inteiras de pedidos e itens, qualquer que seja o mês, e diverge do ERP nos meses de referência.

**Informações disponíveis.**
- Valores oficiais do ERP para três meses de referência (`make lab-info TASK=06`).
- Regra de negócio: o mês é o do calendário de São Paulo e conta pedidos com pagamento confirmado (status `paid`, `picking`, `shipped`, `delivered`).

**Objetivo.** O relatório bate com o ERP e tem custo proporcional ao período consultado.

**Conceitos envolvidos.** Sargability com datas (funções sobre colunas; intervalos semiabertos); fuso horário e fronteiras de mês; índices compostos e de cobertura (`INCLUDE`, index-only scan, visibility map, `VACUUM`); estratégias de join (hash × nested loop); agregação; pré-agregação (materialized view, tabela de resumo) e o custo de atualizá-la.

**Preparar.** `make lab-start TASK=06`

**Endpoint / tabelas.** `GET /api/admin/reports/revenue-by-category` · `orders`, `order_items`, `products`, `categories`

**Critérios de aceite.**
- **AC1** — GOLD (valores do ERP) para os três meses de referência.
- **AC2** — ROWSREAD de um mês ≤ 10% do baseline.
- **AC3** — Custo proporcional ao período: ROWSREAD de 3 meses ≤ 3,5× ROWSREAD de 1 mês.
- **AC4** — Frescor: após `make lab-scenario TASK=06 STEP=new-sales` (insere vendas no mês corrente), o relatório reflete as vendas imediatamente, ou após o comando de atualização declarado no front matter das notas (`refresh_command:`). O check executa esse comando se ele existir.
- **AC5** — As notas descrevem a estratégia escolhida e o frescor garantido (seção "Frescor").

**Medir o antes.** `EXPLAIN (ANALYZE, BUFFERS)` para um mês e para três meses. Compare com os valores do ERP.

**Medir o depois.** Os mesmos planos. `lab-compare`.

**Testes automatizados possíveis.** Teste de feature com pedidos nas bordas do mês (23h30 do último dia em São Paulo). Teste do comando de atualização, se houver.

**Perguntas de reflexão.**
1. Por que o valor divergia do ERP?
2. Se você pré-agregou: que dado pode ficar desatualizado, por quanto tempo, e quem precisa saber disso?
3. Quando um index-only scan não é "only" de verdade?
4. Como o MySQL trataria as funções de data no filtro?

**Hints.**
1. Leia o plano de baixo para cima: onde a maior parte das linhas é produzida e descartada?
2. Como o filtro de data está escrito? O índice consegue usar essa expressão? E qual fuso define "maio"?
3. Às vezes a melhor query é não recalcular o passado toda vez.

---

### T07 — Backoffice: página 40.000 leva 20s e itens se repetem

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-189 | 3 — Pleno | Banco / API | MEDIUM (+ SMALL para o teste de consistência) |

**Cenário empresarial.** A equipe de conciliação percorre todos os pedidos pelo backoffice, e o comando `orders:export` usa o mesmo endpoint para gerar um arquivo diário. As páginas profundas são muito lentas. Durante o dia, a exportação sai com pedidos **duplicados** e **faltando**.

**Sintoma.** `GET /api/admin/orders?page=N&per_page=50` fica mais lento quanto maior o `N` (a página 20.000 leva mais de 15 s no MEDIUM). Exportações feitas em horário comercial têm repetições e lacunas.

**Informações disponíveis.** O cliente da exportação (`orders:export`). Reclamação da conciliação com três exemplos de pedidos repetidos. O front-end só usa "próxima" e "anterior" (nunca pula para uma página específica).

**Objetivo.** Percorrer todos os pedidos com custo estável por página e resultado consistente, mesmo com pedidos entrando durante o percurso.

**Conceitos envolvidos.** Custo de `OFFSET`; paginação por keyset/cursor; ordenação total e desempate; índices para keyset; consistência sob inserções concorrentes; custo de `COUNT(*)`; contratos de API com cursor opaco; `cursorPaginate` do Laravel.

**Preparar.** `make lab-start TASK=07`

**Endpoint / comando / tabela.** `GET /api/admin/orders` · `orders:export` · `orders`

**Critérios de aceite.**
- **AC1** — BLK da página na posição âncora profunda (~90% do conjunto) ≤ 3× o BLK da primeira página.
- **AC2** — Consistência (harness, SMALL): percorrer o conjunto inteiro enquanto o harness insere pedidos entre as páginas gera 0 repetidos e 0 ausentes (entre os pedidos que já existiam no início).
- **AC3** — O contrato de paginação está documentado em `docs/tasks/07-deep-pagination/contract.md` (o template é fornecido e o aluno preenche), e a resposta segue esse contrato. O contrato declara como gerar um cursor para uma posição arbitrária (formato padrão do Laravel ou um comando indicado no template), para que o check chegue à posição profunda sem percorrer tudo. O `orders:export` foi adaptado.
- **AC4** — Nenhuma query da requisição lê a tabela `orders` inteira.

**Medir o antes.** `EXPLAIN (ANALYZE, BUFFERS)` da página 1 e da página profunda. Rode `make lab-race TASK=07 SCENARIO=insert-while-paging` e veja os repetidos.

**Medir o depois.** Os mesmos passos. `lab-compare`.

**Testes automatizados possíveis.** Teste de feature que percorre SMALL inteiro, inserindo registros entre as páginas.

**Perguntas de reflexão.**
1. O que o banco precisa fazer para "pular" N linhas?
2. O que o usuário perde com a paginação por cursor (ir para a página 500, total de páginas) e como o produto contorna isso?
3. Por que empates na ordenação causam repetições?
4. Como expor o total sem contar a tabela a cada requisição?

**Hints.**
1. Meça o custo da página 1 e o da página 20.000 com o mesmo `EXPLAIN`. O que cresce?
2. Em vez de dizer "pule N linhas", como dizer "continue de onde parei"?
3. Se dois registros empatam no critério de ordenação, qual vem primeiro?

---

### T08 — Campanha de reengajamento retorna zero clientes

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-203 | 3 — Pleno | Banco / SQL | SMALL (corretude) + MEDIUM (custo) |

**Cenário empresarial.** O marketing roda `campaigns:build-reengagement --days=180` para listar clientes ativos sem pedido nos últimos 180 dias. Ontem, o resultado veio **vazio**. Um dev escreveu uma versão alternativa (`--strategy=v2`) que dá números plausíveis, mas não termina no MEDIUM em menos de 20 minutos.

**Sintoma.** `--strategy=legacy` retorna 0 clientes. `--strategy=v2` é correta no SMALL, mas o custo cresce com clientes × pedidos.

**Informações disponíveis.** As duas estratégias no código. A contagem aproximada que o marketing espera (ordem de grandeza) no SMALL. O dataset tem compras de convidado.

**Objetivo.** Uma estratégia correta e eficiente, que vira a padrão do comando.

**Conceitos envolvidos.** `NOT IN` e `NULL` (lógica de três valores); `NOT EXISTS` e anti-join; `LEFT JOIN ... IS NULL`; subquery correlacionada; semi-join; planos (Hash Anti Join, SubPlan); diferenças do otimizador entre MySQL e PostgreSQL; índices de suporte.

**Preparar.** `make lab-start TASK=08`

**Comando / tabelas.** `campaigns:build-reengagement` · `customers`, `orders`

**Critérios de aceite.**
- **AC1** — GOLD no SMALL e no MEDIUM.
- **AC2** — Número de queries constante (≤ 3), independente do número de clientes.
- **AC3** — O custo não cresce com clientes × pedidos: BLK ≤ 20% do BLK da estratégia `v2` no MEDIUM, e o plano não executa um SubPlan por linha de `customers`.
- **AC4** — As notas explicam, com um exemplo mínimo em SQL, por que a estratégia `legacy` retornava vazio (seção "Causa").

**Medir o antes.** Rode as duas estratégias no SMALL e compare as contagens. `EXPLAIN` de cada uma.

**Medir o depois.** Os mesmos passos. `lab-compare`.

**Testes automatizados possíveis.** Teste com cliente com pedido recente, cliente sem pedido, cliente só com pedido antigo e pedido de convidado.

**Perguntas de reflexão.**
1. Como `x NOT IN (1, 2, NULL)` é avaliado?
2. Por que `v2` era correta mas inviável?
3. Das formas de escrever "não existe", quais o PostgreSQL e o MySQL otimizam da mesma maneira?
4. Como você evitaria esse tipo de bug em revisão de código?

**Hints.**
1. Rode a subquery sozinha e procure valores que você não esperava.
2. Como `x NOT IN (1, 2, NULL)` é avaliado em SQL?
3. Existem pelo menos três formas de escrever "não existe". Compare os planos.

---

### T09 — Catálogo legado no MySQL: ordenar por preço custa 2 milhões de linhas

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-221 | 3 — Pleno | Banco / **MySQL 8.4** | MEDIUM |

**Cenário empresarial.** O catálogo B2B de parceiros ainda roda num MySQL legado (conexão `legacy_mysql`, tabela `legacy_catalog_items`). A listagem por categoria ordenada por preço (e por "mais novos") está lenta. Um dev comenta: "no Postgres uma query dessas é instantânea, deve ser coisa do MySQL".

**Sintoma.** `GET /api/legacy-catalog/categories/{id}/products?sort=price&page=1` leva 2–6 s nas categorias grandes. `sort=newest` também é lento.

**Informações disponíveis.** O slow query log do MySQL. `performance_schema` ativo. A lista de índices atuais (descubra-a).

**Objetivo.** A listagem examina só as linhas que retorna, para os dois tipos de ordenação.

**Conceitos envolvidos.** `EXPLAIN`, `EXPLAIN FORMAT=TREE`, `EXPLAIN ANALYZE` no MySQL; `Using filesort`, `Using temporary`, `Using index`; índice composto para filtro + ordenação; índice de cobertura; clustered index do InnoDB (PK dentro dos índices secundários); `ROWS_EXAMINED` e `Handler_read_*`; deferred join; diferenças de planner e de index-only scan em relação ao PostgreSQL.

**Preparar.** `make lab-start TASK=09` (sobe o perfil `mysql` e carrega o schema `bp_t09`)

**Endpoint / tabela.** `GET /api/legacy-catalog/categories/{id}/products` · `legacy_catalog_items` (MySQL)

**Critérios de aceite.**
- **AC1** — ROWS examinadas ≤ 2% do baseline em três categorias (grande, média e pequena), para `sort=price` e `sort=newest`.
- **AC2** — O plano não ordena o conjunto inteiro da categoria (sem filesort sobre mais linhas que a página, conforme `EXPLAIN ANALYZE`).
- **AC3** — GOLD das páginas 1 e 5 nas três categorias.
- **AC4** — As notas comparam o comportamento com o PostgreSQL, rodando uma consulta equivalente no PG e usando os planos como evidência (seção "MySQL × PostgreSQL").

**Medir o antes.** `EXPLAIN ANALYZE` e `ROWS_EXAMINED` via `performance_schema`. `SHOW INDEX FROM legacy_catalog_items`.

**Medir o depois.** Os mesmos passos. `lab-compare`.

**Testes automatizados possíveis.** Teste de feature das duas ordenações com desempate estável.

**Perguntas de reflexão.**
1. O que o InnoDB carrega "de graça" em todo índice secundário, e como isso ajuda ou atrapalha?
2. O que muda se a página pedida for a 500?
3. Por que o comentário "no Postgres seria instantâneo" pode ser verdadeiro ou falso?
4. Que custo seus novos índices trazem para a sincronização noturna que atualiza preços?

**Hints.**
1. No `EXPLAIN` do MySQL, a coluna `Extra` conta boa parte da história.
2. Um índice pode servir ao filtro e à ordenação ao mesmo tempo, se as colunas estiverem na ordem certa.
3. Em InnoDB, o que um índice secundário carrega além das próprias colunas?

---

### T10 — Widget "pedidos recentes" dispara 1.200 queries e 4 MB de JSON

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-240 | 2 — Intermediário | Laravel / Eloquent | MEDIUM |

**Cenário empresarial.** O dashboard do backoffice tem um widget "últimos pedidos", com cliente, itens, produto de cada item, pagamento e último status. Ele é aberto por 150 pessoas de manhã e leva vários segundos. O front-end só usa uma fração dos campos devolvidos.

**Sintoma.** `GET /api/admin/orders/recent?limit=50` executa mais de 1.000 queries e devolve cerca de 4 MB de JSON. Com `limit=200`, fica muito pior.

**Informações disponíveis.** O contrato do front-end (`lab/tasks/10/contract.schema.json`: campos efetivamente usados). O header `X-Lab-Queries`. Laravel Debugbar/Telescope **não** instalados. Use as ferramentas do lab ou `DB::listen`.

**Objetivo.** O widget faz trabalho constante por requisição e devolve só o que o contrato pede.

**Conceitos envolvidos.** N+1; eager loading (`with`, aninhado e com restrições); prevenção de lazy loading (`Model::preventLazyLoading`, `shouldBeStrict`); over-fetching (colunas, `$appends`, `$with` padrão, accessors); API Resources e `whenLoaded`; `withCount` e `withSum`; custo de serialização.

**Preparar.** `make lab-start TASK=10`

**Endpoint / modelos.** `GET /api/admin/orders/recent` · `Order`, `Customer`, `OrderItem`, `ProductVariant`, `Product`, `Payment`, `OrderStatusHistory`

**Critérios de aceite.**
- **AC1** — QPR constante e ≤ 8 para `limit` = 10, 50 e 200.
- **AC2** — Payload ≤ 25% do baseline para `limit=50`.
- **AC3** — A resposta valida contra o contrato e é igual ao GOLD nos campos do contrato.
- **AC4** — Em `local` e `testing`, lazy loading acidental gera erro (o check executa um acesso lazy sintético e espera uma exceção). Em `production`, não.

**Medir o antes.** Contagem de queries por tipo (agrupe o SQL capturado por "forma"). Tamanho da resposta.

**Medir o depois.** Os mesmos números. `LOAD=10` informativo.

**Testes automatizados possíveis.** Teste que trava o número de queries (`DB::enableQueryLog` / contador) para `limit=10` e `limit=200`. Teste de contrato com JSON Schema.

**Perguntas de reflexão.**
1. De onde vinham as queries que não estavam visíveis no controller?
2. Qual o custo de carregar colunas grandes (`description`, `payload`) que ninguém usa?
3. Quando `withCount` é melhor que carregar a relação e contar em PHP, e quando é pior?
4. O que muda quando o limite vem do usuário?

**Hints.**
1. Agrupe as queries capturadas pela forma do SQL. Quais se repetem com IDs diferentes?
2. Compare os campos que o front-end usa (contrato) com os que a API devolve.
3. Relacionamentos podem ser carregados implicitamente a partir de lugares inesperados: accessors, `$appends`, Resources.

---

### T11 — Catálogo com filtro "em estoque" e ordenação por avaliação leva 5 s

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-252 | 3 — Pleno | Laravel / Eloquent + SQL | MEDIUM |

**Cenário empresarial.** A vitrine permite filtrar "somente com estoque" e ordenar por "mais bem avaliados", mostrando a contagem de avaliações de cada produto. Desde o lançamento dessa combinação, a vitrine de categorias grandes demora 5 s. O código Eloquent "parece limpo".

**Sintoma.** `GET /api/catalog/products?category=12&in_stock=1&sort=rating&page=1` executa poucas queries, mas cada uma é muito cara.

**Informações disponíveis.** O controller e o scope Eloquent. O contrato de ordenação: por avaliação média (só avaliações aprovadas) decrescente e depois por `id` crescente. O `pg_stat_statements`.

**Objetivo.** A vitrine com filtro e ordenação tem custo proporcional à página, sem mudar a resposta.

**Conceitos envolvidos.** SQL gerado pelo Eloquent (`toSql`, `toRawSql`, `DB::listen`); `whereHas` e `EXISTS` correlacionado; `withCount`/`withAvg` como subselects; `JOIN` × `EXISTS`; ordenação por valor calculado; desnormalização controlada e consistência; índices para subconsultas; **otimização do SQL × otimização do código Eloquent**.

**Preparar.** `make lab-start TASK=11`

**Endpoint / tabelas.** `GET /api/catalog/products` · `products`, `product_variants`, `inventory`, `product_reviews`

**Critérios de aceite.**
- **AC1** — QPR ≤ 3.
- **AC2** — BLK ≤ 10% do baseline em três categorias (grande, média e pequena).
- **AC3** — GOLD das páginas 1–3 nas três categorias (ordem incluída).
- **AC4** — Consistência: depois do cenário `make lab-scenario TASK=11 STEP=review-activity` (cria, aprova, rejeita e remove avaliações e zera o estoque de alguns produtos), a resposta continua igual ao GOLD recalculado para o novo estado.

**Medir o antes.** Imprima o SQL gerado e rode `EXPLAIN (ANALYZE, BUFFERS)` direto nele. Identifique qual parte domina o custo.

**Medir o depois.** Os mesmos passos. `lab-compare`.

**Testes automatizados possíveis.** Teste de feature da ordenação com empates. Teste do cenário do AC4 em escala mínima.

**Perguntas de reflexão.**
1. O código Eloquent estava "errado"? Onde está a fronteira entre otimizar a query e otimizar o modelo de dados?
2. Se você desnormalizou algo: quais eventos precisam atualizar o valor, e o que acontece se um deles falhar?
3. Por que ordenar por um valor calculado obriga o banco a calcular o valor de todas as linhas?
4. Quando você trocaria `whereHas` por um join, e quando não?

**Hints.**
1. Imprima o SQL que o Eloquent gera e rode `EXPLAIN` diretamente nele.
2. Ordenar por um valor calculado por linha obriga o banco a calcular esse valor para todas as linhas antes de ordenar.
3. Quando um número é lido mil vezes e escrito uma vez, onde ele deveria morar?

---

### T12 — Recalcular o LTV dos clientes estoura a memória e pula clientes

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-266 | 3 — Pleno | Laravel / processamento de dados | MEDIUM |

**Cenário empresarial.** Toda noite, `customers:recalculate-ltv` atualiza `lifetime_value_cents` dos clientes marcados como desatualizados. No MEDIUM, a estratégia original morre com `Allowed memory size exhausted`. Um dev criou `--strategy=chunk`, que termina, mas o CRM mostra metade dos clientes com LTV antigo no dia seguinte.

**Sintoma.** `--strategy=all` estoura 512 MB. `--strategy=chunk` termina, mas deixa parte dos clientes elegíveis sem atualização. As duas fazem uma consulta por cliente.

**Informações disponíveis.** As duas estratégias. A regra de LTV: soma de `total_cents` de pedidos pagos menos reembolsos, por cliente. A regra de elegibilidade: clientes com pedido novo desde `ltv_calculated_at` (ou nunca calculados).

**Objetivo.** O recálculo noturno é correto, tem memória limitada e custo linear, sem uma query por cliente.

**Conceitos envolvidos.** `get`/`all` × `chunk` × `chunkById` × `lazy` × `lazyById` × `cursor`; paginar um conjunto que você mesmo modifica; memória (hidratação de modelos, query log, eventos de modelo); PDO bufferizado × não bufferizado; update set-based (`UPDATE ... FROM (SELECT ... GROUP BY)`) × por linha; escrita em lote; `memory_get_peak_usage`; idempotência de rotinas noturnas.

**Preparar.** `make lab-start TASK=12`

**Comando / tabelas.** `customers:recalculate-ltv` · `customers`, `orders`, `payments`

**Critérios de aceite.**
- **AC1** — GOLD: LTV e `ltv_calculated_at` corretos para 100% dos clientes elegíveis. Clientes não elegíveis não são tocados.
- **AC2** — Pico de memória do processo ≤ 64 MB no MEDIUM.
- **AC3** — QPR ≤ 3 queries por 1.000 clientes elegíveis (o custo não cresce com um termo por cliente).
- **AC4** — Idempotência: uma segunda execução imediata altera 0 linhas.
- **AC5** — Rodar a execução duas vezes em paralelo (harness) não gera erro nem resultado divergente.

**Medir o antes.** Rode as duas estratégias com `--memory-report` (flag do lab que imprime a memória por etapa). Conte os elegíveis antes e depois de cada execução.

**Medir o depois.** Os mesmos passos. `lab-compare`.

**Testes automatizados possíveis.** Teste com cerca de 3 lotes de clientes elegíveis, verificando que nenhum é pulado. Teste de idempotência.

**Perguntas de reflexão.**
1. Por que `chunk()` pulou clientes?
2. Quando `cursor()` resolve a memória e quando não resolve?
3. O que você ganha e perde ao mover o cálculo para uma única instrução SQL (observabilidade, eventos de modelo, locks)?
4. Como fazer esse processo retomar do ponto onde parou se o servidor reiniciar no meio?

**Hints.**
1. Meça a memória por etapa: carregar, processar e salvar.
2. Paginar com `OFFSET` uma consulta cujo filtro você altera dentro do loop tem um efeito colateral.
3. O banco é muito bom em agregar. O PHP não precisa ver cada pedido.

---

### T13 — Checkout leva 4 s e às vezes falha depois de autorizar o pagamento

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-281 | 3 — Pleno | Laravel / síncrono × assíncrono | SMALL |

**Cenário empresarial.** O `POST /api/checkout` cria o pedido, reserva estoque, autoriza o pagamento no gateway, envia o e-mail de confirmação, gera a nota em PDF, exporta para o ERP e recalcula recomendações, tudo na mesma requisição. Quando o ERP oscila, o cliente vê erro **depois** de o pagamento ter sido autorizado, e tenta comprar de novo.

**Sintoma.** p95 do checkout ~4 s. Quando o ERP retorna 500 ou demora, o checkout falha e o pedido é desfeito, mas a autorização fica no gateway. Às vezes o e-mail de confirmação é enviado para um pedido que não existe (rollback).

**Informações disponíveis.** O controller e os serviços do checkout. `docs/partners/erp.md` e `docs/partners/gateway.md`. O ledger do mock (`make lab-info TASK=13` mostra como consultar por correlation id).

**Checkpoints do lab (não remover):** `checkout.place.1` a `checkout.place.6`.

**Objetivo.** O checkout responde assim que o que o cliente precisa saber está garantido. Os efeitos secundários acontecem exatamente uma vez, só para pedidos confirmados, e sobrevivem a falhas dos parceiros.

**Conceitos envolvidos.** Caminho crítico; trabalho síncrono × assíncrono; jobs e dispatch; dispatch dentro de transação (`afterCommit`); transactional outbox (conceito); fronteiras de serviço; transações longas e locks; consistência eventual e estados intermediários na UX.

**Preparar.** `make lab-start TASK=13 PROFILES=queue`

**Endpoint / serviços.** `POST /api/checkout` · `App\Services\Checkout\*` · parceiros gateway e ERP

**Critérios de aceite.**
- **AC1** — Durante a requisição de checkout, EXT ≤ 1 (só a autorização no gateway), pelo ledger e por correlation id.
- **AC2** — Após `make lab-drain TASK=13`, e-mail, ERP e recomendações acontecem **exatamente uma vez** para cada checkout bem-sucedido do cenário.
- **AC3** — Checkout que falha e desfaz a transação (harness injeta `throw` no checkpoint 5) não produz nenhum efeito assíncrono.
- **AC4** — Com o ERP fora (`down` por toda a primeira fase), todos os checkouts do cenário concluem com sucesso, e as exportações completam depois que o ERP volta, após o drain.
- **AC5** — Nenhuma chamada HTTP externa acontece com uma transação de banco aberta (o probe registra violações; deve ser 0).

**Medir o antes.** `make lab-race TASK=13 SCENARIO=erp-down` e o ledger por correlation id. Latência informativa com `LOAD=10`.

**Medir o depois.** Os mesmos cenários. `lab-check`.

**Testes automatizados possíveis.** `Queue::fake()` / `Bus::fake()` com asserts de dispatch após commit. Teste de rollback sem efeitos. `Http::fake()` para ERP indisponível.

**Perguntas de reflexão.**
1. O que o cliente precisa saber antes da resposta, e o que pode acontecer depois?
2. Por que um job disparado dentro de uma transação é perigoso?
3. O que é um estado intermediário honesto para o cliente ("pedido recebido, confirmação por e-mail em instantes")?
4. O que acontece com a autorização do gateway se o pedido não for criado? Quem desfaz?

**Hints.**
1. Liste tudo o que acontece na requisição e marque o que o cliente precisa ver antes da resposta.
2. Um job disparado dentro de uma transação pode rodar antes do commit, ou mesmo se ela fizer rollback.
3. Transação aberta + chamada de rede = locks segurados pelo tempo da rede.

---

### T14 — Página de produto: 14 queries na página mais acessada (Black Friday chegando)

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-302 | 2 — Intermediário | Redis / cache | MEDIUM |

**Cenário empresarial.** A página de produto recebe 70% do tráfego. Para a Black Friday, a previsão é de 10× o volume atual. Cada visualização faz 14 queries, e produtos "quentes" são vistos milhares de vezes por minuto.

**Sintoma.** `GET /api/catalog/products/{slug}` executa 14 queries por requisição. Não há cache.

**Informações disponíveis.** O endpoint e o Resource. O contrato da API: o preço pode ser exibido em BRL ou USD via `?currency=`. A distribuição de acessos (Zipf) no script k6 da task. A frequência de mudança de cada dado: descrição e atributos mudam raramente, preço algumas vezes por dia, estoque a cada venda.

**Objetivo.** Absorver o tráfego de leitura da página de produto com cache, sem servir dado errado.

**Conceitos envolvidos.** Key/value; `Cache::remember`; TTL; desenho de chaves (identidade do conteúdo, versão, variações); hit/miss e hit ratio; tamanho e serialização dos valores; o que cachear e o que não cachear; `redis-cli --bigkeys`, `MEMORY USAGE`, `INFO stats`.

**Preparar.** `make lab-start TASK=14`

**Endpoint.** `GET /api/catalog/products/{slug}`

**Critérios de aceite.**
- **AC1** — Com cache quente, QPR ≤ 2 para os produtos âncora.
- **AC2** — No cenário k6 da task (`LOAD=100`, orçamento fixo, distribuição Zipf), hit ratio ≥ 90% (contado pelos eventos de cache do lab).
- **AC3** — Resposta igual ao GOLD com cache frio e com cache quente.
- **AC4** — Nenhum valor em cache passa de 64 KB (`MEMORY USAGE` das chaves criadas no cenário).
- **AC5** — As notas documentam a convenção de chaves e o TTL escolhido para cada dado, com a justificativa (seção "Chaves e TTL").

**Medir o antes.** QPR por requisição. `LOAD=100` informativo (p95 e RPS no modo bench).

**Medir o depois.** Hit ratio, QPR com cache quente, tamanho das chaves. `lab-compare`.

**Testes automatizados possíveis.** Teste de hit/miss com o store `array`. Teste de que a resposta não muda com o cache quente.

**Perguntas de reflexão.**
1. Que dados dessa página você **não** colocaria no mesmo cache, e por quê?
2. O que acontece com a memória do Redis se a chave incluir algo com alta cardinalidade?
3. Hit ratio alto garante página rápida?
4. Onde mais você poderia cachear (HTTP, CDN, OPcache) e com que limites?

**Hints.**
1. Separe o que muda raramente do que muda a cada venda.
2. Uma chave precisa identificar unicamente o conteúdo. O que, além do slug, muda a resposta?
3. Meça hit e miss antes de comemorar.

---

### T15 — Preço antigo por 1 hora após promoção; "disponível" que não existe

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-317 | 3 — Pleno | Redis / cache | SMALL |

**Cenário empresarial.** A página de produto foi cacheada para a Black Friday (versão do baseline desta task). Agora o comercial reclama: ao iniciar uma promoção, o preço antigo aparece por até 1 hora. E clientes veem "disponível", adicionam ao carrinho e recebem "sem estoque" no checkout.

**Sintoma.** Depois de `PATCH /api/admin/variants/{id}/price`, o `GET /api/catalog/products/{slug}` continua mostrando o preço anterior. `GET /api/catalog/variants/{sku}/availability` mostra estoque de minutos atrás.

**Informações disponíveis.** A camada de cache do produto e da disponibilidade. As regras de negócio: preço deve refletir imediatamente; a disponibilidade exibida pode ter até 30 s de atraso, mas o checkout nunca pode aceitar item sem estoque.

**Checkpoints do lab (não remover):** `catalog.product.load.1` a `catalog.product.load.3`.

**Objetivo.** Cache que respeita as regras de frescor de cada dado, inclusive sob concorrência entre leitura e escrita.

**Conceitos envolvidos.** Invalidação (explícita, por evento, versionamento de chave, tags e seus limites no Redis); dado desatualizado e janela aceitável; cache-aside × write-through; corrida entre invalidação e recomputação; quando **não** usar cache; consistência × performance.

**Preparar.** `make lab-start TASK=15 DATASET=small`

**Endpoints.** `PATCH /api/admin/variants/{id}/price` · `GET /api/catalog/products/{slug}` · `GET /api/catalog/variants/{sku}/availability` · `POST /api/checkout`

**Critérios de aceite.**
- **AC1** — Depois de alterar o preço pela API, a próxima leitura do produto retorna o novo preço (0 leituras desatualizadas nos 20 produtos do cenário).
- **AC2** — Corrida (harness): uma leitura com cache frio é pausada depois de ler o banco e antes de gravar no cache. Uma alteração de preço acontece nesse meio, e a leitura é liberada. Ao fim, o cache não contém o preço antigo.
- **AC3** — Com o estoque zerado entre a exibição e o checkout, o checkout nunca aceita o item (0 aceites indevidos em 50 tentativas do cenário).
- **AC4** — O cache continua útil: hit ratio ≥ 85% no cenário k6 da T14 adaptado (`make lab-benchmark TASK=15 LOAD=100`).
- **AC5** — A disponibilidade exibida nunca tem mais de 30 s de atraso (o harness avança o relógio do lab e verifica).

**Medir o antes.** `make lab-race TASK=15 SCENARIO=price-update-during-recompute`. Altere um preço e leia o produto.

**Medir o depois.** Os mesmos cenários. `lab-check`.

**Testes automatizados possíveis.** Teste de invalidação ao alterar o preço. Teste do checkout com estoque zerado depois de uma leitura cacheada.

**Perguntas de reflexão.**
1. Apagar a chave basta? Por quê?
2. Que dados você decidiu **não** cachear, e qual foi o critério?
3. Quais são as vantagens e os riscos de cache tags no Redis?
4. Como avisar outros serviços (marketplace, app) que um preço mudou?

**Hints.**
1. Quem altera o dado sabe que ele mudou. O cache sabe?
2. Apagar a chave não basta se alguém estiver no meio de uma recomputação com o dado antigo.
3. Nem todo dado lido com frequência é bom candidato a cache.

---

### T16 — Meia-noite: o cache da home expira e o banco vai a 100%

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-333 | 4 — Pleno+ | Redis / cache / locks | MEDIUM |

**Cenário empresarial.** A home mostra "mais vendidos dos últimos 7 dias", uma agregação cara (~2 s no MEDIUM). Ela é cacheada por 5 minutos. Em campanhas, quando a chave expira, centenas de requisições recalculam ao mesmo tempo. O banco satura, a home cai e, com ela, o checkout.

**Sintoma.** Picos de CPU no banco a cada expiração. Em `LOAD=300`, a taxa de erro dispara no minuto da expiração.

**Informações disponíveis.** O código da home. Os gráficos de CPU do banco (Grafana, perfil `obs`). O requisito de produto: a home pode mostrar dados com até 10 minutos de atraso, mas nunca pode ficar fora do ar.

**Checkpoints do lab (não remover):** `storefront.home.1` a `storefront.home.4`.

**Objetivo.** Quando o dado expira, a recomputação acontece uma vez e ninguém fica sem resposta.

**Conceitos envolvidos.** Cache stampede (dogpile); locks distribuídos (`Cache::lock`, `SET NX PX`, dono do lock, TTL do lock, liberação segura); stale-while-revalidate (`Cache::flexible`); expiração antecipada probabilística; jitter de TTL; pre-warming por job; degradação graciosa.

**Preparar.** `make lab-start TASK=16`

**Endpoint.** `GET /api/storefront/home`

**Critérios de aceite.**
- **AC1** — Harness com a chave expirada e 200 requisições simultâneas (a recomputação é pausada até todas chegarem): a agregação cara executa **no máximo 1 vez** (contador de recomputações).
- **AC2** — Nenhuma das 200 requisições retorna erro. Todas recebem conteúdo, novo ou anterior.
- **AC3** — Se o processo que recomputa morrer no meio (política `crash`), outra requisição assume a recomputação depois do prazo do lock, sem ninguém esperar indefinidamente. A home continua respondendo.
- **AC4** — A idade do conteúdo servido (header `X-Content-Age`, exigido pelo contrato) nunca passa de 10 minutos no cenário com avanço de relógio.
- **AC5** — Primeira requisição com cache totalmente vazio (cold start): também no máximo 1 recomputação.

**Medir o antes.** `make lab-race TASK=16 SCENARIO=expiry-200` e o contador de recomputações. `LOAD=300` informativo com `obs`.

**Medir o depois.** Os mesmos cenários. `lab-compare`.

**Testes automatizados possíveis.** Teste do lock com store Redis de teste. Teste de fallback ao conteúdo anterior.

**Perguntas de reflexão.**
1. O que acontece com quem não pegou o lock: espera, recebe o antigo ou recebe erro? Qual a escolha certa aqui?
2. Como escolher o TTL do lock?
3. Jitter resolve stampede? Em que casos sim e em que casos não?
4. Por que um job de aquecimento pode não bastar?

**Hints.**
1. Quantas vezes a função cara executa quando a chave expira sob carga? Conte.
2. Só um precisa recalcular. Os outros precisam de uma estratégia enquanto esperam.
3. Um lock sem prazo e um processo que morre formam um problema novo.

---

### T17 — Um bot testando cupons e um cliente derrubando a busca

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-348 | 3 — Pleno | Redis / rate limiting / segurança | SMALL |

**Cenário empresarial.** A segurança detectou um bot testando milhares de códigos de cupom por minuto em `POST /api/coupons/validate`. Existe um limitador "caseiro", mas o bot passa por ele. Além disso, um integrador faz buscas em rajada em `GET /api/catalog/search` e degrada a busca para todos.

**Sintoma.** O limitador atual deixa passar muito mais que o limite configurado sob requisições paralelas, e é contornado trocando um header. Um único cliente consome a capacidade da busca.

**Informações disponíveis.** O limitador atual (middleware do projeto). A topologia: em `bench`, as requisições chegam pelo Nginx. As políticas de produto: validação de cupom limitada a 10/min por cliente autenticado e 30/min por IP real; busca limitada a 60/min por token.

**Objetivo.** Limites corretos, atômicos, impossíveis de contornar pelo cliente e isolados por consumidor.

**Conceitos envolvidos.** Rate limiting (janela fixa, janela deslizante, token bucket); `RateLimiter` e middleware `throttle` do Laravel; escolha da chave (IP, usuário, token, combinação); proxies confiáveis e `X-Forwarded-For`; atomicidade (`INCR` + `EXPIRE`, Lua); `429` com `Retry-After` e `X-RateLimit-*`; brute force.

**Preparar.** `make lab-start TASK=17 PROFILES=bench`

**Endpoints.** `POST /api/coupons/validate` · `GET /api/catalog/search`

**Critérios de aceite.**
- **AC1** — 100 validações simultâneas do mesmo cliente com limite de 10/min resultam em exatamente 10 processadas e 90 com `429`.
- **AC2** — Variar `X-Forwarded-For` nas requisições do cliente não contorna o limite por IP (o IP real vem só do proxy confiável).
- **AC3** — Toda resposta `429` tem `Retry-After` coerente com a janela.
- **AC4** — Isolamento: enquanto um token abusivo é limitado, 20 buscas de outro token são atendidas sem `429`.
- **AC5** — Tentativas com cupom inexistente consomem o limite exatamente como tentativas com cupom válido (o bot não ganha tentativas "grátis" errando).

**Medir o antes.** `make lab-race TASK=17 SCENARIO=parallel-100` e `SCENARIO=spoofed-ip`.

**Medir o depois.** Os mesmos cenários. `lab-check`.

**Testes automatizados possíveis.** Teste de feature com `RateLimiter::for`. Teste com header forjado. Teste de isolamento por token.

**Perguntas de reflexão.**
1. Por que ler, somar e gravar no Redis não é atômico?
2. Quem controla o "IP" que sua aplicação enxerga?
3. Qual limite faz sentido para usuário anônimo × autenticado × parceiro?
4. Rate limit resolve brute force de cupom sozinho? O que mais você faria?

**Hints.**
1. Ler e depois escrever numa chave compartilhada é uma corrida.
2. De onde vem o "IP" que o limitador usa, e quem controla esse valor?
3. O Redis tem operações atômicas para contar.

---

### T18 — Fila de sincronização com o ERP acumulou 120 mil mensagens

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-360 | 3 — Pleno | Filas / Horizon | MEDIUM (backlog de 120 mil) · SMALL (12 mil, para iterar) |

**Cenário empresarial.** Depois de uma indisponibilidade do ERP no fim de semana, a fila acumulou 120 mil exportações de pedidos. As capturas de pagamento usam a mesma fila, e clientes estão esperando **horas** pela confirmação do pagamento. O time sugere "subir 20 workers".

**Sintoma.** A fila `default` tem 120 mil jobs `ExportOrderToErp` na frente dos jobs de pagamento. Cada exportação é lenta. Há um único worker configurado.

**Informações disponíveis.** O Horizon (perfil `queue`) com tempos de espera por fila. `docs/partners/erp.md`. O job de exportação. O limite de conexões do banco (200).

**Objetivo.** Pagamentos voltam a ser confirmados em tempo, e o backlog é drenado com custo razoável e sem exportações duplicadas.

**Conceitos envolvidos.** Backlog; throughput × latência de fila; prioridade por filas; Horizon (supervisores, balanceamento, métricas de espera); escalar workers e seus limites (conexões, rate limit do parceiro); jobs em lote (`Bus::batch`, jobs que processam N itens); custo por job; idempotência no reprocessamento.

**Preparar.** `make lab-start TASK=18 PROFILES=queue` (o cenário enfileira o backlog e, depois, jobs de pagamento)

**Jobs / comando.** `Erp\ExportOrderToErp` · `Payments\CapturePayment` (versão simplificada nesta task) · `erp:enqueue-backlog`

**Critérios de aceite.**
- **AC1** — Com o backlog presente, um job de pagamento enfileirado depois dele é processado antes de, no máximo, 100 jobs de ERP (pela ordem de processamento registrada).
- **AC2** — Drenar o backlog SMALL gera ≤ 0,05 chamada externa por pedido exportado (ledger).
- **AC3** — QPR ≤ 2 queries por pedido exportado.
- **AC4** — Cada pedido do backlog tem **exatamente uma criação efetiva** no ERP (o ERP registra criações efetivas; tentativas repetidas que ele recusa não contam, mas não podem virar falha permanente), com `erp_exports` coerente, inclusive reiniciando os workers no meio (`make lab-race TASK=18 SCENARIO=restart-mid-drain`).
- **AC5** — A configuração de supervisores/filas está versionada (`config/horizon.php`) e explicada nas notas.

**Medir o antes.** Horizon: tempo de espera por fila. Ledger: chamadas por pedido. QPR de um job.

**Medir o depois.** `make lab-drain TASK=18` (throughput informativo), ordem de processamento, ledger. `lab-compare`.

**Testes automatizados possíveis.** Teste do job de exportação com `Http::fake` (número de chamadas por lote). Teste de idempotência reexecutando o mesmo lote.

**Perguntas de reflexão.**
1. Por que "subir 20 workers" poderia piorar as coisas?
2. Como garantir que uma fila nunca atrase outra mais importante?
3. Qual o tamanho de lote ideal e o que acontece quando um item do lote falha?
4. Como o backlog deveria ter sido evitado desde o início?

**Hints.**
1. Meça o custo de um job (queries e chamadas externas) e multiplique por 120 mil.
2. Filas diferentes permitem prioridades diferentes. Um worker pode consumir várias em ordem.
3. O ERP aceita mais de um pedido por chamada? Leia a documentação do parceiro.

---

### T19 — Captura de pagamento: cobranças duplicadas após retries e pedidos presos em "processing"

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-377 | 4 — Pleno+ | Filas / jobs / retries | SMALL |

**Cenário empresarial.** O job `CapturePayment` captura pagamentos autorizados. Em dias de instabilidade do gateway, o financeiro encontra **capturas duplicadas** (o cliente é cobrado duas vezes), pagamentos presos em `processing` para sempre e milhares de tentativas por minuto contra o gateway.

**Sintoma.** Com o gateway lento, o mesmo pagamento é capturado duas vezes. Com o gateway instável, o job martela o parceiro. Com o gateway recusando, o job tenta de novo o que nunca vai funcionar. Falhas definitivas ficam em `processing`.

**Informações disponíveis.** O job, `config/queue.php`, a configuração do worker/Horizon, `docs/partners/gateway.md` e a tabela `failed_jobs`. **Tempos escalados no lab:** os cenários usam segundos em vez de minutos, com margens de no mínimo 3×.

**Objetivo.** Cada pagamento é capturado no máximo uma vez, as tentativas respeitam o parceiro e toda falha termina num estado definitivo e visível.

**Conceitos envolvidos.** `tries`, `attempts`, `backoff` (fixo, exponencial, jitter); timeout do job × `retry_after` da conexão × timeout do cliente HTTP (hierarquia de timeouts); `failed()`, `failed_jobs`, `queue:retry`; `maxExceptions`; `release` × `fail`; erros transitórios × permanentes; idempotency key com o gateway; estados terminais e compensação; entrega at-least-once.

**Preparar.** `make lab-start TASK=19 PROFILES=queue`

**Job / tabelas.** `Payments\CapturePayment` · `payments`, `payment_events`, `failed_jobs`

**Critérios de aceite.**
- **AC1** — Cenário `slow` (gateway responde depois do `retry_after` da conexão): cada pagamento recebe no máximo 1 captura **efetiva** no gateway (ledger, por pagamento).
- **AC2** — Cenário `flaky` (`500, 500, 200`): o pagamento termina `captured`, e os intervalos entre tentativas são crescentes (ledger).
- **AC3** — Cenário `declined` (`4xx` de negócio): nenhuma nova tentativa depois da primeira resposta definitiva. O pagamento termina `failed`, com motivo e evento registrados.
- **AC4** — Cenário `timeout`: depois que as tentativas se esgotam, nenhum pagamento fica em `processing`. O estado é terminal e há registro em `failed_jobs` ou num evento equivalente.
- **AC5** — As notas trazem a tabela da hierarquia de timeouts, com os valores escolhidos e a justificativa (seção "Timeouts").

**Medir o antes.** `make lab-race TASK=19 SCENARIO=slow` (e `flaky`, `declined`, `timeout`). Ledger por pagamento. `failed_jobs`.

**Medir o depois.** Os mesmos cenários. `lab-check`.

**Testes automatizados possíveis.** Testes unitários do job com `Http::fake` sequenciado. Teste de `failed()`. Teste de backoff (`$job->backoff()`).

**Perguntas de reflexão.**
1. Desenhe a linha do tempo de um job lento e mostre onde a duplicação nasce.
2. Quais erros merecem nova tentativa?
3. Se a mesma captura chegar duas vezes ao gateway, como ele pode reconhecer a repetição?
4. Quem acompanha os `failed_jobs`, e como?

**Hints.**
1. Desenhe numa linha do tempo o início do job, o timeout HTTP, o timeout do job e o `retry_after` da conexão. O que acontece quando uma linha cruza a outra?
2. Nem todo erro merece nova tentativa.
3. Se a mesma captura chegar duas vezes ao gateway, como ele saberia que é repetição?

---

### T20 — O worker morreu no deploy: pedidos pagos sem baixa de estoque ou com baixa dupla

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-392 | 4 — Pleno+ | Filas / falhas parciais | SMALL |

**Cenário empresarial.** Depois de um deploy, com os workers reiniciados no meio do expediente, a logística encontrou pedidos pagos sem baixa de estoque, pedidos com baixa **dupla** e clientes que receberam duas vezes o aviso "separação iniciada".

**Sintoma.** O job `FulfillPaidOrder` executa vários passos: atualiza o status, consome reservas e baixa o estoque, grava o histórico, dispara a exportação para o ERP e notifica o cliente pelo parceiro de notificações do mock. Se o processo morre entre passos, a reentrega do job produz estados inconsistentes.

**Informações disponíveis.** O job. A configuração do Horizon e do supervisor. O relato do deploy (os workers foram parados com `SIGKILL` depois de 10 s).

**Checkpoints do lab (não remover):** `fulfillment.run.1` a `fulfillment.run.6`.

**Objetivo.** O job pode morrer em qualquer ponto e ser reentregue quantas vezes for preciso: o resultado final é sempre o mesmo, e os efeitos externos não se repetem.

**Conceitos envolvidos.** Entrega at-least-once; reentrega; jobs idempotentes; transações e atomicidade; efeitos externos não transacionais (outbox, chaves de deduplicação); `SIGTERM` × `SIGKILL`; desligamento gracioso (`queue:restart`, `horizon:terminate`, `stopwaitsecs`); `retry_after`; estados intermediários.

**Preparar.** `make lab-start TASK=20 PROFILES=queue`

**Job / tabelas.** `Orders\FulfillPaidOrder` · `orders`, `inventory`, `inventory_reservations`, `order_status_history`

**Critérios de aceite.**
- **AC1** — Para cada um dos 6 pontos de crash do harness (`crash` em `fulfillment.run.N`), depois da reentrega: estoque baixado exatamente uma vez, status final correto e histórico sem duplicatas (INV).
- **AC2** — A notificação externa é enviada **no máximo uma vez** e **pelo menos uma vez** por pedido, depois do drain (ledger).
- **AC3** — `SIGTERM` durante o job (deploy normal, harness) não deixa efeitos parciais: o job conclui dentro do prazo de desligamento ou é devolvido sem ter alterado nada.
- **AC4** — As notas trazem a tabela "ponto de crash → o que já é permanente → como a reexecução se comporta" (seção "Crash matrix").

**Medir o antes.** `make lab-race TASK=20 SCENARIO=crash-matrix` e os invariantes impressos por ponto.

**Medir o depois.** O mesmo cenário. `lab-check`.

**Testes automatizados possíveis.** Teste que executa o job duas vezes seguidas e compara o estado. Teste com exceção injetada entre passos.

**Perguntas de reflexão.**
1. Para cada passo: se o processo morrer logo depois dele, o que já é permanente?
2. Por que "exactly once" é, na prática, "at-least-once + idempotência"?
3. Como o deploy deveria parar os workers?
4. Onde um outbox ajudaria, e o que ele custa?

**Hints.**
1. Para cada linha do job, pergunte: se o processo morrer logo depois dela, o que já é permanente?
2. A reexecução é certa. O job precisa reconhecer trabalho já feito.
3. O banco garante atomicidade entre passos que estão nele. Efeitos fora dele precisam de outra estratégia.

---

### T21 — Eventos para analytics (RabbitMQ + consumidor Python): perdas, duplicatas e fila travada

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-405 | 4 — Pleno+ | Mensageria / RabbitMQ / **Python** | SMALL |

**Cenário empresarial.** O time de dados consome eventos `order.paid` e `order.refunded`, publicados pela aplicação no RabbitMQ, com um consumidor em Python (`services/analytics-consumer`) que mantém `analytics_daily_sales`. Os números do dashboard de vendas divergem do financeiro: às vezes para menos (depois de reinícios do consumidor), às vezes para mais. Na semana passada, a fila parou de andar por horas até alguém apagar "uma mensagem estranha".

**Sintoma.** Totais divergentes depois de crashes do consumidor. Uma mensagem malformada trava o processamento. O consumidor usa muita memória quando a fila está cheia.

**Informações disponíveis.** O publisher em PHP (`app/Integrations/Events/`), o consumidor em Python, `docker/rabbitmq/definitions.json` e a UI de management (porta 15672). A regra: `analytics_daily_sales` deve bater com os pedidos pagos menos os reembolsados, por dia e canal.

**Checkpoints do lab (Python, não remover):** `consumer.handle.1` a `consumer.handle.3` (o consumidor lê as mesmas políticas do Redis).

**Objetivo.** O pipeline de eventos não perde nem duplica efeitos, isola mensagens venenosas e tem consumo de memória limitado. A escolha de tecnologia está justificada.

**Conceitos envolvidos.** AMQP (exchange, queue, binding, routing key); `ack`, `nack`, `reject` e `requeue`; prefetch (QoS); flag `redelivered`; dead-letter exchange/queue; mensagens venenosas; limite de entregas em quorum queues; publisher confirms; consumidor idempotente (deduplicação por id de evento); at-least-once; **Redis Queue × RabbitMQ**.

**Preparar.** `make lab-start TASK=21 PROFILES=rabbit`

**Componentes.** exchange `commerce.events` · fila `analytics.sales` · `services/analytics-consumer/` · `analytics_daily_sales`

**Critérios de aceite.**
- **AC1** — O cenário publica 5.000 eventos (SMALL) e mata o consumidor 3 vezes em pontos definidos (`crash` nos checkpoints). Depois que a fila esvazia, `analytics_daily_sales` é igual ao GOLD.
- **AC2** — As mensagens malformadas do cenário terminam numa fila de mensagens mortas inspecionável, com o motivo, e a fila principal esvazia.
- **AC3** — Nunca há mais de 50 mensagens não confirmadas simultaneamente por consumidor (API de management, amostrada durante o cenário).
- **AC4** — Publicação confiável: no cenário em que o broker recusa publicações por alguns segundos, nenhum evento é perdido silenciosamente (todo evento publicado ou pendente de reenvio está registrado, e o GOLD final bate).
- **AC5** — As notas contêm um ADR curto: Redis Queue × RabbitMQ para este caso de uso, com critérios (seção "ADR").

**Medir o antes.** `make lab-race TASK=21 SCENARIO=crash-and-poison` e a comparação do resultado com o GOLD. Mensagens `unacked` na UI.

**Medir o depois.** O mesmo cenário. `lab-check`.

**Testes automatizados possíveis.** `pytest` do consumidor com um broker de teste ou um canal simulado. Teste de idempotência reenviando o mesmo evento.

**Perguntas de reflexão.**
1. Em que momento o consumidor diz ao broker "pode apagar"? E o que acontece se ele morrer um instante antes, ou depois?
2. Por que a mensagem venenosa travava tudo?
3. Como o publisher sabe que o broker aceitou a mensagem?
4. O que o RabbitMQ oferece aqui que a fila Redis do Laravel não oferece, e vice-versa?

**Hints.**
1. Em que momento o consumidor diz ao broker "pode apagar"?
2. Uma mensagem que sempre falha precisa de um destino que não seja a frente da fila.
3. Se a mesma mensagem chegar duas vezes, o total dobra?

---

### T22 — Clientes recebendo duas confirmações do mesmo pagamento

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-418 | 3 — Pleno | Concorrência / idempotência | SMALL |

**Cenário empresarial.** O gateway reenvia webhooks quando não recebe `2xx` em 5 s e às vezes entrega o mesmo evento em paralelo. Clientes recebem duas confirmações do mesmo pagamento. O financeiro vê `payment_events` duplicados, e alguns pedidos "voltam" de `captured` para `authorized`.

**Sintoma.** Eventos duplicados processados duas vezes. E-mails duplicados. Regressão de status quando os eventos chegam fora de ordem. O handler demora a responder, o que provoca ainda mais reenvios.

**Informações disponíveis.** O handler de `POST /api/webhooks/gateway`. `docs/partners/gateway.md` (política de reenvio, formato do evento, `event_id`). O plano de controle do mock para emitir duplicatas e eventos fora de ordem.

**Checkpoints do lab (não remover):** `webhook.gateway.1` a `webhook.gateway.4`.

**Objetivo.** Cada evento do gateway produz efeito exatamente uma vez, o estado do pagamento nunca regride e o gateway recebe resposta rápida.

**Conceitos envolvidos.** Idempotência; check-then-insert; restrições `UNIQUE`; `INSERT ... ON CONFLICT DO NOTHING` / upsert; tratar violação de unicidade como resultado normal; janela de corrida; deduplicar dados históricos antes de criar a restrição; eventos fora de ordem (máquina de estados, transições monotônicas); responder `2xx` rápido e processar de forma assíncrona.

**Preparar.** `make lab-start TASK=22 PROFILES=queue`

**Endpoint / tabelas.** `POST /api/webhooks/gateway` · `webhook_events`, `payment_events`, `payments`, `orders`

**Critérios de aceite.**
- **AC1** — Corrida (harness): o mesmo evento é entregue 2× em paralelo, com pausa entre os checkpoints. Resultado: 1 registro, 1 processamento, 1 notificação (ledger).
- **AC2** — 20 entregas do mesmo evento (sequenciais e paralelas misturadas): mesmo resultado do AC1, e todas as respostas são `2xx`.
- **AC3** — Eventos fora de ordem (`captured` antes de `authorized`, `authorized` repetido depois de `captured`): o estado final é `captured` e nunca regride.
- **AC4** — A garantia de unicidade vale mesmo com um bug na aplicação: um `INSERT` direto de evento duplicado via SQL é rejeitado. Os duplicados históricos foram tratados sem perda de informação, com a decisão nas notas.
- **AC5** — A resposta do webhook não depende de chamadas externas: EXT = 0 durante a requisição.

**Medir o antes.** `make lab-race TASK=22 SCENARIO=parallel-duplicate` e `SCENARIO=out-of-order`. Ledger de notificações.

**Medir o depois.** Os mesmos cenários. `lab-check`.

**Testes automatizados possíveis.** Teste de feature com a mesma requisição duas vezes. Teste da máquina de estados com todas as permutações de dois eventos.

**Perguntas de reflexão.**
1. Entre o "já existe?" e o "insere", quem mais pode estar executando?
2. Por que a restrição no banco é necessária mesmo com o código "certo"?
3. Qual status responder para uma duplicata? Por quê?
4. O que fazer com um evento que chega para um pagamento que ainda não existe?

**Hints.**
1. Entre o "já existe?" e o "insere", quanto tempo passa, e quem mais pode estar ali?
2. A aplicação pode esquecer; o banco não esquece uma restrição.
3. Antes de criar a restrição, olhe o que os dados de 3 anos já contêm.

---

### T23 — Cupom com limite de 100 usos foi usado 137 vezes

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-431 | 4 — Pleno+ | Concorrência / transações / isolamento | SMALL |

**Cenário empresarial.** Uma influenciadora divulgou o cupom `LIVE100`, limitado a 100 usos e a 1 por cliente. Em 40 segundos, ele foi aplicado 137 vezes, e alguns clientes usaram duas vezes. O prejuízo foi para o marketing.

**Sintoma.** `used_count` diverge do número de resgates. Há mais resgates que o limite. Clientes com dois resgates do mesmo cupom.

**Informações disponíveis.** `POST /api/orders/{uuid}/apply-coupon` e o `CouponRedemptionService`. O cupom âncora do cenário (`make lab-info TASK=23`). O isolamento padrão da conexão.

**Checkpoints do lab (não remover):** `coupon.redeem.1` a `coupon.redeem.4`.

**Objetivo.** Os limites de uso são respeitados sob qualquer concorrência, e o cliente recebe uma resposta de negócio clara quando o cupom esgota.

**Conceitos envolvidos.** Lost update; read-modify-write; `UPDATE` atômico condicional (com verificação de linhas afetadas / `RETURNING`); `increment()` do Eloquent; `SELECT ... FOR UPDATE` (`lockForUpdate`); níveis de isolamento (READ COMMITTED, REPEATABLE READ, SERIALIZABLE) e falhas de serialização com retry; padrões do MySQL × PostgreSQL; `CHECK` e `UNIQUE` como garantias.

**Preparar.** `make lab-start TASK=23`

**Endpoint / tabelas.** `POST /api/orders/{uuid}/apply-coupon` · `coupons`, `coupon_redemptions`, `orders`

**Critérios de aceite.**
- **AC1** — Stress (harness, semente fixa): 300 aplicações concorrentes de 150 clientes num cupom com limite 100 resultam em exatamente 100 resgates e `used_count = 100 = count(coupon_redemptions)`.
- **AC2** — Nenhum cliente resgata o mesmo cupom duas vezes, nem com duas requisições simultâneas do mesmo cliente (corrida com checkpoints).
- **AC3** — As requisições recusadas recebem `409` ou `422` com código de erro de negócio (`coupon_exhausted`, `coupon_already_used`). **0 respostas `500`**.
- **AC4** — Se a solução usar um isolamento mais forte, as falhas de serialização são tratadas com retry limitado e continuam sem gerar `500`.
- **AC5** — As notas comparam pelo menos duas abordagens testadas, com resultados e custo (seção "Abordagens").

**Medir o antes.** `make lab-race TASK=23 SCENARIO=stress-300` e `SCENARIO=same-customer-twice`. Consulta dos invariantes.

**Medir o depois.** Os mesmos cenários. Latência informativa com `LOAD=100`.

**Testes automatizados possíveis.** Teste com processos paralelos (`pcntl_fork` ou o harness do lab) em escala pequena. Teste de resposta de negócio.

**Perguntas de reflexão.**
1. Dois processos leem `used_count = 99` ao mesmo tempo. O que cada um escreve?
2. Quais os custos do lock pessimista numa promoção de alta concorrência (hot row)?
3. O que o PostgreSQL faz em SERIALIZABLE quando detecta um conflito? E o MySQL em REPEATABLE READ?
4. Se o pedido for cancelado depois, como devolver o uso ao cupom sem criar nova corrida?

**Hints.**
1. Dois processos leem 99 ao mesmo tempo. O que cada um escreve?
2. O banco pode fazer a verificação e a alteração numa única operação.
3. Isolamento mais forte não é gratuito: o que o banco faz quando detecta conflito?

---

### T24 — Dois canais venderam o último item do estoque

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-446 | 4 — Pleno+ | Concorrência / locks | SMALL |

**Cenário empresarial.** O último tênis tamanho 42 foi vendido duas vezes: uma pelo site e outra pelo marketplace, com poucos milissegundos de diferença. Um pedido teve de ser cancelado e o marketplace aplicou uma penalidade. Existe um lock no Redis "para evitar isso", mas o problema continua.

**Sintoma.** `reserved` passa de `on_hand` em variantes disputadas. Reservas ativas somam mais do que o estoque. Ocorre tanto entre dois checkouts quanto entre checkout e importação do marketplace.

**Informações disponíveis.** O `InventoryReservationService` (usado pelo checkout) e o job `ImportMarketplaceOrder` (usa um lock Redis). A SKU âncora com uma unidade (`make lab-info TASK=24`). `docs/partners/marketplace.md` (como recusar um pedido sem estoque).

**Checkpoints do lab (não remover):** `inventory.reserve.1` a `inventory.reserve.4` e `marketplace.import.1` a `marketplace.import.4`.

**Objetivo.** É impossível reservar mais do que existe, qualquer que seja o caminho, e quem perde a disputa recebe um resultado de negócio.

**Conceitos envolvidos.** Lock pessimista (`FOR UPDATE`, `lockForUpdate`); update atômico condicional; `CHECK` como última linha de defesa; locks distribuídos (Redis `SET NX PX`, dono, expiração, fencing tokens); por que um lock distribuído não substitui a garantia no banco; `NOWAIT` e `SKIP LOCKED`; `lock_timeout`; contenção em linhas quentes.

**Preparar.** `make lab-start TASK=24 PROFILES=queue`

**Endpoint / job / tabelas.** `POST /api/checkout` · `Marketplace\ImportMarketplaceOrder` · `inventory`, `inventory_reservations`

**Critérios de aceite.**
- **AC1** — Harness com 4 intercalações definidas entre checkout (API) e importação (worker) disputando a última unidade: `reserved` nunca passa de `on_hand` e exatamente um vence. O checkout perdedor recebe `409` (`out_of_stock`). O pedido de marketplace perdedor é recusado no parceiro (ledger).
- **AC2** — Cenário "lock expira durante o trabalho": o detentor do lock Redis é pausado por mais que o TTL do lock. Não há reserva dupla.
- **AC3** — Stress (semente fixa): 500 reservas concorrentes em 20 SKUs quentes preservam os invariantes, com 0 respostas `500`.
- **AC4** — Garantia no banco: um `UPDATE` direto via SQL que tornaria `reserved > on_hand` é rejeitado.
- **AC5** — Nenhuma requisição espera indefinidamente por lock: existe um limite configurado e documentado, e o check o verifica por configuração e em um cenário de bloqueio prolongado.

**Medir o antes.** `make lab-race TASK=24 SCENARIO=last-item-two-channels` e `SCENARIO=redis-lock-expiry`. Consulta dos invariantes.

**Medir o depois.** Os mesmos cenários. `lab-check`.

**Testes automatizados possíveis.** Teste de serviço com duas conexões e transações intercaladas. Teste do caminho de recusa no marketplace com `Http::fake`.

**Perguntas de reflexão.**
1. Liste todos os caminhos que alteram `inventory` e o mecanismo de proteção de cada um.
2. O que acontece com um lock Redis cujo TTL acaba enquanto o dono ainda trabalha?
3. Quando usar `NOWAIT` ou `SKIP LOCKED` em vez de esperar?
4. Como a solução se comporta com um item "quente" disputado por 5.000 pessoas?

**Hints.**
1. Liste todos os caminhos que alteram `inventory` e quais mecanismos de proteção cada um usa.
2. O que acontece com um lock Redis cujo TTL acaba enquanto o dono ainda trabalha?
3. O banco pode recusar um estado impossível e pode serializar quem mexe na mesma linha.

---

### T25 — Deadlocks intermitentes no checkout de carrinhos grandes

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-459 | 4 — Pleno+ | Banco / transações / deadlocks | SMALL (+ variante MySQL opcional) |

**Cenário empresarial.** Carrinhos com vários itens às vezes falham com erro 500 no checkout. No log do PostgreSQL aparece `deadlock detected`. Coincide com o horário em que roda `inventory:rebalance`, que transfere estoque entre armazéns.

**Sintoma.** Erros `40P01` (deadlock) no checkout e no rebalanceamento. A frequência aumenta com o tamanho do carrinho e com a concorrência.

**Informações disponíveis.** O serviço de checkout (reserva item a item), o comando `inventory:rebalance`, o log do PostgreSQL com `log_lock_waits` e deadlocks, `pg_locks` e `pg_stat_activity`.

**Checkpoints do lab (não remover):** `checkout.reserve-items.1` a `checkout.reserve-items.3` e `inventory.rebalance.1` a `inventory.rebalance.3`.

**Objetivo.** O checkout e o rebalanceamento convivem sem deadlocks nos fluxos conhecidos, e os deadlocks residuais, se ocorrerem, são tratados sem erro para o cliente.

**Conceitos envolvidos.** Deadlock (ciclo de espera); ordem consistente de aquisição de locks; `pg_locks` e `pg_stat_activity`; `log_lock_waits` e `deadlock_timeout`; leitura do log de deadlock do PostgreSQL e de `SHOW ENGINE INNODB STATUS`; retry de transação (`DB::transaction(..., attempts)`) e idempotência do retry; transações curtas; granularidade de lock; gap/next-key locks no MySQL.

**Preparar.** `make lab-start TASK=25`

**Endpoint / comando / tabelas.** `POST /api/checkout` · `inventory:rebalance` · `inventory`, `inventory_reservations`

**Critérios de aceite.**
- **AC1** — Harness com 2 intercalações que produzem deadlock no baseline: 0 deadlocks (delta de `pg_stat_database.deadlocks`) e ambos os participantes concluem.
- **AC2** — Stress (semente fixa): 200 checkouts com itens sobrepostos e 20 rebalanceamentos concorrentes. Resultado: 0 respostas `500`, invariantes de estoque preservados e deadlocks ≤ 1.
- **AC3** — Deadlock residual: o harness injeta um erro de deadlock (SQLSTATE `40P01`) na primeira tentativa de uma transação de checkout. A transação é repetida (no máximo 3 tentativas), sem efeitos duplicados, e o cliente não recebe `500`.
- **AC4** — As notas analisam o log de deadlock do baseline: quais transações, quais linhas e em que ordem cada uma travou (seção "Análise do deadlock").
- **AC5** *(opcional, MySQL)* — O mesmo cenário numa cópia MySQL (`make lab-start TASK=25 VARIANT=mysql`) sem deadlocks, com a análise de gap locks nas notas.

**Medir o antes.** `make lab-race TASK=25 SCENARIO=opposite-order`. Log do PostgreSQL. `pg_stat_database.deadlocks`.

**Medir o depois.** Os mesmos cenários. `lab-check`.

**Testes automatizados possíveis.** Teste com duas conexões e ordens opostas usando o harness em escala mínima. Teste de retry com exceção de deadlock simulada.

**Perguntas de reflexão.**
1. Qual era o ciclo exato?
2. Por que retry é rede de segurança e não correção?
3. Transações mais curtas reduzem deadlocks? Por quê?
4. O que muda no MySQL com REPEATABLE READ e inserções em faixas indexadas?

**Hints.**
1. Leia o log de deadlock: quais duas transações, quais linhas, em que ordem cada uma travou?
2. Se todos pegassem os locks na mesma ordem, um ciclo seria possível?
3. Deadlock não é bug do banco. Retry é rede de segurança, não correção.

---

### T26 — Marketplace: `429` e timeouts travam a sincronização de estoque

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-470 | 4 — Pleno+ | Integrações / resiliência | SMALL |

**Cenário empresarial.** Cada alteração de estoque dispara a sincronização da listing correspondente no marketplace. Em promoções, o marketplace responde `429`, às vezes fica lento ou dá timeout. A fila entope, os workers ficam presos em chamadas e o estoque no marketplace diverge do real. Houve venda de produto zerado e produto disponível aparecendo como esgotado.

**Sintoma.** Rajadas de chamadas acima do limite do parceiro. Workers bloqueados por dezenas de segundos. Atualizações antigas sobrescrevendo novas. Nenhum mecanismo detecta a divergência.

**Informações disponíveis.** O job `SyncListingToMarketplace` e o cliente HTTP do marketplace. `docs/partners/marketplace.md`, que descreve limite de taxa, `Retry-After`, `If-Match`/versões, `Idempotency-Key` e endpoint em lote. O estado do parceiro via `GET /__control/state/marketplace`.

**Objetivo.** A sincronização respeita o parceiro, sobrevive às falhas dele e converge para o estado correto, com um mecanismo que prova a convergência.

**Conceitos envolvidos.** Timeouts de conexão e de leitura; retry com backoff exponencial e jitter; `Retry-After`; rate limiting do lado do cliente (`Redis::throttle`, middleware `RateLimited` de jobs); circuit breaker; idempotency keys; ordem e versionamento de atualizações; coalescência (`ShouldBeUnique`, `WithoutOverlapping`, debounce); reconciliação.

**Preparar.** `make lab-start TASK=26 PROFILES=queue`

**Job / comando.** `Marketplace\SyncListingToMarketplace` · `marketplace:reconcile` (existe como esqueleto vazio)

**Critérios de aceite.**
- **AC1** — Cenário `burst`: 5.000 alterações de estoque em 500 listings. As chamadas ao marketplace são proporcionais às listings alteradas, não às alterações: ≤ 1,2 chamada por listing (ledger).
- **AC2** — Respeito ao parceiro: `429` recebidos ≤ 5% das chamadas, e nenhuma janela de 1 s (pelo relógio do mock) passa de 10 chamadas.
- **AC3** — Cenário `chaos` (sequência de `500`, `timeout`, `slow`, `429` e `409`): depois do drain, o estado do marketplace é igual ao do banco para 100% das listings.
- **AC4** — Nenhuma atualização mais antiga sobrescreve uma mais nova no parceiro (versões no ledger em ordem monotônica por listing).
- **AC5** — `marketplace:reconcile` detecta e corrige as divergências plantadas pelo cenário `drift` e é seguro de rodar repetidamente (segunda execução: 0 correções).
- **AC6** — Nenhum worker fica mais de 15 s preso numa única chamada (probe de chamadas externas por duração: informativo, com limite de liveness).

**Medir o antes.** `make lab-race TASK=26 SCENARIO=burst`, `chaos` e `drift`. Ledger e diferença entre o estado do parceiro e o do banco.

**Medir o depois.** Os mesmos cenários. `lab-check`.

**Testes automatizados possíveis.** `Http::fake` com sequências. Teste de classificação de erros. Teste de reconciliação com divergência plantada.

**Perguntas de reflexão.**
1. Quais erros são transitórios, quais são permanentes e quais pedem "vá mais devagar"?
2. Precisa de 10 chamadas para 10 mudanças no mesmo listing em 1 segundo?
3. O que um circuit breaker protege: você ou o parceiro?
4. Com que frequência reconciliar, e a que custo?

**Hints.**
1. Separe erros transitórios, permanentes e "vá mais devagar".
2. 10 mudanças no mesmo listing em 1 segundo precisam de 10 chamadas?
3. Mesmo com tudo certo, sistemas divergem. Quem confere?

---

### T27 — O webhook do marketplace aceita qualquer payload, e segredos aparecem nos logs

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-482 | 4 — Pleno+ | Segurança / integrações | SMALL |

**Cenário empresarial.** Um pentest mostrou que `POST /api/webhooks/marketplace` aceita pedidos forjados: com um payload alterado, dá para criar um pedido com valor diferente do real. O mesmo relatório encontrou a chave da API do gateway em logs de erro e um segredo de webhook com valor padrão no código.

**Sintoma.** Assinaturas não são verificadas corretamente. Requisições antigas podem ser reenviadas. O pedido é criado com os valores do payload. Segredos aparecem em logs e na configuração versionada.

**Informações disponíveis.** O controller do webhook, `config/services.php`, o cliente HTTP do gateway (com logging de erros), `docs/partners/marketplace.md` (esquema de assinatura e rotação de segredos) e o relatório do pentest (`docs/tasks/27-webhook-security/pentest.md`, com os achados em alto nível).

**Objetivo.** Só webhooks autênticos, recentes e inéditos são aceitos. Os dados do pedido vêm de uma fonte confiável. Nenhum segredo vaza para logs, respostas ou repositório.

**Conceitos envolvidos.** HMAC-SHA256; assinar o corpo bruto × o JSON re-serializado; comparação em tempo constante; tolerância de timestamp e proteção contra replay (nonce com TTL); rotação de segredos (duas chaves válidas); não confiar no payload (confirmar no parceiro); redação de logs; segredos fora do repositório e do histórico Git; falhar fechado; menor privilégio.

**Preparar.** `make lab-start TASK=27`

**Endpoint / arquivos.** `POST /api/webhooks/marketplace` · `config/services.php` · `app/Integrations/*`

**Critérios de aceite.**
- **AC1** — Bateria de 12 requisições do check (válida, assinatura inválida, corpo alterado depois de assinado, JSON reformatado, timestamp antigo, replay, header ausente, segredo anterior durante a janela de rotação, segredo anterior depois da janela...): cada uma recebe o status esperado da tabela publicada em `docs/tasks/27-webhook-security/README.md`.
- **AC2** — Depois de todos os cenários, nenhum log, exceção, resposta ou chamada ao mock contém os valores dos segredos, `Authorization` ou a chave de API (o check procura os valores conhecidos).
- **AC3** — Falha fechada: sem segredo configurado, o webhook rejeita tudo e a aplicação registra o erro de configuração. Nenhum valor padrão de segredo existe no código.
- **AC4** — Um pedido criado a partir de webhook usa valores confirmados pelo parceiro: um payload com valor alterado e assinatura válida (cenário de segredo comprometido) não propaga o valor alterado.
- **AC5** — As notas trazem o plano para o segredo que já foi commitado (rotação e histórico), na seção "Resposta ao incidente".

**Medir o antes.** Rode a bateria (`make lab-race TASK=27 SCENARIO=battery`). Procure os segredos em `storage/logs`.

**Medir o depois.** A mesma bateria. `lab-check`.

**Testes automatizados possíveis.** Testes de feature da bateria. Teste de redação de logs. Teste de configuração ausente.

**Perguntas de reflexão.**
1. Por que o JSON re-serializado não serve para verificar a assinatura?
2. O que `hash_equals` protege?
3. Remover o segredo do código resolve o vazamento?
4. Que outros lugares além dos logs costumam vazar segredos (traces, mensagens de exceção, Horizon, `failed_jobs`)?

**Hints.**
1. Assine exatamente os bytes que chegaram, não uma versão reconstruída.
2. Uma assinatura válida capturada hoje pode ser reenviada amanhã.
3. Procure todos os lugares onde a aplicação escreve headers, configuração e exceções.

---

### T28 — Lentidão intermitente que ninguém consegue explicar

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-495 | 4 — Pleno+ | Observabilidade | MEDIUM |

**Cenário empresarial.** O suporte recebe reclamações esporádicas: "o detalhe do pedido não carrega" e "o checkout ficou girando". A média de latência nos gráficos é ótima, e ninguém reproduz o problema. Hoje, a aplicação escreve logs em texto livre, sem identificador de requisição, sem métricas por rota e sem traces.

**Sintoma.** Uma fração pequena das requisições em `GET /api/me/orders/{uuid}` e `POST /api/checkout` leva mais de 5 s. Não há erros. A causa não aparece em nenhum log atual.

**Informações disponíveis.** O perfil `obs` (Prometheus, Grafana, Jaeger e otel-collector) já sobe, mas a aplicação não exporta nada útil. `make lab-load TASK=28` gera tráfego determinístico misto (100 VUs, orçamento fixo). `pg_stat_statements`. Horizon.

**Objetivo.** Instrumentar a aplicação para que a investigação seja possível e, com essa instrumentação, identificar as causas da cauda de latência, com evidências.

**Conceitos envolvidos.** Logs estruturados (JSON, campos padronizados); request/correlation ID (propagação HTTP → job → chamada externa → log); métricas RED e USE; histogramas e percentis (p50, p95, p99; por que a média engana); cardinalidade de labels; taxa de erro e throughput; tracing (spans, atributos, propagação de contexto); slow queries (`pg_stat_statements`, `auto_explain`); profundidade e idade de filas; saúde de workers (heartbeat).

**Preparar.** `make lab-start TASK=28 PROFILES=obs,queue,bench`

**Pontos de entrada.** Toda a aplicação. Foco em `GET /api/me/orders/{uuid}`, `POST /api/checkout` e nos jobs derivados do checkout.

**Critérios de aceite.**
- **AC1** — Todo log de requisição e de job é JSON e contém `timestamp`, `level`, `message`, `request_id`, `route` ou `job`, `duration_ms` e `status`/`outcome`. Identificadores pessoais aparecem só como hash (o check processa os logs do cenário).
- **AC2** — O `request_id` de uma requisição de checkout aparece nos logs dos jobs derivados e nas chamadas ao mock (header `X-Request-Id` no ledger).
- **AC3** — `/metrics` expõe histograma de latência por rota (sem IDs em labels), contador de erros por rota, profundidade de cada fila e idade do último heartbeat de cada worker. O check valida a cardinalidade: < 200 séries por métrica no cenário.
- **AC4** — Os traces das duas rotas foco têm spans de banco e de chamada externa, com atributos suficientes para distinguir requisições lentas de rápidas (o check consulta a API do Jaeger).
- **AC5** — Diagnóstico: `storage/lab/answers/28.json` identifica as causas da cauda usando o vocabulário de `docs/tasks/28-observability/taxonomy.md` (rota, dimensão, valor e componente; a lista inclui opções que não são causa). A comparação é por hash e tolera no máximo 1 falso positivo. As notas mostram as evidências (queries PromQL, IDs de trace, consultas SQL) na seção "Evidências".
- **AC6** *(opcional)* — Corrigir as causas encontradas: p99 das rotas foco ≤ 3× p50 no mesmo cenário (WARN, não FAIL).

**Medir o antes.** Tente responder "quais requisições estão lentas e por quê" só com o que existe. Registre nas notas o que faltou.

**Medir o depois.** Grafana e Jaeger com o mesmo tráfego. `lab-check`.

**Testes automatizados possíveis.** Teste do middleware de request ID. Teste de propagação para jobs. Teste de formato de log.

**Perguntas de reflexão.**
1. Por que a média estava ótima?
2. Que labels você **não** colocou nas métricas, e por quê?
3. O que um trace mostra que logs e métricas não mostram?
4. Qual alerta você criaria a partir disso, e como evitaria ruído?

**Hints.**
1. A média esconde a cauda: olhe o p99 por rota e depois quebre por dimensões.
2. Um trace de uma requisição lenta vale mais que mil médias, mas você precisa conseguir encontrá-lo.
3. Compare os atributos das requisições lentas com os das rápidas: o que elas têm em comum?

---

### T29 — A tela de pedidos do backoffice trava o navegador

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-503 | 3 — Pleno | Vue / front-end / full stack | MEDIUM |

**Cenário empresarial.** A tela `/admin/orders` (Vue + Inertia) é usada o dia todo pelo atendimento. Ela trava o navegador por segundos ao abrir. Ao digitar na busca, mostra resultados de um termo anterior. Com a aba aberta em segundo plano, o notebook da equipe esquenta.

**Sintoma.** Abertura lenta com payload enorme. Dezenas de requisições ao digitar. Resultados fora de ordem. Milhares de linhas no DOM. Um gráfico pesado carregado de cara. Polling constante.

**Informações disponíveis.** A página Vue, os componentes, o endpoint `GET /api/admin/orders/search` e o build do Vite (`public/build/manifest.json`). DevTools (Network, Performance). O mock de latência do lab: `?lab_delay_ms=` nas requisições da busca, com o lab ativo.

**Objetivo.** A tela abre rápido, a busca reflete o que o usuário digitou e o navegador faz só o trabalho necessário.

**Conceitos envolvidos.** Debounce e throttle; cancelamento de requisições (`AbortController`) e respostas fora de ordem; paginação e scroll infinito no servidor; payload mínimo; virtualização de listas; code splitting e lazy loading (`defineAsyncComponent`, `import()` dinâmico); polling × push e `visibilitychange`; DevTools Network e Performance; INP; separar o tempo de servidor, transferência, parse e render.

**Preparar.** `make lab-start TASK=29` (Playwright usa o Chromium do container)

**Página / endpoint.** `/admin/orders` · `GET /api/admin/orders/search` · `resources/js/pages/admin/Orders.vue` e componentes

**Critérios de aceite.**
- **AC1** — Playwright: digitar "maria silva" em ritmo humano (100 ms entre teclas) gera ≤ 3 requisições de busca. Com respostas atrasadas fora de ordem, a tela termina mostrando o resultado do último termo.
- **AC2** — A carga inicial da tela transfere ≤ 300 KB de JSON.
- **AC3** — Com 5.000 pedidos navegáveis, a tabela mantém ≤ 300 linhas renderizadas no DOM em qualquer posição de rolagem ou página.
- **AC4** — O chunk JS inicial da página não inclui a biblioteca de gráficos (verificado no manifest do Vite). O gráfico carrega sob demanda.
- **AC5** — O polling de estatísticas faz ≤ 1 requisição a cada 10 s e para com a aba oculta (Playwright emulando `visibilitychange`).
- **AC6** — A resposta do endpoint de busca continua correta pelo contrato (GOLD da primeira página para três termos).

**Medir o antes.** DevTools: número de requisições, bytes, tempo de script e renderização. `make lab-benchmark TASK=29` roda os cenários Playwright e registra PW.

**Medir o depois.** Os mesmos cenários. `lab-compare`.

**Testes automatizados possíveis.** Os testes Playwright do check, mais testes de unidade do composable de busca (Vitest, se o aluno adicionar).

**Perguntas de reflexão.**
1. Quanto do tempo total era servidor, rede, parse e render?
2. Debounce resolve respostas fora de ordem? Por quê?
3. Quando virtualizar e quando paginar?
4. Por que um polling de 1 s em cada aba aberta vira problema de backend?

**Hints.**
1. Abra a aba Network e digite devagar: conte as requisições. Depois simule respostas lentas.
2. O usuário vê 30 linhas por vez. Quantas o navegador está desenhando?
3. Quebre o tempo total em servidor, transferência, parse e render.

---

### T30 — Incidente final: Black Friday, 00:00

| Ticket | Nível | Área | Dataset recomendado |
|---|---|---|---|
| BP-600 (SEV-1) | 5 — Sênior | Tudo | MEDIUM |

**Cenário empresarial.** Às 23h a release `2026.11` foi para produção com a feature **Flash Sale**: ofertas relâmpago com estoque limitado e limite por cliente. À meia-noite, a campanha abre. Em minutos:
- a CPU do banco vai a 100% e o p99 passa de 30 s;
- o suporte recebe reclamações de clientes que "garantiram" a oferta, mas o estoque já tinha acabado;
- confirmações de pagamento atrasam 40 minutos;
- a fila de jobs cresce sem parar;
- o front-end de ofertas parece "piscar".

Você é o engenheiro de plantão.

**A release Flash Sale** (existe apenas no baseline desta task):
- tabelas `flash_sales` (id, name, starts_at, ends_at, status), `flash_sale_items` (id, flash_sale_id, variant_id, price_cents, stock_limit, per_customer_limit) e `flash_sale_claims` (id, flash_sale_item_id, customer_id, status, order_id, created_at);
- `GET /api/flash-sales/current` (vitrine da oferta, com estoque restante);
- `POST /api/flash-sales/{id}/claim` (garante o item e cria o pedido pendente);
- job `SettleFlashSaleClaim` (autoriza e captura o pagamento e confirma a claim);
- widget Vue `FlashSaleBanner` na home.

**Sintoma.** O descrito acima, reproduzido por `make lab-load TASK=30 PROFILE=black-friday`: k6 com rampa de 10 → 300 VUs, orçamento fixo de iterações e mistura determinística de navegação, claims e checkout.

**Informações disponíveis.** Tudo o que existe no projeto: Horizon, `obs` (com a instrumentação que você levar da T28, se usar `FROM=lab/task-28`), `pg_stat_statements`, ledger dos parceiros e o runbook vazio em `docs/tasks/30-black-friday/runbook.md`.

**Objetivo.**
1. **Estabilizar** primeiro, com mitigações rápidas registradas na linha do tempo.
2. **Encontrar as causas raiz.** Há mais de uma, e cada uma lembra algo que você já viu.
3. **Corrigir e provar** com antes e depois no mesmo cenário.
4. Escrever o **postmortem**.

**Conceitos envolvidos.** Todos os anteriores, mais triagem, priorização, mitigação × correção, SLOs, runbooks e postmortem sem culpados.

**Preparar.** `make lab-start TASK=30 PROFILES=queue,obs,bench [FROM=lab/task-28]`

**Endpoints / jobs / tabelas.** `GET /api/flash-sales/current` · `POST /api/flash-sales/{id}/claim` · `SettleFlashSaleClaim` · `FlashSaleBanner` · `flash_sales`, `flash_sale_items`, `flash_sale_claims` (e tudo o que o checkout e os pagamentos tocam)

**Critérios de aceite.**
- **AC1 — Corretude (INV)** ao fim do cenário: claims confirmadas ≤ `stock_limit` de cada item; claims por cliente ≤ `per_customer_limit`; nenhum pagamento capturado duas vezes; toda claim confirmada tem pedido e pagamento coerentes.
- **AC2 — Custo por requisição (QPR/CACHE):** `GET /api/flash-sales/current` em regime ≤ 1 query por requisição. `POST /claim` ≤ 8 queries. A vitrine recomputa no máximo 1 vez por expiração, sob carga.
- **AC3 — Filas:** jobs de pagamento nunca esperam atrás de jobs de outra natureza (ordem registrada), e todas as filas drenam completamente depois do cenário (`lab-drain` termina sem falhas pendentes não explicadas).
- **AC4 — Front-end (PW):** com a aba visível, o widget faz ≤ 1 requisição a cada 5 s; com a aba oculta, nenhuma.
- **AC5 — Diagnóstico:** `storage/lab/answers/30.json` identifica corretamente pelo menos 4 causas raiz, usando os códigos de `docs/tasks/30-black-friday/taxonomy.md` (lista genérica de causas e componentes, com opções que não são causa). A comparação é por hash e tolera no máximo 2 falsos positivos.
- **AC6 — Postmortem:** `docs/lab-notes/30-postmortem.md` tem as seções Resumo, Impacto, Linha do tempo, Detecção, Causas raiz, Mitigação, Correções, O que funcionou, O que não funcionou e Ações preventivas (com responsável e prazo fictícios), com no mínimo 600 palavras.
- **AC7 — Carga (informativo, WARN):** em `LOAD=300`, taxa de erro 5xx < 1% e p95 ≥ 5× melhor que o baseline **na mesma máquina**.

**Medir o antes.** `make lab-benchmark TASK=30 LABEL=before LOAD=300` antes de qualquer mudança. Guarde prints do Grafana e do Horizon.

**Medir o depois.** `LABEL=after` com a mesma carga. `lab-compare`. `lab-check`.

**Testes automatizados possíveis.** Regressões para cada causa raiz corrigida (escolha do aluno). O check roda a suíte inteira.

**Perguntas de reflexão.**
1. Qual foi a primeira ação que mais reduziu o impacto, e por que você a escolheu?
2. Que sinais apareceram primeiro? Que alerta teria detectado o problema às 23h50?
3. Quais causas raiz um code review poderia ter evitado? E um teste de carga antes da release?
4. O que você mudaria no processo de release?

**Hints.**
1. Primeiro estabilize: o que você pode desligar ou limitar sem código novo?
2. Separe sintomas de causas: quais métricas se movem primeiro?
3. Revise as tasks anteriores. Cada causa raiz aqui já apareceu antes com outra roupa.

---

## 10. Matriz conceito × task

● = foco principal · ○ = aparece de forma secundária

| Conceito | ● Principal | ○ Secundário |
|---|---|---|
| EXPLAIN / EXPLAIN ANALYZE / BUFFERS | 01, 03, 06, 07, 09 | 02, 04, 05, 08, 11, 30 |
| Full table scan | 01, 02, 06 | 03, 07, 08, 09, 11 |
| Índices B-tree | 01, 02 | 03, 06, 07, 09 |
| Índice composto e ordem das colunas | 03, 09 | 01, 06, 07 |
| Seletividade / cardinalidade / estatísticas | 03 | 04, 06 |
| Índices inúteis e redundantes | 04 | 03 |
| Trade-off leitura × escrita | 04 | 06, 11 |
| Índices sobre expressões / collation | 02 | 06 |
| JOIN / LEFT JOIN / fan-out | 05 | 06, 08, 11 |
| Subqueries / anti-join / NOT IN × NULL | 08 | 05, 11 |
| Agregações / GROUP BY | 05, 06 | 12, 21 |
| ORDER BY / ordenação por índice | 03, 09 | 01, 07, 11 |
| Queries em milhões de registros | 06, 07 | 03, 04, 09 |
| Paginação OFFSET × keyset | 07 | 09, 29 |
| Transações | 13, 20, 23 | 22, 24, 25 |
| Locks (pessimista, row locks) | 24, 25 | 23, 30 |
| Deadlocks | 25 | 24 |
| Isolamento / concorrência no banco | 23 | 24, 25 |
| Otimização SQL × otimização Eloquent | 11 | 10, 12 |
| Diferenças MySQL × PostgreSQL | 09 | 01, 02, 04, 08, 23, 25 |
| N+1 / eager loading | 10 | 18, 28 |
| Over-fetching / select de colunas | 10 | 29 |
| withCount / whereHas | 11 | 10 |
| chunk / lazy / cursor / grandes datasets | 12 | 07, 18 |
| Uso de memória | 12 | 21 |
| Service boundaries / síncrono × assíncrono | 13 | 18, 22 |
| Key/value, Cache::remember, TTL | 14 | 15, 16 |
| Hit / miss / key design | 14 | 15 |
| Invalidação / stale | 15 | 16, 30 |
| Cache stampede | 16 | 30 |
| Locks distribuídos | 16, 24 | 26 |
| Rate limiting | 17 | 26 |
| Quando NÃO usar cache | 15 | 14 |
| Dispatch / queue / worker / jobs | 18 | 13, 19, 20 |
| Retries / attempts / backoff / timeout | 19 | 26 |
| Failed jobs | 19 | 20 |
| Reentrega / worker que morre | 20 | 21 |
| ACK/NACK / DLQ / RabbitMQ | 21 | — |
| Horizon | 18 | 19, 30 |
| Redis Queue × RabbitMQ | 21 | 18 |
| Jobs idempotentes | 20 | 18, 19, 21 |
| Backlog / scaling de workers | 18 | 30 |
| Duplicate webhook / payment event | 22 | 27 |
| Check-then-insert / UNIQUE | 22 | 02, 23 |
| Operações atômicas | 23 | 17, 24 |
| Reserva concorrente de estoque | 24 | 30 |
| Timeouts / backoff exponencial em integrações | 26 | 13, 19 |
| Idempotency keys | 26 | 19, 22 |
| Reconciliação | 26 | 21 |
| Assinatura de webhooks / segurança / secrets | 27 | 17 |
| Logs estruturados / correlation ID | 28 | 30 |
| Métricas / p50-p95-p99 / throughput / error rate | 28 | 16, 30 |
| Tracing | 28 | 30 |
| Queue depth / worker health | 28 | 18, 30 |
| Slow queries | 28 | 01, 06 |
| Debounce / payload / listas extensas / lazy loading | 29 | 30 |
| Python | 21 | (mock de parceiros) |
| Carga com k6 (10 / 100 / 300 usuários) | 14, 16, 30 | 01, 10, 23, 28 |
| Investigação de incidente / postmortem | 30 | 28 |

---

## 11. Ordem recomendada

**Trilha completa (padrão):** 01 → 30 em ordem numérica. Os pré-requisitos principais:

```
01 ─▶ 02 ─▶ 03 ─▶ 04
 └──▶ 05 ─▶ 06 ─▶ 07 ─▶ 08 ─▶ 09
10 ─▶ 11 ─▶ 12 ─▶ 13
14 ─▶ 15 ─▶ 16 ─▶ 17
13 ─▶ 18 ─▶ 19 ─▶ 20 ─▶ 21
22 ─▶ 23 ─▶ 24 ─▶ 25
19 ─▶ 26 ─▶ 27
(qualquer 10+) ─▶ 28 ─▶ 30
29 (independente, após 07 e 10)
```

**Trilha curta de entrevista (13 tasks):** 01, 03, 07, 10, 12, 14, 16, 18, 19, 22, 24, 28, 30.

**Trilha "banco primeiro":** 01–09, depois 23, 25 e 11, e então o restante.

**Recomendações:**
- Registre **sempre** as notas antes de abrir a solução.
- Ao terminar um bloco, faça merge dos seus branches num branch pessoal `lab/progress` para ter um projeto "curado" (opcional).
- Para a T30, use `FROM=lab/task-28` se quiser partir da sua instrumentação.

---

## 12. Estimativa de dificuldade

Escala de 1 (baixa) a 5 (alta) em quatro dimensões. **Não é estimativa de tempo.**

| Task | Investigação | Conceito | Implementação | Concorrência / falhas | Geral |
|---|:-:|:-:|:-:|:-:|:-:|
| T01 | 1 | 1 | 1 | 0 | **1** |
| T02 | 2 | 2 | 2 | 1 | **1,5** |
| T03 | 3 | 3 | 1 | 0 | **2** |
| T04 | 3 | 3 | 2 | 0 | **2,5** |
| T05 | 3 | 2 | 2 | 0 | **2** |
| T06 | 3 | 3 | 3 | 0 | **3** |
| T07 | 2 | 3 | 3 | 2 | **3** |
| T08 | 3 | 3 | 2 | 0 | **2,5** |
| T09 | 3 | 3 | 2 | 0 | **3** |
| T10 | 2 | 2 | 2 | 0 | **2** |
| T11 | 3 | 3 | 3 | 1 | **3** |
| T12 | 3 | 3 | 3 | 1 | **3** |
| T13 | 3 | 3 | 4 | 3 | **3,5** |
| T14 | 2 | 2 | 2 | 0 | **2** |
| T15 | 3 | 3 | 3 | 3 | **3** |
| T16 | 3 | 4 | 3 | 4 | **4** |
| T17 | 3 | 3 | 2 | 3 | **3** |
| T18 | 3 | 3 | 3 | 2 | **3** |
| T19 | 4 | 4 | 3 | 4 | **4** |
| T20 | 4 | 4 | 4 | 5 | **4** |
| T21 | 3 | 4 | 4 | 4 | **4** |
| T22 | 3 | 3 | 3 | 4 | **3,5** |
| T23 | 3 | 4 | 3 | 5 | **4** |
| T24 | 4 | 4 | 4 | 5 | **4,5** |
| T25 | 4 | 4 | 3 | 5 | **4** |
| T26 | 4 | 4 | 4 | 4 | **4** |
| T27 | 3 | 4 | 3 | 2 | **3,5** |
| T28 | 5 | 4 | 4 | 2 | **4** |
| T29 | 3 | 3 | 3 | 2 | **3** |
| T30 | 5 | 5 | 5 | 5 | **5** |

---

## 13. Requisitos de implementação para o Codex

### 13.1 Pré-condições

1. Validar a fundação conforme `docs/foundation-validation.md` (setup executado, lockfiles versionados, testes do starter passando no banco `testing`). Não começar sem isso.
2. Registrar as versões exatas de todas as imagens e pacotes em `docs/lab-versions.md`.
3. Confirmar a compatibilidade com Laravel 13 dos pacotes usados (Horizon, Sanctum, cliente Prometheus, SDK OpenTelemetry, php-amqplib). Se algum não for compatível, escolher a alternativa oficial ou mais próxima e documentar.

### 13.2 Documento selado de cenários

Junto desta especificação existe um documento de design de cenários, **destinado apenas ao implementador**, numa pasta `DO_NOT_OPEN_SOLUTIONS`. Ele define, para cada task:
- o estado exato do baseline (schema, índices, constraints, código);
- o defeito plantado e onde fica;
- os dados e âncoras do cenário;
- os parâmetros dos checks;
- a direção da solução de referência e as alternativas aceitas.

Na implementação, o conteúdo vai para `vault/DO_NOT_OPEN_SOLUTIONS/_design/` e segue todas as regras da §8. **O Codex deve lê-lo antes de implementar as tasks.** Nenhuma informação dele pode aparecer fora do vault.

### 13.3 Fases e critérios de saída

| Fase | Entrega | Critério de saída |
|---|---|---|
| **F1 — Infra** | Perfis Compose (§3), configs de pgsql/mysql/redis/rabbitmq/nginx/fpm/obs, `partners-mock` com plano de controle, Makefile esqueleto | `docker compose --profile ... config` válido. Todos os serviços saudáveis. Testes do mock (pytest) passando. |
| **F2 — Domínio e dataset** | Migrations do baseline, models, factories, gerador SQL determinístico, templates por dataset, export para MySQL, âncoras, manifestos | SMALL e MEDIUM geram manifestos idênticos em duas execuções seguidas. LARGE gera sem erro (pode rodar fora do CI). |
| **F3 — Ferramentas do lab** | `lab:*` (start, reset, check, benchmark, compare, race, drain, load, status, info, hint, reveal, dataset, verify-solutions), probes, checkpoints (PHP e Python), harness de corrida, PlanInspector, cliente do ledger, relatórios JSON | Testes do próprio lab (unitários e integração) passando. `lab-start`/`lab-reset` idempotentes. Isolamento entre duas tasks demonstrado por teste. |
| **F4 — Features do baseline** | Endpoints, jobs, comandos, páginas e a release Flash Sale, conforme §4 e o documento selado | Suíte de testes funcionais do domínio passando. Cada defeito presente e **demonstrável**. Sem comentários-pista. |
| **F5 — Tasks** | `docs/tasks/XX` (README com todos os campos da §6.1 + hints.md), `lab/tasks/XX` (manifesto, cenários, k6, contratos), checks, `baseline.<dataset>.json`, golden checksums | `lab-check` de cada task **falha** no baseline em todos os ACs obrigatórios previstos. |
| **F6 — Vault** | Para cada task: README, investigation, solution.patch, queries, results, tradeoffs | `lab-verify-solutions` verde para as 30 tasks (§13.6). |
| **F7 — CI e documentação** | Workflow de CI, `docs/concepts/*`, `docs/partners/*`, README principal, `docs/lab-notes/README.md` | CI verde. Revisão anti-spoiler (§13.7) concluída. |

### 13.4 Padrões de implementação

- **Código:** PHP 8.5 com tipos estritos onde o starter já usa. Pint e Larastan (nível do starter) passando. Nomes de domínio em inglês. Documentação do aluno em PT-BR.
- **Lab isolado:** tudo do laboratório fica em `app/Lab`, `lab/`, `tests/Lab` e `config/lab.php`, e **não** é registrado quando `LAB_ENABLED=false` ou `APP_ENV=production`.
- **Headers de lab:** `X-Lab-Queries`, `X-Lab-Participant`, `X-Lab-Harness`, `X-Content-Age` (este é contrato de produto na T16).
- **Determinismo:** nenhum check aprova ou reprova por tempo absoluto. Tempo só como liveness, com margem ≥ 3×.
- **Checkers:** um diretório por task em `app/Lab/Tasks/TXX/Checks`, cada AC numa classe pequena. Mensagens neutras (§8). Os checks que alteram estado rodam numa cópia descartável do database da task.
- **Golden:** gerado pelo comando de mantenedor `lab:golden TXX` a partir da solução de referência numa worktree temporária, gravando só hashes (e, no máximo, valores de âncoras para exemplos de divergência).
- **Baseline de métricas:** `lab/tasks/XX/baseline.<dataset>.json`, gerado por `lab:baseline-refresh` a partir da tag `lab-baseline` numa worktree temporária.
- **Partners-mock:** Python 3.13, FastAPI, estado em memória por namespace de task (com persistência opcional em SQLite para o ledger), relógio próprio controlável (`/__control/clock`), testes com pytest.
- **Analytics-consumer:** Python 3.13 com pika (ou aio-pika). Lê as políticas de checkpoint do Redis. Configurável por variáveis de ambiente.
- **Front-end:** seguir o stack do starter (Vue 3, Inertia, TS, Tailwind, componentes shadcn-vue). Playwright para os checks da T29 e T30.
- **k6:** scripts em `lab/k6` e `lab/tasks/XX/bench.k6.js`, com os executores `shared-iterations`/`per-vu-iterations` (orçamento fixo). Resultados em JSON via `--summary-export`.
- **Segurança:** nenhum segredo real. Os segredos de laboratório são gerados por `lab:start` e ficam em `storage/lab/secrets.json` (gitignored). Na T27, o "segredo vazado" é um valor de laboratório plantado de propósito.

### 13.5 Git e tags

- A tag `lab-baseline` aponta para o commit que contém o baseline completo (F1–F5), **sem** o vault. O vault entra em commits posteriores que só tocam `vault/`.
- As mensagens de commit do baseline são neutras (§8, regra 11).
- Os branches `lab/task-XX` são criados localmente pelo aluno e nunca versionados pelo Codex.

### 13.6 Verificação obrigatória (`lab-verify-solutions`)

Para cada task, numa worktree temporária e em SMALL (MEDIUM onde o AC exigir, no job noturno do CI):
1. Com o baseline puro, `lab-check` retorna **FAIL** em todos os ACs marcados como "falha esperada no baseline" no documento selado.
2. Com o `solution.patch` aplicado, `lab-check` retorna **PASS** em todos os ACs obrigatórios.
3. Os cenários de corrida demonstram a falha no baseline em **20 de 20** execuções e passam com a solução em **20 de 20**.
4. A saída do comando mostra só `TXX: baseline FAIL ✔ / solution PASS ✔`, sem conteúdo.

### 13.7 Revisão anti-spoiler (checklist do Codex)

- [ ] `rg -i "vault|DO_NOT_OPEN" --glob '!vault/**'` só encontra o README principal (frase padrão), `.ignore`, `.rgignore`, o Makefile/`lab:reveal` e esta spec.
- [ ] Nenhum nome de índice, coluna nova, classe ou método da solução aparece fora do vault.
- [ ] Os hints revisados um a um contra a solução: nenhum contém a resposta direta.
- [ ] O histórico Git do baseline não tem mensagens reveladoras.
- [ ] Os testes em `tests/Lab` não contêm lógica de solução.
- [ ] Os conceitos em `docs/concepts` não citam tasks, tabelas ou arquivos do projeto.

### 13.8 O que o Codex **não** deve fazer

- Implementar as soluções fora do vault ou "melhorar" o baseline corrigindo defeitos.
- Criar metas de latência absolutas.
- Versionar dumps ou datasets gerados.
- Usar `docker system prune`, `down -v`, `migrate:fresh` nos databases do aluno, ou apagar branches do aluno.
- Introduzir dependências pesadas sem necessidade pedagógica (ex.: Elasticsearch, Kafka, Kubernetes).
- Deixar comentários, nomes ou mensagens que sugiram onde está o defeito.

---

## 14. Definition of Done do projeto

O Bottleneck Playground está pronto quando **todos** os itens abaixo forem verdadeiros:

**Ambiente**
- [ ] Clone novo em Linux/WSL2 → `./scripts/setup.sh` → `make lab-dataset DATASET=small` → `make lab-start TASK=01` funciona sem passos manuais não documentados.
- [ ] Todos os perfis Compose sobem saudáveis; versões fixadas em `docs/lab-versions.md`.
- [ ] SMALL e MEDIUM reproduzem o mesmo `manifest.json` em máquinas diferentes.

**Laboratório**
- [ ] As 30 tasks têm enunciado completo (todos os campos da §6.1), hints (≤ 3), manifesto, cenário, checks, baseline de métricas e golden.
- [ ] `lab-start`, `lab-reset` (com e sem `CODE=1`), `lab-check`, `lab-benchmark`, `lab-compare`, `lab-race`, `lab-drain`, `lab-hint`, `lab-info` e `reveal` funcionam em todas as tasks.
- [ ] Resetar ou refazer uma task não altera o estado, o código ou os resultados de outra (teste automatizado).
- [ ] Nenhum critério obrigatório depende de latência absoluta.

**Qualidade das tasks**
- [ ] `lab-verify-solutions` verde nas 30 tasks (baseline FAIL, solução PASS; corridas 20/20).
- [ ] Cada task foi "jogada" de ponta a ponta por um agente ou revisor que não viu a solução, e o relato está em `vault/DO_NOT_OPEN_SOLUTIONS/_playtest/TXX.md`: a investigação é possível só com o enunciado, as ferramentas e os hints.
- [ ] O bloco de banco (T01–T09) e os de concorrência (T22–T25) passam também no MEDIUM.

**Anti-spoiler**
- [ ] Checklist da §13.7 concluído.
- [ ] README principal contém exatamente: *"Solutions exist in a deliberately isolated vault. Do not open it until you choose to review a task."*
- [ ] `make reveal` só mostra o caminho, e só depois de confirmação explícita.

**Documentação**
- [ ] README principal: propósito, pré-requisitos, instalação, fluxo de uma task, comandos do lab, datasets, troubleshooting.
- [ ] `docs/concepts/`: EXPLAIN (PG e MySQL), índices, paginação, transações e isolamento, locks e deadlocks, cache, Redis, filas e entrega, idempotência, resiliência de integrações, webhooks e segurança, observabilidade, performance de front-end, k6, MySQL × PostgreSQL. Tudo genérico.
- [ ] `docs/partners/`: gateway, ERP, marketplace e notificações.
- [ ] Esta especificação atualizada para refletir as decisões finais de implementação (seção "Desvios" no fim, se houver).

**CI**
- [ ] Lint (Pint, Larastan, ESLint/Vite Plus, ruff para Python), testes da aplicação, testes do lab e do mock, e `lab-verify-solutions` em SMALL a cada PR; MEDIUM em execução noturna ou manual.
