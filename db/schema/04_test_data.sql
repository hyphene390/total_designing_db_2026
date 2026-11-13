SET client_encoding = 'UTF8';
SET search_path TO khorunzhii_food, exts;

CREATE PROCEDURE insert_test_data(value int)
LANGUAGE plpgsql
SET search_path = khorunzhii_food, exts
SET session_replication_role = replica
AS $$
DECLARE
    v_abc              text      := 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя';
    v_now              timestamp := localtimestamp;
    v_month            timestamp := date_trunc('month', localtimestamp);
    v_hire_from        date      := (date_trunc('month', localtimestamp) - interval '5 months')::date;
    v_hire_to          date      := (date_trunc('month', localtimestamp) - interval '4 months' - interval '1 day')::date;
    v_phone_base       bigint;
    v_categories       uuid[];
    v_couriers         uuid[];
    v_courier_statuses courier_status[];
    v_hire_dates       date[];
    v_dismissal_dates  date[];
    v_addresses        uuid[];
    v_restaurants      uuid[];
    v_clients          uuid[];
    v_products         uuid[];
    v_orders           uuid[] := '{}';
    v_order_id         uuid;
    v_restaurant       int;
    v_client           int;
    v_courier          int;
    v_work_from        timestamp;
    v_work_to          timestamp;
    v_order_ts         timestamp;
    v_delivery_ts      timestamp;
    v_status           order_status;
    v_pay_status       order_pay_status;
    v_menu             uuid[];
    v_menu_prices      numeric[];
    v_items            uuid[];
    v_prices           numeric[];
    v_qty              numeric[];
    v_amount           numeric;
    v_review_type      review_entity_type;
    v_review_ts        timestamp;
    v_month_start      timestamp;
    v_month_end        timestamp;
BEGIN
    IF value < 1 THEN
        RAISE EXCEPTION 'insert_test_data: value должно быть больше 0, получено %', value;
    END IF;

    SELECT coalesce(max(substring(phone_number FROM 4)::bigint), 0)
      INTO v_phone_base
      FROM client
     WHERE phone_number LIKE '+79%';

    v_categories  := ARRAY(SELECT exts.uuid_generate_v4() FROM generate_series(1, value));
    v_couriers    := ARRAY(SELECT exts.uuid_generate_v4() FROM generate_series(1, value));
    v_addresses   := ARRAY(SELECT exts.uuid_generate_v4() FROM generate_series(1, 5 * value));
    v_restaurants := ARRAY(SELECT exts.uuid_generate_v4() FROM generate_series(1, value));
    v_clients     := ARRAY(SELECT exts.uuid_generate_v4() FROM generate_series(1, value));
    v_products    := ARRAY(SELECT exts.uuid_generate_v4() FROM generate_series(1, 5 * value));

    INSERT INTO product_category (product_category_id, product_category_name)
    SELECT v_categories[i],
           left(repeat(substring(v_abc, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 50)
      FROM generate_series(1, value) AS i;

    v_courier_statuses := ARRAY(
        SELECT CASE WHEN i = 1 THEN 'свободен'::courier_status
                    ELSE (enum_range(NULL::courier_status))[
                             1 + floor(random() * cardinality(enum_range(NULL::courier_status)))::int]
               END
          FROM generate_series(1, value) AS i);

    v_hire_dates := ARRAY(
        SELECT v_hire_from + floor(random() * (v_hire_to - v_hire_from + 1))::int
          FROM generate_series(1, value));

    v_dismissal_dates := ARRAY(
        SELECT CASE WHEN v_courier_statuses[i] = 'уволен'
                    THEN v_month::date + floor(random() * (current_date - v_month::date + 1))::int
               END
          FROM generate_series(1, value) AS i);

    INSERT INTO courier (courier_id, last_name, first_name, middle_name, phone_number, status, hire_date, dismissal_date)
    SELECT v_couriers[i],
           left(repeat(substring(v_abc, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 50),
           left(repeat(substring(v_abc, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 50),
           CASE WHEN random() < 0.2 THEN NULL
                ELSE left(repeat(substring(v_abc, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 50)
           END,
           '+79' || lpad(floor(random() * 1000000000)::bigint::text, 9, '0'),
           v_courier_statuses[i],
           v_hire_dates[i],
           v_dismissal_dates[i]
      FROM generate_series(1, value) AS i;

    INSERT INTO address (address_id, street, house_number, apartment_office)
    SELECT v_addresses[i],
           left(repeat(substring(v_abc, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 91)
               || ' ' || left(md5(v_addresses[i]::text), 8),
           (1 + floor(random() * 200)::int)::text,
           CASE WHEN random() < 0.5 THEN NULL
                ELSE 'кв. ' || (1 + floor(random() * 300)::int)::text
           END
      FROM generate_series(1, 5 * value) AS i;

    WITH new_restaurants AS (
        SELECT v_restaurants[i] AS restaurant_id,
               v_addresses[i] AS address_id,
               left(repeat(substring(v_abc, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 100) AS restaurant_name,
               repeat(substring(v_abc, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int) AS description,
               time '06:00' + floor(random() * 13)::int * interval '30 minutes' AS work_start,
               (4 + floor(random() * 8)::int) * interval '1 hour' AS work_length,
               lpad(floor(random() * 10000000000)::bigint::text, 10, '0') AS inn,
               lpad(floor(random() * 10000000000000)::bigint::text, 13, '0') AS ogrn,
               lpad(floor(random() * 10000000000)::bigint::text, 10, '0')
                   || lpad(floor(random() * 10000000000)::bigint::text, 10, '0') AS bank_account,
               (enum_range(NULL::restaurant_status))[
                   1 + floor(random() * cardinality(enum_range(NULL::restaurant_status)))::int] AS status
          FROM generate_series(1, value) AS i
    )
    INSERT INTO restaurant (restaurant_id, restaurant_name, address_id, description,
                            work_start, work_end, inn, ogrn, bank_account, status)
    SELECT nr.restaurant_id, nr.restaurant_name, nr.address_id, nr.description,
           nr.work_start, nr.work_start + nr.work_length, nr.inn, nr.ogrn, nr.bank_account, nr.status
      FROM new_restaurants nr;

    INSERT INTO client (client_id, login, password, phone_number)
    SELECT v_clients[i],
           left(repeat(substring(v_abc, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 41)
               || '_' || left(md5(v_clients[i]::text), 8),
           md5(random()::text),
           '+79' || lpad((v_phone_base + i)::text, 9, '0')
      FROM generate_series(1, value) AS i;

    INSERT INTO client_address (client_id, address_id)
    SELECT v_clients[(i - 1) % value + 1], v_addresses[value + i]
      FROM generate_series(1, 4 * value) AS i;

    INSERT INTO product (product_id, product_name, product_category_id, price, restaurant_id,
                         photo_url, status, description)
    SELECT v_products[i],
           left(repeat(substring(v_abc, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 100),
           v_categories[1 + floor(random() * value)::int],
           (10 + floor(random() * 141)::int) * 10,
           v_restaurants[(i - 1) / 5 + 1],
           CASE WHEN random() < 0.3 THEN NULL
                ELSE 'https://img.foodexpress.example/' || md5(v_products[i]::text) || '.jpg'
           END,
           (enum_range(NULL::product_status))[
               1 + floor(random() * cardinality(enum_range(NULL::product_status)))::int],
           repeat(substring(v_abc, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int)
      FROM generate_series(1, 5 * value) AS i;

    FOR v_restaurant IN 1 .. value LOOP
        SELECT array_agg(product_id), array_agg(price)
          INTO v_menu, v_menu_prices
          FROM product
         WHERE restaurant_id = v_restaurants[v_restaurant];

        FOR j IN 1 .. 5 LOOP
            v_order_id := exts.uuid_generate_v4();
            v_client   := 1 + floor(random() * value)::int;
            v_courier  := 1 + floor(random() * value)::int;

            v_work_from := v_hire_dates[v_courier]::timestamp;
            v_work_to   := CASE WHEN v_dismissal_dates[v_courier] IS NULL THEN v_now
                                ELSE least(v_now, (v_dismissal_dates[v_courier] + 1)::timestamp) END;
            v_order_ts  := v_work_from + random() * (v_work_to - v_work_from);

            IF j = 1 OR random() < 0.7 THEN
                v_status := 'доставлен';
            ELSE
                v_status := (enum_range(NULL::order_status))[
                                1 + floor(random() * cardinality(enum_range(NULL::order_status)))::int];
            END IF;

            IF v_status = 'доставлен' THEN
                v_delivery_ts := least(v_order_ts + (20 + floor(random() * 101)::int) * interval '1 minute', v_work_to);
            ELSE
                v_delivery_ts := NULL;
            END IF;

            v_pay_status := (enum_range(NULL::order_pay_status))[
                                1 + floor(random() * cardinality(enum_range(NULL::order_pay_status)))::int];

            SELECT array_agg(t.product_id), array_agg(t.price)
              INTO v_items, v_prices
              FROM (SELECT product_id, price
                      FROM unnest(v_menu, v_menu_prices) AS m(product_id, price)
                     ORDER BY random()
                     LIMIT 1 + floor(random() * cardinality(v_menu))::int) t;

            v_qty    := '{}';
            v_amount := 0;
            FOR i IN 1 .. cardinality(v_items) LOOP
                v_qty    := v_qty || (1 + floor(random() * 3))::numeric;
                v_amount := v_amount + v_qty[i] * v_prices[i];
            END LOOP;

            WHILE v_amount < 1000 LOOP
                v_qty[1] := v_qty[1] + 1;
                v_amount := v_amount + v_prices[1];
            END LOOP;

            INSERT INTO "order" (order_id, courier_id, client_id, address_id, restaurant_id,
                                 order_timestamp, delivery_timestamp, order_amount,
                                 commission, total_amount,
                                 status, pay_status, description)
            VALUES (v_order_id,
                    v_couriers[v_courier],
                    v_clients[v_client],
                    v_addresses[value + v_client + value * floor(random() * 4)::int],
                    v_restaurants[v_restaurant],
                    v_order_ts,
                    v_delivery_ts,
                    v_amount,
                    round(v_amount * 0.10, 2),
                    v_amount + round(v_amount * 0.10, 2),
                    v_status,
                    v_pay_status,
                    CASE WHEN random() < 0.8 THEN NULL
                         ELSE repeat(substring(v_abc, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int)
                    END);

            INSERT INTO order_structure (order_id, product_id, quantity)
            SELECT v_order_id, t.product_id, t.quantity
              FROM unnest(v_items, v_qty) AS t(product_id, quantity);

            v_review_type := (enum_range(NULL::review_entity_type))[
                                 1 + floor(random() * cardinality(enum_range(NULL::review_entity_type)))::int];
            v_review_ts   := coalesce(v_delivery_ts, v_order_ts);
            v_review_ts   := v_review_ts + random() * (v_now - v_review_ts);

            INSERT INTO review (client_id, review_timestamp, entity_id, entity_type, order_id, description, rating,
                                photo_url)
            VALUES (v_clients[v_client],
                    v_review_ts,
                    CASE v_review_type
                        WHEN 'блюдо'    THEN v_items[1]
                        WHEN 'ресторан' THEN v_restaurants[v_restaurant]
                        ELSE v_order_id
                    END,
                    v_review_type,
                    v_order_id,
                    repeat(substring(v_abc, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int),
                    1 + floor(random() * 5)::int,
                    CASE WHEN random() < 0.3 THEN NULL
                         ELSE 'https://img.foodexpress.example/' || md5(random()::text) || '.jpg'
                    END);

            v_orders := v_orders || v_order_id;
        END LOOP;
    END LOOP;

    INSERT INTO payment (order_id, pay_type, amount, transaction_id, transaction_timestamp, status)
    SELECT o.order_id,
           (enum_range(NULL::payment_type))[
               1 + floor(random() * cardinality(enum_range(NULL::payment_type)))::int],
           o.total_amount,
           exts.uuid_generate_v4()::text,
           o.order_timestamp + random() * (v_now - o.order_timestamp),
           CASE o.pay_status WHEN 'оплачен' THEN 'успех'
                             WHEN 'ошибка'  THEN 'ошибка'
                             ELSE 'в_обработке'
           END::payment_status
      FROM "order" o
     WHERE o.order_id = ANY(v_orders);

    UPDATE product p
       SET rating = s.avg_rating
      FROM (SELECT entity_id, round(avg(rating), 2) AS avg_rating
              FROM review
             WHERE entity_type = 'блюдо' AND entity_id = ANY(v_products)
             GROUP BY entity_id) s
     WHERE p.product_id = s.entity_id;

    UPDATE restaurant r
       SET rating = s.avg_rating
      FROM (SELECT entity_id, round(avg(rating), 2) AS avg_rating
              FROM review
             WHERE entity_type = 'ресторан' AND entity_id = ANY(v_restaurants)
             GROUP BY entity_id) s
     WHERE r.restaurant_id = s.entity_id;

    FOR v_month_start IN
        SELECT generate_series(v_month - interval '5 months', v_month, interval '1 month')
    LOOP
        v_month_end := v_month_start + interval '1 month';

        WITH delivered AS (
            SELECT courier_id,
                   sum(commission) AS commission_sum,
                   count(*)        AS delivered_count
              FROM "order"
             WHERE courier_id = ANY(v_couriers)
               AND status = 'доставлен'
               AND order_timestamp >= v_month_start
               AND order_timestamp < v_month_end
             GROUP BY courier_id
        ),
        month_pay AS (
            SELECT c.courier_id,
                   c.coefficient,
                   coalesce(d.commission_sum, 0)  AS commission_sum,
                   coalesce(d.delivered_count, 0) AS delivered_count
              FROM courier c
              LEFT JOIN delivered d ON d.courier_id = c.courier_id
             WHERE c.courier_id = ANY(v_couriers)
        ),
        saved_pay AS (
            INSERT INTO courier_pay (courier_id, year, month, amount, coefficient_used)
            SELECT courier_id,
                   extract(year FROM v_month_start),
                   extract(month FROM v_month_start),
                   round(commission_sum * coefficient, 2),
                   coefficient
              FROM month_pay
        )
        UPDATE courier c
           SET coefficient = CASE WHEN m.delivered_count > 500 THEN 0.5
                                  WHEN m.delivered_count > 250 THEN 0.3
                                  WHEN m.delivered_count > 150 THEN 0.2
                                  ELSE 0.1 END
          FROM month_pay m
         WHERE c.courier_id = m.courier_id
           AND (c.dismissal_date IS NULL OR c.dismissal_date >= v_month_end);
    END LOOP;
END $$;

CREATE PROCEDURE erase_test_data()
LANGUAGE plpgsql SET search_path = khorunzhii_food, exts AS $$
BEGIN
    TRUNCATE client, address, client_address, restaurant, courier, courier_pay,
             product_category, product, "order", order_structure, payment, review;
END $$;
