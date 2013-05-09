#!/bin/bash

function start() {
  /usr/local/bin/bundle exec ruby ./client.rb &
  echo $! > $pidfile
}

pidfile=/tmp/botsy.pid

if [ -e $pidfile ]; then
  pid=`cat $pidfile`
  if kill -0 > /dev/null $pid; then
    exit 1
  else
    rm $pidfile
  fi
fi

start

