# Code Review Fix Plan

## Group A — Security

### 1. Path Traversal in `serve_icons` (`src/onthespot/web.py:L12, L118-L121`)
- **Problem:** `@app.route('/icons/<path:filename>')` joins `filename` directly into `send_file(icon_path)` without traversal sanitization, allowing arbitrary file reads via `../` segments.
- **Fix:**
  - Import `send_from_directory` from `flask`.
  - Replace `send_file(icon_path)` with `send_from_directory(os.path.join(config.app_root, 'resources', 'icons'), filename)`.
  - Keep `/icons/<path:filename>` accessible without `@login_required` so icons on `/login` render when `use_webui_login` is enabled.

### 2. Arbitrary Config Overwrite / RCE in `update_settings` (`src/onthespot/otsconfig.py:L276-L291`, `src/onthespot/web.py:L279-L288`)
- **Problem:** `/api/update_settings` iterates over `request.json` without an allowlist, permitting callers to overwrite internal runtime keys such as `_ffmpeg_bin_path` (which is executed via `subprocess.check_call`) or protected keys (`accounts`, `version`, `total_downloaded_items`, `total_downloaded_data`). Also `request.json` can be `None`.
- **Fix:**
  - Add `Config.is_editable_setting(self, key)` in `src/onthespot/otsconfig.py` returning:
    ```python
    isinstance(key, str)
    and not key.startswith('_')
    and key in self._Config__template_data
    and key not in {'accounts', 'version', 'total_downloaded_items', 'total_downloaded_data'}
    ```
  - In `src/onthespot/web.py:update_settings`:
    - Read `data = request.get_json(silent=True) or {}` and return `jsonify(success=False), 400` if `not isinstance(data, dict)`.
    - Only update keys where `config.is_editable_setting(key)` is `True`.
    - Convert `.isdigit()` strings to `int` only when the template default is an `int` (and not `bool`).
    - Call `config.save()` once after the loop.

---

## Group B — Bugs (`🔴 bug`)

### 3. YouTube Music Artist Channel `NameError` & Redundant `continue` (`src/onthespot/parse_item.py:L237-L250`)
- **Problem:** `parsingworker` calls undefined `youtube_get_channel_track_ids` (`NameError`) instead of `youtube_music_get_channel_track_ids`, and has a redundant `continue` at the end of the `for track_id in track_ids:` loop body (L249).
- **Fix:** Call `youtube_music_get_channel_track_ids(token, current_id)` at L238 and remove `continue` at L249.

### 4. Missing Imports in `web.py` for `cancel_items` (`src/onthespot/web.py:L28, L200-L206`)
- **Problem:** `cancel_items()` references `parsing_lock` and `parsing`, neither of which is imported in `src/onthespot/web.py` (`NameError`).
- **Fix:** Add `parsing, parsing_lock` to the `.runtimedata` import at `src/onthespot/web.py:L28`.

### 5. Broken Download Queue Status Filters (`src/onthespot/qt/mainui.py:L150-L243, L766-L769, L1307-L1328`)
- **Problem:** `StatusCellWidget.update_status` uppercases `self.label.setText(status.upper())` (and L767-768 monkey-patches `status_label.setText`), while `update_table_visibility` compares `widget.label.text()` against Title-Case `self.tr("Waiting")`, etc. No filter checkbox ever matches.
- **Fix:**
  - Initialize `self.raw_status = ""` in `StatusCellWidget.__init__` and set `self.raw_status = raw_status` in `StatusCellWidget.update_status`.
  - Remove the `status_label.setText` lambda monkey-patch at `src/onthespot/qt/mainui.py:L767-L768`.
  - In `update_table_visibility`, read `raw_status = getattr(widget, 'raw_status', '')` and match against raw status identifiers (`"Waiting"`, `"Paused"`, `"Failed"`, `"Unavailable"`, `"Cancelled"`, `"Already Exists"`, `"Downloaded"`).

### 6. Context Menu Dead Zones on Cell-Widget Columns (`src/onthespot/qt/mainui.py:L1337-L1343, L1531-L1540`)
- **Problem:** `on_download_table_context_menu` and `on_search_table_context_menu` use `itemAt(pos)`, which returns `None` on columns populated via `setCellWidget` (Title, Type, Status, Actions).
- **Fix:** Use `row = self.tbl_*.rowAt(pos.y())`, verify `row >= 0`, and check that the backing `QTableWidgetItem` (`item(row, 0)` for downloads, `item(row, 1)` for search) is not `None`.

### 7. `RetryWorker` Thread-Unsafe GUI Access & Blocking Sleep (`src/onthespot/downloader.py:L44-L74`, `src/onthespot/qt/mainui.py:L330-L332`)
- **Problem:** `RetryWorker.run` directly mutates `status_label.setText(...)` and legacy `gui["btn"]` widgets from a non-Qt worker thread, busy-spins at 100% CPU if `retry_worker_delay == 0`, and blocks `RetryWorker.stop()` during `time.sleep()`.
- **Fix:**
  - Remove direct `status_label` and `gui["btn"]` access in `RetryWorker.run`; emit `self.progress.emit(download_queue[local_id], "Waiting" if resume_event.is_set() else "Paused", 0)` when `self.gui` is `True` to preserve raw status keys across locales.
  - Connect `retryworker.progress.connect(self.update_item_in_download_list)` in `MainWindow.__init__`.
  - Sleep in 0.5s increments for `max(config.get('retry_worker_delay', 10), 1) * 60` seconds while `self.is_running`.

### 8. `"Paused"` Skip Tuple & `available` Flag Spin-Cycle (`src/onthespot/downloader.py:L90-L100, L138-L148`, `src/onthespot/web.py:L214-L253`, `src/onthespot/cli.py:L517-L521`)
- **Problem:** `"Paused"` is omitted from the skip tuple in `DownloadWorker.run`, and `readd_item_to_download_queue` unconditionally sets `available = True` even for completed/failed/cancelled/paused items, causing workers to spin-cycle over terminal items every 0.2s.
- **Fix:**
  - Add `"Paused"` to the skip status tuple at `src/onthespot/downloader.py:L138-L145`.
  - Set `download_queue[local_id]['available'] = (item.get('item_status') == 'Waiting')` in `readd_item_to_download_queue`.
  - Set `download_queue[...]['available'] = True` in `web.py:retry_items`, `web.py:retry_item`, and `cli.py:display_queue` when transitioning items back to `'Waiting'`.

### 9. Missing `continue` / Failure Cleanup in Deezer & Apple Music (`src/onthespot/downloader.py:L396-L402, L487-L489`)
- **Problem:**
  - Deezer non-200 HTTP branch marks the item `"Failed"` and re-adds it to queue, but misses `continue`, falling through to `os.rename(temp_file_path, file_path)` (`FileNotFoundError`).
  - Apple Music `if not stream_url:` logs an error and `continue`s without marking the item `"Failed"` or calling `readd_item_to_download_queue(item)`, stranding the item in `"Downloading"` indefinitely.
- **Fix:**
  - Add `continue` at L402 in the Deezer non-200 handler.
  - In Apple Music `if not stream_url:`, set `item['item_status'] = 'Failed'`, emit `Failed` progress if `self.gui`, call `self.readd_item_to_download_queue(item)`, then `continue`.

### 10. FFmpeg Metadata Extensions & Cover Comment Flag (`src/onthespot/utils.py:L369, L442, L590-L592`)
- **Problem:**
  - `embed_metadata` checks `if filetype in ['m4a', 'mp4', 'mov']:` without leading dots, whereas `os.path.splitext` returns `'.m4a'`, `'.mp4'`, `'.mov'`.
  - `set_music_thumbnail` passes `'comment=Cover (front), -id3v2_version 1'` as a single string argument to FFmpeg.
- **Fix:**
  - Change `['m4a', 'mp4', 'mov']` to `['.m4a', '.mp4', '.mov']` at L369 and L442.
  - Change `'comment=Cover (front), -id3v2_version 1'` to `'comment=Cover (front)'` at L591.

### 11. Service & CLI Type / Key Bugs (`src/onthespot/api/spotify.py:L129`, `src/onthespot/api/tidal.py:L99`, `src/onthespot/api/crunchyroll.py:L258`, `src/onthespot/cli.py:L351-L386`)
- **Problem:**
  - `spotify_new_session` checks `username in config.get('accounts')` (`str` in `list[dict]`, always `False`) and does not close `zs` on duplicate.
  - `tidal_login_user` writes refreshed expiry to `acc['login']['expires_in']` instead of `acc['login']['token_expiry']`.
  - `crunchyroll_get_episode_metadata` calls `int(...)` on a maturity rating string (`'PG'`, `'TV-14'`), raising `ValueError`.
  - `CLI.do_config` `delete_account` leaves `account_number = parts[1]` as `str` before `isinstance(account_number, int)`, and both `select_account` and `delete_account` use `>` instead of `>=` for index bounds.
- **Fix:**
  - `spotify.py:L129`: Check `any(a.get('login', {}).get('username') == zs._ZeroconfServer__session.username() for a in config.get('accounts'))` and call `zs.close()` before returning `False`.
  - `tidal.py:L99`: Write `acc['login']['token_expiry'] = auth_data["expires_in"] + time.time()`.
  - `crunchyroll.py:L258`: Remove `int()` cast around rating string.
  - `cli.py:L355-L378`: Cast `account_number = int(parts[1])`, validate `0 <= account_number < len(config.get('accounts'))`, and guard `if account_number < len(account_pool): del account_pool[account_number]`.

### 12. Stale Search Results Column Count Test (`tests/test_layout.py:L50-L53`)
- **Problem:** `test_search_results_table_columns` expects `5` columns, but `main.ui` has `4` columns (`Name`, `By`, `Type`, `Action`) after removing the `Service` column.
- **Fix:** Update expected column count in `test_search_results_table_columns` from `5` to `4`.

---

## Group C — Concurrency & Reliability Risks (`🟡 risk`)

### 13. Thread-Safe Spotify & Tidal Account Login UI Updates (`src/onthespot/qt/mainui.py:L289-L296, L1144-L1191`)
- **Problem:** `add_spotify_account_worker` and `add_tidal_account_worker` run in Python `threading.Thread`s and call QWidget methods (`show_popup_dialog`, `btn_login_add.setText`, `setDisabled`) directly from background threads.
- **Fix:** Add `_login_finished = pyqtSignal(bool)` on `MainWindow` connected to `_on_account_login_finished(self, added: bool)` on the GUI thread, and emit `self._login_finished.emit(added)` from both worker methods.

### 14. Lock Discipline on `parsing`, `pending`, and `download_queue` (`src/onthespot/parse_item.py:L165-L170`, `src/onthespot/qt/mainui.py:L261-L279, L1554-L1560`, `src/onthespot/web.py:L48-L80, L190-L276`, `src/onthespot/cli.py:L54-L83`)
- **Problem:**
  - `show_search_item_context_menu` writes `parsing[result['item_id']]` without `parsing_lock`.
  - `parsingworker` and `QueueWorker.run` call `next(iter(...))` outside `parsing_lock` / `pending_lock` before `.pop()`, and `except Exception:` can hit `UnboundLocalError` if `local_id` / `item` were not bound.
  - Flask routes in `web.py` iterate and mutate `download_queue` without holding `download_queue_lock`.
- **Fix:**
  - Wrap `parsing[result['item_id']] = ...` in `with parsing_lock:`.
  - Initialize `local_id = item = None` before `try:`, check `if not parsing: continue` / `if not pending: continue` inside the lock before `next(iter(...))` + `.pop()`, and guard re-insertion in `except Exception:` with `if local_id is not None and item is not None:`.
  - Wrap `download_queue` route operations in `src/onthespot/web.py` (`clear_items`, `cancel_items`, `retry_items`, `restart`, `cancel_item`, `retry_item`, `delete_media`) with `with download_queue_lock:`.

### 15. Account Pool Bounds, Request Cache Key Params, and Semver Comparison (`src/onthespot/accounts.py:L52-L66`, `src/onthespot/utils.py:L31-L34, L80-L90`, `src/onthespot/otsconfig.py:L308-L335`)
- **Problem:**
  - `get_account_token` indexes `account_pool[parsing_index]` without checking if `account_pool` is empty or `parsing_index` is out of bounds.
  - `make_call` hashes only `url` (`md5(f'{url}'.encode())`), ignoring `params` and causing cache collisions across parameterized calls.
  - Version comparisons strip dots (`'v1.1.10' -> 1110 > 'v1.2.0' -> 120`), breaking on multi-digit version segments.
- **Fix:**
  - Guard `if not account_pool: return None` and clamp out-of-range `parsing_index` to `0` in `get_account_token`.
  - Include sorted JSON of `params` in `make_call`'s MD5 cache key when `params` is present.
  - Parse versions via `tuple(int(x) for x in re.findall(r'\d+', str(v)))` in `is_latest_release` and `Config.migration` (updating `< 110` at `otsconfig.py:L334` to `< (1, 1, 0)`).

---

## Group D — Cleanup (`🔵 nit`)

### 16. Worker References, Duplicate Signal Connections, and Build Mux Log Paths (`src/onthespot/qt/mainui.py:L315-L333, L531-L535`, `scripts/build_mux_mac.sh:L146`, `scripts/build_mux_windows.ps1:L124`)
- **Fix:**
  - Store `self.fillaccountpool`, `self.queue_workers`, `self.download_workers`, and `self.retryworker` on `self` in `MainWindow.__init__`.
  - Remove duplicate `download_queue_show_*.stateChanged.connect` block at `src/onthespot/qt/mainui.py:L531-L535`.
  - Update displayed log paths in `scripts/build_mux_mac.sh` (`build/logs/mac/${s}.log`) and `scripts/build_mux_windows.ps1` (`build\logs\windows\$s.log`).
