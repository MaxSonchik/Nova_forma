
DROP FUNCTION IF EXISTS sp_search_clients(VARCHAR);
CREATE OR REPLACE FUNCTION sp_search_clients(p_query VARCHAR) RETURNS TABLE (
        id_клиента INTEGER,
        фио VARCHAR,
        номер_телефона VARCHAR,
        адрес TEXT,
        дата_регистрации DATE,
        инн VARCHAR
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT c.id_клиента,
    c.фио,
    c.номер_телефона,
    c.адрес,
    c.дата_регистрации,
    c.инн
FROM Клиент c
WHERE LOWER(c.фио) LIKE LOWER(p_query)
    OR LOWER(c.номер_телефона) LIKE LOWER(p_query)
ORDER BY c.фио;
END;
$$;