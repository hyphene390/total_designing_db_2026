SET client_encoding = 'UTF8';
SET search_path TO khorunzhii_food, exts;

CREATE FUNCTION recalc_pay_status() RETURNS trigger
LANGUAGE plpgsql SET search_path = khorunzhii_food, exts AS $$
BEGIN
    IF current_setting('foodexpress.bulk_load', true) = 'on' THEN
        RETURN NULL;
    END IF;

    UPDATE "order" o
       SET pay_status = (SELECT CASE WHEN bool_or(p.status = 'успех')   THEN 'оплачен'
                                     WHEN bool_and(p.status = 'ошибка') THEN 'ошибка'
                                     ELSE 'ожидает'
                                END::order_pay_status
                           FROM payment p
                          WHERE p.order_id = o.order_id)
     WHERE o.order_id IN (OLD.order_id, NEW.order_id);

    RETURN NULL;
END $$;

CREATE TRIGGER payment_pay_status
    AFTER INSERT OR UPDATE OF status, order_id OR DELETE ON payment
    FOR EACH ROW EXECUTE FUNCTION recalc_pay_status();

CREATE FUNCTION rating_change() RETURNS trigger
LANGUAGE plpgsql SET search_path = khorunzhii_food, exts AS $$
BEGIN
    IF current_setting('foodexpress.bulk_load', true) = 'on' THEN
        RETURN NULL;
    END IF;

    UPDATE product p
       SET rating = (SELECT round(avg(r.rating), 2)
                       FROM review r
                      WHERE r.entity_type = 'блюдо' AND r.entity_id = p.product_id)
     WHERE p.product_id IN (OLD.entity_id, NEW.entity_id);

    UPDATE restaurant s
       SET rating = (SELECT round(avg(r.rating), 2)
                       FROM review r
                      WHERE r.entity_type = 'ресторан' AND r.entity_id = s.restaurant_id)
     WHERE s.restaurant_id IN (OLD.entity_id, NEW.entity_id);

    RETURN NULL;
END $$;

CREATE TRIGGER review_rating_change
    AFTER INSERT OR UPDATE OF entity_type, entity_id, rating OR DELETE ON review
    FOR EACH ROW EXECUTE FUNCTION rating_change();
