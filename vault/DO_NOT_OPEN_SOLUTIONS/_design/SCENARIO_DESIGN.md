# ⛔ DO NOT OPEN — Bottleneck Playground: design selado de cenários

> **Se você vai estudar as tasks, feche este arquivo agora.** Ele descreve os defeitos plantados e a direção das soluções de todas as 30 tasks.
>
> Destinatário: o agente implementador (Codex). Na implementação, este conteúdo vai para `vault/DO_NOT_OPEN_SOLUTIONS/_design/` e segue as regras anti-spoiler da §8 da Curriculum Spec. Nada daqui pode aparecer fora do vault: nem em código, comentários, testes, hints, mensagens de commit ou documentação do aluno.

---

## 0. Regras gerais para o implementador

1. **Defeitos plausíveis.** Cada defeito é código ou schema que um time real escreveria. Sem comentários, nomes ou TODOs que apontem para ele.
2. **Neutralização por cenário.** Quando um defeito global (ex.: a falta de índice da T01) contaminaria a medição de outra task, o `scenario.sql` daquela task o neutraliza (ex.: cria o índice). Tabela na §2.
3. **Calibração dos limites.** Para cada AC métrico: o baseline deve falhar com margem ≥ 3×, e a solução de referência deve passar com margem ≥ 1,5×. Se não for possível, ajuste o **cenário ou o dataset**, nunca o limite de forma arbitrária. Registre os valores medidos em `results.md` da task.
4. **Falhas esperadas no baseline.** A coluna "Falha no baseline" de cada task lista os ACs que **precisam** falhar no baseline. `lab-verify-solutions` verifica isso.
5. **Alternativas aceitas.** Os checks não podem exigir a solução de referência. Toda alternativa listada como aceita precisa passar. Escreva um teste de mantenedor por alternativa em `vault/.../TXX/alternatives/`.
6. **Relógio escalado.** Tempos de fila, retry e lock são escalados para segundos no lab (`config/lab.php`), com margens ≥ 3×.

---

## 1. Schema e dados do baseline (global)

### 1.1 Índices e constraints do baseline

| Tabela | Baseline |
|---|---|
| customers | PK; `UNIQUE(email)` (btree, sensível a caixa); sem índice em `segment`, `created_at` |
| addresses | PK; `(customer_id)` |
| categories | PK; `UNIQUE(slug)`; `(parent_id)` |
| products | PK; `UNIQUE(slug)`; `(category_id)`; `(status)` |
| product_variants | PK; `UNIQUE(sku)`; `(product_id)` |
| product_reviews | PK; `(product_id)` — **sem** status/rating |
| warehouses | PK; `UNIQUE(code)` |
| inventory | PK; `UNIQUE(variant_id, warehouse_id)`; **sem CHECK** |
| inventory_reservations | PK; `(order_id)`; `(variant_id)` |
| coupons | PK; `UNIQUE(code)`; **sem CHECK** em `used_count` |
| coupon_redemptions | PK; `(coupon_id)` — **sem** `UNIQUE(coupon_id, customer_id)` |
| orders | PK; `UNIQUE(uuid)`; `UNIQUE(number)`; `(status)`; `(placed_at)`; `(placed_at, status)`; **sem índice em `customer_id`** (FK existe) |
| order_items | PK; `(order_id)`; `(variant_id)` |
| order_status_history | PK; `(order_id)` |
| payments | PK; `(order_id)`; `(provider_payment_id)` (não único) |
| payment_events | PK; `(payment_id)` — **sem** unique em `provider_event_id` |
| webhook_events | PK; `(provider, received_at)` — **sem** unique em `(provider, external_id)` |
| marketplace_listings | PK; `UNIQUE(marketplace, external_listing_id)`; `(variant_id)` |
| marketplace_syncs | PK; `(listing_id)` |
| erp_exports | PK; `(order_id)` (não único) |
| audit_logs | PK; `(subject_type, subject_id)` |
| idempotency_keys | PK; `UNIQUE(scope, key)` |
| legacy_catalog_items (MySQL) | PK; `(category_id)`; `(price_cents)`; `(created_at)`; `(is_active)` |

### 1.2 Distribuições exatas (MEDIUM; SMALL e LARGE são proporcionais)

- **Status de pedidos:** delivered 78%, shipped 5,5%, picking 1,5%, paid 2%, pending_payment 1%, canceled 9%, refunded 3%. `paid` concentrado nos últimos 14 dias; 0,3% dos pedidos `paid` são "backorders" antigos espalhados pelos 36 meses.
- **Armazéns:** SP1 60%, RJ1 20%, PR1 10%, MG1 5%, BA1 5%.
- **Pedidos de convidado** (`customer_id` NULL): 4%.
- **Clientes sem pedidos:** 25%. **Whales** (`segment = wholesale`): 0,2% dos clientes, com 2.000–20.000 pedidos cada (âncora `C-WHALE-01` com 20.000).
- **E-mails:** 30% com caixa mista. **0,6% dos clientes formam pares que diferem só pela caixa** (T02).
- **Endereços:** 60% dos clientes com mais de 1 endereço; exatamente 1 `is_default` de `shipping` por cliente com endereço.
- **Pagamentos:** 10% dos pedidos têm uma tentativa `failed` antes da `captured`.
- **Duplicatas históricas:** 0,3% dos `webhook_events` (gateway) e dos `payment_events` duplicados por `external_id`/`provider_event_id` (T22).
- **`placed_at`:** gerado em ordem cronológica, com `id` crescente correlacionado com o tempo. Resolução de segundo e rajadas com vários pedidos no mesmo segundo (ties da T07).
- **Timezone:** 2% dos pedidos caem entre 21:00 e 23:59 (horário de São Paulo) do último dia de cada mês (fronteira da T06).

### 1.3 Âncoras (IDs estáveis em todos os datasets)

`C-REG` (≈20 pedidos), `C-VIP` (≈300), `C-WHALE-01` (20.000 no MEDIUM), `C-DUP-01..20` (pares de caixa da T02), `C-NOORD-01..05`, `SKU-LAST-42` (1 unidade no SP1), `SKU-HOT-01..20`, `COUPON-LIVE100` (limite 100, 1 por cliente), `WH-SP1`, `WH-MG1`, `CAT-BIG`, `CAT-MID`, `CAT-SMALL` (PG e MySQL), `ORD-DEEP` (pedido na posição de 90% da ordenação por data desc).

---

## 2. Neutralizações por cenário

| Task | O `scenario.sql` neutraliza |
|---|---|
| T12, T13, T18, T20, T22–T26, T28, T30 | cria `orders(customer_id)` (a falta dele pertence à T01) |
| T28, T30 | cria `product_reviews(product_id, status)` e os índices da T03 |
| T14, T15, T16 | desativa os `$with`/`$appends` excessivos do model `Order` (pertencem à T10) |
| T22 | remove as duplicatas históricas de outros providers (mantém só as do gateway) |

---

## 3. Design por task

Formato: **Baseline/defeito** · **Cenário** · **Falha no baseline** · **Referência** · **Alternativas aceitas** · **Armadilhas e notas para o vault**.

### T01
- **Baseline/defeito:** não há índice em `orders.customer_id`. `Order::where('customer_id', $id)->orderByDesc('placed_at')->paginate(20)` → a contagem e a página fazem Seq Scan.
- **Cenário:** nenhum extra. Âncoras `C-REG`, `C-VIP`, `C-WHALE-01`.
- **Falha no baseline:** AC1, AC2.
- **Referência:** migration `CREATE INDEX CONCURRENTLY` (com `$withinTransaction = false`) em `(customer_id, placed_at DESC)`.
- **Alternativas:** índice só em `customer_id` **passa** em AC1 e **falha** em AC2 para o whale (bitmap heap scan de 20 mil linhas). Isso é intencional e deve ser discutido em `tradeoffs.md`. `simplePaginate` não é aceito, porque o contrato (AC3) inclui `total`.
- **Notas:** discutir InnoDB (índice automático em FK), o custo de escrita e a visibility map para o index-only scan da contagem.

### T02
- **Baseline/defeito:** busca via `whereRaw('lower(email) = lower(?)')` com índice só na coluna crua. O cadastro valida `unique:customers,email` (sensível a caixa). Existem ~1.200 pares duplicados por caixa (`C-DUP-*`).
- **Cenário:** gera `crm-duplicates.csv` com 20 exemplos. O harness de cadastro concorrente usa os checkpoints `customers.create.1..3`.
- **Falha no baseline:** AC1, AC3, AC4.
- **Referência:** resolver os pares (manter o mais antigo como principal; mover pedidos e endereços do duplicado; registrar em `audit_logs` e numa tabela `customer_merges`; marcar o duplicado com `deleted_at` e e-mail `merged+<id>@invalid`). Depois, `UNIQUE INDEX ON customers (lower(email))`. A busca passa a usar `lower(email) = lower(?)`. O cadastro captura `UniqueConstraintViolationException` e devolve 422, com validação `Rule::unique` sobre `lower(email)`.
- **Alternativas:** coluna `citext` + UNIQUE; collation ICU não determinística (discutir o `LIKE` e o custo); normalizar na escrita com coluna `email_normalized` + UNIQUE.
- **Notas:** o AC5 aceita merge ou arquivamento, desde que a contagem de clientes + registros de merge/arquivo seja a original.

### T03
- **Baseline/defeito:** existem apenas `(status)`, `(placed_at)` e `(placed_at, status)`. A query é `status='paid' AND warehouse_id=? AND placed_at >= ? ORDER BY placed_at LIMIT 100`. Com a janela de 180 dias, o planner varre o índice de `placed_at` e filtra no heap.
- **Cenário:** parâmetros (`WH-SP1`, `WH-MG1`) × (`LAB_CLOCK-7d`, `LAB_CLOCK-180d`).
- **Falha no baseline:** AC1, AC2 (na janela longa).
- **Referência:** índice parcial `(warehouse_id, placed_at) WHERE status = 'paid'`, e remoção de `(status)` (seletividade inútil), com a justificativa por `pg_stats`.
- **Alternativas:** `(status, warehouse_id, placed_at)` completo. `(warehouse_id, status, placed_at)` também passa. `(placed_at, warehouse_id, status)` **não** passa no AC2 da janela longa.
- **Notas:** discutir planos genéricos com parâmetros (prepared statements) × índice parcial, e o impacto de o status `paid` ser transitório (o índice parcial fica pequeno).

### T04
- **Baseline/defeito:** o `scenario.sql` da T04 cria os índices "de relatório" abaixo, além dos globais:
  - `order_items`: `order_items_order_id_idx2 (order_id)` (duplicado do global), `(order_id, variant_id)`, `(product_id)`, `(created_at)`, `(unit_price_cents)`, `(total_cents)`
  - `payment_events`: `(payment_id, occurred_at)`, `(type)`, `(occurred_at)`, `(created_at)`, `GIN(payload)`
  - `order_status_history`: `(order_id, changed_at)`, `(to_status)`, `(changed_at)`
  - `orders`: `(channel)`, `(channel, placed_at)`, `(currency)`, `(updated_at)`, `(total_cents)`
  - O workload de leitura usa: itens por `order_id`; eventos por `payment_id` ordenados por `occurred_at`; histórico por `order_id` ordenado por `changed_at`; relatório mensal por `channel` + `placed_at`; relatório mensal de vendas por variante (`order_items.variant_id`, executado **uma única vez** no workload, com `idx_scan` baixo mas > 0).
- **Cenário:** gera o arquivo NDJSON (100 mil pedidos no MEDIUM). `lab:workload t04` executa o workload.
- **Falha no baseline:** AC1.
- **Referência (decisão por índice):** remover o duplicado de `order_id`; remover `order_items(order_id)` **ou** `(order_id, variant_id)` (mantendo um que sirva à FK e ao workload); remover `(product_id)`, `(created_at)`, `(unit_price_cents)`, `(total_cents)`, `payment_events(payment_id)` (prefixo de `(payment_id, occurred_at)`), `(type)`, `(created_at)`, `GIN(payload)`, `order_status_history(order_id)` (prefixo), `(to_status)`, `(changed_at)`, `orders(channel)` (prefixo), `(currency)`, `(updated_at)`, `(total_cents)`. **Manter** `order_items(variant_id)` (uso mensal raro, a armadilha do `idx_scan` baixo) e todos os UNIQUE/PK.
- **Alternativas:** qualquer conjunto que passe nos AC1–AC4.
- **Notas:** discutir `pg_stat_reset`, réplicas, `DROP INDEX CONCURRENTLY` e HOT updates.

### T05
- **Baseline/defeito:** `customers JOIN addresses JOIN orders JOIN payments WHERE payments.status='captured' AND orders.placed_at BETWEEN ...` com `GROUP BY customer`. Resultado: fan-out por endereços e por tentativas de pagamento, e clientes sem pedido somem (INNER + WHERE).
- **Cenário:** três combinações de parâmetros com golden no SMALL; uma no MEDIUM.
- **Falha no baseline:** AC1, AC2, AC3, AC5 (o teste do aluno precisa falhar no baseline).
- **Referência:** CTE que agrega `orders` por `customer_id` (status pago no período, sem join com `payments`); `customers` filtrado por segmento com `LEFT JOIN` no agregado e `LEFT JOIN` no endereço padrão de entrega (`is_default AND type='shipping'`); `COALESCE` para 0.
- **Alternativas:** subqueries correlacionadas escalares, se o custo ficar ≤ 100% do baseline (costuma ficar, com o índice de `customer_id`; sem ele, provavelmente não).
- **Notas:** a definição de "pago" pelo status do pedido, não pela tabela de pagamentos, faz parte do contrato do enunciado.

### T06
- **Baseline/defeito:** `WHERE to_char(o.placed_at, 'YYYY-MM') = :month` com sessão em UTC (fronteira errada em 3 h) e `status IN (paid, picking, shipped, delivered, refunded)` (inclui `refunded`, divergindo do ERP). Hash join com `order_items` inteiro.
- **Cenário:** meses de referência 2026-03, 2026-04, 2026-05, com pedidos plantados na fronteira. `STEP=new-sales` insere 500 pedidos pagos em 2026-06.
- **Falha no baseline:** AC1, AC2, AC3.
- **Referência:** tabela de resumo `sales_daily_category (day_local, category_id, revenue_cents, orders_count)` alimentada por job/comando (`reports:refresh-sales --since=`) e atualizada incrementalmente pelo evento `OrderPaid` (ou a cada N minutos). O relatório soma os dias do mês local. O filtro de datas usa um intervalo semiaberto em `America/Sao_Paulo`.
- **Alternativas:** (a) materialized view com `REFRESH ... CONCURRENTLY`, declarada como `refresh_command`; (b) desnormalizar `placed_at` e `status` em `order_items` com índice `(placed_at) INCLUDE (product_id, total_cents)`; (c) particionamento mensal (aceito se passar, mas é caro de implementar). **Só a correção de sargabilidade não passa no AC2** (o hash join lê `order_items` inteiro). Registrar isso em `tradeoffs.md`.
- **Notas:** discutir o frescor, a reconstrução do histórico e o custo de manutenção.

### T07
- **Baseline/defeito:** `Order::orderByDesc('placed_at')->paginate($perPage)` (OFFSET + `COUNT(*)`, sem desempate). O `orders:export` itera por `page`.
- **Cenário:** o harness `insert-while-paging` insere 5 pedidos com `placed_at = LAB_CLOCK` entre cada página no SMALL. Os ties por segundo também geram instabilidade sem inserções.
- **Falha no baseline:** AC1, AC2, AC4.
- **Referência:** `cursorPaginate` ordenado por `placed_at DESC, id DESC`, com índice `(placed_at DESC, id DESC)`; total aproximado via `pg_class.reltuples` (ou omitido, conforme o contrato); `orders:export` por cursor. O template de `contract.md` tem front matter `cursor_format: laravel | command`, e `command` aponta para um comando do aluno que gera o cursor a partir de `(placed_at, id)`.
- **Alternativas:** keyset manual com `(placed_at, id) < (?, ?)` (row comparison). Cursor opaco próprio.
- **Notas:** discutir o "ir para a página N", a busca por data como alternativa de UX e o total estimado.

### T08
- **Baseline/defeito:** `legacy`: `whereNotIn('id', Order::select('customer_id')->where('placed_at', '>=', $cut))` → NOT IN com NULL (pedidos de convidado) → vazio. `v2`: loop em PHP por cliente com `exists()` (sem índice em `customer_id`, ou seja, Seq Scan por cliente). O contrato: clientes `active`, não excluídos, com ≥ 1 pedido na vida e nenhum nos últimos 180 dias.
- **Cenário:** nenhum extra.
- **Falha no baseline:** AC1 (legacy), AC2 e AC3 (v2).
- **Referência:** `EXISTS (pedido antigo) AND NOT EXISTS (pedido recente)` em uma query (via `whereHas`/`whereDoesntHave` ou SQL). O PG faz Hash Semi/Anti Join.
- **Alternativas:** `LEFT JOIN ... IS NULL`; `NOT IN` com `whereNotNull('customer_id')` na subquery (hashed SubPlan: aceito se o plano não fizer SubPlan por linha).
- **Notas:** comparar com o MySQL 8 (antijoin desde a 8.0.17).

### T09
- **Baseline/defeito:** índices só de coluna única em `legacy_catalog_items`. As queries `WHERE category_id=? AND is_active=1 ORDER BY price_cents, id LIMIT 24 OFFSET ?` e `ORDER BY created_at DESC, id DESC` fazem filesort da categoria inteira (`CAT-BIG` ≈ 300 mil linhas no MEDIUM).
- **Cenário:** carrega o MySQL `bp_t09` a partir dos CSVs.
- **Falha no baseline:** AC1, AC2.
- **Referência:** `(category_id, is_active, price_cents)` e `(category_id, is_active, created_at)`. O PK é implícito no InnoDB e dá o desempate por `id`. Deferred join opcional para `SELECT *`.
- **Alternativas:** incluir `id` explicitamente no índice; índices de cobertura.
- **Notas:** discutir a coluna `is_active` de baixa cardinalidade no meio do índice (igualdade, portanto ok) e o custo da sincronização noturna de preços.

### T10
- **Baseline/defeito:** o Resource retorna `parent::toArray()` com as relações carregadas de forma lazy. `Order::$appends = ['customer_name', 'latest_status']` (accessors que consultam). `Product::$with = ['category']`. Colunas pesadas (`description`, `payload`) serializadas. Não há `preventLazyLoading`.
- **Cenário:** nenhum extra.
- **Falha no baseline:** AC1, AC2, AC4.
- **Referência:** `with([...])` com `select` restrito; relação `latestStatus` via `latestOfMany`; Resource explícito com `whenLoaded`; remover os `$appends` e o `$with` padrão; `Model::preventLazyLoading(! app()->isProduction())` no `AppServiceProvider`.
- **Alternativas:** `Model::shouldBeStrict()`.
- **Notas:** medir o payload e o custo da serialização.

### T11
- **Baseline/defeito:** `whereHas('variants.inventory', fn => whereRaw('on_hand - reserved > 0'))`, `withCount`/`withAvg` de reviews aprovadas e `orderByDesc('reviews_avg_rating')`. `category` inclui descendentes (via lista de IDs). `product_reviews` só tem `(product_id)`. O `paginate` repete o `whereHas` na contagem.
- **Cenário:** `STEP=review-activity` cria, aprova, rejeita e remove 200 reviews e zera o estoque de 30 produtos.
- **Falha no baseline:** AC2.
- **Referência:** colunas `rating_avg`, `reviews_count` e `in_stock` em `products`, mantidas por listeners/jobs de `ReviewApproved`, `ReviewRejected`, `ReviewDeleted` e `InventoryChanged` (com recálculo por produto, não incremento cego). Índice `(category_id, in_stock, rating_avg DESC, id)`. Comando de backfill.
- **Alternativas:** tabela `product_stats` 1:1 mantida da mesma forma. **Só índices** (`product_reviews(product_id, status) INCLUDE (rating)`) melhoram mas **não** passam no AC2: o agregado ainda é calculado para a categoria inteira antes da ordenação. Registrar em `tradeoffs.md`.
- **Notas:** discutir a consistência eventual dos contadores e a reconciliação periódica.

### T12
- **Baseline/defeito:** `--strategy=all`: `Customer::all()` + `$customer->orders` por cliente + `DB::enableQueryLog()` deixado no comando. `--strategy=chunk`: `Customer::where(eligible)->chunk(1000, ...)` atualizando `ltv_calculated_at`, o que tira os clientes do filtro e pula páginas.
- **Cenário:** neutraliza `orders(customer_id)`. Marca 60% dos clientes com pedido como elegíveis.
- **Falha no baseline:** AC1 (chunk), AC2 (all), AC3.
- **Referência:** um único `UPDATE customers c SET lifetime_value_cents = coalesce(a.ltv, 0), ltv_calculated_at = :now FROM (...) a` com `LEFT JOIN` via subquery, em lotes por faixa de `id` (`chunkById` sobre os IDs elegíveis + um update set-based por lote). Sem query log.
- **Alternativas:** `lazyById` + agregação por lote em uma query + `upsert` em lote.
- **Notas:** discutir locks de update em lote e a retomada por `id`.

### T13
- **Baseline/defeito:** `DB::transaction` envolve tudo: criação do pedido, reserva, `Gateway::authorize` (HTTP), `Notify` (HTTP), render da nota (CPU, ~300 ms), `Erp::export` (HTTP, 1,5 s) e recomendações (SQL pesado). `ProcessRecommendations::dispatch()` dentro da transação, com `after_commit = false`.
- **Cenário:** `erp-down` (ERP `down` na fase 1); `throw` em `checkout.place.5` para o AC3.
- **Falha no baseline:** AC1, AC2, AC3, AC4, AC5.
- **Referência:** transação curta (pedido `pending_payment` + reserva) → commit → `authorize` fora da transação, com `Idempotency-Key = order uuid` → transação curta marca `authorized` e grava o outbox/dispara jobs `afterCommit` (e-mail, nota, ERP, recomendações). Em falha do gateway, libera a reserva e cancela. Se algo falhar depois de autorizar, compensação (`void`).
- **Alternativas:** `ShouldQueueAfterCommit`; `after_commit = true` na conexão; outbox table + relay.
- **Notas:** discutir UX de estado intermediário e o "ghost authorization".

### T14
- **Baseline/defeito:** sem cache; 14 queries (produto, 3 de breadcrumb, variantes, estoque por variante (N+1), agregado de reviews, relacionados, regras de preço). O preço depende de `?currency=BRL|USD`. **Armadilha:** chave sem a moeda.
- **Cenário:** k6 Zipf sobre `SKU-HOT-*` + cauda. O check pede o mesmo slug nas duas moedas.
- **Falha no baseline:** AC1, AC2.
- **Referência:** `Cache::remember("catalog:product:v1:{$slug}:{$currency}", ttl, ...)` com o payload estável. Disponibilidade calculada à parte (1 query agregada), sem cache ou com TTL curto. TTL de 10–30 min com jitter.
- **Alternativas:** cache por fragmento (produto, variantes, reviews), desde que QPR ≤ 2.
- **Notas:** discutir o tamanho dos valores e a serialização (igbinary).

### T15
- **Baseline/defeito:** payload do produto (inclui preço e estoque) cacheado por 3.600 s; disponibilidade cacheada por 600 s; `PATCH` de preço não invalida; o checkout usa a disponibilidade cacheada para decidir.
- **Cenário:** `price-update-during-recompute` (pausa em `catalog.product.load.2` = depois de ler o banco, antes do `put`); avanço de relógio para o AC5.
- **Falha no baseline:** AC1, AC2, AC3, AC5.
- **Referência:** versionamento de chave por produto (`catalog:product:{id}:ver`, incrementado no `PriceChanged` depois do commit; a leitura usa a versão lida no início); disponibilidade com TTL ≤ 30 s ou sem cache; checkout decide com leitura/lock no banco.
- **Alternativas:** delete depois do commit + "set only if version unchanged" (Lua/CAS); tags com cuidado (discutir as limitações).
- **Notas:** discutir a corrida delete × recompute e o write-through.

### T16
- **Baseline/defeito:** `Cache::remember('storefront:home', 300, fn => BestSellers::last7Days() + ...)`, sem lock nem fallback, sem header `X-Content-Age`. O contador `home.recompute` é instrumentação do lab dentro de `BestSellers::last7Days()`.
- **Cenário:** `expiry-200` (a chegada é contada em `storefront.home.1` e a recomputação é pausada em `storefront.home.2` até 200 chegadas ou 5 s); `crash` em `storefront.home.3`; cold start.
- **Falha no baseline:** AC1, AC3, AC4, AC5.
- **Referência:** `Cache::flexible('storefront:home', [300, 600], ...)` (SWR) com lock para a recomputação. Fallback do conteúdo anterior guardado em chave "last-good" sem TTL. Cold start: `Cache::lock(...)->block(10)` e, esgotado o prazo, conteúdo mínimo estático. Lock com TTL de 30 s (escalado). O header `X-Content-Age` vem do timestamp gravado junto do valor.
- **Alternativas:** early expiration probabilística + lock; job de pre-warm + lock + last-good.
- **Notas:** discutir o TTL do lock × a duração da recomputação e o fencing.

### T17
- **Baseline/defeito:** middleware `SimpleThrottle`: `Cache::get` + `Cache::put(count + 1, 60)` (não atômico, e reestende a janela a cada put); chave pelo header `X-Forwarded-For` quando presente; `trustProxies(at: '*')`; `429` sem `Retry-After`; cupom inexistente responde antes de contar.
- **Cenário:** `parallel-100`, `spoofed-ip`, `abusive-token`.
- **Falha no baseline:** AC1, AC2, AC3, AC5.
- **Referência:** `RateLimiter::for('coupon-validate', fn($r) => [Limit::perMinute(10)->by('c:'.$r->user()->id), Limit::perMinute(30)->by('ip:'.$r->ip())])` + `throttle:coupon-validate`; `trustProxies(at: <CIDR da rede do nginx>)`; `RateLimiter::for('search', ...by(token id))`; contar antes de validar.
- **Alternativas:** `Redis::throttle`, script Lua de janela deslizante.
- **Notas:** discutir o brute force (códigos longos, lockout, CAPTCHA) e o 429 × 403.

### T18
- **Baseline/defeito:** `ExportOrderToErp` por pedido na fila `default`, com N+1 (~8 queries) e `POST /erp/v1/orders` unitário (200 ms no mock); `CapturePayment` também em `default`; Horizon com 1 supervisor e `maxProcesses = 1`; o ERP responde `409` para pedido já existente e o job trata `409` como erro (retry → falha).
- **Cenário:** enfileira 120 mil (MEDIUM) ou 12 mil (SMALL), depois 20 jobs de pagamento; `restart-mid-drain` mata os workers no meio.
- **Falha no baseline:** AC1, AC2, AC3, AC4.
- **Referência:** filas separadas (`payments` com prioridade: supervisor dedicado ou `--queue=payments,erp`); job de lote (100 pedidos, `POST /orders:batch`) com eager loading; `erp_exports` como controle (`status`) e `409` tratado como sucesso idempotente; comando para reempacotar o backlog em lotes; 3–4 workers para `erp`, respeitando o limite do banco.
- **Alternativas:** `Bus::batch` de lotes; Horizon `balance = auto` com prioridades.
- **Notas:** discutir o dimensionamento de workers × conexões × limite do parceiro.

### T19
- **Baseline/defeito:** conexão redis `retry_after = 10` (escalado); job `timeout = 60`, `tries = 5`, sem backoff; `Http` com timeout padrão (30 s); sem `Idempotency-Key`; status `processing` no início e nunca finalizado em falha (sem `failed()`); `4xx` de recusa lança exceção genérica (retry).
- **Cenário:** mock `capture` com `slow` (15 s), `flaky` (500, 500, 200), `declined` (402), `timeout` (`hang` 120 s).
- **Falha no baseline:** AC1, AC2, AC3, AC4.
- **Referência:** timeout HTTP 8 s < job `timeout` 12 s < `retry_after` 30 s (escalados); `backoff = [2, 6, 18]` + jitter; `Idempotency-Key = payment uuid` na captura; recusa `4xx` → `$this->fail()` + status `failed` + `payment_event`; `failed()` marca estado terminal; `maxExceptions`.
- **Alternativas:** `ShouldBeUnique` + consulta de estado no gateway antes de capturar (`GET /payments/{id}`).
- **Notas:** discutir o at-least-once, a duplicidade no parceiro e a reconciliação.

### T20
- **Baseline/defeito:** `FulfillPaidOrder` sem transação: (1) `status = picking` + histórico; (2) para cada reserva, `on_hand -= q`, `reserved -= q`, reserva `consumed` (sem checar o status atual); (3) dispatch da exportação ERP; (4) notificação (sem idempotency key); (5) `fulfillment_started_at`. Checkpoints `fulfillment.run.1..6` entre os passos. Supervisor com `stopwaitsecs = 10`.
- **Cenário:** `crash-matrix` (SIGKILL em cada checkpoint + reentrega); notificação lenta (12 s) + SIGTERM para o AC3.
- **Falha no baseline:** AC1, AC2, AC3.
- **Referência:** passos de banco numa transação com guarda (`UPDATE orders SET status = 'picking' WHERE id = ? AND status = 'paid'`; se 0 linhas, o trabalho já foi feito); reservas consumidas condicionalmente; notificação e ERP via jobs `afterCommit` com `Idempotency-Key = order uuid + evento`; `stopwaitsecs` > timeout do job.
- **Alternativas:** outbox table + relay.
- **Notas:** discutir SIGTERM × SIGKILL e o `horizon:terminate` no deploy.

### T21
- **Baseline/defeito:** publisher sem publisher confirms (exceção engolida → evento perdido); consumidor sem `basic_qos` (prefetch ilimitado); processamento não idempotente (`revenue = revenue + x`), commit e depois ack (crash entre os dois → duplica); JSON inválido → `nack(requeue=True)` (loop infinito); fila sem DLX.
- **Cenário:** 5.000 eventos + 5 mensagens malformadas; `crash` em `consumer.handle.2` (depois do commit, antes do ack) ×2 e em `consumer.handle.1` ×1; broker recusando publicações por 5 s (`rabbitmqctl` / policy de `max-length` com `reject-publish` temporária).
- **Falha no baseline:** AC1, AC2, AC3, AC4.
- **Referência:** tabela `processed_events(event_id PK)` na mesma transação do agregado; ack depois do commit; `basic_qos(prefetch_count = 50)`; `nack(requeue=False)` para mensagens inválidas + DLX `analytics.dlx` → `analytics.sales.dlq` (em `definitions.json`); publisher com confirms + outbox (`event_outbox`) e relay com retry.
- **Alternativas:** quorum queue com `delivery-limit` + DLX; upsert com recomputação do dia (idempotente por construção).
- **Notas:** ADR Redis × RabbitMQ (fan-out, roteamento, DLX nativo, consumidores não-PHP × simplicidade e Horizon).

### T22
- **Baseline/defeito:** `exists()` e depois `create()` (check-then-insert); processamento síncrono (payment_event + atualização de status "cega", sem ordem + notificação lenta de 3 s); sem UNIQUE; 0,3% de duplicatas históricas. Checkpoints `webhook.gateway.1..4` (o 2 fica entre o exists e o create).
- **Cenário:** `parallel-duplicate`, `twenty-deliveries`, `out-of-order`.
- **Falha no baseline:** AC1, AC2, AC3, AC4, AC5.
- **Referência:** migration que move as duplicatas históricas para `webhook_events_duplicates` e `payment_events_duplicates` (mantendo o primeiro) e cria `UNIQUE(provider, external_id)` e `UNIQUE(provider_event_id)`; `insertOrIgnore`/`ON CONFLICT DO NOTHING RETURNING id`; resposta 200 imediata; job `ProcessGatewayEvent` `afterCommit` que aplica transição monotônica (rank) com `UPDATE ... WHERE rank(status) < rank(:new)`; notificação com `Idempotency-Key = event_id`.
- **Alternativas:** `idempotency_keys` com lock; processamento síncrono rápido (sem a notificação na request).
- **Notas:** discutir o evento de um pagamento ainda desconhecido (guardar e reprocessar).

### T23
- **Baseline/defeito:** lê o cupom; `if ($coupon->used_count < $coupon->usage_limit)`; verifica o resgate do cliente com `exists()`; `create` do redemption; `$coupon->used_count++; $coupon->save()`, dentro de `DB::transaction` (READ COMMITTED). Checkpoints `coupon.redeem.1..4`.
- **Cenário:** `stress-300` (semente fixa); `same-customer-twice`.
- **Falha no baseline:** AC1, AC2, AC3.
- **Referência:** `UPDATE coupons SET used_count = used_count + 1 WHERE id = ? AND used_count < usage_limit` (1 linha afetada = sucesso) + `UNIQUE(coupon_id, customer_id)` em `coupon_redemptions` + `CHECK (used_count <= usage_limit)`, na mesma transação; `UniqueConstraintViolationException` → `coupon_already_used` (409).
- **Alternativas:** `lockForUpdate` no cupom; SERIALIZABLE + retry (≤ 3) para `40001`.
- **Notas:** discutir a hot row e o sharding de contador (conceitual).

### T24
- **Baseline/defeito:** `InventoryReservationService`: lê `on_hand - reserved`, compara e faz `reserved += q; save()` (lost update). `ImportMarketplaceOrder`: `Cache::lock("sku:{$sku}", 5)->get()`, chama o marketplace (ack lento) dentro do lock e usa o mesmo serviço; o checkout não usa esse lock. Sem CHECK.
- **Cenário:** `last-item-two-channels` (4 intercalações); `redis-lock-expiry` (o detentor pausa 8 s > TTL de 5 s); `stress-500`; bloqueio prolongado para o AC5.
- **Falha no baseline:** AC1, AC2, AC3, AC4, AC5.
- **Referência:** `UPDATE inventory SET reserved = reserved + :q WHERE variant_id = ? AND warehouse_id = ? AND on_hand - reserved >= :q` (verifica as linhas afetadas); `CHECK (reserved >= 0 AND reserved <= on_hand)`; `SET LOCAL lock_timeout = '2s'`; o importador usa o mesmo serviço, sem depender do lock Redis (ou mantém o lock só como otimização); perdedor do marketplace → `POST /mkt/v1/orders/{ref}/reject`.
- **Alternativas:** `lockForUpdate` + verificação; fencing token com versão (`inventory.version`).
- **Notas:** discutir por que o lock Redis não é garantia (TTL, pausas de GC/rede) e o Redlock (conceitual).

### T25
- **Baseline/defeito:** o checkout faz `lockForUpdate` item a item na ordem do carrinho; `inventory:rebalance` trava origem → destino, em ordem decrescente de `variant_id`. Sem retry.
- **Cenário:** `opposite-order` (2 intercalações com checkpoints); `stress-200`; `throw` de `40P01` na primeira tentativa (AC3).
- **Falha no baseline:** AC1, AC2, AC3.
- **Referência:** ordenar as linhas a travar por `(variant_id, warehouse_id)` nos dois fluxos (ou um único `SELECT ... WHERE (variant_id, warehouse_id) IN (...) ORDER BY ... FOR UPDATE`); `DB::transaction(fn, 3)`; transações curtas.
- **Alternativas:** updates atômicos condicionais em ordem determinística (sem `SELECT FOR UPDATE`).
- **Notas:** variante MySQL: gap/next-key locks em `inventory_reservations` com REPEATABLE READ; discutir o READ COMMITTED no MySQL.

### T26
- **Baseline/defeito:** um job por alteração de estoque, com o valor do estoque no payload (a ordem de execução não é garantida → sobrescrita antiga); `Http::retry(3, 0)` para qualquer erro; timeout padrão (30 s); sem `If-Match` nem `Idempotency-Key`; `409` tratado como erro; sem rate limit; `marketplace:reconcile` vazio.
- **Cenário:** `burst` (5.000 alterações/500 listings); `chaos`; `drift` (altera o estado do mock diretamente).
- **Falha no baseline:** AC1, AC2, AC3, AC4, AC5.
- **Referência:** job `ShouldBeUnique` por listing (`uniqueFor` curto) que lê o estoque **atual** na execução; middleware `RateLimited`/`Redis::throttle('mkt')->allow(10)->every(1)`; `release($retryAfter)` em `429`; timeouts `connectTimeout(2)->timeout(5)`; backoff exponencial com jitter em `5xx`/timeout; em `409`, `GET` da versão e repetição com `If-Match`; `ThrottlesExceptions` como circuit breaker; `reconcile` em lotes via `GET` (respeitando o limite) com correção idempotente.
- **Alternativas:** tabela `marketplace_syncs` como fila de coalescência (dirty flag) + worker periódico em lote (`/listings:batch`).
- **Notas:** discutir push × pull e a frequência de reconciliação.

### T27
- **Baseline/defeito:** verificação `hash_hmac('sha256', json_encode($request->all()), $secret) == $header`, pulada se o header estiver ausente; sem timestamp; `config('services.marketplace.webhook_secret', 'bp-dev-secret')`; pedido criado com os valores do payload; `GatewayClient` registra request/response completos (headers com `Authorization`) em erro; `.env.example` versionado com um "segredo" de lab e presente no histórico do baseline.
- **Cenário:** `battery` (12 casos); segredo comprometido para o AC4.
- **Tabela de status esperados** (publicada no README da task pelo Codex): válida → 202; assinatura inválida → 401; corpo alterado → 401; JSON reformatado → 401; header ausente → 401; timestamp > 5 min no passado → 401; timestamp > 5 min no futuro → 401; replay dentro da janela → 200 sem reprocessar; segredo anterior dentro da janela de rotação → 202; segredo anterior depois da janela → 401; tipo de evento desconhecido → 202 (ignorado); segredo não configurado → 503.
- **Falha no baseline:** AC1, AC2, AC3, AC4.
- **Referência:** parse de `t=`/`v1=`; HMAC sobre `t + "." + $request->getContent()`; `hash_equals` contra cada segredo ativo (`services.marketplace.webhook_secrets` com `valid_until`); tolerância de 300 s; nonce `SET NX EX 600` com o id da assinatura; `GET /mkt/v1/orders/{ref}` para os valores; middleware de log que remove `Authorization`/chaves e processor Monolog de redação; sem fallback de segredo (falha fechada); `.env.example` com placeholder; nota de rotação.
- **Alternativas:** middleware de assinatura reutilizável.
- **Notas:** discutir segredos no histórico Git (rotacionar, não reescrever história publicada) e segredos em `failed_jobs`/Horizon (`ShouldBeEncrypted`).

### T28
- **Baseline/defeito:** logs em texto; sem request ID; `/metrics` inexistente; sem OTel. Causas plantadas:
  1. `GET /api/me/orders/{uuid}` chama `LoyaltyService::summary($customer)`, que carrega todos os pedidos com itens do cliente (lento só para `segment = wholesale`) → causa `{route: "GET /api/me/orders/{uuid}", dimension: "customer.segment", value: "wholesale", component: "db"}`;
  2. `POST /api/checkout` com `payment_method = boleto`: o mock do gateway atrasa 6 s → `{route: "POST /api/checkout", dimension: "payment.method", value: "boleto", component: "gateway"}`.
  - **Chamariz:** um relatório lento em rota fora do foco (não é causa).
- **Cenário:** neutralizações da §2; `lab:load t28` com mistura determinística (whales ≈ 3% das requisições de detalhe; boleto ≈ 8% dos checkouts).
- **Taxonomia (arquivo visível):** rotas do foco + 2 decoys; dimensões `customer.segment`, `customer.country`, `payment.method`, `order.channel`, `order.items_count_bucket`, `http.user_agent_family`; valores possíveis por dimensão; componentes `db`, `cache`, `gateway`, `erp`, `queue`, `cpu`.
- **Falha no baseline:** AC1, AC2, AC3, AC4, AC5.
- **Referência:** middleware de request ID (aceita/gera `X-Request-Id`), `Log::withContext`, formatter JSON; propagação via payload/middleware de job e header no `Http` client; `promphp/prometheus_client_php` com storage Redis e histogramas por rota nomeada; OTel SDK com spans manuais (HTTP, DB via `DB::listen`, `Http` client); heartbeat de worker em Redis via `Looping`/job agendado; exporter de profundidade de fila.
- **Notas:** o AC6 opcional pede corrigir a causa 1 (agregado SQL/cache do resumo) e mitigar a 2 (timeout + processamento assíncrono do boleto).

### T29
- **Baseline/defeito:** `Orders.vue` busca `per_page=5000` no `onMounted`; `v-for` em todas as linhas; `@input` → fetch por tecla, sem abort, aplicando cada resposta ao chegar; `import * as echarts` estático; `setInterval(1000)` para `/stats` sem `visibilitychange`; o endpoint retorna os objetos completos.
- **Cenário:** Playwright com `page.route` atrasando as respostas em ordem inversa.
- **Falha no baseline:** AC1, AC2, AC3, AC4, AC5.
- **Referência:** composable `useDebouncedSearch` (300 ms) + `AbortController`; paginação por cursor, 50 por página; Resource enxuto; virtualização (`@tanstack/vue-virtual`) ou paginação; `defineAsyncComponent(() => import('./RevenueChart.vue'))`; polling de 15 s com pausa em `document.hidden`.
- **Alternativas:** contador de sequência de requisição em vez do abort; paginação sem virtualização.

### T30 — release Flash Sale
- **Causas raiz plantadas (códigos da taxonomia):**
  1. `db.missing_index` @ `flash_sale_claims`: sem `(flash_sale_item_id, status)` nem `(flash_sale_item_id, customer_id)`; o cenário pré-popula 2 milhões de claims históricas; `count(*)` por claim.
  2. `cache.stampede` @ `GET /api/flash-sales/current`: `Cache::remember('flash:current', 10, ...)`, com o estoque restante calculado por `count(*)`.
  3. `concurrency.check_then_act` @ `POST /api/flash-sales/{id}/claim`: verifica o restante e o limite por cliente e depois insere.
  4. `queue.shared_priority` @ `SettleFlashSaleClaim`: fila `default` compartilhada com os pagamentos; supervisor `maxProcesses = 3`.
  5. `integration.no_timeout` + `idempotency.missing_key` @ `SettleFlashSaleClaim`: gateway sem timeout e captura sem `Idempotency-Key` (duplica sob retry).
  6. `frontend.polling` @ `FlashSaleBanner`: polling de 500 ms sem checar visibilidade.
  - **Decoys na taxonomia:** `db.lock_contention`, `cache.key_collision`, `frontend.bundle_size`, `tx.long_transaction`, `queue.worker_crash`, `redis.memory`, `http.nplus1`.
- **Cenário:** `black-friday` (k6: rampa 10 → 300 VUs, orçamento fixo); gateway com `slow` de 2 s para capturas.
- **Falha no baseline:** AC1, AC2, AC3, AC4, AC5, AC6.
- **Referência:** índices; vitrine cacheada com SWR/lock e estoque restante via contador atômico em Redis ou colunas `claimed_count` com update condicional; claim com `UPDATE flash_sale_items SET claimed = claimed + 1 WHERE id = ? AND claimed < stock_limit` + `UNIQUE(flash_sale_item_id, customer_id)` (limite 1) ou contagem por cliente com lock; fila `payments` prioritária; timeouts e `Idempotency-Key`; dispatch `afterCommit`; polling de 5 s com `visibilitychange`.
- **Mitigações esperadas na linha do tempo:** feature flag para desligar o banner/polling; limitar os claims por rate limit; escalar o supervisor de pagamentos.

---

## 4. Conteúdo do vault por task (checklist do implementador)

Para cada `TXX/`:
- `README.md`: resumo do defeito, solução de referência explicada passo a passo, por que funciona;
- `investigation.md`: caminho esperado de investigação (comandos, o que observar, como descartar hipóteses);
- `solution.patch`: diff contra `lab-baseline`;
- `queries.sql`: queries e DDL finais, quando aplicável;
- `results.md`: métricas medidas (baseline × solução) em SMALL, MEDIUM e, quando aplicável, LARGE, mais a calibração dos limites;
- `tradeoffs.md`: alternativas aceitas e rejeitadas, com os números;
- `alternatives/`: testes de mantenedor que provam que as alternativas aceitas passam.

E também:
- `_design/`: este documento;
- `_playtest/TXX.md`: relato de quem jogou a task sem ver a solução.
