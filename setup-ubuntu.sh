#!/usr/bin/env bash
set -e



# Set up Docker APT source:

sudo apt-get update
sudo apt-get install -y \
  apt-transport-https \
  ca-certificates \

sudo apt-key adv \
  --keyserver 'hkp://p80.pool.sks-keyservers.net:80' \
  --recv-keys '58118E89F3A912897C070ADBF76221572C52609D' \

sudo tee /etc/apt/sources.list.d/docker.list \
  <<< "deb https://apt.dockerproject.org/repo ubuntu-$(lsb_release -cs) main"



# Install Docker Engine and the local DNS forwarding server dnsmasq:
sudo apt-get update
sudo apt-get install -y \
  docker-engine \
  linux-image-extra-virtual \
  dnsmasq \

# Fix python-ipaddress in Ubuntu 16.04, see
# https://github.com/docker/compose/issues/3525
sudo apt-get install -y python-ipaddress || true

# Install Docker Compose through Docker:
sudo sh -c 'curl --retry 5 -L https://github.com/docker/compose/releases/download/1.10.0/run.sh > /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose'

# Allow the current user to command the Docker daemon:
sudo adduser "${USER}" docker

# Remove leftover dnsmasq configuration files from old versions of this script:
sudo rm -f '/etc/dnsmasq.d/'{'docker','interfaces'}

# Set up a local DNS forwarding server on the current host.  This server will be
# in charge of DNS resolution for all locally executed applications as well as
# any Docker containers managed by this host, as it will be available on the
# host's loopback interface as well as the host's address on the Docker bridge
# network interface.
#
# The no-resolv option makes the local dnsmasq instance ignore the pre-existing
# DNS servers defined in /etc/resolv.conf at the time the dnsmasq server starts,
# which makes it rely instead on its configuration files to find suitable back
# ends for each query it receives.
#
# The bind-dynamic option makes the local dnsmasq instance bind separate sockets
# for each network interface, which is generally preferred, for security, to a
# single socket listening on the wildcard address that relies on dnsmasq to
# exclude unwanted requests in userspace.  The bind-address option, which is
# mutually exclusive with the bind-dynamic option, also enables this behavior,
# but will additionally adjust its set of listening sockets automatically on
# network interface status changes, so it can start listening automatically on
# network interfaces enabled after the dnsmasq daemon starts.  This is desired
# since Docker creates network interfaces dynamically.
sudo tee '/etc/dnsmasq.d/basic' <<EOF
no-resolv
bind-dynamic
EOF

# Use the Google public DNS servers as the default back ends for DNS queries in
# regions of the DNS namespace with no otherwise specified back end servers:
sudo tee '/etc/dnsmasq.d/google' <<EOF
server=8.8.8.8
server=8.8.4.4
EOF

# Use local Consul service DNS interface for domains under consul.test:
sudo tee '/etc/dnsmasq.d/consul' <<EOF
server=/consul.test/127.0.1.5
EOF

# Disable Network Manager dnsmasq instances:
[[ -f '/etc/NetworkManager/NetworkManager.conf' ]] && \
  sudo sed -i '/etc/NetworkManager/NetworkManager.conf' -e 's/^dns=dnsmasq$/#&/'
sudo rm -f '/etc/dnsmasq.d/network-manager'
sudo pkill -f 'dnsmasq.*NetworkManager'

# Reload local DNS configuration:
sudo service dnsmasq restart

# Configure Docker daemon:
sudo tee '/etc/docker/daemon.json' <<EOF
{
  "bip": "172.17.0.1/24",
  "dns": ["172.17.0.1"]
}
EOF

# Increase system resource limits:
sudo tee '/etc/sysctl.d/50-local-services.conf' << EOF
# Required by Elasticsearch 5:
vm.max_map_count = 262144
EOF

# Reload Docker daemon configuration:
sudo systemctl daemon-reload
sudo service docker restart
