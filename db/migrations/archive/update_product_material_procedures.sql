DROP FUNCTION IF EXISTS sp_create_product(VARCHAR, VARCHAR, VARCHAR, VARCHAR, NUMERIC);
CREATE OR REPLACE FUNCTION sp_create_product(
        p_sku VARCHAR,
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
        артикул_изделия,
        наименование,
        тип,
        размеры,
        стоимость,
        количество_на_складе
    )
VALUES (p_sku, p_name, p_type, p_size, p_price, 0)
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
DROP FUNCTION IF EXISTS sp_update_product(INTEGER, VARCHAR, NUMERIC);
CREATE OR REPLACE FUNCTION sp_update_product(
        p_id INTEGER,
        p_name VARCHAR,
        p_price NUMERIC
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE Изделие
SET наименование = p_name,
    стоимость = p_price
WHERE id_изделия = p_id;
IF FOUND THEN RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Изделие обновлено'::VARCHAR;
ELSE RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    'Изделие не найдено'::VARCHAR;
END IF;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;
DROP FUNCTION IF EXISTS sp_add_product_component(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_add_product_component(
        p_prod_id INTEGER,
        p_comp_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
INSERT INTO СоставИзделия (id_изделия, id_заготовки, количество_заготовок)
VALUES (p_prod_id, p_comp_id, p_qty) ON CONFLICT (id_изделия, id_заготовки) DO
UPDATE
SET количество_заготовок = СоставИзделия.количество_заготовок + p_qty;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Заготовка добавлена'::VARCHAR;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;
DROP FUNCTION IF EXISTS sp_update_product_component(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_update_product_component(
        p_prod_id INTEGER,
        p_comp_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE СоставИзделия
SET количество_заготовок = p_qty
WHERE id_изделия = p_prod_id
    AND id_заготовки = p_comp_id;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Количество обновлено'::VARCHAR;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;
DROP FUNCTION IF EXISTS sp_delete_product_component(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_delete_product_component(p_prod_id INTEGER, p_comp_id INTEGER) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
DELETE FROM СоставИзделия
WHERE id_изделия = p_prod_id
    AND id_заготовки = p_comp_id;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Заготовка удалена из состава'::VARCHAR;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
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
DROP FUNCTION IF EXISTS sp_update_component(INTEGER, VARCHAR);
CREATE OR REPLACE FUNCTION sp_update_component(p_id INTEGER, p_name VARCHAR) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE Заготовка
SET наименование = p_name
WHERE id_заготовки = p_id;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Заготовка обновлена'::VARCHAR;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;
DROP FUNCTION IF EXISTS sp_add_component_material(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_add_component_material(
        p_comp_id INTEGER,
        p_mat_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
INSERT INTO СоставЗаготовки (id_заготовки, id_материала, количество_материала)
VALUES (p_comp_id, p_mat_id, p_qty) ON CONFLICT (id_заготовки, id_материала) DO
UPDATE
SET количество_материала = СоставЗаготовки.количество_материала + p_qty;
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
UPDATE СоставЗаготовки
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
DELETE FROM СоставЗаготовки
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
DROP FUNCTION IF EXISTS sp_create_material(VARCHAR, VARCHAR, INTEGER);
CREATE OR REPLACE FUNCTION sp_create_material(
        p_article VARCHAR,
        p_name VARCHAR,
        p_qty INTEGER DEFAULT 0
    ) RETURNS TABLE (
        status VARCHAR,
        message VARCHAR,
        id_материала INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE new_id INTEGER;
BEGIN
INSERT INTO Материал (
        артикул_материала,
        наименование,
        количество_на_складе
    )
VALUES (p_article, p_name, p_qty)
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