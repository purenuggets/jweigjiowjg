#!/bin/bash

clear
read -p "You're are about to install OpenVPN along with our provided server side firewall based on iptables. Please press enter to continue."

# Install dependencies required for our openvpn server.
sudo apt-get update; sudo apt-get full-upgrade -y; sudo apt-get install curl conntrack -y; modprobe nf_conntrack
clear

# Ask the user for their OpenSSH service port.
read -p "Please enter your server's current OpenSSH listening port: " ssh_port
clear

# Ask the user for their OpenVPN service port.
read -p "Please enter your OpenVPN service port, you must use this port during the setup: " openvpn_port
clear

# Ask the user for their server's primary interface.
read -p "Please specify the primary nic of your instance, aqquire this by typing ('ip a'): " primary_nic
clear

# Help the user understand the importance of their choice of protocal.
echo "You must use the UDP protocol during the setup of OpenVPN, or else our firewall will fail."
sleep 5
clear

# Get our openvpn-install script from angristan, give it ample permissions to run. Then run the installation script.
curl -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh; chmod +x openvpn-install.sh; ./openvpn-install.sh
clear

# Remove all existing firewalls
iptables -t mangle -P PREROUTING ACCEPT; iptables -P INPUT ACCEPT; iptables -P FORWARD ACCEPT; iptables -P OUTPUT ACCEPT
iptables -t mangle -F; iptables -t mangle -X; iptables -F; iptables -X; iptables -t raw -F; iptables -t raw -X; iptables -t nat -X; iptables -t nat -X

# Protect our OpenSSH service port from various forms of SYN floods.
iptables -A PREROUTING -t raw -i $primary_nic -p tcp -m tcp --dport $ssh_port --syn ! --tcp-option 2 -j DROP
iptables -A PREROUTING -t raw -i $primary_nic -p tcp -m tcp --dport $ssh_port --syn ! --tcp-option 1 -j DROP
iptables -A PREROUTING -t raw -i $primary_nic -p tcp -m tcp --dport $ssh_port --syn ! --tcp-option 4 -j DROP
iptables -A PREROUTING -t raw -i $primary_nic -p tcp -m tcp --dport $ssh_port --syn ! --tcp-option 3 -j DROP

# Rate limiting connections in which use a TCP timestamp, most HTTP floods or js based socketing modules will use timestamps.
iptables -A PREROUTING -t raw -i $primary_nic -p tcp -m tcp --dport $ssh_port --syn -m limit --limit 10/sec --limit-burst 5 --tcp-option 8 -j ACCEPT
iptables -A PREROUTING -t raw -i $primary_nic -p tcp -m tcp --dport $ssh_port --syn --tcp-option 8 -j DROP

# Allowing traffic required for our VPN server, then blocking everything else.
iptables -A PREROUTING -t mangle -i $primary_nic -p udp -m udp --dport $openvpn_port -m bpf --bytecode "14,48 0 0 0,84 0 0 240,21 0 10 64,48 0 0 9,21 0 8 17,40 0 0 6,69 6 0 8191,177 0 0 0,80 0 0 8,21 0 3 56,72 0 0 17,21 0 1 0,6 0 0 65535,6 0 0 0" -m conntrack --ctstate NEW -j ACCEPT
iptables -A PREROUTING -t mangle -i $primary_nic -p tcp -m tcp --dport $ssh_port --syn -m hashlimit --hashlimit-name ssh_port --hashlimit-mode srcip --hashlimit-srcmask 32 --hashlimit-upto 3/sec --hashlimit-burst 2 --hashlimit-htable-expire 60000 -m conntrack --ctstate NEW -j ACCEPT
iptables -A PREROUTING -t mangle -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A PREROUTING -t mangle -i tun+ -j ACCEPT
iptables -A PREROUTING -t mangle -i lo -j ACCEPT

# Block all other traffic.
iptables -t mangle -P PREROUTING DROP
clear

# tuning conntrack for performance under heavy loads.
# learn more here, https://wiki.khnet.info/index.php/Conntrack_tuning
# these settings are what allows conntrack to be of use. (the better the resources, the better performance this will grant you).
echo 10000000 > /sys/module/nf_conntrack/parameters/hashsize
clear

# tuning the system's timeout values for conntrack.
sysctl -w net.netfilter.nf_conntrack_max=10000000
sysctl -w net.netfilter.nf_conntrack_generic_timeout=60
sysctl -w net.netfilter.nf_conntrack_icmp_timeout=10
sysctl -w net.netfilter.nf_conntrack_tcp_loose=0
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=900
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_close=10
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_close_wait=10
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_fin_wait=20
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_last_ack=20
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_syn_recv=20
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_syn_sent=20
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_time_wait=10
sysctl -w net.netfilter.nf_conntrack_udp_timeout_stream=60
clear

# save kernel settings.
sysctl -p
clear