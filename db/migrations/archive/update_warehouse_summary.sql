CREATE OR REPLACE FUNCTION sp_get_warehouse_summary(
        p_search VARCHAR DEFAULT NULL,
        p_type VARCHAR DEFAULT NULL
    ) RETURNS TABLE (
        тип VARCHAR,
        наименование VARCHAR,
        количество INTEGER,
        ед_изм VARCHAR
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT base.тип,
    base.наименование,
    base.количество,
    base.ед_изм
FROM (
        
        SELECT 'Материал'::VARCHAR as тип,
            m.наименование,
            m.количество_на_складе as количество,
            m.единица_измерения as ед_изм
        FROM Материал m
        UNION ALL
        
        SELECT 'Заготовка'::VARCHAR,
            z.наименование,
            z.количество_готовых,
            'шт'::VARCHAR
        FROM Заготовка z
        UNION ALL
        
        SELECT 'Изделие'::VARCHAR,
            p.наименование,
            p.расчетный_остаток,
            'шт'::VARCHAR
        FROM sp_calculate_product_stock() p
    ) AS base
WHERE (
        p_type IS NULL
        OR base.тип = p_type
    )
    AND (
        p_search IS NULL
        OR LOWER(base.наименование) LIKE '%' || LOWER(p_search) || '%'
    )
ORDER BY base.наименование;
END;
$$;