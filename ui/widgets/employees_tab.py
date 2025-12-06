import qtawesome as qta
from PyQt6.QtGui import QColor
from PyQt6.QtWidgets import (
    QHBoxLayout,
    QHeaderView,
    QMessageBox,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from db.database import Database
from ui.dialogs.add_employee_dialog import AddEmployeeDialog
from ui.widgets.toast import Toast


class EmployeesTab(QWidget):
    def __init__(self):
        super().__init__()
        self.setup_ui()
        self.load_data()

    def setup_ui(self):
        layout = QVBoxLayout(self)

        # Кнопки
        top = QHBoxLayout()
        btn_add = QPushButton("Нанять сотрудника")
        btn_add.setObjectName("PrimaryButton")
        btn_add.setIcon(qta.icon("fa5s.user-plus", color="white"))
        btn_add.clicked.connect(self.add_emp)

        btn_fire = QPushButton("Уволить")
        btn_fire.setIcon(qta.icon("fa5s.user-times", color="#E74C3C"))
        btn_fire.clicked.connect(self.fire_emp)

        top.addWidget(btn_add)
        top.addWidget(btn_fire)
        top.addStretch()
        layout.addLayout(top)

        # Таблица
        self.table = QTableWidget()
        self.table.setColumnCount(6)
        self.table.setHorizontalHeaderLabels(
            ["ID", "ФИО", "Должность", "Телефон", "ЗП", "Статус"]
        )
        self.table.horizontalHeader().setSectionResizeMode(
            1, QHeaderView.ResizeMode.Stretch
        )
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        layout.addWidget(self.table)

    def load_data(self):
        self.table.setRowCount(0)
        query = "SELECT * FROM сотрудники ORDER BY дата_увольнения NULLS FIRST, фио"
        emps = Database.fetch_all(query)

        for i, e in enumerate(emps):
            self.table.insertRow(i)

            status = "Работает"
            color = None
            if e["дата_увольнения"]:
                status = "Уволен"
                color = QColor("#FFCDD2")  # Красный

            items = [
                str(e["id_сотрудника"]),
                e["фио"],
                e["должность"],
                e["номер_телефона"],
                f"{e['зарплата']:,.0f}",
                status,
            ]

            for j, val in enumerate(items):
                item = QTableWidgetItem(val)
                if color:
                    item.setBackground(color)
                self.table.setItem(i, j, item)

    def add_emp(self):
        if AddEmployeeDialog(self).exec():
            self.load_data()

    def fire_emp(self):
        row = self.table.currentRow()
        if row == -1:
            return

        emp_id = self.table.item(row, 0).text()
        name = self.table.item(row, 1).text()
        status = self.table.item(row, 5).text()

        if status == "Уволен":
            Toast.warning(self, "Ошибка", "Сотрудник уже уволен")
            return

        reply = QMessageBox.question(
            self,
            "Увольнение",
            f"Вы уверены, что хотите уволить:\n{name}?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )

        if reply == QMessageBox.StandardButton.Yes:
            # Увольнение - это просто установка даты увольнения (soft delete)
            Database.execute(
                "UPDATE сотрудники SET дата_увольнения = CURRENT_DATE WHERE id_сотрудника = %s",
                (emp_id,),
            )
            # Также деактивируем доступ? У нас проверка пароля не смотрит на дату увольнения пока.
            # По-хорошему надо бы. Но пока просто помечаем.
            Toast.success(self, "Готово", f"{name} уволен.")
            self.load_data()
