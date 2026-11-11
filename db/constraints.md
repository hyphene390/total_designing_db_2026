# Обоснование ограничений

Кратко:
- Схема называется `khorunzhii_food`
- Скрипты лежат в `db/schema/`
- Дополнительных таблиц не делал, всего 12, как в `docs/erd.md`
- Таблицу заказов назвал `"order"` в кавычках, переименовывать я не стал, чтобы имя совпадало с ERD (BR-13.1 разрешает оба варианта).

---

## Enum-типы

Значения взяты из BR буква в букву, включая `ё` в `'отменён'`. По BR-11.5 статусы нельзя хранить в `varchar`.

| Тип | Значения | BR |
|---|---|---|
| `restaurant_status` | `'активен'`, `'неактивен'` | BR-4.3 |
| `product_status` | `'доступно'`, `'нет_в_наличии'`, `'архив'` | BR-5.5 |
| `courier_status` | `'свободен'`, `'занят'`, `'на_доставке'`, `'уволен'` | BR-6.2 |
| `order_status` | `'создан'`, `'готовится'`, `'в_доставке'`, `'доставлен'`, `'отменён'` | BR-7.7 |
| `order_pay_status` | `'ожидает'`, `'оплачен'`, `'ошибка'` | BR-7.9 |
| `payment_status` | `'успех'`, `'ошибка'`, `'в_обработке'` | BR-8.2 |
| `payment_type` | `'карта'`, `'наличные'`, `'безнал'` | BR-8.2, BR-8.6 |
| `review_entity_type` | `'блюдо'`, `'ресторан'`, `'заказ'` | BR-9.1 |

---

## Ловушки

### Ловушка 1: `payment` — неполная сущность

**Какие атрибуты добавил в `payment` и почему** (BR-8.2):

```
pay_type              payment_type   тип оплаты, BR-8.2 и BR-8.6
amount                numeric(12,2)  сумма попытки, BR-8.2 и BR-8.4
transaction_id        uuid           номер транзакции у провайдера, BR-8.3
transaction_timestamp timestamp      дата и время транзакции, BR-8.2
status                payment_status успех / ошибка / в_обработке, BR-8.2

Все поля NOT NULL. Данных карты нет, только номер транзакции (BR-8.5).
transaction_id сделал uuid, потому что B.4 требует uuid у всех столбцов *_id.

Сумму попытки (BR-8.4) проверяет составной FK:
    FOREIGN KEY (order_id, amount) REFERENCES "order" (order_id, total_amount)
Платёж на другую сумму база не примет. Для этого FK на "order" есть
UNIQUE (order_id, total_amount).

Две успешные попытки у одного заказа не даёт сделать частичный индекс:
    CREATE UNIQUE INDEX payment_one_success_uq ON payment (order_id) WHERE status = 'успех';
Заказ совсем без успешной попытки допустим, иначе не было бы статусов
'ожидает' и 'ошибка' из BR-8.7. В тестовых данных успешная попытка есть у каждого заказа.
```

**Где хранится тип оплаты — `payment` или `order`** (BR-8.6):

```
В payment. Клиент может начать платить картой, получить ошибку и заплатить
наличными, то есть у одного заказа бывают попытки разных типов.
```

### Ловушка 2: `order.address_id` — принадлежность клиенту (BR-7.4)

**Как обеспечено, что адрес доставки принадлежит клиенту:**

```
Составным FK на таблицу связей:
    CONSTRAINT order_client_address_fk FOREIGN KEY (client_id, address_id)
        REFERENCES client_address (client_id, address_id) ON DELETE RESTRICT

Пара (client_id, address_id) из заказа должна быть в client_address, поэтому
на чужой адрес заказ не оформить, т.к. и адрес, и айди клиента должны совпасть одновременно. Ссылаемся на первичный ключ client_address.
Обычные FK на client и address тоже есть, они из ERD.
```

### Ловушка 3: `order_structure` — один ресторан в заказе (BR-7.3)

**Как обеспечено, что все блюда из `order.restaurant_id`:**

```
Триггер order_structure_same_restaurant (файл 02_rules.sql), AFTER INSERT OR UPDATE
на order_structure. Сравнивает ресторан блюда с рестораном заказа, если они
разные, выдаёт ошибку "BR-7.3: блюдо ... не из ресторана заказа ...".

Ключ тут не подходит: для него в order_structure нужен restaurant_id, а он
зависит только от order_id, то есть от части ключа. Это нарушение 2НФ

Еще два триггера (в файле 05_restaurant_locks.sql) закрывают другой потенциальный баг:
нельзя сменить ресторан у заказа, в котором уже есть блюда, и нельзя перенести
в другой ресторан блюдо, которое уже заказывали.
```

### Ловушка 4: `review` — полиморфизм (BR-9.1)

**Как реализована валидность `review.entity_id`:**

```
Оставил полиморфизм как в ERD: entity_type говорит, на что отзыв, entity_id
хранит id блюда, ресторана или заказа. Ключ на entity_id сделать нельзя т.к. он
ссылается на разные таблицы. 

Ключ при создании привязывается к одной таблице и проверяет каждое значение только в ней. 

Например, если сделать FK на product, то отзыв на ресторан не вставится: id ресторана в product нет. 

А сказать ключу "если entity_type = блюдо, ищи в product, если ресторан, то в restaurant"
нельзя, FK не смотрит на другие столбцы строки

Вместо него:
1. FK (order_id, client_id) на "order" (order_id, client_id): отзыв пишет
   клиент этого заказа (BR-9.2). Для него на "order" есть UNIQUE (order_id, client_id).
2. CHECK (entity_type != 'заказ' OR entity_id = order_id): отзыв на заказ
   относится к своему заказу (BR-9.2)
3. Триггер review_matches_order: отзыв на блюдо только если блюдо есть в заказе,
   отзыв на ресторан только на ресторан заказа (BR-9.2)
4. UNIQUE (entity_type, entity_id, order_id): один отзыв на объект в заказе (BR-9.5)
```

---

## CHECK-ограничения

`trim(поле) != ''` стоит на всех обязательных текстовых полях: `NOT NULL` пропускает пустую строку и пробелы, а по BR-11.3 поле должно быть заполнено.

| Таблица | Столбец | Условие | BR | Обоснование |
|---|---|---|---|---|
| `client` | `login` | `trim(login) != ''` | BR-2.1, BR-11.3 | без логина нет регистрации |
| `client` | `password` | `password ~ '^[0-9a-f]{32}$'` | BR-2.3 | MD5 это ровно 32 hex-символа, открытый пароль не пройдёт |
| `client` | `phone_number` | `phone_number ~ '^\+7[0-9]{10}$'` | BR-2.2 | один формат, иначе `+79991234567` и `89991234567` прошли бы UNIQUE как разные номера |
| `address` | `street` | `trim(street) != ''` | BR-3.1, BR-11.3 | улица обязательна |
| `address` | `house_number` | `trim(house_number) != ''` | BR-3.1, BR-11.3 | дом обязателен |
| `address` | `apartment_office` | `apartment_office IS NULL OR trim(apartment_office) != ''` | BR-3.2 | квартиры может не быть, но тогда NULL; пустая строка обошла бы UNIQUE адреса |
| `restaurant` | `restaurant_name`, `description`, `company_details` | `trim(...) != ''` | BR-4.1, BR-4.5, BR-11.3 | название, описание и реквизиты обязательны |
| `restaurant` | `work_start`, `work_end` | `work_end > work_start` | BR-4.4 | закрытие позже открытия |
| `restaurant` | `rating` | `rating BETWEEN 0 AND 5` | BR-4.2 | диапазон рейтинга |
| `courier` | `fio` | `trim(fio) != ''` | BR-6.1, BR-11.3 | ФИО обязательно |
| `courier` | `coefficient` | `coefficient BETWEEN 0.1 AND 0.5` | BR-6.4 | диапазон коэффициента |
| `courier` | `status`, `dismissal_date` | `status != 'уволен' OR dismissal_date IS NOT NULL` | BR-6.3 | у уволенного есть дата увольнения |
| `courier` | `dismissal_date`, `hire_date` | `dismissal_date >= hire_date` | BR-6.1, BR-6.3 | уволить раньше найма нельзя (D.13) |
| `courier_pay` | `month` | `month BETWEEN 1 AND 12` | BR-10.2 | в записи год и месяц выплаты |
| `courier_pay` | `amount` | `amount >= 0` | BR-10.4 | зарплата неотрицательна |
| `courier_pay` | `coefficient_used` | `coefficient_used BETWEEN 0.1 AND 0.5` | BR-6.4, BR-10.2 | тот же диапазон, что у коэффициента курьера |
| `product_category` | `product_category_name` | `trim(...) != ''` | BR-5.7, BR-11.3 | название категории обязательно |
| `product` | `product_name`, `description` | `trim(...) != ''` | BR-5.2, BR-11.3 | название и описание обязательны |
| `product` | `price` | `price >= 0` | BR-5.3 | цена неотрицательна, бесплатный соус допустим |
| `product` | `rating` | `rating BETWEEN 0 AND 5` | BR-5.4 | диапазон рейтинга |
| `product` | `photo_url` | `photo_url IS NULL OR trim(photo_url) != ''` | BR-5.6, BR-11.3 | фото необязательно, но пустой строкой быть не может |
| `"order"` | `total_amount` | `total_amount >= 1000` | BR-1.8, BR-7.11 | минимум 1000 ₽; отдельный CHECK на `order_amount` не нужен, он отсюда следует |
| `"order"` | `status`, `delivery_timestamp` | `(status = 'доставлен') = (delivery_timestamp IS NOT NULL)` | BR-7.12, BR-11.3 | время доставки есть только у доставленного заказа |
| `"order"` | `delivery_timestamp` | `delivery_timestamp >= order_timestamp` | BR-7.13 | доставка не раньше создания |
| `"order"` | `description` | `trim(description) != ''` | BR-11.3 | поле из ERD, необязательным не названо |
| `order_structure` | `quantity` | `quantity > 0` | BR-7.15 | количество положительное, может быть дробным |
| `review` | `entity_type`, `entity_id` | `entity_type != 'заказ' OR entity_id = order_id` | BR-9.2 | ловушка 4 |
| `review` | `description` | `trim(description) != ''` | BR-9.3 | у отзыва есть текст |
| `review` | `photo_url` | `photo_url IS NULL OR trim(photo_url) != ''` | BR-9.3, BR-11.3 | фото необязательно, но пустой строкой быть не может |
| `review` | `rating` | `rating BETWEEN 1 AND 5` | BR-9.4 | оценка от 1 до 5 |

---

## UNIQUE-ограничения

| Таблица | Столбцы | BR | Обоснование |
|---|---|---|---|
| `client` | `login` | BR-2.2 | логин уникален |
| `client` | `phone_number` | BR-2.2 | телефон уникален |
| `address` | `(street, house_number, apartment_office)`, `NULLS NOT DISTINCT` | BR-3.3, BR-2.5 | один адрес хранится одной строкой, иначе две строки "Ленина, 5" обходят оба правила. `NULLS NOT DISTINCT` (с PostgreSQL 15) нужен для частных домов, где квартира NULL |
| `restaurant` | `address_id` | BR-3.3, BR-3.4 | у двух ресторанов не может быть одного адреса |
| `client_address` | `(client_id, address_id)`, PK | BR-2.5 | адрес у клиента один раз |
| `order_structure` | `(order_id, product_id)`, PK | BR-7.16 | блюдо в заказе один раз, повтор через количество |
| `courier_pay` | `(courier_id, year, month)`, PK | BR-10.3 | одна запись на курьера за месяц, на нём работает `ON CONFLICT` в `courier_salary` |
| `"order"` | `(order_id, client_id)` | BR-9.2 | цель составного FK из `review` (ловушка 4) |
| `"order"` | `(order_id, total_amount)` | BR-8.4 | цель составного FK из `payment` (ловушка 1) |
| `payment` | `transaction_id` | BR-8.3 | номер транзакции уникален |
| `payment` | `(order_id) WHERE status = 'успех'`, индекс `payment_one_success_uq` | BR-8.1 | одна успешная попытка на заказ, сделано частичным уникальным индексом |
| `review` | `(entity_type, entity_id, order_id)` | BR-9.5 | один отзыв на объект в заказе; этот же индекс ускоряет пересчёт рейтинга |

Названия ресторанов и категорий, ФИО и телефон курьера не уникальны: в BR такого правила нет, BR-2.2 говорит только о клиентах.

---

## FK-ограничения

По умолчанию `ON DELETE RESTRICT`, потому что по BR-3.5 история заказов сохраняется. `CASCADE` только у позиций заказа и адресов клиента: без заказа или клиента они не нужны.

| Таблица | Столбцы | → Таблица | BR | Обоснование |
|---|---|---|---|---|
| `client_address` | `client_id` | `client` | BR-2.4 | адреса клиента, `CASCADE` |
| `client_address` | `address_id` | `address` | BR-2.4, BR-3.5 | адрес не удаляется, пока к нему привязаны |
| `restaurant` | `address_id` | `address` | BR-3.3, BR-3.5 | у ресторана один адрес |
| `product` | `restaurant_id` | `restaurant` | BR-5.1 | блюдо в одном ресторане |
| `product` | `product_category_id` | `product_category` | BR-5.1, BR-5.7 | блюдо в одной категории |
| `courier_pay` | `courier_id` | `courier` | BR-10.2 | выплата курьеру, история не удаляется |
| `"order"` | `client_id` | `client` | BR-7.1, BR-7.2 | заказ оформляет клиент |
| `"order"` | `restaurant_id` | `restaurant` | BR-7.2 | один ресторан на заказ |
| `"order"` | `courier_id` | `courier` | BR-7.5 | доставляет курьер |
| `"order"` | `address_id` | `address` | BR-7.4 | один адрес доставки |
| `"order"` | `(client_id, address_id)` | `client_address (client_id, address_id)` | BR-7.4 | ловушка 2 |
| `order_structure` | `order_id` | `"order"` | BR-7.14 | позиция заказа, `CASCADE` |
| `order_structure` | `product_id` | `product` | BR-7.14, BR-5.5 | блюдо из истории не удаляют, его переводят в `'архив'` |
| `payment` | `order_id` | `"order"` | BR-8.1 | попытка оплаты заказа |
| `payment` | `(order_id, amount)` | `"order" (order_id, total_amount)` | BR-8.4 | ловушка 1 |
| `review` | `client_id` | `client` | BR-9.2 | отзыв пишет клиент |
| `review` | `order_id` | `"order"` | BR-9.2 | отзыв связан с заказом |
| `review` | `(order_id, client_id)` | `"order" (order_id, client_id)` | BR-9.2 | ловушка 4 |

Всего 18 FK. Обычные FK рядом с составными оставил, они есть в ERD и их считает B.6.

---

## NOT NULL (только бизнес-обязательные)

По BR-11.3 обязательны все поля, кроме тех, что в разделе NULL. Тут только неочевидные.

| Таблица | Столбец | BR | Обоснование |
|---|---|---|---|
| `"order"` | `courier_id` | BR-7.5, BR-11.3 | курьера нет в списке необязательных, и C.6 ждёт его у каждого заказа. Считаю, что курьер назначается сразу при создании заказа |
| `"order"` | `description` | BR-11.3 | поле есть в ERD, в BR про него ничего не сказано, значит обязательное |

---

## NULL (осознанно разрешено)

| Таблица | Столбец | BR | Почему NULL |
|---|---|---|---|
| `address` | `apartment_office` | BR-3.2, BR-11.3 | частный дом |
| `courier` | `dismissal_date` | BR-6.3, BR-11.3 | курьер работает |
| `"order"` | `delivery_timestamp` | BR-7.12, BR-11.3 | заказ ещё не доставлен |
| `product` | `photo_url` | BR-5.6, BR-11.3 | фото необязательно |
| `review` | `photo_url` | BR-9.3, BR-11.3 | фото необязательно |
| `product` | `rating` | BR-9.7, FOOD-104 | отзывов нет. Если блюдо добавлено через `add_product` с начальным рейтингом, хранится он до первого отзыва |
| `restaurant` | `rating` | BR-9.7 | отзывов нет |

---

## DEFAULT и GENERATED

| Таблица | Столбец | Что | Обоснование |
|---|---|---|---|
| все таблицы | `*_id` (PK) | `DEFAULT exts.uuid_generate_v4()` | BR-11.1, BR-13.3 |
| `courier` | `coefficient` | `DEFAULT 0.1` | BR-6.5 |
| `"order"` | `order_timestamp` | `DEFAULT localtimestamp` | BR-7.1, BR-11.2: время сервера, без пояса |
| `"order"` | `status` | `DEFAULT 'создан'` | BR-7.7: первый статус |
| `"order"` | `pay_status` | `DEFAULT 'ожидает'` | BR-8.7: попыток ещё нет |
| `review` | `review_timestamp` | `DEFAULT localtimestamp` | BR-9.3, BR-11.2 |
| `"order"` | `commission` | `GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED` | BR-1.4, BR-7.10 |
| `"order"` | `total_amount` | `GENERATED ALWAYS AS (order_amount + round(order_amount * 0.10, 2)) STORED` | BR-7.10 |

`commission` и `total_amount` считает сама база, поэтому они не расходятся с `order_amount`. Формула комиссии повторена в `total_amount`, потому что вычисляемый столбец не может ссылаться на другой вычисляемый. `STORED` нужен, потому что на `total_amount` ссылается FK из `payment`.

---

## Нормализация (3НФ)

```
2НФ: в таблицах с составным ключом (client_address, order_structure, courier_pay)
неключевые поля зависят от всего ключа: quantity от пары "заказ, блюдо",
amount от тройки "курьер, год, месяц".

3НФ: данные ресторана, клиента, курьера и адреса лежат в своих таблицах,
в "order" только их id

Особые случаи:
- commission и total_amount зависят от order_amount. Это GENERATED-столбцы,
  записать неверное значение нельзя (см. DEFAULT и GENERATED).
- product.rating и restaurant.rating хранятся готовыми, чтобы не считать среднее
  при каждом показе меню. Обновляет их триггер rating_change.
- review.entity_id + entity_type: полиморфная ссылка, см. ловушку 4.
```

Остальные триггеры описаны в ловушках. Ещё триггер `payment_pay_status` пересчитывает `order.pay_status` по попыткам оплаты (BR-8.7). И есть отложенный триггер на BR-7.14: в заказе должно быть хотя бы одно блюдо, проверка выполняется при `COMMIT`, потому что заказ вставляется раньше своих позиций.

---

## Отличия типов от ERD

По BR-11.6 длины и точность выбираю сам. Отличия:

- `client.password` `char(32)`: MD5 всегда 32 символа.
- `phone_number` `char(12)`: `+7` и 10 цифр, в `char(11)` не помещается.
- `review.rating` `smallint`: оценка целая от 1 до 5. Средний рейтинг блюда и ресторана `numeric(3,2)`.
- Коэффициенты `numeric(2,1)`, деньги `numeric(12,2)`, цена `numeric(10,2)`, количество `numeric(8,3)` (бывает 0.5 кг).

---

## Прочие решения

1. BR-8.1 говорит "ровно одна успешная попытка", а BR-8.7 описывает заказы без неё. Схема запрещает вторую успешную попытку, а заказ без успешной разрешает.
2. **Повторный вызов `insert_test_data` добавляет данные** (C.9). Каждый вызов создаёт свои строки, уникальные поля (логин, улица, телефон) не пересекаются с прошлыми вызовами. Начать с нуля можно через `erase_test_data()`.
3. Генератор не вызывает функции схемы (`samples/all_examples.sql`, раздел 10): рейтинги и выплаты считает сам, а триггеры пересчёта на время его работы выключены параметром `foodexpress.bulk_load`.
4. По паттернам сделано не всё, где этого не дают тесты и BR: у клиента ровно 4 адреса (BR-11.7, все `value * 4` клиентских адреса должны использоваться), у заказа одна попытка оплаты (C.3 ждёт `value * 5` платежей). Выплаты генерируются за последние 6 месяцев, включая текущий, как в паттерне. Курьеры нанимаются в первом из этих месяцев, а увольняются только в текущем, поэтому запись есть у каждого курьера за каждый месяц, а коэффициент на следующий месяц уволенным не назначается (BR-10.6).
5. Месяц заказа для зарплаты считается по `order_timestamp`, как в C.8.
6. `add_product` сохраняет переданный `p_rating`: FOOD-104 требует принимать все атрибуты `product`, кроме id. После первого отзыва `rating_change` ставит среднее.
7. BR-6.6 схемой не гарантируется, как и сказано в правиле. В генераторе первый курьер всегда `'свободен'`.
8. E.3 в исходном виде падает: отзыв идёт от случайного клиента на чужой заказ, а BR-9.2 это запрещает. Я сделал по BR, пример на правильных данных есть в `tests.md`.
