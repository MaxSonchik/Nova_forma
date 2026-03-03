

CREATE OR REPLACE FUNCTION sp_add_product_component(
        p_prod_id integer,
        p_comp_id integer,
        p_qty integer
    ) RETURNS TABLE(
        status character varying,
        message character varying
    ) LANGUAGE plpgsql AS $function$ BEGIN
INSERT INTO СоставИзделия (id_изделия, id_заготовки, количество_заготовки)
VALUES (p_prod_id, p_comp_id, p_qty) ON CONFLICT (id_изделия, id_заготовки) DO
UPDATE
SET количество_заготовки = СоставИзделия.количество_заготовки + p_qty;

RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Заготовка добавлена'::VARCHAR;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$function$;

CREATE OR REPLACE FUNCTION sp_update_product_component(
        p_prod_id integer,
        p_comp_id integer,
        p_qty integer
    ) RETURNS TABLE(
        status character varying,
        message character varying
    ) LANGUAGE plpgsql AS $function$ BEGIN
UPDATE СоставИзделия
SET количество_заготовки = p_qty
WHERE id_изделия = p_prod_id
    AND id_заготовки = p_comp_id;
IF NOT FOUND THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    'Заготовка не найдена в составе'::VARCHAR;
ELSE RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Количество обновлено'::VARCHAR;
END IF;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$function$;