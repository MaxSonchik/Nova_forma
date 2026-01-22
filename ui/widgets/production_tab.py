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
            ["ID заготовки", "ID заказа", "Заготовка", "План", "Факт", "Дедлайн", "Статус", "Исполнитель"]
        )
        self.table.horizontalHeader().setSectionResizeMode(
            1, QHeaderView.ResizeMode.Stretch
        )
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)

        layout.addWidget(self.table)

        # --- КНОПКИ ДЕЙСТВИЙ ---
        action_layout = QHBoxLayout()

        self.btn_take = QPushButton("Взять в работу")
        self.btn_take.setObjectName("PrimaryButton")
        self.btn_take.clicked.connect(self.take_task)

        self.btn_report = QPushButton("Сдать работу (+ кол-во)")
        self.btn_report.setStyleSheet(
            "background-color: #27AE60; color: white; padding: 12px; border-radius: 5px;"
        )
        self.btn_report.clicked.connect(self.report_progress)

        action_layout.addWidget(self.btn_take)
        action_layout.addWidget(self.btn_report)

        layout.addLayout(action_layout)

    def load_data(self):
        filter_mode = self.filter_combo.currentText()

        # Запрос к VIEW задач
        query = "SELECT * FROM v_задачи_сборщика WHERE 1=1"
        params = []

        if filter_mode == "Актуальные (Новые + Мои)":
            # ИСПРАВЛЕНО: status -> статус
            query += " AND (статус != 'выполнено' AND (id_сборщика IS NULL OR id_сборщика = %s))"
            params.append(self.user_id)
        elif filter_mode == "История (Выполнено)":
            # ИСПРАВЛЕНО: status -> статус
            query += " AND статус = 'выполнено' AND id_сборщика = %s"
            params.append(self.user_id)

        # ИСПРАВЛЕНО: дата_план -> дедлайн (так называется колонка во View)
        query += " ORDER BY дедлайн ASC"

        try:
            tasks = Database.fetch_all(query, params)
            self.populate_table(tasks)
        except Exception as e:
            print("Ошибка загрузки задач:", e)

    def populate_table(self, tasks):
        self.table.setRowCount(0)
        for row_idx, task in enumerate(tasks):
            self.table.insertRow(row_idx)

            # Сохраняем составной ключ задачи
            id_заготовки = task["id_заготовки"]
            id_заказа = task["id_заказа"]

            items = [
                str(id_заготовки),
                str(id_заказа),
                task["заготовка"],
                str(task["плановое_количество"]),
                str(task["фактическое_количество"]),
                str(task["дедлайн"]),
                task["статус"],
                # Корректное отображение исполнителя
                "Свободно" if task["id_сборщика"] is None else ("Я" if task["id_сборщика"] == self.user_id else "Занято"),
            ]

            # Цвета
            row_color = None
            if task["статус"] == "принято":
                row_color = QColor("#E3F2FD")  # Голубой (свободно)
            if task["статус"] == "в_работе":
                row_color = QColor("#FFF9C4")  # Желтый
            if task["статус"] == "выполнено":
                row_color = QColor("#C8E6C9")  # Зеленый
            if task["статус"] == "просрочено":
                row_color = QColor("#FFCDD2")  # Красный

            for col_idx, text in enumerate(items):
                item = QTableWidgetItem(text)
                if row_color:
                    item.setBackground(row_color)
                self.table.setItem(row_idx, col_idx, item)

            # Храним данные в 0-й ячейке
            self.table.item(row_idx, 0).setData(Qt.ItemDataRole.UserRole, task)

    def get_selected_task(self):
        row = self.table.currentRow()
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
            Toast.warning(self, "Внимание", "Выберите задачу")
            return

        if task["id_сборщика"] != self.user_id:
            Toast.error(self, "Ошибка", "Это не ваша задача!")
            return

        if task["статус"] != "в_работе":
            Toast.warning(self, "Ошибка", "Задачу нужно сначала взять в работу!")
            return

        # Диалог ввода количества
        remaining = task["плановое_количество"] - task["фактическое_количество"]
        qty, ok = QInputDialog.getInt(
            self,
            "Сдача работы",
            f"Сколько '{task['заготовка']}' вы сделали?",
            value=1,
            min=1,
            max=remaining,
        )

        if ok:
            success, msg = Database.execute(
                "CALL sp_сдать_работу(%s, %s, %s)", (task["id_заготовки"], task["id_заказа"], qty)
            )
            if success:
                Toast.success(self, "Принято", f"Принято {qty} шт.")
                self.load_data()
            else:
                Toast.error(self, "Ошибка БД", msg)

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
