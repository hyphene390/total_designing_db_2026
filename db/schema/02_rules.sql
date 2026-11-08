SET client_encoding = 'UTF8';
SET search_path TO khorunzhii_food, exts;

CREATE FUNCTION check_same_restaurant() RETURNS trigger
LANGUAGE plpgsql SET search_path = khorunzhii_food, exts AS $$
BEGIN
    IF NOT EXISTS (SELECT 1
                     FROM product p
                     JOIN "order" o ON o.restaurant_id = p.restaurant_id
                    WHERE p.product_id = NEW.product_id
                      AND o.order_id = NEW.order_id) THEN
        RAISE EXCEPTION 'BR-7.3: блюдо % не из ресторана заказа %', NEW.product_id, NEW.order_id;
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER order_structure_same_restaurant
    AFTER INSERT OR UPDATE OF order_id, product_id ON order_structure
    FOR EACH ROW EXECUTE FUNCTION check_same_restaurant();

CREATE FUNCTION check_order_has_items() RETURNS trigger
LANGUAGE plpgsql SET search_path = khorunzhii_food, exts AS $$
DECLARE
    v_order_id uuid;
BEGIN
    IF TG_TABLE_NAME = 'order' THEN
        v_order_id := NEW.order_id;
    ELSE
        v_order_id := OLD.order_id;
    END IF;

    IF EXISTS (SELECT 1 FROM "order" WHERE order_id = v_order_id)
       AND NOT EXISTS (SELECT 1 FROM order_structure WHERE order_id = v_order_id) THEN
        RAISE EXCEPTION 'BR-7.14: заказ % остался без позиций', v_order_id;
    END IF;
    RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER order_has_items
    AFTER INSERT ON "order"
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION check_order_has_items();

CREATE CONSTRAINT TRIGGER order_structure_keeps_items
    AFTER DELETE OR UPDATE OF order_id ON order_structure
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION check_order_has_items();

CREATE FUNCTION check_review_matches_order() RETURNS trigger
LANGUAGE plpgsql SET search_path = khorunzhii_food, exts AS $$
BEGIN
    IF NEW.entity_type = 'блюдо' AND NOT EXISTS (
           SELECT 1 FROM order_structure
            WHERE order_id = NEW.order_id AND product_id = NEW.entity_id) THEN
        RAISE EXCEPTION 'BR-9.2: блюда % нет в заказе %', NEW.entity_id, NEW.order_id;
    ELSIF NEW.entity_type = 'ресторан' AND NEW.entity_id IS DISTINCT FROM (
           SELECT restaurant_id FROM "order" WHERE order_id = NEW.order_id) THEN
        RAISE EXCEPTION 'BR-9.2: ресторан % не является рестораном заказа %', NEW.entity_id, NEW.order_id;
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER review_matches_order
    AFTER INSERT OR UPDATE OF entity_type, entity_id, order_id ON review
    FOR EACH ROW EXECUTE FUNCTION check_review_matches_order();
