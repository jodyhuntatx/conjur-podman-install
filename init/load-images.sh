#!/bin/bash
source ../conjur.config

for i in $(ls ./image_files); do
  echo "Loading ./image_files/$i..."
  echo "$DOCKER load -i ./image_files/$i"
done
