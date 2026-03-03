


CREATE OR REPLACE PROCEDURE sp_сдать_работу(
        p_id_заготовки INTEGER,
        p_id_заказа INTEGER,
        p_количество INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
v_planned INTEGER;
v_actual INTEGER;
v_missing_material_name VARCHAR;
BEGIN
SELECT статус,
    плановое_количество,
    фактическое_количество INTO v_status,
    v_planned,
    v_actual
FROM ПланЗаготовок
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF NOT FOUND THEN RAISE EXCEPTION 'Задача не найдена';
END IF;
IF v_status = 'выполнено' THEN RAISE EXCEPTION 'Задача уже выполнена';
END IF;
IF v_status = 'отменено' THEN RAISE EXCEPTION 'Задача отменена';
END IF;


SELECT m.наименование INTO v_missing_material_name
FROM СоставЗаготовки sz
    JOIN Материал m ON sz.id_материала = m.id_материала
WHERE sz.id_заготовки = p_id_заготовки
    AND m.количество_на_складе < (sz.количество_материала * p_количество)
LIMIT 1;
IF v_missing_material_name IS NOT NULL THEN RAISE EXCEPTION 'НЕОБХОДИМА ЗАКУПКА: Недостаточно материала "%" для изготовления Заготовка',
v_missing_material_name;
END IF;

UPDATE Материал m
SET количество_на_складе = количество_на_складе - (sz.количество_материала * p_количество)
FROM СоставЗаготовки sz
WHERE sz.id_заготовки = p_id_заготовки
    AND m.id_материала = sz.id_материала;

UPDATE ПланЗаготовок
SET фактическое_количество = фактическое_количество + p_количество,
    дата_факт = CURRENT_DATE
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;

UPDATE Заготовка
SET количество_готовых = количество_готовых + p_количество
WHERE id_заготовки = p_id_заготовки;

IF (v_actual + p_количество) >= v_planned THEN
UPDATE ПланЗаготовок
SET статус = 'выполнено'
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
END IF;
END;
$$;

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
SELECT стоимость,
    количество_на_складе INTO v_price,
    v_stock
FROM Изделие
WHERE id_изделия = p_product_id;

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
message := 'Изделия зарезервированы со склада.';
ELSE 
v_missing_product := p_qty - v_stock;

IF v_stock > 0 THEN
UPDATE Изделие
SET количество_на_складе = 0
WHERE id_изделия = p_product_id;
END IF;


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
RAISE EXCEPTION 'НЕОБХОДИМА ЗАКУПКА: Для производства недостающих изделий не хватает материала "%"',
v_missing_material_name;
END IF;

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
END LOOP;
status := 'WARNING';
message := 'Недостаточно на складе. Созданы задания на производство ' || v_missing_product || ' ед. Материалы в наличии.';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN 












status := 'ERROR';
message := SQLERRM;





DELETE FROM СоставЗаказа
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id
    AND количество_изделий = p_qty
    AND цена_фиксированная = v_price;

RETURN NEXT;
END;
$$;