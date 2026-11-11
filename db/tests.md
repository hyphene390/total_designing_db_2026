# Протокол для самопроверки

## Окружение

| Параметр | Значение |
|---|---|
| PostgreSQL version | PostgreSQL 15.15 (Debian 15.15-1.pgdg13+1), Docker-образ `postgres:15` |
| Дата проверки | 2026-11-11 |
| Схема | `khorunzhii_food` |
| Роль-аудитор | `inspector` |

Все проверки — под `inspector`, если не указано иное. Подключался через `psql -h localhost -U inspector -d audit` с паролем из `grants.sql`.

---

## A. Подготовка

### A.1. Восстановление бэкапа

Ожидается: без ошибок.
Факт: создал пустую базу `audit`, в ней схему `exts` с `uuid-ossp`, потом `pg_restore -d audit db/foodexpress_khorunzhii.backup` и `grants.sql`. Ошибок нет.
Вердикт: OK

### A.2. Переключение на inspector

```sql
SET ROLE inspector;
SET search_path TO khorunzhii_food, exts;
SELECT current_user;
```

Ожидается: `inspector`.
Факт: `inspector`.
Вердикт: OK

---

## B. FOOD-101: Структура схемы

### B.1. Схема существует

```sql
SELECT schema_name FROM information_schema.schemata
WHERE schema_name LIKE '%_food';
```

Ожидается: `<фамилия>_food`.
Факт: `khorunzhii_food`.
Вердикт: OK

### B.2. Схема `exts` с `uuid-ossp`

```sql
SELECT extname, extnamespace::regnamespace AS schema
FROM pg_extension WHERE extname = 'uuid-ossp';
```

Ожидается: `uuid-ossp`, схема `exts`.
Факт: `uuid-ossp | exts`.
Вердикт: OK

### B.3. Все 12 исходных таблиц + N после нормализации

```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'khorunzhii_food'
ORDER BY table_name;
```

Ожидается: `address`, `client`, `client_address`, `courier`, `courier_pay`, `order`, `order_structure`, `payment`, `product`, `product_category`, `restaurant`, `review` (12 + N штук).
Факт: 13 строк: все 12 таблиц и представление `how_much_money`. N = 0.
Вердикт: OK

### B.4. Все PK — `uuid`

```sql
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'khorunzhii_food'
  AND column_name LIKE '%_id'
  AND data_type != 'uuid';
```

Ожидается: пусто.
Факт: пусто.
Вердикт: OK

### B.5. Enum-типы

```sql
SELECT t.typname, array_agg(e.enumlabel ORDER BY e.enumsortorder) AS values
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'khorunzhii_food'
GROUP BY t.typname
ORDER BY t.typname;
```

Ожидается: 8 типов со значениями из constraints.md.
Факт: 8 типов, значения совпадают с `constraints.md`:

```
 courier_status     | {свободен,занят,на_доставке,уволен}
 order_pay_status   | {ожидает,оплачен,ошибка}
 order_status       | {создан,готовится,в_доставке,доставлен,отменён}
 payment_status     | {успех,ошибка,в_обработке}
 payment_type       | {карта,наличные,безнал}
 product_status     | {доступно,нет_в_наличии,архив}
 restaurant_status  | {активен,неактивен}
 review_entity_type | {блюдо,ресторан,заказ}
```

Вердикт: OK

### B.6. FK-ограничения

```sql
SELECT conname, conrelid::regclass AS tbl, confrelid::regclass AS ref
FROM pg_constraint
WHERE contype = 'f'
  AND connamespace = 'khorunzhii_food'::regnamespace
ORDER BY tbl, conname;
```

Ожидается: не менее 15 FK, все из erd.md.
Факт: 18 FK: 15 из ERD и 3 составных (`order_client_address_fk`, `payment_amount_matches_order`, `review_order_client_fk`).
Вердикт: OK

### B.7. Пароль — MD5

```sql
SELECT length(password) AS len, password
FROM client LIMIT 5;
```

Ожидается: `len = 32`, hex-строка.
Факт: 5 строк, у всех `len = 32`, например `f95c30d6eaaee4a2f569963de8b4e90f`.
Вердикт: OK

---

## C. FOOD-102: `insert_test_data(value)`

### C.1. Чистая схема

```sql
CALL erase_test_data();
```

Ожидается: без ошибок.
Факт: без ошибок.
Вердикт: OK

### C.2. Первый запуск

```sql
CALL insert_test_data(10);
```

Ожидается: без ошибок.
Факт: без ошибок, 108 мс.
Вердикт: OK

### C.3. Распределение строк (BR-11.7)

```sql
SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "order"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
ORDER BY tbl;
```

Ожидается: 10, 10, 10, 10, 50, 50, 50, 50, 50.
Факт: address 50, client 10, courier 10, order 50, payment 50, product 50, product_category 10, restaurant 10, review 50.
Вердикт: OK

### C.4. Адреса ресторанов vs клиентов (BR-11.7)

```sql
SELECT 'restaurant addresses' AS cat, count(*) FROM restaurant WHERE address_id IS NOT NULL
UNION ALL
SELECT 'total addresses', count(*) FROM address;
```

Ожидается: 10 ресторанных адресов, 50 всего → 40 клиентских.
Факт: 10 и 50, в `client_address` 40 строк.
Вердикт: OK

### C.5. Нет пустых строк (BR-11.3)

```sql
SELECT count(*) FROM client WHERE login = '' OR password = '' OR phone_number = '';
-- и аналогично для других varchar-полей с NOT NULL
```

Ожидается: 0.
Факт: 0. Так же проверил текстовые поля остальных таблиц, везде 0.
Вердикт: OK

### C.6. Нет NULL там, где запрещено (BR-11.3)

```sql
SELECT count(*) FROM "order" WHERE client_id IS NULL OR restaurant_id IS NULL
  OR courier_id IS NULL OR address_id IS NULL OR total_amount IS NULL;
-- и аналогично для других NOT NULL полей
```

Ожидается: 0.
Факт: 0. Уволенных без даты увольнения и доставленных заказов без времени доставки тоже 0.
Вердикт: OK

### C.7. Минимум один активный курьер (BR-6.6)

```sql
SELECT count(*) FROM courier WHERE status != 'уволен';
```

Ожидается: `>= 1`.
Факт: 9.
Вердикт: OK

### C.8. `courier_pay` консистентен с правилами (BR-10.2)

```sql
SELECT cp.year, cp.month, cp.courier_id, cp.amount, cp.coefficient_used,
       round(coalesce((
           SELECT sum(o.commission)
           FROM "order" o
           WHERE o.courier_id = cp.courier_id
             AND o.status = 'доставлен'
             AND extract(year  from o.order_timestamp) = cp.year
             AND extract(month from o.order_timestamp) = cp.month
       ), 0) * cp.coefficient_used, 2) AS expected_amount
FROM courier_pay cp
LIMIT 20;
```

Ожидается: `amount = expected_amount` в каждой строке.
Факт: во всех 20 строках совпадает (например 81.00 = 81.00, 24.90 = 24.90, у курьеров без доставок 0.00 = 0.00). Без `LIMIT` по всем 60 строкам тоже совпадает. Выплаты за 2026-06 ... 2026-11, по 10 курьерам за 6 месяцев. Коэффициент у всех 0.1: при `value = 10` больше 150 доставок в месяц ни у кого нет.
Вердикт: OK

### C.9. Повторный вызов не ломает

```sql
DO $$
BEGIN
    FOR i IN 1..10 LOOP
        CALL insert_test_data(10);
    END LOOP;
END $$;
```

Ожидается: без ошибок, данные добавляются или заменяются (по решению студента, задокументированному в constraints.md).
Факт: без ошибок, 1 с. Данные добавляются: стало 110 клиентов, 550 заказов, 660 строк `courier_pay`.
Вердикт: OK

---

## D. Проверки бизнес-правил на сгенерированных данных

Проверки D выполнял на данных после C.9 (110 клиентов, 550 заказов).

### D.1. Все FK валидны (нет orphans)

```sql
SELECT 'order_structure → order' AS fk, count(*) AS orphans
FROM order_structure os
LEFT JOIN "order" o ON os.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'order_structure → product', count(*)
FROM order_structure os
LEFT JOIN product p ON os.product_id = p.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'payment → order', count(*)
FROM payment pmt
LEFT JOIN "order" o ON pmt.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'review → order', count(*)
FROM review r
LEFT JOIN "order" o ON r.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'courier_pay → courier', count(*)
FROM courier_pay cp
LEFT JOIN courier c ON cp.courier_id = c.courier_id
WHERE c.courier_id IS NULL
UNION ALL
SELECT 'client_address → client', count(*)
FROM client_address ca
LEFT JOIN client c ON ca.client_id = c.client_id
WHERE c.client_id IS NULL
UNION ALL
SELECT 'client_address → address', count(*)
FROM client_address ca
LEFT JOIN address a ON ca.address_id = a.address_id
WHERE a.address_id IS NULL;
```

Ожидается: все 0.
Факт: все 7 строк 0.
Вердикт: OK

### D.2. Минимальная сумма заказа (BR-1.8)

```sql
SELECT count(*) FROM "order" WHERE total_amount < 1000;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.3. Комиссия = 10% (BR-1.4)

```sql
SELECT count(*) FROM "order" WHERE round(order_amount * 0.10, 2) != commission;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.4. `total_amount = order_amount + commission`

```sql
SELECT count(*) FROM "order"
WHERE round(order_amount + commission, 2) != total_amount;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.5. Дата доставки не раньше создания (BR-7.13)

```sql
SELECT count(*) FROM "order"
WHERE delivery_timestamp IS NOT NULL AND delivery_timestamp < order_timestamp;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.6. Адрес доставки принадлежит клиенту (BR-7.4)

```sql
SELECT count(*) FROM "order" o
LEFT JOIN client_address ca
  ON ca.client_id = o.client_id AND ca.address_id = o.address_id
WHERE ca.client_id IS NULL;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.7. Все блюда в заказе из одного ресторана (BR-7.3)

```sql
SELECT count(DISTINCT os.order_id)
FROM order_structure os
JOIN "order" o ON os.order_id = o.order_id
JOIN product p ON os.product_id = p.product_id
WHERE p.restaurant_id != o.restaurant_id;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.8. Ровно одна успешная оплата на заказ (BR-8.1)

```sql
SELECT order_id, count(*) AS cnt
FROM payment
WHERE status = 'успех'
GROUP BY order_id
HAVING count(*) != 1;
```

Ожидается: пусто.
Факт: пусто.
Вердикт: OK

### D.9. Сумма оплаты = `total_amount` заказа (BR-8.4)

```sql
SELECT count(*) FROM payment p
JOIN "order" o ON p.order_id = o.order_id
WHERE p.amount != o.total_amount;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.10. Нет дубликатов в `client_address` (BR-2.5)

```sql
SELECT client_id, address_id, count(*)
FROM client_address
GROUP BY client_id, address_id
HAVING count(*) > 1;
```

Ожидается: пусто.
Факт: пусто.
Вердикт: OK

### D.11. Нет дубликатов в `order_structure` (BR-7.16)

```sql
SELECT order_id, product_id, count(*)
FROM order_structure
GROUP BY order_id, product_id
HAVING count(*) > 1;
```

Ожидается: пусто.
Факт: пусто.
Вердикт: OK

### D.12. `work_end > work_start` (BR-4.4)

```sql
SELECT count(*) FROM restaurant WHERE work_end <= work_start;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.13. `dismissal_date >= hire_date` (BR-6.3)

```sql
SELECT count(*) FROM courier
WHERE dismissal_date IS NOT NULL AND dismissal_date < hire_date;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.14. Рейтинг блюд/ресторанов соответствует отзывам (BR-9.6)

```sql
-- product.rating = AVG(review.rating) по отзывам на блюдо
SELECT p.product_id, p.rating,
       (SELECT round(avg(r.rating), 2) FROM review r
        WHERE r.entity_type = 'блюдо' AND r.entity_id = p.product_id) AS expected
FROM product p
WHERE p.rating IS NOT NULL
LIMIT 20;
```

Ожидается: `rating = expected`.
Факт: во всех 20 строках совпадает. Сверил и без `LIMIT`, по всем блюдам и ресторанам: расхождений 0 (рейтинг есть у 167 блюд и 95 ресторанов, у остальных отзывов нет и рейтинг NULL).
Вердикт: OK

---

## E. Функции и процедуры

### E.1. `add_product` — успешный вызов

```sql
SELECT count(*) AS before FROM product;

CALL add_product(
    p_restaurant_id => (SELECT restaurant_id FROM restaurant LIMIT 1),
    p_product_category_id => (SELECT product_category_id FROM product_category LIMIT 1),
    p_name => 'Тестовое блюдо',
    p_price => 250,
    p_rating => 4.5,
    p_status => 'доступно',
    p_description => 'Описание'
    -- + photo_url если есть
);

SELECT count(*) AS after FROM product;
```

Ожидается: `after = before + 1`.
Факт: так вызов не проходит, `ERROR: cannot use subquery in CALL argument`: PostgreSQL не разрешает подзапросы в аргументах `CALL`. Вытащил id ресторана и категории заранее через `\gset` и передал их:

```sql
SELECT restaurant_id AS r_id FROM restaurant LIMIT 1 \gset
SELECT product_category_id AS c_id FROM product_category LIMIT 1 \gset

CALL add_product(
    p_restaurant_id => :'r_id',
    p_product_category_id => :'c_id',
    p_name => 'Тестовое блюдо',
    p_price => 250,
    p_rating => 4.5,
    p_status => 'доступно',
    p_description => 'Описание'
);
```

before 550, after 551.
Вердикт: OK

### E.2. `add_product` — падает на несуществующий ресторан

```sql
CALL add_product(
    p_restaurant_id => '00000000-0000-0000-0000-000000000000',
    -- остальные аргументы
);
```

Ожидается: ошибка с внятным сообщением.
Факт: `ERROR: add_product: ресторан 00000000-0000-0000-0000-000000000000 не существует`. С несуществующей категорией: `add_product: категория ... не существует`, с ценой -1: нарушение `product_price_not_negative`.
Вердикт: OK

### E.3. `rating_change` — пересчитывает рейтинг

```sql
-- Выбрать заказ, блюдо и клиента
SELECT p.product_id, p.rating FROM product p WHERE p.rating IS NOT NULL LIMIT 1;

-- Вставить отзыв на это блюдо
INSERT INTO review (review_id, client_id, review_timestamp, entity_id, entity_type, order_id, description, rating)
VALUES (
    exts.uuid_generate_v4(),
    (SELECT client_id FROM client LIMIT 1),
    localtimestamp,
    <product_id>,
    'блюдо',
    (SELECT order_id FROM "order" LIMIT 1),
    'Тестовый отзыв',
    5
);

SELECT rating FROM product WHERE product_id = <product_id>;
```

Ожидается: `rating` пересчитан.
Факт: как в шаблоне вставка не проходит: `violates foreign key constraint "review_order_client_fk"`. Клиент, заказ и блюдо берутся случайные, а по BR-9.2 отзыв можно оставить только на свой заказ. Поэтому взял клиента, заказ и блюдо из одного заказа (блюдо с одним отзывом на 5, rating = 5.00) и вставил отзыв с оценкой 1. Стало rating = 3.00.
Вердикт: OK

### E.4. `rating_change` — удаление отзыва

```sql
-- Удалить отзыв из E.3
DELETE FROM review WHERE review_id = <review_id>;

SELECT rating FROM product WHERE product_id = <product_id>;
```

Ожидается: если других отзывов нет — `rating IS NULL`; иначе — пересчитан.
Факт: rating снова 5.00. Когда удалил и последний отзыв (в транзакции с откатом), rating стал NULL.
Вердикт: OK

### E.5. `get_statistic()`

```sql
SELECT * FROM get_statistic();
```

Ожидается:
- Колонки: `restaurant_name`, `best_product_name`, `total_amount`, `avg_amount`, `best_user`.
- По одной строке на ресторан.
- `best_user` = `client.login` (не NULL при наличии заказов).

Факт: колонки те же. 110 строк на 110 ресторанов. В `best_user` логины, NULL нет ни в `best_user`, ни в `best_product_name`. `total_amount >= avg_amount` во всех строках.
Вердикт: OK

### E.6. `courier_salary()`

```sql
-- До
SELECT courier_id, coefficient FROM courier ORDER BY courier_id;

CALL courier_salary();

-- После
SELECT courier_id, coefficient FROM courier ORDER BY courier_id;
SELECT year, month, courier_id, amount, coefficient_used
FROM courier_pay
ORDER BY year DESC, month DESC, courier_id
LIMIT 20;
```

Ожидается:
- `courier.coefficient` пересчитан для работающих (по BR-10.2).
- У уволенных — не изменился.
- `courier_pay` содержит запись за текущий месяц.

Факт: запись за 2026-11 есть у всех 110 курьеров (её создаёт уже генератор, процедура её пересчитала). Коэффициенты до и после одинаковые, 0.1: при `value = 10` больше 150 доставок ни у кого нет. Чтобы увидеть смену, в транзакции с откатом сделал `insert_test_data(100)` и отдал 151 доставку текущего месяца работающему курьеру, а 260 уволенному. После `courier_salary()` у работающего коэффициент 0.2, у уволенного остался 0.1, зарплату оба получили с `coefficient_used = 0.1`.
Вердикт: OK

### E.7. `courier_salary()` — повторный вызов

```sql
CALL courier_salary();
SELECT count(*) FROM courier_pay
WHERE year = extract(year from current_date)
  AND month = extract(month from current_date);
```

Ожидается: количество не изменилось (idempotency / обновление).
Факт: было 110, осталось 110.
Вердикт: OK

---

## F. Представление `how_much_money`

### F.1. Колонки

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'khorunzhii_food'
  AND table_name = 'how_much_money'
ORDER BY ordinal_position;
```

Ожидается: `year_month` (text), `sum_no_commission`, `sum_with_commission`, `commission`, `prev_commission`, `commission_diff`, `courier_pay`, `net_profit` (numeric).
Факт: `year_month` text, остальные numeric, порядок тот же.
Вердикт: OK

### F.2. Месяцы покрыты

```sql
SELECT * FROM how_much_money ORDER BY year_month;
```

Ожидается: месяцы от первого доставленного заказа до последнего (не пропущено ни одного).
Факт: 6 месяцев подряд, с 2026-06 по 2026-11:

```
 year_month | sum_no_commission | sum_with_commission | commission | prev_commission | commission_diff | courier_pay | net_profit
 2026-06    |         182140.00 |           200354.00 |   18214.00 |                 |                 |     1821.40 |   16392.60
 2026-07    |         495370.00 |           544907.00 |   49537.00 |        18214.00 |        31323.00 |     4953.70 |   44583.30
 2026-08    |         521100.00 |           573210.00 |   52110.00 |        49537.00 |         2573.00 |     5211.00 |   46899.00
 2026-09    |         398760.00 |           438636.00 |   39876.00 |        52110.00 |       -12234.00 |     3987.60 |   35888.40
 2026-10    |         483240.00 |           531564.00 |   48324.00 |        39876.00 |         8448.00 |     4832.40 |   43491.60
 2026-11    |          76890.00 |            84579.00 |    7689.00 |        48324.00 |       -40635.00 |      768.90 |    6920.10
```

Вердикт: OK

### F.3. Месяцы без заказов присутствуют (BR-11.9)

```sql
SELECT year_month FROM how_much_money
WHERE sum_no_commission = 0 OR sum_no_commission IS NULL;
```

Ожидается: если в какие-то месяцы заказов не было — они есть в результате.
Факт: пусто, в сгенерированных данных пустых месяцев нет. Проверил в транзакции с откатом: отменил все доставленные заказы августа, и 2026-08 остался в отчёте с нулевыми суммами.
Вердикт: OK

### F.4. Корректность сумм

```sql
SELECT year_month,
       sum_no_commission,
       sum_with_commission,
       commission,
       prev_commission,
       commission_diff,
       courier_pay,
       net_profit
FROM how_much_money
ORDER BY year_month
LIMIT 10;
```

Ожидается:
- `commission = sum_with_commission - sum_no_commission`.
- `commission_diff = commission - prev_commission` (NULL для первого месяца).
- `net_profit = commission - courier_pay`.

Факт: те же 6 строк, что в F.2. Все три формулы сходятся во всех строках, у 2026-06 `prev_commission` и `commission_diff` NULL.
Вердикт: OK

---

## G. Права `inspector`

### G.1. Права на схему

```sql
SELECT
    nspname AS schema_name,
    has_schema_privilege('inspector', nspname, 'USAGE')  AS usage,
    has_schema_privilege('inspector', nspname, 'CREATE') AS create
FROM pg_namespace
WHERE nspname = 'khorunzhii_food';
```

Ожидается: `<фамилия>_food`, `true`, `true` (полный доступ).
Факт: `khorunzhii_food | t | t`.
Вердикт: OK

### G.2. Права на таблицы

```sql
SELECT table_name, string_agg(privilege_type, ', ') AS privs
FROM information_schema.role_table_grants
WHERE grantee = 'inspector' AND table_schema = 'khorunzhii_food'
GROUP BY table_name;
```

Ожидается: у каждой таблицы `SELECT, INSERT, UPDATE, DELETE` (или `ALL`).
Факт: у всех 12 таблиц и `how_much_money` все права: SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER.
Вердикт: OK

### G.3. `information_schema` читается под `inspector`

```sql
SET ROLE inspector;
SELECT count(*) FROM information_schema.tables
WHERE table_schema = 'khorunzhii_food';
RESET ROLE;
```

Ожидается: 12 + N (количество таблиц).
Факт: 13 (12 таблиц и представление).
Вердикт: OK

### G.4. `pg_catalog` читается под `inspector`

```sql
SET ROLE inspector;
SELECT count(*) FROM pg_catalog.pg_tables
WHERE schemaname = 'khorunzhii_food';
RESET ROLE;
```

Ожидается: 12 + N.
Факт: 12.
Вердикт: OK

### G.5. Все процедуры/функции работают под `inspector`

```sql
SET ROLE inspector;
SET search_path TO khorunzhii_food, exts;

CALL erase_test_data();
CALL insert_test_data(10);
CALL courier_salary();
SELECT * FROM get_statistic();
SELECT * FROM how_much_money LIMIT 5;

RESET ROLE;
```

Ожидается: без `permission denied`.
Факт: всё выполнилось, `get_statistic` вернул 10 строк, `how_much_money` 5. `permission denied` нет.
Вердикт: OK

---

## H. Оптимизация `get_statistic` (BR-11.8)

На 10 курьерах оба запроса выполняются меньше чем за 1 мс, разницы почти не видно. Поэтому H.1 и H.2 прогнал ещё на `insert_test_data(1000)` в транзакции с откатом: 1010 курьеров, 5050 заказов.

### H.1. `EXPLAIN ANALYZE` — паттерн «избыточные подзапросы»

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       (SELECT count(*) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен') AS cnt,
       (SELECT coalesce(sum(commission), 0) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен') AS commission_sum
FROM courier c;
```

Ожидается: два SubPlan, каждый — скан `"order"`. Время растёт линейно от числа курьеров.
Факт: два SubPlan, у каждого `loops=10` на 10 курьерах и `loops=1010` на 1010. Время 0,22 мс на 10 курьерах, 74,8 мс на 1010.

```
 Seq Scan on courier c (rows=1010 loops=1)
   SubPlan 1
     ->  Aggregate (loops=1010)
           ->  Bitmap Heap Scan on "order" o (loops=1010)
                 ->  Bitmap Index Scan on order_courier_idx (loops=1010)
   SubPlan 2
     ->  Aggregate (loops=1010)
           ->  Bitmap Heap Scan on "order" o_1 (loops=1010)
                 ->  Bitmap Index Scan on order_courier_idx (loops=1010)
```

Вердикт: OK

### H.2. `EXPLAIN ANALYZE` — паттерн «один JOIN»

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       count(o.order_id) AS cnt,
       coalesce(sum(o.commission), 0) AS commission_sum
FROM courier c
LEFT JOIN "order" o ON o.courier_id = c.courier_id AND o.status = 'доставлен'
GROUP BY c.courier_id;
```

Ожидается: один `Hash Right Join` / `Hash Left Join`, один скан `"order"`. Время меньше, чем в H.1.
Факт: на 10 курьерах `Hash Left Join`, на 1010 `Hash Right Join`, `"order"` сканируется один раз. Время 0,13 мс на 10 курьерах, 5,0 мс на 1010, то есть в 15 раз быстрее H.1.

```
 HashAggregate / GroupAggregate
   ->  Hash Right Join
         ->  Seq Scan on "order" o
               Filter: (status = 'доставлен'::order_status)
         ->  Hash
               ->  Seq Scan on courier c
```

Вердикт: OK

### H.3. Применить к `get_statistic`

```sql
EXPLAIN ANALYZE SELECT * FROM get_statistic();
```

Ожидается: без `LATERAL`, без множественных подзапросов к одной таблице, без оконных функций там, где хватает агрегата.
Факт: снаружи видно только `Function Scan on get_statistic`, 1,5 мс на 10 ресторанах и 45 мс на 1010. Поэтому сделал `EXPLAIN ANALYZE` для текста запроса из функции: `"order"` сканируется один раз (CTE `delivered`), дальше только `GroupAggregate` и `Hash Left Join`. `LATERAL`, `SubPlan` и `WindowAgg` нет.
Вердикт: OK

---

## I. Очистка и повторная генерация

### I.1. `erase_test_data` очищает всё

```sql
CALL erase_test_data();

SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "order"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
UNION ALL SELECT 'order_structure', count(*) FROM order_structure
UNION ALL SELECT 'client_address', count(*) FROM client_address
UNION ALL SELECT 'courier_pay', count(*) FROM courier_pay;
```

Ожидается: все 0.
Факт: все 12 строк 0. Функции, процедуры и представление на месте.
Вердикт: OK

### I.2. Повторный `erase_test_data` не падает

```sql
CALL erase_test_data();
```

Ожидается: без ошибок.
Факт: без ошибок.
Вердикт: OK

### I.3. После очистки `insert_test_data` снова работает

```sql
CALL insert_test_data(10);
SELECT count(*) FROM "order";
```

Ожидается: 50.
Факт: 50.
Вердикт: OK
