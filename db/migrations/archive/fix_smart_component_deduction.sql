CREATE OR REPLACE FUNCTION sp_add_product_to_order_smart(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_qty INTEGER,
        p_deadline DATE
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE r RECORD;
rm_rec RECORD;
v_needed_qty INTEGER;
v_stock_qty INTEGER;
v_missing_qty INTEGER;
v_components_added INTEGER := 0;
v_price NUMERIC;
v_missing_text VARCHAR := '';
BEGIN
SELECT стоимость INTO v_price
FROM Изделие
WHERE id_изделия = p_product_id;
-- Pre-calculate and check materials for ALL missing components
FOR r IN (
    SELECT si.id_заготовки,
        si.количество_заготовки
    FROM СоставИзделия si
    WHERE si.id_изделия = p_product_id
) LOOP v_needed_qty := COALESCE(r.количество_заготовки, 0) * p_qty;
SELECT количество_готовых INTO v_stock_qty
FROM Заготовка
WHERE id_заготовки = r.id_заготовки;
IF COALESCE(v_stock_qty, 0) < v_needed_qty THEN v_missing_qty := v_needed_qty - COALESCE(v_stock_qty, 0);
-- Check materials for v_missing_qty of this component
FOR rm_rec IN (
    SELECT m.наименование,
        m.количество_на_складе,
        (
            COALESCE(sz.количество_материала, 0) * v_missing_qty
        ) as needed
    FROM СоставЗаготовки sz
        JOIN Материал m ON sz.id_материала = m.id_материала
    WHERE sz.id_заготовки = r.id_заготовки
) LOOP IF COALESCE(rm_rec.количество_на_складе, 0) < rm_rec.needed THEN v_missing_text := v_missing_text || rm_rec.наименование || ' (нужно ' || rm_rec.needed || ', есть ' || COALESCE(rm_rec.количество_на_складе, 0) || '); ';
END IF;
END LOOP;
END IF;
END LOOP;
IF v_missing_text != '' THEN status := 'ERROR';
message := 'Не хватает материалов для заготовок: ' || v_missing_text;
RETURN NEXT;
RETURN;
END IF;
-- All materials are sufficient. Proceed with inserting order item.
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
-- Deduct materials and create tasks
FOR r IN (
    SELECT si.id_заготовки,
        si.количество_заготовки
    FROM СоставИзделия si
    WHERE si.id_изделия = p_product_id
) LOOP v_needed_qty := COALESCE(r.количество_заготовки, 0) * p_qty;
SELECT количество_готовых INTO v_stock_qty
FROM Заготовка
WHERE id_заготовки = r.id_заготовки;
-- Deduct component stock immediately if available
IF COALESCE(v_stock_qty, 0) > 0 THEN
UPDATE Заготовка
SET количество_готовых = GREATEST(0, количество_готовых - v_needed_qty)
WHERE id_заготовки = r.id_заготовки;
END IF;
IF COALESCE(v_stock_qty, 0) < v_needed_qty THEN v_missing_qty := v_needed_qty - COALESCE(v_stock_qty, 0);
-- Deduct materials!
FOR rm_rec IN (
    SELECT sz.id_материала,
        (
            COALESCE(sz.количество_материала, 0) * v_missing_qty
        ) as needed
    FROM СоставЗаготовки sz
    WHERE sz.id_заготовки = r.id_заготовки
) LOOP
UPDATE Материал
SET количество_на_складе = количество_на_складе - rm_rec.needed
WHERE id_материала = rm_rec.id_материала;
END LOOP;
INSERT INTO ПланЗаготовок (
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
IF v_components_added > 0 THEN status := 'OK';
message := 'Товар добавлен. ' || v_components_added || ' заготовок добавлено в план';
ELSE status := 'OK';
message := 'Товар добавлен. Заготовок в план не добавлено (хватает на складе)';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;