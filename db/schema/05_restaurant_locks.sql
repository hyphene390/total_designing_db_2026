SET client_encoding = 'UTF8';
SET search_path TO khorunzhii_food, exts;

CREATE FUNCTION forbid_order_restaurant_change() RETURNS trigger
LANGUAGE plpgsql SET search_path = khorunzhii_food, exts AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM order_structure WHERE order_id = NEW.order_id) THEN
        RAISE EXCEPTION 'нельзя сменить ресторан у заказа %, в нём уже есть блюда', NEW.order_id;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER order_restaurant_locked
    BEFORE UPDATE OF restaurant_id ON "order"
    FOR EACH ROW WHEN (OLD.restaurant_id <> NEW.restaurant_id)
    EXECUTE FUNCTION forbid_order_restaurant_change();

CREATE FUNCTION forbid_product_restaurant_change() RETURNS trigger
LANGUAGE plpgsql SET search_path = khorunzhii_food, exts AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM order_structure WHERE product_id = NEW.product_id) THEN
        RAISE EXCEPTION 'нельзя перенести блюдо % в другой ресторан, оно уже есть в заказах', NEW.product_id;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER product_restaurant_locked
    BEFORE UPDATE OF restaurant_id ON product
    FOR EACH ROW WHEN (OLD.restaurant_id <> NEW.restaurant_id)
    EXECUTE FUNCTION forbid_product_restaurant_change();
