





DROP FUNCTION IF EXISTS sp_get_all_materials();
CREATE OR REPLACE FUNCTION sp_get_all_materials() RETURNS TABLE (
        id_материала INTEGER,
        наименование VARCHAR,
        количество_на_складе INTEGER,
        единица_измерения VARCHAR,
        цена_закупки NUMERIC,
        минимальный_остаток INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT m.id_материала,
    m.наименование,
    m.количество_на_складе,
    m.единица_измерения,
    m.цена_закупки,
    m.минимальный_остаток
FROM Материал m
ORDER BY m.наименование;
END;
$$;


DROP FUNCTION IF EXISTS sp_get_product_components(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_product_components(p_product_id INTEGER) RETURNS TABLE (
        наименование VARCHAR,
        количество INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT z.наименование,
    si.количество_заготовки AS количество
FROM СоставИзделия si
    JOIN Заготовка z ON si.id_заготовки = z.id_заготовки
WHERE si.id_изделия = p_product_id
ORDER BY z.наименование;
END;
$$;


DROP FUNCTION IF EXISTS sp_get_purchase_items(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_purchase_items(p_purchase_id INTEGER) RETURNS TABLE (
        id_материала INTEGER,
        наименование VARCHAR,
        количество INTEGER,
        цена_закупки NUMERIC
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT m.id_материала,
    m.наименование,
    sz.количество,
    sz.цена_закупки
FROM СоставЗакупки sz
    JOIN Материал m ON sz.id_материала = m.id_материала
WHERE sz.id_закупки = p_purchase_id
ORDER BY m.наименование;
END;
$$;