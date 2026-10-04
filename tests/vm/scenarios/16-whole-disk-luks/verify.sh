[ "$(blkid -p -o value -s TYPE $D3)" = crypto_LUKS ]
findmnt -n /t/whole > /dev/null
