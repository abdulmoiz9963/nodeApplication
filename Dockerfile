# Use official Node.js LTS image
FROM node:18-alpine

# Set working directory inside container
WORKDIR /usr/src/app

# Copy package files first (for layer caching)
COPY package*.json ./

# Install only production dependencies
RUN npm install --only=production

# Copy application source code
COPY . .

# Expose NON-80 port (required by lab)
EXPOSE 3000

# Start the application
CMD ["node", "index.js"]
