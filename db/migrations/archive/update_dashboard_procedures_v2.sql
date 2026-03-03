


DROP FUNCTION IF EXISTS sp_get_dashboard_summary(DATE, DATE);
CREATE OR REPLACE FUNCTION sp_get_dashboard_summary(p_start DATE, p_end DATE) RETURNS TABLE (
        revenue NUMERIC,
        orders_count INTEGER,
        expenses NUMERIC,
        cancels INTEGER,
        staff_count INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT (
        SELECT COALESCE(SUM(сумма_заказа), 0)
        FROM Заказ
        WHERE статус IN ('выполнен', 'завершен', 'отгружен')
            AND дата_заказа BETWEEN p_start AND p_end
    ) as revenue,
    (
        SELECT COUNT(*)::INTEGER
        FROM Заказ
        WHERE статус IN ('выполнен', 'завершен', 'отгружен')
            AND дата_заказа BETWEEN p_start AND p_end
    ) as orders_count,
    (
        SELECT COALESCE(SUM(sz.количество * sz.цена_закупки), 0)
        FROM Закупка zm
            JOIN СоставЗакупки sz ON zm.id_закупки = sz.id_закупки
        WHERE zm.статус = 'выполнено'
            AND zm.дата_закупки BETWEEN p_start AND p_end
    ) as expenses,
    (
        SELECT COUNT(*)::INTEGER
        FROM Заказ
        WHERE статус = 'отменен'
            AND дата_заказа BETWEEN p_start AND p_end
    ) as cancels,
    (
        SELECT COUNT(*)::INTEGER
        FROM Сотрудник
        WHERE дата_увольнения IS NULL
    ) as staff_count;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_sales_chart_data(DATE, DATE);
CREATE OR REPLACE FUNCTION sp_get_sales_chart_data(p_start DATE, p_end DATE) RETURNS TABLE (d DATE, val NUMERIC) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT дата_заказа as d,
    SUM(сумма_заказа) as val
FROM Заказ
WHERE статус IN ('выполнен', 'завершен', 'отгружен')
    AND дата_заказа BETWEEN p_start AND p_end
GROUP BY дата_заказа
ORDER BY дата_заказа;
END;
$$;
DROP FUNCTION IF EXISTS sp_get_expenses_chart_data(DATE, DATE);
CREATE OR REPLACE FUNCTION sp_get_expenses_chart_data(p_start DATE, p_end DATE) RETURNS TABLE (d DATE, val NUMERIC) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT zm.дата_закупки as d,
    SUM(sz.количество * sz.цена_закупки) as val
FROM Закупка zm
    JOIN СоставЗакупки sz ON zm.id_закупки = sz.id_закупки
WHERE zm.статус = 'выполнено'
    AND zm.дата_закупки BETWEEN p_start AND p_end
GROUP BY zm.дата_закупки
ORDER BY zm.дата_закупки;
END;
$$;
DROP FUNCTION IF EXISTS sp_get_profit_chart_data(DATE, DATE);
CREATE OR REPLACE FUNCTION sp_get_profit_chart_data(p_start DATE, p_end DATE) RETURNS TABLE (d DATE, val NUMERIC) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT дата_заказа as d,
    SUM(сумма_заказа) * 0.3 as val
FROM Заказ
WHERE статус IN ('выполнен', 'завершен', 'отгружен')
    AND дата_заказа BETWEEN p_start AND p_end
GROUP BY дата_заказа
ORDER BY дата_заказа;
END;
$$;
DROP FUNCTION IF EXISTS sp_get_orders_count_chart_data(DATE, DATE);
CREATE OR REPLACE FUNCTION sp_get_orders_count_chart_data(p_start DATE, p_end DATE) RETURNS TABLE (d DATE, val BIGINT) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT дата_заказа as d,
    COUNT(*) as val
FROM Заказ
WHERE статус IN ('выполнен', 'завершен', 'отгружен')
    AND дата_заказа BETWEEN p_start AND p_end
GROUP BY дата_заказа
ORDER BY дата_заказа;
END;
$$;
DROP FUNCTION IF EXISTS sp_get_avg_check_chart_data(DATE, DATE);
CREATE OR REPLACE FUNCTION sp_get_avg_check_chart_data(p_start DATE, p_end DATE) RETURNS TABLE (d DATE, val NUMERIC) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT дата_заказа as d,
    AVG(сумма_заказа) as val
FROM Заказ
WHERE статус IN ('выполнен', 'завершен', 'отгружен')
    AND дата_заказа BETWEEN p_start AND p_end
GROUP BY дата_заказа
ORDER BY дата_заказа;
END;
$$;
DROP FUNCTION IF EXISTS sp_get_cancel_rate_chart_data(DATE, DATE);
CREATE OR REPLACE FUNCTION sp_get_cancel_rate_chart_data(p_start DATE, p_end DATE) RETURNS TABLE (d DATE, val NUMERIC) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT дата_заказа as d,
    (
        COUNT(*) FILTER (
            WHERE статус = 'отменен'
        )::numeric / NULLIF(COUNT(*), 0)
    ) * 100 as val
FROM Заказ
WHERE дата_заказа BETWEEN p_start AND p_end
GROUP BY дата_заказа
ORDER BY дата_заказа;
END;
$$;