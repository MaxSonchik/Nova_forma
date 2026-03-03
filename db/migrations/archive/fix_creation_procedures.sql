




DROP FUNCTION IF EXISTS sp_create_product(VARCHAR, VARCHAR, VARCHAR, VARCHAR, NUMERIC);
CREATE OR REPLACE FUNCTION sp_create_product(
        p_name VARCHAR,
        p_type VARCHAR,
        p_size VARCHAR,
        p_price NUMERIC
    ) RETURNS TABLE (
        status VARCHAR,
        message VARCHAR,
        id_изделия INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE new_id INTEGER;
BEGIN
INSERT INTO Изделие (
        наименование,
        тип,
        размеры,
        стоимость,
        количество_на_складе
    )
VALUES (p_name, p_type, p_size, p_price, 0)
RETURNING Изделие.id_изделия INTO new_id;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Изделие создано'::VARCHAR,
    new_id;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR,
    NULL::INTEGER;
END;
$$;


DROP FUNCTION IF EXISTS sp_create_material(VARCHAR, VARCHAR, INTEGER);
CREATE OR REPLACE FUNCTION sp_create_material(
        p_name VARCHAR,
        p_qty INTEGER DEFAULT 0,
        p_price NUMERIC DEFAULT 0,
        p_unit VARCHAR DEFAULT 'шт',
        p_min_stock INTEGER DEFAULT 10
    ) RETURNS TABLE (
        status VARCHAR,
        message VARCHAR,
        id_материала INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE new_id INTEGER;
BEGIN
INSERT INTO Материал (
        наименование,
        количество_на_складе,
        цена_за_единицу,
        единица_измерения,
        минимальный_остаток
    )
VALUES (p_name, p_qty, p_price, p_unit, p_min_stock)
RETURNING Материал.id_материала INTO new_id;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Материал создан'::VARCHAR,
    new_id;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR,
    NULL::INTEGER;
END;
$$;



DROP FUNCTION IF EXISTS sp_create_component(VARCHAR);
CREATE OR REPLACE FUNCTION sp_create_component(p_name VARCHAR) RETURNS TABLE (
        status VARCHAR,
        message VARCHAR,
        id_заготовки INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE new_id INTEGER;
BEGIN
INSERT INTO Заготовка (
        наименование,
        количество_готовых
    )
VALUES (p_name, 0)
RETURNING Заготовка.id_заготовки INTO new_id;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Заготовка создана'::VARCHAR,
    new_id;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR,
    NULL::INTEGER;
END;
$$;


DROP FUNCTION IF EXISTS sp_add_component_material(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_add_component_material(
        p_comp_id INTEGER,
        p_mat_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
INSERT INTO расход_материалов (id_заготовки, id_материала, количество_материала)
VALUES (p_comp_id, p_mat_id, p_qty) ON CONFLICT (id_заготовки, id_материала) DO
UPDATE
SET количество_материала = расход_материалов.количество_материала + p_qty;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Материал добавлен'::VARCHAR;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;
DROP FUNCTION IF EXISTS sp_update_component_material(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_update_component_material(
        p_comp_id INTEGER,
        p_mat_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE расход_материалов
SET количество_материала = p_qty
WHERE id_заготовки = p_comp_id
    AND id_материала = p_mat_id;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Количество обновлено'::VARCHAR;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;
DROP FUNCTION IF EXISTS sp_delete_component_material(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_delete_component_material(p_comp_id INTEGER, p_mat_id INTEGER) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
DELETE FROM расход_материалов
WHERE id_заготовки = p_comp_id
    AND id_материала = p_mat_id;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Материал удален из состава'::VARCHAR;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;

CREATE OR REPLACE FUNCTION sp_get_component_materials(p_comp_id INTEGER) RETURNS TABLE (
        id_материала INTEGER,
        наименование VARCHAR,
        количество INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT m.id_материала,
    m.наименование,
    rm.количество_материала
FROM расход_материалов rm
    JOIN Материал m ON rm.id_материала = m.id_материала
WHERE rm.id_заготовки = p_comp_id;
END;
$$;