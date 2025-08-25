#!/data/data/com.termux/files/usr/bin/bash

# Terminal cleanup script
echo "🧹 Cleaning terminal..."

# Clear the screen
clear

# Reset terminal colors and formatting
echo -e "\033[0m"

# Reset cursor position
echo -e "\033[H"

# Clear scrollback buffer
echo -e "\033[3J"

# Show clean prompt
echo "✅ Terminal cleaned and reset"
echo "=============================="
echo ""

# Show current directory
echo "Current directory: $(pwd)"
echo ""

# Show clean file listing
echo "Files in current directory:"
ls -la | head -20

echo ""
echo "Terminal is now clean and ready to use!"
