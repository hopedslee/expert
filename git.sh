#!/bin/bash

git add .

today=$(date +%Y-%m-%d)
echo $today
git commit -m "$today"
git push -u origin master

exit 0

