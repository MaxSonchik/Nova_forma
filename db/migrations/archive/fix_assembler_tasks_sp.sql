

DROP FUNCTION IF EXISTS sp_get_assembler_tasks();
CREATE OR REPLACE FUNCTION sp_get_assembler_tasks() RETURNS TABLE (
        тип_задачи VARCHAR,
        id_объекта INTEGER,
        id_заказа INTEGER,
        наименование_задачи VARCHAR,
        плановое_количество INTEGER,
        фактическое_количество INTEGER,
        дедлайн DATE,
        статус VARCHAR,
        id_сборщика INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT 'заготовка'::VARCHAR as тип_задачи,
    pz.id_заготовки as id_объекта,
    pz.id_заказа,
    z.наименование as наименование_задачи,
    pz.плановое_количество,
    pz.фактическое_количество,
    pz.дата_план as дедлайн,
    pz.статус,
    pz.id_сотрудника as id_сборщика
FROM ПланЗаготовок pz
    JOIN Заготовка z ON pz.id_заготовки = z.id_заготовки
ORDER BY pz.дата_план;
END;
$$;