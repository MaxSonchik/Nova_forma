

DROP FUNCTION IF EXISTS sp_get_warehouse_summary(VARCHAR, VARCHAR);
CREATE OR REPLACE FUNCTION sp_get_warehouse_summary(
        p_search_text VARCHAR DEFAULT NULL,
        p_type VARCHAR DEFAULT NULL
    ) RETURNS TABLE (
        тип VARCHAR,
        наименование VARCHAR,
        количество INTEGER,
        ед_изм VARCHAR,
        артикул VARCHAR
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY WITH warehouse_data AS (
        SELECT 'Материал'::VARCHAR as тип,
            наименование,
            количество_на_складе as количество,
            единица_измерения as ед_изм,
            артикул_материала as артикул
        FROM Материал
        UNION ALL
        SELECT 'Заготовка'::VARCHAR as тип,
            наименование,
            количество_на_складе as количество,
            'шт'::VARCHAR as ед_изм,
            '-'::VARCHAR as артикул
        FROM Заготовка
        UNION ALL
        SELECT 'Изделие'::VARCHAR as тип,
            наименование,
            количество_на_складе as количество,
            'шт'::VARCHAR as ед_изм,
            артикул_изделия as артикул
        FROM Изделие
    )
SELECT *
FROM warehouse_data wd
WHERE (
        p_search_text IS NULL
        OR LOWER(wd.наименование) LIKE LOWER('%' || p_search_text || '%')
        OR LOWER(wd.артикул) LIKE LOWER('%' || p_search_text || '%')
    )
    AND (
        p_type IS NULL
        OR wd.тип = p_type
    )
ORDER BY wd.тип,
    wd.наименование;
END;
$$;