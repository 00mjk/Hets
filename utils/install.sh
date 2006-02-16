#!/bin/sh -x

#change daily snapshot into a backup or release
#the first argument should be a version number or a date  
#compute date by "date -Idate"

INSTALLDIR=/home/www/agbkb/forschung/formal_methods/CoFI/hets 
VERSION=$1
for i in linux solaris mac
do
  (cd $INSTALLDIR/$i; cp -p daily/hets.bz2 versions/hets-$VERSION.bz2)
done
      
(cd $INSTALLDIR/src-distribution; \
 cp -p daily/Het*.t* versions/Hets-src-$VERSION.tgz; \
 cd versions; rm -rf HetCATS; \
 tar zxf Hets-src-$VERSION.tgz) 

# also unpack the new release as "recent overview of the modules"
