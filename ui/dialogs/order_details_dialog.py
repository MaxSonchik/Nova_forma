from PyQt6.QtWidgets import (
    QDialog, QVBoxLayout, QTableWidget, QTableWidgetItem, 
    QPushButton, QHeaderView, QLabel
)
from PyQt6.QtCore import Qt
from db.database import Database

class OrderDetailsDialog(QDialog):
    def __init__(self, parent, order_id):
        super().__init__(parent)
        self.order_id = order_id
        self.setWindowTitle(f"Состав заказа №{order_id}")
        self.resize(600, 400)
        
        layout = QVBoxLayout(self)
        
               
        layout.addWidget(QLabel(f"<h2>Заказ №{order_id}</h2>"))
        
               
        self.table = QTableWidget()
        self.table.setColumnCount(5)
        self.table.setHorizontalHeaderLabels([
            "ID Изделия", "Наименование", "Кол-во", "Цена (руб.)", "Сумма (руб.)"
        ])
        
                        
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        header.setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(3, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(4, QHeaderView.ResizeMode.ResizeToContents)
        
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        
        layout.addWidget(self.table)
        
                      
        btn_close = QPushButton("Закрыть")
        btn_close.clicked.connect(self.accept)
        layout.addWidget(btn_close)
        
        self.load_data()

    def load_data(self):
        try:
            items = Database.fetch_all(
                "SELECT * FROM sp_get_order_items(%s)", 
                (self.order_id,)
            )
            
            self.table.setRowCount(0)
            total_sum = 0
            
            for i, row in enumerate(items):
                self.table.insertRow(i)
                self.table.setItem(i, 0, QTableWidgetItem(str(row['id_изделия'])))
                self.table.setItem(i, 1, QTableWidgetItem(str(row['наименование'])))
                self.table.setItem(i, 2, QTableWidgetItem(str(row['количество'])))
                self.table.setItem(i, 3, QTableWidgetItem(f"{row['цена']:,.2f}"))
                self.table.setItem(i, 4, QTableWidgetItem(f"{row['сумма']:,.2f}"))
                
                total_sum += row['сумма']
                
                                                            
                                                                                               
            
        except Exception as e:
                                                          
            from ui.widgets.toast import Toast
            Toast.error(self, "Ошибка загрузки", str(e))

                              
        self.table.itemDoubleClicked.connect(self.show_components)

    def show_components(self, item):
        row = item.row()
        product_id = int(self.table.item(row, 0).text())
        product_name = self.table.item(row, 1).text()
        
        dialog = ProductComponentsDialog(self, self.order_id, product_id, product_name)
        dialog.exec()

class ProductComponentsDialog(QDialog):
    def __init__(self, parent, order_id, product_id, product_name):
        super().__init__(parent)
        self.setWindowTitle(f"Состав изделия: {product_name}")
        self.resize(500, 300)
        
        layout = QVBoxLayout(self)
        
        layout.addWidget(QLabel(f"<h3>{product_name}</h3>"))
        layout.addWidget(QLabel("Статус заготовок для текущего заказа:"))
        
        self.table = QTableWidget()
        self.table.setColumnCount(4)
        self.table.setHorizontalHeaderLabels([
            "Заготовка", "Требуется", "Готово", "Осталось"
        ])
        
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        
        layout.addWidget(self.table)
        
        btn_close = QPushButton("Закрыть")
        btn_close.clicked.connect(self.accept)
        layout.addWidget(btn_close)
        
        self.load_data(order_id, product_id)

    def load_data(self, order_id, product_id):
        try:
            items = Database.fetch_all(
                "SELECT * FROM sp_get_product_components_status(%s, %s)",
                (order_id, product_id)
            )
            
            self.table.setRowCount(0)
            for i, row in enumerate(items):
                self.table.insertRow(i)
                self.table.setItem(i, 0, QTableWidgetItem(str(row['наименование_заготовки'])))
                self.table.setItem(i, 1, QTableWidgetItem(str(row['требуется'])))
                self.table.setItem(i, 2, QTableWidgetItem(str(row['выполнено'])))
                
                rem_item = QTableWidgetItem(str(row['осталось']))
                if row['осталось'] > 0:
                    rem_item.setForeground(Qt.GlobalColor.red)
                else:
                    rem_item.setForeground(Qt.GlobalColor.green)
                self.table.setItem(i, 3, rem_item)
                
        except Exception as e:
            from ui.widgets.toast import Toast
            Toast.error(self, "Ошибка загрузки состава", str(e))
