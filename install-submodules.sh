# Create .ssh folder
mkdir -p $HOME/.ssh
chmod 700 $HOME/.ssh

# Add private key
echo -e "$SSH_KEY_SPARK_ADDRESS_REGISTRY_PRIVATE" > $HOME/.ssh/id_rsa
chmod 600 $HOME/.ssh/id_rsa

# Add GitHub to known hosts
ssh-keyscan github.com >> $HOME/.ssh/known_hosts

# Configure git to use SSH instead of HTTPS
git config --global url."git@github.com:".insteadOf "https://github.com/"

# Update submodules
git submodule update --init --recursive lib/spark-address-registry

forge install
