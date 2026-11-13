SET client_encoding = 'UTF8';
SET search_path TO khorunzhii_food, exts;

CREATE PROCEDURE courier_salary()
LANGUAGE plpgsql SET search_path = khorunzhii_food, exts AS $$
DECLARE
    v_month_start timestamp := date_trunc('month', localtimestamp);
    v_month_end   timestamp := v_month_start + interval '1 month';
    v_year        int       := extract(year FROM localtimestamp);
    v_month       smallint  := extract(month FROM localtimestamp);
BEGIN
    WITH delivered AS (
        SELECT courier_id,
               sum(commission) AS commission_sum,
               count(*)        AS delivered_count
          FROM "order"
         WHERE status = 'доставлен'
           AND order_timestamp >= v_month_start
           AND order_timestamp < v_month_end
         GROUP BY courier_id
    ),
    month_pay AS (
        SELECT c.courier_id,
               coalesce(cp.coefficient_used, c.coefficient) AS coefficient_used,
               coalesce(d.commission_sum, 0)                AS commission_sum,
               coalesce(d.delivered_count, 0)               AS delivered_count
          FROM courier c
          LEFT JOIN courier_pay cp
                 ON cp.courier_id = c.courier_id
                AND cp.year = v_year
                AND cp.month = v_month
          LEFT JOIN delivered d ON d.courier_id = c.courier_id
    ),
    saved_pay AS (
        INSERT INTO courier_pay (courier_id, year, month, amount, coefficient_used)
        SELECT courier_id, v_year, v_month, round(commission_sum * coefficient_used, 2), coefficient_used
          FROM month_pay
        ON CONFLICT (courier_id, year, month) DO UPDATE
            SET amount = EXCLUDED.amount
    )
    UPDATE courier c
       SET coefficient = CASE WHEN m.delivered_count > 500 THEN 0.5
                              WHEN m.delivered_count > 250 THEN 0.3
                              WHEN m.delivered_count > 150 THEN 0.2
                              ELSE 0.1 END
      FROM month_pay m
     WHERE c.courier_id = m.courier_id
       AND c.status != 'уволен';
END $$;
