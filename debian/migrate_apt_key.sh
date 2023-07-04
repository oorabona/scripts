#!/bin/sh
# Automated script to migrate apt keys from apt-key to apt-keyring (Debian 11+)
# See https://itsfoss.com/key-is-stored-in-legacy-trusted-gpg/

# Run apt-key list only on the trusted.gpg keyring
output=$(apt-key --keyring "/etc/apt/trusted.gpg" list)

# Extract the key IDs using regular expressions
key_ids=$(echo "$output" | grep -E -o '[0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4}  [0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4}' | awk '{print $(NF-1) $NF}')

# Loop through the key IDs
for key_id in $key_ids; do
    # Run apt-key del with the key ID
    echo "apt-key export $key_id | gpg --dearmor -o /etc/apt/trusted.gpg.d/${key_id}.gpg"
done
