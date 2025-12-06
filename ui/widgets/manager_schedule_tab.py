from PyQt6.QtCore import QDate, Qt
from PyQt6.QtGui import QColor
from PyQt6.QtWidgets import (
    QComboBox,
    QGroupBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QPushButton,
    QSpinBox,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from db.database import Database
from ui.widgets.toast import Toast


class ManagerScheduleTab(QWidget):
    def __init__(self):
        super().__init__()
        self.months = [
            "Январь",
            "Февраль",
            "Март",
            "Апрель",
            "Май",
            "Июнь",
            "Июль",
            "Август",
            "Сентябрь",
            "Октябрь",
            "Ноябрь",
            "Декабрь",
        ]
        self.setup_ui()
        self.load_employees()
        self.generate_calendar_grid()

    def setup_ui(self):
        layout = QVBoxLayout(self)

        # --- 1. ПАНЕЛЬ ВЫБОРА ---
        top_layout = QHBoxLayout()

        self.combo_emp = QComboBox()
        self.combo_emp.setPlaceholderText("Выберите сотрудника")
        self.combo_emp.currentIndexChanged.connect(self.load_schedule_colors)

        self.combo_month = QComboBox()
        self.combo_month.addItems(self.months)
        self.combo_month.setCurrentIndex(QDate.currentDate().month() - 1)
        self.combo_month.currentIndexChanged.connect(self.generate_calendar_grid)

        self.spin_year = QSpinBox()
        self.spin_year.setRange(2020, 2030)
        self.spin_year.setValue(QDate.currentDate().year())
        self.spin_year.valueChanged.connect(self.generate_calendar_grid)

        top_layout.addWidget(QLabel("Сотрудник:"))
        top_layout.addWidget(self.combo_emp, 1)
        top_layout.addWidget(QLabel("Месяц:"))
        top_layout.addWidget(self.combo_month)
        top_layout.addWidget(self.spin_year)

        layout.addLayout(top_layout)

        # --- 2. ТАБЛИЦА-КАЛЕНДАРЬ ---
        self.table = QTableWidget()
        self.table.setColumnCount(7)
        self.table.setRowCount(6)
        self.table.setHorizontalHeaderLabels(["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"])

        # Стили
        self.table.setStyleSheet(
            """
            QTableWidget {
                background-color: white;
                gridline-color: #E0E0E0;
                font-size: 14px;
            }
            QTableWidget::item:selected {
                background-color: rgba(0, 0, 0, 60); 
                border: 2px solid #2C3E50;
                color: black;
            }
            QHeaderView::section {
                background-color: #ECF0F1;
                border: none;
                font-weight: bold;
                padding: 5px;
            }
        """
        )

        self.table.horizontalHeader().setSectionResizeMode(
            QHeaderView.ResizeMode.Stretch
        )
        self.table.verticalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        self.table.verticalHeader().setVisible(False)
        self.table.setSelectionMode(QTableWidget.SelectionMode.ExtendedSelection)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)

        layout.addWidget(self.table)

        # --- 3. КНОПКИ СТАТУСОВ ---
        ctrl_group = QGroupBox("Применить к выделенным дням")
        btns_layout = QHBoxLayout(ctrl_group)

        self.btn_work = self.create_status_btn("Рабочий", "#27AE60", "рабочий")
        self.btn_off = self.create_status_btn("Выходной", "#E74C3C", "выходной")
        self.btn_vacation = self.create_status_btn("Отпуск", "#3498DB", "отпуск")
        self.btn_sick = self.create_status_btn("Больничный", "#F1C40F", "больничный")

        btns_layout.addWidget(self.btn_work)
        btns_layout.addWidget(self.btn_off)
        btns_layout.addWidget(self.btn_vacation)
        btns_layout.addWidget(self.btn_sick)

        layout.addWidget(ctrl_group)

    def create_status_btn(self, text, color, status_code):
        btn = QPushButton(text)
        btn.setStyleSheet(
            f"""
            QPushButton {{
                background-color: white; border: 1px solid #BDC3C7; 
                border-left: 5px solid {color}; padding: 10px; font-weight: bold;
            }}
            QPushButton:hover {{ background-color: #ECF0F1; }}
        """
        )
        # Привязываем метод apply_status_to_selection
        btn.clicked.connect(lambda: self.apply_status_to_selection(status_code, text))
        return btn

    def load_employees(self):
        self.combo_emp.clear()
        emps = Database.fetch_all(
            "SELECT id_сотрудника, фио, должность FROM сотрудники ORDER BY фио"
        )
        for e in emps:
            self.combo_emp.addItem(f"{e['фио']} ({e['должность']})", e["id_сотрудника"])
        self.combo_emp.setCurrentIndex(-1)

    def generate_calendar_grid(self):
        self.table.clearContents()
        self.table.setSelectionMode(QTableWidget.SelectionMode.ExtendedSelection)

        year = self.spin_year.value()
        month = self.combo_month.currentIndex() + 1

        first_day = QDate(year, month, 1)
        days_in_month = first_day.daysInMonth()
        start_day_of_week = first_day.dayOfWeek() - 1

        current_day = 1
        for row in range(6):
            for col in range(7):
                if row == 0 and col < start_day_of_week:
                    item = QTableWidgetItem("")
                    item.setFlags(Qt.ItemFlag.NoItemFlags)
                    self.table.setItem(row, col, item)
                    continue

                if current_day > days_in_month:
                    item = QTableWidgetItem("")
                    item.setFlags(Qt.ItemFlag.NoItemFlags)
                    self.table.setItem(row, col, item)
                    continue

                item = QTableWidgetItem(str(current_day))
                item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)

                date_str = QDate(year, month, current_day).toString("yyyy-MM-dd")
                item.setData(Qt.ItemDataRole.UserRole, date_str)

                self.table.setItem(row, col, item)
                current_day += 1

        self.load_schedule_colors()

    def load_schedule_colors(self):
        idx = self.combo_emp.currentIndex()
        if idx == -1:
            for row in range(6):
                for col in range(7):
                    item = self.table.item(row, col)
                    if item:
                        item.setBackground(QColor("white"))
                        item.setForeground(QColor("black"))
            return

        emp_id = self.combo_emp.itemData(idx)
        query = "SELECT дата, статус FROM график_работы WHERE id_сотрудника = %s"
        schedule = Database.fetch_all(query, (emp_id,))

        # Словарь { 'yyyy-MM-dd': 'статус' }
        sched_map = {str(row["дата"]): row["статус"] for row in schedule}

        for row in range(6):
            for col in range(7):
                item = self.table.item(row, col)
                if not item or not item.text():
                    continue

                date_str = item.data(Qt.ItemDataRole.UserRole)
                status = sched_map.get(date_str)

                color = QColor("white")
                fg_color = QColor("black")

                if status == "рабочий":
                    color = QColor("#27AE60")
                    fg_color = QColor("white")
                elif status == "выходной":
                    color = QColor("#E74C3C")
                    fg_color = QColor("white")
                elif status == "отпуск":
                    color = QColor("#3498DB")
                    fg_color = QColor("white")
                elif status == "больничный":
                    color = QColor("#F1C40F")
                    fg_color = QColor("black")

                item.setBackground(color)
                item.setForeground(fg_color)

    # --- ВОТ ЭТОТ МЕТОД, КОТОРЫЙ ТЕРЯЛСЯ ---
    def apply_status_to_selection(self, status_code, status_name):
        """Применяет статус ко всем выделенным ячейкам"""
        # 1. Проверка сотрудника
        idx = self.combo_emp.currentIndex()
        if idx == -1:
            Toast.warning(self, "Внимание", "Сначала выберите сотрудника!")
            return

        emp_id = self.combo_emp.itemData(idx)

        # 2. Проверка выделения
        selected_items = self.table.selectedItems()
        if not selected_items:
            Toast.warning(self, "Внимание", "Выделите дни в календаре!")
            return

        count = 0
        try:
            for item in selected_items:
                date_str = item.data(Qt.ItemDataRole.UserRole)
                if not date_str:
                    continue

                Database.execute(
                    "CALL sp_установить_статус_дня(%s, %s, %s)",
                    (emp_id, date_str, status_code),
                )
                count += 1

            Toast.success(
                self, "Успешно", f"Статус '{status_name}' установлен\nдля {count} дн."
            )
            self.load_schedule_colors()

        except Exception as e:
            Toast.error(self, "Ошибка", str(e))
