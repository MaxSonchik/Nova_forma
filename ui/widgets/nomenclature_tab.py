import qtawesome as qta
from PyQt6.QtWidgets import (
    QDialog,
    QDoubleSpinBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from db.database import Database
from ui.widgets.toast import Toast


class NomenclatureTab(QWidget):
    """Вкладка Номенклатура для Директора"""

    def __init__(self):
        super().__init__()
        self.setup_ui()
        self.load_data()

    def setup_ui(self):
        layout = QVBoxLayout(self)

        # Header
        header = QLabel("Номенклатура изделий")
        header.setStyleSheet("font-size: 18px; font-weight: bold; margin-bottom: 10px;")
        layout.addWidget(header)

        # Toolbar
        toolbar = QHBoxLayout()
        
        btn_add = QPushButton("Новое изделие")
        btn_add.setIcon(qta.icon("fa5s.plus", color="#27AE60"))
        btn_add.clicked.connect(self.add_product)
        
        btn_refresh = QPushButton("Обновить")
        btn_refresh.setIcon(qta.icon("fa5s.sync-alt"))
        btn_refresh.clicked.connect(self.load_data)
        
        toolbar.addWidget(btn_add)
        toolbar.addStretch()
        toolbar.addWidget(btn_refresh)
        layout.addLayout(toolbar)

        # Table
        self.table = QTableWidget()
        self.table.setColumnCount(7)
        self.table.setHorizontalHeaderLabels(["ID", "Артикул", "Наименование", "Тип", "Размеры", "Цена", "На складе"])
        self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.table.doubleClicked.connect(self.edit_product)
        self.table.itemSelectionChanged.connect(self.on_selection_changed)
        layout.addWidget(self.table)

        # Components panel (below table)
        self.components_label = QLabel("Состав изделия:")
        self.components_label.setStyleSheet("font-weight: bold; margin-top: 10px;")
        layout.addWidget(self.components_label)
        
        self.components_table = QTableWidget()
        self.components_table.setColumnCount(2)
        self.components_table.setHorizontalHeaderLabels(["Заготовка", "Количество"])
        self.components_table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        self.components_table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.components_table.setMaximumHeight(150)
        layout.addWidget(self.components_table)

        # Buttons
        btn_layout = QHBoxLayout()
        btn_components = QPushButton("Состав изделия")
        btn_components.setIcon(qta.icon("fa5s.sitemap"))
        btn_components.clicked.connect(self.show_components)
        btn_layout.addStretch()
        btn_layout.addWidget(btn_components)
        layout.addLayout(btn_layout)

    def load_data(self):
        products = Database.fetch_all("SELECT * FROM sp_get_products()")
        self.table.setRowCount(0)
        for i, p in enumerate(products):
            self.table.insertRow(i)
            self.table.setItem(i, 0, QTableWidgetItem(str(p["id_изделия"])))
            self.table.setItem(i, 1, QTableWidgetItem(p["артикул"]))
            self.table.setItem(i, 2, QTableWidgetItem(p["наименование"]))
            self.table.setItem(i, 3, QTableWidgetItem(p["тип"]))
            self.table.setItem(i, 4, QTableWidgetItem(p["размеры"]))
            self.table.setItem(i, 5, QTableWidgetItem(f"{p['стоимость']:,.2f} ₽"))
            self.table.setItem(i, 6, QTableWidgetItem(str(p["количество_на_складе"])))

    def on_selection_changed(self):
        """При выборе изделия показываем его состав"""
        product_id = self.get_selected_id()
        if not product_id:
            self.components_table.setRowCount(0)
            return

        components = Database.fetch_all(
            "SELECT * FROM sp_get_product_components(%s)", (product_id,)
        )
        self.components_table.setRowCount(0)
        for i, c in enumerate(components):
            self.components_table.insertRow(i)
            self.components_table.setItem(i, 0, QTableWidgetItem(c["наименование"]))
            self.components_table.setItem(i, 1, QTableWidgetItem(str(c["количество"])))

    def get_selected_id(self):
        selected = self.table.selectedItems()
        if not selected:
            return None
        row = selected[0].row()
        return int(self.table.item(row, 0).text())

    def edit_product(self):
        product_id = self.get_selected_id()
        if not product_id:
            return

        row = self.table.selectedItems()[0].row()
        current_name = self.table.item(row, 1).text()
        current_price = self.table.item(row, 2).text().replace(" ₽", "").replace(",", "")

        dialog = EditProductDialog(self, product_id, current_name, float(current_price))
        if dialog.exec():
            self.load_data()

    def show_components(self):
        product_id = self.get_selected_id()
        if not product_id:
            Toast.warning(self, "Внимание", "Выберите изделие")
            return

        row = self.table.selectedItems()[0].row()
        product_name = self.table.item(row, 1).text()

        dialog = ProductComponentsDialog(self, product_id, product_name)
        dialog.exec()

    def add_product(self):
        """Open dialog to create new product"""
        dialog = AddProductDialog(self)
        if dialog.exec():
            self.load_data()


class EditProductDialog(QDialog):
    def __init__(self, parent, product_id, name, price):
        super().__init__(parent)
        self.product_id = product_id
        self.setWindowTitle("Редактирование изделия")
        self.setFixedSize(400, 200)

        layout = QVBoxLayout(self)

        self.input_name = QLineEdit(name)
        self.input_price = QLineEdit(str(price))

        layout.addWidget(QLabel("Наименование:"))
        layout.addWidget(self.input_name)
        layout.addWidget(QLabel("Цена:"))
        layout.addWidget(self.input_price)

        btn_layout = QHBoxLayout()
        btn_cancel = QPushButton("Отмена")
        btn_cancel.clicked.connect(self.reject)
        btn_save = QPushButton("Сохранить")
        btn_save.setObjectName("PrimaryButton")
        btn_save.clicked.connect(self.save)
        btn_layout.addStretch()
        btn_layout.addWidget(btn_cancel)
        btn_layout.addWidget(btn_save)
        layout.addLayout(btn_layout)

    def save(self):
        name = self.input_name.text().strip()
        try:
            price = float(self.input_price.text().strip())
        except ValueError:
            QMessageBox.warning(self, "Ошибка", "Некорректная цена")
            return

        result = Database.call_procedure("sp_update_product", [self.product_id, name, price])
        if result.get("status") == "OK":
            Toast.success(self.parent(), "Успешно", result.get("message"))
            self.accept()
        else:
            Toast.error(self, "Ошибка", result.get("message", "Неизвестная ошибка"))


class ProductComponentsDialog(QDialog):
    """Диалог редактирования состава изделия с добавлением/изменением/удалением"""
    def __init__(self, parent, product_id, product_name):
        super().__init__(parent)
        self.product_id = product_id
        self.setWindowTitle(f"Состав: {product_name}")
        self.setFixedSize(550, 400)

        layout = QVBoxLayout(self)

        # Table with component_id stored
        self.table = QTableWidget()
        self.table.setColumnCount(3)
        self.table.setHorizontalHeaderLabels(["ID", "Заготовка", "Количество"])
        self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.table.setColumnHidden(0, True)  # Hide ID column
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        layout.addWidget(self.table)

        # Buttons
        btn_layout = QHBoxLayout()
        
        btn_add = QPushButton("Добавить")
        btn_add.setIcon(qta.icon("fa5s.plus", color="#27AE60"))
        btn_add.clicked.connect(self.add_component)
        
        btn_edit = QPushButton("Изменить")
        btn_edit.setIcon(qta.icon("fa5s.edit", color="#3498DB"))
        btn_edit.clicked.connect(self.edit_component)
        
        btn_delete = QPushButton("Удалить")
        btn_delete.setIcon(qta.icon("fa5s.trash", color="#E74C3C"))
        btn_delete.clicked.connect(self.delete_component)
        
        btn_close = QPushButton("Закрыть")
        btn_close.clicked.connect(self.accept)
        
        btn_layout.addWidget(btn_add)
        btn_layout.addWidget(btn_edit)
        btn_layout.addWidget(btn_delete)
        btn_layout.addStretch()
        btn_layout.addWidget(btn_close)
        layout.addLayout(btn_layout)

        self.load_components()

    def load_components(self):
        components = Database.fetch_all(
            "SELECT * FROM sp_get_product_components(%s)", (self.product_id,)
        )
        self.table.setRowCount(0)
        for i, c in enumerate(components):
            self.table.insertRow(i)
            self.table.setItem(i, 0, QTableWidgetItem(str(c["id_заготовки"])))
            self.table.setItem(i, 1, QTableWidgetItem(c["наименование"]))
            self.table.setItem(i, 2, QTableWidgetItem(str(c["количество"])))

    def get_selected_component_id(self):
        selected = self.table.selectedItems()
        if not selected:
            return None
        row = selected[0].row()
        return int(self.table.item(row, 0).text())

    def add_component(self):
        from PyQt6.QtWidgets import QInputDialog, QComboBox
        
        # Get all available components
        all_components = Database.fetch_all("SELECT * FROM sp_get_components()")
        if not all_components:
            Toast.warning(self, "Внимание", "Нет доступных заготовок")
            return
        
        # Create selection dialog
        dialog = QDialog(self)
        dialog.setWindowTitle("Добавить заготовку")
        dialog.setFixedSize(350, 150)
        dlg_layout = QVBoxLayout(dialog)
        
        combo = QComboBox()
        for c in all_components:
            combo.addItem(c["наименование"], c["id_заготовки"])
        dlg_layout.addWidget(QLabel("Выберите заготовку:"))
        dlg_layout.addWidget(combo)
        
        from PyQt6.QtWidgets import QSpinBox
        spin = QSpinBox()
        spin.setRange(1, 1000)
        spin.setValue(1)
        dlg_layout.addWidget(QLabel("Количество:"))
        dlg_layout.addWidget(spin)
        
        btn_ok = QPushButton("Добавить")
        btn_ok.clicked.connect(dialog.accept)
        dlg_layout.addWidget(btn_ok)
        
        if dialog.exec():
            component_id = combo.currentData()
            qty = spin.value()
            result = Database.call_procedure("sp_add_product_component", [self.product_id, component_id, qty])
            if result.get("status") == "OK":
                Toast.success(self, "Успешно", result.get("message"))
                self.load_components()
            else:
                Toast.error(self, "Ошибка", result.get("message", "Неизвестная ошибка"))

    def edit_component(self):
        component_id = self.get_selected_component_id()
        if not component_id:
            Toast.warning(self, "Внимание", "Выберите заготовку")
            return
        
        # Get current qty
        row = self.table.selectedItems()[0].row()
        current_qty = int(self.table.item(row, 2).text())
        
        from PyQt6.QtWidgets import QInputDialog
        new_qty, ok = QInputDialog.getInt(self, "Изменить количество", "Новое количество:", current_qty, 1, 1000)
        if ok:
            result = Database.call_procedure("sp_update_product_component", [self.product_id, component_id, new_qty])
            if result.get("status") == "OK":
                Toast.success(self, "Успешно", result.get("message"))
                self.load_components()
            else:
                Toast.error(self, "Ошибка", result.get("message", "Неизвестная ошибка"))

    def delete_component(self):
        component_id = self.get_selected_component_id()
        if not component_id:
            Toast.warning(self, "Внимание", "Выберите заготовку")
            return
        
        reply = QMessageBox.question(self, "Подтверждение", "Удалить заготовку из состава изделия?")
        if reply == QMessageBox.StandardButton.Yes:
            result = Database.call_procedure("sp_delete_product_component", [self.product_id, component_id])
            if result.get("status") == "OK":
                Toast.success(self, "Успешно", result.get("message"))
                self.load_components()
            else:
                Toast.error(self, "Ошибка", result.get("message", "Неизвестная ошибка"))


class AddProductDialog(QDialog):
    """Dialog to create a new product with components"""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Новое изделие")
        self.resize(800, 600)
        self.chosen_components = []
        self.setup_ui()

    def setup_ui(self):
        layout = QVBoxLayout(self)

        # 1. Basic Info
        form_layout = QHBoxLayout()
        
        self.name_input = QLineEdit()
        self.name_input.setPlaceholderText("Название изделия...")
        
        self.type_input = QLineEdit()
        self.type_input.setPlaceholderText("Тип (Шкаф, Стол...)")
        
        self.size_input = QLineEdit()
        self.size_input.setPlaceholderText("Размеры (2000x600x400)")
        
        self.price_input = QDoubleSpinBox()
        self.price_input.setRange(0, 1000000)
        self.price_input.setPrefix("Цена: ")
        self.price_input.setButtonSymbols(QDoubleSpinBox.ButtonSymbols.NoButtons)

        form_layout.addWidget(self.name_input)
        form_layout.addWidget(self.type_input)
        form_layout.addWidget(self.size_input)
        form_layout.addWidget(self.price_input)
        
        layout.addLayout(form_layout)

        # 2. Components Selection
        layout.addWidget(QLabel("Состав изделия (заготовки):"))
        
        comp_layout = QHBoxLayout()
        self.comp_search = QLineEdit()
        self.comp_search.setPlaceholderText("Поиск заготовки...")
        self.comp_search.textChanged.connect(self.load_components)
        comp_layout.addWidget(self.comp_search)
        layout.addLayout(comp_layout)

        self.table_comps = QTableWidget()
        self.table_comps.setColumnCount(3)
        self.table_comps.setHorizontalHeaderLabels(["ID", "Наименование", "На складе"])
        self.table_comps.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.table_comps.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table_comps.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        layout.addWidget(self.table_comps)

        # 3. Add Button
        btn_add = QPushButton("Добавить в состав")
        btn_add.clicked.connect(self.add_component_to_list)
        layout.addWidget(btn_add)

        # 4. Selected Components List
        layout.addWidget(QLabel("Выбранные компоненты:"))
        self.list_selected = QTableWidget()
        self.list_selected.setColumnCount(3)
        self.list_selected.setHorizontalHeaderLabels(["ID", "Заготовка", "Кол-во"])
        self.list_selected.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.list_selected.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.list_selected.setMaximumHeight(150)
        layout.addWidget(self.list_selected)

        # 5. Dialog Buttons
        btns = QHBoxLayout()
        ok_btn = QPushButton("Создать изделие")
        ok_btn.clicked.connect(self.accept)
        cancel_btn = QPushButton("Отмена")
        cancel_btn.clicked.connect(self.reject)
        btns.addStretch()
        btns.addWidget(ok_btn)
        btns.addWidget(cancel_btn)
        layout.addLayout(btns)

        self.load_components()

    def load_components(self):
        text = self.comp_search.text().strip().lower()
        query = "SELECT id_заготовки, наименование, количество_готовых FROM заготовки WHERE 1=1"
        params = []
        if text:
            query += " AND LOWER(наименование) LIKE %s"
            params.append(f"%{text}%")
        
        rows = Database.fetch_all(query, params)
        self.table_comps.setRowCount(0)
        for i, r in enumerate(rows):
            self.table_comps.insertRow(i)
            self.table_comps.setItem(i, 0, QTableWidgetItem(str(r["id_заготовки"])))
            self.table_comps.setItem(i, 1, QTableWidgetItem(r["наименование"]))
            self.table_comps.setItem(i, 2, QTableWidgetItem(str(r["количество_готовых"])))

    def add_component_to_list(self):
        row = self.table_comps.currentRow()
        if row < 0:
            Toast.warning(self, "Внимание", "Выберите заготовку из списка выше")
            return
            
        id_zag = int(self.table_comps.item(row, 0).text())
        name_zag = self.table_comps.item(row, 1).text()
        
        # Ask quantity
        from PyQt6.QtWidgets import QSpinBox
        d = QDialog(self)
        d.setWindowTitle(f"Количество: {name_zag}")
        l = QVBoxLayout(d)
        
        form = QHBoxLayout()
        s = QSpinBox()
        s.setRange(1, 100)
        s.setValue(1)
        form.addWidget(QLabel("Кол-во:"))
        form.addWidget(s)
        l.addLayout(form)
        
        btn = QPushButton("OK")
        btn.clicked.connect(d.accept)
        l.addWidget(btn)
        
        if d.exec():
            qty = s.value()
            # Check if already added
            for c in self.chosen_components:
                if c["id"] == id_zag:
                    c["qty"] += qty
                    self.refresh_selected_list()
                    return
            
            self.chosen_components.append({"id": id_zag, "name": name_zag, "qty": qty})
            self.refresh_selected_list()

    def refresh_selected_list(self):
        self.list_selected.setRowCount(0)
        for i, c in enumerate(self.chosen_components):
            self.list_selected.insertRow(i)
            self.list_selected.setItem(i, 0, QTableWidgetItem(str(c["id"])))
            self.list_selected.setItem(i, 1, QTableWidgetItem(c["name"]))
            self.list_selected.setItem(i, 2, QTableWidgetItem(str(c["qty"])))

    def accept(self):
        name = self.name_input.text().strip()
        price = self.price_input.value()
        
        if not name:
            Toast.warning(self, "Ошибка", "Введите название изделия")
            return
            
        if not self.chosen_components:
            Toast.warning(self, "Ошибка", "Добавьте хотя бы одну заготовку в состав")
            return

        # 1. Generate SKU and Insert product
        import random
        import string
        sku = "PRD-" + "".join(random.choices(string.ascii_uppercase + string.digits, k=6))
        
        res_prod = Database.insert_returning(
            "INSERT INTO изделия (артикул_изделия, наименование, тип, размеры, стоимость, количество_на_складе) VALUES (%s, %s, %s, %s, %s, 0) RETURNING id_изделия",
            (sku, name, self.type_input.text(), self.size_input.text(), price)
        )
        if not res_prod:
             Toast.error(self, "Ошибка", "Не удалось создать изделие")
             return
             
        p_id = res_prod["id_изделия"]
        
        # 2. Insert components
        for c in self.chosen_components:
            Database.execute(
                "INSERT INTO состав_изделия (id_изделия, id_заготовки, количество_заготовки) VALUES (%s, %s, %s)",
                (p_id, c["id"], c["qty"])
            )
            
        Toast.success(self, "Успешно", f"Изделие '{name}' создано")
        super().accept()

