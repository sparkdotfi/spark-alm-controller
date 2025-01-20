mkdir $HOME/.ssh
touch $HOME/.ssh/id_rsa
chmod 600 $HOME/.ssh/id_rsa

git config --global url."git@github.com:".insteadOf "https://github.com/"

echo "$SSH_KEY_SPARK_ADDRESS_REGISTRY_PRIVATE" > $HOME/.ssh/id_rsa
git submodule update --init --recursive lib/spark-address-registry

forge install
