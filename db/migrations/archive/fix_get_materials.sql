
DROP FUNCTION IF EXISTS sp_get_all_materials();
CREATE OR REPLACE FUNCTION sp_get_all_materials() RETURNS TABLE (
        id_материала INTEGER,
        наименование VARCHAR,
        количество_на_складе INTEGER,
        единица_измерения VARCHAR,
        минимальный_остаток INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT m.id_материала,
    m.наименование,
    m.количество_на_складе,
    m.единица_измерения,
    
    m.минимальный_остаток
FROM Материал m
ORDER BY m.наименование;
END;
$$;