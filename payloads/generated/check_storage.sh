#!/data/data/com.termux/files/usr/bin/bash

# Simple storage check script
echo "🔍 Checking Termux Storage Access"
echo "================================="

STORAGE_DIR="$HOME/storage"

if [ ! -d "$STORAGE_DIR" ]; then
    echo "❌ Storage directory not found!"
    echo "Please run: termux-setup-storage"
    exit 1
fi

echo "✅ Storage directory: $STORAGE_DIR"
echo ""

# List storage contents
echo "📁 Storage directory contents:"
ls -la "$STORAGE_DIR"
echo ""

# Check each subdirectory
for subdir in downloads pictures documents music movies dcim; do
    full_path="$STORAGE_DIR/$subdir"
    if [ -d "$full_path" ]; then
        echo "📂 $subdir:"
        
        # Check if readable
        if [ -r "$full_path" ]; then
            echo "  ✅ Readable"
            
            # Count items
            item_count=$(ls -1 "$full_path" 2>/dev/null | wc -l)
            echo "  📄 Items: $item_count"
            
            # Show first few items
            if [ "$item_count" -gt 0 ]; then
                echo "  📋 Sample items:"
                ls -1 "$full_path" 2>/dev/null | head -5 | while read item; do
                    if [ -n "$item" ]; then
                        item_path="$full_path/$item"
                        if [ -f "$item_path" ]; then
                            size=$(stat -c %s "$item_path" 2>/dev/null || echo "0")
                            size_kb=$((size / 1024))
                            echo "    📄 $item (${size_kb}KB)"
                        elif [ -d "$item_path" ]; then
                            echo "    📁 $item/"
                        else
                            echo "    ❓ $item"
                        fi
                    fi
                done
            fi
        else
            echo "  ❌ NOT readable"
        fi
        echo ""
    fi
done

# Try to find files with find command
echo "🔍 Testing find command:"
echo "Command: find $STORAGE_DIR -type f -readable | head -10"
find "$STORAGE_DIR" -type f -readable 2>/dev/null | head -10
echo ""

echo "💡 If you see no files, check:"
echo "1. termux-setup-storage permissions"
echo "2. Android storage permissions"
echo "3. If folders actually contain files"
