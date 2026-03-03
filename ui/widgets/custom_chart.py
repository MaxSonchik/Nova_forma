from PyQt6.QtCore import QPointF, Qt
from PyQt6.QtGui import QColor, QFont, QLinearGradient, QPainter, QPainterPath, QPen
from PyQt6.QtWidgets import QWidget


class CustomChart(QWidget):
    def __init__(self, data_dict, title="Динамика"):
        super().__init__()
        self.data = data_dict                            
        self.title = title
        self.setMinimumSize(600, 400)
        self.setStyleSheet("background-color: white; border-radius: 10px;")

    def paintEvent(self, event):
        if not self.data:
            return

        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

                           
        w = self.width()
        h = self.height()
        padding = 60

                
        dates = list(self.data.keys())
        values = list(self.data.values())
        max_val = max(values) if values else 100
        min_val = 0               

                         
        step_x = (w - 2 * padding) / (len(dates) - 1) if len(dates) > 1 else 0
        scale_y = (h - 2 * padding) / (max_val - min_val) if max_val > 0 else 1

                                
        painter.setPen(QPen(QColor("#E0E0E0"), 1, Qt.PenStyle.DashLine))
                                       
        for i in range(6):
            y = h - padding - (i * (h - 2 * padding) / 5)
            painter.drawLine(padding, int(y), w - padding, int(y))
                           
            val = min_val + (i * (max_val - min_val) / 5)
            painter.drawText(
                5, int(y) + 5, 50, 20, Qt.AlignmentFlag.AlignRight, f"{val:,.0f}"
            )

                                  
        path = QPainterPath()
        points = []

        for i, val in enumerate(values):
            x = padding + i * step_x
            y = h - padding - (val - min_val) * scale_y
            points.append(QPointF(x, y))

            if i == 0:
                path.moveTo(x, y)
            else:
                path.lineTo(x, y)

                      
        pen = QPen(QColor("#3498DB"), 3)
        painter.setPen(pen)
        painter.drawPath(path)

                                                    
        fill_path = QPainterPath(path)
        fill_path.lineTo(points[-1].x(), h - padding)
        fill_path.lineTo(points[0].x(), h - padding)
        fill_path.closeSubpath()

        grad = QLinearGradient(0, 0, 0, h)
        grad.setColorAt(0, QColor(52, 152, 219, 100))                        
        grad.setColorAt(1, QColor(52, 152, 219, 0))
        painter.fillPath(fill_path, grad)

                                 
        for i, pt in enumerate(points):
                   
            painter.setBrush(QColor("white"))
            painter.setPen(QPen(QColor("#3498DB"), 2))
            painter.drawEllipse(pt, 4, 4)

                                                                      
            if len(dates) < 10 or i % (len(dates) // 10 + 1) == 0:
                painter.setPen(QPen(QColor("#7F8C8D"), 1))
                                     
                painter.save()
                painter.translate(pt.x(), h - padding + 20)
                painter.rotate(-45)
                                           
                d_str = dates[i].strftime("%d.%m")
                painter.drawText(0, 0, d_str)
                painter.restore()

                   
        painter.setPen(QColor("#2C3E50"))
        painter.setFont(QFont("Arial", 14, QFont.Weight.Bold))
        painter.drawText(0, 20, w, 30, Qt.AlignmentFlag.AlignCenter, self.title)
