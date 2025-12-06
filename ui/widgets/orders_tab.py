import qtawesome as qta
from PyQt6.QtCore import QDate
from PyQt6.QtGui import QColor
from PyQt6.QtWidgets import QFileDialog  # <-- Добавь это
from PyQt6.QtWidgets import (
    QComboBox,
    QDateEdit,
    QGroupBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from business_logic.pdf_generator import PDFGenerator  # <-- И это
from db.database import Database
from ui.dialogs.add_order_dialog import AddOrderDialog  # Не забудь импортировать!
from ui.widgets.toast import Toast  # <-- И это


class OrdersTab(QWidget):
    def __init__(self, current_user_id):
        super().__init__()
        self.current_user_id = current_user_id
        self.setup_ui()
        self.load_data()

    def setup_ui(self):
        layout = QVBoxLayout(self)

        # --- ПАНЕЛЬ ФИЛЬТРОВ (Группировка) ---
        filter_group = QGroupBox("Многокритериальный поиск")
        filter_layout = QHBoxLayout(filter_group)

        # 1. Поиск по тексту
        self.search_input = QLineEdit()
        self.search_input.setPlaceholderText("🔍 Клиент или № заказа...")
        self.search_input.setFixedWidth(200)
        self.search_input.textChanged.connect(self.load_data)

        # 2. Фильтр статусов (обновлен список)
        self.status_filter = QComboBox()
        self.status_filter.addItems(
            [
                "Все статусы",
                "принят",
                "в_работе",
                "выполнен",
                "отгружен",
                "завершен",
                "ПРОСРОЧЕН",
            ]
        )
        self.status_filter.currentTextChanged.connect(self.load_data)

        # 3. Фильтр дат (Период)
        date_label = QLabel("Период заказа:")
        date_label.setStyleSheet("color: #7F8C8D;")

        self.date_from = QDateEdit()
        self.date_from.setCalendarPopup(True)
        self.date_from.setDate(
            QDate.currentDate().addMonths(-1)
        )  # По умолчанию - месяц назад
        self.date_from.dateChanged.connect(self.load_data)

        lbl_to = QLabel("-")

        self.date_to = QDateEdit()
        self.date_to.setCalendarPopup(True)
        self.date_to.setDate(
            QDate.currentDate().addMonths(1)
        )  # По умолчанию + месяц вперед
        self.date_to.dateChanged.connect(self.load_data)

        # 4. Кнопки управления
        btn_refresh = QPushButton()
        btn_refresh.setIcon(qta.icon("fa5s.sync-alt"))
        btn_refresh.setToolTip("Обновить таблицу")
        btn_refresh.clicked.connect(self.load_data)

        self.btn_add = QPushButton("Новый заказ")
        self.btn_add.setIcon(qta.icon("fa5s.plus"))
        self.btn_add.setObjectName("PrimaryButton")
        self.btn_add.clicked.connect(self.open_add_order_dialog)

        self.btn_print = QPushButton()
        self.btn_print.setIcon(qta.icon("fa5s.file-pdf", color="#E74C3C"))
        self.btn_print.setToolTip("Печать бланка заказа")
        self.btn_print.setFixedWidth(40)
        self.btn_print.clicked.connect(self.print_order)

        # Добавляем всё в лайаут фильтров
        filter_layout.addWidget(self.search_input)
        filter_layout.addWidget(self.status_filter)
        filter_layout.addSpacing(15)
        filter_layout.addWidget(date_label)
        filter_layout.addWidget(self.date_from)
        filter_layout.addWidget(lbl_to)
        filter_layout.addWidget(self.date_to)
        filter_layout.addStretch()
        filter_layout.addWidget(btn_refresh)
        filter_layout.addWidget(self.btn_print)
        filter_layout.addWidget(self.btn_add)

        layout.addWidget(filter_group)

        # --- ТАБЛИЦА ---
        self.table = QTableWidget()
        self.table.setColumnCount(7)
        self.table.setHorizontalHeaderLabels(
            ["ID", "Клиент", "Менеджер", "Дата Заказа", "Статус", "Сумма", "Инфо"]
        )

        header = self.table.horizontalHeader()
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.table.verticalHeader().setVisible(False)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)

        layout.addWidget(self.table)

    def load_data(self):
        """Загрузка данных с Multi-criteria search"""
        # Сразу убираем пробелы, чтобы " 5 " считалось числом
        text_search = self.search_input.text().strip().lower()
        status = self.status_filter.currentText()
        d_from = self.date_from.date().toString("yyyy-MM-dd")
        d_to = self.date_to.date().toString("yyyy-MM-dd")

        # Базовый запрос
        query = "SELECT * FROM v_заказы_менеджер WHERE 1=1"
        params = []

        is_id_search = False

        # 1. Текстовый поиск (Клиент или ID)
        if text_search:
            # Пробуем искать как число (ID)
            if text_search.isdigit():
                query += " AND id_заказа = %s"
                params.append(text_search)
                is_id_search = True  # Флаг: мы ищем конкретный ID
            else:
                # Иначе ищем по клиенту
                query += " AND LOWER(клиент) LIKE %s"
                params.append(f"%{text_search}%")

        # 2. Фильтр статуса
        if status != "Все статусы":
            if status == "ПРОСРОЧЕН":
                query += " AND состояние_сроков = 'ПРОСРОЧЕН'"
            else:
                query += " AND статус = %s"
                params.append(status)

        # 3. Фильтр по дате
        # ВАЖНО: Если мы ищем конкретный ID, даты игнорируем!
        if not is_id_search:
            query += " AND дата_заказа BETWEEN %s AND %s"
            params.append(d_from)
            params.append(d_to)

        # Сортировка
        query += " ORDER BY id_заказа DESC"

        orders = Database.fetch_all(query, params)
        self.populate_table(orders)

    def populate_table(self, orders):
        self.table.setRowCount(0)

        for row_idx, order in enumerate(orders):
            self.table.insertRow(row_idx)

            items = [
                str(order["id_заказа"]),
                order["клиент"],
                order["менеджер"] if order["менеджер"] else "—",
                str(order["дата_заказа"]),
                order["статус"],
                f"{order['сумма_заказа']:,.2f} ₽",
                order["состояние_сроков"],
            ]

            # --- ЛОГИКА ЦВЕТОВ ---
            row_color = None
            st = order["статус"]
            cond = order["состояние_сроков"]

            if cond == "ПРОСРОЧЕН":
                row_color = QColor("#FFCDD2")  # Красный (Просрочено)
            elif st == "в_работе":
                row_color = QColor("#FFF9C4")  # Желтый (В работе) - NEW!
            elif st == "выполнен":
                row_color = QColor("#C8E6C9")  # Зеленый (Выполнен)
            elif st == "отгружен" or st == "завершен":
                row_color = QColor("#F5F5F5")  # Серый (Архив)
                # Делаем текст серым для архива

            for col_idx, text in enumerate(items):
                item = QTableWidgetItem(text)
                if row_color:
                    item.setBackground(row_color)

                # Для архива серый текст
                if st in ["отгружен", "завершен"]:
                    item.setForeground(QColor("#9E9E9E"))

                self.table.setItem(row_idx, col_idx, item)

    def open_add_order_dialog(self):
        # Передаем ID менеджера в диалог
        dialog = AddOrderDialog(self, manager_id=self.current_user_id)
        if dialog.exec():  # Если нажали "Создать"
            self.load_data()  # Обновляем таблицу заказов

    def print_order(self):
        # 1. Получаем ID выделенного заказа
        selected_items = self.table.selectedItems()
        if not selected_items:
            Toast.warning(self, "Внимание", "Выберите заказ для печати")
            return

        # ID у нас в 0-м столбце
        row = selected_items[0].row()
        order_id = self.table.item(row, 0).text()

        # 2. Спрашиваем куда сохранить
        file_path, _ = QFileDialog.getSaveFileName(
            self, "Сохранить отчет", f"Заказ_{order_id}.pdf", "PDF Files (*.pdf)"
        )

        if not file_path:
            return

        # 3. Генерация
        try:
            generator = PDFGenerator(file_path)
            success, msg = generator.generate_order_blank(order_id)

            if success:
                Toast.success(self, "Готово", f"Отчет сохранен:\n{file_path}")
            else:
                Toast.error(self, "Ошибка", msg)

        except Exception as e:
            Toast.error(self, "Ошибка генерации", str(e))
