CREATE OR REPLACE PROCEDURE sp_сдать_работу(
    p_id_плана INTEGER, 
    p_колво_сдано INTEGER
)
LANGUAGE plpgsql AS $$
DECLARE
    v_id_заготовки INTEGER;
    v_plan_qty INTEGER;
    v_fact_qty INTEGER;
BEGIN

    SELECT id_заготовки, плановое_количество, фактическое_количество 
    INTO v_id_заготовки, v_plan_qty, v_fact_qty
    FROM план_заготовок WHERE id_плана = p_id_плана;

    UPDATE план_заготовок 
    SET фактическое_количество = фактическое_количество + p_колво_сдано
    WHERE id_плана = p_id_плана;

    UPDATE заготовки 
    SET количество_готовых = количество_готовых + p_колво_сдано
    WHERE id_заготовки = v_id_заготовки;

    IF (v_fact_qty + p_колво_сдано) >= v_plan_qty THEN
        UPDATE план_заготовок SET статус = 'выполнено' WHERE id_плана = p_id_плана;
    END IF;
END;
$$;