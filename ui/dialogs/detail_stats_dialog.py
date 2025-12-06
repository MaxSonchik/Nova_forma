import os

import qtawesome as qta
from PyQt6.QtWidgets import (
    QDialog,
    QFileDialog,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
)
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

from ui.widgets.custom_chart import CustomChart
from ui.widgets.toast import Toast  # <--- Добавлен импорт


class DetailStatsDialog(QDialog):
    def __init__(self, parent, title, metric_type, date_from, date_to, preloaded_data):
        super().__init__(parent)
        self.setWindowTitle(f"Аналитика: {title}")
        self.resize(800, 600)

        self.metric_title = title
        self.d_from = date_from
        self.d_to = date_to
        self.data = preloaded_data

        self.setup_ui()

    def setup_ui(self):
        layout = QVBoxLayout(self)

        # Шапка
        top = QHBoxLayout()
        info = QLabel(
            f"<h2>{self.metric_title}</h2>Период: {self.d_from} — {self.d_to}"
        )

        btn_pdf = QPushButton("Скачать PDF")
        btn_pdf.setIcon(qta.icon("fa5s.file-pdf", color="#E74C3C"))
        btn_pdf.clicked.connect(self.export_pdf)

        top.addWidget(info)
        top.addStretch()
        top.addWidget(btn_pdf)
        layout.addLayout(top)

        # График
        if self.data:
            self.chart = CustomChart(self.data, self.metric_title)
            layout.addWidget(self.chart)
        else:
            layout.addWidget(QLabel("Нет данных"))
            self.chart = None

    def export_pdf(self):
        if not self.chart:
            return
        file_path, _ = QFileDialog.getSaveFileName(
            self, "Сохранить", "Report.pdf", "PDF (*.pdf)"
        )
        if not file_path:
            return

        try:
            # 1. Скриншот
            pixmap = self.chart.grab()
            img_path = "temp_chart.png"
            pixmap.save(img_path)

            # 2. PDF
            c = canvas.Canvas(file_path, pagesize=A4)
            h = A4[1]

            # Шрифт
            font_path = os.path.join("assets", "font.ttf")
            if os.path.exists(font_path):
                pdfmetrics.registerFont(TTFont("RusFont", font_path))
                c.setFont("RusFont", 14)

            # Лого
            logo = os.path.join("assets", "logo.png")
            if os.path.exists(logo):
                c.drawImage(logo, 50, h - 100, 60, 60, mask="auto")

            c.drawString(130, h - 70, f"Отчет: {self.metric_title}")
            c.setFont("RusFont", 10)
            c.drawString(130, h - 90, f"Период: {self.d_from} - {self.d_to}")

            c.drawImage(
                img_path, 50, h - 500, width=500, height=350, preserveAspectRatio=True
            )

            c.save()
            os.remove(img_path)

            # ИСПРАВЛЕНО: Используем Toast вместо QMessageBox
            Toast.success(
                self, "Готово", f"Отчет сохранен:\n{os.path.basename(file_path)}"
            )

        except Exception as e:
            Toast.error(self, "Ошибка", str(e))
