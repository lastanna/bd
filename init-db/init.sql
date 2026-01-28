-- 1. Таблица категорий
CREATE TABLE categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    parent_id INTEGER REFERENCES categories(id) ON DELETE CASCADE,
    CONSTRAINT check_not_self_parent CHECK (parent_id <> id)
);

-- 2. Таблица товаров
CREATE TABLE goods (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    quantity INTEGER NOT NULL DEFAULT 0,
    category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL
);

-- 3. Таблица клиентов
CREATE TABLE customers (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        address VARCHAR(255)
);

-- 4. Таблица заказов
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    order_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    customer_id INTEGER REFERENCES customers(id) ON DELETE CASCADE
);

-- 5. Таблица позиций заказа (с уникальным индексом для ON CONFLICT)
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(id) ON DELETE CASCADE,
    goods_id INTEGER REFERENCES goods(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    UNIQUE(order_id, goods_id)
);

-- 6. Индексы для внешних ключей (Foreign Keys)

-- Таблица категорий (ускоряет поиск детей и рекурсию)
CREATE INDEX idx_categories_parent_id ON categories(parent_id);

-- Таблица товаров (ускоряет фильтрацию по категориям)
CREATE INDEX idx_goods_category_id ON goods(category_id);

-- Индекс на дату заказа (для отчетов и сортировки)
CREATE INDEX idx_orders_order_date ON orders(order_date DESC);

-- Таблица позиций заказа (ускоряет получение состава заказа)
CREATE UNIQUE INDEX idx_unique_order_goods ON order_items (order_id, goods_id);

-- 7. View для создания отчета «Топ-5 самых покупаемых товаров за последний месяц»
CREATE OR REPLACE VIEW top_5_goods_last_month AS
WITH RECURSIVE category_path AS (
    -- Базовый случай: берем все категории
    SELECT id, name, parent_id, id AS root_id, name AS root_name
    FROM categories
    WHERE parent_id IS NULL

    UNION ALL

    -- Рекурсия: спускаемся вниз, сохраняя имя корневого родителя
    SELECT c.id, c.name, c.parent_id, cp.root_id, cp.root_name
    FROM categories c
    JOIN category_path cp ON c.parent_id = cp.id
)
SELECT
    g.name AS "Наименование товара",
    cp.root_name AS "Категория 1-го уровня",
    SUM(oi.quantity) AS "Общее количество"
FROM order_items oi
JOIN orders o ON oi.order_id = o.id
JOIN goods g ON oi.goods_id = g.id
JOIN category_path cp ON g.category_id = cp.id
-- Фильтр за последний месяц от текущей даты
WHERE o.order_date >= CURRENT_DATE - INTERVAL '1 month'
GROUP BY g.id, g.name, cp.root_name
ORDER BY "Общее количество" DESC
LIMIT 5;

-- 8. Процедура для добавления товара в заказ (для REST API)
-- принимает ID заказа, ID номенклатуры и количество
-- Процедура помогает избежать проблем с параллельными запросами
-- (Race Condition), проверяет остатки и добавляет товар одной транзакцией
CREATE OR REPLACE PROCEDURE add_item_to_order(p_order_id INT, p_goods_id INT, p_qty INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_available_qty INT;
    v_order_exists BOOLEAN;
BEGIN
    -- Проверка существования заказа
    SELECT EXISTS(SELECT 1 FROM orders WHERE id = p_order_id) INTO v_order_exists;

    IF NOT v_order_exists THEN
        RAISE EXCEPTION 'Заказ с ID % не существует', p_order_id;
    END IF;

    -- Проверка наличия и получение текущей цены
    SELECT quantity INTO v_available_qty FROM goods WHERE id = p_goods_id;

    IF v_available_qty IS NULL THEN
        RAISE EXCEPTION 'Товар с ID % не найден', p_goods_id;
    END IF;

    IF v_available_qty < p_qty THEN
        RAISE EXCEPTION 'Недостаточно товара (в наличии: %)', v_available_qty;
    END IF;

    -- Добавление или обновление количества
    -- Обработка дублей: INSERT ... ON CONFLICT в SQL гарантирует,
    -- что если товар уже был в заказе, счетчик просто инкрементируется
    INSERT INTO order_items (order_id, goods_id, quantity)
    VALUES (p_order_id, p_goods_id, p_qty)
    ON CONFLICT (order_id, goods_id)
    DO UPDATE SET quantity = order_items.quantity + EXCLUDED.quantity;

    -- Списание со склада
    UPDATE goods SET quantity = quantity - p_qty WHERE id = p_goods_id;
END;
$$;

-- 9. Тестовые данные
INSERT INTO categories (id, name, parent_id) VALUES
(1, 'Электроника', NULL),
(2, 'Бытовая техника', NULL),
(3, 'Смартфоны', 1),
(4, 'Ноутбуки', 1),
(5, 'Холодильники', 2);

INSERT INTO goods (name, price, quantity, category_id) VALUES
('iPhone 15', 89000.00, 10, 3),
('Samsung Galaxy S24', 75000.00, 5, 3),
('MacBook Air M2', 120000.00, 3, 4),
('Холодильник LG', 55000.00, 2, 5);

INSERT INTO customers (id, name) VALUES (1, 'Иван Иванов');

INSERT INTO orders (id, customer_id) VALUES (1, 1);