"""
Script for checking that a database server is available.
Essentially a cross-platform, database agnostic mysqladmin.
"""
import time

from sqlalchemy import create_engine
from sqlalchemy.engine.url import make_url

from CTFd.config import Config

url = make_url(Config.DATABASE_URL)

# Ignore sqlite databases
if url.drivername.startswith("sqlite"):
    exit(0)

# Null out the database so raw_connection doesnt error if it doesnt exist
# CTFd will create the database if it doesnt exist
url = url._replace(database=None)

connect_args = {
    "ssl": {
        "ssl_ca": "/etc/ssl/certs/ca-certificate.crt",
    }
}

# Wait for the database server to be available
engine = create_engine(url, connect_args=connect_args)
print(f"Waiting for {url.host} to be ready")
while True:
    try:
        x = engine.raw_connection()
        print("Connection:", x)
        break
    except Exception as e:
        print("Exception:", e)
        print("Waiting 1s for database connection")
        time.sleep(1)

print(f"{url.host} is ready")
time.sleep(1)
