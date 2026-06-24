#!/bin/bash

echo "========= OnTheSpot RPM Build Script ==========="


echo " => Fetch Dependencies"
sudo dnf install rpm-build python3-pip python3-devel python3-setuptools


echo " => Build OnTheSpot.whl"
python -m build --outdir build/dist


echo " => Build OnTheSpot.rpm"
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
cp build/dist/onthespot-*-py3-none-any.whl ~/rpmbuild/SOURCES/
cp src/onthespot/resources/org.onthespot.OnTheSpot.desktop ~/rpmbuild/SOURCES/
cp src/onthespot/resources/icons/onthespot.png ~/rpmbuild/SOURCES/
cp distros/fedora/onthespot.spec ~/rpmbuild/SPECS/
rpmbuild -ba ~/rpmbuild/SPECS/onthespot.spec
cp ~/rpmbuild/RPMS/noarch/onthespot-*.noarch.rpm build/dist/OnTheSpot.rpm


echo " => Done! Packaged rpm is available in 'build/dist/OnTheSpot.rpm'."
