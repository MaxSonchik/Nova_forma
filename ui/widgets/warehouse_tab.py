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
    def __init__(self, user_id=None):
        super().__init__()
        self.user_id = user_id
        self.setup_ui()
        self.load_data()

    def setup_ui(self):
        layout = QVBoxLayout(self)

                                 
        toolbar = QHBoxLayout()

                  
        self.search_input = QLineEdit()
        self.search_input.setPlaceholderText("🔍 Поиск по Названию...")
        self.search_input.textChanged.connect(self.load_data)

                           
        self.type_filter = QComboBox()
        self.type_filter.addItems(["Все типы", "Материал", "Заготовка", "Изделие"])
        self.type_filter.currentTextChanged.connect(self.load_data)

                            
        btn_refresh = QPushButton()
        btn_refresh.setIcon(qta.icon("fa5s.sync-alt"))
        btn_refresh.setFixedWidth(40)
        btn_refresh.clicked.connect(self.load_data)

        btn_delete = QPushButton("Удалить выбранное")
        btn_delete.setIcon(qta.icon("fa5s.trash", color="#E74C3C"))
        btn_delete.clicked.connect(self.delete_item)

        btn_replenish = QPushButton("Пополнить склад")
        btn_replenish.setIcon(qta.icon("fa5s.box", color="#27AE60"))
        btn_replenish.clicked.connect(self.open_replenish_dialog)

        toolbar.addWidget(self.search_input, 2)
        toolbar.addWidget(self.type_filter, 1)
        toolbar.addWidget(btn_refresh)
        toolbar.addWidget(btn_replenish)
        toolbar.addWidget(btn_delete)

        layout.addLayout(toolbar)

                         
        self.table = QTableWidget()
        self.table.setColumnCount(4)
        self.table.setHorizontalHeaderLabels(
            ["Тип", "Наименование", "Количество", "Ед. изм."]
        )

                          
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(
            1, QHeaderView.ResizeMode.Stretch
        )                        
        header.setSectionResizeMode(
            0, QHeaderView.ResizeMode.ResizeToContents
        )                        

        self.table.verticalHeader().setVisible(False)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(
            QTableWidget.EditTrigger.NoEditTriggers
        )                         

        layout.addWidget(self.table)

    def load_data(self):
        search_text = self.search_input.text().strip().lower()
        selected_type = self.type_filter.currentText()

        if selected_type == "Все типы":
            selected_type = None
            
        if not search_text:
            search_text = None
            
                                                     
        items = Database.fetch_all(
            "SELECT * FROM sp_get_warehouse_summary(%s, %s)", 
            (search_text, selected_type)
        )
        self.populate_table(items)

    def populate_table(self, items):
        self.table.setRowCount(0)

        for row_idx, item in enumerate(items):
            self.table.insertRow(row_idx)

                             
            item_type = item["тип"]
            icon_name = "fa5s.box"          
            if item_type == "Материал":
                icon_name = "fa5s.layer-group"
            elif item_type == "Заготовка":
                icon_name = "fa5s.puzzle-piece"
            elif item_type == "Изделие":
                icon_name = "fa5s.chair"

                                             
            qty = item["количество"]
            text_color = QColor("black")
            if qty == 0:
                text_color = QColor("#E74C3C")           

                              
                                
            type_item = QTableWidgetItem(item_type)
            type_item.setIcon(qta.icon(icon_name, color="#2C3E50"))
            self.table.setItem(row_idx, 0, type_item)

                             
            self.table.setItem(row_idx, 1, QTableWidgetItem(item.get("наименование", "")))

                           
            qty_item = QTableWidgetItem(str(qty))
            qty_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            qty_item.setForeground(text_color)
            qty_item.setToolTip("Нет на складе!")
            self.table.setItem(row_idx, 2, qty_item)

                         
            unit = item.get("ед_изм") or item.get("единица_измерения", "")
            self.table.setItem(row_idx, 3, QTableWidgetItem(unit))
            
            # Store internal ID for deletion operations
            self.table.item(row_idx, 0).setData(Qt.ItemDataRole.UserRole, item["id_объекта"])

    def delete_item(self):
        selected = self.table.selectedItems()
        if not selected:
            from ui.widgets.toast import Toast
            Toast.warning(self, "Внимание", "Выберите строку для удаления")
            return

        row = selected[0].row()
        item_type = self.table.item(row, 0).text()
        item_name = self.table.item(row, 1).text()
        item_id = self.table.item(row, 0).data(Qt.ItemDataRole.UserRole)
        
        proc_map = {
            "Изделие": ("sp_delete_product", "Изделие"),
            "Заготовка": ("sp_delete_component", "Заготовку"),
            "Материал": ("sp_delete_material", "Материал"),
        }
        
        if item_type not in proc_map:
            from ui.widgets.toast import Toast
            Toast.warning(self, "Внимание", f"Удаление для типа '{item_type}' не поддерживается")
            return
            
        proc_name, type_label = proc_map[item_type]

        from PyQt6.QtWidgets import QMessageBox
        reply = QMessageBox.question(
            self,
            "Подтверждение удаления",
            f"ВНИМАНИЕ: Каскадное удаление!\n\nВы действительно хотите безвозвратно удалить {type_label} '{item_name}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )

        if reply == QMessageBox.StandardButton.Yes:
            result = Database.call_procedure(proc_name, [item_id])
            from ui.widgets.toast import Toast
            if result.get("status") == "OK":
                Toast.success(self, "Удалено", result.get("message"))
                self.load_data()
            else:
                Toast.error(self, "Ошибка удаления", result.get("message", "Неизвестная ошибка"))

    def open_replenish_dialog(self):
        """Open dialog to create a stock replenishment (service) order"""
        from ui.widgets.production_planning_tab import AddManualTaskDialog
        from ui.widgets.toast import Toast

        if self.user_id is None:
            Toast.warning(self, "Внимание", "Нет данных о пользователе для создания заказа")
            return

        dialog = AddManualTaskDialog(self, self.user_id, replenish_mode=True)
        if dialog.exec():
            self.load_data()
