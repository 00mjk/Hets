#!/bin/sh -x

#change daily snapshot into a backup or release
#the first argument should be a version number or a date  
#compute date by "date -Idate"

INSTALLDIR=/home/www/agbkb/forschung/formal_methods/CoFI/hets 
VERSION=$1
for i in linux solaris mac
do
  (cd $INSTALLDIR/$i; cp -p daily/hets versions/hets-$VERSION)
done
      
(cd $INSTALLDIR/src-distribution; cp -p daily/Het*.t* versions/Hets-src-$VERSION.tgz) 

