#!/bin/bash
npx browserify -t coffeeify --extension='.coffee' Tamarind.coffee -o bundle.js
cat bundle.js | npx terser | sponge bundle.js
#rsync --progress --verbose --copy-links --exclude=node_modules --recursive ./ tamarind.cococloud.co:/var/www/tamarind.cococloud.co/
#rsync --progress --verbose --copy-links --exclude=node_modules --recursive ./ tamarind.vdomck.org:/var/www/tamarind.cococloud.co/
rsync --progress --verbose --copy-links --exclude=node_modules --recursive ./ karafuu@coconut.mohz.go.tz:/var/www/tamarind/
