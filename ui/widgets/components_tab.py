import qtawesome as qta
from PyQt6.QtWidgets import (
    QComboBox,
    QDialog,
    QHBoxLayout,
    QHeaderView,
    QInputDialog,
    QLabel,
    QLineEdit,
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


class ComponentsTab(QWidget):
    """Вкладка Заготовки (Components) - управление заготовками и их материалами"""

    def __init__(self):
        super().__init__()
        self.setup_ui()
        self.load_data()

    def setup_ui(self):
        layout = QVBoxLayout(self)

        # Header
        header = QLabel("Заготовки и их материалы")
        header.setStyleSheet("font-size: 18px; font-weight: bold; margin-bottom: 10px;")
        layout.addWidget(header)

        # Toolbar
        toolbar = QHBoxLayout()
        btn_refresh = QPushButton("Обновить")
        btn_refresh.setIcon(qta.icon("fa5s.sync-alt"))
        btn_refresh.clicked.connect(self.load_data)
        
        btn_add = QPushButton("Новая заготовка")
        btn_add.setIcon(qta.icon("fa5s.plus", color="#27AE60"))
        btn_add.clicked.connect(self.add_component)
        
        toolbar.addStretch()
        toolbar.addWidget(btn_refresh)
        toolbar.addWidget(btn_add)
        layout.addLayout(toolbar)

        # Table
        self.table = QTableWidget()
        self.table.setColumnCount(3)
        self.table.setHorizontalHeaderLabels(["ID", "Наименование", "На складе"])
        self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.table.itemSelectionChanged.connect(self.on_selection_changed)
        self.table.doubleClicked.connect(self.edit_component)
        layout.addWidget(self.table)

        # Materials panel (below table)
        self.materials_label = QLabel("Материалы для заготовки:")
        self.materials_label.setStyleSheet("font-weight: bold; margin-top: 10px;")
        layout.addWidget(self.materials_label)

        self.materials_table = QTableWidget()
        self.materials_table.setColumnCount(3)
        self.materials_table.setHorizontalHeaderLabels(["ID", "Материал", "Количество"])
        self.materials_table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.materials_table.setColumnHidden(0, True)
        self.materials_table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.materials_table.setMaximumHeight(150)
        layout.addWidget(self.materials_table)

        # Buttons
        btn_layout = QHBoxLayout()
        btn_materials = QPushButton("Управление материалами")
        btn_materials.setIcon(qta.icon("fa5s.cogs"))
        btn_materials.clicked.connect(self.manage_materials)
        btn_layout.addStretch()
        btn_layout.addWidget(btn_materials)
        layout.addLayout(btn_layout)

    def load_data(self):
        components = Database.fetch_all("SELECT * FROM sp_get_all_components()")
        self.table.setRowCount(0)
        for i, c in enumerate(components):
            self.table.insertRow(i)
            self.table.setItem(i, 0, QTableWidgetItem(str(c["id_заготовки"])))
            self.table.setItem(i, 1, QTableWidgetItem(c["наименование"]))
            self.table.setItem(i, 2, QTableWidgetItem(str(c["количество_на_складе"] or 0)))

    def on_selection_changed(self):
        component_id = self.get_selected_id()
        if not component_id:
            self.materials_table.setRowCount(0)
            return

        materials = Database.fetch_all(
            "SELECT * FROM sp_get_component_materials(%s)", (component_id,)
        )
        self.materials_table.setRowCount(0)
        for i, m in enumerate(materials):
            self.materials_table.insertRow(i)
            self.materials_table.setItem(i, 0, QTableWidgetItem(str(m["id_материала"])))
            self.materials_table.setItem(i, 1, QTableWidgetItem(m["наименование"]))
            self.materials_table.setItem(i, 2, QTableWidgetItem(str(m["количество"])))

    def get_selected_id(self):
        selected = self.table.selectedItems()
        if not selected:
            return None
        row = selected[0].row()
        return int(self.table.item(row, 0).text())

    def add_component(self):
        name, ok = QInputDialog.getText(self, "Новая заготовка", "Наименование:")
        if ok and name.strip():
            result = Database.call_procedure("sp_create_component", [name.strip()])
            if result.get("status") == "OK":
                Toast.success(self, "Успешно", result.get("message"))
                self.load_data()
            else:
                Toast.error(self, "Ошибка", result.get("message", "Неизвестная ошибка"))

    def edit_component(self):
        component_id = self.get_selected_id()
        if not component_id:
            return

        row = self.table.selectedItems()[0].row()
        current_name = self.table.item(row, 1).text()

        new_name, ok = QInputDialog.getText(self, "Редактировать", "Наименование:", text=current_name)
        if ok and new_name.strip():
            result = Database.call_procedure("sp_update_component", [component_id, new_name.strip()])
            if result.get("status") == "OK":
                Toast.success(self, "Успешно", result.get("message"))
                self.load_data()
            else:
                Toast.error(self, "Ошибка", result.get("message", "Неизвестная ошибка"))

    def manage_materials(self):
        component_id = self.get_selected_id()
        if not component_id:
            Toast.warning(self, "Внимание", "Выберите заготовку")
            return

        row = self.table.selectedItems()[0].row()
        component_name = self.table.item(row, 1).text()

        dialog = ComponentMaterialsDialog(self, component_id, component_name)
        if dialog.exec():
            self.on_selection_changed()


class ComponentMaterialsDialog(QDialog):
    """Диалог управления материалами заготовки"""
    def __init__(self, parent, component_id, component_name):
        super().__init__(parent)
        self.component_id = component_id
        self.setWindowTitle(f"Материалы: {component_name}")
        self.setFixedSize(550, 400)

        layout = QVBoxLayout(self)

        # Table
        self.table = QTableWidget()
        self.table.setColumnCount(3)
        self.table.setHorizontalHeaderLabels(["ID", "Материал", "Количество"])
        self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.table.setColumnHidden(0, True)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        layout.addWidget(self.table)

        # Buttons
        btn_layout = QHBoxLayout()

        btn_add = QPushButton("Добавить")
        btn_add.setIcon(qta.icon("fa5s.plus", color="#27AE60"))
        btn_add.clicked.connect(self.add_material)

        btn_edit = QPushButton("Изменить")
        btn_edit.setIcon(qta.icon("fa5s.edit", color="#3498DB"))
        btn_edit.clicked.connect(self.edit_material)

        btn_delete = QPushButton("Удалить")
        btn_delete.setIcon(qta.icon("fa5s.trash", color="#E74C3C"))
        btn_delete.clicked.connect(self.delete_material)

        btn_close = QPushButton("Закрыть")
        btn_close.clicked.connect(self.accept)

        btn_layout.addWidget(btn_add)
        btn_layout.addWidget(btn_edit)
        btn_layout.addWidget(btn_delete)
        btn_layout.addStretch()
        btn_layout.addWidget(btn_close)
        layout.addLayout(btn_layout)

        self.load_materials()

    def load_materials(self):
        materials = Database.fetch_all(
            "SELECT * FROM sp_get_component_materials(%s)", (self.component_id,)
        )
        self.table.setRowCount(0)
        for i, m in enumerate(materials):
            self.table.insertRow(i)
            self.table.setItem(i, 0, QTableWidgetItem(str(m["id_материала"])))
            self.table.setItem(i, 1, QTableWidgetItem(m["наименование"]))
            self.table.setItem(i, 2, QTableWidgetItem(str(m["количество"])))

    def get_selected_material_id(self):
        selected = self.table.selectedItems()
        if not selected:
            return None
        row = selected[0].row()
        return int(self.table.item(row, 0).text())

    def add_material(self):
        # Get all materials from DB
        all_materials = Database.fetch_all("SELECT * FROM sp_get_all_materials()")
        if not all_materials:
            Toast.warning(self, "Внимание", "Нет доступных материалов")
            return

        # Selection dialog
        dialog = QDialog(self)
        dialog.setWindowTitle("Добавить материал")
        dialog.setFixedSize(450, 280)
        dlg_layout = QVBoxLayout(dialog)

        # Material selection
        combo = QComboBox()
        for m in all_materials:
            combo.addItem(m["наименование"], m["id_материала"])
        dlg_layout.addWidget(QLabel("Выберите материал:"))
        dlg_layout.addWidget(combo)

        # Or enter new name
        dlg_layout.addWidget(QLabel("Или введите новый (оставьте пустым для выбора):"))
        new_name_input = QLineEdit()
        new_name_input.setPlaceholderText("Название нового материала")
        new_name_input.setStyleSheet("""
            QLineEdit {
                padding: 10px;
                border: 2px solid #3498DB;
                border-radius: 4px;
                font-size: 15px;
                background-color: #FFFFFF;
                color: #2C3E50;
            }
            QLineEdit::placeholder {
                color: #7F8C8D;
            }
            QLineEdit:focus {
                border-color: #2980B9;
            }
        """)
        dlg_layout.addWidget(new_name_input)

        # Quantity
        spin = QSpinBox()
        spin.setRange(1, 1000)
        spin.setValue(1)
        dlg_layout.addWidget(QLabel("Количество:"))
        dlg_layout.addWidget(spin)

        btn_ok = QPushButton("Добавить")
        btn_ok.clicked.connect(dialog.accept)
        dlg_layout.addWidget(btn_ok)

        if dialog.exec():
            new_name = new_name_input.text().strip()
            qty = spin.value()

            if new_name:
                # Create new material first (generate article number)
                import time
                article = f"MAT-{int(time.time()) % 100000}"
                res = Database.insert_returning(
                    "INSERT INTO материалы (артикул_материала, наименование, количество_на_складе) VALUES (%s, %s, 0) RETURNING id_материала",
                    (article, new_name)
                )
                if res:
                    material_id = res["id_материала"]
                else:
                    Toast.error(self, "Ошибка", "Не удалось создать материал")
                    return
            else:
                material_id = combo.currentData()

            result = Database.call_procedure("sp_add_component_material", [self.component_id, material_id, qty])
            if result.get("status") == "OK":
                Toast.success(self, "Успешно", result.get("message"))
                self.load_materials()
            else:
                Toast.error(self, "Ошибка", result.get("message", "Неизвестная ошибка"))

    def edit_material(self):
        material_id = self.get_selected_material_id()
        if not material_id:
            Toast.warning(self, "Внимание", "Выберите материал")
            return

        row = self.table.selectedItems()[0].row()
        current_qty = int(self.table.item(row, 2).text())

        new_qty, ok = QInputDialog.getInt(self, "Изменить количество", "Новое количество:", current_qty, 1, 1000)
        if ok:
            result = Database.call_procedure("sp_update_component_material", [self.component_id, material_id, new_qty])
            if result.get("status") == "OK":
                Toast.success(self, "Успешно", result.get("message"))
                self.load_materials()
            else:
                Toast.error(self, "Ошибка", result.get("message", "Неизвестная ошибка"))

    def delete_material(self):
        material_id = self.get_selected_material_id()
        if not material_id:
            Toast.warning(self, "Внимание", "Выберите материал")
            return

        reply = QMessageBox.question(self, "Подтверждение", "Удалить материал из заготовки?")
        if reply == QMessageBox.StandardButton.Yes:
            result = Database.call_procedure("sp_delete_component_material", [self.component_id, material_id])
            if result.get("status") == "OK":
                Toast.success(self, "Успешно", result.get("message"))
                self.load_materials()
            else:
                Toast.error(self, "Ошибка", result.get("message", "Неизвестная ошибка"))
