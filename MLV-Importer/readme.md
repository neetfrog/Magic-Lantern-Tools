# Magic Lantern MLV Importer

A robust, feature-rich automated Windows PowerShell tool designed specifically for **Magic Lantern** filmmakers and photographers. It monitors for inserted camera cards, automatically detects and copies RAW photos and Magic Lantern video files (including multi-part chunked `.MLV` and `.M00`, `.M01`, etc. sequences), verifies data integrity, manages safe cleanups, and can optionally trigger automated post-import workflows like **MLVFS** mounting.

---

## Features

- **Automated Drive Monitoring**: Continuously watches for newly mounted removable drives or camera cards.
- **Intelligent File Classification**: Automatically categorizes files into Photos and Magic Lantern video segments (`.MLV` + `.M00`, `.M01`, etc.).
- **Smart MLV Chunk Grouping**: Keeps split chunk files (`.MLV`, `.M02`, etc.) bound together as single recording entities, ensuring partial deletions or errors don't corrupt multi-file video spans.
- **Data Integrity & Verification**: Supports file stability checks (ensuring files aren't still being written when detected) and post-copy verification via **Size** or **SHA-256** checksums[cite: 3, 4].
- **Safe Copy Engine**: Uses temporary staging extensions (`.importing`) with configurable automatic retries and delay intervals to prevent partial or corrupted file writes[cite: 3, 4].
- **Flexible Organization**: Supports both **Flat** dumping and structured **ByDate** directory organization based on file modification timestamps[cite: 3, 4].
- **Post-Import Automation (MLVFS)**: Automatically triggers external batch scripts (such as an MLVFS controller) to mount successfully imported raw video folders[cite: 3, 4].
- **Safety First**: Includes a **Dry Run** mode, confirmation dialogs for source card deletion, and strict policies preventing source deletion unless full copy verification passes[cite: 3, 4].
- **Robust Logging & Notifications**: Full Windows Desktop balloon notifications and persistent timestamped log files stored locally[cite: 3, 4].

---

## Project Structure

```text
├── MLV-Importer.cmd         # Standard runner (keeps window open with summary)[cite: 1]
├── Run-Once.cmd             # Single-run execution batch file[cite: 2]
├── MLV-Importer.ps1         # Core PowerShell automation script[cite: 3]
└── config.json              # Configuration file (paths, rules, toggles)
