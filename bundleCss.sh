#!/bin/sh

#Can't seem to get this to work for all of the CSS, so just a few below

echo "

css/atom-one-dark.css
css/tabulator.min.css
css/choices.min.css
css/pivot.min.css
css/daterangepicker.css
css/leaflet.css
" | xargs cat | npx uglifycss > css/bundle-css.min.css
