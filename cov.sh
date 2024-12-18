#!/bin/bash

log_file="/var/log/setup_script.log"

initialize() {
    echo "===== Initializing Setup =====" | tee -a $log_file
    echo "Checking server specifications..." | tee -a $log_file

    # Menampilkan spesifikasi server
    cpu_info=$(lscpu | grep 'Model name' | awk -F: '{print $2}' | xargs)
    ram_info=$(free -h | grep Mem | awk '{print $2}')
    storage_info=$(df -h / | grep / | awk '{print $2}')

    echo "Processor: $cpu_info" | tee -a $log_file
    echo "RAM: $ram_info" | tee -a $log_file
    echo "Storage: $storage_info" | tee -a $log_file

    echo "Checking internet connection..." | tee -a $log_file
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        echo "[FAILED] No internet connection. Please check your network." | tee -a $log_file
        exit 1
    fi

    echo "[DONE] Internet connection is active." | tee -a $log_file

    echo "Checking installed applications..." | tee -a $log_file
    apps=("apache2" "php8.1" "composer" "psql")

    for app in "${apps[@]}"; do
        if command -v $app &>/dev/null; then
            echo "[CHECK] $app is already installed." | tee -a $log_file
        else
            echo "[CHECK] $app is not installed." | tee -a $log_file
        fi
    done

    # Prompt untuk melanjutkan instalasi
    read -p "Do you want to proceed with the installation? (y/n): " proceed
    if [[ "$proceed" != "y" && "$proceed" != "Y" ]]; then
        echo "Installation aborted." | tee -a $log_file
        exit 0
    fi

    echo "Initialization complete. Proceeding with installation..." | tee -a $log_file
}

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
        echo -e "\r$message [FAILED]" | tee -a $log_file
        echo "Error: Failed to execute '$command'. Please troubleshoot manually." | tee -a $log_file
        exit 1
    fi

    end_time=$(date +%s)
    elapsed_time=$((end_time - start_time))

    total_percentage=$((total_percentage + step_percentage))

    kill $pid
    wait $pid 2>/dev/null
    echo -e "\r$message [$total_percentage%] [DONE in ${elapsed_time}s, estimated ${estimated_time}s]" | tee -a $log_file
}

# Menjalankan proses initialize
initialize

# Prompt untuk konfigurasi PostgreSQL
read -p "Enter PostgreSQL username (default: postgres): " postgres_user
postgres_user=${postgres_user:-postgres}

read -p "Enter PostgreSQL password: " -s postgres_password
echo

read -p "Enter PostgreSQL database name: " postgres_db
postgres_db=${postgres_db:-my_database}

# Pengecekan aplikasi yang sudah terinstal
check_and_install() {
    package=$1
    message=$2

    if dpkg -l | grep -q "$package"; then
        echo "$package is already installed. Skipping installation." | tee -a $log_file
    else
        run_with_loading "sudo apt install -y $package" "$message" 10 30
    fi
}

# Update dan upgrade sistem
run_with_loading "sudo apt update && sudo apt upgrade -y" "Updating and upgrading system..." 10 120

# Pengecekan dan instalasi Apache2
check_and_install apache2 "Installing Apache2..."

# Pengecekan dan instalasi PHP 8.1
if php -v | grep -q "8.1"; then
    echo "PHP 8.1 is already installed. Skipping installation." | tee -a $log_file
else
    run_with_loading "sudo apt install software-properties-common -y" "Preparing PHP repository..." 10 20
    run_with_loading "sudo add-apt-repository ppa:ondrej/php -y && sudo apt update" "Adding PHP repository..." 10 40
    run_with_loading "sudo apt install php8.1 php8.1-ctype php8.1-curl php8.1-dom php8.1-fileinfo php8.1-mbstring php8.1-pdo php8.1-tokenizer php8.1-xml -y" "Installing PHP 8.1 and extensions..." 20 60
fi

# Pengecekan dan instalasi Composer
if composer --version &> /dev/null; then
    echo "Composer is already installed. Skipping installation." | tee -a $log_file
else
    run_with_loading "sudo apt install curl unzip -y" "Installing prerequisites for Composer..." 5 15
    run_with_loading "curl -sS https://getcomposer.org/installer | php" "Downloading Composer..." 5 10
    run_with_loading "sudo mv composer.phar /usr/local/bin/composer" "Finalizing Composer installation..." 5 5
fi

# Pengecekan dan instalasi PostgreSQL
if psql --version &> /dev/null; then
    echo "PostgreSQL is already installed. Skipping installation." | tee -a $log_file
else
    run_with_loading "sudo apt install postgresql postgresql-contrib -y" "Installing PostgreSQL..." 10 30
    run_with_loading "sudo systemctl start postgresql && sudo systemctl enable postgresql" "Starting and enabling PostgreSQL service..." 5 5
fi

# Konfigurasi PostgreSQL
run_with_loading "sudo -u postgres psql -c \"CREATE USER $postgres_user WITH PASSWORD '$postgres_password';\"" "Creating PostgreSQL user '$postgres_user'..." 5 5
run_with_loading "sudo -u postgres psql -c \"CREATE DATABASE $postgres_db OWNER $postgres_user;\"" "Creating PostgreSQL database '$postgres_db'..." 5 5

# Konfigurasi Apache untuk PHP
run_with_loading "sudo a2enmod php8.1" "Enabling PHP module for Apache..." 5 5
run_with_loading "sudo systemctl restart apache2" "Restarting Apache..." 5 10

# Menampilkan versi yang terinstall
echo -e "Installation complete! Checking installed versions:" | tee -a $log_file

apache2 -v | tee -a $log_file
php -v | tee -a $log_file
composer --version | tee -a $log_file
psql --version | tee -a $log_file

# Prompt untuk instalasi eRapor SMK
read -p "Do you want to install eRapor SMK? (y/n): " install_erapor
if [[ "$install_erapor" == "y" || "$install_erapor" == "Y" ]]; then
    run_with_loading "sudo apt install git -y && sudo git clone https://github.com/eraporsmk/erapor7.git /var/www/eraporsmk" "Cloning eRapor SMK repository..." 10 30
    run_with_loading "sudo chown -R www-data:www-data /var/www/eraporsmk && sudo chmod -R 755 /var/www/eraporsmk" "Setting permissions for eRapor SMK..." 5 5
    if [ -f /var/www/eraporsmk/.env.example ]; then
        run_with_loading "cp /var/www/eraporsmk/.env.example /var/www/eraporsmk/.env" "Copying .env.example to .env..." 5 5
        run_with_loading "sed -i \"s/DB_HOST=.*/DB_HOST=127.0.0.1/;s/DB_PORT=.*/DB_PORT=5432/;s/DB_DATABASE=.*/DB_DATABASE=$postgres_db/;s/DB_USERNAME=.*/DB_USERNAME=$postgres_user/;s/DB_PASSWORD=.*/DB_PASSWORD=$postgres_password/\" /var/www/eraporsmk/.env" "Configuring database credentials in .env..." 5 5
    else
        echo "Error: .env.example file not found in /var/www/eraporsmk." | tee -a $log_file
        exit 1
    fi

    # Konfigurasi VirtualHost untuk eRapor SMK
    read -p "Enter ServerName for VirtualHost (e.g., eraporsmk.local): " server_name
    read -p "Enter ServerAdmin email (e.g., admin@example.com): " server_admin

    run_with_loading "echo '<VirtualHost *:80>
    ServerAdmin $server_admin
    DocumentRoot /var/www/eraporsmk/public
    ServerName $server_name
    <Directory /var/www/eraporsmk/public>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \\\\${APACHE_LOG_DIR}/eraporsmk_error.log
    CustomLog \\\\${APACHE_LOG_DIR}/eraporsmk_access.log combined
</VirtualHost>' | sudo tee /etc/apache2/sites-available/eraporsmk.conf" "Creating VirtualHost configuration..." 5 5
    run_with_loading "sudo a2ensite eraporsmk.conf" "Enabling eRapor SMK VirtualHost..." 5 5
    run_with_loading "sudo systemctl restart apache2" "Restarting Apache with VirtualHost configuration..." 5 10
    echo "VirtualHost for eRapor SMK has been successfully configured!" | tee -a $log_file
else
    echo "Skipping eRapor SMK installation." | tee -a $log_file
fi
