
import os

import psycopg


DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://wallet_user:wallet_dev_password@localhost:5432/wallet_db",
)


def get_connection():
    """Open a connection to the wallet database."""
    return psycopg.connect(DATABASE_URL)