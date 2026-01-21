import qtawesome as qta
from PyQt6.QtWidgets import (
    QComboBox,
    QDialog,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QMessageBox,
    QPushButton,
    QSpinBox,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from db.database import Database
from ui.widgets.toast import Toast


class ProductionPlanningTab(QWidget):
    """Вкладка Планирование Производства для Менеджера"""

    def __init__(self):
        super().__init__()
        self.setup_ui()
        self.load_data()

    def setup_ui(self):
        layout = QVBoxLayout(self)

        header = QLabel("План производства заготовок")
        header.setStyleSheet("font-size: 18px; font-weight: bold;")
        layout.addWidget(header)

        # Toolbar
        toolbar = QHBoxLayout()
        btn_refresh = QPushButton("Обновить")
        btn_refresh.setIcon(qta.icon("fa5s.sync-alt"))
        btn_refresh.clicked.connect(self.load_data)

        btn_add_task = QPushButton("Добавить задачу")
        btn_add_task.setIcon(qta.icon("fa5s.plus"))
        btn_add_task.clicked.connect(self.add_manual_task)

        toolbar.addStretch()
        toolbar.addWidget(btn_refresh)
        toolbar.addWidget(btn_add_task)
        layout.addLayout(toolbar)

        # Table
        self.table = QTableWidget()
        self.table.setColumnCount(7)
        self.table.setHorizontalHeaderLabels([
            "ID", "Заготовка", "План", "Факт", "Дедлайн", "Статус", "Сборщик"
        ])
        self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        layout.addWidget(self.table)

        # Buttons
        btn_layout = QHBoxLayout()
        
        btn_release = QPushButton("Освободить задачу")
        btn_release.setIcon(qta.icon("fa5s.user-minus", color="#E74C3C"))
        btn_release.clicked.connect(self.release_task)
        
        btn_assign = QPushButton("Назначить сборщика")
        btn_assign.setIcon(qta.icon("fa5s.user-plus"))
        btn_assign.clicked.connect(self.assign_worker)
        
        btn_layout.addStretch()
        btn_layout.addWidget(btn_release)
        btn_layout.addWidget(btn_assign)
        layout.addLayout(btn_layout)

    def load_data(self):
        tasks = Database.fetch_all("SELECT * FROM sp_get_production_plan_full()")
        self.table.setRowCount(0)
        for i, t in enumerate(tasks):
            self.table.insertRow(i)
            self.table.setItem(i, 0, QTableWidgetItem(str(t["id_плана"])))
            self.table.setItem(i, 1, QTableWidgetItem(t["заготовка"]))
            self.table.setItem(i, 2, QTableWidgetItem(str(t["плановое_количество"])))
            self.table.setItem(i, 3, QTableWidgetItem(str(t["фактическое_количество"] or 0)))
            self.table.setItem(i, 4, QTableWidgetItem(str(t["дедлайн"])))
            self.table.setItem(i, 5, QTableWidgetItem(t["статус"]))
            self.table.setItem(i, 6, QTableWidgetItem(t["сборщик"]))

    def get_selected_plan_id(self):
        selected = self.table.selectedItems()
        if not selected:
            return None
        row = selected[0].row()
        return int(self.table.item(row, 0).text())

    def assign_worker(self):
        plan_id = self.get_selected_plan_id()
        if not plan_id:
            Toast.warning(self, "Внимание", "Выберите задачу")
            return

        dialog = AssignWorkerDialog(self, plan_id)
        if dialog.exec():
            self.load_data()

    def release_task(self):
        plan_id = self.get_selected_plan_id()
        if not plan_id:
            Toast.warning(self, "Внимание", "Выберите задачу")
            return

        result = Database.call_procedure("sp_release_task", [plan_id])
        status = result.get("status")
        msg = result.get("message", "")

        if status == "OK":
            Toast.success(self, "Успешно", msg)
            self.load_data()
        else:
            Toast.error(self, "Ошибка", msg)

    def add_manual_task(self):
        dialog = AddManualTaskDialog(self)
        if dialog.exec():
            self.load_data()


class AssignWorkerDialog(QDialog):
    def __init__(self, parent, plan_id):
        super().__init__(parent)
        self.plan_id = plan_id
        self.setWindowTitle("Назначить сборщика")
        self.setFixedSize(350, 150)

        layout = QVBoxLayout(self)
        layout.addWidget(QLabel("Выберите сборщика:"))

        self.combo_worker = QComboBox()
        workers = Database.fetch_all("SELECT * FROM sp_get_workers()")
        for w in workers:
            self.combo_worker.addItem(w["фио"], w["id_сотрудника"])
        layout.addWidget(self.combo_worker)

        btn_layout = QHBoxLayout()
        btn_cancel = QPushButton("Отмена")
        btn_cancel.clicked.connect(self.reject)
        btn_save = QPushButton("Назначить")
        btn_save.setObjectName("PrimaryButton")
        btn_save.clicked.connect(self.save)
        btn_layout.addStretch()
        btn_layout.addWidget(btn_cancel)
        btn_layout.addWidget(btn_save)
        layout.addLayout(btn_layout)

    def save(self):
        worker_id = self.combo_worker.currentData()
        if not worker_id:
            QMessageBox.warning(self, "Ошибка", "Выберите сборщика")
            return

        result = Database.call_procedure("sp_assign_worker_to_task", [self.plan_id, worker_id])
        status = result.get("status")
        msg = result.get("message", "")

        if status == "OK":
            Toast.success(self.parent(), "Успешно", msg)
            self.accept()
        elif status == "WARNING":
            Toast.warning(self.parent(), "Предупреждение", msg)
            self.accept()
        else:
            Toast.error(self, "Ошибка", msg)


class AddManualTaskDialog(QDialog):
    def __init__(self, parent):
        super().__init__(parent)
        self.setWindowTitle("Добавить задачу в план")
        self.setFixedSize(400, 250)

        layout = QVBoxLayout(self)

        # Order
        layout.addWidget(QLabel("Заказ (ID):"))
        self.spin_order = QSpinBox()
        self.spin_order.setRange(1, 999999)
        layout.addWidget(self.spin_order)

        # Component
        layout.addWidget(QLabel("Заготовка:"))
        self.combo_component = QComboBox()
        components = Database.fetch_all("SELECT * FROM sp_get_components()")
        for c in components:
            self.combo_component.addItem(c["наименование"], c["id_заготовки"])
        layout.addWidget(self.combo_component)

        # Qty
        layout.addWidget(QLabel("Количество:"))
        self.spin_qty = QSpinBox()
        self.spin_qty.setRange(1, 10000)
        layout.addWidget(self.spin_qty)

        # Buttons
        btn_layout = QHBoxLayout()
        btn_cancel = QPushButton("Отмена")
        btn_cancel.clicked.connect(self.reject)
        btn_save = QPushButton("Добавить")
        btn_save.setObjectName("PrimaryButton")
        btn_save.clicked.connect(self.save)
        btn_layout.addStretch()
        btn_layout.addWidget(btn_cancel)
        btn_layout.addWidget(btn_save)
        layout.addLayout(btn_layout)

    def save(self):
        order_id = self.spin_order.value()
        component_id = self.combo_component.currentData()
        qty = self.spin_qty.value()

        if not component_id:
            QMessageBox.warning(self, "Ошибка", "Выберите заготовку")
            return

        result = Database.call_procedure(
            "sp_add_manual_component_task", [order_id, component_id, qty, None]
        )
        if result.get("status") == "OK":
            Toast.success(self.parent(), "Успешно", result.get("message"))
            self.accept()
        else:
            Toast.error(self, "Ошибка", result.get("message", "Неизвестная ошибка"))
