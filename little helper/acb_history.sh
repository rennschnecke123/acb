#!/bin/bash

acb -lb > backup-history.txt
acb -s >> backup-history.txt

read -p "Press any key..."