# React Widget - Multi-stage build
# Stage 1: Build the widget with Node.js
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files
COPY package.json ./

# Install dependencies
RUN npm install

# Copy source code
COPY . .

# Build the widget
RUN npm run build

# Stage 2: Serve with Nginx
FROM nginx:alpine

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy built widget from builder stage
COPY --from=builder /app/dist/widget.js /usr/share/nginx/html/widget.js

# Create a simple index.html for testing
RUN echo '<!DOCTYPE html>\
<html>\
<head><title>Nepal Location Widget Test</title></head>\
<body>\
<h1>Nepal Location Widget Test Page</h1>\
<div id="nepal-location-widget"></div>\
<script src="/widget.js"></script>\
</body>\
</html>' > /usr/share/nginx/html/index.html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
