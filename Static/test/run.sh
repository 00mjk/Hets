#!/bin/bash

createXUpdate ()
{
f=`dirname $1`/`basename $1 .het`
hets -v2 -o xml $f
mv $f.xml $f.xh
hets -v2 -A -o xml $f
mv $f.xml $f.xhi
cp $1 $1.bak
propagateDiff $1 $1 $2
hets -v2 -o xml $f
mv $f.xml $f.new.xh
cp $1.bak $1
dir=`pwd`
b2=`basename $2 .het`
#pushd $HETS_GMOC
rm -f tmp/*.xupdate
rm -f tmp/*.imp
#bin/gmoc -c Configuration.xml -itype file moc \
#  $dir/$f.xh $dir/$f.xhi $dir/$f.new.xh
#mv tmp/*.xupdate $dir/$b2.xupdate
#mv tmp/*.imp $dir/$b2.imp
#popd

cp $dir/$f.xh $dir/$f.hetsdginternxml
cp $dir/$f.new.xh $dir/$f.new.hetsdginternxml
pushd $HETS_GMOC2
bin/gmoc -itype file -otype diff -o $dir/$b2.xupdate2 sdiff \
  $dir/$f.hetsdginternxml $dir/$f.new.hetsdginternxml
popd
}

propagateDiff ()
{
diff -u $1 $3 > patch
patch $2 patch
}

createUpdates ()
{
for i in Spec.het
do
   for j in Add Remove Modify
   do
       for k in Symbol Axiom Theorem
       do createXUpdate $i $j$k$i
       done
   done
done
for i in Spec2.het
do
   for j in Add Remove
   do k=Node; createXUpdate $i $j$k$i
   done
done
}

callHets ()
{
for i in *Spec.xupdate2
do
hets -v2 -U $i Spec.het
done
for i in *Spec2.xupdate2
do
hets -v2 -U $i Spec2.het
done
}

## uncomment the slow createUpdates if you do not have the .xupdates files
#createUpdates
callHets
