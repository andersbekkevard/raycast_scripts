#!/bin/bash

# Simple test script to see what URL would be retrieved from Comet history
# This doesn't open any browser, just prints the result

echo "Testing Comet browser history query for Panopto URLs..."
echo "=============================================="
echo ""

# Path to Comet's history database
HISTORY_DB="$HOME/Library/Application Support/Comet/Default/History"
TEMP_HISTORY="/tmp/comet_history_test_$$.db"

# Check if history database exists
if [ ! -f "$HISTORY_DB" ]; then
    echo "❌ Comet history database not found at:"
    echo "   $HISTORY_DB"
    echo ""
    echo "Make sure Comet browser is installed and has been used."
    exit 1
fi

echo "✓ Found Comet history database"
echo ""

# Copy history DB to avoid lock issues
if ! cp "$HISTORY_DB" "$TEMP_HISTORY" 2>/dev/null; then
    echo "❌ Could not copy history database (may be locked)"
    exit 1
fi

echo "Querying for panopto.eu URLs..."
echo ""

# Get all matching URLs with visit count and last visit
echo "All panopto.eu URLs in history (most recent first):"
echo "---------------------------------------------------"
sqlite3 "$TEMP_HISTORY" \
    "SELECT url, visit_count, datetime(last_visit_time/1000000-11644473600, 'unixepoch', 'localtime') as last_visit
     FROM urls 
     WHERE url LIKE '%panopto.eu%'
     ORDER BY last_visit_time DESC 
     LIMIT 10;" \
    -header \
    -column 2>/dev/null

echo ""
echo "Most recent non-login/logout URL:"
echo "---------------------------------------------------"
MOST_RECENT=$(sqlite3 "$TEMP_HISTORY" \
    "SELECT url FROM urls 
     WHERE url LIKE '%panopto.eu%' 
     AND url NOT LIKE '%/Pages/Auth/Login.aspx%'
     AND url NOT LIKE '%/Pages/Auth/Logout.aspx%'
     ORDER BY last_visit_time DESC 
     LIMIT 1;" 2>/dev/null)

if [ -n "$MOST_RECENT" ]; then
    echo "✓ $MOST_RECENT"
else
    echo "⚠️  No panopto.eu URLs found (would use default: https://ntnu.cloud.panopto.eu/)"
fi

# Clean up
rm -f "$TEMP_HISTORY"

echo ""
echo "Done!"

