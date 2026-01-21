CREATE OR REPLACE PROCEDURE sp_установить_статус_дня(
    p_id_сотрудника INTEGER,
    p_дата DATE,
    p_статус VARCHAR
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO график_работы (id_сотрудника, дата, статус)
    VALUES (p_id_сотрудника, p_дата, p_статус)
    ON CONFLICT (id_сотрудника, дата) 
    DO UPDATE SET статус = p_статус;
END;
$$;