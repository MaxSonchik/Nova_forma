CREATE OR REPLACE FUNCTION sp_calculate_product_stock() RETURNS TABLE (
        id_изделия INTEGER,
        наименование VARCHAR,
        расчетный_остаток INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT i.id_изделия,
    i.наименование,
    COALESCE(
        MIN(
            FLOOR(z.количество_готовых / si.количество_заготовки)
        ),
        0
    )::INTEGER AS расчетный_остаток
FROM Изделие i
    JOIN СоставИзделия si ON i.id_изделия = si.id_изделия
    JOIN Заготовка z ON si.id_заготовки = z.id_заготовки
GROUP BY i.id_изделия,
    i.наименование
ORDER BY i.наименование;
END;
$$;