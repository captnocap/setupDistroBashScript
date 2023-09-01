#!/bin/bash

# Function to check internet connectivity
check_internet() {
    if ping -q -c 1 -W 1 8.8.8.8 >/dev/null; then
        return 0 # Internet connection is available
    else
        return 1 # No internet connection
    fi
}

# Function to get available disk space in bytes
get_available_disk_space() {
    df -B1 --output=avail "$1" | tail -n 1
}

# Function to display disk space requirements and check available space
check_disk_space() {
    local space_required=$1
    local space_available=$(get_available_disk_space "/")

    echo "Disk space required: $space_required bytes"
    echo "Available disk space: $space_available bytes"

    if [ "$space_available" -lt "$space_required" ]; then
        echo "Not enough disk space available."
        return 1
    fi

    return 0
}

get_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt-get (Debian/Ubuntu)"
    fi
    if command -v dnf >/dev/null 2>&1; then
        echo "dnf (Fedora)"
    fi
    if command -v yum >/dev/null 2>&1; then
        echo "yum (RHEL/CentOS)"
    fi
    # Add more package managers here
}

# Function to prompt for user choice
select_package_manager() {
    local options=("$@")
    local choice

    echo "Multiple package managers detected:"
    for ((i = 0; i < ${#options[@]}; i++)); do
        echo "$(($i + 1)). ${options[$i]}"
    done

    while true; do
        read -p "Select a package manager (1-${#options[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
            selected_option=${options[$(($choice - 1))]}
            echo "Selected package manager: $selected_option"
            break
        else
            echo "Invalid choice. Please enter a number between 1 and ${#options[@]}."
        fi
    done

    echo "$selected_option"
}

# Variables to track successful and failed installations
successful_installs=0
failed_installs=0
failed_packages=""

# Function to prompt for user input
prompt_user() {
    while true; do
        read -p "$1 [y/n]: " choice
        case "$choice" in
        [Yy]*) return 0 ;;
        [Nn]*) return 1 ;;
        *) echo "Please enter y or n." ;;
        esac
    done
}

# Update and upgrade
if prompt_user "Perform system update and upgrade?"; then
    echo "Performing system update..."
    sudo apt-get update
    echo "System update complete."

    echo "Performing system upgrade..."
    sudo apt-get upgrade -y
    echo "System upgrade complete."
fi

# Determine available package manager(s)
available_package_managers=($(get_package_manager))
num_package_managers=${#available_package_managers[@]}

if [ "$num_package_managers" -eq 0 ]; then
    echo "No supported package manager found."
    exit 1
fi

if [ "$num_package_managers" -eq 1 ]; then
    package_manager="${available_package_managers[0]}"
    echo "Detected package manager: $package_manager"
else
    package_manager=$(select_package_manager "${available_package_managers[@]}")
fi

# List of packages to install
packages_to_install=(
    package1
    package2
    package3
    # Add more packages here
)

# Install regular packages
if prompt_user "Install regular packages using $package_manager?"; then
    echo "Installing regular packages..."
    case "$package_manager" in
    apt-get*) sudo apt-get install -y "${packages_to_install[@]}" ;;
    dnf*) sudo dnf install -y "${packages_to_install[@]}" ;;
    yum*) sudo yum install -y "${packages_to_install[@]}" ;;
        # Add more package managers here
    esac
    echo "Regular packages installation complete."
fi

# Function to import PGP keys from a directory
import_pgp_keys() {
    local key_dir="$1"
    for key_file in "$key_dir"/*.asc; do
        if gpg --import "$key_file"; then
            echo "Imported PGP key from: $key_file"
            ((successful_installs++))
        else
            echo "Failed to import PGP key from: $key_file"
            ((failed_installs++))
            failed_packages="$failed_packages\nPGP Key(s)"
        fi
    done
}

# Function to check if a user has a password
has_password() {
    [[ -n "$(getent shadow $USER | cut -d: -f2)" ]]
}

# Function to check if the user can run sudo without a password
can_sudo_without_password() {
    sudo -n true 2>/dev/null
    [[ $? -eq 0 ]]
}

# Function to remove temporary files and cleanup
cleanup() {
    if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
        echo "Cleaning up temporary files..."
        rm -rf "$temp_dir"
    fi
}

# Check if script was started with sudo
if [ "$(id -u)" -ne 0 ]; then
    echo "Please restart the script using sudo:"
    echo "sudo $0"
    echo "Press any key to close the terminal window..."
    read -n 1 -s
    exit 1
fi

# Check if user has a password
if ! has_password; then
    if can_sudo_without_password; then
        echo "You have sudo access without a password."
    else
        if prompt_user "You don't have a password set. Would you like to set one?"; then
            sudo passwd $USER
        fi
    fi
elif [[ "$(getent shadow $USER | cut -d: -f2)" == "changeme" ]]; then
    if prompt_user "Your password is set to 'changeme'. Would you like to change it?"; then
        sudo passwd $USER
    fi
fi

# Check for internet connection
if ! check_internet; then
    echo "No internet connection detected."
    while true; do
        read -p "Do you want to recheck for an internet connection? [y/n]: " choice
        case "$choice" in
        [Yy]*) if check_internet; then
            echo "Internet connection established."
            break
        else
            echo "No internet connection detected."
        fi ;;
        [Nn]*) break ;;
        *) echo "Please enter y or n." ;;
        esac
    done
fi

# ... (Rest of the script remains the same)

# ... (Previous code remains the same)

# Install regular packages
if prompt_user "Install regular packages using $package_manager?"; then
    if check_internet && check_disk_space "$disk_space_for_packages"; then
        echo "Installing regular packages..."
        if ! install_packages "$package_manager" "${packages_to_install[@]}"; then
            echo "Failed to install packages using $package_manager."

            if [ "$num_package_managers" -gt 1 ]; then
                echo "Trying other available package managers..."
                for alt_manager in "${available_package_managers[@]}"; do
                    if [ "$alt_manager" != "$package_manager" ]; then
                        echo "Trying to install using $alt_manager..."
                        if install_packages "$alt_manager" "${packages_to_install[@]}"; then
                            echo "Packages successfully installed using $alt_manager."
                            break
                        else
                            echo "Failed to install packages using $alt_manager."
                        fi
                    fi
                done
            fi
        else
            echo "Regular packages installation complete."
        fi

        cleanup
    elif ! check_internet; then
        echo "Skipping regular packages installation due to no internet connection."
    else
        echo "Not enough disk space for package installations."
    fi
fi

# ... (Rest of the script remains the same)

# Install NVM and Node.js
if prompt_user "Install NVM and Node.js?"; then
    if check_internet && check_disk_space "$disk_space_for_nodejs"; then
        echo "Installing NVM..."
        if curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash; then
            source "$HOME/.nvm/nvm.sh"
            # ... (Rest of the Node.js installation logic remains the same)
            echo "NVM and Node.js installation complete."
        else
            echo "Failed to install NVM."
            ((failed_installs++))
            failed_packages="$failed_packages\nNVM"
        fi

        cleanup
    elif ! check_internet; then
        echo "Skipping NVM and Node.js installation due to no internet connection."
    else
        echo "Not enough disk space for NVM and Node.js installation."
    fi
fi

# Import PGP Key(s)
if prompt_user "Import PGP key(s)?\n\nIf you have multiple PGP key files, place them in a directory in your home folder named 'pgp_keys' and name them as 'key1.asc', 'key2.asc', etc.\n\nHave you followed these instructions?"; then
    pgp_key_dir="$HOME/pgp_keys"
    if [ -d "$pgp_key_dir" ]; then
        num_keys=1
        read -p "Enter the number of additional keys you have (default is 1): " num_keys_input
        if [[ "$num_keys_input" =~ ^[0-9]+$ ]]; then
            num_keys="$num_keys_input"
        fi

        echo "Importing PGP key(s)..."
        import_pgp_keys "$pgp_key_dir"
        echo "PGP key(s) import complete."
    else
        echo "PGP key directory '$pgp_key_dir' not found."
    fi
fi

# ... (Rest of the script remains the same)

# Display summary and perform cleanup
echo "Script execution completed."
echo "Successful installs: $successful_installs"
echo "Failed installs: $failed_installs"
if [ "$failed_installs" -gt 0 ]; then
    echo "List of failed packages:$failed_packages"
fi

# Provide instructions to close the terminal window
echo "Press any key to close the terminal window..."
read -n 1 -s

# Clean up at the end of the script
cleanup
