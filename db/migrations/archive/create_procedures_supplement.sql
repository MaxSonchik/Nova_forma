















DROP FUNCTION IF EXISTS sp_get_employees();
CREATE OR REPLACE FUNCTION sp_get_employees() RETURNS TABLE (
        id_сотрудника INTEGER,
        фио VARCHAR,
        должность VARCHAR,
        login VARCHAR,
        дата_увольнения DATE
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT s.id_сотрудника,
    s.фио,
    s.должность,
    s.login,
    s.дата_увольнения
FROM Сотрудник s
ORDER BY s.дата_увольнения NULLS FIRST,
    s.фио;
END;
$$;
DROP FUNCTION IF EXISTS sp_get_workers();
CREATE OR REPLACE FUNCTION sp_get_workers() RETURNS TABLE (
        id_сотрудника INTEGER,
        фио VARCHAR,
        должность VARCHAR
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT s.id_сотрудника,
    s.фио,
    s.должность
FROM Сотрудник s
WHERE s.дата_увольнения IS NULL
ORDER BY s.фио;
END;
$$;
DROP FUNCTION IF EXISTS sp_get_schedule(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_schedule(p_employee_id INTEGER) RETURNS TABLE (дата DATE, статус VARCHAR) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT График.дата,
    График.статус
FROM График
WHERE id_сотрудника = p_employee_id;
END;
$$;



DROP FUNCTION IF EXISTS sp_get_components();
CREATE OR REPLACE FUNCTION sp_get_components() RETURNS TABLE (
        id_заготовки INTEGER,
        наименование VARCHAR,
        количество_на_складе INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT z.id_заготовки,
    z.наименование,
    z.количество_на_складе
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
SELECT *
FROM sp_get_components();
END;
$$;
DROP FUNCTION IF EXISTS sp_get_product_components(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_product_components(p_product_id INTEGER) RETURNS TABLE (
        id_заготовки INTEGER,
        наименование VARCHAR,
        количество INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT si.id_заготовки,
    z.наименование,
    si.количество_заготовок
FROM СоставИзделия si
    JOIN Заготовка z ON si.id_заготовки = z.id_заготовки
WHERE si.id_изделия = p_product_id;
END;
$$;
DROP FUNCTION IF EXISTS sp_get_component_materials(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_component_materials(p_component_id INTEGER) RETURNS TABLE (
        id_материала INTEGER,
        наименование VARCHAR,
        количество INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT sz.id_материала,
    m.наименование,
    sz.количество_материала
FROM СоставЗаготовки sz
    JOIN Материал m ON sz.id_материала = m.id_материала
WHERE sz.id_заготовки = p_component_id;
END;
$$;
DROP FUNCTION IF EXISTS sp_get_assembler_tasks();
CREATE OR REPLACE FUNCTION sp_get_assembler_tasks() RETURNS TABLE (
        id_плана INTEGER,
        изделие VARCHAR,
        количество INTEGER,
        дата_план DATE,
        статус VARCHAR
    ) LANGUAGE plpgsql AS $$ BEGIN 
    RETURN QUERY
SELECT ps.id_плана,
    i.наименование as изделие,
    ps.количество_план as количество,
    ps.дата_план,
    ps.статус
FROM ПланСборки ps
    JOIN Изделие i ON ps.id_изделия = i.id_изделия
WHERE ps.статус != 'выполнено'
ORDER BY ps.дата_план;
END;
$$;
DROP FUNCTION IF EXISTS sp_get_production_plan_full();
CREATE OR REPLACE FUNCTION sp_get_production_plan_full() RETURNS TABLE (
        id_плана INTEGER,
        тип VARCHAR,
        наименование VARCHAR,
        план INTEGER,
        факт INTEGER,
        дата DATE,
        статус VARCHAR,
        исполнитель VARCHAR
    ) LANGUAGE plpgsql AS $$ BEGIN 
    
    
    RETURN QUERY
SELECT ps.id_плана,
    'Сборка'::VARCHAR as тип,
    i.наименование,
    ps.количество_план,
    ps.количество_факт,
    ps.дата_план,
    ps.статус,
    COALESCE(s.фио, '-') as исполнитель
FROM ПланСборки ps
    JOIN Изделие i ON ps.id_изделия = i.id_изделия
    LEFT JOIN Сотрудник s ON ps.id_сотрудника = s.id_сотрудника;
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
SELECT *
FROM (
        SELECT 'Материал'::VARCHAR as тип,
            наименование,
            количество_на_складе as количество,
            единица_измерения as ед_изм,
            артикул_материала as артикул
        FROM Материал
        UNION ALL
        SELECT 'Заготовка'::VARCHAR,
            наименование,
            количество_на_складе,
            'шт'::VARCHAR,
            '-'::VARCHAR
        FROM Заготовка
        UNION ALL
        SELECT 'Изделие'::VARCHAR,
            наименование,
            количество_на_складе,
            'шт'::VARCHAR,
            артикул_изделия
        FROM Изделие
    ) AS base
WHERE (
        p_type IS NULL
        OR base.тип = p_type
    )
    AND (
        p_search IS NULL
        OR LOWER(base.наименование) LIKE '%' || LOWER(p_search) || '%'
        OR LOWER(base.артикул) LIKE '%' || LOWER(p_search) || '%'
    );
END;
$$;
DROP FUNCTION IF EXISTS sp_get_purchases();
CREATE OR REPLACE FUNCTION sp_get_purchases() RETURNS TABLE (
        id_закупки INTEGER,
        дата_закупки DATE,
        поставщик VARCHAR,
        статус VARCHAR,
        сумма NUMERIC
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT z.id_закупки,
    z.дата_закупки,
    z.поставщик,
    z.статус,
    (
        SELECT COALESCE(SUM(количество * цена_закупки), 0)
        FROM СоставЗакупки sz
        WHERE sz.id_закупки = z.id_закупки
    ) as сумма
FROM Закупка z
ORDER BY z.дата_закупки DESC;
END;
$$;
DROP FUNCTION IF EXISTS sp_get_purchase_items(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_purchase_items(p_purchase_id INTEGER) RETURNS TABLE (
        id_материала INTEGER,
        наименование VARCHAR,
        количество INTEGER,
        цена NUMERIC
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT sz.id_материала,
    m.наименование,
    sz.количество,
    sz.цена_закупки
FROM СоставЗакупки sz
    JOIN Материал m ON sz.id_материала = m.id_материала
WHERE sz.id_закупки = p_purchase_id;
END;
$$;



DROP FUNCTION IF EXISTS sp_get_dashboard_counts();
CREATE OR REPLACE FUNCTION sp_get_dashboard_counts() RETURNS TABLE (
        orders_count INTEGER,
        revenue NUMERIC,
        employees_count INTEGER,
        products_count INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT (
        SELECT COUNT(*)::INTEGER
        FROM Заказ
    ),
    (
        SELECT COALESCE(SUM(сумма_заказа), 0)
        FROM Заказ
    ),
    (
        SELECT COUNT(*)::INTEGER
        FROM Сотрудник
        WHERE дата_увольнения IS NULL
    ),
    (
        SELECT COUNT(*)::INTEGER
        FROM Изделие
    );
END;
$$;