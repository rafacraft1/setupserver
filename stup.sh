#!/bin/bash

# Update dan upgrade sistem
echo "Updating and upgrading system..."
sudo apt update && sudo apt upgrade -y

# Install Apache2
echo "Installing Apache2..."
sudo apt install apache2 -y

# Install PHP 8.1 dan ekstensi-ekstensi yang diperlukan
echo "Installing PHP 8.1 and required extensions..."
sudo apt install software-properties-common -y
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update
sudo apt install php8.1 php8.1-ctype php8.1-curl php8.1-dom php8.1-fileinfo php8.1-filter php8.1-hash php8.1-mbstring php8.1-openssl php8.1-pcre php8.1-pdo php8.1-session php8.1-tokenizer php8.1-xml -y

# Install Composer
echo "Installing Composer..."
sudo apt install curl unzip -y
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer

# Install PostgreSQL
echo "Installing PostgreSQL..."
sudo apt install postgresql postgresql-contrib -y

# Konfigurasi Apache untuk PHP
echo "Configuring Apache for PHP..."
sudo a2enmod php8.1
sudo systemctl restart apache2

# Menampilkan versi yang terinstall
echo "Installation complete!"
echo "Checking versions..."
apache2 -v
php -v
composer --version
psql --version
