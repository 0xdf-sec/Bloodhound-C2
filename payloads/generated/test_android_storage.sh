#!/data/data/com.termux/files/usr/bin/bash

echo "🔍 Testing Direct Android Storage Access"
echo "======================================="

ANDROID_STORAGE="/storage/emulated/0"

echo "Testing path: $ANDROID_STORAGE"
echo ""

# Check if directory exists
if [ -d "$ANDROID_STORAGE" ]; then
    echo "✅ Android storage directory exists"
else
    echo "❌ Android storage directory not found"
    exit 1
fi

# Check if readable
if [ -r "$ANDROID_STORAGE" ]; then
    echo "✅ Android storage is readable"
else
    echo "❌ Android storage is NOT readable"
fi

echo ""

# Test each subdirectory
for subdir in downloads pictures documents music movies dcim; do
    full_path="$ANDROID_STORAGE/$subdir"
    echo "📂 Testing $subdir:"
    
    if [ -d "$full_path" ]; then
        echo "  ✅ Directory exists"
        
        if [ -r "$full_path" ]; then
            echo "  ✅ Directory is readable"
            
            # Count files
            file_count=$(find "$full_path" -type f -readable 2>/dev/null | wc -l)
            echo "  📄 Found $file_count files"
            
            # Show first few files
            if [ "$file_count" -gt 0 ]; then
                echo "  📋 Sample files:"
                find "$full_path" -type f -readable 2>/dev/null | head -3 | while read file; do
                    if [ -n "$file" ]; then
                        size=$(stat -c %s "$file" 2>/dev/null || echo "0")
                        size_kb=$((size / 1024))
                        echo "    📄 $(basename "$file") (${size_kb}KB)"
                    fi
                done
            fi
        else
            echo "  ❌ Directory is NOT readable"
        fi
    else
        echo "  ❌ Directory not found"
    fi
    echo ""
done

echo "💡 If you see files above, the auto-upload should work!"
echo "💡 If not, check Android storage permissions in Settings > Apps > Termux > Permissions"
