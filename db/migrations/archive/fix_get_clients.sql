CREATE OR REPLACE FUNCTION sp_get_clients() RETURNS TABLE (
        id_клиента INTEGER,
        фио VARCHAR,
        номер_телефона VARCHAR,
        адрес TEXT,
        дата_регистрации DATE,
        инн VARCHAR
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT k.id_клиента,
    k.фио,
    k.номер_телефона,
    k.адрес,
    k.дата_регистрации,
    k.инн
FROM Клиент k
ORDER BY k.фио;
END;
$$;