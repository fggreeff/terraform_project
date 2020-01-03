#!/bin/sh
aws configure set default.region us-east-1
aws configure set aws_access_key_id 'YOUR_ACCESS_KEY'
aws configure set aws_secret_access_key 'YOUR_SECRET_KEY'
aws ecr get-login | sudo sh
