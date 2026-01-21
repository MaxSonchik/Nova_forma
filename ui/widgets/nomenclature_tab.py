import qtawesome as qta
from PyQt6.QtWidgets import (
    QDialog,
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
        btn_refresh = QPushButton("Обновить")
        btn_refresh.setIcon(qta.icon("fa5s.sync-alt"))
        btn_refresh.clicked.connect(self.load_data)
        toolbar.addStretch()
        toolbar.addWidget(btn_refresh)
        layout.addLayout(toolbar)

        # Table
        self.table = QTableWidget()
        self.table.setColumnCount(4)
        self.table.setHorizontalHeaderLabels(["ID", "Наименование", "Цена", "На складе"])
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
            self.table.setItem(i, 1, QTableWidgetItem(p["наименование"]))
            self.table.setItem(i, 2, QTableWidgetItem(f"{p['стоимость']:,.2f} ₽"))
            self.table.setItem(i, 3, QTableWidgetItem(str(p["количество_на_складе"])))

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

