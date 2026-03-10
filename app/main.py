"""
API for testing Serverless VPC Access connectivity
"""
import os
import requests
from flask import Flask, jsonify

app = Flask(__name__)

DB_HOST = os.environ.get("DB_HOST", "127.0.0.1")
DB_NAME = os.environ.get("DB_NAME", "appdb")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASS = os.environ.get("DB_PASS", "changeme123")


@app.route("/")
def health():
    return jsonify({"service": "my-api", "status": "healthy"})


@app.route("/db")
def check_db():
    """Test connectivity to Cloud SQL through VPC connector"""
    try:
        import psycopg2

        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASS,
            connect_timeout=5,
        )
        cur = conn.cursor()
        cur.execute("SELECT version();")
        version = cur.fetchone()[0]
        cur.close()
        conn.close()

        return jsonify({
            "database": "connected",
            "host": DB_HOST,
            "version": version,
        })
    except Exception as e:
        return jsonify({
            "database": "error",
            "host": DB_HOST,
            "error": str(e),
        }), 500


@app.route("/check-internal/<ip>")
def check_internal(ip):
    """Test connectivity to any internal VPC resource"""
    try:
        resp = requests.get(f"http://{ip}", timeout=5)
        return jsonify({
            "target": ip,
            "reachable": True,
            "status_code": resp.status_code,
            "response": resp.text[:100],
        })
    except requests.exceptions.Timeout:
        return jsonify({
            "target": ip,
            "reachable": False,
            "error": "timeout",
        }), 504
    except requests.exceptions.ConnectionError:
        return jsonify({
            "target": ip,
            "reachable": False,
            "error": "connection refused",
        }), 502


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
