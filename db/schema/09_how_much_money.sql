SET client_encoding = 'UTF8';
SET search_path TO khorunzhii_food, exts;

CREATE VIEW how_much_money AS
WITH RECURSIVE
delivered_by_month AS (
    SELECT date_trunc('month', order_timestamp) AS month_start,
           sum(order_amount) AS sum_no_commission,
           sum(total_amount) AS sum_with_commission
      FROM "order"
     WHERE status = 'доставлен'
     GROUP BY date_trunc('month', order_timestamp)
),
month_series (month_start, last_month_start) AS (
    SELECT min(month_start), max(month_start)
      FROM delivered_by_month
    HAVING count(*) > 0
    UNION ALL
    SELECT month_start + interval '1 month', last_month_start
      FROM month_series
     WHERE month_start < last_month_start
),
pay_by_month AS (
    SELECT year, month, sum(amount) AS courier_pay
      FROM courier_pay
     GROUP BY year, month
),
month_totals AS (
    SELECT ms.month_start,
           coalesce(d.sum_no_commission, 0)   AS sum_no_commission,
           coalesce(d.sum_with_commission, 0) AS sum_with_commission,
           coalesce(d.sum_with_commission, 0) - coalesce(d.sum_no_commission, 0) AS commission,
           coalesce(p.courier_pay, 0)         AS courier_pay
      FROM month_series ms
      LEFT JOIN delivered_by_month d ON d.month_start = ms.month_start
      LEFT JOIN pay_by_month p       ON p.year  = extract(year FROM ms.month_start)
                                    AND p.month = extract(month FROM ms.month_start)
)
SELECT to_char(month_start, 'YYYY-MM') AS year_month,
       sum_no_commission,
       sum_with_commission,
       commission,
       lag(commission) OVER by_month AS prev_commission,
       commission - lag(commission) OVER by_month AS commission_diff,
       courier_pay,
       commission - courier_pay AS net_profit
  FROM month_totals
WINDOW by_month AS (ORDER BY month_start);
