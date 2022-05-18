#!/bin/sh

TEMP_DEB="$(mktemp).deb" &&
curl -o "$TEMP_DEB" -L $(curl -q -s https://api.github.com/repos/sskaje/ubnt-clash/releases/latest | jq -r '.assets[] | select( .browser_download_url | contains(".deb")) | .browser_download_url' | sed -e 's#github.com#p.rst.im/q/github.com#') &&
sudo dpkg -i "$TEMP_DEB"
rm -f "$TEMP_DEB"
