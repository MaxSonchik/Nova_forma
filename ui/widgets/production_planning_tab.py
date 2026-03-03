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
    QLineEdit,
    QRadioButton,
    QGroupBox,
    QDateEdit,
)

from db.database import Database
from ui.widgets.toast import Toast


class ProductionPlanningTab(QWidget):
    """Вкладка Планирование Производства для Менеджера"""

    def __init__(self, user_id=None):
        super().__init__()
        self.user_id = user_id
        self.setup_ui()
        self.load_data()

    def setup_ui(self):
        layout = QVBoxLayout(self)

        header = QLabel("План производства заготовок")
        header.setStyleSheet("font-size: 18px; font-weight: bold;")
        layout.addWidget(header)

                             
        toolbar = QHBoxLayout()
        
                 
        self.filter_order_id = QLineEdit()
        self.filter_order_id.setPlaceholderText("ID заказа...")
        self.filter_order_id.setFixedWidth(100)
        self.filter_order_id.textChanged.connect(self.apply_filters)
        
        self.filter_status = QComboBox()
        self.filter_status.addItem("Все статусы")
        self.filter_status.addItems(["принято", "в_работе", "выполнено", "отменено", "просрочено"])
        self.filter_status.currentTextChanged.connect(self.apply_filters)

        toolbar.addWidget(QLabel("Фильтр:"))
        toolbar.addWidget(self.filter_order_id)
        toolbar.addWidget(self.filter_status)
        
        toolbar.addStretch()

        btn_refresh = QPushButton("Обновить")
        btn_refresh.setIcon(qta.icon("fa5s.sync-alt"))
        btn_refresh.clicked.connect(self.load_data)

        btn_add_task = QPushButton("Добавить задачу (Ручн.)")
        btn_add_task.setIcon(qta.icon("fa5s.plus"))
        btn_add_task.clicked.connect(self.add_manual_task)
        
        btn_add_product = QPushButton("Добавить изделие (Smart)")
        btn_add_product.setIcon(qta.icon("fa5s.magic"))
        btn_add_product.clicked.connect(self.add_smart_product)

        toolbar.addWidget(btn_refresh)
        toolbar.addWidget(btn_add_task)
        toolbar.addWidget(btn_add_product)
        layout.addLayout(toolbar)

               
        self.table = QTableWidget()
        self.table.setColumnCount(9)                    
        self.table.setHorizontalHeaderLabels([
            "ID", "ID заказа", "Задача", "План", "Факт", "Дедлайн", "Дата факт.", "Статус", "Сборщик"
        ])
        
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(QHeaderView.ResizeMode.Interactive)
        header.setStretchLastSection(True)
                                     
        header.resizeSection(2, 200)

        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        layout.addWidget(self.table)
        
                                                    
        actions_layout = QHBoxLayout()
        btn_assign = QPushButton("Назначить")
        btn_assign.clicked.connect(self.assign_worker)
        actions_layout.addWidget(btn_assign)
        
        btn_release = QPushButton("Снять задачу")
        btn_release.clicked.connect(self.release_task)
        actions_layout.addWidget(btn_release)
        
        actions_layout.addStretch()
        layout.addLayout(actions_layout)

    def load_data(self):
                              
                                                                                                                                                                
        tasks = Database.fetch_all("SELECT * FROM sp_get_production_plan_full()")
        self.table.setRowCount(0)
        
                                  
        self.table.setColumnCount(9)
        self.table.setHorizontalHeaderLabels([
            "ID", "ID заказа", "Задача", "План", "Факт", "Дедлайн", "Дата факт.", "Статус", "Сборщик"
        ])

        for i, t in enumerate(tasks):
            self.table.insertRow(i)
                   
            obj_id = str(t.get("id_заготовки"))
            
            self.table.setItem(i, 0, QTableWidgetItem(obj_id))
            self.table.setItem(i, 1, QTableWidgetItem(str(t["id_заказа"])))
            self.table.setItem(i, 2, QTableWidgetItem(t.get("заготовка") or t.get("наименование") or ""))
            self.table.setItem(i, 3, QTableWidgetItem(str(t["плановое_количество"])))
            self.table.setItem(i, 4, QTableWidgetItem(str(t["фактическое_количество"] or 0)))
            self.table.setItem(i, 5, QTableWidgetItem(str(t.get("дата_план") or t.get("дедлайн", ""))))
            
                         
            actual_date = t.get("дата_фактическая")
            actual_date_str = actual_date.strftime("%d.%m.%Y %H:%M") if actual_date else "-"
            self.table.setItem(i, 6, QTableWidgetItem(actual_date_str))
            
            self.table.setItem(i, 7, QTableWidgetItem(t["статус"]))
            self.table.setItem(i, 8, QTableWidgetItem(t["сборщик"]))
            
                                         
            self.table.item(i, 0).setData(Qt.ItemDataRole.UserRole, t)

    def apply_filters(self):
        order_filter = self.filter_order_id.text().strip()
        status_filter = self.filter_status.currentText()
        
        for row in range(self.table.rowCount()):
            item_order = self.table.item(row, 1)           
            item_status = self.table.item(row, 7)                           
            
            show = True
            
                                                
            if order_filter and item_order.text() != order_filter:
                show = False
            
                              
            if status_filter != "Все статусы" and item_status.text() != status_filter:
                show = False
                
            self.table.setRowHidden(row, not show)

    def get_selected_composite_key(self):
        """Returns (id_заготовки, id_заказа) or None"""
        selected = self.table.selectedItems()
        if not selected:
            return None, None
        row = selected[0].row()
        id_zag = int(self.table.item(row, 0).text())
        id_order = int(self.table.item(row, 1).text())
        return id_zag, id_order

    def filter_by_order(self, order_id):
        """Show only tasks for specific order"""
        self.load_data()
        
                                                 
                                  
        for row in range(self.table.rowCount()):
            item = self.table.item(row, 1)             
            if item and item.text() == str(order_id):
                self.table.setRowHidden(row, False)
            else:
                self.table.setRowHidden(row, True)
        
        Toast.info(self, "Фильтр", f"Показаны задачи для заказа №{order_id}")

    def assign_worker(self):
        id_заготовки, id_заказа = self.get_selected_composite_key()
        if not id_заготовки:
            Toast.warning(self, "Внимание", "Выберите задачу")
            return

        dialog = AssignWorkerDialog(self, id_заготовки, id_заказа)
        if dialog.exec():
            self.load_data()

    def release_task(self):
        id_заготовки, id_заказа = self.get_selected_composite_key()
        if not id_заготовки:
            Toast.warning(self, "Внимание", "Выберите задачу")
            return

        confirm = QMessageBox.question(
            self, "Подтверждение",
            "Снять задачу? Если задача была в работе, материалы будут возвращены на склад.",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if confirm != QMessageBox.StandardButton.Yes:
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
        dialog = AddManualTaskDialog(self, self.user_id)
        if dialog.exec():
                                                            
            self.load_data()

    def add_smart_product(self):
        from ui.dialogs.add_product_dialog import AddProductDialog
        dialog = AddProductDialog(self, self.user_id)
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
            if w.get("должность", "").lower() == "сборщик":
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
    def __init__(self, parent, user_id, replenish_mode=False):
        super().__init__(parent)
        self.user_id = user_id
        self.initial_replenish = replenish_mode
        self.setWindowTitle("Добавить задачу в план")
        self.setFixedSize(450, 380)

        layout = QVBoxLayout(self)

                        
        mode_group = QGroupBox("Режим задачи")
        mode_layout = QHBoxLayout()
        self.radio_existing = QRadioButton("Существующий заказ")
        self.radio_new = QRadioButton("Новый заказ")
        self.radio_replenish = QRadioButton("Пополнение склада")
        self.radio_existing.setChecked(True)
        self.radio_existing.toggled.connect(self.toggle_mode)
        self.radio_new.toggled.connect(self.toggle_mode)
        self.radio_replenish.toggled.connect(self.toggle_mode)
        
        mode_layout.addWidget(self.radio_existing)
        mode_layout.addWidget(self.radio_new)
        mode_layout.addWidget(self.radio_replenish)
        mode_group.setLayout(mode_layout)
        layout.addWidget(mode_group)

                              
        self.existing_widget = QWidget()
        ex_layout = QVBoxLayout(self.existing_widget)
        ex_layout.setContentsMargins(0,0,0,0)
        ex_layout.addWidget(QLabel("ID Заказа:"))
        self.spin_order = QSpinBox()
        self.spin_order.setRange(1, 999999)
        ex_layout.addWidget(self.spin_order)
        layout.addWidget(self.existing_widget)

                         
        self.new_order_widget = QWidget()
        new_layout = QVBoxLayout(self.new_order_widget)
        new_layout.setContentsMargins(0,0,0,0)
        new_layout.addWidget(QLabel("Клиент:"))
        self.combo_client = QComboBox()
        self.load_clients()
        new_layout.addWidget(self.combo_client)
        layout.addWidget(self.new_order_widget)
        
        self.new_order_widget.setVisible(False)

        # If opened in replenish mode, pre-select it
        if self.initial_replenish:
            self.radio_replenish.setChecked(True)

                   
        layout.addWidget(QLabel("Заготовка:"))
        self.combo_component = QComboBox()
        components = Database.fetch_all("SELECT * FROM sp_get_components()")
        for c in components:
            self.combo_component.addItem(c["наименование"], c["id_заготовки"])
        layout.addWidget(self.combo_component)

             
        layout.addWidget(QLabel("Количество:"))
        self.spin_qty = QSpinBox()
        self.spin_qty.setRange(1, 10000)
        layout.addWidget(self.spin_qty)
        
                  
        layout.addWidget(QLabel("Дедлайн (для задачи):"))
        self.date_deadline = QDateEdit()
        self.date_deadline.setDate(QDate.currentDate().addDays(1))
        self.date_deadline.setCalendarPopup(True)
        self.date_deadline.setDisplayFormat("dd.MM.yyyy")
        layout.addWidget(self.date_deadline)
        
                 
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

    def load_clients(self):
                                                                 
                                                       
        clients = Database.fetch_all("SELECT * FROM sp_get_clients()")
        self.combo_client.clear()
        for c in clients:
                                                  
            self.combo_client.addItem(str(c['фио']), c['id_клиента'])

    def toggle_mode(self):
        is_new = self.radio_new.isChecked()
        is_replenish = self.radio_replenish.isChecked()
        self.new_order_widget.setVisible(is_new)
        self.existing_widget.setVisible(not is_new and not is_replenish)

    def save(self):
        comp_idx = self.combo_component.currentIndex()
        if comp_idx == -1:
            QMessageBox.warning(self, "Ошибка", "Выберите заготовку")
            return
        
        comp_id = self.combo_component.itemData(comp_idx)
        qty = self.spin_qty.value()
        deadline = self.date_deadline.date().toString("yyyy-MM-dd")

        try:
            order_id = None
            
            if self.radio_replenish.isChecked():
                # Service order: no client (stock replenishment)
                res_order = Database.call_procedure(
                    "sp_create_order",
                    [None, self.user_id, deadline]
                )
                
                if res_order.get("status") == "OK":
                    order_id = res_order.get("id_заказа")
                    Toast.info(self.parent(), "Инфо", f"Создан служебный заказ №{order_id} (пополнение склада)")
                else:
                    Toast.error(self, "Ошибка заказа", res_order.get("message", ""))
                    return
            elif self.radio_new.isChecked():
                                  
                client_id = self.combo_client.currentData()
                if not client_id:
                     QMessageBox.warning(self, "Ошибка", "Выберите клиента")
                     return
                
                                                                     
                res_order = Database.call_procedure(
                    "sp_create_order",
                    [client_id, self.user_id, deadline] 
                )
                
                if res_order.get("status") == "OK":
                    order_id = res_order.get("id_заказа")
                    Toast.info(self.parent(), "Инфо", f"Создан заказ №{order_id}")
                else:
                    Toast.error(self, "Ошибка заказа", res_order.get("message", ""))
                    return
            else:
                                
                order_id = self.spin_order.value()

                      
            res = Database.call_procedure(
                'sp_create_manual_production_task',
                [order_id, comp_id, qty, deadline]
            )
            
            if res.get('status') == 'OK':
                Toast.success(self.parent(), "Успешно", f"Задача добавлена к заказу №{order_id}")
                self.accept()
            else:
                Toast.error(self.parent(), "Ошибка задачи", res.get('message', 'Неизвестная ошибка'))
                
        except Exception as e:
            Toast.error(self.parent(), "Ошибка", str(e))
