#!/bin/bash
# Description: Automating the openvpn client certificate, keys and .ovpn files
# Created by:  mailgannt
# Date:        10-November-2020

tmpSocket() {
# Create a temporary SSH config file:
cat > "$1" <<ENDCFG
Host *
        ControlMaster auto
        ControlPath $2
        ControlPersist 10m
ENDCFG
}

sshTunnelOp() {
# Open a SSH tunnel:
ssh -F "$1" -f -N -l "$2" "$3"
}

sshTunnelCl() {
# Close the SSH tunnel:
ssh -F "$1" -S "$2" -O exit "$3"
}

tmp_dir=$(mktemp -d)
ssh_cfg=$tmp_dir/ssh-cfg
ssh_socket=$tmp_dir/ssh-socket

cd ~/easy-rsa
#read -p "$(tput setaf 3)Enter the Certificate of Authority User ID: " caUser
read -p "Enter the Certificate of Authority User ID: " caUser
read -p 'Enter the Certificate of Authority Hostname: ' caHostname
read -p "Client Common Name: " newClient

# Read CA pass phrase
echo -n 'Enter the Certificate of Authority passphrase: '
read -s caPass
echo

# s.w.o. index.txt
tmpSocket $ssh_cfg $ssh_socket;
sshTunnelOp $ssh_cfg $caUser $caHostname;
#ssh -F "$ssh_cfg" $caUser@$caHostname "grep -e $newClient /home/$caUser/easy-rsa/pki/index.txt"
#ssh -F "$ssh_cfg" $caUser@$caHostname "grep -e "\<$newClient\>" /home/$caUser/easy-rsa/pki/index.txt"
sftp -F "$ssh_cfg" $caUser@$caHostname:easy-rsa/pki/index.txt /tmp
grep -e "\<$newClient\>" /tmp/index.txt
dupClient=$?
echo $dupClient

# Enter the client name until it is unique
until [ "$dupClient" = "1" ]
do
  echo "The Client Common Name you selected has already been used"
  echo -n "Select a unique client name: "
  read newClient
  sftp -F "$ssh_cfg" $caUser@$caHostname:easy-rsa/pki/index.txt /tmp
  grep -e "\<$newClient\>" /tmp/index.txt
  dupClient=$?
  if [ "$dupClient" != "0" ]; then
    echo "The Client Common Name is unique"
  fi
done
# ---

./easyrsa gen-req ${newClient} nopass;
cp ~/easy-rsa/pki/private/${newClient}.key ~/vpnclient/keys;

host_path=~/easy-rsa/pki/reqs/$newClient.req
target_path=/tmp
tmpSocket $ssh_cfg $ssh_socket;
sshTunnelOp $ssh_cfg $caUser $caHostname;

# Upload the file:
scp -F "$ssh_cfg" "$host_path" $caUser@$caHostname:"$target_path"

# Importing and signing the CSR::
ssh -F "$ssh_cfg" $caUser@$caHostnameS -T <<ENDSSH
cd ~/easy-rsa;
./easyrsa import-req /tmp/"$newClient".req "$newClient";
cat << EOF | ./easyrsa sign-req client "$newClient";
yes
${caPass}
EOF
ENDSSH
# ---

sftp -F "$ssh_cfg" $caUser@$caHostname:easy-rsa/pki/issued/$newClient.crt /tmp

# Creating .ovpn file
pwd
cp /tmp/$newClient.crt ~/vpnclient/keys/
cd ~/vpnclient
./make_config.sh $newClient
if [[ $? -eq 0 ]]; then
	echo "The open vpn client configuration is successfully created."
	echo "Please download the file at /home/$caUser/vpnclient/files."
else
	exit 1
fi
# ---

sshTunnelCl $ssh_cfg $ssh_socket $caHostname;
