-- Rewritten sp_search_orders to fetch directly from tables (bypassing view)
-- to ensure maximum robustness against missing data or view definition issues.
DROP FUNCTION IF EXISTS sp_search_orders(INTEGER, VARCHAR, VARCHAR, DATE, DATE);
CREATE OR REPLACE FUNCTION sp_search_orders(
        p_manager_id INTEGER,
        p_search_text VARCHAR DEFAULT NULL,
        p_status VARCHAR DEFAULT 'Все статусы',
        p_date_from DATE DEFAULT NULL,
        p_date_to DATE DEFAULT NULL
    ) RETURNS TABLE (
        id_заказа INTEGER,
        клиент VARCHAR,
        менеджер VARCHAR,
        дата_заказа DATE,
        дата_готовности DATE,
        статус_заказа VARCHAR,
        сумма_заказа NUMERIC,
        позиций_в_заказе BIGINT,
        состояние_сроков TEXT
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT z.id_заказа,
    COALESCE(k.фио, 'Неизвестный клиент')::VARCHAR AS клиент,
    COALESCE(s.фио, '—')::VARCHAR AS менеджер,
    z.дата_заказа,
    z.дата_готовности,
    z.статус::VARCHAR AS статус_заказа,
    COALESCE(z.сумма_заказа, 0)::NUMERIC AS сумма_заказа,
    (
        SELECT COUNT(*)
        FROM состав_заказа sz
        WHERE sz.id_заказа = z.id_заказа
    )::BIGINT AS позиций_в_заказе,
    CASE
        WHEN z.статус = 'выполнено' THEN 'Готов к отгрузке'
        WHEN z.статус = 'отменен' THEN 'Отмена'
        WHEN z.статус = 'завершен' THEN 'Завершен'
        WHEN z.статус = 'отгружен' THEN 'Отгружен'
        WHEN z.дата_готовности < CURRENT_DATE
        AND z.статус NOT IN ('выполнено', 'отгружен', 'завершен', 'отменен') THEN 'ПРОСРОЧЕН'
        ELSE 'В норме'
    END::TEXT AS состояние_сроков
FROM заказы z
    LEFT JOIN клиенты k ON z.id_клиента = k.id_клиента
    LEFT JOIN сотрудники s ON z.id_менеджера = s.id_сотрудника
WHERE (
        p_search_text IS NULL
        OR p_search_text = ''
        OR CASE
            WHEN p_search_text ~ '^[0-9]+$' THEN z.id_заказа = p_search_text::INTEGER
            ELSE LOWER(COALESCE(k.фио, '')) LIKE '%' || LOWER(p_search_text) || '%'
        END
    )
    AND (
        p_status IS NULL
        OR p_status = 'Все статусы'
        OR (
            p_status = 'ПРОСРОЧЕН'
            AND (
                z.дата_готовности < CURRENT_DATE
                AND z.статус NOT IN ('выполнено', 'отгружен', 'завершен', 'отменен')
            )
        )
        OR (z.статус = p_status)
    )
    AND (
        p_date_from IS NULL
        OR z.дата_заказа >= p_date_from
    )
    AND (
        p_date_to IS NULL
        OR z.дата_заказа <= p_date_to
    )
ORDER BY z.id_заказа DESC;
END;
$$;