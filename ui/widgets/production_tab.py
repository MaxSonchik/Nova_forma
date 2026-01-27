import qtawesome as qta
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QColor
from PyQt6.QtWidgets import (
    QComboBox,
    QFileDialog,
    QHBoxLayout,
    QHeaderView,
    QInputDialog,
    QLabel,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from business_logic.pdf_generator import PDFGenerator
from db.database import Database
from ui.widgets.toast import Toast


class ProductionTab(QWidget):
    def __init__(self, user_id):
        super().__init__()
        self.user_id = user_id  # ID текущего сборщика
        self.setup_ui()
        self.load_data()

    def setup_ui(self):
        layout = QVBoxLayout(self)

        # --- ФИЛЬТРЫ ---
        top_layout = QHBoxLayout()

        self.filter_combo = QComboBox()
        self.filter_combo.addItems(
            ["Актуальные (Новые + Мои)", "Все задачи", "История (Выполнено)"]
        )
        self.filter_combo.currentTextChanged.connect(self.load_data)

        btn_print = QPushButton()
        btn_print.setIcon(qta.icon("fa5s.print"))
        btn_print.setToolTip("Печать сменного задания")
        btn_print.clicked.connect(self.print_tasks)

        btn_refresh = QPushButton("Обновить")
        btn_refresh.setIcon(qta.icon("fa5s.sync-alt"))
        btn_refresh.clicked.connect(self.load_data)

        top_layout.addWidget(QLabel("Фильтр:"))
        top_layout.addWidget(self.filter_combo)
        top_layout.addStretch()
        top_layout.addWidget(btn_print)
        top_layout.addWidget(btn_refresh)

        layout.addLayout(top_layout)

        # --- ТАБЛИЦА ---
        self.table = QTableWidget()
        self.table.setColumnCount(8)
        self.table.setHorizontalHeaderLabels(
            ["ID", "Заготовка", "Заказ", "План", "Факт", "Дедлайн", "Статус", "Сборщик"]
        )
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(QHeaderView.ResizeMode.Interactive)
        header.setStretchLastSection(True)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)

        layout.addWidget(self.table)

        # --- КНОПКИ ДЕЙСТВИЙ ---
        action_layout = QHBoxLayout()

        action_layout.addWidget(self.btn_report)

        layout.addLayout(action_layout)

    def load_data(self):
        filter_mode = self.filter_combo.currentText()

        # Запрос к VIEW задач
        query = "SELECT * FROM v_задачи_сборщика WHERE 1=1"
        params = []

        if filter_mode == "Актуальные (Новые + Мои)":
            query += " AND (статус != 'выполнено' AND (id_сборщика IS NULL OR id_сборщика = %s))"
            params.append(self.user_id)
        elif filter_mode == "Актуальные": # Fallback for alias
            query += " AND (статус != 'выполнено' AND (id_сборщика IS NULL OR id_сборщика = %s))"
            params.append(self.user_id)
        elif filter_mode == "Мои задачи":
            query += " AND id_сборщика = %s"
            params.append(self.user_id)
        elif filter_mode == "Свободные":
            query += " AND id_сборщика IS NULL AND статус != 'выполнено'"
        elif filter_mode == "История (Выполнено)":
            query += " AND статус = 'выполнено' AND id_сборщика = %s"
            params.append(self.user_id)
        query += " ORDER BY дедлайн ASC"

        try:
            tasks = Database.fetch_all(query, tuple(params))
            
            self.table.setRowCount(0)
            # Re-set headers just in case
            self.table.setHorizontalHeaderLabels(
                ["ID", "Заготовка", "Заказ", "План", "Факт", "Дедлайн", "Статус", "Сборщик"]
            )
            
            for i, task in enumerate(tasks):
                self.table.insertRow(i)
                
                # View Columns: тип_задачи, id_задачи, id_заказа, наименование_задачи, ... id_объекта
                
                # Colors
                row_color = None
                status = task.get("статус")
                if status == "принято":
                    row_color = QColor("#E3F2FD")  # Light Blue
                elif status == "в_работе":
                    row_color = QColor("#FFF9C4")  # Yellow
                elif status == "выполнено":
                    row_color = QColor("#C8E6C9")  # Green
                elif status == "просрочено":
                    row_color = QColor("#FFCDD2")  # Red

                # Access Keys safely with fallback
                t_id = str(task.get("id_объекта", task.get("id_заготовки", "")))
                t_name = str(task.get("наименование_задачи", task.get("заготовка", "???")))
                t_order = str(task.get("id_заказа", ""))
                t_plan = str(task.get("плановое_количество", 0))
                t_fact = str(task.get("фактическое_количество", 0))
                t_dead = str(task.get("дедлайн", task.get("дата_план", "")))
                t_status = str(task.get("статус", ""))
                
                assignee_id = task.get("id_сборщика")
                t_assignee = str(assignee_id) if assignee_id else "—"

                # Items
                items = [t_id, t_name, t_order, t_plan, t_fact, t_dead, t_status, t_assignee]

                for col, text in enumerate(items):
                    item = QTableWidgetItem(text)
                    if row_color:
                        item.setBackground(row_color)
                    self.table.setItem(i, col, item)

                # Store user role
                self.table.item(i, 0).setData(Qt.ItemDataRole.UserRole, task)

        except Exception as e:
            print("Ошибка загрузки задач:", e)
            Toast.error(self, "Ошибка загрузки", str(e))
        if row == -1:
            return None
        return self.table.item(row, 0).data(Qt.ItemDataRole.UserRole)

    def take_task(self):
        task = self.get_selected_task()
        if not task:
            Toast.warning(self, "Внимание", "Выберите задачу")
            return

        current_status = task["статус"]
        assigned_to = task["id_сборщика"]  # Может быть None, если задача общая

        # --- ЛОГИКА ПРОВЕРОК ---

        # 1. Проверка на завершенность
        if current_status == "выполнено":
            Toast.warning(self, "Ошибка", "Эта задача уже выполнена!")
            return

        # 2. Проверка, не в работе ли она уже
        if current_status == "в_работе":
            if assigned_to == self.user_id:
                Toast.warning(
                    self,
                    "Инфо",
                    "Вы уже работаете над этой задачей.\nИспользуйте кнопку 'Сдать работу'.",
                )
            else:
                Toast.error(self, "Ошибка", "Задача уже в работе у другого сотрудника!")
            return

        # 3. Проверка на чужую задачу (если статус 'принято', но назначена другому)
        # Если assigned_to None - значит задача общая, брать можно.
        # Если assigned_to == self.user_id - значит назначена мне, брать нужно.
        if assigned_to is not None and assigned_to != self.user_id:
            Toast.error(self, "Ошибка", "Эта задача назначена другому сотруднику!")
            return

        # --- ПОПЫТКА ВЗЯТЬ ---
        try:
            # Вызов процедуры с составным ключом
            success, msg = Database.execute(
                "CALL sp_взять_задачу_в_работу(%s, %s, %s)",
                (task["id_заготовки"], task["id_заказа"], self.user_id),
            )
            if success:
                Toast.success(
                    self,
                    "В работе",
                    "Задача успешно взята в работу.\nМатериалы списаны.",
                )
                self.load_data()
            else:
                # Обработка ошибок процедуры (например, нехватка материалов)
                if "Недостаточно материала" in msg:
                    Toast.error(self, "Склад пуст", f"Не удалось взять задачу:\n{msg}")
                else:
                    Toast.error(self, "Ошибка БД", msg)

        except Exception as e:
            Toast.error(self, "Критическая ошибка", str(e))

    def report_progress(self):
        task = self.get_selected_task()
        if not task:
            Toast.warning(self, "Внимание", "Выберите задачу для сдачи")
            return

        order_id = task["id_заказа"]
        task_type = task.get("тип_задачи", "заготовка")
        
        # ID is stored in 'id_объекта' for new view, or 'id_заготовки' for old fallback
        object_id = task.get("id_объекта", task.get("id_заготовки"))
        
        task_name = task.get("наименование_задачи", "")
        plan = task["плановое_количество"]
        fact = task["фактическое_количество"]
        
        start_qty = 1
        max_qty = plan - fact
        if max_qty < 1:
            Toast.warning(self, "Внимание", "План по этой задаче выполнен!")
            return

        qty, ok = QInputDialog.getInt(
            self, "Сдать работу", 
            f"Сколько единиц '{task_name}' вы сделали?", 
            start_qty, 1, 1000000
        )
        if ok:
            try:
                if task_type == 'сборка':
                    # Call sp_сдать_сборку(id_prod, id_order, qty)
                    Database.call_procedure(
                        "sp_сдать_сборку", 
                        [object_id, order_id, qty]
                    )
                else:
                    # Call sp_сдать_работу(id_comp, id_order, qty)
                    Database.call_procedure(
                        "sp_сдать_работу", 
                        [object_id, order_id, qty]
                    )
                    
                Toast.success(self, "Успешно", "Работа принята, склад обновлен!")
                self.load_data()
            except Exception as e:
                # Handle "Purchase Needed" errors gracefully (shown as Error toast)
                Toast.error(self, "Ошибка", str(e))

    def print_tasks(self):
        file_path, _ = QFileDialog.getSaveFileName(
            self, "Сохранить задание", "Tasks.pdf", "PDF (*.pdf)"
        )
        if not file_path:
            return

        try:
            gen = PDFGenerator(file_path)
            success, msg = gen.generate_assembler_tasks(self.user_id)
            if success:
                Toast.success(self, "Успешно", f"Файл сохранен:\n{file_path}")
            else:
                Toast.error(self, "Ошибка", msg)
        except Exception as e:
            Toast.error(self, "Ошибка", str(e))
