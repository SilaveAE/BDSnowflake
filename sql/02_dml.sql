-- =========================================================================
-- ЭТАП 3: Заполняю таблицы данными из mock_data
-- =========================================================================
-- Порядок важен: сначала справочники 2-го уровня, потом измерения
-- 1-го уровня (которые на них ссылаются), и в самом конце — факты,
-- потому что фактам нужны уже готовые ID из измерений.


-- -------------------------------------------------------------------------
-- 3.1  Заполняю справочники 2-го уровня.
-- -------------------------------------------------------------------------

-- Беру уникальные значения pet_category из mock_data и складываю в справочник.
INSERT INTO dim_pet_category (category_name)
SELECT DISTINCT pet_category
FROM mock_data
WHERE pet_category IS NOT NULL AND pet_category <> '';

-- То же самое для категорий товаров.
INSERT INTO dim_product_category (category_name)
SELECT DISTINCT product_category
FROM mock_data
WHERE product_category IS NOT NULL AND product_category <> '';

-- И для брендов.
INSERT INTO dim_product_brand (brand_name)
SELECT DISTINCT product_brand
FROM mock_data
WHERE product_brand IS NOT NULL AND product_brand <> '';

-- Заполняю календарь. Даты в исходнике в формате MM/DD/YYYY,
-- поэтому явно указываю маску в TO_DATE. Дополнительно вытаскиваю
-- год, месяц и день, чтобы потом удобно было агрегировать.
INSERT INTO dim_date (full_date, year, month, day)
SELECT DISTINCT
    TO_DATE(sale_date, 'MM/DD/YYYY'),
    EXTRACT(YEAR  FROM TO_DATE(sale_date, 'MM/DD/YYYY'))::INT,
    EXTRACT(MONTH FROM TO_DATE(sale_date, 'MM/DD/YYYY'))::INT,
    EXTRACT(DAY   FROM TO_DATE(sale_date, 'MM/DD/YYYY'))::INT
FROM mock_data
WHERE sale_date IS NOT NULL AND sale_date <> '';


-- -------------------------------------------------------------------------
-- 3.2  Заполняю измерения 1-го уровня.
-- -------------------------------------------------------------------------

-- Покупатели. Использую DISTINCT ON по sale_customer_id, чтобы для каждого
-- ID взялась ровно одна (первая) строка — иначе PK упадёт на дубликате.
-- NULLIF(..., '') нужен, потому что пустые строки в CSV не превращаются
-- в NULL автоматически, а NUMERIC/INT из пустой строки не кастуется.
INSERT INTO dim_customer (customer_id, first_name, last_name, age, email, country, postal_code)
SELECT DISTINCT ON (NULLIF(sale_customer_id, '')::INT)
    NULLIF(sale_customer_id, '')::INT,
    customer_first_name, customer_last_name,
    NULLIF(customer_age, '')::INT,
    customer_email, customer_country, customer_postal_code
FROM mock_data
ORDER BY NULLIF(sale_customer_id, '')::INT;

-- Продавцы — та же логика.
INSERT INTO dim_seller (seller_id, first_name, last_name, email, country, postal_code)
SELECT DISTINCT ON (NULLIF(sale_seller_id, '')::INT)
    NULLIF(sale_seller_id, '')::INT,
    seller_first_name, seller_last_name,
    seller_email, seller_country, seller_postal_code
FROM mock_data
ORDER BY NULLIF(sale_seller_id, '')::INT;

-- Магазины. Тут ID нет, поэтому просто беру DISTINCT по всем атрибутам —
-- SERIAL сам присвоит уникальные store_id.
INSERT INTO dim_store (store_name, location, city, state, country, phone, email)
SELECT DISTINCT store_name, store_location, store_city, store_state,
                store_country, store_phone, store_email
FROM mock_data;

-- Поставщики — аналогично.
INSERT INTO dim_supplier (supplier_name, contact_name, email, phone, address, city, country)
SELECT DISTINCT supplier_name, supplier_contact, supplier_email,
                supplier_phone, supplier_address, supplier_city, supplier_country
FROM mock_data;

-- Питомцы. Связываю через JOIN с dim_pet_category, чтобы подставить
-- уже готовый pet_category_id. Плюс явно запоминаю customer_id,
-- чтобы позже можно было корректно связать питомца с покупателем в фактах.
INSERT INTO dim_pet (customer_id, pet_type, pet_name, pet_breed, pet_category_id)
SELECT DISTINCT
    NULLIF(m.sale_customer_id, '')::INT,
    m.customer_pet_type, m.customer_pet_name, m.customer_pet_breed,
    pc.pet_category_id
FROM mock_data m
JOIN dim_pet_category pc ON m.pet_category = pc.category_name;

-- Товары. Джойню сразу с двумя справочниками — категориями и брендами.
-- Опять использую DISTINCT ON по sale_product_id, чтобы не нарушить PK.
-- Даты релиза и истечения тоже конвертирую из текста в DATE.
INSERT INTO dim_product (product_id, product_name, category_id, brand_id,
                         price, weight, color, size, material, description,
                         rating, reviews, release_date, expiry_date)
SELECT DISTINCT ON (NULLIF(sale_product_id, '')::INT)
    NULLIF(sale_product_id, '')::INT,
    m.product_name,
    dc.category_id,
    db.brand_id,
    NULLIF(m.product_price, '')::NUMERIC,
    NULLIF(m.product_weight, '')::NUMERIC,
    m.product_color, m.product_size, m.product_material, m.product_description,
    NULLIF(m.product_rating, '')::NUMERIC,
    NULLIF(m.product_reviews, '')::INT,
    TO_DATE(NULLIF(m.product_release_date, ''), 'MM/DD/YYYY'),
    TO_DATE(NULLIF(m.product_expiry_date, ''), 'MM/DD/YYYY')
FROM mock_data m
JOIN dim_product_category dc ON m.product_category = dc.category_name
JOIN dim_product_brand    db ON m.product_brand    = db.brand_name
ORDER BY NULLIF(sale_product_id, '')::INT;


-- -------------------------------------------------------------------------
-- 3.3  Заполняю таблицу фактов.
-- -------------------------------------------------------------------------
-- В fact_sales кладу:
--   - sale_id (просто ID из source для справки),
--   - внешние ключи на все измерения (подтягиваю через JOIN),
--   - метрики: количество проданных единиц, сумму продажи и остаток товара.
--
-- Важный момент: для магазинов и поставщиков сравниваю по "естественным"
-- атрибутам (имя + адрес), потому что готового ID для них нет. NULL
-- заменяю на пустую строку через COALESCE, иначе сравнение NULL = NULL
-- даст NULL и JOIN потеряет строку.

INSERT INTO fact_sales (
    sale_id, customer_id, seller_id, product_id, pet_id,
    store_id, supplier_id, date_id,
    sale_quantity, sale_total_price, product_quantity
)
SELECT
    NULLIF(m.id, '')::INT,
    dc.customer_id,
    ds.seller_id,
    dp.product_id,
    dpet.pet_id,
    dst.store_id,
    dsup.supplier_id,
    dd.date_id,
    NULLIF(m.sale_quantity, '')::INT,
    NULLIF(m.sale_total_price, '')::NUMERIC,
    NULLIF(m.product_quantity, '')::INT
FROM mock_data m
JOIN dim_customer dc ON NULLIF(m.sale_customer_id, '')::INT = dc.customer_id
JOIN dim_seller   ds ON NULLIF(m.sale_seller_id, '')::INT   = ds.seller_id
JOIN dim_product  dp ON NULLIF(m.sale_product_id, '')::INT  = dp.product_id
JOIN dim_store    dst ON m.store_name = dst.store_name
                    AND COALESCE(m.store_location, '') = COALESCE(dst.location, '')
                    AND COALESCE(m.store_city, '')     = COALESCE(dst.city, '')
JOIN dim_supplier dsup ON m.supplier_name = dsup.supplier_name
                     AND COALESCE(m.supplier_contact, '') = COALESCE(dsup.contact_name, '')
JOIN dim_pet dpet ON dc.customer_id      = dpet.customer_id
                 AND m.customer_pet_type = dpet.pet_type
                 AND m.customer_pet_name = dpet.pet_name
                 AND m.customer_pet_breed = dpet.pet_breed
JOIN dim_date dd ON TO_DATE(m.sale_date, 'MM/DD/YYYY') = dd.full_date;


-- =========================================================================
-- ЭТАП 4: Проверяю, что всё загрузилось как надо
-- =========================================================================

-- В источнике должно быть ровно 10 000 строк (10 файлов × 1000 строк).
SELECT COUNT(*) AS mock_data_rows FROM mock_data;

-- В фактах тоже должно быть 10 000 строк — сколько продаж, столько и записей.
SELECT COUNT(*) AS fact_sales_rows FROM fact_sales;

-- fact_id уникален везде (это PK).
SELECT COUNT(*) AS unique_fact_ids FROM (SELECT DISTINCT fact_id FROM fact_sales) t;

-- sale_id уникален только в пределах одного файла, поэтому различных значений — 1000.
SELECT COUNT(DISTINCT sale_id) AS unique_sale_ids FROM fact_sales;