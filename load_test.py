import psycopg2
import time
import threading
import os
import random

# PostgreSQL connection details with default values or environment variables
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_NAME = os.getenv("DB_NAME", "postgres")  # Default database name for PostgreSQL container
DB_USER = os.getenv("DB_USER", "postgres")  # Default user for PostgreSQL
DB_PASSWORD = os.getenv("POSTGRES_PASSWORD", "default_password")  # Default password or loaded from environment
DB_PORT = int(os.getenv("DB_PORT", 30007))  # Default PostgreSQL port (nodeport)

print(f"Attempting to connect to PostgreSQL with the following details:")
print(f"Host: {DB_HOST}, Database: {DB_NAME}, User: {DB_USER}, Port: {DB_PORT}")

# Function to create load on PostgreSQL
def create_load(thread_id, db_host, db_name, db_user, db_password, db_port):
    connection = None  # Initialize connection to None to prevent UnboundLocalError
    try:
        # Connect to PostgreSQL
        connection = psycopg2.connect(
            host=db_host,
            dbname=db_name,
            user=db_user,
            password=db_password,
            port=db_port
        )
        cursor = connection.cursor()

        # Ensure the table exists
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS load_test_table (
                thread_id INT,
                iteration INT,
                value DECIMAL,
                timestamp TIMESTAMP
            );
        """)
        connection.commit()

        for i in range(2000):
            operation = random.choice(["read", "write"])
            if operation == "read":
                # Execute a read query to perform aggregation and calculation
                cursor.execute("""
                    SELECT thread_id, COUNT(*), AVG(value), MAX(value), MIN(value)
                    FROM load_test_table
                    GROUP BY thread_id
                    ORDER BY COUNT(*) DESC
                    LIMIT 1;
                """)
                result = cursor.fetchone()
                print(f"Thread {thread_id}: Read request {i}, result: {result}")
            else:
                # Execute a write query to insert mocked data
                value = random.uniform(1.0, 100.0)  # Generate a random float value
                cursor.execute("INSERT INTO load_test_table (thread_id, iteration, value, timestamp) VALUES (%s, %s, %s, NOW());", (thread_id, i, value))
                connection.commit()
                print(f"Thread {thread_id}: Write request {i}, value: {value}")
            time.sleep(0.5)  # Adding a small delay between queries

    except Exception as e:
        print(f"Thread {thread_id}: Error - {e}")

    finally:
        # Close the database connection
        if connection:
            cursor.close()
            connection.close()
            print(f"Thread {thread_id}: Connection closed")

# Number of threads to create concurrent load
NUM_THREADS = 150

# Create threads to generate load
threads = []
for i in range(NUM_THREADS):
    thread = threading.Thread(target=create_load, args=(i, DB_HOST, DB_NAME, DB_USER, DB_PASSWORD, DB_PORT))
    threads.append(thread)
    thread.start()
    time.sleep(30)

# Wait for all threads to finish
for thread in threads:
    thread.join()

print("Load testing completed.")
