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

                
        header = QLabel("Номенклатура изделий")
        header.setStyleSheet("font-size: 18px; font-weight: bold; margin-bottom: 10px;")
        layout.addWidget(header)

                 
        toolbar = QHBoxLayout()
        
        btn_add = QPushButton("Новое изделие")
        btn_add.setIcon(qta.icon("fa5s.plus", color="#27AE60"))
        btn_add.clicked.connect(self.add_product)
        
        btn_delete = QPushButton("Удалить изделие")
        btn_delete.setIcon(qta.icon("fa5s.trash", color="#E74C3C"))
        btn_delete.clicked.connect(self.delete_product)
        
        btn_refresh = QPushButton("Обновить")
        btn_refresh.setIcon(qta.icon("fa5s.sync-alt"))
        btn_refresh.clicked.connect(self.load_data)
        
        toolbar.addWidget(btn_add)
        toolbar.addWidget(btn_delete)
        toolbar.addStretch()
        toolbar.addWidget(btn_refresh)
        layout.addLayout(toolbar)

               
        self.table = QTableWidget()
        self.table.setColumnCount(5)                         
        self.table.setHorizontalHeaderLabels(["ID", "Наименование", "Тип", "Размеры", "Цена"])
        
                      
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)     
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)                
        header.setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)       
        header.setSectionResizeMode(3, QHeaderView.ResizeMode.ResizeToContents)             
        header.setSectionResizeMode(4, QHeaderView.ResizeMode.ResizeToContents)        


        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.table.doubleClicked.connect(self.edit_product)
        self.table.itemSelectionChanged.connect(self.on_selection_changed)
        layout.addWidget(self.table)

                                        
        self.components_label = QLabel("Состав Изделие:")
        self.components_label.setStyleSheet("font-weight: bold; margin-top: 10px;")
        layout.addWidget(self.components_label)
        
        self.components_table = QTableWidget()
        self.components_table.setColumnCount(2)
        self.components_table.setHorizontalHeaderLabels(["Заготовка", "Количество"])
        self.components_table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        self.components_table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.components_table.setMaximumHeight(150)
        layout.addWidget(self.components_table)

                 
        btn_layout = QHBoxLayout()
        btn_components = QPushButton("Состав Изделие")
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
            self.table.setItem(i, 2, QTableWidgetItem(p["тип"]))
            self.table.setItem(i, 3, QTableWidgetItem(p["размеры"]))
            self.table.setItem(i, 4, QTableWidgetItem(f"{p['стоимость']:,.2f} ₽"))

    def on_selection_changed(self):
        """При выборе Изделие показываем его состав"""
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
        current_type = self.table.item(row, 2).text()
        current_size = self.table.item(row, 3).text()
        current_price = self.table.item(row, 4).text().replace(" ₽", "").replace(",", "").replace("\xa0", "").strip()                     

        dialog = EditProductDialog(self, product_id, current_name, current_type, current_size, float(current_price))
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
        if dialog.exec():
            self.on_selection_changed()

    def add_product(self):
         dialog = AddProductDialog(self)
         if dialog.exec():
             self.load_data()

    def delete_product(self):
        product_id = self.get_selected_id()
        if not product_id:
            Toast.warning(self, "Внимание", "Выберите изделие для удаления")
            return

        row = self.table.selectedItems()[0].row()
        product_name = self.table.item(row, 1).text()

        reply = QMessageBox.question(
            self,
            "Подтверждение удаления",
            f"ВНИМАНИЕ: Каскадное удаление!\n\nВы действительно хотите безвозвратно удалить Изделие '{product_name}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )

        if reply == QMessageBox.StandardButton.Yes:
            result = Database.call_procedure("sp_delete_product", [product_id])
            if result.get("status") == "OK":
                Toast.success(self, "Удалено", result.get("message"))
                self.load_data()
                self.components_table.setRowCount(0)
            else:
                Toast.error(self, "Ошибка удаления", result.get("message", "Неизвестная ошибка"))


class AddProductDialog(QDialog):
    def __init__(self, parent):
        super().__init__(parent)
        self.setWindowTitle("Новое изделие")
        self.resize(400, 350)
        
        layout = QVBoxLayout(self)
        
        layout.addWidget(QLabel("Наименование:"))
        self.input_name = QLineEdit()
        layout.addWidget(self.input_name)

        layout.addWidget(QLabel("Тип:"))
        self.input_type = QLineEdit()
        layout.addWidget(self.input_type)
        
        layout.addWidget(QLabel("Размеры:"))
        self.input_size = QLineEdit()
        layout.addWidget(self.input_size)
        
        layout.addWidget(QLabel("Стоимость (руб):"))
        self.spin_price = QDoubleSpinBox()
        self.spin_price.setRange(0, 1000000)
        layout.addWidget(self.spin_price)
        
        btn_save = QPushButton("Сохранить")
        btn_save.clicked.connect(self.save)
        layout.addWidget(btn_save)

    def save(self):
        name = self.input_name.text().strip()
        p_type = self.input_type.text().strip()
        size = self.input_size.text().strip()
        price = self.spin_price.value()

        if not name:
            QMessageBox.warning(self, "Ошибка", "Введите наименование")
            return

        res = Database.call_procedure("sp_create_product", [name, p_type, size, price])
        if res.get("status") == "OK":
            Toast.success(self.parent(), "Успешно", "Изделие создано")
            self.accept()
        else:
            Toast.error(self, "Ошибка", res.get("message", ""))


class EditProductDialog(QDialog):
    def __init__(self, parent, product_id, name, p_type, size, price):
        super().__init__(parent)
        self.product_id = product_id
        self.setWindowTitle("Редактировать изделие")
        self.resize(400, 350)
        
        layout = QVBoxLayout(self)
        
        layout.addWidget(QLabel("Наименование:"))
        self.input_name = QLineEdit(name)
        layout.addWidget(self.input_name)

        layout.addWidget(QLabel("Тип:"))
        self.input_type = QLineEdit(p_type)
        layout.addWidget(self.input_type)
        
        layout.addWidget(QLabel("Размеры:"))
        self.input_size = QLineEdit(size)
        layout.addWidget(self.input_size)
        
        layout.addWidget(QLabel("Стоимость:"))
        self.spin_price = QDoubleSpinBox()
        self.spin_price.setRange(0, 1000000)
        self.spin_price.setValue(price)
        layout.addWidget(self.spin_price)
        
        btn_save = QPushButton("Сохранить")
        btn_save.clicked.connect(self.save)
        layout.addWidget(btn_save)

    def save(self):
        name = self.input_name.text().strip()
        p_type = self.input_type.text().strip()
        size = self.input_size.text().strip()
        price = self.spin_price.value()
        
        if not name:
            QMessageBox.warning(self, "Ошибка", "Введите наименование")
            return
            
        res = Database.call_procedure("sp_update_product", [self.product_id, name, p_type, size, price])
        if res.get("status") == "OK":
            Toast.success(self.parent(), "Успешно", "Изделие обновлено")
            self.accept()
        else:
            Toast.error(self, "Ошибка", res.get("message", "Не удалось обновить"))


class ProductComponentsDialog(QDialog):
    """Диалог управления составом изделия (Product Composition)"""
    def __init__(self, parent, product_id, product_name):
        super().__init__(parent)
        self.product_id = product_id
        self.setWindowTitle(f"Состав изделия: {product_name}")
        self.setFixedSize(600, 450)

        layout = QVBoxLayout(self)

               
        self.table = QTableWidget()
        self.table.setColumnCount(3)
        self.table.setHorizontalHeaderLabels(["ID", "Заготовка", "Количество"])
        self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.table.setColumnHidden(0, True)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        layout.addWidget(self.table)

                 
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
                                         
        all_components = Database.fetch_all("SELECT * FROM sp_get_all_components()")
        if not all_components:
            Toast.warning(self, "Внимание", "Нет доступных заготовок")
            return

                                     
                                                                   
                                                                                                            
        
                                 
        dialog = QDialog(self)
        dialog.setWindowTitle("Добавить заготовку")
        dialog.setFixedSize(400, 150)
        l = QVBoxLayout(dialog)
        
        import PyQt6.QtWidgets as QtWidgets
        combo = QtWidgets.QComboBox()
        for c in all_components:
            combo.addItem(c["наименование"], c["id_заготовки"])
        l.addWidget(QLabel("Выберите заготовку:"))
        l.addWidget(combo)

        spin = QtWidgets.QSpinBox()
        spin.setRange(1, 1000)
        spin.setValue(1)
        l.addWidget(QLabel("Количество:"))
        l.addWidget(spin)
        
        btn_ok = QPushButton("Добавить")
        btn_ok.clicked.connect(dialog.accept)
        l.addWidget(btn_ok)
        
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

        row = self.table.selectedItems()[0].row()
        current_qty = int(self.table.item(row, 2).text())

        import PyQt6.QtWidgets as QtWidgets
        new_qty, ok = QtWidgets.QInputDialog.getInt(self, "Изменить количество", "Новое количество:", current_qty, 1, 1000)
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
