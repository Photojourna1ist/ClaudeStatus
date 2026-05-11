#!/usr/bin/env bash
# Tail the iOS SDK download progress
echo 'Latest progress:'
tail -3 /tmp/ios_download.log 2>/dev/null
echo ''
echo 'Process status:'
pgrep -fl xcodebuild | grep -i download || echo '  (download process not running — either finished or stopped)'
