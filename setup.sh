#!/bin/bash

log_file="/var/log/setup_script.log"
apps=("apache2" "php8.1" "composer" "psql")

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a $log_file
}

spinner() {
    spin='|/-\\'
    pid=$1
    message=$2
    while kill -0 $pid 2>/dev/null; do
        for i in {0..3}; do
            echo -ne "\r$message ${spin:$i:1}"
            sleep 0.2
        done
    done
    echo -ne "\r$message [DONE]\n"
}

run_with_spinner() {
    command=$1
    message=$2
    eval "$command" &>/dev/null &
    pid=$!
    spinner $pid "$message"
    wait $pid
    result=$?
    if [ $result -ne 0 ]; then
        log "$message [FAILED]"
        exit 1
    fi
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

validate_input() {
    input=$1
    pattern=$2
    if [[ ! $input =~ $pattern ]]; then
        log "Error: Invalid input."
        exit 1
    fi
}

configure_postgres() {
    read -p "PostgreSQL username (default: postgres): " postgres_user
    postgres_user=${postgres_user:-postgres}
    validate_input "$postgres_user" '^[a-zA-Z0-9_]+$'

    read -sp "PostgreSQL password: " postgres_password
    echo
    validate_input "$postgres_password" '^[a-zA-Z0-9_@#*]+$'

    read -p "PostgreSQL database name (default: my_database): " postgres_db
    postgres_db=${postgres_db:-my_database}
    validate_input "$postgres_db" '^[a-zA-Z0-9_]+$'

    # Check if database already exists
    db_exists=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$postgres_db'")

    if [ "$db_exists" == "1" ]; then
        log "Database $postgres_db already exists."
        read -p "Use existing database? (y/n): " use_existing
        if [ "$use_existing" == "y" ]; then
            log "Using existing database $postgres_db."
        else
            while true; do
                read -p "Enter a new database name: " postgres_db
                validate_input "$postgres_db" '^[a-zA-Z0-9_]+$'
                db_exists=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$postgres_db'")
                if [ "$db_exists" != "1" ]; then
                    break
                else
                    log "Error: Database $postgres_db also exists. Please choose a different name."
                fi
            done
        fi
    fi

    # Create user and database
    run_with_spinner "sudo -u postgres psql -c \"CREATE USER $postgres_user WITH PASSWORD '$postgres_password';\"" "Creating PostgreSQL user"
    run_with_spinner "sudo -u postgres psql -c \"CREATE DATABASE $postgres_db OWNER $postgres_user;\"" "Creating PostgreSQL database"
}

install_erapor() {
    run_with_spinner "sudo apt install git -y && sudo git clone https://github.com/eraporsmk/erapor7.git /var/www/eraporsmk" "Cloning eRapor SMK repository"
    run_with_spinner "sudo chown -R www-data:www-data /var/www/eraporsmk && sudo chmod -R 755 /var/www/eraporsmk" "Setting permissions for eRapor SMK"

    if [ -f /var/www/eraporsmk/.env.example ]; then
        if cp /var/www/eraporsmk/.env.example /var/www/eraporsmk/.env; then
            sed -i "s/DB_HOST=.*/DB_HOST=127.0.0.1/;s/DB_PORT=.*/DB_PORT=5432/;s/DB_DATABASE=.*/DB_DATABASE=$postgres_db/;s/DB_USERNAME=.*/DB_USERNAME=$postgres_user/;s/DB_PASSWORD=.*/DB_PASSWORD=$postgres_password/" /var/www/eraporsmk/.env
        else
            log "Error: Failed to copy .env.example to .env."
            exit 1
        fi
    else
        log "Error: .env.example file not found."
        exit 1
    fi
}

set_default_site() {
    log "Configuring default Apache site to use /var/www/eraporsmk/public"
    
    # File default Apache2 site configuration
    local default_site="/etc/apache2/sites-available/000-default.conf"

    if [ -f "$default_site" ]; then
        # Backup existing configuration
        sudo cp "$default_site" "$default_site.bak"
        log "Backup of the default site configuration saved at $default_site.bak"
        
        # Replace DocumentRoot and add Directory block
        sudo sed -i "s|DocumentRoot .*|DocumentRoot /var/www/eraporsmk/public|g" "$default_site"
        
        # Check if Directory block exists, if not, add it
        if ! grep -q "<Directory /var/www/eraporsmk/public>" "$default_site"; then
            echo -e "\n<Directory /var/www/eraporsmk/public>\n    AllowOverride All\n    Require all granted\n</Directory>" | sudo tee -a "$default_site" >/dev/null
        fi

        log "Default Apache site updated successfully."
    else
        log "Error: Default Apache site configuration not found at $default_site."
        exit 1
    fi

    # Restart Apache to apply changes
    run_with_spinner "sudo systemctl restart apache2" "Restarting Apache"
}

initialize
run_with_spinner "sudo apt update -y" "Updating system"
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

install_erapor
set_default_site

log "Installation complete!"
