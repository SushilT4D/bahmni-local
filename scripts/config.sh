brew install podman-compose
brew install mkcert
brew install mysql-client
echo 'export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"' >> ~/.zshrc

podman machine ssh
# The following 2 lines are executed within the shell
#  echo 'net.ipv4.ip_unprivileged_port_start=443' | sudo tee -a /etc/sysctl.conf
#  sudo sysctl -w net.ipv4.ip_unprivileged_port_start=443

# back in the mac
podman machine stop
podman machine set --rootful podman-machine-default
podman machine start

# set it up to restart
mkdir -p ~/Library/LaunchAgents
cat > ~/Library/LaunchAgents/com.podman.machine.plist << EOF
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>Label</key>
      <string>com.podman.machine</string>
      <key>ProgramArguments</key>
      <array>
          <string>/opt/homebrew/bin/podman</string>
          <string>machine</string>
          <string>start</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>KeepAlive</key>
      <false/>
  </dict>
  </plist>
EOF

#  Load it:
launchctl load ~/Library/LaunchAgents/com.podman.machine.plist

# Inside the Podman Configure
sudo mkdir -p ~/.config/systemd/user/
sudo cat > ~/.config/systemd/user/bahmni.service << 'EOF'
  [Unit]
  Description=Bahmni Docker Compose
  Requires=podman.socket

  [Service]
  Type=oneshot
  RemainAfterExit=yes
  WorkingDirectory=/Users/admin/bahmni
  ExecStart=/usr/bin/podman-compose up -d
  ExecStop=/usr/bin/podman-compose down

  [Install]
  WantedBy=default.target
EOF

# Enable the service
sudo systemctl --user enable bahmni.service
sudo systemctl --user start bahmni.service

exit


echo "In the next step, you will need to enter your password 2-3 times"
mkcert -cert-file cert.pem -key-file key.pem localhost 127.0.0.1
mkcert -install

podman build -t bahmni/proxy:nginx-0.1 proxy

