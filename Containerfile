# Pull RHEL 10 bootc base image
FROM registry.redhat.io/rhel10/rhel-bootc:latest

# Install LAMP components
RUN dnf install -y \
      httpd mariadb mariadb-server \
      php-fpm php-mysqlnd \
      sudo \
    && dnf update -y \
    && dnf clean all

# Enable services for bootc/systemd usage
RUN systemctl enable httpd mariadb php-fpm

# Create user 'redhat'
RUN useradd -m -s /bin/bash redhat

# Set password for 'redhat' from a mounted secret (plaintext version)
# NOTE: The secret file must contain only the password string.
RUN --mount=type=secret,id=redhat-password \
    echo "redhat:$(cat /run/secrets/redhat-password)" | chpasswd

# Add 'redhat' to wheel group for sudo access
RUN usermod -aG wheel redhat

# Create a home page in /usr/share/www/html (non-persisted)
RUN mkdir -p /usr/share/www/html && \
    echo '<h1 style="text-align:center;">Podman ROXXX!</h1> <?php phpinfo(); ?>' \
        > /usr/share/www/html/index.php

# Configure httpd to serve from /usr/share/www/html
RUN sed -i 's|DocumentRoot "/var/www/html"|DocumentRoot "/usr/share/www/html"|' /etc/httpd/conf/httpd.conf && \
    sed -i 's|Directory "/var/www/html"|Directory "/usr/share/www/html"|' /etc/httpd/conf/httpd.conf

# Default command — bootc uses systemd/init
CMD ["/usr/sbin/init"]

