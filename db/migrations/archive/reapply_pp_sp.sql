

DROP FUNCTION IF EXISTS sp_get_production_plan_full();
CREATE OR REPLACE FUNCTION sp_get_production_plan_full() RETURNS TABLE (
        id_плана INTEGER,
        id_заказа INTEGER,
        заготовка VARCHAR,
        плановое_количество INTEGER,
        фактическое_количество INTEGER,
        дедлайн DATE,
        статус VARCHAR,
        сборщик VARCHAR,
        id_сотрудника INTEGER,
        id_заготовки INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT pz.id_плана,
    pz.id_заказа,
    z.наименование AS заготовка,
    pz.плановое_количество,
    pz.фактическое_количество,
    pz.дата_план AS дедлайн,
    pz.статус,
    COALESCE(s.фио, 'Не назначен')::VARCHAR as сборщик,
    pz.id_сотрудника,
    pz.id_заготовки
FROM ПланЗаготовок pz
    JOIN Заготовка z ON pz.id_заготовки = z.id_заготовки
    LEFT JOIN Сотрудник s ON pz.id_сотрудника = s.id_сотрудника
ORDER BY CASE
        WHEN pz.статус = 'выполнено' THEN 1
        ELSE 0
    END,
    pz.дата_план ASC;
END;
$$;