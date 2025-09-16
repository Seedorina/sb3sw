#!/bin/bash

# Define the local directory where files will be saved
DOWNLOAD_DIR="/home/seedbot/sb3/dist/"

# Define the path to the environment info file
ENVIRONMENT_INFO_FILE="${DOWNLOAD_DIR}environment.info"

# Define the full path to the local version file
LOCAL_VERSION_FILE="${DOWNLOAD_DIR}sb3vers.txt"

# Define the path for the update marker file
# This will create a file named "update.to" directly inside the DOWNLOAD_DIR
UPDATE_MARKER_FILE="${DOWNLOAD_DIR}update.to"

# Define a generic filename for the downloaded AppImage
# This will be used if the URL doesn't suggest a specific filename
APPIMAGE_GENERIC_FILENAME="downloaded_app.AppImage"

## Directory Check

# Check if the download directory exists
if [ ! -d "$DOWNLOAD_DIR" ]; then
  echo "Error: Directory '$DOWNLOAD_DIR' does not exist. Can't proceed."
  exit 1 # Exit with an error code
fi

## Get Version File URL from environment.info

# Check if the environment info file exists
if [ ! -f "$ENVIRONMENT_INFO_FILE" ]; then
  echo "Error: Environment info file '$ENVIRONMENT_INFO_FILE' not found. Cannot determine VERSION_FILE_URL."
  exit 1
fi

# Read the VERSION_FILE_URL from the first line of environment.info
VERSION_FILE_URL=$(head -n 1 "$ENVIRONMENT_INFO_FILE")

# Basic validation for VERSION_FILE_URL
if [ -z "$VERSION_FILE_URL" ]; then
  echo "Error: VERSION_FILE_URL not found on the first line of '$ENVIRONMENT_INFO_FILE'."
  exit 1
fi

echo "Version file URL taken from '$ENVIRONMENT_INFO_FILE': $VERSION_FILE_URL"

## Download New Version Info

echo "Attempting to download new version information from $VERSION_FILE_URL..."
TEMP_VERSION_FILE=$(mktemp) # Create a temporary file for the version info
wget -q -O "$TEMP_VERSION_FILE" "$VERSION_FILE_URL"

if [ $? -ne 0 ]; then
  echo "Error: Failed to download the new version information file from $VERSION_FILE_URL."
  rm -f "$TEMP_VERSION_FILE" # Clean up temporary file
  exit 1
fi

## Read New Version, URL, and SHA256

# The first line of sb3vers.txt should be the integer version number.
NEW_VERSION=$(head -n 1 "$TEMP_VERSION_FILE")
# The second line of sb3vers.txt should be the download URL.
NEW_APPIMAGE_DOWNLOAD_URL=$(sed -n '2p' "$TEMP_VERSION_FILE")
# --- MODIFICATION START ---
# The third line of sb3vers.txt should be the expected SHA256 checksum.
NEW_SHA256=$(sed -n '3p' "$TEMP_VERSION_FILE")
# --- MODIFICATION END ---

# Basic validation for new version and URL
if ! [[ "$NEW_VERSION" =~ ^[0-9]+$ ]]; then
  echo "Error: Downloaded version content '$NEW_VERSION' from first line is not a valid integer."
  rm -f "$TEMP_VERSION_FILE"
  exit 1
fi

if [ -z "$NEW_APPIMAGE_DOWNLOAD_URL" ]; then
  echo "Error: Download URL not found on the second line of the remote version file."
  rm -f "$TEMP_VERSION_FILE"
  exit 1
fi

# --- MODIFICATION START ---
# Basic validation for the SHA256 checksum
if [ -z "$NEW_SHA256" ]; then
  echo "Error: Expected SHA256 checksum not found on the third line of the remote version file."
  rm -f "$TEMP_VERSION_FILE"
  exit 1
fi
# --- MODIFICATION END ---

echo "Newly downloaded version: $NEW_VERSION"
echo "New AppImage download URL: $NEW_APPIMAGE_DOWNLOAD_URL"
echo "Expected SHA256 Checksum: $NEW_SHA256"

## Read Stored Version

STORED_VERSION=0 # Default to 0 if no local file exists

if [ -f "$LOCAL_VERSION_FILE" ]; then
  STORED_VERSION_RAW=$(head -n 1 "$LOCAL_VERSION_FILE")

  # Check if the stored content is a valid integer
  if [[ "$STORED_VERSION_RAW" =~ ^[0-9]+$ ]]; then
    STORED_VERSION="$STORED_VERSION_RAW"
    echo "Locally stored version: $STORED_VERSION"
  else
    echo "Warning: Stored version '$STORED_VERSION_RAW' from first line is not a valid integer. Treating as no valid version found."
  fi
else
  echo "No local version file found at '$LOCAL_VERSION_FILE'. Assuming this is a new installation."
fi

## Compare and Download

if [ "$NEW_VERSION" -gt "$STORED_VERSION" ]; then
  echo "New version ($NEW_VERSION) is GREATER than stored version ($STORED_VERSION)."
  echo "Initiating download of new AppImage from: $NEW_APPIMAGE_DOWNLOAD_URL"

  # Determine the AppImage filename from the URL, or use a generic one
  APPIMAGE_FILENAME=$(basename "${NEW_APPIMAGE_DOWNLOAD_URL}" | cut -d '?' -f 1)
  if [ -z "$APPIMAGE_FILENAME" ] || [ "$APPIMAGE_FILENAME" == "/" ]; then
      APPIMAGE_FILENAME="$APPIMAGE_GENERIC_FILENAME"
  fi
  NEW_APPIMAGE_PATH="${DOWNLOAD_DIR}${APPIMAGE_FILENAME}"

  # Use curl for reliable download (handles redirects)
  curl -L -o "$NEW_APPIMAGE_PATH" "$NEW_APPIMAGE_DOWNLOAD_URL"

  if [ $? -eq 0 ]; then
    echo "AppImage downloaded successfully to $NEW_APPIMAGE_PATH"

    # --- MODIFICATION START: CHECKSUM VERIFICATION ---
    echo "Verifying file integrity..."
    # Calculate the SHA256 sum of the downloaded file. awk '{print $1}' extracts just the hash.
    LOCAL_SHA256=$(sha256sum "$NEW_APPIMAGE_PATH" | awk '{print $1}')

    if [ "$LOCAL_SHA256" == "$NEW_SHA256" ]; then
        echo "Checksum OK."

        # Make the AppImage executable
        chmod +x "$NEW_APPIMAGE_PATH"
        echo "AppImage made executable."

        # Update the local version file (move the temporary file to its final location)
        mv "$TEMP_VERSION_FILE" "$LOCAL_VERSION_FILE"
        echo "Local version file updated to $NEW_VERSION and new download URL."

        # Create update.to file with the downloaded AppImage filename
        echo "$APPIMAGE_FILENAME" > "$UPDATE_MARKER_FILE"
        echo "Created '$UPDATE_MARKER_FILE' with content: $APPIMAGE_FILENAME"

    else
        echo "Error: CHECKSUM MISMATCH!"
        echo "Expected: $NEW_SHA256"
        echo "Got:      $LOCAL_SHA256"
        echo "Deleting corrupt file: $NEW_APPIMAGE_PATH"
        rm -f "$NEW_APPIMAGE_PATH"   # Delete the bad download
        rm -f "$TEMP_VERSION_FILE"   # Clean up temporary version file
        exit 1
    fi
    # --- MODIFICATION END ---

  else
    echo "Error: Failed to download AppImage from $NEW_APPIMAGE_DOWNLOAD_URL."
    rm -f "$TEMP_VERSION_FILE" # Clean up temporary version file
    exit 1
  fi
elif [ "$NEW_VERSION" -lt "$STORED_VERSION" ]; then
  echo "New version ($NEW_VERSION) is LESS than stored version ($STORED_VERSION)."
  echo "Local version remains at $STORED_VERSION."
  rm -f "$TEMP_VERSION_FILE" # Clean up temporary version file
  # Remove update.to if no update happened
  rm -f "$UPDATE_MARKER_FILE"
else
  echo "New version ($NEW_VERSION) is EQUAL to stored version ($STORED_VERSION)."
  echo "No update needed."
  rm -f "$TEMP_VERSION_FILE" # Clean up temporary version file
fi
