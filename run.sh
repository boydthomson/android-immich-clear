#!/usr/bin/env bash
#
# delete_synced_old_photos_adb.sh
# 
# Deletes photos from Android device via ADB that are:
#   1. Older than a configurable number of days
#   2. Confirmed synced to Immich server
#
# Requirements: adb, curl, jq
# 
# Usage:
#   ./delete_synced_old_photos_adb.sh [--dry-run] [--days N] [--verbose]
#
# Author: Boyd's Homelab
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
IMMICH_SERVER="${IMMICH_SERVER:-http://your-immich-server:2283}"  # Set via env var or --server flag
API_KEY="${IMMICH_API_KEY:-}"                                     # Set via env var or --api-key flag
DCIM_PATH="/sdcard/DCIM/Camera"              # Standard Android camera path
DAYS_OLD=30                                  # Delete files older than this
DRY_RUN=true                                 # Safety default - set false to delete
VERBOSE=false                                # Extra debug output
LOG_FILE="${HOME}/photo_cleanup_$(date +%Y%m%d_%H%M%S).log"

# File extensions to process (case-insensitive matching done in script)
EXTENSIONS=("jpg" "jpeg" "png" "heic" "heif" "mp4" "mov" "webp" "gif")

# ─────────────────────────────────────────────────────────────────────────────
# COLOR OUTPUT
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ─────────────────────────────────────────────────────────────────────────────
# COUNTERS
# ─────────────────────────────────────────────────────────────────────────────
declare -i FILES_SCANNED=0
declare -i FILES_DELETED=0
declare -i FILES_SKIPPED_AGE=0
declare -i FILES_SKIPPED_NOT_SYNCED=0
declare -i FILES_ERROR=0
declare -i BYTES_FREED=0

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────
log() {
    local level="$1"
    local color="$2"
    shift 2
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Write to log file (no colors)
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"

    # Write to console (with colors) - use stderr to avoid interfering with stdout redirects
    echo -e "${color}[$timestamp] [$level]${NC} $msg" >&2
}

log_info()  { log "INFO " "$GREEN" "$@"; }
log_warn()  { log "WARN " "$YELLOW" "$@"; }
log_error() { log "ERROR" "$RED" "$@"; }
log_debug() { 
    if [[ "$VERBOSE" == "true" ]]; then
        log "DEBUG" "$CYAN" "$@"
    else
        # Still write to log file even if not verbose
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] [DEBUG] $*" >> "$LOG_FILE"
    fi
}

log_action() { log "ACTION" "$BLUE" "$@"; }

# ─────────────────────────────────────────────────────────────────────────────
# ARGUMENT PARSING
# ─────────────────────────────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --execute|--no-dry-run)
                DRY_RUN=false
                shift
                ;;
            --days)
                if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then
                    DAYS_OLD="$2"
                    shift 2
                else
                    log_error "--days requires a numeric argument"
                    exit 1
                fi
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --server)
                if [[ -n "${2:-}" ]]; then
                    IMMICH_SERVER="$2"
                    shift 2
                else
                    log_error "--server requires an argument"
                    exit 1
                fi
                ;;
            --api-key)
                if [[ -n "${2:-}" ]]; then
                    API_KEY="$2"
                    shift 2
                else
                    log_error "--api-key requires an argument"
                    exit 1
                fi
                ;;
            --path)
                if [[ -n "${2:-}" ]]; then
                    DCIM_PATH="$2"
                    shift 2
                else
                    log_error "--path requires an argument"
                    exit 1
                fi
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Delete photos from Android device that are older than N days AND synced to Immich.

OPTIONS:
    --dry-run           Show what would be deleted without deleting (default)
    --execute           Actually delete files (use with caution!)
    --days N            Delete files older than N days (default: 30)
    --server URL        Immich server URL (e.g., http://192.168.180.50:2283)
    --api-key KEY       Immich API key
    --path PATH         Android path to scan (default: /sdcard/DCIM/Camera)
    --verbose, -v       Enable verbose debug output
    --help, -h          Show this help message

EXAMPLES:
    # Dry run with defaults
    $(basename "$0") --dry-run

    # Delete files older than 60 days
    $(basename "$0") --execute --days 60

    # Specify server and API key
    $(basename "$0") --server http://192.168.180.50:2283 --api-key abc123

CONFIGURATION:
    You can also edit the script directly to set defaults for:
    - IMMICH_SERVER
    - API_KEY
    - DCIM_PATH
    - DAYS_OLD

EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# DEPENDENCY CHECKS
# ─────────────────────────────────────────────────────────────────────────────
check_dependencies() {
    log_info "Checking dependencies..."
    local missing=()
    
    for cmd in adb curl jq; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
            log_debug "Missing: $cmd"
        else
            log_debug "Found: $cmd ($(command -v "$cmd"))"
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        log_error "Install with: sudo apt install ${missing[*]}"
        exit 1
    fi
    
    log_debug "All dependencies satisfied"
}

# ─────────────────────────────────────────────────────────────────────────────
# ADB CONNECTION
# ─────────────────────────────────────────────────────────────────────────────
check_adb_connection() {
    log_info "Checking ADB connection..."
    
    # Start ADB server if not running
    adb start-server &>/dev/null || true
    
    # Check for connected devices
    local devices
    devices=$(adb devices | grep -v "List of devices" | grep -v "^$" | wc -l)
    
    if [[ "$devices" -eq 0 ]]; then
        log_error "No Android device connected via ADB"
        log_error "Connect your phone via USB and enable USB debugging"
        log_error "Or connect wirelessly with: adb connect <phone-ip>:5555"
        exit 1
    elif [[ "$devices" -gt 1 ]]; then
        log_warn "Multiple devices connected. Using first device."
        log_warn "Devices:"
        adb devices | grep -v "List of devices" | grep -v "^$" | while read -r line; do
            log_warn "  $line"
        done
    fi
    
    # Get device info
    local device_model
    device_model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    local android_version
    android_version=$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
    
    log_info "Connected to: $device_model (Android $android_version)"
    log_debug "ADB connection verified"
}

check_path_exists() {
    log_info "Checking if path exists on device: $DCIM_PATH"
    
    if ! adb shell "[ -d '$DCIM_PATH' ]" 2>/dev/null; then
        log_error "Path does not exist on device: $DCIM_PATH"
        log_error "Common camera paths:"
        log_error "  /sdcard/DCIM/Camera"
        log_error "  /sdcard/DCIM"
        log_error "  /storage/emulated/0/DCIM/Camera"
        exit 1
    fi
    
    local file_count
    file_count=$(adb shell "ls -1 '$DCIM_PATH' 2>/dev/null | wc -l" | tr -d '\r')
    log_info "Found $file_count files in $DCIM_PATH"
}

# ─────────────────────────────────────────────────────────────────────────────
# IMMICH API
# ─────────────────────────────────────────────────────────────────────────────
check_immich_connection() {
    log_info "Testing Immich API connection..."
    
    if [[ -z "$API_KEY" ]]; then
        log_error "Immich API key not set"
        log_error "Get your API key from: Immich Web UI → Account Settings → API Keys"
        log_error "Then set it with --api-key or edit the script"
        exit 1
    fi
    
    if [[ "$IMMICH_SERVER" == *"XX"* ]]; then
        log_error "Immich server URL not configured"
        log_error "Set it with --server or edit the script"
        exit 1
    fi
    
    log_debug "Testing connection to $IMMICH_SERVER"
    
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 10 \
        -H "x-api-key: $API_KEY" \
        "$IMMICH_SERVER/api/server/ping" 2>/dev/null) || {
        log_error "Failed to connect to Immich server at $IMMICH_SERVER"
        log_error "Check that the server is reachable and the URL is correct"
        exit 1
    }
    
    if [[ "$http_code" != "200" ]]; then
        log_error "Immich API returned HTTP $http_code"
        case "$http_code" in
            401) log_error "Invalid API key" ;;
            403) log_error "API key lacks required permissions" ;;
            404) log_error "API endpoint not found - check server URL" ;;
            5*) log_error "Server error - Immich may be down" ;;
        esac
        exit 1
    fi
    
    # Get server version for logging
    local server_info
    server_info=$(curl -s -H "x-api-key: $API_KEY" "$IMMICH_SERVER/api/server/version" 2>/dev/null)
    local version
    version=$(echo "$server_info" | jq -r '"\(.major).\(.minor).\(.patch)"' 2>/dev/null || echo "unknown")
    
    log_info "Connected to Immich server v$version"
}

# Check if a file is synced to Immich by searching for the original filename
# Returns 0 if synced, 1 if not synced
check_file_synced() {
    local filename="$1"
    
    log_debug "Querying Immich for: $filename"
    
    # Use the search/metadata endpoint to find by original filename
    local response
    response=$(curl -s --connect-timeout 10 \
        -H "x-api-key: $API_KEY" \
        -H "Content-Type: application/json" \
        -X POST \
        -d "{\"originalFileName\": \"$filename\"}" \
        "$IMMICH_SERVER/api/search/metadata" 2>/dev/null)
    
    if [[ -z "$response" ]]; then
        log_debug "  Empty response from Immich API"
        return 1
    fi
    
    # Check if we got any results
    local total
    total=$(echo "$response" | jq -r '.assets.total // 0' 2>/dev/null)
    
    if [[ "$total" -gt 0 ]]; then
        log_debug "  Found $total matching asset(s) in Immich"
        return 0
    else
        log_debug "  No matching asset found in Immich"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# FILE PROCESSING
# ─────────────────────────────────────────────────────────────────────────────
get_file_list() {
    log_info "Building file list from device..."

    # Build find command with extensions
    local find_expr=""
    for ext in "${EXTENSIONS[@]}"; do
        if [[ -n "$find_expr" ]]; then
            find_expr="$find_expr -o"
        fi
        find_expr="$find_expr -iname '*.$ext'"
    done

    # Get file list with modification times using -printf (much faster than -exec stat)
    # Format: epoch_timestamp filename
    # Note: %T@ gives modification time as Unix timestamp with fractional seconds
    log_debug "Executing find command on device..."
    # Stream directly instead of buffering in a variable to avoid issues with large output
    adb shell "find '$DCIM_PATH' -maxdepth 1 -type f \\( $find_expr \\) -printf '%T@ %p\\n'" 2>/dev/null | tr -d '\r'
    log_debug "Find command completed"
}

process_files() {
    log_info "Processing files..."
    log_info "Age threshold: $DAYS_OLD days"
    log_info "Dry run: $DRY_RUN"
    echo ""
    
    local now
    now=$(date +%s)
    local threshold=$((DAYS_OLD * 86400))
    
    # Process each file
    log_debug "Starting file processing loop..."

    # Get file list to a temp file to avoid process substitution issues
    local temp_file=$(mktemp)
    get_file_list > "$temp_file"
    local file_count=$(wc -l < "$temp_file")
    log_debug "Retrieved $file_count files from device"

    # Use file descriptor 3 to prevent commands in the loop from consuming stdin
    while IFS= read -r line <&3; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Parse line: "epoch_timestamp /full/path/to/file.jpg"
        # Note: %T@ from find -printf gives fractional seconds, so we truncate to integer
        local file_epoch file_path filename file_age_days
        file_epoch=$(echo "$line" | awk '{print int($1)}')
        file_path=$(echo "$line" | cut -d' ' -f2-)
        filename=$(basename "$file_path")

        FILES_SCANNED=$((FILES_SCANNED + 1))

        # Debug first file and every 100 files
        if [[ $FILES_SCANNED -eq 1 ]] || [[ $((FILES_SCANNED % 100)) -eq 0 ]]; then
            log_debug "Processed $FILES_SCANNED files so far... (current: $filename)"
        fi

        # Validate epoch
        if ! [[ "$file_epoch" =~ ^[0-9]+$ ]]; then
            log_warn "Could not parse timestamp for: $filename"
            FILES_ERROR=$((FILES_ERROR + 1))
            continue
        fi
        
        # Calculate age
        local age_seconds=$((now - file_epoch))
        file_age_days=$((age_seconds / 86400))
        
        log_debug "Processing: $filename (${file_age_days} days old)"
        
        # Check age threshold
        if [[ $age_seconds -lt $threshold ]]; then
            log_debug "  Skipping: only $file_age_days days old"
            FILES_SKIPPED_AGE=$((FILES_SKIPPED_AGE + 1))
            continue
        fi
        
        # Check if synced to Immich
        if ! check_file_synced "$filename"; then
            log_warn "NOT SYNCED - keeping: $filename ($file_age_days days old)"
            FILES_SKIPPED_NOT_SYNCED=$((FILES_SKIPPED_NOT_SYNCED + 1))
            continue
        fi
        
        # File is old AND synced - delete it
        # Get file size for stats
        local filesize
        filesize=$(adb shell "stat -c '%s' '$file_path'" 2>/dev/null | tr -d '\r')
        filesize=${filesize:-0}
        
        local size_human
        size_human=$(numfmt --to=iec "$filesize" 2>/dev/null || echo "${filesize}B")
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_action "[DRY-RUN] Would delete: $filename ($file_age_days days, $size_human)"
            FILES_DELETED=$((FILES_DELETED + 1))
            BYTES_FREED=$((BYTES_FREED + filesize))
        else
            log_debug "Deleting: $file_path"
            if adb shell "rm '$file_path'" 2>/dev/null; then
                log_action "Deleted: $filename ($file_age_days days, $size_human)"
                FILES_DELETED=$((FILES_DELETED + 1))
                BYTES_FREED=$((BYTES_FREED + filesize))
            else
                log_error "Failed to delete: $filename"
                FILES_ERROR=$((FILES_ERROR + 1))
            fi
        fi

    done 3< "$temp_file"

    # Clean up temp file
    rm -f "$temp_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
print_summary() {
    local freed_human
    freed_human=$(numfmt --to=iec "$BYTES_FREED" 2>/dev/null || echo "${BYTES_FREED}B")
    
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                           SUMMARY                              ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    printf "  %-30s %s\n" "Files scanned:" "$FILES_SCANNED"
    printf "  %-30s %s\n" "Files deleted:" "$FILES_DELETED"
    printf "  %-30s %s\n" "Skipped (too recent):" "$FILES_SKIPPED_AGE"
    printf "  %-30s %s\n" "Skipped (not synced):" "$FILES_SKIPPED_NOT_SYNCED"
    printf "  %-30s %s\n" "Errors:" "$FILES_ERROR"
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        printf "  %-30s %s\n" "Space that would be freed:" "$freed_human"
        echo ""
        echo -e "  ${YELLOW}This was a DRY RUN. No files were deleted.${NC}"
        echo -e "  ${YELLOW}Run with --execute to actually delete files.${NC}"
    else
        printf "  %-30s %s\n" "Space freed:" "$freed_human"
    fi
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    log_info "Log file: $LOG_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────
main() {
    # Initialize log file
    echo "# Photo Cleanup Log - $(date)" > "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    parse_args "$@"
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          Android Photo Cleanup via ADB + Immich               ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log_info "Starting photo cleanup"
    log_info "Configuration:"
    log_info "  Immich Server: $IMMICH_SERVER"
    log_info "  Device Path:   $DCIM_PATH"
    log_info "  Age Threshold: $DAYS_OLD days"
    log_info "  Dry Run:       $DRY_RUN"
    log_info "  Verbose:       $VERBOSE"
    echo ""
    
    check_dependencies
    check_adb_connection
    check_path_exists
    check_immich_connection
    
    echo ""
    process_files
    print_summary
    
    log_info "Cleanup complete"
}

main "$@"
