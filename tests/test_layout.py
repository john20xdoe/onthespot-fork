import os
import sys
import unittest

# Run Qt in offscreen/headless mode to prevent connection errors in sandbox
os.environ["QT_QPA_PLATFORM"] = "offscreen"

# Ensure src/ is in the python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))

from PyQt6 import QtWidgets, uic

class TestLayoutStandardization(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QtWidgets.QApplication.instance()
        if not cls.app:
            cls.app = QtWidgets.QApplication([])
        
        cls.ui_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src", "onthespot", "qt", "qtui", "main.ui"))
        cls.window = QtWidgets.QMainWindow()
        uic.loadUi(cls.ui_path, cls.window)

    def test_settings_tab_refactored(self):
        # Verify that settings_sidebar (QListWidget) exists
        sidebar = self.window.findChild(QtWidgets.QListWidget, "settings_sidebar")
        self.assertIsNotNone(sidebar, "settings_sidebar not found in settings layout")
        
        # Verify that settings_stack (QStackedWidget) exists
        stack = self.window.findChild(QtWidgets.QStackedWidget, "settings_stack")
        self.assertIsNotNone(stack, "settings_stack not found in settings layout")
        
        # Verify that the stacked widget contains exactly 5 pages
        self.assertEqual(stack.count(), 5, f"Expected 5 pages in settings_stack, found {stack.count()}")

    def test_settings_form_layouts(self):
        # Verify that form parameters group box inside settings contains a QFormLayout
        gb_gen_params = self.window.findChild(QtWidgets.QGroupBox, "gb_gen_params")
        self.assertIsNotNone(gb_gen_params, "gb_gen_params not found in general page")
        layout = gb_gen_params.layout()
        self.assertIsInstance(layout, QtWidgets.QFormLayout, "General parameters layout is not a QFormLayout")

    def test_dl_progress_table_columns(self):
        # Verify that the download progress table column count is 7
        tbl_dl_progress = self.window.findChild(QtWidgets.QTableWidget, "tbl_dl_progress")
        self.assertIsNotNone(tbl_dl_progress, "tbl_dl_progress not found")
        self.assertEqual(tbl_dl_progress.columnCount(), 7, f"Expected 7 columns, found {tbl_dl_progress.columnCount()}")

    def test_search_results_table_columns(self):
        # Verify that the search results table column count is 5
        tbl_search_results = self.window.findChild(QtWidgets.QTableWidget, "tbl_search_results")
        self.assertIsNotNone(tbl_search_results, "tbl_search_results not found")
        self.assertEqual(tbl_search_results.columnCount(), 5, f"Expected 5 columns, found {tbl_search_results.columnCount()}")

    def test_save_reset_buttons(self):
        # Verify that save/reset buttons exist under new parent container
        btn_save = self.window.findChild(QtWidgets.QPushButton, "btn_save_config")
        btn_reset = self.window.findChild(QtWidgets.QPushButton, "btn_reset_config")
        self.assertIsNotNone(btn_save, "btn_save_config button not found")
        self.assertIsNotNone(btn_reset, "btn_reset_config button not found")

if __name__ == "__main__":
    unittest.main()
