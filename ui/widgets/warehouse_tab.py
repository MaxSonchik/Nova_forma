import qtawesome as qta
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QColor
from PyQt6.QtWidgets import (
    QComboBox,
    QHBoxLayout,
    QHeaderView,
    QLineEdit,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from db.database import Database


class WarehouseTab(QWidget):
    def __init__(self):
        super().__init__()
        self.setup_ui()
        self.load_data()

    def setup_ui(self):
        layout = QVBoxLayout(self)

        # --- ПАНЕЛЬ ФИЛЬТРОВ ---
        toolbar = QHBoxLayout()

        # 1. Поиск
        self.search_input = QLineEdit()
        self.search_input.setPlaceholderText("🔍 Поиск по Артикулу или Названию...")
        self.search_input.textChanged.connect(self.load_data)

        # 2. Фильтр по Типу
        self.type_filter = QComboBox()
        self.type_filter.addItems(["Все типы", "Материал", "Заготовка", "Изделие"])
        self.type_filter.currentTextChanged.connect(self.load_data)

        # 3. Кнопка Обновить
        btn_refresh = QPushButton()
        btn_refresh.setIcon(qta.icon("fa5s.sync-alt"))
        btn_refresh.setFixedWidth(40)
        btn_refresh.clicked.connect(self.load_data)

        toolbar.addWidget(self.search_input, 2)
        toolbar.addWidget(self.type_filter, 1)
        toolbar.addWidget(btn_refresh)

        layout.addLayout(toolbar)

        # --- ТАБЛИЦА ---
        self.table = QTableWidget()
        self.table.setColumnCount(5)
        self.table.setHorizontalHeaderLabels(
            ["Тип", "Артикул", "Наименование", "Количество", "Ед. изм."]
        )

        # Настройка ширины
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(
            2, QHeaderView.ResizeMode.Stretch
        )  # Наименование тянется
        header.setSectionResizeMode(
            0, QHeaderView.ResizeMode.ResizeToContents
        )  # Тип по ширине текста

        self.table.verticalHeader().setVisible(False)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(
            QTableWidget.EditTrigger.NoEditTriggers
        )  # Запрет редактирования

        layout.addWidget(self.table)

    def load_data(self):
        search_text = self.search_input.text().strip().lower()
        selected_type = self.type_filter.currentText()

        # Запрос к нашему VIEW
        query = "SELECT * FROM v_склад_общий WHERE 1=1"
        params = []

        # 1. Фильтр поиска
        if search_text:
            query += " AND (LOWER(наименование) LIKE %s OR LOWER(артикул) LIKE %s)"
            like_str = f"%{search_text}%"
            params.append(like_str)
            params.append(like_str)

        # 2. Фильтр типа
        if selected_type != "Все типы":
            query += " AND tipo = %s"  # ВАЖНО: проверить название колонки во VIEW
            # В миграции 002 мы назвали колонку 'тип', но Postgres мог привести к lower case.
            # Лучше использовать имя 'тип' в кавычках или просто тип.
            # PS: В скрипте создания view было: SELECT 'Материал' as тип
            query = query.replace("tipo", "тип")
            params.append(selected_type)

        # Сортировка: Сначала тип, потом имя
        query += " ORDER BY тип, наименование"

        items = Database.fetch_all(query, params)
        self.populate_table(items)

    def populate_table(self, items):
        self.table.setRowCount(0)

        for row_idx, item in enumerate(items):
            self.table.insertRow(row_idx)

            # Иконка для типа
            item_type = item["тип"]
            icon_name = "fa5s.box"  # дефолт
            if item_type == "Материал":
                icon_name = "fa5s.layer-group"
            elif item_type == "Заготовка":
                icon_name = "fa5s.puzzle-piece"
            elif item_type == "Изделие":
                icon_name = "fa5s.chair"

            # Кол-во 0 -> Красный цвет текста
            qty = item["количество"]
            text_color = QColor("black")
            if qty == 0:
                text_color = QColor("#E74C3C")  # Красный

            # Заполнение ячеек
            # 0. Тип (с иконкой)
            type_item = QTableWidgetItem(item_type)
            type_item.setIcon(qta.icon(icon_name, color="#2C3E50"))
            self.table.setItem(row_idx, 0, type_item)

            # 1. Артикул
            self.table.setItem(row_idx, 1, QTableWidgetItem(str(item["артикул"])))

            # 2. Наименование
            self.table.setItem(row_idx, 2, QTableWidgetItem(item["наименование"]))

            # 3. Количество
            qty_item = QTableWidgetItem(str(qty))
            qty_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            qty_item.setForeground(text_color)
            if qty == 0:
                qty_item.setToolTip("Нет на складе!")
            self.table.setItem(row_idx, 3, qty_item)

            # 4. Ед. изм.
            self.table.setItem(row_idx, 4, QTableWidgetItem(item["единица_измерения"]))
