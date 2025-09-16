#!/bin/bash

CONNECT_FILE="/home/seedbot/sb3/dist/update.to"
DIST_DIR="/home/seedbot/sb3/dist"

# --- Renaming Logic ---
if [ -f "$CONNECT_FILE" ]; then
    # Read the desired AppImage name from connect.to
    DESIRED_APPIMAGE=$(head -n 1 "$CONNECT_FILE" | tr -d '\n\r')
    echo "connect.to found. Desired AppImage: $DESIRED_APPIMAGE"

    # Iterate through all .AppImage files in the dist directory
    # and rename those that are NOT the desired one.
    for appimage_file in "$DIST_DIR"/*.AppImage; do
        # Check if the glob found actual files
        if [ -e "$appimage_file" ]; then
            filename=$(basename "$appimage_file")
            if [ "$filename" != "$DESIRED_APPIMAGE" ]; then
                # Rename if it's not the desired AppImage
                mv "$appimage_file" "${appimage_file}.old"
                echo "Renamed '$filename' to '${filename}.old'"
            else
                echo "Keeping '$filename' (matches connect.to)."
            fi
        fi
    done
    rm -f "$CONNECT_FILE"
else
    echo "No connect.to file found. No specific AppImage will be preserved based on connect.to."
    # If no connect.to, you might want to rename all but one, or none.
    # The current logic will just proceed to find *one* .AppImage.
    # If you want to rename all but one in this case, more logic is needed here.
fi

# --- AppImage Execution Logic ---
# Now, find the single .AppImage to execute.
# If connect.to existed and the desired file was there, that's what's left.
# Otherwise, it will pick the first one it finds.
APPIMAGE=$(find "$DIST_DIR" -maxdepth 1 -name "*.AppImage" -type f | head -n 1)

# Check if an AppImage was found
if [ -z "$APPIMAGE" ]; then
    echo "Error: No .AppImage file found in $DIST_DIR to execute after processing."
    exit 1
fi

echo "Executing: $APPIMAGE"
chmod +x "$APPIMAGE"
"$APPIMAGE"
