-- Fix for sp_create_product function to remove SKU argument
-- Drops the old function with 5 arguments and creates a new one with 4 arguments.
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