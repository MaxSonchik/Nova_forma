-- Fix Assignments v11
-- Unassign tasks from Directors and Managers
UPDATE план_заготовок
SET id_сборщика = NULL,
    статус = 'принято'
WHERE id_сборщика IN (
        SELECT id_сотрудника
        FROM сотрудники
        WHERE должность IN ('директор', 'менеджер')
    );