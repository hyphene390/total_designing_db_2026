SET client_encoding = 'UTF8';
SET search_path TO khorunzhii_food, exts;

CREATE FUNCTION get_statistic()
RETURNS TABLE (restaurant_name   text,
               best_product_name text,
               total_amount      numeric,
               avg_amount        numeric,
               best_user         text)
LANGUAGE sql
SET search_path = khorunzhii_food, exts AS $$
WITH delivered AS (
    SELECT order_id, restaurant_id, client_id, total_amount
      FROM "order"
     WHERE status = 'доставлен'
),
totals AS (
    SELECT restaurant_id,
           sum(total_amount)           AS total_amount,
           round(avg(total_amount), 2) AS avg_amount
      FROM delivered
     GROUP BY restaurant_id
),
client_orders AS (
    SELECT restaurant_id, client_id, count(*) AS orders_count
      FROM delivered
     GROUP BY restaurant_id, client_id
),
best_client AS (
    SELECT DISTINCT ON (co.restaurant_id) co.restaurant_id, co.client_id
      FROM client_orders co
      JOIN (SELECT restaurant_id, max(orders_count) AS max_orders_count
              FROM client_orders
             GROUP BY restaurant_id) mx
        ON mx.restaurant_id = co.restaurant_id
       AND mx.max_orders_count = co.orders_count
     ORDER BY co.restaurant_id, random()
),
product_sales AS (
    SELECT dl.restaurant_id, os.product_id, sum(os.quantity) AS sold_quantity
      FROM delivered dl
      JOIN order_structure os ON os.order_id = dl.order_id
     GROUP BY dl.restaurant_id, os.product_id
),
best_product AS (
    SELECT DISTINCT ON (ps.restaurant_id) ps.restaurant_id, ps.product_id
      FROM product_sales ps
      JOIN (SELECT restaurant_id, max(sold_quantity) AS max_sold_quantity
              FROM product_sales
             GROUP BY restaurant_id) mx
        ON mx.restaurant_id = ps.restaurant_id
       AND mx.max_sold_quantity = ps.sold_quantity
     ORDER BY ps.restaurant_id, random()
)
SELECT r.restaurant_name::text,
       p.product_name::text,
       coalesce(t.total_amount, 0),
       t.avg_amount,
       c.login::text
  FROM restaurant r
  LEFT JOIN totals t        ON t.restaurant_id  = r.restaurant_id
  LEFT JOIN best_product bp ON bp.restaurant_id = r.restaurant_id
  LEFT JOIN product p       ON p.product_id     = bp.product_id
  LEFT JOIN best_client bc  ON bc.restaurant_id = r.restaurant_id
  LEFT JOIN client c        ON c.client_id      = bc.client_id
 ORDER BY r.restaurant_name, r.restaurant_id;
$$;
