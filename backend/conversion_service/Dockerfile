# backend/conversion_service/Dockerfile

# Use the official slim Python image as a more neutral base
FROM python:3.11-slim

# Set the working directory
WORKDIR /srv

# Install LibreOffice and clean up to reduce image size
RUN apt-get update && apt-get install -y libreoffice --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the function's source code
COPY . .

# Set the PORT environment variable that the Functions Framework expects
ENV PORT=8080

# Set the entrypoint to run the Functions Framework for an event-driven function
CMD ["functions-framework", "--target=process_file_to_pdf", "--signature-type=event"]