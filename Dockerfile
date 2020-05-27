FROM node:12
WORKDIR /home/app/code
COPY package.json .
COPY package-lock.json .
RUN npm install
COPY tsconfig.json .
COPY src src
RUN npm run build

FROM node:12
WORKDIR /home/app/code
MAINTAINER Jean-Christophe Hoelt <hoelt@fovea.cc>
EXPOSE 8000
ENV NODE_ENV=production

# Create 'app' user
RUN useradd app -d /home/app

# Install NPM packages
COPY package.json .
COPY package-lock.json .
RUN npm install --production

# Copy app source files
COPY src src
COPY --from=0 /home/app/code/build build
RUN chown -R app /home/app

USER app
CMD npm start