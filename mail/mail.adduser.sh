#!/bin/sh

die () {
    echo >&2 "$@"
    exit 1
}

[ "$#" -eq 2 ] || die "inform username and password"

echo "Please, inform mysql root password:"
mysql mail -u root -p -e "INSERT INTO \`user\` (\`email\`, \`password\`, \`name\`) VALUES (\"$1@infratec.eco.br\", ENCRYPT(\"$2\"), \"$1\");"

DOMAIN=infratec.eco.br
mkdir -p /var/spool/mail/virtual/$DOMAIN/$1/{new,tmp,cur}
chown -R virtual:virtual /var/spool/mail/virtual/$DOMAIN/$1/