CREATE OR REPLACE FUNCTION sp_get_product_components_status(p_order_id INTEGER, p_product_id INTEGER) RETURNS TABLE (
        наименование_заготовки VARCHAR,
        требуется INTEGER,
        выполнено INTEGER,
        осталось INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE v_product_qty INTEGER;
BEGIN 
SELECT COALESCE(sz.количество_изделий, 0) INTO v_product_qty
FROM СоставЗаказа sz
WHERE sz.id_заказа = p_order_id
    AND sz.id_изделия = p_product_id;
IF v_product_qty IS NULL
OR v_product_qty = 0 THEN RETURN;
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
    LEFT JOIN "ПланПроизводства" pp ON pp.id_заказа = p_order_id
    AND pp.id_заготовки = si.id_заготовки
WHERE si.id_изделия = p_product_id
GROUP BY z.наименование,
    si.количество_заготовки;
END;
$$;