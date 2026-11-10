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
    INSERT INTO courier_pay (courier_id, year, month, amount, coefficient_used)
    SELECT c.courier_id,
           v_year,
           v_month,
           round(coalesce(sum(o.commission), 0) * coalesce(cp.coefficient_used, c.coefficient), 2),
           coalesce(cp.coefficient_used, c.coefficient)
      FROM courier c
      LEFT JOIN courier_pay cp
             ON cp.courier_id = c.courier_id
            AND cp.year = v_year
            AND cp.month = v_month
      LEFT JOIN "order" o
             ON o.courier_id = c.courier_id
            AND o.status = 'доставлен'
            AND o.order_timestamp >= v_month_start
            AND o.order_timestamp < v_month_end
     GROUP BY c.courier_id, c.coefficient, cp.coefficient_used
    ON CONFLICT (courier_id, year, month) DO UPDATE
        SET amount = EXCLUDED.amount;

    UPDATE courier c
       SET coefficient = CASE WHEN m.delivered_count > 500 THEN 0.5
                              WHEN m.delivered_count > 250 THEN 0.3
                              WHEN m.delivered_count > 150 THEN 0.2
                              ELSE 0.1 END
      FROM (SELECT c2.courier_id, count(o.order_id) AS delivered_count
              FROM courier c2
              LEFT JOIN "order" o
                     ON o.courier_id = c2.courier_id
                    AND o.status = 'доставлен'
                    AND o.order_timestamp >= v_month_start
                    AND o.order_timestamp < v_month_end
             GROUP BY c2.courier_id) m
     WHERE c.courier_id = m.courier_id
       AND c.status != 'уволен';
END $$;
