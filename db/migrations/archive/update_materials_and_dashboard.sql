


DROP FUNCTION IF EXISTS sp_get_all_materials();
CREATE OR REPLACE FUNCTION sp_get_all_materials() RETURNS TABLE (
        id_материала INTEGER,
        наименование VARCHAR,
        количество_на_складе INTEGER,
        единица_измерения VARCHAR,
        артикул_материала VARCHAR,
        цена_закупки NUMERIC,
        минимальный_остаток INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT m.id_материала,
    m.наименование,
    m.количество_на_складе,
    m.единица_измерения,
    m.артикул_материала,
    m.цена_закупки,
    m.минимальный_остаток
FROM Материал m
ORDER BY m.наименование;
END;
$$;


DROP FUNCTION IF EXISTS sp_get_sales_chart_data();
CREATE OR REPLACE FUNCTION sp_get_sales_chart_data() RETURNS TABLE (d DATE, val NUMERIC) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT дата_заказа as d,
    SUM(сумма_заказа) as val
FROM Заказ
WHERE дата_заказа >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY дата_заказа
ORDER BY дата_заказа;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_profit_chart_data();
CREATE OR REPLACE FUNCTION sp_get_profit_chart_data() RETURNS TABLE (d DATE, val NUMERIC) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT дата_заказа as d,
    SUM(сумма_заказа) * 0.3 as val
FROM Заказ
WHERE дата_заказа >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY дата_заказа
ORDER BY дата_заказа;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_orders_count_chart_data();
CREATE OR REPLACE FUNCTION sp_get_orders_count_chart_data() RETURNS TABLE (
        d DATE,
        val BIGINT 
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT дата_заказа as d,
    COUNT(*) as val
FROM Заказ
WHERE дата_заказа >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY дата_заказа
ORDER BY дата_заказа;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_avg_check_chart_data();
CREATE OR REPLACE FUNCTION sp_get_avg_check_chart_data() RETURNS TABLE (d DATE, val NUMERIC) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT дата_заказа as d,
    AVG(сумма_заказа) as val
FROM Заказ
WHERE дата_заказа >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY дата_заказа
ORDER BY дата_заказа;
END;
$$;