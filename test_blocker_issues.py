"""
Test file with blocker-level issues for SonarQube testing
This file intentionally contains code quality issues that SonarQube will flag as blockers
"""

import os
import sys
import subprocess
import pickle
import base64

# BLOCKER ISSUE 1: Hardcoded credentials (security vulnerability)
PASSWORD = "admin123"
API_KEY = "sk_live_51HqZu2LmSI3mH2KQ9XvN8pL4mR5tY7wE2vF3gH4jK5lM6nO7pQ8rS9tU0vW1xY2zA3bC4dE5fG6hH7iJ8kK9lL0mM1nN2oO3pP4qQ5rR6sS7tT8uU9vV0wW1xX2yY3zZ4aA5bB6cC7dD8eE9fF0gG1hH2iI3jJ4kK5lL6mM7nN8oO9pP0qQ1rR2sS3tT4uU5vV6wW7xX8yY9zZ0aA1bB2cC3dD4eE5fF6gG7hH8iI9jJ0kK1lL2mM3nN4oO5pP6qQ7rR8sS9tT0uU1vV2wW3xX4yY5zZ"

# BLOCKER ISSUE 2: SQL injection vulnerability
def get_user_data(username):
    query = f"SELECT * FROM users WHERE username = '{username}'"  # SQL injection risk
    return query

# BLOCKER ISSUE 3: Command injection vulnerability
def execute_command(user_input):
    os.system(f"rm -rf {user_input}")  # Command injection risk
    subprocess.call(["sh", "-c", user_input])  # Another command injection

# BLOCKER ISSUE 4: Use of eval (code injection)
def process_data(data):
    result = eval(data)  # Dangerous use of eval
    return result

# BLOCKER ISSUE 5: Hardcoded cryptographic key
SECRET_KEY = "my-secret-key-12345"  # Should use environment variable

# BLOCKER ISSUE 6: Insecure random number generation
import random
def generate_token():
    return random.randint(1000, 9999)  # Insecure random

# BLOCKER ISSUE 7: Unpickle from untrusted source (deserialization vulnerability)
def load_data(data):
    return pickle.loads(base64.b64decode(data))  # Dangerous unpickling

# BLOCKER ISSUE 8: Missing input validation
def process_file(filename):
    with open(filename, 'r') as f:  # No validation of filename
        return f.read()

# BLOCKER ISSUE 9: Hardcoded IP address
DATABASE_HOST = "192.168.1.100"  # Should be configurable

# BLOCKER ISSUE 10: Use of deprecated/unsafe function
def hash_password(password):
    import hashlib
    return hashlib.md5(password.encode()).hexdigest()  # MD5 is insecure

# This function will be called and cause issues
if __name__ == "__main__":
    user_input = sys.argv[1] if len(sys.argv) > 1 else "test"
    execute_command(user_input)
    process_data(user_input)
    load_data(base64.b64encode(b"test").decode())

