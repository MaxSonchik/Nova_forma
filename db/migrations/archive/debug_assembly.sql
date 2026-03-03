
CREATE TABLE IF NOT EXISTS DebugLog (
    id SERIAL PRIMARY KEY,
    msg TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

DROP FUNCTION IF EXISTS sp_add_order_item(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_add_order_item(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_stock INTEGER;
v_price NUMERIC;
v_missing_product INTEGER;
v_missing_material_name VARCHAR;
v_date_ready DATE;
rec RECORD;
BEGIN
INSERT INTO DebugLog (msg)
VALUES (
        'START sp_add_order_item: order=' || p_order_id || ' prod=' || p_product_id || ' qty=' || p_qty
    );
SELECT стоимость,
    количество_на_складе INTO v_price,
    v_stock
FROM Изделие
WHERE id_изделия = p_product_id;
INSERT INTO DebugLog (msg)
VALUES ('Stock found: ' || COALESCE(v_stock, -1));

INSERT INTO СоставЗаказа (
        id_заказа,
        id_изделия,
        количество_изделий,
        цена_фиксированная
    )
VALUES (p_order_id, p_product_id, p_qty, v_price);
SELECT дата_готовности INTO v_date_ready
FROM Заказ
WHERE id_заказа = p_order_id;

IF v_stock >= p_qty THEN 
UPDATE Изделие
SET количество_на_складе = количество_на_складе - p_qty
WHERE id_изделия = p_product_id;
status := 'OK';
message := 'Изделия резервированы (на складе было ' || v_stock || ').';
INSERT INTO DebugLog (msg)
VALUES ('Sufficient stock. No tasks created.');
ELSE 
v_missing_product := p_qty - v_stock;

IF v_stock > 0 THEN
UPDATE Изделие
SET количество_на_складе = 0
WHERE id_изделия = p_product_id;
END IF;
INSERT INTO DebugLog (msg)
VALUES (
        'Insufficient stock. Missing: ' || v_missing_product
    );

SELECT m.наименование INTO v_missing_material_name
FROM СоставИзделия si
    JOIN СоставЗаготовки sz ON si.id_заготовки = sz.id_заготовки
    JOIN Материал m ON sz.id_материала = m.id_материала
WHERE si.id_изделия = p_product_id
    AND m.количество_на_складе < (
        v_missing_product * si.количество_заготовок * sz.количество_материала
    )
LIMIT 1;
IF v_missing_material_name IS NOT NULL THEN
INSERT INTO DebugLog (msg)
VALUES (
        'ERROR: Missing material ' || v_missing_material_name
    );
RAISE EXCEPTION 'НЕОБХОДИМА ЗАКУПКА: Для производства недостающих изделий не хватает материала "%"',
v_missing_material_name;
END IF;

INSERT INTO ПланСборки (
        id_заказа,
        id_изделия,
        плановое_количество,
        дата_план,
        статус
    )
VALUES (
        p_order_id,
        p_product_id,
        v_missing_product,
        v_date_ready,
        'принято'
    );
INSERT INTO DebugLog (msg)
VALUES ('Created ASSEMBLY task');

FOR rec IN
SELECT id_заготовки,
    количество_заготовок
FROM СоставИзделия
WHERE id_изделия = p_product_id LOOP
INSERT INTO ПланЗаготовок (
        id_заказа,
        id_заготовки,
        плановое_количество,
        дата_план,
        статус
    )
VALUES (
        p_order_id,
        rec.id_заготовки,
        rec.количество_заготовок * v_missing_product,
        v_date_ready - INTERVAL '1 day',
        'принято'
    );
INSERT INTO DebugLog (msg)
VALUES (
        'Created COMPONENT task for zagotovka ' || rec.id_заготовки
    );
END LOOP;
status := 'WARNING';
message := 'Недостаточно на складе. Созданы задания на производство и сборку ' || v_missing_product || ' ед.';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := SQLERRM;
INSERT INTO DebugLog (msg)
VALUES ('EXCEPTION: ' || SQLERRM);

DELETE FROM СоставЗаказа
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id
    AND количество_изделий = p_qty
    AND цена_фиксированная = v_price;
RETURN NEXT;
END;
$$;