import qtawesome as qta
from PyQt6.QtCore import QDate, Qt
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
        self.table.setColumnCount(9) # Added Type column
        self.table.setHorizontalHeaderLabels([
            "ID", "Тип", "ID заказа", "Задача", "План", "Факт", "Дедлайн", "Статус", "Сборщик"
        ])
        
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(QHeaderView.ResizeMode.Interactive)
        header.setStretchLastSection(True)
        # Resize "Rule" for Task Name
        header.resizeSection(3, 200)

        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        layout.addWidget(self.table)
        
        # ... (rest of setup)

    def load_data(self):
        # Procedure now returns: 
        # id_заготовки, id_заказа, заготовка, плановое_количество, фактическое_количество, дедлайн, статус, сборщик, тип_задачи, id_объекта
        tasks = Database.fetch_all("SELECT * FROM sp_get_production_plan_full()")
        self.table.setRowCount(0)
        
        self.table.setColumnCount(9)
        self.table.setHorizontalHeaderLabels([
            "ID", "Тип", "ID заказа", "Задача", "План", "Факт", "Дедлайн", "Статус", "Сборщик"
        ])

        for i, t in enumerate(tasks):
            self.table.insertRow(i)
            # 0. ID (Display composite or object id?)
            # Use id_объекта if available (the view wrapper puts component ID in id_объекта)
            obj_id = str(t.get("id_объекта", t.get("id_заготовки")))
            
            self.table.setItem(i, 0, QTableWidgetItem(obj_id))
            self.table.setItem(i, 1, QTableWidgetItem(t.get("тип_задачи", "заготовка")))
            self.table.setItem(i, 2, QTableWidgetItem(str(t["id_заказа"])))
            self.table.setItem(i, 3, QTableWidgetItem(t["заготовка"]))
            self.table.setItem(i, 4, QTableWidgetItem(str(t["плановое_количество"])))
            self.table.setItem(i, 5, QTableWidgetItem(str(t["фактическое_количество"] or 0)))
            self.table.setItem(i, 6, QTableWidgetItem(str(t["дедлайн"])))
            self.table.setItem(i, 7, QTableWidgetItem(t["статус"]))
            self.table.setItem(i, 8, QTableWidgetItem(t["сборщик"]))
            
            # Store full data for actions
            self.table.item(i, 0).setData(Qt.ItemDataRole.UserRole, t)

    def get_selected_composite_key(self):
        """Returns (id_объекта, id_заказа, тип_задачи) or None"""
        selected = self.table.selectedItems()
        if not selected:
            return None, None, None
        row = selected[0].row()
        id_obj = int(self.table.item(row, 0).text())
        task_type = self.table.item(row, 1).text()
        id_order = int(self.table.item(row, 2).text())
        return id_obj, id_order, task_type

    def filter_by_order(self, order_id):
        """Show only tasks for specific order"""
        self.load_data()
        
        # Simple client-side filter (hiding rows)
        # Column 2 is "ID заказа" after adding Type column
        for row in range(self.table.rowCount()):
            item = self.table.item(row, 2)  # ID заказа is in column 2
            if item and item.text() == str(order_id):
                self.table.setRowHidden(row, False)
            else:
                self.table.setRowHidden(row, True)
        
        Toast.info(self, "Фильтр", f"Показаны задачи для заказа №{order_id}")

    def assign_worker(self):
        id_заготовки, id_заказа, _ = self.get_selected_composite_key()
        if not id_заготовки:
            Toast.warning(self, "Внимание", "Выберите задачу")
            return

        dialog = AssignWorkerDialog(self, id_заготовки, id_заказа)
        if dialog.exec():
            self.load_data()

    def release_task(self):
        id_заготовки, id_заказа, _ = self.get_selected_composite_key()
        if not id_заготовки:
            Toast.warning(self, "Внимание", "Выберите задачу")
            return

        result = Database.call_procedure("sp_release_task", [id_заготовки, id_заказа])
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
    def __init__(self, parent, id_заготовки, id_заказа):
        super().__init__(parent)
        self.id_заготовки = id_заготовки
        self.id_заказа = id_заказа
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

        result = Database.call_procedure("sp_assign_worker_to_task", [self.id_заготовки, self.id_заказа, worker_id])
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
        comp_idx = self.combo_component.currentIndex()
        if comp_idx == -1:
            return
        
        comp_id = self.combo_component.itemData(comp_idx)
        qty = self.spin_qty.value()
        
        # Deadline defaults to tomorrow for manual tasks
        deadline = QDate.currentDate().addDays(1).toString("yyyy-MM-dd")
        
        try:
            res = Database.call_procedure(
                'sp_create_manual_production_task',
                [order_id, comp_id, qty, deadline]
            )
            
            if res.get('status') == 'OK':
                Toast.success(self.parent(), "Успешно", "Задача добавлена")
                self.accept()
            else:
                # Show error from DB (e.g. Purchase needed)
                Toast.error(self.parent(), "Ошибка", res.get('message', 'Неизвестная ошибка'))
                
        except Exception as e:
            Toast.error(self.parent(), "Ошибка", str(e))
