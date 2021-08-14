brew install mysql@5.7
env LDFLAGS="-I/usr/local/opt/openssl/include -L/usr/local/opt/openssl/lib" pip3.6 install mysqlclient

