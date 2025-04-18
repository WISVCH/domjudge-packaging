apt-get update
apt-get install software-properties-common gnupg

echo "deb [trusted=yes] https://wisvch.github.io/chipcie-repo/debian ./" >> /etc/apt/sources.list
echo 'Acquire::wisvch.github.io::Verify-Peer "false";
Acquire::https::wisvch.github.io::Verify-Host "false";' >> /etc/apt/apt.conf.d/80trust-baylor-mirror

# Add pypy repo
add-apt-repository ppa:pypy/ppa

apt-get update
