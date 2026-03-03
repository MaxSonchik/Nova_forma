# Nova Forma CRM - Developer Manual

## Project Overview
Nova Forma CRM is a PyQt6-based desktop application for managing a furniture manufacturing business. It handles clients, orders, production planning, warehouse management, purchasing, and employee scheduling.

## Directory Structure

### Root Directory
- `main.py`: Entry point of the application.
- `config.py`: Configuration loader (loads `.env`).
- `requirements.txt`: Python dependencies.
- `.env`: Database connection string (not committed).

### /ui
Contains all User Interface code.
- `windows/main_window.py`: The main application window holding the navigation and stacking of tabs.
- `widgets/`: Individual tabs and reusable widgets.
    - `clients_tab.py`: Client management.
    - `orders_tab.py`: Order list and status management.
    - `production_tab.py`: Worker interface for tasks.
    - `production_planning_tab.py`: Manager interface for planning.
    - `warehouse_tab.py`: Stock levels.
    - `purchases_tab.py`: Procurement and supply chain.
    - `employees_tab.py`: HR management.
    - `schedule_tab.py`: Employee work schedule (Employee view).
    - `manager_schedule_tab.py`: Schedule management (Manager view).
    - `dashboard_tab.py`: Analytics and charts.
    - `nomenclature_tab.py`: Product catalog management.
    - `components_tab.py`: Component and material catalog.
    - `login_widget.py`: Authentication screen.
- `dialogs/`: Pop-up dialogs for creating/editing entities (e.g., `add_order_dialog.py`).

### /db
Database related files.
- `database.py`: Singleton class for database connection and execution.
- `migrations/`: SQL scripts for schema changes and stored procedures.

### /business_logic
Core business logic (currently mostly integrated into widgets or stored procedures, but contains some helpers).

### /utils
Utility scripts, mostly for initial setup or data seeding.

### /tools
Maintenance scripts.
- `refactor_db_names.py`: Tool used to renaming columns in code.

## Database Architecture
The project uses PostgreSQL.
Key changes in the recent refactoring:
1. **Naming Convention**: All tables are singular and capitalized (e.g., `Сотрудник`, `Заказ`, `Изделие`).
2. **Stored Procedures**: All logic has been migrated to stored procedures (prefixed with `sp_`).
   - Standardized return format: `(status, message, [data])` for mutation operations.
   - `sp_get_*` procedures for data retrieval.

## Key Stored Procedures
- **Auth**: `sp_login`
- **Orders**: `sp_create_order`, `sp_update_order_status`, `sp_report_defect`
- **Production**: `sp_get_assembler_tasks`, `sp_take_task`, `sp_submit_work`
- **Planning**: `sp_assign_worker_to_task`, `sp_create_manual_production_task`
- **Dashboard**: `sp_get_dashboard_summary`, `sp_get_sales_chart_data`

## How to Run
1. Ensure PostgreSQL is running and `.env` is configured.
2. Run the application:
   ```bash
   python3 main.py
   ```

## Development Notes
- **Avoid Raw SQL**: Do not write raw SQL queries in Python code. Use `Database.call_procedure` or `Database.fetch_all("SELECT * FROM sp_procedure()")`.
- **UI Updates**: When adding features, create a corresponding stored procedure first, then call it from the UI.
