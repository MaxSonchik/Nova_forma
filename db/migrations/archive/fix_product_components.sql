
DROP FUNCTION IF EXISTS sp_get_product_components(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_product_components(p_product_id INTEGER) RETURNS TABLE (
        id_заготовки INTEGER,
        наименование VARCHAR,
        количество INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT z.id_заготовки,
    z.наименование,
    si.количество_заготовки AS количество
FROM СоставИзделия si
    JOIN Заготовка z ON si.id_заготовки = z.id_заготовки
WHERE si.id_изделия = p_product_id
ORDER BY z.наименование;
END;
$$;