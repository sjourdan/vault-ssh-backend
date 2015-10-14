# Vault SSH Helper Build

Notes

    apt-get install -y git make
    cd ~; wget https://storage.googleapis.com/golang/go1.5.1.linux-amd64.tar.gz
    cd /usr/local; tar xvfz go1.5.1.linux-amd64.tar.gz
    export GOPATH=~/go
    export GOROOT=/usr/local/go
    export PATH=$PATH:/usr/local/go/bin
    mkdir -p $GOROOT/src/github.com/hashicorp
    cd $GOROOT/src/github.com/hashicorp
    git clone https://github.com/hashicorp/vault-ssh-helper
    cd vault-ssh-helper
    make bootstrap
    go get
    make
    make install
