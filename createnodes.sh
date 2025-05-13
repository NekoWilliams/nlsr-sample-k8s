#!/bin/sh

for yml in $(ls | grep yaml)
do
  kubectl apply -f $yml
done