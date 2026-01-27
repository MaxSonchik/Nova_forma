#!/bin/bash
export PGPASSWORD=123456

echo "Applying Fixes..."

# 1. Fix Assembly creation logic (Stored Procedure)
psql -h localhost -U postgres -d nova_forma_crm -f db/migrations/fix_missing_assembly.sql
if [ $? -eq 0 ]; then
    echo "[OK] Assembly Logic Fixed"
else
    echo "[ERROR] Failed to fix Assembly Logic"
fi

# 2. Fix Manager Plan View (Stored Procedure)
psql -h localhost -U postgres -d nova_forma_crm -f db/migrations/fix_manager_plan.sql
if [ $? -eq 0 ]; then
    echo "[OK] Manager Plan Function Fixed"
else
    echo "[ERROR] Failed to fix Manager Plan Function"
fi

echo "Done. Please restart the application."
