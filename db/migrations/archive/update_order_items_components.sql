
CREATE OR REPLACE FUNCTION sp_get_order_items(p_order_id INTEGER) RETURNS TABLE (
        id_изделия INTEGER,
        наименование VARCHAR,
        количество INTEGER,
        цена NUMERIC,
        сумма NUMERIC
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT sz.id_изделия,
    i.наименование,
    sz.количество_изделий AS количество,
    i.стоимость AS цена,
    (sz.количество_изделий * i.стоимость) AS сумма
FROM СоставЗаказа sz
    JOIN Изделие i ON sz.id_изделия = i.id_изделия
WHERE sz.id_заказа = p_order_id;
END;
$$;

CREATE OR REPLACE FUNCTION sp_get_product_components_status(p_order_id INTEGER, p_product_id INTEGER) RETURNS TABLE (
        наименование_заготовки VARCHAR,
        требуется INTEGER,
        выполнено INTEGER,
        осталось INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE v_product_qty INTEGER;
BEGIN 
SELECT количество_изделий INTO v_product_qty
FROM СоставЗаказа
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;
IF v_product_qty IS NULL THEN RETURN;
END IF;
RETURN QUERY
SELECT z.наименование::VARCHAR,
    (si.количество_заготовки * v_product_qty)::INTEGER AS требуется,
    COALESCE(SUM(pp.фактическое_количество), 0)::INTEGER AS выполнено,
    GREATEST(
        0,
        (si.количество_заготовки * v_product_qty) - COALESCE(SUM(pp.фактическое_количество), 0)
    )::INTEGER AS осталось
FROM СоставИзделия si
    JOIN Заготовка z ON si.id_заготовки = z.id_заготовки
    LEFT JOIN ПланПроизводства pp ON pp.id_заказа = p_order_id
    AND pp.id_заготовки = si.id_заготовки
WHERE si.id_изделия = p_product_id
GROUP BY z.наименование,
    si.количество_заготовки;
END;
$$;