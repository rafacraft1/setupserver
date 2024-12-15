#!/bin/bash

log_file="/var/log/setup_script.log"
apps=("apache2" "php8.1" "composer" "psql")

log() {
    echo "$1" | tee -a $log_file
}

spinner() {
    spin='|/-\\'
    for i in {0..3}; do
        echo -ne "\r$1 ${spin:$i:1}"
        sleep 0.2
    done
}

run_with_spinner() {
    command=$1
    message=$2
    spinner "$message" &
    pid=$!
    eval "$command" &>/dev/null
    result=$?
    if [ $result -ne 0 ]; then
        kill $pid; wait $pid 2>/dev/null
        log "$message [FAILED]"
        exit 1
    fi
    kill $pid; wait $pid 2>/dev/null
    log "$message [DONE]"
}

initialize() {
    log "===== Initializing Setup ====="
    log "Processor: $(lscpu | grep 'Model name' | awk -F: '{print $2}' | xargs)"
    log "RAM: $(free -h | grep Mem | awk '{print $2}')"
    log "Storage: $(df -h / | grep / | awk '{print $2}')"

    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        log "[FAILED] No internet connection."
        exit 1
    fi

    for app in "${apps[@]}"; do
        if command -v $app &>/dev/null; then
            log "$app is already installed."
        else
            log "$app is not installed."
        fi
    done

    read -p "Proceed with installation? (y/n): " proceed
    [[ "$proceed" != "y" ]] && exit 0
    log "Initialization complete."
}

check_and_install() {
    package=$1
    message=$2
    if ! dpkg -l | grep -q "$package"; then
        run_with_spinner "sudo apt install -y $package" "$message"
    else
        log "$package is already installed."
    fi
}

configure_postgres() {
    read -p "PostgreSQL username (default: postgres): " postgres_user
    postgres_user=${postgres_user:-postgres}
    read -sp "PostgreSQL password: " postgres_password
    echo
    read -p "PostgreSQL database name (default: my_database): " postgres_db
    postgres_db=${postgres_db:-my_database}

    run_with_spinner "sudo -u postgres psql -c \"CREATE USER $postgres_user WITH PASSWORD '$postgres_password';\"" "Creating PostgreSQL user"
    run_with_spinner "sudo -u postgres psql -c \"CREATE DATABASE $postgres_db OWNER $postgres_user;\"" "Creating PostgreSQL database"
}

install_erapor() {
    run_with_spinner "sudo apt install git -y && sudo git clone https://github.com/eraporsmk/erapor7.git /var/www/eraporsmk" "Cloning eRapor SMK repository"
    run_with_spinner "sudo chown -R www-data:www-data /var/www/eraporsmk && sudo chmod -R 755 /var/www/eraporsmk" "Setting permissions for eRapor SMK"

    if [ -f /var/www/eraporsmk/.env.example ]; then
        cp /var/www/eraporsmk/.env.example /var/www/eraporsmk/.env
        sed -i "s/DB_HOST=.*/DB_HOST=127.0.0.1/;s/DB_PORT=.*/DB_PORT=5432/;s/DB_DATABASE=.*/DB_DATABASE=$postgres_db/;s/DB_USERNAME=.*/DB_USERNAME=$postgres_user/;s/DB_PASSWORD=.*/DB_PASSWORD=$postgres_password/" /var/www/eraporsmk/.env
    else
        log "Error: .env.example file not found."
        exit 1
    fi

    read -p "ServerName for VirtualHost (e.g., eraporsmk.local): " server_name
    read -p "ServerAdmin email: " server_admin

    echo "<VirtualHost *:80>
    ServerAdmin $server_admin
    DocumentRoot /var/www/eraporsmk/public
    ServerName $server_name
    <Directory /var/www/eraporsmk/public>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/eraporsmk_error.log
    CustomLog \${APACHE_LOG_DIR}/eraporsmk_access.log combined
</VirtualHost>" | sudo tee /etc/apache2/sites-available/eraporsmk.conf

    run_with_spinner "sudo a2ensite eraporsmk.conf && sudo systemctl restart apache2" "Configuring eRapor SMK VirtualHost"
}

initialize
run_with_spinner "sudo apt update && sudo apt upgrade -y" "Updating system"
check_and_install apache2 "Installing Apache2"
check_and_install "software-properties-common" "Preparing PHP repository"
run_with_spinner "sudo add-apt-repository ppa:ondrej/php -y && sudo apt update" "Adding PHP repository"
check_and_install "php8.1" "Installing PHP 8.1"
check_and_install "curl unzip" "Installing prerequisites for Composer"
run_with_spinner "curl -sS https://getcomposer.org/installer | php && sudo mv composer.phar /usr/local/bin/composer" "Installing Composer"
check_and_install "postgresql postgresql-contrib" "Installing PostgreSQL"
run_with_spinner "sudo systemctl start postgresql && sudo systemctl enable postgresql" "Starting PostgreSQL service"

configure_postgres
run_with_spinner "sudo a2enmod php8.1 && sudo systemctl restart apache2" "Configuring Apache for PHP"

read -p "Install eRapor SMK? (y/n): " install_erapor
[[ "$install_erapor" == "y" ]] && install_erapor

log "Installation complete!"
