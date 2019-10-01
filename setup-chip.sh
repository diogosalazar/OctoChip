#!/bin/bash
clear

echo "Disabling current limit"
sudo i2cset -y -f 0 0x34 0x30 0x63

echo "Fixing broken repositories"
sed -i -e 's/opensource.nextthing.co/chip.jfpossibilities.com/g' -e 's/ftp.us.debian.org/archive.debian.org/g' -e 's/http.debian.net/archive.debian.org/g' -e 's$/debian jessie-backports$/debian/ jessie-backports$g' /etc/apt/sources.list
if [ ! -f "/etc/apt/apt.conf.d/10no--check-valid-until" ]; then
    sudo echo "Acquire::Check-Valid-Until \"0\";" > /etc/apt/apt.conf.d/10no--check-valid-until
fi

echo "Setting up locales"
sudo apt install locales -y && 
# TODO: MANUAL STEP !!! Figure out how to set this programmatically
sudo dpkg-reconfigure locales &&

echo "Updating package listing"
apt-get update

echo "Setting up timezone"
sudo timedatectl set-timezone America/Los_Angeles

echo "Upgrading old packages"
apt-get upgrade -y

echo "Installing OctoPrint"
sudo apt install python-pip python-dev python-setuptools python-virtualenv git libyaml-dev build-essential -y
su -c 'mkdir OctoPrint' chip
cd OctoPrint
su chip <<'EOF'
virtualenv venv
source venv/bin/activate
pip install pip --upgrade
pip install octoprint
EOF
sudo usermod -a -G tty chip
sudo usermod -a -G dialout chip
wget https://github.com/foosel/OctoPrint/raw/master/scripts/octoprint.init && sudo mv octoprint.init /etc/init.d/octoprint
wget https://github.com/foosel/OctoPrint/raw/master/scripts/octoprint.default && sudo mv octoprint.default /etc/default/octoprint
sudo sed -i -r -e 's/pi\b/chip/g' -e '/^#.+home\/chip/s/^#//g' /etc/default/octoprint
sudo chmod +x /etc/init.d/octoprint
sudo update-rc.d octoprint defaults
sudo service octoprint start
sudo cat <<'EOF' | (sudo su -c 'EDITOR="tee" visudo -f /etc/sudoers.d/octoprint-shutdown')
chip ALL=NOPASSWD:/bin/systemctl poweroff
chip ALL=NOPASSWD:/bin/systemctl reboot
EOF

echo "Installing HAProxy"
sudo apt install haproxy -y
sudo tee /etc/haproxy/haproxy.cfg << EOF
global
        maxconn 4096
        user haproxy
        group haproxy
        daemon
        log 127.0.0.1 local0 debug

defaults
        log     global
        mode    http
        option  httplog
        option  dontlognull
        retries 3
        option redispatch
        option http-server-close
        option forwardfor
        maxconn 2000
        timeout connect 5s
        timeout client  15min
        timeout server  15min

frontend public
        bind :::80 v4v6
        use_backend webcam if { path_beg /webcam/ }
        default_backend octoprint

backend octoprint
        reqrep ^([^\ :]*)\ /(.*)     \1\ /\2
        option forwardfor
        server octoprint1 127.0.0.1:5000

backend webcam
        reqrep ^([^\ :]*)\ /webcam/(.*)     \1\ /\2
        server webcam1  127.0.0.1:8080
EOF
sudo service haproxy restart