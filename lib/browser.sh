# Shared launcher; source this from repository shell commands.
BROWSER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
browser_control() {
    python3 "$BROWSER_LIB_DIR/browser_control.py" "$@"
}
