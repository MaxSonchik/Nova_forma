-- Fix warehouse summary: match actual live schema columns
-- Материал: id_материала, наименование, количество_на_складе, единица_измерения, минимальный_остаток, цена_за_единицу
-- Заготовка: id_заготовки, наименование, количество_готовых, описание
-- Изделие: id_изделия, наименование, тип, размеры, стоимость, количество_на_складе
DROP FUNCTION IF EXISTS sp_get_warehouse_summary(VARCHAR, VARCHAR);
CREATE OR REPLACE FUNCTION sp_get_warehouse_summary(
        p_search_text VARCHAR DEFAULT NULL,
        p_type VARCHAR DEFAULT NULL
    ) RETURNS TABLE (
        id_объекта INTEGER,
        тип VARCHAR,
        наименование VARCHAR,
        количество INTEGER,
        ед_изм VARCHAR
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY WITH warehouse_data AS (
        SELECT m.id_материала as id_объекта,
            'Материал'::VARCHAR as тип,
            m.наименование,
            m.количество_на_складе as количество,
            m.единица_измерения as ед_изм
        FROM Материал m
        UNION ALL
        SELECT z.id_заготовки as id_объекта,
            'Заготовка'::VARCHAR as тип,
            z.наименование,
            z.количество_готовых as количество,
            'шт'::VARCHAR as ед_изм
        FROM Заготовка z
        UNION ALL
        SELECT i.id_изделия as id_объекта,
            'Изделие'::VARCHAR as тип,
            i.наименование,
            i.количество_на_складе as количество,
            'шт'::VARCHAR as ед_изм
        FROM Изделие i
    )
SELECT *
FROM warehouse_data wd
WHERE (
        p_search_text IS NULL
        OR LOWER(wd.наименование) LIKE LOWER('%' || p_search_text || '%')
    )
    AND (
        p_type IS NULL
        OR wd.тип = p_type
    )
ORDER BY wd.тип,
    wd.наименование;
END;
$$;