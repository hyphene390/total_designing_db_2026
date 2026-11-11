SET client_encoding = 'UTF8';

CREATE SCHEMA khorunzhii_food;
SET search_path TO khorunzhii_food, exts;

CREATE TYPE restaurant_status  AS ENUM ('активен', 'неактивен');
CREATE TYPE product_status     AS ENUM ('доступно', 'нет_в_наличии', 'архив');
CREATE TYPE courier_status     AS ENUM ('свободен', 'занят', 'на_доставке', 'уволен');
CREATE TYPE order_status       AS ENUM ('создан', 'готовится', 'в_доставке', 'доставлен', 'отменён');
CREATE TYPE order_pay_status   AS ENUM ('ожидает', 'оплачен', 'ошибка');
CREATE TYPE payment_status     AS ENUM ('успех', 'ошибка', 'в_обработке');
CREATE TYPE payment_type       AS ENUM ('карта', 'наличные', 'безнал');
CREATE TYPE review_entity_type AS ENUM ('блюдо', 'ресторан', 'заказ');

CREATE TABLE client (
    client_id    uuid        PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    login        varchar(50) NOT NULL,
    password     char(32)    NOT NULL,
    phone_number char(12)    NOT NULL,
    CONSTRAINT client_login_uq          UNIQUE (login),
    CONSTRAINT client_phone_uq          UNIQUE (phone_number),
    CONSTRAINT client_login_not_blank   CHECK (trim(login) != ''),
    CONSTRAINT client_password_md5      CHECK (password ~ '^[0-9a-f]{32}$'),
    CONSTRAINT client_phone_format      CHECK (phone_number ~ '^\+7[0-9]{10}$')
);

CREATE TABLE address (
    address_id       uuid         PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    street           varchar(100) NOT NULL,
    house_number     varchar(10)  NOT NULL,
    apartment_office varchar(10),
    CONSTRAINT address_street_not_blank CHECK (trim(street) != ''),
    CONSTRAINT address_house_not_blank  CHECK (trim(house_number) != ''),
    CONSTRAINT address_apartment_not_blank
        CHECK (apartment_office IS NULL OR trim(apartment_office) != ''),
    CONSTRAINT address_uq
        UNIQUE NULLS NOT DISTINCT (street, house_number, apartment_office)
);

CREATE TABLE client_address (
    client_id  uuid NOT NULL,
    address_id uuid NOT NULL,
    CONSTRAINT client_address_pk PRIMARY KEY (client_id, address_id),
    CONSTRAINT client_address_client_fk  FOREIGN KEY (client_id)
        REFERENCES client (client_id) ON DELETE CASCADE,
    CONSTRAINT client_address_address_fk FOREIGN KEY (address_id)
        REFERENCES address (address_id) ON DELETE RESTRICT
);

CREATE TABLE restaurant (
    restaurant_id   uuid              PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    restaurant_name varchar(100)      NOT NULL,
    address_id      uuid              NOT NULL,
    description     text              NOT NULL,
    work_start      time              NOT NULL,
    work_end        time              NOT NULL,
    company_details text              NOT NULL,
    rating          numeric(3,2),
    status          restaurant_status NOT NULL,
    CONSTRAINT restaurant_address_uq UNIQUE (address_id),
    CONSTRAINT restaurant_address_fk FOREIGN KEY (address_id)
        REFERENCES address (address_id) ON DELETE RESTRICT,
    CONSTRAINT restaurant_name_not_blank        CHECK (trim(restaurant_name) != ''),
    CONSTRAINT restaurant_description_not_blank CHECK (trim(description) != ''),
    CONSTRAINT restaurant_details_not_blank     CHECK (trim(company_details) != ''),
    CONSTRAINT restaurant_work_hours            CHECK (work_end > work_start),
    CONSTRAINT restaurant_rating_range          CHECK (rating BETWEEN 0 AND 5)
);

CREATE TABLE courier (
    courier_id     uuid           PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    fio            varchar(150)   NOT NULL,
    phone_number   char(12)       NOT NULL,
    status         courier_status NOT NULL,
    hire_date      date           NOT NULL,
    dismissal_date date,
    coefficient    numeric(2,1)   NOT NULL DEFAULT 0.1,
    CONSTRAINT courier_fio_not_blank      CHECK (trim(fio) != ''),
    CONSTRAINT courier_coefficient_range  CHECK (coefficient BETWEEN 0.1 AND 0.5),
    CONSTRAINT courier_dismissed_has_date CHECK (status != 'уволен' OR dismissal_date IS NOT NULL),
    CONSTRAINT courier_dismissal_after_hire CHECK (dismissal_date >= hire_date)
);

CREATE TABLE courier_pay (
    courier_id       uuid          NOT NULL,
    year             int           NOT NULL,
    month            smallint      NOT NULL,
    amount           numeric(12,2) NOT NULL,
    coefficient_used numeric(2,1)  NOT NULL,
    CONSTRAINT courier_pay_pk PRIMARY KEY (courier_id, year, month),
    CONSTRAINT courier_pay_courier_fk FOREIGN KEY (courier_id)
        REFERENCES courier (courier_id) ON DELETE RESTRICT,
    CONSTRAINT courier_pay_month_range       CHECK (month BETWEEN 1 AND 12),
    CONSTRAINT courier_pay_amount_not_negative CHECK (amount >= 0),
    CONSTRAINT courier_pay_coefficient_range CHECK (coefficient_used BETWEEN 0.1 AND 0.5)
);

CREATE TABLE product_category (
    product_category_id   uuid        PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_category_name varchar(50) NOT NULL,
    CONSTRAINT product_category_name_not_blank CHECK (trim(product_category_name) != '')
);

CREATE TABLE product (
    product_id          uuid           PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_name        varchar(100)   NOT NULL,
    product_category_id uuid           NOT NULL,
    price               numeric(10,2)  NOT NULL,
    restaurant_id       uuid           NOT NULL,
    photo_url           text,
    rating              numeric(3,2),
    status              product_status NOT NULL,
    description         text           NOT NULL,
    CONSTRAINT product_category_fk FOREIGN KEY (product_category_id)
        REFERENCES product_category (product_category_id) ON DELETE RESTRICT,
    CONSTRAINT product_restaurant_fk FOREIGN KEY (restaurant_id)
        REFERENCES restaurant (restaurant_id) ON DELETE RESTRICT,
    CONSTRAINT product_name_not_blank        CHECK (trim(product_name) != ''),
    CONSTRAINT product_description_not_blank CHECK (trim(description) != ''),
    CONSTRAINT product_price_not_negative    CHECK (price >= 0),
    CONSTRAINT product_rating_range          CHECK (rating BETWEEN 0 AND 5),
    CONSTRAINT product_photo_url_not_blank   CHECK (photo_url IS NULL OR trim(photo_url) != '')
);

CREATE TABLE "order" (
    order_id           uuid             PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    courier_id         uuid             NOT NULL,
    client_id          uuid             NOT NULL,
    address_id         uuid             NOT NULL,
    restaurant_id      uuid             NOT NULL,
    order_timestamp    timestamp        NOT NULL DEFAULT localtimestamp,
    delivery_timestamp timestamp,
    order_amount       numeric(12,2)    NOT NULL,
    commission         numeric(12,2)    NOT NULL,
    total_amount       numeric(12,2)    NOT NULL,
    status             order_status     NOT NULL DEFAULT 'создан',
    pay_status         order_pay_status NOT NULL DEFAULT 'ожидает',
    description        text             NOT NULL,
    CONSTRAINT order_courier_fk    FOREIGN KEY (courier_id)
        REFERENCES courier (courier_id) ON DELETE RESTRICT,
    CONSTRAINT order_client_fk     FOREIGN KEY (client_id)
        REFERENCES client (client_id) ON DELETE RESTRICT,
    CONSTRAINT order_address_fk    FOREIGN KEY (address_id)
        REFERENCES address (address_id) ON DELETE RESTRICT,
    CONSTRAINT order_restaurant_fk FOREIGN KEY (restaurant_id)
        REFERENCES restaurant (restaurant_id) ON DELETE RESTRICT,
    CONSTRAINT order_client_address_fk FOREIGN KEY (client_id, address_id)
        REFERENCES client_address (client_id, address_id) ON DELETE RESTRICT,
    CONSTRAINT order_id_client_uq UNIQUE (order_id, client_id),
    CONSTRAINT order_id_total_uq  UNIQUE (order_id, total_amount),
    CONSTRAINT order_commission_10_percent CHECK (commission = round(order_amount * 0.10, 2)),
    CONSTRAINT order_total_is_sum         CHECK (total_amount = order_amount + commission),
    CONSTRAINT order_total_min            CHECK (total_amount >= 1000),
    CONSTRAINT order_delivered_has_time
        CHECK ((status = 'доставлен') = (delivery_timestamp IS NOT NULL)),
    CONSTRAINT order_delivery_after_order CHECK (delivery_timestamp >= order_timestamp),
    CONSTRAINT order_description_not_blank CHECK (trim(description) != '')
);

CREATE TABLE order_structure (
    order_id   uuid         NOT NULL,
    product_id uuid         NOT NULL,
    quantity   numeric(8,3) NOT NULL,
    CONSTRAINT order_structure_pk PRIMARY KEY (order_id, product_id),
    CONSTRAINT order_structure_order_fk FOREIGN KEY (order_id)
        REFERENCES "order" (order_id) ON DELETE CASCADE,
    CONSTRAINT order_structure_product_fk FOREIGN KEY (product_id)
        REFERENCES product (product_id) ON DELETE RESTRICT,
    CONSTRAINT order_structure_quantity_positive CHECK (quantity > 0)
);

CREATE TABLE payment (
    payment_id            uuid           PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    order_id              uuid           NOT NULL,
    pay_type              payment_type   NOT NULL,
    amount                numeric(12,2)  NOT NULL,
    transaction_id        uuid           NOT NULL,
    transaction_timestamp timestamp      NOT NULL,
    status                payment_status NOT NULL,
    CONSTRAINT payment_order_fk FOREIGN KEY (order_id)
        REFERENCES "order" (order_id) ON DELETE RESTRICT,
    CONSTRAINT payment_amount_matches_order FOREIGN KEY (order_id, amount)
        REFERENCES "order" (order_id, total_amount),
    CONSTRAINT payment_transaction_uq UNIQUE (transaction_id)
);
CREATE UNIQUE INDEX payment_one_success_uq ON payment (order_id) WHERE status = 'успех';

CREATE TABLE review (
    review_id        uuid               PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    client_id        uuid               NOT NULL,
    review_timestamp timestamp          NOT NULL DEFAULT localtimestamp,
    entity_id        uuid               NOT NULL,
    entity_type      review_entity_type NOT NULL,
    order_id         uuid               NOT NULL,
    description      text               NOT NULL,
    photo_url        text,
    rating           smallint           NOT NULL,
    CONSTRAINT review_client_fk FOREIGN KEY (client_id)
        REFERENCES client (client_id) ON DELETE RESTRICT,
    CONSTRAINT review_order_fk FOREIGN KEY (order_id)
        REFERENCES "order" (order_id) ON DELETE RESTRICT,
    CONSTRAINT review_order_client_fk FOREIGN KEY (order_id, client_id)
        REFERENCES "order" (order_id, client_id),
    CONSTRAINT review_order_entity_is_this_order
        CHECK (entity_type != 'заказ' OR entity_id = order_id),
    CONSTRAINT review_one_per_entity_in_order
        UNIQUE (entity_type, entity_id, order_id),
    CONSTRAINT review_description_not_blank CHECK (trim(description) != ''),
    CONSTRAINT review_photo_url_not_blank   CHECK (photo_url IS NULL OR trim(photo_url) != ''),
    CONSTRAINT review_rating_range CHECK (rating BETWEEN 1 AND 5)
);

CREATE INDEX order_courier_idx              ON "order" (courier_id);
CREATE INDEX payment_order_idx              ON payment (order_id);
CREATE INDEX order_structure_product_idx    ON order_structure (product_id);
