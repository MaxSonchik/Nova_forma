
DROP FUNCTION IF EXISTS sp_create_order(integer, integer, date);
CREATE OR REPLACE FUNCTION sp_create_order(
        p_client_id integer,
        p_manager_id integer,
        p_deadline date
    ) RETURNS TABLE(
        status character varying,
        message character varying,
        id_заказа integer
    ) LANGUAGE plpgsql AS $function$
DECLARE new_id INTEGER;
BEGIN
INSERT INTO Заказ (
        id_клиента,
        id_менеджера,
        дата_заказа,
        дата_готовности,
        статус,
        сумма_заказа
    )
VALUES (
        p_client_id,
        p_manager_id,
        CURRENT_DATE,
        p_deadline,
        'принят',
        
        0
    )
RETURNING Заказ.id_заказа INTO new_id;
status := 'OK';
message := 'Заказ создан';
id_заказа := new_id;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка создания заказа: ' || SQLERRM;
id_заказа := NULL;
RETURN NEXT;
END;
$function$;