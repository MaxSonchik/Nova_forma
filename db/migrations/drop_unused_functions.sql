-- ============================================================================
-- МИГРАЦИЯ: Удаление неиспользуемых функций/процедур
-- Дата: 2026-03-04
-- ============================================================================
-- Эти функции были идентифицированы как НЕ используемые из Python UI
-- и являются дублями с кириллическими именами или устаревшими версиями.
--
-- Проведён полный аудит:
--   - Все файлы ui/widgets/*.py, ui/dialogs/*.py, ui/windows/*.py
--   - Перекрёстная проверка с pgAdmin
-- ============================================================================
BEGIN;
-- 1. Кириллические дубли (имеют английские аналоги в UI)
-- sp_взять_задачу_в_работу → дубль sp_take_component_task
DROP FUNCTION IF EXISTS sp_взять_задачу_в_работу(INTEGER, INTEGER, INTEGER);
-- sp_сдать_работу → дубль sp_submit_component_work
DROP FUNCTION IF EXISTS sp_сдать_работу(INTEGER, INTEGER, INTEGER, INTEGER);
-- sp_сдать_сборку → дубль sp_submit_assembly_work
DROP FUNCTION IF EXISTS sp_сдать_сборку(INTEGER, INTEGER, INTEGER);
DROP PROCEDURE IF EXISTS sp_сдать_сборку(INTEGER, INTEGER, INTEGER);
-- sp_установить_статус_дня → дубль sp_set_day_status
DROP FUNCTION IF EXISTS sp_установить_статус_дня(INTEGER, DATE, VARCHAR);
DROP PROCEDURE IF EXISTS sp_установить_статус_дня(INTEGER, DATE, VARCHAR);
-- 2. Кириллические процедуры, используемые только в тестах (не в UI)
DROP FUNCTION IF EXISTS sp_закрыть_заказ(INTEGER);
DROP PROCEDURE IF EXISTS sp_закрыть_заказ(INTEGER);
DROP FUNCTION IF EXISTS sp_отгрузить_заказ(INTEGER);
DROP PROCEDURE IF EXISTS sp_отгрузить_заказ(INTEGER);
DROP FUNCTION IF EXISTS sp_подтвердить_закупку(INTEGER);
DROP PROCEDURE IF EXISTS sp_подтвердить_закупку(INTEGER);
DROP FUNCTION IF EXISTS sp_подтвердить_отгрузку(INTEGER);
DROP PROCEDURE IF EXISTS sp_подтвердить_отгрузку(INTEGER);
-- 3. Английские функции, не используемые в UI
-- sp_confirm_purchase — не вызывается
DROP FUNCTION IF EXISTS sp_confirm_purchase(INTEGER);
-- sp_get_dashboard_counts — не вызывается (используется sp_get_dashboard_summary)
DROP FUNCTION IF EXISTS sp_get_dashboard_counts();
-- sp_update_client — не вызывается (используется sp_save_client для создания и обновления)
DROP FUNCTION IF EXISTS sp_update_client(INTEGER, VARCHAR, VARCHAR, TEXT, VARCHAR);
-- sp_get_production_dashboard_data — не вызывается из UI
DROP FUNCTION IF EXISTS sp_get_production_dashboard_data(INTEGER);
COMMIT;