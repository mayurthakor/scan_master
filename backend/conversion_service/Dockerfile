# backend/conversion_service/Dockerfile

# Use a Debian-based image for compatibility with apt-get
FROM python:3.11-slim

# Set the working directory
WORKDIR /app

# Install system-level build tools AND LibreOffice
RUN apt-get update && apt-get install -y build-essential gcc libreoffice --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python packages
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code
COPY . .

# Set the startup command for the event-driven function
CMD ["functions-framework", "--target=process_file_to_pdf", "--signature-type=cloudevent"]