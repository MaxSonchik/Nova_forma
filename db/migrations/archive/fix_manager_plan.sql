

DROP FUNCTION IF EXISTS sp_get_production_plan_full();
CREATE OR REPLACE FUNCTION sp_get_production_plan_full() RETURNS TABLE (
        id_заготовки INTEGER,
        id_заказа INTEGER,
        заготовка VARCHAR,
        плановое_количество INTEGER,
        фактическое_количество INTEGER,
        дедлайн DATE,
        статус VARCHAR,
        сборщик VARCHAR,
        тип_задачи VARCHAR,
        
        id_объекта INTEGER 
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT v.id_задачи as id_заготовки,
    
    v.id_заказа,
    v.наименование_задачи as заготовка,
    v.плановое_количество,
    v.фактическое_количество,
    v.дата_план as дедлайн,
    v.статус,
    COALESCE(s.фио, 'Не назначен')::VARCHAR as сборщик,
    v.тип_задачи,
    v.id_объекта
FROM v_задачи_сборщика v
    LEFT JOIN Сотрудник s ON v.id_сборщика = s.id_сотрудника
ORDER BY v.дата_план ASC;
END;
$$;