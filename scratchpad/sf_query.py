#!/usr/bin/env python3
"""Snowflake query runner with key-pair auth."""
import sys
import snowflake.connector
from cryptography.hazmat.primitives import serialization

def get_conn():
    key_path = "/Users/riley/Documents/rsa_key.p8"
    with open(key_path, "rb") as f:
        p_key = serialization.load_pem_private_key(f.read(), password=None)
    pkb = p_key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    )
    return snowflake.connector.connect(
        account="A1542297460671-LOB24395",
        user="RILEYSORENSON",
        private_key=pkb,
        role="SYSADMIN",
        warehouse="COMPUTE_WH",
        database="DBT_ANALYTICS",
        schema="DBT_WGTDATA"
    )

def run(sql):
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute(sql)
        cols = [d[0] for d in cur.description]
        rows = cur.fetchall()
        return cols, rows
    finally:
        conn.close()

if __name__ == "__main__":
    sql = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()
    cols, rows = run(sql)
    print(" | ".join(cols))
    print("-" * 80)
    for row in rows[:25]:
        print(" | ".join(str(v) for v in row))
    if len(rows) > 25:
        print(f"... ({len(rows)} total rows)")
