

DROP FUNCTION IF EXISTS sp_get_order_items(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_order_items(p_order_id INTEGER) RETURNS TABLE (
        id_изделия INTEGER,
        наименование VARCHAR,
        количество INTEGER,
        цена NUMERIC,
        сумма NUMERIC
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT sz.id_изделия,
    i.наименование::VARCHAR,
    sz.количество_изделий,
    sz.цена_фиксированная,
    (sz.количество_изделий * sz.цена_фиксированная)::NUMERIC
FROM СоставЗаказа sz
    JOIN Изделие i ON sz.id_изделия = i.id_изделия
WHERE sz.id_заказа = p_order_id;
END;
$$;