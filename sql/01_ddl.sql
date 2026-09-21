-- =========================================================================
-- ЭТАП 2: Проектирую модель "снежинка" и создаю таблицы измерений и фактов
-- =========================================================================
-- Идея модели: в центре — fact_sales с метриками (количество, сумма продажи),
-- вокруг — измерения (покупатели, продавцы, товары, магазины, поставщики, даты, питомцы).
-- Чтобы это была именно "снежинка" (а не "звезда"), выношу некоторые
-- атрибуты в отдельные справочники 2-го уровня: категории питомцев,
-- категории товаров и бренды товаров.


-- -------------------------------------------------------------------------
-- 2.1  Сначала создаю справочники 2-го уровня.
--      На них будут ссылаться измерения dim_pet и dim_product.
-- -------------------------------------------------------------------------

-- Категории питомцев ("Cats", "Dogs", "Birds", "Fish", "Reptiles").
-- В исходных данных они повторяются в каждой строке, поэтому выношу их отдельно.
CREATE TABLE dim_pet_category (
    pet_category_id SERIAL PRIMARY KEY,
    category_name VARCHAR(50)
);

-- Категории товаров ("Food", "Toy", "Cage").
CREATE TABLE dim_product_category (
    category_id SERIAL PRIMARY KEY,
    category_name VARCHAR(100)
);

-- Бренды товаров.
CREATE TABLE dim_product_brand (
    brand_id SERIAL PRIMARY KEY,
    brand_name VARCHAR(100)
);


-- -------------------------------------------------------------------------
-- 2.2  Теперь создаю измерения 1-го уровня.
-- -------------------------------------------------------------------------

-- Покупатели. ID беру прямо из исходных данных (поле sale_customer_id),
-- поэтому он у меня первичный ключ.
CREATE TABLE dim_customer (
    customer_id INT PRIMARY KEY,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    age INT,
    email VARCHAR(150),
    country VARCHAR(100),
    postal_code VARCHAR(20)
);

-- Продавцы. Аналогично — беру готовый ID из source-данных.
CREATE TABLE dim_seller (
    seller_id INT PRIMARY KEY,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(150),
    country VARCHAR(100),
    postal_code VARCHAR(20)
);

-- Магазины. В исходных данных нет ID магазина, поэтому генерирую
-- суррогатный ключ через SERIAL.
CREATE TABLE dim_store (
    store_id SERIAL PRIMARY KEY,
    store_name VARCHAR(150),
    location VARCHAR(150),
    city VARCHAR(100),
    state VARCHAR(100),
    country VARCHAR(100),
    phone VARCHAR(50),
    email VARCHAR(150)
);

-- Поставщики. Тоже без готового ID — генерирую SERIAL.
CREATE TABLE dim_supplier (
    supplier_id SERIAL PRIMARY KEY,
    supplier_name VARCHAR(150),
    contact_name VARCHAR(150),
    email VARCHAR(150),
    phone VARCHAR(50),
    address VARCHAR(255),
    city VARCHAR(100),
    country VARCHAR(100)
);

-- Календарь дат. Выношу дату продажи отдельно, чтобы удобно было
-- группировать продажи по году, месяцу и дню.
CREATE TABLE dim_date (
    date_id SERIAL PRIMARY KEY,
    full_date DATE,
    year INT,
    month INT,
    day INT
);

-- Питомцы. Ссылаюсь на dim_pet_category (это и делает модель "снежинкой").
-- Дополнительно храню customer_id, чтобы понимать, чей это питомец —
-- иначе у разных покупателей питомцы с одинаковой кличкой слились бы в одного.
CREATE TABLE dim_pet (
    pet_id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES dim_customer(customer_id),
    pet_type VARCHAR(50),
    pet_name VARCHAR(100),
    pet_breed VARCHAR(100),
    pet_category_id INT REFERENCES dim_pet_category(pet_category_id)
);

-- Товары. Ссылаюсь на категорию и бренд (снова принцип "снежинки").
CREATE TABLE dim_product (
    product_id INT PRIMARY KEY,
    product_name VARCHAR(200),
    category_id INT REFERENCES dim_product_category(category_id),
    brand_id INT REFERENCES dim_product_brand(brand_id),
    price NUMERIC(10, 2),
    weight NUMERIC(10, 2),
    color VARCHAR(50),
    size VARCHAR(50),
    material VARCHAR(100),
    description TEXT,
    rating NUMERIC(3, 1),
    reviews INT,
    release_date DATE,
    expiry_date DATE
);


-- -------------------------------------------------------------------------
-- 2.3  Центральная таблица фактов.
-- -------------------------------------------------------------------------

-- Изначально я делал sale_id первичным ключом, но потом выяснил, что id
-- в исходных данных повторяется в каждом из 10 файлов (1..1000 × 10 файлов).
-- Поэтому PK сделал суррогатный fact_id, а sale_id оставил как обычную колонку.
CREATE TABLE fact_sales (
    fact_id SERIAL PRIMARY KEY,
    sale_id INT,
    customer_id INT REFERENCES dim_customer(customer_id),
    seller_id INT REFERENCES dim_seller(seller_id),
    product_id INT REFERENCES dim_product(product_id),
    pet_id INT REFERENCES dim_pet(pet_id),
    store_id INT REFERENCES dim_store(store_id),
    supplier_id INT REFERENCES dim_supplier(supplier_id),
    date_id INT REFERENCES dim_date(date_id),
    sale_quantity INT,
    sale_total_price NUMERIC(10, 2),
    product_quantity INT
);