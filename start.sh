#!/bin/bash
# Copyright 2015 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and

# Env says we're using SSL
if [ -n "${ENABLE_SSL+1}" ] && [ "${ENABLE_SSL,,}" = "true" ]; then
  echo "Enabling SSL..."
  cp /usr/src/proxy_ssl.conf /etc/nginx/conf.d/proxy.conf
  # If the server name is unset then we don't want a deafult
  if [ "${SERVER_NAME}X" != "X" ] ; then
    cp /usr/src/default_ssl.conf /etc/nginx/conf.d/default.conf
  fi
else
  # No SSL
  cp /usr/src/proxy_nossl.conf /etc/nginx/conf.d/proxy.conf
  # If the server name is set then we don't want a default
  if [ "${SERVER_NAME}X" != "X" ] ; then
    cp /usr/src/default_nossl.conf /etc/nginx/conf.d/default.conf
  fi
fi

# If contents of htpasswd is supplied via env, write it out.
# String should be | (pipe) delimited. e.g. "bob:xxxxxxxxx|mary:yyyyyyyyy|joe:zzzzzzzz"
if [ -n "${HTPASSWD_CONTENTS+1}" ] ; then
  echo "Writing out htpasswd entries..."
  mkdir -p /etc/secrets/
  echo "${HTPASSWD_CONTENTS}" | sed 's/|/\n/g' > /etc/secrets/htpasswd
  chown nginx /etc/secrets/htpasswd
  chmod 600 /etc/secrets/htpasswd
fi

# If an htpasswd file is provided, download and configure nginx
if [ -n "${ENABLE_BASIC_AUTH+1}" ] && [ "${ENABLE_BASIC_AUTH,,}" = "true" ]; then
  echo "Enabling basic auth..."
   sed -i "s/#auth_basic/auth_basic/g;" /etc/nginx/conf.d/proxy.conf
fi

# If the SERVICE_HOST_ENV_NAME and SERVICE_PORT_ENV_NAME vars are provided,
# they point to the env vars set by Kubernetes that contain the actual
# target address and port. Override the default with them.
if [ -n "${SERVICE_HOST_ENV_NAME+1}" ]; then
  TARGET_SERVICE=${!SERVICE_HOST_ENV_NAME}
fi
if [ -n "${SERVICE_PORT_ENV_NAME+1}" ]; then
  TARGET_SERVICE="$TARGET_SERVICE:${!SERVICE_PORT_ENV_NAME}"
fi

# Specify if we're passing in http or https
if [ -n "${PASS_HTTPS+1}" ] ; then
  echo "Proxying passing in HTTPS..."
  sed -i "s/#PASS-HTTPS# //g;" /etc/nginx/conf.d/proxy.conf
else
  echo "Proxying passing in HTTP (default)..."
  sed -i "s/#PASS-HTTP# //g;" /etc/nginx/conf.d/proxy.conf
fi

# If the CERT_SERVICE_HOST_ENV_NAME and CERT_SERVICE_PORT_ENV_NAME vars
# are provided, they point to the env vars set by Kubernetes that contain the
# actual target address and port of the encryption service. Override the
# default with them.
if [ -n "${CERT_SERVICE_HOST_ENV_NAME+1}" ]; then
  CERT_SERVICE=${!CERT_SERVICE_HOST_ENV_NAME}
fi
if [ -n "${CERT_SERVICE_PORT_ENV_NAME+1}" ]; then
  CERT_SERVICE="$CERT_SERVICE:${!CERT_SERVICE_PORT_ENV_NAME}"
fi

if [ -n "${CERT_SERVICE+1}" ]; then
    # Tell nginx the address and port of the certification service.
    sed -i "s/{{CERT_SERVICE}}/${CERT_SERVICE}/g;" /etc/nginx/conf.d/proxy.conf
    sed -i "s/#letsencrypt# //g;" /etc/nginx/conf.d/proxy.conf
fi

if [ -n "${WEB_SOCKETS+1}" ]; then
    sed -i "s/#websockets# //g;" /etc/nginx/conf.d/proxy.conf
fi

if [ -n "${GZIP+1}" ]; then
    sed -i "s/#GZIP# //g;" /etc/nginx/conf.d/proxy.conf
fi

if [ -n "${HTTPS_REDIRECT+1}" ]; then
    sed -i "s/#proto-redir# //g;" /etc/nginx/conf.d/proxy.conf
fi

# Tell nginx the address and port of the service to proxy to
sed -i "s|{{TARGET_SERVICE}}|${TARGET_SERVICE}|" /etc/nginx/conf.d/proxy.conf

# Tell nginx the name of the service
if [ "${SERVER_NAME}X" != "X" ] ; then
	sed -i "s/{{SERVER_NAME}}/${SERVER_NAME}/g;" /etc/nginx/conf.d/proxy.conf
else
	sed -i "s/{{SERVER_NAME}}/_/g;" /etc/nginx/conf.d/proxy.conf
fi

# Allow override of client max body size
if [ "${CLIENT_MAX_BODY}X" != "X" ] ; then
  sed -i "s/#client-max-body# //g;" /etc/nginx/conf.d/proxy.conf
  sed -i "s/{{CLIENT_MAX_BODY}}/${CLIENT_MAX_BODY}/g;" /etc/nginx/conf.d/proxy.conf
fi

# Allow listening on alt port
if [ "${LISTEN_PORT}X" != "X" ] ; then
  sed -i "s/{{LISTEN_PORT}}/${LISTEN_PORT}/g;" /etc/nginx/conf.d/proxy.conf
else
  sed -i "s/{{LISTEN_PORT}}/80/g;" /etc/nginx/conf.d/proxy.conf
fi

echo "Starting nginx..."
nginx -g 'daemon off;'
