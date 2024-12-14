#!/bin/bash

loading() {
    spin='|/-\'
    percentage=0
    while :
    do
        for i in {0..3}
        do
            echo -ne "\r$1 ${spin:$i:1} [$percentage%]"
            sleep 0.2
        done
        ((percentage+=1))
        if [ $percentage -ge 100 ]; then
            percentage=99
        fi
    done
}

run_with_loading() {
    command=$1
    message=$2
    step_percentage=$3
    estimated_time=$4
    total_percentage=0

    loading "$message" &
    pid=$!

    start_time=$(date +%s)
    eval "$command"
    if [ $? -ne 0 ]; then
        kill $pid
        wait $pid 2>/dev/null
        echo -e "\r$message [FAILED]"
        echo "Error: Failed to execute '$command'. Please troubleshoot manually."
        exit 1
    fi

    end_time=$(date +%s)
    elapsed_time=$((end_time - start_time))

    total_percentage=$((total_percentage + step_percentage))

    kill $pid
    wait $pid 2>/dev/null
    echo -e "\r$message [$total_percentage%] [DONE in ${elapsed_time}s, estimated ${estimated_time}s]"
}

# Menampilkan spesifikasi server
cpu_info=$(lscpu | grep 'Model name' | awk -F: '{print $2}' | xargs)
ram_info=$(free -h | grep Mem | awk '{print $2}')
storage_info=$(df -h / | grep / | awk '{print $2}')

clear

echo "===== Server Specifications ====="
echo "Processor: $cpu_info"
echo "RAM: $ram_info"
echo "Storage: $storage_info"

echo "Checking internet connection..."
if ! ping -c 1 8.8.8.8 &> /dev/null; then
    echo "[FAILED] No internet connection. Please check your network."
    exit 1
fi

echo "[DONE] Internet connection is active."

# Prompt untuk melanjutkan instalasi
read -p "Do you want to proceed with the installation? (y/n): " proceed
if [[ "$proceed" != "y" && "$proceed" != "Y" ]]; then
    echo "Installation aborted."
    exit 0
fi

# Prompt untuk konfigurasi PostgreSQL
read -p "Enter PostgreSQL username (default: postgres): " postgres_user
postgres_user=${postgres_user:-postgres}

read -p "Enter PostgreSQL password: " -s postgres_password
echo

read -p "Enter PostgreSQL database name: " postgres_db
postgres_db=${postgres_db:-my_database}

# Update dan upgrade sistem
run_with_loading "sudo apt update && sudo apt upgrade -y" "Updating and upgrading system..." 10 120

# Install Apache2
run_with_loading "sudo apt install apache2 -y" "Installing Apache2..." 10 30

# Install PHP 8.1 dan ekstensi-ekstensi yang diperlukan
run_with_loading "sudo apt install software-properties-common -y" "Preparing PHP repository..." 10 20
run_with_loading "sudo add-apt-repository ppa:ondrej/php -y && sudo apt update" "Adding PHP repository..." 10 40
run_with_loading "sudo apt install php8.1 php8.1-ctype php8.1-curl php8.1-dom php8.1-fileinfo php8.1-mbstring php8.1-pdo php8.1-tokenizer php8.1-xml -y" "Installing PHP 8.1 and extensions..." 20 60

# Install Composer
run_with_loading "sudo apt install curl unzip -y" "Installing prerequisites for Composer..." 5 15
run_with_loading "curl -sS https://getcomposer.org/installer | php" "Downloading Composer..." 5 10
run_with_loading "sudo mv composer.phar /usr/local/bin/composer" "Finalizing Composer installation..." 5 5

# Install PostgreSQL
run_with_loading "sudo apt install postgresql postgresql-contrib -y" "Installing PostgreSQL..." 10 30

# Konfigurasi PostgreSQL
run_with_loading "sudo systemctl start postgresql && sudo systemctl enable postgresql" "Starting and enabling PostgreSQL service..." 5 5
run_with_loading "sudo -u postgres psql -c \"CREATE USER $postgres_user WITH PASSWORD '$postgres_password';\"" "Creating PostgreSQL user '$postgres_user'..." 5 5
run_with_loading "sudo -u postgres psql -c \"CREATE DATABASE $postgres_db OWNER $postgres_user;\"" "Creating PostgreSQL database '$postgres_db'..." 5 5

# Konfigurasi Apache untuk PHP
run_with_loading "sudo a2enmod php8.1" "Enabling PHP module for Apache..." 5 5
run_with_loading "sudo systemctl restart apache2" "Restarting Apache..." 5 10

# Menampilkan versi yang terinstall
echo -e "Installation complete! Checking installed versions:"

apache2 -v
php -v
composer --version
psql --version

# Menampilkan log instalasi jika diminta
echo -e "\nAll installation logs are displayed above."
read -p "Do you want to view detailed logs in real-time? (y/n): " view_log
if [[ "$view_log" == "y" || "$view_log" == "Y" ]]; then
    echo "No log file saved as output is directly shown."
fi

# Prompt untuk instalasi eRapor SMK
read -p "Do you want to install eRapor SMK? (y/n): " install_erapor
if [[ "$install_erapor" == "y" || "$install_erapor" == "Y" ]]; then
    run_with_loading "sudo apt install git -y && git clone https://github.com/eraporsmk/erapor7.git /var/www/eraporsmk" "Cloning eRapor SMK repository..." 10 30
    run_with_loading "sudo chown -R www-data:www-data /var/www/eraporsmk && sudo chmod -R 755 /var/www/eraporsmk" "Setting permissions for eRapor SMK..." 5 5
    if [ -f /var/www/eraporsmk/.env.example ]; then
        run_with_loading "cp /var/www/eraporsmk/.env.example /var/www/eraporsmk/.env" "Copying .env.example to .env..." 5 5
        run_with_loading "sed -i \"s/DB_HOST=.*/DB_HOST=127.0.0.1/;s/DB_PORT=.*/DB_PORT=5432/;s/DB_DATABASE=.*/DB_DATABASE=$postgres_db/;s/DB_USERNAME=.*/DB_USERNAME=$postgres_user/;s/DB_PASSWORD=.*/DB_PASSWORD=$postgres_password/\" /var/www/eraporsmk/.env" "Configuring database credentials in .env..." 5 5
    else
        echo "Error: .env.example file not found in /var/www/eraporsmk."
        exit 1
    fi
    run_with_loading "sudo systemctl restart apache2" "Restarting Apache after eRapor SMK setup..." 5 10
    echo "eRapor SMK has been successfully installed!"
else
    echo "Skipping eRapor SMK installation."
fi
