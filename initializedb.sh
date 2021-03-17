#!/bin/bash

set -ex

docker pull ${DB}
docker run -it --name=mysqld -d -e MYSQL_ALLOW_EMPTY_PASSWORD=yes -p 3306:3306 ${DB}

mysql() {
    docker exec -i mysqld mysql "${@}"
}
while :
do
    sleep 3
    mysql --protocol=tcp -e 'select version()' && break
done
docker logs mysqld

if [ $DB == 'mysql:8.0' ]; then
    WITH_PLUGIN='with mysql_native_password'
    mysql -e 'SET GLOBAL local_infile=on'
    docker cp mysqld:/var/lib/mysql/public_key.pem "${HOME}"
    docker cp mysqld:/var/lib/mysql/ca.pem "${HOME}"
    docker cp mysqld:/var/lib/mysql/server-cert.pem "${HOME}"
    docker cp mysqld:/var/lib/mysql/client-key.pem "${HOME}"
    docker cp mysqld:/var/lib/mysql/client-cert.pem "${HOME}"

    # Test user for auth test
    mysql -e '
        CREATE USER
            user_sha256   IDENTIFIED WITH "sha256_password" BY "pass_sha256_01234567890123456789",
            nopass_sha256 IDENTIFIED WITH "sha256_password",
            user_caching_sha2   IDENTIFIED WITH "caching_sha2_password" BY "pass_caching_sha2_01234567890123456789",
            nopass_caching_sha2 IDENTIFIED WITH "caching_sha2_password"
            PASSWORD EXPIRE NEVER;'
    mysql -e 'GRANT RELOAD ON *.* TO user_caching_sha2;'
elif [[ $DB == mariadb:10.* ]] && [ ${DB#mariadb:10.} -ge 3 ]; then
    mysql -e '
        INSTALL SONAME "auth_ed25519";
        CREATE FUNCTION ed25519_password RETURNS STRING SONAME "auth_ed25519.so";'
    # we need to pass the hashed password manually until 10.4, so hide it here
    mysql -sNe "SELECT CONCAT('CREATE USER nopass_ed25519 IDENTIFIED VIA ed25519 USING \"',ed25519_password(\"\"),'\";');" | mysql
    mysql -sNe "SELECT CONCAT('CREATE USER user_ed25519 IDENTIFIED VIA ed25519 USING \"',ed25519_password(\"pass_ed25519\"),'\";');" | mysql
    WITH_PLUGIN=''
else
    WITH_PLUGIN=''
fi

mysql -uroot -e 'create database test1 DEFAULT CHARACTER SET utf8mb4'
mysql -uroot -e 'create database test2 DEFAULT CHARACTER SET utf8mb4'

mysql -u root -e "create user test2           identified ${WITH_PLUGIN} by 'some password'; grant all on test2.* to test2;"
mysql -u root -e "create user test2@localhost identified ${WITH_PLUGIN} by 'some password'; grant all on test2.* to test2@localhost;"

cp ci/docker.json pymysql/tests/databases.json
