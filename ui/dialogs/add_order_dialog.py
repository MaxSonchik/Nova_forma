import qtawesome as qta
from PyQt6.QtCore import QDate
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


class AddOrderDialog(QDialog):
    def __init__(self, parent=None, manager_id=None):
        super().__init__(parent)
        self.manager_id = manager_id
        self.setWindowTitle("Новый заказ")
        self.resize(700, 500)

        # Корзина: список словарей {'id': 1, 'name': '...', 'qty': 2, 'price': 100}
        self.cart_items = []

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
        """Загрузка клиентов и изделий из БД"""
        # Клиенты
        clients = Database.fetch_all("SELECT id_клиента, фио FROM клиенты ORDER BY фио")
        for c in clients:
            # addItem(text, userData) -> userData хранит скрытый ID
            self.combo_client.addItem(c["фио"], c["id_клиента"])

        # Изделия
        products = Database.fetch_all(
            "SELECT id_изделия, наименование, стоимость, количество_на_складе FROM изделия ORDER BY наименование"
        )
        for p in products:
            text = f"{p['наименование']} (Остаток: {p['количество_на_складе']}) - {p['стоимость']} ₽"
            # Храним кортеж (id, price) в userData
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
        """Отправка в БД"""
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
            # 1. Создаем заголовок заказа с COMMIT (используем новый метод)
            res = Database.insert_returning(
                """
                INSERT INTO заказы (id_клиента, id_менеджера, дата_готовности, статус)
                VALUES (%s, %s, %s, 'принят') RETURNING id_заказа
            """,
                (client_id, self.manager_id, deadline),
            )

            if not res:
                raise Exception("Не удалось создать заказ (Ошибка БД)")

            order_id = res["id_заказа"]
            warnings = []

            # 2. Добавление товаров через процедуру
            for item in self.cart_items:
                # ВАЖНО: Используем fetch_one, так как это SELECT вызов функции
                # Функция внутри себя делает INSERT/UPDATE, но сам вызов идет через SELECT
                res_msg = Database.fetch_one(
                    "SELECT sp_добавить_изделие_в_заказ(%s, %s, %s)",
                    (order_id, item["id"], item["qty"]),
                )

                # Добавляем проверку, чтобы не было 'NoneType' error
                if res_msg and "sp_добавить_изделие_в_заказ" in res_msg:
                    msg = res_msg["sp_добавить_изделие_в_заказ"]
                    if "WARNING" in msg:
                        warnings.append(f"- {item['name']}: {msg}")
                else:
                    print(f"❌ Ошибка добавления позиции {item['name']}")

            # Успех
            final_msg = f"Заказ №{order_id} успешно создан!"
            if warnings:
                short_msg = "Заказ создан, но не хватает материалов. Проверьте план."
                Toast.warning(self.parent(), "Заказ создан с оговорками", short_msg)
            else:
                # Всё чисто - Зеленый тост
                Toast.success(self.parent(), "Успешно", f"Заказ №{order_id} создан!")

            self.accept()  # Закрываем диалог

        except Exception as e:
            # Ошибка - Красный тост
            # Важно: self.parent() может быть закрыт, показываем поверх самого диалога, если он открыт
            Toast.error(self, "Ошибка сохранения", str(e))
