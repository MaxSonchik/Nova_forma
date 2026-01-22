-- Update sp_get_products to return full details
DROP FUNCTION IF EXISTS sp_get_products();
CREATE OR REPLACE FUNCTION sp_get_products() RETURNS TABLE (
        id_изделия INTEGER,
        артикул VARCHAR,
        наименование VARCHAR,
        тип VARCHAR,
        размеры VARCHAR,
        стоимость NUMERIC,
        количество_на_складе INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT i.id_изделия,
    i.артикул_изделия::VARCHAR AS артикул,
    i.наименование::VARCHAR AS наименование,
    COALESCE(i.тип, '')::VARCHAR AS тип,
    COALESCE(i.размеры, '')::VARCHAR AS размеры,
    i.стоимость,
    COALESCE(i.количество_на_складе, 0) AS количество_на_складе
FROM изделия i
ORDER BY i.наименование;
END;
$$;