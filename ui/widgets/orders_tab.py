import qtawesome as qta
from PyQt6.QtCore import QDate
from PyQt6.QtGui import QColor
from PyQt6.QtWidgets import QFileDialog
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

from business_logic.pdf_generator import PDFGenerator
from db.database import Database
from ui.dialogs.add_order_dialog import AddOrderDialog
from ui.widgets.toast import Toast


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
            QDate(2020, 1, 1)
        )  # По умолчанию - с 2020 года
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
        self.table.doubleClicked.connect(self.show_order_details)

        layout.addWidget(self.table)

        # --- КНОПКИ СТАТУСА ---
        status_btn_layout = QHBoxLayout()
        self.btn_to_work = QPushButton("В работу")
        self.btn_to_work.setIcon(qta.icon("fa5s.play", color="#3498DB"))
        self.btn_to_work.clicked.connect(lambda: self.change_status("в_работе"))

        self.btn_done = QPushButton("Готово")
        self.btn_done.setIcon(qta.icon("fa5s.check", color="#27AE60"))
        self.btn_done.clicked.connect(lambda: self.change_status("выполнен"))

        self.btn_ship = QPushButton("Отгрузить")
        self.btn_ship.setIcon(qta.icon("fa5s.truck", color="#9B59B6"))
        self.btn_ship.clicked.connect(lambda: self.change_status("отгружен"))

        self.btn_defect = QPushButton("Зафиксировать брак")
        self.btn_defect.setIcon(qta.icon("fa5s.exclamation-triangle", color="#E74C3C"))
        self.btn_defect.clicked.connect(self.report_defect)

        self.btn_cancel = QPushButton("Отменить")
        self.btn_cancel.setIcon(qta.icon("fa5s.ban", color="#7F8C8D"))
        self.btn_cancel.clicked.connect(lambda: self.change_status("отменен"))

        status_btn_layout.addStretch()
        status_btn_layout.addWidget(self.btn_to_work)
        status_btn_layout.addWidget(self.btn_done)
        status_btn_layout.addWidget(self.btn_ship)
        status_btn_layout.addWidget(self.btn_defect)
        status_btn_layout.addWidget(self.btn_cancel)
        layout.addLayout(status_btn_layout)

    def load_data(self):
        """Загрузка данных через Хранимую Процедуру"""
        try:
            text_search = self.search_input.text().strip()
            if not text_search:
                text_search = None # Ensure it's None if empty

            status = self.status_filter.currentText()
            # If "Все статусы" is selected, pass None to the stored procedure
            if status == "Все статусы":
                status = None

            d_from = self.date_from.date().toString("yyyy-MM-dd")
            d_to = self.date_to.date().toString("yyyy-MM-dd")

            # Вызываем функцию поиска (возвращает таблицу)
            # Параметры: p_manager_id, p_search_text, p_status, p_date_from, p_date_to
            query = "SELECT * FROM sp_search_orders(%s, %s, %s, %s, %s)"
            params = (self.current_user_id, text_search, status, d_from, d_to)

            orders = Database.fetch_all(query, params)
            self.populate_table(orders)

        except Exception as e:
            print(f"Ошибка загрузки заказов: {e}")

    def populate_table(self, orders):
        self.table.setRowCount(0)

        for row_idx, order in enumerate(orders):
            self.table.insertRow(row_idx)

            items = [
                str(order["id_заказа"]),
                order["клиент"],
                order["менеджер"] if order["менеджер"] else "—",
                str(order["дата_заказа"]),
                order["статус_заказа"],
                f"{order['сумма_заказа']:,.2f} ₽",
                order["состояние_сроков"],
            ]

            # --- ЛОГИКА ЦВЕТОВ ---
            row_color = None
            st = order["статус_заказа"]
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
        from ui.dialogs.add_order_dialog import AddOrderDialog
        
        # Получаем ID текущего менеджера (пользователя)
        dialog = AddOrderDialog(self, self.current_user_id)
        if dialog.exec():
            self.load_data()
            
            # Check for navigation request
            if dialog.navigate_to_plan_order_id:
                # Access main window
                main = self.window()
                # Duck typing check or import verification
                if hasattr(main, "switch_to_production_plan"):
                    main.switch_to_production_plan(dialog.navigate_to_plan_order_id)  # Обновляем таблицу заказов

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
            Toast.error(self, "Ошибка при обновлении", str(e))

    def show_order_details(self):
        """Открывает диалог с составом заказа при двойном клике"""
        row = self.table.currentRow()
        if row < 0:
            return
            
        try:
            item_id = self.table.item(row, 0)
            if not item_id:
                return
                
            order_id = int(item_id.text())
            
            from ui.dialogs.order_details_dialog import OrderDetailsDialog
            dialog = OrderDetailsDialog(self, order_id)
            dialog.exec()
            
        except Exception as e:
            Toast.error(self, "Ошибка", f"Не удалось открыть заказ: {e}")

    def change_status(self, new_status):
        """Изменение статуса выбранного заказа"""
        selected_items = self.table.selectedItems()
        if not selected_items:
            Toast.warning(self, "Внимание", "Выберите заказ")
            return

        row = selected_items[0].row()
        order_id = int(self.table.item(row, 0).text())

        result = Database.call_procedure("sp_update_order_status", [order_id, new_status])
        status = result.get("status")
        msg = result.get("message", "")

        if status == "OK":
            Toast.success(self, "Успешно", msg)
            self.load_data()
        else:
            Toast.error(self, "Ошибка", msg)

    def report_defect(self):
        """Зафиксировать брак для выбранного заказа"""
        from PyQt6.QtWidgets import QDialog, QComboBox, QSpinBox
        
        selected_items = self.table.selectedItems()
        if not selected_items:
            Toast.warning(self, "Внимание", "Выберите заказ")
            return

        row = selected_items[0].row()
        order_id = int(self.table.item(row, 0).text())
        
        # Get order items
        order_items = Database.fetch_all(
            "SELECT sz.id_изделия, i.наименование, sz.количество_изделий "
            "FROM состав_заказа sz "
            "JOIN изделия i ON sz.id_изделия = i.id_изделия "
            "WHERE sz.id_заказа = %s",
            (order_id,)
        )
        
        if not order_items:
            Toast.warning(self, "Внимание", "В заказе нет позиций")
            return
        
        # Dialog to select product and qty
        dialog = QDialog(self)
        dialog.setWindowTitle("Зафиксировать брак")
        dialog.setFixedSize(400, 250)
        layout = QVBoxLayout(dialog)
        
        layout.addWidget(QLabel("Выберите изделие:"))
        combo = QComboBox()
        for item in order_items:
            combo.addItem(f"{item['наименование']} (в заказе: {item['количество_изделий']})", item['id_изделия'])
        layout.addWidget(combo)
        
        layout.addWidget(QLabel("Количество брака:"))
        spin = QSpinBox()
        spin.setRange(1, 1000)
        layout.addWidget(spin)
        
        layout.addWidget(QLabel("Причина брака:"))
        reason_input = QLineEdit()
        reason_input.setPlaceholderText("Например: дефект материала")
        layout.addWidget(reason_input)
        
        btn_ok = QPushButton("Зафиксировать")
        btn_ok.clicked.connect(dialog.accept)
        layout.addWidget(btn_ok)
        
        if dialog.exec():
            product_id = combo.currentData()
            qty = spin.value()
            reason = reason_input.text().strip() or "Не указана"
            
            result = Database.call_procedure("sp_report_defect", [order_id, product_id, qty, reason])
            status = result.get("status")
            msg = result.get("message", "")
            
            if status == "OK" or status == "WARNING":
                Toast.warning(self, "Брак зафиксирован", msg)
                self.load_data()
            else:
                Toast.error(self, "Ошибка", msg)
