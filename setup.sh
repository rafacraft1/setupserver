#!/bin/bash

loading() {
    spin='|/-\'
    while :
    do
        for i in {0..3}
        do
            echo -ne "\r$1 ${spin:$i:1}"
            sleep 0.2
        done
    done
}

run_with_loading() {
    command=$1
    message=$2
    loading "$message" &
    pid=$!

    eval "$command" &> /dev/null
    if [ $? -ne 0 ]; then
        kill $pid
        wait $pid 2>/dev/null
        echo -e "\r$message [FAILED]"
        echo "Error: Failed to execute '$command'. Please check logs or troubleshoot manually."
        exit 1
    fi

    kill $pid
    wait $pid 2>/dev/null
    echo -e "\r$message [DONE]"
}

cpu_info=$(lscpu | grep 'Model name' | awk -F: '{print $2}' | xargs)
ram_info=$(free -h | grep Mem | awk '{print $2}')
storage_info=$(df -h / | grep / | awk '{print $2}')

clear

echo "===== Server Specifications ====="
echo "Processor: $cpu_info"
echo "RAM: $ram_info"
echo "Storage: $storage_info"

echo "\nChecking internet connection..."
if ! ping -c 1 8.8.8.8 &> /dev/null; then
    echo "[FAILED] No internet connection. Please check your network."
    exit 1
fi

echo "[DONE] Internet connection is active.\n"

read -p "Do you want to proceed with the installation? (y/n): " proceed
if [[ "$proceed" != "y" && "$proceed" != "Y" ]]; then
    echo "Installation aborted."
    exit 0
fi

run_with_loading "sudo apt update && sudo apt upgrade -y" "Updating and upgrading system..."

run_with_loading "sudo apt install apache2 -y" "Installing Apache2..."

run_with_loading "sudo apt install software-properties-common -y" "Preparing PHP repository..."
run_with_loading "sudo add-apt-repository ppa:ondrej/php -y && sudo apt update" "Adding PHP repository..."
run_with_loading "sudo apt install php8.1 php8.1-ctype php8.1-curl php8.1-dom php8.1-fileinfo php8.1-filter php8.1-hash php8.1-mbstring php8.1-openssl php8.1-pcre php8.1-pdo php8.1-session php8.1-tokenizer php8.1-xml -y" "Installing PHP 8.1 and extensions..."

run_with_loading "sudo apt install curl unzip -y" "Installing prerequisites for Composer..."
run_with_loading "curl -sS https://getcomposer.org/installer | php" "Downloading Composer..."
run_with_loading "sudo mv composer.phar /usr/local/bin/composer" "Finalizing Composer installation..."

run_with_loading "sudo apt install postgresql postgresql-contrib -y" "Installing PostgreSQL..."

run_with_loading "sudo a2enmod php8.1" "Enabling PHP module for Apache..."
run_with_loading "sudo systemctl restart apache2" "Restarting Apache..."

echo -e "\nInstallation complete! Checking installed versions:\n"

apache2 -v
php -v
composer --version
psql --version
