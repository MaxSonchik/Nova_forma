import qtawesome as qta
from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import (
    QDialog,
    QDoubleSpinBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QPushButton,
    QSpinBox,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from db.database import Database
from ui.widgets.toast import Toast


class PurchasesTab(QWidget):
    """Tab for director to manage material purchases.

    Allows: list purchases, create new purchase with several materials,
    change status and confirm executed purchases (which increases stock).
    """

    def __init__(self):
        super().__init__()
        self.setup_ui()
        self.load_purchases()

    def setup_ui(self):
        layout = QVBoxLayout(self)

        toolbar = QHBoxLayout()

        self.search_input = QLineEdit()
        self.search_input.setPlaceholderText("Поиск по поставщику или статусу...")
        self.search_input.textChanged.connect(self.load_purchases)

        btn_new = QPushButton("Новая закупка")
        btn_new.setIcon(qta.icon("fa5s.plus"))
        btn_new.clicked.connect(self.open_new_purchase_dialog)

        btn_refresh = QPushButton()
        btn_refresh.setIcon(qta.icon("fa5s.sync-alt"))
        btn_refresh.clicked.connect(self.load_purchases)

        btn_confirm = QPushButton("Подтвердить выполнено")
        btn_confirm.clicked.connect(self.confirm_selected)

        btn_cancel = QPushButton("Отменить закупку")
        btn_cancel.setIcon(qta.icon("fa5s.times", color="#E74C3C"))
        btn_cancel.clicked.connect(self.cancel_selected)

        toolbar.addWidget(self.search_input)
        toolbar.addWidget(btn_new)
        toolbar.addWidget(btn_confirm)
        toolbar.addWidget(btn_cancel)
        toolbar.addWidget(btn_refresh)

        layout.addLayout(toolbar)

        self.table = QTableWidget()
        self.table.setColumnCount(5)
        self.table.setHorizontalHeaderLabels(
            ["ID", "Дата", "Поставщик", "Статус", "Сумма"]
        )
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(2, QHeaderView.ResizeMode.Stretch)
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        self.table.verticalHeader().setVisible(False)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.table.doubleClicked.connect(self.show_details)
        layout.addWidget(self.table)

    def load_purchases(self):
        text = self.search_input.text().strip().lower()
        query = "SELECT id_закупки, дата_закупки, поставщик, статус FROM закупки_материалов WHERE 1=1"
        params = []
        if text:
            query += " AND (LOWER(поставщик) LIKE %s OR LOWER(статус) LIKE %s)"
            like = f"%{text}%"
            params.extend([like, like])
        query += " ORDER BY дата_закупки DESC"

        rows = Database.fetch_all(query, params)
        # compute sum per purchase
        self.table.setRowCount(0)
        for i, r in enumerate(rows):
            self.table.insertRow(i)
            self.table.setItem(i, 0, QTableWidgetItem(str(r["id_закупки"])))
            self.table.setItem(i, 1, QTableWidgetItem(str(r["дата_закупки"])))
            self.table.setItem(i, 2, QTableWidgetItem(r["поставщик"] or ""))
            self.table.setItem(i, 3, QTableWidgetItem(r["статус"] or ""))

            sum_row = Database.fetch_one(
                "SELECT COALESCE(SUM(количество * цена_закупки), 0) AS s FROM состав_закупки WHERE id_закупки = %s",
                (r["id_закупки"],),
            )
            total = float(sum_row["s"]) if sum_row else 0.0
            self.table.setItem(i, 4, QTableWidgetItem(f"{total:.2f}"))

    def open_new_purchase_dialog(self):
        d = NewPurchaseDialog(self)
        if d.exec():
            supplier, items = d.get_data()
            # Insert into закупки_материалов
            res = Database.insert_returning(
                "INSERT INTO закупки_материалов (поставщик, статус) VALUES (%s, %s) RETURNING id_закупки",
                (supplier, "ожидает_подтверждения"),
            )
            if not res:
                Toast.error(self, "Ошибка", "Не удалось создать закупку")
                return
            purchase_id = res["id_закупки"]
            # Insert items
            for mat in items:
                Database.execute(
                    "INSERT INTO состав_закупки (id_закупки, id_материала, количество, цена_закупки) VALUES (%s, %s, %s, %s)",
                    (purchase_id, mat["id"], mat["qty"], mat["price"]),
                )
            Toast.success(self, "ОК", "Закупка создана")
            self.load_purchases()

    def confirm_selected(self):
        selected = self.table.currentRow()
        if selected < 0:
            Toast.error(self, "Ошибка", "Выберите закупку")
            return
        purchase_id = int(self.table.item(selected, 0).text())
        # Update status to выполнено and add quantities to materials
        ok, msg = Database.execute(
            "UPDATE закупки_материалов SET статус = %s WHERE id_закупки = %s",
            ("выполнено", purchase_id),
        )
        if not ok:
            Toast.error(self, "Ошибка", msg)
            return
        # Add quantities to materials (increase stock)
        items = Database.fetch_all(
            "SELECT id_материала, количество FROM состав_закупки WHERE id_закупки = %s",
            (purchase_id,),
        )
        for it in items:
            Database.execute(
                "UPDATE материалы SET количество_на_складе = COALESCE(количество_на_складе,0) + %s WHERE id_материала = %s",
                (it["количество"], it["id_материала"]),
            )
        Toast.success(self, "ОК", "Закупка подтверждена и склад обновлён")
        self.load_purchases()

    def cancel_selected(self):
        selected = self.table.currentRow()
        if selected < 0:
            Toast.error(self, "Ошибка", "Выберите закупку")
            return
        purchase_id = int(self.table.item(selected, 0).text())
        
        result = Database.call_procedure("sp_cancel_purchase", [purchase_id])
        if result.get("status") == "OK":
            Toast.success(self, "ОК", result.get("message"))
            self.load_purchases()
        else:
            Toast.error(self, "Ошибка", result.get("message", "Неизвестная ошибка"))

    def show_details(self):
        """Show popup with purchase details"""
        selected = self.table.currentRow()
        if selected < 0:
            return
            
        purchase_id = int(self.table.item(selected, 0).text())
        
        # Get items for this purchase
        items = Database.fetch_all(
            """
            SELECT m.наименование, sz.количество, sz.цена_закупки 
            FROM состав_закупки sz 
            JOIN материалы m ON sz.id_материала = m.id_материала 
            WHERE sz.id_закупки = %s
            """,
            (purchase_id,)
        )
        
        # Create simple dialog
        d = QDialog(self)
        d.setWindowTitle(f"Состав закупки #{purchase_id}")
        d.resize(500, 300)
        
        layout = QVBoxLayout(d)
        
        table = QTableWidget()
        table.setColumnCount(3)
        table.setHorizontalHeaderLabels(["Материал", "Кол-во", "Цена"])
        table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        table.verticalHeader().setVisible(False)
        table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        
        table.setRowCount(len(items))
        for i, item in enumerate(items):
            table.setItem(i, 0, QTableWidgetItem(item["наименование"]))
            table.setItem(i, 1, QTableWidgetItem(str(item["количество"])))
            table.setItem(i, 2, QTableWidgetItem(f"{item['цена_закупки']:.2f}"))
            
        layout.addWidget(table)
        
        btn = QPushButton("Закрыть")
        btn.clicked.connect(d.accept)
        layout.addWidget(btn)
        
        d.exec()
        

class NewPurchaseDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Новая закупка")
        self.resize(800, 500)
        self.setup_ui()

    def setup_ui(self):
        layout = QVBoxLayout(self)

        top = QHBoxLayout()
        top.addWidget(QLabel("Поставщик:"))
        self.supplier_input = QLineEdit()
        top.addWidget(self.supplier_input)

        self.material_search = QLineEdit()
        self.material_search.setPlaceholderText(
            "Поиск материала по наименованию или артикулу"
        )
        self.material_search.textChanged.connect(self.load_materials)
        top.addWidget(self.material_search)

        layout.addLayout(top)

        # Show only material name to the user (keep id hidden for internal use)
        self.materials_table = QTableWidget()
        # Column 0: hidden id, Column 1: Наименование
        self.materials_table.setColumnCount(2)
        self.materials_table.setHorizontalHeaderLabels(["ID", "Наименование"])
        self.materials_table.verticalHeader().setVisible(False)
        header = self.materials_table.horizontalHeader()
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.materials_table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.materials_table.setSelectionBehavior(
            QTableWidget.SelectionBehavior.SelectRows
        )
        self.materials_table.setSelectionMode(
            QTableWidget.SelectionMode.ExtendedSelection
        )
        layout.addWidget(self.materials_table)

        btns = QHBoxLayout()
        self.btn_add_selected = QPushButton("Добавить выбранные")
        self.btn_add_selected.clicked.connect(self.add_selected)
        btns.addWidget(self.btn_add_selected)

        self.save_btn = QPushButton("Сохранить")
        self.save_btn.clicked.connect(self.accept)
        btns.addWidget(self.save_btn)

        self.cancel_btn = QPushButton("Отмена")
        self.cancel_btn.clicked.connect(self.reject)
        btns.addWidget(self.cancel_btn)

        layout.addLayout(btns)

        # Internal list of chosen items
        self.chosen = []
        self.load_materials()

    def load_materials(self):
        q = self.material_search.text().strip().lower()
        sql = "SELECT id_материала, артикул_материала AS артикул, наименование FROM материалы WHERE 1=1"
        params = []
        if q:
            sql += (
                " AND (LOWER(наименование) LIKE %s OR LOWER(артикул_материала) LIKE %s)"
            )
            like = f"%{q}%"
            params.extend([like, like])
        rows = Database.fetch_all(sql, params)
        self.materials_table.setRowCount(0)
        for i, r in enumerate(rows):
            self.materials_table.insertRow(i)
            id_item = QTableWidgetItem(str(r["id_материала"]))
            id_item.setFlags(id_item.flags() & ~Qt.ItemFlag.ItemIsEditable)
            self.materials_table.setItem(i, 0, id_item)
            name_item = QTableWidgetItem(r["наименование"])
            name_item.setFlags(name_item.flags() & ~Qt.ItemFlag.ItemIsEditable)
            self.materials_table.setItem(i, 1, name_item)
        self.materials_table.hideColumn(0)

    def add_selected(self):
        # Gather selected rows and prompt for qty/price via inline spins (simpler UX)
        selected = self.materials_table.selectionModel().selectedRows()
        rows = [r.row() for r in selected]
        if not rows:
            Toast.error(self, "Ошибка", "Выберите материалы в списке")
            return
        added = 0
        for r in rows:
            mid = int(self.materials_table.item(r, 0).text())
            name = self.materials_table.item(r, 1).text()
            # Ask qty/price via inline simple dialog composed as a small QDialog
            d = QDialog(self)
            d.setWindowTitle(f"Добавить: {name}")
            l = QVBoxLayout(d)
            h = QHBoxLayout()
            h.addWidget(QLabel("Кол-во:"))
            qty = QSpinBox()
            qty.setRange(1, 1000000)
            h.addWidget(qty)
            h.addWidget(QLabel("Цена за ед.:"))
            price = QDoubleSpinBox()
            price.setRange(0.0, 1e9)
            price.setDecimals(2)
            h.addWidget(price)
            l.addLayout(h)
            btns = QHBoxLayout()
            ok = QPushButton("OK")
            ok.clicked.connect(d.accept)
            cancel = QPushButton("Отмена")
            cancel.clicked.connect(d.reject)
            btns.addWidget(ok)
            btns.addWidget(cancel)
            l.addLayout(btns)
            if d.exec():
                # Enforce price > 0 when adding
                if price.value() <= 0:
                    Toast.error(
                        self,
                        "Ошибка",
                        f"У материала '{name}' должна быть указана цена > 0",
                    )
                    continue
                self.chosen.append(
                    {"id": mid, "qty": qty.value(), "price": price.value()}
                )
                added += 1
        if added:
            Toast.success(
                self, "Добавлено", f"Добавлено {added} элементов во временный список"
            )
        else:
            Toast.error(
                self,
                "Не добавлено",
                "Ни один материал не был добавлен (проверьте цены)",
            )

    def get_data(self):
        return self.supplier_input.text().strip(), self.chosen

    def accept(self) -> None:
        # Validate supplier and that at least one item has been added
        supplier = self.supplier_input.text().strip()
        if not supplier:
            Toast.error(
                self, "Ошибка", "Нельзя создать закупку без указания поставщика"
            )
            return
        if not self.chosen:
            Toast.error(self, "Ошибка", "Добавьте хотя бы один материал с ценой > 0")
            return
        super().accept()
