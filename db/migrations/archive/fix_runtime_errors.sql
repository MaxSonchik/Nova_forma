
DROP FUNCTION IF EXISTS sp_get_employees();
CREATE OR REPLACE FUNCTION sp_get_employees() RETURNS TABLE (
        id_сотрудника INTEGER,
        фио VARCHAR,
        должность VARCHAR,
        login VARCHAR,
        дата_увольнения DATE,
        номер_телефона VARCHAR,
        зарплата NUMERIC
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT s.id_сотрудника,
    s.фио,
    s.должность,
    s.login,
    s.дата_увольнения,
    s.номер_телефона,
    s.зарплата
FROM Сотрудник s
ORDER BY s.дата_увольнения NULLS FIRST,
    s.фио;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_components();
CREATE OR REPLACE FUNCTION sp_get_components() RETURNS TABLE (
        id_заготовки INTEGER,
        артикул_заготовки VARCHAR,
        наименование VARCHAR,
        количество_на_складе INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT z.id_заготовки,
    z.артикул_заготовки,
    z.наименование,
    z.количество_готовых 
FROM Заготовка z
ORDER BY z.наименование;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_all_components();
CREATE OR REPLACE FUNCTION sp_get_all_components() RETURNS TABLE (
        id_заготовки INTEGER,
        наименование VARCHAR,
        количество_на_складе INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT z.id_заготовки,
    z.наименование,
    z.количество_готовых 
FROM Заготовка z;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_warehouse_summary(VARCHAR, VARCHAR);
CREATE OR REPLACE FUNCTION sp_get_warehouse_summary(
        p_search VARCHAR DEFAULT NULL,
        p_type VARCHAR DEFAULT NULL
    ) RETURNS TABLE (
        тип VARCHAR,
        наименование VARCHAR,
        количество INTEGER,
        ед_изм VARCHAR,
        артикул VARCHAR
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT base.тип,
    base.наименование,
    base.количество,
    base.ед_изм,
    base.артикул
FROM (
        SELECT 'Материал'::VARCHAR as тип,
            m.наименование,
            m.количество_на_складе as количество,
            m.единица_измерения as ед_изм,
            m.артикул_материала as артикул
        FROM Материал m
        UNION ALL
        SELECT 'Заготовка'::VARCHAR,
            z.наименование,
            z.количество_готовых,
            
            'шт'::VARCHAR,
            '-'::VARCHAR
        FROM Заготовка z
        UNION ALL
        SELECT 'Изделие'::VARCHAR,
            i.наименование,
            i.количество_на_складе,
            'шт'::VARCHAR,
            i.артикул_изделия
        FROM Изделие i
    ) AS base
WHERE (
        p_type IS NULL
        OR base.тип = p_type
    )
    AND (
        p_search IS NULL
        OR LOWER(base.наименование) LIKE '%' || LOWER(p_search) || '%'
        OR LOWER(base.артикул) LIKE '%' || LOWER(p_search) || '%'
    )
ORDER BY base.наименование;
END;
$$;

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
SELECT v.id_задачи AS id_заготовки,
    v.id_заказа,
    v.наименование_задачи AS заготовка,
    v.плановое_количество,
    v.фактическое_количество,
    v.дата_план AS дедлайн,
    v.статус,
    COALESCE(s.фио, 'Не назначен')::VARCHAR AS сборщик,
    v.тип_задачи,
    v.id_объекта
FROM v_задачи_сборщика v
    LEFT JOIN Сотрудник s ON v.id_сборщика = s.id_сотрудника 
ORDER BY v.дата_план ASC;
END;
$$;