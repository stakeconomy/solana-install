#!/usr/bin/env bash
#
# Script to setup new mainnet-beta instance
#

set -ex
cd ~

SOLANA_VERSION=$1

test -n "$SOLANA_VERSION"

# Setup timezone
sudo ln -sf /usr/share/zoneinfo/Europe/Amsterdam /etc/localtime

# Install minimal tools
sudo apt-get update
sudo apt-get --assume-yes install \
  cron \
  graphviz \
  iotop \
  iputils-ping \
  less \
  lsof \
  psmisc \
  screen \
  silversearcher-ag \
  software-properties-common \
  vim \
  htop \
  zstd

# Create sol user
sudo adduser sol --gecos "" --disabled-password --quiet
sudo adduser sol sudo
sudo adduser sol adm
sudo -- bash -c 'echo "sol ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers'

# Install solana release as the sol user
sudo --login -u sol -- bash -c "
  curl -sSf https://raw.githubusercontent.com/solana-labs/solana/v1.0.0/install/solana-install-init.sh | sh -s $SOLANA_VERSION

sudo --login -u sol -- bash -c "
  echo ~/bin/print-keys.sh >> ~/.profile;
  cp /etc/hostname ~/.hostname;
  mkdir ~/.ssh;
  chmod 0700 ~/.ssh;
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMM6f3drqz3lIjuxyEnz4dhxpiBLcFJFZhjsLcmfD5Ue' >> ~/.ssh/authorized_keys;
"

# Put `syslog` user in the `tty` group
# This prevents log spam due to rsyslogd not having access to /etc/console
# which is configured as the log source for Google's services
sudo usermod -aG tty syslog
sudo systemctl restart rsyslog.service

# Setup log rotation
cat > logrotate.sol <<EOF
/home/sol/solana-validator.log {
  rotate 7
  daily
  missingok
  postrotate
    systemctl kill -s USR1 solana.service
  endscript
}
EOF
sudo cp logrotate.sol /etc/logrotate.d/sol
rm logrotate.sol


cat > stop <<EOF
#!/usr/bin/env bash
# Stop the Validator software
set -ex
sudo systemctl stop solana
EOF
chmod +x stop

cat > restart <<EOF
#!/usr/bin/env bash
# Restart the Validator software
set -ex
sudo systemctl daemon-reload
sudo systemctl restart solana
EOF
chmod +x restart

cat > journalctl <<EOF
#!/usr/bin/env bash
# Follow new journalctl entries for a service to the console
set -ex
sudo journalctl -f "\$@"
EOF
chmod +x journalctl

cat > sol <<EOF
#!/usr/bin/env bash
# Switch to the sol user
set -ex
sudo --login -u sol -- "\$@"
EOF
chmod +x sol

cat > update <<EOF
#!/usr/bin/env bash
# Software update
if [[ -z \$1 ]]; then
  echo "Usage: \$0 [version]"
  exit 1
fi
set -ex
if [[ \$USER != sol ]]; then
  sudo --login -u sol -- solana-install init "\$@"
else
  solana-install init "\$@"
fi
sudo systemctl daemon-reload
sudo systemctl restart solana
sudo systemctl --no-pager status solana
EOF
chmod +x update

cat > catchup <<EOF
#!/usr/bin/env bash
solana catchup ./validator-keypair.json http://127.0.0.1:10899/
EOF
chmod +x catchup

# copy solana services
sudo cp /home/sol/bin/solana-sys-tuner.service /etc/systemd/system/solana-sys-tuner.service
sudo cp /home/sol/bin/validator.service /etc/systemd/system/solana.service
sudo cp /home/sol/bin/watchtower.service /etc/systemd/system/watchtower.service
sudo systemctl daemon-reload

# Start the solana-sys-tuner service
sudo systemctl enable --now solana-sys-tuner
sudo systemctl start solana-sys-tuner
sudo systemctl --no-pager status solana-sys-tuner

# Start the solana service
sudo systemctl enable --now solana
sudo systemctl --no-pager status solana

# Start the solana-Watchtower service
sudo systemctl enable --now watchtower
sudo systemctl start watchtower
sudo systemctl --no-pager status watchtower

sudo --login -u sol -- bash -c "
  set -ex;
  echo '#!/bin/sh' > ~/on-reboot;
  echo '/home/sol/bin/run-monitors.sh &' > ~/on-reboot;
  chmod +x ~/on-reboot;
  echo '@reboot /home/sol/on-reboot' | crontab -;
  crontab -l;
  screen -dmS on-reboot ~/on-reboot
"


# set solana network
solana config set --url https://api.mainnet-beta.solana.com
solana cluster-version

# install cuda and NVidia drivers
#wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/cuda-ubuntu1804.pin
#sudo mv cuda-ubuntu1804.pin /etc/apt/preferences.d/cuda-repository-pin-600
#sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub
#sudo add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/ /"
#sudo apt-get update
#sudo apt-get -y install cuda
#ln -s /usr/local/cuda-11.1 /usr/local/cuda-10.2 

exit 0
