# Android Immich Photo Cleanup

A bash script that frees up space on your Android device by deleting photos/videos that are **older than N days** AND **confirmed synced** to your [Immich](https://immich.app/) server. Uses ADB to communicate with the device and the Immich API to verify sync status.

## Requirements

- **adb** - Android Debug Bridge (install via `sudo apt install adb` or [Android SDK Platform Tools](https://developer.android.com/tools/releases/platform-tools))
- **curl** - HTTP client
- **jq** - JSON processor (`sudo apt install jq`)
- An **Immich** server with an API key
- An Android device connected via USB (with USB debugging enabled) or wirelessly via ADB

## Setup

1. **Get your Immich API key**: Go to your Immich Web UI → Account Settings → API Keys → Create new key.

2. **Connect your Android device**: Enable USB debugging on your phone and connect via USB, or connect wirelessly:
   ```bash
   adb connect <phone-ip>:5555
   ```

3. **Configure the script** using either environment variables or command-line flags:

   ```bash
   # Option A: Environment variables
   export IMMICH_SERVER="http://192.168.1.100:2283"
   export IMMICH_API_KEY="your-api-key-here"

   # Option B: Command-line flags
   ./run.sh --server http://192.168.1.100:2283 --api-key your-api-key-here
   ```

## Usage

```bash
# Dry run (default) - shows what would be deleted without deleting anything
./run.sh --dry-run

# Delete files older than 30 days (default threshold)
./run.sh --execute

# Delete files older than 60 days
./run.sh --execute --days 60

# Scan a different path on the device
./run.sh --path /sdcard/DCIM --dry-run

# Verbose output for debugging
./run.sh --dry-run --verbose
```

### Options

| Flag | Description |
|------|-------------|
| `--dry-run` | Show what would be deleted without deleting (default) |
| `--execute` | Actually delete files |
| `--days N` | Delete files older than N days (default: 30) |
| `--server URL` | Immich server URL |
| `--api-key KEY` | Immich API key |
| `--path PATH` | Android path to scan (default: `/sdcard/DCIM/Camera`) |
| `--verbose`, `-v` | Enable verbose debug output |
| `--help`, `-h` | Show help message |

## How It Works

1. Connects to your Android device via ADB
2. Scans the camera directory for photo/video files (jpg, jpeg, png, heic, heif, mp4, mov, webp, gif)
3. For each file older than the threshold:
   - Queries the Immich API to check if the file has been synced
   - If synced: deletes it (or logs what it would delete in dry-run mode)
   - If not synced: keeps it and logs a warning
4. Prints a summary with stats on files scanned, deleted, skipped, and space freed

## Supported File Types

jpg, jpeg, png, heic, heif, mp4, mov, webp, gif

## Logs

Each run creates a timestamped log file in your home directory: `~/photo_cleanup_YYYYMMDD_HHMMSS.log`

## Safety

- **Dry run is the default** - you must explicitly pass `--execute` to delete files
- Only files confirmed synced to Immich are deleted
- A summary is printed after each run showing exactly what happened
