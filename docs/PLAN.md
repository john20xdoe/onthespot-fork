# UI Layout Standardization Plan

This document outlines the proposed changes to standardize the OnTheSpot PyQt6 user interface. The goal is to bring the application layout closer to standard desktop Human Interface Guidelines (HIG), improve accessibility, resolve layout fragility, and ensure styling is robust across all supported platforms (macOS, Windows, Linux).

---

## 1. Goal Description

Standardize the UI components in [main.ui](file:///Volumes/Dev/etal/onthespot-fork/src/onthespot/qt/qtui/main.ui) and their corresponding logic in [mainui.py](file:///Volumes/Dev/etal/onthespot-fork/src/onthespot/qt/mainui.py) and [settings.py](file:///Volumes/Dev/etal/onthespot-fork/src/onthespot/qt/settings.py). 

---

## 2. Proposed Changes & Task Breakdown

### Task 1: Refactor Settings Page Navigation
Currently, the settings page is a single scroll view. Clicking category bookmarks scrolls to hardcoded, arbitrary pixel offsets (`328`, `1176`, `2019`) via scrollbar values in [settings.py](file:///Volumes/Dev/etal/onthespot-fork/src/onthespot/qt/settings.py). This breaks when translations wrap or layouts change.
* **Action Items:**
  - `[ ]` Replace the single scroll settings frame in [main.ui](file:///Volumes/Dev/etal/onthespot-fork/src/onthespot/qt/qtui/main.ui) with a `QStackedWidget` containing separate page layouts for:
    - Accounts
    - General
    - Audio Downloads
    - Audio Metadata
    - Video Downloads
  - `[ ]` Replace the top bookmark buttons with a sidebar navigation layout (e.g., a styled `QListWidget` on the left side of the Settings tab) linked to the stacked widget pages.
  - `[ ]` Update bindings in [settings.py](file:///Volumes/Dev/etal/onthespot-fork/src/onthespot/qt/settings.py) to toggle stacked widget index pages on click instead of setting scrollbar values.

### Task 2: Standardize Form Spacing and Alignment
Settings inputs are currently arranged in mixed inline configurations (e.g., placing Language, Theme, and Download Path on a single line), causing horizontal cramping and scanning difficulties.
* **Action Items:**
  - `[ ]` Replace custom container layouts inside Settings tabs with standard `QFormLayout` layouts.
  - `[ ]` Ensure that input labels are vertically aligned to the left side and their corresponding inputs are aligned to the right.
  - `[ ]` Group Boolean settings (checkboxes) using clean `QGridLayout` layouts within dedicated group boxes.

### Task 3: Migrate to Native QTabWidget Tabs
The main navigation switches views via custom button widgets styled to look like tabs.
* **Action Items:**
  - `[ ]` Replace the custom button tab layout with a native `QTabWidget`.
  - `[ ]` Apply custom QSS selectors to the `QTabBar::tab` components to retain a modern flat appearance without losing native platform benefits (e.g., keyboard traversal using arrow keys, screen readers, focus outlines).

### Task 4: Simplify Table Cells and Action Buttons
`tbl_dl_progress` and `tbl_search_results` embed complex horizontal widgets (with multiple icons, progress bars, and hover indicators) in single cells.
* **Action Items:**
  - `[ ]` Refactor the download progress table to use separate columns for metadata, status, progress (native `QProgressBar`), and actions.
  - `[ ]` Replace cluttered inline action buttons (e.g. Copy, Open, Locate, Delete) with a standard right-click Context Menu (`Qt.ContextMenuPolicy.CustomContextMenu`) or a single clean settings cog/actions dropdown button column.
  - `[ ]` Clean up custom widgets in [dl_progressbtn.py](file:///Volumes/Dev/etal/onthespot-fork/src/onthespot/qt/dl_progressbtn.py) and [thumb_listitem.py](file:///Volumes/Dev/etal/onthespot-fork/src/onthespot/qt/thumb_listitem.py).

### Task 5: Unified Stylesheet Architecture (QSS)
The program injects dynamic background and text color strings directly onto the `centralwidget` container. This destroys native child styling (e.g., combo box arrows and checkboxes disappear or render incorrectly).
* **Action Items:**
  - `[ ]` Define a modular Qt Style Sheet (QSS) file (e.g., `theme.qss` or similar) in `src/onthespot/resources/`.
  - `[ ]` Specify explicit styles for child control states (like hover, pressed, disabled, and focus states on buttons, checkboxes, and line inputs).
  - `[ ]` Update the color picker logic in `open_theme_dialog` to inject variables into the QSS rather than raw overriding strings.

### Task 6: Restructure Save/Reset Buttons
The Settings view features massive bottom action buttons that dominate the interface.
* **Action Items:**
  - `[ ]` Replace the full-width Save and Reset buttons at the bottom of the Settings panel with a right-aligned `QDialogButtonBox` containing standard-sized buttons.
  - `[ ]` Ensure proper spacing, margins, and standard sizing relative to the rest of the application.

---

## 3. Verification & Testing Plan

Since this is a desktop GUI refactoring task, verification requires validation of both visual layout states and functional behavior.

### Automated Checks
* **Widget Structure Validation:**
  - `[ ]` Create / update layout verification unit tests checking that the main window contains `QStackedWidget`, `QTabWidget`, and `QFormLayout` widgets, and verifying that the legacy hardcoded scroll offset bindings are completely removed.
  - `[ ]` Check that no UI layout overlaps or clipping occurs programmatically by asserting children configurations.

### Manual Verification Checklist
* **Navigation & Flow:**
  - `[ ]` Test clicking each sidebar category inside the Settings pane and verify the correct page is displayed.
  - `[ ]` Validate that tab switching can be done using standard keyboard traversal (Tab key and Arrow keys).
* **Visual Scaling & Responsiveness:**
  - `[ ]` Run the app on multiple screen resolutions and sizes; verify that settings elements dynamically adjust without horizontal scrolling.
  - `[ ]` Test with maximum font sizes (or different language locales like German) to verify that labels wrap correctly inside `QFormLayout` without overlapping input boxes.
* **Theming Consistency:**
  - `[ ]` Switch between light, dark, and custom colored themes; verify that all combo box arrows, scrollbars, checked checkmarks, and button states remain visible and stylized.
  - `[ ]` Verify hover and pressed indicator states on all buttons and tables.
* **Context Menus & Actions:**
  - `[ ]` Right-click row entries in the downloads table; verify that options like "Copy Link", "Locate File", "Open", and "Delete" perform their respective functions correctly.
