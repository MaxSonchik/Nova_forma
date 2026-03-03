-- db/migrations/enforce_transactional_deduction_and_update_product.sql
-- 1. Updates sp_update_product to accept type and size parameters.
CREATE OR REPLACE FUNCTION sp_update_product(
        p_id integer,
        p_name character varying,
        p_type character varying,
        p_size character varying,
        p_price numeric
    ) RETURNS TABLE(
        status character varying,
        message character varying
    ) LANGUAGE plpgsql AS $$ BEGIN
UPDATE Изделие
SET наименование = p_name,
    тип = p_type,
    размеры = p_size,
    стоимость = p_price
WHERE id_изделия = p_id;
IF FOUND THEN RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Изделие обновлено'::VARCHAR;
ELSE RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    'Изделие не найдено'::VARCHAR;
END IF;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;
-- 2. Modifies sp_add_product_to_order_smart to strictly enforce transactional material 
--    and component availability during order creation.
CREATE OR REPLACE FUNCTION sp_add_product_to_order_smart(
        p_order_id integer,
        p_product_id integer,
        p_qty integer,
        p_deadline date
    ) RETURNS TABLE(
        status character varying,
        message character varying
    ) LANGUAGE plpgsql AS $$
DECLARE r RECORD;
m RECORD;
v_needed_qty INTEGER;
v_stock_qty INTEGER;
v_missing_qty INTEGER;
v_take_from_stock INTEGER;
v_components_added INTEGER := 0;
v_price NUMERIC;
BEGIN
SELECT стоимость INTO v_price
FROM Изделие
WHERE id_изделия = p_product_id;
IF EXISTS (
    SELECT 1
    FROM СоставЗаказа
    WHERE id_заказа = p_order_id
        AND id_изделия = p_product_id
) THEN
UPDATE СоставЗаказа
SET количество_изделий = количество_изделий + p_qty
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;
ELSE
INSERT INTO СоставЗаказа (
        id_заказа,
        id_изделия,
        количество_изделий,
        цена_фиксированная
    )
VALUES (
        p_order_id,
        p_product_id,
        p_qty,
        COALESCE(v_price, 0)
    );
END IF;
-- Component processing loop
FOR r IN (
    SELECT si.id_заготовки,
        si.количество_заготовки
    FROM СоставИзделия si
    WHERE si.id_изделия = p_product_id
) LOOP v_needed_qty := COALESCE(r.количество_заготовки, 0) * p_qty;
SELECT количество_готовых INTO v_stock_qty
FROM Заготовка
WHERE id_заготовки = r.id_заготовки;
-- Determine how much we can take from stock immediately
v_take_from_stock := LEAST(v_needed_qty, COALESCE(v_stock_qty, 0));
-- Deduct available stock immediately
IF v_take_from_stock > 0 THEN
UPDATE Заготовка
SET количество_готовых = количество_готовых - v_take_from_stock
WHERE id_заготовки = r.id_заготовки;
END IF;
-- If more components are needed, deduct materials AND create tasks
IF v_take_from_stock < v_needed_qty THEN v_missing_qty := v_needed_qty - v_take_from_stock;
-- Strict material check for missing components
FOR m IN (
    SELECT rm.id_материала,
        rm.количество_материала,
        mat.количество_на_складе,
        mat.наименование
    FROM РасходМатериалов rm
        JOIN Материал mat ON rm.id_материала = mat.id_материала
    WHERE rm.id_заготовки = r.id_заготовки
) LOOP -- Compare required material vs existing material in warehouse
IF m.количество_на_складе < (m.количество_материала * v_missing_qty) THEN status := 'ERROR';
message := 'НЕОБХОДИМА ЗАКУПКА: Недостаточно материала "' || m.наименование || '" для заготовки (нужно ' || (m.количество_материала * v_missing_qty) || ', есть ' || m.количество_на_складе || ').';
RETURN NEXT;
RETURN;
END IF;
-- Deduct material immediately
UPDATE Материал
SET количество_на_складе = количество_на_складе - (m.количество_материала * v_missing_qty)
WHERE id_материала = m.id_материала;
END LOOP;
-- Create task for missing quantity
INSERT INTO "ПланЗаготовок" (
        id_заказа,
        id_заготовки,
        плановое_количество,
        фактическое_количество,
        дата_план,
        статус,
        дата_факт
    )
VALUES (
        p_order_id,
        r.id_заготовки,
        v_missing_qty,
        0,
        p_deadline,
        'принято',
        NULL
    );
v_components_added := v_components_added + 1;
END IF;
END LOOP;
IF v_components_added = 0 THEN status := 'OK';
message := 'Изделие добавлено. Все компоненты взяты со склада.';
ELSE
UPDATE Заказ
SET статус = 'в_работе'
WHERE id_заказа = p_order_id
    AND статус = 'принят';
status := 'OK';
message := 'Созданы задачи для ' || v_components_added || ' компонентов.';
END IF;
RETURN NEXT;
END;
$$;