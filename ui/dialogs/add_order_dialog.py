import qtawesome as qta
from PyQt6.QtCore import QDate, Qt
from PyQt6.QtWidgets import (
    QComboBox,
    QDateEdit,
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
)

from db.database import Database
from ui.widgets.toast import Toast


class OrderTasksDialog(QDialog):
    """Dialog to display tasks created by an order"""
    
    def __init__(self, parent, order_id, warnings=None):
        super().__init__(parent)
        self.order_id = order_id
        self.setWindowTitle(f"Задачи заказа №{order_id}")
        self.resize(600, 400)
        
        layout = QVBoxLayout(self)
        
        # Header with warnings if any
        if warnings:
            warn_label = QLabel("<b>Замечания:</b>")
            layout.addWidget(warn_label)
            for w in warnings:
                layout.addWidget(QLabel(w))
            layout.addSpacing(10)
        
        # Title
        layout.addWidget(QLabel(f"<h3>Созданные производственные задачи:</h3>"))
        
        # Table
        self.table = QTableWidget()
        self.table.setColumnCount(4)
        self.table.setHorizontalHeaderLabels(["Тип", "Наименование", "Количество", "Статус"])
        
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        header.setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(3, QHeaderView.ResizeMode.ResizeToContents)
        
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        
        layout.addWidget(self.table)
        
        # Buttons
        btn_layout = QHBoxLayout()
        btn_close = QPushButton("Закрыть")
        btn_close.clicked.connect(self.accept)
        btn_layout.addStretch()
        btn_layout.addWidget(btn_close)
        layout.addLayout(btn_layout)
        
        self.load_tasks()
    
    def load_tasks(self):
        """Load tasks from database"""
        try:
            tasks = Database.fetch_all(
                "SELECT * FROM sp_get_order_tasks(%s)",
                (self.order_id,)
            )
            
            self.table.setRowCount(0)
            
            for i, t in enumerate(tasks):
                self.table.insertRow(i)
                
                # Type with icon
                type_text = "🔧 Заготовка" if t['тип_задачи'] == 'заготовка' else "📦 Сборка"
                self.table.setItem(i, 0, QTableWidgetItem(type_text))
                self.table.setItem(i, 1, QTableWidgetItem(t['наименование']))
                self.table.setItem(i, 2, QTableWidgetItem(str(t['плановое_количество'])))
                self.table.setItem(i, 3, QTableWidgetItem(t['статус']))
                
        except Exception as e:
            Toast.error(self, "Ошибка загрузки", str(e))


class AddOrderDialog(QDialog):
    def __init__(self, parent=None, manager_id=None):
        super().__init__(parent)
        self.manager_id = manager_id
        self.setWindowTitle("Новый заказ")
        self.resize(700, 500)

        # Корзина: список словарей {'id': 1, 'name': '...', 'qty': 2, 'price': 100}
        self.cart_items = []
        self.navigate_to_plan_order_id = None

        self.setup_ui()
        self.load_dictionaries()

    def setup_ui(self):
        layout = QVBoxLayout(self)

        # --- 1. ШАПКА ЗАКАЗА ---
        top_layout = QHBoxLayout()

        # Выбор клиента
        lbl_client = QLabel("Клиент:")
        self.combo_client = QComboBox()
        self.combo_client.setEditable(True)  # Чтобы можно было писать имя
        self.combo_client.setPlaceholderText("Начните вводить имя...")

        # Дата готовности
        lbl_date = QLabel("Дата готовности:")
        self.date_edit = QDateEdit()
        self.date_edit.setCalendarPopup(True)
        self.date_edit.setDate(QDate.currentDate().addDays(1))  # Минимум завтра
        self.date_edit.setMinimumDate(
            QDate.currentDate().addDays(1)
        )  # Блокируем прошлое

        top_layout.addWidget(lbl_client)
        top_layout.addWidget(self.combo_client, 2)
        top_layout.addSpacing(20)
        top_layout.addWidget(lbl_date)
        top_layout.addWidget(self.date_edit)

        layout.addLayout(top_layout)

        layout.addSpacing(10)
        layout.addWidget(QLabel("<b>Добавление товаров:</b>"))

        # --- 2. ДОБАВЛЕНИЕ ТОВАРА ---
        prod_layout = QHBoxLayout()

        self.combo_product = QComboBox()
        self.combo_product.setEditable(True)
        self.combo_product.setPlaceholderText("Выберите изделие...")

        self.spin_qty = QSpinBox()
        self.spin_qty.setRange(1, 1000)
        self.spin_qty.setSuffix(" шт")

        btn_add_item = QPushButton("Добавить")
        btn_add_item.setIcon(qta.icon("fa5s.cart-plus"))
        btn_add_item.clicked.connect(self.add_to_cart)

        prod_layout.addWidget(self.combo_product, 3)
        prod_layout.addWidget(self.spin_qty)
        prod_layout.addWidget(btn_add_item)

        layout.addLayout(prod_layout)

        # --- 3. ТАБЛИЦА КОРЗИНЫ ---
        self.table_cart = QTableWidget()
        self.table_cart.setColumnCount(4)
        self.table_cart.setHorizontalHeaderLabels(
            ["Изделие", "Кол-во", "Цена/шт", "Сумма"]
        )
        self.table_cart.horizontalHeader().setSectionResizeMode(
            0, QHeaderView.ResizeMode.Stretch
        )
        layout.addWidget(self.table_cart)

        # --- 4. ПОДВАЛ (Сумма и Кнопки) ---
        bottom_layout = QHBoxLayout()

        self.lbl_total = QLabel("Итого: 0.00 ₽")
        self.lbl_total.setStyleSheet(
            "font-size: 16px; font-weight: bold; color: #2C3E50;"
        )

        btn_save = QPushButton("Создать заказ")
        btn_save.setObjectName("PrimaryButton")
        btn_save.clicked.connect(self.save_order)

        btn_cancel = QPushButton("Отмена")
        btn_cancel.clicked.connect(self.reject)

        bottom_layout.addWidget(self.lbl_total)
        bottom_layout.addStretch()
        bottom_layout.addWidget(btn_cancel)
        bottom_layout.addWidget(btn_save)

        layout.addLayout(bottom_layout)

    def load_dictionaries(self):
        """Загрузка клиентов и изделий через процедуры"""
        # Клиенты
        clients = Database.fetch_all("SELECT * FROM sp_get_clients()")
        for c in clients:
            self.combo_client.addItem(c["фио"], c["id_клиента"])

        # Изделия
        products = Database.fetch_all("SELECT * FROM sp_get_products()")
        for p in products:
            text = f"{p['наименование']} (Остаток: {p['количество_на_складе']}) - {p['стоимость']} ₽"
            self.combo_product.addItem(
                text, (p["id_изделия"], p["стоимость"], p["наименование"])
            )

    def add_to_cart(self):
        idx = self.combo_product.currentIndex()
        if idx == -1:
            return

        # Получаем данные из userData
        p_data = self.combo_product.itemData(idx)  # (id, price, name)
        if not p_data:
            return

        p_id, p_price, p_name = p_data
        qty = self.spin_qty.value()

        # Добавляем в список (или обновляем, если уже есть)
        for item in self.cart_items:
            if item["id"] == p_id:
                item["qty"] += qty
                self.update_cart_table()
                return

        self.cart_items.append(
            {"id": p_id, "name": p_name, "price": p_price, "qty": qty}
        )
        self.update_cart_table()

    def update_cart_table(self):
        self.table_cart.setRowCount(0)
        total_sum = 0

        for i, item in enumerate(self.cart_items):
            self.table_cart.insertRow(i)
            sum_item = item["price"] * item["qty"]
            total_sum += sum_item

            self.table_cart.setItem(i, 0, QTableWidgetItem(item["name"]))
            self.table_cart.setItem(i, 1, QTableWidgetItem(str(item["qty"])))
            self.table_cart.setItem(i, 2, QTableWidgetItem(str(item["price"])))
            self.table_cart.setItem(i, 3, QTableWidgetItem(str(sum_item)))

        self.lbl_total.setText(f"Итого: {total_sum:,.2f} ₽")

    def save_order(self):
        """Отправка в БД (Refactored)"""
        if not self.cart_items:
            QMessageBox.warning(self, "Ошибка", "Корзина пуста!")
            return

        client_idx = self.combo_client.currentIndex()
        if client_idx == -1:
            QMessageBox.warning(self, "Ошибка", "Выберите клиента!")
            return

        client_id = self.combo_client.itemData(client_idx)
        deadline = self.date_edit.date().toString("yyyy-MM-dd")

        try:
            # 1. Создаем заголовок заказа через процедуру
            res_order = Database.call_procedure(
                'sp_create_order', 
                [client_id, self.manager_id, deadline]
            )

            if res_order.get('status') != 'OK':
                raise Exception(res_order.get('message', 'Ошибка создания заказа'))

            order_id = res_order.get('new_order_id')
            warnings = []

            # 2. Добавление товаров через процедуру
            for item in self.cart_items:
                res_item = Database.call_procedure(
                    'sp_add_order_item', 
                    [order_id, item["id"], item["qty"]]
                )

                status = res_item.get('status')
                msg = res_item.get('message', '')

                if status == 'WARNING':
                    warnings.append(f"- {item['name']}: {msg}")
                elif status == 'ERROR':
                    # Логируем, но не прерываем (или прерываем? по ТЗ - обработка всех исключений на БД)
                    # Если БД вернула Error, значит позиция не добавлена.
                    warnings.append(f"❌ Ошибка {item['name']}: {msg}")

            # Успех
            if warnings:
                # Check if any warning is a critical purchase error
                is_critical = any("НЕОБХОДИМА ЗАКУПКА" in w for w in warnings)

                if is_critical:
                    # Critical error - show error dialog
                    msg_box = QMessageBox(self)
                    msg_box.setWindowTitle("Ошибка создания заказа")
                    msg_box.setText("Заказ не может быть полностью сформирован!")
                    msg_box.setInformativeText("Критическая нехватка материалов:\n" + "\n".join(warnings))
                    msg_box.setIcon(QMessageBox.Icon.Critical)
                    msg_box.exec()
                else:
                    # Production tasks created - show tasks dialog
                    tasks_dialog = OrderTasksDialog(self, order_id, warnings)
                    tasks_dialog.exec()
                    
                    # Ask if user wants to navigate to plan
                    reply = QMessageBox.question(
                        self,
                        "Заказ создан",
                        f"Заказ №{order_id} успешно создан!\nОтобразить в плане работ?",
                        QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
                    )
                    if reply == QMessageBox.StandardButton.Yes:
                        self.navigate_to_plan_order_id = order_id
            else:
                Toast.success(self.parent(), "Успешно", f"Заказ №{order_id} создан!")

            self.accept()  # Закрываем диалог

        except Exception as e:
            Toast.error(self, "Ошибка сохранения", str(e))
