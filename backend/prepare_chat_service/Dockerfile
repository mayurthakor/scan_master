# backend/prepare_chat_service/Dockerfile

# Use the official Python 3.11 slim base image
FROM python:3.11-slim

# Set the application's working directory
WORKDIR /app

# This is the crucial step: Install the system build tools needed to compile Python packages
RUN apt-get update && apt-get install -y build-essential gcc --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Copy the requirements file and install the Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application's source code
COPY . .

# Start the Functions Framework server for an HTTP-triggered function
CMD ["functions-framework", "--target=prepare_chat_session", "--signature-type=http"]