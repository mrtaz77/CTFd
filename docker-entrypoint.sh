#!/bin/bash
set -euo pipefail

# Fix SSH directory permissions (in case mounted from host)
if [ -d /root/.ssh ]; then
    chmod 700 /root/.ssh
    # Fix permissions for all files in .ssh directory
    if [ -f /root/.ssh/id_rsa ]; then
        chmod 600 /root/.ssh/id_rsa
    fi
    if [ -f /root/.ssh/id_rsa.pub ]; then
        chmod 644 /root/.ssh/id_rsa.pub
    fi
    if [ -f /root/.ssh/known_hosts ]; then
        chmod 644 /root/.ssh/known_hosts
    fi
fi

# Generate SSH keys if they don't exist and CHALLENGE_DROPLET_IP is set
if [ -n "${CHALLENGE_DROPLET_IP:-}" ] && [ ! -f /root/.ssh/id_rsa ]; then
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -q
    chmod 600 /root/.ssh/id_rsa
    chmod 644 /root/.ssh/id_rsa.pub
    
    ssh-keyscan -H "$CHALLENGE_DROPLET_IP" >> /root/.ssh/known_hosts 2>/dev/null
    chmod 644 /root/.ssh/known_hosts
    
    if [ -n "${CHALLENGE_DROPLET_PASSWORD:-}" ]; then
        SSHPASS="$CHALLENGE_DROPLET_PASSWORD" sshpass -e ssh-copy-id -i /root/.ssh/id_rsa root@$CHALLENGE_DROPLET_IP 2>/dev/null || true
    fi
fi

# Copy Certificate for MySQL
cp /opt/CTFd/conf/ca-certificate.crt /etc/ssl/certs/

WORKERS=${WORKERS:-1}
WORKER_CLASS=${WORKER_CLASS:-gevent}
ACCESS_LOG=${ACCESS_LOG:--}
ERROR_LOG=${ERROR_LOG:--}
WORKER_TEMP_DIR=${WORKER_TEMP_DIR:-/dev/shm}
SECRET_KEY=${SECRET_KEY:-}
SKIP_DB_PING=${SKIP_DB_PING:-false}

# Check that a .ctfd_secret_key file or SECRET_KEY envvar is set
if [ ! -f .ctfd_secret_key ] && [ -z "$SECRET_KEY" ]; then
    if [ $WORKERS -gt 1 ]; then
        echo "[ ERROR ] You are configured to use more than 1 worker."
        echo "[ ERROR ] To do this, you must define the SECRET_KEY environment variable or create a .ctfd_secret_key file."
        echo "[ ERROR ] Exiting..."
        exit 1
    fi
fi

# Skip db ping if SKIP_DB_PING is set to a value other than false or empty string
if [[ "$SKIP_DB_PING" == "false" ]]; then
  # Ensures that the database is available
  gosu ctfd python ping.py
fi

# Initialize database
gosu ctfd flask db upgrade

# Start CTFd
echo "Starting CTFd"
# Drop privileges to ctfd user before starting the application
exec gosu ctfd gunicorn 'CTFd:create_app()' \
    --bind '0.0.0.0:8000' \
    --workers $WORKERS \
    --worker-tmp-dir "$WORKER_TEMP_DIR" \
    --worker-class "$WORKER_CLASS" \
    --access-logfile "$ACCESS_LOG" \
    --error-logfile "$ERROR_LOG"
