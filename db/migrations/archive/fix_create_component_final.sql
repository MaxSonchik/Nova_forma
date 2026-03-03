-- Fix for sp_create_component function
-- Removes incorrect values (0, 0) for just 2 columns.
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
VALUES (p_name, 0) -- Corrected: 2 values for 2 columns
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